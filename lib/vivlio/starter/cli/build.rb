# frozen_string_literal: true

require 'rbconfig'
require 'fileutils'
require 'time'

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
        module_function

        BUILD_DESC = {
          build: {
            short: '書籍をビルドします（Rake に依存しない統合版）',
            long: <<~DESC
              Rake タスクに依存せず、CLI から直接ビルドの各ステップを実行します。
              将来的な完全置換の第一段階として、主要な自動生成フロー（前書き→目次→本文/付録→frontmatter→後書き/奥付→結合→圧縮→クリーン）
              を Thor コマンド内で統合しています。

              オプション:
                --no-resize     Step1 画像最適化をスキップ
                --high          画像最適化プリセット: 高品質
                --medium        画像最適化プリセット: 中品質（既定）
                --low           画像最適化プリセット: 低品質
                --no-compress   PDF圧縮をスキップ
                --no-clean      中間生成物のクリーンアップをスキップ
                --log[=level]   ログ出力の詳細度（error/warn/info/debug、未指定時は info）
            DESC
          }
        }.freeze

        def included(base)
          base.class_eval do
            desc 'build [TOKENS...]', BUILD_DESC[:build][:short]
            long_desc BUILD_DESC[:build][:long]

            method_option :resize,   type: :boolean, default: true,  desc: '画像最適化を行う（--no-resize で無効）'
            method_option :high,     type: :boolean, default: false, desc: '画像最適化プリセット: 高品質'
            method_option :medium,   type: :boolean, default: false, desc: '画像最適化プリセット: 中品質'
            method_option :low,      type: :boolean, default: false, desc: '画像最適化プリセット: 低品質'
            method_option :compress, type: :boolean, default: true,  desc: 'PDF圧縮を行う（--no-compress で無効）'
            method_option :clean,    type: :boolean, default: true,  desc: '中間生成物をクリーンアップ（--no-clean で無効）'
            method_option :dry_run,  type: :boolean, aliases: '-n',  desc: '実行せずにビルド予定のみを表示（試行）'
            method_option :merge,    type: :boolean, aliases: '-m',
                                     desc: '生成された各PDFを結合して出力（出力名: output.pdf / output_compressed.pdf）'
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
                  Common.echo_always "\n== Dry Run: ビルド予定一覧 =="
                  expanded_tokens.each do |t|
                    Common.echo_always "  - 章: #{t} → 生成予定: #{t}.pdf"
                  end
                  Common.echo_always '  - 結合: output.pdf（圧縮有効時は output_compressed.pdf も生成）' if options[:merge]
                  Common.echo_always "\n合計 #{expanded_tokens.size} 章（dry-run、実処理は行いません）。"
                  return
                end

                generated_pdfs = []
                last_pdf = nil
                expanded_tokens.each do |target|
                  %w[pre_process convert post_process entries].each do |t|
                    BuildHelpers.time_step_for_chapter(target, t) do
                      Vivlio::Starter::ThorCLI.start([t, target])
                    end
                  end
                  # 単章PDFを生成
                  BuildHelpers.time_step_for_chapter(target, 'pdf') do
                    Vivlio::Starter::ThorCLI.start(['pdf'])
                  end
                  pdf_config = Common::CONFIG['pdf'] || {}
                  output_pdf = pdf_config['output_file'] || 'output.pdf'
                  chapter_pdf = "#{target}.pdf"
                  if File.exist?(output_pdf)
                    FileUtils.rm_f(chapter_pdf)
                    FileUtils.mv(output_pdf, chapter_pdf)
                    Common.log_success("単章PDFを生成しました: #{chapter_pdf}")
                    generated_pdfs << chapter_pdf
                    last_pdf = chapter_pdf
                  else
                    Common.log_warn("出力PDFが見つかりません: #{output_pdf}")
                  end
                end

                # 複数生成時の結合処理
                if options[:merge] && generated_pdfs.any?
                  Common.log_action('[Merge] 生成した章PDFを結合して output.pdf を作成します…')
                  FileUtils.rm_f('output.pdf')
                  cmd = ['bundle', 'exec', 'hexapdf', 'merge', *generated_pdfs, 'output.pdf'].join(' ')
                  merged = system(cmd)
                  if merged && File.exist?('output.pdf')
                    Common.log_success('[Merge] output.pdf を生成しました')
                    if options[:compress] != false
                      # 既定の圧縮フローを利用
                      Vivlio::Starter::ThorCLI.start(['pdf_compress'])
                    end
                    # 最後に open:pdf（圧縮があれば圧縮版が優先される実装）
                    open_pdf
                    return
                  else
                    Common.log_error('[Merge] PDF結合に失敗しました（output.pdf 未生成）')
                  end
                end

                # 生成した単章PDFを一度だけ開く（open_pdf を用いてウィンドウ位置も適用）
                begin
                  open_pdf(last_pdf) if last_pdf
                rescue StandardError => _e
                  # 失敗しても処理は継続
                end
                return
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
                Common.echo_always '  - 結合: output.pdf（圧縮有効時は output_compressed.pdf も生成）' if options[:merge]
                Common.echo_always "\n計画のみを表示しました（dry-run、実処理は行いません）。"
                return
              end

              # タイマー初期化（フルビルド用）
              build_timings = []
              time_step = lambda do |label, &blk|
                t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
                Common.log_action("[Timer] #{label} start")
                begin
                  blk&.call
                ensure
                  t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
                  dt = (t1 - t0)
                  build_timings << [label, dt]
                  Common.log_action("[Timer] #{label} finish: #{format('%.2f', dt)}s")
                end
              end

              # ================================================================
              # Step 0: 事前クリーンアップ（フルビルド前の初期化）
              # ------------------------------------------------
              # - Rake に依存しない統合ビルドの初期化として clean を実行
              # - 失敗しても警告のみで続行
              # ================================================================
              time_step.call('Step 0 (clean)') do
                if options[:clean] == false
                  Common.log_action('[Step 0] クリーンアップをスキップします（--no-clean）')
                else
                  Common.log_action('[Step 0] クリーンアップを実行します…')
                  Vivlio::Starter::ThorCLI.start(['clean'])
                end
              end

              # ================================================================
              # Step 1: 画像最適化（オプションでスキップ/プリセット指定）
              # ------------------------------------------------
              # - --no-resize でスキップ
              # - プリセット: --high / --medium(既定) / --low
              # - build_helpers.optimize_images! を呼び出し
              # ================================================================
              time_step.call('Step 1 (optimize images)') do
                if options[:resize] == false
                  Common.log_action('[Step 1] 画像最適化をスキップします（--no-resize）')
                else
                  if options.values_at(:high, :low).count(true) > 1
                    Common.log_warn('[Step 1] --high と --low が同時指定されています。--high を優先します')
                  end
                  preset = %i[high low].find { |k| options[k] } || :medium
                  BuildHelpers.optimize_images!(preset)
                end
              end

              # ================================================================
              # Step 2: 旧章別CSS仮想連番処理（廃止済み）
              # ------------------------------------------------
              # time_step.call('Step 2 (chapter css virtual numbers)') do
              #   Common.log_info('[Step 2] 章別CSSの仮想連番処理は廃止されました。処理をスキップします。')
              # end

              # Step 3/4 は廃止（02 の先行生成と付録 merge をやめ、通常フローに統合）

              # ================================================================
              # Step 5: 本文(11..89) + 付録(91..97) + 後書き(98) をビルド（HTML生成）
              # ------------------------------------------------
              # - build_helpers.build_sections_html!
              # ================================================================
              time_step.call('Step 5 (build sections html)') do
                BuildHelpers.build_sections_html!(keep)
              end

              # if ENV['VIVLIO_STOP_AFTER_STEP5']&.downcase == 'true'
              #   Common.log_action('[Step 5] VIVLIO_STOP_AFTER_STEP5=true のため処理を終了します')
              #   return
              # end

              # ================================================================
              # Step 6: TOC 生成（11..97 を対象）
              # ------------------------------------------------
              # - build_helpers.generate_toc_and_pdf!('.')
              # ================================================================
              time_step.call('Step 6 (generate toc and pdf)') do
                BuildHelpers.generate_toc_and_pdf!('.', keep)
              end

              # ================================================================
              # Step 7: 全体PDF生成（従来の entries.js → output.pdf → 分割）
              # ------------------------------------------------
              # - BuildHelpers.compile_overall_pdf_and_split! を経由するディレクトリスキャン版
              # ================================================================
              time_step.call('Step 7 (build overall pdf and split)') do
                Common.log_info('[Step 7] 従来フローで全体PDFを生成し分割します')
                BuildHelpers.build_overall_pdf_and_split_from_dir!('.', keep)
              end

              # ================================================================
              # Step 8: 02-03-front.pdf 構成 + ローマ小付与
              # ------------------------------------------------
              # - build_helpers.build_frontmatter_pdf!
              # ================================================================
              time_step.call('Step 8 (build 02-03-front.pdf)') do
                BuildHelpers.build_frontmatter_pdf!(keep)
              end

              # ================================================================
              # Step 9: 本扉・扉裏・後書き・奥付
              # ------------------------------------------------
              # - build_helpers.build_front_pages_and_tail!
              # ================================================================
              time_step.call('Step 9 (build front pages and tail)') do
                title_md    = File.join(Common::CONTENTS_DIR, '00-titlepage.md')
                legal_md    = File.join(Common::CONTENTS_DIR, '01-legalpage.md')
                colophon_md = File.join(Common::CONTENTS_DIR, '99-colophon.md')
                book_yml    = File.join('config', 'book.yml')
                front_pdf   = '00-01-front.pdf'
                col_pdf     = '99-colophon.pdf'

                newer_than_any = lambda do |target, sources|
                  return true unless File.exist?(target)

                  t_mtime = begin
                    File.mtime(target)
                  rescue StandardError
                    Time.at(0)
                  end
                  Array(sources).any? { |s| File.exist?(s) && File.mtime(s) > t_mtime }
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

              # ================================================================
              # Step 10: すべてのPDFを結合して output.pdf を生成
              # ------------------------------------------------
              # - build_helpers.merge_all_pdfs_only!
              # ================================================================
              time_step.call('Step 10 (merge all pdfs with outline)') do
                BuildHelpers.merge_all_pdfs_only!(keep)
              end

              # ================================================================
              # Step 11: output.pdf にアウトラインを付与
              # ------------------------------------------------
              # - build_helpers.add_outline_to_output_pdf!
              # ================================================================
              time_step.call('Step 11 (apply outline to output pdf)') do
                BuildHelpers.add_outline_to_output_pdf!(keep)
              end

              # ================================================================
              # Step 12: 生成PDFを圧縮（--no-compress でスキップ可）
              # ------------------------------------------------
              # - build_helpers.compress_pdf!
              # ================================================================
              time_step.call('Step 12 (compress pdf)') do
                if options[:compress] == false
                  Common.log_action('[Step 12] PDF圧縮をスキップします（--no-compress）')
                else
                  BuildHelpers.compress_pdf!
                end
              end

              # ================================================================
              # Step 13: 中間生成物クリーン（--no-clean でスキップ可）
              # ------------------------------------------------
              # - Thor 'clean' を呼び出し
              # ================================================================
              time_step.call('Step 13 (final clean)') do
                if options[:clean] == false
                  Common.log_action('[Step 13] クリーンアップをスキップします（--no-clean）')
                else
                  Common.log_action('[Step 13] 中間生成物をクリーンアップします…')
                  Vivlio::Starter::ThorCLI.start(['clean'])
                end
              end

              # タイマーサマリー
              total = build_timings.map { |(_, dt)| dt }.inject(0.0, :+)
              label_width = build_timings.map { |(label, _)| label.to_s.length }.max || 0
              label_width = [label_width, 'TOTAL'.length, 34].max
              value_width = 7
              Common.echo_always "\n== Build Step Timings =="
              build_timings.each do |label, dt|
                Common.echo_always format("  - %-#{label_width}s %#{value_width}.2fs", label, dt)
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
                new_block << format("  - %-#{label_width}s %#{value_width}.2fs", label, dt)
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

              def chapter_number_from_basename(basename)
                (basename[/^(\d+)-/, 1] || nil)&.to_i
              end

              def find_basenames_in_range(from_num, to_num)
                a, b = [from_num.to_i, to_num.to_i].minmax
                list_contents_basenames.select do |bn|
                  n = chapter_number_from_basename(bn)
                  n && n >= a && n <= b
                end
              end

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

              def expand_tokens_to_targets(tokens)
                Array(tokens).compact.flat_map { |tok| expand_token_to_basenames(tok) }.uniq
              end
            end
          end
        end
      end
    end
  end
end
