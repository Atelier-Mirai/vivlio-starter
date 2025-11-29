# frozen_string_literal: true

require 'rbconfig'
require 'fileutils'
require 'time'
require_relative 'post_process/heading_processor'

# Build モジュール群
require_relative 'build/utilities'
require_relative 'build/catalog_loader'
require_relative 'build/catalog_updater'
require_relative 'build/chapter_config'
require_relative 'build/section_builder'
require_relative 'build/image_optimizer'
require_relative 'build/toc_generator'
require_relative 'build/pdf_builder'
require_relative 'build/pdf_merger'
require_relative 'build/pdf_finalizer'
require_relative 'build/page_numberer'
require_relative 'build/outline_extractor'
require_relative 'build/pipeline'
require_relative 'build/token_expander'
require_relative 'build/output_helpers'

module Vivlio
  module Starter
    module CLI
      # ==============================================================================
      # Module: BuildCommands
      # ------------------------------------------------------------------------------
      # Vivlio Starter の統合ビルドコマンド群。
      # 前処理→変換→後処理→目次生成→PDF 結合→圧縮→クリーンまでを一括実行する。
      #
      # 構成:
      #   - build/pipeline.rb       UnifiedBuildPipeline クラス
      #   - build/token_expander.rb トークン展開ロジック
      #   - build/output_helpers.rb 出力・デバッグヘルパー
      # ==============================================================================
      module BuildCommands
        BUILD_DESC = {
          build: {
            short: '書籍全体または指定章をビルドします',
            long: <<~DESC
              CLI から書籍のビルドを一括実行します。

              引数を指定しない場合は、画像最適化、本文/付録の HTML 生成、目次や frontmatter/後書きの生成、
              PDF 結合とアウトライン付与、圧縮、クリーンアップまでを順番に実行し、書籍全体の PDF を生成します。

              引数として章番号や範囲（例: 54 または 54-56）を指定した場合は、その章だけを対象に
              必要な変換処理を実行して PDF を生成します。複数章指定時は統合された 1 つの PDF を出力します。
            DESC
          }
        }.freeze

        module_function

        def included(base)
          base.class_eval do
            desc 'build [TARGETS...]', BUILD_DESC[:build][:short]
            long_desc BUILD_DESC[:build][:long]

            method_option :resize,   type: :boolean, default: true,  desc: '画像最適化を行う（--no-resize で無効）'
            method_option :high,     type: :boolean, default: false, desc: '画像最適化プリセット: 高品質'
            method_option :medium,   type: :boolean, default: false, desc: '画像最適化プリセット: 中品質'
            method_option :low,      type: :boolean, default: false, desc: '画像最適化プリセット: 低品質'
            method_option :compress, type: :boolean, default: nil,   desc: 'PDF圧縮を行う（--no-compress で無効）'
            method_option :clean,    type: :boolean, default: true,  desc: '中間生成物をクリーンアップ（--no-clean で無効）'
            method_option :dry_run,  type: :boolean, aliases: '-n',  desc: '実行せずにビルド予定のみを表示'
            method_option :log,      type: :string,  banner: '[level]', desc: 'ログレベルを指定（error/warn/info/debug）'
            method_option :force,    type: :boolean, default: false, desc: 'タイトル/リーガル/奥付を強制再生成'
            method_option :'no-cache', type: :boolean, default: false, desc: 'キャッシュを無効化（--force と同義）'

            # build コマンド本体
            def build(*tokens)
              files = Common.normalize_tokens(tokens)
              expanded_basenames = expand_tokens_to_targets(files)
              expanded_tokens = expanded_basenames.map { |bn| bn.sub(/\.md\z/, '') }

              # Single Mode: 指定章のみビルド
              if expanded_tokens.any?
                run_single_mode_build(expanded_tokens)
                return
              end

              # Full Mode: 全章ビルド
              run_full_mode_build
            end

            no_commands do
              include TokenExpander
            end

            private

            include OutputHelpers

            # Single Mode ビルドを実行
            def run_single_mode_build(expanded_tokens)
              Common.log_action("単章/選択ビルドを実行します: #{expanded_tokens.join(', ')}")

              if options[:dry_run]
                print_single_chapter_dry_run(expanded_tokens)
                return
              end

              begin
                PostProcessCommands::HeadingProcessor.chapter_tokens_override = expanded_tokens

                pipeline = UnifiedBuildPipeline.new(self, targets: expanded_tokens, mode: :single)
                build_timings = pipeline.run

                print_build_timings(build_timings)

                generated_pdf = pipeline.generated_pdf_name
                if generated_pdf && File.exist?(generated_pdf)
                  begin
                    open_pdf(generated_pdf)
                  rescue StandardError
                    # 失敗してもビルド完了は維持
                  end
                end

                Common.log_success("単章ビルドが完了しました: #{generated_pdf}")
              ensure
                PostProcessCommands::HeadingProcessor.chapter_tokens_override = nil
              end
            end

            # Full Mode ビルドを実行
            def run_full_mode_build
              keep = Build::ChapterConfig.configured_chapters
              if keep&.any?
                Common.log_action("[Subset] 退避なしで論理的に対象を限定してビルドします: #{keep.inspect}")
              else
                Common.log_action("[Subset] chapters 設定なし/'all'のため、フルビルドします（退避なし）")
              end

              if options[:dry_run]
                print_full_build_dry_run(keep)
                return
              end

              pipeline = UnifiedBuildPipeline.new(self, keep: keep, mode: :full)
              build_timings = pipeline.run

              print_build_timings(build_timings)
              print_outline_debug_info
              save_timings_to_file(build_timings)

              begin
                open_pdf
              rescue StandardError
                # 失敗してもビルド完了は維持
              end

              Common.log_success('全ファイルのビルドが完了しました')
            end

            # Dry Run (Full build) を表示
            def print_full_build_dry_run(keep)
              Common.echo_always "\n== Dry Run: フルビルド予定 =="
              resize_desc = if options[:resize] == false
                              'スキップ'
                            else
                              preset = %i[high low].find { |k| options[k] } || :medium
                              "実行 (#{preset})"
                            end
              begin
                keep_numbers = Build::Utilities.chapter_numbers_for_book(keep)
              rescue StandardError
                keep_numbers = nil
              end
              all_md_basenames = Dir.glob(File.join(Common::CONTENTS_DIR, '*.md')).map { |p| File.basename(p, '.md') }
              main_targets     = Build::ChapterConfig.filter_basenames_by_range(all_md_basenames, 11..89, keep_numbers)
              appendix_targets = Build::ChapterConfig.filter_basenames_by_range(all_md_basenames, 91..97, keep_numbers)
              Common.echo_always "  - 画像最適化: #{resize_desc}"
              Common.echo_always "  - 本文(11..89): #{main_targets.empty? ? '対象なし' : main_targets.join(', ')}"
              Common.echo_always "  - 付録(91..97): #{appendix_targets.empty? ? '対象なし' : appendix_targets.join(', ')}"
              Common.echo_always '  - TOC: _toc.html / _toc.pdf'
              Common.echo_always '  - 全体PDF: sections.pdf → 章/TOCに分割'
              Common.echo_always "  - PDF圧縮: #{options[:compress] == false ? 'スキップ' : '実行'}"
              Common.echo_always "  - クリーン: #{options[:clean] == false ? 'スキップ' : '実行'}"
              Common.echo_always "\n計画のみを表示しました（dry-run、実処理は行いません）。"
            end
          end
        end
      end
    end
  end
end
