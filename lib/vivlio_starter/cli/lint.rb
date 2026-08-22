# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/lint.rb
# ================================================================
# 責務:
#   textlint を使用した Markdown ファイルの文章校正を実行する。
#   日本語技術文書向けのルールセットで文章品質をチェックする。
#
# 機能:
#   - contents/ 以下の Markdown ファイルを textlint で検査
#   - 章番号指定・範囲指定による部分検査
#   - 英語エラーメッセージの日本語翻訳
#
# 使用される textlint ルール:
#   - textlint-rule-preset-ja-technical-writing: 技術文書向け
#   - textlint-rule-preset-japanese: 日本語一般
#   - textlint-rule-prh: 表記揺れ検出
#
# 依存:
#   - textlint: npm グローバルインストール
#   - TextlintFormatter: エラーメッセージの日本語化
#   - Common: ファイル解決・ログ出力
# ================================================================

require 'open3'
require 'shellwords'
require 'rbconfig'
require 'set'
require 'tempfile'
require 'yaml'

require_relative 'common'
require_relative 'masking'
require_relative 'textlint_formatter'
require_relative 'token_resolver'
require_relative 'lint/notation_guard'
require_relative 'lint/tokenizer'
require_relative 'lint/dict_manager'
require_relative 'lint/spell_checker'
require_relative 'lint/prose_checker'

