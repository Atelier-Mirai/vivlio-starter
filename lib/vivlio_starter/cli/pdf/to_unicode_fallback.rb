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
    # 4. 縦書きの書体（符号表の名前が -V で終わる）に印を付ける。pdf-reader は縦書きの字も横に進めて位置を出すので、
    #    版面の外のつめに縦に組んだ「リポジトリを作ってみよう」が本文の行に混ざる（MarkedContentReceiver が回した字として扱う）
    # 5. dvips が TeX の書体をビットマップの Type 3 で埋め込んだ PDF（字の名前が「102」のような番号）の 0〜31 番。
    #    名前で引けず、pdf-reader は標準の符号表で読むので、合字の「fi」「ff」や数式の「−」「π」が「▯」になる
    #    （heidelberg で 100 字あまり）。書体の名前が無いので、持っている字の番号で TeX の書体の種類を見分け、その並びで補う。
    #    英字が多く「<」「>」（60・62 番。本文の書体では「¡」「¿」）を持てば数式の書体（OML）、ほかの英字の多い書体は
    #    本文の書体（OT1）、英字をほとんど持たないものは記号の書体（OMS）。見当が外れても「▯」が別の字になるだけ
    # 6. Linotype の数式記号の書体（Mathematical Pi）は、字の名前を「H9266」のような番号にし、書き出したソフトが ToUnicode に
    #    Symbol 書体の慣習の英字（π を「p」）や名前の末尾の数字（= を「5」）を書く（IPSJ の論文の「f(x)51/x2a50」）。
    #    ToUnicode より先に、字の名前で読む（H9251 から α β γ… の順。H11001〜H11005 は + − × ÷ =）
    module ToUnicodeFallback
      # pdf-reader が名前の分からない字に当てる字
      UNKNOWN_CHAR = "▯"
      TEX_SYMBOL_FONT = /\A(?:[A-Z]{6}\+)?CMSY\d+\z/
      # CMSY（OMS）の 0〜31 番。14 番（openbullet）と 15 番（bullet）は箇条書きの点として「◦」「•」にする
      CMSY_LOW = '−·×∗÷⋄±∓⊕⊖⊗⊘⊙◯◦•≍≡⊆⊇≤≥⪯⪰∼≈⊂⊃≪≫≺≻'
      # TeX の本文の書体（OT1）の 0〜31 番。18〜24 番は字に重ねて描くアクセントなので補わない（「▯」のまま）
      OT1_LOW = [*'ΓΔΘΛΞΠΣΥΦΨΩ'.chars, 'ff', 'fi', 'fl', 'ffi', 'ffl', 'ı', 'ȷ', *Array.new(7), *'ßæœøÆŒØ'.chars].freeze
      # TeX の数式の書体（OML）の 0〜31 番
      OML_LOW = 'ΓΔΘΛΞΠΣΥΦΨΩαβγδϵζηθικλμνξπρστυϕχ'
      NUMBERED_GLYPH_NAME = /\A\d+\z/
      MATH_PI_FONT = /\A(?:[A-Z]{6}\+)?MathematicalPi/
      MATH_PI_NAMES = {
        **'αβγδεζηθικλμνξοπρστυφχψω'.each_char.with_index.to_h { |char, index| [:"H#{9251 + index}", char] },
        H11001: '+', H11002: '−', H11003: '×', H11004: '÷', H11005: '='
      }.freeze

      def initialize(objects, font)
        super
        @builtin_encoding = font[:Encoding].nil?
        @vertical_writing = objects.deref(font[:Encoding]).to_s.end_with?('-V')
        @differences = ToUnicodeFallback.differences(objects, font) unless subtype == :Type0
        @tex_low = ToUnicodeFallback.tex_bitmap_low(objects, font) if subtype == :Type3
        @math_pi = ToUnicodeFallback.math_pi_chars(objects, font) if basefont.to_s.match?(MATH_PI_FONT)
      end

      def vertical_writing? = @vertical_writing

      def to_utf8(code)
        text = super
        return text unless code.is_a?(Integer)
        return @math_pi[code] if @math_pi&.key?(code)

        # ToUnicode があればそれが先。無ければ、ずれを直した Differences が pdf-reader の読みに代わる
        if tounicode ? text.empty? && subtype != :Type0 : @differences&.key?(code)
          text = @differences&.[](code) || encoding.int_to_utf8_string(code)
        end
        cmsy_low = @builtin_encoding && code < CMSY_LOW.size && basefont.to_s.match?(TEX_SYMBOL_FONT)
        return CMSY_LOW[code] if text == UNKNOWN_CHAR && cmsy_low

        text == UNKNOWN_CHAR && @tex_low && code < 32 ? @tex_low[code] || text : text
      end

      # Mathematical Pi の書体の、符号と字（Differences の字の名前で MATH_PI_NAMES に載るものだけ）
      # @return [Hash{Integer => String}]
      def self.math_pi_chars(objects, font)
        encoding = objects.deref(font[:Encoding])
        entries = encoding.is_a?(Hash) ? objects.deref(encoding[:Differences]) : nil
        return {} unless entries.is_a?(Array)

        code = 0
        entries.each_with_object({}) do |entry, chars|
          next code = entry.to_i if entry.is_a?(Numeric)

          chars[code] = MATH_PI_NAMES[entry] if MATH_PI_NAMES.key?(entry)
          code += 1
        end
      rescue ::PDF::Reader::MalformedPDFError
        {}
      end

      # 字の名前が番号の Type 3 の書体（dvips のビットマップの TeX の書体）の 0〜31 番の並び（ほかの書体なら nil）
      # @return [String, Array<String, nil>, nil]
      def self.tex_bitmap_low(objects, font)
        encoding = objects.deref(font[:Encoding])
        entries = encoding.is_a?(Hash) ? objects.deref(encoding[:Differences]) : nil
        return nil unless entries.is_a?(Array) && entries.any?(Symbol) && entries.grep(Symbol).all? { it.to_s.match?(NUMBERED_GLYPH_NAME) }

        codes = entries.grep(Symbol).map { it.to_s.to_i }
        return CMSY_LOW if codes.count { (97..122).cover?(it) } < 3
        return OML_LOW if codes.intersect?([60, 62])

        OT1_LOW
      rescue ::PDF::Reader::MalformedPDFError
        nil
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
