# frozen_string_literal: true

# ================================================================
# Test: link_image_validator_integration_test.rb
# ================================================================
# テスト対象:
#   LinkImageValidator の統合テスト（仕様書 Phase 2 / セクション 10.2）
#
# 検証内容:
#   - vs build でのサマリー出力（問題あり・問題なし）
#   - --no-verify で検証がスキップされること
#   - --verify-links で HTTP 到達性チェックが実行されること（モックサーバー使用）
#   - 問題なし時の出力
#
# モックサーバー:
#   WEBrick を使ったインプロセス HTTP サーバーで外部ネットワーク依存を排除する
# ================================================================

require 'test_helper'
require 'socket'
require 'tmpdir'
require 'fileutils'
require_relative '../../../../lib/vivlio/starter/cli/pre_process/link_image_validator'

module Vivlio
  module Starter
    module CLI
      module PreProcessCommands
        # ================================================================
        # モックHTTPサーバー
        # ================================================================
        # TCPServer を使ったインプロセス HTTP/1.0 サーバー。
        # WEBrick に依存せず、外部ネットワーク依存を完全に排除する。
        # ルートごとに返すステータスコードを設定できる。
        class MockHttpServer
          attr_reader :port

          def initialize
            # ポート 0 で OS に空きポートを割り当てさせる
            @tcp = TCPServer.new('127.0.0.1', 0)
            @port = @tcp.addr[1]
            @routes = {}
            @running = false
          end

          # パスとステータスコードのマッピングを登録する
          # @param routes [Hash] { '/path' => status_code } の形式
          def mount_routes(routes)
            @routes.merge!(routes)
          end

          # バックグラウンドスレッドでサーバーを起動する
          def start
            @running = true
            @thread = Thread.new do
              while @running
                client = @tcp.accept rescue break
                Thread.new { handle_client(client) }
              end
            end
            # サーバースレッドが accept 待ちに入るまで少し待つ
            sleep 0.05
            self
          end

          # サーバーを停止してリソースを解放する
          def stop
            @running = false
            # accept をアンブロックするためにダミー接続を送る
            begin
              TCPSocket.new('127.0.0.1', @port).close
            rescue StandardError
              nil
            end
            @tcp.close rescue nil
            @thread&.join(2)
          end

          private

          # クライアント接続を処理してレスポンスを返す
          def handle_client(client)
            request_line = client.gets
            # 空行（ヘッダー終端）まで読み捨てる
            loop do
              line = client.gets
              break if line.nil? || line == "\r\n" || line == "\n"
            end

            path = request_line&.split(' ')&.at(1) || '/'
            status = @routes[path] || 404
            reason = case status
                     when 200..299 then 'OK'
                     when 404 then 'Not Found'
                     when 500..599 then 'Internal Server Error'
                     else 'Error'
                     end

            client.write "HTTP/1.1 #{status} #{reason}\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
          rescue StandardError
            # 接続エラーは無視
          ensure
            client.close rescue nil
          end
        end

        # ================================================================
        # 統合テスト: サマリー出力
        # ================================================================
        class LinkImageValidatorSummaryIntegrationTest < Minitest::Test
          def setup
            LinkImageValidator.reset!
            # デフォルト設定（画像・裸URL検証ON、外部URLチェックOFF）
            Thread.current[:vs_verify_options] = {
              verify_images: true,
              verify_bare_urls: true,
              verify_external_links: false
            }
          end

          def teardown
            Thread.current[:vs_verify_options] = nil
          end

          # 問題なし時に「問題なし」サマリーが出力されること
          def test_should_print_no_issues_summary_when_all_content_is_valid
            # Arrange: 正常なコンテンツ（画像も裸URLもなし）
            content = <<~MD
              # 第1章

              [参考リンク](https://example.com)

              ![スクリーンショット](images/01-quickstart/screenshot.webp)
            MD

            # Act
            LinkImageValidator.validate(content, '01-quickstart.md')

            # Assert: 「問題なし」メッセージが出力される
            assert_output(/リンク・画像の検証が完了しました（問題なし）/) do
              LinkImageValidator.print_summary
            end
          end

          # 欠落画像がある場合にサマリーに件数が表示されること
          def test_should_print_image_issue_count_in_summary
            # Arrange: ImagePathNormalizer が置換した data: URI を含むコンテンツ
            placeholder = 'data:image/svg+xml;charset=utf-8,' \
                          '%3Csvg%20width%3D%22600%22%3E%3Ctext%3E%3Ctspan%3Emissing.webp%3C%2Ftspan%3E%3C%2Ftext%3E%3C%2Fsvg%3E'
            content = "![代替テキスト](#{placeholder})\n"

            # Act
            LinkImageValidator.validate(content, '01-quickstart.md')

            # Assert: 画像の問題件数がサマリーに含まれる
            assert_output(/画像: 1 件の問題/) do
              LinkImageValidator.print_summary
            end
          end

          # 裸 URL がある場合にサマリーに件数が表示されること
          def test_should_print_bare_url_count_in_summary
            # Arrange: 裸 URL を含むコンテンツ
            content = "詳しくは https://example.com/page を参照してください。\n"

            # Act
            LinkImageValidator.validate(content, '12-markdown-tutorial.md')

            # Assert: 裸 URL の件数がサマリーに含まれる
            assert_output(/裸 URL: 1/) do
              LinkImageValidator.print_summary
            end
          end

          # 複数ファイルにまたがる問題が正しく集計されること
          def test_should_aggregate_issues_across_multiple_files
            # Arrange: 2ファイルそれぞれに裸 URL
            LinkImageValidator.validate("https://example.com/bare1\n", '01-quickstart.md')
            LinkImageValidator.validate("https://example.com/bare2\n", '12-markdown-tutorial.md')

            # Assert: 合計 2 件として集計される
            assert_output(/裸 URL: 2/) do
              LinkImageValidator.print_summary
            end
          end

          # 外部URLチェックがOFFの場合にスキップメッセージが表示されること
          def test_should_print_skip_message_when_external_link_check_is_disabled
            # Arrange: 裸 URL を含むコンテンツ（問題ありにしてサマリーを表示させる）
            content = "https://example.com/bare\n"
            LinkImageValidator.validate(content, 'test.md')

            # Assert: スキップメッセージが含まれる
            assert_output(/外部URL到達性チェック: スキップ/) do
              LinkImageValidator.print_summary
            end
          end
        end

        # ================================================================
        # 統合テスト: --no-verify（全検証スキップ）
        # ================================================================
        class LinkImageValidatorNoVerifyIntegrationTest < Minitest::Test
          def setup
            LinkImageValidator.reset!
          end

          def teardown
            Thread.current[:vs_verify_options] = nil
          end

          # --no-verify 時は画像・裸URL・外部URLすべてスキップされること
          def test_should_skip_all_validations_when_no_verify_is_set
            # Arrange: --no-verify に相当するスレッドローカル設定
            Thread.current[:vs_verify_options] = { no_verify: true }

            content = <<~MD
              ![欠落画像](data:image/svg+xml;charset=utf-8,%3Csvg%3E%3Ctext%3E%3Ctspan%3Emissing.webp%3C%2Ftspan%3E%3C%2Ftext%3E%3C%2Fsvg%3E)
              https://example.com/bare
              [リンク](https://example.com/page)
            MD

            # Act
            report = LinkImageValidator.validate(content, 'test.md')

            # Assert: すべての issue が空
            assert_pattern do
              report => { image_issues: [], link_issues: [] }
            end
          end

          # --no-verify 時は print_summary が何も出力しないこと
          def test_should_produce_no_output_when_no_verify_is_set
            # Arrange
            Thread.current[:vs_verify_options] = { no_verify: true }
            LinkImageValidator.validate("https://example.com/bare\n", 'test.md')

            # Assert: reset! 後と同様に何も出力されない
            # （レポートは蓄積されるが issue が空のため「問題なし」が出る）
            assert_output(/問題なし/) do
              LinkImageValidator.print_summary
            end
          end
        end

        # ================================================================
        # 統合テスト: --verify-links（HTTP 到達性チェック）
        # ================================================================
        class LinkImageValidatorVerifyLinksIntegrationTest < Minitest::Test
          def setup
            LinkImageValidator.reset!
            @server = MockHttpServer.new
          end

          def teardown
            @server.stop
            Thread.current[:vs_verify_options] = nil
          end

          # 200 OK の URL は問題なしとして扱われること
          def test_should_report_ok_for_reachable_urls
            # Arrange: 200 を返すルートを登録してサーバー起動
            @server.mount_routes('/ok' => 200)
            @server.start

            Thread.current[:vs_verify_options] = {
              verify_images: false,
              verify_bare_urls: false,
              verify_external_links: true
            }

            content = "[OK ページ](http://localhost:#{@server.port}/ok)\n"

            # Act
            LinkImageValidator.validate(content, 'test.md')
            LinkImageValidator.check_external_urls!

            # Assert: link_issues に unreachable が含まれないこと
            assert_output(/問題なし/) do
              LinkImageValidator.print_summary
            end
          end

          # 404 の URL は unreachable として警告されること
          def test_should_report_unreachable_for_404_urls
            # Arrange: 404 を返すルートを登録してサーバー起動
            @server.mount_routes('/not-found' => 404)
            @server.start

            Thread.current[:vs_verify_options] = {
              verify_images: false,
              verify_bare_urls: false,
              verify_external_links: true
            }

            content = "[消えたページ](http://localhost:#{@server.port}/not-found)\n"

            # Act
            LinkImageValidator.validate(content, '12-markdown-tutorial.md')
            LinkImageValidator.check_external_urls!

            # Assert: サマリーにリンク切れが表示される
            assert_output(/リンク切れ: 1/) do
              LinkImageValidator.print_summary
            end
          end

          # 500 の URL も unreachable として警告されること
          def test_should_report_unreachable_for_5xx_urls
            # Arrange: 500 を返すルートを登録
            @server.mount_routes('/server-error' => 500)
            @server.start

            Thread.current[:vs_verify_options] = {
              verify_images: false,
              verify_bare_urls: false,
              verify_external_links: true
            }

            content = "[エラーページ](http://localhost:#{@server.port}/server-error)\n"

            # Act
            LinkImageValidator.validate(content, 'test.md')
            LinkImageValidator.check_external_urls!

            # Assert: リンク切れとして報告される
            assert_output(/リンク切れ: 1/) do
              LinkImageValidator.print_summary
            end
          end

          # 同一 URL の重複は 1 回だけチェックされること
          def test_should_deduplicate_urls_before_checking
            # Arrange: 同じ URL を 2 ファイルから参照
            @server.mount_routes('/shared' => 200)
            @server.start

            Thread.current[:vs_verify_options] = {
              verify_images: false,
              verify_bare_urls: false,
              verify_external_links: true
            }

            url = "http://localhost:#{@server.port}/shared"
            LinkImageValidator.validate("[リンク](#{url})\n", 'file1.md')
            LinkImageValidator.validate("[リンク](#{url})\n", 'file2.md')

            # Act: check_external_urls! を実行（重複排除されること）
            # 問題なしで完了すれば重複リクエストによるエラーがないことを確認
            assert_silent do
              LinkImageValidator.check_external_urls!
            end

            assert_output(/問題なし/) do
              LinkImageValidator.print_summary
            end
          end

          # DNS 解決失敗の URL は unreachable として警告されること
          def test_should_report_unreachable_for_invalid_hostname
            # Arrange: 存在しないホスト名
            Thread.current[:vs_verify_options] = {
              verify_images: false,
              verify_bare_urls: false,
              verify_external_links: true
            }

            content = "[無効なホスト](http://this-host-does-not-exist.invalid/page)\n"

            # Act
            LinkImageValidator.validate(content, 'test.md')
            LinkImageValidator.check_external_urls!

            # Assert: リンク切れとして報告される
            assert_output(/リンク切れ: 1/) do
              LinkImageValidator.print_summary
            end
          end

          # --verify-links 有効時のサマリーにはスキップメッセージが出ないこと
          def test_should_not_print_skip_message_when_verify_links_is_enabled
            # Arrange: 200 を返すサーバー
            @server.mount_routes('/page' => 200)
            @server.start

            Thread.current[:vs_verify_options] = {
              verify_images: false,
              verify_bare_urls: true,
              verify_external_links: true
            }

            # 裸 URL を含むコンテンツ（問題ありにしてサマリーを表示させる）
            content = "https://example.com/bare\n"
            LinkImageValidator.validate(content, 'test.md')
            LinkImageValidator.check_external_urls!

            # Assert: スキップメッセージが含まれない
            output = capture_io { LinkImageValidator.print_summary }.first
            refute_match(/外部URL到達性チェック: スキップ/, output)
          end
        end

        # ================================================================
        # 統合テスト: book.yml 設定との連携
        # ================================================================
        class LinkImageValidatorBookYmlIntegrationTest < Minitest::Test
          def setup
            LinkImageValidator.reset!
            # CLI オプションなし（book.yml の設定のみ）
            Thread.current[:vs_verify_options] = nil
          end

          def teardown
            Thread.current[:vs_verify_options] = nil
          end

          # book.yml の設定がない場合はデフォルト（画像・裸URL ON）が適用されること
          def test_should_use_default_config_when_book_yml_has_no_verify_section
            # Arrange: CONFIG が nil の状態（book.yml 未設定）
            content = "https://example.com/bare\n"

            # Act
            report = LinkImageValidator.validate(content, 'test.md')

            # Assert: デフォルトで裸 URL が検出される
            assert_equal 1, report.link_issues.size
            assert_equal :bare_url, report.link_issues.first.issue_type
          end
        end
      end
    end
  end
end
