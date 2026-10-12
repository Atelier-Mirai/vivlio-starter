# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/build/variant_glyph_font.rb
# ================================================================
# 責務:
#   異体字セレクタ付きの字（`禰󠄀` = U+79B0 U+E0100）の字形を書体の cmap format 14 から引き、
#   「セレクタの付かない親字がその字形を指す」小さな書体を作る（kindle-ivs-font-spec.md）。
#
# なぜ要るのか:
#   Kindle（KFX）は異体字セレクタを読まず、文字のまま組まれる字はすべて親字の形に戻る。
#   画像にすると読者が文字を大きくしたときに追従できない（kindle-inline-math-textify-spec.md
#   と同じ制約）。親字そのものに異体の字形を割り当てた書体なら、文字のまま正しい形で出る。
#
# なぜ自前で cmap を読むのか:
#   TTFunk は format 14 を解さない。読むのは表の決まった位置の数値だけなので、
#   ライブラリを足すより短く済む。
#
# 書体の名前:
#   同梱の Noto は SIL OFL 1.1 で、Noto Sans JP には予約名 `Source` がある。改変版は予約名を
#   名乗れない（OFL 第 3 条）ので、name テーブルは作り直す。著作権表示とライセンスは
#   機械可読のメタデータとして写す（OFL 第 2 条）。
# ================================================================

require 'ttfunk'
require 'ttfunk/subset'

