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

require_relative 'common'
require_relative 'textlint_formatter'

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

            command = build_command(files)
            Common.log_action("textlint 実行: #{Shellwords.join(command)}")

            stdout, stderr, status = Open3.capture3(*command)
            raw_stdout = stdout
            raw_stderr = stderr

            stdout = filter_textlint_summary(stdout)
            stderr = filter_textlint_summary(stderr)

            # 出力を日本語化
            stdout = TextlintFormatter.translate_output(stdout) unless stdout.nil? || stdout.empty?
            stderr = TextlintFormatter.translate_output(stderr) unless stderr.nil? || stderr.empty?

            $stdout.print(stdout) unless stdout.nil? || stdout.empty?
            $stderr.print(stderr) unless stderr.nil? || stderr.empty?

            return handle_status(status, raw_stdout, raw_stderr)
          rescue TextLintError => e
            Common.log_error(e.message)
            1
          end

          private

          def extract_fixable_count(output)
            return 0 if output.nil? || output.empty?

            # "✓ 325 fixable problems." のような行から数値を抽出
            match = output.match(/✓\s+(\d+)\s+fixable\s+problems?\./)
            match ? match[1].to_i : 0
          end

          def extract_problem_count(output)
            return nil if output.nil? || output.empty?

            match = output.match(/✖\s+(\d+)\s+problems?/)
            match ? match[1].to_i : nil
          end

          def print_failure_summary(problem_count, fixable_count)
            $stdout.puts ''
            $stdout.puts '✏️ 文章の品質チェックが完了しました'
            if problem_count && problem_count.positive?
              $stdout.puts "⚠️ #{problem_count}箇所に改善提案があります"
            else
              $stdout.puts '⚠️ 文章に改善提案があります'
            end

            if fixable_count.to_i.positive? && !options[:fix]
              $stdout.puts "💡 そのうち#{fixable_count}箇所は自動修正可能です。次のコマンドで修正できます:"
              $stdout.puts '   vs lint --fix'
            else
              $stdout.puts '💡 表記揺れや文法上の改善点を修正してからもう一度実行してください。'
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

              unless path && File.file?(path)
                raise LintError, "textlint サポート用設定ファイルが見つかりません: #{display}"
              end

              begin
                yaml_text = File.read(path, encoding: 'UTF-8')
                YAML.safe_load(yaml_text, permitted_classes: [], aliases: true)
              rescue StandardError => e
                raise LintError, "textlint サポート用設定ファイルの読み込みに失敗しました: #{display} (#{e.class}: #{e.message})"
              end
            end
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

          def handle_status(status, raw_stdout, raw_stderr)
            if status.success?
              Common.log_success('textlint: ✅ 文章チェックで問題は見つかりませんでした。')
              return 0
            end

            combined_summary_output = [raw_stdout, raw_stderr].compact.join("\n")
            problem_count = extract_problem_count(combined_summary_output)
            fixable_count = extract_fixable_count(combined_summary_output)
            print_failure_summary(problem_count, fixable_count)

            status.exitstatus || 1
          end

          # Markdown 対象ファイルの解決
          class TargetResolver
            def initialize(raw_targets)
              @raw_targets = Array(raw_targets)
            end

            def resolve
              return glob_all if raw_targets.empty?

              resolved_files = []
              raw_targets.each do |target|
                files = resolve_target(target.to_s)
                resolved_files.concat(files)
              end

              resolved_files.uniq.sort
            end

            private

            attr_reader :raw_targets

            def resolve_target(target)
              # 範囲指定（例: 11-21）
              if range_pattern?(target)
                return resolve_range(target)
              end

              # 章番号のみ（例: 91, 93）
              if numeric_only?(target)
                return resolve_by_chapter_number(target)
              end

              # 通常のファイル名指定（例: 11-install）
              resolve_by_name(target)
            end

            def range_pattern?(target)
              target =~ /^\d+-\d+$/
            end

            def numeric_only?(target)
              target =~ /^\d+$/
            end

            def resolve_range(range_str)
              parts = range_str.split('-')
              return [] if parts.size != 2

              start_num = parts[0].to_i
              end_num = parts[1].to_i
              return [] if start_num > end_num

              all_files = glob_all
              all_files.select do |path|
                basename = File.basename(path, '.md')
                chapter_num = extract_chapter_number(basename)
                chapter_num && chapter_num >= start_num && chapter_num <= end_num
              end
            end

            def resolve_by_chapter_number(num_str)
              all_files = glob_all
              prefix = num_str
              all_files.select do |path|
                basename = File.basename(path, '.md')
                basename.start_with?(prefix + '-')
              end
            end

            def resolve_by_name(name)
              # contents/ プレフィックスを削除し、.md 拡張子を削除
              normalized = name.sub(%r{^#{Regexp.escape(Common::CONTENTS_DIR)}/}, '')
              normalized = normalized.sub(/\.md$/, '')

              path = File.join(Common::CONTENTS_DIR, "#{normalized}.md")
              if File.exist?(path)
                [path]
              else
                Common.log_warn("見つかりません: #{path}")
                []
              end
            end

            def extract_chapter_number(basename)
              match = basename.match(/^(\d+)-/)
              match ? match[1].to_i : nil
            end

            def glob_all
              Dir.glob(File.join(Common::CONTENTS_DIR, '**', '*.md')).sort
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
