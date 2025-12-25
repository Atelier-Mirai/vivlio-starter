# frozen_string_literal: true

module Vivlio
  module Starter
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
          Step = Struct.new(:label, :handler)

          attr_reader :timings, :mode, :targets, :generated_pdf_name

          def initialize(command, keep: nil, targets: [], mode: :full)
            @command = command
            @keep = keep
            @targets = targets
            @mode = mode
            @options = command.options
            @timings = []
            @steps = []
            @generated_pdf_name = nil
            register_steps
          end

          # 登録済みステップを順に実行し、経過時間を収集する
          def run
            Common.reset_vivliostyle_build_timings
            @steps.each do |step|
              execute(step)
            end
            timings
          end

          private

          attr_reader :command, :keep, :options

          # モードに応じたステップを登録する
          def register_steps
            if mode == :single
              register_single_mode_steps
            else
              register_full_mode_steps
            end
          end

          # full mode: 全ステップを実行
          def register_full_mode_steps
            add_step('Step  1 (clean)',                       -> { run_step1_clean })
            add_step('Step  2 (optimize images)',             -> { run_step2_optimize_images })
            add_step('Step  3 (prepare theme images)',        -> { Build::ImageOptimizer.prepare_theme_images! })
            add_step('Step  4 (build sections html)',         -> { Build::SectionBuilder.build_sections_html!(keep) })
            # Step 5 は single mode 専用のため full mode ではスキップ
            add_step('Step  6 (generate toc and pdf)',        -> { Build::TocGenerator.generate_toc_and_pdf!('.', keep) })
            add_step('Step  7 (build overall pdf and split)', -> {
              Common.log_info('[Step 7] 全体PDF生成 → toc(目次)とsections(本文+付録+後書き)に分割')
              Build::PdfBuilder.build_overall_pdf_and_split_from_dir!('.', keep)
            })
            add_step('Step  8 (build _preface_toc.pdf)',       -> { Build::PdfBuilder.build_frontmatter_pdf!(keep) })
            add_step('Step  9 (build front pages and tail)',  -> { run_step9_front_pages_and_tail })
            add_step('Step 10 (merge all pdfs with outline)', -> { Build::PdfMerger.merge_all_pdfs_only!(keep) })
            add_step('Step 11 (apply outline to output pdf)', -> { Build::PdfMerger.add_outline_to_output_pdf!(keep) })
            add_step('Step 12 (compress pdf)',                -> { run_step12_compress_pdf })
            add_step('Step 13 (rename output pdfs)',          -> { Build::PdfFinalizer.rename_output_pdfs! })
            add_step('Step 14 (final clean)',                 -> { run_step14_final_clean })
          end

          # single mode: 対象章のみビルド + entries.js + pdf
          def register_single_mode_steps
            add_step('Step  1 (clean)',                -> { run_step1_clean })
            add_step('Step  2 (optimize images)',      -> { run_step2_optimize_images })
            add_step('Step  3 (prepare theme images)', -> { Build::ImageOptimizer.prepare_theme_images! })
            add_step('Step  4 (build sections html)',  -> { build_target_sections_html })
            add_step('Step  5 (entries.js + pdf)',     -> { generate_entries_and_pdf })
            add_step('Step 13 (rename output pdfs)',   -> { rename_single_mode_pdf })
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
          def run_step1_clean
            if options[:clean] == false
              Common.log_action('[Step 1] クリーンアップをスキップします（--no-clean）')
            else
              Common.log_action('[Step 1] クリーンアップを実行します…')
              CleanCommands.execute_clean({})
            end
          end

          # 画像最適化をプリセット付きで実行する
          def run_step2_optimize_images
            if options[:resize] == false
              Common.log_action('[Step 2] 画像最適化をスキップします（--no-resize）')
              return
            end

            if options.values_at(:high, :low).count(true) > 1
              Common.log_warn('[Step 2] --high と --low が同時指定されています。--high を優先します')
            end
            preset = %i[high low].find { |k| options[k] } || :medium
            Build::ImageOptimizer.optimize_images!(preset)
          end

          # single mode: 対象章のみ HTML をビルド
          def build_target_sections_html
            Common.log_action("[Step 4] 対象章をビルドします: #{targets.join(', ')}")
            targets.each do |target|
              %w[pre_process convert post_process].each do |task|
                case task
                when 'pre_process'
                  PreProcessCommands.execute_pre_process({}, [target])
                when 'convert'
                  ConvertCommands.execute_convert({}, [target])
                when 'post_process'
                  PostProcessCommands.execute_post_process({}, [target])
                end
              end
            end
          end

          # single mode: entries.js を生成して PDF をビルド
          def generate_entries_and_pdf
            Common.log_action('[Step 5] entries.js を生成して PDF をビルドします…')
            # 対象章のみを含む entries.js を生成
            EntriesCommands.execute_entries({}, targets)
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
            Common.log_success("[Step 13] PDFをリネームしました: #{@generated_pdf_name}")
          end

          # single mode の出力 PDF 名を決定する
          def determine_single_mode_pdf_name
            if targets.size == 1
              # 単一章: 54.pdf
              "#{targets.first}.pdf"
            else
              # 複数章: 54-56.pdf（最初と最後の章番号）
              sorted = targets.sort_by { |t| t[/^(\d+)/, 1].to_i }
              first_num = sorted.first[/^(\d+)/, 1]
              last_num = sorted.last[/^(\d+)/, 1]
              "#{first_num}-#{last_num}.pdf"
            end
          end

          # タイトル・リーガルページなど front/tail PDF を生成する
          def run_step9_front_pages_and_tail
            # 新仕様: 内部 basename 方式
            title_md    = File.join(Common::CONTENTS_DIR, '_titlepage.md')
            legal_md    = File.join(Common::CONTENTS_DIR, '_legalpage.md')
            colophon_md = File.join(Common::CONTENTS_DIR, '_colophon.md')
            book_yml    = File.join('config', 'book.yml')
            front_pdf   = '_titlepage_legalpage.pdf'
            col_pdf     = '_colophon.pdf'

            newer_than_any = lambda do |target, sources|
              return true unless File.exist?(target)

              target_mtime = safe_mtime(target)
              Array(sources).any? { |s| File.exist?(s) && File.mtime(s) > target_mtime }
            end

            force = options[:force]

            # 特殊ページが存在しない場合は自動生成
            ensure_special_page_exists!('titlepage', title_md)
            ensure_special_page_exists!('legalpage', legal_md)
            ensure_special_page_exists!('colophon', colophon_md)

            if force || newer_than_any.call(front_pdf, [title_md, legal_md, book_yml])
              [['create:titlepage', title_md], ['create:legalpage', legal_md]].each do |cmd, _path|
                case cmd
                when 'create:titlepage'
                  CreateCommands.execute_titlepage({ options: { force: true } })
                when 'create:legalpage'
                  CreateCommands.execute_legalpage({ options: { force: true } })
                end
              end
            end

            if force || newer_than_any.call(col_pdf, [colophon_md, book_yml])
              CreateCommands.execute_colophon({ options: { force: true } })
            end

            Build::PdfBuilder.build_front_pages_and_tail!(force)
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

          # MTime 取得時の例外を吸収して 0 時刻にフォールバックする
          def safe_mtime(path)
            File.mtime(path)
          rescue StandardError
            Time.at(0)
          end

          # 必要に応じて生成済みPDFを圧縮する
          def run_step12_compress_pdf
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
          def run_step14_final_clean
            if options[:clean] == false
              Common.log_action('[Step 14] クリーンアップをスキップします（--no-clean）')
            else
              Common.log_action('[Step 14] 中間生成物をクリーンアップします…')
              CleanCommands.execute_clean({})
            end
          end
        end
      end
    end
  end
end
