# frozen_string_literal: true

# ================================================================
# Test: guards/code_fence_check_test.rb
# ================================================================
# テスト対象:
#   Guards::CodeFenceCheck（lib/vivlio_starter/cli/guards/code_fence_check.rb）
#
# 検証内容:
#   - フェンス区切り行が奇数の章を「閉じ忘れ／余分」としてエラー（ビルド前に停止）
#   - 整合（偶数）の章はエラーにしない
#   - 入れ子（外側 4 連バッククォート）の章は偶数で整合扱い
#   - detail に出現箇所（フェンス行番号）と修正案を含む
#   - contents/*.md のみを対象にする
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/guards'

module VivlioStarter
  module CLI
    class CodeFenceCheckTest < Minitest::Test
      # 閉じ忘れ（奇数）を検出し、エラー（ビルド前に停止）として報告する
      def test_should_error_when_fence_count_is_odd
        with_temp_project do
          File.write('contents/11-install.md', <<~MD)
            # インストール

            ```bash
            gem install vivlio-starter
          MD

          violations = Guards::CodeFenceCheck.new.validate

          assert_equal 1, violations.size
          violation = violations.first
          assert_predicate violation, :error?
          assert_includes violation.message, '11-install.md'
          assert_includes violation.message, '奇数'
        end
      end

      # 整合（偶数）の章はエラーにしない
      def test_should_not_warn_when_balanced
        with_temp_project do
          File.write('contents/11-install.md', <<~MD)
            # インストール

            ```bash
            gem install vivlio-starter
            ```
          MD

          assert_empty Guards::CodeFenceCheck.new.validate
        end
      end

      # 入れ子（外側 4 連バッククォート）は偶数で整合扱い
      def test_should_treat_nested_four_backtick_fence_as_balanced
        with_temp_project do
          File.write('contents/61-developer.md', <<~MD)
            # 記法

            ````markdown
            ** CSS定義 @css-table **
            ```css
            table { border-collapse: collapse; }
            ```
            ````
          MD

          assert_empty Guards::CodeFenceCheck.new.validate
        end
      end

      # detail に出現箇所（フェンス行番号）と修正案を含む
      def test_detail_includes_fence_line_numbers_and_suggestion
        with_temp_project do
          File.write('contents/11-install.md', "x\n```bash\ny\n")

          detail = Guards::CodeFenceCheck.new.validate.first.detail

          assert(detail.any? { it.include?('フェンス行: 2') })
          assert(detail.any? { it.include?('4 連バッククォート') })
        end
      end

      # contents/ 以外（config 等）は対象にしない
      def test_should_scan_only_contents
        with_temp_project do
          # contents 配下は整合、config に奇数フェンスのファイルを置いても無視される
          File.write('contents/11-install.md', "ok\n")
          File.write('config/note.md', "```\n")

          assert_empty Guards::CodeFenceCheck.new.validate
        end
      end

      private

      def with_temp_project
        Dir.mktmpdir('vs-code-fence') do |dir|
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
