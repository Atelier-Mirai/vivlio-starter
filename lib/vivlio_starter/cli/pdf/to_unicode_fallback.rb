# frozen_string_literal: true

require 'pdf/reader'

module VivlioStarter
  module PDF
    # pdf-reader が Unicode に戻せない字を補う（pdf-read-structure-spec.md §2.3）。
    #
    # 1. ToUnicode に無い字を、書体の符号表（Encoding）で読む。pLaTeX（dvipdfmx）の英字の書体（SFRM1000 など）は、
    #    ToUnicode に合字「ff」の 1 字だけを書き、ほかの字は符号表で読ませる。pdf-reader は ToUnicode があると
    #    符号表を見ないので、ToUnicode に無い字が空になり、『実践 Rust Web 開発 5』の「Axum は Tokio（非同期の実行
    #    環境）の上に作られた」から英字の語がすべて消えていた。poppler と同じく、ToUnicode で引けなかった字だけを
    #    符号表で読む。Type 0（CID）の書体は除く。符号は字形の番号で、符号表から読むと化けた字になる
    #    （日本語の書体は AdobeJapan1Unicode が補う）。
    # 2. 符号表の Differences を読み直す。pdf-reader は字の名前の一覧に無い名前（「zero.a」のような接尾辞付きの
    #    別字形）を飛ばすとき、番号を進め忘れるので、後ろの字が 1 つずつ前の番号にずれる。Rust-tutorial のコードでは
    #    行番号の「0」（zero.a）が空白に、空白が名前の分からない字「▯」になっていた（2 冊で 4,000 字あまり）。
    #    名前の一覧に無い名前は、字の名前の決まりどおり接尾辞（「.」から後ろ）を外して引く。
    # 3. TeX の記号の書体（CMSY）の 0〜31 番。符号表（Encoding）を持たない CMSY は、書体の中の並びで字を決めるが、
    #    pdf-reader は標準の符号表で読むので、箇条書きの点（15 番）や ≤・× が「▯」になる。
    #    0〜31 番は標準の符号表では空きなので、CMSY の並びで補う。32 番以降（平方根の根号の「p」など）は変えない。
    #    dvipdfmx が符号を付け直した CMSY（Differences 付きの符号表。2 番が circlecopyrt など）は並びが違うので除く
    module ToUnicodeFallback
      # pdf-reader が名前の分からない字に当てる字
      UNKNOWN_CHAR = "▯"
      TEX_SYMBOL_FONT = /\A(?:[A-Z]{6}\+)?CMSY\d+\z/
      # CMSY（OMS）の 0〜31 番。14 番（openbullet）と 15 番（bullet）は箇条書きの点として「◦」「•」にする
      CMSY_LOW = '−·×∗÷⋄±∓⊕⊖⊗⊘⊙◯◦•≍≡⊆⊇≤≥⪯⪰∼≈⊂⊃≪≫≺≻'

      def initialize(objects, font)
        super
        @builtin_encoding = font[:Encoding].nil?
        @differences = ToUnicodeFallback.differences(objects, font) unless subtype == :Type0
      end

      def to_utf8(code)
        text = super
        return text unless code.is_a?(Integer)

        # ToUnicode があればそれが先。無ければ、ずれを直した Differences が pdf-reader の読みに代わる
        if tounicode ? text.empty? && subtype != :Type0 : @differences&.key?(code)
          text = @differences&.[](code) || encoding.int_to_utf8_string(code)
        end
        cmsy_low = @builtin_encoding && code < CMSY_LOW.size && basefont.to_s.match?(TEX_SYMBOL_FONT)
        text == UNKNOWN_CHAR && cmsy_low ? CMSY_LOW[code] : text
      end

      # Differences の番号と字の対応（pdf-reader が正しく読める Differences なら nil）
      # @return [Hash{Integer => String}, nil]
      def self.differences(objects, font)
        encoding = objects.deref(font[:Encoding])
        entries = encoding.is_a?(Hash) ? objects.deref(encoding[:Differences]) : nil
        return nil unless entries.is_a?(Array)

        glyphs = ::PDF::Reader::GlyphHash.new
        return nil if entries.all? { !it.is_a?(Symbol) || glyphs.name_to_unicode(it) }

        code = 0
        entries.each_with_object({}) do |entry, map|
          next code = entry.to_i if entry.is_a?(Numeric)

          unicode = glyphs.name_to_unicode(entry) || glyphs.name_to_unicode(entry.to_s.split('.').first.to_s.to_sym)
          map[code] = [unicode].pack('U') if unicode
          code += 1
        end
      rescue ::PDF::Reader::MalformedPDFError
        nil
      end
    end

    ::PDF::Reader::Font.prepend(ToUnicodeFallback)
  end
end
