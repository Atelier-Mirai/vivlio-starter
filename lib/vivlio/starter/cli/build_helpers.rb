# frozen_string_literal: true

require 'rbconfig'
require 'fileutils'
require 'hexapdf'
require 'nokogiri'
require 'cgi'
require 'time'
require 'etc'

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
        @last_outline_debug_info = nil

        def last_outline_debug_info
          @last_outline_debug_info
        end
        module_function :last_outline_debug_info

        module_function

        def cache_store_file(cache_on, source, dest, step_label)
          return false unless cache_on && source && dest && File.exist?(source)

          FileUtils.cp(source, dest)
          Common.log_info("[#{step_label}] キャッシュへ保存しました: #{dest}")
          true
        end

        module_function :cache_store_file

        def cache_restore_file(cache_on, source, dest, step_label)
          return false unless cache_on && source && File.exist?(source) && dest && !File.exist?(dest)

          FileUtils.cp(source, dest)
          Common.log_info("[#{step_label}] キャッシュから復元しました: #{dest}")
          true
        end
        module_function :cache_restore_file

        def chapter_order_from(basenames, base_dir = '.')
          basenames = Array(basenames).map { |bn| bn.to_s.strip }.reject(&:empty?).uniq
          return [] if basenames.empty?

          sort_key = lambda do |bn|
            number = Common.get_chapter_number(bn)
            number ? [number.to_i, bn] : [Float::INFINITY, bn]
          end

          html_basenames = Dir.glob(File.join(base_dir, '*.html'))
                              .map { |path| File.basename(path, '.html') }
                              .uniq
                              .sort_by { |bn| sort_key.call(bn) }

          ordered = html_basenames.select { |bn| basenames.include?(bn) }

          remaining = basenames - ordered
          remaining_sorted = remaining.sort_by { |bn| sort_key.call(bn) }

          ordered + remaining_sorted
        end
        module_function :chapter_order_from

        # 章レンジ（定数化）
        PREFACE_RANGE  = (2..2)
        MAIN_RANGE     = (11..89)
        APPX_RANGE     = (91..97)
        POSTFACE_RANGE = (98..98)

        # ------------------------------------------------
        # Helper: ensure_appendices_guard_html
        # ------------------------------------------------
        # - 目的: 付録を奇数（右）開始にするための 1ページ空白HTMLを生成
        # - 入力: base_dir（生成先ディレクトリ）
        # - 出力: 生成した guard HTML のパス（失敗時は nil）
        # ------------------------------------------------
        def ensure_appendices_guard_html(base_dir = '.')
          path = File.join(base_dir, '90-appendices-guard.html')
          # @page size を現在の book 設定（A4/B5/A5）に合わせる（共通ヘルパ使用）
          width, height = BuildHelpers.page_size_strings_from_config
          html = <<~HTML
            <!doctype html>
            <html>
            <head>
              <meta charset="utf-8">
              <title>Appendices Guard</title>
              <style>
                /* 用紙サイズを book.yml に合わせる */
                @page {
                  size: #{width} #{height};
                }
              </style>
            </head>
            <body></body>
            </html>
          HTML
          File.write(path, html, encoding: 'utf-8')
          path
        end
        module_function :ensure_appendices_guard_html

        # 章ごとの各ステップ処理に計時を付与して実行するユーティリティ。
        # 引数:
        #   chapter: 計測対象の章名（例: '11-install' など）
        #   step:    計測対象のステップ名（例: 'pre_process', 'pdf' など）
        # 仕様:
        #   - 例外の有無に関わらず ensure で計測終了し、ログ出力を行う。
        #   - 計測には単調増加クロック（CLOCK_MONOTONIC）を使用し、システム時刻変更の影響を受けない。
        def time_step_for_chapter(chapter, step)
          # 計測開始（単調クロック）
          t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          begin
            yield if block_given?
          ensure
            t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            dt = (t1 - t0)
            Common.log_action("[Timer] #{chapter} / #{step} : #{format('%.2f', dt)}s")
          end
        end

        # ================================================================
        # Config: 章サブセット（config/book.yml の chapters キー）
        # ------------------------------------------------
        # - 'all' の場合はフルビルド（nil を返して従来どおり）
        # - 配列（['11-foo.md', '12-bar.md', ...]）指定時は、その章のみを残す
        # ================================================================
        def configured_chapters
          cfg = Common::CONFIG['chapters']
          Common.log_info("[Subset] raw chapters config=#{cfg.inspect}") unless cfg.nil?
          return nil if cfg.nil?

          if cfg.is_a?(String)
            str = cfg.to_s
            return nil if str.strip.downcase == 'all'

            # 複数行の文字列もサポート（行ごとに1ファイル名）
            items = str.lines.map { |l| l.to_s.strip }.reject(&:empty?)
            # 正規化: contents/ 接頭や拡張子省略を許容
            items = items.map do |s|
              name = s.sub(%r{\A#{Regexp.escape(Common::CONTENTS_DIR)}/}, '')
              name = "#{name}.md" unless name.end_with?('.md')
              name
            end
            Common.log_info("[Subset] normalized keep(list)=#{items.inspect}") if items.any?
            return items if items.any?

            return nil
          elsif cfg.is_a?(Array)
            items = cfg.map { |s| s.to_s.strip }.reject(&:empty?)
            items = items.map do |s|
              name = s.sub(%r{\A#{Regexp.escape(Common::CONTENTS_DIR)}/}, '')
              name = "#{name}.md" unless name.end_with?('.md')
              name
            end
            Common.log_info("[Subset] normalized keep(array)=#{items.inspect}") if items.any?
            return items
          end
          nil
        end

        # ------------------------------------------------
        # Shared helper: ベース名配列を章番号レンジ＋keepでフィルタ
        # ------------------------------------------------
        # - basenames: 拡張子なしのベース名配列（例: ['11-install', '21-customize']）
        # - range:     章番号レンジ（例: 11..89, 91..97）
        # - keep_numbers: nil または許可する章番号配列（nil の場合は全許可）
        # 返り値: フィルタ済みベース名配列（uniq + sort 済み）
        def filter_basenames_by_range(basenames, range, keep_numbers = nil)
          keep_set = keep_numbers.respond_to?(:include?) ? keep_numbers : nil
          Array(basenames)
            .map(&:to_s)
            .grep(/\A(\d+)-/)
            .select do |bn|
              n = bn[/\A(\d+)-/, 1].to_i
              in_range = range.include?(n)
              allowed  = keep_set ? keep_set.include?(n) : true
              in_range && allowed
            end
            .uniq
            .sort
        end
        module_function :filter_basenames_by_range

        # ------------------------------------------------
        # Shared helper: ディレクトリ内の *.html から、章番号レンジと keep_numbers でフィルタ
        # ------------------------------------------------
        def htmls_for_range(base_dir, range, keep_numbers = nil)
          Dir.glob(File.join(base_dir, '*.html')).select do |path|
            bn = File.basename(path, '.html')
            n = bn[/\A(\d+)-/, 1]&.to_i
            n && range.include?(n) && (keep_numbers.nil? || keep_numbers.include?(n))
          end.sort
        end
        module_function :htmls_for_range

        # ------------------------------------------------
        # Shared helper: 簡易スレッドプールで並列実行
        # ------------------------------------------------
        def parallel_each(items, concurrency: 1, &)
          list = Array(items)
          effective_concurrency = concurrency.to_i
          effective_concurrency = 1 if effective_concurrency <= 0
          Common.log_info("[parallel_each] concurrency=#{effective_concurrency}")
          return list.each(&) if effective_concurrency <= 1

          q = Queue.new
          list.each { |it| q << it }
          sentinel = Object.new
          effective_concurrency.times { q << sentinel }
          workers = Array.new(effective_concurrency) do
            Thread.new do
              loop do
                it = q.pop
                break if it.equal?(sentinel)

                yield(it)
              end
            end
          end
          workers.each(&:join)
        end
        module_function :parallel_each

        def ensure_chapter_html_up_to_date!(basename, extra_sources: [])
          html_path = File.join('.', "#{basename}.html")
          md_path = File.join(Common::CONTENTS_DIR, "#{basename}.md")
          sources = [md_path, *Array(extra_sources)].compact

          needs_regeneration = !File.exist?(html_path)
          unless needs_regeneration
            html_mtime = begin
              File.mtime(html_path)
            rescue StandardError
              Time.at(0)
            end
            latest_source_mtime = sources.select { |src| File.exist?(src) }
                                         .map do |src|
              File.mtime(src)
            rescue StandardError
              Time.at(0)
            end
                                         .max
            needs_regeneration = latest_source_mtime && latest_source_mtime > html_mtime
          end

          return unless needs_regeneration

          Common.log_info("[HTML] 再生成します: #{basename}.html")
          %w[pre_process convert post_process].each do |task|
            Vivlio::Starter::ThorCLI.start([task, basename])
          end
        end
        module_function :ensure_chapter_html_up_to_date!

        # ================================================================
        # Step 1: 画像最適化（WebP 変換/リサイズ）
        # ------------------------------------------------
        # - 対象: images/, stylesheets/images
        # - プリセット: :high / :medium / :low（既定: :medium）
        # - 実行: Thor タスク resize:*
        # ================================================================
        def optimize_images!(preset = nil)
          p = preset&.to_sym || :medium
          preset_task = { high: 'resize:high', low: 'resize:low' }[p] || 'resize:medium'

          Common.log_action("[Step 1] 画像の最適化（WebP 変換/リサイズ）を実行します… preset=#{p}")
          dirs = [Common::IMAGES_DIR, File.join(Common::STYLESHEETS_DIR, 'images')]
          dirs.each do |d|
            if Dir.exist?(d)
              Common.log_info("[Step 1] 対象ディレクトリ: #{d}（preset: #{p}）")
              Vivlio::Starter::ThorCLI.start([preset_task, d])
            else
              Common.log_info("[Step 1] スキップ（存在しません）: #{d}")
            end
          end
          Common.log_success('[Step 1] 画像最適化が完了しました')
        end

        # ================================================================
        # Step 5: 本文、付録、後書き (11..98) をビルド（HTML生成）
        # ------------------------------------------------
        # - 対象: contents/*.md のうち 11..98 の接頭辞
        # - 実行: pre_process -> convert -> post_process
        # ================================================================
        def build_sections_html!(keep = nil)
          Common.log_action('[Step 5] セクション（本文/付録/後書き）をビルドします…（仮想連番: 1,2,3…）')
          keep_numbers_main = BuildHelpers.chapter_numbers_for_book(keep)
          # 付録の keep 抽出（91..97）
          keep_numbers_appx = nil
          keep_numbers_post = nil
          if keep&.any?
            normalized_keep = Array(keep)
                              .map { |s| File.basename(s.to_s, '.md') }
            keep_numbers_appx = normalized_keep
                                .map { |bn| Common.get_chapter_number(bn) }
                                .compact.map(&:to_i)
                                .select { |n| APPX_RANGE.include?(n) }
            keep_numbers_post = normalized_keep
                                .map { |bn| Common.get_chapter_number(bn) }
                                .compact.map(&:to_i)
                                .select { |n| POSTFACE_RANGE.include?(n) }
          end
          all_md_basenames = Dir[File.join(Common::CONTENTS_DIR, '*.md')].map { |p| File.basename(p, '.md') }
          main_targets     = BuildHelpers.filter_basenames_by_range(all_md_basenames, MAIN_RANGE, keep_numbers_main)
          appendix_targets = BuildHelpers.filter_basenames_by_range(all_md_basenames, APPX_RANGE, keep_numbers_appx)
          postface_targets = BuildHelpers.filter_basenames_by_range(all_md_basenames, POSTFACE_RANGE, keep_numbers_post)
          chapter_targets  = (main_targets + appendix_targets + postface_targets).uniq.sort

          if chapter_targets.empty?
            Common.log_warn('[Step 5] 章が見つかりません。Step 5 をスキップします。')
            return
          end

          Common.log_info("[Step 5] 対象: #{chapter_targets.join(', ')}")

          # 並列度（未設定時は min(4, n_cores) を既定に）
          concurrency = (ENV['VIVLIO_BUILD_CONCURRENCY'] || '').to_i
          if concurrency <= 0
            n_cores = Etc.respond_to?(:nprocessors) ? Etc.nprocessors : 2
            concurrency = [n_cores, 4].min
            concurrency = 1 if concurrency <= 0
            Common.log_info("[Step 5] 並列度を自動設定: concurrency=#{concurrency} (cores=#{n_cores})")
          end

          if concurrency == 1
            chapter_targets.each do |target|
              %w[pre_process convert post_process].each do |tn|
                BuildHelpers.time_step_for_chapter(target, tn) do
                  Vivlio::Starter::ThorCLI.start([tn, target])
                end
              end
            end
            return
          end

          Common.log_info("[Step 5] 並列実行を開始します（concurrency=#{concurrency}、対象=#{chapter_targets.size}）")
          BuildHelpers.parallel_each(chapter_targets, concurrency: concurrency) do |target|
            %w[pre_process convert post_process].each do |tn|
              BuildHelpers.time_step_for_chapter(target, tn) do
                Vivlio::Starter::ThorCLI.start([tn, target])
              end
            end
          end
        end

        # ================================================================
        # Step 6: TOC 生成（03-toc.html, 03-toc.pdf）
        # ------------------------------------------------
        # - 対象: 章HTML + 90-appendices.html(存在時)
        # - 実行: toc -> entries(03-toc.html) -> pdf -> 03-toc.pdf へリネーム
        # ================================================================
        def generate_toc_and_pdf!(base_dir = '.', keep = nil)
          keep_numbers_main = BuildHelpers.chapter_numbers_for_book(keep)
          # 付録側の keep（91..97）
          keep_numbers_appx = nil
          if keep&.any?
            normalized_keep = Array(keep)
                              .map { |s| File.basename(s.to_s, '.md') }
            keep_numbers_appx = normalized_keep
                                .map { |bn| Common.get_chapter_number(bn) }
                                .compact.map(&:to_i)
                                .select { |n| APPX_RANGE.include?(n) }
            normalized_keep
              .map { |bn| Common.get_chapter_number(bn) }
              .compact.map(&:to_i)
              .select { |n| POSTFACE_RANGE.include?(n) }
          end
          # base_dir 内の HTML から本文(11..89) + 付録(91..97) を抽出
          chapter_htmls_main = BuildHelpers.htmls_for_range(base_dir, MAIN_RANGE, keep_numbers_main)
          chapter_htmls_appx = BuildHelpers.htmls_for_range(base_dir, APPX_RANGE, keep_numbers_appx)
          targets_for_toc = (chapter_htmls_main + chapter_htmls_appx).uniq.sort

          if targets_for_toc.empty?
            Common.log_warn('[Step 6] 対象HTMLが見つかりません。Step 6 をスキップします。')
            return
          end

          Common.log_info("[Step 6] 対象: #{targets_for_toc.map { |p| File.basename(p) }.join(', ')}")
          Vivlio::Starter::ThorCLI.start(['toc', *targets_for_toc])
          toc_html = File.join(base_dir, '03-toc.html')
          unless File.exist?(toc_html)
            Common.log_warn('[Step 6] 03-toc.html が見つかりません。TOC の PDF 生成をスキップします。')
            return
          end
          # TOC も post_process を適用して見出しメタを付与（PDFアウトライン用）
          Vivlio::Starter::ThorCLI.start(%w[post_process 03-toc])
          Common.log_info('[Step 6] 03-toc.html に post_process を適用しました（見出しメタ付与）')
          Vivlio::Starter::ThorCLI.start(%w[entries 03-toc])
          # 改良された pdf コマンドに出力ファイル名を渡してリネームも一括処理
          Vivlio::Starter::ThorCLI.start(['pdf', '03-toc.pdf'])
          Common.log_success('[Step 6] 03-toc.pdf を生成しました') if File.exist?('03-toc.pdf')
        end

        # ================================================================
        # Step 7: 全体PDF生成→分割（ディレクトリスキャン版）
        # ------------------------------------------------
        # - base_dir から対象HTML収集
        # - compile_overall_pdf_and_split! に委譲
        # ================================================================
        def build_overall_pdf_and_split_from_dir!(base_dir = '.', keep = nil)
          toc_html = [File.join(base_dir, '03-toc.html')].select { |f| File.exist?(f) }
          keep_numbers_main = BuildHelpers.chapter_numbers_for_book(keep)
          keep_numbers_appx = nil
          keep_numbers_post = nil
          if keep&.any?
            normalized_keep = Array(keep)
                              .map { |s| File.basename(s.to_s, '.md') }
            keep_numbers_appx = normalized_keep
                                .map { |bn| Common.get_chapter_number(bn) }
                                .compact.map(&:to_i)
                                .select { |n| APPX_RANGE.include?(n) }
            keep_numbers_post = normalized_keep
                                .map { |bn| Common.get_chapter_number(bn) }
                                .compact.map(&:to_i)
                                .select { |n| POSTFACE_RANGE.include?(n) }
          end
          chapter_htmls_for_pdf = [
            BuildHelpers.htmls_for_range(base_dir, MAIN_RANGE, keep_numbers_main),
            BuildHelpers.htmls_for_range(base_dir, APPX_RANGE, keep_numbers_appx),
            BuildHelpers.htmls_for_range(base_dir, POSTFACE_RANGE, keep_numbers_post)
          ].flatten

          # 付録を奇数（右）ページ開始にするためのガードページを挿入
          # 付録はCSSで右ページ開始を徹底するため、ガードHTMLの自動挿入は行わない

          pdf_target_names = chapter_htmls_for_pdf.map { |p| File.basename(p) }
          toc_target_names = toc_html.map { |p| File.basename(p) }
          targets_for_pdf = chapter_htmls_for_pdf + toc_html
          Common.log_info("[Step 7] targets_for_pdf: #{(pdf_target_names + toc_target_names).join(', ')}")

          BuildHelpers.compile_overall_pdf_and_split!(targets_for_pdf, keep)
        end

        # ================================================================
        # Step 7: 全体PDF生成 → toc(目次)とsections(本文+付録+後書き)に分割
        # ------------------------------------------------
        # - entries.js 生成 -> pdf 出力(output.pdf)
        # - 03-toc.pdf のページ数取得
        # - qpdf によりtoc(目次)とsections(本文+付録+後書き)に分割
        # ================================================================
        def compile_overall_pdf_and_split!(targets_for_pdf, _keep = nil)
          if targets_for_pdf.empty?
            Common.log_warn('[Step 7] 対象HTMLが見つかりません。Step 7 をスキップします。')
            return
          end
          Common.log_info("[Step 7] 対象: #{targets_for_pdf.map { |p| File.basename(p) }.join(', ')}")

          Vivlio::Starter::ThorCLI.start(['entries', *targets_for_pdf])
          Vivlio::Starter::ThorCLI.start(['pdf'])

          pdf_config   = Common::CONFIG['pdf'] || {}
          output_pdf   = pdf_config['output_file'] || 'output.pdf'
          unless File.exist?(output_pdf)
            Common.log_warn("[Step 7] 出力PDFが見つかりません: #{output_pdf}")
            return
          end

          toc_pages = (BuildHelpers.page_count('03-toc.pdf') || '0').to_i
          if toc_pages <= 0
            Common.log_warn('[Step 7] toc のページ数が 0 です。分割をスキップします。')
            return
          end

          BuildHelpers.split_pdf_into_toc_and_sections(
            output_pdf,
            toc_pages,
            '03-toc.pdf',
            '11-98-sections.pdf'
          )
        end

        # 指定PDFの全ページ下部にローマ小を描画（紙面上オーバーレイ）
        def overlay_roman_page_numbers!(pdf_path, options = {})
          return false unless File.exist?(pdf_path)

          opts = { margin_bottom: 24, font: 'Helvetica', size: 10, color: [0, 0, 0] }.merge(options)

          doc = HexaPDF::Document.open(pdf_path)
          total = doc.pages.count
          mm = 72.0 / 25.4
          (0...total).each do |i|
            page = doc.pages[i]
            media_box = page.box(:media)
            width = media_box.width
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
            x += ((i + 1) % 2).zero? ? 6 * mm : -4 * mm
            canvas.text(text, at: [x, y])
          end

          doc.write(pdf_path, optimize: true)
          true
        end

        # HexaPDF で PageLabels を設定する
        def apply_page_labels_hexapdf(pdf_path, body_pages)
          return false unless File.exist?(pdf_path)

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
        end

        # ================================================================
        # Step 8: 02-03-front.pdf 構成 + ローマ小付与
        # ------------------------------------------------
        # - 02-preface.pdf + 03-toc.pdf を merge
        # - HexaPDF PageLabels 設定 → 小文字ローマ数字をオーバーレイ描画
        # ================================================================
        def build_frontmatter_pdf!(keep = nil)
          Common.log_action('[Step 8] 02-03-front.pdf を構成し、ローマ小 i〜 を付与します…')
          # keep 方針: 02/03 は keep に従う（nil=フルビルド時は両方含める）
          include_preface = keep.nil? || Array(keep).map(&:to_s).any? { |s| File.basename(s) == '02-preface.md' }
          include_toc     = keep.nil? || Array(keep).map(&:to_s).any? { |s| File.basename(s) == '03-toc.md' }

          # 02-preface.pdf をキャッシュから復元（必要なら再生成）
          if include_preface && File.exist?(File.join(Common::CONTENTS_DIR, '02-preface.md'))
            cache_on = Common.cache_enabled?
            cache_dir = cache_on ? Common.ensure_cache_dir! : nil
            preface_cache = cache_on && cache_dir ? File.join(cache_dir, '02-preface.pdf') : nil
            BuildHelpers.ensure_chapter_html_up_to_date!('02-preface', extra_sources: File.join('config', 'book.yml'))

            needs_preface = !File.exist?('02-preface.pdf')
            needs_preface &&= !cache_restore_file(cache_on, preface_cache, '02-preface.pdf', 'Step 8')

            if needs_preface
              %w[pre_process convert post_process entries].each do |t|
                Vivlio::Starter::ThorCLI.start([t, '02-preface'])
              end
              Vivlio::Starter::ThorCLI.start(['pdf', '02-preface.pdf'])
              Common.log_success('[Step 8] 02-preface.pdf を生成しました') if File.exist?('02-preface.pdf')
              cache_store_file(cache_on, '02-preface.pdf', preface_cache, 'Step 8')
            else
              Common.log_action('[Step 8] 前書きPDFは最新のため再利用します: 02-preface.pdf')
            end
          end

          files_to_merge = []
          files_to_merge << '02-preface.pdf' if include_preface
          files_to_merge << '03-toc.pdf'     if include_toc
          existing_files = files_to_merge.select { |f| File.exist?(f) }
          missing_files  = files_to_merge - existing_files
          Common.log_warn("[Step 8] 結合対象が見つかりません: #{missing_files.join(', ')}") if missing_files.any?

          # どちらか1つだけ存在する場合は、それを 02-03-front.pdf として採用
          if existing_files.length == 1
            src = existing_files.first
            FileUtils.rm_f('02-03-front.pdf')
            FileUtils.cp(src, '02-03-front.pdf')
            Common.log_success("[Step 8] 02-03-front.pdf を単一ソースから生成しました: #{src}")

            # frontmatter のページ数が奇数なら、末尾に空白1ページを追加して本文を右ページ開始に揃える
            pages = (BuildHelpers.page_count('02-03-front.pdf') || '0').to_i
            if pages.odd?
              doc = HexaPDF::Document.open('02-03-front.pdf')
              first_box = doc.pages[0].box(:media)
              doc.pages.add([first_box.left, first_box.bottom, first_box.right, first_box.top])
              doc.write('02-03-front.pdf', optimize: true)
              Common.log_info('[Step 8] 02-03-front.pdf が奇数ページのため、空白1ページを末尾に挿入しました')
            end

            BuildHelpers.apply_page_labels_hexapdf('02-03-front.pdf', 0)
            if BuildHelpers.overlay_roman_page_numbers!('02-03-front.pdf')
              Common.log_success('[Step 8] 02-03-front.pdf にローマ小 i〜 を描画しました')
            else
              Common.log_warn('[Step 8] 02-03-front.pdf へのローマ小描画をスキップ/失敗')
            end

            return
          elsif existing_files.empty?
            Common.log_warn('[Step 8] frontmatter 構成対象PDFがありません。02-03-front.pdf の生成をスキップします')
            return
          end

          Common.log_info("[Step 8] 結合順: #{existing_files.join(' -> ')}")
          FileUtils.rm_f('02-03-front.pdf')
          cmd = ['bundle', 'exec', 'hexapdf', 'merge', *existing_files, '02-03-front.pdf'].join(' ')
          merged = system(cmd)
          if merged && File.exist?('02-03-front.pdf')
            Common.log_success('[Step 8] 02-03-front.pdf を生成しました')

            # frontmatter のページ数が奇数なら、末尾に空白1ページを追加して本文を右ページ開始に揃える
            pages = (BuildHelpers.page_count('02-03-front.pdf') || '0').to_i
            if pages.odd?
              doc = HexaPDF::Document.open('02-03-front.pdf')
              first_box = doc.pages[0].box(:media)
              doc.pages.add([first_box.left, first_box.bottom, first_box.right, first_box.top])
              doc.write('02-03-front.pdf', optimize: true)
              Common.log_info('[Step 8] 02-03-front.pdf が奇数ページのため、空白1ページを末尾に挿入しました')
            end

            BuildHelpers.apply_page_labels_hexapdf('02-03-front.pdf', 0)
            if BuildHelpers.overlay_roman_page_numbers!('02-03-front.pdf')
              Common.log_success('[Step 8] 02-03-front.pdf にローマ小 i〜 を描画しました')
            else
              Common.log_warn('[Step 8] 02-03-front.pdf へのローマ小描画をスキップ/失敗')
            end
          else
            Common.log_error('[Step 8] 02-03-front.pdf の生成に失敗しました')
          end
        end

        # ================================================================
        # Step 9: 本扉・扉裏・後書き・奥付の生成
        # ------------------------------------------------
        # - 00-titlepage/01-legalpage をまとめて 00-01-front.pdf に統合
        # - 98-postface/99-colophon を個別に PDF 化
        # - postface 開始ページ番号を自動設定（可能なら）
        # ================================================================
        def build_front_pages_and_tail!(force = false)
          front_regenerated = false
          BuildHelpers.ensure_chapter_html_up_to_date!('00-titlepage', extra_sources: File.join('config', 'book.yml'))
          BuildHelpers.ensure_chapter_html_up_to_date!('01-legalpage', extra_sources: File.join('config', 'book.yml'))
          BuildHelpers.ensure_chapter_html_up_to_date!('99-colophon', extra_sources: File.join('config', 'book.yml'))
          # 判定ヘルパ
          front_srcs = [
            File.join(Common::CONTENTS_DIR, '00-titlepage.md'),
            File.join(Common::CONTENTS_DIR, '01-legalpage.md'),
            File.join('config', 'book.yml')
          ]
          colophon_srcs = [
            File.join(Common::CONTENTS_DIR, '99-colophon.md'),
            File.join('config', 'book.yml')
          ]

          newer_than_any = lambda do |target, sources|
            return true unless File.exist?(target)

            t_mtime = File.exist?(target) ? File.mtime(target) : Time.at(0)
            Array(sources).any? { |s| File.exist?(s) && File.mtime(s) > t_mtime }
          end

          front_pdf = '00-01-front.pdf'
          colophon_pdf = '99-colophon.pdf'
          cache_on = Common.cache_enabled? && !force
          cache_dir = cache_on ? Common.ensure_cache_dir! : nil
          front_cache = cache_on && cache_dir ? File.join(cache_dir, front_pdf) : nil
          colophon_cache = cache_on && cache_dir ? File.join(cache_dir, colophon_pdf) : nil

          front_missing = !File.exist?(front_pdf)
          front_missing &&= !cache_restore_file(cache_on, front_cache, front_pdf, 'Step 9')

          colophon_missing = !File.exist?(colophon_pdf)
          colophon_missing &&= !cache_restore_file(cache_on, colophon_cache, colophon_pdf, 'Step 9')

          need_front = force || front_missing || newer_than_any.call(front_pdf, front_srcs)

          if need_front
            # マージは行わず、2本のHTMLを entries に渡して単一PDF化
            Vivlio::Starter::ThorCLI.start(['entries', '00-titlepage.html', '01-legalpage.html'])
            # 直接フロントPDF名を指定して生成
            Vivlio::Starter::ThorCLI.start(['pdf', front_pdf])
            if File.exist?(front_pdf)
              Common.log_success("[Step 9] #{front_pdf} を生成しました")
              cache_store_file(cache_on, front_pdf, front_cache, 'Step 9')
              front_regenerated = true
            else
              Common.log_warn("[Step 9] #{front_pdf} の生成に失敗しました")
            end
          else
            Common.log_action("[Step 9] フロント/奥付PDFは最新のため再利用します: #{front_pdf}, #{colophon_pdf}")
            cache_restore_file(cache_on, front_cache, front_pdf, 'Step 9') unless File.exist?(front_pdf)
            cache_restore_file(cache_on, colophon_cache, colophon_pdf, 'Step 9') unless File.exist?(colophon_pdf)
          end

          # ここから奥付の生成（必要に応じて再生成）
          need_colophon = force || front_regenerated || colophon_missing || newer_than_any.call(colophon_pdf, colophon_srcs)
          if need_colophon
            Vivlio::Starter::ThorCLI.start(['entries', '99-colophon.html'])
            Vivlio::Starter::ThorCLI.start(['pdf', colophon_pdf])
            if File.exist?(colophon_pdf)
              Common.log_success('[Step 9] 99-colophon.pdf を生成しました')
              cache_store_file(cache_on, colophon_pdf, colophon_cache, 'Step 9')
            else
              Common.log_warn('[Step 9] 99-colophon.pdf の生成に失敗しました')
            end
          else
            Common.log_info('[Step 9] 奥付は最新のため、再生成をスキップしました（既存/キャッシュを利用）')
          end
        end

        # ================================================================
        # Step 10: すべてのPDFを結合して output.pdf を生成
        # ------------------------------------------------
        # - 必要に応じて 98-postface.pdf の奇数開始調整（空白ページ挿入）
        # - HexaPDF で結合
        # ================================================================
        def merge_all_pdfs_only!(_keep = nil)
          Common.log_action('[Step 10] フロント(00-01)、前書き、目次、本文、付録、奥付を結合します…')
          Common.log_info('[Step 10] 存在するPDFのみで結合を実行します（02-preface.pdf は任意）')
          files_to_merge = [
            '00-01-front.pdf', '02-03-front.pdf',
            '11-98-sections.pdf', '99-colophon.pdf'
          ]
          existing_files = files_to_merge.select { |f| File.exist?(f) }
          missing_files  = files_to_merge - existing_files
          optional_files = []
          missing_required = missing_files - optional_files
          Common.log_warn("[Step 10] 結合対象が見つかりません: #{missing_required.join(', ')}") if missing_required.any?
          missing_optional = missing_files & optional_files
          Common.log_info("[Step 10] 任意のPDFが見つかりません（スキップ）: #{missing_optional.join(', ')}") if missing_optional.any?
          if existing_files.empty?
            Common.log_error('[Step 10] 結合対象PDFがありません。処理を中止します')
            return false
          end

          FileUtils.rm_f('output.pdf')
          cmd = ['bundle', 'exec', 'hexapdf', 'merge', *existing_files, 'output.pdf'].join(' ')
          merged = system(cmd)
          if merged && File.exist?('output.pdf')
            Common.log_success('[Step 10] output.pdf を生成しました')
            true
          else
            Common.log_error('[Step 10] PDF結合に失敗しました')
            false
          end
        end

        def add_outline_to_output_pdf!(keep = nil)
          unless File.exist?('output.pdf')
            Common.log_warn('[Step 11] output.pdf がまだ存在しないため、アウトライン付与をスキップします')
            return false
          end

          keep_numbers = BuildHelpers.chapter_numbers_for_outline(keep)
          chapter_htmls = Dir.glob(File.join('.', '*.html')).select do |path|
            bn = File.basename(path, '.html')
            n = bn[/\A(\d+)-/, 1]&.to_i
            next false unless n

            keep_numbers.nil? || keep_numbers.include?(n)
          end.sort

          if chapter_htmls.any?
            Common.log_action('[Step 11] 本文HTMLの h1〜h3 から PDF ブックマーク（アウトライン）を付与します…')
            total_pages = (BuildHelpers.page_count('output.pdf') || '0').to_i
            start_from  = 1
            Common.log_info("[Outline] page offset: start_page=#{start_from}, total_pages=#{total_pages}")
            BuildHelpers.add_outline_from_headings!(
              'output.pdf',
              chapter_htmls,
              max_level: 3,
              start_page: start_from
            )
            true
          else
            Common.log_info('[Step 11] 本文HTMLが見つからないため、アウトライン付与をスキップします')
            false
          end
        end

        def extract_headings_from_html_file(path, max_level:, include_appendix_label: true)
          html = File.read(path, encoding: 'utf-8')
          doc  = Nokogiri::HTML.parse(html)
          basename = File.basename(path, '.html')
          headings = []
          selector = (1..max_level).map { |lvl| "h#{lvl}" }.join(',')
          doc.css(selector).each do |node|
            lvl = node.name.delete_prefix('h').to_i
            next unless lvl.positive? && lvl <= max_level

            text = node["data-h#{lvl}"].to_s.strip
            text = node['data-heading'].to_s.strip if text.empty?
            text = node.text.to_s.strip if text.empty?
            next if text.empty?

            appendix_label = nil
            appendix_label = BuildHelpers.appendix_label_for_basename(basename) if include_appendix_label && lvl == 1

            chapter_token = node['data-chapter'].to_s.strip
            chapter_token = basename if chapter_token.empty?
            heading_attr = node['data-heading'].to_s.strip

            number_text = case lvl
                          when 1
                            val = node['data-chapter-number-display'].to_s.strip
                            val = node.at_css('span.chapter-number')&.text&.strip if val.empty?
                            val
                          when 2
                            val = node['data-section-number-display'].to_s.strip
                            val = node.at_css('span.section-number')&.text&.strip if val.empty?
                            val
                          when 3
                            val = node['data-subsection-number-display'].to_s.strip
                            val = node.at_css('span.subsection-marker')&.text&.strip if val.empty?
                            val
                          end

            title_text = case lvl
                         when 1
                           node['data-chapter-title'].to_s.strip
                         when 2
                           node['data-section-title'].to_s.strip
                         when 3
                           node['data-subsection-title'].to_s.strip
                         else
                           ''
                         end
            title_text = text if title_text.empty?

            search_terms = []
            number_variants = []
            if number_text && !number_text.empty?
              unless title_text.empty?
                number_variants << "#{number_text}#{title_text}"
                number_variants << "#{number_text} #{title_text}"
              end
              number_variants << number_text
            end
            search_terms.concat(number_variants)
            search_terms << heading_attr unless heading_attr.empty?
            search_terms << text
            search_terms << appendix_label.to_s unless appendix_label.to_s.empty?
            search_terms = search_terms.compact.map { |term| term.to_s.strip }.reject(&:empty?).uniq

            headings << {
              level: lvl,
              text: text,
              chapter: chapter_token,
              id: node['id'].to_s.strip,
              appendix_label: appendix_label,
              search_terms: search_terms,
              number_display: number_text
            }
          end
          headings
        end
        module_function :extract_headings_from_html_file

        def extract_headings_from_markdown_file(path, max_level: 2)
          headings = []
          return headings unless File.exist?(path)

          title = nil
          subtitles = []
          File.foreach(path, encoding: 'utf-8') do |line|
            stripped = line.strip
            if max_level >= 1 && title.nil? && stripped.start_with?('# ')
              title = stripped.sub('\A#\\s+', '').strip
              next
            end
            subtitles << stripped.sub('\A##\\s+', '').strip if max_level >= 2 && stripped.start_with?('## ')
            break if max_level <= 2 && !title.nil? && !subtitles.empty?
          end
          headings << { level: 1, text: title } if title && !title.empty?
          if max_level >= 2
            subtitles.each do |text|
              next if text.empty?

              headings << { level: 2, text: text }
            end
          end
          headings
        end
        module_function :extract_headings_from_markdown_file

        def heading_page_entries(pdf_path, html_paths, max_level: 3, start_page: 1)
          @last_outline_debug_info = nil
          unless File.exist?(pdf_path)
            Common.log_warn("[Outline] PDF が見つかりません: #{pdf_path}")
            return []
          end
          if html_paths.nil? || html_paths.empty?
            Common.log_warn('[Outline] HTML ファイルが指定されていません')
            return []
          end
          if html_paths.any? { |path| !File.exist?(path) }
            Common.log_warn('[Outline] HTML ファイルが存在しません')
            return []
          end

          unless system('which pdftotext >/dev/null 2>&1')
            Common.log_warn('[Outline] pdftotext が見つかりません。`brew install poppler` を実行してください。アウトライン付与をスキップします')
            return []
          end

          total_pages = (BuildHelpers.page_count(pdf_path) || '0').to_i
          if total_pages <= 0
            Common.log_warn('[Outline] PDF のページ数を取得できませんでした')
            return []
          end

          from_base = [[start_page.to_i, 1].max, total_pages].min
          max_level = [[max_level.to_i, 1].max, 6].min

          chapter_paths = {}
          html_paths.each do |path|
            bn = File.basename(path, '.html')
            chapter_paths[bn] = path
          end
          html_basenames = chapter_paths.keys

          chapter_order = BuildHelpers.chapter_order_from(html_basenames)
          frontmatter_sequence = %w[00-titlepage 01-legalpage 02-preface 03-toc]
          chapter_order = (frontmatter_sequence + chapter_order).uniq

          headings_by_chapter = Hash.new { |h, k| h[k] = [] }
          chapter_markers = {}

          first_chapter_bn = chapter_order.find { |token| Common.get_file_type("#{token}.html") == 'chapter' }

          chapter_order.each do |bn|
            path = chapter_paths[bn]
            headings = []
            if path
              headings = BuildHelpers.extract_headings_from_html_file(path, max_level: max_level,
                                                                            include_appendix_label: true)
            end
            headings_by_chapter[bn].concat(headings) if headings.any?

            primary = headings.find { |h| h[:level] == 1 } || headings.first
            markers = []
            if primary
              markers.concat(Array(primary[:search_terms]))
              markers << primary[:text]
            end
            markers = markers.compact.map { |s| s.to_s.strip }.reject(&:empty?).uniq
            chapter_markers[bn] = markers if markers.any?
          end

          page_cache = {}
          normalized_cache = {}
          normalize = lambda do |str|
            str.to_s.gsub(/[[:space:]\u00A0\u2000-\u200B\u202F\u205F\u3000]+/, '')
          end
          fetch_page_text = lambda do |page|
            page = [[page.to_i, 1].max, total_pages].min
            page_cache[page] ||= `pdftotext -f #{page} -l #{page} "#{pdf_path}" - 2>/dev/null`
          end
          find_page_in_pdf = lambda do |term, from_page, to_page|
            term = term.to_s.strip
            return nil if term.empty?

            normalized_term = normalize.call(term)
            from_page = [[from_page.to_i, 1].max, total_pages].min
            to_page = [[to_page.to_i, total_pages].min, from_page].max
            return nil if from_page > to_page

            (from_page..to_page).each do |page|
              text = fetch_page_text.call(page)
              next if text.nil? || text.empty?
              return page if text.include?(term)

              normalized_text = normalized_cache[page]
              unless normalized_text
                normalized_text = normalize.call(text)
                normalized_cache[page] = normalized_text
              end
              return page if !normalized_term.empty? && normalized_text.include?(normalized_term)
            end
            nil
          end
          search_markers = lambda do |markers, from_page, to_page|
            Array(markers).each do |term|
              page = find_page_in_pdf.call(term, from_page, to_page)
              return page if page
            end
            nil
          end

          preface_pages = (BuildHelpers.page_count('02-preface.pdf') || '0').to_i
          toc_pages      = (BuildHelpers.page_count('03-toc.pdf') || '0').to_i

          chapter_starts = {}
          chapter_ranges = {}

          prev_bn = nil

          chapter_order.each do |bn|
            start_page = nil
            end_page = nil

            case bn
            when '00-titlepage'
              start_page = [from_base, 1].max
              end_page = 1
            when '01-legalpage'
              start_page = [[2, from_base].max, total_pages].min
              end_page = start_page
            when '02-preface'
              start_page = [[3, from_base].max, total_pages].min
              end_page = if preface_pages.positive?
                           [start_page + preface_pages - 1, total_pages].min
                         else
                           start_page
                         end
            when '03-toc'
              preface_end = chapter_ranges['02-preface']&.[](1) || ((start_page || 3) + preface_pages - 1)
              start_candidate = preface_end ? preface_end + 1 : 4
              start_page = [[start_candidate, from_base].max, total_pages].min
              end_page = if toc_pages.positive?
                           [start_page + toc_pages - 1, total_pages].min
                         else
                           start_page
                         end
            when first_chapter_bn
              toc_end = chapter_ranges['03-toc']&.[](1)
              start_candidate = toc_end ? toc_end + 1 : (chapter_starts[prev_bn] || from_base)
              start_page = [[start_candidate, from_base].max, total_pages].min
              end_page = total_pages
            when '99-colophon'
              start_page = total_pages
              end_page = total_pages
            when '98-postface'
              search_from = chapter_starts[prev_bn] || from_base
              search_from = [[search_from, from_base].max, total_pages].min
              markers = chapter_markers[bn] || ['終わりに']
              start_page = search_markers.call(markers, search_from, total_pages)
              if start_page.nil? && search_from > from_base
                start_page = search_markers.call(markers, from_base, total_pages)
              end
              start_page ||= search_from
              end_page = [total_pages - 1, total_pages].min
              end_page = start_page if end_page < start_page
            else
              search_from = chapter_starts[prev_bn] || from_base
              search_from = [[search_from, from_base].max, total_pages].min
              markers = chapter_markers[bn] || []
              start_page = search_markers.call(markers, search_from, total_pages)
              if start_page.nil? && search_from > from_base
                start_page = search_markers.call(markers, from_base, total_pages)
              end
              start_page ||= search_from
              end_page = total_pages
            end

            if prev_bn && chapter_ranges[prev_bn]
              prev_start = chapter_ranges[prev_bn][0] || from_base
              prev_end = [start_page - 1, total_pages].min
              prev_end = prev_start if prev_end < prev_start
              chapter_ranges[prev_bn][1] = prev_end
            end

            chapter_starts[bn] = start_page
            chapter_ranges[bn] = [start_page, end_page]
            prev_bn = bn
          end

          unless chapter_ranges.empty?
            chapter_ranges.each_value do |rng|
              next unless rng

              rng[0] = [[rng[0], from_base].max, total_pages].min
              rng[1] = [[rng[1], rng[0]].max, total_pages].min
            end
          end

          items = []
          fallback_items = []
          headings_by_chapter.each do |bn, headings|
            range = chapter_ranges[bn]
            next unless range

            range_start = range[0]
            range_end   = range[1]
            headings.each do |heading|
              search_terms = Array(heading[:search_terms]) + [heading[:text], heading[:appendix_label]]
              search_terms = search_terms.compact.map { |s| s.to_s.strip }.reject(&:empty?).uniq
              page = search_markers.call(search_terms, range_start, range_end)
              page = search_markers.call(search_terms, range_start, total_pages) if page.nil?
              if page.nil?
                fallback_items << {
                  chapter: bn,
                  text: heading[:text],
                  target_page: range_start,
                  search_terms: search_terms
                }
                page = range_start
              end
              display_text = heading[:text]
              if bn == '99-colophon' && heading[:level].to_i == 1
                display_text = '奥付'
              elsif heading[:appendix_label] && heading[:level].to_i == 1
                label = heading[:appendix_label].to_s.strip
                display_text = "#{label} #{display_text}".strip if !label.empty? && !display_text.start_with?(label)
              elsif heading[:level].to_i == 1
                number_display = heading[:number_display].to_s.strip
                if number_display.empty?
                  chapter_number = Common.get_chapter_number(bn)
                  if chapter_number
                    number = chapter_number.to_i
                    number_display = "第#{number - 10}章" if number.between?(11, 89)
                  end
                end
                unless number_display.empty? || display_text.start_with?(number_display)
                  display_text = "#{number_display} #{display_text}".strip
                end
              end
              items << {
                level: heading[:level],
                text: display_text,
                page: page,
                chapter: bn,
                id: heading[:id]
              }
            end
          end

          if chapter_ranges['03-toc'] && !chapter_order.include?('03-toc'.dup)
            # no-op placeholder; kept for backward compatibility structure
          end

          if chapter_ranges['03-toc']
            toc_range = chapter_ranges['03-toc']
            toc_page = search_markers.call(['目次'], toc_range[0], toc_range[1]) || toc_range[0]
            already_has_toc = items.any? { |it| it[:chapter] == '03-toc' }
            unless already_has_toc
              insert_index = items.index do |it|
                chapter_order.index(it[:chapter]) && chapter_order.index(it[:chapter]) > chapter_order.index('03-toc')
              end
              insert_index ||= items.length
              items.insert(insert_index, { level: 1, text: '目次', page: toc_page, chapter: '03-toc', id: nil })
            end
          end

          if fallback_items.any? && Common.current_log_level >= 3
            Common.log_warn('[Outline] 以下の見出しはページ検出に失敗したため章先頭へフォールバックしました:')
            fallback_items.each do |fb|
              terms = fb[:search_terms].join(' / ')
              Common.log_warn("  - #{fb[:chapter]} ##{fb[:text]} (fallback page=#{fb[:target_page]}, search terms=#{terms})")
            end
          end

          @last_outline_debug_info = {
            chapter_order: chapter_order.dup,
            chapter_starts: chapter_starts.dup,
            chapter_ranges: chapter_ranges.transform_values(&:dup),
            items: items.map(&:dup)
          }

          items
        end
        module_function :heading_page_entries

        # ------------------------------------------------
        # Appendix helpers
        # ------------------------------------------------
        def appendix_label_for_basename(basename)
          number = Common.get_chapter_number(basename)
          return nil unless number && APPX_RANGE.include?(number.to_i)

          letter = Common.appendix_number_to_letter(number)
          return nil unless letter

          "付録#{letter.upcase}"
        end
        module_function :appendix_label_for_basename

        # HTML から h1..max_level を抽出し、output_pdf にアウトラインを付与
        # - pdf_path: 対象 PDF（上書き保存）
        # - html_paths: 章 HTML 群（結合順）
        # - max_level: 1..6（既定: 3）
        # 実装メモ:
        # - 以前は見出し内に不可視テキスト "VS-H: <text>" を注入して PDF 検索の安定化を図っていたが、
        #   レイアウトに悪影響があるため廃止。
        # - 代替として、章先頭に注入する不可視テキスト "VS-CHAPTER: <basename>" を利用し、
        #   章ごとのページ範囲を特定した上で、その範囲内で見出しテキストを検索することで誤検出を抑制する。
        def add_outline_from_headings!(pdf_path, html_paths, max_level: 3, start_page: 1)
          items = heading_page_entries(pdf_path, html_paths, max_level: max_level, start_page: start_page)
          return false if items.empty?

          # HexaPDF でアウトラインを構築
          doc = HexaPDF::Document.open(pdf_path)
          root = doc.outline
          if root[:First]
            existing_items = []
            root.each_item { |item, _level| existing_items << item }
            existing_items.each do |item|
              doc.delete(item)
            rescue StandardError
              # 既存のブックマーク削除で失敗しても続行
            end
            root.delete(:First)
            root.delete(:Last)
            root.delete(:Count)
          end
          parents = { 1 => root }
          items.each do |it|
            lvl = [[it[:level].to_i, 1].max, max_level].min
            parents.keys.select { |k| k > lvl }.each { |k| parents.delete(k) }
            parent = parents[lvl] || parents[parents.keys.select { |k| k < lvl }.max] || root
            parents[lvl] = parent
            # HexaPDF destination array must be of the form [page, :Fit] etc.
            # Use :Fit so the page is displayed entirely.
            page_obj = doc.pages[it[:page] - 1]
            parent.add_item(it[:text], destination: [page_obj, :Fit]) do |node|
              parents.keys.select { |k| k > lvl }.each { |k| parents.delete(k) }
              parents[lvl + 1] = node
            end
          end
          doc.write(pdf_path, optimize: true)
          Common.log_success('[Outline] PDF にブックマーク（アウトライン）を付与しました')
          true
        end

        # ================================================================
        # Step 12: 生成PDFを圧縮（output.pdf -> output_compressed.pdf）
        # ------------------------------------------------
        # - Vivlio::Starter::ThorCLI.start(['pdf_compress']) を呼び出し
        # - 失敗時は警告ログのみ（ビルド継続）
        # ================================================================
        def compress_pdf!
          Common.log_action('[Step 12] 生成PDFを圧縮します…')
          Vivlio::Starter::ThorCLI.start(['pdf_compress'])
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

        # 11..89 範囲の章番号（整数）の配列を返す。keep（.md 含む可）指定時はその集合に限定。
        def chapter_numbers_for_book(keep = nil)
          basenames = if keep&.any?
                        Array(keep).map { |s| File.basename(s.to_s, '.md') }
                      else
                        Dir[File.join(Common::CONTENTS_DIR, '*.md')].map { |p| File.basename(p, '.md') }
                      end
          basenames
            .map { |bn| Common.get_chapter_number(bn) }
            .compact
            .map(&:to_i)
            .select { |n| n.between?(11, 89) }
            .uniq
            .sort
        end

        def chapter_numbers_for_outline(keep = nil)
          allowed_numbers = [0, 1, 2, 3, 99] + MAIN_RANGE.to_a + APPX_RANGE.to_a + POSTFACE_RANGE.to_a
          basenames = if keep&.any?
                        Array(keep).map do |entry|
                          name = File.basename(entry.to_s)
                          name.sub(/\.[^.]+\z/, '')
                        end
                      else
                        md = Dir[File.join(Common::CONTENTS_DIR, '*.md')].map { |p| File.basename(p, '.md') }
                        html = Dir[File.join('.', '*.html')].map { |p| File.basename(p, '.html') }
                        (md + html)
                      end

          numbers = basenames
                    .map { |bn| Common.get_chapter_number(bn) }
                    .compact
                    .map(&:to_i)
                    .select { |n| allowed_numbers.include?(n) }
          numbers.uniq!
          numbers.sort!
          numbers
        end

        # 空白1ページPDFを生成（既存時は何もしない）
        # - 用紙サイズは book.yml の page 設定に追従（共有ヘルパ使用）
        def ensure_blank_page_pdf(path = 'blank_page.pdf')
          return path if File.exist?(path)

          doc = HexaPDF::Document.new
          w_pt, h_pt = BuildHelpers.page_size_points_from_config
          doc.pages.add([0, 0, w_pt, h_pt])
          doc.write(path, optimize: true)
          path
        end

        # 共有ヘルパ: 現在の設定からページサイズ（文字列: mm/pt）を取得
        def page_size_strings_from_config
          page_cfg = Common::CONFIG['page'] || {}
          result = Common.resolve_page_size(page_cfg)
          if result.is_a?(Array) && result.size == 2 && result.all? do |dim|
            dim.to_s.strip.match?(/\A[0-9.]+(mm|pt)?\z/)
          end
            result
          else
            %w[182mm 257mm]
          end
        end

        # 共有ヘルパ: 現在の設定からページサイズ（pt）を取得
        def page_size_points_from_config
          width_s, height_s = BuildHelpers.page_size_strings_from_config
          mm_to_pt = 72.0 / 25.4
          parse_len = lambda { |s|
            str = s.to_s.strip.downcase
            if str.end_with?('mm')
              str.sub(/mm\z/, '').to_f * mm_to_pt
            elsif str.end_with?('pt')
              str.sub(/pt\z/, '').to_f
            else
              # 単位不明 → 数値のみなら pt と解釈
              str.to_f
            end
          }
          w_pt = parse_len.call(width_s)
          h_pt = parse_len.call(height_s)
          if w_pt <= 0 || h_pt <= 0 || w_pt.nan? || h_pt.nan?
            w_pt = 182.0 * mm_to_pt
            h_pt = 257.0 * mm_to_pt
          end
          [w_pt, h_pt]
        end

        # qpdf で「本文+付録（先頭〜frontmatter直前）」と「末尾frontmatter」を抽出
        def split_pdf_into_toc_and_sections(output_pdf, frontmatter_pages, front_pdf, body_pdf)
          total_pages = (BuildHelpers.page_count(output_pdf) || '0').to_i
          if total_pages <= 0
            Common.log_warn("[Step 7] 総ページ数の取得に失敗しました: #{output_pdf}")
            return false
          end

          unless system('which qpdf >/dev/null 2>&1')
            Common.log_warn('[Step 7] qpdf が見つかりません。`brew install qpdf` でインストールしてください。')
            return false
          end

          FileUtils.rm_f(front_pdf)
          FileUtils.rm_f(body_pdf)

          body_end = total_pages - frontmatter_pages
          ok1 = ok2 = true

          if body_end.positive?
            Common.log_action("[Step 7] 本文・付録を抽出しています (1-#{body_end})…")
            ok1 = system(%(qpdf "#{output_pdf}" --pages "#{output_pdf}" 1-#{body_end} -- "#{body_pdf}" > /dev/null))
          else
            Common.log_warn('[Step 7] 本文側のページがありません。frontmatter が全ページを占めています。')
          end

          if frontmatter_pages < total_pages
            start_last = body_end + 1
            Common.log_action("[Step 7] frontmatter を抽出しています (#{start_last}-z)…")
            ok2 = system(%(qpdf "#{output_pdf}" --pages "#{output_pdf}" #{start_last}-z -- "#{front_pdf}" > /dev/null))
          else
            Common.log_warn('[Step 7] frontmatter が全ページを占めています。frontmatter 側のみ生成します。')
          end

          if ok1 && ok2
            Common.log_success("[Step 7] 分割完了: #{front_pdf}, #{body_pdf}")
            true
          else
            Common.log_warn('[Step 7] PDF の分割に失敗しました (qpdf 実行エラー)')
            false
          end
        end

        # stylesheets/NN.css の chapter-counter と章コメントを与えた番号に更新
        def update_css_counter(_css_path, _number)
          Common.log_info('update_css_counter は廃止されました。処理をスキップします。')
          false
        end
      end
    end
  end
end
