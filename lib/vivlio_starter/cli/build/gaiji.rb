# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/build/gaiji.rb
# ================================================================
# 責務:
#   本の書体にない漢字（外字）を、その字を持つ書体から取った字の形の図形にして、PDF に組む
#   （改善案 #127 段階 4）。lives-mathematics の「祖暅」の「暅」のように、本文の書体（Noto Serif JP）
#   にも HackGen・DejaVu にも無い字は、Chromium が OS の書体で代わりに組み、Type 3 になる。
#
# どの書体から取るか（使用条件の調べは改善案 #127 段階 4）:
#   - OFL の書体（思源宋体・Noto Serif CJK など、著者が入れたもの）。build では取った形を
#     プロジェクトにも保存する（images/gaiji/）。書体の無い PC でも同じ形で組める
#   - macOS 付属の書体のうち、埋め込みを許すもの（fsType が「埋め込み不可」でない）。使用許諾
#     （第 2 条 E）が文書への埋め込みを、書体の埋め込みの制限が許す範囲で認めている。取った形は
#     ファイルとして持ち回らないよう、.cache/ にだけ置く（第 2 条 N。どの Mac にも同じ書体がある）
#   ほかの書体（使用条件の分からないもの）は使わない。選ぶ順は、周りの字に合う形（明朝系か
#   ゴシック系か）→ OFL の書体 → 太さの近い面。preflight は .cache/ にだけ置く。
#
# 置き方:
#   PDF に入れる HTML（build/pdf/）の字を、インラインの <svg>（fill="currentColor"）に替える。
#   1 字 = 1em の枠で、下端を基線から 0.12em 下に置く（和文の字面の枠）。字の黒い部分の
#   上下の中心は、字面の中心（基線から 0.38em 上）にそろえる——宋体は字面の枠が日本の書体と
#   違い、字の形も枠の中で下寄りに描かれている。EPUB は読者の端末の書体で表示されるので替えない。
# ================================================================

require 'cgi'
require 'digest'
require 'fileutils'
require 'json'
require 'ttfunk'
require_relative '../common'
require_relative 'glyph_outline'

