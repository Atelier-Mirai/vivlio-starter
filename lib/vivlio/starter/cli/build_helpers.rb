# frozen_string_literal: true

require 'rbconfig'
require 'fileutils'
require 'hexapdf'
require 'time'

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

        # 内部ユーティリティ: --single-doc を強制無効化して pdf を実行
        def run_pdf_without_single_doc!
          prev = ENV['VIVLIO_SINGLE_DOC']
          begin
            ENV['VIVLIO_SINGLE_DOC'] = '0'
            Vivlio::Starter::ThorCLI.start(['pdf'])
          ensure
            if prev.nil?
              ENV.delete('VIVLIO_SINGLE_DOC')
            else
              ENV['VIVLIO_SINGLE_DOC'] = prev
            end
          end
        end

        # 単一HTMLを単独PDFにする補助（一時config + single-docで直接ビルド）
        # html: プロジェクトルート相対の HTML パス（例: '00-titlepage.html')
        # out_pdf: 生成先のPDFファイル名（プロジェクトルートに配置）
        def build_single_html_to_pdf!(html, out_pdf)
          return unless File.exist?(html)
          require 'tmpdir'
          Dir.mktmpdir('vs_cfg_') do |dir|
            # proj/ シンボリックリンク（ローカルサーバ配下の相対参照にする）
            proj_link = File.join(dir, 'proj')
            begin
              File.symlink(Dir.pwd, proj_link)
            rescue
              proj_link = Dir.pwd
            end
            width, height = BuildHelpers.page_size_strings_from_config
            tmp_config = File.join(dir, 'vivliostyle.tmp.config.js')
            File.open(tmp_config, 'w', encoding: 'utf-8') do |f|
              f.puts <<~JS
                /** @type {import('@vivliostyle/cli').VivliostyleConfigSchema} */
                const vivliostyleConfig = {
                  entry: [ './proj/#{html}' ],
                  output: [ './out.pdf' ],
                  size: '#{width} #{height}'
                };
                export default vivliostyleConfig;
              JS
            end
            # single-docで直接ビルド（entries.jsを介さない）
            system('npx', 'vivliostyle', 'build', '-c', tmp_config, '-d', chdir: dir)
            src = File.join(dir, 'out.pdf')
            if File.exist?(src)
              FileUtils.rm_f(out_pdf)
              FileUtils.cp(src, out_pdf)
              true
            else
              Common.log_warn("[single-doc] PDF が生成されませんでした: #{html}")
              false
            end
          end
        rescue => e
          Common.log_warn("[single-doc] 生成でエラー: #{html} (#{e})")
          false
        end

        # ------------------------------------------------
        # Timing utilities: 章別×ステップ別の計測を timings.csv に追記
        # ------------------------------------------------
        # - CSV フォーマット: chapter,step,seconds
        # - 既存ファイルにヘッダーが無い場合はヘッダーを追記
        # - 例外は握りつぶしてビルド継続
        def record_timing(chapter, step, seconds)
          begin
            path = File.join(Dir.pwd, 'timings.csv')
            write_header = !File.exist?(path) || File.zero?(path)
            File.open(path, 'a', encoding: 'utf-8') do |f|
              if write_header
                f.puts 'chapter,step,seconds'
              end
              f.puts [chapter.to_s, step.to_s, format('%.2f', seconds.to_f)].join(',')
            end
          rescue => e
            begin
              Common.log_warn("[Timing] timings.csv への書き込みに失敗: #{e}")
            rescue
              # ignore logging failures
            end
          end
        end

        def time_step_for_chapter(chapter, step)
          t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          begin
            yield if block_given?
          ensure
            t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            dt = (t1 - t0)
            begin
              Common.log_action("[Timer] #{chapter} / #{step} : #{format('%.2f', dt)}s")
            rescue
              # ignore
            end
            record_timing(chapter, step, dt)
          end
        end

        # ================================================================
        # Config: 章サブセット（config/book.yml の chapters キー）
        # ------------------------------------------------
        # - 'all' の場合はフルビルド（nil を返して従来どおり）
        # - 配列（['11-foo.md', '12-bar.md', ...]）指定時は、その章のみを残す
        # ================================================================
        def configured_chapters
          cfg = Common::CONFIG['chapters'] rescue nil
          begin
            Common.log_info("[Subset] raw chapters config=#{cfg.inspect}") unless cfg.nil?
          rescue
            # ignore logging errors
          end
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
            begin
              Common.log_info("[Subset] normalized keep(list)=#{items.inspect}") if items.any?
            rescue
              # ignore logging errors
            end
            return items if items.any?
            return nil
          elsif cfg.is_a?(Array)
            items = cfg.map { |s| s.to_s.strip }.reject(&:empty?)
            items = items.map { |s|
              name = s.sub(%r{\A#{Regexp.escape(Common::CONTENTS_DIR)}/}, '')
              name = name + '.md' unless name.end_with?('.md')
              name
            }
            begin
              Common.log_info("[Subset] normalized keep(array)=#{items.inspect}") if items.any?
            rescue
              # ignore logging errors
            end
            return items
          end
          nil
        rescue => _e
          nil
        end

        # Note: Legacy backup-based subset utilities were removed in favor of
        # logical filtering with configured_chapters (no file moves).

        # ------------------------------------------------
        # Shared helpers: 章の抽出（11..89 本文、付録）
        # ------------------------------------------------
        # - main_text_basenames(keep): '11-install' のような拡張子なしベース名を返す
        # - main_text_htmls(base_dir, keep): ディレクトリ内の HTML を 11..89 (+ keep で限定) で抽出
        # - appendix_basenames(keep): '91-foo' 等の付録ベース名（拡張子なし）を返す
        def main_text_basenames(keep = nil)
          basenames = if keep && keep.any?
                        Array(keep).map { |s| File.basename(s.to_s, '.md') }
                      else
                        Dir[File.join(Common::CONTENTS_DIR, '*.md')].map { |p| File.basename(p, '.md') }
                      end
          basenames
            .select { |bn| bn =~ /\A(\d+)-/ && $1.to_i.between?(11, 89) }
            .uniq
            .sort
        rescue => _e
          []
        end

        def main_text_htmls(base_dir = '.', keep = nil)
          numbers = BuildHelpers.chapter_numbers_for_book(keep)
          limit_by_keep = keep && keep.any?
          Dir.glob(File.join(base_dir, '*.html'))
            .select { |f|
              bn = File.basename(f)
              if bn =~ /\A(\d+)-.*\.html\z/
                n = $1.to_i
                (11..89).include?(n) && (!limit_by_keep || numbers.include?(n))
              else
                false
              end
            }
            .sort
        rescue => _e
          []
        end

        def appendix_basenames(keep = nil)
          appendix_paths   = Dir[File.join(Common::CONTENTS_DIR, '{91,92,93,94,95,96,97}-*.md')]
          appendix_targets = appendix_paths.map { |p| File.basename(p, '.md') }.uniq.sort
          if keep && keep.any?
            appendix_targets.select! { |t| keep.include?("#{t}.md") }
          end
          appendix_targets
        rescue => _e
          []
        end

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
        rescue => e
          Common.log_warn("[Step 1] 画像最適化でエラー: #{e}。ビルドは続行します")
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
            begin
              backup = css + '.orig'
              unless File.exist?(backup)
                FileUtils.cp(css, backup)
              end
              update_css_counter(css, idx + 1)
            rescue => e
              Common.log_warn("[Step 2] 仮想連番更新に失敗: #{css} (#{e})")
            end
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

          # chapters 指定がある場合は、含まれないときスキップ
          if keep && !keep.include?('02-preface.md')
            Common.log_action('[Step 3] 02-preface は chapters 設定に含まれないためスキップします')
            return
          end

          # 02-preface.md が存在しない場合はスキップ（ページ数0相当で続行）
          begin
            md_path = File.join(Common::CONTENTS_DIR, '02-preface.md')
            unless File.exist?(md_path)
              Common.log_warn('[Step 3] 02-preface.md が見つかりません。先行ビルドをスキップします（ページ数0として続行）')
              return
            end
          rescue => e
            Common.log_warn("[Step 3] 02-preface の存在確認に失敗: #{e}。スキップします")
            return
          end

          %w[pre_process convert post_process entries].each do |t|
            BuildHelpers.time_step_for_chapter('02-preface', t) do
              Vivlio::Starter::ThorCLI.start([t, '02-preface'])
            end
          end
          BuildHelpers.time_step_for_chapter('02-preface', 'pdf') do
            # 従来ルート: entries.js 経由で pdf を生成し、output.pdf を 02-preface.pdf にリネーム
            Vivlio::Starter::ThorCLI.start(['pdf'])
            pdf_config   = Common::CONFIG['pdf'] || {}
            output_pdf   = pdf_config['output_file'] || 'output.pdf'
            preface_pdf  = '02-preface.pdf'
            if File.exist?(output_pdf)
              Common.log_action("#{output_pdf} をリネームしています: #{output_pdf} → #{preface_pdf}")
              FileUtils.rm_f(preface_pdf)
              FileUtils.mv(output_pdf, preface_pdf)
            else
              Common.log_warn("[Step 3] 出力PDFが見つかりません: #{output_pdf}")
            end
          end
          preface_pdf  = '02-preface.pdf'
          if File.exist?(preface_pdf)
            pages = BuildHelpers.page_count(preface_pdf)
            pages ? Common.log_success("ページ数: #{pages} (#{preface_pdf})") : Common.log_warn("ページ数の取得に失敗しました: #{preface_pdf}")
          end
        end

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

          # chapters 指定がある場合は、含まれる付録のみ対象
          if keep && keep.any?
            appendix_targets.select! { |t| keep.include?("#{t}.md") }
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

          # 個別付録HTMLをクリーンアップ
          begin
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
          rescue => e
            Common.log_warn("[Step 4] 個別付録HTMLのクリーンアップでエラー: #{e}")
          end
        rescue => e
          Common.log_warn("[Step 4] 付録ビルド/結合でエラー: #{e}")
        end

        # ================================================================
        # Step 5: 本文章 (11..89) をビルド（HTML生成）
        # ------------------------------------------------
        # - 対象: contents/*.md のうち 11..89 の接頭辞
        # - 実行: pre_process -> convert -> post_process
        # ================================================================
        def build_chapters_html!(keep = nil)
          Common.log_action('[Step 5] 章をビルドします…（仮想連番: 1,2,3…）')
          chapter_targets = BuildHelpers.main_text_basenames(keep)

          if chapter_targets.empty?
            Common.log_warn('[Step 5] 章が見つかりません。Step 5 をスキップします。')
            return
          end

          Common.log_info("[Step 5] 対象: #{chapter_targets.join(', ')}")

          # 並列度（未設定/1以下は逐次）
          concurrency = (ENV['VIVLIO_BUILD_CONCURRENCY'] || '').to_i
          concurrency = 1 if concurrency <= 0

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

          # スレッドプールで並列実行
          require 'thread'
          q = Queue.new
          chapter_targets.each { |t| q << t }
          workers = []
          Common.log_info("[Step 5] 並列実行を開始します（concurrency=#{concurrency}、対象=#{chapter_targets.size}）")
          concurrency.times do |i|
            workers << Thread.new do
              Thread.current[:name] = "builder-#{i+1}"
              while true
                target = nil
                begin
                  target = q.pop(true)
                rescue ThreadError
                  break
                end
                begin
                  %w[pre_process convert post_process].each do |tn|
                    BuildHelpers.time_step_for_chapter(target, tn) do
                      Vivlio::Starter::ThorCLI.start([tn, target])
                    end
                  end
                rescue => e
                  begin
                    Common.log_warn("[Step 5] 並列ビルド中にエラー: #{target} (#{e})")
                  rescue
                  end
                end
              end
            end
          end
          workers.each(&:join)
        rescue => e
          Common.log_warn("[Step 5] 章ビルドでエラー: #{e}")
        end

        # ================================================================
        # Step 6: TOC 生成（03-toc.html, 03-toc.pdf）
        # ------------------------------------------------
        # - 対象: 章HTML + 90-appendices.html(存在時)
        # - 実行: toc -> entries(03-toc.html) -> pdf -> 03-toc.pdf へリネーム
        # ================================================================
        def generate_toc_and_pdf!(base_dir = '.', keep = nil)
          chapter_htmls = BuildHelpers.main_text_htmls(base_dir, keep)
          appendix_html = File.join(base_dir, '90-appendices.html')
          targets_for_toc = chapter_htmls
          targets_for_toc << appendix_html if File.exist?(appendix_html)

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
          Vivlio::Starter::ThorCLI.start(['entries', '03-toc'])
          Vivlio::Starter::ThorCLI.start(['pdf'])

          pdf_config   = Common::CONFIG['pdf'] || {}
          output_pdf   = pdf_config['output_file'] || 'output.pdf'
          toc_pdf      = '03-toc.pdf'
          if File.exist?(output_pdf)
            Common.log_action("output.pdf をリネームしています: #{output_pdf} → #{toc_pdf}")
            FileUtils.rm_f(toc_pdf)
            FileUtils.mv(output_pdf, toc_pdf)
            Common.log_success('[Step 6] 03-toc.pdf を生成しました')
          end
        end

        # ================================================================
        # Step 7: 全体PDF生成→分割（ディレクトリスキャン版）
        # ------------------------------------------------
        # - base_dir から対象HTML収集
        # - compile_overall_pdf_and_split! に委譲
        # ================================================================
        def build_overall_pdf_and_split_from_dir!(base_dir = '.', keep = nil)
          toc_html = [File.join(base_dir, '03-toc.html')].select { |f| File.exist?(f) }
          chapter_htmls_for_pdf = BuildHelpers.main_text_htmls(base_dir, keep)
          appendix_html_for_pdf = File.exist?(File.join(base_dir, '90-appendices.html')) ? [File.join(base_dir, '90-appendices.html')] : []

          # 付録を奇数（右）ページ開始にするためのガードページを挿入
          guard_html = nil
          if appendix_html_for_pdf.any?
            guard_html = File.join(base_dir, '90-appendices-guard.html')
            begin
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
              File.write(guard_html, html, encoding: 'utf-8')
            rescue => e
              Common.log_warn("[Step 7] 付録ガードHTMLの作成に失敗: #{e}。ガードをスキップします")
              guard_html = nil
            end
          end

          targets_for_pdf = if guard_html
                               chapter_htmls_for_pdf + [guard_html] + appendix_html_for_pdf + toc_html
                             else
                               chapter_htmls_for_pdf + appendix_html_for_pdf + toc_html
                             end

          BuildHelpers.compile_overall_pdf_and_split!(targets_for_pdf)
        rescue => e
          Common.log_warn("[Step 7] 章PDF化/分割でエラー: #{e}")
        end

        # ================================================================
        # Step 7 (Alternative): 本文(11..89)を単一 chapters.html に結合してから PDF 生成
        # ------------------------------------------------
        # - base_dir の 11..89 章 HTML を収集し、1つの HTML に結合
        # - 付録(90-appendices.html) と TOC(03-toc.html) は従来どおり別扱い
        # - 生成した chapters.html を先頭に据えて compile_overall_pdf_and_split!
        # ================================================================
        def build_overall_pdf_from_single_chapters_html!(base_dir = '.', keep = nil)
          Common.log_action('[Step 7] 単一 HTML への結合モードで全体PDFを生成します…')
          chapter_htmls = BuildHelpers.main_text_htmls(base_dir, keep)
          if chapter_htmls.empty?
            Common.log_warn('[Step 7] 本文HTMLが見つかりません。結合モードをスキップします。')
            return
          end

          combined_path = File.join(base_dir, 'chapters.html')
          begin
            # head は先頭章から流用し、body は各章の <body> 内のみを抽出して結合
            first = chapter_htmls.first
            first_text = File.read(first, encoding: 'utf-8') rescue ''
            head_html = (first_text[/<head[\s\S]*?<\/head>/i] || <<~HEAD)
              <head>
                <meta charset="utf-8">
                <title>Chapters</title>
              </head>
            HEAD

            bodies = []
            chapter_htmls.each do |path|
              name = File.basename(path)
              text = File.read(path, encoding: 'utf-8') rescue ''
              inner = text[/<body[^>]*>([\s\S]*?)<\/body>/i, 1] || text
              bodies << "<section data-chapter=\"#{name}\">\n#{inner}\n</section>"
            end

            width, height = BuildHelpers.page_size_strings_from_config
            html = <<~HTML
              <!doctype html>
              <html>
              #{head_html}
              <body>
              <!-- Combined chapters (11..89) -->
              #{bodies.join("\n\n")}
              </body>
              </html>
            HTML
            File.write(combined_path, html, encoding: 'utf-8')
            Common.log_success("[Step 7] chapters.html を生成しました（#{chapter_htmls.size} 章を結合）")
          rescue => e
            Common.log_warn("[Step 7] chapters.html の生成に失敗: #{e}")
            return
          end

          appendix_html_for_pdf = File.exist?(File.join(base_dir, '90-appendices.html')) ? [File.join(base_dir, '90-appendices.html')] : []
          toc_html = [File.join(base_dir, '03-toc.html')].select { |f| File.exist?(f) }

          # 付録を奇数（右）ページ開始にするためのガードページを挿入（従来と同じ）
          guard_html = nil
          if appendix_html_for_pdf.any?
            guard_html = File.join(base_dir, '90-appendices-guard.html')
            begin
              width, height = BuildHelpers.page_size_strings_from_config
              html = <<~HTML
                <!doctype html>
                <html>
                <head>
                  <meta charset="utf-8">
                  <title>Appendices Guard</title>
                  <style>
                    @page { size: #{width} #{height}; }
                  </style>
                </head>
                <body></body>
                </html>
              HTML
              File.write(guard_html, html, encoding: 'utf-8')
            rescue => e
              Common.log_warn("[Step 7] 付録ガードHTMLの作成に失敗: #{e}。ガードをスキップします")
              guard_html = nil
            end
          end

          targets_for_pdf = if guard_html
                               [combined_path] + [guard_html] + appendix_html_for_pdf + toc_html
                             else
                               [combined_path] + appendix_html_for_pdf + toc_html
                             end

          BuildHelpers.compile_overall_pdf_and_split!(targets_for_pdf)
        rescue => e
          Common.log_warn("[Step 7] 結合 chapters.html でのPDF生成に失敗: #{e}")
        end

        # ================================================================
        # Step 7: 全体PDF生成 → frontmatter/chapters に分割
        # ------------------------------------------------
        # - entries.js 生成 -> pdf 出力(output.pdf)
        # - 03-toc.pdf のページ数取得
        # - qpdf により本文+付録と frontmatter に分割
        # ================================================================
        def compile_overall_pdf_and_split!(targets_for_pdf)
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

          BuildHelpers.split_pdf_chapters_then_frontmatter(
            output_pdf,
            toc_pages,
            '03-toc.pdf',
            'chapters_appendices.pdf'
          )
        end

        # ================================================================
        # Experimental: 章PDFを並列生成して chapters_appendices.pdf に結合
        # ------------------------------------------------
        # - 本文(11..89)の各章を個別PDF化（pre/convert/post/entries/pdf）
        # - 90-appendices.html があれば 90-appendices.pdf も生成
        # - 生成した PDF 群を hexapdf merge で chapters_appendices.pdf に結合
        # - 並列度は ENV['VIVLIO_PDF_CONCURRENCY']（既定: 2）
        # 注意:
        # - 付録の右ページ開始（奇数ページ頭）ガードは簡略化のため未実装（実験段階）
        # ================================================================
        def build_chapter_pdfs_in_parallel_and_merge!(keep = nil)
          Common.log_action('[Step 7-EXPERIMENT] 章PDFを並列生成し、結合します…')
          chapter_targets = BuildHelpers.main_text_basenames(keep)
          if chapter_targets.empty?
            Common.log_warn('[Step 7-EXPERIMENT] 本文章が見つかりません。処理をスキップします。')
            return
          end

          # 並列度
          concurrency = (ENV['VIVLIO_PDF_CONCURRENCY'] || '2').to_i
          concurrency = 2 if concurrency <= 0

          # 章を並列でPDF化
          require 'thread'
          q = Queue.new
          chapter_targets.each { |t| q << t }
          pdfs_mutex = Mutex.new
          generated_pdfs = []
          port_counter = 0
          port_mutex = Mutex.new

          workers = []
          concurrency.times do |i|
            workers << Thread.new do
              while true
                target = nil
                begin
                  target = q.pop(true)
                rescue ThreadError
                  break
                end
                begin
                  %w[pre_process convert post_process].each do |tn|
                    BuildHelpers.time_step_for_chapter(target, tn) do
                      Vivlio::Starter::ThorCLI.start([tn, target])
                    end
                  end
                  # 単一HTMLとして Vivliostyle CLIを直接呼び出し（entries.js を共有しない）
                  chapter_html = "#{target}.html"
                  unless File.exist?(chapter_html)
                    Common.log_warn("[Step 7-EXPERIMENT] HTMLが見つかりません: #{chapter_html}")
                    next
                  end
                  tmp_config = nil
                  require 'tmpdir'
                  BuildHelpers.time_step_for_chapter(target, 'pdf') do
                    Dir.mktmpdir("vs_cfg_") do |dir|
                      # 作業ディレクトリを隔離し、プロジェクト全体にシンボリックリンクを張る
                      proj_link = File.join(dir, 'proj')
                      begin
                        File.symlink(Dir.pwd, proj_link)
                      rescue
                        # symlink 失敗時はフォールバックでそのまま参照（絶対パスに戻す）
                        proj_link = Dir.pwd
                      end

                      tmp_config = File.join(dir, 'vivliostyle.tmp.config.js')
                      width, height = BuildHelpers.page_size_strings_from_config
                      # proj/ 経由で参照（ローカルサーバ配下の相対パスになる）
                      entry_path = "./proj/#{chapter_html}"
                      output_path = "./#{target}.pdf"
                      File.open(tmp_config, 'w', encoding: 'utf-8') do |f|
                        f.puts <<~JS
                          // auto-generated temporary config for single-doc build
                          /** @type {import('@vivliostyle/cli').VivliostyleConfigSchema} */
                          const vivliostyleConfig = {
                            title: '#{Common::CONFIG.dig('book', 'title') || 'chapter'}',
                            author: '#{Common::CONFIG.dig('book', 'author') || ''}',
                            language: '#{Common::CONFIG.dig('book', 'language') || 'ja'}',
                            readingProgression: 'ltr',
                            entry: [ '#{entry_path.gsub("'", "\\'")}' ],
                            output: [ '#{output_path.gsub("'", "\\'")}' ],
                            size: '#{width} #{height}'
                          };
                          export default vivliostyleConfig;
                        JS
                      end
                      # ユニークポート採番
                      port = nil
                      port_mutex.synchronize do
                        port_counter += 1
                        port = 13000 + (port_counter % 1000)
                      end
                      system('npx', 'vivliostyle', 'build', '-c', 'vivliostyle.tmp.config.js', '--port', port.to_s, '-d', chdir: dir)
                      # 生成PDFをプロジェクトルートへコピー
                      src_pdf = File.join(dir, "#{target}.pdf")
                      if File.exist?(src_pdf)
                        pdfs_mutex.synchronize do
                          FileUtils.rm_f("#{target}.pdf")
                          FileUtils.cp(src_pdf, "#{target}.pdf")
                          generated_pdfs << "#{target}.pdf"
                          Common.log_success("[Step 7-EXPERIMENT] 章PDF生成: #{target}.pdf")
                        end
                      else
                        Common.log_warn("[Step 7-EXPERIMENT] 出力PDFが見つかりません: #{target}.pdf")
                      end
                    end
                  end
                rescue => e
                  Common.log_warn("[Step 7-EXPERIMENT] 章PDF生成でエラー: #{target} (#{e})")
                end
              end
            end
          end
          workers.each(&:join)

          # 付録PDF（存在時）
          appendix_pdf = nil
          begin
            if File.exist?('90-appendices.html')
              BuildHelpers.time_step_for_chapter('90-appendices', 'pdf') do
                Dir.mktmpdir("vs_cfg_") do |dir|
                  # プロジェクトルートへのシンボリックリンクを張る
                  proj_link = File.join(dir, 'proj')
                  begin
                    File.symlink(Dir.pwd, proj_link)
                  rescue
                    proj_link = Dir.pwd
                  end
                  tmp_config = File.join(dir, 'vivliostyle.tmp.config.js')
                  width, height = BuildHelpers.page_size_strings_from_config
                  File.open(tmp_config, 'w', encoding: 'utf-8') do |f|
                    f.puts <<~JS
                      /** @type {import('@vivliostyle/cli').VivliostyleConfigSchema} */
                      const vivliostyleConfig = {
                        title: 'appendices',
                        author: '#{Common::CONFIG.dig('book', 'author') || ''}',
                        language: '#{Common::CONFIG.dig('book', 'language') || 'ja'}',
                        readingProgression: 'ltr',
                        entry: [ './proj/90-appendices.html' ],
                        output: [ './90-appendices.pdf' ],
                        size: '#{width} #{height}'
                      };
                      export default vivliostyleConfig;
                    JS
                  end
                  # ユニークポート採番
                  port = nil
                  port_mutex.synchronize do
                    port_counter += 1
                    port = 13000 + (port_counter % 1000)
                  end
                  system('npx', 'vivliostyle', 'build', '-c', tmp_config, '--port', port.to_s, '-d', chdir: dir)
                  # 移動
                  src_pdf = File.join(dir, '90-appendices.pdf')
                  if File.exist?(src_pdf)
                    FileUtils.rm_f('90-appendices.pdf')
                    FileUtils.cp(src_pdf, '90-appendices.pdf')
                  end
                end
              end
              appendix_pdf = '90-appendices.pdf' if File.exist?('90-appendices.pdf')
            end
          rescue => e
            Common.log_warn("[Step 7-EXPERIMENT] 付録PDF生成でエラー: #{e}")
          end

          # 結合順: 本文章 → 付録（存在時）
          merge_list = generated_pdfs.sort_by { |p| p[/^(\d+)-/, 1].to_i }
          merge_list << appendix_pdf if appendix_pdf && File.exist?(appendix_pdf)

          if merge_list.empty?
            Common.log_warn('[Step 7-EXPERIMENT] 結合対象PDFがありません。')
            return
          end

          begin
            FileUtils.rm_f('chapters_appendices.pdf')
            cmd = ['bundle', 'exec', 'hexapdf', 'merge', *merge_list, 'chapters_appendices.pdf'].join(' ')
            merged = system(cmd)
            if merged && File.exist?('chapters_appendices.pdf')
              Common.log_success('[Step 7-EXPERIMENT] chapters_appendices.pdf を生成しました（並列章PDF結合）')
            else
              Common.log_error('[Step 7-EXPERIMENT] chapters_appendices.pdf の生成に失敗しました')
            end
          rescue => e
            Common.log_warn("[Step 7-EXPERIMENT] PDF結合でエラー: #{e}")
          end
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
            Common.log_warn("[Step 8] ページ番号のオーバーレイ描画でエラー: #{e}")
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
            Common.log_warn("[Step 8] HexaPDF によるページラベル設定でエラー: #{e}")
            false
          end
        end

        # ================================================================
        # Step 8: frontmatter.pdf 構成 + ローマ小付与
        # ------------------------------------------------
        # - 02-preface.pdf + 03-toc.pdf を merge
        # - HexaPDF PageLabels 設定 → 小文字ローマ数字をオーバーレイ描画
        # ================================================================
        def build_frontmatter_pdf!
          Common.log_action('[Step 8] frontmatter.pdf を構成し、ローマ小 i〜 を付与します…')

          files_to_merge = ['02-preface.pdf', '03-toc.pdf']
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
            begin
              pages = (BuildHelpers.page_count('frontmatter.pdf') || '0').to_i
              if pages.odd?
                doc = HexaPDF::Document.open('frontmatter.pdf')
                first_box = doc.pages[0].box(:media)
                doc.pages.add([first_box.left, first_box.bottom, first_box.right, first_box.top])
                doc.write('frontmatter.pdf', optimize: true)
                Common.log_info('[Step 8] frontmatter.pdf が奇数ページのため、空白1ページを末尾に挿入しました')
              end
            rescue => e
              Common.log_warn("[Step 8] frontmatter への空白ページ追加に失敗: #{e}")
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
            begin
              pages = (BuildHelpers.page_count('frontmatter.pdf') || '0').to_i
              if pages.odd?
                doc = HexaPDF::Document.open('frontmatter.pdf')
                first_box = doc.pages[0].box(:media)
                doc.pages.add([first_box.left, first_box.bottom, first_box.right, first_box.top])
                doc.write('frontmatter.pdf', optimize: true)
                Common.log_info('[Step 8] frontmatter.pdf が奇数ページのため、空白1ページを末尾に挿入しました')
              end
            rescue => e
              Common.log_warn("[Step 8] frontmatter への空白ページ追加に失敗: #{e}")
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
        rescue => e
          Common.log_warn("[Step 8] ページ番号連番化処理でエラー: #{e}")
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
            t_mtime = File.mtime(target) rescue Time.at(0)
            Array(sources).any? { |s| File.exist?(s) && File.mtime(s) > t_mtime }
          end

          front_pdf = '00-01-front.pdf'
          cache_on = Common.cache_enabled? && !force
          cache_dir = Common.ensure_cache_dir! if cache_on rescue nil
          front_cache = cache_on ? File.join(cache_dir, '00-01-front.pdf') : nil
          need_front = force || newer_than_any.call(front_pdf, front_srcs)

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
            Vivlio::Starter::ThorCLI.start(['pdf'])
            pdf_config   = Common::CONFIG['pdf'] || {}
            output_pdf   = pdf_config['output_file'] || 'output.pdf'
            if File.exist?(output_pdf)
              FileUtils.rm_f(front_pdf)
              FileUtils.mv(output_pdf, front_pdf)
            end
            if File.exist?(front_pdf)
              Common.log_success("[Step 9] #{front_pdf} を生成しました")
              # キャッシュへ保存
              if cache_on
                begin
                  FileUtils.cp(front_pdf, front_cache)
                  Common.log_info("[Step 9] キャッシュへ保存しました: #{front_cache}")
                rescue => e
                  Common.log_warn("[Step 9] フロントPDFのキャッシュ保存に失敗: #{e}")
                end
              end
              front_regenerated = true
            else
              Common.log_warn("[Step 9] #{front_pdf} の生成に失敗しました")
            end
          else
            Common.log_action("[Step 9] フロント/奥付PDFは最新のため再利用します: #{front_pdf}, 99-colophon.pdf")
            # ルートにファイルが無ければキャッシュから復元
            if cache_on
              begin
                if !File.exist?(front_pdf) && front_cache && File.exist?(front_cache)
                  FileUtils.cp(front_cache, front_pdf)
                  Common.log_info("[Step 9] キャッシュから復元しました: #{front_pdf}")
                end
                colo_cache = File.join(cache_dir, '99-colophon.pdf')
                if !File.exist?('99-colophon.pdf') && File.exist?(colo_cache)
                  FileUtils.cp(colo_cache, '99-colophon.pdf')
                  Common.log_info('[Step 9] キャッシュから復元しました: 99-colophon.pdf')
                end
              rescue => e
                Common.log_warn("[Step 9] キャッシュからの復元に失敗: #{e}")
              end
            end
            # フロントが最新でも、後書き(postface)の生成はこの後に続行する
          end

          # ここから奥付の生成（フロントを再生成した場合は必ず奥付も再生成）
          if front_regenerated
            %w[pre_process convert post_process entries].each do |t|
              Vivlio::Starter::ThorCLI.start([t, '99-colophon'])
            end
            Vivlio::Starter::ThorCLI.start(['pdf'])
            pdf_config   = Common::CONFIG['pdf'] || {}
            output_pdf   = pdf_config['output_file'] || 'output.pdf'
            if File.exist?(output_pdf)
              FileUtils.rm_f('99-colophon.pdf')
              FileUtils.mv(output_pdf, '99-colophon.pdf')
              Common.log_success('[Step 9] 99-colophon.pdf を生成しました')
              # キャッシュへ保存
              if cache_on
                begin
                  colo_cache = File.join(cache_dir, '99-colophon.pdf')
                  FileUtils.cp('99-colophon.pdf', colo_cache)
                  Common.log_info("[Step 9] キャッシュへ保存しました: #{colo_cache}")
                rescue => e
                  Common.log_warn("[Step 9] 奥付PDFのキャッシュ保存に失敗: #{e}")
                end
              end
            end
          else
            Common.log_info('[Step 9] フロントが最新のため、奥付の再生成はスキップしました（キャッシュ/既存を利用）')
          end

          begin
            ca_pdf = 'chapters_appendices.pdf'
            postface_css = File.join(Common::STYLESHEETS_DIR, 'postface.css')
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
                Common.log_info("[Step 9] postface.css の開始ページを #{start_page_number} に設定しました (counter-reset: #{reset_value})")
              else
                Common.log_info('[Step 9] postface.css の更新対象が見つかりませんでした（変更なし）')
              end
            else
              Common.log_warn("[Step 9] chapters_appendices.pdf または #{postface_css} が見つからないため、postface 開始ページの自動設定をスキップします")
            end
          rescue => e
            Common.log_warn("[Step 9] postface 開始ページ設定でエラー: #{e}")
          end

          begin
            postface_md = File.join(Common::CONTENTS_DIR, '98-postface.md')
            if File.exist?(postface_md)
              %w[pre_process convert post_process entries].each do |t|
                Vivlio::Starter::ThorCLI.start([t, '98-postface'])
              end
              # entries.js 経由で PDF 生成し、出力を 98-postface.pdf にリネーム
              Vivlio::Starter::ThorCLI.start(['pdf'])
              pdf_config   = Common::CONFIG['pdf'] || {}
              output_pdf   = pdf_config['output_file'] || 'output.pdf'
              if File.exist?(output_pdf)
                FileUtils.rm_f('98-postface.pdf')
                FileUtils.mv(output_pdf, '98-postface.pdf')
              end
              if File.exist?('98-postface.pdf')
                Common.log_success('[Step 9] 98-postface.pdf を生成しました')
              else
                Common.log_warn('[Step 9] 98-postface.pdf の生成に失敗しました')
              end
            else
              Common.log_warn('[Step 9] 98-postface.md が見つかりません。後書きPDF生成をスキップします')
            end
          rescue => e
            Common.log_warn("[Step 9] 98-postface の生成でエラー: #{e}")
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
          Common.log_action('[Step 10] フロント(00-01)、前書き、目次、本文、付録、後書き、奥付を結合します…')
          # 存在するPDFのみで結合を続行します（preface/postface が無くても処理継続）
          Common.log_info('[Step 10] 存在するPDFのみで結合を実行します（02-preface.pdf / 98-postface.pdf は任意）')
          files_to_merge = [
            '00-01-front.pdf', 'frontmatter.pdf',
            'chapters_appendices.pdf', '98-postface.pdf', '99-colophon.pdf'
          ]
          existing_files = files_to_merge.select { |f| File.exist?(f) }
          missing_files  = files_to_merge - existing_files
          # 任意ファイル（存在しなくても正常）
          optional_files = ['98-postface.pdf']
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

          begin
            postface_name = '98-postface.pdf'
            idx = existing_files.index(postface_name)
            if idx
              total_before = 0
              existing_files[0...idx].each do |pf|
                begin
                  total_before += HexaPDF::Document.open(pf).pages.count
                rescue => e
                  Common.log_warn("[Step 10] ページ数取得失敗: #{pf} (#{e})。0ページとして扱います")
                end
              end
              if total_before.odd?
                blank_path = BuildHelpers.ensure_blank_page_pdf('blank_page.pdf')
                if blank_path && File.exist?(blank_path)
                  existing_files.insert(idx, blank_path)
                  Common.log_info('[Step 10] 98-postface.pdf を奇数開始にするため、空白1ページを挿入しました')
                else
                  Common.log_warn('[Step 10] 空白ページPDFを挿入できませんでした（作成失敗）')
                end
              end
            end

            # 99-colophon.pdf は偶数ページ（左ページ）開始になるように調整
            colophon_name = '99-colophon.pdf'
            idx_c = existing_files.index(colophon_name)
            if idx_c
              total_before_c = 0
              existing_files[0...idx_c].each do |pf|
                begin
                  total_before_c += HexaPDF::Document.open(pf).pages.count
                rescue => e
                  Common.log_warn("[Step 10] ページ数取得失敗: #{pf} (#{e})。0ページとして扱います")
                end
              end
              # 次ページ (total_before_c + 1) を偶数にするには、total_before_c が偶数なら空白1ページを追加する
              if total_before_c.even?
                blank_path = BuildHelpers.ensure_blank_page_pdf('blank_page.pdf')
                if blank_path && File.exist?(blank_path)
                  existing_files.insert(idx_c, blank_path)
                  Common.log_info('[Step 10] 99-colophon.pdf を偶数開始にするため、空白1ページを挿入しました')
                else
                  Common.log_warn('[Step 10] 空白ページPDFを挿入できませんでした（作成失敗）')
                end
              end
            end
          rescue => e
            Common.log_warn("[Step 10] 奇数ページ開始調整中にエラー: #{e}")
          end

          Common.log_info("[Step 10] 結合順: #{existing_files.join(' -> ')}")
          FileUtils.rm_f('output.pdf')
          cmd = ['bundle', 'exec', 'hexapdf', 'merge', *existing_files, 'output.pdf'].join(' ')
          merged = system(cmd)
          if merged && File.exist?('output.pdf')
            Common.log_success('[Step 10] output.pdf を生成しました')
          else
            Common.log_error('[Step 10] PDF結合に失敗しました')
          end
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
            begin
              FileUtils.mv(backup, css, force: true)
              Common.log_info("[Step 11] 復元: #{File.basename(css)}")
            rescue => e
              Common.log_warn("[Step 11] 復元に失敗: #{css} (#{e})")
            end
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
        rescue => e
          Common.log_warn("[Step 12] PDF圧縮でエラー: #{e}")
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
        rescue => _e
          []
        end

        # 空白1ページPDFを生成（既存時は何もしない）
        # - 用紙サイズは book.yml の page 設定に追従（共有ヘルパ使用）
        def ensure_blank_page_pdf(path = 'blank_page.pdf')
          return path if File.exist?(path)
          doc = HexaPDF::Document.new

          begin
            w_pt, h_pt = BuildHelpers.page_size_points_from_config
            doc.pages.add([0, 0, w_pt, h_pt])
          rescue => _e
            # 失敗時は B5 で生成
            mm_to_pt = 72.0 / 25.4
            doc.pages.add([0, 0, 182.0 * mm_to_pt, 257.0 * mm_to_pt])
          end

          doc.write(path, optimize: true)
          path
        rescue => _e
          # 失敗時は既存の path 不在でも無視（呼び出し側で rescue 済み）
          nil
        end

        # 共有ヘルパ: 現在の設定からページサイズ（文字列: mm/pt）を取得
        def page_size_strings_from_config
          page_cfg = (Common::CONFIG['page'] || {})
          Common.resolve_page_size(page_cfg)
        rescue
          ['182mm', '257mm'] # B5 既定
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
          if w_pt <= 0 || h_pt <= 0
            w_pt = 182.0 * mm_to_pt
            h_pt = 257.0 * mm_to_pt
          end
          [w_pt, h_pt]
        rescue
          mm_to_pt = 72.0 / 25.4
          [182.0 * mm_to_pt, 257.0 * mm_to_pt]
        end

        # qpdf で「本文+付録（先頭〜frontmatter直前）」と「末尾frontmatter」を抽出
        def split_pdf_chapters_then_frontmatter(output_pdf, frontmatter_pages, front_pdf, body_pdf)
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
          begin
            num = number.to_i
            css = File.read(css_path, encoding: 'utf-8')

            updated_css = css.dup
            # counter-reset: chapter-counter XX;
            updated_css = updated_css.gsub(/(counter-reset:\s*chapter-counter\s*)\d+(\s*;)/) do
              pre, post = $1, $2
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
          rescue => e
            Common.log_warn("CSS更新に失敗しました: #{css_path} (#{e})")
            false
          end
        end
      end
    end
  end
end
