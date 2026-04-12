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
require_relative '../epub'
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
            option '--[no]-verify', 'リンク・画像の基本検証を実行する（--no-verify でスキップ）', default: true, key: :verify
            option '--verify-links', '外部 URL の HTTP 到達性チェックを実行する', default: false, key: :verify_links
            option '--log <level>', 'ログレベルを指定（error/warn/info/debug）', key: :log_level
            option '-h/--help', 'このコマンドの使い方を表示', key: :help
          end

          include Vivlio::Starter::CLI::BuildCommands::OutputHelpers

          def initialize(input = nil, **)
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

            super(processed_input, **)
          end

          def call
            if options[:help]
              print_usage
              return 0
            end

            # 検証オプションをスレッドローカルに設定（LinkImageValidator が参照）
            setup_verify_options!
            PreProcessCommands::LinkImageValidator.reset!

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
            Thread.current[:vs_verify_options] = nil
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

            PostProcessCommands::HeadingProcessor.chapter_tokens_override = basenames

            pipeline = BuildCommands::UnifiedBuildPipeline.new(self, entries: entries, mode: :single)
            build_timings = pipeline.run
            IndexCommands.flush_post_build_messages

            open_generated_pdf(pipeline.generated_pdf_name)

            # 外部 URL の到達性チェック（--verify-links 有効時のみ）
            PreProcessCommands::LinkImageValidator.check_external_urls!
            # 検証サマリーを表示
            PreProcessCommands::LinkImageValidator.print_summary

            common.log_success("単章ビルドが完了しました: #{pipeline.generated_pdf_name}")
            created_files = get_created_files_list_for_single_mode(basenames)
            print_created_files_message(created_files)

            print_build_timings(build_timings)
          ensure
            PostProcessCommands::HeadingProcessor.chapter_tokens_override = nil
          end

          # フルビルドを実行
          def run_full_mode_build
            resolver = TokenResolver::Resolver.new
            entries = resolver.resolve # 引数なし = catalog.yml 全章

            if entries.any?
              common.log_action("[Subset] 対象章: #{entries.map(&:basename).inspect}")
            else
              common.log_action('[Subset] catalog.yml に章が定義されていません')
            end

            pipeline = BuildCommands::UnifiedBuildPipeline.new(self, entries: entries, mode: :full)
            build_timings = pipeline.run
            IndexCommands.flush_post_build_messages

            open_pdf(print_pdf_only? ? Common.generate_print_pdf_filename : nil)

            # 外部 URL の到達性チェック（--verify-links 有効時のみ）
            PreProcessCommands::LinkImageValidator.check_external_urls!
            # 検証サマリーを表示
            PreProcessCommands::LinkImageValidator.print_summary

            common.log_success('全ファイルのビルドが完了しました')

            created_files = get_created_files_list
            print_created_files_message(created_files)

            print_outline_debug_info
            print_build_timings(build_timings)
          end

          def open_generated_pdf(path)
            return unless pdf_outputs_requested?
            return unless path && File.exist?(path)

            open_pdf(path)
          rescue StandardError
            # PDF を開く処理は失敗してもビルド結果には影響させない
          end

          def open_pdf(path = nil)
            unless pdf_outputs_requested?
              Common.log_info('[open] output.targets に pdf/print_pdf が含まれないためスキップします')
              return
            end
            return unless defined?(Vivlio::Starter::CLI::PdfCommands::PdfOpener)

            Vivlio::Starter::CLI::PdfCommands::PdfOpener.new(pdf_command_options, path).call
          rescue StandardError
            # macOS 専用機能のため失敗しても握りつぶす
          end

          # targets に print_pdf のみ（pdf なし）が指定されているかを判定する
          def print_pdf_only?
            cfg = Common::CONFIG
            targets = Build::PdfMerger.extract_targets(cfg.dig(:output, :targets))
            targets.include?('print_pdf') && !targets.include?('pdf')
          end

          # pdf または print_pdf の出力が要求されているかを判定する
          def pdf_outputs_requested?
            cfg = Common::CONFIG
            targets = Build::PdfMerger.extract_targets(cfg.dig(:output, :targets))

            # targets未指定時はデフォルトでpdfを開く
            return true if targets.empty?

            targets.any? { |target| target.include?('pdf') }
          end

          def pdf_command_options
            { verbose: parent_verbose? }
          end

          def parent_verbose?
            parent&.options&.[](:verbose) || false
          end

          # 生成されたファイルのリストを取得
          def get_created_files_list
            files = []
            targets = Build::PdfMerger.extract_targets(Common::CONFIG.dig(:output, :targets))

            # PDF系
            if targets.include?('pdf')
              normal_pdf = Common.generate_output_filename('pdf')
              files << normal_pdf if File.exist?(normal_pdf)
            end

            if targets.include?('pdf') && options[:compress]
              compressed_pdf = Common.generate_compressed_pdf_filename('pdf')
              files << compressed_pdf if File.exist?(compressed_pdf)
            end

            if targets.include?('print_pdf')
              print_pdf = Common.generate_print_pdf_filename
              files << print_pdf if File.exist?(print_pdf)
            end

            # EPUB
            if targets.include?('epub')
              epub_file = Common.generate_epub_filename
              files << epub_file if File.exist?(epub_file)
            end

            files
          end

          # targetsに応じてファイル名を調整
          def adjust_filename_for_targets(original_name, _basenames)
            targets = Build::PdfMerger.extract_targets(Common::CONFIG.dig(:output, :targets))

            # PDFがtargetsに含まれていない場合
            unless targets.include?('pdf')
              base_name = original_name.sub(/\.pdf$/, '')

              # EPUBがtargetsに含まれている場合
              return "#{base_name}.epub" if targets.include?('epub')
            end

            original_name
          end

          # 単章ビルド用の生成ファイルリストを取得
          def get_created_files_list_for_single_mode(basenames)
            files = []
            targets = Build::PdfMerger.extract_targets(Common::CONFIG.dig(:output, :targets))

            # 単章ビルドのファイル名ベースを決定
            if basenames.size == 1
              base_name = basenames.first
            else
              sorted = basenames.sort_by { |bn| bn[/^(\d+)/, 1].to_i }
              first_num = sorted.first[/^(\d+)/, 1]
              last_num = sorted.last[/^(\d+)/, 1]
              base_name = "#{first_num}-#{last_num}"
            end

            # PDF系
            if targets.include?('pdf')
              pdf_file = "#{base_name}.pdf"
              files << pdf_file if File.exist?(pdf_file)

              if options[:compress]
                compressed_file = "#{base_name}_compressed.pdf"
                files << compressed_file if File.exist?(compressed_file)
              end
            end

            # 入稿用PDF
            if targets.include?('print_pdf')
              print_pdf_file = "#{base_name}_print.pdf"
              files << print_pdf_file if File.exist?(print_pdf_file)
            end

            # EPUB
            if targets.include?('epub')
              epub_file = "#{base_name}.epub"
              files << epub_file if File.exist?(epub_file)
            end

            files
          end

          # 作成されたファイルメッセージを表示
          def print_created_files_message(files)
            return if files.empty?

            file_list = files.map { |f| File.basename(f) }.join(', ')
            Common.echo_always "📚 #{file_list} を作成しました。"
          end

          # CLI の --verify / --verify-links オプションをスレッドローカルに設定する
          # LinkImageValidator が resolve_config で参照する
          def setup_verify_options!
            opts = {}
            if options[:verify] == false
              opts[:no_verify] = true
            else
              opts[:verify_images] = true
              opts[:verify_bare_urls] = true
              opts[:verify_external_links] = options[:verify_links] || false
            end
            Thread.current[:vs_verify_options] = opts
          end

          def common
            Vivlio::Starter::CLI::Common
          end
        end
      end
    end
  end
end
