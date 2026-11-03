# frozen_string_literal: true

require 'minitest/autorun'
require 'tempfile'
require 'nokogiri'
require_relative '../../../../lib/vivlio_starter/cli/post_process'

module VivlioStarter
  module CLI
    module PostProcessCommands
      # set_pictures_columns! は、写真グリッドの画像の数を --pictures-columns として渡す。
      # layout-utils.css はこの数で各画像の幅を決め、次の行へ回った画像を伸ばさない
      # （伸ばすと版面より高くなり、紙面から消えた）。
      class PicturesColumnsTest < Minitest::Test
        def process(container_html)
          html = <<~HTML
            <!DOCTYPE html>
            <html><head><title>t</title></head><body>
            #{container_html}
            </body></html>
          HTML

          Tempfile.create(['vs_pictures_', '.html']) do |f|
            f.write(html)
            f.flush
            PostProcessCommands.set_pictures_columns!(f.path)
            return Nokogiri::HTML(File.read(f.path, encoding: 'utf-8'))
          end
        end

        def test_should_set_column_count_from_number_of_images
          doc = process(<<~HTML)
            <div class="pictures">
              <figure><img src="a.webp"></figure>
              <figure><img src="b.webp"></figure>
              <figure><img src="c.webp"></figure>
              <figure><img src="d.webp"></figure>
            </div>
          HTML

          assert_equal '--pictures-columns: 4', doc.at_css('div.pictures')['style']
        end

        def test_should_keep_existing_style_and_replace_previous_count
          doc = process(<<~HTML)
            <div class="pictures" style="margin: 0; --pictures-columns: 9">
              <figure><img src="a.webp"></figure>
              <img src="b.webp">
            </div>
          HTML

          assert_equal 'margin: 0; --pictures-columns: 2', doc.at_css('div.pictures')['style']
        end

        def test_should_leave_container_without_images_untouched
          doc = process('<div class="pictures"><p>画像なし</p></div>')

          assert_nil doc.at_css('div.pictures')['style']
        end
      end
    end
  end
end
