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
require_relative '../pre_process/book_settings_css'

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

        # 出力先はワークスペースの html/（P4 §3.4-1）
        INDEX_OUTPUT_FILE = File.join(Common::BUILD_HTML_DIR, '_indexpage.html')
        GLOSSARY_OUTPUT_FILE = File.join(Common::BUILD_HTML_DIR, '_glossarypage.html')

        # 参照の出し方（book.yml の index.reference_style）
        REFERENCE_STYLES = %w[main_and_sub main_only all].freeze
        DEFAULT_REFERENCE_STYLE = 'main_and_sub'
        DEFAULT_MAX_SUB_REFERENCES = 8

        attr_reader :index_data, :limited_reference_terms

        def initialize(glossary_config: {}, index_config: nil)
          @index_data = {}
          @glossary_config = glossary_config
          @index_config = index_config || Common::CONFIG.index.to_h
          @glossary_backlinks = {}
          # 間引いた語（no silent caps: 絞ったことは呼び出し元から必ず報告する）
          @limited_reference_terms = []
        end

        # --- Phase: 索引ページ生成 ---

        # 索引ページを生成
        # @return [String, nil] 出力ファイルパス、または nil
        def build_index!
          unless File.exist?(Common::INDEX_MATCHES_FILE)
            Common.log_warn("索引データが見つかりません: #{Common::INDEX_MATCHES_FILE}")
            return nil
          end

          load_index_data!

          if @index_data.empty?
            Common.log_info('索引に登録された用語がありません')
            cleanup_stale_file!(INDEX_OUTPUT_FILE)
            return nil
          end

          html = generate_index_html
          FileUtils.mkdir_p(File.dirname(INDEX_OUTPUT_FILE))
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

          # バックリンクはそのビルドのスキャン結果（中間 YAML）から導出する（R2）。
          # 辞書の backlink_sources は読まない——前回ビルドの幽霊リンクを持ち込まないため
          @glossary_backlinks = load_glossary_backlinks

          sorted_terms = terms.sort_by { it['yomi'] || it['term'] }
          html = generate_glossary_html(sorted_terms)
          FileUtils.mkdir_p(File.dirname(GLOSSARY_OUTPUT_FILE))
          File.write(GLOSSARY_OUTPUT_FILE, html, encoding: 'utf-8')
          Common.log_success("用語集ページを生成しました: #{GLOSSARY_OUTPUT_FILE}")
          GLOSSARY_OUTPUT_FILE
        end

        # 参照を絞った事実。呼び出し元が必ず報告する（no silent caps・R6）
        Limitation = Data.define(:style, :limit, :terms) do
          def any? = terms.any?
          def size = terms.size
        end

        def reference_limitation
          Limitation.new(style: reference_style, limit: max_sub_references, terms: @limited_reference_terms)
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
          data = YAML.load_file(Common::INDEX_MATCHES_FILE, permitted_classes: [Time, Symbol])
          @index_data = data['terms'] || {}

          link_count = @index_data.values.sum(&:size)
          Common.log_info("索引データを読み込み: #{@index_data.size} 件の用語、#{link_count} 件のリンク")
        end

        # 生成物 book-settings.css への link。索引・用語集は章 HTML と違って
        # FrontmatterGenerator を通らないため、ここで自前に並べる必要がある。
        # {種別}.css の**後段**に置くことで book.yml 由来の設定値がテーマ CSS に
        # カスケードで勝つ（章 HTML と同じ順序・P3）。これが無いと索引・用語集だけが
        # 判型もテーマ色も book.yml を見ずに組まれる（chapter-pagebreak-spec.md §6 実装記録）。
        def book_settings_link
          href = "#{Common.asset_prefix}#{PreProcessCommands::BookSettingsCss.output_path}"
          %(<link rel="stylesheet" href="#{href}">)
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
              <link rel="stylesheet" href="#{Common.asset_prefix}stylesheets/index.css">
              #{book_settings_link}
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

        # 索引ページリンクの HTML を生成。
        # 主要参照（説明箇所）を先頭へ出し、太字用のクラスを付ける。
        #
        # **並べ替えは dedup より前でなければならない。** BacklinkDeduplicator は
        # 同一ページを指すリンクの「DOM 上で最初の 1 本」を残すので、主要参照が
        # 先頭にあればそれが生き残る。順序が逆だと主要参照のほうが消える。
        # `all` は主要参照の扱いを丸ごと切るための逃げ道。並べ替えも太字も
        # 間引きもせず、Phase 2 以前とまったく同じ索引を組む。
        def generate_index_page_links(term)
          highlight = reference_style != 'all'
          occurrences = if highlight
                          apply_reference_style(term, order_occurrences(@index_data[term]))
                        else
                          @index_data[term].to_a
                        end

          occurrences.map do |occ|
            link = occ['link'] || occ[:link]
            classes = []
            classes << 'main-ref' if highlight && main_occurrence?(occ)
            classes << 'frontmatter' if link.start_with?('00-preface')
            attr = classes.empty? ? '' : %( class="#{classes.join(' ')}")
            %(<a href="#{link}"#{attr}></a>)
          end.join
        end

        # 主要参照を先頭へ。同種のなかでは元の走査順（章順）を保つ。
        def order_occurrences(occurrences)
          occurrences.to_a.partition { main_occurrence?(it) }.flatten(1)
        end

        def main_occurrence?(occ) = (occ['is_main'] || occ[:is_main]) ? true : false

        # 副次参照を間引く（R6）。`all` は呼び出し側で分岐済み。
        #
        # **主要参照が無い語は間引かない。** 「まずここを読めばよい」を示せないまま
        # 出現箇所だけ削ると、語が索引から実質消える——絞り込みは主要参照という
        # 代替の案内があってはじめて成立する。
        def apply_reference_style(term, occurrences)
          style = reference_style
          main, sub = occurrences.partition { main_occurrence?(it) }
          return occurrences if main.empty?

          if style == 'main_only'
            @limited_reference_terms << term if sub.any?
            return main
          end

          limit = max_sub_references
          return occurrences if limit.zero? || sub.size <= limit

          @limited_reference_terms << term
          main + sub.first(limit)
        end

        def reference_style
          value = @index_config[:reference_style].to_s
          return value if REFERENCE_STYLES.include?(value)

          unless value.empty?
            Common.log_warn(
              "index.reference_style の値 '#{value}' は解釈できません（#{DEFAULT_REFERENCE_STYLE} として扱います）",
              detail: "指定できるのは #{REFERENCE_STYLES.join(' / ')} です"
            )
          end
          DEFAULT_REFERENCE_STYLE
        end

        # 0 は「無制限」。nil（未設定）は既定値
        def max_sub_references
          value = @index_config[:max_sub_references]
          value.nil? ? DEFAULT_MAX_SUB_REFERENCES : [value.to_i, 0].max
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
              <link rel="stylesheet" href="#{Common.asset_prefix}stylesheets/glossary.css">
              #{book_settings_link}
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

        # 中間 YAML（_index_matches.yml）から用語集バックリンクを読み込む
        # @return [Hash{String => Array<Hash>}] 用語名 → 出現箇所リスト
        def load_glossary_backlinks
          return {} unless File.exist?(Common::INDEX_MATCHES_FILE)

          data = YAML.load_file(Common::INDEX_MATCHES_FILE, permitted_classes: [Time, Symbol])
          data['glossary_backlinks'] || {}
        end

        # 用語集のバックリンクを構築
        def build_glossary_backlinks(term)
          sources = @glossary_backlinks[term['term']]
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
