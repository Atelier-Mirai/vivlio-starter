# frozen_string_literal: true

require 'minitest/autorun'
require 'tempfile'
require_relative '../../../../lib/vivlio_starter/cli/post_process/terminal_block_converter'

module VivlioStarter
  module CLI
    module PostProcessCommands
      # 前処理が :::{.terminal} を ~~~vs-terminal フェンスへ書き換えるため、VFM は
      # <pre class="language-vs-terminal"><code …>…</code></pre> を出力する。
      # TerminalBlockConverter はこれを端末枠 <div class="terminal"><pre>…</pre></div>
      # へ戻す（Kindle のラベル注入が div.terminal に依存するため div で包む）。
      class TerminalBlockConverterTest < Minitest::Test
        def convert(html)
          Tempfile.create(['vs_terminal_test_', '.html']) do |f|
            f.write(html)
            f.flush
            TerminalBlockConverter.convert_terminal_blocks!(f.path)
            HtmlParser.parse_html_document(File.read(f.path, encoding: 'utf-8'))
          end
        end

        def test_should_wrap_pre_in_terminal_div_and_drop_language_classes
          html = '<html><body><pre class="language-vs-terminal">' \
                 '<code class="language-vs-terminal">$ cp *.png *.bak</code></pre></body></html>'

          doc = convert(html)

          pre = doc.at_css('div.terminal > pre')
          refute_nil pre, '<pre> は div.terminal 直下へ移される'
          assert_nil pre['class'], 'language-* クラスは残さない（code.css の枠が二重に描かれるため）'
          assert_nil pre.at_css('code'), '<code> ラッパは畳む'
          assert_equal '$ cp *.png *.bak', pre.text
          assert_empty doc.css('pre.language-vs-terminal')
        end

        def test_should_keep_verbatim_whitespace_and_metacharacters
          body = " id | name  | email\n----+-------+------\n  1 | Alice | a@b.net"
          html = "<html><body><pre class=\"language-vs-terminal\"><code>#{body}</code></pre></body></html>"

          doc = convert(html)

          assert_equal body, doc.at_css('div.terminal > pre').text
        end

        def test_should_leave_ordinary_code_blocks_untouched
          html = '<html><body><pre class="language-ruby"><code class="language-ruby">puts 1</code></pre></body></html>'

          doc = convert(html)

          assert_empty doc.css('div.terminal')
          assert_equal 'language-ruby', doc.at_css('pre')['class']
        end
      end
    end
  end
end
