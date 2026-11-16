# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/build/transforms/shared/decorate_footnotes.rb
# ================================================================
# 責務:
#   脚注に、番号を実体の字で入れる
# ================================================================

require_relative '../context'

module VivlioStarter
  module CLI
    module Build
      # 脚注に、番号を実体の字で入れる
      module Transforms::Shared::DecorateFootnotes
        module_function

        # tip / memo / column / notice / note（コラム・注記枠）に見出しラベル要素を実体注入する。
        # EPUB / Kindle の脚注へ番号を実テキストで注入する。
        #
        # リフローにはページ下部が無いので、PDF が脚注領域へ降ろしている aside は
        # 参照した段落の直後にそのまま残る。素のままだと番号も区切りも無く、本文と
        # 地続きの文字列にしか見えない（どこからが脚注か読者に分からない）。
        # 番号を実体で置き、CSS 側（stylesheets/targets/epub.css の body.vs-epub 規則）で
        # 一回り小さい注記ブロックとして見せる。
        #
        # ::before ではなく実テキストにするのは Kindle(KFX) が擬似要素を解さないため。
        # クリーン EPUB も同じ経路に揃えてフレーバ分岐を増やさない（vs-adm-label と同じ方式）。
        #
        # @param doc [Nokogiri::HTML5::Document] 1 ページの HTML（破壊的に書き換える）
        # @param ctx [Transforms::Context]
        def call(doc, ctx)
          changed = false
          doc.css('aside.page-footnote-print[data-footnote-number]').each do |aside|
            next if aside.at_css('.vs-fn-num') # 二重注入を防ぐ（冪等）

            span = Nokogiri::XML::Node.new('span', doc)
            span['class'] = 'vs-fn-num'
            span.content = "#{aside['data-footnote-number']}. "
            aside.prepend_child(span)
            changed = true
          end
          Common.log_info("[EPUB] #{ctx.page_name} の脚注に番号を注入しました") if changed
        end
      end
    end
  end
end
