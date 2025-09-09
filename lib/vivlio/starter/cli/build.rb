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
        extend self
        def included(base)
          base.class_eval do
            desc 'build [TOKENS...]', '書籍をビルドします（Rake に依存しない統合版）'
            long_desc <<~DESC
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

            method_option :resize,   type: :boolean, default: true,  desc: '画像最適化を行う（--no-resize で無効）'
            method_option :high,     type: :boolean, default: false, desc: '画像最適化プリセット: 高品質'
            method_option :medium,   type: :boolean, default: false, desc: '画像最適化プリセット: 中品質'
            method_option :low,      type: :boolean, default: false, desc: '画像最適化プリセット: 低品質'
            method_option :compress, type: :boolean, default: true,  desc: 'PDF圧縮を行う（--no-compress で無効）'
            method_option :clean,    type: :boolean, default: true,  desc: '中間生成物をクリーンアップ（--no-clean で無効）'
            method_option :dry_run,  type: :boolean, aliases: '-n',  desc: '実行せずにビルド予定のみを表示（試行）'
            method_option :merge,    type: :boolean, aliases: '-m',  desc: '生成された各PDFを結合して出力（出力名: output.pdf / output_compressed.pdf）'
            method_option :parallel_pdf, type: :boolean, default: false, desc: '実験: 章PDFを並列生成して結合（Step 7 を置換）'
            method_option :single_html,  type: :boolean, default: false, desc: '実験: 本文(11..89)を chapters.html に結合してから PDF 生成（Step 7 を置換）'
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
            #   --parallel_pdf, --single_html
            #   --log[=level]（error/warn/info/debug、未指定は info）
            #
            # 注意:
            #   --log により Common.current_log_level を制御（既定 warn）。
            # ================================================================
            def build(*tokens)
              # --no-cache は --force のエイリアス
              options[:force] ||= options[:'no-cache']
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
                  if options[:merge]
                    Common.echo_always "  - 結合: output.pdf（圧縮有効時は output_compressed.pdf も生成）"
                  end
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
                    begin
                      FileUtils.rm_f(chapter_pdf)
                      FileUtils.mv(output_pdf, chapter_pdf)
                      Common.log_success("単章PDFを生成しました: #{chapter_pdf}")
                      generated_pdfs << chapter_pdf
                      last_pdf = chapter_pdf
                    rescue => e
                      Common.log_warn("単章PDFのリネームに失敗しました: #{e}")
                    end
                  else
                    Common.log_warn("出力PDFが見つかりません: #{output_pdf}")
                  end
                end

                # 複数生成時の結合処理
                if options[:merge] && generated_pdfs.any?
                  Common.log_action('[Merge] 生成した章PDFを結合して output.pdf を作成します…')
                  begin
                    FileUtils.rm_f('output.pdf')
                    cmd = ['bundle', 'exec', 'hexapdf', 'merge', *generated_pdfs, 'output.pdf'].join(' ')
                    merged = system(cmd)
                    if merged && File.exist?('output.pdf')
                      Common.log_success('[Merge] output.pdf を生成しました')
                      if options[:compress] != false
                        # 既定の圧縮フローを利用
                        begin
                          Vivlio::Starter::ThorCLI.start(['pdf_compress'])
                        rescue => e
                          Common.log_warn("[Merge] 圧縮に失敗またはスキップ: #{e}")
                        end
                      end
                      # 最後に open:pdf（圧縮があれば圧縮版が優先される実装）
                      begin
                        open_pdf
                      rescue => _e
                        # 続行
                      end
                      return
                    else
                      Common.log_error('[Merge] PDF結合に失敗しました（output.pdf 未生成）')
                    end
                  rescue => e
                    Common.log_warn("[Merge] 結合中にエラー: #{e}")
                  end
                end

                # 生成した単章PDFを一度だけ開く（open_pdf を用いてウィンドウ位置も適用）
                begin
                  if last_pdf
                    open_pdf(last_pdf)
                  end
                rescue => _e
                  # 失敗しても処理は継続
                end
                return
              end

              # chapters 指定（keep）を取得（'all' または未設定は nil）
              keep = BuildHelpers.configured_chapters
              if keep && keep.any?
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
                                 preset = ([:high, :low].find { |k| options[k] } || :medium)
                                 "実行 (#{preset})"
                               end
                main_targets = BuildHelpers.main_text_basenames(keep)
                appendix_targets = BuildHelpers.appendix_basenames(keep)
                Common.echo_always "  - 画像最適化: #{resize_desc}"
                Common.echo_always "  - 本文(11..89): #{main_targets.empty? ? '対象なし' : main_targets.join(', ')}"
                Common.echo_always "  - 付録(91..97): #{appendix_targets.empty? ? '対象なし' : appendix_targets.join(', ')}"
                Common.echo_always "  - TOC: 03-toc.html / 03-toc.pdf"
                Common.echo_always "  - 全体PDF: chapters_appendices.pdf → 章/TOCに分割"
                Common.echo_always "  - PDF圧縮: #{options[:compress] == false ? 'スキップ' : '実行'}"
                Common.echo_always "  - クリーン: #{options[:clean] == false ? 'スキップ' : '実行'}"
                if options[:merge]
                  Common.echo_always "  - 結合: output.pdf（圧縮有効時は output_compressed.pdf も生成）"
                end
                Common.echo_always "\n計画のみを表示しました（dry-run、実処理は行いません）。"
                return
              end

              # タイマー初期化（フルビルド用）
              build_timings = []
              time_step = lambda do |label, &blk|
                t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
                Common.log_action("[Timer] #{label} start")
                begin
                  blk && blk.call
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
                begin
                  Common.log_action('[Step 0] クリーンアップを実行します…')
                  Vivlio::Starter::ThorCLI.start(['clean'])
                rescue => e
                  Common.log_warn("[Step 0] クリーンアップでエラー: #{e}")
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
                begin
                  if options[:resize] != false
                    # --high と --low の同時指定は high を優先（ユーザーに警告）
                    if options.values_at(:high, :low).count(true) > 1
                      Common.log_warn('[Step 1] --high と --low が同時指定されています。--high を優先します')
                    end
                    # --high が優先、次に --low。指定がなければ medium を既定値とする
                    preset = ([:high, :low].find { |k| options[k] } || :medium)
                    BuildHelpers.optimize_images!(preset)
                  else
                    Common.log_action('[Step 1] 画像最適化をスキップします（--no-resize）')
                  end
                rescue => e
                  Common.log_warn("[Step 1] エラー: #{e}")
                end
              end

              # ================================================================
              # Step 2: CSS を仮想連番 1,2,3… に更新（.orig バックアップ作成）
              # ------------------------------------------------
              # - build_helpers.apply_virtual_chapter_numbers_for_book!
              # ================================================================
              time_step.call('Step 2 (apply virtual chapter numbers)') do
                begin
                  BuildHelpers.apply_virtual_chapter_numbers_for_book!(keep)
                rescue => e
                  Common.log_warn("[Step 2] 仮想連番適用でエラー: #{e}")
                end
              end

              # ================================================================
              # Step 3: 前書き (02-preface) のみ先行ビルド
              # ------------------------------------------------
              # - build_helpers.preface_prebuild! を実行
              # - 失敗時は警告のみ
              # ================================================================
              time_step.call('Step 3 (preface prebuild)') do
                begin
                  BuildHelpers.preface_prebuild!(keep)
                rescue => e
                  Common.log_warn("[Step 3] エラー: #{e}")
                end
              end

              # ================================================================
              # Step 4: 付録 (91〜97) をビルドし、結合HTMLを作成
              # ------------------------------------------------
              # - build_helpers.build_appendices_and_merge_html!
              # ================================================================
              time_step.call('Step 4 (build appendices and merge html)') do
                begin
                  BuildHelpers.build_appendices_and_merge_html!(keep)
                rescue => e
                  Common.log_warn("[Step 4] 付録ビルド/結合でエラー: #{e}")
                end
              end

              # ================================================================
              # Step 5: 本文章 (11..89) をビルド（HTML生成）
              # ------------------------------------------------
              # - build_helpers.build_chapters_html!
              # ================================================================
              time_step.call('Step 5 (build chapters html)') do
                begin
                  BuildHelpers.build_chapters_html!(keep)
                rescue => e
                  Common.log_warn("[Step 5] 章ビルドでエラー: #{e}")
                end
              end

              # ================================================================
              # Step 6: TOC 生成（11..89 + 90-appendices.html を対象）
              # ------------------------------------------------
              # - build_helpers.generate_toc_and_pdf!('.')
              # ================================================================
              time_step.call('Step 6 (generate toc and pdf)') do
                begin
                  BuildHelpers.generate_toc_and_pdf!('.', keep)
                rescue => e
                  Common.log_warn("[Step 6] 目次生成でエラー: #{e}")
                end
              end

              # ================================================================
              # Step 7: 全体PDF生成 → chapters_appendices.pdf/03-toc.pdf に分割
              # ------------------------------------------------
              # - build_helpers.build_overall_pdf_and_split_from_dir!('.')
              # ================================================================
              time_step.call('Step 7 (build overall pdf and split)') do
                begin
                  if options[:parallel_pdf] || ENV['VIVLIO_EXPERIMENTAL_PARALLEL_PDF'] == '1'
                    Common.log_info('[Step 7] 実験モード: 章PDFの並列生成＋結合を使用します')
                    BuildHelpers.build_chapter_pdfs_in_parallel_and_merge!(keep)
                  elsif options[:single_html] || ENV['VIVLIO_EXPERIMENTAL_SINGLE_HTML'] == '1'
                    Common.log_info('[Step 7] 実験モード: 本文(11..89)を chapters.html に結合してから PDF 生成します')
                    BuildHelpers.build_overall_pdf_from_single_chapters_html!('.', keep)
                  else
                    BuildHelpers.build_overall_pdf_and_split_from_dir!('.', keep)
                  end
                rescue => e
                  Common.log_warn("[Step 7] 章PDF化/分割でエラー: #{e}")
                end
              end

              # ================================================================
              # Step 8: frontmatter.pdf 構成 + ローマ小付与
              # ------------------------------------------------
              # - build_helpers.build_frontmatter_pdf!
              # ================================================================
              time_step.call('Step 8 (build frontmatter pdf)') do
                begin
                  BuildHelpers.build_frontmatter_pdf!
                rescue => e
                  Common.log_warn("[Step 8] ページ番号連番化処理でエラー: #{e}")
                end
              end

              # ================================================================
              # Step 9: 本扉・扉裏・後書き・奥付
              # ------------------------------------------------
              # - build_helpers.build_front_pages_and_tail!
              # ================================================================
              time_step.call('Step 9 (build front pages and tail)') do
                begin
                  # 00/01/99 の有無を確認し、--force 指定時は常に再生成、未指定時は無いものだけ生成
                  title_md    = File.join(Common::CONTENTS_DIR, '00-titlepage.md')
                  legal_md    = File.join(Common::CONTENTS_DIR, '01-legalpage.md')
                  colophon_md = File.join(Common::CONTENTS_DIR, '99-colophon.md')
                  book_yml    = File.join('config', 'book.yml')
                  front_pdf   = '00-01-front.pdf'
                  col_pdf     = '99-colophon.pdf'

                  newer_than_any = lambda do |target, sources|
                    return true unless File.exist?(target)
                    t_mtime = File.mtime(target) rescue Time.at(0)
                    Array(sources).any? { |s| File.exist?(s) && File.mtime(s) > t_mtime }
                  end

                  begin
                    # 00/01 は front_pdf の鮮度に基づいて再生成
                    if options[:force] || newer_than_any.call(front_pdf, [title_md, legal_md, book_yml])
                      [['create:titlepage', title_md], ['create:legalpage', legal_md]].each do |cmd, _path|
                        Vivlio::Starter::ThorCLI.start([cmd, '--force'])
                      end
                    end

                    # 99 は col_pdf の鮮度に基づいて再生成
                    if options[:force] || newer_than_any.call(col_pdf, [colophon_md, book_yml])
                      Vivlio::Starter::ThorCLI.start(['create:colophon', '--force'])
                    end
                  rescue => e
                    Common.log_warn("[Step 9] create:* の生成でエラー: #{e}")
                  end
                  BuildHelpers.build_front_pages_and_tail!(options[:force] ? true : false)
                rescue => e
                  Common.log_warn("[Step 9] タイトル/奥付の生成でエラー: #{e}")
                end
              end

              # ================================================================
              # Step 10: すべてのPDFを結合して output.pdf を生成
              # ------------------------------------------------
              # - build_helpers.merge_all_pdfs!
              # ================================================================
              time_step.call('Step 10 (merge all pdfs)') do
                begin
                  # 章サブセット（keep）を尊重しつつ結合し、アウトライン付与を行う
                  BuildHelpers.merge_all_pdfs_with_outline!(keep)
                rescue => e
                  Common.log_warn("[Step 10] PDF結合でエラー: #{e}")
                end
              end

              # ================================================================
              # Step 11: CSS をバックアップ(.orig)から復元
              # ------------------------------------------------
              # - build_helpers.restore_chapter_css_backups_for_book!
              # ================================================================
              time_step.call('Step 11 (restore chapter css backups)') do
                begin
                  BuildHelpers.restore_chapter_css_backups_for_book!(keep)
                rescue => e
                  Common.log_warn("[Step 11] CSS復元でエラー: #{e}")
                end
              end

              # ================================================================
              # Step 12: 生成PDFを圧縮（--no-compress でスキップ可）
              # ------------------------------------------------
              # - build_helpers.compress_pdf!
              # ================================================================
              time_step.call('Step 12 (compress pdf)') do
                begin
                  if options[:compress] == false
                    Common.log_action('[Step 12] PDF圧縮をスキップします（--no-compress）')
                  else
                    BuildHelpers.compress_pdf!
                  end
                rescue => e
                  Common.log_warn("[Step 12] PDF圧縮でエラー: #{e}")
                end
              end

              # ================================================================
              # Step 13: 中間生成物クリーン（--no-clean でスキップ可）
              # ------------------------------------------------
              # - Thor 'clean' を呼び出し
              # ================================================================
              time_step.call('Step 13 (final clean)') do
                begin
                  if options[:clean] == false
                    Common.log_action('[Step 13] クリーンアップをスキップします（--no-clean）')
                  else
                    Common.log_action('[Step 13] 中間生成物をクリーンアップします…')
                    Vivlio::Starter::ThorCLI.start(['clean'])
                  end
                rescue => e
                  Common.log_warn("[Step 13] クリーンアップでエラー: #{e}")
                end
              end

              # タイマーサマリー
              begin
                total = build_timings.map { |(_, dt)| dt }.inject(0.0, :+)
                Common.echo_always "\n== Build Step Timings =="
                build_timings.each do |label, dt|
                  Common.echo_always sprintf("  - %-34s %6.2fs", label, dt)
                end
                Common.echo_always sprintf("  = %-34s %6.2fs", 'TOTAL', total)
                Common.echo_always "==========================\n"

                # timings_summary.md の先頭に追記（新しいビルド結果をファイル先頭に）
                begin
                  ts = Time.now.iso8601
                  new_block = []
                  new_block << "\n## Build Step Timings (#{ts})\n"
                  new_block << "```\n"
                  new_block << "== Build Step Timings =="
                  build_timings.each do |label, dt|
                    new_block << sprintf("  - %-34s %6.2fs", label, dt)
                  end
                  new_block << sprintf("  = %-34s %6.2fs", 'TOTAL', total)
                  new_block << "`````".sub('`````', "```")

                  path = File.join(Dir.pwd, 'timings_summary.md')
                  previous = ''
                  if File.exist?(path)
                    begin
                      previous = File.read(path, encoding: 'utf-8')
                    rescue
                      previous = ''
                    end
                  end
                  File.open(path, 'w', encoding: 'utf-8') do |f|
                    f.write(new_block.join("\n"))
                    f.write("\n")
                    f.write(previous.to_s)
                  end
                rescue => _e
                  # ignore file append errors
                end
              rescue => _e
                # ignore summary errors
              end

              # 最後に1度だけPDFをオープン（OS判定は open_pdf 側に委譲）
              begin
                open_pdf
              rescue => _e
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
                if t =~ /(\A\d+)-(\d+\z)/
                  return find_basenames_in_range($1, $2)
                end
                if t =~ /\A\d+\z/
                  return list_contents_basenames.select { |bn| bn.start_with?("#{t}-") }
                end
                # Support explicit basename with or without .md, optionally prefixed by contents/
                name = t.sub(%r{\A#{Regexp.escape(Common::CONTENTS_DIR)}/}, '')
                name = name.end_with?('.md') ? name : (name + '.md')
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
