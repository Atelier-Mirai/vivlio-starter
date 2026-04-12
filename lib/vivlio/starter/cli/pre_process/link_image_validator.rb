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
#
# 設計方針:
#   - ビルドを止めない（警告のみ）
#   - ImagePathNormalizer が置換済みの data: URI を検出する方式（方式 A）
#   - 外部 URL チェックはオプション（--verify-links / book.yml）
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
            # @param config [Hash] 検証設定（verify_images, verify_bare_urls, verify_external_links）
            def validate(content, filename, config: resolve_config)
              image_issues = config[:verify_images] ? scan_missing_images(content, filename) : []
              link_issues = config[:verify_bare_urls] ? scan_bare_urls(content, filename) : []

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

              total_image = reports.sum { it.image_issues.size }
              total_link = reports.sum { it.link_issues.size }

              if total_image.zero? && total_link.zero?
                Common.echo_always('✅ リンク・画像の検証が完了しました（問題なし）')
                return
              end

              Common.echo_always ''
              Common.echo_always '🔍 リンク・画像検証の結果:'

              Common.echo_always "   画像: #{total_image} 件の問題（存在しない画像: #{total_image}）" if total_image.positive?

              if total_link.positive?
                bare = reports.sum { it.link_issues.count { |i| i.issue_type == :bare_url } }
                unreachable = reports.sum { it.link_issues.count { |i| i.issue_type == :unreachable } }
                parts = []
                parts << "リンク切れ: #{unreachable}" if unreachable.positive?
                parts << "裸 URL: #{bare}" if bare.positive?
                Common.echo_always "   リンク: #{total_link} 件の問題（#{parts.join(', ')}）"

                # リンク切れの詳細を表示
                reports.each do |report|
                  report.link_issues.select { it.issue_type == :unreachable }.each do |issue|
                    Common.echo_always "     ❌ #{issue.url} → #{issue.message}"
                    Common.echo_always "        参照元: #{issue.filename}:#{issue.line_number}"
                  end
                end
              end

              config = resolve_config
              Common.echo_always '   外部URL到達性チェック: スキップ（--verify-links で有効化）' unless config[:verify_external_links]

              Common.echo_always ''
            end

            # 検証が有効か判定する
            def any_verification_enabled?(config: resolve_config)
              config[:verify_images] || config[:verify_bare_urls] || config[:verify_external_links]
            end

            private

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

                  Common.log_warn("#{filename}:#{line_number} - 裸 URL を検出しました")
                  Common.log_warn("  URL: #{url}")
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
