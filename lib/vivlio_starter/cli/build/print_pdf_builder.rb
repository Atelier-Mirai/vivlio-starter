# frozen_string_literal: true

require 'fileutils'
require_relative '../cover'
require_relative 'vivliostyle_config_writer'
require_relative 'crop_marks_overlay'
require_relative 'print_geometry'

module VivlioStarter
  module CLI
    module Build
      # ================================================================
      # Build::PrintPdfBuilder — 入稿用（print_pdf）PDF 生成
      # ================================================================
      # output.targets に print_pdf が含まれる場合の一連の生成フローを担う。
      #
      # 生成経路は 2 つある:
      #
      # 【導出フロー（既定）】「pdf ＋トンボ＝ print_pdf」
      #   閲覧用の中間 PDF（`_titlepage_legalpage.pdf` / `_sections.pdf` / `_colophon.pdf`・
      #   dedup 済み）を結合し、qpdf でページジオメトリを塗り足し＋トンボ代付きへ拡張して、
      #   トンボ・ノンブルを重畳し、最後に仕上がり線（TrimBox/BleedBox）を確定する。
      #   入稿用本文が閲覧用と同一レンダリング由来になるため、
      #   ページずれ・内容差・入稿用レンダの flaky が構造的に消え、
      #   本文の再レンダリング 3 回分（実測 172 秒）が丸ごと不要になる。
      #
      # 【従来フロー（フォールバック）】
      #   `output.print_pdf.full_bleed: true`（本文にフチなし＝塗り足しまで届く要素がある本）
      #   では閲覧用 PDF から塗り足しを復元できないため、`--crop-marks --bleed` 付きで
      #   個別にレンダリングする。導出が不能な PDF（回転ページ等）を検出した場合の
      #   自動退避先でもある。
      #
      # いずれの経路でも、結合後は 隠しノンブル → アウトライン → リネーム と進む。
      #
      # ビルド対象の Entry 配列に依存するため、ビルドごとにインスタンス化する。
      # ================================================================
      class PrintPdfBuilder
        # vivliostyle --crop-marks が確保するトンボ代（塗り足しの外側・mm）
        CROP_MARK_OFFSET_MM = CoverCommands::CROP_MARK_OFFSET_MM

        # @param entries [Array<TokenResolver::Entry>] ビルド対象の Entry 配列
        # @param derive [Boolean] 閲覧用 PDF から導出するか。既定は book.yml の
        #   `output.print_pdf.full_bleed` の否定（フチなし要素がなければ導出できる）
        def initialize(entries, derive: !Common.print_pdf_full_bleed?)
          @entries = Array(entries)
          @derive = derive
        end

        # 入稿用 PDF 生成のメインフロー。
        def build!
          Common.log_action('[print pdf] 入稿用 PDF を生成します…')

          # --- Phase: カバー画像の生成（本文と別ファイルで入稿・経路によらず共通） ---
          CoverCommands.ensure_cover_files_for_build!

          # --- Phase: 本文の用意（導出 or 個別レンダリング） ---
          derived = build_by_derivation!
          build_by_rendering! unless derived

          # --- Phase: 仕上げ ---
          stamp_nombre!
          # 導出フローの仕上がり線（TrimBox/BleedBox）はノンブル重畳の後に確定する。
          # 先に書くと qpdf --overlay がトンボ・ノンブルを TrimBox に合わせて
          # 縮小配置してしまうため（仕様 §3.8）、overlay 完了後まで遅延させる。
          finalize_print_boxes! if derived
          add_outline!
          rename!
        end

        private

        attr_reader :entries, :derive

        # ワークスペース pdf/ 配下のパスを組み立てる
        def pdf_path(basename) = File.join(Common::BUILD_PDF_DIR, basename)

        # 結合済み入稿用 PDF のパス（ワークスペース pdf/ 内）
        def output_print_pdf = pdf_path('output_print.pdf')

        # 塗り足し幅（mm）。book.yml の output.print_pdf.bleed 由来
        def bleed_mm = Build::NombreStamper.bleed_mm_from_config

        # トンボを付けるか（book.yml の output.print_pdf.crop_marks。既定 true）
        def crop_marks? = Common::CONFIG.output.print_pdf.crop_marks != false

        # ================================================================
        # 導出フロー
        # ================================================================

        # 閲覧用の中間 PDF から入稿用 PDF を導出する。
        # 導出できない場合（設定・中間物欠落・変換不能な PDF）は false を返し、
        # 呼び出し側が従来フローへ退避する。
        #
        # @return [Boolean] 導出に成功したか
        def build_by_derivation!
          return false unless derive
          return false unless viewing_pdfs_ready?

          Common.log_action('[print pdf] 閲覧用 PDF からトンボ・塗り足し付き PDF を導出します…')
          return false unless merge_into_output_print!(viewing_pdfs, base_basename: '_sections.pdf')

          # crop_marks: false の本はトリムサイズのまま入稿する（従来レンダも --bleed を付けない）
          return true unless crop_marks?

          unless Build::PrintGeometry.expand!(output_print_pdf, bleed_mm:, crop_offset_mm: CROP_MARK_OFFSET_MM)
            Common.log_warn('[print pdf] ジオメトリ変換に失敗したため、従来のレンダリング経路へ切り替えます')
            return false
          end

          Build::CropMarksOverlay.apply!(output_print_pdf, bleed_mm:, crop_offset_mm: CROP_MARK_OFFSET_MM)
        end

        # 手順 3b: 仕上がり線（TrimBox / BleedBox）の確定。
        # トンボ（build_by_derivation!）とノンブル（stamp_nombre!）の overlay が
        # すべて済んでから書く。crop_marks: false の本はジオメトリ拡張自体を
        # 行っていないため対象外。
        def finalize_print_boxes!
          return unless crop_marks? && File.exist?(output_print_pdf)

          return if Build::PrintGeometry.finalize_boxes!(output_print_pdf, bleed_mm:,
                                                         crop_offset_mm: CROP_MARK_OFFSET_MM)

          Common.log_warn('[print pdf] TrimBox / BleedBox の書き込みに失敗しました')
        end

        # 導出のソースになる閲覧用中間 PDF（トリムサイズ・非圧縮・dedup 済み）
        def viewing_pdfs
          %w[_titlepage_legalpage.pdf _sections.pdf _colophon.pdf].map { pdf_path(it) }
        end

        # 本文がなければ導出は成立しない（前付・奥付は欠けても結合を続行できる）
        def viewing_pdfs_ready?
          return true if File.exist?(pdf_path('_sections.pdf'))

          Common.log_warn('[print pdf] 閲覧用の本文 PDF が見つからないため、従来のレンダリング経路で生成します')
          false
        end

        # ================================================================
        # 従来フロー（full_bleed / 導出不能時）
        # ================================================================

        # 本文・前付・奥付を --crop-marks --bleed 付きで個別にレンダリングして結合する。
        def build_by_rendering!
          build_sections!
          build_front_and_tail!

          files = %w[_titlepage_legalpage_print.pdf _sections_print.pdf _colophon_print.pdf].map { pdf_path(it) }
          merge_into_output_print!(files, base_basename: '_sections_print.pdf')
        end

        # 本文セクションの入稿用 PDF を生成
        # 本文 entries（entries.sections.js）を共用し、出力だけ入稿用へ差し替える。
        #
        # 入稿用本文は最重量レンダリングで Chrome の一過性失敗により本文欠落（約4ページ）に
        # なる flaky があったため、本文ガードで検証・リトライし、回復不能ならビルドを中断する。
        def build_sections!
          Common.log_action('[print pdf] 本文 PDF をトンボ・塗り足し付きでビルドします…')
          sections_print = pdf_path('_sections_print.pdf')
          Build::Utilities.build_pdf_with_body_guard!(sections_print, min_pages: sections_min_pages) do
            config = Build::VivliostyleConfigWriter.write_config_only!(
              name: 'sections_print', entries_name: 'sections', output: sections_print
            )
            PdfCommands.execute_print_pdf({}, config_path: config, output_path: sections_print)
          end
        end

        # 入稿用本文 PDF の本文欠落判定に使う下限ページ数。
        # 閲覧用本文 _sections.pdf（既に生成済みの既知良）があればその半分、
        # 無ければ（print_pdf 単独ビルド）本文エントリ数の半分を下限にする。
        # いずれも degenerate（約4ページ）は確実に下回り、正常ビルドは余裕で上回る。
        def sections_min_pages
          viewing = Build::Utilities.page_count(pdf_path('_sections.pdf')).to_i
          return [(viewing * 0.5).floor, 5].max if viewing.positive?

          [(entries.size / 2.0).floor, 5].max
        end

        # 前付・奥付の入稿用 PDF を生成
        # print_pdf 単独ビルドでは特殊ページ HTML が pdf/ に未ステージのため、ここで届ける
        # （pdf 併用時は Step 9 でステージ済み・再コピーは冪等で無害）。
        def build_front_and_tail!
          Build::PdfBuilder.stage_special_pages!(%w[_titlepage _legalpage _colophon])

          build_print_pdf!(name: 'front_print', basenames: %w[_titlepage _legalpage],
                           output_basename: '_titlepage_legalpage_print.pdf')
          build_print_pdf!(name: 'colophon_print', basenames: %w[_colophon],
                           output_basename: '_colophon_print.pdf')
        end

        # 特殊ページの入稿用 PDF を用途別 config でビルドする
        def build_print_pdf!(name:, basenames:, output_basename:)
          entry_htmls = basenames.map { pdf_path("#{it}.html") }.select { File.exist?(it) }
          output = pdf_path(output_basename)
          config = Build::VivliostyleConfigWriter.write!(name:, entry_htmls:, output:)
          PdfCommands.execute_print_pdf({}, config_path: config, output_path: output)
        end

        # ================================================================
        # 共通の仕上げ
        # ================================================================

        # 結合対象を並び順のまま qpdf で結合し output_print.pdf を作る。
        # ※ print_pdf のカバーは本文と別ファイルで入稿するため結合しない
        #   （本文はトンボ・塗り足し付きでサイズが異なる）
        #
        # base_pdf に本文 PDF を指定するのが要点。qpdf はベース PDF の文書カタログを
        # 出力へ引き継ぐため、未指定（＝先頭の前付がベース）だと本文が持つ
        # named destinations（`/Dests`・数千件）が丸ごと捨てられ、リンクのクリック領域だけが
        # 残って目次・索引・用語集の全リンクが無反応になる（閲覧用 merge_all_pdfs! と同じ規約）。
        #
        # @param files [Array<String>] 結合順の PDF パス（未生成のものは自動で除外）
        # @param base_basename [String] カタログ引き継ぎ元にする本文 PDF の basename
        # @return [Boolean] 結合に成功したか
        def merge_into_output_print!(files, base_basename:)
          existing = files.select { File.exist?(it) }

          if existing.empty?
            Common.log_error('[print pdf] 結合対象の入稿用 PDF がありません')
            return false
          end

          # 奥付が偶数ページ（左ページ）に来るよう空白ページ挿入判定
          existing = Build::PdfMerger.insert_blank_page_before_colophon(existing)
          base = pdf_path(base_basename)
          base = existing.first unless existing.include?(base)

          if Build::PdfMerger.merge_pdfs_with_qpdf!(existing, output: output_print_pdf, base_pdf: base)
            Common.log_success('[print pdf] output_print.pdf を生成しました')
            true
          else
            Common.log_error('[print pdf] 入稿用 PDF 結合に失敗しました')
            false
          end
        end

        # 隠しノンブルを書き込む
        def stamp_nombre!
          return unless File.exist?(output_print_pdf)

          Build::NombreStamper.stamp!(output_print_pdf, bleed_mm:)
        end

        # 入稿用 PDF にアウトラインを付与する
        def add_outline!
          return unless File.exist?(output_print_pdf)

          keep_numbers = Build::Utilities.chapter_numbers_for_outline(entries)
          special_pages = %w[_toc]
          special_pages.push('_glossarypage', '_indexpage') if IndexCommands.index_enabled?

          chapter_htmls = Dir.glob(File.join(Common::BUILD_PDF_DIR, '*.html')).select do |path|
            bn = File.basename(path, '.html')
            num = bn[/\A(\d+)-/, 1]&.to_i
            (num && (keep_numbers.nil? || keep_numbers.include?(num))) ||
              special_pages.include?(bn)
          end

          return if chapter_htmls.empty?

          Build::OutlineExtractor.add_outline_from_headings!(
            output_print_pdf, chapter_htmls, max_level: 3, start_page: 1
          )
        end

        # 入稿用 PDF をルート直下の最終ファイル名へ移動する（P4 §3.4-6:
        # 最終成果物のリネーム時のみワークスペースからルートへ出る）
        def rename!
          return unless File.exist?(output_print_pdf)

          target_name = Common.generate_print_pdf_filename
          FileUtils.rm_f(target_name)
          FileUtils.mv(output_print_pdf, target_name)
          Common.log_success("入稿用 PDF をリネームしました: output_print.pdf → #{target_name}")
        end
      end
    end
  end
end
