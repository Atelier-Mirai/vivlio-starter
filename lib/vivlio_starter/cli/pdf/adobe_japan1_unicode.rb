# frozen_string_literal: true

require 'pdf/reader'

module VivlioStarter
  module PDF
    # ToUnicode を持たない日本語の書体の字を、Adobe-Japan1 の字の番号（CID）から Unicode へ戻す
    # （pdf-read-structure-spec.md §2.3）。
    #
    # 市販の技術書の PDF には、ヒラギノや新ゴを ToUnicode 無しの Identity-H で埋め込んだものが多い。
    # pdf-reader はそのとき CID をそのまま Unicode とみなすので、「MOSFET」が「.04'&5」に、「図」が「ਤ」になる。
    # PDF の仕様（ISO 32000-1 9.10.2）は、ToUnicode が無く、子の書体の CIDSystemInfo が Adobe-Japan1 などの
    # 既定の字の集まりなら、その集まりの表で Unicode を求めると定めている。HexaPDF はそうしているが、
    # pdf-reader はしていないので、ここで補う。
    #
    # 表は Adobe の mapping-resources-pdf の pdf2unicode/Adobe-Japan1-UCS2 を手を加えずに同梱した
    # （BSD 3 条項・著作権表示はファイルの先頭）。cmap-resources の cid2code.txt は比例幅の仮名
    # （新ゴ・ヒラギノの 90msp が使う CID 12063 以降）に Unicode を持たないので使わない。
    module AdobeJapan1Unicode
      CMAP_PATH = File.expand_path('data/Adobe-Japan1-UCS2', __dir__)
      IDENTITY = %i[Identity-H Identity-V].freeze

      # 異体字セレクタ。表は数字の「0」の斜線なしの字形などを「0」+ U+FE00 で書くが、本文の字としては要らない
      VARIATION_SELECTOR = /[\u{FE00}-\u{FE0F}\u{E0100}-\u{E01EF}]/

      # pdf-reader の CMap と同じ形で、CID から Unicode の配列を返す（表に無い字は空）
      def self.decode(cid) = cmap.decode(cid).reject { VARIATION_SELECTOR.match?(it.chr(Encoding::UTF_8)) }

      # 表は 2 万字あまりあるので、表で字を引くことになったときに初めて読む（0.1 秒ほど）
      def self.cmap = @cmap ||= ::PDF::Reader::CMap.new(File.read(CMAP_PATH))

      # Identity-H/V で CID をそのまま字の番号に使い、子の書体が Adobe-Japan1 を名乗る Type 0 の書体か（ToUnicode の有無は問わない）
      def self.applies?(objects, font)
        return false unless IDENTITY.include?(objects.deref(font[:Encoding]))

        descendant = objects.deref_hash(objects.deref_array(font[:DescendantFonts])&.first)
        info = descendant && objects.deref_hash(descendant[:CIDSystemInfo])
        !info.nil? && objects.deref_string(info[:Registry]) == 'Adobe' && objects.deref_string(info[:Ordering]) == 'Japan1'
      rescue ::PDF::Reader::MalformedPDFError
        false
      end

      # ToUnicode を持つのに、一部の字の対応を欠く PDF がある（Exercise D の「小」「整」「設」。poppler も落とす）。
      # 仕様は ToUnicode を先に見ると定めるので、ToUnicode で引けなかった字だけを表で補う（HexaPDF と同じ）。
      # ToUnicode が康熙部首の字（U+2F00〜2FD5）を返し、表の字がそれを NFKC で戻した字と違うときも表を使う。IPSJ の論文は
      # 見出しの頭の「◼」（CID 12238）と空白（CID 1）を「⿎」に当てていて、受け手が NFKC で戻すと「鼓鼓」になった。
      # 「行」を「⾏」に当てる PDF（practicaltests）は、表の字と NFKC で戻した字が同じなので ToUnicode のまま
      WithFallback = Data.define(:to_unicode) do
        def decode(cid)
          mapped = to_unicode.decode(cid)
          return AdobeJapan1Unicode.decode(cid) if mapped.empty?
          return mapped unless mapped.one? && KANGXI_RADICALS.cover?(mapped.first)

          table = AdobeJapan1Unicode.decode(cid)
          table.empty? || table.pack('U*') == mapped.pack('U*').unicode_normalize(:nfkc) ? mapped : table
        end
      end
      KANGXI_RADICALS = (0x2F00..0x2FD5)

      # pdf-reader は書体の辞書をページの読み取りの奥で Font にするので、作るところで表を当てる。
      # Font は元の辞書を持ち歩かない（CIDSystemInfo を後から見られない）ため、初期化に割り込むしかない
      module FontExtension
        def initialize(objects, font)
          super
          return unless AdobeJapan1Unicode.applies?(objects, font)

          @tounicode = @tounicode ? WithFallback.new(@tounicode) : AdobeJapan1Unicode
        end
      end

      ::PDF::Reader::Font.prepend(FontExtension)
    end
  end
end
