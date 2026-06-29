# frozen_string_literal: true

require_relative '../../../test_helper'
require 'tmpdir'
require 'vivlio_starter/cli/lint/tokenizer'
require 'vivlio_starter/cli/lint/spell_checker'
require 'vivlio_starter/cli/lint/dict_manager'

class TestSpellChecker < Minitest::Test
  SC = VivlioStarter::CLI::Lint::SpellChecker

  # --- threshold_for ---

  # 3文字以下の短い単語の許容距離が 1 であることを確認する
  def test_threshold_very_short_word
    assert_equal 1, SC.threshold_for('cat')
  end

  # 4文字の単語の許容距離が 1 であることを確認する
  def test_threshold_four_chars
    assert_equal 1, SC.threshold_for('abcd')
  end

  # 5〜8文字の単語の許容距離が 2 であることを確認する
  def test_threshold_five_chars
    assert_equal 2, SC.threshold_for('hello')
  end

  # 8文字でも許容距離が 2 であること（境界値）を確認する
  def test_threshold_eight_chars
    assert_equal 2, SC.threshold_for('abcdefgh')
  end

  # 9文字以上の単語の許容距離が 3 であることを確認する
  def test_threshold_nine_chars
    assert_equal 3, SC.threshold_for('abcdefghi')
  end

  # --- find_suggestion ---

  # Levenshtein距離が閾値以内の候補語が返ることを確認する
  def test_find_suggestion_close_word
    word_map = { 'bundle' => 'bundle', 'bind' => 'bind' }
    assert_equal 'bundle', SC.find_suggestion('bandle', word_map)
  end

  # 閾値を超える距離の単語には nil が返ることを確認する
  def test_find_suggestion_no_close_match_returns_nil
    word_map = { 'xyz' => 'xyz' }
    assert_nil SC.find_suggestion('hello', word_map)
  end

  # 大文字小文字を区別せず候補を検索することを確認する
  def test_find_suggestion_case_insensitive
    word_map = { 'ruby' => 'Ruby' }
    assert_equal 'Ruby', SC.find_suggestion('Ruvy', word_map)
  end

  # 単語長が大きく異なる場合に候補が除外されることを確認する
  def test_find_suggestion_length_filter_applied
    word_map = { 'superlongword' => 'superlongword' }
    assert_nil SC.find_suggestion('cat', word_map)
  end

  # --- check ---

  # 全単語が辞書に存在する場合にエラーが返らないことを確認する
  def test_check_clean_file_returns_empty
    word_map = { 'hello' => 'hello', 'world' => 'world' }
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'test.md')
      File.write(path, "Hello world\n")
      assert_empty SC.check(path, word_map)
    end
  end

  # スペルミスが検出され行番号・候補語が付与されることを確認する
  def test_check_detects_misspelling
    word_map = { 'bundle' => 'bundle', 'hello' => 'hello' }
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'test.md')
      File.write(path, "Hello bandle\n")
      errors = SC.check(path, word_map)
      assert_equal 1, errors.length
      assert_equal 'bandle', errors[0][:word]
      assert_equal 'bundle', errors[0][:suggestion]
      assert_equal 1,        errors[0][:line]
    end
  end

  # ignore_words に指定された単語がスキップされることを確認する
  def test_check_respects_ignore_words
    word_map = { 'using' => 'Using' }
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'test.md')
      File.write(path, "Using htmx here\n")
      errors = SC.check(path, word_map, ignore_words: %w[htmx here])
      assert_empty errors
    end
  end

  # <!-- vs-lint-disable-next-line --> が付いた行の次の行がスキップされることを確認する
  def test_check_skips_vs_lint_disable_next_line
    word_map = {}
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'test.md')
      File.write(path, "<!-- vs-lint-disable-next-line -->\nbadword\n")
      assert_empty SC.check(path, word_map)
    end
  end

  # <!-- vs-lint-disable --> 〜 <!-- vs-lint-enable --> の範囲がスキップされることを確認する
  def test_check_skips_vs_lint_disable_enable_block
    word_map = {}
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'test.md')
      File.write(path, "before\n<!-- vs-lint-disable -->\nbadword1\nbadword2\n<!-- vs-lint-enable -->\nafter\n")
      errors = SC.check(path, word_map)
      words = errors.map { _1[:word] }
      refute_includes words, 'badword1'
      refute_includes words, 'badword2'
    end
  end

  # 旧記法 <!-- spellcheck:ignore --> が機能しないことを確認する
  def test_check_old_spellcheck_ignore_not_supported
    word_map = {}
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'test.md')
      File.write(path, "badword <!-- spellcheck:ignore -->\n")
      errors = SC.check(path, word_map)
      # 旧記法は無視されるため、badword が検出される
      assert_equal 1, errors.length
      assert_equal 'badword', errors[0][:word]
    end
  end

  # デフォルトではコードフェンス内の単語が検査されないことを確認する
  def test_check_skips_code_fence_by_default
    word_map = {}
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'test.md')
      File.write(path, "Normal\n```\nbandleword\n```\nEnd\n")
      words = SC.check(path, word_map).map { _1[:word] }
      refute_includes words, 'bandleword'
    end
  end

  # 存在しないファイルパスを渡した場合に空配列が返ることを確認する
  def test_check_nonexistent_file_returns_empty
    errors = SC.check('/nonexistent/file.md', {})
    assert_empty errors
  end

  # --- print_errors ---

  # エラーが空の場合に false を返し何も出力しないことを確認する
  def test_print_errors_empty_returns_false
    result = capture_io { SC.print_errors({}) }
    assert_equal false, SC.print_errors({})
  end

  # 候補語がある場合に「語 => 候補」形式で出力され、ヘッダに (spellcheck) が付くことを確認する
  def test_print_errors_with_suggestion_shows_arrow
    errors = { 'test.md' => [{ line: 5, word: 'bandle', suggestion: 'bundle' }] }
    out, = capture_io { SC.print_errors(errors) }
    assert_includes out, 'bandle => bundle'
    assert_includes out, '(spellcheck)'
  end

  # 候補語がない場合は単語のみ表示され '=>' が含まれないことを確認する
  def test_print_errors_without_suggestion_shows_word_only
    errors = { 'test.md' => [{ line: 3, word: 'xyzzy', suggestion: nil }] }
    out, = capture_io { SC.print_errors(errors) }
    assert_includes out, 'xyzzy'
    refute_includes out, '=>'
  end

  # エラー出力にファイルパスが含まれることを確認する
  def test_print_errors_shows_filepath
    errors = { 'contents/01-intro.md' => [{ line: 1, word: 'foo', suggestion: nil }] }
    out, = capture_io { SC.print_errors(errors) }
    assert_includes out, 'contents/01-intro.md'
  end

  # エラーが存在する場合に true を返すことを確認する
  def test_print_errors_returns_true_when_has_errors
    errors = { 'test.md' => [{ line: 1, word: 'foo', suggestion: nil }] }
    capture_io { assert_equal true, SC.print_errors(errors) }
  end

  # --- aggregate（語ごとの集約） ---

  # 同じ語を 1 行へ集約し、出現数の多い順に並べることを確認する
  def test_aggregate_groups_by_word_and_sorts_by_count
    errors = [
      { line: 302, word: 'textlint', suggestion: 'textline' },
      { line: 4,   word: 'textlint', suggestion: 'textline' },
      { line: 383, word: 'yml', suggestion: nil }
    ]
    rows = SC.aggregate(errors)

    assert_equal 'textlint => textline', rows.first[:label], '件数の多い語が先頭'
    assert_equal 2, rows.first[:count]
    assert_equal '4, 302', rows.first[:lines], '出現行はソートして列挙'
    assert_equal 'yml', rows.last[:label]
    assert_equal 1, rows.last[:count]
  end

  # --- extra_words による抑制（end-to-end / #2） ---

  # book.yml の extra_words に登録した語がスペルチェックで検出されないことを確認する
  def test_extra_words_suppress_spellcheck_end_to_end
    config = Struct.new(:extra_dictionaries, :extra_words, :ignore_words, :check_code_blocks)
                   .new(nil, ['Mbed'], nil, false)
    word_map = VivlioStarter::CLI::Lint::DictManager.new.build_word_map(config)
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'test.md')
      File.write(path, "Mbed\n")
      assert_empty SC.check(path, word_map), 'extra_words の語は検出されない'
    end
  end
end
