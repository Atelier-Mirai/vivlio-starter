# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/pre_process/mermaid_transformer.rb
# ================================================================
# 責務:
#   ```mermaid フェンスブロックを前処理で消費し、mmdc で描いた図への
#   <figure class="vs-mermaid"><img> 参照へ置換する（mermaid-diagram-spec.md §4.1）。
#   生成物の後段処理（PDF=ベクタ SVG / EPUB・Kindle=対のラスター）は図解注釈
#   （showcase）と同型で、EpubBuilder が data-vs-raster の PNG へ差し替える。
#
# なぜコード保護の前段で横取りするのか（§0・§4.2）:
#   ```mermaid は言語付きフェンスなので、通常のコード保護に任せると Prism へ流れ、
#   図の代わりに「行番号付きソース」が本文に載る（prism_lines が全 <pre> に行番号を
#   付けるため）。よってコード化される前にブロックを図へ置換する。
#
# フェンス解釈は Masking に委ねる（P1「唯一の実装」）:
#   ブロックの抽出は Masking.replace_top_level_fences が担う。記法解説フェンス
#   （````markdown の中の ```mermaid の作例）は外側フェンスの本文として素通りし、
#   トップレベルの ```mermaid だけが yield される（§2.1）。
#
# 生成物のキャッシュは GeneratedAssetCache に委ねる:
#   mmdc は Chromium を起動し 1 図 ≈0.9s と重いため、生成物は .cache/vs/mermaid/ に
#   永続キャッシュされ、図ソースが変わらない限りクリーンビルドを跨いで再描画しない。
#
# 縮退（§6）:
#   mmdc 不在時・生成失敗時は当該ブロックを ```mermaid のまま残す（＝コードブロック
#   として表示され、ビルドは止まらない）。失敗は出現位置つきで著者に警告する
#   （[[warning-messages-actionable]]）。
# ================================================================

require 'digest'
require 'fileutils'
require_relative '../common'
require_relative '../masking'
require_relative 'generated_asset_cache'
require_relative 'mermaid_renderer'

