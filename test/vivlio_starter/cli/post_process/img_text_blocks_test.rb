# frozen_string_literal: true

require 'minitest/autorun'
require 'tempfile'
require 'nokogiri'
require_relative '../../../../lib/vivlio_starter/cli/post_process'

module VivlioStarter
  module CLI
    module PostProcessCommands
      # wrap_img_text_blocks! は、横並びのコンテナを「本文の div」と「画像の figure」の
      # 2 要素にそろえる。ファイル名を付けたコードブロックも <figure> で出力されるので、
      # それを画像と取り違えないことを確かめる（42 章で画像が本文の列に入り、コードが
      # 画像の列へ押し出された）。
      class ImgTextBlocksTest < Minitest::Test
        def process(container_html)
          html = <<~HTML
            <!DOCTYPE html>
            <html><head><title>t</title></head><body>
            #{container_html}
            </body></html>
          HTML

          Tempfile.create(['vs_img_text_', '.html']) do |f|
            f.write(html)
            f.flush
            PostProcessCommands.wrap_img_text_blocks!(f.path)
            return Nokogiri::HTML(File.read(f.path, encoding: 'utf-8'))
          end
        end

        def test_should_wrap_text_and_leave_image_figure_as_second_column
          doc = process(<<~HTML)
            <div class="text2-img">
              <p>本文</p>
              <figure><img src="a.webp"><figcaption>図</figcaption></figure>
            </div>
          HTML

          children = doc.at_css('div.text2-img').element_children
          assert_equal %w[div figure], children.map(&:name)
          assert_equal 'img-text-body', children[0]['class']
          assert_equal '本文', children[0].text.strip
        end

        def test_should_keep_captioned_code_block_in_text_column
          doc = process(<<~HTML)
            <div class="text2-img">
              <p>本文</p>
              <figure class="language-yaml"><figcaption>config/book.yml</figcaption><pre><code>theme:</code></pre></figure>
              <figure><img src="floral.webp"><figcaption>図</figcaption></figure>
            </div>
          HTML

          body, image = doc.at_css('div.text2-img').element_children.to_a
          assert_equal 'img-text-body', body['class']
          assert body.at_css('figure.language-yaml pre'), 'コードブロックは本文の列に入る'
          assert_nil body.at_css('img'), '画像は本文の列に入らない'
          assert image.at_css('img'), '画像の figure が 2 列目に残る'
        end

        def test_should_leave_container_with_only_code_figure_untouched
          doc = process(<<~HTML)
            <div class="text2-img">
              <p>本文</p>
              <figure class="language-yaml"><pre><code>theme:</code></pre></figure>
            </div>
          HTML

          assert_nil doc.at_css('div.img-text-body')
        end
      end

      # wrap_sideimage_blocks! も同じく「画像の figure」と「本文の div」にそろえる。
      class SideimageBlocksTest < Minitest::Test
        def test_should_keep_captioned_code_block_in_sideimage_body
          html = <<~HTML
            <!DOCTYPE html>
            <html><head><title>t</title></head><body>
            <div class="sideimage-right">
              <figure class="language-yaml"><figcaption>config/book.yml</figcaption><pre><code>theme:</code></pre></figure>
              <figure><img src="a.webp"></figure>
              <p>本文</p>
            </div>
            </body></html>
          HTML

          doc = Tempfile.create(['vs_sideimage_', '.html']) do |f|
            f.write(html)
            f.flush
            PostProcessCommands.wrap_sideimage_blocks!(f.path)
            Nokogiri::HTML(File.read(f.path, encoding: 'utf-8'))
          end

          # 列は CSS が要素の種類で決める（figure が画像の列）ので、子の順番は問わない
          container = doc.at_css('div.sideimage-right')
          assert_equal %w[div figure], container.element_children.map(&:name).sort
          assert container.at_css('> figure img'), '画像の figure が直下に残る'
          body = container.at_css('> div.sideimage-body')
          assert body.at_css('figure.language-yaml pre'), 'コードブロックは本文の側に入る'
          assert_nil body.at_css('img'), '画像は本文の側に入らない'
        end

        # 本文に残ったバッククォートとリンク記法は <code>・<a> に直すが、コードの中の文字は
        # 書いたとおりに残す（Markdown の書き方を示すコードが組み替えられていた）。
        def test_should_convert_markdown_in_prose_but_leave_code_untouched
          html = <<~HTML
            <!DOCTYPE html>
            <html><head><title>t</title></head><body>
            <div class="sideimage-right">
              <figure><img src="a.webp"></figure>
              <p>本文の `vs build` と [公式](https://example.com) を直す</p>
              <pre><code class="language-markdown">`vs build` と [公式](https://example.com)</code></pre>
              <p><code>[a](b)</code> はそのまま</p>
            </div>
            </body></html>
          HTML

          doc = Tempfile.create(['vs_sideimage_', '.html']) do |f|
            f.write(html)
            f.flush
            PostProcessCommands.wrap_sideimage_blocks!(f.path)
            Nokogiri::HTML(File.read(f.path, encoding: 'utf-8'))
          end

          prose, inline_code = doc.css('div.sideimage-body > p').to_a
          assert_equal 'vs build', prose.at_css('code').text
          assert_equal 'https://example.com', prose.at_css('a')['href']

          code = doc.at_css('div.sideimage-body pre code')
          assert_equal '`vs build` と [公式](https://example.com)', code.inner_html
          assert_equal '[a](b)', inline_code.at_css('code').inner_html
        end
      end
    end
  end
end
