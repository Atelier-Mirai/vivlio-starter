# frozen_string_literal: true

# ================================================================
# Test: guards/container_fence_check_test.rb
# ================================================================
# テスト対象:
#   Guards::ContainerFenceCheck（lib/vivlio_starter/cli/guards/container_fence_check.rb）
#
# 検証内容:
#   - 均衡した原稿は違反ゼロ
#   - 閉じ忘れ（走査後に深さが正）をエラーで検出し、開始行番号を示す
#   - 過剰な閉じ（深さが負）をエラーで検出し、その行番号を示す
#   - 入れ子は均衡と判定する
#   - contents/*.md のみを対象にする
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/guards'

module VivlioStarter
  module CLI
    class ContainerFenceCheckTest < Minitest::Test
      # 均衡した原稿はエラーにしない
      def test_should_not_error_when_balanced
        with_temp_project do
          File.write('contents/11-install.md', ":::{.column}\n本文\n:::\n")

          assert_empty Guards::ContainerFenceCheck.new.validate
        end
      end

      # 入れ子（column の中の note）は均衡と判定する
      def test_should_treat_nested_containers_as_balanced
        with_temp_project do
          File.write('contents/11-install.md', <<~MD)
            :::{.column}
            :::{.note}
            本文
            :::
            :::
          MD

          assert_empty Guards::ContainerFenceCheck.new.validate
        end
      end

      # 閉じ忘れをエラーで検出し、閉じられていない開始行を示す
      def test_should_error_on_unclosed_container
        with_temp_project do
          File.write('contents/11-install.md', "# 見出し\n\n:::{.column}\n本文\n")

          violations = Guards::ContainerFenceCheck.new.validate

          assert_equal 1, violations.size
          violation = violations.first
          assert_predicate violation, :error?
          assert_equal 'コンテナ記法（:::）の開始と終了の数が合いません（開始 1 個 / 終了 0 個）: contents/11-install.md',
                       violation.message
          assert(violation.detail.any? { it.include?('3 行目の :::{.column} が閉じられていません') })
        end
      end

      # 過剰な閉じをエラーで検出し、その行番号を示す
      def test_should_error_on_surplus_closing
        with_temp_project do
          File.write('contents/11-install.md', ":::{.column}\n本文\n:::\n:::\n")

          violations = Guards::ContainerFenceCheck.new.validate

          assert_equal 1, violations.size
          assert_predicate violations.first, :error?
          assert(violations.first.detail.any? { it.include?('4 行目の ::: に対応する開始行がありません') })
        end
      end

      # フェンス内の記法解説は数えない（偽陽性を出さない）
      def test_should_not_count_directives_inside_code_fence
        with_temp_project do
          File.write('contents/11-install.md', "```markdown\n:::{.column}\n```\n")

          assert_empty Guards::ContainerFenceCheck.new.validate
        end
      end

      # contents/ 以外（config 等）は対象にしない
      def test_should_scan_only_contents
        with_temp_project do
          File.write('contents/11-install.md', "ok\n")
          File.write('config/note.md', ":::{.column}\n")

          assert_empty Guards::ContainerFenceCheck.new.validate
        end
      end

      private

      def with_temp_project
        Dir.mktmpdir('vs-container-fence') do |dir|
          Dir.chdir(dir) do
            FileUtils.mkdir_p('config')
            FileUtils.mkdir_p('contents')
            File.write('config/book.yml', "book:\n  main_title: 'test'\n")
            yield
          end
        end
      end
    end
  end
end
