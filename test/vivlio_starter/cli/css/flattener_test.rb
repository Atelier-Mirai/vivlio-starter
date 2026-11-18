# frozen_string_literal: true

# ================================================================
# Test: css/flattener_test.rb
# ================================================================
# テスト対象:
#   Css::Stylesheet（CSS の読み取り）と Css::Flattener（@import を解いて層の順に並べる）。
#   css-layer-restructure-spec.md §4.2 の 1・2。
#
# 検証方法:
#   一時ディレクトリに入口と部品の CSS を書き、平らにした結果の規則の並びと url() を見る。
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'vivlio_starter/cli/css/flattener'

module VivlioStarter
  module CLI
    module Css
      class FlattenerTest < Minitest::Test
        # 層の宣言の順に並び、層の外が最後に来る。同じ層の中は出現の順のまま
        def test_should_order_rules_by_layer_declaration_and_put_unlayered_last
          files = {
            'entry.css' => <<~CSS,
              @charset "utf-8";
              @layer base, parts, settings;
              @import url("free.css");
              @import url("settings.css") layer(settings);
              @import url("a.css") layer(parts);
              @import url("base.css") layer(base);
              @import url("b.css") layer(parts);
            CSS
            'free.css' => '.free { color: red; }',
            'settings.css' => '.settings { color: blue; }',
            'a.css' => '.a { color: green; }',
            'base.css' => '.base { color: black; }',
            'b.css' => '.b { color: gray; }'
          }

          with_files(files) do
            pieces = Flattener.pieces('entry.css', rebase: ->(path) { path })

            assert_equal ['.base { color: black; }', '.a { color: green; }', '.b { color: gray; }',
                          '.settings { color: blue; }', '.free { color: red; }'], pieces.map(&:text)
            assert_equal [%w[base], %w[parts], %w[parts], %w[settings], []], pieces.map(&:layer)
          end
        end

        # 下位の層は親の層の中で宣言の順に並び、親の層に直に書いた規則は下位の層より後に来る
        def test_should_place_sublayers_before_rules_written_directly_in_the_parent
          files = {
            'entry.css' => <<~CSS,
              @layer theme;
              @import url("theme.css") layer(theme);
            CSS
            'theme.css' => <<~CSS
              .direct { color: red; }
              @layer main { .main { color: blue; } }
              @layer base { .base { color: green; } }
              @layer base, main;
            CSS
          }

          with_files(files) do
            pieces = Flattener.pieces('entry.css', rebase: ->(path) { path })

            assert_equal %w[.main .base .direct], pieces.map { it.text[/\A\S+/] },
                         '最初に現れた順（main → base）で並び、後の宣言では動かない'
            assert_equal [%w[theme main], %w[theme base], %w[theme]], pieces.map(&:layer)
          end
        end

        # @layer の囲みと宣言と @import と @charset は出力しない。規則は書かれたとおりに残る
        def test_should_drop_layer_blocks_imports_and_charset_from_the_output
          files = {
            'entry.css' => <<~CSS,
              @charset "utf-8";
              @layer parts;
              @import url("parts.css") layer(parts);
            CSS
            'parts.css' => <<~CSS
              @page :left { @bottom-left { content: counter(page); } }
              body.vs-kindle > p::before { content: "}"; }
            CSS
          }

          with_files(files) do
            css = Flattener.flatten('entry.css', rebase: ->(path) { path })

            assert css.start_with?(%(@charset "utf-8";\n)), '先頭に 1 つだけ置く'
            assert_equal 1, css.scan('@charset').size
            refute_includes css, '@layer'
            refute_includes css, '@import'
            assert_includes css, '@page :left { @bottom-left { content: counter(page); } }'
            assert_includes css, 'body.vs-kindle > p::before { content: "}"; }'
          end
        end

        # 相対の url() は書かれたファイルの位置から解き、rebase の返す文字列に置き換える。
        # data URI・外部の URL・ページ内の参照は触らない
        def test_should_rebase_relative_urls_from_the_file_that_wrote_them
          files = {
            'cache/entry.css' => %(@import url("../sheets/parts.css") layer(parts);\n),
            'sheets/parts.css' => <<~CSS
              .a { background: url("images/a.webp"); }
              .b { background: url(images/b.webp#frag); }
              .c { background: url("data:image/svg+xml,%3Csvg%3E%3C/svg%3E"); }
              .d { background: url("https://example.com/d.png"); }
            CSS
          }

          with_files(files) do |root|
            rebase = ->(path) { "PKG/#{path.delete_prefix("#{root}/")}" }
            css = Flattener.flatten('cache/entry.css', rebase:)

            assert_includes css, 'url("PKG/sheets/images/a.webp")'
            assert_includes css, 'url("PKG/sheets/images/b.webp#frag")', '断片は引き直した後ろに付け直す'
            assert_includes css, 'url("data:image/svg+xml,%3Csvg%3E%3C/svg%3E")'
            assert_includes css, 'url("https://example.com/d.png")'
          end
        end

        # 読めない @import は飛ばし、循環する @import は一度だけ読む
        def test_should_skip_missing_files_and_stop_import_cycles
          files = {
            'entry.css' => %(@import url("missing.css");\n@import url("loop.css");\n),
            'loop.css' => %(@import url("entry.css");\n.loop { color: red; }\n)
          }

          with_files(files) do
            pieces = Flattener.pieces('entry.css', rebase: ->(path) { path })

            assert_equal ['.loop { color: red; }'], pieces.map(&:text)
          end
        end

        # 入口の中身を文字列で渡せる。@import は entry_path の位置から解く（ファイルは読まない）
        def test_should_read_entry_from_given_css_relative_to_entry_path
          files = { 'cache/entry.css' => '.on-disk { color: red; }', 'parts.css' => '.part { color: blue; }' }

          with_files(files) do
            css = %(@layer parts;\n@import url("../parts.css") layer(parts);\n)
            pieces = Flattener.pieces('cache/entry.css', rebase: ->(path) { path }, css:)

            assert_equal ['.part { color: blue; }'], pieces.map(&:text)
          end
        end

        # 入れ子の規則は開いて、同じ層・同じ順のまま平らな CSS に入れる（@media の中の入れ子も）
        def test_should_unfold_nested_rules_in_place_keeping_their_layer
          files = { 'entry.css' => <<~CSS, 'theme.css' => <<~THEME }
            @layer parts, theme;
            @import url("theme.css") layer(theme);
            .plain { color: green; }
          CSS
            h1 { & { font-size: 2em; } }
            .box { color: red; & p { color: blue; } }
            @media print { .print { color: gray; & span { color: black; } } }
          THEME

          with_files(files) do
            pieces = Flattener.pieces('entry.css', rebase: ->(path) { path })

            assert_equal ['h1 { font-size: 2em; }', '.box { color: red; }', '.box p { color: blue; }'],
                         pieces.first(3).map(&:text)
            assert_equal [%w[theme]] * 4, pieces.first(4).map(&:layer)
            assert_match(/\A@media print \{\s*\.print \{ color: gray; \}\s*\.print span \{ color: black; \}\s*\}\z/, pieces[3].text)
            assert_equal ['.plain { color: green; }', []], [pieces.last.text, pieces.last.layer]
            refute_includes Flattener.render(pieces), '&'
          end
        end

        private

        def with_files(files)
          Dir.mktmpdir('vs-css-flatten') do |root|
            Dir.chdir(root) do
              files.each do |name, content|
                FileUtils.mkdir_p(File.dirname(name))
                File.write(name, content)
              end
              yield Dir.pwd
            end
          end
        end
      end
    end
  end
end
