# frozen_string_literal: true

require 'rbconfig'
require 'fileutils'
require 'hexapdf'
require 'nokogiri'
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

        # 章レンジ（定数化）
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
            items = items.map { |s|
              name = s.sub(%r{\A#{Regexp.escape(Common::CONTENTS_DIR)}/}, '')
              name = name + '.md' unless name.end_with?('.md')
              name
            }
            Common.log_info("[Subset] normalized keep(list)=#{items.inspect}") if items.any?
            return items if items.any?
            return nil
          elsif cfg.is_a?(Array)
            items = cfg.map { |s| s.to_s.strip }.reject(&:empty?)
            items = items.map { |s|
              name = s.sub(%r{\A#{Regexp.escape(Common::CONTENTS_DIR)}/}, '')
              name = name + '.md' unless name.end_with?('.md')
              name
            }
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
          keep_set = keep_numbers && keep_numbers.respond_to?(:include?) ? keep_numbers : nil
          Array(basenames)
            .map { |bn| bn.to_s }
            .select { |bn| bn =~ /\A(\d+)-/ }
            .select { |bn|
              n = bn[/\A(\d+)-/, 1].to_i
              in_range = range.include?(n)
              allowed  = keep_set ? keep_set.include?(n) : true
              in_range && allowed
            }
            .uniq
            .sort
        end
        module_function :filter_basenames_by_range

        # ------------------------------------------------
        # Shared helper: ディレクトリ内の *.html から、章番号レンジと keep_numbers でフィルタ
        # ------------------------------------------------
        def htmls_for_range(base_dir, range, keep_numbers = nil)
          Dir.glob(File.join(base_dir, '*.html')).select { |path|
            bn = File.basename(path, '.html')
            n = bn[/\A(\d+)-/, 1]&.to_i
            n && range.include?(n) && (keep_numbers.nil? || keep_numbers.include?(n))
          }.sort
        end
        module_function :htmls_for_range

        # ------------------------------------------------
        # Shared helper: 簡易スレッドプールで並列実行
        # ------------------------------------------------
        def parallel_each(items, concurrency: 1)
          list = Array(items)
          effective_concurrency = concurrency.to_i
          effective_concurrency = 1 if effective_concurrency <= 0
          Common.log_info("[parallel_each] concurrency=#{effective_concurrency}")
          return list.each { |it| yield(it) } if effective_concurrency <= 1
          require 'thread'
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

        # ================================================================
        # Step 1: 画像最適化（WebP 変換/リサイズ）
        # ------------------------------------------------
        # - 対象: images/, stylesheets/images
        # - プリセット: :high / :medium / :low（既定: :medium）
        # - 実行: Thor タスク resize:*
        # ================================================================
        def optimize_images!(preset = nil)
          p = (preset&.to_sym || :medium)
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
        # Step 2: PDF 生成前に CSS を 1,2,3… の仮想連番へ更新
        # ------------------------------------------------
        # - 対象: 11..89 章に対応する stylesheets/NN.css
        # - 各 CSS の .orig を作成（未作成時のみ）し、counter とコメントを仮想番号へ更新
        # - 元への復元は Step 11（.orig から復元）で実施
        # ================================================================
        def apply_virtual_chapter_numbers_for_book!(keep = nil)
          # 11..89 の順序に対応する stylesheets/NN.css を算出（共通ロジックに委譲）
          numbers = BuildHelpers.chapter_numbers_for_book(keep)
          css_paths = numbers
                        .map { |n| File.join(Common::STYLESHEETS_DIR, "#{n}.css") }
                        .select { |css| File.exist?(css) }
          if css_paths.empty?
            Common.log_info("[Step 2] 対象CSSが見つかりません（#{Common::STYLESHEETS_DIR}/NN.css が存在しません）")
            return
          end
          Common.log_action("[Step 2] 章CSSを仮想連番 1..#{css_paths.size} に更新します…（対象章: #{numbers.join(', ')}）")
          css_paths.each_with_index do |css, idx|
            backup = css + '.orig'
            unless File.exist?(backup)
              FileUtils.cp(css, backup)
            end
            update_css_counter(css, idx + 1)
          end
        end

        # ================================================================
        # Step 3: 前書き (02-preface) のみ先行ビルド
        # ------------------------------------------------
        # - pre_process -> convert -> post_process -> entries -> pdf
        # - 出力 output.pdf を 02-preface.pdf にリネーム
        # - ページ数を取得してログ出力
        # ================================================================
        def preface_prebuild!(keep = nil)
          Common.log_action('[Step 3] 前書き (02-preface) のみ先行ビルドを実行します…')

          # 汎用ガードで対象/存在を確認
          return unless BuildHelpers.buildable?('02-preface', keep)

          %w[pre_process convert post_process entries].each do |t|
            BuildHelpers.time_step_for_chapter('02-preface', t) do
              Vivlio::Starter::ThorCLI.start([t, '02-preface'])
            end
          end
          BuildHelpers.time_step_for_chapter('02-preface', 'pdf') do
            # 改良された pdf コマンドに出力ファイル名を渡してリネームも一括処理
            Vivlio::Starter::ThorCLI.start(['pdf', '02-preface.pdf'])
          end
        end

        # ------------------------------------------------
        # Helper: buildable?
        # ------------------------------------------------
        # - 目的: 指定ベース名(basename)の対象判定と存在確認を一元化
        # - 引数: basename (例: '02-preface')、keep（configの chapters 正規化リスト or nil）
        # - 戻り値: true（処理続行）/false（スキップ）
        # - ログ: 各条件で適切に出力（章名は basename で汎用化）
        # ------------------------------------------------
        def buildable?(basename, keep)
          # chapters 指定: 対象外ならスキップ
          if keep && !keep.include?("#{basename}.md")
            Common.log_action("[Guard] #{basename} は chapters 設定に含まれないためスキップします")
            return false
          end
          # 存在確認
          md_path = File.join(Common::CONTENTS_DIR, "#{basename}.md")
          unless File.exist?(md_path)
            Common.log_warn("[Guard] #{basename}.md が見つかりません。処理をスキップします")
            return false
          end
          true
        end
        module_function :buildable?

        # ================================================================
        # Step 4: 付録 (91〜97) のビルドと結合
        # ------------------------------------------------
        # - 91..97 の章を HTML 生成
        # - merge_appendices で 90-appendices.html を生成
        # - 個別付録 HTML をクリーンアップ
        # ================================================================
        def build_appendices_and_merge_html!(keep = nil)
          Common.log_action('[Step 4] 付録章 (91〜97) をビルドします…')

          appendix_paths   = Dir[File.join(Common::CONTENTS_DIR, '{91,92,93,94,95,96,97}-*.md')]
          appendix_targets = appendix_paths.map { |p| File.basename(p, '.md') }.uniq.sort

          # chapters 指定がある場合は、含まれる付録のみ対象（存在確認も含めて汎用ガードで判定）
          if keep && keep.any?
            appendix_targets.select! { |t| BuildHelpers.buildable?(t, keep) }
          end

          if appendix_targets.empty?
            Common.log_warn('[Step 4] 付録候補(91〜97)が見つかりません。Step 4 をスキップします。')
            return
          end

          Common.log_info("[Step 4] 対象: #{appendix_targets.join(', ')}")
          appendix_targets.each do |target|
            %w[pre_process convert post_process].each do |tn|
              BuildHelpers.time_step_for_chapter(target, tn) do
                Vivlio::Starter::ThorCLI.start([tn, target])
              end
            end
          end

          # 付録HTMLを結合して 90-appendices.html を生成
          Common.log_action('[Step 4] 付録HTMLを結合して 90-appendices.html を生成します…')
          Vivlio::Starter::ThorCLI.start(['merge_appendices'])
          Common.log_success('[Step 4] 90-appendices.html を生成しました')

          # 付録結合後に post_process を適用して見出しメタ等を付与（PDFアウトライン用）
          if File.exist?('90-appendices.html')
            Vivlio::Starter::ThorCLI.start(['post_process', '90-appendices'])
            Common.log_info('[Step 4] 90-appendices.html に post_process を適用しました（見出しメタ付与）')
          else
            Common.log_warn('[Step 4] 90-appendices.html が見つからないため post_process をスキップします')
          end

          # 個別付録HTMLをクリーンアップ
          patterns = ['{91,92,93,94,95,96,97}-*.html', '{91,92,93,94,95,96,97}-*.md']
          removed = []
          patterns.each do |pattern|
            Dir.glob(pattern).each do |f|
              next unless File.file?(f)
              File.delete(f)
              removed << File.basename(f)
            end
          end
          if removed.any?
            Common.log_info("[Step 4] 個別付録(HTML/MD)を削除: #{removed.join(', ')}")
          else
            Common.log_info('[Step 4] 削除対象の個別付録(HTML/MD)はありません')
          end
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
          if keep && keep.any?
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
          keep_numbers_post = nil
          if keep && keep.any?
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
          Vivlio::Starter::ThorCLI.start(['post_process', '03-toc'])
          Common.log_info('[Step 6] 03-toc.html に post_process を適用しました（見出しメタ付与）')
          Vivlio::Starter::ThorCLI.start(['entries', '03-toc'])
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
          if keep && keep.any?
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
          guard_html = nil
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
        def compile_overall_pdf_and_split!(targets_for_pdf, keep = nil)
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
            'sections.pdf'
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
        # Step 8: frontmatter.pdf 構成 + ローマ小付与
        # ------------------------------------------------
        # - 02-preface.pdf + 03-toc.pdf を merge
        # - HexaPDF PageLabels 設定 → 小文字ローマ数字をオーバーレイ描画
        # ================================================================
        def build_frontmatter_pdf!(keep = nil)
          Common.log_action('[Step 8] frontmatter.pdf を構成し、ローマ小 i〜 を付与します…')
          # keep 方針: 02/03 は keep に従う（nil=フルビルド時は両方含める）
          include_preface = keep.nil? || Array(keep).map(&:to_s).any? { |s| File.basename(s) == '02-preface.md' }
          include_toc     = keep.nil? || Array(keep).map(&:to_s).any? { |s| File.basename(s) == '03-toc.md' }

          # 02-preface.pdf をキャッシュから復元（必要なら再生成）
          if include_preface && File.exist?(File.join(Common::CONTENTS_DIR, '02-preface.md'))
            cache_on = Common.cache_enabled?
            cache_dir = cache_on ? Common.ensure_cache_dir! : nil
            preface_cache = cache_on && cache_dir ? File.join(cache_dir, '02-preface.pdf') : nil

            needs_preface = !File.exist?('02-preface.pdf')
            needs_preface &&= !cache_restore_file(cache_on, preface_cache, '02-preface.pdf', 'Step 8')

            if needs_preface
              %w[pre_process convert post_process entries].each do |t|
                Vivlio::Starter::ThorCLI.start([t, '02-preface'])
              end
              Vivlio::Starter::ThorCLI.start(['pdf', '02-preface.pdf'])
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

          # どちらか1つだけ存在する場合は、それを frontmatter.pdf として採用
          if existing_files.length == 1
            src = existing_files.first
            FileUtils.rm_f('frontmatter.pdf')
            FileUtils.cp(src, 'frontmatter.pdf')
            Common.log_success("[Step 8] frontmatter.pdf を単一ソースから生成しました: #{src}")

            # frontmatter のページ数が奇数なら、末尾に空白1ページを追加して本文を右ページ開始に揃える
            pages = (BuildHelpers.page_count('frontmatter.pdf') || '0').to_i
            if pages.odd?
              doc = HexaPDF::Document.open('frontmatter.pdf')
              first_box = doc.pages[0].box(:media)
              doc.pages.add([first_box.left, first_box.bottom, first_box.right, first_box.top])
              doc.write('frontmatter.pdf', optimize: true)
              Common.log_info('[Step 8] frontmatter.pdf が奇数ページのため、空白1ページを末尾に挿入しました')
            end

            BuildHelpers.apply_page_labels_hexapdf('frontmatter.pdf', 0)
            if BuildHelpers.overlay_roman_page_numbers!('frontmatter.pdf')
              Common.log_success('[Step 8] frontmatter.pdf にローマ小 i〜 を描画しました')
            else
              Common.log_warn('[Step 8] frontmatter.pdf へのローマ小描画をスキップ/失敗')
            end
            return
          elsif existing_files.empty?
            Common.log_warn('[Step 8] frontmatter 構成対象PDFがありません。frontmatter.pdf の生成をスキップします')
            return
          end

          Common.log_info("[Step 8] 結合順: #{existing_files.join(' -> ')}")
          cmd = ['bundle', 'exec', 'hexapdf', 'merge', *existing_files, 'frontmatter.pdf'].join(' ')
          merged = system(cmd)
          if merged && File.exist?('frontmatter.pdf')
            Common.log_success('[Step 8] frontmatter.pdf を生成しました')

            # frontmatter のページ数が奇数なら、末尾に空白1ページを追加して本文を右ページ開始に揃える
            pages = (BuildHelpers.page_count('frontmatter.pdf') || '0').to_i
            if pages.odd?
              doc = HexaPDF::Document.open('frontmatter.pdf')
              first_box = doc.pages[0].box(:media)
              doc.pages.add([first_box.left, first_box.bottom, first_box.right, first_box.top])
              doc.write('frontmatter.pdf', optimize: true)
              Common.log_info('[Step 8] frontmatter.pdf が奇数ページのため、空白1ページを末尾に挿入しました')
            end

            BuildHelpers.apply_page_labels_hexapdf('frontmatter.pdf', 0)
            if BuildHelpers.overlay_roman_page_numbers!('frontmatter.pdf')
              Common.log_success('[Step 8] frontmatter.pdf にローマ小 i〜 を描画しました')
            else
              Common.log_warn('[Step 8] frontmatter.pdf へのローマ小描画をスキップ/失敗')
            end
          else
            Common.log_error('[Step 8] frontmatter.pdf の生成に失敗しました')
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
          # 判定ヘルパ
          front_srcs = [
            File.join(Common::CONTENTS_DIR, '00-titlepage.md'),
            File.join(Common::CONTENTS_DIR, '01-legalpage.md'),
            File.join('config', 'book.yml'),
          ]
          colophon_srcs = [
            File.join(Common::CONTENTS_DIR, '99-colophon.md'),
            File.join('config', 'book.yml'),
          ]

          newer_than_any = lambda do |target, sources|
            return true unless File.exist?(target)
            t_mtime = File.exist?(target) ? File.mtime(target) : Time.at(0)
            Array(sources).any? { |s| File.exist?(s) && File.mtime(s) > t_mtime }
          end

          front_pdf = '00-01-front.pdf'
          cache_on = Common.cache_enabled? && !force
          cache_dir = cache_on ? Common.ensure_cache_dir! : nil
          front_cache = cache_on && cache_dir ? File.join(cache_dir, front_pdf) : nil
          front_missing = !File.exist?(front_pdf)
          front_missing &&= !cache_restore_file(cache_on, front_cache, front_pdf, 'Step 9')

          need_front = force || front_missing || newer_than_any.call(front_pdf, front_srcs)

          if need_front
            # 00,01 の HTML を生成（entries は後で 2本を指定して1つのPDF化）
            %w[pre_process convert post_process].each do |t|
              Vivlio::Starter::ThorCLI.start([t, '00-titlepage'])
            end
            %w[pre_process convert post_process].each do |t|
              Vivlio::Starter::ThorCLI.start([t, '01-legalpage'])
            end
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
            Common.log_action("[Step 9] フロント/奥付PDFは最新のため再利用します: #{front_pdf}, 99-colophon.pdf")
            colo_cache = cache_on && cache_dir ? File.join(cache_dir, '99-colophon.pdf') : nil
            cache_restore_file(cache_on, front_cache, front_pdf, 'Step 9')
            cache_restore_file(cache_on, colo_cache, '99-colophon.pdf', 'Step 9')
          end

          # ここから奥付の生成（フロントを再生成した場合は必ず奥付も再生成）
          if front_regenerated
            %w[pre_process convert post_process entries].each do |t|
              Vivlio::Starter::ThorCLI.start([t, '99-colophon'])
            end
            Vivlio::Starter::ThorCLI.start(['pdf', '99-colophon.pdf'])
            if File.exist?('99-colophon.pdf')
              Common.log_success('[Step 9] 99-colophon.pdf を生成しました')
              colo_cache = cache_on && cache_dir ? File.join(cache_dir, '99-colophon.pdf') : nil
              cache_store_file(cache_on, '99-colophon.pdf', colo_cache, 'Step 9')
            end
          else
            Common.log_info('[Step 9] フロントが最新のため、奥付の再生成はスキップしました（キャッシュ/既存を利用）')
          end

          # （重複していた奥付再生成ブロックを削除。必要時は上で実行済み）
        end

        # ================================================================
        # Step 10: すべてのPDFを結合して output.pdf を生成
        # ------------------------------------------------
        # - 必要に応じて 98-postface.pdf の奇数開始調整（空白ページ挿入）
        # - HexaPDF で結合
        # ================================================================
        def merge_all_pdfs!
          # NOTE: 呼び出し元から keep（chapters サブセット）を受け取りたいケースがあるため
          #       後方互換のため引数なし定義を残し、内部で nil を扱う新メソッドへ委譲します。
          merge_all_pdfs_with_outline!(nil)
        end

        # 章サブセット keep を尊重して結合し、可能なら HTML 見出しから PDF アウトラインを付与
        # - keep: ['11-install.md', '81-install.md', ...] 形式または nil
        def merge_all_pdfs_with_outline!(keep = nil)
          Common.log_action('[Step 10] フロント(00-01)、前書き、目次、本文、付録、奥付を結合します…')
          # 存在するPDFのみで結合を続行します（02-preface.pdf が無くても処理継続）
          Common.log_info('[Step 10] 存在するPDFのみで結合を実行します（02-preface.pdf は任意）')
          files_to_merge = [
            '00-01-front.pdf', 'frontmatter.pdf',
            'sections.pdf', '99-colophon.pdf'
          ]
          existing_files = files_to_merge.select { |f| File.exist?(f) }
          missing_files  = files_to_merge - existing_files
          # 任意ファイル（存在しなくても正常）
          optional_files = []
          missing_required = missing_files - optional_files
          if missing_required.any?
            Common.log_warn("[Step 10] 結合対象が見つかりません: #{missing_required.join(', ')}")
          end
          # 任意欠落は情報として出すに留める
          missing_optional = missing_files & optional_files
          if missing_optional.any?
            Common.log_info("[Step 10] 任意のPDFが見つかりません（スキップ）: #{missing_optional.join(', ')}")
          end
          if existing_files.empty?
            Common.log_error('[Step 10] 結合対象PDFがありません。処理を中止します')
            return
          end

          FileUtils.rm_f('output.pdf')
          cmd = ['bundle', 'exec', 'hexapdf', 'merge', *existing_files, 'output.pdf'].join(' ')
          merged = system(cmd)
          if merged && File.exist?('output.pdf')
            Common.log_success('[Step 10] output.pdf を生成しました')
            # 可能なら、本文HTMLの見出し(h1〜h3)からアウトラインを生成して付与
            keep_numbers = BuildHelpers.chapter_numbers_for_book(keep)
            chapter_htmls = Dir.glob(File.join('.', '*.html')).select { |path|
              bn = File.basename(path, '.html')
              n = bn[/\A(\d+)-/, 1]&.to_i
              next false unless n
              in_scope = MAIN_RANGE.include?(n) || APPX_RANGE.include?(n) || POSTFACE_RANGE.include?(n)
              allowed = keep_numbers.nil? || keep_numbers.include?(n) || POSTFACE_RANGE.include?(n)
              in_scope && allowed
            }.sort
            if chapter_htmls.any?
              Common.log_action('[Step 10] 本文HTMLの h1〜h3 から PDF ブックマーク（アウトライン）を付与します…')
              # 先頭の front(00-01) + frontmatter(02+03) をスキップして本文へジャンプ
              fr_pages = (BuildHelpers.page_count('00-01-front.pdf')   || '0').to_i
              fm_pages = (BuildHelpers.page_count('frontmatter.pdf')   || '0').to_i
              start_from = [[fr_pages + fm_pages + 1, 1].max, 10**9].min
              Common.log_info("[Outline] page offset: front=#{fr_pages}, frontmatter=#{fm_pages}, start_page=#{start_from}")
              BuildHelpers.add_outline_from_headings!(
                'output.pdf',
                chapter_htmls,
                max_level: 3,
                start_page: start_from
              )
            else
              Common.log_info('[Step 10] 本文HTMLが見つからないため、アウトライン付与をスキップします')
            end
          else
            Common.log_error('[Step 10] PDF結合に失敗しました')
          end
        end

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
          unless File.exist?(pdf_path)
            Common.log_warn("[Outline] PDF が見つかりません: #{pdf_path}")
            return false
          end
          if html_paths.nil? || html_paths.empty?
            Common.log_info('[Outline] HTML が空のためスキップします')
            return false
          end
          max_level = [[max_level.to_i, 1].max, 6].min

          # Nokogiri で h1..hN 見出しを抽出（テキストのみ + 所属章）
          # - post_process で data-heading を付与している場合はそれを優先
          headings = [] # [{level:, text:, chapter:}]
          chapter_order = [] # ['11-install', ...]（html_paths の順）
          html_paths.each do |hp|
            next unless File.exist?(hp)
            html = File.read(hp, encoding: 'utf-8')
            doc  = Nokogiri::HTML.parse(html)
            bn   = File.basename(hp, '.html')
            chapter_order << bn
            (1..max_level).each do |lvl|
              doc.css("h#{lvl}").each do |h|
                text = h['data-heading'].to_s.strip
                text = h.text.to_s.strip if text.nil? || text.empty?
                next if text.empty?
                headings << { level: lvl, text: text, chapter: bn }
              end
            end
          end
          if headings.empty?
            Common.log_info('[Outline] 見出しが検出できませんでした（h1..h3）。スキップします')
            return false
          end

          # pdftotext でページ単位テキストを走査するヘルパ
          unless system('which pdftotext >/dev/null 2>&1')
            Common.log_warn('[Outline] pdftotext が見つかりません。`brew install poppler` を実行してください。アウトライン付与をスキップします')
            return false
          end

          total_pages = (BuildHelpers.page_count(pdf_path) || '0').to_i
          if total_pages <= 0
            Common.log_warn('[Outline] PDF のページ数を取得できませんでした')
            return false
          end

          page_cache = {}
          from_base = [[start_page.to_i, 1].max, total_pages].min
          get_page_text = lambda do |p|
            txt = page_cache[p]
            unless txt
              txt = `pdftotext -f #{p} -l #{p} "#{pdf_path}" - 2>/dev/null`
              page_cache[p] = txt
            end
            txt
          end
          find_page_in_range = lambda do |needle, from_p, to_p|
            fr = [[from_p.to_i, from_base].max, total_pages].min
            to = [[to_p.to_i, total_pages].min, fr].max
            (fr..to).each do |p|
              text = get_page_text.call(p)
              return p if text && !text.empty? && text.include?(needle)
            end
            nil
          end

          # 章開始ページを 'VS-CHAPTER: <basename>' マーカーから検出
          chapter_starts = {}
          chapter_order.each do |bn|
            p = find_page_in_range.call("VS-CHAPTER: #{bn}", from_base, total_pages)
            chapter_starts[bn] = p
          end
          # 章ごとのページ範囲を決定（次章開始 - 1）。未知の場合は本文全体を範囲とする
          chapter_ranges = {}
          chapter_order.each_with_index do |bn, i|
            s = chapter_starts[bn] || from_base
            e = if i + 1 < chapter_order.size
                  nxt_bn = chapter_order[i + 1]
                  nxt_s  = chapter_starts[nxt_bn]
                  (nxt_s && nxt_s > 0) ? (nxt_s - 1) : total_pages
                else
                  total_pages
                end
            chapter_ranges[bn] = [s, e]
          end

          items = [] # [{level:, text:, page:}]
          headings.each do |h|
            rng = chapter_ranges[h[:chapter]] || [from_base, total_pages]
            p = find_page_in_range.call(h[:text], rng[0], rng[1])
            # 章範囲で見つからない場合は本文全体でフォールバック検索
            p ||= find_page_in_range.call(h[:text], from_base, total_pages)
            items << { level: h[:level], text: h[:text], page: p } if p
          end
          if items.empty?
            Common.log_info('[Outline] 対応ページが見つからなかったため、アウトライン付与をスキップします')
            return false
          end

          # HexaPDF でアウトラインを構築
          doc = HexaPDF::Document.open(pdf_path)
          root = doc.outline
          if root[:First]
            existing_items = []
            root.each_item { |item, _level| existing_items << item }
            existing_items.each do |item|
              begin
                doc.delete(item)
              rescue StandardError
                # 既存のブックマーク削除で失敗しても続行
              end
            end
            root.delete(:First)
            root.delete(:Last)
            root.delete(:Count)
          end
          parents = { 1 => root }
          items.each do |it|
            lvl = [[it[:level].to_i, 1].max, max_level].min
            parent = parents[lvl] || parents[parents.keys.select { |k| k < lvl }.max] || root
            # HexaPDF destination array must be of the form [page, :Fit] etc.
            # Use :Fit so the page is displayed entirely.
            page_obj = doc.pages[it[:page] - 1]
            parent.add_item(it[:text], destination: [page_obj, :Fit]) do |node|
              parents[lvl + 1] = node
            end
          end
          doc.write(pdf_path, optimize: true)
          Common.log_success('[Outline] PDF にブックマーク（アウトライン）を付与しました')
          true
        end

        # ================================================================
        # Step 11: ビルド完了前に .orig バックアップから CSS を復元
        # ------------------------------------------------
        # - 11..89 章に対応する stylesheets/NN.css を対象
        # - 存在する .orig を元ファイルへ復元し、変更を巻き戻す
        # ================================================================
        def restore_chapter_css_backups_for_book!(keep = nil)
          # Step 2 で仮想連番を適用した章に対応する stylesheets/NN.css を同じ規則で決定
          numbers = BuildHelpers.chapter_numbers_for_book(keep)
          css_paths = numbers
                        .map { |n| File.join(Common::STYLESHEETS_DIR, "#{n}.css") }
                        .select { |css| File.exist?(css) }
          if css_paths.empty?
            Common.log_info('[Step 11] 復元対象CSSが見つかりません')
            return
          end
          Common.log_action('[Step 11] 章CSSをバックアップから復元します…')
          css_paths.each do |css|
            backup = css + '.orig'
            next unless File.exist?(backup)
            FileUtils.mv(backup, css, force: true)
            Common.log_info("[Step 11] 復元: #{File.basename(css)}")
          end
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
          basenames = if keep && keep.any?
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
          page_cfg = (Common::CONFIG['page'] || {})
          result = Common.resolve_page_size(page_cfg)
          if result.is_a?(Array) && result.size == 2 && result.all? { |dim| dim.to_s.strip.match?(/\A[0-9.]+(mm|pt)?\z/) }
            result
          else
            ['182mm', '257mm']
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

          if body_end > 0
            Common.log_action("[Step 7] 本文・付録を抽出しています (1-#{body_end})…")
            ok1 = system(%(qpdf "#{output_pdf}" --pages "#{output_pdf}" 1-#{body_end} -- "#{body_pdf}"))
          else
            Common.log_warn('[Step 7] 本文側のページがありません。frontmatter が全ページを占めています。')
          end

          if frontmatter_pages < total_pages
            start_last = body_end + 1
            Common.log_action("[Step 7] frontmatter を抽出しています (#{start_last}-z)…")
            ok2 = system(%(qpdf "#{output_pdf}" --pages "#{output_pdf}" #{start_last}-z -- "#{front_pdf}"))
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
        def update_css_counter(css_path, number)
          return false unless File.exist?(css_path)
          num = number.to_i
          css = File.read(css_path, encoding: 'utf-8')

          updated_css = css.dup
          # counter-reset: chapter-counter XX;
          updated_css = updated_css.gsub(/(counter-reset:\s*chapter-counter\s*)\d+(\s*;)/) do
            pre, post = Regexp.last_match(1), Regexp.last_match(2)
            "#{pre}#{num}#{post}"
          end
          # コメント: /* 第XX章用スタイル */
          updated_css = updated_css.gsub(/\/\*\s*第\s*\d+\s*章用スタイル\s*\*\//) do
            "/* 第#{num}章用スタイル */"
          end

          if updated_css != css
            File.write(css_path, updated_css, encoding: 'utf-8')
            Common.log_success("CSSの章番号/コメントを更新しました: #{File.basename(css_path)} → #{num}")
            true
          else
            Common.log_info("CSSに更新対象が見つかりません: #{css_path}")
            false
          end
        end
      end
    end
  end
end
