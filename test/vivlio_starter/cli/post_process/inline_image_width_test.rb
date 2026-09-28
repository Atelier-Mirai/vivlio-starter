# frozen_string_literal: true

require 'minitest/autorun'
require 'tempfile'
require 'nokogiri'
require_relative '../../../../lib/vivlio_starter/cli/post_process'

module VivlioStarter
  module CLI
    module PostProcessCommands
      # apply_inline_image_widths! は、文中に置いた画像の幅（VFM が出す <img width="10%">）を
      # style の width へ移す（改善案.md #53）。HTML の width 属性は整数（px）しか取らず、
      # Vivliostyle は 10% や 2em を幅として扱わないため、画像が本文幅いっぱいに広がっていた。
      class InlineImageWidthTest < Minitest::Test
        def apply(body_html)
          html = "<!DOCTYPE html>\n<html><head><title>t</title></head><body>\n#{body_html}\n</body></html>\n"

          Tempfile.create(['vs_inline_image_width_', '.html']) do |f|
            f.write(html)
            f.flush
            PostProcessCommands.apply_inline_image_widths!(f.path)
            return Nokogiri::HTML(File.read(f.path, encoding: 'utf-8'))
          end
        end

        def test_should_move_percentage_width_into_style
          img = apply('<p>文中の <img src="a.webp" alt="a" width="10%"> です。</p>').at_css('img')

          assert_equal 'width: 10%', img['style']
          assert_nil img['width']
        end

        def test_should_keep_css_length_units
          img = apply('<p>文中の <img src="a.webp" alt="a" width="2em"> です。</p>').at_css('img')

          assert_equal 'width: 2em', img['style']
        end

        # 単位のない整数は、HTML の width 属性の意味どおり px とみなす
        def test_should_treat_bare_integer_as_pixels
          img = apply('<p>文中の <img src="a.webp" alt="a" width="48"> です。</p>').at_css('img')

          assert_equal 'width: 48px', img['style']
        end

        # 箇条書き・表の中の画像も文中の画像として扱う
        def test_should_apply_to_images_in_list_items_and_table_cells
          doc = apply(<<~HTML)
            <ul><li>項目 <img src="a.webp" alt="a" width="10%"> です。</li></ul>
            <table><tr><td>セル <img src="b.webp" alt="b" width="10%"></td></tr></table>
          HTML

          assert_equal ['width: 10%', 'width: 10%'], doc.css('img').map { it['style'] }
        end

        # すでにある style は残し、幅を先頭に足す
        def test_should_keep_existing_style
          img = apply('<p><img src="a.webp" alt="a" width="10%" style="vertical-align: middle"></p>').at_css('img')

          assert_equal 'width: 10%; vertical-align: middle', img['style']
        end

        # 単独で置いた画像（figure の中）は前処理が幅を組むので触らない
        def test_should_leave_images_inside_figures_untouched
          img = apply('<figure style="width: 30%"><img src="a.webp" alt="a" width="30%"></figure>').at_css('img')

          assert_equal '30%', img['width']
          assert_nil img['style']
        end

        def test_should_leave_images_without_width_untouched
          img = apply('<p>文中の <img src="a.webp" alt="a"> です。</p>').at_css('img')

          assert_nil img['style']
        end
      end
    end
  end
end
