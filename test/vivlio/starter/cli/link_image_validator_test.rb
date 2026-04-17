# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../../../../lib/vivlio/starter/cli/pre_process/link_image_validator'

module Vivlio
  module Starter
    module CLI
      module PreProcessCommands
        class LinkImageValidatorTest < Minitest::Test
          def setup
            LinkImageValidator.reset!
            # 検証を全有効にするスレッドローカル設定
            Thread.current[:vs_verify_options] = {
              verify_images: true,
              verify_bare_urls: true,
              verify_external_links: false
            }
          end

          def teardown
            Thread.current[:vs_verify_options] = nil
          end

          # =================================================================
          # 画像パス検証（プレースホルダー data: URI の検出）
          # =================================================================

          # data: URI に置換された画像が検出されること
          def test_should_detect_placeholder_images
            content = <<~MD
              # テスト章

              ![代替テキスト](data:image/svg+xml;charset=utf-8,%3Csvg%20width%3D%22600%22%3E%3Ctext%3E%3Ctspan%20fill%3D%22url(%23vivlioTextGradient)%22%3Efoo.webp%3C%2Ftspan%3E%3C%2Ftext%3E%3C%2Fsvg%3E)
            MD

            report = LinkImageValidator.validate(content, 'test.md')

            assert_equal 1, report.image_issues.size
            assert_equal :missing, report.image_issues.first.issue_type
            assert_equal 3, report.image_issues.first.line_number
          end

          # 正常な画像パスは検出されないこと
          def test_should_not_flag_normal_images
            content = <<~MD
              ![テスト](images/01-test/screenshot.webp)
            MD

            report = LinkImageValidator.validate(content, 'test.md')

            assert_empty report.image_issues
          end

          # コードブロック内の画像記法は無視されること
          def test_should_skip_images_in_code_blocks
            content = <<~MD
              ```markdown
              ![代替テキスト](data:image/svg+xml;charset=utf-8,%3Csvg%3E%3Ctext%3E%3Ctspan%3Efoo.webp%3C%2Ftspan%3E%3C%2Ftext%3E%3C%2Fsvg%3E)
              ```
            MD

            report = LinkImageValidator.validate(content, 'test.md')

            assert_empty report.image_issues
          end

          # =================================================================
          # 裸 URL 検出
          # =================================================================

          # 裸 URL が検出されること
          def test_should_detect_bare_urls
            content = <<~MD
              詳しくは https://example.com/page を参照してください。
            MD

            report = LinkImageValidator.validate(content, 'test.md')

            assert_equal 1, report.link_issues.size
            assert_equal :bare_url, report.link_issues.first.issue_type
            assert_equal 'https://example.com/page', report.link_issues.first.url
          end

          # Markdown リンク記法の URL は裸 URL として検出されないこと
          def test_should_not_flag_markdown_links
            content = <<~MD
              [参考ページ](https://example.com/page)
            MD

            report = LinkImageValidator.validate(content, 'test.md')

            assert_empty report.link_issues
          end

          # コードブロック内の URL は無視されること
          def test_should_skip_urls_in_code_blocks
            content = <<~MD
              ```bash
              curl https://example.com/api
              ```
            MD

            report = LinkImageValidator.validate(content, 'test.md')

            assert_empty report.link_issues
          end

          # インラインコード内の URL は無視されること
          def test_should_skip_urls_in_inline_code
            content = <<~MD
              URL は `https://example.com/api` です。
            MD

            report = LinkImageValidator.validate(content, 'test.md')

            assert_empty report.link_issues
          end

          # 脚注定義行の URL は裸 URL として検出されないこと
          def test_should_skip_footnote_definition_urls
            content = <<~MD
              [^url1]: https://example.com/page
            MD

            report = LinkImageValidator.validate(content, 'test.md')

            assert_empty report.link_issues
          end

          # クエリパラメータ付き裸 URL が正しく検出されること
          def test_should_detect_bare_url_with_query_params
            content = <<~MD
              https://foobar.com/hoge?fuga=piyo
            MD

            report = LinkImageValidator.validate(content, 'test.md')

            assert_equal 1, report.link_issues.size
            assert_equal 'https://foobar.com/hoge?fuga=piyo', report.link_issues.first.url
          end

          # =================================================================
          # 外部 URL 収集
          # =================================================================

          # Markdown リンクから外部 URL が正しく抽出されること
          def test_should_extract_external_urls_from_markdown_links
            Thread.current[:vs_verify_options] = {
              verify_images: true,
              verify_bare_urls: true,
              verify_external_links: true
            }

            content = <<~MD
              [Google](https://www.google.com)
              [Example](https://example.com/path)
            MD

            LinkImageValidator.validate(content, 'test.md')

            # 外部 URL が蓄積されていることを確認（print_summary で集約される）
            # 直接アクセスできないため、サマリー出力が正常に動くことで間接確認
            assert_output(/リンク・画像の検証が完了しました/) do
              Common.stub(:log_info, ->(msg) { puts "ℹ️  #{msg}" }) { LinkImageValidator.print_summary }
            end
          end

          # =================================================================
          # 検証サマリー
          # =================================================================

          # 問題なし時のサマリー出力
          def test_should_print_no_issues_summary
            content = <<~MD
              # 正常なファイル

              [テスト](https://example.com)
            MD

            LinkImageValidator.validate(content, 'test.md')

            assert_output(/問題なし/) do
              Common.stub(:log_info, ->(msg) { puts "ℹ️  #{msg}" }) { LinkImageValidator.print_summary }
            end
          end

          # 画像問題があるときのサマリー出力
          def test_should_print_image_issues_in_summary
            content = <<~MD
              ![テスト](data:image/svg+xml;charset=utf-8,%3Csvg%3E%3Ctext%3E%3Ctspan%3Emissing.webp%3C%2Ftspan%3E%3C%2Ftext%3E%3C%2Fsvg%3E)
            MD

            LinkImageValidator.validate(content, 'test.md')

            assert_output(/画像: 1 件の問題/) { LinkImageValidator.print_summary }
          end

          # 裸 URL があるときのサマリー出力
          def test_should_print_bare_url_issues_in_summary
            content = <<~MD
              https://example.com/bare
            MD

            LinkImageValidator.validate(content, 'test.md')

            assert_output(/裸 URL: 1/) { LinkImageValidator.print_summary }
          end

          # =================================================================
          # --no-verify（全無効化）
          # =================================================================

          # 検証が全無効時は何も検出されないこと
          def test_should_skip_all_checks_when_no_verify
            Thread.current[:vs_verify_options] = { no_verify: true }

            content = <<~MD
              ![テスト](data:image/svg+xml;charset=utf-8,%3Csvg%3E%3Ctext%3E%3Ctspan%3Emissing.webp%3C%2Ftspan%3E%3C%2Ftext%3E%3C%2Fsvg%3E)
              https://example.com/bare
            MD

            report = LinkImageValidator.validate(content, 'test.md')

            assert_empty report.image_issues
            assert_empty report.link_issues
          end

          # =================================================================
          # reset!
          # =================================================================

          # reset! でレポートがクリアされること
          def test_should_clear_reports_on_reset
            content = "https://example.com/bare\n"
            LinkImageValidator.validate(content, 'test.md')
            LinkImageValidator.reset!

            # reset 後はサマリーに何も出力されない
            assert_silent { LinkImageValidator.print_summary }
          end

          # =================================================================
          # 複数ファイルの蓄積
          # =================================================================

          # 複数ファイルのレポートが正しく蓄積されること
          def test_should_accumulate_reports_from_multiple_files
            LinkImageValidator.validate("https://example.com/bare1\n", 'file1.md')
            LinkImageValidator.validate("https://example.com/bare2\n", 'file2.md')

            assert_output(/裸 URL: 2/) { LinkImageValidator.print_summary }
          end
        end
      end
    end
  end
end
