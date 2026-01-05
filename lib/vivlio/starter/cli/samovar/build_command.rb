# frozen_string_literal: true

# ================================================================
# File: lib/vivlio/starter/cli/samovar/build_command.rb
# ================================================================
# 責務:
#   Samovar CLI の build コマンドを実装する。
#   書籍全体または指定章の PDF 生成を実行する。
#
# 実行モード:
#   - フルビルド（引数なし）: 全章を含む書籍全体の PDF を生成
#   - 単章ビルド（章番号指定）: 指定章のみの PDF を生成
#
# 主要オプション:
#   - --[no]-resize: 画像最適化の有効/無効
#   - --high/--medium/--low: 画像品質プリセット
#   - --[no]-compress: PDF 圧縮の有効/無効
#   - --dry-run: 実行せずにビルド予定を表示
#   - --force: 特殊ページを強制再生成
#
# 依存:
#   - Build::UnifiedBuildPipeline: ビルドパイプライン
#   - TokenExpander: 章番号・範囲の展開
# ================================================================

require_relative '../build'
require_relative '../build/pipeline'
require_relative '../build/chapter_config'
require_relative '../build/token_expander'
require_relative '../build/output_helpers'
require_relative '../pdf'
require_relative '../post_process'

module Vivlio
  module Starter
    module CLI
      module SamovarCommands
        # build コマンドの Samovar 実装
        class BuildCommand < Samovar::Command
          self.description = '書籍全体または指定章をビルドします'

          many :targets, 'ビルド対象（章番号 / 範囲 / ベース名）', default: []

          options do
            option '--resize/--no-resize', '画像最適化を行う（--no-resize で無効）', default: true, key: :resize
            option '--high', '画像最適化プリセット: 高品質', default: false
            option '--medium', '画像最適化プリセット: 中品質', default: false
            option '--low', '画像最適化プリセット: 低品質', default: false
            option '--compress/--no-compress', 'PDF圧縮を行う（--no-compress で無効）', default: nil, key: :compress
            option '--clean/--no-clean', '中間生成物をクリーンアップ（--no-clean で無効）', default: true, key: :clean
            option '-n/--dry-run', '実行せずにビルド予定のみを表示', default: false, key: :dry_run
            option '--log <level>', 'ログレベルを指定（error/warn/info/debug）', key: :log_level
            option '--force', 'タイトル/リーガル/奥付を強制再生成', default: false
            option '--no-cache', 'キャッシュを無効化（--force と同義）', default: false, key: :'no-cache'
            option '-h/--help', 'このコマンドの使い方を表示', key: :help
          end

          include Vivlio::Starter::CLI::BuildCommands::TokenExpander
          include Vivlio::Starter::CLI::BuildCommands::OutputHelpers

          def initialize(input = nil, **options)
            input = normalize_log_option_tokens(input) if input
            super
          rescue Samovar::UnknownOptionError => e
            @unknown_option_error = e
          end

          def call
            if @unknown_option_error
              Common.log_error("未知のオプションです: #{@unknown_option_error.message}")
              print_usage
              return 1
            end

            if options[:help]
              print_usage
              return 0
            end

            expanded_tokens = expanded_target_tokens

            if expanded_tokens.any?
              run_single_mode_build(expanded_tokens)
            else
              run_full_mode_build
            end

            0
          rescue SystemExit => e
            raise e
          rescue StandardError => e
            common.log_error("Error: #{e.message}")
            1
          ensure
            PostProcessCommands::HeadingProcessor.chapter_tokens_override = nil
          end

          private

          def normalize_log_option_tokens(input)
            tokens = array_from_input(input)
            normalized = []
            idx = 0

            while idx < tokens.length
              token = tokens[idx]

              if token == '--log'
                normalized << '--log'
                next_value = tokens[idx + 1]

                if next_value.nil? || next_value.start_with?('-')
                  normalized << 'info'
                  idx += 1
                else
                  normalized << next_value
                  idx += 2
                  next
                end
              elsif token.start_with?('--log=')
                normalized << '--log'
                level = token.split('=', 2)[1]
                normalized << (level.nil? || level.empty? ? 'info' : level)
              else
                normalized << token
              end

              idx += 1
            end

            normalized
          end

          def array_from_input(input)
            if input.is_a?(Array)
              input.dup
            elsif input.respond_to?(:to_a)
              input.to_a
            else
              Array(input)
            end
          end

          def expanded_target_tokens
            files = Common.normalize_tokens(targets)
            expand_tokens_to_targets(files).map { |basename| basename.sub(/\.md\z/, '') }
          end

          def run_single_mode_build(expanded_tokens)
            common.log_action("単章/選択ビルドを実行します: #{expanded_tokens.join(', ')}")

            if options[:dry_run]
              print_single_chapter_dry_run(expanded_tokens)
              return
            end

            PostProcessCommands::HeadingProcessor.chapter_tokens_override = expanded_tokens

            pipeline = BuildCommands::UnifiedBuildPipeline.new(self, targets: expanded_tokens, mode: :single)
            build_timings = pipeline.run

            print_build_timings(build_timings)
            open_generated_pdf(pipeline.generated_pdf_name)

            common.log_success("単章ビルドが完了しました: #{pipeline.generated_pdf_name}")
          ensure
            PostProcessCommands::HeadingProcessor.chapter_tokens_override = nil
          end

          def run_full_mode_build
            keep = Build::ChapterConfig.configured_chapters

            if keep&.any?
              common.log_action("[Subset] 退避なしで論理的に対象を限定してビルドします: #{keep.inspect}")
            else
              common.log_action("[Subset] chapters 設定なし/'all'のため、フルビルドします（退避なし）")
            end

            if options[:dry_run]
              print_full_build_dry_run(keep)
              return
            end

            pipeline = BuildCommands::UnifiedBuildPipeline.new(self, keep: keep, mode: :full)
            build_timings = pipeline.run

            print_build_timings(build_timings)
            print_outline_debug_info
            save_timings_to_file(build_timings)

            open_pdf
            common.log_success('全ファイルのビルドが完了しました')
          end

          def open_generated_pdf(path)
            return unless path && File.exist?(path)

            open_pdf(path)
          rescue StandardError
            # PDF を開く処理は失敗してもビルド結果には影響させない
          end

          def open_pdf(path = nil)
            return unless defined?(Vivlio::Starter::CLI::PdfCommands::PdfOpener)

            Vivlio::Starter::CLI::PdfCommands::PdfOpener.new(pdf_command_context, path).call
          rescue StandardError
            # macOS 専用機能のため失敗しても握りつぶす
          end

          def pdf_command_context
            @pdf_command_context ||= Struct.new(:options).new(options)
          end

          def common
            Vivlio::Starter::CLI::Common
          end
        end
      end
    end
  end
end
