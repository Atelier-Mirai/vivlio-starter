# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/samovar/preflight_command.rb
# ================================================================
# 責務:
#   Samovar CLI の preflight コマンドを実装する。
#   vs build の Step 1〜4 のみを実行し、PDF生成なしで原稿エラーを高速検出する。
#
# 実行内容:
#   Step 1: 画像最適化（--no-resize でスキップ）
#   Step 2: テーマ画像準備
#   Step 3: Markdown前処理（frontmatter・画像パス・QueryStream・コードインクルード・クロスリファレンス）
#   Step 4: 索引スキャン（index_glossary.enabled かつ全章実行時のみ）
#
# 「vs build が報告することを先に見る」機能なので、build が言わないことは言わない:
#   章を絞った実行（vs preflight 24）は vs build 24（single mode）と同じく Step 4 を行わない。
#   索引・用語集は書籍全体を単位とする検査のため、章を絞ると誤検知の山になる
#   （preflight-glossary-warning-scope-report.md）。
#
# 終了コード:
#   0: 🔴 なし（🟡 警告のみ、または問題なし）
#   1: 🔴 1件以上（欠落画像・欠落コード・リンク切れ・危険スキーム・ラベルID重複・
#      QueryStream 展開エラー）、または実行時例外
#   ＝画面に出た絵文字と CI の成否が一致する。判定は IssueRegistry の severity のみで行う。
# ================================================================

require_relative '../build'
require_relative '../build/pipeline'
require_relative '../index'
require_relative '../pre_process'
require_relative '../token_resolver'
require_relative '../clean'
require_relative '../guards'
require_relative 'vs_command'

