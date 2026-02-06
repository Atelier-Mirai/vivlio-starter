# frozen_string_literal: true

# ================================================================
# Module: BacklinkDedupOrchestrator
# ================================================================
# 責務:
#   バックリンク重複排除のワークフロー全体を統括する。
#
# 処理フロー:
#   1. PageMappingExtractor でヘッドレスブラウザからページマッピングを取得
#   2. BacklinkDeduplicator で HTML を浄化
#   3. 結果のログ出力
#
# パイプライン上の位置:
#   Step 8（全体PDF生成）の後、Step 8b として実行。
#   浄化後の HTML で再度 PDF をビルドする（Step 8c）。
# ================================================================

require_relative 'page_mapping_extractor'
require_relative 'backlink_deduplicator'

module Vivlio
  module Starter
    module CLI
      module Build
        # バックリンク重複排除の全ワークフローを管理
        module BacklinkDedupOrchestrator
          module_function

          # 重複排除を実行し、浄化済み HTML で PDF を再ビルドする
          # @param entries [Array] ビルド対象エントリ（PDF再ビルド時に使用）
          # @return [Boolean] 重複排除が実行されたか
          def run!(entries = [])
            unless glossary_dedup_enabled?
              Common.log_info('[Step 8b] バックリンク重複排除は無効です（book.yml: glossary.backlink_dedup = false）')
              return false
            end

            unless glossary_page_exists?
              Common.log_info('[Step 8b] _glossarypage.html が存在しないためスキップします')
              return false
            end

            # --- Phase 1: ページマッピング抽出 ---
            Common.log_action('[Step 8b] バックリンク重複排除を開始します…')
            page_mapping = extract_page_mapping

            return false unless page_mapping

            # --- Phase 2: HTML 浄化 ---
            result = deduplicate_backlinks(page_mapping)
            log_result(result)

            # --- Phase 3: 浄化された HTML で PDF を再ビルド ---
            if result.files_modified.any?
              Common.log_action('[Step 8c] 浄化済み HTML で PDF を再ビルドします…')
              rebuild_pdf!(entries)
              true
            else
              Common.log_info('[Step 8b] 重複なし。PDF 再ビルドは不要です')
              false
            end
          rescue StandardError => e
            Common.log_warn("[Step 8b] バックリンク重複排除でエラーが発生しました: #{e.message}")
            Common.log_warn('[Step 8b] 重複排除をスキップし、既存の PDF で続行します')
            false
          end

          # --- 設定チェック ---

          # 重複排除機能が有効か
          # book.yml の glossary.backlink_dedup 設定を参照
          # デフォルト: 索引・用語集機能が有効なら true
          def glossary_dedup_enabled?
            # 索引・用語集自体が無効なら dedup も無効
            return false unless IndexCommands.index_enabled?

            # glossary.backlink_dedup が明示的に false なら無効
            dedup_setting = Common::CONFIG.dig('glossary', 'backlink_dedup')
            return dedup_setting != false if dedup_setting != nil

            # デフォルト: 有効
            true
          end

          # 用語集ページが存在するか
          def glossary_page_exists? = File.exist?('_glossarypage.html')

          # --- 各フェーズの実行 ---

          # ページマッピングを抽出
          # @return [PageMappingExtractor::PageMapping, nil]
          def extract_page_mapping
            extractor = PageMappingExtractor.new
            extractor.extract!
          rescue StandardError => e
            Common.log_error("[Step 8b] ページマッピング抽出に失敗: #{e.message}")
            nil
          end

          # HTML のバックリンク重複を排除
          # @param page_mapping [PageMappingExtractor::PageMapping]
          # @return [BacklinkDeduplicator::Result]
          def deduplicate_backlinks(page_mapping)
            deduplicator = BacklinkDeduplicator.new(page_mapping)
            deduplicator.deduplicate!
          end

          # 浄化済み HTML で PDF を再ビルド
          def rebuild_pdf!(entries)
            # entries.js を再生成して PDF をビルド
            # 既存の entries.js がそのまま使えるため、PDF 生成のみ
            PdfCommands.execute_pdf({})

            pdf_config = Common::CONFIG['pdf'] || {}
            output_pdf = pdf_config['output_file'] || 'output.pdf'

            if File.exist?(output_pdf)
              FileUtils.cp(output_pdf, '_sections.pdf')
              Common.log_success('[Step 8c] 重複排除済み _sections.pdf を再生成しました')
            else
              Common.log_warn('[Step 8c] PDF 再ビルドの出力が見つかりません')
            end
          end

          # 結果をログ出力
          def log_result(result)
            Common.log_info("[Step 8b] 用語集バックリンク: #{result.glossary_removed} 件の重複を削除")
            Common.log_info("[Step 8b] 本文 †マーク: #{result.body_removed} 件の重複を削除")
            Common.log_info("[Step 8b] 更新ファイル: #{result.files_modified.join(', ')}") if result.files_modified.any?
          end
        end
      end
    end
  end
end
