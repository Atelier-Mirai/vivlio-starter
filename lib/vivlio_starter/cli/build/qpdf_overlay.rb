# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/build/qpdf_overlay.rb
# ================================================================
# 責務:
#   qpdf --overlay で、ある PDF の内容を別の PDF のページへ重畳する（in-place）。
#   トンボ（1 ページを全ページへ）と隠しノンブル（ページ 1:1）の共通基盤。
#
# なぜ CombinePDF ではないのか:
#   CombinePDF は保存時に文書カタログの named destinations（`/Dests`）を再構築しないため、
#   重ねただけで目次・索引・用語集のリンクが全滅する。qpdf は構造保存型で壊さない。
#
# なぜページボックスを外すのか（重要）:
#   qpdf --overlay は「重ねる側のページを、重ねられる側の TrimBox（無ければ CropBox）に
#   収まるよう拡大縮小してセンタリング」する。入稿用 PDF の TrimBox は仕上がり線なので、
#   そのまま重ねるとトンボも隠しノンブルも縮小されて本文の内側へ入り込んでしまう。
#   MediaBox しか無いページには等倍で重なるため、重畳の間だけ他のボックスを退避し、
#   終わってから元に戻す。
# ================================================================

require_relative 'qpdf_json'

module VivlioStarter
  module CLI
    module Build
      module QpdfOverlay
        module_function

        # 等倍重畳の妨げになるページボックス（MediaBox 以外）
        SCALING_BOXES = %w[/TrimBox /BleedBox /CropBox /ArtBox].freeze

        # overlay_pdf の内容を target_pdf へ等倍で重畳する。
        #
        # @param target_pdf [String] 重畳先。成功時に上書きされる
        # @param overlay_pdf [String] 重ねる PDF
        # @param repeat [Boolean] true: overlay の 1 ページ目を全ページへ繰り返す /
        #   false: overlay の N ページ目を target の N ページ目へ 1:1 で重ねる
        # @return [Boolean] 重畳に成功したか
        def apply!(target_pdf, overlay_pdf, repeat: false)
          return false unless File.exist?(target_pdf) && File.exist?(overlay_pdf)

          # --- Phase: 等倍で重なるようページボックスを退避 ---
          saved_boxes = detach_scaling_boxes!(target_pdf)
          return false if saved_boxes.nil?

          # --- Phase: 重畳 ---
          success = overlay!(target_pdf, overlay_pdf, repeat:)

          # --- Phase: ページボックスの復帰（重畳でオブジェクト ID が動くため再走査する） ---
          success && attach_boxes!(target_pdf, saved_boxes)
        end

        # MediaBox 以外のページボックスを取り除き、ページ順に控えを返す。
        # 退避すべきボックスが無ければ PDF に触れず空配列を返す（高速パス）。
        #
        # @return [Array<Hash>, nil] ページ順のボックス控え。読み取り失敗時 nil
        def detach_scaling_boxes!(pdf_path)
          header, objects, pages = QpdfJson.read(pdf_path)
          return nil unless pages

          saved = pages.map do |page|
            value = objects["obj:#{page['object']}"]['value']
            value.slice(*SCALING_BOXES)
          end
          return saved if saved.all?(&:empty?)

          updates = pages.each_with_index.to_h do |page, index|
            value = objects["obj:#{page['object']}"]['value'].reject { |key, _| saved[index].key?(key) }
            ["obj:#{page['object']}", { 'value' => value }]
          end

          QpdfJson.apply!(pdf_path, header, updates) ? saved : nil
        end

        # 控えたページボックスを書き戻す
        def attach_boxes!(pdf_path, saved_boxes)
          return true if saved_boxes.all?(&:empty?)

          header, objects, pages = QpdfJson.read(pdf_path)
          return false unless pages

          updates = pages.each_with_index.to_h do |page, index|
            value = objects["obj:#{page['object']}"]['value'].merge(saved_boxes[index] || {})
            ["obj:#{page['object']}", { 'value' => value }]
          end

          QpdfJson.apply!(pdf_path, header, updates)
        end

        # qpdf --overlay 本体
        def overlay!(target_pdf, overlay_pdf, repeat:)
          overlaid = "#{target_pdf}.overlay.tmp.pdf"
          page_args = repeat ? ['--from=', '--repeat=1'] : ['--to=1-z', '--from=1-z']
          success = system('qpdf', target_pdf, overlaid, '--overlay', overlay_pdf, *page_args, '--',
                           out: File::NULL, err: File::NULL)

          if success && File.exist?(overlaid)
            FileUtils.mv(overlaid, target_pdf)
            true
          else
            FileUtils.rm_f(overlaid)
            Common.log_warn('[qpdf] --overlay による重畳に失敗しました')
            false
          end
        end
      end
    end
  end
end
