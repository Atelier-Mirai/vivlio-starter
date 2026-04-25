# frozen_string_literal: true

# ================================================================
# File: lib/vivlio/starter/cli/pre_process/link_image_validator.rb
# ================================================================
# 責務:
#   Markdown 原稿内のリンクと画像パスを自動検証し、問題を報告する。
#
# 検証内容:
#   - ローカル画像パスの存在チェック（プレースホルダー置換済みの data: URI を検出）
#   - 裸 URL（Markdown リンク記法でない直書き URL）の検出
#   - 外部 URL の HTTP 到達性チェック（オプション）
#   - 危険スキーム（file:// / javascript:）の検出 — セキュリティ保護、常時有効
#
# 設計方針:
#   - ビルドを止めない（警告のみ）
#   - ImagePathNormalizer が置換済みの data: URI を検出する方式（方式 A）
#   - 外部 URL チェックはオプション（--verify-links / book.yml）
#   - 危険スキームの検出はセキュリティ保護であり、--no-verify でも無効化できない
#
# セキュリティ観点（堅牢性仕様 11-1）:
#   原稿内の `<img src="file:///etc/passwd">` 等によるローカルファイル漏洩を
#   ビルド前の静的解析で検出し、警告する。Vivliostyle/Chromium のポリシーに
#   一切頼らず、Ruby 側で明示的にブロックする第一の防衛線。
# ================================================================

require 'net/http'
require 'uri'
require 'monitor'
require_relative '../common'

