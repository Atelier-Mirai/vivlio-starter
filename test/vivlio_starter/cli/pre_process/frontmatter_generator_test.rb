# frozen_string_literal: true

# ================================================================
# Test: frontmatter_generator_test.rb
# ================================================================
# 検証内容:
#   - 未クローズ frontmatter の警告（2-1-1 の回帰テスト）
#   - コードフェンス内の `---` を閉じと誤認しないこと
# ================================================================

require_relative '../../../test_helper'
require 'vivlio_starter/cli/pre_process/frontmatter_generator'

class FrontmatterGeneratorUnclosedTest < Minitest::Test
  FG = VivlioStarter::CLI::PreProcessCommands::FrontmatterGenerator

  # 開始 `---` の後に閉じがない場合、警告が stderr に出て元テキストを返す
  def test_unclosed_frontmatter_emits_warning_and_returns_original
    content = "---\ntitle: 閉じていない\nauthor: テスト\n本文はここから\n"
    result = nil
    _out, err = capture_io do
      result = FG.apply_frontmatter(content, 'chapter', '01', path: 'contents/99-draft.md')
    end

    assert_match(/frontmatter/i, err)
    assert_match(%r{contents/99-draft\.md}, err)
    assert_match(/閉じ.*見つかりません/, err)
    # 元のテキストがそのまま返ること
    assert_equal content, result
  end

  # path 省略時でも警告が出る（unknown file 表記）
  def test_unclosed_frontmatter_warns_without_path
    content = "---\ntitle: foo\n"
    _out, err = capture_io { FG.apply_frontmatter(content, 'chapter', '01') }

    assert_match(/unknown file/, err)
  end
end
