# frozen_string_literal: true

require 'fileutils'

require_relative 'emoji_replacer'
require_relative 'variable_font_injector'
require_relative '../common'
require_relative '../resize'

module VivlioStarter
  module CLI
    module Techbook
      class Processor
        # @param config [Data] book.yml の設定オブジェクト（Common::CONFIG の再帰的 Data ラッパー）
        def initialize(config)
          @config = config
          @techbook = config.dig(:output, :pdf, :techbook) == true
        end

        def enabled? = @techbook

        # HTML 中の絵文字を Twemoji SVG に差し替え、Type 3 フォント化する文字を置換する
        # @param html [String] 変換対象の HTML
        # @return [String] 処理済み HTML（無効時はそのまま返す）
        def process(html)
          return html unless enabled?

          # --- Phase: 全角チルダ → 波ダッシュ正規化 ---
          # 同梱 Zen フォント（Old Mincho / Kaku Gothic New）は U+301C（波ダッシュ）を
          # 収録するが U+FF5E（全角チルダ）を収録しない。全角チルダはキーボードから
          # 入力しやすく原稿に混入するため、Zen が描画できる U+301C へ正規化する。
          # （さもないと Chromium が OS フォントへフォールバックし、Chrome 149 が
          #   それを Type 3 フォントとして埋め込む。字形は同一。）
          html = html.gsub("\uFF5E", "\u301C")

          # --- Phase: 囲み数字 → ラスタ画像化 ---
          # ①〜⑳ は環境によって Chromium が Type 3 フォント化しやすいため、
          # 事前生成した WebP 画像に置換する。
          html = replace_circled_numbers(html)

          # --- Phase: 絵文字 SVG 差し替え ---
          EmojiReplacer.new.process(html)
        end

        # Techbook 用 CSS（絵文字スタイル + 可変フォント静的インスタンス）を返す
        # @return [String] CSS 文字列（無効時は空文字列）
        def inject_css
          return "" unless enabled?

          css_parts = []
          css_parts << emoji_css
          font_css = VariableFontInjector.new(variable_font_configs).css
          css_parts << font_css unless font_css.empty?
          css_parts.join("\n")
        end

        # 生成済み HTML に対して Techbook 後処理を適用する。
        # Step 5c と Step 9 後の両方から呼ばれるため、CSS 注入は既存ブロックを置換して冪等にする。
        # @param html_files [Array<String>, nil] 対象 HTML（nil 時はワークスペース html/ の全 HTML）
        # @param inject_css [Boolean] CSS 注入も実施するか
        def post_process_html_files!(html_files = nil, inject_css: true)
          return unless enabled?

          files = Array(html_files || Dir.glob(File.join(Common::BUILD_HTML_DIR, '*.html')))
                  .select { File.file?(it) }.sort
          return if files.empty?

          ensure_generated_assets!
          rewrite_svg_references!(files)
          normalize_heading_marker_spans!(files)
          normalize_circled_number_spans!(files)
          replace_emoji_and_type3_prone_chars!(files)
          inject_css_into_files!(files) if inject_css
        end

        private

        TECHBOOK_CSS_BEGIN = '<!-- Vivlio Starter Techbook CSS BEGIN -->'
        TECHBOOK_CSS_END = '<!-- Vivlio Starter Techbook CSS END -->'
        TECHBOOK_CSS_BLOCK_REGEX = /\n?<!-- Vivlio Starter Techbook CSS BEGIN -->.*?<!-- Vivlio Starter Techbook CSS END -->\n?/m
        CIRCLED_NUMBER_TEXT = {
          "\u24EA" => '0',
          "\u2460" => '1', "\u2461" => '2', "\u2462" => '3', "\u2463" => '4', "\u2464" => '5',
          "\u2465" => '6', "\u2466" => '7', "\u2467" => '8', "\u2468" => '9', "\u2469" => '10',
          "\u246A" => '11', "\u246B" => '12', "\u246C" => '13', "\u246D" => '14', "\u246E" => '15',
          "\u246F" => '16', "\u2470" => '17', "\u2471" => '18', "\u2472" => '19', "\u2473" => '20'
        }.freeze
        CIRCLED_NUMBER_REGEX = Regexp.union(CIRCLED_NUMBER_TEXT.keys)
        GENERATED_ASSET_DIR = File.join('stylesheets', 'twemoji', 'vs-techbook')
        THEME_COLOR_HEX = {
          'yellow' => '#f0a000', 'orange' => '#ea580c', 'red' => '#dc2626',
          'magenta' => '#e11d48', 'purple' => '#7c3aed', 'indigo' => '#4f46e5',
          'navy' => '#1e40af', 'blue' => '#0ea5e9', 'cyan' => '#06b6d4',
          'teal' => '#0d9488', 'green' => '#16a34a', 'lime' => '#65a30d'
        }.freeze

        def replace_circled_numbers(html)
          replace_text_segments(html) do |text|
            text.gsub(CIRCLED_NUMBER_REGEX) do |char|
              number = CIRCLED_NUMBER_TEXT.fetch(char)
              # src はワークスペース内 HTML からの相対（asset_prefix 前置・P4 §3.3）
              src = "#{Common.asset_prefix}#{File.join(GENERATED_ASSET_DIR, "circled-#{number}.webp")}"
              %(<img src="#{src}" alt="#{number}" aria-label="#{number}" class="emoji vs-emoji vs-circled-number" style="width: 1em; height: 1em; vertical-align: -0.12em;">)
            end
          end
        end

        def replace_text_segments(html)
          in_ignored_element = nil

          html.split(/(<[^>]+>)/).map do |part|
            if part.start_with?('<')
              in_ignored_element = update_ignored_element_state(part, in_ignored_element)
              part
            elsif in_ignored_element
              part
            else
              yield part
            end
          end.join
        end

        def update_ignored_element_state(tag, current)
          normalized = tag.downcase
          return nil if current && normalized.match?(%r{\A</\s*#{Regexp.escape(current)}\s*>})
          return current if current

          matched = normalized.match(%r{\A<\s*(script|style|svg)\b})
          matched ? matched[1] : nil
        end

        def ensure_generated_assets!
          FileUtils.mkdir_p(GENERATED_ASSET_DIR)
          accent = theme_color_hex

          h3_char = @config.dig(:theme, :markers, :h3).to_s.strip
          h3_char = '♣' if h3_char.empty?
          h3_codepoint = marker_codepoint(h3_char)

          h4_char = @config.dig(:theme, :markers, :h4).to_s.strip
          h4_char = '♦' if h4_char.empty?
          h4_codepoint = marker_codepoint(h4_char)

          write_file_if_changed(File.join(GENERATED_ASSET_DIR, 'marker-h3.svg'), recolored_twemoji_svg(h3_codepoint, h3_char, accent))
          write_file_if_changed(File.join(GENERATED_ASSET_DIR, 'marker-h4.svg'), recolored_twemoji_svg(h4_codepoint, h4_char, accent))
          write_file_if_changed(File.join(GENERATED_ASSET_DIR, 'wave.svg'), wave_svg)

          CIRCLED_NUMBER_TEXT.values.uniq.each do |number|
            write_file_if_changed(File.join(GENERATED_ASSET_DIR, "circled-#{number}.svg"), circled_number_svg(number))
          end

          ResizeCommands.convert_svg_to_webp([GENERATED_ASSET_DIR])
        rescue StandardError => e
          Common.log_warn("[Techbook] 画像化アセットの生成に失敗しました: #{e.message}")
        end

        def theme_color_hex
          raw = @config.dig(:theme, :color).to_s.strip.downcase
          return '#f0a000' if raw.empty?
          return raw if raw.match?(/\A#(?:[0-9a-f]{3}|[0-9a-f]{6}|[0-9a-f]{8})\z/i)
          return "##{raw}" if raw.match?(/\A(?:[0-9a-f]{3}|[0-9a-f]{6}|[0-9a-f]{8})\z/i)
          return "##{raw.delete_prefix('0x')}" if raw.match?(/\A0x(?:[0-9a-f]{6}|[0-9a-f]{8})\z/i)

          THEME_COLOR_HEX.fetch(raw, '#f0a000')
        end

        def marker_codepoint(char)
          char.codepoints
              .reject { it == 0xFE0F }
              .map { it.to_s(16).downcase }
              .join("-")
        end

        def recolored_twemoji_svg(codepoint, char, color)
          svg_path = File.join('stylesheets', 'twemoji', "#{codepoint}.svg")
          if File.exist?(svg_path)
            svg = File.read(svg_path, encoding: 'utf-8')
            # Suit symbols (♣, ♦, ♥, ♠) are recolored with the theme accent color.
            # Other natively colored emojis (like 🌸) retain their original colors.
            if ["♣", "♦", "♥", "♠"].include?(char.to_s.strip)
              svg.gsub(/fill="#[0-9a-fA-F]{3,8}"/, %(fill="#{color}"))
            else
              svg
            end
          else
            fallback_marker_svg(char, color)
          end
        end

        def fallback_marker_svg(char, color)
          case char.to_s.strip
          when "■", "◼", "square", "rectangle"
            %(<?xml version="1.0" encoding="UTF-8"?><svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 36 36"><rect x="2" y="2" width="32" height="32" rx="2" ry="2" fill="#{color}"/></svg>)
          when "◆", "◇", "diamond"
            %(<?xml version="1.0" encoding="UTF-8"?><svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 36 36"><path d="M18 2 L34 18 L18 34 L2 18 Z" fill="#{color}"/></svg>)
          when "▲", "triangle"
            %(<?xml version="1.0" encoding="UTF-8"?><svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 36 36"><path d="M18 2 L34 32 L2 32 Z" fill="#{color}"/></svg>)
          when "▼"
            %(<?xml version="1.0" encoding="UTF-8"?><svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 36 36"><path d="M18 34 L2 4 L34 4 Z" fill="#{color}"/></svg>)
          when "★", "☆", "star"
            %(<?xml version="1.0" encoding="UTF-8"?><svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 36 36"><path d="M18 2 L22 13 L34 13 L24 20 L28 32 L18 24 L8 32 L12 20 L2 13 L14 13 Z" fill="#{color}"/></svg>)
          when "●", "○", "circle"
            %(<?xml version="1.0" encoding="UTF-8"?><svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 36 36"><circle cx="18" cy="18" r="16" fill="#{color}"/></svg>)
          else
            %(<?xml version="1.0" encoding="UTF-8"?><svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 36 36"><circle cx="18" cy="18" r="16" fill="#{color}"/></svg>)
          end
        end

        def wave_svg
          <<~SVG
            <?xml version="1.0" encoding="UTF-8"?>
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 128 128" width="128" height="128">
              <path d="M12 78 C30 36, 48 36, 64 64 S98 92, 116 50" fill="none" stroke="#000000" stroke-width="10" stroke-linecap="round"/>
            </svg>
          SVG
        end

        def circled_number_svg(number)
          font_size = number.to_s.length >= 2 ? 50 : 64
          <<~SVG
            <?xml version="1.0" encoding="UTF-8"?>
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 128 128" width="128" height="128">
              <circle cx="64" cy="64" r="57" fill="none" stroke="#000000" stroke-width="8"/>
              <text x="64" y="67" text-anchor="middle" dominant-baseline="central"
                    font-family="Arial, Helvetica, sans-serif" font-size="#{font_size}" font-weight="700" fill="#000000">#{number}</text>
            </svg>
          SVG
        end

        def write_file_if_changed(path, content)
          return if File.exist?(path) && File.read(path, encoding: 'utf-8') == content

          File.write(path, content, encoding: 'utf-8')
        end

        def normalize_circled_number_spans!(html_files)
          html_files.each do |html_file|
            content = File.read(html_file, encoding: 'utf-8')
            normalized = content.gsub(%r{<span\b[^>]*\bclass="[^"]*\bvs-circled-number\b[^"]*"[^>]*\baria-label="(\d{1,2})"[^>]*>\s*\d{1,2}\s*</span>}i) do
              number = Regexp.last_match(1)
              src = "#{Common.asset_prefix}#{File.join(GENERATED_ASSET_DIR, "circled-#{number}.webp")}"
              %(<img src="#{src}" alt="#{number}" aria-label="#{number}" class="emoji vs-emoji vs-circled-number" style="width: 1em; height: 1em; vertical-align: -0.12em;">)
            end
            next if content == normalized

            File.write(html_file, normalized, encoding: 'utf-8')
            Common.log_info("[Techbook] 囲み数字を画像参照に正規化しました: #{html_file}")
          end
        end

        def rewrite_svg_references!(html_files)
          html_files.each do |html_file|
            content = File.read(html_file, encoding: 'utf-8')
            rewritten = content.gsub(/(<img\s[^>]*src=")([^"]*\.svg)(")/i) do
              prefix, svg_src, suffix = Regexp.last_match.captures
              webp_src = svg_src.sub(/\.svg\z/i, '.webp')
              # 存在確認は src を HTML ファイル自身の位置基準で解決する（P4b §2.4）。
              # asset_prefix 付き（ルート資産）・dir 相対（数式など workspace 生成物）の
              # 両参照形を 1 つの規則で正しく扱える。
              webp_on_disk = File.expand_path(webp_src, File.dirname(html_file))
              File.exist?(webp_on_disk) ? "#{prefix}#{webp_src}#{suffix}" : "#{prefix}#{svg_src}#{suffix}"
            end
            next if content == rewritten

            File.write(html_file, rewritten, encoding: 'utf-8')
            Common.log_info("[Techbook] SVG→WebP 参照を書き換えました: #{html_file}")
          end
        end

        def normalize_heading_marker_spans!(html_files)
          html_files.each do |html_file|
            content = File.read(html_file, encoding: 'utf-8')
            normalized = content.gsub(/<span\b([^>]*\bclass="[^"]*\bsubsection-marker\b[^"]*"[^>]*)>.*?<\/span>/mi) do
              attrs = Regexp.last_match(1).to_s
              attrs = attrs.gsub(/\s+aria-hidden="[^"]*"/i, '')
              attrs = attrs.gsub(/\s+role="[^"]*"/i, '')
              %(<span#{attrs} aria-hidden="true" role="presentation"></span>)
            end
            next if content == normalized

            File.write(html_file, normalized, encoding: 'utf-8')
            Common.log_info("[Techbook] h3 マーカーをCSS描画に正規化しました: #{html_file}")
          end
        end

        def replace_emoji_and_type3_prone_chars!(html_files)
          Common.log_info('[Techbook] 絵文字 SVG 差し替えを実行します')

          html_files.each do |html_file|
            content = File.read(html_file, encoding: 'utf-8')
            processed = process(content)
            next if content == processed

            File.write(html_file, processed, encoding: 'utf-8')
            Common.log_info("[Techbook] 絵文字を差し替えました: #{html_file}")
          end
        end

        def inject_css_into_files!(html_files)
          css = inject_css
          return if css.empty?

          html_files.each do |html_file|
            content = File.read(html_file, encoding: 'utf-8')
            styled = inject_css_into_html(content, css)
            next if content == styled

            File.write(html_file, styled, encoding: 'utf-8')
          end
          Common.log_info('[Techbook] CSS を注入しました')
        end

        def inject_css_into_html(html, css)
          css_block = "#{TECHBOOK_CSS_BEGIN}\n<style>\n#{css}\n</style>\n#{TECHBOOK_CSS_END}"
          cleaned = html.gsub(TECHBOOK_CSS_BLOCK_REGEX, "")
          return cleaned unless cleaned.include?('</head>')

          cleaned.sub('</head>', "\n#{css_block}\n</head>")
        end

        def emoji_css
          # インライン <style> の url() は HTML ファイル基準で解決されるため、
          # ワークスペース内 HTML からの相対（asset_prefix 前置）で書く（P4 §3.3）
          p = Common.asset_prefix
          <<~CSS
            /* Vivlio Starter: techbook emoji style */
            img.vs-emoji {
              display: inline;
              width: 1em;
              height: 1em;
              vertical-align: -0.15em;
              border: none !important;
              box-shadow: none;
              background: transparent;
              padding: 0;
              margin: 0;
            }

            /* Techbook: CSS 擬似要素のマーカー記号を画像化
               記号を CSS 文字列として描画すると Chromium が Type 3
               フォントとして埋め込むため、Twemoji WebP の url() に置き換える。 */
            :root {
              --h3-marker: url("#{p}stylesheets/twemoji/vs-techbook/marker-h3.webp") !important;
              --h4-marker: url("#{p}stylesheets/twemoji/vs-techbook/marker-h4.webp") !important;
              --subtitle-wave-image: url("#{p}stylesheets/twemoji/vs-techbook/wave.webp") !important;
            }

            .subsection-marker,
            h4::before {
              display: inline-block;
              inline-size: 1em;
              block-size: 1em;
              margin-inline-end: 1mm;
              vertical-align: -0.15em;
              background-repeat: no-repeat;
              background-position: center;
              background-size: contain;
            }

            .subsection-marker {
              background-image: var(--h3-marker) !important;
            }

            h4::before {
              content: "" !important;
              background-image: var(--h4-marker) !important;
            }

            /* Techbook: CSS文字列の波線装飾は Type 3 化しやすいため画像化する。 */
            .subtitle--wave {
              --subtitle-prefix: "" !important;
              --subtitle-suffix: "" !important;
            }

            .subtitle--wave::before,
            .subtitle--wave::after {
              content: "" !important;
              display: inline-block;
              inline-size: 0.9em;
              block-size: 0.9em;
              margin-inline: 0.12em;
              vertical-align: -0.12em;
              background-image: var(--subtitle-wave-image);
              background-repeat: no-repeat;
              background-position: center;
              background-size: contain;
            }

            /* Type 3 フォント対策: コードを必ず --font-code で組み、text-shadow を消す。 */
            code,
            pre,
            code[class*="language-"],
            pre[class*="language-"] {
              font-family: var(--font-code), monospace !important;
              text-shadow: none !important;
            }
          CSS
        end

        def variable_font_configs
          Array(@config.dig(:output, :pdf, :variable_fonts))
        end
      end
    end
  end
end
