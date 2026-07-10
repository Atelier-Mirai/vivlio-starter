# frozen_string_literal: true

# ================================================================
# Module: BacklinkDedupOrchestrator
# ================================================================
# 責務:
#   用語集バックリンクおよび索引ページ番号の重複排除ワークフローを統括する。
#
# 処理フロー:
#   1. PdfPageMapExtractor で本文 PDF の named destinations からページマッピングを取得
#      （gls-src-* / idx-* を一括収集）
#   2. BacklinkDeduplicator で HTML を浄化
#      - _glossarypage.html: バックリンク重複排除
#      - 本文 HTML: †リンク重複排除
#      - _indexpage.html: ページ番号リンク重複排除
#   3. 本文 PDF を必要な場合のみ再ビルド
#
# パイプライン上の位置:
#   Step 7（全体PDF生成）の後、Step 8 として実行。
# ================================================================

require_relative 'pdf_page_map_extractor'
require_relative 'backlink_deduplicator'

module VivlioStarter
  module CLI
    module Build
      # バックリンク重複排除の全ワークフローを管理
      module BacklinkDedupOrchestrator
        module_function

        # 重複排除を実行し、必要なら浄化済み HTML で本文 PDF を再ビルドする
        #
        # @param entries [Array] ビルド対象エントリ
        # @param rebuild_pdf [Boolean] 浄化後に閲覧用 _sections.pdf を再レンダするか。
        #   閲覧用 PDF を出力する場合、または入稿用 PDF を閲覧用から導出する場合に true。
        #   入稿用を個別レンダする経路では、print レンダ自体が浄化済み HTML を読むため不要。
        # @return [Boolean] 重複排除が実行されたか
        def run!(entries = [], rebuild_pdf: true)
          unless dedup_enabled?
            Common.log_info('[Step 8] 重複排除は無効です')
            return false
          end

          unless dedup_target_exists?
            Common.log_info('[Step 8] _glossarypage.html / _indexpage.html がいずれも存在しないためスキップします')
            return false
          end

          # --- Phase 1: ページマッピング抽出（本文 PDF の /Dests から） ---
          Common.log_action('[Step 8] 重複排除を開始します…')
          page_mapping = extract_page_mapping

          return false unless page_mapping

          # --- Phase 2: HTML 浄化（用語集 + 索引を一括処理） ---
          result = deduplicate_backlinks(page_mapping)
          log_result(result)

          return false if result.files_modified.empty?

          # --- Phase 3: 浄化された HTML で本文 PDF を再ビルド ---
          if rebuild_pdf
            Common.log_action('[Step 8] 浄化済み HTML で PDF を再ビルドします…')
            rebuild_pdf!(entries)
          else
            Common.log_info('[Step 8] 閲覧用 PDF は出力しないため再ビルドを省略します')
          end
          true
        rescue StandardError => e
          Common.log_warn("[Step 8] 重複排除でエラーが発生しました: #{e.message}")
          Common.log_warn('[Step 8] 重複排除をスキップし、既存の PDF で続行します')
          false
        end

        # --- 設定チェック ---

        # 重複排除機能が有効か
        # 索引・用語集機能が有効で、かつ用語集または索引の重複排除が有効な場合に true
        def dedup_enabled?
          # 索引・用語集自体が無効なら dedup も無効
          return false unless IndexCommands.index_enabled?

          # 用語集または索引のいずれかの dedup が有効なら実行
          glossary_dedup_enabled? || index_dedup_enabled?
        end

        # 用語集の重複排除が有効か
        def glossary_dedup_enabled?
          Common::CONFIG.glossary.backlink_dedup != false
        end

        # 索引の重複排除が有効か
        def index_dedup_enabled?
          Common::CONFIG.index.backlink_dedup != false
        end

        # 重複排除対象の HTML が存在するか
        # dedup はワークスペース pdf/ 配下のコピーに閉じる（P4 §3.4-4）
        def dedup_target_exists?
          File.exist?(File.join(Common::BUILD_PDF_DIR, '_glossarypage.html')) ||
            File.exist?(File.join(Common::BUILD_PDF_DIR, '_indexpage.html'))
        end

        # 本文 PDF（マッピングの供給源であり、dedup 後の再レンダ先でもある）
        def sections_pdf = File.join(Common::BUILD_PDF_DIR, '_sections.pdf')

        # --- 各フェーズの実行 ---

        # ページマッピングを抽出
        # 本文 PDF が未生成の経路（入稿用を個別レンダする print_pdf 単独ビルド）では
        # ここで一度だけ本文をレンダする。従来この経路では preview が全ページを
        # レンダしていたので、同等コストで実 PDF が手に入る。
        #
        # @return [PdfPageMapExtractor::PageMapping, nil]
        def extract_page_mapping
          unless File.exist?(sections_pdf)
            Common.log_action('[Step 8] ページマッピング取得のため本文 PDF を生成します…')
            build_sections_pdf!
          end

          PdfPageMapExtractor.new(sections_pdf).extract!
        rescue StandardError => e
          Common.log_error("[Step 8] ページマッピング抽出に失敗: #{e.message}")
          nil
        end

        # HTML のバックリンク重複を排除
        # @param page_mapping [PdfPageMapExtractor::PageMapping]
        # @return [BacklinkDeduplicator::Result]
        def deduplicate_backlinks(page_mapping)
          deduplicator = BacklinkDeduplicator.new(page_mapping)
          deduplicator.deduplicate!
        end

        # 浄化済み HTML で本文 PDF を再ビルド
        # 本文用生成 config（vivliostyle.config.sections.js）を再実行するだけでよい
        # （P4 §3.2: entries は用途別ファイルのため再生成不要・出力も pdf/_sections.pdf 直行）
        def rebuild_pdf!(_entries = [])
          build_sections_pdf!

          if File.exist?(sections_pdf)
            Common.log_success('[Step 8] 重複排除済み _sections.pdf を再生成しました')
          else
            Common.log_warn('[Step 8] PDF 再ビルドの出力が見つかりません')
          end
        end

        # 本文用生成 config で _sections.pdf をレンダする
        def build_sections_pdf!
          config = File.join(Common::BUILD_PDF_DIR, 'vivliostyle.config.sections.js')
          PdfCommands.execute_pdf({}, config_path: config, output_path: sections_pdf)
        end

        # 結果をログ出力
        def log_result(result)
          Common.log_info("[Step 8] 用語集バックリンク: #{result.glossary_removed} 件の重複を削除")
          Common.log_info("[Step 8] 本文 †マーク: #{result.body_removed} 件の重複を削除")
          Common.log_info("[Step 8] 索引ページ番号: #{result.index_removed} 件の重複を削除")
          if result.files_modified.any?
            Common.log_info("[Step 8] 更新ファイル: #{result.files_modified.join(', ')}")
          else
            Common.log_info('[Step 8] 重複なし。PDF 再ビルドは不要です')
          end
        end
      end
    end
  end
end
