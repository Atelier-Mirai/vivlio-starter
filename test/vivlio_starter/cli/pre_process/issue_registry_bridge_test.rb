# frozen_string_literal: true

# ================================================================
# Test: issue_registry_bridge_test.rb
# ================================================================
# テスト対象:
#   各発生源から IssueRegistry へのブリッジ
#   （preflight-chapter-summary-spec.md §2.2・§3-3）
#
# 検証内容:
#   - LinkImageValidator: 欠落画像 🔴 / 裸 URL 🟡 が category 付きで積まれる
#   - コードインクルード: record_code_include_error が :code_include で積まれる
#   - Guards::Guard: :warn 違反が chapter なしで :guard として積まれる
#   - クロスリファレンス: ラベルID 重複 🔴・未定義参照/孤立ラベル 🟡 が積まれる
#   - DataRender（QueryStream）: 展開エラーが :query_stream で積まれる
#
# いずれも「従来の逐次ログは出したまま registry にも積む」ことを確認する
# （registry は集計専用で表示しないため、ログの消失は回帰になる）。
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'vivlio_starter/cli/pre_process/issue_registry'
require 'vivlio_starter/cli/pre_process/link_image_validator'
require 'vivlio_starter/cli/pre_process'
require 'vivlio_starter/cli/pre_process/data_render'
require 'vivlio_starter/cli/guards'

