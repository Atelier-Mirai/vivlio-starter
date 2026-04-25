# frozen_string_literal: true

require 'nokogiri'
require_relative 'html_parser'

module Vivlio
  module Starter
    module CLI
      module PostProcessCommands
        # ================================================================
        # Module: FootnoteConverter
        # ----------------------------------------------------------------
        # 【役割】
        # - 章末脚注（endnotes）をページ脚注（page footnotes）に変換
        #
        # 【処理の流れ】
        # 1. section.footnotes 内の <li id="fnN"> を収集
        # 2. 戻りリンク/空段落を除去した内側HTMLを定義として保持
        # 3. footnotes セクションを削除
        # 4. 本文の参照アンカー直後に脚注を挿入
        #    - 画面用: <span class="page-footnote page-footnote-inline">
        #    - 印刷用: <aside class="page-footnote page-footnote-print">
        # 5. 未使用の定義は <body> 末尾に追加
        # 6. 定義のない参照は前方リンクから推測して補完
        # ================================================================
        module FootnoteConverter
          module_function

          # 章末脚注をページ脚注へ変換
          # @param html [String] HTML文字列
          # @return [String] 変換後のHTML文字列
          def convert_endnotes_to_page_footnotes!(html)
            doc = HtmlParser.parse_html_document(html)
            footnotes = doc.at_css('section.footnotes')
            return html unless footnotes

            definitions = extract_footnote_definitions(footnotes)
            footnotes.remove

            # footnote-anchor span 内の参照を使って、VFM が割り当てた実際のIDに
            # definitions のキーを正規化する（例: fn-url3 → fn4）
            normalize_definition_ids!(doc, definitions)

            insert_footnotes_for_references!(doc, definitions)
            append_unused_footnotes_to_body!(doc, definitions)
            fill_missing_footnote_references!(doc)

            HtmlParser.render_html_document(doc)
          end

          # section.footnotes 内の脚注定義を id => HTML として抽出する
          # @param footnotes_section [Nokogiri::XML::Element] footnotes section要素
          # @return [Hash<String, String>] 脚注ID => 内容のハッシュ
          def extract_footnote_definitions(footnotes_section)
            footnotes_section.css('li[id]').each_with_object({}) do |li, memo|
              fid = li['id']
              cleaned = li.dup
              # 戻りリンクを削除
              cleaned.css('a.footnote-back, a.footnote-backref').each(&:remove)
              # 空段落を削除
              cleaned.css('p').select { |p| p.text.strip.empty? }.each(&:remove)
              memo[fid] = cleaned.children.map(&:to_html).join.strip
            end
          end

          # 本文中の脚注参照アンカーへ定義を差し込む
          # @param doc [Nokogiri::HTML::Document] Nokogiriドキュメント
          # @param definitions [Hash<String, String>] 脚注定義
          def insert_footnotes_for_references!(doc, definitions)
            # DOM順序で脚注参照を処理するため、本文中の全参照アンカーを取得
            # expose_container_footnotes! が生成した非表示の footnote-anchor span 内の参照は
            # process_sideimage_footnotes! が別途処理するためスキップする
            doc.css('a.footnote-ref[href^="#fn"]').each do |anchor|
              next if anchor.ancestors('span.footnote-anchor').any?

              fid = anchor['href']&.delete_prefix('#')
              next unless fid
              next unless definitions.key?(fid)

              body = definitions[fid]
              insert_footnote_for_anchor!(doc, anchor, fid, body)
              definitions.delete(fid)
            end
          end

          # アンカー位置に応じてインライン/印刷脚注を挿入する
          # @param doc [Nokogiri::HTML::Document] Nokogiriドキュメント
          # @param anchor [Nokogiri::XML::Element] 脚注参照アンカー
          # @param fid [String] 脚注ID
          # @param body [String] 脚注本文HTML
          def insert_footnote_for_anchor!(doc, anchor, fid, body)
            if anchor.ancestors('p').any?
              # 段落内の参照の場合
              insert_inline_footnote!(doc, anchor, fid, body)
              insert_print_footnote_after_paragraph!(doc, anchor, fid, body)
            else
              # 段落外の参照の場合
              insert_print_footnote_after_anchor!(doc, anchor, fid, body)
            end
          end

          # インライン脚注 span を参照アンカー直後に挿入する
          # @param doc [Nokogiri::HTML::Document] Nokogiriドキュメント
          # @param anchor [Nokogiri::XML::Element] 脚注参照アンカー
          # @param fid [String] 脚注ID
          # @param body [String] 脚注本文HTML
          def insert_inline_footnote!(doc, anchor, fid, body)
            span = build_inline_footnote_node(doc, fid, body)
            anchor.add_next_sibling(span)
            adjust_following_whitespace(span)
          end

          # 段落内参照の場合、段落直後に印刷用脚注 aside を差し込む
          # sideimage コンテナ内の場合はコンテナの外に配置する
          # （Vivliostyle の float:footnote が sideimage 内で正しく動作しないため）
          # @param doc [Nokogiri::HTML::Document] Nokogiriドキュメント
          # @param anchor [Nokogiri::XML::Element] 脚注参照アンカー
          # @param fid [String] 脚注ID
          # @param body [String] 脚注本文HTML
          def insert_print_footnote_after_paragraph!(doc, anchor, fid, body)
            sideimage = find_sideimage_container(anchor)
            aside = build_print_footnote_node(doc, fid, body, endnote: !!sideimage)
            if sideimage
              # sideimage 内の脚注は所属する section の末尾に配置する
              # （Vivliostyle の float:footnote がページ境界で重複表示されるのを防ぐ）
              section = anchor.ancestors('section').first
              if section
                section.add_child("\n")
                section.add_child(aside)
              else
                sideimage.add_next_sibling("\n")
                sideimage.add_next_sibling(aside)
              end
            else
              para = anchor.ancestors('p').first
              if para
                insertion_point = find_last_print_footnote_sibling(para)
                insertion_point.add_next_sibling(aside)
              else
                anchor.add_next_sibling(aside)
              end
            end
            aside.add_next_sibling("\n")
          end

          def find_last_print_footnote_sibling(node)
            current = node
            while (sibling = current.next_sibling)
              break unless print_footnote_related_node?(sibling)

              current = sibling
            end
            current
          end

          def print_footnote_related_node?(node)
            return false unless node

            (node.text? && node.text.strip.empty?) ||
              (node.element? && node['class'].to_s.split.any? { |c| c == 'page-footnote' })
          end

          # 段落外参照の場合、アンカーの直後に印刷用脚注を配置する
          # sideimage コンテナ内の場合は section 末尾に配置する
          # @param doc [Nokogiri::HTML::Document] Nokogiriドキュメント
          # @param anchor [Nokogiri::XML::Element] 脚注参照アンカー
          # @param fid [String] 脚注ID
          # @param body [String] 脚注本文HTML
          def insert_print_footnote_after_anchor!(doc, anchor, fid, body)
            sideimage = find_sideimage_container(anchor)
            aside = build_print_footnote_node(doc, fid, body, endnote: !!sideimage)
            if sideimage
              section = anchor.ancestors('section').first
              if section
                section.add_child("\n")
                section.add_child(aside)
              else
                sideimage.add_next_sibling("\n")
                sideimage.add_next_sibling(aside)
              end
            else
              anchor.add_next_sibling("\n")
              anchor.add_next_sibling(aside)
            end
          end

          # sideimage のトップレベルコンテナ（div.sideimage-right 等）を探す
          # sideimage-body は除外し、sideimage / sideimage-right / sideimage-left のみ対象
          # @param node [Nokogiri::XML::Element] 起点ノード
          # @return [Nokogiri::XML::Element, nil] sideimage コンテナ、見つからなければ nil
          def find_sideimage_container(node)
            node.ancestors('div').find do |d|
              classes = d['class'].to_s.split
              (classes & %w[sideimage sideimage-right sideimage-left]).any?
            end
          end

          # 残った脚注定義を本文末尾の aside として追加する
          # 未使用の定義は sideimage 内の脚注（footnote-anchor 経由）であるため
          # endnote クラスを付与して float:footnote を無効化する
          # @param doc [Nokogiri::HTML::Document] Nokogiriドキュメント
          # @param definitions [Hash<String, String>] 未使用の脚注定義
          def append_unused_footnotes_to_body!(doc, definitions)
            return if definitions.empty?

            body_el = doc.at_css('body') || doc
            definitions.each do |fid, body|
              aside = build_print_footnote_node(doc, fid, body, endnote: true)
              body_el.add_child("\n")
              body_el.add_child(aside)
            end
          end

          # footnote-anchor span 内の参照を使って、definitions のキーを
          # VFM が割り当てた実際のIDに正規化する
          # 例: section.footnotes 内の fnurl3 は、footnote-anchor span 内の
          #     <a href="#fn4"> に対応するため、fnurl3 → fn4 に変換する
          # @param doc [Nokogiri::HTML::Document] Nokogiriドキュメント
          # @param definitions [Hash<String, String>] 脚注定義（破壊的に変更）
          def normalize_definition_ids!(doc, definitions)
            # footnote-anchor span 内の参照を DOM 順で収集
            anchor_refs = doc.css('span.footnote-anchor a.footnote-ref[href^="#fn"]')
                             .map { |a| a['href']&.delete_prefix('#') }
                             .compact
            return if anchor_refs.empty?

            # footnote-anchor span 内の参照に対応する定義IDのみを対象とする
            # （fn-urlN または fnurlN 形式のキーのみ）
            url_keys = definitions.keys.select { |k| k.match?(/\Afn-?url\d+\z/) }
            return if url_keys.empty?
            return if url_keys.size != anchor_refs.size

            url_keys.zip(anchor_refs).each do |old_id, new_id|
              next if old_id == new_id || new_id.nil?

              definitions[new_id] = definitions.delete(old_id)
            end
          end

          # footnote-anchor 内の参照と未使用定義を対応付けるマップを構築する（廃止予定）
          def build_anchor_ref_map(doc, definitions)
            {}
          end

          # 定義が存在しない脚注参照を前方リンクから推測して補完する
          # @param doc [Nokogiri::HTML::Document] Nokogiriドキュメント
          def fill_missing_footnote_references!(doc)
            doc.css('a.footnote-ref[href^="#fn"]').each do |anchor|
              # expose_container_footnotes! が生成した非表示参照はスキップする
              next if anchor.ancestors('span.footnote-anchor').any?

              fid = anchor['href']&.delete_prefix('#')
              next unless fid
              next if doc.at_css(%(##{fid}))

              body = inferred_body_from_previous_link(anchor)
              next unless body

              if anchor.ancestors('p').any?
                insert_inline_footnote!(doc, anchor, fid, body)
                insert_print_footnote_after_paragraph!(doc, anchor, fid, body)
              else
                insert_print_footnote_after_anchor!(doc, anchor, fid, body)
              end
            end
          end

          # 脚注参照直前のリンク要素から本文 HTML を推定する。
          # 内部リンク（#fn... など）は脚注本文として不適切なため除外する。
          # @param anchor [Nokogiri::XML::Element] 脚注参照アンカー
          # @return [String, nil] 推定された脚注本文HTML
          def inferred_body_from_previous_link(anchor)
            prev_link = anchor.previous_element
            prev_link = prev_link.previous_element while prev_link && prev_link.name != 'a'
            url = prev_link&.[]('href')
            # http(s):// で始まる外部URLのみを対象とし、内部リンク（#fn...）は除外する
            return unless url&.match?(/\Ahttps?:\/\//)

            %(<a href="#{url}">#{url}</a>)
          end

          # インライン脚注用の span ノードを生成する
          # @param doc [Nokogiri::HTML::Document] Nokogiriドキュメント
          # @param fid [String] 脚注ID
          # @param body [String] 脚注本文HTML
          # @return [Nokogiri::XML::Element] span要素
          def build_inline_footnote_node(doc, fid, body)
            span = Nokogiri::XML::Node.new('span', doc)
            span['role'] = 'doc-footnote'
            span['class'] = 'page-footnote page-footnote-inline'
            span['id'] = fid
            span.inner_html = body
            span
          end

          # 印刷用脚注の aside ノードを生成する
          # @param doc [Nokogiri::HTML::Document] Nokogiriドキュメント
          # @param fid [String] 脚注ID
          # @param body [String] 脚注本文HTML
          # @param endnote [Boolean] true の場合 page-footnote-endnote クラスを追加
          # @return [Nokogiri::XML::Element] aside要素
          def build_print_footnote_node(doc, fid, body, endnote: false)
            aside = Nokogiri::XML::Node.new('aside', doc)
            aside['role'] = 'doc-footnote'
            classes = 'page-footnote page-footnote-print'
            classes += ' page-footnote-endnote' if endnote
            aside['class'] = classes
            aside['id'] = fid
            # IDから脚注番号を抽出（例: fn5 -> 5, fnurl1 -> url1）
            footnote_number = fid.sub(/^fn/, '')
            aside['data-footnote-number'] = footnote_number
            aside.inner_html = body
            aside
          end

          # インライン脚注後の空白をノーブレークスペースへ変換する
          # @param node [Nokogiri::XML::Element] 脚注ノード
          def adjust_following_whitespace(node)
            following = node.next_sibling
            return unless following&.text?

            text = following.text
            following.content = " #{text.lstrip}" if text.start_with?(' ')
          end
        end
      end
    end
  end
end
