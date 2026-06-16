# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/image_filename_sanitizer.rb
# ================================================================
# 責務:
#   画像ファイル名に含まれる「ビルド／EPUB を壊す文字」の判定と除去を一元化する。
#
# なぜ一元化するか（docs/specs/epub-kindle-webp-transcode-spec.md §4）:
#   同じ基準を 2 つの局面で使うため、ここを単一の真実とする。
#     - 検出: Guards::ImageFilenameCheck が既存プロジェクトの画像名を警告する
#     - 正規化: vs import が Re:VIEW Starter から取り込む際にファイル名を正す
#   import では実体（images/ へコピーするファイル名）と参照（markdown の
#   ![](name.webp)）の両方へ同一の sanitize を掛けないと食い違うため、基準の
#   ずれを避ける目的でも共有が要る。
# ================================================================

module VivlioStarter
  module CLI
    # 画像ファイル名の危険文字の判定・除去
    module ImageFilenameSanitizer
      module_function

      # 確実にビルド／EPUB を壊す文字（spec §4-2 の「危険」）。
      # () は Markdown ![alt](path) を壊す。' " & < > は XHTML 属性・実体参照（W14010）。
      # # ? % は URL 特殊文字。\ : * | は Windows 不可・zip 移植性。制御文字も対象。
      DANGEROUS_PATTERN = /[()'"&<>#?%\\:*|\x00-\x1f]/

      # 拡張子を除いた basename から危険文字を除去し、連続 `_` を畳む。
      # 削除方式により Einstein's → Einsteins のように自然な名前になる。空なら 'image'。
      # @param basename [String] 拡張子を含まないファイル名
      # @return [String]
      def sanitize(basename)
        safe = basename.to_s.gsub(DANGEROUS_PATTERN, '').strip.gsub(/_{2,}/, '_').sub(/\.+\z/, '')
        safe.empty? ? 'image' : safe
      end

      # 危険文字を含むか。
      def unsafe?(str) = str.to_s.match?(DANGEROUS_PATTERN)

      # 含まれる危険文字を出現順・重複なしで返す。
      def offending_characters(str) = str.to_s.chars.select { it.match?(DANGEROUS_PATTERN) }.uniq
    end
  end
end
