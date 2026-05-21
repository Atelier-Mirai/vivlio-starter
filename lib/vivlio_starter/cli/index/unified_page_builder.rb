# frozen_string_literal: true

# ================================================================
# Class: UnifiedPageBuilder
# ----------------------------------------------------------------
# 責務:
#   統合用語辞書（index_glossary_terms.yml）から索引ページと用語集ページを生成。
#   Phase B で IndexPageBuilder と GlossaryPageBuilder を統合。
#
#   flags に基づく出力制御:
#     i  → _indexpage.html にのみ掲載
#     g  → _glossarypage.html にのみ掲載
#     ig → 両方に掲載
#
# 主要メソッド:
#   - build_index!: 索引ページを生成
#   - build_glossary!: 用語集ページを生成
# ================================================================

require 'yaml'
require 'fileutils'
require 'cgi'
require_relative '../common'
require_relative 'hierarchical_index'

module VivlioStarter
  module CLI
    module IndexCommands
      class UnifiedPageBuilder
        # 五十音の行判定用マッピング（ひらがな・カタカナ両対応）
        KANA_ROWS = {
          'あ' => /^[あ-おぁ-ぉア-オァ-ォ]/,
          'か' => /^[か-ごゕゖカ-ゴヵヶ]/,
          'さ' => /^[さ-ぞサ-ゾ]/,
          'た' => /^[た-どタ-ド]/,
          'な' => /^[な-のナ-ノ]/,
          'は' => /^[は-ぽハ-ポ]/,
          'ま' => /^[ま-もマ-モ]/,
          'や' => /^[や-よゃゅょヤ-ヨャュョ]/,
          'ら' => /^[ら-ろラ-ロ]/,
          'わ' => /^[わ-んゎワ-ンヮ]/
        }.freeze

        SYMBOL_ROW_LABEL = '記号'
        NUMBER_ROW_LABEL = '数字'
        DIGIT_REGEX = /\A[0-9０-９]\z/

        ALPHA_ROWS = ('A'..'Z').to_h do |letter|
          [letter, /^[#{letter.downcase}#{letter}]/]
        end.freeze

        INDEX_MATCH_FILE = '_index_matches.yml'
        INDEX_OUTPUT_FILE = '_indexpage.html'
        GLOSSARY_OUTPUT_FILE = '_glossarypage.html'

        attr_reader :index_data, :hierarchical_index

        def initialize(glossary_config: {})
          @index_data = {}
          @hierarchical_index = HierarchicalIndex.new
          @glossary_config = glossary_config
        end

        # --- Phase: 索引ページ生成 ---

        # 索引ページを生成
        # @return [String, nil] 出力ファイルパス、または nil
        def build_index!
          unless File.exist?(INDEX_MATCH_FILE)
            Common.log_warn("索引データが見つかりません: #{INDEX_MATCH_FILE}")
            return nil
          end

          load_index_data!

          if @index_data.empty?
            Common.log_info('索引に登録された用語がありません')
            cleanup_stale_file!(INDEX_OUTPUT_FILE)
            return nil
          end

          html = generate_index_html
          File.write(INDEX_OUTPUT_FILE, html, encoding: 'utf-8')
          Common.log_success("索引ページを生成しました: #{INDEX_OUTPUT_FILE}")
          INDEX_OUTPUT_FILE
        end

        # --- Phase: 用語集ページ生成 ---

        # 用語集ページを生成
        # @param terms [Array<Hash>] 用語集対象の用語リスト（flags に g を含む）
        # @return [String, nil] 出力ファイルパス、または nil
        def build_glossary!(terms)
          if terms.nil? || terms.empty?
            Common.log_info('用語集に登録された用語がありません')
            cleanup_stale_file!(GLOSSARY_OUTPUT_FILE)
            return nil
          end

          sorted_terms = terms.sort_by { it['yomi'] || it['term'] }
          html = generate_glossary_html(sorted_terms)
          File.write(GLOSSARY_OUTPUT_FILE, html, encoding: 'utf-8')
          Common.log_success("用語集ページを生成しました: #{GLOSSARY_OUTPUT_FILE}")
          GLOSSARY_OUTPUT_FILE
        end

        # 以前のビルドで残ったファイルを削除
        def cleanup_stale_file!(file)
          return unless File.exist?(file)

          FileUtils.rm_f(file)
          Common.log_info("#{file} を削除しました")
        end

        private

        # ================================================================
        # 索引ページ生成（旧 IndexPageBuilder のロジック）
        # ================================================================

        # 索引データを読み込み
        def load_index_data!
          data = YAML.load_file(INDEX_MATCH_FILE, permitted_classes: [Time, Symbol])
          @index_data = data['terms'] || {}

          # HierarchicalIndex にエントリを追加（全リンクを保持、重複排除なし）
          @index_data.each do |term, occurrences|
            occurrences.each do |occ|
              link = occ['link'] || occ[:link]
              @hierarchical_index.add_entry(term, link)
            end
          end

          Common.log_info("索引データを読み込み: #{@index_data.size} 件の用語、#{@hierarchical_index.link_count} 件のリンク")
        end

        # 索引 HTML を生成
        def generate_index_html
          sorted_terms = sort_index_terms_by_yomi
          groups = group_by_kana_row(sorted_terms)

          <<~HTML
            <!DOCTYPE html>
            <html lang="ja">
            <head>
              <meta charset="UTF-8">
              <title>索引</title>
              <link rel="stylesheet" href="stylesheets/index.css">
            </head>
            <body class="index-page">
              <section class="index">
                <h1>索引</h1>
                #{generate_index_sections(groups)}
              </section>
            </body>
            </html>
          HTML
        end

        # 用語を読みでソート
        def sort_index_terms_by_yomi
          @index_data.sort_by do |_term, occurrences|
            first_yomi = occurrences.first['yomi'] || occurrences.first[:yomi] || ''
            first_yomi.to_s
          end
        end

        # 五十音の行ごとにグループ化
        def group_by_kana_row(sorted_terms)
          groups = Hash.new { |h, k| h[k] = [] }

          sorted_terms.each do |term, occurrences|
            first_yomi = occurrences.first['yomi'] || occurrences.first[:yomi] || term
            row = determine_kana_row(first_yomi.to_s, term)
            groups[row] << [term, occurrences]
          end

          ordered_rows = [SYMBOL_ROW_LABEL, NUMBER_ROW_LABEL] + ('A'..'Z').to_a + %w[あ か さ た な は ま や ら わ] + ['その他']
          ordered_rows.filter_map do |row|
            [row, groups[row]] if groups.key?(row)
          end.to_h
        end

        # 読みの先頭から五十音の行を判定
        def determine_kana_row(yomi, term)
          term_char = term.to_s[0]

          symbol_row = match_symbol_row(term_char)
          return symbol_row if symbol_row

          number_row = match_number_row(term_char)
          return number_row if number_row

          row = match_alpha_row(term_char)
          return row if row

          first_char = yomi[0]

          row = match_alpha_row(first_char)
          return row if row

          row = match_kana_row(first_char)
          return row if row

          'その他'
        end

        def match_kana_row(char)
          return nil unless char

          KANA_ROWS.each do |row, pattern|
            return row if char.match?(pattern)
          end
          nil
        end

        def match_alpha_row(char)
          return unless char

          ALPHA_ROWS.each do |row, regex|
            return row if regex.match?(char)
          end
          nil
        end

        def match_symbol_row(char)
          return unless char

          SYMBOL_ROW_LABEL unless char.match?(/[[:alnum:]]/)
        end

        def match_number_row(char)
          return unless char

          NUMBER_ROW_LABEL if DIGIT_REGEX.match?(char)
        end

        # 索引セクションの HTML を生成
        def generate_index_sections(groups)
          groups.map do |row, terms|
            next if terms.empty?

            <<~SECTION
              <div class="index-section" data-initial="#{row}">
                <h2>#{row}</h2>
                <dl class="index-list">
                  #{generate_index_term_entries(terms)}
                </dl>
              </div>
            SECTION
          end.compact.join("\n")
        end

        # 索引用語エントリの HTML を生成
        def generate_index_term_entries(terms)
          terms.map do |term, _occurrences|
            escaped_term = CGI.escapeHTML(term.to_s)
            links = generate_index_page_links(term)
            <<~ENTRY
              <dt>#{escaped_term}</dt>
              <dd>#{links}</dd>
            ENTRY
          end.join
        end

        # 索引ページリンクの HTML を生成
        def generate_index_page_links(term)
          @index_data[term].map do |occ|
            link = occ['link'] || occ[:link]
            css_class = link.start_with?('00-preface') ? ' class="frontmatter"' : ''
            %(<a href="#{link}"#{css_class}></a>)
          end.join
        end

        # ================================================================
        # 用語集ページ生成（旧 GlossaryPageBuilder のロジック）
        # ================================================================

        # 用語集 HTML を生成
        def generate_glossary_html(terms)
          title = @glossary_config[:title] || '用語集'

          <<~HTML
            <!DOCTYPE html>
            <html lang="ja">
            <head>
              <meta charset="UTF-8">
              <title>#{title}</title>
              <link rel="stylesheet" href="stylesheets/glossary.css">
            </head>
            <body class="glossary-page">
              <section class="glossarypage" role="doc-glossary">
                <h1 class="glossary-title">#{title}</h1>
                <dl class="glossary-list">
                  #{build_glossary_entries(terms)}
                </dl>
              </section>
            </body>
            </html>
          HTML
        end

        # 用語集エントリを構築
        def build_glossary_entries(terms)
          grouped = group_glossary_by_initial(terms)

          entries = []
          grouped.each do |initial, group_terms|
            entries << %(<div class="glossary-group-header" role="heading" aria-level="2">#{initial}</div>)
            group_terms.each { entries << build_glossary_term_entry(it) }
          end

          entries.join("\n")
        end

        # 読みの先頭文字でグループ化
        def group_glossary_by_initial(terms)
          terms.group_by do |term|
            yomi = term['yomi'] || term['term']
            normalize_glossary_initial(yomi)
          end.sort.to_h
        end

        # 先頭文字を正規化
        def normalize_glossary_initial(yomi)
          return 'その他' if yomi.nil? || yomi.empty?

          first_char = yomi[0]
          normalized_char = katakana_to_hiragana(first_char)

          case normalized_char
          when /[あ-おぁ-ぉ]/ then 'あ'
          when /[か-こが-ご]/ then 'か'
          when /[さ-そざ-ぞ]/ then 'さ'
          when /[た-とだ-ど]/ then 'た'
          when /[な-の]/ then 'な'
          when /[は-ほば-ぼぱ-ぽ]/ then 'は'
          when /[ま-も]/ then 'ま'
          when /[や-よゃ-ょ]/ then 'や'
          when /[ら-ろ]/ then 'ら'
          when /[わ-んを]/ then 'わ'
          when /[a-zA-Z]/ then 'A-Z'
          when /[0-9]/ then '0-9'
          else 'その他'
          end
        end

        # カタカナをひらがなに変換
        def katakana_to_hiragana(char)
          return char unless char.match?(/[\u30A0-\u30FF]/)

          (char.ord - 96).chr('UTF-8')
        end

        # 用語集エントリを構築
        def build_glossary_term_entry(term)
          term_text = term['term']
          yomi = term['yomi'] || term_text
          definition = term['definition'] || ''
          slug = generate_slug(term_text)
          backlinks = build_glossary_backlinks(term)

          <<~HTML.chomp
            <dt id="gls-#{slug}" class="glossary-term">
              <ruby>#{escape_html(term_text)}<rp>(</rp><rt>#{escape_html(yomi)}</rt><rp>)</rp></ruby>
            </dt>
            <dd class="glossary-definition">
              #{render_definition(definition)}
              #{backlinks}
            </dd>
          HTML
        end

        # 説明文をレンダリング（Markdown 対応）
        def render_definition(definition)
          return '' if definition.nil? || definition.empty?

          lines = definition.to_s.strip.split("\n")
          html_parts = []
          current_list = []

          lines.each do |line|
            if line.match?(/^\s*\*\s+/)
              current_list << line.sub(/^\s*\*\s+/, '').strip
              next
            end

            unless current_list.empty?
              html_parts << render_list(current_list)
              current_list = []
            end

            case line
            when /^####\s+(.+)$/
              html_parts << %(<h6 class="glossary-h6">#{render_inline(::Regexp.last_match(1))}</h6>)
            when /^###\s+(.+)$/
              html_parts << %(<h5 class="glossary-h5">#{render_inline(::Regexp.last_match(1))}</h5>)
            when /^##\s+(.+)$/
              html_parts << %(<h4 class="glossary-h4">#{render_inline(::Regexp.last_match(1))}</h4>)
            when /^\s*$/
              next
            else
              html_parts << %(<p class="glossary-text-line">#{render_inline(line)}</p>)
            end
          end

          html_parts << render_list(current_list) unless current_list.empty?

          %(<div class="glossary-body">#{html_parts.join("\n")}</div>)
        end

        def render_list(items)
          return '' if items.empty?

          li_tags = items.map { %(<li>#{render_inline(it)}</li>) }.join("\n")
          %(<ul class="glossary-list-items">\n#{li_tags}\n</ul>)
        end

        def render_inline(text)
          result = escape_html(text.to_s)
          result = result.gsub(/\*\*(.+?)\*\*/, '<strong>\1</strong>')
          result = result.gsub(/\*(.+?)\*/, '<em>\1</em>')
          result.gsub(/`(.+?)`/, '<code>\1</code>')
        end

        # 用語集のバックリンクを構築
        def build_glossary_backlinks(term)
          sources = term['backlink_sources']
          return '' unless sources&.any?

          sorted_sources = sources.sort_by do |source|
            chapter = source['chapter'] || source[:chapter]
            occurrence = source['occurrence'] || source[:occurrence] || 1
            chapter_num = chapter.to_s[/\A(\d+)/, 1]&.to_i || 999
            [chapter_num, occurrence]
          end

          links = sorted_sources.map do |source|
            chapter = source['chapter'] || source[:chapter]
            occurrence = source['occurrence'] || source[:occurrence] || 1
            anchor_id = source['anchor_id'] || source[:anchor_id] || "gls-src-#{chapter}-#{occurrence}"

            classes = ['glossary-backlink']
            classes << 'frontmatter' if chapter.to_s.start_with?('00-')

            %(<a href="#{chapter}.html##{anchor_id}" class="#{classes.join(' ')}"></a>)
          end

          <<~HTML.chomp
            <p class="glossary-backlinks">#{links.join(' ')}</p>
          HTML
        end

        # ================================================================
        # 共通ユーティリティ
        # ================================================================

        def generate_slug(term)
          term.downcase.gsub(/\s+/, '-').gsub(/[^\p{L}\p{N}-]/, '')
        end

        def escape_html(text)
          text.to_s
              .gsub('&', '&amp;')
              .gsub('<', '&lt;')
              .gsub('>', '&gt;')
              .gsub('"', '&quot;')
        end
      end
    end
  end
end
