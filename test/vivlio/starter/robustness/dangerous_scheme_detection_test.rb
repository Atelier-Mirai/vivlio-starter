# frozen_string_literal: true

# ================================================================
# robustness: 原稿内の危険スキーム検出（file:// / javascript:）
# ================================================================
# 対応する堅牢性テスト仕様書項目:
#   - 11-1 (L306): 原稿内の <img src="file:///etc/passwd">
#                 → Vivliostyle/Chromium のローカルファイル読み取り
#                   ポリシーに依存せず、ビルド成果物にローカルシステム
#                   情報が埋め込まれないこと
#   docs/specs/vivlio_starter_robustness_test_spec.md
#
# 検証観点:
#   A. HTML <img src="file:///..."> を検出し警告する
#   B. HTML <a href="javascript:..."> を検出し警告する
#   C. Markdown 画像 ![](file:///...) を検出し警告する
#   D. Markdown リンク [text](javascript:...) を検出し警告する
#   E. コードブロック内の例示は無視する（誤検出防止）
#   F. インラインコード内の例示は無視する
#   G. 検出結果が print_summary で表示される
#   H. --no-verify 指定下でも危険スキーム検出は無効化されない（常時有効）
# ================================================================

require 'test_helper'
require 'vivlio/starter/cli/pre_process/link_image_validator'

