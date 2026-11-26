# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/html_contract.rb
# ================================================================
# 責務:
#   契約 HTML（theme-contract-spec.md §2）の表。テーマの CSS が選んでよいクラス・属性・role を、
#   分類と水準つきで 1 か所に置く。仕様書の §2.2〜§2.5 は分類と決まりだけを定め、1 行ずつの
#   一覧はこの表を正典とする。テーマを作る人向けの一覧は `ruby scripts/html_contract_doc.rb` が
#   ここから書き出す。
#
# 水準（LEVELS）:
#   :guaranteed … 契約の版が同じ間は変えない
#   :theme      … テーマが theme.yml で宣言したクラス。そのテーマの中でだけ意味を持つ
#   :internal   … テーマは選ばない。後段の処理の目印で、予告なく変わる
#
# 付く段（stage）:
#   :contract … 契約 HTML（.cache/vs/build/html/）に付く
#   :target   … 出力先の変換（PDF・EPUB・Kindle の写し）が付ける。契約 HTML には現れないが、
#               テーマの CSS は選んでよい（body.vs-epub など）
#
# 表を直すときの決まり（§2.8）: 足すのは契約の版を上げずにできる。保証したものの名前を
# 変える・消すのは契約の版を上げるときだけ。
# ================================================================

require 'set'
require_relative 'common'

