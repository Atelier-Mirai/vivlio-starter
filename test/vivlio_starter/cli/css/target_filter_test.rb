# frozen_string_literal: true

# ================================================================
# Test: target_filter_test.rb
# ================================================================
# テスト対象:
#   Css::TargetFilter（css-layer-restructure-spec.md §4.2 の 4）
#
# 検証内容:
#   1.x の sanitize_epub_css!（組み上がった EPUB の CSS の書き換え）が確かめていたことを、
#   平らな CSS を作る段で確かめる。
#   - EPUB・Kindle: @page の余白の箱と @footnote を落とし、size: と通常の規則は残す
#   - 書体を埋め込まないとき: @font-face を落とし、keyfont と異体字の 1 字書体の面は残す
#   - Kindle だけ: WebP の url() と data URI を含む宣言を落とす
#   - PDF: 何も落とさない
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'vivlio_starter/cli/css/target_filter'

module VivlioStarter
  module CLI
    module Css
      class TargetFilterTest < Minitest::Test
        def test_should_strip_margin_boxes_and_footnote_but_keep_page_size
          css = <<~CSS
            @page { size: A5; @bottom-center { content: counter(page); } @footnote { margin: 0; } }
            .foo { margin-bottom: 1em; }
            .bar { padding-top: 2px; }
          CSS

          result = filtered(css, target: :epub)

          refute_includes result, '@bottom-center'
          refute_includes result, '@footnote'
          assert_includes result, 'size: A5', '@page の size: は残す'
          assert_includes result, '.foo { margin-bottom: 1em; }', 'bottom を名前に含むプロパティは壊さない'
          assert_includes result, '.bar { padding-top: 2px; }'
        end

        def test_should_strip_font_faces_but_keep_bundled_ones_when_not_embedding
          css = <<~CSS
            @font-face { font-family: "Noto Serif JP"; src: url("fonts/NotoSerifJP-Regular.ttf"); }
            @font-face { font-family: keyfont; src: url("fonts/Keyboard_font/Keyboard-JP-Regular.ttf"); }
            @font-face { font-family: "vs-variant-1"; font-weight: 400; src: url("fonts/vs-variant-1.ttf"); }
            body { font-family: var(--font-main-text); }
          CSS

          result = filtered(css, target: :kindle)

          refute_includes result, 'Noto Serif JP', '運ばない書体の面は落とす（RSC-007）'
          assert_includes result, 'font-family: keyfont', 'keyfont は実体も運ぶので面を残す'
          assert_includes result, 'font-family: "vs-variant-1"; font-weight: 400', '異体字の書体の面を残す'
          assert_includes result, 'font-family: var(--font-main-text)', '通常の宣言は残す'
        end

        def test_should_keep_font_faces_when_embedding
          css = %(@font-face { font-family: "X"; src: url("fonts/x.ttf"); }\n)

          assert_includes filtered(css, target: :epub, embed_fonts: true), '@font-face'
        end

        def test_should_strip_webp_and_data_uri_declarations_only_for_kindle
          css = <<~CSS
            :root { --h3-marker: url("images/marker.webp"); --vs-plain-color: #333; }
            li.task-list-item > input[type="checkbox"]:checked {
              background-color: currentColor;
              background-image: url("data:image/svg+xml,%3Csvg%3E%3C/svg%3E");
            }
          CSS

          kindle = filtered(css, target: :kindle)
          epub = filtered(css, target: :epub)

          refute_includes kindle, '.webp'
          refute_match(/--h3(?!-)/, kindle, '数字を含む変数の名前の断片を残さない（CSS-008）')
          refute_includes kindle, 'data:'
          assert_includes kindle, '--vs-plain-color: #333', 'WebP を含まない宣言は残す'
          assert_includes kindle, 'background-color: currentColor', '同じ規則の他の宣言は残す'
          assert_includes epub, 'marker.webp', 'クリーン EPUB は WebP を運ぶので残す'
          assert_includes epub, 'data:', 'クリーン EPUB は data URI を残す'
        end

        def test_should_leave_pdf_untouched
          css = <<~CSS
            @page { @bottom-center { content: counter(page); } }
            @font-face { font-family: "X"; src: url("fonts/x.ttf"); }
            .a { background: url("a.webp"); }
          CSS

          result = filtered(css, target: :pdf, embed_fonts: false)

          assert_includes result, '@bottom-center'
          assert_includes result, '@font-face'
          assert_includes result, 'a.webp'
        end

        private

        def filtered(css, target:, embed_fonts: false)
          Dir.mktmpdir('vs-target-filter') do |dir|
            entry = File.join(dir, 'entry.css')
            pieces = Flattener.pieces(entry, rebase: ->(path) { path.delete_prefix("#{dir}/") }, css:)
            Flattener.render(TargetFilter.apply(pieces, target:, embed_fonts:))
          end
        end
      end
    end
  end
end
