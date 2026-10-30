# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/build/font_metrics.rb
# ================================================================
# 責務:
#   書体ファイル（TrueType）から、字の送り・x ハイト・カーニングを読む。章扉のリードが何行に
#   なるかを、組まずに見積もるために使う（LeadLayout・chapter-lead-size-spec.md §4.4）。
#
# なぜカーニングまで読むのか:
#   Chromium は和文にも書体の kern を当てる。Noto Serif JP では「す。」が 0.08 字詰まり、
#   「え、」が 0.06 字開く。字数ちょうどの行が入るかどうかは、これで決まる。3 冊のリードを
#   6 通りの設定で組んで比べると、kern を省いた見積もりは行数が 94% しか合わず、入れると
#   99% 合った。
#
# 読むのは GPOS の kern の PairPos（型 2、拡張の型 9 に包まれたものも）だけ。字の置き換え
# （GSUB）は見ない。字の送りの調整は、HarfBuzz と同じく、最初に当てはまった下位表の値を使う。
# ================================================================

require 'ttfunk'
require_relative 'glyph_outline'

module VivlioStarter
  module CLI
    module Build
      class FontMetrics
        # @param path [String] TTF のパス
        # @return [FontMetrics] 同じ書体は一度だけ読む
        # 鍵は絶対パス。相対パスのままだと、作業ディレクトリが変わっても別の書体を返してしまう
        def self.load(path) = (@cache ||= {})[File.expand_path(path)] ||= new(path)

        # @return [Float] x ハイト（字の大きさに対する比）。CSS の ex の換算に使う
        attr_reader :x_height

        def initialize(path)
          @font = TTFunk::File.open(path)
          @upem = @font.header.units_per_em.to_f
          @cmap = @font.cmap.unicode.first
          @x_height = @font.os2.x_height.to_f / @upem
          @advances = {}
          @pairs = {}
          @kern = Kerning.new(@font)
        end

        # 書体にある字か
        def glyph?(char) = !glyph_id(char).nil?

        # 書体にある字のコードポイント（予備の書体の unicode-range を作る）
        def codepoints = @cmap.code_map.filter_map { |code, id| code if id.positive? }

        # 字の送り（字の大きさに対する比）。書体に無い字は nil
        def advance(char)
          @advances.fetch(char) do
            id = glyph_id(char)
            @advances[char] = id && (@font.horizontal_metrics.for(id).advance_width / @upem)
          end
        end

        # 字の輪郭（GlyphOutline::Outline）。書体に無い字・読めない輪郭は nil
        def outline(char) = GlyphOutline.for(@font, char)
        
        # 並んだ 2 字の送りの調整（字の大きさに対する比）。前の字の送りに足す
        def kern(left, right)
          @pairs.fetch([left, right]) do
            a = glyph_id(left)
            b = glyph_id(right)
            @pairs[[left, right]] = a && b ? @kern.adjust(a, b) / @upem : 0.0
          end
        end

        private

        def glyph_id(char)
          id = @cmap[char.ord]
          id&.positive? ? id : nil
        end

        # GPOS の kern の PairPos を引く
        class Kerning
          def initialize(font)
            table = font.directory.tables['GPOS']
            @data = table ? font.contents.string.byteslice(table[:offset], table[:length]) : nil
            @subtables = @data ? kern_lookups.map { subtables_of(it) } : []
          rescue StandardError
            @subtables = []
          end

          # @return [Integer] 前の字の送りに足す量（書体の単位）
          def adjust(left, right)
            @subtables.sum do |subtables|
              subtables.lazy.filter_map { pair_value(it, left, right) }.first || 0
            end
          rescue StandardError
            0
          end

          private

          def u16(offset) = @data.byteslice(offset, 2).unpack1('n')
          def i16(offset) = @data.byteslice(offset, 2).unpack1('s>')
          def u32(offset) = @data.byteslice(offset, 4).unpack1('N')

          # kern の機能が指す lookup の表の位置（どの用字系の kern も同じ lookup を指すので、まとめて引く）
          def kern_lookups
            features = u16(6)
            lookups = u16(8)
            indexes = (0...u16(features)).flat_map do |i|
              record = features + 2 + (i * 6)
              next [] unless @data.byteslice(record, 4) == 'kern'

              feature = features + u16(record + 4)
              (0...u16(feature + 2)).map { u16(feature + 4 + (it * 2)) }
            end
            indexes.uniq.sort.map { lookups + u16(lookups + 2 + (it * 2)) }
          end

          # PairPos の下位表の位置。拡張（型 9）は中身を開く
          def subtables_of(lookup)
            type = u16(lookup)
            (0...u16(lookup + 4)).filter_map do |i|
              subtable = lookup + u16(lookup + 6 + (i * 2))
              if type == 9 && u16(subtable + 2) == 2
                subtable + u32(subtable + 4)
              elsif type == 2
                subtable
              end
            end
          end

          # 下位表が 2 字に当てはまれば送りの調整を、当てはまらなければ nil を返す
          def pair_value(subtable, left, right)
            index = coverage_index(subtable + u16(subtable + 2), left) or return nil
            format1 = u16(subtable + 4)
            format2 = u16(subtable + 6)
            size1 = value_size(format1)
            size2 = value_size(format2)
            case u16(subtable)
            when 1 then pair_set_value(subtable + u16(subtable + 10 + (index * 2)), right, format1, size1 + size2)
            when 2 then class_pair_value(subtable, left, right, format1, size1 + size2)
            end
          end

          # 形式 1: 前の字ごとに、後ろの字と値の組を字の番号順に並べた表
          def pair_set_value(set, right, format, record_size)
            low = 0
            high = u16(set) - 1
            while low <= high
              mid = (low + high) / 2
              record = set + 2 + (mid * (2 + record_size))
              second = u16(record)
              return x_advance(record + 2, format) if second == right

              second < right ? low = mid + 1 : high = mid - 1
            end
            nil
          end

          # 形式 2: 字の組を級（クラス）の組で引く。前の字が覆われていれば、値が 0 でも当てはまったとみなす
          def class_pair_value(subtable, left, right, format, record_size)
            class1 = class_of(subtable + u16(subtable + 8), left)
            class2 = class_of(subtable + u16(subtable + 10), right)
            count1 = u16(subtable + 12)
            count2 = u16(subtable + 14)
            return nil if class1 >= count1 || class2 >= count2

            x_advance(subtable + 16 + (((class1 * count2) + class2) * record_size), format)
          end

          # 値の記録の中の XAdvance。無ければ 0
          def x_advance(record, format)
            return 0 if format.nobits?(0x0004)

            i16(record + ((format & 0x0003).to_s(2).count('1') * 2))
          end

          def value_size(format) = format.to_s(2).count('1') * 2

          def coverage_index(coverage, glyph)
            case u16(coverage)
            when 1
              low = 0
              high = u16(coverage + 2) - 1
              while low <= high
                mid = (low + high) / 2
                id = u16(coverage + 4 + (mid * 2))
                return mid if id == glyph

                id < glyph ? low = mid + 1 : high = mid - 1
              end
            when 2
              range = find_range(coverage + 4, u16(coverage + 2), glyph)
              range && (u16(range + 4) + glyph - u16(range))
            end
          end

          def class_of(class_def, glyph)
            case u16(class_def)
            when 1
              start = u16(class_def + 2)
              offset = glyph - start
              offset >= 0 && offset < u16(class_def + 4) ? u16(class_def + 6 + (offset * 2)) : 0
            when 2
              range = find_range(class_def + 4, u16(class_def + 2), glyph)
              range ? u16(range + 4) : 0
            else 0
            end
          end

          # 字の番号の範囲の並び（開始・終わり・値の 6 バイト）から、字を含む範囲を探す
          def find_range(records, count, glyph)
            low = 0
            high = count - 1
            while low <= high
              mid = (low + high) / 2
              record = records + (mid * 6)
              if glyph < u16(record) then high = mid - 1
              elsif glyph > u16(record + 2) then low = mid + 1
              else return record
              end
            end
            nil
          end
        end
      end
    end
  end
end
