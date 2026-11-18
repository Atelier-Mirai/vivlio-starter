# frozen_string_literal: true

# ================================================================
# Test: pre_process/svg_font_subset_maxp_test.rb
# ================================================================
# テスト対象:
#   SvgFontEmbedder.subset（図の SVG に埋め込む字の組）の maxp
#
# 背景:
#   ttfunk 1.8.0 の Subset は、maxp の点・輪郭の最大値を実際より小さく書く。
#   「楕円の周の長さ」の 6 字で、輪郭は 13 本あるのに 5 本と書いた。Chrome はこの表を
#   写したまま字の組を PDF に埋め込み、Adobe Acrobat は maxp を超える字（楕・周・長）を
#   描かずに「埋め込みフォントを抽出できません」と出した（改善案 #139）。
#   macOS のプレビューと Chrome は maxp を見ないので、PDF を目で見ても気づけない。
#
# 検証方法:
#   同梱の Noto Serif JP から字の組を作り、TTFunk で読み直して、maxp の最大値が
#   組の中のどの字の点・輪郭の数も下回らないことを確かめる。検査合計も確かめる。
# ================================================================

require 'test_helper'
require 'ttfunk'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/pre_process'

module VivlioStarter
  module CLI
    class SvgFontSubsetMaxpTest < Minitest::Test
      Embedder = PreProcessCommands::SvgFontEmbedder
      FONT = File.expand_path('../../../../stylesheets/fonts/Noto_Serif_JP/NotoSerifJP-Regular.ttf', __dir__)
      # 輪郭の多い字（楕 13 本）を含める。ttfunk の値のままだと 5 本と書かれる。
      CHARS = '楕円の周の長さ'.chars.uniq

      def test_should_not_understate_points_or_contours_in_maxp
        data = Embedder.subset(CHARS, FONT)
        font = TTFunk::File.new(data)
        maxp = font.maximum_profile
        outlines = (0...maxp.num_glyphs).filter_map { font.glyph_outlines.for(it) }.reject(&:compound?)

        assert_operator maxp.max_contours, :>=, outlines.map(&:number_of_contours).max
        assert_operator maxp.max_points, :>=, outlines.map { it.end_point_of_last_contour + 1 }.max
      end

      def test_should_keep_checksums_consistent_after_rewriting_maxp
        data = Embedder.subset(CHARS, FONT)
        whole = (data + ("\0" * (-data.bytesize % 4))).unpack('N*').sum & 0xFFFFFFFF

        assert_equal Embedder::CHECKSUM_MAGIC, whole, 'checkSumAdjustment を付け直す'
        data[4, 2].unpack1('n').times do |i|
          tag, checksum, offset, length = data[12 + (i * 16), 16].unpack('a4NNN')
          next if tag == 'head'

          assert_equal checksum, Embedder.table_checksum(data[offset, length]), "#{tag} の検査合計"
        end
      end
    end
  end
end
