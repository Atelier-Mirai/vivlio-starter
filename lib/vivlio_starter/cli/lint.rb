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
require 'tempfile'
require 'yaml'

require_relative 'common'
require_relative 'textlint_formatter'
require_relative 'token_resolver'
require_relative 'lint/tokenizer'
require_relative 'lint/dict_manager'
require_relative 'lint/spell_checker'

module VivlioStarter
  module CLI
    # textlint による文章校正コマンド
    module LintCommands
      DEFAULT_CONFIG_FALLBACK = File.join(Common::CONFIG_DIR, '.textlintrc.yml')

      # textlint 用サポート YAML（allowlist/prh）の既定パス
      TEXTLINT_ALLOWLIST_RELATIVE = File.join(Common::CONFIG_DIR, 'textlint_allowlist.yml')
      TEXTLINT_PRH_RELATIVE       = File.join(Common::CONFIG_DIR, 'textlint_prh.yml')

      LINT_DESC = {
        short: 'contents/ 以下の Markdown を textlint で検査します',
        long: <<~DESC
          contents/ ディレクトリ以下の Markdown ファイルを textlint で検査します。
          引数を指定しない場合は全ての Markdown が対象です。章のベース名（11-install など）を
          指定すると、そのファイルのみを検査します（拡張子や contents/ の省略可）。

          章番号のみ、または範囲指定も可能です：
            章番号のみ: vs lint 91 93      # 91-*.md と 93-*.md を検査
            範囲指定:   vs lint 11-21      # 11-*.md から 21-*.md を検査

          例:
            vs lint                 # 全 Markdown を検査
            vs lint 11-install      # 11-install.md のみ検査
            vs lint 11-install 21-customize
            vs lint 91 93           # 91-*.md と 93-*.md を検査
            vs lint 11-21           # 11-*.md から 21-*.md の範囲を検査
            vs lint:check           # lint のエイリアス

          オプション:
            --fix              自動修正可能なエラーを修正します。
            --textlint-only    日本語校正（textlint）のみ実行します。
            --spellcheck-only  スペルチェックのみ実行します。
            --register         未知語を config/user_words.txt へ一括登録します（スペルチェック専用）。
        DESC
      }.freeze

      TEXTLINT_ENV_VAR = 'VIVLIO_TEXTLINT_BIN'

      # CONFIG.lint セクションから設定ファイルパスを取得（シンボルキー前提）
      def self.default_lint_config
        value = Common::CONFIG.lint.config
        value = nil if Common.blank?(value)
        value || DEFAULT_CONFIG_FALLBACK
      rescue StandardError
        DEFAULT_CONFIG_FALLBACK
      end

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

          lint_info  = { exit: 0, lint_count: 0, fixable_count: 0 }
          spell_info = { exit: 0, spell_count: 0 }

          lint_info  = run_textlint(files) unless spellcheck_only?
          spell_info = run_spellcheck(files) unless textlint_only?

          print_combined_summary(lint_info, spell_info)
          [lint_info[:exit], spell_info[:exit]].max
        rescue LintError => e
          Common.log_error(e.message)
          1
        end

        # textlint 本体を実行して結果サマリーを返す。
        # 出力は常にルール単位の集約表示（textlint --format json を取得して整形）。
        def run_textlint(files)
          converted_files = convert_vs_lint_comments(files)
          # textlint は一時ファイルを検査するため、出力の一時パスを元ファイル名へ戻すマップ
          path_map = files.zip(converted_files).to_h { |orig, tmp| [File.expand_path(tmp), orig] }
          run_textlint_aggregated(converted_files, path_map)
        ensure
          cleanup_temp_files(converted_files) if converted_files
          @runtime_config_tmp&.unlink
        end

        # ルール単位で集約した独自表示（--format json で取得して整形）
        def run_textlint_aggregated(files, path_map = {})
          command = build_command(files, format: 'json')
          Common.log_action("textlint 実行: #{Shellwords.join(command)}")
          stdout, stderr, status = Open3.capture3(*command)
          $stderr.print(stderr) unless stderr.nil? || stderr.empty?

          result = TextlintFormatter.aggregate_json(
            stdout, disabled_rules: disabled_rules, disabled_terms: disabled_terms,
                    trim_long_vowel: trim_long_vowel?
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

        # book.yml lint.disabled_rules（ルール ID で丸ごと無効化）
        def disabled_rules
          Array(Common::CONFIG.lint.disabled_rules).map(&:to_s)
        end

        # book.yml lint.disabled_terms（"X => Y" 表記揺れ系の指摘を語で無効化）
        def disabled_terms
          Array(Common::CONFIG.lint.disabled_terms).map(&:to_s)
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

        def print_combined_summary(lint_info, spell_info)
          lint_count  = lint_info[:lint_count].to_i
          spell_count = spell_info[:spell_count].to_i
          fixable     = lint_info[:fixable_count].to_i
          total       = lint_count + spell_count

          Common.log_always ''
          Common.log_always '✏️ 文章の品質チェックが完了しました'
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
          [TEXTLINT_ALLOWLIST_RELATIVE, TEXTLINT_PRH_RELATIVE].each do |rel|
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
          ignore_words = Array(config&.ignore_words).map { it.to_s.downcase }
          check_code   = Common.truthy?(config&.check_code_blocks)

          all_errors = {}
          files.each do |path|
            errors = Lint::SpellChecker.check(path, word_map,
                                              ignore_words: ignore_words,
                                              check_code_blocks: check_code)
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
            Common.log_success("ユーザー辞書へ #{added.size} 語を登録しました")
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

        # 集約表示のため出力は常に json で取得する
        def build_command(files, format: 'json')
          cmd = [textlint_command, '--config', effective_config_path]
          cmd << '--fix' if options[:fix]
          cmd += ['--format', format]
          cmd + files
        end

        def config_path
          path = LintCommands.default_lint_config
          resolved = Common.resolve_path_from_root(path)
          resolved || File.expand_path(path.to_s)
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
        def sentence_length_max
          value = Common::CONFIG.lint.sentence_length_max
          return nil if Common.blank?(value)

          value.to_i.positive? ? value.to_i : nil
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

          if sentence_max
            (rules['preset-ja-technical-writing'] ||= {})['sentence-length'] = { 'max' => sentence_max }
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

        # vs-lint コメントを textlint ネイティブ記法に変換する
        # @param files [Array<String>] 対象ファイルパスの配列
        # @return [Array<String>] 変換後のファイルパスの配列（一時ファイル）
        def convert_vs_lint_comments(files)
          files.map do |path|
            content = File.read(path, encoding: 'UTF-8')
            converted = rewrite_vs_lint_to_textlint(content)

            # 一時ファイルに書き出す
            tmpfile = Tempfile.new(['textlint_', '.md'], encoding: 'UTF-8')
            tmpfile.write(converted)
            tmpfile.close
            tmpfile.path
          end
        end

        # vs-lint コメントを textlint コメントに置換する
        # @param source [String] 元のMarkdown内容
        # @return [String] 変換後のMarkdown内容
        def rewrite_vs_lint_to_textlint(source)
          source
            .gsub(/<!--\s*vs-lint-disable-next-line\s*-->/, '<!-- textlint-disable-next-line -->')
            .gsub(/<!--\s*vs-lint-disable\s*-->/, '<!-- textlint-disable -->')
            .gsub(/<!--\s*vs-lint-enable\s*-->/, '<!-- textlint-enable -->')
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
