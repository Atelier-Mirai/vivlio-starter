# frozen_string_literal: true

require_relative '../../../test_helper'
require 'tmpdir'
require 'vivlio_starter/cli/lint/dict_manager'

class TestDictManager < Minitest::Test
  DM = VivlioStarter::CLI::Lint::DictManager

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

  # --- 辞書ディレクトリの解決（パッケージング回帰） ---

  # gem 同梱の scaffold 辞書ディレクトリが実在し kotlin.txt を含む。
  # ※ gemspec は {bin,lib}/**/* しかパッケージしないため、辞書がリポジトリ直下 config/ ではなく
  #   lib/project_scaffold/config/ 側に在ることがインストール済み gem で読めるための必須条件。
  def test_packaged_dict_dir_is_packaged_and_has_dictionaries
    assert Dir.exist?(DM::PACKAGED_DICT_DIR), "gem 同梱辞書が存在しません: #{DM::PACKAGED_DICT_DIR}"
    assert File.exist?(File.join(DM::PACKAGED_DICT_DIR, 'kotlin.txt')), 'kotlin.txt が同梱されていること'
  end

  # プロジェクト直下 config/ があればそれを優先する
  def test_bundled_dir_prefers_project_config
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir_p(DM::PROJECT_DICT_DIR)
        assert_equal DM::PROJECT_DICT_DIR, DM.new.bundled_dir
      end
    end
  end

  # プロジェクト config/ が無ければ gem 同梱の scaffold コピーへフォールバックする
  # （旧実装はリポジトリ直下 config/ を指し、インストール済み gem で辞書 0 件になっていた）
  def test_bundled_dir_falls_back_to_packaged_when_no_project_config
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        assert_equal DM::PACKAGED_DICT_DIR, DM.new.bundled_dir
      end
    end
  end

  # フォールバック経路でも技術用語が word_map に載る（インストール済み gem 相当の担保）
  def test_word_map_loads_tech_terms_via_packaged_fallback
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        map = DM.new.build_word_map(nil)
        assert_operator map.size, :>, 10_000, '大量の辞書語が読み込まれること'
        %w[kotlin aws azure javascript markdown].each do |w|
          assert map.key?(w), "#{w} が辞書に登録されていること"
        end
      end
    end
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
    path = File.join(@dm.bundled_dir, 'basic.txt')
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

  # プロジェクト管理辞書（vivlio-starter-terms.txt）の用語が登録されることを確認する。
  # textlint / yml / SCOWL は標準辞書に未収録のため、補助辞書で誤検知を防ぐ。
  def test_build_word_map_includes_project_curated_terms
    map = @dm.build_word_map(nil)
    %w[textlint yml scowl].each do |w|
      assert map.key?(w), "プロジェクト辞書の '#{w}' が登録されていること"
    end
  end

  # --- ユーザー辞書（config/user_words.txt・--register） ---

  # CWD を一時プロジェクトへ移して実プロジェクトの config/ を汚さない
  def in_temp_project
    Dir.mktmpdir { |dir| Dir.chdir(dir) { yield dir } }
  end

  # register_user_words が新語を追加し、重複（大文字小文字無視）は除くことを確認する
  def test_register_user_words_appends_and_dedups
    in_temp_project do
      added = @dm.register_user_words(%w[Mbed STM32 Mbed])
      assert_equal %w[Mbed STM32], added, '新語のみ・重複除去して追加される'
      assert_equal 'config/user_words.txt', @dm.user_dict_path
      assert File.exist?(@dm.user_dict_path), 'ユーザー辞書ファイルが作成される'
      assert_empty @dm.register_user_words(%w[mbed]), '登録済み（大文字小文字無視）は再追加しない'
    end
  end

  # 登録語が辞書順（大文字小文字無視）に整列して書き出されることを確認する
  def test_register_user_words_sorts_alphabetically
    in_temp_project do
      @dm.register_user_words(%w[Zebra apple Mango])
      @dm.register_user_words(%w[banana])
      words = File.readlines(@dm.user_dict_path, chomp: true).reject { it.start_with?('#') }
      assert_equal %w[apple banana Mango Zebra], words, '辞書順に整列される'
    end
  end

  # ユーザー辞書へ登録した語が word_map に載ることを確認する
  def test_user_dict_terms_load_into_word_map
    in_temp_project do
      @dm.register_user_words(%w[Mbed STM32])
      map = @dm.build_word_map(nil)
      assert map.key?('mbed'), 'ユーザー辞書の語が word_map に載ること'
      assert map.key?('stm32')
    end
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
