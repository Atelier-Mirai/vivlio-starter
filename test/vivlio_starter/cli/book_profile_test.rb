# frozen_string_literal: true

# ================================================================
# Test: book_profile_test.rb
# ================================================================
# テスト対象:
#   BookProfile（lib/vivlio_starter/cli/book_profile.rb）と、Common.load_config の値の解決の順
#   （v2-architecture-spec.md §2.2・§5.3）
#   - 表のキーがすべて ConfigKeys::KEYS にあり、値が既定値と違う（同じなら表に書く意味が無い）
#   - book.type の読み方（無い・知らない名前は techbook）
#   - 解決の順: ConfigKeys の既定値 < 種類の既定値 < 判型のプリセット < book.yml に書いた値
#   - book.type は分冊の巻では上書きできない（§5.4）
#
# 種類ごとの雛形の book.yml との照合（§2.2 の検査の (2)）は、雛形ができる S8 で足す。
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'yaml'
require 'vivlio_starter/cli/common'

module VivlioStarter
  module CLI
    class BookProfileTest < Minitest::Test
      # --- 表 ---

      def test_should_declare_every_profile_key_in_config_keys
        unknown = BookProfile::PROFILES.flat_map { |_, table| table.keys } - ConfigKeys::KEYS.keys

        assert_empty unknown.map { it.join('.') }, 'ConfigKeys::KEYS に無いキーを種類の既定値に書いている'
      end

      def test_should_only_list_values_that_differ_from_the_defaults
        same = BookProfile::PROFILES.flat_map do |type, table|
          table.filter_map { |path, value| "#{type}: #{path.join('.')}" if ConfigKeys::KEYS.fetch(path).default == value }
        end

        assert_empty same, '既定値と同じ値は書かない（既定値を変えたときに種類の値が取り残される）'
      end

      # 種類の既定のテーマの名前は、そのテーマを同梱する段階で足す（v2-architecture-spec.md §2.2）。
      # 名前だけが先に入ると、その種類の本が「テーマが無い」で止まる
      def test_should_name_only_bundled_themes_in_the_profiles
        bundled = Dir.glob('*/theme.yml', base: File.expand_path('../../../themes', __dir__)).map { File.dirname(it) }
        named = BookProfile::PROFILES.filter_map { |_, table| table[%i[theme name]] }

        assert_includes bundled, ConfigKeys::KEYS.fetch(%i[theme name]).default
        assert_empty named - bundled, 'PROFILES の theme.name が同梱のテーマ（リポジトリの themes/）に無い'
      end

      def test_should_keep_techbook_as_the_default_with_no_overrides
        assert_equal :techbook, BookProfile::DEFAULT_TYPE
        assert_empty BookProfile::PROFILES.fetch(:techbook), '1.x の本は何も書き足さずに今と同じ値で組める'
        assert_equal %i[techbook novel picture_book], BookProfile.types
      end

      # --- book.type の読み方 ---

      def test_should_read_the_type_from_the_raw_book_yml
        assert_equal :novel, BookProfile.type_of(book: { type: 'novel' })
        assert_equal :picture_book, BookProfile.type_of(book: { type: ' picture_book ' })
        assert_equal :techbook, BookProfile.type_of(book: { main_title: '題' }), '書かなければ techbook'
        assert_equal :techbook, BookProfile.type_of(book: { type: '' })
        assert_equal :techbook, BookProfile.type_of({})
        assert_equal :techbook, BookProfile.type_of(book: nil)
      end

      # 名前の誤りは組み合わせの検査が 🔴 で示す。読み込みでは止めない（vs doctor が起動できなくなる）
      def test_should_read_an_unknown_type_as_techbook_and_keep_the_written_name
        raw = { book: { type: 'novle' } }

        assert_equal :techbook, BookProfile.type_of(raw)
        assert_equal 'novle', BookProfile.written_type(raw)
      end

      def test_should_build_nested_defaults_for_a_type
        defaults = BookProfile.defaults_for(:novel)

        assert_equal 'vertical', defaults.dig(:page, :writing_mode)
        assert_equal 'none', defaults.dig(:page, :heading_numbering)
        assert_equal false, defaults.dig(:index_glossary, :enabled)
        assert_equal({}, BookProfile.defaults_for(:techbook))
      end

      # --- 分冊 ---

      def test_should_not_let_a_volume_override_the_book_type
        refute_includes ConfigKeys.book_keys, 'type'
        assert_includes ConfigKeys.book_keys, 'main_title', '書誌のキーはこれまでどおり巻で上書きできる'
      end
    end

    # Common.load_config の値の解決の順（book.yml を一時ディレクトリに書いて読む）
    class BookProfileLoadConfigTest < Minitest::Test
      def setup
        @original_dir = Dir.pwd
        @temp_dir = Dir.mktmpdir('vs-book-profile')
        Dir.chdir(@temp_dir)
        FileUtils.mkdir_p('config')
        File.write('config/page_presets.yml', {
          'a5_standard' => { 'size' => 'A5', 'base_font_size' => '10pt', 'base_line_height' => 1.7 }
        }.to_yaml)
      end

      def teardown
        Dir.chdir(@original_dir)
        FileUtils.rm_rf(@temp_dir)
      end

      def load(book_yml)
        File.write(Common::CONFIG_FILE, book_yml.to_yaml)
        Common.wrap_config(Common.load_config)
      end

      def test_should_read_a_book_without_type_as_techbook
        cfg = load('book' => { 'main_title' => '題' })

        assert_equal 'techbook', cfg.book.type
        assert_equal 'horizontal', cfg.page.writing_mode
        assert_equal 'chapter_and_section', cfg.page.heading_numbering
        assert_equal true, cfg.index_glossary.enabled
      end

      def test_should_put_the_type_defaults_over_the_config_key_defaults
        cfg = load('book' => { 'type' => 'novel' })

        assert_equal 'vertical', cfg.page.writing_mode
        assert_equal 'none', cfg.page.heading_numbering
        assert_equal false, cfg.index_glossary.enabled
        assert_equal 'reflowable', cfg.page.layout, '種類が書かないキーは ConfigKeys の既定値'
      end

      def test_should_let_the_book_yml_win_over_the_type_defaults
        cfg = load('book' => { 'type' => 'novel' },
                   'page' => { 'writing_mode' => 'horizontal', 'heading_numbering' => 'chapter' },
                   'index_glossary' => { 'enabled' => true })

        assert_equal 'horizontal', cfg.page.writing_mode, '横書きの小説'
        assert_equal 'chapter', cfg.page.heading_numbering
        assert_equal true, cfg.index_glossary.enabled, 'false を書いた本と true を書いた本を見分ける'
      end

      # 値を空欄にしたキーは、種類の既定値で動く（ConfigKeys の既定値ではない）
      def test_should_fall_back_to_the_type_default_for_a_blank_value
        cfg = load('book' => { 'type' => 'novel' }, 'page' => { 'heading_numbering' => nil })

        assert_equal 'none', cfg.page.heading_numbering
      end

      def test_should_apply_the_page_preset_over_the_type_defaults
        cfg = load('book' => { 'type' => 'novel' }, 'page' => { 'use' => 'a5_standard' })

        assert_equal 'A5', cfg.page.size
        assert_equal 'vertical', cfg.page.writing_mode
      end

      # 種類が判型のプリセットを選ぶ形（S8 の小説の判型）。book.yml の page.use が先に勝つ
      def test_should_choose_the_fallback_preset_only_without_page_use
        preset = Common.apply_page_preset({ book: {} }, fallback_use: 'a5_standard')
        written = Common.apply_page_preset({ page: { use: 'b5' } }, fallback_use: 'a5_standard')

        assert_equal 'A5', preset.dig(:page, :size)
        assert_nil written.dig(:page, :size), 'book.yml の page.use（ここでは無いプリセット）が勝つ'
      end

      # 小説は、page.use を書かなければ文庫判で組み、節で改ページせず、章は面を問わず改ページする
      # （novel-vertical-spec.md §4.3）。book.yml に書いた値が勝つ
      def test_should_give_a_novel_the_bunko_preset_and_its_page_breaks
        FileUtils.cp(File.expand_path('../../../config/page_presets.yml', __dir__), 'config/page_presets.yml')
        cfg = load('book' => { 'type' => 'novel' })
        written = load('book' => { 'type' => 'novel' }, 'page' => { 'use' => 'b6_standard', 'section_pagebreak' => true })

        assert_equal %w[a6_standard A6 any], [cfg.page.use, cfg.page.size, cfg.page.chapter_pagebreak]
        assert_equal false, cfg.page.section_pagebreak
        assert_equal ['B6', true], [written.page.size, written.page.section_pagebreak]
      end

      def test_should_keep_an_unknown_type_readable
        cfg = load('book' => { 'type' => 'novle' })

        assert_equal 'novle', cfg.book.type, '名前の誤りを示せるよう、書いた字は残す'
        assert_equal 'horizontal', cfg.page.writing_mode, '値は techbook のもの'
      end
    end
  end
end
