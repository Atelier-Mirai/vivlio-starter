# frozen_string_literal: true

require 'minitest/autorun'
require 'tempfile'
require 'nokogiri'
require_relative '../../../../lib/vivlio_starter/cli/post_process'

module VivlioStarter
  module CLI
    module PostProcessCommands
      # mark_full_page_figures! は、`![題](x.png){.full-page}` を VFM が組んだ形（figure と figcaption・
      # 説明文の無いときは段落）を、契約 HTML の figure.vs-full-page にそろえる（novel-vertical-spec.md §5.2）
      class FullPageFigureTest < Minitest::Test
        def apply(body_html)
          html = "<!DOCTYPE html>\n<html><head><title>t</title></head><body>\n#{body_html}\n</body></html>\n"

          Tempfile.create(['vs_full_page_', '.html']) do |f|
            f.write(html)
            f.flush
            PostProcessCommands.mark_full_page_figures!(f.path)
            return Nokogiri::HTML(File.read(f.path, encoding: 'utf-8'))
          end
        end

        # 説明文のある形: figcaption を外し、説明文は alt に残す
        def test_should_turn_captioned_figure_into_full_page_figure_without_caption
          doc = apply(<<~HTML)
            <figure>
              <img src="images/x.png" alt="題" class="full-page">
              <figcaption aria-hidden="true">題</figcaption>
            </figure>
          HTML

          figure = doc.at_css('figure')
          assert_equal 'vs-full-page', figure['class']
          assert_equal ['img'], figure.element_children.map(&:name)
          assert_equal '題', figure.at_css('img')['alt']
          assert_nil figure.at_css('img')['class']
        end

        # 説明文の無い形: 段落を figure に置き換え、著者の書いた幅は使わない
        def test_should_replace_paragraph_holding_only_the_image
          doc = apply('<p><img src="images/y.png" class="full-page" width="50%"></p>')

          assert_nil doc.at_css('body > p')
          img = doc.at_css('figure.vs-full-page > img')
          assert_equal 'images/y.png', img['src']
          assert_nil img['width']
        end

        # 相互参照の付いた図（cross_reference_processor が組む figure.full-page）も同じ形にし、id は残す
        def test_should_keep_figure_id_and_drop_width_style
          doc = apply('<figure id="fig-a" class="full-page" style="width: 50%"><img src="a.png" alt="a">' \
                      '<figcaption>図 1-1: a</figcaption></figure>')

          figure = doc.at_css('figure#fig-a')
          assert_equal 'vs-full-page', figure['class']
          assert_nil figure['style']
          assert_nil figure.at_css('figcaption')
        end

        # 字と並んだ画像は 1 ページを使えないので、行の中の画像のままにする
        def test_should_leave_image_inside_running_text
          doc = apply('<p>文中の <img src="a.png" alt="a" class="full-page"> です。</p>')

          assert_nil doc.at_css('figure')
          assert_equal 'full-page', doc.at_css('p > img')['class']
        end
      end
    end
  end
end
