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
#   付けるため）。よってコード化される前に、行スキャンでブロックを抜き出して図へ置換する。
#
# 記法解説フェンスは温存（§2.1）:
#   拡張記法リファレンスでは ````markdown の中に ```mermaid の**書き方の例**が入る。
#   フェンスの入れ子（外側が長いフェンス）を状態機械で追い、トップレベルの ```mermaid
#   だけを変換対象にする（内側の例示は本文に残す）。Masking.scan_lines と同じ意味論。
#
# 縮退（§6）:
#   mmdc 不在時は本文を変えずブロックを ```mermaid のまま残す（＝コードブロックとして
#   表示され、ビルドは止まらない）。生成失敗時も当該ブロックだけ原文のまま残し、
#   出現位置つきで著者に警告する（[[warning-messages-actionable]]）。
# ================================================================

require 'digest'
require 'fileutils'
require_relative '../common'
require_relative 'mermaid_renderer'

module VivlioStarter
  module CLI
    module PreProcessCommands
      # ```mermaid ブロックを図（figure）へ変換するモジュール。
      module MermaidTransformer
        module_function

        # 生成物の出力先（images/ 配下）。著者画像・数式・showcase とは別系統に置く。
        REL_BASE = 'mermaid'

        # 行頭フェンス（``` または ~~~ を 3 連以上・先頭空白許容）。
        FENCE = /\A[ \t]*(`{3,}|~{3,})/

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
          blocks = scan_blocks(content)
          return content if blocks.empty?

          unless renderer.available?
            warn_renderer_missing(source_filename)
            return content
          end

          rewrite(content, blocks, chapter_slug:, source_filename:, renderer:)
        end

        # 走査で得たブロック（末尾から）を置換していく。末尾から処理するのは、
        # 前方の [start, end) 範囲が後続の置換でずれないようにするため。
        def rewrite(content, blocks, chapter_slug:, source_filename:, renderer:)
          result = content.dup
          blocks.reverse_each do |block|
            replacement = render_block(block, chapter_slug:, source_filename:, renderer:)
            result[block[:range]] = replacement
          end
          result
        end

        # ブロック 1 つを figure へ変換する。生成できないときは原文（raw フェンス）を返す。
        def render_block(block, chapter_slug:, source_filename:, renderer:)
          source = block[:source]
          font_family = configured_font_family
          key = cache_key(source, font_family, renderer)
          out_dir = File.join(Common::BUILD_HTML_DIR, 'images', REL_BASE, chapter_slug)
          return block[:raw] unless write_assets!(source, key, out_dir, font_family, renderer, block, source_filename)

          rel_dir = "images/#{REL_BASE}/#{chapter_slug}"
          figure("#{rel_dir}/#{key}.svg", "#{rel_dir}/#{key}.png", alt_text(source))
        end

        # 未生成なら SVG（PDF 用）とラスター PNG（EPUB/Kindle 用）を対で書き出す。
        # 既に両方あればスキップ（--no-clean で効く）。どちらか描けなければ縮退させる。
        def write_assets!(source, key, out_dir, font_family, renderer, block, source_filename)
          svg_path = File.join(out_dir, "#{key}.svg")
          png_path = File.join(out_dir, "#{key}.png")
          return true if File.exist?(svg_path) && File.exist?(png_path)

          svg = renderer.render(source, format: :svg, font_family:)
          png = renderer.render(source, format: :png, font_family:)
          unless svg && png
            warn_render_failed(source_filename, block[:lineno])
            return false
          end

          FileUtils.mkdir_p(out_dir)
          File.write(svg_path, svg, encoding: 'utf-8')
          File.binwrite(png_path, png)
          true
        end

        # --- 行スキャン（トップレベルの ```mermaid ブロックだけを拾う） ---

        # フェンスの入れ子を状態機械で追い、トップレベルの ```mermaid ブロックを
        # [範囲, 図ソース, 原文, 開始行番号] として返す。内側（記法解説）の ```mermaid は
        # 外側フェンスの本文として素通りするので拾わない。
        # @return [Array<Hash>] { range:, source:, raw:, lineno: } の配列（出現順）
        def scan_blocks(content)
          blocks = []
          fence = nil           # 開いているフェンスのマーカー（nil = コード外）
          collecting = false    # トップレベル mermaid ブロックを収集中か
          start_off = nil       # 収集中ブロックの開始バイトオフセット
          source_lines = nil    # 図ソース行の蓄積
          block_lineno = nil    # 収集中ブロックの開始行番号（ループ前に宣言し反復間で保持）
          lineno = 0
          offset = 0

          content.each_line do |line|
            lineno += 1
            marker = fence_marker(line)

            if fence.nil?
              if marker
                fence = marker
                if mermaid_opener?(line, marker)
                  collecting = true
                  start_off = offset
                  source_lines = []
                  block_lineno = lineno
                end
              end
            elsif marker && closing_fence?(marker, fence)
              if collecting
                raw = content[start_off...(offset + line.length)]
                blocks << { range: start_off...(offset + line.length),
                            source: source_lines.join, raw:, lineno: block_lineno }
                collecting = false
              end
              fence = nil
            elsif collecting
              source_lines << line
            end

            offset += line.length
          end

          blocks
        end

        # 行頭（空白許容）のフェンスマーカー（``` または ~~~ の連なり）を返す。無ければ nil。
        def fence_marker(line)
          m = line.match(FENCE)
          m && m[1]
        end

        # 閉じフェンスとして妥当か（同種・同連長以上）。Masking と同じ規則。
        def closing_fence?(marker, opener) = marker[0] == opener[0] && marker.length >= opener.length

        # 開始フェンス行の情報文字列が mermaid か（```mermaid / ~~~ mermaid、大小無視）。
        def mermaid_opener?(line, marker)
          info = line.lstrip.delete_prefix(marker).strip
          info.casecmp?('mermaid')
        end

        # --- 生成物のパスとキー ---

        # 図ソース＋フォント＋テーマ＋mermaid バージョンのハッシュをキーにする（§4.1-2）。
        # 図ソースを撮り直せば（＝内容が変われば）別キーになり再生成される。
        def cache_key(source, font_family, renderer)
          version = renderer.respond_to?(:version) ? renderer.version.to_s : ''
          payload = ['v1', Digest::SHA256.hexdigest(source), font_family.to_s,
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
