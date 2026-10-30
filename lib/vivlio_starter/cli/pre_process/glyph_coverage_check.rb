# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/pre_process/glyph_coverage_check.rb
# ================================================================
# 責務:
#   本の書体に無い字を、組む前に見つける（改善案 #124 の前倒し）。PDF の Type 3 の確かめ
#   （Type3FontCheck）は全章の build でしか走らないので、preflight と単章の build でも、
#   原稿の行を添えて同じ字を知らせる。Type3FontCheck は、ここで知らせた字を重ねて言わない。
#
# 字が書体に無いと何が起きるか:
#   Chromium は字を書体の並び（font-family）の順に探し、どれにも無ければ OS の書体で描く。
#   その書体が Type 3 で埋め込まれる。どの書体の並びで探すかは、字の置き場所で違う:
#   - 本文・見出し: 本文（見出し）の書体 → HackGen（page-settings.css の --font-body・--font-header）
#     → DejaVu Sans Mono → DejaVu Sans（book-settings.css が HackGen と同じ書体名の面として足す・改善案 #127）
#   - コード: コードの書体だけ（--font-code の次は monospace = OS の書体）。HackGen なら DejaVu も
#   - 数式の画像: SVG に埋めた本文の書体だけ（MathTransformer#embed_text_font）
#   - 図の SVG: SVG に埋めた書体だけ（DerivedSvg が、図の名指しする書体と見出しの書体を埋め、
#     それらに無い字は予備の書体 SvgFontEmbedder::FALLBACK_FONTS で補う・改善案 #127）
#   spiral-ruby では、本文の ≒ は HackGen で組めていて、図の中の ≒・ⁿ・✊、コードの中の ⌃・ₙ が
#   Type 3 になっていた。OS の書体が TrueType なら Type 3 にはならない（コードの ⟹ など）が、組む PC で
#   書体も字形も変わるので、本の書体に無い字はすべて知らせる。
#
# 本の書体にない漢字（外字）は、その字を持つ書体から取った字の形の図形にして PDF に組む
# （Build::Gaiji・改善案 #127 段階 4）ので、形を取れる字は数えない（本文・見出し・コード）。
#
# 絵文字・囲み数字・全角のチルダは、techbook（既定）なら PDF を組む前に画像や別の字へ置き換える
# （Techbook::Processor）ので数えない。図の SVG の中は、中身が絵文字だけの字を twemoji の図形に
# 差し替える（Build::FigureEmoji）ので数えず、文字と混ざった絵文字だけを数える。
# ================================================================

require 'cgi'
require 'set'
require_relative '../masking'
require_relative 'svg_font_embedder'
require_relative '../build/font_metrics'
require_relative '../build/derived_svg'
require_relative '../build/figure_emoji'
require_relative '../build/gaiji'

