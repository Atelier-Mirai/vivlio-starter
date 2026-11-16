# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/build/finalizers/variant_glyph_fonts.rb
# ================================================================
# 責務:
#   異体字セレクタ付きの字を 1 字書体で出す（Kindle だけ）
# ================================================================

require 'fileutils'
require_relative '../epub/stylesheets'
require_relative 'book'
require_relative '../variant_glyph_font'
require_relative '../../post_process/html_parser'

module VivlioStarter
  module CLI
    module Build
      # 異体字セレクタ付きの字を 1 字書体で出す（Kindle だけ）
      module Finalizers::VariantGlyphFonts
        module_function

        # ================================================================
        # 異体字の 1 字書体（Kindle 専用・kindle-ivs-font-spec.md）
        # ================================================================

        # 異体字の書体が字形を引く 1 面（書体名・太さ・実体・異体の表）。
        VariantFace = Data.define(:name, :weight, :path, :variants)

        # 書体を置く消費者 dir 内の場所と、CSS 上のファミリ名の接頭辞。
        # 接頭辞は Css::TargetFilter が @font-face を残す目印も兼ねる（KEPT_FACE_PATTERN）。
        VARIANT_FONT_DIR = 'fonts'
        VARIANT_FAMILY_PREFIX = 'vs-variant-'

        # 本全体の段の入口。書き換えるのは HTML と、ワークスペースの styles/ の CSS のファイルで、
        # book の CSS の表は変えない
        #
        # @param book [Finalizers::Book]
        # @param ctx [Transforms::Context]
        # @return [Finalizers::Book] そのままの book
        def call(book, ctx)
          apply!(book.pages, ctx.workspace)
          book
        end

        # 異体字セレクタ付きの字を、親字に異体の字形を割り当てた書体で出す。
        #
        # KFX は異体字セレクタを読まず、`禰󠄀` は文字のまま組まれる場所で親字の示偏に戻る。
        # 原稿に出た組の字形だけを集めた書体を作り、本文はセレクタを外した親字を
        # `<span class="vs-variant-N">` で囲んでその書体を当てる。文字のままなので、
        # 文字の大きさの変更・ダークモード・検索に従う（画像では大きさに追従できない）。
        #
        # 書き換えるのはテキストノードだけ。id・alt・data-* と <title> のセレクタは残す
        # （アンカーの一致と読み上げを壊さないため）。組が無い本では書体を読みもしない。
        #
        # @param html_files [Array<String>] Kindle 消費者 dir の HTML
        # @param base_dir [String] Kindle 消費者 dir（平らにした CSS を styles/ に持つ）
        # @return [Array<String>] そのままの配列
        def apply!(html_files, base_dir)
          # --- Phase: 原稿に出た組を集める ---
          docs = html_files.to_h do |path|
            [path, PostProcessCommands::HtmlParser.parse_html_document(File.read(path, encoding: 'utf-8'))]
          end
          occurrences = docs.flat_map do |path, doc|
            variant_text_nodes(doc).flat_map { variant_occurrences(it.content, path) }
          end
          return html_files if occurrences.empty?

          # 規則は、平らにした CSS（ページの種類ごとに 1 枚）のすべてへ足す
          css_paths = Dir.glob(File.join(base_dir, Epub::Stylesheets::EPUB_STYLES_DIR, '*.css'))
          if css_paths.empty?
            Common.log_warn("[Kindle] #{File.join(base_dir, Epub::Stylesheets::EPUB_STYLES_DIR)} に CSS が無いため、異体字の書体を当てられません")
            return html_files
          end

          # --- Phase: 字形を引き、置き換える組と字形の無い組に分ける ---
          sources = variant_glyph_sources
          reference = sources[:body].first&.variants
          lookups = occurrences.to_h { [it[:pair], reference&.lookup(*it[:pair])] }
          warn_missing_variant_glyphs(occurrences.select { lookups[it[:pair]].nil? }, sources[:body].first)
          replaced = occurrences.map { it[:pair] }.select { lookups[it].is_a?(Integer) }
          return html_files if replaced.empty?

          # --- Phase: 書体と CSS を書き出す ---
          slots = VariantGlyphFont.assign(replaced)
          rules = write_variant_glyph_fonts!(slots, sources, base_dir)
          css_paths.each do |css_path|
            File.write(css_path, "\n/* 異体字の 1 字書体（kindle-ivs-font-spec.md） */\n#{rules.join("\n")}\n",
                       mode: 'a', encoding: 'utf-8')
          end

          # --- Phase: 本文の字を親字＋span へ置き換える ---
          slot_of = slots.each_with_index.flat_map { |pairs, i| pairs.map { [it, i + 1] } }.to_h
          docs.each do |path, doc|
            count = variant_text_nodes(doc).sum { replace_variant_sequences!(it, doc, slot_of) }
            next if count.zero?

            PostProcessCommands::HtmlParser.save_html_document(path, doc)
            Common.log_info("[EPUB] #{File.basename(path)} の異体字 #{count} 字に専用の書体を当てました")
          end
          html_files
        end

        # 本文の中で、異体字セレクタを含みうるテキストノード。script・style の中は字ではない。
        def variant_text_nodes(doc)
          body = doc.at_css('body')
          return [] unless body

          body.xpath('.//text()').select do |node|
            node.content.match?(VariantGlyphFont::SEQUENCE) && node.ancestors.none? { %w[script style].include?(it.name) }
          end
        end

        # テキスト 1 つの中の組と、その前後（警告で出現箇所を示すため）。
        def variant_occurrences(text, path)
          text.to_enum(:scan, VariantGlyphFont::SEQUENCE).map do
            match = Regexp.last_match
            context = text[[match.begin(0) - 8, 0].max...(match.end(0) + 8)].gsub(/\s+/, ' ').strip
            { pair: [match[1].ord, match[2].ord], file: File.basename(path), context: }
          end
        end

        # 本文用・見出し用の字形の取り元。設定の書体が異体の表を持たなければ同梱の Noto へ寄せる
        # （Google Fonts の静的 TTF は表を持たないことがある・spec §2.3）。
        # @return [Hash{Symbol => Array<VariantFace>}] 役割 => 面（400 が先頭）。見つからなければ空
        def variant_glyph_sources
          embedder = PreProcessCommands::SvgFontEmbedder
          {
            body: [embedder.configured_body_font, embedder::DEFAULT_BODY_FONT],
            heading: [embedder.configured_heading_font, embedder::DEFAULT_FONT]
          }.transform_values do |names|
            names.uniq.lazy.map { variant_faces_of(it) }.find { |faces| faces.any? && !faces.first.variants.empty? } || []
          end
        end

        # 書体 1 つぶんの面。Regular と Bold が同じ実体なら 1 面だけ。
        def variant_faces_of(name)
          embedder = PreProcessCommands::SvgFontEmbedder
          regular = embedder.font_path(name, weight: :regular)
          return [] unless regular && File.file?(regular)

          bold = embedder.font_path(name, weight: :bold)
          paths = bold && bold != regular ? { 400 => regular, 700 => bold } : { 400 => regular }
          paths.map { |weight, path| VariantFace.new(name:, weight:, path:, variants: VariantGlyphFont.read(path)) }
        end

        # 割り振った組ごとに書体を書き出し、対応する CSS の規則を返す。
        #
        # 見出しの書体が本文と同じ実体なら見出し用は作らない。見出し用のファミリには本文用を
        # 後ろに並べる——見出しの書体にだけ字形が無い組でも、本文の字形で異体の形を保てる。
        # KFX は `:is()` を解さないので、見出しのセレクタは並べて書く。
        # @return [Array<String>] CSS の規則
        def write_variant_glyph_fonts!(slots, sources, base_dir)
          dir = File.join(base_dir, VARIANT_FONT_DIR)
          FileUtils.mkdir_p(dir)
          FileUtils.rm_f(Dir.glob(File.join(dir, "#{VARIANT_FAMILY_PREFIX}*.ttf")))
          roles = { body: '' }
          roles[:heading] = '-heading' unless sources[:heading].map(&:path) == sources[:body].map(&:path)

          slots.each_with_index.flat_map do |pairs, index|
            family = "#{VARIANT_FAMILY_PREFIX}#{index + 1}"
            faces = roles.flat_map do |role, suffix|
              sources[role].filter_map { write_variant_face(it, pairs, "#{family}#{suffix}", dir) }
            end
            faces << %(.#{family} { font-family: "#{family}"; })
            if roles.key?(:heading)
              selectors = (1..6).map { "h#{it} .#{family}" }.join(', ')
              faces << %(#{selectors} { font-family: "#{family}-heading", "#{family}"; })
            end
            faces
          end
        end

        # 1 面ぶんの TTF を書き、@font-face を返す。この面に字形が 1 つも無ければ nil。
        def write_variant_face(face, pairs, family, dir)
          glyphs = pairs.filter_map do |base, selector|
            glyph = face.variants.lookup(base, selector)
            [base, glyph] if glyph.is_a?(Integer)
          end.to_h
          return nil if glyphs.empty?

          file = "#{family}#{'-bold' if face.weight == 700}.ttf"
          internal_name = "VS Variant Glyphs #{family.delete_prefix(VARIANT_FAMILY_PREFIX).tr('-', ' ')}"
          File.binwrite(File.join(dir, file), VariantGlyphFont.encode(face.path, glyphs, family: internal_name))
          # 規則を書く CSS は styles/ の中にあるので、消費者 dir の fonts/ へは一段上がる
          %(@font-face { font-family: "#{family}"; font-weight: #{face.weight}; src: url("../#{VARIANT_FONT_DIR}/#{file}"); })
        end

        # テキストノード 1 つの中の、書体を割り振った組を親字＋span へ置き換える。
        # 既定の組・字形の無い組はセレクタごとそのまま残す。
        # @return [Integer] 置き換えた字数
        def replace_variant_sequences!(node, doc, slot_of)
          text = node.content
          pieces = []
          cursor = 0
          text.to_enum(:scan, VariantGlyphFont::SEQUENCE).each do
            match = Regexp.last_match
            slot = slot_of[[match[1].ord, match[2].ord]]
            next unless slot

            pieces << doc.create_text_node(text[cursor...match.begin(0)]) if match.begin(0) > cursor
            span = Nokogiri::XML::Node.new('span', doc)
            span['class'] = "#{VARIANT_FAMILY_PREFIX}#{slot}"
            span.content = match[1]
            pieces << span
            cursor = match.end(0)
          end
          return 0 if pieces.empty?

          pieces << doc.create_text_node(text[cursor..]) if cursor < text.length
          pieces.each { node.add_previous_sibling(it) }
          node.remove
          pieces.count { it.element? }
        end

        # 書体に字形が無い組を、出現箇所つきで 1 回だけ知らせる。
        def warn_missing_variant_glyphs(missing, source)
          return if missing.empty?

          groups = missing.group_by { it[:pair] }
          Common.log_warn("[Kindle] 異体字の字形が書体にないため、Kindle では親字の形で表示されます（#{groups.size} 組）")
          groups.each do |(base, selector), found|
            first = found.first
            others = found.size > 1 ? "ほか #{found.size - 1} か所" : ''
            Common.log_warn(format('    %<char>s（U+%<base>04X U+%<sel>04X）… %<file>s「%<context>s」%<others>s',
                                   char: [base, selector].pack('U*'), base:, sel: selector,
                                   file: first[:file], context: first[:context], others:))
          end
          if source
            Common.log_warn("    → 書体 #{source.name} がこの異体を持っていません。PDF でも親字の形になります。")
          else
            Common.log_warn('    → 異体の字形を引ける書体（同梱の Noto Serif JP など）が見つかりませんでした。')
          end
          Common.log_warn('      字形が要るなら、その字だけ画像にするか、この異体を持つ書体を typography.body.font に指定してください。')
        end
      end
    end
  end
end
