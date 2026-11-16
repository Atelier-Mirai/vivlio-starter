# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/build/transforms/kindle/decorate_admonitions.rb
# ================================================================
# 責務:
#   囲みのラベルを、実体の段落で入れる
# ================================================================

require_relative '../context'

module VivlioStarter
  module CLI
    module Build
      # 囲みのラベルを、実体の段落で入れる
      module Transforms::Kindle::DecorateAdmonitions
        module_function

        # PDF では ::before（position:absolute）でラベル帯を描くが、Kindle は absolute を無視して
        # ラベルが消える。実体の <p class="vs-adm-label"> を先頭に挿し、枠線は code/chapter CSS の
        # body.vs-kindle ルール（px 枠線）に委ねることで、Kindle でもラベル付きの囲み枠を保証する（§5）。
        # notice / note は PDF では ::before ラベルを持たないが、Kindle では囲み枠＋ラベルへ劣化させる。
        ADMONITION_LABELS = {
          'tip' => '【TIP】', 'memo' => '【MEMO】', 'column' => '【COLUMN】',
          'notice' => '【NOTICE】', 'note' => '【NOTE】',
          'output' => '【OUTPUT】', 'terminal' => '【TERMINAL】'
        }.freeze

        # 枠を描く囲み。中の横並びは表で組む（lay_out_in_table!）。
        FRAMED_BOX_SELECTOR = [*ADMONITION_LABELS.keys, 'diagram'].map { "div.#{it}" }.join(', ').freeze

        #
        # @param doc [Nokogiri::HTML5::Document] 1 ページの HTML（破壊的に書き換える）
        # @param ctx [Transforms::Context]
        def call(doc, ctx)
          changed = false
          ADMONITION_LABELS.each do |klass, label|
            doc.css("div.#{klass}").each do |box|
              next if box.at_css('.vs-adm-label') # 二重注入を防ぐ

              node = Nokogiri::XML::Node.new('p', doc)
              node['class'] = 'vs-adm-label'
              node.content = label
              box.prepend_child(node)
              changed = true
            end
          end
          Common.log_info("[EPUB] #{ctx.page_name} のコラム枠にラベルを注入しました") if changed
        end
      end
    end
  end
end
