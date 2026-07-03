# frozen_string_literal: true

require 'digest'
require 'tmpdir'

require_relative 'backlink_dedup_orchestrator'
require_relative 'epub_builder'
require_relative 'epub_flow'
require_relative 'print_pdf_builder'
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

        attr_reader :timings, :mode, :entries, :generated_pdf_name, :targets

        # @param command [Samovar::Command] ビルドコマンドインスタンス
        # @param entries [Array<TokenResolver::Entry>] ビルド対象の Entry 配列
        # @param mode [:full, :single] ビルドモード
        # @param targets [Build::Targets, nil] 出力ターゲット（省略時は book.yml から 1 回だけ解決）。
        #   ビルド中は不変（ターゲット集合はビルド開始時に確定し、reload には追従しない）。
        def initialize(command, entries: [], mode: :full, targets: nil)
          @command = command
          @entries = Array(entries)
          @mode = mode
          @options = command.options
          @targets = targets || Build::Targets.resolve
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

        # full mode: 1 枚の宣言的ステップ表を上から評価して登録する。
        # 従来の 5 分岐＋3 補助メソッドを、行ごとの実行条件（targets 依存）を持つ
        # 1 テーブルへ畳んだ（課題 A: 分岐爆発・番号矛盾の解消）。ステップ番号は撤去し、
        # 安定したラベル名をログ・計時・ドキュメントの共通語彙とする。
        def register_full_mode_steps
          full_mode_step_table.each do |label, handler, enabled|
            add_step(label, handler) if enabled
          end
        end

        # full mode のステップ表。各行 = [ラベル, ハンドラ, 実行条件]。
        # 条件はビルド開始時に確定した targets から評価した真偽値（ビルド中は不変）。
        # 分岐はこの条件列に吸収され、経路の組み合わせは表を上から評価するだけで一意に定まる。
        def full_mode_step_table
          t = targets
          [
            # --- 共通prep（HTML 生成まで・無条件） ---
            ['clean',                     -> { run_step0_clean },                                     true],
            ['optimize images',           -> { run_step1_optimize_images },                           true],
            ['prepare theme images',      -> { Build::ImageOptimizer.prepare_theme_images! },         true],
            ['preprocess sections',       -> { Build::SectionBuilder.preprocess_sections!(entries) }, true],
            ['index scan and build',      -> { run_step4_index_processing },                          true],
            ['convert sections html',     -> { Build::SectionBuilder.convert_sections_html!(entries) }, true],
            ['generate part title pages', -> { Build::PartTitleGenerator.generate_all! },             true],
            ['techbook post-process',     -> { run_techbook_post_process },                           true],
            ['generate toc html',         -> { Build::TocGenerator.generate_toc_html!('.', entries) }, true],
            # --- toc 後: ターゲット依存（分岐は条件列に吸収） ---
            # 閲覧用 PDF は本文全体を、入稿用のみ経路は entries.js だけを生成する。
            ['build overall pdf',   -> { Build::PdfBuilder.build_overall_pdf_from_dir!('.', entries) }, t.pdf],
            ['generate entries.js', -> { Build::PdfBuilder.generate_entries_for_sections!('.', entries) }, !t.pdf && t.print_pdf],
            # EPUB/Kindle かつ PDF も作る場合のみ、dedup 前の章 HTML を退避（⑦: EPUB を dedup から隔離）。
            ['snapshot pre-dedup html for epub', -> { epub_flow.snapshot_pre_dedup! }, t.epub_or_kindle? && t.any_pdf?],
            ['backlink dedup',      -> { Build::BacklinkDedupOrchestrator.run!(entries) }, t.any_pdf?],
            # 前付・奥付: PDF 経路は PDF まで、それ以外（入稿用のみ／EPUB のみ）は HTML のみ。
            ['build front pages and tail', -> { run_step9_front_pages_and_tail },  t.pdf],
            ['build front pages html',     -> { run_step9_front_pages_html_only }, !t.pdf],
            ['merge all pdfs',             -> { Build::PdfMerger.merge_all_pdfs!(entries) },        t.pdf],
            ['apply outline to output pdf', -> { Build::PdfMerger.add_outline_to_output_pdf!(entries) }, t.pdf],
            # --- 終端: リネーム／入稿用／EPUB／クリーンアップ ---
            # 閲覧用 PDF 単独はリネーム＋圧縮＋クリーンを一括。他ターゲット併存時はリネームのみで
            # クリーンを最後へ延期（HTML を後段の入稿用・EPUB が再利用するため）。
            ['compress, rename and final clean', -> { run_step12_rename_and_clean }, t.pdf && !t.print_pdf && !t.epub_or_kindle?],
            ['rename',       -> { run_step12_rename_only }, t.pdf && (t.print_pdf || t.epub_or_kindle?)],
            ['print pdf',    -> { Build::PrintPdfBuilder.new(entries).build! }, t.print_pdf],
            ['generate epub', -> { epub_flow.run! },        t.epub_or_kindle?],
            # 閲覧用 PDF 単独以外は、末尾で明示的にクリーンアップする。
            ['final clean',  -> { run_final_clean },        t.print_pdf || t.epub_or_kindle? || !t.pdf]
          ]
        end

        # preflight mode: Step 1〜4 のみ実行（HTML変換・PDF生成なし）
        # build 側の Step 1〜4 変更が自動追従するよう、既存メソッドを直接呼ぶ
        def register_preflight_steps
          [
            ['optimize images',      -> { run_step1_optimize_images }],
            ['prepare theme images', -> { Build::ImageOptimizer.prepare_theme_images! }],
            ['preprocess sections',  -> { Build::SectionBuilder.preprocess_sections!(entries) }],
            ['index scan and build', -> { run_step4_index_processing }]
          ].each { |label, handler| add_step(label, handler) }
        end

        # single mode は閲覧用 PDF のみ生成する（プレビュー・サンプル配布が主用途）。
        # print_pdf / EPUB / Kindle(KPF) は入稿・配信を前提とした全章成果物なので、
        # 単章では作らず全章 `vs build` 専用とする（中途半端な出力を避け、負担も抑える）。
        def register_single_mode_steps
          warn_single_mode_pdf_only

          add_step('clean',                -> { run_step0_clean })
          add_step('optimize images',      -> { run_step1_optimize_images })
          add_step('prepare theme images', -> { Build::ImageOptimizer.prepare_theme_images! })
          add_step('build sections html',  -> { build_target_sections_html })
          add_step('entries.js + pdf',     -> { generate_entries_and_pdf })
          add_step('rename output pdfs',   -> { rename_single_mode_pdf })
          add_step('final clean',          -> { run_final_clean })
        end

        # targets に PDF 以外（print_pdf / EPUB / Kindle）が含まれていても、
        # 単章ビルドは閲覧用 PDF のみ生成する旨を一度だけ案内する。
        def warn_single_mode_pdf_only
          return unless targets.print_pdf || targets.epub_or_kindle?

          Common.log_info('単章ビルドは閲覧用 PDF のみ生成します（print_pdf / EPUB / Kindle は全章 `vs build` で生成してください）')
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
            Common.log_action('[clean] クリーンアップをスキップします（--no-clean）')
          else
            Common.log_action('[clean] クリーンアップを実行します…')
            CleanCommands.execute_clean({})
          end
        end

        # 画像最適化をプリセット付きで実行する
        def run_step1_optimize_images
          if options[:resize] == false
            Common.log_action('[optimize images] 画像最適化をスキップします（--no-resize）')
            return
          end

          if options.values_at(:high, :low).count(true) > 1
            Common.log_warn('[optimize images] --high と --low が同時指定されています。--high を優先します')
          end
          preset = %i[high low].find { |k| options[k] } || :medium
          Build::ImageOptimizer.optimize_images!(preset)
        end

        # single mode: 対象章のみ HTML をビルド
        def build_target_sections_html
          Common.log_action("[build sections html] 対象章をビルドします: #{basenames.join(', ')}")
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
          Common.log_action('[entries.js + pdf] entries.js を生成して PDF をビルドします…')
          # 対象章のみを含む entries.js を生成
          EntriesCommands.execute_entries({}, entries)
          # PDF を生成
          PdfCommands.execute_pdf({})
        end

        # single mode: 出力 PDF を章名にリネーム（54.pdf または 54-56.pdf）
        def rename_single_mode_pdf
          output_pdf = PdfCommands::PdfCommandRunner::DEFAULT_OUTPUT_PDF

          unless File.exist?(output_pdf)
            Common.log_warn("出力PDFが見つかりません: #{output_pdf}")
            return
          end

          # 出力ファイル名を決定（54.pdf または 54-56.pdf）
          @generated_pdf_name = determine_single_mode_pdf_name
          FileUtils.rm_f(@generated_pdf_name)
          FileUtils.mv(output_pdf, @generated_pdf_name)
          Common.log_success("[rename output pdfs] PDFをリネームしました: #{@generated_pdf_name}")
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

          Common.log_success('[build front pages html] 前付・奥付 HTML を生成しました（PDF ビルドはスキップ）')
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
            Common.log_action("[compress] PDF圧縮をスキップします（#{source}）")
          end
        end

        # 圧縮設定を判定（オプション優先、次に book.yml）
        def determine_compress_setting
          # --compress または --no-compress が明示的に指定されている場合はそれを優先
          return options[:compress] unless options[:compress].nil?

          # オプション未指定の場合は book.yml の output.pdf.compress を参照（デフォルト: false）
          # （従来はレガシーの pdf.compress を読んでおり、正規キーが効いていなかった）
          Common.pdf_compress?
        end

        # 圧縮設定のソース（ログ用）
        def compress_setting_source
          unless options[:compress].nil?
            return options[:compress] ? '--compress オプション' : '--no-compress オプション'
          end

          case Common::CONFIG.output.pdf.compress
          in true then 'book.yml: output.pdf.compress = true'
          in false then 'book.yml: output.pdf.compress = false'
          else 'デフォルト設定 (compress: false)'
          end
        end

        # 最終的なクリーン処理を担当する
        def run_final_clean
          if options[:clean] == false
            Common.log_action('[final clean] クリーンアップをスキップします（--no-clean）')
          else
            Common.log_action('[final clean] 中間生成物をクリーンアップします…')
            # 単章ビルドで生成した最終 PDF がクリーン対象パターンに含まれる場合があるため、
            # 一時退避してからクリーンし、復元する
            pdf_to_protect = @generated_pdf_name
            tmp_path = pdf_to_protect && File.exist?(pdf_to_protect) ? "#{pdf_to_protect}.keep" : nil
            FileUtils.mv(pdf_to_protect, tmp_path) if tmp_path
            CleanCommands.execute_clean({})
            FileUtils.mv(tmp_path, pdf_to_protect) if tmp_path
          end
        end

        # EPUB / Kindle ビルドのオーケストレーションは Build::EpubFlow へ移設済み（P2）。
        # dedup 隔離のスナップショットを 2 ステップ間で共有するため、同一インスタンスを使い回す。
        def epub_flow
          @epub_flow ||= Build::EpubFlow.new(entries, targets, options)
        end

        # Techbook モード: SVG→WebP 参照書き換え + 絵文字差し替え + CSS 注入
        # techbook: true でない場合は何もしない（Processor 内部で判定）
        def run_techbook_post_process
          Techbook::Processor.new(Common::CONFIG).post_process_html_files!
        end

        # Step 4: 索引処理を実行
        def run_step4_index_processing
          unless IndexCommands.index_enabled?
            Common.log_action('[index scan and build] 索引・用語集機能が無効のためスキップします（book.yml: index_glossary.enabled = false）')
            return
          end

          Common.log_action('[index scan and build] 索引語のスキャンと索引ページ生成を実行します…')

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