module VivlioStarter
  module CLI
    # textlint による文章校正コマンド
    module LintCommands
      TEXTLINT_CONFIG_PATH = File.join(Common::CONFIG_DIR, '.textlintrc.yml')

      # textlint 用サポート YAML（allowlist/prh）の既定パス
      TEXTLINT_ALLOWLIST_RELATIVE = File.join(Common::CONFIG_DIR, 'textlint_allowlist.yml')
      TEXTLINT_REWRITE_RELATIVE   = File.join(Common::CONFIG_DIR, 'textlint_rewrite.yml')

      TEXTLINT_ENV_VAR = 'VIVLIO_TEXTLINT_BIN'

      def self.execute_lint(targets, options = {})
        LintRunner.new(targets, options).call
      end

      # text:lint 実行ロジックをまとめたランナー
      class LintRunner
        attr_reader :targets, :options

        def initialize(targets, options)
          @targets = Array(targets)
          @options = normalize_options(options)
        end

        # --spellcheck-only / --textlint-only / --register による実行範囲。
        # --register はスペルチェック専用の操作なので、暗黙に spellcheck 単独で動く
        # （`--spellcheck-only` を併記する必要はない）。
        def spellcheck_only? = options[:register] || options[:spellcheck_only]
        def textlint_only?   = !options[:register] && options[:textlint_only]

        def call
          ensure_textlint_available! unless spellcheck_only?
          ensure_config_present! unless spellcheck_only?
          ensure_support_yaml_files! unless spellcheck_only?

          files = resolve_targets
          if files.empty?
            Common.log_warn('検査対象となる Markdown ファイルが見つかりません。')
            return 0
          end

          lint_info  = { exit: 0, lint_count: 0, fixable_count: 0, fixed_files: [] }
          prose_info = { exit: 0, prose_count: 0, fixed_files: [] }
          spell_info = { exit: 0, spell_count: 0 }

          unless spellcheck_only?
            # 交ぜ書きの置換を先に済ませてから textlint を走らせる。逆順にすると
            # textlint が見る原稿と、置換後に残る原稿が食い違う。
            prose_fixed = options[:fix] ? apply_prose_fixes!(files) : []
            lint_info   = run_textlint(files)
            prose_info  = run_prose_check(files).merge(fixed_files: prose_fixed)
          end
          spell_info = run_spellcheck(files) unless textlint_only?

          print_combined_summary(lint_info, prose_info, spell_info)
          [lint_info[:exit], prose_info[:exit], spell_info[:exit]].max
        rescue LintError => e
          Common.log_error(e.message)
          1
        end

        # textlint 本体を実行して結果サマリーを返す。
        # 出力は常にルール単位の集約表示（textlint --format json を取得して整形）。
        #
        # --fix 指定時は「修正パス → 解析パス」の 2 段構成を採る。修正パスは記法ガードを
        # 通さない一時ファイルを textlint に直させて原稿へ書き戻し、解析パスはガード済みの
        # 一時ファイルから残存指摘を集める。ガードによる記法の中和は非可逆なので、
        # ガード済みの内容を原稿へ書き戻すことはできない（両立させるための 2 パス）。
        # 仕様: lint-notation-guard-spec.md §2.3
        def run_textlint(files)
          fixed_files = options[:fix] ? apply_textlint_fixes!(files) : []

          converted_files = convert_vs_lint_comments(files)
          # textlint は一時ファイルを検査するため、出力の一時パスを元ファイル名へ戻すマップ
          path_map = files.zip(converted_files).to_h { |orig, tmp| [File.expand_path(tmp), orig] }
          hushed = suppressed_lines_map(files, converted_files)
          run_textlint_aggregated(converted_files, path_map, hushed).merge(fixed_files: fixed_files)
        ensure
          cleanup_temp_files(converted_files) if converted_files
          @runtime_config_tmp&.unlink
        end

        # ルール単位で集約した独自表示（--format json で取得して整形）
        def run_textlint_aggregated(files, path_map = {}, suppressed_lines = {})
          command = build_command(files, format: 'json')
          stdout, stderr, status = Open3.capture3(*command)
          $stderr.print(stderr) unless stderr.nil? || stderr.empty?

          result = TextlintFormatter.aggregate_json(
            stdout, disabled_rules: disabled_rules, trim_long_vowel: trim_long_vowel?,
                    suppressed_lines: suppressed_lines
          )
          if result.nil?
            # JSON 解釈に失敗（textlint 自体のエラー等）。生出力をそのまま見せる。
            $stdout.print(stdout) unless stdout.nil? || stdout.empty?
            return { exit: textlint_exit(status), lint_count: 0, fixable_count: 0 }
          end

          # 一時ファイルのパスを元ファイル名へ戻す
          result[:files].each { |f| f[:path] = path_map[File.expand_path(f[:path])] || f[:path] }
          print_textlint_aggregated(result)
          # 無効化で除外した分は問題数に数えない（残り 0 なら成功扱い）
          { exit: result[:total].positive? ? 1 : 0, lint_count: result[:total], fixable_count: result[:fixable] }
        end

        # textlint では扱えない指摘（交ぜ書き・二通りに読める対比）を当てる。
        # 件数は「日本語校正」へ合算する——著者から見れば textlint の指摘と区別する
        # 理由がない。仕様: lint-japanese-prose-rules-spec.md §5
        def run_prose_check(files)
          findings_by_file = files.to_h { [it, check_prose(it)] }
                                  .reject { |_path, findings| findings.empty? }
          Lint::ProseChecker.print_errors(findings_by_file)

          all = findings_by_file.values.flatten
          { exit: all.empty? ? 0 : 1,
            prose_count: all.size,
            fixable_count: all.count { it.rule == Lint::ProseChecker::MAZEGAKI_RULE } }
        end

        # 交ぜ書きの置換を原稿へ適用する（--fix 指定時のみ）。
        # 対比の指摘は自動修正しない（どちらが X するのかは著者しか知らないため）。
        # @return [Array<String>] 実際に書き換えた原稿パス
        def apply_prose_fixes!(files)
          return [] if disabled_rules.include?(Lint::ProseChecker::MAZEGAKI_RULE)

          files.filter_map do |path|
            original = File.read(path, encoding: 'UTF-8')
            fixed    = Lint::ProseChecker.fix_mazegaki(original, prose_allowlist)
            next if fixed == original

            atomic_write(path, fixed)
            path
          end
        end

        def check_prose(path)
          Lint::ProseChecker.check(path, disabled_rules: disabled_rules, allowlist: prose_allowlist)
        end

        # config/textlint_allowlist.yml の語で交ぜ書きの指摘を黙らせる。
        # textlint と同じファイルを読むので、著者が窓口を二度覚えなくて済む。
        def prose_allowlist
          @prose_allowlist ||=
            Lint::ProseChecker.allowlist_from(Common.resolve_path_from_root(TEXTLINT_ALLOWLIST_RELATIVE))
        end

        # book.yml lint.disabled_rules（ルール ID で丸ごと無効化）
        def disabled_rules
          Array(Common::CONFIG.lint.disabled_rules).map(&:to_s)
        end

        # book.yml lint.trim_long_vowel（末尾長音を足す指摘を抑止：技術者向け文体）
        def trim_long_vowel?
          Common.truthy?(Common::CONFIG.lint.trim_long_vowel)
        end

        def print_textlint_aggregated(result)
          result[:files].each do |file|
            Common.log_always "📄 #{file[:path]}  (textlint)"
            file[:rows].each do |row|
              Common.log_always format('  %3d件  %s', row[:count], row[:label])
              Common.log_always format('         行: %s', row[:lines])
            end
            Common.log_always ''
          end
        end

        def textlint_exit(status) = status.success? ? 0 : (status.exitstatus || 1)

        private

        def print_combined_summary(lint_info, prose_info, spell_info)
          lint_count  = lint_info[:lint_count].to_i + prose_info[:prose_count].to_i
          spell_count = spell_info[:spell_count].to_i
          fixable     = lint_info[:fixable_count].to_i + prose_info[:fixable_count].to_i
          total       = lint_count + spell_count

          Common.log_always ''
          Common.log_always '✏️ 文章の品質チェックが完了しました'
          # 修正パスが原稿を直したファイル数。以降のサマリーは「修正後に残った指摘」を指す。
          # 和集合を取るのは、textlint と交ぜ書きが同じ原稿を直しうるため（二重に数えない）。
          fixed = (Array(lint_info[:fixed_files]) | Array(prose_info[:fixed_files])).size
          Common.log_always "🔧 #{fixed}ファイルへ自動修正を適用しました" if fixed.positive?
          if total.positive?
            Common.log_warn("#{total}箇所に改善提案があります")
            Common.log_always "   - 日本語校正: #{lint_count}箇所" if lint_count.positive?
            Common.log_always "   - スペルチェック: #{spell_count}箇所" if spell_count.positive?
            if fixable.positive? && !options[:fix]
              Common.log_always "💡 そのうち#{fixable}箇所は自動修正可能です。"
              Common.log_always '   vs lint --fix'
            else
              Common.log_always '💡 表記揺れや文法上の改善点を修正してからもう一度実行してください。'
            end
          else
            Common.log_result('文章チェックで問題は見つかりませんでした。', status: :success)
          end
        end

        def normalize_options(raw)
          return {} if raw.nil?

          raw.to_h.each_with_object({}) do |(key, value), memo|
            sym_key = begin
              key.to_sym
            rescue StandardError
              key
            end
            memo[sym_key] = value
          end
        end

        def ensure_textlint_available!
          return if command_exists?(textlint_command)

          raise LintError, <<~MSG.strip
            textlint コマンドが見つかりません。npm などで textlint をインストールしてください。
            例: npm install -g textlint textlint-rule-preset-ja-technical-writing
          MSG
        end

        def ensure_config_present!
          path = config_path
          return if File.file?(path)

          display_path = Common.relative_path_from_root(path) || path
          raise LintError, "textlint 設定ファイルが見つかりません: #{display_path}"
        end

        # textlint 用サポート YAML (allowlist/prh) の存在・パースを検証する
        def ensure_support_yaml_files!
          [TEXTLINT_ALLOWLIST_RELATIVE, TEXTLINT_REWRITE_RELATIVE].each do |rel|
            path = Common.resolve_path_from_root(rel)
            display = Common.relative_path_from_root(path) || path

            raise LintError, "textlint サポート用設定ファイルが見つかりません: #{display}" unless path && File.file?(path)

            begin
              yaml_text = File.read(path, encoding: 'UTF-8')
              YAML.safe_load(yaml_text, permitted_classes: [], aliases: true)
            rescue StandardError => e
              raise LintError, "textlint サポート用設定ファイルの読み込みに失敗しました: #{display} (#{e.class}: #{e.message})"
            end
          end
        end

        def run_spellcheck(files)
          config       = Common::CONFIG.spellcheck
          dict         = Lint::DictManager.new
          word_map     = dict.build_word_map(config)
          check_code   = Common.truthy?(config&.check_code_blocks)

          all_errors = {}
          files.each do |path|
            errors = Lint::SpellChecker.check(path, word_map, check_code_blocks: check_code)
            all_errors[path] = errors unless errors.empty?
          end

          Lint::SpellChecker.print_errors(all_errors)
          return register_unknown_words(dict, all_errors) if options[:register]

          spell_count = all_errors.values.sum(&:length)
          { exit: spell_count.positive? ? 1 : 0, spell_count: spell_count }
        rescue StandardError => e
          Common.log_warn("[spellcheck] スペルチェック中にエラーが発生しました: #{e.message}")
          { exit: 0, spell_count: 0 }
        end

        # 検出した未知語をユーザー辞書へ一括登録する（--register）
        def register_unknown_words(dict, all_errors)
          words = all_errors.values.flatten.filter_map { it[:word] }.uniq
          added = dict.register_user_words(words)
          if added.empty?
            Common.log_result('登録すべき新しい語はありませんでした（すべて登録済み）。', status: :success)
          else
            Common.log_result("ユーザー辞書へ #{added.size} 語を登録しました", status: :success)
            Common.log_always "   ファイル: #{dict.user_dict_path}"
            Common.log_always "   登録語: #{added.join(', ')}"
          end
          # 登録が目的のため、未知語が在っても成功（次回 vs lint で消える）
          { exit: 0, spell_count: 0 }
        end

        def resolve_targets
          resolver = TargetResolver.new(targets)
          resolver.resolve
        end

        # 集約表示のため出力は常に json で取得する。
        # --fix は付けない（自動修正は apply_textlint_fixes! の修正パスが担う。
        # ここで付けると解析用の一時ファイルを直して捨てるだけの no-op になる）。
        def build_command(files, format: 'json')
          cmd = [textlint_command, '--config', effective_config_path]
          cmd += ['--format', format]
          cmd + files
        end

        def config_path
          path = TEXTLINT_CONFIG_PATH
          resolved = Common.resolve_path_from_root(path)
          resolved || File.expand_path(path)
        end

        # 実際に textlint へ渡す設定パス。book.yml の lint.* で文体の上書きが指定されていれば、
        # 既定 textlintrc にその上書きを反映した一時設定を生成して使う（なければ既定をそのまま）。
        def effective_config_path
          return config_path unless runtime_overrides?

          @effective_config_path ||= generate_runtime_config(
            config_path,
            sentence_max: sentence_length_max,
            allow_code_space: allow_space_around_code?,
            allow_ja_en_space: allow_space_between_ja_en?
          )
        end

        # 実行時 textlintrc を生成する必要があるか（いずれかの上書きが指定されている）
        def runtime_overrides?
          sentence_length_max || allow_space_around_code? || allow_space_between_ja_en?
        end

        # book.yml lint.sentence_length_max（一文の最大文字数。未指定なら nil＝既定 100）
        # book.yml lint.sentence_length_max。
        #   未指定 … nil（textlintrc の既定 100）
        #   0      … :off（一文の長さを検査しない）
        #   正の数 … その値を上限にする
        # 0 を「制限しない」に当てるのは book.yml 内の既存の流儀に揃えたもの
        # （index.max_sub_references が「0 で無制限」）。上限を変えるのも
        # 検査を切るのも同じキーで済み、disabled_rules を知らなくてよくなる。
        def sentence_length_max
          value = Common::CONFIG.lint.sentence_length_max
          return nil if Common.blank?(value)

          count = value.to_i
          return :off if count.zero?

          count.positive? ? count : nil
        end

        # book.yml lint.allow_space_around_code（インラインコード前後のスペースを許容）
        def allow_space_around_code? = Common.truthy?(Common::CONFIG.lint.allow_space_around_code)

        # book.yml lint.allow_space_between_ja_en（全角と半角の間のスペースを許容）
        def allow_space_between_ja_en? = Common.truthy?(Common::CONFIG.lint.allow_space_between_ja_en)

        # 既定 textlintrc に文体の上書きを反映した一時設定を config/ 直下に生成する。
        # 設定レベルで無効化するため、隠すだけの出力フィルタと違い --fix でも変更されない。
        # 相対パス（prh.rulePaths / allowlistConfigPaths）が壊れないよう、元の設定と同じ
        # ディレクトリへ書き出す。後始末は run_textlint の ensure で行う。
        def generate_runtime_config(base_path, sentence_max: nil, allow_code_space: false, allow_ja_en_space: false)
          cfg = YAML.safe_load_file(base_path) || {}
          rules = (cfg['rules'] ||= {})

          # :off はルールごと切る（textlint の作法は `<rule>: false`）。
          # 大きな上限を書いて実質無効にする手もあるが、値から意図が読めなくなる。
          case sentence_max
          when :off then (rules['preset-ja-technical-writing'] ||= {})['sentence-length'] = false
          when Integer then (rules['preset-ja-technical-writing'] ||= {})['sentence-length'] = { 'max' => sentence_max }
          end
          if allow_code_space || allow_ja_en_space
            spacing = (rules['preset-ja-spacing'] ||= {})
            spacing['ja-space-around-code'] = false if allow_code_space
            spacing['ja-space-between-half-and-full-width'] = false if allow_ja_en_space
          end

          @runtime_config_tmp = Tempfile.new(['.textlintrc-runtime-', '.yml'], File.dirname(base_path))
          @runtime_config_tmp.write(cfg.to_yaml)
          @runtime_config_tmp.close
          @runtime_config_tmp.path
        end

        def textlint_command
          ENV.fetch(TEXTLINT_ENV_VAR, 'textlint')
        end

        def command_exists?(cmd)
          return false if cmd.nil? || cmd.strip.empty?

          candidate = cmd.strip
          return file_executable?(candidate) if path_like?(candidate)

          pathext = windows_platform? ? ENV.fetch('PATHEXT', '').split(';').map(&:downcase) : ['']
          ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).any? do |path|
            pathext.any? do |ext|
              extname = ext.empty? || candidate.downcase.end_with?(ext) ? candidate : "#{candidate}#{ext.downcase}"
              resolved = File.join(path, extname)
              file_executable?(resolved)
            end
          end
        end

        def file_executable?(path)
          if Common.respond_to?(:file_executable?)
            Common.file_executable?(path)
          else
            File.exist?(path) && File.executable?(path)
          end
        end

        def path_like?(candidate)
          candidate.include?(File::SEPARATOR) || candidate.include?('\\')
        end

        def windows_platform?
          !!(RbConfig::CONFIG['host_os'] =~ /mswin|mingw|cygwin|bccwin|wince|emx/i)
        end

        # `<!-- vs-lint-disable-next-line -->` の直後の行番号を、原稿ごとに集める。
        #
        # **textlint 側でこの記法は効かない。** 変換先の `<!-- textlint-disable-next-line -->` を
        # `textlint-filter-rule-comments`（v1.3.0）が実装しておらず、無効なコメントとして
        # 黙って捨てられる（囲む形の disable/enable は効く）。原稿は「一行だけ除外」を
        # 案内しているので、**出力段で行ごと落として辻褄を合わせる**。
        #
        # 一時ファイルへ disable/enable を挿し込む手は採れない——行数が変わり、
        # 報告される行番号が原稿とずれる。
        # @return [Hash] { 一時ファイルの絶対パス => 抑止する行番号の Set }
        def suppressed_lines_map(files, converted_files)
          files.zip(converted_files).to_h do |original, tmp|
            [File.expand_path(tmp), next_line_suppressions(File.read(original, encoding: 'UTF-8'))]
          end
        rescue StandardError => e
          # 抑止情報が作れなくても検査は続ける（指摘が余分に出るだけで、止まるよりよい）
          Common.log_debug("[lint] 抑止行の収集に失敗しました: #{e.message}")
          {}
        end

        # 抑止コメントの次の行番号を集める。コメント自身の行は数えない。
        #
        # コード領域の中は見ない——校正の使い方を解説する原稿はフェンスの中へ
        # コメントを書き写すので、それを本物の指示と取ると例示が抑止として働く
        # （Tokenizer / ProseChecker と同じ扱いに揃える）。
        def next_line_suppressions(text)
          hushed  = Set.new
          pending = false
          prose   = Set.new
          Masking.each_prose_line(text) { |_line, lineno| prose << lineno }

          text.each_line.with_index(1) do |line, lineno|
            next unless prose.include?(lineno)

            if pending
              hushed << lineno
              pending = false
            end
            pending = true if line.match?(/<!--\s*vs-lint-disable-next-line\s*-->/)
          end

          hushed
        end

        # vs-lint コメントを textlint ネイティブ記法に変換する
        # @param files [Array<String>] 対象ファイルパスの配列
        # @param guard [Boolean] VFM 記法を中和するか（解析パスは true、修正パスは false）
        # @return [Array<String>] 変換後のファイルパスの配列（一時ファイル）
        def convert_vs_lint_comments(files, guard: true)
          files.map do |path|
            content = File.read(path, encoding: 'UTF-8')
            converted = rewrite_vs_lint_to_textlint(content, guard: guard)

            # Tempfile.new は不可: パス文字列だけ返すと Tempfile オブジェクトが GC され、
            # ファイナライザが textlint 実行前にファイルを削除してしまう（textlint は
            # 存在しないパスを黙って無視するため、一部ファイルだけ検査されない事故になる）。
            # Tempfile.create はファイナライザを登録せず、削除は cleanup_temp_files だけが担う。
            file = Tempfile.create(['textlint_', '.md'], encoding: 'UTF-8')
            file.write(converted)
            file.close
            file.path
          end
        end

        # vs-lint コメントを textlint コメントに置換する。
        # あわせて VFM 記法を中和する（guard: true）。記法は機械データであって文ではなく、
        # textlint に読ませると誤検出になるため、textlint へ渡す前にここで落とす。
        # 中和は非可逆なので、原稿へ書き戻す修正パス（--fix）は guard: false で呼ぶ。
        # @param source [String] 元のMarkdown内容
        # @param guard [Boolean] VFM 記法を中和するか
        # @return [String] 変換後のMarkdown内容
        def rewrite_vs_lint_to_textlint(source, guard: true)
          source = Lint::NotationGuard.strip_notation(source) if guard
          source
            .gsub(/<!--\s*vs-lint-disable-next-line\s*-->/, '<!-- textlint-disable-next-line -->')
            .gsub(/<!--\s*vs-lint-disable\s*-->/, '<!-- textlint-disable -->')
            .gsub(/<!--\s*vs-lint-enable\s*-->/, '<!-- textlint-enable -->')
        end

        # --- 修正パス（--fix） ------------------------------------------------

        # textlint の自動修正を原稿へ実際に適用する（--fix 指定時のみ）。
        # 一時ファイルを直させてから書き戻すのは、textlint に原稿を直接掴ませないため
        # （プロセス実行中に中断されても原稿が半端な状態で残らない）。
        # @param files [Array<String>] 対象の原稿パス
        # @return [Array<String>] 実際に書き戻した原稿パス
        def apply_textlint_fixes!(files)
          # 記法ガードは通さない。中和は非可逆で、ガード済みの内容は原稿へ書き戻せない。
          # **数式だけは別**——退避は可逆なので、修正パスでも守る。守らないと prh が
          # 数式の中の半角括弧を全角へ「直し」、`$(1/2)πr³$` が `$（1/2）πr³$` になって壊れる。
          converted = convert_vs_lint_comments(files, guard: false)
          math_spans = mask_math_in_place!(converted)
          baselines = converted.map { File.read(it, encoding: 'UTF-8') }

          command = [textlint_command, '--config', effective_config_path, '--fix', *converted]
          stdout, stderr, = Open3.capture3(*command)
          # --fix の終了コードと出力は判定に使わない。残存指摘の判定は解析パスが行う。
          Common.log_debug(stdout) unless stdout.nil? || stdout.empty?
          $stderr.print(stderr) unless stderr.nil? || stderr.empty?

          write_back_fixes(files, converted, baselines, math_spans)
        ensure
          cleanup_temp_files(converted) if converted
        end

        # textlint が実際に書き換えた一時ファイルだけを原稿へ書き戻す。
        # 未変更のファイルへは触れない（原稿の mtime とコメント書式を無用に変えない）。
        # @return [Array<String>] 書き戻した原稿パス
        # 一時ファイルの数式を目印へ退避する（修正パス専用）。
        # @return [Array<Hash>] ファイルごとの { 目印 => 原文 }
        def mask_math_in_place!(converted)
          converted.map do |tmp|
            masked, spans = Lint::NotationGuard.mask_math(File.read(tmp, encoding: 'UTF-8'))
            File.write(tmp, masked, encoding: 'UTF-8')
            spans
          end
        end

        def write_back_fixes(files, converted, baselines, math_spans)
          files.zip(converted, baselines, math_spans).filter_map do |original, tmp, baseline, spans|
            fixed = File.read(tmp, encoding: 'UTF-8')
            next if fixed == baseline

            restored = Lint::NotationGuard.restore_math(fixed, spans)
            atomic_write(original, rewrite_textlint_to_vs_lint(restored))
            original
          end
        end

        # textlint ネイティブ記法を vs-lint コメントへ戻す（rewrite_vs_lint_to_textlint の逆）。
        # next-line を先に処理する（後続の disable パターンが next-line 形を食わないように）。
        # 著者が素の textlint コメントを直書きしていた場合も vs-lint 形へ正規化されるが、
        # 機能は等価であり vs-lint 形が本プロジェクトの正典記法なので許容する。
        # @param source [String] textlint が修正した内容
        # @return [String] 原稿へ書き戻す内容
        def rewrite_textlint_to_vs_lint(source)
          source
            .gsub(/<!--\s*textlint-disable-next-line\s*-->/, '<!-- vs-lint-disable-next-line -->')
            .gsub(/<!--\s*textlint-disable\s*-->/, '<!-- vs-lint-disable -->')
            .gsub(/<!--\s*textlint-enable\s*-->/, '<!-- vs-lint-enable -->')
        end

        # 原稿を同一ディレクトリの一時ファイル経由で置換する。
        # File.write の直書きだと書き込み中に Ctrl+C を受けた原稿が半端な状態で残るため、
        # rename によるアトミック置換にする（旧内容のままか新内容へ完全置換済みかの
        # どちらかにしかならない）。パーミッションは元ファイルから引き継ぐ。
        def atomic_write(path, content)
          mode = File.stat(path).mode & 0o7777
          # Tempfile.create（ファイナライザなし）。rename で移動した後に GC の削除が走る余地を残さない。
          tmp  = Tempfile.create(['.vs-lint-fix-', '.md'], File.dirname(path), encoding: 'UTF-8')
          begin
            tmp.write(content)
            tmp.close
            File.chmod(mode, tmp.path)
            File.rename(tmp.path, path)
          ensure
            # rename 済みなら既に存在しない。失敗・中断時に原稿の隣へ残さないための保険。
            FileUtils.rm_f(tmp.path)
          end
        end

        # 一時ファイルをクリーンアップする
        # @param temp_files [Array<String>] 一時ファイルパスの配列
        def cleanup_temp_files(temp_files)
          temp_files.each do |path|
            FileUtils.rm_f(path)
          rescue StandardError => e
            Common.log_warn("[lint] 一時ファイルの削除に失敗しました: #{path} (#{e.message})")
          end
        end

        # TokenResolver を用いた Markdown 対象ファイルの解決
        #
        # ゼロ埋め・レンジ展開・カンマ区切りなどの正規化を TokenResolver に委譲し、
        # lint 対象は contents/ 配下の利用者原稿（*.md）に限定する。
        class TargetResolver
          def initialize(raw_targets)
            @raw_targets = Array(raw_targets)
            @resolver = TokenResolver::Resolver.new
          end

          # プロジェクトルートからの相対 Markdown パスの配列を返す
          def resolve
            entries = resolve_entries

            # --- Phase: Validation ---
            reject_invalid_entries!(entries)
            reject_unknown_entries!(entries)

            # --- Phase: contents/ 配下のみに限定 ---
            content_entries = entries.select { it.path.start_with?(Common::CONTENTS_DIR) }
            existing, missing = content_entries.partition(&:exists?)
            missing.each { Common.log_warn("見つかりません: #{it.path}") }

            # --- Phase: 相対パス化 ---
            root = Pathname.new('.')
            existing.map { Pathname.new(it.path).cleanpath.relative_path_from(root).to_s }.sort
          end

          private

          attr_reader :raw_targets, :resolver

          # TokenResolver で Entry 配列を取得する
          # 引数なし → catalog.yml 全章、引数あり → トークン解決
          def resolve_entries
            raw_targets.empty? ? resolver.resolve([]) : resolver.resolve(raw_targets)
          end

          # invalid な Entry が含まれていれば即座にエラー終了する
          def reject_invalid_entries!(entries)
            invalid = entries.reject(&:valid?)
            return if invalid.empty?

            Common.log_error("不正な章指定が含まれています: #{invalid.map(&:slug).join(', ')}")
            exit 1
          end

          def reject_unknown_entries!(entries)
            unknown = entries.reject { system_entry?(it) }.select { !it.in_catalog? && !it.exists? }
            return if unknown.empty?

            labels = unknown.map { it.slug || it.basename }.uniq
            Common.log_error("不正な章指定が含まれています: #{labels.join(', ')}")
            exit 1
          end

          def system_entry?(entry)
            entry.respond_to?(:number) && entry.number.nil?
          end
        end
      end

      # 後方互換: 旧 TextLintCommands 定数を維持
      TextLintCommands = LintCommands

      class LintError < StandardError; end
    end
  end
end
