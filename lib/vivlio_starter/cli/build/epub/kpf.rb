# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/build/epub/kpf.rb
# ================================================================
# 責務:
#   KPF への変換と記録の要約
# ================================================================

require 'fileutils'
require 'tmpdir'
require_relative 'workspace'
require_relative '../vivliostyle_config_writer'

module VivlioStarter
  module CLI
    module Build
      # KPF への変換と記録の要約
      module Epub::Kpf
        module_function

        # ================================================================
        # Kindle KPF 変換（§1-7）
        # ================================================================

        # Kindle Previewer 4 の CLI（kindlepreviewer）コマンド名。
        KINDLEPREVIEWER_COMMAND = 'kindlepreviewer'

        # 変換を試みる回数。Kindle Previewer 4 が変換の入口で落ちたときだけ、1 回やり直す
        # （kpf_converter_aborted?）。
        KPF_ATTEMPTS = 2

        # Kindle Previewer が落ちたときに macOS がクラッシュレポートを書く場所。
        KPF_CRASH_REPORT_DIR = File.expand_path('~/Library/Logs/DiagnosticReports')

        # `-locale` が受け付ける綴り（`kindlepreviewer -help` より）。
        # **これは本の言語ではなく、変換ログと Previewer UI の表示言語**である。
        KPF_LOCALES = %w[en de fr it es zh ja pt nl].freeze

        # 対応表に無い言語での既定。Previewer 自身の既定でもある。
        KPF_LOCALE_FALLBACK = 'en'

        # `-locale` を `book.language` から導出する。
        #
        # **専用のキーは設けない**（`config-key-criteria-guidelines.md` §2.2「重複した入口」）。
        # 本の言語と工具の表示言語は概念としては別だが、`book.yml` に言語らしきキーが
        # 2 つ並ぶと著者はどちらを設定すべきか毎回迷う。しかも実際に見える差は小さい——
        # 変換ログ CSV は一時ディレクトリごと捨てており、著者へはこちらが日本語で
        # 要約して見せる（`summarize_kpf_logs`）。残る効きどころは Previewer の UI だけ。
        #
        # `ja-JP` のような地域付きは主要部分（`ja`）で解決する。対応表に無ければ `en`。
        #
        # @return [String] `-locale` へ渡す綴り
        def kpf_locale
          primary = VivliostyleConfigWriter.resolve_language.split(/[-_]/).first.to_s.downcase
          KPF_LOCALES.include?(primary) ? primary : KPF_LOCALE_FALLBACK
        end

        # kindlepreviewer が PATH 上に存在するかを返す。テストでは本メソッドをスタブして
        # 「未導入時はスキップして継続」する経路を検証する（DI・§5-1）。
        #
        # @param command [String] チェックするコマンド名
        # @return [Boolean]
        def kindlepreviewer_available?(command = KINDLEPREVIEWER_COMMAND)
          Common.external_command_available?(command)
        end

        # kindlepreviewer が Kindle Previewer 3 か。KPF の変換には 4 を使うので、3 では変換しない。
        #
        # 3 のオプションは `-convert`、4 は `--convert` なので、`-help` の綴りで見分ける。
        # 版の番号を解析しないのは、4.1 以降で表記が変わっても綴りを直接見るほうが
        # 壊れにくいためである。ラッパーの向き先が無いときは綴りが出ないので false を返し、
        # 変換の失敗として報告する。
        #
        # @param command [String] kindlepreviewer コマンド名
        # @return [Boolean]
        def kindle_previewer_3?(command = KINDLEPREVIEWER_COMMAND)
          `#{command} -help 2>&1`.match?(/(?<!-)-convert/)
        rescue StandardError
          false
        end

        # Kindle 用中間 EPUB を kindlepreviewer で KPF へ変換し、kpf_path へ回収する（§1-7）。
        # 変換ログ（Summary_Log.csv / Logs/*_log.csv）の Error/Quality 件数を log_summary で要約する。
        # 未導入・変換失敗時は false を返し（中間 EPUB は残す）、ビルド全体は止めない。
        #
        # @param epub_path [String] 入力 Kindle EPUB（…-kindle.epub）
        # @param kpf_path [String] 出力 KPF（ルート直下）
        # @param locale [String] kindlepreviewer の -locale（既定は book.language 由来）
        # @param command [String] kindlepreviewer コマンド名（DI 用）
        # @return [Boolean] KPF を生成できたか
        def convert_epub_to_kpf!(epub_path, kpf_path, locale: kpf_locale, command: KINDLEPREVIEWER_COMMAND)
          return false unless File.exist?(epub_path)

          unless kindlepreviewer_available?(command)
            # 入れ方は、ビルドの終わりに Build::KindlePreviewerNotice が 1 度だけ 💡 で知らせる
            # （改善案.md #87）。ここで 🟡 を出すと、同じことを 2 度言うことになる
            Common.log_info("[KPF] #{command} が見つからないため、KPF への変換を飛ばしました（中間 EPUB: #{epub_path}）")
            return false
          end

          if kindle_previewer_3?(command)
            DoctorCommands.report_kindle_previewer_outdated
            Common.log_info("[KPF] Kindle Previewer 3 では変換しないため、KPF への変換を飛ばしました（中間 EPUB: #{epub_path}）")
            return false
          end

          Common.log_action("[KPF] #{File.basename(epub_path)} を KPF へ変換しています…")
          since = Time.now
          KPF_ATTEMPTS.times do |attempt|
            Dir.mktmpdir('vs-kpf') do |outdir|
              return true if run_kpf_conversion(epub_path, kpf_path, outdir, locale:, command:)

              # 本の変換ログすら残さずに終わったときだけやり直す。変換を終えて KPF が出なかった
              # （Mobi が出た・エラーがあった）ときは、やり直しても結果は変わらない。
              if kpf_converter_aborted?(outdir) && attempt + 1 < KPF_ATTEMPTS
                Common.log_warn('[KPF] Kindle Previewer が変換の途中で終了しました。もう一度変換します')
                next
              end

              report_missing_kpf(outdir, epub_path, since:)
              return false
            end
          end
        end

        # 変換を 1 回だけ走らせ、KPF ができたら kpf_path へ移す。
        # @return [Boolean] KPF を生成できたか
        def run_kpf_conversion(epub_path, kpf_path, outdir, locale:, command:)
          ok = system(command, File.expand_path(epub_path), '--convert', '--output', outdir,
                      '--locale', locale, out: File::NULL, err: File::NULL)
          summarize_kpf_logs(outdir)

          kpf = Dir.glob(File.join(outdir, '**', '*.kpf')).max_by { File.mtime(it) }
          return false unless ok && kpf

          FileUtils.rm_f(kpf_path)
          FileUtils.mv(kpf, kpf_path)
          Common.log_success("[KPF] KPF を生成しました: #{kpf_path}")
          true
        end

        # Kindle Previewer が本を変換する前に終わったか。
        #
        # **Kindle Previewer 4（4.0.3）は、ときどき変換の入口で落ちる。** 変換の本体（Java）を
        # 起動する `fork` の直後、子プロセスが「os_once_t is corrupt」で止まる。複数スレッドの
        # プロセスから fork したときに起きる macOS の競合で、起きるかどうかは巡り合わせ次第
        # （実測 2026-10-12: その日のおよそ 12 回の変換で 1 回）。vs からは防げないが、
        # やり直せば通る。
        #
        # 見分けは「本ごとの変換ログ（Logs/*_log.csv）が無い」こと。変換まで進めば、エラーで
        # KPF が出なかったときでもこのログは残る。落ちたときは Summary_Log.csv しか残らない。
        def kpf_converter_aborted?(outdir)
          Dir.glob(File.join(outdir, '**', '*.{kpf,mobi}')).empty? &&
            Dir.glob(File.join(outdir, 'Logs', '*.csv')).empty?
        end

        # KPF が出なかった理由を、次に何をすればよいか分かる形で伝える。
        #
        # 紛らわしいのは「変換は成功したのに Mobi が出た」形である。Kindle Previewer が
        # Enhanced Typesetting を無効と判定したときで、引き金は**同梱された SVG**
        # （`kindle-css-compatibility-notes.md` §5.5）。ツールが落ちたときと同じ文面で
        # 流すと、原因に辿り着けないまま中間 EPUB だけが残る。
        #
        # ツールが落ちていれば、macOS が残したクラッシュレポートを添える。vs の不具合と
        # 取り違えないよう、もう一度ビルドすればよいことをはっきり書く。
        def report_missing_kpf(outdir, epub_path, since: nil, report_dir: KPF_CRASH_REPORT_DIR)
          unless Dir.glob(File.join(outdir, '**', '*.mobi')).any?
            crash = since && kpf_crash_report(since, report_dir)
            detail = if crash
                       "→ Kindle Previewer が落ちました（vs の不具合ではありません）。もう一度 vs build してください。\n" \
                         "  クラッシュレポート: #{crash}"
                     end
            Common.log_error("[KPF] Kindle 変換に失敗しました。中間 EPUB を残します: #{epub_path}", detail:)
            return
          end

          Common.log_error(
            '[KPF] Enhanced Typesetting が無効と判定され、KPF ではなく Mobi が出ました',
            detail: '→ 同梱された SVG が引き金になることがあります（Kindle Previewer 4 は SVG が 1 枚でもあると ET を落とします）。' \
                    "次で中身を確かめてください: unzip -l #{epub_path} | grep '\\.svg'"
          )
        end

        # since 以降に書かれた Kindle Previewer のクラッシュレポート（無ければ nil）。
        def kpf_crash_report(since, report_dir = KPF_CRASH_REPORT_DIR)
          Dir.glob(File.join(report_dir, 'KindlePreviewer*.ips'))
             .select { File.mtime(it) >= since }
             .max_by { File.mtime(it) }
        end

        # ほかの行のまとめにすぎないコード。W14002「解決できないハイパーリンクがあります」は、
        # 個々のリンクを挙げる W14001 と同じことを言い直すだけなので並べない（件数には数える）。
        KPF_SUMMARY_CODES = %w[W14002].freeze

        # vs が意図して起こしていて、著者がすることのないコード。表示も件数もしない。
        # W14016「カバーが指定されていません」は、Kindle 用 EPUB に表紙を埋め込まない（embed:false 固定・
        # KDP では表紙を別にアップロードする・43 章）ために毎回出る。Kindle Previewer は表紙を EPUB に
        # 含めて納める出版社にも使われる道具なので、表紙の無い EPUB には一律に注意を出す
        KPF_EXPECTED_CODES = %w[W14016].freeze

        # kindlepreviewer の変換ログを、コードと説明文つきで要約表示する。
        #
        # 本ごとのログ（Logs/*_log.csv）は 1 行に 1 件、「種類, 説明, ソースファイル, 行番号,
        # 前のテキスト, 推奨される修正」の列を持ち、説明は `W14001: …` とコードで始まる。
        # 以前はコードの件数だけを出していて、`W14001×2` と言われても著者には分からなかった。
        # 説明は `--locale` の言語で書かれる。一時ディレクトリのパスは削り、EPUB の中の
        # ファイル名だけを残す。版差でファイル名が変わっても拾えるよう出力配下の全 CSV を走査し、
        # ヘッダ列名（"Error" 等の語）を数えないよう、コード（E#####/W#####）のある行だけを読む。
        # 想定どおりのコード（KPF_EXPECTED_CODES）しか無ければ何も出さない。
        def summarize_kpf_logs(outdir)
          csvs = Dir.glob(File.join(outdir, '**', '*.csv'))
          return if csvs.empty?

          rows = csvs.flat_map { kpf_log_rows(it) }.reject { KPF_EXPECTED_CODES.include?(it[:code]) }
          return if rows.empty?

          errors  = rows.count { it[:code].start_with?('E') }
          notices = rows.count { it[:code].start_with?('W') }
          headline = "[KPF] 変換ログ: エラー #{errors} 件・注意 #{notices} 件"
          headline += '（注意は出版を止めません）' if errors.zero? && notices.positive?
          lines = rows.reject { KPF_SUMMARY_CODES.include?(it[:code]) }.sort_by { it[:code] }.map { kpf_log_line(it) }
          Common.log_summary(headline, detail: lines.empty? ? nil : lines.join("\n"))
        rescue StandardError => e
          Common.log_warn("[KPF] 変換ログの解析に失敗: #{e.message}")
        end

        # 変換ログ 1 本から、コードのある行を { code:, text:, fix: } で返す。
        def kpf_log_rows(csv)
          File.foreach(csv, encoding: 'bom|utf-8').filter_map do |line|
            code = line[/\b([EW]\d{4,5})\b/, 1]
            next unless code

            fields = csv_fields(line.chomp)
            description = fields.find { it.include?(code) } || line
            text = description.sub(/\A.*?#{code}:?\s*/, '').gsub(%r{\S*/EPUB/}, '').squeeze(' ').strip
            { code:, text:, fix: fields[5].to_s.strip }
          end
        rescue StandardError
          []
        end

        # 表示する 1 行。Kindle Previewer の推奨される修正があれば添える
        def kpf_log_line(row)
          line = "#{row[:code]} #{row[:text]}"
          line += " → #{row[:fix]}" unless row[:fix].empty?
          line
        end

        # 引用符で囲んだ CSV の 1 行を列に分ける（"" は " に戻す）。csv gem は依存に入れていない
        def csv_fields(line)
          line.scan(/(?:\A|,)(?:"((?:[^"]|"")*)"|([^,]*))/).map { (it[0] || it[1]).to_s.gsub('""', '"') }
        end
      end
    end
  end
end
