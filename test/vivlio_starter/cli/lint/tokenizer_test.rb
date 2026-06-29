# frozen_string_literal: true

require_relative '../../../test_helper'
require 'vivlio_starter/cli/lint/tokenizer'

class TestTokenizer < Minitest::Test
  T = VivlioStarter::CLI::Lint::Tokenizer

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

  # <!-- vs-lint-disable-next-line --> コメントの次の行がスキップされることを確認する
  def test_vs_lint_disable_next_line_skips_next_line
    content = "good word\n<!-- vs-lint-disable-next-line -->\nbadword\nmore words\n"
    words = T.tokenize(content).map { _1[0] }
    refute_includes words, 'badword'
    assert_includes words, 'good'
    assert_includes words, 'more'
  end

  # <!-- vs-lint-disable --> 〜 <!-- vs-lint-enable --> の範囲がスキップされることを確認する
  def test_vs_lint_disable_enable_block_skipped
    content = "before\n<!-- vs-lint-disable -->\nbadword1\nbadword2\n<!-- vs-lint-enable -->\nafter\n"
    words = T.tokenize(content).map { _1[0] }
    refute_includes words, 'badword1'
    refute_includes words, 'badword2'
    assert_includes words, 'before'
    assert_includes words, 'after'
  end

  # <!-- vs-lint-enable --> がない場合にファイル末尾まで除外されることを確認する
  def test_vs_lint_disable_without_enable_skips_to_end
    content = "before\n<!-- vs-lint-disable -->\nbadword1\nbadword2\n"
    tokens = nil
    capture_io { tokens = T.tokenize(content) }
    words = tokens.map { _1[0] }
    refute_includes words, 'badword1'
    refute_includes words, 'badword2'
    assert_includes words, 'before'
  end

  # <!-- vs-lint-disable --> が閉じられていない場合に警告が stderr に出ることを確認する
  def test_vs_lint_disable_unclosed_emits_warning
    content = "before\n<!-- vs-lint-disable -->\nbadword\n"
    _out, err = capture_io { T.tokenize(content, path: 'sample.md') }
    assert_match(/vs-lint/, err)
    assert_match(/sample\.md:2/, err)
    assert_match(/閉じられていません/, err)
  end

  # 閉じられた disable-enable では警告が出ないことを確認する
  def test_vs_lint_disable_closed_does_not_warn
    content = "<!-- vs-lint-disable -->\nword\n<!-- vs-lint-enable -->\n"
    _out, err = capture_io { T.tokenize(content, path: 'sample.md') }
    refute_match(/vs-lint/, err)
  end

  # path 省略時でも警告が出ることを確認する（ただし行番号のみ表示）
  def test_vs_lint_disable_unclosed_warns_without_path
    content = "<!-- vs-lint-disable -->\nword\n"
    _out, err = capture_io { T.tokenize(content) }
    assert_match(/line 1/, err)
  end

  # vs-lint コメント行自体がスキップされることを確認する
  def test_vs_lint_comment_lines_themselves_skipped
    content = "<!-- vs-lint-disable -->\n<!-- vs-lint-enable -->\n<!-- vs-lint-disable-next-line -->\n"
    words = T.tokenize(content).map { _1[0] }
    assert_empty words
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

  # 相互参照ラベル @id が除外され、ラベル内の語が誤検出されないことを確認する
  def test_cross_reference_label_excluded
    words = T.tokenize("@photoelectric-table に示した値\n").map { _1[0] }
    refute_includes words, 'photoelectric-table'
    refute_includes words, 'photoelectric'
  end

  # 見出し中のラベル定義 ** タイトル @id ** でもラベルが除外されることを確認する
  def test_cross_reference_label_in_caption_excluded
    words = T.tokenize("**しきい周波数 @photoelectric-table**\n").map { _1[0] }
    refute_includes words, 'photoelectric-table'
  end

  # メールアドレスは相互参照ラベルとして誤って分解されないことを確認する
  def test_email_address_not_treated_as_label
    words = T.tokenize("contact@example.com まで\n").map { _1[0] }
    assert_includes words, 'example'  # @ 直前が単語文字なのでラベル除去は発動しない
    assert_includes words, 'contact'
  end
end
