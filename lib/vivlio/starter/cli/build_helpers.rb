# frozen_string_literal: true

require 'rbconfig'
require 'fileutils'
require 'hexapdf'

module Vivlio
  module Starter
    module CLI
      # ==============================================================================
      # Module: BuildHelpers
      # ------------------------------------------------------------------------------
      # build プロセスのステップ実装とユーティリティ群。
      # 「画像最適化 / 前書き先行 / 付録ビルド・結合 / 本文ビルド / TOC 生成 /
      #  全体PDF生成と分割 / frontmatter 構成 / front・tail 生成 / 全PDF結合 / 圧縮 /
      #  ページラベル設定 / ローマ小描画」などの処理を提供する。
      #
      # 直接 Thor コマンドではなく、`BuildCommands#build` から順序制御される想定。
      # 例外は基本的に握りつぶしてログし、可能な限り後続ステップを継続する。
      # ==============================================================================
      module BuildHelpers 
        module_function

        # ================================================================
        # Step 1: 画像最適化（WebP 変換/リサイズ）
        # ------------------------------------------------
        # - 対象: images/, stylesheets/images
        # - プリセット: :high / :medium / :low（既定: :medium）
        # - 実行: Thor タスク resize:*
        # ================================================================
        def optimize_images!(preset = nil)
          p = preset.to_sym
          preset_task = { high: 'resize:high', low: 'resize:low' }[p] || 'resize:medium'

          Common.log_action("[Step 1] 画像の最適化（WebP 変換/リサイズ）を実行します… preset=#{p}")
          dirs = ['images', 'stylesheets/images']
          dirs.each do |d|
            if Dir.exist?(d)
              Common.log_info("[Step 1] 対象ディレクトリ: #{d}（preset: #{p}）")
              Vivlio::Starter::ThorCLI.start([preset_task, d])
            else
              Common.log_info("[Step 1] スキップ（存在しません）: #{d}")
            end
          end
          Common.log_success('[Step 1] 画像最適化が完了しました')
        rescue => e
          Common.log_warn("[Step 1] 画像最適化でエラー: #{e}。ビルドは続行します")
        end

        # ================================================================
        # Step 2: 前書き (02-preface) のみ先行ビルド
        # ------------------------------------------------
        # - pre_process -> convert -> post_process -> entries -> pdf
        # - 出力 output.pdf を 02-preface.pdf にリネーム
        # - ページ数を取得してログ出力
        # ================================================================
        def preface_prebuild!
          Common.log_action('[Step 2] 前書き (02-preface) のみ先行ビルドを実行します…')

          %w[pre_process convert post_process entries].each do |t|
            Vivlio::Starter::ThorCLI.start([t, '02-preface'])
          end
          Vivlio::Starter::ThorCLI.start(['pdf'])

          pdf_config   = CONFIG['pdf'] || {}
          output_pdf   = pdf_config['output_file'] || 'output.pdf'
          preface_pdf  = '02-preface.pdf'
          if File.exist?(output_pdf)
            Common.log_action("preface PDF をリネームしています: #{output_pdf} → #{preface_pdf}")
            FileUtils.rm_f(preface_pdf)
            FileUtils.mv(output_pdf, preface_pdf)
            pages = BuildHelpers.page_count(preface_pdf)
            pages ? Common.log_success("ページ数: #{pages} (#{preface_pdf})") : Common.log_warn("ページ数の取得に失敗しました: #{preface_pdf}")
          else
            Common.log_warn("出力PDFが見つかりません: #{output_pdf}")
          end
        end

        # ================================================================
        # Step 3: 付録 (91〜97) のビルドと結合
        # ------------------------------------------------
        # - 91..97 の章を HTML 生成
        # - merge_appendices で 90-appendices.html を生成
        # - 個別付録 HTML をクリーンアップ
        # ================================================================
        def build_appendices_and_merge_html!
          Common.log_action('[Step 3] 付録章 (91〜97) をビルドします…')

          appendix_paths   = Dir[File.join('contents', '{91,92,93,94,95,96,97}-*.md')]
          appendix_targets = appendix_paths.map { |p| File.basename(p, '.md') }.uniq.sort

          if appendix_targets.empty?
            Common.log_warn('[Step 3] 付録候補(91〜97)が見つかりません。Step 3 をスキップします。')
            return
          end

          Common.log_info("[Step 3] 対象: #{appendix_targets.join(', ')}")
          appendix_targets.each do |target|
            %w[pre_process convert post_process].each do |tn|
              Vivlio::Starter::ThorCLI.start([tn, target])
            end
          end

          # 付録HTMLを結合して 90-appendices.html を生成
          Common.log_action('[Step 3] 付録HTMLを結合して 90-appendices.html を生成します…')
          Vivlio::Starter::ThorCLI.start(['merge_appendices'])
          Common.log_success('[Step 3] 90-appendices.html を生成しました')

          # 個別付録HTMLをクリーンアップ
          begin
            removed = []
            Dir.glob('{91,92,93,94,95,96,97}-*.html').each do |f|
              next unless File.file?(f)
              File.delete(f)
              removed << File.basename(f)
            end
            if removed.any?
              Common.log_info("[Step 3] 個別付録HTMLを削除: #{removed.join(', ')}")
            else
              Common.log_info('[Step 3] 削除対象の個別付録HTMLはありません')
            end
          rescue => e
            Common.log_warn("[Step 3] 個別付録HTMLのクリーンアップでエラー: #{e}")
          end
        rescue => e
          Common.log_warn("[Step 3] 付録ビルド/結合でエラー: #{e}")
        end

        # ================================================================
        # Step 4: 本文章 (11..89) をビルド（HTML生成）
        # ------------------------------------------------
        # - 対象: contents/*.md のうち 11..89 の接頭辞
        # - 実行: pre_process -> convert -> post_process
        # ================================================================
        def build_chapters_html!
          Common.log_action('[Step 4] 章をビルドします…')
          chapter_paths = Dir[File.join('contents', '*.md')]
          chapter_targets = chapter_paths
                              .map { |p| File.basename(p, '.md') }
                              .select { |name| name =~ /\A(\d+)-/ && (11..89).include?($1.to_i) }
                              .uniq
                              .sort

          if chapter_targets.empty?
            Common.log_warn('[Step 4] 章が見つかりません。Step 4 をスキップします。')
            return
          end

          Common.log_info("[Step 4] 対象: #{chapter_targets.join(', ')}")
          chapter_targets.each do |target|
            %w[pre_process convert post_process].each do |tn|
              Vivlio::Starter::ThorCLI.start([tn, target])
            end
          end
        rescue => e
          Common.log_warn("[Step 4] 章ビルドでエラー: #{e}")
        end

        # qpdf で「本文+付録（先頭〜frontmatter直前）」と「末尾frontmatter」を抽出
        def split_pdf_chapters_then_frontmatter(output_pdf, frontmatter_pages, front_pdf, body_pdf)
          total_pages = (BuildHelpers.page_count(output_pdf) || '0').to_i
          if total_pages <= 0
            Common.log_warn("[Step 5] 総ページ数の取得に失敗しました: #{output_pdf}")
            return false
          end

          unless system('which qpdf >/dev/null 2>&1')
            Common.log_warn('[Step 5] qpdf が見つかりません。`brew install qpdf` でインストールしてください。')
            return false
          end

          FileUtils.rm_f(front_pdf)
          FileUtils.rm_f(body_pdf)

          body_end = total_pages - frontmatter_pages
          ok1 = ok2 = true

          if body_end > 0
            Common.log_action("[Step 5] 本文・付録を抽出しています (1-#{body_end})…")
            ok1 = system(%(qpdf "#{output_pdf}" --pages "#{output_pdf}" 1-#{body_end} -- "#{body_pdf}"))
          else
            Common.log_warn('[Step 5] 本文側のページがありません。frontmatter が全ページを占めています。')
          end

          if frontmatter_pages < total_pages
            start_last = body_end + 1
            Common.log_action("[Step 5] frontmatter を抽出しています (#{start_last}-z)…")
            ok2 = system(%(qpdf "#{output_pdf}" --pages "#{output_pdf}" #{start_last}-z -- "#{front_pdf}"))
          else
            Common.log_warn('[Step 5] frontmatter が全ページを占めています。frontmatter 側のみ生成します。')
          end

          if ok1 && ok2
            Common.log_success("[Step 5] 分割完了: #{front_pdf}, #{body_pdf}")
            true
          else
            Common.log_warn('[Step 5] PDF の分割に失敗しました (qpdf 実行エラー)')
            false
          end
        end

        # 付録の番号(91..97)を appendix-[a..g] の letter に対応付け
        def appendix_number_to_letter(num)
          n = num.to_i
          return nil unless n.between?(91, 97)
          ("a".."g").to_a[n - 91]
        rescue
          nil
        end

        # stylesheets/NN.css の chapter-counter を与えた番号に更新
        def update_css_counter(css_path, number)
          return false unless File.exist?(css_path)
          begin
            css = File.read(css_path, encoding: 'utf-8')
            updated = css.gsub(/(counter-reset:\s*chapter-counter\s*)\d+(\s*;)/) do
              pre, post = $1, $2
              "#{pre}#{number.to_i}#{post}"
            end
            if updated != css
              File.write(css_path, updated, encoding: 'utf-8')
              Common.log_success("CSSの章番号を更新しました: #{File.basename(css_path)} → #{number}")
              true
            else
              Common.log_info("CSSに更新対象の counter-reset が見つかりません: #{css_path}")
              false
            end
          rescue => e
            Common.log_warn("CSS更新に失敗しました: #{css_path} (#{e})")
            false
          end
        end


        # ================================================================
        # Step 5: TOC 生成（03-toc.html, 03-toc.pdf）
        # ------------------------------------------------
        # - 対象: 章HTML + 90-appendices.html(存在時)
        # - 実行: toc -> entries(03-toc.html) -> pdf -> 03-toc.pdf へリネーム
        # ================================================================
        def generate_toc_and_pdf!(base_dir = '.')
          chapter_htmls = Dir.glob(File.join(base_dir, '*.html'))
                         .select { |f| File.basename(f) =~ /\A(\d+)-.*\.html\z/ && (11..89).include?($1.to_i) }
                         .sort
          appendix_html = File.join(base_dir, '90-appendices.html')
          targets_for_toc = chapter_htmls
          targets_for_toc << appendix_html if File.exist?(appendix_html)

          if targets_for_toc.empty?
            Common.log_warn('[Step 5] 対象HTMLが見つかりません。Step 5 をスキップします。')
            return
          end

          Common.log_info("[Step 5] 対象: #{targets_for_toc.map { |p| File.basename(p) }.join(', ')}")
          Vivlio::Starter::ThorCLI.start(['toc', *targets_for_toc])
          Vivlio::Starter::ThorCLI.start(['entries', File.join(base_dir, '03-toc.html')])
          Vivlio::Starter::ThorCLI.start(['pdf'])

          pdf_config   = CONFIG['pdf'] || {}
          output_pdf   = pdf_config['output_file'] || 'output.pdf'
          toc_pdf      = '03-toc.pdf'
          if File.exist?(output_pdf)
            Common.log_action("output.pdf をリネームしています: #{output_pdf} → #{toc_pdf}")
            FileUtils.rm_f(toc_pdf)
            FileUtils.mv(output_pdf, toc_pdf)
            Common.log_success('[Step 5] 03-toc.pdf を生成しました')
          end
        end

        # ================================================================
        # Step 6: 全体PDF生成→分割（ディレクトリスキャン版）
        # ------------------------------------------------
        # - base_dir から対象HTML収集
        # - compile_overall_pdf_and_split! に委譲
        # ================================================================
        def build_overall_pdf_and_split_from_dir!(base_dir = '.')
          toc_html = [File.join(base_dir, '03-toc.html')].select { |f| File.exist?(f) }
          chapter_htmls_for_pdf = Dir.glob(File.join(base_dir, '*.html'))
                                     .select { |f| File.basename(f) =~ /\A(\d+)-.*\.html\z/ && (11..89).include?($1.to_i) }
                                     .sort
          appendix_html_for_pdf = File.exist?(File.join(base_dir, '90-appendices.html')) ? [File.join(base_dir, '90-appendices.html')] : []
          targets_for_pdf = chapter_htmls_for_pdf + appendix_html_for_pdf + toc_html

          BuildHelpers.compile_overall_pdf_and_split!(targets_for_pdf)
        rescue => e
          Common.log_warn("[Step 6] 章PDF化/分割でエラー: #{e}")
        end

        # ================================================================
        # Step 6: 全体PDF生成 → frontmatter/chapters に分割
        # ------------------------------------------------
        # - entries.js 生成 -> pdf 出力(output.pdf)
        # - 03-toc.pdf のページ数取得
        # - qpdf により本文+付録と frontmatter に分割
        # ================================================================
        def compile_overall_pdf_and_split!(targets_for_pdf)
          if targets_for_pdf.empty?
            Common.log_warn('[Step 6] 対象HTMLが見つかりません。Step 6 をスキップします。')
            return
          end
          Common.log_info("[Step 6] 対象: #{targets_for_pdf.map { |p| File.basename(p) }.join(', ')}")

          Vivlio::Starter::ThorCLI.start(['entries', *targets_for_pdf])
          Vivlio::Starter::ThorCLI.start(['pdf'])

          pdf_config   = CONFIG['pdf'] || {}
          output_pdf   = pdf_config['output_file'] || 'output.pdf'
          unless File.exist?(output_pdf)
            Common.log_warn("[Step 6] 出力PDFが見つかりません: #{output_pdf}")
            return
          end

          toc_pages = (BuildHelpers.page_count('03-toc.pdf') || '0').to_i
          if toc_pages <= 0
            Common.log_warn('[Step 6] toc のページ数が 0 です。分割をスキップします。')
            return
          end

          BuildHelpers.split_pdf_chapters_then_frontmatter(
            output_pdf,
            toc_pages,
            '03-toc.pdf',
            'chapters_appendices.pdf'
          )
        end

        # 指定PDFの全ページ下部にローマ小を描画（紙面上オーバーレイ）
        def overlay_roman_page_numbers!(pdf_path, options = {})
          return false unless File.exist?(pdf_path)
          opts = { margin_bottom: 24, font: 'Helvetica', size: 10, color: [0, 0, 0] }.merge(options)

          begin
            doc = HexaPDF::Document.open(pdf_path)
            total = doc.pages.count
            mm = 72.0 / 25.4
            (0...total).each do |i|
              page = doc.pages[i]
              media_box = page.box(:media)
              width  = media_box.width
              y = media_box.bottom + opts[:margin_bottom] + (3 * mm)
              text = Common.to_roman_lower(i + 1)

              canvas = page.canvas(type: :overlay)
              canvas.save_graphics_state
              canvas.fill_color(1.0, 1.0, 1.0)
              canvas.opacity(fill_alpha: 1.0, stroke_alpha: 1.0)
              canvas.rectangle(media_box.left, media_box.bottom, width, 25 * mm)
              canvas.fill
              canvas.restore_graphics_state

              canvas.font(opts[:font], size: opts[:size])
              canvas.fill_color(*opts[:color])
              est_text_width = text.length * opts[:size] * 0.5
              x = media_box.left + (width / 2.0) - (est_text_width / 2.0)
              if ((i + 1) % 2) == 1
                x -= 4 * mm
              else
                x += 6 * mm
              end
              canvas.text(text, at: [x, y])
            end

            doc.write(pdf_path, optimize: true)
            true
          rescue => e
            Common.log_warn("[Step 7] ページ番号のオーバーレイ描画でエラー: #{e}")
            false
          end
        end

        # HexaPDF で PageLabels を設定する
        def apply_page_labels_hexapdf(pdf_path, body_pages)
          return false unless File.exist?(pdf_path)
          begin
            doc = HexaPDF::Document.open(pdf_path)
            total = doc.pages.count
            nums = []
            bp = body_pages.to_i
            if bp <= 0
              nums = [0, { S: :r, St: 1 }]
            else
              nums = [0, { S: :D, St: 1 }]
              nums += [bp, { S: :r, St: 1 }] if bp < total
            end
            doc.catalog[:PageLabels] = doc.add({ Type: :NumberTree, Nums: nums })
            doc.write(pdf_path, optimize: true)
            true
          rescue => e
            Common.log_warn("[Step 7] HexaPDF によるページラベル設定でエラー: #{e}")
            false
          end
        end

        # ================================================================
        # Step 7: frontmatter.pdf 構成 + ローマ小付与
        # ------------------------------------------------
        # - 02-preface.pdf + 03-toc.pdf を merge
        # - HexaPDF PageLabels 設定 → 小文字ローマ数字をオーバーレイ描画
        # ================================================================
        def build_frontmatter_pdf!
          Common.log_action('[Step 7] frontmatter.pdf を構成し、ローマ小 i〜 を付与します…')

          files_to_merge = ['02-preface.pdf', '03-toc.pdf']
          existing_files = files_to_merge.select { |f| File.exist?(f) }
          missing_files  = files_to_merge - existing_files
          Common.log_warn("[Step 7] 結合対象が見つかりません: #{missing_files.join(', ')}") if missing_files.any?

          if existing_files.empty?
            Common.log_error('[Step 7] 結合対象PDFがありません。処理を中止します')
            return
          end

          Common.log_info("[Step 7] 結合順: #{existing_files.join(' -> ')}")
          cmd = ['bundle', 'exec', 'hexapdf', 'merge', *existing_files, 'frontmatter.pdf'].join(' ')
          merged = system(cmd)
          if merged && File.exist?('frontmatter.pdf')
            Common.log_success('[Step 7] frontmatter.pdf を生成しました')

            BuildHelpers.apply_page_labels_hexapdf('frontmatter.pdf', 0)
            if BuildHelpers.overlay_roman_page_numbers!('frontmatter.pdf')
              Common.log_success('[Step 7] frontmatter.pdf にローマ小 i〜 を描画しました')
            else
              Common.log_warn('[Step 7] frontmatter.pdf へのローマ小描画をスキップ/失敗')
            end
          else
            Common.log_error('[Step 7] frontmatter.pdf の生成に失敗しました')
          end
        rescue => e
          Common.log_warn("[Step 7] ページ番号連番化処理でエラー: #{e}")
        end

        # ================================================================
        # Step 8: 本扉・扉裏・後書き・奥付の生成
        # ------------------------------------------------
        # - 00-titlepage/01-legalpage/98-postface/99-colophon を個別に PDF 化
        # - postface 開始ページ番号を自動設定（可能なら）
        # ================================================================
        def build_front_pages_and_tail!
          Vivlio::Starter::ThorCLI.start(['create:titlepage'])
          %w[pre_process convert post_process entries].each do |t|
            Vivlio::Starter::ThorCLI.start([t, '00-titlepage'])
          end
          Vivlio::Starter::ThorCLI.start(['pdf'])
          FileUtils.rm_f('titlepage.pdf')
          if File.exist?('output.pdf')
            FileUtils.mv('output.pdf', '00-titlepage.pdf')
            Common.log_success('[Step 8] 00-titlepage.pdf を生成しました')
          else
            Common.log_warn('[Step 8] 00-titlepage の output.pdf が見つかりません')
          end

          %w[pre_process convert post_process entries].each do |t|
            Vivlio::Starter::ThorCLI.start([t, '01-legalpage'])
          end
          Vivlio::Starter::ThorCLI.start(['pdf'])
          FileUtils.rm_f('legalpage.pdf')
          if File.exist?('output.pdf')
            FileUtils.mv('output.pdf', '01-legalpage.pdf')
            Common.log_success('[Step 8] 01-legalpage.pdf を生成しました')
          else
            Common.log_warn('[Step 8] 01-legalpage の output.pdf が見つかりません')
          end

          begin
            ca_pdf = 'chapters_appendices.pdf'
            postface_css = File.join('stylesheets', 'postface.css')
            if File.exist?(ca_pdf) && File.exist?(postface_css)
              ca_pages = HexaPDF::Document.open(ca_pdf).pages.count
              start_page_number = ca_pages + 1
              start_page_number += 1 if ca_pages.odd?
              reset_value = start_page_number - 1

              css = File.read(postface_css, encoding: 'utf-8')
              updated = nil
              if css.include?('counter-reset: page')
                updated = css.gsub(/counter-reset:\s*page\s*\d+/, "counter-reset: page #{reset_value}")
              else
                append_block = <<~CSS

                  @page postface:first {
                      /* 自動設定: 後書き開始ページ番号 */
                      counter-reset: page #{reset_value};
                  }
                  CSS
                updated = css + append_block
              end
              if updated != css
                File.write(postface_css, updated, encoding: 'utf-8')
                Common.log_info("[Step 8] postface.css の開始ページを #{start_page_number} に設定しました (counter-reset: #{reset_value})")
              else
                Common.log_info('[Step 8] postface.css の更新対象が見つかりませんでした（変更なし）')
              end
            else
              Common.log_warn('[Step 8] chapters_appendices.pdf または stylesheets/postface.css が見つからないため、postface 開始ページの自動設定をスキップします')
            end
          rescue => e
            Common.log_warn("[Step 8] postface 開始ページ設定でエラー: #{e}")
          end

          %w[pre_process convert post_process entries].each do |t|
            Vivlio::Starter::ThorCLI.start([t, '98-postface'])
          end
          Vivlio::Starter::ThorCLI.start(['pdf'])
          FileUtils.rm_f('postface.pdf')
          if File.exist?('output.pdf')
            FileUtils.mv('output.pdf', '98-postface.pdf')
            Common.log_success('[Step 8] 98-postface.pdf を生成しました')
          else
            Common.log_warn('[Step 8] 98-postface の output.pdf が見つかりません')
          end

          Vivlio::Starter::ThorCLI.start(['create:colophon'])
          %w[pre_process convert post_process entries].each do |t|
            Vivlio::Starter::ThorCLI.start([t, '99-colophon'])
          end
          Vivlio::Starter::ThorCLI.start(['pdf'])
          FileUtils.rm_f('colophon.pdf')
          if File.exist?('output.pdf')
            FileUtils.mv('output.pdf', '99-colophon.pdf')
            Common.log_success('[Step 8] 99-colophon.pdf を生成しました')
          else
            Common.log_warn('[Step 8] 99-colophon の output.pdf が見つかりません')
          end
        end

        # ================================================================
        # Step 9: すべてのPDFを結合して output.pdf を生成
        # ------------------------------------------------
        # - 必要に応じて 98-postface.pdf の奇数開始調整（空白ページ挿入）
        # - HexaPDF で結合
        # ================================================================
        def merge_all_pdfs!
          Common.log_action('[Step 9] 本扉、扉裏、前書き、目次、本文、付録、後書き、奥付を結合します…')
          files_to_merge = [
            '00-titlepage.pdf', '01-legalpage.pdf', 'frontmatter.pdf',
            'chapters_appendices.pdf', '98-postface.pdf', '99-colophon.pdf'
          ]
          existing_files = files_to_merge.select { |f| File.exist?(f) }
          missing_files  = files_to_merge - existing_files
          Common.log_warn("[Step 9] 結合対象が見つかりません: #{missing_files.join(', ')}") if missing_files.any?
          if existing_files.empty?
            Common.log_error('[Step 9] 結合対象PDFがありません。処理を中止します')
            return
          end

          begin
            postface_name = '98-postface.pdf'
            idx = existing_files.index(postface_name)
            if idx
              total_before = 0
              existing_files[0...idx].each do |pf|
                begin
                  total_before += HexaPDF::Document.open(pf).pages.count
                rescue => e
                  Common.log_warn("[Step 9] ページ数取得失敗: #{pf} (#{e})。0ページとして扱います")
                end
              end
              if total_before.odd?
                blank_path = 'blank_page.pdf'
                begin
                  doc = HexaPDF::Document.new
                  doc.pages.add([0, 0, 595.28, 841.89])
                  doc.write(blank_path, optimize: true)
                  existing_files.insert(idx, blank_path)
                  Common.log_info('[Step 9] 98-postface.pdf を奇数開始にするため、空白1ページを挿入しました')
                rescue => e
                  Common.log_warn("[Step 9] 空白ページPDFの作成に失敗: #{e}。調整をスキップします")
                end
              end
            end
          rescue => e
            Common.log_warn("[Step 9] 奇数ページ開始調整中にエラー: #{e}")
          end

          Common.log_info("[Step 9] 結合順: #{existing_files.join(' -> ')}")
          FileUtils.rm_f('output.pdf')
          cmd = ['bundle', 'exec', 'hexapdf', 'merge', *existing_files, 'output.pdf'].join(' ')
          merged = system(cmd)
          if merged && File.exist?('output.pdf')
            Common.log_success('[Step 9] output.pdf を生成しました')
          else
            Common.log_error('[Step 9] PDF結合に失敗しました')
          end
        end

        # ================================================================
        # Step 10: 生成PDFを圧縮（output.pdf -> output_compressed.pdf）
        # ------------------------------------------------
        # - Vivlio::Starter::ThorCLI.start(['pdf_compress']) を呼び出し
        # - 失敗時は警告ログのみ（ビルド継続）
        # ================================================================
        def compress_pdf!
          Common.log_action('[Step 10] 生成PDFを圧縮します…')
          Vivlio::Starter::ThorCLI.start(['pdf_compress'])
        rescue => e
          Common.log_warn("[Step 10] PDF圧縮でエラー: #{e}")
        end

        # ================================================================
        # Utility: PDF のページ数を取得（pdfinfo が必要）
        # ------------------------------------------------
        # - which pdfinfo で存在確認
        # - `pdfinfo` の出力から "Pages:" を抽出
        # - 取得不可の場合は nil を返す
        # ================================================================
        def page_count(file)
          return nil unless File.exist?(file)
          if system('which pdfinfo >/dev/null 2>&1')
            info = `pdfinfo "#{file}" 2>/dev/null`
            pages = info[/^Pages:\s+(\d+)/i, 1]
            return pages if pages
          end
          nil
        end
      end
    end
  end
end
