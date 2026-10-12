# frozen_string_literal: true

# ================================================================
# Test: build/variant_glyph_font_test.rb
# ================================================================
# テスト対象:
#   Build::VariantGlyphFont（異体字の字形を親字へ割り当てた書体・kindle-ivs-font-spec.md）
#
# 検証方法:
#   cmap format 14 の読み取りと書体の生成は、同梱の Noto Serif JP を実物として使う。
#   字形 ID は書体の版で変わりうるので、期待値は ID ではなく「元の書体で引いた字形と
#   同じ輪郭か」で比べる。同梱書体が無い環境では skip する。
# ================================================================

require 'test_helper'
require 'stringio'
require 'tmpdir'
require 'vivlio_starter/cli/build/variant_glyph_font'

module VivlioStarter
  module CLI
    class VariantGlyphFontTest < Minitest::Test
      Font = Build::VariantGlyphFont

      NOTO_SERIF = File.expand_path('../../../../stylesheets/fonts/Noto_Serif_JP/NotoSerifJP-Regular.ttf', __dir__)

      NE = 0x79B0      # 禰
      HEN = 0x9089     # 邉（異体が 14 種ある）

      # 同じ親字でも、セレクタによって 3 通りに分かれる。
      # 非既定（字形が違う）だけが置き換えの対象で、既定は親字の形が正しく、無しは警告の対象。
      def test_should_classify_each_sequence_by_the_fonts_variation_table
        skip '同梱書体が無い環境では検証できない' unless File.file?(NOTO_SERIF)

        variants = Font.read(NOTO_SERIF)

        assert_kind_of Integer, variants.lookup(NE, 0xE0100), '禰󠄀（ネ偏）は親字と違う字形を持つ'
        refute_equal plain_glyph(NE), variants.lookup(NE, 0xE0100)
        assert_equal :default, variants.lookup(NE, 0xE0101), 'E0101 は親字と同じ字形（既定）'
        assert_nil variants.lookup(NE, 0xE0105), '書体が知らない組は nil'
      end

      # 表を持たない書体（cmap format 14 が無い）は空の表として扱い、例外にしない。
      def test_should_treat_a_font_without_the_table_as_empty
        Dir.mktmpdir('vs-variant-font') do |dir|
          path = File.join(dir, 'broken.ttf')
          File.binwrite(path, 'not a font')

          variants = Font.read(path)

          assert_empty variants
          assert_nil variants.lookup(NE, 0xE0100)
        end
      end

      # 作った書体では、セレクタの付かない親字が異体の字形を指す。輪郭まで同じであること。
      def test_should_map_the_base_character_to_the_variant_outline
        skip '同梱書体が無い環境では検証できない' unless File.file?(NOTO_SERIF)

        variant = Font.read(NOTO_SERIF).lookup(NE, 0xE0100)
        font = TTFunk::File.open(StringIO.new(Font.encode(NOTO_SERIF, { NE => variant }, family: 'VS Variant Glyphs 1')))

        glyph = font.glyph_outlines.for(font.cmap.unicode.first[NE])
        original = TTFunk::File.open(NOTO_SERIF).glyph_outlines.for(variant)

        assert_equal original.raw, glyph.raw, '異体の輪郭がそのまま入っている'
      end

      # name テーブルは作り直す。予約名（Noto Sans JP の `Source`）を名乗らず、
      # 著作権表示とライセンスの URL は元の書体から写す（OFL 第 2 条・第 3 条）。
      def test_should_rename_the_font_and_keep_the_license_notices
        skip '同梱書体が無い環境では検証できない' unless File.file?(NOTO_SERIF)

        variant = Font.read(NOTO_SERIF).lookup(NE, 0xE0100)
        ttf = Font.encode(NOTO_SERIF, { NE => variant }, family: 'VS Variant Glyphs 1')
        names = name_strings(ttf)

        assert_equal 'VS Variant Glyphs 1', names[1]
        assert_equal 'VSVariantGlyphs1', names[6]
        refute(names.except(0).values.any? { it.match?(/Noto|Source/) }, '著作権表示（ID 0）以外に Noto・Source を名乗らない')
        assert_equal name_strings(File.binread(NOTO_SERIF))[0], names[0], '著作権表示は元のまま'
        assert_equal name_strings(File.binread(NOTO_SERIF))[14], names[14], 'ライセンスの URL は元のまま'
      end

      # 1 本の書体の中で 1 つの親字は 1 つの字形しか指せない。同じ親字の別の異体は次の書体へ回す。
      def test_should_split_fonts_only_when_the_same_base_has_two_variants
        together = Font.assign([[NE, 0xE0100], [HEN, 0xE0101]])
        split = Font.assign([[NE, 0xE0100], [HEN, 0xE0101], [HEN, 0xE0102], [NE, 0xE0100]])

        assert_equal [[[NE, 0xE0100], [HEN, 0xE0101]]], together, '親字が重ならなければ 1 本'
        assert_equal [[[NE, 0xE0100], [HEN, 0xE0101]], [[HEN, 0xE0102]]], split,
                     '重なった異体だけ 2 本目へ。同じ組の再出現は増やさない'
      end

      # 対象にするのは漢字の親字だけ。絵文字の表示切替（FE0F）や数学記号の SVS は拾わない。
      def test_should_match_only_ideographs_with_variation_selectors
        assert_match Font::SEQUENCE, "竈門禰\u{E0100}豆子"
        assert_match Font::SEQUENCE, "\u{4FAE}\u{FE00}"
        refute_match Font::SEQUENCE, "\u{26A0}\u{FE0F}"
        refute_match Font::SEQUENCE, "\u{2269}\u{FE00}"
        refute_match Font::SEQUENCE, '禰'
      end

      private

      def plain_glyph(code) = TTFunk::File.open(NOTO_SERIF).cmap.unicode.first[code]

      # Windows 向け（UTF-16BE）の名前を、name ID => 文字列で返す。
      def name_strings(data)
        offset = Font.table_offset(data, 'name')
        _format, count, storage = data[offset, 6].unpack('nnn')
        (0...count).each_with_object({}) do |i, names|
          platform, _encoding, _language, id, length, start = data[offset + 6 + (i * 12), 12].unpack('n6')
          next unless platform == 3

          names[id] = data[offset + storage + start, length].dup.force_encoding('UTF-16BE').encode('UTF-8')
        end
      end
    end
  end
end
