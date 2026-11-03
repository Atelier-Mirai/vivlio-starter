# frozen_string_literal: true

require 'minitest/autorun'
require 'tempfile'
require_relative '../../../../lib/vivlio_starter/cli/post_process'

module VivlioStarter
  module CLI
    module PostProcessCommands
      # add_line_break_opportunities! は、インラインコードと地の文の URL の `/` の後、
      # `.` で始まるインラインコードの先頭に <wbr> を入れる。改行の規則では、ここで
      # 行を分けられず、手前の行が字間を広げて組まれるため。
      class LineBreakOpportunitiesTest < Minitest::Test
        def apply(html)
          Tempfile.create(['vs_wbr_test_', '.html']) do |f|
            f.write("<html><body>#{html}</body></html>")
            f.flush
            PostProcessCommands.add_line_break_opportunities!(f.path)
            return File.read(f.path, encoding: 'utf-8')
          end
        end

        def test_should_allow_break_after_slash_in_inline_code
          out = apply('<p><code>stylesheets/custom.css</code> に書きます。</p>')

          assert_includes out, '<code>stylesheets/<wbr>custom.css</code>'
        end

        # `https://` の直後と `//` の途中、末尾の `/` には入れない
        def test_should_allow_break_after_slash_in_url_but_not_after_scheme
          out = apply('<p>場所は <a href="https://github.com/a/b/">https://github.com/a/b/</a> です。</p>')

          assert_includes out, '>https://github.com/<wbr>a/<wbr>b/</a>'
        end

        def test_should_allow_break_before_inline_code_starting_with_dot
          out = apply('<p>困らないなら <code>.memo</code>・<code>.tip</code> から選びます。</p>')

          assert_includes out, '<code><wbr>.memo</code>・<code><wbr>.tip</code>'
        end

        # コードブロックと、URL でない地の文の `/` は触らない
        def test_should_leave_code_blocks_and_plain_slashes
          out = apply('<pre><code>a/b/c</code></pre><p>入力/出力の比</p>')

          refute_includes out, '<wbr>'
        end
      end
    end
  end
end
