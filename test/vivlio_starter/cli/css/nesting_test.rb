# frozen_string_literal: true

# ================================================================
# Test: css/nesting_test.rb
# ================================================================
# テスト対象:
#   Css::Nesting（CSS の入れ子を開く）。CSS Nesting Module Level 1 の開き方。
#
# 検証方法:
#   入れ子を含む規則を Stylesheet で読み、開いた規則の文字列の並びを見る。
# ================================================================

require 'test_helper'
require 'vivlio_starter/cli/css/stylesheet'

module VivlioStarter
  module CLI
    module Css
      class NestingTest < Minitest::Test
        # theme-base の basic.css の形。`& { … }` は親の選択子の規則になる
        def test_should_unfold_bare_ampersand_blocks_into_parent_rules
          assert_equal ['h1 { font-size: 2em; }', 'h1 { string-set: title content(); }'],
                       texts('h1 { & { font-size: 2em; } & { string-set: title content(); } }')
        end

        # 親が一つの複合選択子なら埋め込み、`&` を書かない子孫は前に親を補う
        def test_should_inline_compound_parent_and_prefix_implicit_descendants
          assert_equal ['.box { color: red; }', '.box p { color: blue; }', '.box > .title { x: 1; }',
                        '.box:hover { y: 2; }', '.dark .box { z: 3; }'],
                       texts('.box { color: red; & p { color: blue; } > .title { x: 1; } &:hover { y: 2; } .dark & { z: 3; } }')
        end

        # 親が並びのときと、結合子を含む親を `&` の左に祖先が来る形で使うときは :is() にまとめる
        # （埋め込むと祖先の順が変わる）。`&` が先頭なら結合子を含む親も埋め込む
        def test_should_wrap_list_and_complex_parents_in_is
          assert_equal [':is(.a, .b) .c { x: 1; }'], texts('.a, .b { .c { x: 1; } }')
          assert_equal ['.x :is(.p .q) { k: 1; }', '.p .q.y { k: 2; }'],
                       texts('.p .q { .x & { k: 1; } &.y { k: 2; } }')
        end

        # 入れ子の @media は親の規則をその条件の中に置く。入れ子の後の宣言は、順を保って別の規則にする
        def test_should_unfold_nested_media_and_keep_trailing_declarations_in_order
          assert_equal ['.a { color: red; }', '@media print { .a { color: black; } }', '.a { margin: 0; }'],
                       texts('.a { color: red; @media print { color: black; } margin: 0; }')
        end

        # 入れ子の中の入れ子と、!important を保つ
        def test_should_unfold_deeper_levels_and_keep_important
          assert_equal ['.a .b .c { color: red !important; }'], texts('.a { .b { .c { color: red !important; } } }')
        end

        # 文字列・属性の値の中の & は選択子ではない
        def test_should_not_replace_ampersand_inside_strings
          assert_equal ['[data-x="&"] .a { q: 1; }', '.a::after { content: "&"; }'],
                       texts('.a { [data-x="&"] & { q: 1; } &::after { content: "&"; } }')
        end

        # @media の中の入れ子は、@media を保ったまま中を開く。入れ子の無い規則は書いたとおり
        def test_should_unfold_rules_inside_media_and_leave_flat_rules_as_written
          media, = texts('@media print { .a { & .b { c: 1; } } .z { d: 2 } }')

          assert_match(/\A@media print \{\s*\.a \.b \{ c: 1; \}\s*\.z \{ d: 2 \}\s*\}\z/, media)
          assert_equal ['.flat > p { color: red }'], texts('.flat > p { color: red }')
        end

        # 開いた結果に @layer の囲みが出たら、層の項目として読む
        def test_should_read_nested_layer_as_layer_block
          items = Stylesheet.parse('.a { @layer theme { color: red; } }')

          assert_pattern { items => [Stylesheet::LayerBlock[name: 'theme', items: [Stylesheet::Rule[text: '.a { color: red; }']]]] }
        end

        private

        def texts(css) = Stylesheet.parse(css).map(&:text)
      end
    end
  end
end
