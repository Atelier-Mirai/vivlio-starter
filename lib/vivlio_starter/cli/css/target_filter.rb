# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/css/target_filter.rb
# ================================================================
# 責務:
#   平らにした規則の列から、出力先が扱えない規則と宣言を落とす
#   （css-layer-restructure-spec.md §4.2 の 4）。
#
# なぜ EPUB に入れる前に落とすか:
#   1.x は組み上がった EPUB を開いて CSS を書き換えていた（sanitize_epub_css!）。
#   平らな CSS を生成する段で落とせば、EPUB を開き直す処理が要らず、Vivliostyle も
#   参照の切れた url() を見ない。
#
# 落とすもの:
#   epub・kindle
#     - @page の中の余白の箱（@top-left など）と @footnote。EPUBCheck が構文ごと
#       CSS-008 として拒む
#     - 書体を埋め込まないときの @font-face。fonts/ を運ばないので src が参照切れ
#       （RSC-007）になる。実体を運ぶ keyfont（キーの図）の面は残す
#   kindle
#     - WebP を指す url() を含む宣言。Kindle には WebP を運ばない（扉絵・節絵の背景は
#       合成した画像に置き換わっていて、リフローの EPUB では元々描かれない）
#     - data URI を含む宣言。Kindle Previewer が W14224（無効な datauri）を出す。本書で
#       当たるのはタスクリストの鉤だけで、Kindle では実体の文字（□・■）に置き換わる
# ================================================================

require_relative 'flattener'

module VivlioStarter
  module CLI
    module Css
      # 出力先のフィルタ
      module TargetFilter
        # @page の余白の箱と @footnote（中身は 1 段の宣言だけ）。
        # `margin-bottom` などのプロパティの名前（先頭に @ が無い）には当たらない。
        MARGIN_BOX_PATTERN = /@(?:(?:top|bottom|left|right)-[a-z-]+|footnote)\s*\{[^{}]*\}/

        # @font-face の囲み 1 つ（中身は 1 段の宣言だけ）
        FONT_FACE_PATTERN = /@font-face\s*\{[^{}]*\}/

        # 書体を埋め込まなくても運ぶ面。keyfont は実体も同梱する（Epub::Workspace.keyfont_asset?）。
        # Kindle の異体字の 1 字書体（vs-variant-*）は、このフィルタの後に足されるが、
        # 目印として同じ表に置く
        KEPT_FACE_PATTERN = /font-family:\s*["']?(?:keyfont\b|vs-variant-)/i

        # `url(….webp)` を含む宣言 1 つ。`[^;{}]*` で宣言の境を越えず、url は 1 つに限る。
        # プロパティの名前は数字を含む（`--h3-marker`）ので `[\w-]+` で丸ごと拾う
        WEBP_URL_PATTERN = /[\w-]+\s*:\s*[^;{}]*url\([^)]*\.webp[^)]*\)[^;}]*;?/i

        # `url("data:…")` を含む宣言 1 つ（境の取り方は WEBP_URL_PATTERN と同じ）
        DATA_URI_DECL_PATTERN = /[\w-]+\s*:\s*[^;{}]*url\(["']?data:[^)]*\)[^;}]*;?/i

        module_function

        # @param pieces [Array<Flattener::Piece>]
        # @param target [Symbol] :pdf / :epub / :kindle
        # @param embed_fonts [Boolean] EPUB に書体の実体を入れるか
        # @return [Array<Flattener::Piece>]
        def apply(pieces, target:, embed_fonts:)
          return pieces if target == :pdf

          pieces.filter_map do |piece|
            text = piece.text.gsub(MARGIN_BOX_PATTERN, '')
            text = text.gsub(FONT_FACE_PATTERN) { it.match?(KEPT_FACE_PATTERN) ? it : '' } unless embed_fonts
            text = text.gsub(WEBP_URL_PATTERN, '').gsub(DATA_URI_DECL_PATTERN, '') if target == :kindle
            piece.with(text:) unless text.strip.empty?
          end
        end
      end
    end
  end
end
