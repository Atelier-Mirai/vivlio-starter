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
        # book.yml の文字数指定（PDF 側 BookSettingsCss::DEFAULT_*_CHARS と同じ既定）
        METRICS = HeadingImageComposer::DEFAULT_METRICS
        ORNAMENT_CHARS = METRICS[:ornament_chars]

        # 節絵の帯（PDF の aspect-ratio 480/100 と同じ比率）
        def band_height(width) = (width / HeadingImageComposer::ORNAMENT_BAND_ASPECT).round

        # 節題の基準字面 = 節題領域の幅 ÷ 字数
        def ornament_base_font(width, chars = ORNAMENT_CHARS)
          ((width * HeadingImageComposer::ORNAMENT_TEXT_WIDTH) / chars).round
        end

        def test_should_compose_frontispiece_with_image_and_heading_text
          svg = HeadingImageComposer.frontispiece_svg(1000, 1414, DATA_URI, '第1章', '春のお花見', '', FONT, nil, 0.60, METRICS)

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
          svg = HeadingImageComposer.frontispiece_svg(2880, 4153, DATA_URI, '第3章', '章タイトル', lead, FONT, nil, 0.60, METRICS)

          assert_includes svg, '　最初の段落です。', '段落先頭は全角 1 字下げ'
          assert_includes svg, '　二つ目の段落です。', '2 段落目も字下げ'
          assert_includes svg, 'aria-label="第3章 章タイトル 最初の段落です。'
        end

        # リードが空なら扉絵にリード <text> ブロックは現れない（従来相当の SVG）
        def test_should_omit_lead_block_when_lead_blank
          with_lead    = HeadingImageComposer.frontispiece_svg(2880, 4153, DATA_URI, '第3章', 'T', 'リード文', FONT, nil, 0.60, METRICS)
          without_lead = HeadingImageComposer.frontispiece_svg(2880, 4153, DATA_URI, '第3章', 'T', '', FONT, nil, 0.60, METRICS)

          assert_operator with_lead.scan('<text').size, :>, without_lead.scan('<text').size,
                          'リードありは <text> が 1 つ多い'
        end

        # 極端に長いリードは基準フォントより縮小され、下限で止まる。
        # 基準は「リード領域の幅 ÷ lead_chars」（旧 LEAD_FONT_RATIO 固定から変更）。
        def test_should_shrink_long_lead_font_down_to_floor
          base_size, = HeadingImageComposer.lead_layout(2880, 4153, '短い。', 0.60, METRICS[:lead_chars])
          long = '長い文章。' * 400
          long_size, = HeadingImageComposer.lead_layout(2880, 4153, long, 0.60, METRICS[:lead_chars])
          floor = (2880 * HeadingImageComposer::LEAD_FONT_FLOOR).round

          assert_equal ((2880 * 0.60) / METRICS[:lead_chars]).round, base_size, '短文は字数から導いた基準フォント'
          assert_operator long_size, :<, base_size, '長文は縮小される'
          assert_operator long_size, :>=, floor, '下限を割らない'
        end

        # lead_chars を減らすと 1 行の字数が減る＝字面が大きくなる（PDF の箱幅指定と同じ意図）
        def test_should_enlarge_lead_font_when_fewer_chars_requested
          few, = HeadingImageComposer.lead_layout(2880, 4153, '短い。', 0.60, 12)
          many, = HeadingImageComposer.lead_layout(2880, 4153, '短い。', 0.60, 30)

          assert_operator few, :>, many, '字数が少ないほど字面は大きい'
        end

        # リード内の Latin 語は語中で折れない（wrap_text_by_width 経由）
        def test_should_not_break_latin_word_in_lead
          lead = 'コマンド --add-missing を実行します。' * 3
          _size, lines = HeadingImageComposer.lead_layout(2880, 4153, lead, 0.60, METRICS[:lead_chars])

          assert lines.none? { |l| l.match?(/--add-\z/) || l.match?(/\A(?:missing)/) && l.length < 8 },
                 'Latin 語が語中で分断されない'
          assert lines.any? { |l| l.include?('--add-missing') }, '語が 1 つの塊として残る行がある'
        end

        # レイアウト版数はキャッシュ鍵ソルト。コンパクト帯＋文字数指定は v3 以上。
        # 上げ忘れると --no-clean 時に旧レイアウトの合成画像を掴む（§5-3）。
        def test_layout_version_reflects_compact_band
          assert_operator HeadingImageComposer::LAYOUT_VERSION, :>=, 3
        end

        # 裾帯 SVG（frontispiece_tail_svg）と FRONTISPIECE_SPLIT は廃止された（回帰防止）
        def test_frontispiece_tail_svg_is_removed
          refute HeadingImageComposer.respond_to?(:frontispiece_tail_svg), 'frontispiece_tail_svg は削除済み'
          refute HeadingImageComposer.const_defined?(:FRONTISPIECE_SPLIT), 'FRONTISPIECE_SPLIT 定数は削除済み'
        end

        def test_should_compose_ornament_with_colored_number_tspan
          svg = HeadingImageComposer.ornament_svg(1196, 500, DATA_URI, '1-1', '導入', FONT, '#f0a000', ORNAMENT_CHARS)

          assert svg.start_with?('<svg')
          # 帯は元画像の高さではなく PDF と同じ 4.8:1（コンパクト帯・§5-3）
          assert_includes svg, %(viewBox="0 0 1196 #{band_height(1196)}")
          assert_includes svg, %(<tspan fill="#f0a000" font-weight="900">1-1</tspan>)
          assert_includes svg, '導入'
        end

        # 飾りは左右 2 層に切り出して同じ行へ並べる（PDF の 2 層スプライトの SVG 版・§5-3）
        def test_should_place_ornament_decorations_side_by_side_with_clip_paths
          svg = HeadingImageComposer.ornament_svg(1196, 500, DATA_URI, '1-1', '導入', FONT, '#f0a000', ORNAMENT_CHARS)
          band_h = band_height(1196)
          img_w = (1196 * HeadingImageComposer::ORNAMENT_LAYER_IMAGE_WIDTH).round
          img_h = (img_w * 500.0 / 1196).round

          assert_equal 2, svg.scan('<clipPath').size, '左右 2 つの切り出し領域'
          assert_equal 2, svg.scan('<image').size, '飾りは 2 層'
          # 左は上寄せ・右は下寄せ（差分がそのまま右飾りの下がり量になる）
          assert_includes svg, %(x="0" y="0" width="#{img_w}" height="#{img_h}" clip-path="url(#vs-orn-l)")
          assert_includes svg,
                          %(x="#{1196 - img_w}" y="#{band_h - img_h}" width="#{img_w}" ) +
                          %(height="#{img_h}" clip-path="url(#vs-orn-r)")
        end

        # 節題は帯の中央ではなく左の飾りを避けた位置から始まる（PDF の text-align: left と同じ）
        def test_should_left_align_ornament_text_after_left_decoration
          svg = HeadingImageComposer.ornament_svg(1196, 500, DATA_URI, '1-1', '導入', FONT, '#f0a000', ORNAMENT_CHARS)

          assert_includes svg, 'text-anchor="start"'
          assert_includes svg, %(x="#{(1196 * HeadingImageComposer::ORNAMENT_PAD_START).round}")
        end

        # 節題の長短でフォントサイズが不揃いにならない（固定基準・kindle_h2 c/d/e の回帰テスト）
        def test_should_use_uniform_ornament_font_size_regardless_of_title_length
          short = HeadingImageComposer.ornament_svg(1196, 500, DATA_URI, '8-1', '概要', FONT, '#f0a000', ORNAMENT_CHARS)
          mid   = HeadingImageComposer.ornament_svg(1196, 500, DATA_URI, '8-2', 'はじめかた', FONT, '#f0a000', ORNAMENT_CHARS)
          long  = HeadingImageComposer.ornament_svg(1196, 500, DATA_URI, '7-5', 'トラブルシューティング', FONT, '#f0a000', ORNAMENT_CHARS)

          size = ->(svg) { svg[/<text [^>]*font-size="(\d+)"/, 1].to_i }
          base = ornament_base_font(1196)
          assert_equal base, size.call(short), '短い節題も基準サイズ（巨大化しない）'
          assert_equal base, size.call(mid), '中間長も基準サイズ'
          assert_equal base, size.call(long), '1 行に収まる長さは基準サイズのまま（縮小しない）'
        end

        # ornament.heading_chars を減らすと字面が大きくなる（帯は版面幅で固定のため・§1-2）
        def test_should_enlarge_ornament_font_when_fewer_chars_requested
          size = ->(svg) { svg[/<text [^>]*font-size="(\d+)"/, 1].to_i }
          few  = HeadingImageComposer.ornament_svg(1196, 500, DATA_URI, '1-1', '導入', FONT, '#f0a000', 10)
          many = HeadingImageComposer.ornament_svg(1196, 500, DATA_URI, '1-1', '導入', FONT, '#f0a000', 20)

          assert_equal ornament_base_font(1196, 10), size.call(few)
          assert_equal ornament_base_font(1196, 20), size.call(many)
          assert_operator size.call(few), :>, size.call(many), '字数が少ないほど字面は大きい'
        end

        # 1 行に収まらない長い節題は縮小せず 2 行へ折り返す（kindle_h2_c 極小化の回帰テスト）
        def test_should_wrap_long_ornament_title_instead_of_shrinking
          svg = HeadingImageComposer.ornament_svg(
            1196, 500, DATA_URI, '6-4', 'vs renumber — 章番号を一括で付け直す', FONT, '#f0a000', ORNAMENT_CHARS
          )

          font_size = svg[/<text [^>]*font-size="(\d+)"/, 1].to_i
          assert_equal ornament_base_font(1196), font_size, '折り返しで対応し、フォントは基準サイズを保つ'
          assert_equal 2, svg.scan('<text ').size, '2 行の <text> へ折り返される'
          assert_equal 1, svg.scan('<tspan fill=').size, '番号 tspan は 1 行目にのみ付く'
        end

        # 合成 SVG は intrinsic size（width/height 属性）を持つ（epub_h2 はみ出しの回帰テスト）
        def test_should_emit_intrinsic_size_attributes_on_svg_root
          svg = HeadingImageComposer.ornament_svg(1196, 500, DATA_URI, '1-1', '導入', FONT, '#f0a000', ORNAMENT_CHARS)
          band_h = band_height(1196)

          assert_includes svg, %(width="1196" height="#{band_h}" viewBox="0 0 1196 #{band_h}")
        end

        # 扉絵タイトルの字面は heading_chars から導く（旧 0.072 固定のマジックナンバーを廃止・§5-2）
        def test_should_derive_frontispiece_title_size_from_heading_chars
          few  = HeadingImageComposer.frontispiece_title_size(1000, 8)
          many = HeadingImageComposer.frontispiece_title_size(1000, 14)

          assert_equal ((1000 * HeadingImageComposer::FRONTISPIECE_TITLE_WIDTH) / 8).round, few
          assert_operator few, :>, many, '字数が少ないほど字面は大きい'
          # 極端な指定でも番号・リードとの階層を壊さない安全域に収まる
          assert_equal (1000 * HeadingImageComposer::FRONTISPIECE_TITLE_SIZE_RANGE.end).round,
                       HeadingImageComposer.frontispiece_title_size(1000, 2)
          assert_equal (1000 * HeadingImageComposer::FRONTISPIECE_TITLE_SIZE_RANGE.begin).round,
                       HeadingImageComposer.frontispiece_title_size(1000, 40)
        end

        def test_should_wrap_long_frontispiece_title_into_multiple_tspans
          long_title = 'あ' * 30
          svg = HeadingImageComposer.frontispiece_svg(1000, 1414, DATA_URI, '第2章', long_title, '', FONT, nil, 0.60, METRICS)

          tspan_count = svg.scan('<tspan').size
          assert_operator tspan_count, :>=, 2, 'long title should wrap into multiple tspans'
        end

        def test_should_escape_xml_reserved_characters_in_heading_text
          svg = HeadingImageComposer.frontispiece_svg(800, 1131, DATA_URI, '第3章', 'A < B & "C"', '', FONT, nil, 0.60, METRICS)

          assert_includes svg, '&lt;'
          assert_includes svg, '&amp;'
          refute_includes svg, '<text>A < B', 'raw < must not appear inside text'
        end

        def test_should_omit_number_markup_when_number_blank
          svg = HeadingImageComposer.frontispiece_svg(1000, 1414, DATA_URI, '', 'タイトルのみ', '', FONT, nil, 0.60, METRICS)

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
