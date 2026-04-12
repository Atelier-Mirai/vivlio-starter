# frozen_string_literal: true

# ================================================================
# File: lib/vivlio/starter/cli/lint.rb
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

require_relative 'common'
require_relative 'textlint_formatter'
require_relative 'token_resolver'
require_relative 'lint/tokenizer'
require_relative 'lint/dict_manager'
require_relative 'lint/spell_checker'

module Vivlio
  module Starter
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
              --config PATH    使用する .textlintrc.yml のパスを切り替えます。
                               省略時は book.yml の lint.config が使われます。
              --format NAME    textlint の出力フォーマットを指定します。
                               省略時は book.yml の lint.format（既定: stylish）が使われます。
              --fix            自動修正可能なエラーを修正します。
          DESC
        }.freeze

        DEFAULT_FORMAT_FALLBACK = 'stylish'
        TEXTLINT_ENV_VAR = 'VIVLIO_TEXTLINT_BIN'

        # CONFIG.lint セクションから設定ファイルパスを取得（シンボルキー前提）
        def self.default_lint_config
          value = Common::CONFIG.lint&.config
          value = nil if Common.blank?(value)
          value || DEFAULT_CONFIG_FALLBACK
        rescue StandardError
          DEFAULT_CONFIG_FALLBACK
        end

        # CONFIG.lint セクションから出力フォーマットを取得（シンボルキー前提）
        def self.default_lint_format
          value = Common::CONFIG.lint&.format
          value = nil if Common.blank?(value)
          format = value || DEFAULT_FORMAT_FALLBACK
          format.to_s.strip.empty? ? DEFAULT_FORMAT_FALLBACK : format
        rescue StandardError
          DEFAULT_FORMAT_FALLBACK
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

          def call
            ensure_textlint_available!
            ensure_config_present!
            ensure_support_yaml_files!

            files = resolve_targets
            if files.empty?
              Common.log_warn('textlint 対象となる Markdown ファイルが見つかりません。')
              return 0
            end

            # vs-lint コメントを textlint ネイティブ記法に変換
            converted_files = convert_vs_lint_comments(files)

            begin
              command = build_command(converted_files)
              Common.log_action("textlint 実行: #{Shellwords.join(command)}")

              stdout, stderr, status = Open3.capture3(*command)
              raw_stdout = stdout
              raw_stderr = stderr

              # stylish 出力の構造的再整形（列番号除去・ルール名括弧化・冗長部除去・日本語化）
              stdout = TextlintFormatter.reformat_output(stdout) unless stdout.nil? || stdout.empty?

              stdout = filter_textlint_summary(stdout)
              stderr = filter_textlint_summary(stderr)

              $stdout.print(stdout) unless stdout.nil? || stdout.empty?
              $stderr.print(stderr) unless stderr.nil? || stderr.empty?
              $stdout.puts '' unless stdout.nil? || stdout.empty?

              lint_info   = collect_textlint_info(status, raw_stdout, raw_stderr)
              spell_info  = run_spellcheck(files)
              print_combined_summary(lint_info, spell_info)
              [lint_info[:exit], spell_info[:exit]].max
            ensure
              # 一時ファイルのクリーンアップ
              cleanup_temp_files(converted_files)
            end
          rescue TextLintError => e
            Common.log_error(e.message)
            1
          end

          private

          def extract_fixable_count(output)
            return 0 if output.nil? || output.empty?

            match = output.match(/✓\s+(\d+)\s+fixable\s+problems?\./)
            match ? match[1].to_i : 0
          end

          def extract_problem_count(output)
            return 0 if output.nil? || output.empty?

            match = output.match(/✖\s+(\d+)\s+problems?/)
            match ? match[1].to_i : 0
          end

          def collect_textlint_info(status, raw_stdout, raw_stderr)
            combined      = [raw_stdout, raw_stderr].compact.join("\n")
            lint_count    = extract_problem_count(combined)
            fixable_count = extract_fixable_count(combined)
            exit_code     = status.success? ? 0 : (status.exitstatus || 1)
            { exit: exit_code, lint_count: lint_count, fixable_count: fixable_count }
          end

          def print_combined_summary(lint_info, spell_info)
            lint_count  = lint_info[:lint_count].to_i
            spell_count = spell_info[:spell_count].to_i
            fixable     = lint_info[:fixable_count].to_i
            total       = lint_count + spell_count

            $stdout.puts ''
            $stdout.puts '✏️ 文章の品質チェックが完了しました'
            if total.positive?
              $stdout.puts "⚠️ #{total}箇所に改善提案があります"
              $stdout.puts "   - 日本語校正: #{lint_count}箇所" if lint_count.positive?
              $stdout.puts "   - スペルチェック: #{spell_count}箇所" if spell_count.positive?
              if fixable.positive? && !options[:fix]
                $stdout.puts "💡 そのうち#{fixable}箇所は自動修正可能です。"
                $stdout.puts '   vs lint --fix'
              else
                $stdout.puts '💡 表記揺れや文法上の改善点を修正してからもう一度実行してください。'
              end
            else
              $stdout.puts '✅ 文章チェックで問題は見つかりませんでした。'
            end
            $stdout.flush
          end

          SUMMARY_PATTERNS = [
            /^\s*✖\s+\d+\s+problems?.*$/i,
            /^\s*✓\s+\d+\s+fixable\s+problems?.*$/i,
            /^\s*Try to run:.*$/i
          ].freeze

          def filter_textlint_summary(output)
            return output if output.nil? || output.empty?

            filtered_lines = output.lines.reject do |line|
              SUMMARY_PATTERNS.any? { |pattern| line.match?(pattern) }
            end
            filtered_lines.join
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
            word_map     = Lint::DictManager.new.build_word_map(config)
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
            spell_count = all_errors.values.sum(&:length)
            { exit: spell_count.positive? ? 1 : 0, spell_count: spell_count }
          rescue StandardError => e
            Common.log_warn("[spellcheck] スペルチェック中にエラーが発生しました: #{e.message}")
            { exit: 0, spell_count: 0 }
          end

          def resolve_targets
            resolver = TargetResolver.new(targets)
            resolver.resolve
          end

          def build_command(files)
            cmd = [textlint_command, '--config', config_path]
            cmd << '--fix' if options[:fix]
            fmt = format_option
            cmd += ['--format', fmt] if fmt
            cmd + files
          end

          def config_path
            path = options[:config]
            path = LintCommands.default_lint_config if Common.blank?(path)
            resolved = Common.resolve_path_from_root(path)
            resolved || File.expand_path(path.to_s)
          end

          def format_option
            value = options[:format]
            value = LintCommands.default_lint_format if Common.blank?(value)
            stripped = value.to_s.strip
            stripped.empty? ? LintCommands.default_lint_format : stripped
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
end
