# frozen_string_literal: true

require_relative '../../../../test_helper'
require 'vivlio/starter/cli/lint/tokenizer'

class TestTokenizer < Minitest::Test
  T = Vivlio::Starter::CLI::Lint::Tokenizer

  # 基本的な英単語が正しく抽出されることを確認する
  def test_basic_word_extraction
    tokens = T.tokenize("Hello world\n")
    words = tokens.map { _1[0] }
    assert_includes words, 'Hello'
    assert_includes words, 'world'
  end

  # 各トークンに正しい行番号が付与されることを確認する
  def test_line_number_tracking
    content = "first line\nsecond line\nthird line\n"
    tokens = T.tokenize(content)
    assert tokens.select { _1[1] == 1 }.map { _1[0] }.include?('first')
    assert tokens.select { _1[1] == 2 }.map { _1[0] }.include?('second')
    assert tokens.select { _1[1] == 3 }.map { _1[0] }.include?('third')
  end

  # YAMLフロントマター内の単語がスキップされることを確認する
  def test_frontmatter_skipped
    content = "---\ntitle: My Book\nauthor: Someone\n---\nHello world\n"
    words = T.tokenize(content).map { _1[0] }
    refute_includes words, 'title'
    refute_includes words, 'author'
    assert_includes words, 'Hello'
  end

  # デフォルト設定でコードブロック内の単語がスキップされることを確認する
  def test_code_fence_skipped_by_default
    content = "Normal text\n```\nwrongword typo\n```\nAfter fence\n"
    words = T.tokenize(content).map { _1[0] }
    refute_includes words, 'wrongword'
    assert_includes words, 'Normal'
    assert_includes words, 'After'
  end

  # check_code_blocks: true の場合にコードブロック内もチェックされることを確認する
  def test_code_fence_checked_when_enabled
    content = "```\nwrongword\n```\n"
    words = T.tokenize(content, check_code_blocks: true).map { _1[0] }
    assert_includes words, 'wrongword'
  end

  # バッククォートで囲まれたインラインコード内の単語がスキップされることを確認する
  def test_inline_code_skipped
    words = T.tokenize("Use `wrongword` here\n").map { _1[0] }
    refute_includes words, 'wrongword'
    assert_includes words, 'Use'
    assert_includes words, 'here'
  end

  # HTMLタグが除去されてタグ内容のみ抽出されることを確認する
  def test_html_tags_removed
    words = T.tokenize("Text <span class=\"foo\">hello</span> end\n").map { _1[0] }
    refute_includes words, 'span'
    assert_includes words, 'hello'
  end

  # Vivliostyle拡張記法 {.xxx} がスキップされることを確認する
  def test_vivliostyle_class_notation_skipped
    words = T.tokenize("This is {.aki} extended syntax\n").map { _1[0] }
    refute_includes words, 'aki'
    assert_includes words, 'This'
    assert_includes words, 'extended'
  end

  # 複合クラス名を持つ拡張記法 {.chapter-lead} もスキップされることを確認する
  def test_vivliostyle_chapter_lead_notation_skipped
    words = T.tokenize("paragraph {.chapter-lead} here\n").map { _1[0] }
    refute_includes words, 'chapter'
    refute_includes words, 'lead'
    assert_includes words, 'paragraph'
  end

  # <!-- spellcheck:ignore --> コメントがある行がスキップされることを確認する
  def test_spellcheck_ignore_html_comment_skipped
    content = "good word\nbadword <!-- spellcheck:ignore -->\nmore words\n"
    words = T.tokenize(content).map { _1[0] }
    refute_includes words, 'badword'
    assert_includes words, 'good'
    assert_includes words, 'more'
  end

  # URLが除去されてURL内の単語が誤検出されないことを確認する
  def test_url_removed
    words = T.tokenize("Visit https://example.com for details\n").map { _1[0] }
    refute_includes words, 'https'
    refute_includes words, 'example'
    assert_includes words, 'Visit'
    assert_includes words, 'for'
  end

  # Markdownリンクのリンクテキストは残りURLは除去されることを確認する
  def test_markdown_link_text_kept_url_removed
    words = T.tokenize("See [Ruby docs](https://ruby-lang.org) for info\n").map { _1[0] }
    assert_includes words, 'Ruby'
    assert_includes words, 'docs'
    refute_includes words, 'ruby'  # URL部分は除去済み
  end

  # ハイフン複合語が1つのトークンとして抽出されることを確認する
  def test_hyphenated_word_extracted_as_one
    words = T.tokenize("use vivlio-starter here\n").map { _1[0] }
    assert_includes words, 'vivlio-starter'
  end

  # 1文字の単語が除外され2文字以上のみ抽出されることを確認する
  def test_single_char_words_excluded
    words = T.tokenize("a b c in on\n").map { _1[0] }
    refute_includes words, 'a'
    refute_includes words, 'b'
    refute_includes words, 'c'
    assert_includes words, 'in'
    assert_includes words, 'on'
  end

  # 空文字列を渡した場合に空配列が返ることを確認する
  def test_empty_content
    assert_empty T.tokenize('')
  end

  # Markdownの見出し記号（##等）が除去されて単語のみ抽出されることを確認する
  def test_heading_prefix_removed
    words = T.tokenize("## Introduction\n").map { _1[0] }
    assert_includes words, 'Introduction'
  end
end
