# frozen_string_literal: true

require 'rbconfig'
require 'fileutils'
require 'time'
require_relative 'post_process/heading_processor'

module Vivlio
  module Starter
    module CLI
      # ==============================================================================
      # Module: BuildCommands
      # ------------------------------------------------------------------------------
      # Vivlio Starter の統合ビルドコマンド群。
      # Rake タスクに依存しないビルド実行を Thor コマンドとして提供し、
      # 前処理→変換→後処理→目次生成→PDF 結合→圧縮→クリーンまでを一括実行する。
      #
      # 提供コマンド:
      #   - build [TOKENS...]
      #       書籍を統合ビルドする。TOKENS 指定時は指定対象のみ HTML 生成して終了。
      #
      # 主なオプション:
      #   --no-resize / --high / --medium / --low    画像最適化の制御・プリセット
      #   --no-compress                               PDF 圧縮をスキップ
      #   --no-clean                                  中間生成物のクリーンをスキップ
      #   --log[=level]                               ログレベル（error/warn/info/debug、無指定は info）
      #
      # 備考:
      #   - 処理は安全側で例外を握りつぶしつつ継続する（各 Step で警告ログ）。
      #   - PDF オープンは OS 判定を内部実装に委譲。
      # ==============================================================================
      module BuildCommands
        # ------------------------------------------------
        # FullBuildPipeline: フルビルド用ステップ実行クラス
        # ------------------------------------------------
        # - BuildCommands#build から利用し、各 Step の処理と計時を一元管理する。
        # - 既存の step ごとの条件分岐をメソッド単位に分割し、可読性を高める。
        # ------------------------------------------------
        class FullBuildPipeline
          Step = Struct.new(:label, :handler)

          attr_reader :timings

          def initialize(command, keep)
            @command = command
            @keep = keep
            @options = command.options
            @timings = []
            @steps = []
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

          # フルビルドの個別ステップを登録する
          def register_steps
            add_step('Step 0 (clean)',            -> { run_step0_clean })
            add_step('Step 1 (optimize images)', -> { run_step1_optimize_images })
            add_step('Step 2 (prepare theme images)', -> { BuildHelpers.prepare_theme_images! })
            add_step('Step 5 (build sections html)', -> { BuildHelpers.build_sections_html!(keep) })
            add_step('Step 6 (generate toc and pdf)', -> { BuildHelpers.generate_toc_and_pdf!('.', keep) })
            add_step('Step 7 (build overall pdf and split)', -> {
              Common.log_info('[Step 7] 全体PDF生成 → toc(目次)とsections(本文+付録+後書き)に分割')
              BuildHelpers.build_overall_pdf_and_split_from_dir!('.', keep)
            })
            add_step('Step 8 (build 02-03-front.pdf)', -> { BuildHelpers.build_frontmatter_pdf!(keep) })
            add_step('Step 9 (build front pages and tail)', -> { run_step9_front_pages_and_tail })
            add_step('Step 10 (merge all pdfs with outline)', -> { BuildHelpers.merge_all_pdfs_only!(keep) })
            add_step('Step 11 (apply outline to output pdf)', -> { BuildHelpers.add_outline_to_output_pdf!(keep) })
            add_step('Step 12 (compress pdf)', -> { run_step12_compress_pdf })
            add_step('Step 13 (rename output pdfs)', -> { BuildHelpers.rename_output_pdfs! })
            add_step('Step 14 (final clean)', -> { run_step14_final_clean })
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
              Vivlio::Starter::ThorCLI.start(['clean'])
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
            BuildHelpers.optimize_images!(preset)
          end

          # タイトル・リーガルページなど front/tail PDF を生成する
          def run_step9_front_pages_and_tail
            title_md    = File.join(Common::CONTENTS_DIR, '00-titlepage.md')
            legal_md    = File.join(Common::CONTENTS_DIR, '01-legalpage.md')
            colophon_md = File.join(Common::CONTENTS_DIR, '99-colophon.md')
            book_yml    = File.join('config', 'book.yml')
            front_pdf   = '00-01-front.pdf'
            col_pdf     = '99-colophon.pdf'

            newer_than_any = lambda do |target, sources|
              return true unless File.exist?(target)

              target_mtime = safe_mtime(target)
              Array(sources).any? { |s| File.exist?(s) && File.mtime(s) > target_mtime }
            end

            force = options[:force]
            if force || newer_than_any.call(front_pdf, [title_md, legal_md, book_yml])
              [['create:titlepage', title_md], ['create:legalpage', legal_md]].each do |cmd, _path|
                Vivlio::Starter::ThorCLI.start([cmd, '--force'])
              end
            end

            if force || newer_than_any.call(col_pdf, [colophon_md, book_yml])
              Vivlio::Starter::ThorCLI.start(['create:colophon', '--force'])
            end

            BuildHelpers.build_front_pages_and_tail!(force)
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
              BuildHelpers.compress_pdf!
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
              Vivlio::Starter::ThorCLI.start(['clean'])
            end
          end
        end

        # ------------------------------------------------
        # SingleChapterRunner: 指定チャプターの各ステップを順に実行
        # ------------------------------------------------
        # - pre_process → convert → post_process → entries → pdf を個別に実行
        # - PDF 生成後は output.pdf を <chapter>.pdf にリネームして返す
        # ------------------------------------------------
        class SingleChapterRunner
          attr_reader :command, :chapter, :timings

          def initialize(command, chapter)
            @command = command
            @chapter = chapter
            @generated_pdfs = []
            @timings = []
          end

          # 章向けの全ステップを順番に実行し、生成PDFを返す
          def run
            steps.each do |step_name, callable|
              duration = BuildHelpers.time_step_for_chapter(chapter, step_name) { callable.call }
              duration ||= 0.0
              timings << { step: step_name, duration: duration }
            end
            generated_pdfs.dup
          end

          private

          attr_reader :generated_pdfs

          # 章ごとに実行するステップ配列を返す
          def steps
            @steps ||= [
              ['pre_process', -> { run_thor_task('pre_process') }],
              ['convert',     -> { run_thor_task('convert') }],
              ['post_process',-> { run_thor_task('post_process') }],
              ['entries',     -> { run_thor_task('entries') }],
              ['pdf',         -> { generate_chapter_pdf }]
            ]
          end

          # Thor タスクをラップして呼び出す
          def run_thor_task(task)
            Vivlio::Starter::ThorCLI.start([task, chapter])
          end

          # output.pdf を章専用 PDF 名にリネームして配列に記録する
          def generate_chapter_pdf
            Vivlio::Starter::ThorCLI.start(['pdf'])
            pdf_config = Common::CONFIG['pdf'] || {}
            output_pdf = pdf_config['output_file'] || 'output.pdf'
            chapter_pdf = "#{chapter}.pdf"
            if File.exist?(output_pdf)
              FileUtils.rm_f(chapter_pdf)
              FileUtils.mv(output_pdf, chapter_pdf)
              Common.log_success("単章PDFを生成しました: #{chapter_pdf}")
              generated_pdfs << chapter_pdf
            else
              Common.log_warn("出力PDFが見つかりません: #{output_pdf}")
            end
          end
        end

        # ------------------------------------------------
        # SingleChapterMerger: 章ごとの PDF を結合し、必要なら圧縮
        # ------------------------------------------------
        class SingleChapterMerger
          attr_reader :command, :generated_pdfs

          def initialize(command, generated_pdfs)
            @command = command
            @generated_pdfs = Array(generated_pdfs)
          end

          # 章PDFの結合処理を実施し、成功可否を返す
          def apply
            return false unless merge_enabled? && generated_pdfs.any?

            merge_pdfs
          end

          private

          # --merge オプションが有効か判定する
          def merge_enabled?
            command.options[:merge]
          end

          # hexapdf を利用して章PDFを結合し、必要なら圧縮する
          def merge_pdfs
            Common.log_action('[Merge] 生成した章PDFを結合して output.pdf を作成します…')
            FileUtils.rm_f('output.pdf')
            cmd = ['bundle', 'exec', 'hexapdf', 'merge', *generated_pdfs, 'output.pdf'].join(' ')
            merged = system(cmd)
            if merged && File.exist?('output.pdf')
              Common.log_success('[Merge] output.pdf を生成しました')
              compress_if_needed
              rename_output_pdfs
              command.send(:open_pdf)
              true
            else
              Common.log_error('[Merge] PDF結合に失敗しました（output.pdf 未生成）')
              false
            end
          end

          # --no-compress 指定がない場合は圧縮処理を呼び出す
          def compress_if_needed
            return if command.options[:compress] == false

            Vivlio::Starter::ThorCLI.start(['pdf_compress'])
          end

          # 出力PDFを動的ファイル名にリネームする
          def rename_output_pdfs
            BuildHelpers.rename_output_pdfs!
          end
        end

        # ------------------------------------------------
        # SingleChapterOpener: 生成済みの最終PDFを1件だけ開く
        # ------------------------------------------------
        class SingleChapterOpener
          attr_reader :command, :generated_pdfs

          def initialize(command, generated_pdfs)
            @command = command
            @generated_pdfs = Array(generated_pdfs)
          end

          # 最後に生成された章PDFを一度だけ開く
          def open
            target = generated_pdfs.last
            return unless target

            begin
              command.send(:open_pdf, target)
            rescue StandardError
              # 失敗時も処理は継続
            end
          end
        end

        module_function

        BUILD_DESC = {
          build: {
            short: '書籍全体または指定章をビルドします',
            long: <<~DESC
              CLI から書籍のビルドを一括実行します。

              引数を指定しない場合は、画像最適化、本文/付録の HTML 生成、目次や frontmatter/後書きの生成、
              PDF 結合とアウトライン付与、圧縮、クリーンアップまでを順番に実行し、書籍全体の PDF を生成します。

              引数として章ベース名（例: 11-install 21-customize）を指定した場合は、その章だけを対象に
              必要な変換処理を実行して各章の PDF を生成します。オプションに応じて、生成した章 PDF の結合（--merge）
              や圧縮（--compress）も行えます。

              利用可能なオプションと既定値の詳細は、下記の「オプション」セクションを参照してください。
            DESC
          }
        }.freeze

        def included(base)
          base.class_eval do
            desc 'build [TARGETS...]', BUILD_DESC[:build][:short]
            long_desc BUILD_DESC[:build][:long]

            method_option :resize,   type: :boolean, default: true,  desc: '画像最適化を行う（--no-resize で無効）'
            method_option :high,     type: :boolean, default: false, desc: '画像最適化プリセット: 高品質'
            method_option :medium,   type: :boolean, default: false, desc: '画像最適化プリセット: 中品質'
            method_option :low,      type: :boolean, default: false, desc: '画像最適化プリセット: 低品質'
            method_option :compress, type: :boolean, default: nil,   desc: 'PDF圧縮を行う（--no-compress で無効、未指定時は book.yml の設定に従う）'
            method_option :clean,    type: :boolean, default: true,  desc: '中間生成物をクリーンアップ（--no-clean で無効）'
            method_option :dry_run,  type: :boolean, aliases: '-n',  desc: '実行せずにビルド予定のみを表示（試行）'
            method_option :merge,    type: :boolean, aliases: '-m',
                                     desc: '生成された各PDFを結合して出力（出力名: book.yml設定に基づく動的ファイル名）'
            method_option :log,      type: :string,  banner: '[level]', desc: 'ログレベルを指定（error/warn/info/debug）'
            method_option :force,    type: :boolean, default: false, desc: 'タイトル/リーガル/奥付を強制再生成（--no-cache のエイリアス）'
            method_option :'no-cache', type: :boolean, default: false, desc: 'キャッシュを無効化（--force と同義）'

            # ================================================================
            # Command: build（統合ビルドエントリポイント）
            # ------------------------------------------------
            # 概要:
            #   書籍のビルドを統合的に実行する。
            #   tokens 指定時は対象のみ HTML 生成（pre_process→convert→post_process→entries）
            #   を行い、完了後に PDF を一度だけ開いて終了。
            #
            # 入力:
            #   tokens    対象チャプター名の配列（例: 11-install 21-customize）
            #             未指定時はフルビルド（Step 0〜11）を実行。
            #
            # オプション:
            #   --no-resize / --high / --medium / --low
            #   --no-compress, --no-clean, --no-cache (--force と同義)
            #   --single_html
            #   --log[=level]（error/warn/info/debug、未指定は info）
            #
            # 注意:
            #   --log により Common.current_log_level を制御（既定 warn）。
            # ================================================================
            def build(*tokens)
              # --no-cache は --force のエイリアス（options は凍結される可能性があるため不変のまま扱う）
              force = options[:force] || options[:'no-cache'] ? true : false
              files = Common.normalize_tokens(tokens)
              # delete.rb と同様の規則でトークンを展開（数値/レンジ/拡張子→実在 .md ベース名）
              expanded_basenames = expand_tokens_to_targets(files)
              # Thor タスクに渡すトークンは拡張子なし
              expanded_tokens = expanded_basenames.map { |bn| bn.sub(/\.md\z/, '') }

              # 指定ターゲットのみ 単章/複数章ビルドを実行（pre_process → convert → post_process → entries → pdf → リネーム）
              if expanded_tokens.any?
                Common.log_action("単章/選択ビルドを実行します: #{expanded_tokens.join(', ')}")

                if options[:dry_run]
                  print_single_chapter_dry_run(expanded_tokens)
                  return
                end

                begin
                  # 章番号の表示用に、選択された章トークンの並びを HeadingProcessor に伝える
                  # これにより、vs build 54-56 のような範囲ビルド時に「第1章〜」として振り直される
                  PostProcessCommands::HeadingProcessor.chapter_tokens_override = expanded_tokens

                  Common.reset_vivliostyle_build_timings
                  generated_pdfs = []
                  timing_rows = []

                  expanded_tokens.each do |target|
                    runner = SingleChapterRunner.new(self, target)
                    chapter_pdfs = runner.run
                    generated_pdfs.concat(chapter_pdfs)
                    runner.timings.each do |entry|
                      label = "#{target} / #{entry[:step]}"
                      timing_rows << [label, entry[:duration].to_f]
                    end
                  end

                  vs_timings = Common.consume_vivliostyle_build_timings
                  vs_map = vs_timings.group_by { |entry| entry[:label].to_s }

                  if timing_rows.any?
                    total = timing_rows.map { |(_, dt)| dt }.inject(0.0, :+)
                    label_width = timing_rows.map { |(label, _)| label.length }.max || 0
                    label_width = [label_width, 'TOTAL'.length, 34].max
                    value_width = 7

                    Common.echo_always "\n== Build Step Timings =="
                    timing_rows.each do |label, dt|
                      value_text = format("%#{value_width}.2fs", dt)
                      label_text = format("%-#{label_width}s", label)
                      line = "  - #{label_text} #{value_text}"
                      Common.echo_always line

                      entries = vs_map[label]
                      next unless entries&.any?

                      value_start_idx = line.length - value_text.length
                      indent = ' ' * 4
                      sub_label = '(vivliostyle build)'

                      entries.each do |entry|
                        entry_value = format('(%.2fs)', entry[:duration])
                        extra_spaces = if entry[:duration] >= 100
                                         0
                                       elsif entry[:duration] >= 10
                                         1
                                       else
                                         2
                                       end

                        target_index = value_start_idx + extra_spaces
                        label_segment = format("%-#{label_width}s", sub_label)
                        base_prefix = "#{indent}#{label_segment} "

                        if base_prefix.length < target_index
                          base_prefix += ' ' * (target_index - base_prefix.length)
                        end

                        Common.echo_always("#{base_prefix}#{entry_value}")
                      end
                    end
                    Common.echo_always format("  = %-#{label_width}s %#{value_width}.2fs", 'TOTAL', total)
                    Common.echo_always "==========================\n"
                  end

                  handled = handle_single_chapter_merge(generated_pdfs)
                  open_last_generated_pdf(generated_pdfs) unless handled
                  return
                ensure
                  # 単章ビルドが終了したら、次回ビルドへの影響を避けるためオーバーライドを解除
                  PostProcessCommands::HeadingProcessor.chapter_tokens_override = nil
                end
              end

              # chapters 指定（keep）を取得（'all' または未設定は nil）
              keep = BuildHelpers.configured_chapters
              if keep&.any?
                Common.log_action("[Subset] 退避なしで論理的に対象を限定してビルドします: #{keep.inspect}")
              else
                Common.log_action("[Subset] chapters 設定なし/'all'のため、フルビルドします（退避なし）")
              end

              # ================================================================
              # Dry Run (Full build): 実処理を行わず予定のみを表示
              # ================================================================
              if options[:dry_run]
                Common.echo_always "\n== Dry Run: フルビルド予定 =="
                # 画像最適化の予定
                resize_desc = if options[:resize] == false
                                'スキップ'
                              else
                                preset = %i[high low].find { |k| options[k] } || :medium
                                "実行 (#{preset})"
                              end
                # 章リストを論理フィルタで算出（ファイル移動なし）
                begin
                  keep_numbers = BuildHelpers.chapter_numbers_for_book(keep)
                rescue StandardError
                  keep_numbers = nil
                end
                all_md_basenames = Dir.glob(File.join(Common::CONTENTS_DIR, '*.md')).map { |p| File.basename(p, '.md') }
                main_targets     = BuildHelpers.filter_basenames_by_range(all_md_basenames, 11..89, keep_numbers)
                appendix_targets = BuildHelpers.filter_basenames_by_range(all_md_basenames, 91..97, keep_numbers)
                Common.echo_always "  - 画像最適化: #{resize_desc}"
                Common.echo_always "  - 本文(11..89): #{main_targets.empty? ? '対象なし' : main_targets.join(', ')}"
                Common.echo_always "  - 付録(91..97): #{appendix_targets.empty? ? '対象なし' : appendix_targets.join(', ')}"
                Common.echo_always '  - TOC: 03-toc.html / 03-toc.pdf'
                Common.echo_always '  - 全体PDF: sections.pdf → 章/TOCに分割'
                Common.echo_always "  - PDF圧縮: #{options[:compress] == false ? 'スキップ' : '実行'}"
                Common.echo_always "  - クリーン: #{options[:clean] == false ? 'スキップ' : '実行'}"
                if options[:merge]
                  normal_name = Common.generate_output_filename('pdf')
                  compressed_name = Common.generate_compressed_pdf_filename('pdf')
                  Common.echo_always "  - 結合: #{normal_name}（圧縮有効時は #{compressed_name} も生成）"
                end
                Common.echo_always "\n計画のみを表示しました（dry-run、実処理は行いません）。"
                return
              end

              pipeline = FullBuildPipeline.new(self, keep)
              build_timings = pipeline.run

              # タイマーサマリー
              total = build_timings.map { |(_, dt)| dt }.inject(0.0, :+)
              label_width = build_timings.map { |(label, _)| label.to_s.length }.max || 0
              label_width = [label_width, 'TOTAL'.length, 34].max
              value_width = 7
              Common.echo_always "\n== Build Step Timings =="
              vs_timings = Common.consume_vivliostyle_build_timings
              vs_map = vs_timings.group_by { |entry| entry[:label].to_s }
              sub_label = '(vivliostyle build)'

              build_timings.each do |label, dt|
                raw_label = label.to_s
                display_label = raw_label.sub(/\AStep (\d)(?=\D)/, 'Step  \1')
                value_text = format("%#{value_width}.2fs", dt)
                label_text = format("%-#{label_width}s", display_label)
                line = "  - #{label_text} #{value_text}"
                Common.echo_always line

                entries = vs_map[raw_label]
                next unless entries&.any?

                value_start_idx = line.length - value_text.length
                indent = ' ' * 4

                entries.each do |entry|
                  entry_value = format("(%.2fs)", entry[:duration])
                  extra_spaces = if entry[:duration] >= 100
                                   0
                                 elsif entry[:duration] >= 10
                                   1
                                 else
                                   2
                                 end

                  target_index = value_start_idx + extra_spaces
                  label_segment = format("%-#{label_width}s", sub_label)
                  base_prefix = "#{indent}#{label_segment} "

                  if base_prefix.length < target_index
                    base_prefix += ' ' * (target_index - base_prefix.length)
                  end

                  Common.echo_always("#{base_prefix}#{entry_value}")
                end
              end
              Common.echo_always format("  = %-#{label_width}s %#{value_width}.2fs", 'TOTAL', total)
              Common.echo_always "==========================\n"
              outline_info = BuildHelpers.last_outline_debug_info
              if outline_info && Common.current_log_level >= 3
                Common.echo_always '-- Outline Debug Info --'
                outline_info[:items].each do |item|
                  next unless item[:chapter] && item[:text]

                  level_tag = case item[:level].to_i
                              when 1 then 'H1'
                              when 2 then 'H2'
                              when 3 then 'H3'
                              else "H#{item[:level]}"
                              end
                  Common.echo_always format('  %s / [%s] %s -> page %d', item[:chapter], level_tag, item[:text],
                                            item[:page])
                end
                chapter_ranges = outline_info[:chapter_ranges] || {}
                chapter_order  = outline_info[:chapter_order] || []
                if chapter_ranges.any?
                  Common.echo_always '-- Chapter Ranges --'
                  order = chapter_order.is_a?(Array) && !chapter_order.empty? ? chapter_order : chapter_ranges.keys.sort
                  order.each do |bn|
                    rng = chapter_ranges[bn]
                    next unless rng

                    Common.echo_always format('  %s %s %s', bn, rng[0] || '-', rng[1] || '-')
                  end
                end
              end

              # timings_summary.md の先頭に追記（新しいビルド結果をファイル先頭に）
              ts = Time.now.iso8601
              new_block = []
              new_block << "\n## Build Step Timings (#{ts})\n"
              new_block << "````\n"
              new_block << '== Build Step Timings =='
              build_timings.each do |label, dt|
                raw_label = label.to_s
                display_label = raw_label.sub(/\AStep (\d)(?=\D)/, 'Step  \1')
                value_text = format("%#{value_width}.2fs", dt)
                label_text = format("%-#{label_width}s", display_label)
                line = "  - #{label_text} #{value_text}"
                new_block << line

                entries = vs_map[raw_label]
                next unless entries&.any?

                paren_idx = line.index('(') || line.index(label.to_s.strip) || 4
                value_start_idx = line.length - value_text.length
                value_digit_idx = line.length - value_text.lstrip.length
                prefix_spaces = ' ' * paren_idx

                entries.each do |entry|
                  entry_value = format("(%.2fs)", entry[:duration])
                  label_segment = "#{prefix_spaces}#{sub_label}"
                  digit_column = value_digit_idx
                  target_length = [digit_column - 1, label_segment.length + 1].max
                  line_segment = label_segment.ljust(target_length)
                  new_block << "#{line_segment}#{entry_value}"
                end
              end
              new_block << format("  = %-#{label_width}s %#{value_width}.2fs", 'TOTAL', total)
              new_block << '```'

              path = File.join(Dir.pwd, 'timings_summary.md')
              previous = File.exist?(path) ? File.read(path, encoding: 'utf-8') : ''
              File.open(path, 'w', encoding: 'utf-8') do |f|
                f.write(new_block.join("\n"))
                f.write("\n")
                f.write(previous.to_s)
              end

              # 最後に1度だけPDFをオープン（OS判定は open_pdf 側に委譲）
              begin
                open_pdf
              rescue StandardError => _e
                # 失敗してもビルド完了は維持
              end

              Common.log_success('全ファイルのビルドが完了しました')
            end

            # ==============================================================================
            # Helper methods
            # ==============================================================================
            no_commands do
              # delete.rb のロジックを参照したトークン展開
              def list_contents_basenames
                Dir.glob(File.join(Common::CONTENTS_DIR, '*.md')).map { |p| File.basename(p) }
              end

              # ベース名から章番号部分だけを整数として取得する
              def chapter_number_from_basename(basename)
                (basename[/^(\d+)-/, 1] || nil)&.to_i
              end

              # 指定レンジに収まる章ベース名をフィルタリングして返す
              def find_basenames_in_range(from_num, to_num)
                a, b = [from_num.to_i, to_num.to_i].minmax
                list_contents_basenames.select do |bn|
                  n = chapter_number_from_basename(bn)
                  n && n >= a && n <= b
                end
              end

              # トークン1つを展開して対象ベース名の配列に変換する
              def expand_token_to_basenames(token)
                t = token.to_s.strip
                return [] if t.empty?
                return find_basenames_in_range(::Regexp.last_match(1), ::Regexp.last_match(2)) if t =~ /(\A\d+)-(\d+\z)/
                return list_contents_basenames.select { |bn| bn.start_with?("#{t}-") } if t =~ /\A\d+\z/

                # Support explicit basename with or without .md, optionally prefixed by contents/
                name = t.sub(%r{\A#{Regexp.escape(Common::CONTENTS_DIR)}/}, '')
                name = "#{name}.md" unless name.end_with?('.md')
                path = File.join(Common::CONTENTS_DIR, name)
                File.exist?(path) ? [name] : []
              end

              # トークン配列を章ベース名配列として重複なく取得する
              def expand_tokens_to_targets(tokens)
                Array(tokens).compact.flat_map { |tok| expand_token_to_basenames(tok) }.uniq
              end
            end

            private

            # 単章ビルド実行前の Dry Run 結果を整形して表示する
            def print_single_chapter_dry_run(tokens)
              Common.echo_always "\n== Dry Run: ビルド予定一覧 =="
              tokens.each do |t|
                Common.echo_always "  - 章: #{t} → 生成予定: #{t}.pdf"
              end
              if options[:merge]
                normal_name = Common.generate_output_filename('pdf')
                compressed_name = Common.generate_compressed_pdf_filename('pdf')
                Common.echo_always "  - 結合: #{normal_name}（圧縮有効時は #{compressed_name} も生成）"
              end
              Common.echo_always "\n合計 #{tokens.size} 章（dry-run、実処理は行いません）。"
            end

            # 単章向けパイプラインを実行し、生成PDF一覧を返す
            def run_single_chapter_pipeline(target)
              SingleChapterRunner.new(self, target).run
            end

            # 生成された章PDFの結合処理を委譲する
            def handle_single_chapter_merge(generated_pdfs)
              SingleChapterMerger.new(self, generated_pdfs).apply
            end

            # 結合を行わなかった場合に最後のPDFを開く
            def open_last_generated_pdf(generated_pdfs)
              SingleChapterOpener.new(self, generated_pdfs).open
            end
          end
        end
      end
    end
  end
end
