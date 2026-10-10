# frozen_string_literal: true

require 'pdf/reader'

module VivlioStarter
  module PDF
    # 既定の符号表（CMap）の名前を符号に使う日本語の書体の字を、文字コードとして読む（pdf-read-structure-spec.md §2.3）。
    #
    # Word が書き出した古い論文の PDF は、MS 明朝・MS ゴシックを埋め込まず、符号を Shift_JIS のまま書く
    # （`90ms-RKSJ-H`）か UTF-16 で書く（`UniJIS-UTF16-H`）。ToUnicode も無い。pdf-reader はこの符号表を知らないので、
    # 1 バイトずつ標準の符号表で読み、「統計数理」が「v æ33“」のように化ける（poppler は読める）。
    # 符号表の名前から文字コードが分かるので、その文字コードで区切って Unicode へ戻す。
    #
    # 字の幅は子の書体の W が字の番号（CID）で引くので、符号からは引けない（符号から CID への表は Adobe の
    # cmap-resources にあるが、大きいので同梱しない）。MS 明朝・MS ゴシックの幅は半角が 500・全角が 1000 なので、
    # 半角の字（1 バイトの字・ASCII・半角カナ）を 500、ほかを子の書体の既定の幅（DW）とみなす。
    module PredefinedCMap
      # Shift_JIS（RKSJ）・UCS-2/UTF-16 の符号表。90ms-RKSJ-H・90msp-RKSJ-V・UniJIS-UTF16-H・UniJIS-UCS2-H など
      SHIFT_JIS = /RKSJ-[HV]\z/
      UTF16 = /(?:UCS2|UTF16)-[HV]\z/
      # Shift_JIS の 2 バイトの字の 1 バイト目
      LEAD_BYTE = ->(byte) { (0x81..0x9F).cover?(byte) || (0xE0..0xFC).cover?(byte) }
      HALF_WIDTH = /[ -~｡-ﾟ]/
      HALF_WIDTH_GLYPH = 500

      def initialize(objects, font)
        super
        name = objects.deref(font[:Encoding]).to_s
        @predefined_cmap = if subtype != :Type0 then nil
                           elsif name.match?(SHIFT_JIS) then :shift_jis
                           elsif name.match?(UTF16) then :utf16
                           end
        return unless @predefined_cmap

        descendant = objects.deref_hash(objects.deref_array(font[:DescendantFonts])&.first)
        @full_width_glyph = descendant&.[](:DW) || 1000
      end

      # 文字コードの 1 字を 1 つの符号にする（Shift_JIS は 1〜2 バイト、UTF-16 はサロゲートの組を 1 つに）
      def unpack(data)
        case @predefined_cmap
        when :shift_jis
          bytes = data.bytes
          codes = []
          codes << (LEAD_BYTE.(bytes.first) && bytes.size > 1 ? (bytes.shift << 8) | bytes.shift : bytes.shift) until bytes.empty?
          codes
        when :utf16
          data.unpack('n*').slice_when { |a, b| !(0xD800..0xDBFF).cover?(a) || !(0xDC00..0xDFFF).cover?(b) }.map { it.reduce { (_1 << 16) | _2 } }
        else super
        end
      end

      # ToUnicode があればそれで引く（符号の区切りが正しくなれば引ける）。無ければ文字コードとして読む
      def to_utf8(code)
        return super unless @predefined_cmap && code.is_a?(Integer) && !tounicode

        bytes = case @predefined_cmap
                when :shift_jis then code > 0xFF ? [code].pack('n') : [code].pack('C')
                else code > 0xFFFF ? [code >> 16, code & 0xFFFF].pack('n*') : [code].pack('n')
                end
        source = @predefined_cmap == :shift_jis ? Encoding::Windows_31J : Encoding::UTF_16BE
        bytes.force_encoding(source).encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: ToUnicodeFallback::UNKNOWN_CHAR)
      end

      def glyph_width(code)
        return super unless @predefined_cmap && code.is_a?(Integer)

        half = @predefined_cmap == :shift_jis ? code <= 0xFF : to_utf8(code).match?(HALF_WIDTH)
        half ? HALF_WIDTH_GLYPH : @full_width_glyph
      end
    end

    ::PDF::Reader::Font.prepend(PredefinedCMap)
  end
end