module VivlioStarter
  module CLI
    module Build
      # 異体字の字形だけを持つ書体の生成
      module VariantGlyphFont
        # 対象にする「親字＋セレクタ」。IVS と、CJK 互換漢字の標準異体字シーケンス。
        # 絵文字の表示切替（FE0E・FE0F）と数学記号の SVS は、親字を漢字に限ることで外す。
        SEQUENCE = /(\p{Han})([\u{FE00}-\u{FE0D}\u{E0100}-\u{E01EF}])/

        # 書き直した name テーブルへ元の書体から写す名前（著作権表示・ライセンス・その URL）。
        COPIED_NAME_IDS = [0, 13, 14].freeze

        # 書体 1 本ぶんの異体の表。
        #
        # non_default: { [親字, セレクタ] => 字形 ID }（親字と違う字形を割り当てた組）
        # default:     { セレクタ => [[先頭の親字, 続く個数], ...] }（親字と同じ字形を使う組）
        Variants = Data.define(:non_default, :default) do
          # 組の種類。字形 ID（置き換える）・:default（親字の形が正しい）・nil（書体が知らない）。
          def lookup(base, selector)
            non_default.fetch([base, selector]) do
              ranges = default.fetch(selector, [])
              ranges.any? { |start, extra| base.between?(start, start + extra) } ? :default : nil
            end
          end

          def empty? = non_default.empty?
        end

        module_function

        # 書体の cmap format 14 を読む。表が無い・読めない書体は空の表を返す。
        # @param path [String] TTF の実体
        # @return [Variants]
        def read(path)
          data = File.binread(path)
          cmap = table_offset(data, 'cmap')
          return Variants.new(non_default: {}, default: {}) unless cmap

          subtable = format14_offset(data, cmap)
          return Variants.new(non_default: {}, default: {}) unless subtable

          parse_format14(data, subtable)
        rescue StandardError
          Variants.new(non_default: {}, default: {})
        end

        # 原稿に出た組を書体へ割り振る。1 本の書体の中で 1 つの親字は 1 つの字形しか指せないので、
        # 同じ親字の別の異体は次の書体へ回す（kindle-ivs-font-spec.md §2.4）。
        # @param pairs [Array<Array(Integer, Integer)>] 出現順の [親字, セレクタ]
        # @return [Array<Array<Array(Integer, Integer)>>] 書体ごとの組（先頭が 1 本目）
        def assign(pairs)
          pairs.uniq.each_with_object([]) do |pair, slots|
            slot = slots.find { |members| members.none? { it[0] == pair[0] } }
            slot ? slot << pair : slots << [pair]
          end
        end

        # 親字に異体の字形を割り当てた書体を作る。
        # @param path [String] 字形の取り元の TTF
        # @param glyphs [Hash{Integer => Integer}] 親字 => 元の書体での字形 ID
        # @param family [String] name テーブルに書くファミリ名（Noto・Source を含めない）
        # @return [String] TTF のバイト列
        def encode(path, glyphs, family:)
          original = TTFunk::File.open(path)
          subset = RemappedSubset.new(original, glyphs)
          glyphs.each_key { subset.use(it) }
          RenamedEncoder.new(original, subset, family:, notices: copied_names(File.binread(path))).encode
        end

        # --- 以下は cmap / name テーブルの読み書き ---

        # テーブルディレクトリから、指定したタグの位置を返す。
        def table_offset(data, tag)
          count = data[4, 2].unpack1('n')
          record = (0...count).map { data[12 + (it * 16), 16].unpack('a4NNN') }.find { it[0] == tag }
          record&.at(2)
        end

        # cmap の中の format 14 の位置。
        def format14_offset(data, cmap)
          data[cmap + 2, 2].unpack1('n').times do |i|
            offset = cmap + data[cmap + 4 + (i * 8) + 4, 4].unpack1('N')
            return offset if data[offset, 2].unpack1('n') == 14
          end
          nil
        end

        # format 14 の本体。セレクタごとの記録に、既定（範囲）と非既定（1 字ずつ）の表が付く。
        def parse_format14(data, start)
          non_default = {}
          default = Hash.new { |hash, key| hash[key] = [] }

          data[start + 6, 4].unpack1('N').times do |i|
            record = data[start + 10 + (i * 11), 11]
            selector = uint24(record[0, 3])
            default_offset, non_default_offset = record[3, 8].unpack('NN')

            each_entry(data, start, default_offset, 4) do |entry|
              default[selector] << [uint24(entry[0, 3]), entry[3].ord]
            end
            each_entry(data, start, non_default_offset, 5) do |entry|
              non_default[[uint24(entry[0, 3]), selector]] = entry[3, 2].unpack1('n')
            end
          end

          Variants.new(non_default:, default: default.to_h)
        end

        # 個数（uint32）に続く固定長の項目を順に渡す。オフセットは format 14 の先頭からで、0 は「表が無い」。
        def each_entry(data, start, offset, size)
          return if offset.zero?

          table = start + offset
          data[table, 4].unpack1('N').times { yield data[table + 4 + (it * size), size] }
        end

        def uint24(bytes) = bytes.unpack('C3').then { |a, b, c| (a << 16) | (b << 8) | c }

        # 元の書体の Windows 向け（UTF-16BE）の名前から、写すべきものを拾う。
        # @return [Hash{Integer => String}] name ID => UTF-16BE のバイト列
        def copied_names(data)
          name = table_offset(data, 'name')
          return {} unless name

          _format, count, storage = data[name, 6].unpack('nnn')
          (0...count).each_with_object({}) do |i, names|
            platform, encoding, language, id, length, offset = data[name + 6 + (i * 12), 12].unpack('n6')
            next unless platform == 3 && encoding == 1 && language == 0x409 && COPIED_NAME_IDS.include?(id)

            names[id] = data[name + storage + offset, length]
          end
        end

        # 親字の字形を、指定の字形 ID へ差し替えたサブセット。
        class RemappedSubset < TTFunk::Subset::Unicode
          # `@glyphs` は TTFunk::Subset::Base が字形のメモに使っているので別の名前にする。
          def initialize(original, glyphs)
            @remapped_glyphs = glyphs
            super(original)
          end

          # 元の cmap の代わりに引かれる表。差し替える親字だけ異体の字形を返す。
          def unicode_cmap
            @unicode_cmap ||= begin
              original_cmap = super
              glyphs = @remapped_glyphs
              Object.new.tap do |table|
                table.define_singleton_method(:[]) { |code| glyphs.fetch(code) { original_cmap[code] } }
              end
            end
          end
        end

        # name テーブルだけ作り直すエンコーダ。ほかのテーブルは TTFunk に任せる。
        class RenamedEncoder < TTFunk::TTFEncoder
          def initialize(original, subset, family:, notices:)
            @family = family
            @notices = notices
            super(original, subset)
          end

          def name_table
            @name_table ||= begin
              postscript = @family.delete(' ')
              names = @notices.merge(
                1 => utf16(@family), 2 => utf16('Regular'), 3 => utf16(postscript),
                4 => utf16(@family), 6 => utf16(postscript)
              ).sort.to_h

              records = +''
              storage = +''
              names.each do |id, bytes|
                records << [3, 1, 0x409, id, bytes.bytesize, storage.bytesize].pack('n6')
                storage << bytes
              end
              [0, names.size, 6 + (names.size * 12)].pack('n3') + records + storage
            end
          end

          private

          def utf16(text) = text.encode('UTF-16BE').b
        end
      end
    end
  end
end
