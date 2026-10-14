# frozen_string_literal: true

require 'minitest/autorun'
require 'tempfile'
require_relative '../../../../lib/vivlio_starter/cli/post_process'

module VivlioStarter
  module CLI
    module PostProcessCommands
      # unescape_pipes_in_table_code! は、表のセルのインラインコードに VFM が残した
      # `\|` を `|` に戻す。GFM ではコードの中の `\|` も `|` になるが、VFM は戻さない
      # （改善案.md #110）。表の外のコードとコードブロックには触れない。
      class TableCodePipeTest < Minitest::Test
        # HTML を一時ファイルに書いて処理を適用し、結果文字列を返す。
        def unescape(html)
          Tempfile.create(['vs_table_pipe_test_', '.html']) do |f|
            f.write("<html><body>#{html}</body></html>")
            f.flush
            PostProcessCommands.unescape_pipes_in_table_code!(f.path)
            return File.read(f.path, encoding: 'utf-8')
          end
        end

        def test_should_unescape_pipe_in_table_cell_code
          out = unescape('<table><tbody><tr><td><code>{漢字\|よみ}</code></td></tr></tbody></table>')

          assert_includes out, '<code>{漢字|よみ}</code>'
        end

        def test_should_unescape_every_pipe_in_header_cell_code
          out = unescape('<table><thead><tr><th><code>= books \| tags=ruby \| 3</code></th></tr></thead></table>')

          assert_includes out, '<code>= books | tags=ruby | 3</code>'
        end

        def test_should_keep_backslash_pipe_outside_tables
          html = '<p><code>a\|b</code></p>'

          assert_includes unescape(html), html, '表の外のコードは書いたとおり'
        end

        def test_should_keep_code_blocks_inside_table_cells
          out = unescape('<table><tbody><tr><td><code>x\|y</code><pre><code>a\|b</code></pre></td></tr></tbody></table>')

          assert_includes out, '<code>x|y</code>'
          assert_includes out, '<pre><code>a\|b</code></pre>', 'セルの中のコードブロックは書いたとおり'
        end
      end
    end
  end
end
