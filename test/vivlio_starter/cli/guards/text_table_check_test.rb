# frozen_string_literal: true

# ================================================================
# Test: guards/text_table_check_test.rb
# ================================================================
# テスト対象:
#   Guards::TextTableCheck（lib/vivlio_starter/cli/guards/text_table_check.rb）
#
# 検証内容（text-table-spec.md §5）:
#   - 表が 1 つなら指摘しない（キャプション・ラベル付きも）
#   - 表が無い・二つ以上・.long-table が中にある、を 🟡 で開始行とともに指摘する
#   - コードフェンスの中の記法の解説は調べない
#   - 改ページの `---` を表の区切り行と取り違えない
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/guards'

module VivlioStarter
  module CLI
    class TextTableCheckTest < Minitest::Test
      def test_should_accept_one_table_with_caption
        violations = check(<<~MD)
          :::{.text-table}
          本文です。

          **評価の範囲 @tbl-range**

          | 範囲 | 評価 |
          |------|------|
          | 0.5 未満 | 単調 |
          :::
        MD

        assert_empty violations
      end

      def test_should_warn_when_no_table
        violations = check("# 見出し\n\n:::{.text-table}\n本文だけです。\n:::\n")

        assert_equal 1, violations.size
        assert_predicate violations.first, :warn?
        assert_equal 'contents/11-sample.md:3 - :::{.text-table} の中に表がありません', violations.first.message
      end

      def test_should_warn_when_two_tables
        violations = check(<<~MD)
          :::{.text-table}
          本文です。

          | a |
          |---|
          | 1 |

          | b | c |
          |:--|--:|
          | 2 | 3 |
          :::
        MD

        assert_equal ['contents/11-sample.md:1 - :::{.text-table} の中に表が 2 つあります'], violations.map(&:message)
      end

      def test_should_warn_on_long_table_inside
        violations = check(<<~MD)
          ::::{.text-table}
          本文です。

          :::{.long-table}
          | a |
          |---|
          | 1 |
          :::
          ::::
        MD

        assert_equal ['contents/11-sample.md:1 - :::{.text-table} の中では :::{.long-table} を使えません'],
                     violations.map(&:message)
      end

      # 記法の解説（コードフェンスの中）は調べない
      def test_should_ignore_example_inside_code_fence
        violations = check(<<~MD)
          ```markdown
          :::{.text-table}
          本文だけです。
          :::
          ```
        MD

        assert_empty violations
      end

      # `|` を含む行の直後の `---`（改ページ）は表の区切り行ではない
      def test_should_not_take_page_break_for_delimiter_row
        violations = check(":::{.text-table}\nA | B の比較。\n---\n:::\n")

        assert_equal [':::{.text-table} の中に表がありません'], violations.map { it.message.split(' - ').last }
      end

      private

      def check(markdown)
        Dir.mktmpdir('vs-text-table-check') do |dir|
          Dir.chdir(dir) do
            FileUtils.mkdir_p('config')
            FileUtils.mkdir_p('contents')
            File.write('config/book.yml', "book:\n  main_title: 'test'\n")
            File.write('contents/11-sample.md', markdown)
            return Guards::TextTableCheck.new.validate
          end
        end
      end
    end
  end
end
