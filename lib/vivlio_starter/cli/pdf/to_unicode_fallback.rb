# frozen_string_literal: true

require 'pdf/reader'

module VivlioStarter
  module PDF
    # ToUnicode に無い字を、書体の符号表（Encoding）で読む（pdf-read-structure-spec.md §2.3）。
    #
    # pLaTeX（dvipdfmx）の英字の書体（SFRM1000 など）は、ToUnicode に合字「ff」の 1 字だけを書き、
    # ほかの字は符号表で読ませる。pdf-reader は ToUnicode があると符号表を見ないので、ToUnicode に無い字が
    # 空になり、『実践 Rust Web 開発 5』の「Axum は Tokio（非同期の実行 環境）の上に作られた」から英字の語が
    # すべて消えていた。poppler と同じく、ToUnicode で引けなかった字だけを符号表で読む。
    #
    # Type 0（CID）の書体は除く。符号は字形の番号で、符号表から読むと化けた字になる（日本語の書体は
    # AdobeJapan1Unicode が補う）。
    module ToUnicodeFallback
      def to_utf8(code)
        text = super
        return text unless text.empty? && code.is_a?(Integer) && tounicode && subtype != :Type0

        encoding.int_to_utf8_string(code)
      end
    end

    ::PDF::Reader::Font.prepend(ToUnicodeFallback)
  end
end
