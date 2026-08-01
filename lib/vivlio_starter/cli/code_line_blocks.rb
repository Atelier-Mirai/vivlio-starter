# frozen_string_literal: true

require 'nokogiri'

module VivlioStarter
  module CLI
    # ================================================================
    # File: lib/vivlio_starter/cli/code_line_blocks.rb
    # ================================================================
    # 責務:
    #   Prism 済みコードブロック（<pre><code>）の中身を「1 論理行 = 1 断片」へ
    #   割る唯一の実装。トークン span が行を跨いでも各行で開き直して色を保つ。
    #
    # なぜ共有なのか:
    #   行番号を論理行に正しく対応させるには、絶対配置ガターではなく
    #   「1 論理行 = 1 ブロック要素＋ぶら下げインデント」が要る（F 案）。
    #   これは EPUB/Kindle だけの要求ではなく PDF も同じで、実際 PDF では
    #   長行の折返しで番号がずれていた（epub-code-line-numbers-spec.md §0 は
    #   「PDF はページ幅固定のため崩れない」としていたが、code.css が全 pre に
    #   white-space: pre-wrap を掛けているため前提が成り立っていなかった）。
    #   分割の意味論を 2 度実装しないための正典（notation-implementation-guide.md §2）。
    #
    # 使い分け（容器の作りは利用側の責務）:
    #   - EPUB/Kindle: pre を div.vs-code-epub > div.vs-code-line へ置換（EpubBuilder）
    #   - PDF:         pre を保ったまま code の中身を span.vs-code-line へ組み直す（PdfBuilder）
    # ================================================================
    module CodeLineBlocks
      module_function

      # <code> の中身を論理行ごとの HTML 断片へ割る。
      # @param code [Nokogiri::XML::Element] pre 内の code 要素
      # @return [Array<String>] 1 要素 = 1 論理行の HTML 断片
      def split(code)
        lines = [+'']
        collect_fragments(code, lines, [])
        lines.pop if lines.size > 1 && lines.last.empty? # 末尾改行由来の空行を除く
        lines
      end

      # ノードを再帰走査し、テキストの改行で行を分割しながら、祖先のトークン span を
      # 各行で開き直して HTML 断片を組み立てる。
      #
      # @param node [Nokogiri::XML::Node] 走査中のノード
      # @param lines [Array<String>] 構築中の行配列（破壊的に追記）
      # @param open_tags [Array<String>] 現在開いている span 開始タグ（行跨ぎ復元用）
      def collect_fragments(node, lines, open_tags)
        node.children.each do |child|
          if child.text?
            append_text_with_newlines(child.content, lines, open_tags)
          elsif child.element? && child.name == 'span'
            open_tag = span_open_tag(child)
            lines[-1] << open_tag
            open_tags.push(open_tag)
            collect_fragments(child, lines, open_tags)
            open_tags.pop
            lines[-1] << '</span>'
          else
            lines[-1] << child.to_html
          end
        end
      end

      # テキストを改行で分割して各行へ積む。改行ごとに、開いている span を閉じてから
      # 改行し、次行の冒頭で同じ span を開き直す（トークンの行跨ぎを保つ）。
      def append_text_with_newlines(text, lines, open_tags)
        segments = text.split("\n", -1)
        segments.each_with_index do |segment, idx|
          lines[-1] << escape_html_text(segment)
          next if idx == segments.length - 1

          open_tags.reverse_each { lines[-1] << '</span>' }
          lines.push(+open_tags.join)
        end
      end

      # span 要素の開始タグ（属性つき）を組み立てる。
      def span_open_tag(span)
        attrs = span.attribute_nodes.map { %( #{it.name}="#{escape_attr(it.value)}") }.join
        "<span#{attrs}>"
      end

      # コードテキストの HTML エスケープ。
      def escape_html_text(str) = str.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;')

      # span 属性値の HTML エスケープ（開始タグ再構成用）。
      def escape_attr(str) = escape_html_text(str).gsub('"', '&quot;')
    end
  end
end
