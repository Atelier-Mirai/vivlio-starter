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
#   - TokenResolver: 章トークンの解決
# ================================================================

require_relative '../build'
require_relative '../build/pipeline'
require_relative '../build/output_helpers'
require_relative '../pre_process'
require_relative '../convert'
require_relative '../post_process'
require_relative '../entries'
require_relative '../pdf'
require_relative '../token_resolver'

module Vivlio
  module Starter
    module CLI
      module SamovarCommands
        # build コマンドの Samovar 実装
        class BuildCommand < Samovar::Command
          self.description = '書籍全体または指定章をビルドします'

          many :targets, 'ビルド対象（章番号 / 範囲 / ベース名）', default: []

          options do
            option '--[no]-resize', '画像最適化を行う（--no-resize で無効）', default: true, key: :resize
            option '--high', '画像最適化プリセット: 高品質', default: false
            option '--medium', '画像最適化プリセット: 中品質', default: false
            option '--low', '画像最適化プリセット: 低品質', default: false
            option '--[no]-compress', 'PDF圧縮を行う（--no-compress でスキップ）', key: :compress
            option '--[no]-clean', '中間生成物をクリーンアップ（--no-clean でスキップ）', default: true, key: :clean
            option '-n/--dry-run', '実行せずにビルド予定のみを表示', default: false, key: :dry_run
            option '--log <level>', 'ログレベルを指定（error/warn/info/debug）', key: :log_level
            option '--force', 'タイトル/リーガル/奥付を強制再生成', default: false
            option '--no-cache', 'キャッシュを無効化（--force と同義）', default: false, value: true, key: :'no-cache'
            option '-h/--help', 'このコマンドの使い方を表示', key: :help
          end

          include Vivlio::Starter::CLI::BuildCommands::OutputHelpers

          def initialize(input = nil, **options)
            processed_input = if input
                                normalized = normalize_log_option_tokens(input)

                                if input.respond_to?(:replace) && !input.equal?(normalized)
                                  input.replace(normalized)
                                  input
                                else
                                  normalized
                                end
                              else
                                input
                              end

            super(processed_input, **options)
          end

          def call
            if options[:help]
              print_usage
              return 0
            end

            if targets.any?
              target_entries = resolve_target_entries

              if target_entries.empty?
                common.log_error('指定した章が catalog.yml に存在しません。build を中断します。')
                return 1
              end

              run_single_mode_build(target_entries)
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

          # CLI 引数から Entry 配列を解決する
          # @return [Array<TokenResolver::Entry>] カタログに存在する章の Entry 配列
          def resolve_target_entries
            resolver = TokenResolver::Resolver.new
            entries = resolver.resolve(targets)
            # カタログに存在する章のみを対象とする
            entries.select(&:in_catalog?)
          end

          # 単章/選択ビルドを実行
          # @param entries [Array<TokenResolver::Entry>] ビルド対象の Entry 配列
          def run_single_mode_build(entries)
            basenames = entries.map(&:basename)
            common.log_action("単章/選択ビルドを実行します: #{basenames.join(', ')}")

            if options[:dry_run]
              print_single_chapter_dry_run(basenames)
              return
            end

            PostProcessCommands::HeadingProcessor.chapter_tokens_override = basenames

            pipeline = BuildCommands::UnifiedBuildPipeline.new(self, entries: entries, mode: :single)
            build_timings = pipeline.run
            IndexCommands.flush_post_build_messages

            print_build_timings(build_timings)
            open_generated_pdf(pipeline.generated_pdf_name)

            common.log_success("単章ビルドが完了しました: #{pipeline.generated_pdf_name}")
          ensure
            PostProcessCommands::HeadingProcessor.chapter_tokens_override = nil
          end

          # フルビルドを実行
          def run_full_mode_build
            resolver = TokenResolver::Resolver.new
            entries = resolver.resolve  # 引数なし = catalog.yml 全章

            if entries.any?
              common.log_action("[Subset] 対象章: #{entries.map(&:basename).inspect}")
            else
              common.log_action('[Subset] catalog.yml に章が定義されていません')
            end

            if options[:dry_run]
              print_full_build_dry_run(entries.map(&:basename))
              return
            end

            pipeline = BuildCommands::UnifiedBuildPipeline.new(self, entries: entries, mode: :full)
            build_timings = pipeline.run
            IndexCommands.flush_post_build_messages

            print_build_timings(build_timings)
            print_outline_debug_info
            save_timings_to_file(build_timings)

            open_pdf(print_pdf_only? ? Common.generate_print_pdf_filename : nil)
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

            Vivlio::Starter::CLI::PdfCommands::PdfOpener.new(pdf_command_options, path).call
          rescue StandardError
            # macOS 専用機能のため失敗しても握りつぶす
          end

          # targets に print_pdf のみ（pdf なし）が指定されているかを判定する
          def print_pdf_only?
            cfg = Common::CONFIG
            targets = Build::PdfMerger.extract_targets(cfg.output&.targets)
            targets = Build::PdfMerger.extract_targets(cfg.output&.pdf&.targets) if targets.empty?
            targets.include?('print_pdf') && !targets.include?('pdf')
          end

          def pdf_command_options
            { verbose: parent_verbose? }
          end

          def parent_verbose?
            parent&.options&.[](:verbose) || false
          end

          def common
            Vivlio::Starter::CLI::Common
          end
        end
      end
    end
  end
end
