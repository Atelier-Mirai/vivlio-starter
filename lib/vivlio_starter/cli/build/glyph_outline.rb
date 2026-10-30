# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/build/glyph_outline.rb
# ================================================================
# 責務:
#   書体ファイルから 1 字の輪郭を読み、SVG の path（`d` 属性）にする（改善案 #127 段階 4）。
#   本の書体にない漢字（外字）を、字の形の図形として組むために使う（Gaiji）。
#
# なぜ自前で TrueType の輪郭を読むのか:
#   TTFunk は CFF の輪郭を Path として返す（Cff::Charstring#path）が、TrueType の `glyf` は
#   座標を読まない（部分集合を作るのに要らないため）。読むのは表の決まった形の数値だけなので、
#   道具（hb-view など）を足すより短く済む。
#
# 座標:
#   字の大きさを 1000 に直し、上下を返す（SVG は下向きが正）。基線が y = 0 で、
#   和文の字面の枠（em box）は y = -880〜120 になる（Gaiji::VIEW_BOX）。
# ================================================================

require 'ttfunk'

module VivlioStarter
  module CLI
    module Build
      # 書体の 1 字の輪郭 → SVG の path
      module GlyphOutline
        # 字の大きさをこの値に直す
        EM = 1000.0

        # TrueType の点の印（glyf の flags）
        ON_CURVE = 0x01
        X_SHORT = 0x02
        Y_SHORT = 0x04
        REPEAT = 0x08
        X_SAME_OR_POSITIVE = 0x10
        Y_SAME_OR_POSITIVE = 0x20

        # 1 字の輪郭
        # @!attribute d [String] SVG の path の `d`
        # @!attribute advance [Float] 字の送り（EM に直した値）
        # @!attribute top [Float] 字の上端（SVG の座標・基線より上は負）。制御点を含めた外枠
        # @!attribute bottom [Float] 字の下端（同じ座標）
        Outline = Data.define(:d, :advance, :top, :bottom)

        module_function

        # @param font [TTFunk::File] 書体（TTC は面を選んだもの）
        # @param char [String] 1 字
        # @return [Outline, nil] 書体に無い字・読めない輪郭（複合の字形など）は nil
        def for(font, char)
          gid = glyph_id(font, char) or return nil
          scale = EM / font.header.units_per_em
          commands = font.directory.tables.key?('CFF ') ? cff_commands(font, gid) : truetype_commands(font, gid)
          return nil if commands.nil? || commands.empty?

          advance = font.horizontal_metrics.for(gid).advance_width * scale
          ys = commands.flat_map { |_, *values| values.each_slice(2).map { -it[1] * scale } }
          Outline.new(d: svg_path(commands, scale), advance:, top: ys.min, bottom: ys.max)
        end

        # 字の番号。cmap の表のどれかにあれば引く（format 14 の異体字の表は除く）
        def glyph_id(font, char)
          font.cmap.tables.select { it.unicode? && it.respond_to?(:code_map) }
              .map { it.code_map[char.ord] }.find { it.to_i.positive? }
        end

        # CFF の輪郭（TTFunk の Path の命令をそのまま使う）
        def cff_commands(font, gid)
          font.cff.top_index[0].charstrings_index[gid].path.commands
        end

        # TrueType の輪郭を、CFF と同じ形の命令（:move・:line・:quad・:close）にする。
        # 複合の字形（部品を組み合わせた字）は読まない（nil）——外字の候補が尽きるだけで、
        # 次の書体を探せばよい
        def truetype_commands(font, gid)
          glyph = font.glyph_outlines.for(gid)
          return nil if glyph.nil? || glyph.compound?

          contours(glyph).flat_map { contour_commands(it) }
        end

        # 輪郭ごとの点（[x, y, on_curve?]）
        def contours(glyph)
          raw = glyph.raw
          ends = glyph.end_points_of_contours
          count = ends.last + 1
          offset = 10 + (ends.size * 2) + 2 + glyph.instruction_length

          # --- Phase: 点の印 ---
          flags = []
          while flags.size < count
            flag = raw.getbyte(offset)
            offset += 1
            repeat = 0
            if flag & REPEAT != 0
              repeat = raw.getbyte(offset)
              offset += 1
            end
            (repeat + 1).times { flags << flag }
          end

          # --- Phase: 座標（前の点からの差） ---
          xs, offset = coordinates(raw, offset, flags, X_SHORT, X_SAME_OR_POSITIVE)
          ys, = coordinates(raw, offset, flags, Y_SHORT, Y_SAME_OR_POSITIVE)
          points = xs.zip(ys, flags.map { it & ON_CURVE != 0 })

          starts = [0, *ends[0...-1].map { it + 1 }]
          starts.zip(ends).map { |first, last| points[first..last] }
        end

        def coordinates(raw, offset, flags, short_bit, same_bit)
          value = 0
          values = flags.map do |flag|
            if flag & short_bit != 0
              delta = raw.getbyte(offset)
              offset += 1
              value += flag & same_bit != 0 ? delta : -delta
            elsif flag & same_bit == 0
              value += raw.byteslice(offset, 2).unpack1('s>')
              offset += 2
            end
            value
          end
          [values, offset]
        end

        # 1 つの輪郭を命令にする。曲線の外の点（off-curve）が続くときは、間に中点の
        # 曲線上の点を補う（TrueType の 2 次ベジェの決まり）
        def contour_commands(points)
          return [] if points.size < 2

          # 曲線上の点から始める。どれも外の点なら、最初の 2 点の中点から始める
          start = points.index { it[2] }
          ring = if start
                   points.rotate(start)
                 else
                   [[(points[0][0] + points[1][0]) / 2.0, (points[0][1] + points[1][1]) / 2.0, true], *points]
                 end

          first = ring.first
          commands = [[:move, first[0], first[1]]]
          control = nil
          (ring.drop(1) + [first]).each do |x, y, on|
            if on
              commands << (control ? [:quad, *control, x, y] : [:line, x, y])
              control = nil
            elsif control
              mid = [(control[0] + x) / 2.0, (control[1] + y) / 2.0]
              commands << [:quad, *control, *mid]
              control = [x, y]
            else
              control = [x, y]
            end
          end
          commands << [:close]
        end

        # 命令を SVG の path にする。大きさを EM に直し、上下を返す
        def svg_path(commands, scale)
          commands.map do |name, *values|
            points = values.each_slice(2).map { |x, y| "#{number(x * scale)} #{number(-y * scale)}" }
            case name
            when :move then "M#{points.join(' ')}"
            when :line then "L#{points.join(' ')}"
            when :quad then "Q#{points.join(' ')}"
            when :curve then "C#{points.join(' ')}"
            when :close then 'Z'
            end
          end.join
        end

        def number(value) = format('%.1f', value).delete_suffix('.0')
      end
    end
  end
end
