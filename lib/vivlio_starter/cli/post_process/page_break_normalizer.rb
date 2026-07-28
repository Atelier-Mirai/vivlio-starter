# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/post_process/page_break_normalizer.rb
# ================================================================
# 責務:
#   二重改ページ（著者が書いた改ページマーカーの直後に、CSS で自動改ページする
#   h2 が来る並び）を正規化し、空白ページが 1 枚挟まるのを防ぐ
#   （page-break-control-spec.md §2.1）。
#
# なぜ post_process なのか:
#   h2 の改ページは CSS 由来でマークアップには現れない。Markdown 段階では検出
#   できず、HTML ＋ 既知の CSS 規約に対して行うのが唯一確実な位置。
#
# 隣接判定が単純な兄弟比較で済まない理由:
#   VFM は h2 ごとに <section class="level2"> を作るため、`---` 由来の hr は
#   直前セクションの末尾要素、h2 は次セクションの先頭要素として離れた位置に置かれる。
#   さらに image スタイルでは SectionWrapper が h2 を <article class="section-topic">
#   で包む。そこで「文書順で次の内容要素」を、親を遡り・ラッパーを降りて探す。
#
# 正規化の 2 種類:
#   - hr.pagebreak / div.vs-break-page … マーカーを削除（h2 自身の改ページに一本化）
#   - div.vs-break-recto / :verso      … マーカーを残し h2 側を無効化（recto 指定が勝つ）
# ================================================================

require 'nokogiri'
require_relative '../common'
require_relative 'html_parser'

module VivlioStarter
  module CLI
    module PostProcessCommands
      # 二重改ページを正規化するモジュール。
      module PageBreakNormalizer
        module_function

        # 改ページを引き起こす著者由来のマーカー要素。
        BREAK_MARKERS = 'hr.pagebreak, div.vs-break-page, div.vs-break-recto, div.vs-break-verso'

        # recto/verso 指定へ合流した h2 に付ける印（CSS 側で改ページを打ち消す）。
        MERGED_CLASS = 'vs-break-merged'

        # 走査中に透過するラッパー要素（この中へ降りて最初の内容要素を探す）。
        WRAPPER_ELEMENTS = %w[section article div].freeze

        # 二重改ページを正規化してファイルへ書き戻す。
        # @param html_file [String] 対象 HTML のパス
        # @return [Integer] 正規化した件数
        def normalize!(html_file)
          # page.section_page_break: false なら h2 は改ページしない＝冗長性が消えるため何もしない
          return 0 unless section_page_break_enabled?

          doc = HtmlParser.parse_html_document(File.read(html_file, encoding: 'utf-8'))
          count = doc.css(BREAK_MARKERS).count { normalize_marker(it) }
          return 0 if count.zero?

          HtmlParser.save_html_document(html_file, doc)
          Common.log_info("#{html_file}: 冗長な改ページを #{count} 件正規化しました")
          count
        end

        # マーカー 1 つを見て、直後が h2 なら正規化する。
        # @return [Boolean] 正規化したか
        def normalize_marker(marker)
          following = next_content_element(marker)
          return false unless following&.name == 'h2'

          if recto_or_verso?(marker)
            # recto/verso 指定が勝つ。マーカーは残し、h2 側の改ページだけを無効化する。
            add_class(following, MERGED_CLASS)
          else
            # 単純改ページは h2 自身の改ページと重複するので、マーカーごと落とす。
            marker.remove
          end
          true
        end

        # 文書順で次に現れる「内容要素」を返す。
        # 次の兄弟が無ければ親を遡り、見つけた要素がラッパーならその中へ降りる。
        def next_content_element(node)
          current = node
          while current
            sibling = next_element_sibling(current)
            return descend_to_content(sibling) if sibling

            current = current.parent
            return nil unless current&.element?
          end
          nil
        end

        # 空白テキスト・コメントを飛ばして次の兄弟要素を返す。
        def next_element_sibling(node)
          sibling = node.next_sibling
          while sibling
            return sibling if sibling.element?
            return nil if sibling.text? && !sibling.text.strip.empty?

            sibling = sibling.next_sibling
          end
          nil
        end

        # ラッパー（section / article / div）なら、その中の最初の内容要素まで降りる。
        # 空のラッパーはそれ自体を内容要素として返す（h2 ではないので正規化されない）。
        def descend_to_content(element)
          node = element
          while WRAPPER_ELEMENTS.include?(node.name)
            child = first_content_child(node)
            return node unless child

            node = child
          end
          node
        end

        # 空白テキスト・コメントを飛ばして最初の子要素を返す。
        def first_content_child(node)
          child = node.children.find { it.element? || (it.text? && !it.text.strip.empty?) }
          child&.element? ? child : nil
        end

        def recto_or_verso?(marker)
          classes = marker['class'].to_s.split
          classes.include?('vs-break-recto') || classes.include?('vs-break-verso')
        end

        def add_class(element, name)
          classes = element['class'].to_s.split
          return if classes.include?(name)

          element['class'] = (classes + [name]).join(' ')
        end

        # 節（h2）で改ページする設定かどうか。BookSettingsCss と同じ判定
        # （明示的に false と書かれたときだけ無効）を用いる。
        def section_page_break_enabled?
          return true unless Common.configured?

          case Common::CONFIG.page.section_page_break.to_s.strip.downcase
          in 'false' | 'no' | 'off' | '0' then false
          else true
          end
        end
      end
    end
  end
end