module VivlioStarter
  module CLI
    module Build
      # 外字を字の形の図形にする
      module Gaiji
        # 字の形の SVG を保存する所。OFL の書体から取った形だけをプロジェクトに置く
        PROJECT_DIR = File.join(Common::IMAGES_DIR, 'gaiji')
        CACHE_DIR = File.join(Common::CACHE_DIR, 'gaiji')

        # 字面の枠の上端（SVG の座標）と、字の黒い部分の上下の中心を置く位置
        EM_TOP = -880
        INK_CENTER = -380

        # 書体を探す所。OFL の書体は著者が入れた所、付属の書体は macOS の所
        AUTHOR_FONT_DIRS = %w[
          ~/Library/Fonts /Library/Fonts ~/.local/share/fonts ~/.fonts /usr/share/fonts /usr/local/share/fonts
        ].freeze
        SYSTEM_FONT_DIRS = %w[/System/Library/Fonts /System/Library/Fonts/Supplemental].freeze
        FONT_FILES = '*.{ttf,otf,ttc,TTF,OTF,TTC}'

        OFL = /Open Font License|scripts\.sil\.org\/OFL|openfontlicense/i
        # 保存する SVG に書く使用条件。OFL の書体から取った形かを、後でこれで見分ける
        OFL_NOTE = 'SIL Open Font License'
        SERIF = /Serif|Mincho|Ming|Song|Kai|STIX|明朝|宋|楷/i

        # 外字にする字。漢字と、数学用英数字（`𝓐`・`𝕜`・`𝛂` など。MathJax が描ける字は前処理で数式に
        # 包まれる——PreProcessCommands::MathLetterWrapper）。記号や他の文字は予備の書体が受け持つ
        TARGET = /\p{Han}|[\u{1D400}-\u{1D7FF}]/

        # 字の形を取れる書体の 1 面
        # @!attribute tier [Integer] 0 = OFL の書体・1 = 付属の書体
        Face = Data.define(:path, :index, :name, :tier, :style, :weight)

        # 1 字の図形（保存する SVG の中身から読む）
        Glyph = Data.define(:view_box, :width, :d)

        module_function

        # --- 置き換える ---

        # build/pdf/ の HTML の外字を図形に替える。
        # @param dir [String] PDF 用に写した HTML の置き場
        # @return [Integer] 替えた字の数
        def apply_to_dir!(dir)
          require_relative '../post_process/html_parser'
          require_relative '../pre_process/glyph_coverage_check'
          chains = PreProcessCommands::GlyphCoverageCheck.font_chains or return 0

          # --- Phase: 外字を集める ---
          # 漢字がどの置き場所の書体にもそろっている HTML は、組み直さずに飛ばす（ほとんどの章がそう）
          covered = ->(char) { chains.values_at(:body, :heading, :code).compact.all? { |chain| chain.any? { |font| font.glyph?(char) } } }
          docs = Dir.glob(File.join(dir, '*.html')).filter_map do |path|
            html = File.read(path, encoding: 'utf-8')
            next if html.scan(TARGET).uniq.all?(&covered)

            [path, PostProcessCommands::HtmlParser.parse_html_document(html)]
          end.to_h
          targets = docs.transform_values { |doc| gaiji_nodes(doc, chains) }
          wanted = targets.values.flatten(1).flat_map { |_, chars, style, bold| chars.map { [it, style, bold] } }.uniq
          return 0 if wanted.empty?

          # --- Phase: 字の形を用意する（書体を探すのは足りない字があるときだけ） ---
          glyphs = resolve(wanted, keep: true)

          # --- Phase: 字を図形に替える ---
          replaced = 0
          targets.each do |path, nodes|
            next if nodes.empty?

            nodes.each do |node, _chars, style, bold|
              html = node.text.each_char.map do |char|
                glyph = glyphs[[char, style, bold]]
                next CGI.escapeHTML(char) unless glyph

                replaced += 1
                inline_svg(char, glyph)
              end.join
              node.replace(html)
            end
            PostProcessCommands::HtmlParser.save_html_document(path, docs[path])
          end
          missing = wanted.reject { glyphs.key?(it) }.map(&:first).uniq
          Common.log_info("[PDF] 外字を字の形の図形にしました: #{replaced} 字") if replaced.positive?
          Common.log_debug("[PDF] 外字の形を取れる書体がありません: #{missing.join(' ')}") unless missing.empty?
          replaced
        end

        # 外字のある字の並び。[テキストノード, 外字, 書体の形, 太字か]
        def gaiji_nodes(doc, chains)
          doc.xpath('//body//text()').filter_map do |node|
            text = node.text
            next unless text.match?(TARGET)

            ancestors = node.ancestors.select(&:element?).map(&:name)
            next if ancestors.intersect?(%w[script style svg title head textarea])

            place = place_of(ancestors)
            chain = chains[place] or next
            chars = text.each_char.select { |char| char.match?(TARGET) && chain.none? { |font| font.glyph?(char) } }.uniq
            next if chars.empty?

            [node, chars, style_of(place), place == :heading || ancestors.intersect?(%w[strong b th])]
          end
        end

        # 字の置き場所（GlyphCoverageCheck の書体の並びの名前）
        def place_of(ancestors)
          return :code if ancestors.intersect?(%w[code pre kbd samp])
          return :heading if ancestors.any? { it.match?(/\Ah[1-6]\z/) }

          :body
        end

        # 置き場所の書体の形。本文・見出しは本の書体の名前で決め、コードはゴシック系
        def style_of(place)
          embedder = PreProcessCommands::SvgFontEmbedder
          font = { body: embedder.configured_body_font, heading: embedder.configured_heading_font }[place]
          font.to_s.match?(SERIF) ? :serif : :sans
        end

        def inline_svg(char, glyph)
          label = CGI.escapeHTML(char)
          %(<svg xmlns="http://www.w3.org/2000/svg" class="vs-gaiji" viewBox="#{glyph.view_box}" role="img" ) +
            %(aria-label="#{label}" style="display:inline-block;width:#{glyph.width}em;height:1em;) +
            %(vertical-align:-0.12em;fill:currentColor"><path d="#{glyph.d}"/></svg>)
        end

        # --- 字の形を用意する ---

        # 字の形を、保存したもの → 書体から取ったもの の順に引く。書体を探すのは、
        # 保存したものが無い字があるときだけ、まとめて 1 回。
        # @param wanted [Array(String, Symbol, Boolean)] 字・書体の形・太字か
        # @return [Hash{Array => Glyph}] 形の取れた字だけ
        #
        # 取った形はいつも .cache/ に置く。keep（build）のときは、OFL の書体から取った形を
        # プロジェクトにも置く——preflight（確かめるだけのコマンド）はプロジェクトのファイルを増やさない
        def resolve(wanted, keep: false)
          @mutex.synchronize do
            found = wanted.filter_map { |key| (glyph = stored(*key, keep:)) && [key, glyph] }.to_h
            rest = wanted.reject { found.key?(it) || known_missing?(it) }
            unless rest.empty?
              faces = font_faces
              rest.each do |key|
                glyph = extract(key, faces, keep:)
                glyph ? found[key] = glyph : remember_missing(key)
              end
            end
            found
          end
        end

        # 外字にできるか（GlyphCoverageCheck が、図形にできる字を知らせないために使う）
        def available?(char, place)
          return false unless char.match?(TARGET)

          !resolve([[char, style_of(place), place == :heading]]).empty?
        end

        # 保存した字の形
        def stored(char, style, bold, keep: false)
          name = file_name(char, style, bold)
          path = [PROJECT_DIR, CACHE_DIR].map { File.join(it, name) }.find { File.file?(it) } or return nil
          svg = File.read(path, encoding: 'utf-8')
          save(PROJECT_DIR, name, svg) if keep && path.start_with?(CACHE_DIR) && svg.include?(OFL_NOTE)
          parse_svg(svg)
        end

        def save(dir, name, svg)
          FileUtils.mkdir_p(dir)
          File.write(File.join(dir, name), svg, encoding: 'utf-8')
        end

        def file_name(char, style, bold) = format('u%04x-%s%s.svg', char.ord, style, bold ? '-bold' : '')

        def parse_svg(svg)
          view_box = svg[/viewBox="([^"]+)"/, 1]
          d = svg[/<path d="([^"]+)"/, 1]
          return nil unless view_box && d

          Glyph.new(view_box:, width: format('%.3g', view_box.split[2].to_f / 1000), d:)
        end

        # 書体から字の形を取り、保存する。OFL の書体はプロジェクトへ、付属の書体は .cache/ へ
        #
        # 選ぶ順は、形（明朝系かゴシック系か）が合う → OFL の書体 → 太さが近い。明朝の書体しか
        # 入っていなくても、ゴシックの見出しには付属のゴシックの書体を使う（どちらも使用条件は満たす）
        def extract((char, style, bold), faces, keep: false)
          face = best_face(faces.select { contains?(it, char) }, style, bold) or return nil

          outline = GlyphOutline.for(open_face(face), char) or return nil
          # 漢字は字の黒い部分を字面の中ほどに置く。欧文の字（数学用英数字）は基線をそろえる——
          # 小文字や下に伸びる字（`𝒿`）を中ほどへ寄せると、基線から浮く
          top = char.match?(/\p{Han}/) ? EM_TOP + (((outline.top + outline.bottom) / 2.0) - INK_CENTER) : EM_TOP
          view_box = "0 #{GlyphOutline.number(top)} #{GlyphOutline.number(outline.advance)} 1000"
          license = face.tier.zero? ? OFL_NOTE : 'macOS 付属の書体（埋め込みを許すもの）'
          svg = %(<svg xmlns="http://www.w3.org/2000/svg" viewBox="#{view_box}">) +
                %(<!-- #{char}: #{face.name}（#{license}） --><path d="#{outline.d}"/></svg>\n)
          name = file_name(char, style, bold)
          save(CACHE_DIR, name, svg)
          save(PROJECT_DIR, name, svg) if keep && face.tier.zero?
          Common.log_info("[PDF] 外字「#{char}」の形を #{face.name} から取りました")
          parse_svg(svg)
        end

        # 形（明朝系かゴシック系か）が合う → OFL の書体 → 太さが近い の順で 1 つ選ぶ
        def best_face(candidates, style, bold)
          candidates.min_by { [it.style == style ? 0 : 1, it.tier, (it.weight - (bold ? 700 : 400)).abs] }
        end

        # --- 書体を探す ---

        # 字の形を取れる書体の面の一覧。OFL の書体と、埋め込みを許す付属の書体だけ
        def font_faces
          @font_faces ||= begin
            author = AUTHOR_FONT_DIRS.flat_map { Dir.glob(File.join(File.expand_path(it), '**', FONT_FILES)) }
            system = SYSTEM_FONT_DIRS.flat_map { Dir.glob(File.join(it, FONT_FILES)) }
            (author.map { [it, false] } + system.map { [it, true] }).uniq(&:first).flat_map { |path, system_font| faces_in(path, system_font) }
          end
        end

        # OFL の書体は、付属の書体（STIX Two Math）でも OFL の書体として扱う（形をプロジェクトに保存してよい）。
        # 付属の書体で OFL でないものは、埋め込みを許すものだけ。著者が入れた書体は OFL のものだけ
        def faces_in(path, system_font)
          each_face(path).filter_map do |font, index|
            name = english_name(font)
            next if name.nil? || name.start_with?('.', 'LastResort')

            tier = if ofl?(font) then 0
                   elsif system_font && embeddable?(font.os2.type) then 1
                   end
            next unless tier

            Face.new(path:, index:, name:, tier:, style: name.match?(SERIF) ? :serif : :sans,
                     weight: font.os2.weight_class)
          end
        rescue StandardError => e
          Common.log_debug("[gaiji] 書体を読めませんでした: #{path} (#{e.message})")
          []
        end

        # OFL の書体か。使用条件（nameID 13）か、その URL（nameID 14・Noto はこちらだけ）で見る
        def ofl?(font)
          (font.name.license + font.name.license_url).any? { it.to_s.delete("\0").match?(OFL) }
        end

        # 書体の面（TTC は全部）
        def each_face(path)
          return [[TTFunk::File.open(path), nil]] unless path.downcase.end_with?('.ttc')

          TTFunk::Collection.open(path) { |collection| (0...collection.count).map { [collection[it], it] } }
        end

        def open_face(face)
          return TTFunk::File.open(face.path) unless face.index

          TTFunk::Collection.open(face.path) { it[face.index] }
        end

        # 埋め込みの制限（OS/2 の fsType）が、文書への埋め込みを許すか。
        # 「埋め込み不可」（2）と「ビットマップだけ」（0x200）を除く
        def embeddable?(fs_type) = (fs_type & 0x000F) != 2 && (fs_type & 0x0200).zero?

        def english_name(font)
          font.name.font_name.map { it.to_s.delete("\0") }.find(&:ascii_only?)
        end

        # 面がその字を持つか。cmap は面ごとに一度だけ読む
        def contains?(face, char)
          @cmaps[[face.path, face.index]] ||= begin
            font = open_face(face)
            font.cmap.tables.select { it.unicode? && it.respond_to?(:code_map) }
                .each_with_object(Set[]) { |table, set| table.code_map.each { |code, gid| set << code if gid.positive? } }
          end
          @cmaps[[face.path, face.index]].include?(char.ord)
        end

        # --- 形の取れなかった字を覚える（preflight のたびに書体を探し直さないため） ---

        # 書体の置き場が変わっていなければ（書体を入れていなければ）、探し直さない
        def known_missing?(key)
          data = missing_record
          data['signature'] == fonts_signature && data['keys'].include?(key.join('/'))
        end

        def remember_missing(key)
          data = missing_record
          data = { 'signature' => fonts_signature, 'keys' => [] } unless data['signature'] == fonts_signature
          data['keys'] |= [key.join('/')]
          FileUtils.mkdir_p(CACHE_DIR)
          File.write(missing_path, JSON.generate(data))
          @missing_record = data
        end

        def missing_record
          @missing_record ||= File.file?(missing_path) ? JSON.parse(File.read(missing_path)) : { 'keys' => [] }
        rescue JSON::ParserError
          @missing_record = { 'keys' => [] }
        end

        def missing_path = File.join(CACHE_DIR, 'missing.json')

        def fonts_signature
          dirs = (AUTHOR_FONT_DIRS.map { File.expand_path(it) } + SYSTEM_FONT_DIRS).select { File.directory?(it) }
          Digest::SHA256.hexdigest(dirs.map { "#{it}:#{File.mtime(it).to_i}" }.join('|'))[0, 16]
        end

        # 覚えた書体・字を忘れる（テストのため）
        def reset!
          @font_faces = nil
          @missing_record = nil
          @cmaps = {}
        end

        @mutex = Mutex.new
        @cmaps = {}
      end
    end
  end
end