module Vivlio
  module Starter
    module CLI
      class DangerousSchemeDetectionTest < Minitest::Test
        LinkImageValidator = Vivlio::Starter::CLI::PreProcessCommands::LinkImageValidator

        def setup
          LinkImageValidator.reset!
          @warn_messages = []
          @echo_messages = []
        end

        def teardown
          LinkImageValidator.reset!
        end

        # ----------------------------------------------------------------
        # A. HTML <img src="file:///..."> を検出する
        # ----------------------------------------------------------------
        def test_should_detect_html_img_with_file_scheme
          md = <<~MD
            # 章タイトル

            <img src="file:///etc/passwd" alt="evil">

            本文...
          MD

          stub_common_log_warn do
            report = LinkImageValidator.validate(md, 'chapter.md',
                                                  config: all_disabled_config)
            dangerous = report.link_issues.select { it.issue_type == :dangerous_scheme }
            assert_equal 1, dangerous.size, '1 件検出されるべき'
            assert_equal 'file:///etc/passwd', dangerous.first.url
            assert_equal 3, dangerous.first.line_number
          end

          combined = @warn_messages.join("\n")
          assert_match(/chapter\.md:3/, combined)
          assert_match(%r{危険なスキーム.*file://}, combined)
        end

        # ----------------------------------------------------------------
        # B. HTML <a href="javascript:..."> を検出する
        # ----------------------------------------------------------------
        def test_should_detect_html_anchor_with_javascript_scheme
          md = %q(<a href="javascript:alert('xss')">click</a>) + "\n"

          stub_common_log_warn do
            report = LinkImageValidator.validate(md, 'evil.md', config: all_disabled_config)
            dangerous = report.link_issues.select { it.issue_type == :dangerous_scheme }
            assert_equal 1, dangerous.size
            assert_match(/\Ajavascript:/, dangerous.first.url)
          end
        end

        # ----------------------------------------------------------------
        # C. Markdown 画像 ![](file:///...) を検出する
        # ----------------------------------------------------------------
        def test_should_detect_markdown_image_with_file_scheme
          md = "![secret](file:///etc/passwd)\n"

          stub_common_log_warn do
            report = LinkImageValidator.validate(md, 'ch.md', config: all_disabled_config)
            dangerous = report.link_issues.select { it.issue_type == :dangerous_scheme }
            assert_equal 1, dangerous.size
            assert_equal 'file:///etc/passwd', dangerous.first.url
          end
        end

        # ----------------------------------------------------------------
        # D. Markdown リンク [text](javascript:...) を検出する
        # ----------------------------------------------------------------
        def test_should_detect_markdown_link_with_javascript_scheme
          md = "[click me](javascript:alert(1))\n"

          stub_common_log_warn do
            report = LinkImageValidator.validate(md, 'ch.md', config: all_disabled_config)
            dangerous = report.link_issues.select { it.issue_type == :dangerous_scheme }
            assert_equal 1, dangerous.size
            assert_match(/\Ajavascript:alert/, dangerous.first.url)
          end
        end

        # ----------------------------------------------------------------
        # E. コードブロック内の例示は無視する
        # ----------------------------------------------------------------
        def test_should_ignore_dangerous_schemes_inside_code_block
          md = <<~MD
            # セキュリティ注意

            ```html
            <img src="file:///etc/passwd">
            <a href="javascript:alert(1)">bad</a>
            ```

            上記はコードブロック内の例示です。
          MD

          stub_common_log_warn do
            report = LinkImageValidator.validate(md, 'doc.md', config: all_disabled_config)
            dangerous = report.link_issues.select { it.issue_type == :dangerous_scheme }
            assert_empty dangerous, 'コードブロック内の例示は検出しないこと'
          end
        end

        # ----------------------------------------------------------------
        # F. インラインコード内の例示は無視する
        # ----------------------------------------------------------------
        def test_should_ignore_dangerous_schemes_inside_inline_code
          md = "例えば `<img src=\"file:///etc/passwd\">` のようなタグは避けてください。\n"

          stub_common_log_warn do
            report = LinkImageValidator.validate(md, 'doc.md', config: all_disabled_config)
            dangerous = report.link_issues.select { it.issue_type == :dangerous_scheme }
            assert_empty dangerous, 'インラインコード内の例示は検出しないこと'
          end
        end

        # ----------------------------------------------------------------
        # G. 複数の危険スキームが混在する場合もすべて検出する
        # ----------------------------------------------------------------
        def test_should_detect_multiple_dangerous_schemes_in_one_file
          md = <<~MD
            <img src="file:///etc/passwd">
            ![secret](file:///root/.ssh/id_rsa)
            [click](javascript:steal())
            <a href="javascript:void(0)">fake</a>
          MD

          stub_common_log_warn do
            report = LinkImageValidator.validate(md, 'evil.md', config: all_disabled_config)
            dangerous = report.link_issues.select { it.issue_type == :dangerous_scheme }
            assert_equal 4, dangerous.size, '4 件すべて検出されるべき'
          end
        end

        # ----------------------------------------------------------------
        # H. --no-verify 指定下でも危険スキーム検出は常時有効
        # ----------------------------------------------------------------
        def test_dangerous_scheme_detection_is_not_disabled_by_no_verify
          md = %(<img src="file:///etc/passwd">\n)
          no_verify_config = {
            verify_images: false,
            verify_bare_urls: false,
            verify_external_links: false,
            timeout: 10, max_concurrency: 5
          }

          stub_common_log_warn do
            report = LinkImageValidator.validate(md, 'ch.md', config: no_verify_config)
            dangerous = report.link_issues.select { it.issue_type == :dangerous_scheme }
            assert_equal 1, dangerous.size,
                         'セキュリティ検証は --no-verify でも無効化されないこと'
          end
        end

        # ----------------------------------------------------------------
        # print_summary に危険スキームの件数・詳細が表示される
        # ----------------------------------------------------------------
        def test_print_summary_should_include_dangerous_scheme_details
          md = %(<img src="file:///etc/passwd">\n)

          stub_common_log_warn do
            LinkImageValidator.validate(md, 'ch.md', config: all_disabled_config)
          end

          combined = ''
          Common.stub(:log_summary, ->(msg, detail: nil) {
            combined += msg.to_s + "\n"
            combined += detail.to_s + "\n" if detail
          }) do
            Common.stub(:log_warn, ->(msg, detail: nil) {
              combined += msg.to_s + "\n"
              combined += detail.to_s + "\n" if detail
            }) do
              Common.stub(:log_error, ->(msg, detail: nil) {
                combined += msg.to_s + "\n"
                combined += detail.to_s + "\n" if detail
              }) do
                LinkImageValidator.print_summary
              end
            end
          end

          assert_match(/危険スキーム: 1/, combined, 'サマリに危険スキーム件数が表示されること')
          assert_match(/file:\/\/\/etc\/passwd/, combined, 'サマリに検出 URL が表示されること')
          assert_match(/ch\.md:1/, combined, 'サマリに参照元ファイル名:行番号が表示されること')
        end

        # ----------------------------------------------------------------
        # any_issues? が危険スキーム検出を含めて true を返す
        # ----------------------------------------------------------------
        def test_any_issues_should_be_true_when_only_dangerous_scheme_detected
          md = %(<img src="file:///etc/passwd">\n)

          stub_common_log_warn do
            LinkImageValidator.validate(md, 'ch.md', config: all_disabled_config)
          end

          assert LinkImageValidator.any_issues?,
                 '危険スキーム検出のみでも any_issues? は true を返すこと'
        end

        private

        # 画像・裸URL・外部リンク系をすべて無効化した config
        # （危険スキーム検出のみをピンポイントで検証するため）
        def all_disabled_config
          {
            verify_images: false,
            verify_bare_urls: false,
            verify_external_links: false,
            timeout: 10, max_concurrency: 5
          }
        end

        def stub_common_log_warn
          Common.stub(:log_warn, ->(msg, detail: nil) { @warn_messages << msg }) do
            Common.stub(:log_info, ->(*) {}) do
              yield
            end
          end
        end

        def stub_common_log_always
          Common.stub(:log_always, ->(msg) { @echo_messages << msg.to_s }) do
            Common.stub(:log_info, ->(*) {}) do
              yield
            end
          end
        end
      end
    end
  end
end
