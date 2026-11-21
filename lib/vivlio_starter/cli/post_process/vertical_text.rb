# frozen_string_literal: true

require_relative 'html_parser'

module VivlioStarter
  module CLI
    module PostProcessCommands
      # ================================================================
      # Module: VerticalText
      # ----------------------------------------------------------------
      # 【役割】
      # 縦書きの本の契約 HTML に、縦書きで要る印を付ける（L3 の後処理の一段。条件は traits.vertical?）。
      #
      # 1. 縦中横の自動（novel-vertical-spec.md §5.3）: 半角の数字 1〜2 桁と、半角の `!?`・`?!`・`!!`・`??`
      #    （ちょうど 2 字）を `span.tcy` で包む。縦の行の中で 1 字分の幅に横に並べて立てる
      # 2. 括弧の段落の印（同 §6.1）: 開き括弧で始まる段落に `vs-open-bracket` を付ける。テーマが
      #    字下げを 0 にする（開き括弧の字は上半分が空いているので、見た目は二分下げになる）
      #
      # 【対象にしない場所】
      # コード・数式・ルビの読み・`span.tcy` の中・URL を字にしたリンク・横組みの箱として置く部品
      # （parts/vertical.css と同じ並び）・奥付と権利ページ（横に組むページ）。見出しは対象にする。
      # 3 桁以上の数字は包まない（横倒しのまま組まれる。小説の lint が書き換えを勧める）。
      # 全角の数字・全角の「！」「？」・半角の英字には触れない。
      # ================================================================
      module VerticalText
        TCY_CLASS = 'tcy'
        OPEN_BRACKET_CLASS = 'vs-open-bracket'

        # 前後が半角の英数字・小数点・桁区切りでない数字 1〜2 桁と、ちょうど 2 字の感嘆符と疑問符
        TCY_PATTERN = /(?<![0-9A-Za-z.,])[0-9]{1,2}(?![0-9A-Za-z.,])|(?<![!?])(?:!\?|\?!|!!|\?\?)(?![!?])/

        # 開き括弧（novel-vertical-spec.md §6.1 の表）
        OPEN_BRACKETS = %w[「 『 （ 〈 《 【 〔].freeze

        # 横に組むページの種類（body のクラス）。奥付と権利ページ（§2.2）
        HORIZONTAL_PAGES = %w[colophon legalpage].freeze

        # この中の字には触れない要素（CSS の選択子。祖先にあれば飛ばす）
        SKIP_ANCESTORS = [
          'code', 'pre', 'kbd', 'samp', 'script', 'style', 'rt', 'rp', 'svg', 'math',
          ".#{TCY_CLASS}", '.vs-math',
          # 横組みの箱（stylesheets/parts/vertical.css）
          'figure', 'table', '.long-table', '.cross-ref-table', '.cross-ref-list',
          '.memo', '.tip', '.note', '.notice', '.column', '.output', '.terminal', '.diagram'
        ].join(', ').freeze

        # URL を字にしたリンク（`<https://…>` やリンクの字が URL のもの）の字
        URL_TEXT = %r{\A\s*(?:https?://|www\.)}

        module_function

        # @param html_file [String] HTML ファイルのパス
        # @return [Boolean] 書き換えたか
        def mark!(html_file)
          doc = HtmlParser.parse_html_document(File.read(html_file, encoding: 'utf-8'))
          return false if horizontal_page?(doc)

          changed = [wrap_tcy!(doc.at('body')), mark_open_brackets!(doc)].any?
          HtmlParser.save_html_document(html_file, doc) if changed
          changed
        end

        # @param doc [Nokogiri::HTML5::Document]
        def horizontal_page?(doc) = doc.at('body')&.[]('class').to_s.split.intersect?(HORIZONTAL_PAGES)

        # 縦中横の自動。目次の生成（TocCommands）も同じものを呼ぶ
        # @param root [Nokogiri::XML::Node, nil] この下の字を対象にする
        # @return [Boolean] 包んだか
        def wrap_tcy!(root)
          return false unless root

          nodes = root.xpath('.//text()').select { it.content.match?(TCY_PATTERN) && !skipped?(it) }
          nodes.each { wrap_text_node!(it) }
          !nodes.empty?
        end

        def skipped?(text_node)
          parent = text_node.parent
          return true if parent.ancestors.any? { it.element? && it.matches?(SKIP_ANCESTORS) } || parent.matches?(SKIP_ANCESTORS)

          link = text_node.ancestors('a').first
          !link.nil? && link.text.match?(URL_TEXT)
        end

        # 字の並びを、包む字と包まない字に分けて置き換える
        def wrap_text_node!(text_node)
          doc = text_node.document
          fragment = Nokogiri::XML::NodeSet.new(doc)
          rest = text_node.content
          while (match = TCY_PATTERN.match(rest))
            fragment << doc.create_text_node(match.pre_match) unless match.pre_match.empty?
            span = doc.create_element('span', class: TCY_CLASS)
            span.content = match[0]
            fragment << span
            rest = match.post_match
          end
          fragment << doc.create_text_node(rest) unless rest.empty?
          text_node.replace(fragment)
        end

        # 開き括弧で始まる段落に印を付ける（横組みの箱の中は除く）
        # @return [Boolean] 付けたか
        def mark_open_brackets!(doc)
          marked = doc.css('body p').select do |p|
            next false if p.ancestors.any? { it.element? && it.matches?(SKIP_ANCESTORS) }

            OPEN_BRACKETS.include?(p.text.lstrip[0]) && !p['class'].to_s.split.include?(OPEN_BRACKET_CLASS)
          end
          marked.each { it['class'] = [*it['class'].to_s.split, OPEN_BRACKET_CLASS].join(' ') }
          !marked.empty?
        end
      end
    end
  end
end