module VivlioStarter
  module CLI
    module PreProcessCommands
      # ----------------------------------------------------------------
      # LinkImageValidator → IssueRegistry
      # ----------------------------------------------------------------
      class LinkImageValidatorBridgeTest < Minitest::Test
        # data: URI プレースホルダー（= 欠落画像）を作る断片
        MISSING_IMAGE = '![代替](data:image/svg+xml;charset=utf-8,%3Csvg%3E%3Ctext%3E' \
                        '%3Ctspan%3Efoo.webp%3C%2Ftspan%3E%3C%2Ftext%3E%3C%2Fsvg%3E)'

        def setup
          LinkImageValidator.reset!
          IssueRegistry.reset!
          Thread.current[:vs_verify_options] = {
            verify_images: true, verify_bare_urls: true, verify_external_links: false
          }
        end

        def teardown
          Thread.current[:vs_verify_options] = nil
          IssueRegistry.reset!
        end

        # 欠落画像は 🔴 error・category :image として積まれる
        def test_should_record_missing_image_as_error
          capture_io { LinkImageValidator.validate("# 章\n\n#{MISSING_IMAGE}\n", '21-images.md') }

          issue = IssueRegistry.issues.first
          assert_pattern do
            issue => { chapter: '21-images', severity: :error, category: :image, line: 3 }
          end
          assert_includes issue.message, 'foo.webp'
        end

        # 裸 URL は 🟡 warn・category :link として積まれ、逐次ログも従来どおり出る
        def test_should_record_bare_url_as_warning_and_keep_log
          out, = capture_io do
            LinkImageValidator.validate("詳しくは https://example.com/page を参照。\n", '10-intro.md')
          end

          assert_includes out, '🟡'
          assert_includes out, '裸 URL'
          counts = IssueRegistry.summary_by_chapter['10-intro']
          assert_equal 0, counts.errors
          assert_equal 1, counts.warns
          assert_equal :link, IssueRegistry.issues.first.category
        end

        # コードインクルードの欠落は :code_include の 🔴 error として積まれる
        def test_should_record_code_include_error
          LinkImageValidator.record_code_include_error('31-codes.md', 42, 'sample.rb')

          issue = IssueRegistry.issues.first
          assert_pattern do
            issue => { chapter: '31-codes', line: 42, severity: :error, category: :code_include }
          end
          assert_includes issue.message, 'sample.rb'
        end

      end

      # ----------------------------------------------------------------
      # クロスリファレンス（ライブ経路）→ IssueRegistry
      # ----------------------------------------------------------------
      # 実ビルドが通るのは PreProcessCommands.process_cross_references_for_files。
      # CrossReferenceProcessor.process_cross_references は未定義メソッド
      # generate_report を呼ぶ到達不能コードなので、そちらは検証対象にしない。
      class CrossReferenceBridgeTest < Minitest::Test
        def setup
          IssueRegistry.reset!
        end

        def teardown
          IssueRegistry.reset!
        end

        # 未定義参照は 🟡 warn、孤立ラベルも 🟡 warn として :cross_reference で積まれる
        def test_should_record_undefined_reference_and_orphan_label_as_warnings
          body = <<~MD
            # 画像の章

            **図 サンプル @orphan**

            ![](images/a.webp)

            詳しくは @nosuchlabel を参照してください。
          MD

          in_project(body) do
            out, = capture_io { PreProcessCommands.process_cross_references_for_files(['21-images.md']) }

            assert_includes out, '🟡'
            issues = IssueRegistry.issues.select { it.category == :cross_reference }
            assert_equal %i[warn warn], issues.map(&:severity)
            assert_equal ['21-images'], issues.map(&:chapter).uniq
            assert(issues.any? { it.message.include?('未定義') }, '未定義参照が積まれるべきです')
            assert(issues.any? { it.message.include?('孤立ラベル') }, '孤立ラベルが積まれるべきです')
          end
        end

        # 同一ラベルID の重複は 🔴 error として積まれる
        def test_should_record_duplicate_label_as_error
          body = <<~MD
            # 画像の章

            **図 ひとつめ @dup**

            ![](images/a.webp)

            **図 ふたつめ @dup**

            ![](images/b.webp)

            @dup と @dup を参照します。
          MD

          in_project(body) do
            capture_io { PreProcessCommands.process_cross_references_for_files(['21-images.md']) }

            errors = IssueRegistry.issues.select { it.severity == :error }
            assert_equal 1, errors.size
            assert_pattern do
              errors.first => { chapter: '21-images', category: :cross_reference }
            end
            assert_includes errors.first.message, '@dup'
          end
        end

        private

        # catalog.yml・contents/・html/ ワークスペースを備えた最小プロジェクトを組む
        def in_project(chapter_body)
          Dir.mktmpdir('vs-xref-bridge-') do |dir|
            Dir.chdir(dir) do
              FileUtils.mkdir_p('config')
              File.write('config/catalog.yml', "CHAPTERS:\n  - 21-images\n")
              FileUtils.mkdir_p(Common::CONTENTS_DIR)
              File.write(File.join(Common::CONTENTS_DIR, '21-images.md'), chapter_body)
              FileUtils.mkdir_p(Common::BUILD_HTML_DIR)
              File.write(File.join(Common::BUILD_HTML_DIR, '21-images.md'), chapter_body)
              yield
            end
          end
        end
      end

      # ----------------------------------------------------------------
      # DataRender（QueryStream）→ IssueRegistry
      # ----------------------------------------------------------------
      class DataRenderBridgeTest < Minitest::Test
        def setup
          IssueRegistry.reset!
        end

        def teardown
          IssueRegistry.reset!
        end

        # データファイル不在の展開エラーが :query_stream の 🔴 error として積まれる
        def test_should_record_query_stream_error
          Dir.mktmpdir('vs-issue-bridge-') do |dir|
            Dir.chdir(dir) do
              FileUtils.mkdir_p('data')
              FileUtils.mkdir_p('templates')

              out, = capture_io do
                DataRender.process(
                  "= nosuchdata\n",
                  source_filename: '41-data.md', data_dir: 'data', templates_dir: 'templates'
                )
              end

              assert_includes out, '🔴'
              issue = IssueRegistry.issues.first
              assert_pattern do
                issue => { chapter: '41-data', severity: :error, category: :query_stream }
              end
            end
          end
        end
      end
    end

    # ----------------------------------------------------------------
    # Guards::Guard → IssueRegistry
    # ----------------------------------------------------------------
    class GuardIssueBridgeTest < Minitest::Test
      def setup
        PreProcessCommands::IssueRegistry.reset!
      end

      def teardown
        PreProcessCommands::IssueRegistry.reset!
      end

      # :warn 違反は chapter なし・category :guard として積まれる
      # （停止しない警告が最終判定から漏れる非対称の解消・§0-2）
      def test_should_record_warn_violation_without_chapter
        capture_io { Guards::Guard.run!(stub_check(:warn, '未知のコンテナクラス .foo')) }

        issue = PreProcessCommands::IssueRegistry.issues.first
        assert_pattern do
          issue => { chapter: nil, severity: :warn, category: :guard, message: '未知のコンテナクラス .foo' }
        end
      end

      # :error 違反は GuardError で即停止しサマリーへ到達しないため積まない
      def test_should_not_record_error_violation
        capture_io do
          assert_raises(Guards::GuardError) { Guards::Guard.run!(stub_check(:error, '致命的な違反')) }
        end

        assert_empty PreProcessCommands::IssueRegistry.issues
      end

      private

      def stub_check(severity, message)
        Class.new(Guards::BaseCheck) do
          define_method(:validate) { [Guards::Violation.new(severity:, message:, detail: nil)] }
        end.new
      end
    end
  end
end
