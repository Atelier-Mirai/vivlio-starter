# frozen_string_literal: true

# ================================================================
# Test: legacy_tokens_test.rb
# ================================================================
# 検証内容（css-layer-restructure-spec.md §7.2・theme-contract-spec.md §5）:
#   2.0 で --book-* に名前を変えた変数の対応の表（Css::LegacyTokens）。
#   - r1 の雛形の CSS が定義していた名前が、どれも今も定義されているか、表にあるか、消した変数の表にある
#   - 同梱の CSS は今の名前を使わない（別名の tokens-legacy.css を除く）
#   - tokens-legacy.css が表と同じ中身
#   - 置き換えは名前の全体だけに当たる
#   - custom.css が今の名前に値を入れたら、settings 層で新しい名前へ渡す
# ================================================================

require_relative '../../../test_helper'
require 'tmpdir'
require 'vivlio_starter/cli/loader'

module VivlioStarter
  module CLI
    module Css
      class LegacyTokensTest < Minitest::Test
        LT = LegacyTokens
        ROOT = File.expand_path('../../../..', __dir__)
        R1_VARIABLES = File.expand_path('../../fixtures/css/r1_variables.txt', __dir__)

        # 同梱の CSS（stylesheets/ の全部。Google Fonts の書き出しを除く）
        def bundled_css
          Dir[File.join(ROOT, 'stylesheets/**/*.css')].reject { it.include?('/fonts/') }
                                                       .to_h { [it.delete_prefix("#{ROOT}/"), File.read(it)] }
        end

        # 注釈を除いた CSS が定義している変数の名前
        def defined_names(css) = css.gsub(%r{/\*.*?\*/}m, '').scan(/(#{LT::NAME})\s*:/o).flatten

        def test_should_account_for_every_variable_that_r1_defined
          r1 = File.readlines(R1_VARIABLES, chomp: true).reject { it.start_with?('#') || it.empty? }
          defined = bundled_css.except('stylesheets/tokens-legacy.css').values.flat_map { defined_names(it) }.uniq

          unaccounted = r1.reject { defined.include?(it) || LT::MAP.key?(it) || LT::REMOVED.include?(it) }

          assert_equal 72, r1.size, 'r1 の雛形の CSS が定義していた変数は 72 個'
          assert_empty unaccounted, '名前を変えたなら LegacyTokens::MAP に、消したなら REMOVED に載せる'
        end

        def test_should_not_use_legacy_names_in_bundled_stylesheets
          offenders = bundled_css.except('stylesheets/tokens-legacy.css').flat_map do |path, css|
            LT.legacy_names_in(css).map { "#{path}: #{it}" }
          end

          assert_empty offenders, '同梱の CSS は新しい名前で書く（今の名前は tokens-legacy.css の別名だけ）'
        end

        def test_should_keep_new_names_and_old_names_apart
          assert_empty LT::MAP.keys & LT::MAP.values, '今の名前と新しい名前が重なると、別名が循環する'
          assert_empty LT::MAP.keys & LT::REMOVED
          assert(LT::MAP.values.all? { it.start_with?('--book-', '--standard-') })
        end

        def test_should_match_tokens_legacy_css_with_the_table
          assert_equal LT.alias_css, File.read(File.join(ROOT, 'stylesheets/tokens-legacy.css')),
                       'tokens-legacy.css は LegacyTokens.alias_css から書き出す（手で直さない）'
        end

        def test_should_rename_whole_names_only
          css = <<~CSS
            :root { --color-link: #1a73e8; --color-link-hover: red; --book-color-link: blue; }
            a { color: var(--color-link); border-color: var(--theme-accent, #000); }
          CSS

          assert_equal <<~CSS, LT.rename(css)
            :root { --book-color-link: #1a73e8; --color-link-hover: red; --book-color-link: blue; }
            a { color: var(--book-color-link); border-color: var(--book-color-accent, #000); }
          CSS
        end

        # vs upgrade が見せる行の計画。自分自身を読む定義になる行は残す（cyclic）
        def test_should_plan_line_renames_and_keep_self_referring_definitions
          css = ":root {\n  --theme-accent: var(--book-color-accent);\n  --color-link: var(--theme-accent);\n}\np { color: red; }\n"

          lines = LT.rename_lines(css)

          assert_equal [[2, true], [3, false]], lines.map { [it.lineno, it.cyclic] }
          assert_equal '  --book-color-link: var(--book-color-accent);', lines.last.after
          assert_equal ":root {\n  --theme-accent: var(--book-color-accent);\n  --book-color-link: var(--book-color-accent);\n}\np { color: red; }\n",
                       LT.renamed_css(css)
        end

        def test_should_find_legacy_names_outside_comments
          css = "/* :root { --color-mark: red; } */\n.box { color: var(--theme-accent); --color-link: blue; }\n"

          assert_equal %w[--theme-accent --color-link], LT.legacy_names_in(css)
        end

        def test_should_pass_root_definitions_of_legacy_names_to_new_names
          css = <<~CSS
            :root { --color-link: #1a73e8; --font-header: "Zen Kaku Gothic New"; }
            html { --theme-accent: #c00; }
            .box { --color-mark: red; }
            :root { --color-border: var(--book-color-border-weak); }
          CSS

          assert_equal ['--book-color-accent: var(--theme-accent);', '--book-color-link: var(--color-link);',
                        '--book-font-heading: var(--font-header);'],
                       LT.settings_declarations(css),
                       ':root と html の定義だけを、表の順で渡す。新しい名前を読む値は循環するので渡さない'
        end

        # 1.x の custom.css の書き方（:root { --color-link: … }）が、settings 層の最後で新しい名前へ渡り、
        # テーマ色の行に勝つ
        def test_should_write_legacy_values_last_in_book_settings_root
          css = Dir.mktmpdir do |dir|
            Dir.chdir(dir) do
              FileUtils.mkdir_p('stylesheets')
              File.write('stylesheets/custom.css', ":root { --theme-accent: #c00; }\n")
              PreProcessCommands::BookSettingsCss.render(Common::CONFIG)
            end
          end
          root = css[/^:root \{\n(.*?)^\}/m, 1].lines.map(&:strip)

          assert_equal '--book-color-accent: var(--theme-accent);', root.last
          assert_operator root.index { it.start_with?('--book-color-accent: var(--book-accent-') }, :<, root.size - 1
        end

        def test_should_suggest_vs_upgrade_when_custom_css_uses_legacy_names
          output = Dir.mktmpdir do |dir|
            Dir.chdir(dir) do
              FileUtils.mkdir_p('stylesheets')
              File.write('stylesheets/custom.css', ":root { --color-link: #1a73e8; --color-column-bg: #f5f5dc; }\n" \
                                                   ".box { color: var(--theme-accent); }\n")
              capture_io { PreProcessCommands::BookSettingsCss.suggest_new_token_names }.first
            end
          end

          assert_equal "💡 custom.css の 1.x の変数の名前は、vs upgrade で新しい名前に置き換えられます" \
                       "（--color-link → --book-color-link、--color-column-bg → --book-color-column-bg ほか 1 個）\n",
                       output
        end

        def test_should_stay_silent_when_custom_css_mentions_legacy_names_only_in_comments
          output = Dir.mktmpdir do |dir|
            Dir.chdir(dir) do
              FileUtils.mkdir_p('stylesheets')
              File.write('stylesheets/custom.css', "/* :root { --color-link: #1a73e8; } */\n")
              capture_io { PreProcessCommands::BookSettingsCss.suggest_new_token_names }.first
            end
          end

          assert_empty output
        end
      end
    end
  end
end
