# frozen_string_literal: true

# ================================================================
# Test: theme_options_test.rb
# ================================================================
# テスト対象:
#   Theme::Option・Theme::OptionParser・Theme::Values・Theme::Features と、Theme::Resolved のうち
#   オプションと機能を読むところ（options・features・config_specs・active_features・body_classes・
#   token_value）、Theme.for_settings・Theme.token_value
#
# 検証内容（theme-contract-spec.md §3.2〜§3.4）:
#   - standard の options: と features: が、今の theme: 節の 15 キー（name を除く）になる
#   - 配色のテーマの tokens: が、土台のオプションの既定値になる（§3.2 の決め 4）
#   - enum のオプションの features: が機能を絞る（§3.4 の決め 2）・body_class: を種類ごとに付ける
#   - 値は書いた値 → default_from: の先 → default: の順に決まる。数は範囲の端へ寄せる
#   - 公開する変数の窓口は、オプション → テーマの tokens: → tokens.css の既定の順に引く（§3.4 の決め 1）
#   - theme.yml の options:・features: の誤りは 🔴（Theme::Error）
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'yaml'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/theme'

module VivlioStarter
  module CLI
    class ThemeOptionsTest < Minitest::Test
      REPO_ROOT = File.expand_path('../../..', __dir__)

      # 今の theme: 節のキー（name を除く 15 個）が、options: と機能の宣言に分かれて全部ある（§3.4 の表）
      def test_should_declare_the_current_theme_keys_in_standard
        theme = Theme.resolve('standard', root: REPO_ROOT)

        assert_equal %w[frontispiece ornament], theme.features
        assert_equal [%i[color], %i[preface_color], %i[appendix_color], %i[style], %i[lead_size], %i[markers h3],
                      %i[markers h4]], theme.options.map(&:path)
        assert_equal %w[image edge_inset heading_offset heading_chars lead_chars lead_size],
                     theme.feature_options.filter_map { it.key if it.path.first == :frontispiece }
        assert_equal %w[image heading_chars], theme.feature_options.filter_map { it.key if it.path.first == :ornament }
        assert_equal %w[color-accent color-accent-preface color-accent-appendix chapter-lead-size marker-h3 marker-h4],
                     theme.options.filter_map(&:token)
        assert_equal 15, theme.all_options.size
      end

      # ConfigKeys の形の宣言。default_from: のオプションは既定値を持たない
      def test_should_return_config_specs_with_default_from_as_nil
        specs = Theme.resolve('standard', root: REPO_ROOT).config_specs

        assert_equal 'green', specs.fetch(%i[theme color]).default
        assert_nil specs.fetch(%i[theme preface_color]).default
        assert_nil specs.fetch(%i[theme frontispiece lead_size]).default
        assert_equal '♣', specs.fetch(%i[theme markers h3]).default
        assert_equal 'sakura', specs.fetch(%i[theme ornament image]).default
      end

      # 配色のテーマの tokens: は、土台のオプションの token: と同じ名前なら、その既定値になる（§3.2 の決め 4）
      def test_should_use_the_color_theme_tokens_as_option_defaults
        with_book do |root|
          copy_standard(root)
          write_theme(root, 'mono', 'extends' => 'standard', 'tokens' => { 'color-accent' => '#555', 'color-link' => '#222' })

          specs = Theme.resolve('mono', root:).config_specs

          assert_equal '#555', specs.fetch(%i[theme color]).default
          assert_nil specs.fetch(%i[theme appendix_color]).default, '付録の色は今の色に従う'
        end
      end

      # standard の style: simple は扉絵・節絵を使わない。付録は値に依らず vs-header-simple
      def test_should_narrow_features_and_add_body_classes_by_the_enum_value
        theme = Theme.resolve('standard', root: REPO_ROOT)
        image = Common.wrap_config({ theme: { style: 'image' } })
        simple = Common.wrap_config({ theme: { style: 'simple' } })
        broken = Common.wrap_config({ theme: { style: 'fancy' } })

        assert_equal %w[frontispiece ornament], theme.active_features(image)
        assert_empty theme.active_features(simple)
        assert_equal %w[frontispiece ornament], theme.active_features(broken), '読めない値は既定値（image）'
        assert_equal %w[vs-header-image], theme.body_classes(:chapter, image)
        assert_equal %w[vs-header-simple], theme.body_classes(:chapter, simple)
        assert_equal %w[vs-header-simple], theme.body_classes(:appendix, image)
        assert_empty theme.body_classes(:preface, image)
      end

      # 値は書いた値 → default_from: の先 → default:。読めない値は書かなかったのと同じ
      def test_should_resolve_values_in_order
        theme = Theme.resolve('standard', root: REPO_ROOT)
        options = theme.all_options
        option = ->(path) { options.find { it.path == path } }
        cfg = { color: 'red', preface_color: 'pink', lead_size: '1.5em', frontispiece: { lead_size: nil } }

        assert_equal 'red', Theme::Values.effective(option.(%i[color]), cfg, options)
        assert_equal 'red', Theme::Values.effective(option.(%i[preface_color]), cfg, options), '読めない色は color に従う'
        assert_equal 'red', Theme::Values.effective(option.(%i[appendix_color]), cfg, options)
        assert_in_delta 1.5, Theme::Values.effective(option.(%i[frontispiece lead_size]), cfg, options)
        assert_equal 'var(--book-accent-red)', Theme::Values.css(option.(%i[color]), 'red')
        assert_equal '"♣"', Theme::Values.css(option.(%i[markers h3]), '♣')
      end

      # 倍率は範囲の端へ寄せる。em は付けてよく、ほかの単位の長さは :length
      def test_should_parse_numbers_with_the_declared_range_and_unit
        option = Theme.resolve('standard', root: REPO_ROOT).options.find { it.key == 'lead_size' }

        assert_equal [1.0, :too_small], Theme::Values.parse(option, 0.9)
        assert_equal [2.0, :too_large], Theme::Values.parse(option, '2.5')
        assert_equal [1.05, nil], Theme::Values.parse(option, '1.05em')
        assert_equal [nil, :length], Theme::Values.parse(option, '12pt')
        assert_equal [nil, :invalid], Theme::Values.parse(option, 'large')
        assert_equal '105%', Theme::Values.css(option, 1.05), '倍率は百分率で書く（§3.4 の決め 3）'
      end

      # 公開する変数の窓口: オプション → テーマの tokens: → stylesheets/tokens.css の既定（§3.4 の決め 1）
      def test_should_read_token_values_from_options_tokens_and_defaults
        with_book do |root|
          copy_standard(root)
          write_theme(root, 'plain', 'tokens' => { 'color-accent' => '#555' })
          FileUtils.mkdir_p(File.join(root, 'stylesheets'))
          File.write(File.join(root, 'stylesheets', 'tokens.css'), ":root {\n  --book-marker-h3: \"♠\";\n}\n")
          Dir.chdir(root) do
            standard = Common.wrap_config({ theme: { name: 'standard', markers: { h3: '★' } } })
            plain = Common.wrap_config({ theme: { name: 'plain' } })

            assert_equal '★', Theme.token_value('marker-h3', standard)
            assert_equal '#555', Theme.token_value('color-accent', plain)
            assert_equal '♠', Theme.token_value('marker-h3', plain), 'テーマに無ければ tokens.css の既定（引用符を外す）'
            assert_empty Theme.declared(plain).active_features(plain), '機能を使わないテーマ'
          end
        end
      end

      # 本の themes/ に読めるテーマが無ければ、同梱の宣言を読む（設定の読み込みを止めない）
      def test_should_fall_back_to_the_bundled_theme_for_settings
        with_book do |root|
          theme = Theme.for_settings('missing', root:)

          assert_equal 'standard', theme.name
          assert_includes theme.config_specs.keys, %i[theme color]
        end
      end

      # theme.yml の options:・features: の誤りは 🔴
      def test_should_reject_broken_option_declarations
        with_book do |root|
          {
            { 'options' => { 'x' => { 'type' => 'colour' } } } => /type: colour は書けません/,
            { 'options' => { 'x' => { 'type' => 'color', 'body_class' => { 'a' => 'b' } } } } => /enum のオプションにだけ/,
            { 'options' => { 'x' => { 'type' => 'enum', 'values' => %w[a b], 'default' => 'c' } } } => /values: にありません/,
            { 'options' => { 'x' => { 'type' => 'enum', 'values' => %w[a], 'features' => { 'a' => %w[sparkle] } } } } =>
              /知らない機能/,
            { 'options' => { 'x' => { 'type' => 'color', 'default' => 'red', 'default_from' => 'y' } } } => /両方/,
            { 'options' => { 'x' => { 'type' => 'number', 'token' => '--book-x' } } } => /--book- を除いた/,
            { 'features' => %w[sparkle] } => /features: に、知らない機能/
          }.each do |extra, message|
            write_theme(root, 'broken', extra)
            error = assert_raises(Theme::Error) { Theme.resolve('broken', root:) }
            assert_match message, error.message
          end
        end
      end

      private

      def with_book(&) = Dir.mktmpdir('vs-theme-options', &)

      def copy_standard(root)
        FileUtils.mkdir_p(File.join(root, 'themes'))
        FileUtils.cp_r(File.join(REPO_ROOT, 'themes', 'standard'), File.join(root, 'themes'))
      end

      def write_theme(root, name, extra = {})
        dir = File.join(root, 'themes', name)
        FileUtils.rm_rf(dir)
        FileUtils.mkdir_p(dir)
        File.write(File.join(dir, 'theme.yml'), { 'name' => name, 'contract' => 1 }.merge(extra).to_yaml)
      end
    end
  end
end
