# frozen_string_literal: true

require 'digest'
require 'tmpdir'

require_relative 'backlink_dedup_orchestrator'
require_relative 'epub_builder'
require_relative '../cover'
require_relative 'nombre_stamper'
require_relative 'part_title_generator'
require_relative '../techbook/processor'

module VivlioStarter
  module CLI
    module BuildCommands
      # ------------------------------------------------
      # UnifiedBuildPipeline: フル/単章ビルド統合パイプライン
      # ------------------------------------------------
      # - BuildCommands#build から利用し、各 Step の処理と計時を一元管理する。
      # - mode: :full（全章ビルド）または :single（単章/複数章ビルド）
      # - single mode では Step 6〜12, 14 をスキップし、Step 5 で entries.js + pdf を生成
      # ------------------------------------------------
      class UnifiedBuildPipeline
        Step = Data.define(:label, :handler)

        attr_reader :timings, :mode, :entries, :generated_pdf_name

        # @param command [Samovar::Command] ビルドコマンドインスタンス
        # @param entries [Array<TokenResolver::Entry>] ビルド対象の Entry 配列
        # @param mode [:full, :single] ビルドモード
        def initialize(command, entries: [], mode: :full)
          @command = command
          @entries = Array(entries)
          @mode = mode
          @options = command.options
          @timings = []
          @steps = []
          @generated_pdf_name = nil
          register_steps
        end

        # 登録済みステップを順に実行し、経過時間を収集する
        def run
          ensure_entry_files_exist!
          Common.reset_vivliostyle_build_timings
          @steps.each do |step|
            execute(step)
          end
          timings
        end

        private

        attr_reader :command, :options

        # catalog.yml に記載があるのに contents/ に原稿が存在しない場合、
        # 並列前処理のスレッド内で Errno::ENOENT が発生し、著者には
        # 長いスタックトレースしか見えない。ビルド開始前に検証し、
        # 原因と対処を示した上で速やかに終了する。
        def ensure_entry_files_exist!
          missing = entries.reject(&:exists?)
          return if missing.empty?

          Common.log_error('config/catalog.yml に記載されている章ファイルが contents/ に見つかりません:')
          missing.each { Common.log_error("  - contents/#{it.basename}.md") }
          Common.log_error('原稿を削除した場合は、config/catalog.yml から該当する行も削除してください。')
          Common.log_error('（vs delete <章番号> を使うと、原稿・画像・catalog.yml をまとめて削除できます）')
          exit 1
        end

        # Entry 配列から basename 配列を取得
        # @return [Array<String>] basename 配列
        def basenames
          @basenames ||= entries.map(&:basename)
        end

        # モードに応じたステップを登録する
        def register_steps
          case mode
          in :single    then register_single_mode_steps
          in :preflight then register_preflight_steps
          in _          then register_full_mode_steps
          end
        end

        # full mode: 全ステップを実行
        # ビルドパイプライン概要:
        #   Step  0-2:  準備（クリーン、画像最適化）
        #   Step  3:    Markdown前処理（frontmatter付加、画像パス修正）
        #   Step  4:    索引スキャン・索引ページ生成
        #   Step  5:    Markdown→HTML変換
        #   Step  6:    目次生成
        #   Step  7:    全体PDF生成（前書き+目次+本文+付録+後書き+索引）
        #   Step  8:    バックリンク重複排除
        #   Step  9:    表紙・奥付PDF生成
        #   Step 10:    PDF結合
        #   Step 11:    アウトライン付与
        #   Step 12:    リネーム・クリーンアップ
        #   Step 13:    入稿用PDF生成（print_pdf ターゲット時のみ）
        #   Step E:     EPUB生成（epub ターゲット時のみ）
        def register_full_mode_steps
          # 共通ステップ（HTML 生成まで）
          register_common_prep_steps

          if pdf_target? && print_pdf_target?
            # --- 閲覧用 + 入稿用の両方 ---
            register_pdf_build_steps
            # Step 12 ではリネーム・圧縮のみ。クリーンアップは最後に延期
            add_step('Step 12 (rename)',                      -> { run_step12_rename_only })
            add_step('Step 13 (print pdf)',                   -> { run_step13_print_pdf })
            # EPUB ターゲット時は EPUB → final clean の順
            add_step('Step E (generate epub)', -> { run_step_epub }) if epub_target?
            add_step('Step 14 (final clean)', -> { run_final_clean })
          elsif print_pdf_target?
            # --- 入稿用のみ（閲覧用 PDF をスキップ） ---
            register_print_pdf_only_steps_with_epub
          elsif epub_target? && !pdf_target?
            # --- EPUB のみ（PDF ビルドをスキップ） ---
            register_epub_only_steps
          elsif epub_target?
            # --- 閲覧用 + EPUB ---
            # クリーンアップは EPUB ビルド後に延期（HTML を保持するため）
            register_pdf_build_steps
            add_step('Step 12 (rename)',                      -> { run_step12_rename_only })
            add_step('Step E (generate epub)',                -> { run_step_epub })
            add_step('Step F (final clean)',                  -> { run_final_clean })
          else
            # --- 閲覧用のみ（従来どおり） ---
            register_pdf_build_steps
            add_step('Step 12 (compress, rename and final clean)', -> { run_step12_rename_and_clean })
          end
        end

        # preflight mode: Step 1〜4 のみ実行（HTML変換・PDF生成なし）
        # build 側の Step 1〜4 変更が自動追従するよう、既存メソッドを直接呼ぶ
        def register_preflight_steps
          [
            ['Step  1 (optimize images)',      -> { run_step1_optimize_images }],
            ['Step  2 (prepare theme images)', -> { Build::ImageOptimizer.prepare_theme_images! }],
            ['Step  3 (preprocess sections)',  -> { Build::SectionBuilder.preprocess_sections!(entries) }],
            ['Step  4 (index scan and build)', -> { run_step4_index_processing }]
          ].each { |label, handler| add_step(label, handler) }
        end

        # Steps 0-5: HTML 生成までの共通ステップ
        def register_common_prep_steps
          add_step('Step  0 (clean)',                       -> { run_step0_clean })
          add_step('Step  1 (optimize images)',             -> { run_step1_optimize_images })
          add_step('Step  2 (prepare theme images)',        -> { Build::ImageOptimizer.prepare_theme_images! })
          add_step('Step  3 (preprocess sections)',         lambda {
            Build::SectionBuilder.preprocess_sections!(entries)
          })
          add_step('Step  4 (index scan and build)',        -> { run_step4_index_processing })
          add_step('Step  5 (convert sections html)',       lambda {
            Build::SectionBuilder.convert_sections_html!(entries)
          })
          add_step('Step 5b (generate part title pages)', -> { Build::PartTitleGenerator.generate_all! })
          add_step('Step 5c (techbook post-process)', -> { run_techbook_post_process })
        end

        # Steps 6-11: 閲覧用 PDF のビルド・結合・アウトライン
        def register_pdf_build_steps
          add_step('Step  6 (generate toc and pdf)', lambda {
            Build::TocGenerator.generate_toc_and_pdf!('.', entries)
          })
          add_step('Step  7 (build overall pdf)', lambda {
            Build::PdfBuilder.build_overall_pdf_from_dir!('.', entries)
          })
          add_step('Step  8 (backlink dedup)',              -> { Build::BacklinkDedupOrchestrator.run!(entries) })
          add_step('Step  9 (build front pages and tail)',  -> { run_step9_front_pages_and_tail })
          add_step('Step 10 (merge all pdfs)',              -> { Build::PdfMerger.merge_all_pdfs!(entries) })
          add_step('Step 11 (apply outline to output pdf)', lambda {
            Build::PdfMerger.add_outline_to_output_pdf!(entries)
          })
        end

        # print_pdf のみ（+ 任意で epub）: 閲覧用 PDF ビルドをスキップし、
        # entries.js / HTML 生成のみ行ってから入稿用 PDF を生成する。
        # epub ターゲットがある場合は入稿用 PDF の後に EPUB を生成し、最後にクリーンアップする。
        def register_print_pdf_only_steps_with_epub
          add_step('Step  6 (generate toc html)',          lambda {
            Build::TocGenerator.generate_toc_html!('.', entries)
          })
          add_step('Step  7 (generate entries.js)', lambda {
            Build::PdfBuilder.generate_entries_for_sections!('.', entries)
          })
          add_step('Step  8 (backlink dedup)',             -> { Build::BacklinkDedupOrchestrator.run!(entries) })
          add_step('Step  9 (build front pages html)',     -> { run_step9_front_pages_html_only })
          add_step('Step 10 (print pdf)',                  -> { run_step13_print_pdf })
          add_step('Step E (generate epub)', -> { run_step_epub }) if epub_target?
          add_step('Step 11 (final clean)', -> { run_final_clean })
        end

        # single mode: targetsに応じてビルド方法を切り替え
        def register_single_mode_steps
          add_step('Step  0 (clean)',                -> { run_step0_clean })
          add_step('Step  1 (optimize images)',      -> { run_step1_optimize_images })
          add_step('Step  2 (prepare theme images)', -> { Build::ImageOptimizer.prepare_theme_images! })
          add_step('Step  3 (build sections html)',  -> { build_target_sections_html })

          if pdf_target?
            add_step('Step  4 (entries.js + pdf)',    -> { generate_entries_and_pdf })
            add_step('Step  5 (rename output pdfs)',  -> { rename_single_mode_pdf })
          end

          if print_pdf_target?
            add_step('Step  6 (generate entries js)', lambda {
              Build::PdfBuilder.generate_entries_for_sections!('.', entries)
            })
            add_step('Step  7 (print pdf)', -> { generate_single_mode_print_pdf })
          end

          add_step('Step E (generate epub)', -> { generate_single_mode_epub }) if epub_target?

          add_step('Step F (final clean)', -> { run_final_clean })
        end

        # ステップを記録して順次処理できるようにする
        def add_step(label, handler)
          @steps << Step.new(label, handler)
        end

        # 指定ステップを実行し、前後でタイマーを計測する
        def execute(step)
          start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          Common.log_action("[Timer] #{step.label} start")
          Common.with_current_step_label(step.label) do
            step.handler.call
          end
        ensure
          finish_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          elapsed = finish_time - start_time
          timings << [step.label, elapsed]
          Common.log_action("[Timer] #{step.label} finish: #{format('%.2f', elapsed)}s")
        end

        # クリーンオプションに応じて中間生成物を削除する
        def run_step0_clean
          if options[:clean] == false
            Common.log_action('[Step 0] クリーンアップをスキップします（--no-clean）')
          else
            Common.log_action('[Step 0] クリーンアップを実行します…')
            CleanCommands.execute_clean({})
          end
        end

        # 画像最適化をプリセット付きで実行する
        def run_step1_optimize_images
          if options[:resize] == false
            Common.log_action('[Step 1] 画像最適化をスキップします（--no-resize）')
            return
          end

          if options.values_at(:high, :low).count(true) > 1
            Common.log_warn('[Step 1] --high と --low が同時指定されています。--high を優先します')
          end
          preset = %i[high low].find { |k| options[k] } || :medium
          Build::ImageOptimizer.optimize_images!(preset)
        end

        # single mode: 対象章のみ HTML をビルド
        def build_target_sections_html
          Common.log_action("[Step 3] 対象章をビルドします: #{basenames.join(', ')}")
          entries.each do |entry|
            PreProcessCommands.execute_pre_process({}, [entry])
          end
          # 全章の前処理完了後に1回だけクロスリファレンス処理を実行する
          PreProcessCommands.execute_cross_references(entries)
          entries.each do |entry|
            ConvertCommands.execute_convert({}, [entry])
            PostProcessCommands.execute_post_process({}, [entry])
          end
        end

        # single mode: entries.js を生成して PDF をビルド
        def generate_entries_and_pdf
          Common.log_action('[Step 4] entries.js を生成して PDF をビルドします…')
          # 対象章のみを含む entries.js を生成
          EntriesCommands.execute_entries({}, entries)
          # PDF を生成
          PdfCommands.execute_pdf({})
        end

        # single mode: 出力 PDF を章名にリネーム（54.pdf または 54-56.pdf）
        def rename_single_mode_pdf
          pdf_config = Common::CONFIG['pdf'] || {}
          output_pdf = pdf_config['output_file'] || 'output.pdf'

          unless File.exist?(output_pdf)
            Common.log_warn("出力PDFが見つかりません: #{output_pdf}")
            return
          end

          # 出力ファイル名を決定（54.pdf または 54-56.pdf）
          @generated_pdf_name = determine_single_mode_pdf_name
          FileUtils.rm_f(@generated_pdf_name)
          FileUtils.mv(output_pdf, @generated_pdf_name)
          Common.log_success("[Step 5] PDFをリネームしました: #{@generated_pdf_name}")
        end

        # single mode: 単章EPUB生成
        def generate_single_mode_epub
          Common.log_action('[Step E] 単章 EPUB を生成します…')

          # --- Phase: EPUB 用カバー画像生成 ---
          generate_epub_cover_if_needed

          # --- Phase: EPUB 用 entries.js 生成 ---
          epub_htmls = Build::EpubBuilder.generate_epub_entries!('.', entries)
          if epub_htmls.empty?
            Common.log_warn('[Step E] EPUB 対象 HTML がありません。スキップします。')
            return
          end

          # --- Phase: EPUB 用 vivliostyle.config.js 生成 ---
          Build::EpubBuilder.generate_epub_config!

          # --- Phase: Vivliostyle build ---
          target_name = determine_single_mode_epub_name
          EpubCommands.execute_epub({}, target_name)

          # --- Phase: EPUB identifier 安定化 ---
          stabilize_epub_identifier!(target_name) if File.exist?(target_name)

          Common.log_success("[Step E] 単章 EPUB を生成しました: #{target_name}")
        end

        # single mode: 単章EPUB名を決定
        def determine_single_mode_epub_name
          if basenames.size == 1
            # 単一章: 01-life.epub
            "#{basenames.first}.epub"
          else
            # 複数章: 01-03.epub（最初と最後の章番号）
            sorted = basenames.sort_by { |bn| bn[/^(\d+)/, 1].to_i }
            first_num = sorted.first[/^(\d+)/, 1]
            last_num = sorted.last[/^(\d+)/, 1]
            "#{first_num}-#{last_num}.epub"
          end
        end

        # single mode: 単章入稿用PDF生成
        def generate_single_mode_print_pdf
          Common.log_action('[Step 5] 単章 入稿用 PDF を生成します…')

          # --- Phase: Vivliostyle build（トンボ・塗り足し付き） ---
          print_pdf_build_sections_for_single!

          # --- Phase: PDF 結合 ---
          print_pdf_merge_for_single!

          # --- Phase: 隠しノンブル書き込み ---
          print_pdf_stamp_nombre!

          # --- Phase: アウトライン付与 ---
          print_pdf_add_outline!

          # --- Phase: リネーム ---
          rename_single_mode_print_pdf!
        end

        # single mode: 単章本文の入稿用 PDF を生成
        def print_pdf_build_sections_for_single!
          Common.log_action('[Step 5] 単章 PDF をトンボ・塗り足し付きでビルドします…')
          PdfCommands.execute_print_pdf({}, '_sections_print.pdf')
        end

        # single mode: 単章入稿用 PDF を結合する
        def print_pdf_merge_for_single!
          files = %w[_sections_print.pdf]
          existing = files.select { File.exist?(it) }

          if existing.empty?
            Common.log_error('[Step 5] 結合対象の入稿用 PDF がありません')
            return
          end

          if Build::PdfMerger.merge_pdfs_with_qpdf!(existing, output: 'output_print.pdf')
            Common.log_success('[Step 5] 入稿用 PDF を結合しました')
          else
            Common.log_error('[Step 5] 入稿用 PDF の結合に失敗しました')
          end
        end

        # single mode: 単章入稿用PDFリネーム
        def rename_single_mode_print_pdf!
          return unless File.exist?('output_print.pdf')

          target_name = determine_single_mode_print_pdf_name
          return if target_name == 'output_print.pdf'

          FileUtils.rm_f(target_name)
          FileUtils.mv('output_print.pdf', target_name)
          Common.log_success("[Step 5] 単章 入稿用 PDF をリネームしました: output_print.pdf → #{target_name}")
        end

        # single mode: 単章入稿用PDF名を決定
        def determine_single_mode_print_pdf_name
          if basenames.size == 1
            # 単一章: 01-life_print.pdf
            "#{basenames.first}_print.pdf"
          else
            # 複数章: 01-03_print.pdf（最初と最後の章番号）
            sorted = basenames.sort_by { |bn| bn[/^(\d+)/, 1].to_i }
            first_num = sorted.first[/^(\d+)/, 1]
            last_num = sorted.last[/^(\d+)/, 1]
            "#{first_num}-#{last_num}_print.pdf"
          end
        end

        # single mode の出力 PDF 名を決定する
        def determine_single_mode_pdf_name
          if basenames.size == 1
            # 単一章: 54.pdf
            "#{basenames.first}.pdf"
          else
            # 複数章: 54-56.pdf（最初と最後の章番号）
            sorted = basenames.sort_by { |bn| bn[/^(\d+)/, 1].to_i }
            first_num = sorted.first[/^(\d+)/, 1]
            last_num = sorted.last[/^(\d+)/, 1]
            "#{first_num}-#{last_num}.pdf"
          end
        end

        # Step 9: タイトル・リーガルページなど front/tail PDF を生成する
        #
        # 設計方針: mtime 比較・キャッシュ判定は行わず、常に .md / HTML / PDF を再生成する。
        # 詳細は docs/specs/book_yml_regeneration_spec.md を参照。
        def run_step9_front_pages_and_tail
          # --- Phase: 特殊ページ .md を常に（強制）再生成 ---
          CreateCommands.execute_titlepage(force: true)
          CreateCommands.execute_legalpage(force: true)
          CreateCommands.execute_colophon(force: true)

          # --- Phase: HTML と PDF の再生成（PdfBuilder 内部で常時再生成） ---
          Build::PdfBuilder.build_front_pages_and_tail!
        end

        # Step 9 (print_pdf only): 前付・奥付の HTML 生成のみ（PDF ビルドをスキップ）
        # 入稿用 PDF は Step 13（print_pdf only 時は Step 10）で個別にビルドする
        def run_step9_front_pages_html_only
          title_md    = File.join(Common::CACHE_DIR, '_titlepage.md')
          legal_md    = File.join(Common::CACHE_DIR, '_legalpage.md')
          colophon_md = File.join(Common::CACHE_DIR, '_colophon.md')

          ensure_special_page_exists!('titlepage', title_md)
          ensure_special_page_exists!('legalpage', legal_md)
          ensure_special_page_exists!('colophon', colophon_md)

          CreateCommands.execute_titlepage({})
          CreateCommands.execute_legalpage({})
          CreateCommands.execute_colophon({})

          # HTML が生成されたことを確認
          Build::SectionBuilder.ensure_chapter_html_up_to_date!('_titlepage',
                                                                extra_sources: File.join('config', 'book.yml'))
          Build::SectionBuilder.ensure_chapter_html_up_to_date!('_legalpage',
                                                                extra_sources: File.join('config', 'book.yml'))
          Build::SectionBuilder.ensure_chapter_html_up_to_date!('_colophon',
                                                                extra_sources: File.join('config', 'book.yml'))

          special_html_files = %w[_titlepage _legalpage _colophon].map { "#{it}.html" }
          Techbook::Processor.new(Common::CONFIG).post_process_html_files!(special_html_files)

          Common.log_success('[Step 9] 前付・奥付 HTML を生成しました（PDF ビルドはスキップ）')
        end

        # 特殊ページが存在しない場合は自動生成
        def ensure_special_page_exists!(type, path)
          return if File.exist?(path)

          Common.log_info("#{type} が存在しないため自動生成します: #{path}")
          case type
          when 'titlepage'
            CreateCommands.execute_titlepage({})
          when 'legalpage'
            CreateCommands.execute_legalpage({})
          when 'colophon'
            CreateCommands.execute_colophon({})
          end
        end

        # Step 12: リネームと最終クリーンアップを実行
        def run_step12_rename_and_clean
          run_compress_pdf_if_needed
          Build::PdfFinalizer.rename_output_pdfs!
          run_final_clean
        end

        # Step 12 (print_pdf ターゲット時): リネーム・圧縮のみ。クリーンアップは Step 14 へ延期
        def run_step12_rename_only
          run_compress_pdf_if_needed
          Build::PdfFinalizer.rename_output_pdfs!
        end

        # 必要に応じて生成済みPDFを圧縮する
        def run_compress_pdf_if_needed
          should_compress = determine_compress_setting

          if should_compress
            Build::PdfFinalizer.compress_pdf!
          else
            source = compress_setting_source
            Common.log_action("[Step 12] PDF圧縮をスキップします（#{source}）")
          end
        end

        # 圧縮設定を判定（オプション優先、次に book.yml）
        def determine_compress_setting
          # --compress または --no-compress が明示的に指定されている場合はそれを優先
          return options[:compress] unless options[:compress].nil?

          # オプション未指定の場合は book.yml の pdf.compress を参照（デフォルト: false）
          config = Common::CONFIG
          pdf_config = config&.dig('pdf')
          pdf_config&.dig('compress') == true
        end

        # 圧縮設定のソース（ログ用）
        def compress_setting_source
          unless options[:compress].nil?
            return options[:compress] ? '--compress オプション' : '--no-compress オプション'
          end

          config = Common::CONFIG
          pdf_config = config&.dig('pdf')
          if pdf_config&.dig('compress') == true
            'book.yml: pdf.compress = true'
          elsif pdf_config&.dig('compress') == false
            'book.yml: pdf.compress = false'
          else
            'デフォルト設定 (compress: false)'
          end
        end

        # 最終的なクリーン処理を担当する
        def run_final_clean
          if options[:clean] == false
            Common.log_action('[Step 12] クリーンアップをスキップします（--no-clean）')
          else
            Common.log_action('[Step 12] 中間生成物をクリーンアップします…')
            # 単章ビルドで生成した最終 PDF がクリーン対象パターンに含まれる場合があるため、
            # 一時退避してからクリーンし、復元する
            pdf_to_protect = @generated_pdf_name
            tmp_path = pdf_to_protect && File.exist?(pdf_to_protect) ? "#{pdf_to_protect}.keep" : nil
            FileUtils.mv(pdf_to_protect, tmp_path) if tmp_path
            CleanCommands.execute_clean({})
            FileUtils.mv(tmp_path, pdf_to_protect) if tmp_path
          end
        end

        # ================================================================
        # Step 13: 入稿用 PDF 生成
        # ================================================================
        # output.targets に print_pdf が含まれる場合に実行。
        # 閲覧用ビルドで生成済みの HTML を再利用し、
        # --crop-marks --bleed 付きで vivliostyle build → PDF 結合 →
        # 隠しノンブル書き込み → アウトライン付与 → リネーム の一連を行う。
        # ================================================================

        # output.targets に pdf が含まれるかを判定する
        def pdf_target?
          cfg = Common::CONFIG
          targets = Build::PdfMerger.extract_targets(cfg.dig(:output, :targets))
          targets = Build::PdfMerger.extract_targets(cfg.dig(:output, :pdf, :targets)) if targets.empty?
          # targets 未指定時はデフォルトで pdf を生成
          return true if targets.empty?

          targets.include?('pdf')
        end

        # output.targets に print_pdf が含まれるかを判定する
        def print_pdf_target?
          cfg = Common::CONFIG
          targets = Build::PdfMerger.extract_targets(cfg.dig(:output, :targets))
          targets = Build::PdfMerger.extract_targets(cfg.dig(:output, :pdf, :targets)) if targets.empty?
          targets.include?('print_pdf')
        end

        # Step 13 のメインフロー
        def run_step13_print_pdf
          Common.log_action('[Step 13] 入稿用 PDF を生成します…')

          # --- Phase: カバー画像の生成 ---
          CoverCommands.ensure_cover_files_for_build!

          # --- Phase: Vivliostyle build（トンボ・塗り足し付き） ---
          print_pdf_build_sections!
          print_pdf_build_front_and_tail!

          # --- Phase: PDF 結合 ---
          print_pdf_merge!

          # --- Phase: 隠しノンブル書き込み ---
          print_pdf_stamp_nombre!

          # --- Phase: アウトライン付与 ---
          print_pdf_add_outline!

          # --- Phase: リネーム ---
          print_pdf_rename!
        end

        # 本文セクションの入稿用 PDF を生成（既存 entries.js を再利用）
        def print_pdf_build_sections!
          Common.log_action('[Step 13] 本文 PDF をトンボ・塗り足し付きでビルドします…')
          PdfCommands.execute_print_pdf({}, '_sections_print.pdf')
        end

        # 前付・奥付の入稿用 PDF を生成
        def print_pdf_build_front_and_tail!
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
        def print_pdf_merge!
          files = %w[_titlepage_legalpage_print.pdf _sections_print.pdf _colophon_print.pdf]
          existing = files.select { File.exist?(it) }

          if existing.empty?
            Common.log_error('[Step 13] 結合対象の入稿用 PDF がありません')
            return
          end

          # 奥付が偶数ページ（左ページ）に来るよう空白ページ挿入判定
          existing = Build::PdfMerger.insert_blank_page_before_colophon(existing)

          if Build::PdfMerger.merge_pdfs_with_qpdf!(existing, output: 'output_print.pdf')
            Common.log_success('[Step 13] output_print.pdf を生成しました')
          else
            Common.log_error('[Step 13] 入稿用 PDF 結合に失敗しました')
          end
        end

        # 隠しノンブルを書き込む
        def print_pdf_stamp_nombre!
          return unless File.exist?('output_print.pdf')

          bleed_mm = Build::NombreStamper.bleed_mm_from_config
          Build::NombreStamper.stamp!('output_print.pdf', bleed_mm:)
        end

        # 入稿用 PDF にアウトラインを付与する
        def print_pdf_add_outline!
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
        def print_pdf_rename!
          return unless File.exist?('output_print.pdf')

          target_name = Common.generate_print_pdf_filename
          return if target_name == 'output_print.pdf'

          FileUtils.rm_f(target_name)
          FileUtils.mv('output_print.pdf', target_name)
          Common.log_success("入稿用 PDF をリネームしました: output_print.pdf → #{target_name}")
        end

        # ================================================================
        # EPUB ビルド
        # ================================================================
        # output.targets に epub が含まれる場合に実行。
        # PDF ビルドで生成済みの HTML を再利用し、
        # EPUB 専用 entries / config を生成して vivliostyle build --format epub を実行する。
        # ================================================================

        # output.targets に epub が含まれるかを判定する
        def epub_target?
          cfg = Common::CONFIG
          targets = Build::PdfMerger.extract_targets(cfg.dig(:output, :targets))
          targets.include?('epub')
        end

        # EPUB のみビルド（PDF ビルドをスキップ）
        # 前付・奥付の HTML 生成は行うが、PDF 結合等はスキップ
        # Step 8 (backlink dedup) は vivliostyle preview が必要なため除外
        def register_epub_only_steps
          add_step('Step  6 (generate toc html)', lambda {
            Build::TocGenerator.generate_toc_html!('.', entries)
          })
          add_step('Step  9 (build front pages html)',     -> { run_step9_front_pages_html_only })
          add_step('Step E (generate epub)',               -> { run_step_epub })
          add_step('Step F (final clean)',                 -> { run_final_clean })
        end

        # EPUB ビルドのメインフロー
        def run_step_epub
          Common.log_action('[Step E] EPUB を生成します…')

          # --- Phase: EPUB 用カバー画像生成 ---
          generate_epub_cover_if_needed

          # --- Phase: EPUB 用 entries.js 生成 ---
          epub_htmls = Build::EpubBuilder.generate_epub_entries!('.', entries)
          if epub_htmls.empty?
            Common.log_warn('[Step E] EPUB 対象 HTML がありません。スキップします。')
            return
          end

          # --- Phase: EPUB 用 vivliostyle.config.js 生成 ---
          Build::EpubBuilder.generate_epub_config!

          # --- Phase: Vivliostyle build ---
          target_name = Common.generate_epub_filename
          EpubCommands.execute_epub({}, target_name)

          # --- Phase: EPUB identifier 安定化 ---
          stabilize_epub_identifier!(target_name) if File.exist?(target_name)

          # --- Phase: 中間ファイルクリーンアップ ---
          Build::EpubBuilder.cleanup!
        end

        # EPUB の dc:identifier を書籍固有の決定的な UUID に置換する。
        # プロジェクト名（config.project.name）が同一である限り、バージョンが変わっても
        # UUID が変化しないため、電子書籍ストアでの差し替えが容易になる。
        def stabilize_epub_identifier!(epub_path)
          stable_id = stable_project_uuid
          return unless stable_id

          abs_epub = File.expand_path(epub_path)

          Dir.mktmpdir('vs-epub-id') do |tmpdir|
            system('unzip', '-o', abs_epub, 'EPUB/content.opf', '-d', tmpdir,
                   out: File::NULL, err: File::NULL)
            opf_path = File.join(tmpdir, 'EPUB', 'content.opf')
            return unless File.exist?(opf_path)

            content = File.read(opf_path, encoding: 'UTF-8')
            replaced = content.sub(
              %r{(<dc:identifier\s+id="bookid">)urn:uuid:[0-9a-f-]+(</dc:identifier>)},
              "\\1#{stable_id}\\2"
            )

            if replaced == content
              Common.log_info('[EPUB] identifier は既に安定化済みです')
              return
            end

            File.write(opf_path, replaced)

            Dir.chdir(tmpdir) do
              system('zip', '-q', abs_epub, 'EPUB/content.opf',
                     out: File::NULL, err: File::NULL)
            end

            Common.log_info("[EPUB] identifier を安定化しました: #{stable_id}")
          end
        rescue StandardError => e
          Common.log_warn("[EPUB] identifier 安定化に失敗: #{e.message}")
        end

        # プロジェクト名から決定的に算出した UUID を urn:uuid: に載せて返す。
        # プロジェクト名が未設定の場合は book.main_title を fallback とし、
        # それでも空なら nil を返す。
        def stable_project_uuid
          project = Common::CONFIG.project
          book    = Common::CONFIG.book
          raw     = project&.name.to_s.strip
          fallback = [book&.main_title, book&.subtitle].compact.join(' ').strip
          base = raw.empty? ? fallback : raw
          base = base.to_s.strip
          return if base.empty?

          normalized = base.downcase
          hex = Digest::SHA1.hexdigest(normalized)
          uuid = [
            hex[0, 8],
            hex[8, 4],
            hex[12, 4],
            hex[16, 4],
            hex[20, 12]
          ].join('-')
          "urn:uuid:#{uuid}"
        end

        # EPUB 用カバー画像を生成（cover_{theme}.jpg が未生成の場合のみ）
        def generate_epub_cover_if_needed
          unless Common.validate_cover_settings
            Common.log_warn('[EPUB] カバー設定が無効なためカバー生成をスキップします')
            return
          end

          unless Common.epub_embed?
            Common.log_info('[EPUB] カバー埋め込みが無効なためスキップします')
            return
          end

          config = Common::CONFIG
          cover_path = Build::EpubBuilder.resolve_cover_image_path(config)

          if cover_path && File.exist?(cover_path)
            Common.log_info("[EPUB] カバー画像は既に存在します: #{cover_path}")
            return
          end

          Common.log_action('[EPUB] カバー画像を生成しています…')
          CoverCommands.ensure_cover_files_for_build!
        end

        # Techbook モード: SVG→WebP 参照書き換え + 絵文字差し替え + CSS 注入
        # techbook: true でない場合は何もしない（Processor 内部で判定）
        def run_techbook_post_process
          Techbook::Processor.new(Common::CONFIG).post_process_html_files!
        end

        # Step 4: 索引処理を実行
        def run_step4_index_processing
          unless IndexCommands.index_enabled?
            Common.log_action('[Step 4] 索引・用語集機能が無効のためスキップします（book.yml: index_glossary.enabled = false）')
            return
          end

          Common.log_action('[Step 4] 索引語のスキャンと索引ページ生成を実行します…')

          # 対象章を取得（Entry 配列から basename を抽出）
          chapter_targets = if entries.any?
                              basenames.sort
                            else
                              Dir[File.join(Common::CONTENTS_DIR, '*.md')]
                                .map { |p| File.basename(p, '.md') }
                                .reject { |bn| bn.start_with?('_') }
                                .sort
                            end

          IndexCommands.process_index_for_build!(chapter_targets)
        end
      end
    end
  end
end
