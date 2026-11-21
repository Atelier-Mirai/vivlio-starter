# frozen_string_literal: true

require 'minitest/autorun'
require 'tempfile'
require 'nokogiri'
require_relative '../../../../lib/vivlio_starter/cli/post_process'

module VivlioStarter
  module CLI
    module PostProcessCommands
      # 縦書きの本の縦中横の自動（novel-vertical-spec.md §5.3）と、括弧の段落の印（同 §6.1）
      class VerticalTextTest < Minitest::Test
        def apply(body_html, body_class: 'chapter vs-vertical')
          html = %(<!DOCTYPE html>\n<html><head><title>t</title></head><body class="#{body_class}">\n#{body_html}\n</body></html>\n)

          Tempfile.create(['vs_vertical_', '.html']) do |f|
            f.write(html)
            f.flush
            VerticalText.mark!(f.path)
            return Nokogiri::HTML(File.read(f.path, encoding: 'utf-8'))
          end
        end

        def tcy(doc) = doc.css('span.tcy').map(&:text)

        # 半角の数字 1〜2 桁と、ちょうど 2 字の感嘆符と疑問符だけを包む
        def test_should_wrap_one_or_two_digits_and_paired_marks
          doc = apply('<p>針は10時、星は3つ。2026年に3.5度、x12 と 1,000。本当に!? いや!! そう?!? 全角の１２と！？</p>')

          assert_equal %w[10 3 !? !!], tcy(doc)
          assert_includes doc.at('p').text, '2026年に3.5度、x12 と 1,000'
        end

        # 見出しの中も対象。コード・ルビの読み・横組みの箱・URL のリンクは対象にしない
        def test_should_skip_code_ruby_reading_boxes_and_url_links
          doc = apply(<<~HTML)
            <h2>第12話</h2>
            <p><code>a = 12</code> と <ruby>十二<rt>12</rt></ruby> と <a href="https://example.com/12">https://example.com/12</a> と <a href="#x">注 1</a></p>
            <figure><figcaption>図 12</figcaption></figure>
            <div class="memo"><p>メモの 12</p></div>
            <p><span class="tcy">12</span></p>
          HTML

          assert_equal %w[12 1 12], tcy(doc), '見出しの 12・リンクの字の 1・もとからある縦中横'
          assert_equal 'a = 12', doc.at('code').text
        end

        # 開き括弧で始まる段落に印を付ける。横組みの箱の中の段落には付けない
        def test_should_mark_paragraphs_that_open_with_a_bracket
          doc = apply(<<~HTML)
            <p>「会話の段落」</p>
            <p>　『全角空白の後の括弧』</p>
            <p class="aki">（補足の段落）</p>
            <p>地の文の「段落」</p>
            <div class="note"><p>「囲みの中」</p></div>
          HTML

          marked = doc.css('p.vs-open-bracket').map(&:text)
          assert_equal ['「会話の段落」', '（補足の段落）'], marked
          assert_equal 'aki vs-open-bracket', doc.css('p')[2]['class']
        end

        # 奥付と権利ページは横に組むので触らない
        def test_should_leave_horizontal_pages_alone
          doc = apply('<p>「第2版」</p>', body_class: 'colophon vs-vertical')

          assert_empty tcy(doc)
          assert_nil doc.at('p')['class']
        end
      end
    end
  end
end