module VivlioStarter
  module CLI
    module PreProcessCommands
      module GlyphCoverageCheck
        # 字ごとの直し方。上から順に見て、最初に当たったものを使う（Type3FontCheck と共用）
        ADVICE = [
          [/≒/, '≈ に置き換える'],
          [/[ᴬ-ᵪ⁰-₟]/, '本文は $x^n$・$H_n$ の数式に、図（SVG）は <tspan baseline-shift="super"> で上付き・下付きに'],
          [/[∛∜]/, '本文は $\sqrt[3]{x}$ の数式に、図（SVG）は ³√ のように'],
          [/[⌃⌥⌘⇧]/, 'Control・Option・Command・Shift のように言葉で書く'],
          [/\p{Extended_Pictographic}/, '言葉か画像に置き換える'],
          [/\p{Han}/, 'この字を持つ書体（思源宋体・Noto Serif CJK など）を PC に入れると、字の形を取って組みます'],
          [/[\u{1D400}-\u{1D7FF}]/, 'この字を持つ書体（STIX Two Math など）を PC に入れると、字の形を取って組みます']
        ].freeze
        DEFAULT_ADVICE = '本の書体にある字に置き換える'

        # 見つけた字。line は原稿の行（引けなければ nil）、where は字のある所（「コード」「図 x.svg」など）
        Finding = Data.define(:line, :chars, :where)

        # 予備の書体（SvgFontEmbedder::FALLBACK_FONTS）。絵文字は補わない
        Fallback = Data.define(:metrics) do
          def glyph?(char) = !char.match?(SvgFontEmbedder::FALLBACK_EXCLUDED) && metrics.glyph?(char)
        end

        # 書体に関わらない字（空白・制御文字・結合文字・異体字セレクタ）
        IGNORED = /[[:space:]\p{Cc}\p{Cf}\p{M}\u{FE00}-\u{FE0F}\u{E0100}-\u{E01EF}]/
        # techbook が PDF を組む前に置き換える字（Techbook::Processor）
        TECHBOOK_REPLACED = /\p{Extended_Pictographic}|[①-⑳～]/

        MATH_IMAGE = %r{<img\b[^>]*\bsrc="([^"]*images/math/[^"]+\.svg)"}
        FIGURE_IMAGE = /<img\b[^>]*\bsrc="([^"]+\.svg)"|!\[[^\]]*\]\(([^)\s]+\.svg)[^)]*\)/

        module_function

        def advice_for(char) = ADVICE.find { |pattern, _| char.match?(pattern) }&.last || DEFAULT_ADVICE

        # --- 知らせた字（Type3FontCheck が重ねて言わないため） ---

        def reported = @reported_mutex.synchronize { @reported.dup }

        def remember(chars) = @reported_mutex.synchronize { @reported.merge(chars) }

        def reset! = @reported_mutex.synchronize { @reported.clear }

        @reported = Set[]
        @reported_mutex = Mutex.new

        # --- 調べる ---

        # 前処理を終えた原稿の中で、本の書体に無い字を探す。
        #
        # @param content [String] 前処理を終えた原稿（数式は <img> になっている）
        # @param source [String] 元の原稿（行番号を引く）
        # @return [Array<Finding>]
        def scan(content, source:)
          chains = font_chains
          return [] unless chains

          findings = []
          each_text_run(content) do |kind, text, processed_line|
            # 本の書体にない漢字は、PDF では字の形の図形にして組む（Build::Gaiji・改善案 #127 段階 4）
            missing = missing_chars(text, chains[kind], replaced: true).reject { Build::Gaiji.available?(it, kind) }
            next if missing.empty?

            findings << Finding.new(line: source_line(source, processed_line, missing.first),
                                    chars: missing, where: kind == :code ? 'コード' : nil)
          end
          findings.concat(image_findings(content, source, chains))
          merge_by_line(findings)
        end

        # 本文・見出し・コードの字を、置き場所ごとに渡す
        # @yieldparam kind [Symbol] :body・:heading・:code
        def each_text_run(content)
          prose = {}
          Masking.each_prose_line(content) { |line, lineno| prose[lineno] = line }
          in_svg = false
          content.each_line.with_index(1) do |line, lineno|
            # 原稿に直に書いた <svg> は、自分で書体を抱えている（showcase・mermaid）
            in_svg = true if line.include?('<svg')
            if in_svg
              in_svg = false if line.include?('</svg>')
              next
            end

            unless prose.key?(lineno)
              yield :code, line, line unless line.match?(/\A\s*(?:`{3,}|~{3,})/)
              next
            end

            codes = []
            text = line.gsub(Masking::HTML_INLINE_CODE) do |code|
              codes << code.sub(/\A<code\b[^>]*>/, '').delete_suffix('</code>')
              ''
            end
            text = text.gsub(Masking::INLINE_CODE_SPAN) do |code|
              codes << code.gsub(/\A`+|`+\z/, '')
              ''
            end
            codes.each { yield :code, CGI.unescapeHTML(it), line }
            plain = CGI.unescapeHTML(text.gsub(/<[^>]*>/, ''))
            yield line.match?(/\A\#{1,6}\s/) ? :heading : :body, plain, line
          end
        end

        # 数式の画像と図の SVG の字。画像の中は、埋め込んだ書体だけで描かれる
        def image_findings(content, source, chains)
          math = content.scan(MATH_IMAGE).flatten.uniq.flat_map do |src|
            path = File.join(Common::BUILD_HTML_DIR, src[/images\/math\/.+/])
            missing = File.file?(path) ? missing_chars(svg_text(File.read(path, encoding: 'utf-8')), chains[:math]) : []
            missing.empty? ? [] : [Finding.new(line: source_line(source, nil, missing.first), chars: missing, where: '数式')]
          end
          figures = content.scan(FIGURE_IMAGE).map { it.compact.first }.uniq.reject { it.include?('images/math/') }
          math + figures.filter_map do |src|
            path = figure_path(src) or next
            svg = File.read(path, encoding: 'utf-8')
            next if svg.include?('data:font/') # 生成した SVG は書体を抱えている

            # 絵文字だけの字は、DerivedSvg が twemoji の図形に差し替える（FigureEmoji）
            missing = missing_chars(svg_text(Build::FigureEmoji.replace(svg)), figure_fonts(svg))
            next if missing.empty?

            Finding.new(line: source_line(source, File.basename(path), nil), chars: missing, where: "図 #{File.basename(path)}")
          end
        end

        # 図の SVG のパス。前処理は images/ の手前に ../ を足すので、images/ から後ろで探す
        def figure_path(src)
          tail = src[%r{(?:\A|/)(images/.+)\z}, 1] or return nil
          path = File.join(File.dirname(Common::IMAGES_DIR), tail)
          File.file?(path) ? path : nil
        end

        def svg_text(svg) = CGI.unescapeHTML(svg.scan(%r{<(?:text|tspan)\b[^>]*>([^<]*)}).flatten.join)

        # 書体の並びのどれにも無い字。replaced は techbook が組む前に置き換える字を数えないか
        # （HTML の地の文だけ。数式と図の SVG の中は置き換えない）
        def missing_chars(text, chain, replaced: false)
          return [] if chain.nil? || chain.empty?

          text.each_char.reject { it.match?(IGNORED) || (replaced && techbook? && it.match?(TECHBOOK_REPLACED)) }
              .uniq.reject { |char| chain.any? { it.glyph?(char) } }
        end

        def techbook? = Common::CONFIG.output.pdf.techbook != false

        # 置き場所ごとの書体の並び（FontMetrics）。本文の書体が見つからなければ nil（調べない）
        def font_chains
          @font_chains ||= begin
            embedder = SvgFontEmbedder
            load = ->(name) { (path = embedder.font_path(name, weight: :regular)) && File.file?(path) ? Build::FontMetrics.load(path) : nil }
            body = load.(embedder.configured_body_font)
            # HackGen と、その後ろの予備の書体（book-settings.css が HackGen と同じ書体名の面として足す）
            hackgen = [load.(SvgFontEmbedder::DEFAULT_CODE_FONT),
                       *SvgFontEmbedder::FALLBACK_FONTS.drop(1).filter_map { load.(it) }.map { Fallback.new(it) }].compact
            code_font = embedder.configured_code_font
            code_hackgen = embedder.comparable(code_font) == embedder.comparable(SvgFontEmbedder::DEFAULT_CODE_FONT)
            body && {
              body: [body, *hackgen],
              heading: [load.(embedder.configured_heading_font), *hackgen].compact,
              code: code_hackgen ? hackgen : [load.(code_font)].compact,
              math: [body]
            }
          end
        end

        # 図に埋める書体（DerivedSvg と同じ寄せ方）と、それらに無い字を補う予備の書体
        def figure_fonts(svg)
          _, families = Build::DerivedSvg.resolve_families(svg)
          load = ->(names) { names.flat_map { SvgFontEmbedder.face_paths(it).values }.uniq.select { File.file?(it) }.map { Build::FontMetrics.load(it) } }
          own = load.([*families, Build::DerivedSvg.default_family(svg)].compact.uniq)
          own + load.(SvgFontEmbedder::FALLBACK_FONTS).map { Fallback.new(it) }
        end

        # 原稿の行番号。前処理後の行で字の前後にある字を、元の原稿の行から探す。
        # 図は、参照に書いたファイル名で探す。見つからなければ nil（取り込んだコードの字など）
        def source_line(source, processed_line, char)
          lines = source.lines
          if char.nil?
            index = lines.index { it.include?(processed_line) }
            return index && (index + 1)
          end

          text = processed_line.to_s.gsub(/<[^>]*>/, '')
          at = text.index(char) or return lines.index { it.include?(char) }&.+(1)
          [6, 3, 0].each do |reach|
            snippet = text[[at - reach, 0].max, (reach * 2) + 1]
            index = lines.index { it.include?(snippet) }
            return index + 1 if index
          end
          nil
        end

        # 同じ行・同じ所の字をまとめる
        def merge_by_line(findings)
          findings.group_by { [it.line, it.where] }.map do |(line, where), group|
            Finding.new(line:, chars: group.flat_map(&:chars).uniq, where:)
          end
        end
      end
    end
  end
end
