# frozen_string_literal: true

# ================================================================
# Test: css/author_priority_test.rb
# ================================================================
# テスト対象:
#   Css::AuthorPriority（層の外の宣言を平らな CSS でも勝たせる。css-layer-restructure-spec.md §7.1）
#
# 検証内容:
#   - 平らな CSS で vs の規則に負ける custom.css の宣言にだけ !important を付ける
#   - custom.css が無い・負けない宣言しか無いときは、規則の列を変えない
#   - 付けた結果、custom.css の宣言どうしの勝ち負けが変わる要素があれば、層ありで勝つ側にも付ける
#   - !important の宣言と取り合うもの・style 属性で同じプロパティを指定した要素に当たるものは
#     付けずに返す
#   - 疑似要素は同じ疑似要素どうしで比べる。章が足した CSS（別の 1 枚）にも付ける
# ================================================================

require 'test_helper'
require 'nokogiri'
require 'vivlio_starter/cli/css/flattener'
require 'vivlio_starter/cli/css/author_priority'

module VivlioStarter
  module CLI
    module Css
      class AuthorPriorityTest < Minitest::Test
        def test_should_promote_author_declaration_that_loses_in_flat_css
          sheets = { 'chapter' => [vs('body.simple h2 { margin-top: 0; color: green; }'),
                                   author('h2 { margin-top: calc(2em + 1px); }')] }

          result = AuthorPriority.apply(sheets, [document('<body class="simple"><h2>見出し</h2></body>')])

          assert_equal 'h2 { margin-top: calc(2em + 1px) !important; }', result.sheets['chapter'].last.text
          assert_equal({ 'chapter' => 1 }, result.promoted)
          assert_empty result.unresolved
        end

        def test_should_leave_sheets_unchanged_without_losing_author_declarations
          plain = { 'chapter' => [vs('body.simple h2 { margin-top: 0; }')] }
          winning = { 'chapter' => [vs('h2 { margin-top: 0; }'), author('h2 { margin-top: 2em; }')] }
          doc = document('<body class="simple"><h2>見出し</h2></body>')

          assert_same plain, AuthorPriority.apply(plain, [doc]).sheets, 'custom.css が無ければ何もしない'
          result = AuthorPriority.apply(winning, [doc])

          assert_equal winning, result.sheets, '詳細度で勝っている宣言には付けない'
          assert_empty result.promoted
        end

        # h2 に付けると、.x の中の h2.k（vs の規則は当たらない）で .x h2 に勝ってしまうので、.x h2 にも付ける
        def test_should_promote_until_author_declarations_agree
          sheets = { 'chapter' => [vs('body.s h2:not(.k) { color: green; }'),
                                   author('h2 { color: red; }'), author('.x h2 { color: blue; }')] }
          html = '<body class="s"><h2>一</h2><div class="x"><h2 class="k">二</h2></div></body>'

          result = AuthorPriority.apply(sheets, [document(html)])

          assert_equal ['h2 { color: red !important; }', '.x h2 { color: blue !important; }'],
                       result.sheets['chapter'].drop(1).map(&:text)
          assert_empty result.unresolved
        end

        def test_should_not_promote_over_important_declaration
          sheets = { 'chapter' => [vs('body.s h2.t { color: green; }'),
                                   author('.x h2 { color: blue !important; }'), author('h2.t { color: red; }')] }
          html = '<body class="s"><h2 class="t">一</h2><div class="x"><h2 class="t">二</h2></div></body>'

          result = AuthorPriority.apply(sheets, [document(html, path: '10-intro.html')])

          assert_equal 'h2.t { color: red; }', result.sheets['chapter'].last.text
          assert_pattern do
            result.unresolved => [{ reason: :important, path: '10-intro.html', decl: { selector: 'h2.t' },
                                    rival: { selector: '.x h2' } }]
          end
        end

        # 付ける宣言が style 属性のある要素にも当たるときは、style 属性の同じプロパティにも付ける
        # （PDF と同じく style 属性が勝つ）。重ならないプロパティと、当たらない要素には付けない
        def test_should_keep_style_attribute_winning_over_promoted_declaration
          sheets = { 'chapter' => [vs('.figure img { width: 100%; }'), author('img { inline-size: 50%; }')] }
          html = '<body><div class="figure"><img src="a.png"></div>' \
                 '<img src="b.png" style="width: 10px; border: none"><p style="width: 1px">本文</p></body>'
          doc = document(html)

          result = AuthorPriority.apply(sheets, [doc])

          assert_equal 'img { inline-size: 50% !important; }', result.sheets['chapter'].last.text
          assert_equal 'width: 10px !important; border: none;', doc.doc.at_css('img[src="b.png"]')['style']
          assert_equal 'width: 1px', doc.doc.at_css('p')['style']
          assert_equal [doc], result.restyled
          assert_empty result.unresolved
        end

        def test_should_compare_pseudo_elements_and_promote_in_added_sheet
          sheets = { 'chapter' => [vs('body.s h2::before { content: ""; margin-top: 0; }')],
                     'extra' => [author('h2::before { content: "★"; }', source: 'stylesheets/extra.css'),
                                 author('h2 { margin-top: 1em; }', source: 'stylesheets/extra.css')] }
          doc = document('<body class="s"><h2>一</h2></body>', sheets: %w[chapter extra])

          result = AuthorPriority.apply(sheets, [doc])

          assert_equal ['h2::before { content: "★" !important; }', 'h2 { margin-top: 1em; }'],
                       result.sheets['extra'].map(&:text), 'h2 の margin は ::before の規則と取り合わない'
          assert_equal({ 'extra' => 1 }, result.promoted)
        end

        private

        # 縦書きのページ（束に base/vertical.css がある）では、論理方向を縦の向きで読む。
        # margin-block-start は右・margin-inline-start は上（novel-vertical-spec.md §10.5）
        def test_should_read_logical_sides_in_the_vertical_writing_mode
          vertical = Flattener::Piece.new(layer: ['base'], text: ':root { writing-mode: vertical-rl; }',
                                          source: '/book/stylesheets/base/vertical.css')
          html = '<body class="s"><h2>見出し</h2></body>'
          sheets = lambda do |*pieces|
            { 'chapter' => [*pieces, vs('body.s h2 { margin-block-start: 0; }'), author('h2 { margin-right: 2em; }')] }
          end

          promoted = AuthorPriority.apply(sheets.call(vertical), [document(html)]).sheets['chapter'].last.text
          assert_equal 'h2 { margin-right: 2em !important; }', promoted, '縦書きでは同じ場所（右）を取り合う'
          assert_equal 'h2 { margin-right: 2em; }',
                       AuthorPriority.apply(sheets.call, [document(html)]).sheets['chapter'].last.text,
                       '横書きでは上と右で、取り合わない'
          assert_equal %w[margin-top], Cascade.longhands('margin-inline-start', vertical: true)
          assert_equal %w[height], Cascade.longhands('inline-size', vertical: true)
          assert_equal %w[border-right-width border-left-width], Cascade.longhands('border-block-width', vertical: true)
        end

        def vs(text) = Flattener::Piece.new(layer: ['parts'], text:, source: 'stylesheets/parts/x.css')

        def author(text, source: 'stylesheets/custom.css')
          Flattener::Piece.new(layer: [], text:, source:)
        end

        def document(html, path: 'a.html', sheets: ['chapter'])
          AuthorPriority::Document.new(doc: Nokogiri::HTML5("<html>#{html}</html>", max_errors: 0), path:, sheets:)
        end
      end
    end
  end
end
