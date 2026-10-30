# frozen_string_literal: true

require 'minitest/autorun'
require 'tempfile'
require 'nokogiri'
require_relative '../../../../lib/vivlio_starter/cli/post_process'

module VivlioStarter
  module CLI
    module PostProcessCommands
      # wrap_sideimage_blocks! は、sideimage-body の中に Markdown のまま残ったリンクを
      # <a> に替える。URL の中で対になった括弧（Wikimedia の `…_(2008).jpg`）は URL の一部。
      class SideimageLinkTest < Minitest::Test
        def wrap(body_html)
          html = <<~HTML
            <!DOCTYPE html>
            <html><head><title>t</title></head><body>
            <div class="sideimage-right">
              <figure><img src="a.webp"></figure>
              <div class="sideimage-body">#{body_html}</div>
            </div>
            </body></html>
          HTML

          Tempfile.create(['vs_sideimage_link_', '.html']) do |f|
            f.write(html)
            f.flush
            PostProcessCommands.wrap_sideimage_blocks!(f.path)
            return Nokogiri::HTML(File.read(f.path, encoding: 'utf-8'))
          end
        end

        def test_should_keep_balanced_parentheses_in_sideimage_link_url
          doc = wrap('<p>肖像：[Commons](https://commons.wikimedia.org/wiki/File:Karen_(2008).jpg) [^url1]。</p>')

          link = doc.at_css('.sideimage-body a')
          assert_equal 'https://commons.wikimedia.org/wiki/File:Karen_(2008).jpg', link['href']
          assert_equal 'Commons', link.text
          assert_equal '肖像：Commons [^url1]。', doc.at_css('.sideimage-body p').text
        end
      end
    end
  end
end