module Vivlio
  module Starter
    module CLI
      module PreProcessCommands
        module LinkImageValidator
          # 画像検証の単一結果
          ImageIssue = Data.define(:filename, :line_number, :image_path, :issue_type)

          # URL 検証の単一結果
          LinkIssue = Data.define(:filename, :line_number, :url, :issue_type, :status_code, :message)

          # ファイル単位の検証結果
          ValidationReport = Data.define(:filename, :image_issues, :link_issues)

          # --- グローバル蓄積用（スレッドセーフ） ---
          @monitor = Monitor.new
          @reports = []
          @external_urls = []

          class << self
            # レポート蓄積をリセットする（ビルド開始時に呼ぶ）
            def reset!
              @monitor.synchronize do
                @reports = []
                @external_urls = []
              end
            end

            # ファイル単位の検証を実行し、レポートを蓄積する
            # @param content [String] Markdown テキスト（画像パス正規化済み）
            # @param filename [String] 対象ファイル名
            # @param source_path [String, nil] 元ファイルのパス（行番号補正用）
            # @param config [Hash] 検証設定（verify_images, verify_bare_urls, verify_external_links）
            def validate(content, filename, source_path: nil, config: resolve_config)
              source_content = source_path && File.exist?(source_path) ? File.read(source_path, encoding: 'utf-8') : nil

              image_issues = config[:verify_images] ? scan_missing_images(content, filename) : []
              link_issues = config[:verify_bare_urls] ? scan_bare_urls(content, filename) : []

              # 行番号を元ファイルの行番号に補正する
              if source_content
                image_issues = image_issues.map { correct_line_number(it, source_content) }
                link_issues = link_issues.map { correct_link_line_number(it, source_content) }
              end

              # 補正後の行番号でログを出力
              link_issues.select { it.issue_type == :bare_url }.each do |issue|
                Common.log_warn(
                  "#{issue.filename}:#{issue.line_number} - 裸 URL を検出しました",
                  detail: "URL: #{issue.url}"
                )
              end

              # セキュリティ検証（11-1）: 危険スキームの検出は常時有効
              # file:// / javascript: 等は --no-verify でも無効化しない
              link_issues += scan_dangerous_schemes(content, filename)

              # 外部 URL チェック用に URL を蓄積（後でバッチ実行）
              if config[:verify_external_links]
                urls = extract_external_urls(content, filename)
                @monitor.synchronize { @external_urls.concat(urls) }
              end

              report = ValidationReport.new(filename:, image_issues:, link_issues:)
              @monitor.synchronize { @reports << report }
              report
            end

            # 蓄積された外部 URL に対して HTTP 到達性チェックを実行する
            def check_external_urls!
              config = resolve_config
              return unless config[:verify_external_links]

              urls = @monitor.synchronize { @external_urls.dup }
              return if urls.empty?

              # URL を重複排除（同じ URL は 1 回だけチェック）
              unique_urls = urls.uniq { it[:url] }
              Common.log_action("[検証] 外部 URL の到達性を確認しています（#{unique_urls.size} 件）…")

              results = check_urls_batch(unique_urls, config)

              # 結果をレポートに反映
              results.each do |result|
                next if result[:ok]

                issue = LinkIssue.new(
                  filename: result[:filename],
                  line_number: result[:line_number],
                  url: result[:url],
                  issue_type: :unreachable,
                  status_code: result[:status_code],
                  message: result[:message]
                )
                add_link_issue_to_report(result[:filename], issue)
              end
            end

            # 検証結果のサマリーを表示する
            def print_summary
              reports = @monitor.synchronize { @reports.dup }
              return if reports.empty?

              total_missing_image = reports.sum { it.image_issues.count { |i| i.issue_type == :missing } }
              total_missing_code  = reports.sum { it.image_issues.count { |i| i.issue_type == :missing_code } }
              total_link = reports.sum { it.link_issues.size }

              if total_missing_image.zero? && total_missing_code.zero? && total_link.zero?
                Common.log_info('リンク・画像の検証が完了しました（良好な状態です）')
                return
              end

              # --- サマリー集計 ---
              detail_lines = []
              detail_lines << "画像: #{total_missing_image} 件の課題（存在しない画像: #{total_missing_image}）" if total_missing_image.positive?
              detail_lines << "ソースコード: #{total_missing_code} 件の課題（存在しないファイル: #{total_missing_code}）" if total_missing_code.positive?

              if total_link.positive?
                bare = reports.sum { it.link_issues.count { |i| i.issue_type == :bare_url } }
                unreachable = reports.sum { it.link_issues.count { |i| i.issue_type == :unreachable } }
                dangerous = reports.sum { it.link_issues.count { |i| i.issue_type == :dangerous_scheme } }
                parts = []
                parts << "危険スキーム: #{dangerous}" if dangerous.positive?
                parts << "リンク切れ: #{unreachable}" if unreachable.positive?
                parts << "裸 URL: #{bare}" if bare.positive?
                detail_lines << "リンク: #{total_link} 件の問題（#{parts.join(', ')}）"
              end

              config = resolve_config
              detail_lines << '外部URL到達性チェック: スキップ（--verify-links で有効化）' unless config[:verify_external_links]

              Common.log_summary('リンク・画像検証の結果:', detail: detail_lines.join("\n"))

              # --- 危険スキームの詳細（セキュリティ上の重要度が高いため先頭）---
              reports.each do |report|
                report.link_issues.select { it.issue_type == :dangerous_scheme }.each do |issue|
                  Common.log_warn(
                    "#{issue.filename}:#{issue.line_number} - 危険なスキームを検出しました",
                    detail: "URL: #{issue.url}\n#{issue.message}"
                  )
                end
              end

              # --- リンク切れの詳細 ---
              reports.each do |report|
                report.link_issues.select { it.issue_type == :unreachable }.each do |issue|
                  Common.log_error(
                    "#{issue.filename}:#{issue.line_number} - リンク切れを検出しました",
                    detail: "URL: #{issue.url} → #{issue.message}"
                  )
                end
              end
            end

            # 検証が有効か判定する
            def any_verification_enabled?(config: resolve_config)
              config[:verify_images] || config[:verify_bare_urls] || config[:verify_external_links]
            end

            # 蓄積されたレポートにエラー（issue）が1件以上あるか判定する
            def any_issues?
              @monitor.synchronize do
                @reports.any? { |r| r.image_issues.any? || r.link_issues.any? }
              end
            end

            # コードインクルードエラーをレポートに記録する
            # MarkdownTransformer から呼ばれ、preflight の終了コード判定に反映させる
            # @param filename [String] ソースファイル名
            # @param line_number [Integer] 行番号
            # @param code_name [String] 見つからなかったコードファイル名
            def record_code_include_error(filename, line_number, code_name)
              issue = ImageIssue.new(
                filename:,
                line_number:,
                image_path: code_name,
                issue_type: :missing_code
              )
              @monitor.synchronize do
                report = @reports.find { it.filename == filename }
                if report
                  idx = @reports.index(report)
                  @reports[idx] = ValidationReport.new(
                    filename: report.filename,
                    image_issues: report.image_issues + [issue],
                    link_issues: report.link_issues
                  )
                else
                  # process_code_includes! は validate の後に実行されるため、
                  # レポートが存在しない場合は新規作成する
                  @reports << ValidationReport.new(filename:, image_issues: [issue], link_issues: [])
                end
              end
            end

            private

            # 画像 issue の行番号を元ファイルの行番号に補正する。
            # プレースホルダー SVG から抽出した画像名を元ファイルで検索し、
            # 元ファイルでの行番号を返す。
            def correct_line_number(issue, source_content)
              image_name = issue.image_path
              return issue if image_name == '(不明)'

              # 元ファイルで画像名を含む行を探す
              source_content.each_line.with_index(1) do |line, idx|
                if line.include?(image_name) && line.match?(/!\[/)
                  return ImageIssue.new(
                    filename: issue.filename,
                    line_number: idx,
                    image_path: issue.image_path,
                    issue_type: issue.issue_type
                  )
                end
              end

              issue
            end

            # リンク issue の行番号を元ファイルの行番号に補正する。
            def correct_link_line_number(issue, source_content)
              url = issue.url
              source_content.each_line.with_index(1) do |line, idx|
                if line.include?(url)
                  return LinkIssue.new(
                    filename: issue.filename,
                    line_number: idx,
                    url: issue.url,
                    issue_type: issue.issue_type,
                    status_code: issue.status_code,
                    message: issue.message
                  )
                end
              end

              issue
            end

            # book.yml + CLI オプションから検証設定を解決する
            def resolve_config
              build_cfg = Common::CONFIG&.dig(:build, :verify) || {}
              cli_opts = Thread.current[:vs_verify_options] || {}

              # --no-verify で全無効
              if cli_opts[:no_verify]
                return { verify_images: false, verify_bare_urls: false, verify_external_links: false,
                         timeout: 10, max_concurrency: 5 }
              end

              {
                verify_images: cli_opts.fetch(:verify_images, build_cfg.fetch(:images, true)),
                verify_bare_urls: cli_opts.fetch(:verify_bare_urls, build_cfg.fetch(:bare_urls, true)),
                verify_external_links: cli_opts.fetch(:verify_external_links, build_cfg.fetch(:external_links, false)),
                timeout: build_cfg.fetch(:timeout, 10),
                max_concurrency: build_cfg.fetch(:max_concurrency, 5)
              }
            end

            # --- Phase: 画像パス検証 ---

            # プレースホルダー（data: URI）に置換された画像を検出する
            # ImagePathNormalizer が存在しない画像を data: URI に置き換えるため、
            # その痕跡から欠落画像を特定する
            def scan_missing_images(content, filename)
              issues = []
              in_code_block = false

              content.each_line.with_index(1) do |line, line_number|
                stripped = line.lstrip

                if stripped.start_with?('```')
                  in_code_block = !in_code_block
                  next
                end
                next if in_code_block

                # data: URI に置換された画像を検出
                line.scan(%r{!\[([^\]]*)\]\((data:image/svg\+xml[^)]+)\)}) do
                  # プレースホルダー SVG 内にファイル名が埋め込まれている
                  data_uri = ::Regexp.last_match(2)
                  image_name = extract_image_name_from_placeholder(data_uri)

                  issues << ImageIssue.new(
                    filename:,
                    line_number:,
                    image_path: image_name || '(不明)',
                    issue_type: :missing
                  )
                end
              end

              issues
            end

            # プレースホルダー SVG の data URI からファイル名を抽出する
            def extract_image_name_from_placeholder(data_uri)
              # URL デコードして SVG テキスト内のファイル名を取得
              decoded = URI.decode_www_form_component(data_uri.sub(%r{\Adata:image/svg\+xml;charset=utf-8,}, ''))
              match = decoded.match(%r{<tspan[^>]*>([^<]+)</tspan>})
              match ? match[1] : nil
            rescue StandardError
              nil
            end

            # --- Phase: 危険スキーム検出（セキュリティ／堅牢性 11-1）---

            # Markdown 原稿内の危険スキーム（file:// / javascript:）を検出する
            #
            # 検出対象:
            #   - HTML タグ: <img src="file:///..."> / <a href="javascript:...">
            #   - Markdown 画像: ![](file:///...)
            #   - Markdown リンク: [text](javascript:alert(1))
            #
            # ImagePathNormalizer が生成する `data:image/svg+xml;...` プレースホルダーは
            # 安全なスキームとして除外する（scan_missing_images で別途検出される）。
            #
            # @param content [String] Markdown テキスト
            # @param filename [String] 対象ファイル名
            # @return [Array<LinkIssue>] 検出された issue の配列
            def scan_dangerous_schemes(content, filename)
              issues = []
              in_code_block = false

              content.each_line.with_index(1) do |line, line_number|
                stripped = line.lstrip

                if stripped.start_with?('```')
                  in_code_block = !in_code_block
                  next
                end
                next if in_code_block

                # インラインコード内はスキップ（説明文中の例示を無視）
                scannable = line.gsub(/`[^`]+`/, '')

                # (1) HTML タグの src / href 属性
                #     <img src="file:///..."> / <a href="javascript:...">
                scannable.scan(/\b(?:src|href)\s*=\s*["'](file:[^"']*|javascript:[^"']*)["']/i) do
                  url = ::Regexp.last_match(1)
                  issues << build_dangerous_issue(filename, line_number, url)
                end

                # (2) Markdown 画像記法: ![](file:///...)
                scannable.scan(/!\[[^\]]*\]\((file:[^)]*|javascript:[^)]*)\)/i) do
                  url = ::Regexp.last_match(1)
                  issues << build_dangerous_issue(filename, line_number, url)
                end

                # (3) Markdown リンク記法: [text](javascript:...) / [text](file:///...)
                #     ただし画像記法 ![](...)（上の (2)）と被らないよう、直前 ! を除外
                scannable.scan(/(?<!\!)\[[^\]]*\]\((file:[^)]*|javascript:[^)]*)\)/i) do
                  url = ::Regexp.last_match(1)
                  issues << build_dangerous_issue(filename, line_number, url)
                end
              end

              issues
            end

            # 危険スキーム検出 issue を生成しつつ警告ログを出力する
            def build_dangerous_issue(filename, line_number, url)
              scheme_label = url.match?(/\Afile:/i) ? 'file://' : 'javascript:'
              Common.log_warn(
                "#{filename}:#{line_number} - 危険なスキームを検出しました（#{scheme_label}）",
                detail: "URL: #{url}\n→ ローカルファイル漏洩 / スクリプト注入のリスクがあります。"
              )

              LinkIssue.new(
                filename:,
                line_number:,
                url:,
                issue_type: :dangerous_scheme,
                status_code: nil,
                message: "危険なスキーム（#{scheme_label}）: ローカルファイル漏洩 / スクリプト注入のリスク"
              )
            end

            # --- Phase: 裸 URL 検出 ---

            # Markdown リンク記法でない直書き URL を検出する
            def scan_bare_urls(content, filename)
              issues = []
              in_code_block = false

              content.each_line.with_index(1) do |line, line_number|
                stripped = line.lstrip

                if stripped.start_with?('```')
                  in_code_block = !in_code_block
                  next
                end
                next if in_code_block

                # インラインコード内はスキップ
                line_without_inline_code = line.gsub(/`[^`]+`/, '')

                # 脚注定義行はスキップ
                next if line_without_inline_code.match?(/^\[\^[^\]]+\]:/)

                # 裸 URL を検出（Markdown リンク記法の中にある URL は除外）
                # ](https://...) や [text](https://...) は正規のリンク記法
                line_without_inline_code.scan(%r{(?<!\]\()(?<!\()https?://[^\s)\]>]+}) do |url|
                  # Markdown リンクの URL 部分として使われていないか再確認
                  # [text](URL) のパターンに含まれる URL は脚注化で処理済み
                  next if line.include?("](#{url})")

                  issues << LinkIssue.new(
                    filename:,
                    line_number:,
                    url:,
                    issue_type: :bare_url,
                    status_code: nil,
                    message: '裸 URL です（リンク記法 [テキスト](URL) の使用を推奨します）'
                  )
                end
              end

              issues
            end

            # --- Phase: 外部 URL 収集 ---

            # Markdown リンク記法から外部 URL を抽出する
            def extract_external_urls(content, filename)
              urls = []
              in_code_block = false

              content.each_line.with_index(1) do |line, line_number|
                stripped = line.lstrip

                if stripped.start_with?('```')
                  in_code_block = !in_code_block
                  next
                end
                next if in_code_block

                # Markdown リンク記法 [text](https://...)
                line.scan(%r{\[([^\]]*)\]\((https?://[^\s)]+)\)}) do
                  urls << { url: ::Regexp.last_match(2), filename:, line_number: }
                end
              end

              urls
            end

            # --- Phase: HTTP 到達性チェック ---

            # 外部 URL にバッチで HEAD リクエストを送信する
            def check_urls_batch(url_entries, config)
              timeout = config[:timeout] || 10
              max_concurrency = config[:max_concurrency] || 5
              results = []
              mutex = Mutex.new

              # 最大同時接続数でスレッドプール実行
              url_entries.each_slice(max_concurrency) do |batch|
                threads = batch.map do |entry|
                  Thread.new do
                    result = check_single_url(entry[:url], timeout)
                    result[:filename] = entry[:filename]
                    result[:line_number] = entry[:line_number]
                    mutex.synchronize { results << result }
                  end
                end
                threads.each(&:join)
              end

              results
            end

            # 単一 URL に HEAD リクエストを送信する
            def check_single_url(url, timeout)
              uri = URI.parse(url)
              http = Net::HTTP.new(uri.host, uri.port)
              http.use_ssl = (uri.scheme == 'https')
              http.open_timeout = timeout
              http.read_timeout = timeout

              response = http.request_head(uri.request_uri)
              status = response.code.to_i

              if status < 400
                { url:, ok: true, status_code: status, message: "#{status} #{response.message}" }
              else
                { url:, ok: false, status_code: status, message: "#{status} #{response.message}" }
              end
            rescue Net::OpenTimeout, Net::ReadTimeout
              { url:, ok: false, status_code: nil, message: 'タイムアウト' }
            rescue SocketError => e
              { url:, ok: false, status_code: nil, message: "DNS 解決失敗: #{e.message}" }
            rescue StandardError => e
              { url:, ok: false, status_code: nil, message: "エラー: #{e.message}" }
            end

            # レポートにリンク issue を追加する
            def add_link_issue_to_report(filename, issue)
              @monitor.synchronize do
                report = @reports.find { it.filename == filename }
                if report
                  # Data.define は immutable なので、新しいレポートで置き換え
                  idx = @reports.index(report)
                  @reports[idx] = ValidationReport.new(
                    filename: report.filename,
                    image_issues: report.image_issues,
                    link_issues: report.link_issues + [issue]
                  )
                end
              end
            end
          end
        end
      end
    end
  end
end
