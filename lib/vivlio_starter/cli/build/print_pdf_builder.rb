# frozen_string_literal: true

require 'fileutils'

module VivlioStarter
  module CLI
    module Build
      # ================================================================
      # Build::PrintPdfBuilder — 入稿用（print_pdf）PDF 生成
      # ================================================================
      # output.targets に print_pdf が含まれる場合の一連の生成フローを担う。
      # 閲覧用ビルドで生成済みの HTML を再利用し、--crop-marks --bleed 付きで
      # vivliostyle build → PDF 結合 → 隠しノンブル書き込み → アウトライン付与 →
      # リネーム を行う。P2 で pipeline.rb から本ビルダーへ移設した。
      #
      # ビルド対象の Entry 配列に依存するため、ビルドごとにインスタンス化する。
      # ================================================================
      class PrintPdfBuilder
        # @param entries [Array<TokenResolver::Entry>] ビルド対象の Entry 配列
        def initialize(entries)
          @entries = Array(entries)
        end

        # 入稿用 PDF 生成のメインフロー。
        def build!
          Common.log_action('[print pdf] 入稿用 PDF を生成します…')

          # --- Phase: カバー画像の生成 ---
          CoverCommands.ensure_cover_files_for_build!

          # --- Phase: Vivliostyle build（トンボ・塗り足し付き） ---
          build_sections!
          build_front_and_tail!

          # --- Phase: PDF 結合 ---
          merge!

          # --- Phase: 隠しノンブル書き込み ---
          stamp_nombre!

          # --- Phase: アウトライン付与 ---
          add_outline!

          # --- Phase: リネーム ---
          rename!
        end

        private

        attr_reader :entries

        # 本文セクションの入稿用 PDF を生成
        # pdf + print_pdf 併用フローでは、直前の前付・奥付ビルドで entries.js が
        # 奥付のみに上書きされている。周囲の entries.js 状態に依存せず本文を確実にビルドするため、
        # ここで本文用 entries.js を再生成してから入稿用 PDF を生成する。
        #
        # 入稿用本文は最重量レンダリングで Chrome の一過性失敗により本文欠落（約4ページ）に
        # なる flaky があったため、本文ガードで検証・リトライし、回復不能ならビルドを中断する。
        def build_sections!
          Common.log_action('[print pdf] 本文 PDF をトンボ・塗り足し付きでビルドします…')
          Build::Utilities.build_pdf_with_body_guard!('_sections_print.pdf', min_pages: sections_min_pages) do
            Build::PdfBuilder.generate_entries_for_sections!('.', entries)
            PdfCommands.execute_print_pdf({}, '_sections_print.pdf')
          end
        end

        # 入稿用本文 PDF の本文欠落判定に使う下限ページ数。
        # 閲覧用本文 _sections.pdf（既に生成済みの既知良）があればその半分、
        # 無ければ（print_pdf 単独ビルド）本文エントリ数の半分を下限にする。
        # いずれも degenerate（約4ページ）は確実に下回り、正常ビルドは余裕で上回る。
        def sections_min_pages
          viewing = Build::Utilities.page_count('_sections.pdf').to_i
          return [(viewing * 0.5).floor, 5].max if viewing.positive?

          [(entries.size / 2.0).floor, 5].max
        end

        # 前付・奥付の入稿用 PDF を生成
        def build_front_and_tail!
          # タイトルページ + リーガルページ
          EntriesCommands.execute_entries({}, ['_titlepage.html', '_legalpage.html'])
          PdfCommands.execute_print_pdf({}, '_titlepage_legalpage_print.pdf')

          # 奥付
          EntriesCommands.execute_entries({}, ['_colophon.html'])
          PdfCommands.execute_print_pdf({}, '_colophon_print.pdf')
        end

        # 入稿用 PDF を結合する
        # ※ print_pdf のカバーは本文と別ファイルで入稿するため結合しない
        #   （本文はトンボ・塗り足し付きでサイズが異なる）
        #   カバーPDF（CMYK）は covers/ に生成済み
        def merge!
          files = %w[_titlepage_legalpage_print.pdf _sections_print.pdf _colophon_print.pdf]
          existing = files.select { File.exist?(it) }

          if existing.empty?
            Common.log_error('[print pdf] 結合対象の入稿用 PDF がありません')
            return
          end

          # 奥付が偶数ページ（左ページ）に来るよう空白ページ挿入判定
          existing = Build::PdfMerger.insert_blank_page_before_colophon(existing)

          if Build::PdfMerger.merge_pdfs_with_qpdf!(existing, output: 'output_print.pdf')
            Common.log_success('[print pdf] output_print.pdf を生成しました')
          else
            Common.log_error('[print pdf] 入稿用 PDF 結合に失敗しました')
          end
        end

        # 隠しノンブルを書き込む
        def stamp_nombre!
          return unless File.exist?('output_print.pdf')

          bleed_mm = Build::NombreStamper.bleed_mm_from_config
          Build::NombreStamper.stamp!('output_print.pdf', bleed_mm:)
        end

        # 入稿用 PDF にアウトラインを付与する
        def add_outline!
          return unless File.exist?('output_print.pdf')

          keep_numbers = Build::Utilities.chapter_numbers_for_outline(entries)
          special_pages = %w[_toc]
          special_pages.push('_glossarypage', '_indexpage') if IndexCommands.index_enabled?

          chapter_htmls = Dir.glob('*.html').select do |path|
            bn = File.basename(path, '.html')
            num = bn[/\A(\d+)-/, 1]&.to_i
            (num && (keep_numbers.nil? || keep_numbers.include?(num))) ||
              special_pages.include?(bn)
          end

          return if chapter_htmls.empty?

          Build::OutlineExtractor.add_outline_from_headings!(
            'output_print.pdf', chapter_htmls, max_level: 3, start_page: 1
          )
        end

        # 入稿用 PDF を最終ファイル名にリネームする
        def rename!
          return unless File.exist?('output_print.pdf')

          target_name = Common.generate_print_pdf_filename
          return if target_name == 'output_print.pdf'

          FileUtils.rm_f(target_name)
          FileUtils.mv('output_print.pdf', target_name)
          Common.log_success("入稿用 PDF をリネームしました: output_print.pdf → #{target_name}")
        end
      end
    end
  end
end
