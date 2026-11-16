# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/build/transforms/kindle/constrain_layout_images.rb
# ================================================================
# 責務:
#   画像の配置（回り込み・並び）を、style 属性と表で組み直す
# ================================================================

require_relative '../context'
require_relative '../dom'
require_relative 'decorate_admonitions'
require_relative '../../../post_process/html_parser'

module VivlioStarter
  module CLI
    module Build
      # 画像の配置（回り込み・並び）を、style 属性と表で組み直す
      module Transforms::Kindle::ConstrainLayoutImages
        module_function

        # 横並びレイアウト（book-card / sideimage / img-text 系）のコンテナ画像に、幅と回り込みを
        # inline style で課す。Kindle は外部 CSS の画像サイズ指定を無視するが inline は尊重するため、
        # grid 崩壊時の全幅化を inline で確実に防ぐ。container クラス → 幅(%)・float 側の対応表で制御。
        LAYOUT_IMAGE_RULES = {
          'book-card' => { width: 40, float: 'left' },
          # sideimage 系は text 3 : image 1（画像 1/4 ＝ 25%）。本文を主役にし画像は脇に小さく添える。
          'sideimage' => { width: 25, float: 'left' },
          'sideimage-left' => { width: 25, float: 'left' },
          'sideimage-right' => { width: 25, float: 'right' },
          'img-text' => { width: 45, float: 'left' },
          'img-text2' => { width: 45, float: 'left' },
          'img-text3' => { width: 45, float: 'left' },
          'text-img' => { width: 45, float: 'right' },
          'text2-img' => { width: 45, float: 'right' },
          'text3-img' => { width: 45, float: 'right' }
        }.freeze

        # 横並びコンテナ内の画像に inline で幅・float を付与する。
        #
        # @param html_files [Array<String>] HTML ファイルパスの配列
        # @return [Array<String>] そのままの配列（パス変更なし）
        def call(html_files, _ctx)
          html_files.each do |path|
            html = File.read(path, encoding: 'utf-8')
            doc = PostProcessCommands::HtmlParser.parse_html_document(html)

            changed = false
            LAYOUT_IMAGE_RULES.each do |klass, rule|
              doc.css(".#{klass}").each do |container|
                target = layout_image_target(container)
                next unless target

                if target.parent == container && container.ancestors(Transforms::Kindle::DecorateAdmonitions::FRAMED_BOX_SELECTOR).any?
                  lay_out_in_table!(container, target, rule)
                else
                  apply_inline_image_constraint!(target, rule)
                  # float は後ろの本文にしか回り込まない。本文 → 画像の順の原稿では、
                  # 画像が本文の下へ落ちるので先頭へ動かす。
                  first = container.element_children.first
                  first.add_previous_sibling(target) if target.parent == container && first != target
                end
                changed = true
              end
            end
            next unless changed

            PostProcessCommands::HtmlParser.save_html_document(path, doc)
            Common.log_info("[EPUB] #{File.basename(path)} の横並び画像を inline で制約しました")
          end
          html_files
        end

        # 枠の中の横並びを、float から 1 行の表へ組み替える。
        #
        # KFX は枠を中の float まで伸ばさないので、本文が画像より短いと画像が枠の下へはみ出す。
        # clearfix・実体の clear・overflow・inline-block・vw の min-height はどれも効かず、
        # 表のセルなら枠は画像の高さまで伸びる（Previewer の画面で確かめた。2026-11-01）。
        # 枠の外は回り込みのほうが紙面を使い切れるので float のままにする。
        #
        # @param container [Nokogiri::XML::Element] 横並びのコンテナ
        # @param image [Nokogiri::XML::Element] コンテナ直下の画像（img または figure）
        # @param rule [Hash] LAYOUT_IMAGE_RULES の 1 件
        def lay_out_in_table!(container, image, rule)
          apply_inline_image_constraint!(image, rule.merge(width: 100, float: 'none'))
          Transforms::Dom.add_inline_style(image, 'max-height: none; margin: 0;')
          # KFX は表の中の画像をページの残りの高さまで縮める。page-break-inside は表にも枠にも
          # 効かず、min-width を付けると縮めずに表ごと次のページへ送る（Previewer で確かめた）。
          Transforms::Dom.add_inline_style(image.at_css('img') || image, 'min-width: 100%;')

          doc = container.document
          left = rule[:float] == 'left'
          gap = left ? '0 1em 0 0' : '0 0 0 1em'
          image_cell = doc.create_element('td', style: "width: #{rule[:width]}%; border: none; padding: #{gap}; vertical-align: top;")
          body_cell = doc.create_element('td', style: 'border: none; padding: 0; vertical-align: top;')
          container.children.reject { it == image }.each { body_cell.add_child(it) }
          image_cell.add_child(image)

          row = doc.create_element('tr')
          (left ? [image_cell, body_cell] : [body_cell, image_cell]).each { row.add_child(it) }
          table = doc.create_element('table', style: 'width: 100%; border: none; margin: 0;')
          table.add_child(row)
          container.add_child(table)
        end

        # コンテナ直下の画像要素（figure 優先・無ければ img、無ければ子孫 img）を返す。
        def layout_image_target(container)
          direct = container.element_children.find { %w[figure img].include?(it.name) }
          direct || container.at_css('img')
        end

        # 画像要素（img/figure）へ幅・float を inline で付与する。figure の場合は内側 img も 100% に。
        def apply_inline_image_constraint!(node, rule)
          Transforms::Dom.add_inline_style(node, "max-width: #{rule[:width]}%; width: #{rule[:width]}%; height: auto; float: #{rule[:float]};")
          return unless node.name == 'figure'

          inner = node.at_css('img')
          Transforms::Dom.add_inline_style(inner, 'width: 100%; height: auto;') if inner
        end
      end
    end
  end
end
