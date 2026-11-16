# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/build/transforms/kindle/layout_index_columns.rb
# ================================================================
# 責務:
#   索引を 2 列に組む
# ================================================================

require_relative '../context'

module VivlioStarter
  module CLI
    module Build
      # 索引を 2 列に組む
      module Transforms::Kindle::LayoutIndexColumns
        module_function

        # 索引の語を、横に 2 つずつ並ぶ形へ組み替える（Kindle 限定）。
        #
        # KFX は `columns` を解さないので、PDF の 2 段組みは 1 列に潰れ、語とページ番号が別の行へ
        # 分かれて画面の右半分が空く。表にすれば 2 列に組めるが、KFX の表は一度拡大しないと
        # リンクをたどれず、索引の役目を果たさない。float は横に並ばなかった。
        # `inline-block` の幅なら文字のリンクのまま 2 列になる（Previewer の画面で確かめた）。
        #
        # 並びは行ごとに左・右とする。リフローではページの高さが読者の設定で変わるので、
        # 左の段を下まで埋めてから右の段へ移る組み方はできない。節の中だけ縦に並べると、
        # 節がページをまたいだときに語の順が飛ぶ。
        #
        # @param doc [Nokogiri::HTML5::Document] 1 ページの HTML（破壊的に書き換える）
        # @param ctx [Transforms::Context]
        def call(doc, ctx)
          return unless File.basename(ctx.path, '.html') == '_indexpage'

          lists = doc.css('div.index-section dl.index-list')
          return if lists.empty?

          lists.each { it.replace(doc.fragment(index_items_html(it))) }
          Common.log_info('[EPUB] 索引を 2 列に組み替えました')
        end

        # `index-list` を残すのは、リンクの体裁（太字の主要参照など）の規則をそのまま使うため。
        # 語の間に空白を置かない——行頭に回った空白のぶん、語の先頭がずれる。
        def index_items_html(list)
          items = list.css('dt').map do |term|
            %(<span class="vs-index-item"><span class="vs-index-term">#{term.inner_html}</span> ) +
              %(<span class="vs-index-refs">#{term.next_element.inner_html}</span></span>)
          end
          %(<div class="index-list vs-index-items">#{items.join}</div>)
        end
      end
    end
  end
end
