# frozen_string_literal: true
require 'rbconfig'
require 'fileutils'

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
      #   -v, --verbose                               詳細ログ（ENV['VERBOSE']=1）
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
            DESC

            method_option :resize,   type: :boolean, default: true,  desc: '画像最適化を行う（--no-resize で無効）'
            method_option :high,     type: :boolean, default: false, desc: '画像最適化プリセット: 高品質'
            method_option :medium,   type: :boolean, default: false, desc: '画像最適化プリセット: 中品質'
            method_option :low,      type: :boolean, default: false, desc: '画像最適化プリセット: 低品質'
            method_option :compress, type: :boolean, default: true,  desc: 'PDF圧縮を行う（--no-compress で無効）'
            method_option :clean,    type: :boolean, default: true,  desc: '中間生成物をクリーンアップ（--no-clean で無効）'
            method_option :dry_run,  type: :boolean, aliases: '-n',  desc: '実行せずにビルド予定のみを表示（試行）'
            method_option :merge,    type: :boolean, aliases: '-m',  desc: '生成された各PDFを結合して出力（出力名: output.pdf / output_compressed.pdf）'

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
            #   --no-compress, --no-clean, -v/--verbose
            #
            # 注意:
            #   options[:verbose] 指定時に ENV['VERBOSE']=1 をセットして詳細ログを出力。
            # ================================================================
            def build(*tokens)
              ENV['VERBOSE'] = '1' if options[:verbose]
              # Common ベース実装

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
                    Vivlio::Starter::ThorCLI.start([t, target])
                  end
                  # 単章PDFを生成
                  Vivlio::Starter::ThorCLI.start(['pdf'])
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

                # 生成した単章PDFを一度だけ開く（macOS のみ）
                begin
                  if last_pdf && RbConfig::CONFIG['host_os'] =~ /darwin|mac os/i
                    system(%(open -a Preview "#{last_pdf}"))
                  end
                rescue => _e
                  # 失敗しても処理は継続
                end
                return
              end

              # chapters 指定（keep）を取得（'all' または未設定は nil）
              begin
                keep = BuildHelpers.configured_chapters
                if keep && keep.any?
                  Common.log_action("[Subset] 退避なしで論理的に対象を限定してビルドします: #{keep.inspect}")
                else
                  Common.log_action('[Subset] chapters 設定なし/\'all\'のため、フルビルドします（退避なし）')
                end

              # ================================================================
              # Step 0: 事前クリーンアップ（フルビルド前の初期化）
              # ------------------------------------------------
              # - Rake に依存しない統合ビルドの初期化として clean を実行
              # - 失敗しても警告のみで続行
              # ================================================================
              begin
                Common.log_action('[Step 0] クリーンアップを実行します…')
                Vivlio::Starter::ThorCLI.start(['clean'])
              rescue => e
                Common.log_warn("[Step 0] クリーンアップでエラー: #{e}")
              end

              # ================================================================
              # Step 1: 画像最適化（オプションでスキップ/プリセット指定）
              # ------------------------------------------------
              # - --no-resize でスキップ
              # - プリセット: --high / --medium(既定) / --low
              # - build_helpers.optimize_images! を呼び出し
              # ================================================================
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

              # ================================================================
              # Step 2: CSS を仮想連番 1,2,3… に更新（.orig バックアップ作成）
              # ------------------------------------------------
              # - build_helpers.apply_virtual_chapter_numbers_for_book!
              # ================================================================
              begin
                BuildHelpers.apply_virtual_chapter_numbers_for_book!(keep)
              rescue => e
                Common.log_warn("[Step 2] 仮想連番適用でエラー: #{e}")
              end

              # ================================================================
              # Step 3: 前書き (02-preface) のみ先行ビルド
              # ------------------------------------------------
              # - build_helpers.preface_prebuild! を実行
              # - 失敗時は警告のみ
              # ================================================================
              begin
                BuildHelpers.preface_prebuild!(keep)
              rescue => e
                Common.log_warn("[Step 3] エラー: #{e}")
              end

              # ================================================================
              # Step 4: 付録 (91〜97) をビルドし、結合HTMLを作成
              # ------------------------------------------------
              # - build_helpers.build_appendices_and_merge_html!
              # ================================================================
              begin
                BuildHelpers.build_appendices_and_merge_html!(keep)
              rescue => e
                Common.log_warn("[Step 4] 付録ビルド/結合でエラー: #{e}")
              end

              # ================================================================
              # Step 5: 本文章 (11..89) をビルド（HTML生成）
              # ------------------------------------------------
              # - build_helpers.build_chapters_html!
              # ================================================================
              begin
                BuildHelpers.build_chapters_html!(keep)
              rescue => e
                Common.log_warn("[Step 5] 章ビルドでエラー: #{e}")
              end

              # ================================================================
              # Step 6: TOC 生成（11..89 + 90-appendices.html を対象）
              # ------------------------------------------------
              # - build_helpers.generate_toc_and_pdf!('.')
              # ================================================================
              begin
                BuildHelpers.generate_toc_and_pdf!('.')
              rescue => e
                Common.log_warn("[Step 6] 目次生成でエラー: #{e}")
              end

              # ================================================================
              # Step 7: 全体PDF生成 → chapters_appendices.pdf/03-toc.pdf に分割
              # ------------------------------------------------
              # - build_helpers.build_overall_pdf_and_split_from_dir!('.')
              # ================================================================
              begin
                BuildHelpers.build_overall_pdf_and_split_from_dir!('.')
              rescue => e
                Common.log_warn("[Step 7] 章PDF化/分割でエラー: #{e}")
              end

              # ================================================================
              # Step 8: frontmatter.pdf 構成 + ローマ小付与
              # ------------------------------------------------
              # - build_helpers.build_frontmatter_pdf!
              # ================================================================
              begin
                BuildHelpers.build_frontmatter_pdf!
              rescue => e
                Common.log_warn("[Step 8] ページ番号連番化処理でエラー: #{e}")
              end

              # ================================================================
              # Step 9: 本扉・扉裏・後書き・奥付
              # ------------------------------------------------
              # - build_helpers.build_front_pages_and_tail!
              # ================================================================
              begin
                BuildHelpers.build_front_pages_and_tail!
              rescue => e
                Common.log_warn("[Step 9] タイトル/奥付の生成でエラー: #{e}")
              end

              # ================================================================
              # Step 10: すべてのPDFを結合して output.pdf を生成
              # ------------------------------------------------
              # - build_helpers.merge_all_pdfs!
              # ================================================================
              begin
                BuildHelpers.merge_all_pdfs!
              rescue => e
                Common.log_warn("[Step 10] PDF結合でエラー: #{e}")
              end

              # ================================================================
              # Step 11: CSS をバックアップ(.orig)から復元
              # ------------------------------------------------
              # - build_helpers.restore_chapter_css_backups_for_book!
              # ================================================================
              begin
                BuildHelpers.restore_chapter_css_backups_for_book!
              rescue => e
                Common.log_warn("[Step 11] CSS復元でエラー: #{e}")
              end

              # ================================================================
              # Step 12: 生成PDFを圧縮（--no-compress でスキップ可）
              # ------------------------------------------------
              # - build_helpers.compress_pdf!
              # ================================================================
              begin
                if options[:compress] == false
                  Common.log_action('[Step 12] PDF圧縮をスキップします（--no-compress）')
                else
                  BuildHelpers.compress_pdf!
                end
              rescue => e
                Common.log_warn("[Step 12] PDF圧縮でエラー: #{e}")
              end

              # ================================================================
              # Step 13: 中間生成物クリーン（--no-clean でスキップ可）
              # ------------------------------------------------
              # - Thor 'clean' を呼び出し
              # ================================================================
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

              # 最後に1度だけPDFをオープン（OS判定は open_pdf 側に委譲）
              begin
                open_pdf
              rescue => _e
                # 失敗してもビルド完了は維持
              end

              Common.log_success('全ファイルのビルドが完了しました')
              ensure
                # 退避方式は廃止のため、復元処理は不要
              end
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
                name = t + '.md'
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
