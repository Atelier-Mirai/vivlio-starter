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
#   - page_presets.yml に無いプリセット・判型の表に無い size: の本は、本を読むコマンドを 🔴 で止める（cover-size-independence-spec.md §8）
#
#   - 種類ごとの雛形の book.yml に書いた値が、その種類の解決後の既定値と一致する（§2.2 の検査の (2)）
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'yaml'
require 'samovar'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/samovar'

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

      # (2) 種類ごとの雛形の book.yml に書いた値が、その種類の解決後の既定値と一致する（v2-architecture-spec.md §2.2）。
      # 一致しないと、著者が書いていない値で雛形の本が組まれ、消すと組み上がりが変わる
      def test_should_match_the_type_scaffold_book_yml_with_the_type_defaults
        types_root = File.expand_path('../../../lib/project_scaffold_types', __dir__)
        books = Dir.glob('*/config/book.yml', base: types_root)
        refute_empty books, '種類ごとの雛形がある（ruby scripts/copy_to_scaffold.rb）'

        mismatches = books.flat_map do |relative|
          type = relative.split('/').first.to_sym
          raw = YAML.safe_load_file(File.join(types_root, relative), aliases: true, permitted_classes: [Date])
          leaves(raw).filter_map do |path, value|
            spec = ConfigKeys::KEYS[path] or next "#{type}: #{path.join('.')} は ConfigKeys::KEYS に無い"
            next if spec.authored? || value.to_s.match?(/\A\{\{.+\}\}\z/)

            expected = path == %i[book type] ? type.to_s : BookProfile::PROFILES.fetch(type).fetch(path) { spec.default }
            "#{type}: #{path.join('.')}: 既定値 #{expected.inspect} / 雛形 #{value.inspect}" unless expected == value
          end
        end

        assert_empty mismatches
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

      private

      # book.yml を { [:a, :b] => 値 } に平坦化する
      def leaves(node, prefix = [], into = {})
        node.each do |key, value|
          path = prefix + [key.to_sym]
          value.is_a?(Hash) ? leaves(value, path, into) : into[path] = value
        end
        into
      end
    end

    # Common.load_config の値の解決の順（book.yml を一時ディレクトリに書いて読む）
    class BookProfileLoadConfigTest < Minitest::Test
      # load_config は読んだ本のテーマの宣言を Common に覚えさせる（小説は novel）。
      # 戻さないと、後で走る既定値のテストが standard の宣言（theme.markers）を見失う
      def setup
        @original_dir = Dir.pwd
        @original_specs = Common.instance_variable_get(:@theme_specs)
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
        Common.instance_variable_set(:@theme_specs, @original_specs)
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

        assert_equal %w[bunko_standard BUNKO any], [cfg.page.use, cfg.page.size, cfg.page.chapter_pagebreak]
        assert_equal false, cfg.page.section_pagebreak
        assert_equal ['B6', true], [written.page.size, written.page.section_pagebreak]
      end

      # 小説は、テーマを書かなければ novel で組み、見出しを本文と同じ明朝にする（novel-vertical-spec.md §3.3・§4.3）。
      # 書体は book-settings.css（settings 層）が書くので、テーマの tokens: でなく種類の既定値で決める
      def test_should_give_a_novel_the_novel_theme_and_a_mincho_heading
        cfg = load('book' => { 'type' => 'novel' })
        written = load('book' => { 'type' => 'novel' }, 'theme' => { 'name' => 'standard' },
                       'typography' => { 'heading' => { 'font' => 'Noto Sans JP' } })

        assert_equal %w[novel Noto\ Serif\ JP], [cfg.theme.name, cfg.typography.heading.font]
        assert_equal %w[standard Noto\ Sans\ JP], [written.theme.name, written.typography.heading.font]
        assert_equal 'standard', load('book' => { 'type' => 'techbook' }).theme.name
      end

      # theme: を書いていない小説の本の theme: 節には、novel の宣言の既定値だけが入る（standard の
      # color・style などが入ると、「テーマ novel には無い設定です」の 🟡 が出る）
      def test_should_fill_the_theme_section_from_the_type_default_theme
        FileUtils.cp_r(File.expand_path('../../../themes', __dir__), 'themes')
        cfg = load('book' => { 'type' => 'novel' })

        assert_nil cfg.theme.to_h[:color]
        assert_equal 'green', load('book' => { 'type' => 'techbook' }).theme.color
      end

      # page_presets.yml に無い判型を選んだ本は止める（本文が黙って B5 で組まれるのを防ぐ）。
      # gem の雛形にある名前なら本の page_presets.yml が古いだけなので vs upgrade を、無い名前なら選べる名前を示す
      def test_should_stop_a_book_whose_page_preset_is_missing
        File.write(Common::CONFIG_FILE, { 'page' => { 'use' => 'bunko_standard' } }.to_yaml)
        message, detail = Common.unknown_page_preset_notice

        assert_equal 'config/book.yml の page.use: bunko_standard は config/page_presets.yml にない判型のため、本を組めません', message
        assert_equal '→ vs upgrade で config/page_presets.yml を新しくすると、この判型で組めます', detail

        File.write(Common::CONFIG_FILE, { 'page' => { 'use' => 'a5_standrad' } }.to_yaml)
        assert_equal '→ config/book.yml の page.use に、次のどれかを書いてください: a5_standard', Common.unknown_page_preset_notice.last

        File.write(Common::CONFIG_FILE, { 'book' => { 'type' => 'novel' } }.to_yaml)
        assert_match(/\Abook\.type: novel の既定の判型 bunko_standard は/, Common.unknown_page_preset_notice.first)

        File.write(Common::CONFIG_FILE, { 'page' => { 'use' => 'a5_standard' } }.to_yaml)
        assert_nil Common.unknown_page_preset_notice
        File.write(Common::CONFIG_FILE, { 'book' => { 'main_title' => '題' } }.to_yaml)
        assert_nil Common.unknown_page_preset_notice, 'page.use を書かない技術書はプリセットを選んでいない'
      end

      # 判型の表に無い size: も止める（表紙を作るところで止まるより先に）。page.width と page.height を
      # 書いた本と、size: を書いていない本（B5）は止めない
      def test_should_stop_a_book_whose_page_size_is_unknown
        File.write(Common::CONFIG_FILE, { 'page' => { 'size' => 'B4' } }.to_yaml)
        message, detail = Common.page_size_notice

        assert_equal 'config/book.yml の page.size: B4 は vs が知らない判型のため、本を組めません', message
        assert_match(/\A→ size: に A4・A5・B5・.*のどれかを書くか、page\.width と page\.height に寸法を書いてください/, detail)

        File.write('config/page_presets.yml', { 'b4_standard' => { 'size' => 'B4' } }.to_yaml)
        File.write(Common::CONFIG_FILE, { 'page' => { 'use' => 'b4_standard' } }.to_yaml)
        assert_equal 'config/page_presets.yml の b4_standard の size: B4 は vs が知らない判型のため、本を組めません',
                     Common.page_size_notice.first

        File.write(Common::CONFIG_FILE, { 'page' => { 'size' => 'B4', 'width' => '257mm', 'height' => '364mm' } }.to_yaml)
        assert_nil Common.page_size_notice, '寸法を書いた本は組める'
        File.write(Common::CONFIG_FILE, { 'book' => { 'main_title' => '題' } }.to_yaml)
        assert_nil Common.page_size_notice, 'size: を書いていない本は B5'
      end

      # 本を読むコマンドは止め、page_presets.yml を新しくする vs upgrade は止めない
      def test_should_stop_book_commands_but_not_upgrade_on_a_missing_page_preset
        File.write(Common::CONFIG_FILE, { 'page' => { 'use' => 'bunko_standard' } }.to_yaml)
        build = SamovarCommands::RootCommand.new(%w[build])
        upgrade = SamovarCommands::RootCommand.new(%w[upgrade])

        out, = capture_io do
          assert_raises(SystemExit) { build.send(:ensure_project_context!, build.command) }
        end
        assert_includes out, '🔴 config/book.yml の page.use: bunko_standard は'

        out, = capture_io do
          Common.stub(:ensure_configured!, nil) { upgrade.send(:ensure_project_context!, upgrade.command) }
        end
        refute_includes out, 'page.use'
      end

      def test_should_keep_an_unknown_type_readable
        cfg = load('book' => { 'type' => 'novle' })

        assert_equal 'novle', cfg.book.type, '名前の誤りを示せるよう、書いた字は残す'
        assert_equal 'horizontal', cfg.page.writing_mode, '値は techbook のもの'
      end
    end
  end
end
