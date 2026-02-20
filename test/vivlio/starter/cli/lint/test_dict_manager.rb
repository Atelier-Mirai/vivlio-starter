# frozen_string_literal: true

require_relative '../../../../test_helper'
require 'vivlio/starter/cli/lint/dict_manager'

class TestDictManager < Minitest::Test
  DM = Vivlio::Starter::CLI::Lint::DictManager

  def setup
    @dm = DM.new
  end

  # --- normalize ---

  # # で始まるコメント行が nil を返すことを確認する
  def test_normalize_skips_comment_line
    assert_nil @dm.send(:normalize, '# comment line')
  end

  # 空行・空白のみの行が nil を返すことを確認する
  def test_normalize_skips_empty_line
    assert_nil @dm.send(:normalize, '   ')
  end

  # 行中の # 以降がコメントとして除去されることを確認する
  def test_normalize_removes_inline_comment
    assert_equal 'word', @dm.send(:normalize, 'word # inline comment')
  end

  # word/SM 形式の Hunspell フラグが除去されることを確認する
  def test_normalize_removes_hunspell_flags
    assert_equal 'word', @dm.send(:normalize, 'word/SM')
  end

  # *Auth* 形式のワイルドカード記号が除去されることを確認する
  def test_normalize_removes_glob_symbols
    assert_equal 'Auth', @dm.send(:normalize, '*Auth*')
  end

  # 通常の単語がそのまま返ることを確認する
  def test_normalize_plain_word
    assert_equal 'hello', @dm.send(:normalize, 'hello')
  end

  # 記号のみの行が nil を返すことを確認する
  def test_normalize_returns_nil_for_symbol_only
    assert_nil @dm.send(:normalize, '***')
  end

  # --- bundled_dict_names ---

  # BUNDLED_DIR が存在することを確認する
  def test_bundled_dir_exists
    assert Dir.exist?(DM::BUNDLED_DIR), "BUNDLED_DIR が存在しません: #{DM::BUNDLED_DIR}"
  end

  # bundled_dict_names が非空の配列を返すことを確認する
  def test_bundled_dict_names_returns_array
    names = @dm.send(:bundled_dict_names)
    assert_kind_of Array, names
    assert_predicate names, :any?
  end

  # SCOWL 一般英単語辞書が含まれることを確認する
  def test_bundled_dict_names_includes_english_words
    names = @dm.send(:bundled_dict_names)
    assert_includes names, 'english-words-20'
  end

  # 自作辞書（css-properties, tech-terms 等）が自動認識されることを確認する
  def test_bundled_dict_names_includes_custom_dicts
    names = @dm.send(:bundled_dict_names)
    assert_includes names, 'css-properties'
    assert_includes names, 'tech-terms'
  end

  # --- load_into_word_map ---

  # basic.txt から単語が word_map に登録されることを確認する
  def test_load_into_word_map_registers_words
    words = {}
    path = File.join(DM::BUNDLED_DIR, 'basic.txt')
    @dm.send(:load_into_word_map, path, words) if File.exist?(path)
    assert_predicate words, :any?
  end

  # ハイフン複合語がハイフンあり・なしの両形式で登録されることを確認する
  def test_load_into_word_map_hyphen_registers_both_forms
    words = {}
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'test.txt')
      File.write(path, "open-source\n")
      @dm.send(:load_into_word_map, path, words)
      assert words.key?('open-source'), 'ハイフンあり形式が登録されること'
      assert words.key?('opensource'),  'ハイフンなし形式が登録されること'
    end
  end

  # --- build_word_map ---

  # config が nil でも Hash が返ることを確認する
  def test_build_word_map_nil_config_returns_hash
    map = @dm.build_word_map(nil)
    assert_kind_of Hash, map
    assert_predicate map, :any?
  end

  # hello や ruby など一般的な単語が word_map に含まれることを確認する
  def test_build_word_map_includes_common_words
    map = @dm.build_word_map(nil)
    assert map.key?('hello'), "word_map に 'hello' が含まれること"
    assert map.key?('ruby'),  "word_map に 'ruby' が含まれること"
  end

  # book.yml の extra_words が word_map に登録されることを確認する
  def test_build_word_map_extra_words_registered
    config = Struct.new(:extra_dictionaries, :extra_words, :ignore_words, :check_code_blocks)
                   .new(nil, ['vivliostyle'], nil, false)
    map = @dm.build_word_map(config)
    assert map.key?('vivliostyle'), "extra_words が word_map に登録されること"
  end

  # extra_words のハイフン複合語が両形式で登録されることを確認する
  def test_build_word_map_extra_words_hyphen_both_forms
    config = Struct.new(:extra_dictionaries, :extra_words, :ignore_words, :check_code_blocks)
                   .new(nil, ['vivlio-starter'], nil, false)
    map = @dm.build_word_map(config)
    assert map.key?('vivlio-starter'), 'ハイフンあり形式が登録されること'
    assert map.key?('vivliostarter'),  'ハイフンなし形式が登録されること'
  end
end
