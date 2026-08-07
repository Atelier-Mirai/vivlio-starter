# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/pre_process/svg_font_embedder.rb
# ================================================================
# 責務:
#   `<img>` から参照される合成 SVG に、その SVG が使う字だけを絞った
#   @font-face（data: URI）を持たせる。
#
# なぜ要るのか:
#   showcase / mermaid の生成 SVG はファイルへ書き出して `<img src="...svg">` で
#   参照する。これは**独立文書**なので、本文 HTML の @font-face も CSS 変数も届かず、
#   相対パスの外部フォントも読めない（実測で確認済み）。結果、指定した書体は解決されず
#   OS の既定和文フォント（macOS なら Hiragino）へフォールバックし、Chromium が
#   それを **Type 3 フォント**として PDF へ埋め込む。Type 3 は技術書典等の入稿で不可。
#
#   全章ビルドの実測（2026-08-07）では、`techbook: true` でも残っていた Type 3 の
#   全件がこの経路だった（showcase 14 件・mermaid 18 件）。
#
# なぜサブセットなのか:
#   和文フォントは 2〜4MB あり、丸ごと data: URI にすると SVG 1 枚が数 MB 太る。
#   図中に出る字だけに絞れば 8 文字で 3.3KB 程度に収まり、実質太らない。
#   サブセット化は ttfunk（Prawn 経由で既に入っている MIT ライブラリ）で行う。
#
# 使い分け:
#   - mermaid: SVG が書体名を名指ししているので、**同名**の @font-face を注げば解決する
#   - showcase: font-family が汎用名（sans-serif）なので、専用ファミリ名を別途与える
#
# 詳細と実測は `type3-font-embedding-notes.md`。
# ================================================================

require 'ttfunk'
require 'ttfunk/subset'
require_relative '../common'

module VivlioStarter
  module CLI
    module PreProcessCommands
      # 生成 SVG へサブセットフォントを埋め込むユーティリティ
      module SvgFontEmbedder
        module_function

        # SVG の <text> に現れる字を重複なく集める。
        # @param svg [String] SVG 全文
        # @return [Array<String>] 空白を除いた 1 文字の配列
        def characters_in(svg)
          svg.to_s.scan(%r{<text[^>]*>(.*?)</text>}m)
             .flatten.join.gsub(/<[^>]+>/, '')
             .then { unescape(it) }
             .chars.uniq.reject { it.match?(/\s/) }
        end

        # 指定した字だけを含む @font-face の <style> を組み立てる。
        # @param chars [Array<String>] 埋め込む字
        # @param family [String] CSS 上で名乗るファミリ名
        # @param font_path [String, nil] TTF の実体（省略時は書籍の見出し書体を解決）
        # @return [String, nil] <style> 要素。埋め込めないときは nil（呼び出し側は従来動作へ）
        def font_face_style(chars, family:, font_path: nil)
          return nil if chars.empty?

          data = subset(chars, font_path || heading_font_path)
          return nil unless data

          %(<style>@font-face{font-family:"#{family}";) +
            %(src:url("data:font/ttf;base64,#{[data].pack('m0')}") format("truetype");}</style>)
        end

        # SVG のルート直下へ <style> を差し込む。
        # @return [String] 差し込み済みの SVG（style が nil ならそのまま返す）
        def inject(svg, style)
          return svg if style.nil? || style.empty?

          svg.sub(/(<svg[^>]*>)/) { "#{::Regexp.last_match(1)}#{style}" }
        end

        # 書籍の見出し書体（Bold）の実体。ディレクトリ名の規則は FontManager.slug_for と同じ。
        # @return [String, nil]
        def heading_font_path
          family = configured_heading_font
          dir = File.join(Common.stylesheets_dir, 'fonts', family.gsub(/[^A-Za-z0-9]+/, '_'))
          Dir.glob(File.join(dir, '*Bold.ttf')).first || Dir.glob(File.join(dir, '*.ttf')).min
        end

        # book.yml の見出し書体名（未設定・プロジェクト外では同梱既定）。
        def configured_heading_font
          name = Common.configured? ? Common::CONFIG.typography.heading.font.to_s.strip : ''
          name.empty? ? DEFAULT_FONT : name
        end

        DEFAULT_FONT = 'Zen Kaku Gothic New'

        # 指定の字だけを含む TTF を作る。フォントが読めない場合は nil。
        def subset(chars, path)
          return nil unless path && File.file?(path)

          subset = TTFunk::Subset.for(TTFunk::File.open(path), :unicode)
          chars.each { subset.use(it.ord) }
          subset.encode
        rescue StandardError => e
          Common.log_debug("[svg-font] サブセットを作れませんでした: #{path} (#{e.message})")
          nil
        end

        # SVG のテキストノードに現れる実体参照を戻す（サブセットの対象文字を取り違えないため）。
        def unescape(text)
          text.gsub('&lt;', '<').gsub('&gt;', '>').gsub('&quot;', '"')
              .gsub('&#39;', "'").gsub('&amp;', '&')
        end
      end
    end
  end
end
