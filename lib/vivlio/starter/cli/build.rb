# frozen_string_literal: true

# ================================================================
# File: lib/vivlio/starter/cli/build.rb
# ================================================================
# 責務:
#   Vivlio Starter の統合ビルドコマンドのエントリーポイント。
#   書籍全体または指定章の PDF 生成を一括実行する。
#
# ビルドパイプライン:
#   1. 画像最適化（WebP 変換、リサイズ）
#   2. 前処理（Markdown → frontmatter 付加）
#   3. 変換（Markdown → HTML）
#   4. 後処理（見出し番号付け、コードハイライト）
#   5. 目次生成（_toc.md）
#   6. PDF 生成（Vivliostyle CLI）
#   7. PDF 結合（qpdf）
#   8. アウトライン付与（qpdf）
#   9. PDF 圧縮（Ghostscript）
#   10. クリーンアップ
#
# 依存モジュール（build/ 以下）:
#   - pipeline.rb: UnifiedBuildPipeline（メインのビルドフロー）
#   - catalog_loader.rb: catalog.yml の読み込み
#   - pdf_builder.rb: PDF 生成
#   - pdf_merger.rb: PDF 結合
#   - pdf_finalizer.rb: 最終 PDF の仕上げ
# ================================================================

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
require_relative 'build/outline_extractor'
require_relative 'build/pipeline'
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

        # NOTE: 実際のビルドコマンドは lib/vivlio/starter/cli/samovar/build_command.rb で実装されています。
        # このモジュールは UnifiedBuildPipeline や TokenExpander などのビルドロジックを提供します。
      end
    end
  end
end