module VivlioStarter
  module CLI
    module SamovarCommands
      # preflight コマンドの Samovar 実装
      class PreflightCommand < VsCommand
        self.description = 'ビルド前の原稿エラーチェックを高速実行します'

        # 章別サマリー表のラベル幅（全角 1 文字＝2 幅で数える）。
        # 長い章タイトルは切り詰めて 🔴🟡✅ の縦位置を揃える（揃わないと表として読めない）
        CHAPTER_LABEL_WIDTH = 30

        # 章に紐付かない指摘（Guard 警告など）を示す行ラベル
        UNATTACHED_LABEL = '章に紐付かない指摘'

        # 章タイトル（H1）を探す行数の上限。原稿冒頭にあるため深追いしない
        TITLE_SCAN_LINES = 60

        # 指摘ゼロの章に使う件数オブジェクト
        NO_ISSUES = PreProcessCommands::IssueRegistry::Counts.new(errors: 0, warns: 0)

        many :targets, 'チェック対象（章番号 / 範囲 / スラッグ）', default: []

        options do
          option '--[no]-resize', '画像最適化を行う（--no-resize で無効）', default: true, key: :resize
          option '--[no]-verify', 'リンク・画像の基本検証を実行する（--no-verify でスキップ）', default: true, key: :verify
          option '--verify-links', '外部 URL の HTTP 到達性チェックを実行する', default: false, key: :verify_links
          option '--log <level>', 'ログレベルを指定（error/warn/info/debug）', key: :log_level
          option '-h/--help', 'このコマンドの使い方を表示', key: :help
        end

        def call
          if options[:help]
            print_usage
            return 0
          end

          # 章別サマリーの集計をリセットする。Guard の 🟡 警告も最終判定に含めるため、
          # Guard.run! より前に置く（preflight-chapter-summary-spec.md §2.2）
          PreProcessCommands::IssueRegistry.reset!

          # 前提条件の網羅的診断（precondition-guard-spec.md Phase 4）
          # preflight は診断コマンドのため build より広く全 Check を実行する。
          # Guard.run! は全違反をログしてから停止判定するため、複数の問題を一度に報告できる
          Guards::Guard.run!(
            Guards::ProjectRootCheck.new,
            Guards::CatalogFileCheck.new,
            Guards::CatalogEntriesCheck.new,
            Guards::ContentsDirCheck.new,
            Guards::NodeCheck.new,
            Guards::OrphanFileCheck.new,
            Guards::ImageFilenameCheck.new,
            Guards::CodeFenceCheck.new,
            Guards::ContainerFenceCheck.new,
            Guards::ContainerClassCheck.new
          )

          # ensure 節の execute_clean は本処理開始後のみ実行する
          # （Guard 違反＝プロジェクト外の可能性があるディレクトリでクリーンを走らせない）
          @preflight_started = true

          PreProcessCommands::LinkImageValidator.reset!

          # 検証オプションをスレッドローカルに設定（LinkImageValidator が参照）
          setup_verify_options!

          entries = resolve_entries
          if entries.empty? && targets.any?
            Common.log_error('指定した章が catalog.yml に存在しません。preflight を中断します。')
            return 1
          end

          pipeline = BuildCommands::UnifiedBuildPipeline.new(self, entries: entries, mode: :preflight)
          pipeline.run

          # 索引処理が積んだ案内（未走査章の vs index:auto 誘導・辞書不在）を吐き出す。
          # build 側は従来から flush しており、preflight だけが握り潰していた
          # （＝原稿の問題を先に知るための機能なのに知らせていなかった）
          IndexCommands.flush_post_build_messages

          # --verify-links 有効時のみ外部 URL チェックを実行
          PreProcessCommands::LinkImageValidator.check_external_urls!
          PreProcessCommands::LinkImageValidator.print_summary

          print_chapter_summary(entries)
          print_preflight_summary

          # 終了コードは 🔴 の有無だけで決める。画面に出た絵文字と CI の成否が一致し、
          # 「⚠️ 警告 N 件（ビルドは可能です）」と言いながら 1 を返す食い違いが起きない。
          # 従来は LinkImageValidator.any_issues?（severity を見ない）で判定していたため、
          # 裸 URL の警告だけでも 1 を返していた。
          PreProcessCommands::IssueRegistry.counts.errors.positive? ? 1 : 0
        rescue Guards::GuardError => e
          Common.log_error(e.message)
          1
        rescue SystemExit => e
          raise e
        rescue StandardError => e
          Common.log_error("Error: #{e.message}")
          1
        ensure
          # 前処理で生成した中間 .md ファイルを後始末する（本処理開始後のみ。
          # --help や Guard 違反時はプロジェクト外で実行された可能性があるため触らない）
          CleanCommands.execute_clean({}) if @preflight_started
          Thread.current[:vs_verify_options] = nil
        end

        private

        # CLI 引数から Entry 配列を解決する
        def resolve_entries
          resolver = TokenResolver::Resolver.new
          entries = resolver.resolve(targets)
          entries.select(&:in_catalog?)
        end

        # 検証オプションをスレッドローカルに設定する（BuildCommand と同一ロジック）
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

        # 章別サマリーを表示する（preflight-chapter-summary-spec.md §1）。
        # 前処理はファイル単位（並列）で流れるため 🔴🟡 が章をまたいで混在する。
        # 「どの章に何件あるか」を最後に一覧化して読み取れるようにする。
        # 指摘ゼロの章も載せる（検査したことの証明）が、全章 ✅ なら 1 行へ短縮する。
        def print_chapter_summary(entries)
          by_chapter = PreProcessCommands::IssueRegistry.summary_by_chapter
          rows = chapter_summary_rows(entries, by_chapter)
          unattached = by_chapter[nil]

          if unattached.nil? && rows.all? { |_, counts| counts.clean? }
            Common.log_result("全 #{rows.size} 章: 問題なし", status: :success) unless rows.empty?
            return
          end

          Common.log_always ''
          Common.log_always '📋 章別サマリー'
          rows.each { |label, counts| Common.log_always("   #{format_label(label)} #{issue_mark(counts)}") }
          return unless unattached

          Common.log_always ''
          Common.log_always("   #{format_label(UNATTACHED_LABEL)} #{issue_mark(unattached)}")
          print_unattached_details
        end

        # 「章に紐付かない指摘」の中身を並べる。
        #
        # 章に紐付く指摘は章名と行番号が出るので発生源を辿れるが、こちらは
        # 件数だけだと**何の話か分からないまま終わる**。build 側は
        # 「詳細は vs preflight で確認できます」と案内しているので、
        # ここで内訳を出さないと案内が堂々巡りになる。
        #
        # 全件出してよい。この枠に入るのは横断的な指摘（Guard・索引・用語集）だけで、
        # 章ごとの指摘のように数十件へ膨らむことがない。
        def print_unattached_details
          PreProcessCommands::IssueRegistry.issues.reject { it.chapter }.each do |issue|
            mark = issue.severity == :error ? '🔴' : '🟡'
            label = PreProcessCommands::IssueRegistry.category_label(issue.category)
            Common.log_always("      #{mark} [#{label}] #{issue.message}")
          end
        end

        # 表の行（[ラベル, Counts]）を章番号順に組み立てる。
        # registry のキーが entries に無い場合（コードインクルードの '(不明)' 等）も
        # 末尾へ足し、集計した指摘を表から取りこぼさない。
        def chapter_summary_rows(entries, by_chapter)
          sorted = entries.sort_by { it.number.to_i }
          rows = sorted.map { [chapter_summary_label(it), by_chapter[it.basename] || NO_ISSUES] }

          extras = by_chapter.keys.compact - sorted.map(&:basename)
          rows + extras.sort.map { [it, by_chapter[it]] }
        end

        # 「21 画像」のように番号＋章タイトルで表示する
        def chapter_summary_label(entry)
          number = entry.number ? format('%02d', entry.number.to_i) : ''
          "#{number} #{chapter_title(entry)}".strip
        end

        # 原稿冒頭の H1 見出しを章タイトルとして読む。
        # 見つからない・読めない場合はスラッグで代替する（表示だけの用途なので失敗させない）。
        def chapter_title(entry)
          return entry.slug.to_s unless entry.path && File.file?(entry.path)

          File.foreach(entry.path, encoding: 'utf-8').with_index do |line, idx|
            break if idx >= TITLE_SCAN_LINES

            matched = line.match(/\A#\s+(.+)/)
            return plain_title(matched[1]) if matched
          end
          entry.slug.to_s
        rescue StandardError
          entry.slug.to_s
        end

        # H1 には改行タグ・振り仮名・強調が入り得るため、1 行表示用に地の文だけを取り出す
        def plain_title(text)
          text.gsub(/<[^>]*>/, '')                       # <br> などのインライン HTML
              .gsub(/\{([^|{}]+)\|[^{}]*\}/, '\1')       # 振り仮名 {漢字|よみ} → 漢字
              .delete('*`')                              # 強調・コード記法の記号
              .squeeze(' ').strip
        end

        # ラベルを CHAPTER_LABEL_WIDTH に揃える（溢れは … で切り、不足は空白で埋める）
        def format_label(text)
          truncated = truncate_to_width(text, CHAPTER_LABEL_WIDTH)
          truncated + (' ' * [CHAPTER_LABEL_WIDTH - display_width(truncated), 0].max)
        end

        def truncate_to_width(text, width)
          return text if display_width(text) <= width

          kept = +''
          text.each_char do |char|
            break if display_width(kept) + display_width(char) > width - 1

            kept << char
          end
          "#{kept}…"
        end

        # 全角文字を 2 幅として数える（Metrics::Formatter と同じ数え方）
        def display_width(text) = text.each_char.sum { it.ascii_only? ? 1 : 2 }

        # 件数を 🔴 / 🟡 表示へ変換する。指摘ゼロは ✅。
        def issue_mark(counts)
          return '✅' if counts.clean?

          parts = []
          parts << "🔴 エラー #{counts.errors} 件" if counts.errors.positive?
          parts << "🟡 警告 #{counts.warns} 件" if counts.warns.positive?
          parts.join('・')
        end

        # preflight 完了サマリーを表示する。
        # 🔴 エラーあり / 🟡 警告のみ / ✅ 指摘なし の 3 段階（同 spec §1・§2.3）。
        # 終了コードは従来判定（LinkImageValidator.any_issues?）のままで、
        # ここで変えるのは文言だけ（警告件数を拾う）。
        def print_preflight_summary
          counts = PreProcessCommands::IssueRegistry.counts

          if counts.errors.positive?
            Common.log_result(
              "Preflight 完了: エラー #{counts.errors} 件・警告 #{counts.warns} 件 — 詳細は上記を確認してください",
              status: :failure
            )
          elsif counts.warns.positive?
            Common.log_result("Preflight 完了: 警告 #{counts.warns} 件（ビルドは可能です）", status: :warning)
          else
            Common.log_result('Preflight 完了: 良好な状態です', status: :success)
          end
          # preflight は構造チェックのみ。文章校正（textlint/spellcheck）は別コマンドへ誘導する。
          Common.log_always '   文章校正（表記揺れ・スペル）は vs lint で行えます。'
        end

        def print_usage
          puts <<~USAGE
            vs preflight - ビルド前の原稿エラーチェックを高速実行します

            Usage:
              vs preflight [targets...] [options]

            引数:
              targets...          チェック対象（章番号 / 範囲 / スラッグ）。省略時は全章

            オプション:
              --[no]-resize       画像最適化を行う（--no-resize で無効）         （既定: 有効）
              --[no]-verify       リンク・画像の基本検証を実行する（--no-verify でスキップ）（既定: 有効）
              --verify-links      外部 URL の HTTP 到達性チェックを実行する
              --log <level>       ログレベルを指定（error/warn/info/debug）
              -h, --help          このコマンドの使い方を表示

            終了コード:
              0: エラーなし（警告のみ、または問題なし）
              1: エラー1件以上、または実行時例外
          USAGE
        end

      end
    end
  end
end
