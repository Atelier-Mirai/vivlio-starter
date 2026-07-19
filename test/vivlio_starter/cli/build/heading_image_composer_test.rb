# frozen_string_literal: true

# ================================================================
# Test: heading_image_composer_test.rb
# ================================================================
# テスト対象:
#   Build::HeadingImageComposer
#   （lib/vivlio_starter/cli/build/heading_image_composer.rb）
#
# 検証内容:
#   - 扉絵（frontispiece）SVG が <image>（data URI）＋ 番号・タイトル <text> を組むこと
#   - 節絵（ornament）SVG が番号色付き <tspan> ＋ タイトルを組むこと
#   - 長いタイトルが複数行（tspan）へ折り返されること
#   - HTML/XML 予約文字がエスケープされること
#   - 画像が存在しないときは compose が nil（→ simple 縮退）を返すこと
#
# 注記:
#   compose は ImageMagick に依存するため、SVG 組み立てロジックは純粋な
#   frontispiece_svg / ornament_svg を直接呼んで検証する（magick 非依存）。
# ================================================================

require_relative '../../../test_helper'
require_relative '../../../../lib/vivlio_starter/cli/build/heading_image_composer'

module VivlioStarter
  module CLI
    module Build
      class HeadingImageComposerTest < Minitest::Test
        FONT = "'Zen Kaku Gothic New', sans-serif"
        DATA_URI = 'data:image/jpeg;base64,AAAA'

        def test_should_compose_frontispiece_with_image_and_heading_text
          svg = HeadingImageComposer.frontispiece_svg(1000, 1414, DATA_URI, '第1章', '春のお花見', '', FONT, nil, 0.60)

          assert svg.start_with?('<svg')
          # 原画は全高で出す（帯切り出しは廃止・facsimile 仕様）
          assert_includes svg, %(viewBox="0 0 1000 1414")
          assert_includes svg, %(width="1000" height="1414")
          assert_includes svg, %(xlink:href="#{DATA_URI}")
          assert_includes svg, 'aria-label="第1章 春のお花見"'
          assert_includes svg, '第1章'
          assert_includes svg, '春のお花見'
          # 番号には下線（line）が付く
          assert_includes svg, '<line'
        end

        # リードを渡すと段落先頭が全角字下げされた <tspan> として焼き込まれる
        def test_should_bake_lead_paragraphs_into_frontispiece
          lead = "最初の段落です。\n二つ目の段落です。"
          svg = HeadingImageComposer.frontispiece_svg(2880, 4153, DATA_URI, '第3章', '章タイトル', lead, FONT, nil, 0.60)

          assert_includes svg, '　最初の段落です。', '段落先頭は全角 1 字下げ'
          assert_includes svg, '　二つ目の段落です。', '2 段落目も字下げ'
          assert_includes svg, 'aria-label="第3章 章タイトル 最初の段落です。'
        end

        # リードが空なら扉絵にリード <text> ブロックは現れない（従来相当の SVG）
        def test_should_omit_lead_block_when_lead_blank
          with_lead    = HeadingImageComposer.frontispiece_svg(2880, 4153, DATA_URI, '第3章', 'T', 'リード文', FONT, nil, 0.60)
          without_lead = HeadingImageComposer.frontispiece_svg(2880, 4153, DATA_URI, '第3章', 'T', '', FONT, nil, 0.60)

          assert_operator with_lead.scan('<text').size, :>, without_lead.scan('<text').size,
                          'リードありは <text> が 1 つ多い'
        end

        # 極端に長いリードは基準フォントより縮小され、下限で止まる
        def test_should_shrink_long_lead_font_down_to_floor
          base_size, = HeadingImageComposer.lead_layout(2880, 4153, '短い。', 0.60)
          long = '長い文章。' * 400
          long_size, = HeadingImageComposer.lead_layout(2880, 4153, long, 0.60)
          floor = (2880 * HeadingImageComposer::LEAD_FONT_FLOOR).round

          assert_equal (2880 * HeadingImageComposer::LEAD_FONT_RATIO).round, base_size, '短文は基準フォント'
          assert_operator long_size, :<, base_size, '長文は縮小される'
          assert_operator long_size, :>=, floor, '下限を割らない'
        end

        # リード内の Latin 語は語中で折れない（wrap_text_by_width 経由）
        def test_should_not_break_latin_word_in_lead
          lead = 'コマンド --add-missing を実行します。' * 3
          _size, lines = HeadingImageComposer.lead_layout(2880, 4153, lead, 0.60)

          assert lines.none? { |l| l.match?(/--add-\z/) || l.match?(/\A(?:missing)/) && l.length < 8 },
                 'Latin 語が語中で分断されない'
          assert lines.any? { |l| l.include?('--add-missing') }, '語が 1 つの塊として残る行がある'
        end

        # レイアウト版数はキャッシュ鍵ソルト用に 2 以上（62% 帯からの刷新の目印）
        def test_layout_version_is_at_least_two
          assert_operator HeadingImageComposer::LAYOUT_VERSION, :>=, 2
        end

        # 裾帯 SVG（frontispiece_tail_svg）と FRONTISPIECE_SPLIT は廃止された（回帰防止）
        def test_frontispiece_tail_svg_is_removed
          refute HeadingImageComposer.respond_to?(:frontispiece_tail_svg), 'frontispiece_tail_svg は削除済み'
          refute HeadingImageComposer.const_defined?(:FRONTISPIECE_SPLIT), 'FRONTISPIECE_SPLIT 定数は削除済み'
        end

        # simple 章見出し（付録）: 角丸枠＋アクセント番号＋下線＋タイトルのベクター（背景画像なし）
        def test_should_compose_simple_frontispiece_as_pure_vector
          svg = HeadingImageComposer.compose(
            image_path: nil, number: '付録 A', title: 'サンプル',
            kind: :simple_frontispiece, font_family: FONT, accent_color: '#f0a000'
          )

          assert svg.start_with?('<svg')
          refute_includes svg, '<image', '背景画像を持たない（ピュアベクター）'
          assert_includes svg, '<rect', '角丸枠を描く'
          assert_includes svg, 'fill="#f0a000"', 'アクセント色を使う'
          assert_includes svg, '付録 A'
          assert_includes svg, 'サンプル'
          assert_includes svg, 'aria-label="付録 A サンプル"'
        end

        # simple 節見出し（付録）: 番号バッジ（アクセント地・白文字）＋タイトル
        def test_should_compose_simple_ornament_with_number_badge
          svg = HeadingImageComposer.compose(
            image_path: nil, number: 'A-1', title: '導入',
            kind: :simple_ornament, font_family: FONT, accent_color: '#0ea5e9'
          )

          assert svg.start_with?('<svg')
          refute_includes svg, '<image'
          assert_includes svg, 'fill="#0ea5e9"', 'バッジ・帯にアクセント色'
          assert_includes svg, 'fill="#ffffff"', 'バッジ番号は白文字'
          assert_includes svg, 'A-1'
          assert_includes svg, '導入'
        end

        # accent 未指定時は既定の金へフォールバックする
        def test_should_fall_back_to_default_accent_when_blank
          svg = HeadingImageComposer.compose(
            image_path: nil, number: '付録 B', title: 'X',
            kind: :simple_frontispiece, font_family: FONT, accent_color: ''
          )

          assert_includes svg, HeadingImageComposer::SIMPLE_DEFAULT_ACCENT
        end

        def test_should_compose_ornament_with_colored_number_tspan
          svg = HeadingImageComposer.ornament_svg(1196, 500, DATA_URI, '1-1', '導入', FONT, '#f0a000')

          assert svg.start_with?('<svg')
          assert_includes svg, 'viewBox="0 0 1196 500"'
          assert_includes svg, %(<tspan fill="#f0a000" font-weight="900">1-1</tspan>)
          assert_includes svg, '導入'
        end

        # 節題の長短でフォントサイズが不揃いにならない（固定基準・kindle_h2 c/d/e の回帰テスト）
        def test_should_use_uniform_ornament_font_size_regardless_of_title_length
          short = HeadingImageComposer.ornament_svg(1196, 500, DATA_URI, '8-1', '概要', FONT, '#f0a000')
          mid   = HeadingImageComposer.ornament_svg(1196, 500, DATA_URI, '8-2', 'はじめかた', FONT, '#f0a000')
          long  = HeadingImageComposer.ornament_svg(1196, 500, DATA_URI, '7-5', 'トラブルシューティング', FONT, '#f0a000')

          size = ->(svg) { svg[/<text [^>]*font-size="(\d+)"/, 1].to_i }
          base = (500 * HeadingImageComposer::ORNAMENT_FONT_RATIO).round
          assert_equal base, size.call(short), '短い節題も基準サイズ（巨大化しない）'
          assert_equal base, size.call(mid), '中間長も基準サイズ'
          assert_equal base, size.call(long), '1 行に収まる長さは基準サイズのまま（縮小しない）'
        end

        # 1 行に収まらない長い節題は縮小せず 2 行へ折り返す（kindle_h2_c 極小化の回帰テスト）
        def test_should_wrap_long_ornament_title_instead_of_shrinking
          svg = HeadingImageComposer.ornament_svg(
            1196, 500, DATA_URI, '6-4', 'vs renumber — 章番号を一括で付け直す', FONT, '#f0a000'
          )

          font_size = svg[/<text [^>]*font-size="(\d+)"/, 1].to_i
          assert_equal (500 * HeadingImageComposer::ORNAMENT_FONT_RATIO).round, font_size,
                       '折り返しで対応し、フォントは基準サイズを保つ'
          assert_equal 2, svg.scan('<text ').size, '2 行の <text> へ折り返される'
          assert_equal 1, svg.scan('<tspan fill=').size, '番号 tspan は 1 行目にのみ付く'
        end

        # 合成 SVG は intrinsic size（width/height 属性）を持つ（epub_h2 はみ出しの回帰テスト）
        def test_should_emit_intrinsic_size_attributes_on_svg_root
          svg = HeadingImageComposer.ornament_svg(1196, 500, DATA_URI, '1-1', '導入', FONT, '#f0a000')

          assert_includes svg, 'width="1196" height="500" viewBox="0 0 1196 500"'
        end

        def test_should_wrap_long_frontispiece_title_into_multiple_tspans
          long_title = 'あ' * 30
          svg = HeadingImageComposer.frontispiece_svg(1000, 1414, DATA_URI, '第2章', long_title, '', FONT, nil, 0.60)

          tspan_count = svg.scan('<tspan').size
          assert_operator tspan_count, :>=, 2, 'long title should wrap into multiple tspans'
        end

        def test_should_escape_xml_reserved_characters_in_heading_text
          svg = HeadingImageComposer.frontispiece_svg(800, 1131, DATA_URI, '第3章', 'A < B & "C"', '', FONT, nil, 0.60)

          assert_includes svg, '&lt;'
          assert_includes svg, '&amp;'
          refute_includes svg, '<text>A < B', 'raw < must not appear inside text'
        end

        def test_should_omit_number_markup_when_number_blank
          svg = HeadingImageComposer.frontispiece_svg(1000, 1414, DATA_URI, '', 'タイトルのみ', '', FONT, nil, 0.60)

          refute_includes svg, '<line', 'no underline when number is blank'
          assert_includes svg, 'タイトルのみ'
        end

        def test_should_return_nil_when_image_file_missing
          result = HeadingImageComposer.compose(
            image_path: '/nonexistent/path/door.webp',
            number: '第1章', title: 'X', kind: :frontispiece, font_family: FONT
          )

          assert_nil result
        end

        # render は画像が読めなければ（compose が nil）ラスタライズに進まず nil を返す（→ simple 縮退）
        def test_render_should_return_nil_when_image_file_missing
          result = HeadingImageComposer.render(
            image_path: '/nonexistent/path/door.webp',
            number: '第1章', title: 'X', kind: :frontispiece, font_family: FONT
          )

          assert_nil result
        end
      end
    end
  end
end
