# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/samovar/build_command.rb
# ================================================================
# 責務:
#   Samovar CLI の build コマンドを実装する。
#   書籍全体または指定章の PDF 生成を実行する。
#
# 実行モード:
#   - フルビルド（引数なし）: 全章を含む書籍全体の PDF を生成
#   - 単章ビルド（章番号指定）: 指定章のみの PDF を生成
#
# 主要オプション:
#   - --[no]-resize: 画像最適化の有効/無効
#   - --high/--medium/--low: 画像品質プリセット
#   - --[no]-compress: PDF 圧縮の有効/無効
#
# 依存:
#   - Build::UnifiedBuildPipeline: ビルドパイプライン
#   - TokenResolver: 章トークンの解決
# ================================================================

require_relative '../build'
require_relative '../build/build_lock'
require_relative '../build/direct_build'
require_relative '../build/pipeline'
require_relative '../build/output_helpers'
require_relative '../pre_process'
require_relative '../convert'
require_relative '../post_process'
require_relative '../entries'
require_relative '../epub'
require_relative '../pdf'
require_relative '../token_resolver'
require_relative '../guards'
require_relative 'vs_command'

module VivlioStarter
  module CLI
    module SamovarCommands
      # build コマンドの Samovar 実装
      class BuildCommand < VsCommand
        self.description = '書籍全体または指定章をビルドします'

        many :targets, 'ビルド対象（章番号 / 範囲 / ベース名 / 単一の .md ファイル）', default: []

        options do
          option '--theme <color>', 'テーマカラー（.md 直接指定時のみ有効）', key: :theme
          option '--[no]-resize', '画像最適化を行う（--no-resize で無効）', default: true, key: :resize
          option '--high', '画像最適化プリセット: 高品質', default: false
          option '--medium', '画像最適化プリセット: 中品質', default: false
          option '--low', '画像最適化プリセット: 低品質', default: false
          option '--[no]-compress', 'PDF圧縮を行う（--no-compress でスキップ）', key: :compress
          option '--[no]-clean', '中間生成物をクリーンアップ（--no-clean でスキップ）', default: true, key: :clean
          option '--[no]-verify', 'リンク・画像の基本検証を実行する（--no-verify でスキップ）', default: true, key: :verify
          option '--verify-links', '外部 URL の HTTP 到達性チェックを実行する', default: false, key: :verify_links
          option '--log <level>', 'ログレベルを指定（error/warn/info/debug）', key: :log_level
          option '-h/--help', 'このコマンドの使い方を表示', key: :help
        end

        include VivlioStarter::CLI::BuildCommands::OutputHelpers

        def call
          if options[:help]
            print_usage
            return 0
          end

          # 設定ファイルを経由しない直接ビルド（vs build myawesome.md）。
          # プロジェクト前提の Guard は通さず、PDF 生成に必須の Node だけを確認する。
          if direct_mode?
            Guards::Guard.run!(Guards::NodeCheck.new)
            return run_direct_build
          end

          warn_theme_option_ignored

          # 前提条件の検証（precondition-guard-spec.md）
          # 違反があれば 🔴 メッセージを表示して本処理に入らず終了する
          Guards::Guard.run!(
            Guards::ProjectRootCheck.new,
            Guards::CatalogFileCheck.new,
            Guards::CatalogEntriesCheck.new,
            Guards::ContentsDirCheck.new,
            Guards::NodeCheck.new,
            Guards::ImageFilenameCheck.new,
            Guards::ChapterTargetCheck.new(targets)
          )

          # 検証オプションをスレッドローカルに設定（LinkImageValidator が参照）
          setup_verify_options!
          PreProcessCommands::LinkImageValidator.reset!
          PreProcessCommands::IssueRegistry.reset!

          # 同一プロジェクトでの多重 build を防ぐため、.cache/vs/.build.lock を
          # File::LOCK_EX | LOCK_NB で取得する。取得失敗時は即座にエラー終了。
          BuildCommands::BuildLock.with_lock do
            if targets.any?
              target_entries = resolve_target_entries

              # 解決できない章指定は ChapterTargetCheck が本処理の前に止めるので、
              # ここへ来るのは空白だけの引数（vs build ""）のような、
              # 検査対象にすらならなかった指定に限られる。最後の網として残す。
              if target_entries.empty?
                common.log_error("章として読める指定がありません: #{targets.join(', ').inspect}")
                return 1
              end

              run_single_mode_build(target_entries)
            else
              run_full_mode_build
            end
          end

          0
        rescue Guards::GuardError => e
          common.log_error(e.message)
          1
        rescue BuildCommands::BuildLock::AlreadyLockedError => e
          common.log_error(e.message)
          1
        rescue SystemExit => e
          raise e
        rescue StandardError => e
          common.log_error("Error: #{e.message}")
          1
        ensure
          Thread.current[:vs_verify_options] = nil
          PostProcessCommands::HeadingProcessor.chapter_tokens_override = nil
        end

        # プロジェクト文脈（config/book.yml）なしで実行できるか。
        # RootCommand#ensure_project_context! がこの応答を見て ensure_configured! を省く。
        # 直接ビルドは book.yml の値に依存しないことが機能の定義そのもの（spec §2.2）。
        def projectless? = direct_mode?

        private

        # ターゲットが .md ファイル指定なら直接ビルドの候補とする（spec §1.3）。
        # catalog の章 basename は拡張子を含まないため衝突しない。
        # 個数・混在・実在の検証は run_direct_build 側で行い、ここでは分岐だけを決める。
        def direct_mode? = targets.any? { it.to_s.end_with?('.md') }

        # 設定ファイルを経由しない単一 Markdown のビルドを実行する（spec §1.3）。
        # 誤用（複数指定・章トークンとの混在・不在ファイル）は従来解釈へフォールバック
        # させず、その場で 🔴 と対処を示して終える。
        def run_direct_build
          mixed = targets.reject { it.to_s.end_with?('.md') }
          if mixed.any?
            common.log_error(".md ファイルと章の指定は同時に使えません: #{mixed.join(', ')}",
                             detail: '対処: 直接ビルドなら .md だけ' \
                                     "（vs build #{targets.find { it.to_s.end_with?('.md') }}）、" \
                                     "プロジェクトの章なら拡張子なし（vs build #{mixed.first}）で指定してください。")
            return 1
          end

          if targets.size > 1
            common.log_error("直接ビルドは 1 ファイルのみ指定できます: #{targets.join(', ')}",
                             detail: '対処: 1 ファイルずつ実行するか、複数の原稿を 1 冊にまとめるなら ' \
                                     'vs new でプロジェクトを作成してください。')
            return 1
          end

          source = targets.first.to_s
          unless File.file?(source)
            common.log_error("ファイルが見つかりません: #{source}",
                             detail: '対処: パスを確認してください。プロジェクトの章を指定する場合は' \
                                     '拡張子を付けません（例: vs build 10-intro）。')
            return 1
          end

          warn_ignored_options!
          BuildCommands::DirectBuild.new(source, theme: options[:theme]).call
        end

        # 直接ビルドで受け付けないオプションを 1 回だけ通知する（spec §1.4）。
        # 既定値と区別できる「明示指定」だけを拾う。
        def warn_ignored_options!
          ignored = []
          ignored << '--no-resize' if options[:resize] == false
          ignored << '--no-clean' if options[:clean] == false
          ignored << '--no-verify' if options[:verify] == false
          ignored << '--verify-links' if options[:verify_links]
          ignored << (options[:compress] ? '--compress' : '--no-compress') unless options[:compress].nil?
          ignored.concat(%w[--high --medium --low].select { options[it.delete_prefix('--').to_sym] })
          return if ignored.empty?

          common.log_warn("直接ビルドでは次のオプションは無視されます: #{ignored.join(', ')}",
                          detail: '対処: これらを使うには vs new で作成したプロジェクトでビルドしてください。')
        end

        # 通常ビルドでの --theme を案内する（テーマ色はプロジェクトの設定が正典・spec §2.1）。
        def warn_theme_option_ignored
          return if options[:theme].nil?

          common.log_warn('--theme は直接ビルド（.md 指定）専用です。',
                          detail: "対処: config/book.yml の theme.color を '#{options[:theme]}' に変更してください。")
        end

        # CLI 引数から Entry 配列を解決する
        # @return [Array<TokenResolver::Entry>] カタログに存在する章の Entry 配列
        def resolve_target_entries
          resolver = TokenResolver::Resolver.new
          entries = resolver.resolve(targets)
          # カタログに存在する章のみを対象とする
          entries.select(&:in_catalog?)
        end

        # 単章/選択ビルドを実行
        # @param entries [Array<TokenResolver::Entry>] ビルド対象の Entry 配列
        def run_single_mode_build(entries)
          basenames = entries.map(&:basename)
          common.log_action("単章/選択ビルドを実行します: #{basenames.join(', ')}")

          PostProcessCommands::HeadingProcessor.chapter_tokens_override = basenames

          pipeline = BuildCommands::UnifiedBuildPipeline.new(self, entries: entries, mode: :single)
          build_timings = pipeline.run
          IndexCommands.flush_post_build_messages

          # 単章ビルドは output.targets によらず閲覧用 PDF だけを作る
          # （pipeline.rb register_single_mode_steps）。よって成果物の報告・自動オープンも
          # targets ではなく「実際に生成された PDF」で判断する——targets: kindle 等のときに
          # PDF は出来ているのに無言で終わり、開きもしない、という食い違いを避けるため。
          generated_pdf = pipeline.generated_pdf_name
          open_generated_pdf(generated_pdf)

          # 外部 URL の到達性チェック（--verify-links 有効時のみ）
          PreProcessCommands::LinkImageValidator.check_external_urls!
          # 検証サマリーを表示
          PreProcessCommands::LinkImageValidator.print_summary

          common.log_success("単章ビルドが完了しました: #{generated_pdf}")
          created_files = [generated_pdf].compact.select { File.exist?(it) }
          print_created_files_message(created_files, build_timings:, wall_time: pipeline.wall_time)

          print_build_timings(build_timings, wall_time: pipeline.wall_time,
                                             parallel_labels: pipeline.parallel_step_labels)
        ensure
          PostProcessCommands::HeadingProcessor.chapter_tokens_override = nil
        end

        # フルビルドを実行
        def run_full_mode_build
          resolver = TokenResolver::Resolver.new
          entries = resolver.resolve # 引数なし = catalog.yml 全章

          if entries.any?
            common.log_action("[Subset] 対象章: #{entries.map(&:basename).inspect}")
          else
            common.log_action('[Subset] catalog.yml に章が定義されていません')
          end

          pipeline = BuildCommands::UnifiedBuildPipeline.new(self, entries: entries, mode: :full)
          build_timings = pipeline.run
          IndexCommands.flush_post_build_messages

          open_pdf(print_pdf_only? ? Common.generate_print_pdf_filename : nil)

          # 外部 URL の到達性チェック（--verify-links 有効時のみ）
          PreProcessCommands::LinkImageValidator.check_external_urls!
          # 検証サマリーを表示
          PreProcessCommands::LinkImageValidator.print_summary

          common.log_success('全ファイルのビルドが完了しました')

          created_files = get_created_files_list
          print_created_files_message(created_files, build_timings:, wall_time: pipeline.wall_time)

          print_outline_debug_info
          print_build_timings(build_timings, wall_time: pipeline.wall_time,
                                             parallel_labels: pipeline.parallel_step_labels)
        end

        # 単章ビルドの成果物を開く。フルビルドの open_pdf と違い output.targets は見ない——
        # 単章は targets によらず常に閲覧用 PDF だけを生成するため、生成できた事実が唯一の条件。
        def open_generated_pdf(path)
          return unless path && File.exist?(path)
          return unless defined?(VivlioStarter::CLI::PdfCommands::PdfOpener)

          VivlioStarter::CLI::PdfCommands::PdfOpener.new(pdf_command_options, path).call
        rescue StandardError
          # PDF を開く処理は失敗してもビルド結果には影響させない
        end

        def open_pdf(path = nil)
          unless pdf_outputs_requested?
            Common.log_info('[open] output.targets に pdf/print_pdf が含まれないためスキップします')
            return
          end
          return unless defined?(VivlioStarter::CLI::PdfCommands::PdfOpener)

          VivlioStarter::CLI::PdfCommands::PdfOpener.new(pdf_command_options, path).call
        rescue StandardError
          # macOS 専用機能のため失敗しても握りつぶす
        end

        # targets に print_pdf のみ（pdf なし）が指定されているかを判定する
        def print_pdf_only?
          cfg = Common::CONFIG
          targets = Build::PdfMerger.extract_targets(cfg.dig(:output, :targets))
          targets.include?('print_pdf') && !targets.include?('pdf')
        end

        # pdf または print_pdf の出力が要求されているかを判定する
        def pdf_outputs_requested?
          cfg = Common::CONFIG
          targets = Build::PdfMerger.extract_targets(cfg.dig(:output, :targets))

          # targets未指定時はデフォルトでpdfを開く
          return true if targets.empty?

          targets.any? { |target| target.include?('pdf') }
        end

        def pdf_command_options
          { verbose: parent_verbose? }
        end

        def parent_verbose?
          parent&.options&.[](:verbose) || false
        end

        # 生成されたファイルのリストを取得
        def get_created_files_list
          files = []
          targets = Build::PdfMerger.extract_targets(Common::CONFIG.output.targets)

          # PDF系
          if targets.include?('pdf')
            normal_pdf = Common.generate_output_filename('pdf')
            files << normal_pdf if File.exist?(normal_pdf)
          end

          if targets.include?('pdf') && options[:compress]
            compressed_pdf = Common.generate_compressed_pdf_filename('pdf')
            files << compressed_pdf if File.exist?(compressed_pdf)
          end

          if targets.include?('print_pdf')
            print_pdf = Common.generate_print_pdf_filename
            files << print_pdf if File.exist?(print_pdf)
          end

          # EPUB
          if targets.include?('epub')
            epub_file = Common.generate_epub_filename
            files << epub_file if File.exist?(epub_file)
          end

          # Kindle（KPF・最終成果物）
          if targets.include?('kindle')
            kpf_file = Common.generate_kpf_filename
            files << kpf_file if File.exist?(kpf_file)
          end

          files
        end

        # 作成されたファイルメッセージを表示
        # build_timings が渡された場合は所要時間を末尾に付加する（通常時のみ）。
        # 枝を並列に走らせるとステップ計時の合計は実際に待った時間より長くなるため、
        # 著者へ見せるのは壁時計（wall_time）を優先する（§3.5）。
        def print_created_files_message(files, build_timings: nil, wall_time: nil)
          return if files.empty?

          file_list = files.map { |f| File.basename(f) }.join(', ')

          if build_timings && Common.current_log_level < 3
            aggregated, = aggregate_step_timings(build_timings)
            total = wall_time || aggregated.map { |(_, dt)| dt }.inject(0.0, :+)
            Common.log_result("#{file_list} を作成しました (#{format('%.1f', total)}s)", status: :artifact)
          else
            Common.log_result("#{file_list} を作成しました。", status: :artifact)
          end
        end

        # CLI の --verify / --verify-links オプションをスレッドローカルに設定する
        # LinkImageValidator が resolve_config で参照する
        def setup_verify_options!
          opts = {}
          if options[:verify] == false
            opts[:no_verify] = true
          else
            opts[:verify_images] = true
            opts[:verify_bare_urls] = true
            opts[:verify_external_links] = options[:verify_links] || false
          end
          Thread.current[:vs_verify_options] = opts
        end

        def common
          VivlioStarter::CLI::Common
        end
      end
    end
  end
end