module VivlioStarter
  module CLI
    module PreProcessCommands
      # ```mermaid ブロックを図（figure）へ変換するモジュール。
      module MermaidTransformer
        module_function

        # 生成物の出力先（images/ 配下）と永続キャッシュの種別名。
        REL_BASE = 'mermaid'

        # ```mermaid / ~~~mermaid 開始行の存在を安価に判定する前置きフィルタ
        # （大半の章はこれで即 return し、行走査すら行わない）。
        OPENER_HINT = /^[ \t]*(?:`{3,}|~{3,})[ \t]*mermaid[ \t]*$/i

        # mmdc の描画が利用可能か（既定レンダラ経由）。
        def available?(renderer: default_renderer)
          renderer.available?
        end

        # 本文中のトップレベル ```mermaid ブロックをすべて <figure> へ置換する。
        #
        # @param content [String] 処理対象の Markdown 本文
        # @param chapter_slug [String] 生成物の出力先章ディレクトリ名（例: "10-intro"）
        # @param source_filename [String] 警告に出す原稿ファイル名
        # @param renderer [#available?, #render, #version] mmdc レンダラ（テスト差し替え用）
        # @return [String] 置換後の本文
        def transform(content, chapter_slug:, source_filename:, renderer: default_renderer)
          return content unless content.match?(OPENER_HINT)

          warned = false
          Masking.replace_top_level_fences(content) do |block, lineno|
            next nil unless mermaid_block?(block)

            unless renderer.available?
              warn_renderer_missing(source_filename) unless warned
              warned = true
              next nil
            end

            render_block(block_source(block), lineno, chapter_slug:, source_filename:, renderer:)
          end
        end

        # ブロック 1 つを figure へ変換する。生成できないときは nil（原文フェンス温存）。
        def render_block(source, lineno, chapter_slug:, source_filename:, renderer:)
          font_family = configured_font_family
          key = cache_key(source, font_family, renderer)
          out_dir = File.join(Common::BUILD_HTML_DIR, 'images', REL_BASE, chapter_slug)

          ok = GeneratedAssetCache.fetch(REL_BASE, ["#{key}.svg", "#{key}.png"], out_dir:) do |cache_dir|
            generate_pair!(source, font_family, renderer, cache_dir, key)
          end
          unless ok
            warn_render_failed(source_filename, lineno)
            return nil
          end

          rel_dir = "images/#{REL_BASE}/#{chapter_slug}"
          figure("#{rel_dir}/#{key}.svg", "#{rel_dir}/#{key}.png", alt_text(source))
        end

        # SVG（PDF 用）とラスター PNG（EPUB/Kindle 用）を対でキャッシュへ描き出す。
        def generate_pair!(source, font_family, renderer, cache_dir, key)
          svg = renderer.render(source, format: :svg, font_family:)
          png = renderer.render(source, format: :png, font_family:)
          return false unless svg && png

          File.write(File.join(cache_dir, "#{key}.svg"), svg, encoding: 'utf-8')
          File.binwrite(File.join(cache_dir, "#{key}.png"), png)
          true
        end

        # --- ブロック判定・切り出し ---

        # 開始フェンス行の情報文字列が mermaid か（```mermaid / ~~~ mermaid、大小無視）。
        def mermaid_block?(block)
          first = block.lines.first.to_s.lstrip
          marker = first[/\A(?:`{3,}|~{3,})/]
          return false unless marker

          first.delete_prefix(marker).strip.casecmp?('mermaid')
        end

        # フェンスブロックから図ソース（開始行・終了行を除く中身）を取り出す。
        def block_source(block) = block.lines[1..-2].to_a.join

        # --- 生成物のパスとキー ---

        # 図ソース＋フォント＋テーマ＋mermaid バージョンのハッシュをキーにする（§4.1-2）。
        # 図ソースを書き換えれば（＝内容が変われば）別キーになり再生成される。
        def cache_key(source, font_family, renderer)
          version = renderer.respond_to?(:version) ? renderer.version.to_s : ''
          # v2: mmdc 設定を htmlLabels:false へ変更（foreignObject→native text）した際に
          # 旧キャッシュを無効化するためスキーマ版を上げた。
          payload = ['v2', Digest::SHA256.hexdigest(source), font_family.to_s,
                     MermaidRenderer::DEFAULT_THEME, version].join('|')
          Digest::SHA256.hexdigest(payload)[0, 16]
        end

        # 図中テキストの font-family（§5.1・案 1）。本書の見出しフォントを先頭に、
        # リーダー標準の和文 sans フォールバックを併記する（epub_heading_font_family と同型）。
        # 設定未ロード（プロジェクト外・単体テスト）では nil（mmdc 既定フォント）。
        def configured_font_family
          return nil unless Common.configured?

          book = Common::CONFIG.typography.heading.font.to_s.strip
          stack = []
          stack << "'#{book}'" unless book.empty?
          stack.concat(["'Hiragino Sans'", "'Hiragino Kaku Gothic ProN'", "'Noto Sans JP'",
                        "'Noto Sans CJK JP'", 'sans-serif'])
          stack.join(', ')
        rescue StandardError
          nil
        end

        # --- 出力 HTML ---

        # 置換後の HTML。前後に空行を補い独立段落として組ませる。ラスター参照は
        # data-vs-raster に明示し、EpubBuilder が EPUB/Kindle で src を PNG へ差し替える。
        def figure(svg_rel, raster_rel, alt)
          "\n\n<figure class=\"vs-mermaid\">\n" \
            "<img class=\"vs-mermaid\" src=\"#{svg_rel}\" data-vs-raster=\"#{raster_rel}\" " \
            "alt=\"#{escape_attr(alt)}\">\n" \
            "</figure>\n\n"
        end

        # alt テキスト（図ソースの最初の意味ある行＝種別/宣言行）。
        def alt_text(source)
          line = source.each_line.map(&:strip).find { |l| !l.empty? && !l.start_with?('%%') }
          (line || 'mermaid diagram').gsub(/\s+/, ' ')[0, 120]
        end

        def escape_attr(str)
          str.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;').gsub('"', '&quot;')
        end

        # --- 警告（出現位置つき・修正案つき） ---

        def warn_renderer_missing(source_filename)
          Common.log_warn(
            "[mermaid] #{source_filename}: mmdc が無いため ```mermaid を図にできません（コードブロックのまま出力します）",
            detail: '→ `vs doctor --fix` で導入できます（npm install -g @mermaid-js/mermaid-cli）'
          )
        end

        def warn_render_failed(source_filename, lineno)
          Common.log_warn(
            "[mermaid] #{source_filename}:#{lineno} - mermaid の図を生成できませんでした（当該ブロックはコードのまま残します）",
            detail: '→ 図ソースの構文を確認してください（例: `graph LR` の行から始める）'
          )
        end

        # 既定のレンダラ（mmdc）。プロセス内で 1 つを共有する。
        def default_renderer = (@default_renderer ||= MermaidRenderer.new)
      end
    end
  end
end
