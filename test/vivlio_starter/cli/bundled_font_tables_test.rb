# frozen_string_literal: true

# ================================================================
# Test: bundled_font_tables_test.rb
# ================================================================
# テスト対象:
#   同梱の TrueType 書体（stylesheets/fonts/**/*.ttf と、雛形の写し）の maxp 表
#
# 背景:
#   Keyboard-JP-Regular.ttf は原本の OTF（CFF）から作った TTF で、maxp が CFF 用の
#   版 0.5（numGlyphs だけ）のまま残っていた。Chrome はこの表を写したまま字の組を
#   PDF に埋め込むので、Adobe Acrobat Reader が「埋め込みフォント
#   「KAAAAA+Keyboard-JP-Regular」を抽出できません」と出し、技術書典の審査で
#   データ破損として差し戻された（改善案 #138）。pdffonts・qpdf --check・
#   macOS のプレビューでは何も出ない。
#
# 検証方法:
#   書体のファイルの表の並び（sfnt のテーブルディレクトリ）を読み、glyf 表を持つ書体の
#   maxp が版 1.0（0x00010000）であることを確かめる。
# ================================================================

require 'test_helper'

module VivlioStarter
  module CLI
    class BundledFontTablesTest < Minitest::Test
      ROOT = File.expand_path('../../..', __dir__)
      FONT_DIRS = %w[stylesheets/fonts lib/project_scaffold/stylesheets/fonts].freeze
      TRUETYPE_MAXP_VERSION = 0x00010000

      def test_should_give_every_bundled_truetype_font_a_version_one_maxp
        fonts = FONT_DIRS.flat_map { Dir.glob(File.join(ROOT, it, '**', '*.ttf')) }
        refute_empty fonts, '同梱の TTF が見つかりません'

        broken = fonts.filter_map do |path|
          tables = table_directory(path)
          next unless tables.key?('glyf')

          version = read_u32(path, tables.fetch('maxp'))
          "#{path.delete_prefix("#{ROOT}/")}: maxp 0x#{version.to_s(16)}" unless version == TRUETYPE_MAXP_VERSION
        end

        assert_empty broken, "glyf を持つ書体の maxp は版 1.0 にする（改善案 #138）:\n#{broken.join("\n")}"
      end

      private

      # sfnt のテーブルディレクトリ（表の名前 → ファイル内の位置）
      def table_directory(path)
        File.open(path, 'rb') do |file|
          _version, count = file.read(12).unpack('NnX2')
          count.times.to_h do
            tag, _checksum, offset, _length = file.read(16).unpack('a4NNN')
            [tag, offset]
          end
        end
      end

      def read_u32(path, offset) = File.binread(path, 4, offset).unpack1('N')
    end
  end
end
