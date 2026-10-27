# frozen_string_literal: true

require 'test_helper'
require_relative '../../../lib/vivlio_starter/cli/pre_process/link_image_validator'

module VivlioStarter
  module CLI
    module PreProcessCommands
      class LinkImageValidatorTest < Minitest::Test
        def setup
          LinkImageValidator.reset!
          # 検証を全有効にするスレッドローカル設定
          Thread.current[:vs_verify_options] = {
            verify_external_links: false
          }
        end

        # 存在しない画像（ImagePathNormalizer が置き換えたプレースホルダー）を 1 つ含む原稿
        def missing_image = "![テスト](data:image/svg+xml;charset=utf-8,%3Csvg%3E%3Ctext%3E%3Ctspan%3Emissing.webp%3C%2Ftspan%3E%3C%2Ftext%3E%3C%2Fsvg%3E)\n"

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
        # 外部 URL の収集（--verify-links のリンク切れの確かめ）
        # =================================================================
        # 裸 URL は警告しない（改善案 #123）。代わりに、リンク記法と同じく
        # リンク切れの確かめの対象に集める。

        def urls_of(content) = LinkImageValidator.external_urls(content, 'test.md').map { it[:url] }

        # 直書きの URL は警告せず、リンク切れの確かめに集めること
        def test_should_not_warn_bare_urls_but_collect_them
          content = <<~MD
            詳しくは https://example.com/page を参照してください。
          MD

          assert_empty LinkImageValidator.validate(content, 'test.md').link_issues
          assert_equal ['https://example.com/page'], urls_of(content)
        end

        # リンク記法・自動リンク・直書き・脚注や参照リンクの定義の URL を、どれも集めること。
        # 以前はリンク記法の URL しか集めず、出典の一覧に書いた URL のリンク切れを確かめていなかった
        def test_should_collect_urls_in_every_notation
          content = <<~MD
            [参考ページ](https://a.example.com/) と <https://b.example.com/> と https://c.example.com/
            RubyInstaller (https://d.example.com/) も使います。

            [^1]: https://e.example.com/
            [ref]: https://f.example.com/
          MD

          assert_equal %w[https://a.example.com/ https://b.example.com/ https://c.example.com/
                          https://d.example.com/ https://e.example.com/ https://f.example.com/],
                       urls_of(content)
        end

        # コードブロック・インラインコード・HTML コメント・HTML の属性値・@qr: の引数の URL は集めないこと
        def test_should_skip_urls_that_readers_do_not_follow
          content = <<~MD
            ```bash
            curl https://fence.example.com/api
            ```
            URL は `https://code.example.com/api` です。
            <!-- https://comment.example.com はコメントアウトされています -->
            <img src="qr.png" alt="https://alt.example.com/">
            サンプルはこちら: @qr:https://qr.example.com
          MD

          assert_empty urls_of(content)
        end

        # 同じ URL が何度も出てくる原稿でも、行番号が丸められないこと
        def test_should_record_the_actual_line_of_each_url
          content = <<~MD
            1 行目: [リンク](https://example.com) は正規の記法です。
            2 行目
            3 行目
            4 行目: https://example.com も同じ URL です。
          MD

          lines = LinkImageValidator.external_urls(content, 'test.md').map { it[:line_number] }
          assert_equal [1, 4], lines
        end

        # クエリパラメータ付きの URL を丸ごと取ること
        def test_should_collect_url_with_query_params
          assert_equal ['https://foobar.com/hoge?fuga=piyo'], urls_of("https://foobar.com/hoge?fuga=piyo\n")
        end

        # 全角の括弧・句読点の手前で URL を切ること。日本語のパスは URL のうちに数える
        def test_should_end_url_before_full_width_symbols
          content = <<~MD
            公式の「RubyInstaller」（https://rubyinstaller.org/）を使います。「Ruby+Devkit 4.0」を選びます。
            詳しくは https://ja.wikipedia.org/wiki/日本語。
          MD

          assert_equal ['https://rubyinstaller.org/', 'https://ja.wikipedia.org/wiki/日本語'], urls_of(content)
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

          assert_output(/良好な状態です/) do
            Common.stub(:log_info, ->(msg) { puts "ℹ️  #{msg}" }) { LinkImageValidator.print_summary }
          end
        end

        # 画像問題があるときのサマリー出力
        def test_should_print_image_issues_in_summary
          content = <<~MD
            ![テスト](data:image/svg+xml;charset=utf-8,%3Csvg%3E%3Ctext%3E%3Ctspan%3Emissing.webp%3C%2Ftspan%3E%3C%2Ftext%3E%3C%2Fsvg%3E)
          MD

          LinkImageValidator.validate(content, 'test.md')

          assert_output(/画像: 1 件の課題/) { LinkImageValidator.print_summary }
        end

        # 裸 URL だけなら問題として数えないこと（改善案 #123）
        def test_should_not_count_bare_urls_in_summary
          LinkImageValidator.validate("https://example.com/bare\n", 'test.md')

          assert_output(/良好な状態です/) do
            Common.stub(:log_info, ->(msg) { puts "ℹ️  #{msg}" }) { LinkImageValidator.print_summary }
          end
        end

        # =================================================================
        # reset!
        # =================================================================

        # reset! でレポートがクリアされること
        def test_should_clear_reports_on_reset
          LinkImageValidator.validate(missing_image, 'test.md')
          LinkImageValidator.reset!

          # reset 後はサマリーに何も出力されない
          assert_silent { LinkImageValidator.print_summary }
        end

        # =================================================================
        # 複数ファイルの蓄積
        # =================================================================

        # 複数ファイルのレポートが正しく蓄積されること
        def test_should_accumulate_reports_from_multiple_files
          LinkImageValidator.validate(missing_image, 'file1.md')
          LinkImageValidator.validate(missing_image, 'file2.md')

          assert_output(/画像: 2 件の課題/) { LinkImageValidator.print_summary }
        end
      end
    end
  end
end
