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
        # 見出しに語を掲げた節がこれより多い語は、主要参照の章の外の `###` を省く（R3）。
        # 実測で Canvas（11 節）と関数（15〜16 節）の間に引いた線。設定にしないのは、厚い本（spiral-ruby・3 巻）でも
        # 12 で足り、上げると関数のようなふつうの言葉が絞られなくなるため（R4・§7.3）
        MAIN_CHAPTER_ONLY_OVER = 12

        attr_reader :index_data, :limited_reference_terms

        # @param other_volume_guides [Hash{String => String}] 主要参照が別の巻にある語の案内（OtherVolumeMain.guides）
        def initialize(glossary_config: {}, index_config: nil, other_volume_guides: {})
          @index_data = {}
          @other_volume_guides = other_volume_guides
          @glossary_config = glossary_config
          @index_config = index_config || Common::CONFIG.index.to_h
          @glossary_backlinks = {}
          # 間引いた語（no silent caps: 絞ったことは呼び出し元から必ず報告する）
          @limited_reference_terms = []
          # 見出しに出る節が多すぎて、主要参照の章の外の `###` を省いた語（R7 で名前を挙げる）
          @main_chapter_only_terms = []
          # 語 → 選んだ参照。索引と用語集が同じ選び方を一度だけ通す（R8）
          @selected_references = {}
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
          # 索引にも載る語は、索引の項目と同じ参照を並べる（R8）。索引を組んだ後なら読み込み済み
          load_index_data! if @index_data.empty? && File.exist?(Common::INDEX_MATCHES_FILE)

          sorted_terms = terms.sort_by { yomi_order(it['yomi'] || it['term']) }
          html = generate_glossary_html(sorted_terms)
          FileUtils.mkdir_p(File.dirname(GLOSSARY_OUTPUT_FILE))
          File.write(GLOSSARY_OUTPUT_FILE, html, encoding: 'utf-8')
          Common.log_success("用語集ページを生成しました: #{GLOSSARY_OUTPUT_FILE}")
          GLOSSARY_OUTPUT_FILE
        end

        # 参照を絞った事実。呼び出し元が必ず報告する（no silent caps・R6）。
        # main_chapter_only は、見出しに出る節が多すぎて、主要参照の章の外の `###` を省いた語
        Limitation = Data.define(:style, :limit, :terms, :main_chapter_only) do
          def any? = terms.any?
          def size = terms.size
        end

        def reference_limitation
          Limitation.new(style: reference_style, limit: max_sub_references, terms: @limited_reference_terms,
                         main_chapter_only: @main_chapter_only_terms)
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
            <html lang="#{Common.book_language}">
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
            yomi_order((occurrences.first['yomi'] || occurrences.first[:yomi]).to_s)
          end
        end

        # 読みの並べ順。英字の大文字と小文字を区別しない（辞書の並び）。文字コードのまま
        # 比べると大文字が小文字より先に来て、K の行が「KPF → Kindle」になっていた（改善案 #99）。
        # 大文字・小文字だけが違う読みは、元の読みで並べて順番を毎回同じにする
        def yomi_order(yomi) = [yomi.to_s.downcase, yomi.to_s]

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
          occurrences = highlight ? selected_references(term) : @index_data[term].to_a

          links = occurrences.map do |occ|
            link = occ['link'] || occ[:link]
            classes = []
            classes << 'main-ref' if highlight && main_occurrence?(occ)
            classes << 'frontmatter' if frontmatter_link?(link)
            attr = classes.empty? ? '' : %( class="#{classes.join(' ')}")
            %(<a href="#{link}"#{attr}></a>)
          end.join
          guide = highlight && other_volume_guide(term)
          guide ? "#{links}#{other_volume_guide_html(guide)}" : links
        end

        # 案内は、この巻のページ番号の後ろに、ほかの参照と同じく「,」で区切って置く。
        # 先頭に置くと、すぐ後ろのページ番号が別の巻のページに読める（「下巻 付録 E 4」）。
        # 「→」を付けると、直前のページの続きが別の巻にあるように読める。
        # 太字は主要参照と同じ「ここに説明がある」の印。CSS でなく <strong> で付ける
        # ——本の index.css は雛形を写したもので、vs upgrade するまで新しい規則が届かない。
        # 区切りの「,」は、PDF では最後の <a> に付く CSS が、範囲を畳んだ索引と EPUB では文字が受け持つ
        def other_volume_guide_html(guide)
          %(<span class="index-other-volume"><strong>#{CGI.escapeHTML(guide)}</strong></span>)
        end

        # 主要参照が別の巻にあり、組む巻には主要参照の出現が無い語の案内（index-other-volume-main-spec.md R1）。
        # 組む巻に主要参照があれば、そちらが案内になるので添えない
        def other_volume_guide(term)
          guide = @other_volume_guides[term] or return nil
          @index_data[term].to_a.any? { main_occurrence?(it) } ? nil : guide
        end

        # 前書きの原稿の basename。前書きのページはノンブルの体裁が違うので、索引の参照に印を付ける。
        # 前書きは catalog.yml の PREFACE で決まり、`00-preface` に限らない（catalog-section-kind-spec.md §2.1）
        def preface_basenames
          @preface_basenames ||= TokenResolver::Resolver.new.resolve.select { it.kind == :preface }.map(&:basename)
        end

        def frontmatter_link?(link) = preface_basenames.include?(link.to_s[/\A[^#]+?(?=\.html|#|\z)/])

        # 主要参照を先頭へ並べ、副次参照を選んだ参照。`all` 以外の索引と用語集が使う。
        # 選び方は一つの関数を通し、二重に持たない（R8）。覚えておくのは、用語集で
        # もう一度選んだときに、絞った語を二重に数えないため
        def selected_references(term)
          @selected_references[term] ||= apply_reference_style(term, order_occurrences(@index_data[term]))
        end

        # 主要参照を先頭へ。同種のなかでは元の走査順（章順）を保つ。
        def order_occurrences(occurrences)
          occurrences.to_a.partition { main_occurrence?(it) }.flatten(1)
        end

        def main_occurrence?(occ) = (occ['is_main'] || occ[:is_main]) ? true : false

        # 副次参照を選ぶ（index-sub-reference-selection-spec.md R1〜R5）。`all` は呼び出し側で分岐済み。
        #
        # 載せるのは、索引を引く手間に見合う所——語を見出しに掲げた節だけである。
        # 名前が出ているだけの所と、別の話題の中の一文ほどの説明は載せない。
        #
        # **主要参照が無い語は間引かない。** 「まずここを読めばよい」を示せないまま
        # 出現箇所だけ削ると、語が索引から実質消える——絞り込みは主要参照という
        # 代替の案内があってはじめて成立する。
        #
        # 主要参照が別の巻にある語は、巻の名前で案内するので、主要参照のある語と同じく絞る
        # （index-other-volume-main-spec.md R2）。`main_only` なら案内だけを載せる。
        def apply_reference_style(term, occurrences)
          main, sub = occurrences.partition { main_occurrence?(it) }
          return occurrences if main.empty? && !other_volume_guide(term)

          if reference_style == 'main_only'
            @limited_reference_terms << term if sub.any?
            return main
          end

          # --- Phase: 見出しに語を掲げた節の、最初の出現（R1・R2） ---
          selected = first_of_headed_sections(main, sub)

          # --- Phase: 多すぎる語は、主要参照の章の外の `###` を省く（R3） ---
          selected = main_chapter_sections(term, main, sub, selected)

          # --- Phase: 上限と章をまたぐ公平さ（R5） ---
          limit = max_sub_references
          selected = trim_across_chapters(selected, limit) unless limit.zero? || selected.size <= limit

          @limited_reference_terms << term if selected.size < sub.size
          main + selected
        end

        # 読者は索引から節へ飛び、その節を読む。同じ節の 2 回目以降の出現は同じ所を指すだけなので、
        # 節の入り口の 1 件で足りる。主要参照の節は主要参照が入り口を受け持つ。
        # `##` の見出しが語を掲げていれば、その `##` 全体を 1 節とする（R2 改訂）——「## 課題33　素数」の下の
        # 「### 解説」「### 勘所」は同じまとまりの続きで、読者は `##` の頭から読み進める
        def first_of_headed_sections(main, sub)
          taken = main.to_set { unit_key(it) }
          sub.select { headed?(it) && taken.add?(unit_key(it)) }
        end

        def unit_key(occ) = [occurrence_chapter(occ), occ['h2'] || occ[:h2] || section_of(occ)]
        def section_key(occ) = [occurrence_chapter(occ), section_of(occ)]
        def section_of(occ) = occ['section'] || occ[:section]
        def headed?(occ) = occ['headed'] || occ[:headed]
        def headed_by_h2?(occ) = !(occ['h2'] || occ[:h2]).nil?

        # ふつうの言葉（関数・状態）は作例の見出しにも出て、語を使っているだけの節まで選んでしまう。
        # 語を説明している節は主要参照の章に集まるので、節が多すぎる語は、主要参照の章の外の `###` を省く（R3）。
        #
        # 多すぎるかは `##` でまとめる前の `###` ごとの数で見る。まとめた後で数えると、関数（15 節 → 11 節）が
        # 12 を下回って作例の見出しが戻る。省くのは `###` だけで、`##` の見出しに語を掲げた節は章の外でも残す
        # ——`##` の見出しに語があるのは、その語を主題にしたまとまり（「## 課題33　素数」）だから（R3 改訂・§7.3）。
        # 主要参照の章は辞書の `main:` で確定したもの——`main?` の推測は、ふつうの言葉ほど外れる。
        # 主要参照が別の巻にある語は、この巻の `###` が残らず、`##` の節と巻の名前の案内になる
        def main_chapter_sections(term, main, sub, selected)
          return selected if headed_section_count(main, sub) <= MAIN_CHAPTER_ONLY_OVER

          chapters = main.to_set { occurrence_chapter(it) }
          kept = selected.select { chapters.include?(occurrence_chapter(it)) || headed_by_h2?(it) }
          @main_chapter_only_terms << term if kept.size < selected.size
          kept
        end

        # 見出しに語を掲げた `###` ごとの節の数（主要参照の節を除く）。R3 の判定に使う
        def headed_section_count(main, sub)
          taken = main.to_set { section_key(it) }
          sub.count { headed?(it) && taken.add?(section_key(it)) }
        end

        # 上限に収める。**章をまたいで公平に**残すのが要点。
        #
        # 上限は出現回数で数えるので（ページ番号は組版が決めるため Ruby からは
        # 見えない）、先頭から機械的に切ると 1 つの章に集中した語が他の章を丸ごと
        # 押し出す。実測: CMYK が 43 章で 12 回出るようになった途端、44 章の 1 件
        # （p.292）が 8 件の枠から溢れて索引から消えた——読者からは「44 章にも
        # 出てくるのに索引から辿れない」ことになる。
        # まず章ごとに 1 件ずつ拾い、余った枠を先頭から埋める。並びは元のまま返す
        # ——ページ番号は組版が振るので、ここで順序を変えると昇順が崩れる。
        def trim_across_chapters(sub, limit)
          # `it` は 2 引数で呼ばれるブロックの第 1 引数しか受けないので、
          # each_with_index との組み合わせでは添字が落ちる。明示的に受ける。
          position = sub.each_with_index.to_h { |occ, i| [occ.object_id, i] }
          first_of_each = sub.group_by { occurrence_chapter(it) }.values.map(&:first).first(limit)
          fill = (sub - first_of_each).first(limit - first_of_each.size)
          (first_of_each + fill).sort_by { position[it.object_id] }
        end

        def occurrence_chapter(occ) = (occ['link'] || occ[:link]).to_s[/\A[^#]+/]

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
          title = @glossary_config[:title]

          <<~HTML
            <!DOCTYPE html>
            <html lang="#{Common.book_language}">
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

        # 用語集のバックリンクを構築。
        # 索引にも載る語は、索引の項目と同じ所を指す（R8）。用語集の説明を読んだ読者が次に
        # 知りたいのは本文で詳しく扱っている所で、索引で選んだ所と同じ理由で同じ所が答えになる。
        # 用語集だけの語・主要参照の無い語・`all` は、章ごとの初出（† の位置）を並べる
        def build_glossary_backlinks(term)
          index_backlinks(term['term'], term['flags']) || chapter_backlinks(term['term'])
        end

        # 索引の項目と同じ参照。並びも太字も別の巻の案内も索引にそろえる。
        # 太字はクラスで付ける——<strong> でくくると、区切りの「,」を付ける
        # `.glossary-backlink + .glossary-backlink` が主要参照の直後で効かなくなる。
        # 案内の手前の「,」は文字で持つ。用語集の CSS は次のリンクの ::before で区切るので、
        # 案内の手前には付かない（古い glossary.css のままの本でも同じに組める）
        # @return [String, nil] 索引の参照を使わない語なら nil
        def index_backlinks(name, flags)
          return nil unless flags.to_s.include?('i') && @index_data.key?(name)
          return nil if reference_style == 'all'
          return nil if @index_data[name].none? { main_occurrence?(it) } && !other_volume_guide(name)

          links = selected_references(name).map do |occ|
            link = occ['link'] || occ[:link]
            classes = ['glossary-backlink']
            classes << 'main-ref' if main_occurrence?(occ)
            classes << 'frontmatter' if frontmatter_link?(link)
            %(<a href="#{link}" class="#{classes.join(' ')}"></a>)
          end
          guide = other_volume_guide(name)
          tail = guide ? "#{', ' if links.any?}#{other_volume_guide_html(guide)}" : ''
          # リンクの間に空白を置かない。区切りの「, 」は CSS の ::before が付けるので、
          # 空白があると「935 , 843」と、コンマの前にも空いてしまう（索引の側と同じつなぎ方）
          %(<p class="glossary-backlinks">#{links.join}#{tail}</p>)
        end

        # 章ごとの初出（† の位置）を章の順に並べる
        def chapter_backlinks(name)
          sources = @glossary_backlinks[name]
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
            classes << 'frontmatter' if preface_basenames.include?(chapter.to_s)

            %(<a href="#{chapter}.html##{anchor_id}" class="#{classes.join(' ')}"></a>)
          end

          # 空白でつながない理由は index_backlinks と同じ
          <<~HTML.chomp
            <p class="glossary-backlinks">#{links.join}</p>
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
