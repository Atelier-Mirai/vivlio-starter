# frozen_string_literal: true

require_relative '../common'
require_relative 'html_parser'

module VivlioStarter
  module CLI
    module PostProcessCommands
      # ================================================================
      # Module: SectionWrapper
      # ----------------------------------------------------------------
      # 【役割】
      # - theme.style: image のとき、section.level2 内の h2 を
      #   <article class="section-topic"> でラップ
      #
      # 【処理内容】
      # - <section class="level2"> の直下にある <h2> を検出
      # - 直後にある .section-lead も一緒にラップ（存在すれば）
      # - CSS グリッドの対象構造を整える
      # ================================================================
      module SectionWrapper
        module_function

        # theme.style が image の場合に、章セクションの見出しをラップ
        # @param html [String] HTML文字列
        # @return [String] 変換後のHTML文字列
        def wrap_h2_with_article_if_image_style!(html)
          return html unless Common::CONFIG.theme.style == 'image'

          doc = HtmlParser.parse_html_document(html)
          transformed = wrap_sections_with_article!(doc)
          transformed ? HtmlParser.render_html_document(doc) : html
        end

        # section.level2 直下の h2 を article.section-topic でラップする
        # @param doc [Nokogiri::HTML::Document] Nokogiriドキュメント
        # @return [Boolean] 変更があったかどうか
        def wrap_sections_with_article!(doc)
          changed = false
          doc.css('section.level2').each do |section|
            h2 = section.at_css('> h2')
            next unless h2 && h2.ancestors('article.section-topic').empty?

            lead = find_section_lead_for(h2)
            wrap_with_article(section, h2, lead)
            changed = true
          end
          changed
        end

        # h2 に続く .section-lead ノードを探索して返す
        # @param h2 [Nokogiri::XML::Element] h2要素
        # @return [Nokogiri::XML::Element, nil] section-lead要素またはnil
        def find_section_lead_for(h2)
          node = h2.next_sibling
          while node
            return node if node.element? && (node['class']&.split || []).include?('section-lead')

            # ゼロ幅文字のみの段落はスキップ
            if node.element? && node.name == 'p' && HtmlParser.zero_width_text?(node.text)
              node = node.next_sibling
              next
            end

            node = node.element? ? nil : node.next_sibling
          end
          nil
        end

        # h2 と（存在すれば）section-lead を article.section-topic で包む
        # @param section [Nokogiri::XML::Element] section要素
        # @param h2 [Nokogiri::XML::Element] h2要素
        # @param lead [Nokogiri::XML::Element, nil] section-lead要素
        def wrap_with_article(section, h2, lead)
          article = Nokogiri::XML::Node.new('article', section.document)
          article['class'] = 'section-topic'
          h2.add_previous_sibling("\n")
          h2.add_previous_sibling(article)
          article.add_child(h2)
          return unless lead

          article.add_child("\n")
          article.add_child(lead)
        end
      end
    end
  end
end
