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
# 先回り（dedup-rerender-skip-spec.md）:
#   2 回目の組版で直るのはほぼ巻末の索引だけなので、前回のビルドのページ対応で先に
#   索引・用語集の重複を除いてから 1 回目を組み（speculate!）、Step 8 でその判定が今回の
#   PDF でも正しいかを確かめる。正しければ 2 回目を組まない。外れたら今までどおり組み直すので、
#   出来上がりは先回りしないときと変わらない。ページ番号は今までどおり Vivliostyle が数える。
#
# パイプライン上の位置:
#   speculate! は Step 7 のステージングの直後（PdfBuilder）、run! は Step 8。
# ================================================================

require 'fileutils'
require 'json'
require 'tmpdir'
require_relative 'pdf_page_map_extractor'
require_relative 'backlink_deduplicator'

module VivlioStarter
  module CLI
    module Build
      # バックリンク重複排除の全ワークフローを管理
      module BacklinkDedupOrchestrator
        # 先回りの対象（巻末の 2 文書）。本文の † は先回りしない（§4.6）
        BACK_MATTER = %w[_indexpage.html _glossarypage.html].freeze
        RECORD_VERSION = 1

        module_function

        # 重複排除を実行し、必要なら浄化済み HTML で本文 PDF を再ビルドする
        #
        # @param entries [Array] ビルド対象エントリ
        # @param rebuild_pdf [Boolean] 浄化後に閲覧用 _sections.pdf を再レンダするか。
        #   閲覧用 PDF を出力する場合、または入稿用 PDF を閲覧用から導出する場合に true。
        #   入稿用を個別レンダする経路では、print レンダ自体が浄化済み HTML を読むため不要。
        # @param images_changed [Boolean] 1 回目の組版の後、縮小版の画像へ差し替えて HTML が変わったか。
        #   変わっていれば、先回りが当たっても組み直す（§2.6）
        # @return [Boolean] 重複排除が実行されたか
        def run!(_entries = [], rebuild_pdf: true, images_changed: false)
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
          return finish_speculation!(page_mapping, rebuild_pdf:, images_changed:) if speculated?

          # --- Phase 2: HTML 浄化（用語集 + 索引を一括処理） ---
          result = deduplicate_backlinks(page_mapping)
          log_result(result)
          save_record!(page_mapping, result)

          return false if result.files_modified.empty?

          # --- Phase 3: 浄化された HTML で本文 PDF を再ビルド ---
          rerender!(rebuild_pdf)
          true
        rescue StandardError => e
          Common.log_warn("[Step 8] 重複排除でエラーが発生しました: #{e.message}")
          Common.log_warn('[Step 8] 重複排除をスキップし、既存の PDF で続行します')
          false
        end

        # --- 先回り（dedup-rerender-skip-spec.md §4） ---

        # Step 7 の組版の直前（ステージングの後）に、前回のビルドのページ対応で索引・用語集の重複を
        # 先に除く。消したリンクは証拠として文書末に残し、Step 8 で判定を確かめられるようにする。
        # 前回の記録が無いとき・前回本文の † を除いたときは何もしない（今までどおり 2 回組む）
        def speculate!
          FileUtils.rm_rf(originals_dir)
          return unless dedup_enabled? && dedup_target_exists?

          record = load_record
          return unless record

          if record[:body_removed].positive?
            Common.log_info('[Step 8] 前回は本文の † を除いたため、先回りしません')
            return
          end

          FileUtils.mkdir_p(originals_dir)
          back_matter_paths(Common::BUILD_PDF_DIR).each { FileUtils.cp(it, originals_dir) }
          result = BacklinkDeduplicator.new(record[:mapping], body: false, witness: true).deduplicate!
          Common.log_info('[Step 8] 前回のページ対応で、索引・用語集の重複を先に除きました' \
                          "（#{result.index_removed + result.glossary_removed} 件）")
        rescue StandardError => e
          # 書きかけで止まっても、先回り前の HTML へ戻せば今までどおり組める
          back_matter_paths(originals_dir).each { FileUtils.cp(it, Common::BUILD_PDF_DIR) } if Dir.exist?(originals_dir)
          FileUtils.rm_rf(originals_dir)
          Common.log_info("[Step 8] 先回りをやめました: #{e.message}")
        end

        # 1 回目の組版を先回りした HTML で組んだか
        def speculated? = Dir.exist?(originals_dir)

        # 先回りの判定を確かめる。先回り前の HTML に、今回のページ対応（D1）と前回のページ対応（D0）で
        # 重複除去をやり直し、索引・用語集の結果が同じなら当たり。ページ対応そのものではなく結果を比べるのは、
        # 判定に効かないずれ（同じ章の中で吸収される）まで外れに数えないため（§4.3）
        def finish_speculation!(page_mapping, rebuild_pdf:, images_changed:)
          record = load_record
          Dir.mktmpdir('vs-dedup') do |tmp|
            current = File.join(tmp, 'current')
            previous = File.join(tmp, 'previous')
            [current, previous].each { FileUtils.mkdir_p(it) }
            originals = back_matter_paths(originals_dir)
            FileUtils.cp(originals, current)
            FileUtils.cp(originals, previous)
            # 本文は先回りしていないので、pdf/ のものがそのまま元の HTML
            FileUtils.cp(body_paths(Common::BUILD_PDF_DIR), current)

            result = BacklinkDeduplicator.new(page_mapping, dir: current).deduplicate!
            log_result(result)
            save_record!(page_mapping, result)
            BacklinkDeduplicator.new(record[:mapping], dir: previous, body: false).deduplicate! if record

            reason = speculation_miss_reason(result, current, previous, record:, images_changed:, page_mapping:)
            if reason.nil?
              Common.log_info('[Step 8] 前回のページ対応がそのまま使えたため、2 回目の組版を省きました')
              # 入稿用だけの経路は、このあと pdf/ の HTML で入稿用を組むので、証拠のリンクの無い形にしておく
              adopt!(current, result) unless rebuild_pdf
              return true
            end

            Common.log_info("[Step 8] 2 回目の組版を省けませんでした（#{reason}）")
            adopt!(current, result)
          end
          rerender!(rebuild_pdf)
          true
        ensure
          FileUtils.rm_rf(originals_dir)
        end

        # 外れた理由。当たりなら nil
        def speculation_miss_reason(result, current, previous, record:, images_changed:, page_mapping:)
          return '前回の記録を読めませんでした' unless record
          return '縮小版の画像へ差し替えました' if images_changed
          return '本文の † を除きました' if result.body_removed.positive?

          same = BACK_MATTER.all? do |name|
            read_if_exist(File.join(current, name)) == read_if_exist(File.join(previous, name))
          end
          return if same

          # 索引語を書き足す・消すと、その語の参照の通し番号（idx-…-N）が後ろへ向かってずれ、
          # 前回の記録は別の箇所のページを指す。ページのずれとは直し方の見当が違うので分けて知らせる
          if anchor_ids(page_mapping) == anchor_ids(record[:mapping])
            'ページがずれて、索引・用語集の判定が変わりました'
          else
            '本文の索引語・用語が増えたか減ったため、索引・用語集が変わりました'
          end
        end

        def anchor_ids(page_mapping) = (page_mapping.mappings + page_mapping.index_mappings).to_set(&:anchor_id)

        # 今回のページ対応で作り直した HTML を pdf/ へ戻す（索引・用語集は証拠のリンクの無い形）
        def adopt!(dir, result)
          back_matter_paths(dir).each { FileUtils.cp(it, Common::BUILD_PDF_DIR) }
          body_changed = result.files_modified.reject { BACK_MATTER.include?(File.basename(it)) }
          body_changed.each { FileUtils.cp(it, Common::BUILD_PDF_DIR) }
        end

        def rerender!(rebuild_pdf)
          if rebuild_pdf
            Common.log_action('[Step 8] 浄化済み HTML で PDF を再ビルドします…')
            rebuild_pdf!
          else
            Common.log_info('[Step 8] 閲覧用 PDF は出力しないため再ビルドを省略します')
          end
        end

        # 先回り前の索引・用語集の置き場。entries に入らないので組版には混ざらない
        def originals_dir = File.join(Common::BUILD_PDF_DIR, '.dedup-originals')

        def back_matter_paths(dir) = BACK_MATTER.map { File.join(dir, it) }.select { File.exist?(it) }

        def body_paths(dir)
          Dir.glob(File.join(dir, '*.html')).reject { BACK_MATTER.include?(File.basename(it)) }
        end

        def read_if_exist(path) = File.exist?(path) ? File.read(path, encoding: 'utf-8') : nil

        # --- 前回のページ対応の記録（§4.2） ---

        # 巻ごとに分ける。vs build all は巻ごとに別のプロセスで組むので、ファイルが分かれていれば互いを壊さない
        def record_path = File.join(Common::CACHE_DIR, "dedup-pages-#{Volumes.selection_key}.json")

        def save_record!(page_mapping, result)
          pages = (page_mapping.mappings + page_mapping.index_mappings).to_h { [it.anchor_id, it.page_index] }
          data = { 'version' => RECORD_VERSION, 'body_removed' => result.body_removed,
                   'total_pages' => page_mapping.total_pages, 'pages' => pages }
          FileUtils.mkdir_p(File.dirname(record_path))
          File.write(record_path, JSON.generate(data), encoding: 'utf-8')
        rescue SystemCallError => e
          Common.log_debug("[Step 8] ページ対応を記録できませんでした: #{e.message}")
        end

        # 読めない・形の違う記録は無いものとして扱う（今までどおり 2 回組むだけで、出来上がりは変わらない）
        # @return [Hash, nil] { body_removed:, mapping: PdfPageMapExtractor::PageMapping }
        def load_record
          data = JSON.parse(File.read(record_path, encoding: 'utf-8'))
          return nil unless data.is_a?(Hash) && data['version'] == RECORD_VERSION && data['pages'].is_a?(Hash)

          mapping = PdfPageMapExtractor.page_mapping_from(data['pages'], total_pages: data['total_pages'].to_i)
          { body_removed: data['body_removed'].to_i, mapping: }
        rescue SystemCallError, JSON::ParserError
          nil
        end

        # --- 設定チェック ---

        # 重複排除機能が有効か
        # 索引・用語集機能が有効で、かつ用語集または索引の重複排除が有効な場合に true
        # 重複排除は常に行なう。索引・用語集自体が無効なときだけ走らない。
        #
        # かつては index.backlink_dedup / glossary.backlink_dedup で切れたが、
        # 切る利点が無いため 2026-08-08 に設定をやめた。オフにして浮くのは
        # dedup 判定の 0.8 秒だけ（Step 8 の 107 秒はほぼ再レンダで、dedup の
        # 有無に関わらず発生する）。対して失うのは可読性で、用語の出現箇所
        # すべてにダガー印が付き数千箇所のノイズになる
        # （`backlink-dedup-pdf-map-spec.md` §4.4 の実測）。
        def dedup_enabled? = IndexCommands.index_enabled?

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