module VivlioStarter
  module CLI
    module HtmlContract
      LEVELS = {
        guaranteed: '保証',
        theme: 'テーマ',
        internal: '内部'
      }.freeze

      # 分類。順序は仕様書の節の順（§2.2 → §2.5）で、書き出す一覧もこの順に並ぶ
      CATEGORIES = {
        page_kind: { section: '2.2', label: 'ページの種類', added_by: 'BodyClassInjector・各ページの生成' },
        position: { section: '2.2', label: '位置', added_by: 'BodyClassInjector' },
        writing_mode: { section: '2.2', label: '組方向', added_by: 'BodyClassInjector（traits.vertical?）' },
        layout: { section: '2.2', label: 'レイアウト', added_by: 'BodyClassInjector（traits.fixed?）' },
        theme_option: { section: '2.2', label: 'テーマのオプション', added_by: 'BodyClassInjector（theme.yml の body_class）' },
        target: { section: '2.2', label: '出力先', added_by: '出力先の変換（L4）' },
        skeleton: { section: '2.3', label: '章の骨格', added_by: 'VFM・SectionWrapper' },
        heading: { section: '2.3', label: '見出しの印と章・節のリード', added_by: 'HeadingProcessor・前処理のコンテナ変換' },
        box: { section: '2.4', label: '囲み', added_by: '前処理のコンテナ変換' },
        arrangement: { section: '2.4', label: '並べ方', added_by: '前処理と後処理' },
        spacing: { section: '2.4', label: '位置と余白・改ページ', added_by: '前処理・置換の規則' },
        figure: { section: '2.4', label: '図と表', added_by: '後処理・生成資産' },
        code: { section: '2.4', label: 'コード', added_by: 'VFM と後処理' },
        footnote: { section: '2.4', label: '脚注', added_by: 'VFM と後処理' },
        reference: { section: '2.4', label: '参照', added_by: '相互参照・索引' },
        list: { section: '2.4', label: 'リスト', added_by: '前処理と後処理' },
        inline: { section: '2.4', label: '行内', added_by: '後処理' },
        talk: { section: '2.4', label: '会話', added_by: '前処理' },
        generated_page: { section: '2.4', label: '目次・索引・用語集・奥付・扉・権利ページ・全巻目次の部品',
                          added_by: '各ページの生成' },
        new_part: { section: '2.5', label: '2.0 で足す部品', added_by: '小説・絵本・動く絵本の段階（S8〜S10）' }
      }.freeze

      ClassEntry = Data.define(:name, :category, :level, :stage)

      # [分類, 水準, 段, クラスの並び]。並びは分類の中で読みやすい順に置く
      GROUPS = [
        [:page_kind, :guaranteed, :contract,
         %w[chapter appendix preface postface part-title toc titlepage legalpage colophon index-page glossary-page
            whole_toc]],
        [:position, :guaranteed, :contract, %w[chapter-first]],
        [:writing_mode, :guaranteed, :contract, %w[vs-vertical]],
        [:layout, :guaranteed, :contract, %w[vs-fixed]],
        [:target, :guaranteed, :target, %w[vs-epub vs-kindle]],

        [:skeleton, :guaranteed, :contract, %w[level1 level2 level3 level4 section-topic]],
        [:heading, :guaranteed, :contract,
         %w[vs-h-marker chapter-number chapter-title section-number section-title subsection-marker subsection-title
            chapter-lead section-lead]],
        [:heading, :guaranteed, :target, %w[vs-image-heading-epub vs-section-topic-epub]],
        [:heading, :internal, :target, %w[vs-image-heading-img]],

        [:box, :guaranteed, :contract,
         %w[memo tip note notice column output terminal diagram small references book-card book-info book-meta
            book-description book-title]],
        [:box, :guaranteed, :target, %w[vs-adm-label]],
        [:arrangement, :guaranteed, :contract,
         %w[side-by-side img-text img-text2 img-text3 text-img text2-img text3-img img-text-body pictures image-group
            sideimage sideimage-left sideimage-right sideimage-body text-table text-table-body text-table-table
            table-text table-text-body table-text-table rotate-table text-2dan gap-s gap-m gap-l clear-both
            clear-inline]],
        [:spacing, :guaranteed, :contract,
         %w[align-left align-center align-right align-top align-bottom text-left text-center text-right aki aki2
            vs-hspace pagebreak vs-break-page vs-break-recto vs-break-verso vs-break-merged]],
        [:figure, :guaranteed, :contract,
         %w[table-caption code-caption long-table cross-ref-figure vs-borderless vs-bordered vs-cropped vs-math-inline
            vs-math-display vs-mermaid vs-qr vs-showcase vs-emoji]],
        [:figure, :guaranteed, :target, %w[vs-rotate-table-image]],
        [:figure, :internal, :contract, %w[vs-math emoji vs-circled-number]],
        [:figure, :internal, :target, %w[vs-math-text vs-math-plain]],
        [:code, :guaranteed, :contract, %w[line-numbers line-numbers-rows codenum-elem]],
        [:code, :guaranteed, :target, %w[vs-code-line vs-code-ln vs-code-epub]],
        [:footnote, :guaranteed, :contract, %w[footnotes footnote-back page-footnote page-footnote-inline]],
        [:footnote, :guaranteed, :target, %w[vs-fn-num]],
        [:footnote, :internal, :contract, %w[footnote-ref page-footnote-print]],
        [:reference, :guaranteed, :contract,
         %w[cross-ref-link cross-ref-number cross-ref-other-volume pageref glossary-link glossary-backlink main-ref
            vs-sec-anchor frontmatter]],
        [:reference, :internal, :contract, %w[cross-ref-list cross-ref-table index-term]],
        [:reference, :internal, :target, %w[vs-epub-anchor vs-index-term vs-heading-anchor]],
        [:list, :guaranteed, :contract,
         %w[vs-fancy-list outline-list vs-list-decimal-paren2 vs-list-lower-alpha vs-list-lower-alpha-paren
            vs-list-lower-alpha-paren2 vs-list-upper-alpha vs-list-upper-alpha-paren vs-list-upper-alpha-paren2
            vs-list-lower-roman vs-list-lower-roman-paren vs-list-lower-roman-paren2 vs-list-upper-roman
            vs-list-upper-roman-paren vs-list-upper-roman-paren2 contains-task-list task-list-item def-list akakome
            aokome]],
        [:list, :guaranteed, :target, %w[vs-li-marker vs-task-mark]],
        [:inline, :guaranteed, :contract, %w[vs-nobr vs-inline-image strong-heading]],
        [:inline, :internal, :target, %w[vs-gaiji]],
        [:talk, :guaranteed, :contract,
         %w[talk talk-style-chat talk-style-inline talk-item talk-left talk-right talk-speaker talk-icon talk-name
            talk-name-off talk-body talk-sep]],
        [:generated_page, :guaranteed, :contract,
         %w[toc-title toc-label toc-chapter toc-chapter-appendix toc-chapter-no-number toc-preface toc-section toc-subsection
            whole-toc whole-toc-volume whole-toc-volume-name vs-current-volume whole-toc-preface whole-toc-part
            whole-toc-chapter whole-toc-appendix whole-toc-postface whole-toc-number whole-toc-sections
            whole-toc-section
            index index-section index-list sub-entry page-range resolved index-other-volume
            glossarypage glossary-title glossary-list glossary-list-items glossary-group-header glossary-term
            glossary-definition glossary-body glossary-text-line glossary-backlinks glossary-source glossary-h4
            glossary-h5 glossary-h6
            subtitle subtitle--wave subtitle--bar subtitle--none author series release-info publication-info
            info-list copyright powered-by disclaimer trademark twemoji-credit]],
        [:generated_page, :guaranteed, :target, %w[vs-index-item vs-index-items vs-index-refs]],
        [:new_part, :guaranteed, :contract, %w[tcy sesame vs-full-page vs-video vs-open-bracket]]
      ].freeze

      CLASSES = GROUPS.each_with_object({}) do |(category, level, stage, names), table|
        names.each do |name|
          raise ArgumentError, "契約 HTML の表でクラスが重なっています: #{name}" if table.key?(name)

          table[name] = ClassEntry.new(name:, category:, level:, stage:)
        end
      end.freeze

      # 名前の形で決まるクラス。表に 1 つずつ書けない（著者や言語の数だけある）もの
      #   language-* … VFM がコードの言語から付ける
      #   talk-c-*   … 会話の話者ごとの目印（talk-registry.rb の登録名から付く）
      PATTERNS = [
        [/\Alanguage-[\w+#-]+\z/, ClassEntry.new(name: 'language-*', category: :code, level: :guaranteed, stage: :contract)],
        [/\Atalk-c-[\w-]+\z/, ClassEntry.new(name: 'talk-c-*', category: :talk, level: :internal, stage: :contract)]
      ].freeze

      # Prism のトークン（span.token.*）。HTML では `token` と同じ要素に付いたクラスをすべて
      # トークンとみなす。CSS で選んでよいのは、ここに挙げた種類と `token` そのもの
      PRISM_TOKENS = %w[
        token atrule attr-name attr-value bold boolean builtin cdata char class-name codered comment constant deleted
        doctype entity function important inserted italic keyword namespace number operator prolog property
        punctuation regex selector string style symbol tag url variable
      ].to_set.freeze

      # ページの種類ごとの role と、付ける要素（§2.3）。RoleInjector と各ページの生成がこれを読む。
      # 扉・権利ページは付けない。全巻目次は §2.3 の表に無いので付けない
      PAGE_ROLES = {
        chapter: { role: 'doc-chapter', element: 'section.level1' },
        preface: { role: 'doc-preface', element: 'section.level1' },
        postface: { role: 'doc-afterword', element: 'section.level1' },
        appendix: { role: 'doc-appendix', element: 'section.level1' },
        part_title: { role: 'doc-part', element: 'section.level1' },
        colophon: { role: 'doc-colophon', element: 'section（奥付の中身を包む）' },
        indexpage: { role: 'doc-index', element: 'section.index' },
        toc: { role: 'doc-toc', element: 'nav' },
        glossarypage: { role: 'doc-glossary', element: 'section.glossarypage' }
      }.freeze

      # 保証する role の値。ページの role に、VFM の脚注の 2 つを足したもの
      GUARANTEED_ROLES = (PAGE_ROLES.values.map { it[:role] } + %w[doc-noteref doc-footnote]).freeze

      # 保証する属性。ここに無い data-* は内部（data-vs-* を含む）
      GUARANTEED_ATTRIBUTES = {
        'lang' => 'html に Common.book_language の値',
        'role' => 'GUARANTEED_ROLES の値',
        'id' => '見出しの id（値の形は内部）',
        'data-chapter-title' => '章扉の h1。章の題',
        'data-footnote-number' => '脚注の番号',
        'data-footnote-anchored' => '参照の直後に本体を置いた脚注の控え'
      }.freeze

      module_function

      # クラス名を表で引く。表にも名前の形にも無ければ nil。テーマのオプションのクラス（:theme_option）は、
      # 選ばれたテーマの theme.yml の body_class: から引く（theme-contract-spec.md §3.3）
      # @return [ClassEntry, nil]
      def lookup(name, config: Common::CONFIG)
        return CLASSES[name] if CLASSES.key?(name)
        if theme_option_classes(config).include?(name)
          return ClassEntry.new(name:, category: :theme_option, level: :theme, stage: :contract)
        end

        PATTERNS.find { |pattern, _| pattern.match?(name) }&.last
      end

      # 選ばれたテーマのオプションが body に付けるクラス（body_class: に書かれたものの全部）
      # @return [Array<String>]
      def theme_option_classes(config = Common::CONFIG)
        Theme.declared(config)&.options.to_a.flat_map(&:body_classes).uniq
      end

      # CSS が選んでよいクラスか。保証・テーマのクラスと、Prism のトークン
      def selectable?(name)
        return true if PRISM_TOKENS.include?(name)

        entry = lookup(name)
        !entry.nil? && entry.level != :internal
      end

      # HTML の要素に付いたクラスのうち、表に無いもの。Prism のトークンの要素は見ない
      # @param doc [Nokogiri::HTML5::Document]
      # @return [Set<String>]
      def unclassified_classes(doc)
        doc.css('[class]').each_with_object(Set.new) do |element, unknown|
          classes = element['class'].split
          next if classes.include?('token')

          classes.each { unknown << it unless lookup(it) }
        end
      end

      # CSS のセレクタが選ぶクラスの名前。コメント・url()・文字列を除き、宣言の中身を
      # 消してからセレクタの部分だけを見る（v2-inventory-report.md §8 の数え方）
      # @return [Array<String>]
      def css_classes(css)
        selectors_of(css).flat_map { it.scan(/\.(-?[A-Za-z_][\w-]*)/).flatten }.uniq
      end

      # CSS のセレクタが選ぶ data-* 属性の名前
      def css_data_attributes(css)
        selectors_of(css).flat_map { it.scan(/\[(data-[\w-]+)/).flatten }.uniq
      end

      # `{` の直前までの文字の並び（セレクタと at 規則の前置き）を集める。
      # `;` と `}` で区切りを捨てるので、宣言の中身はセレクタに混ざらない
      def selectors_of(css)
        text = css.gsub(%r{/\*.*?\*/}m, '')
                  .gsub(/url\([^)]*\)/, '')
                  .gsub(/"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'/, '""')
        text.scan(/([^{};]*)\{/).flatten
      end
    end
  end
end
