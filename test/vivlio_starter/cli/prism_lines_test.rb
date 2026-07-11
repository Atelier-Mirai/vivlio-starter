# frozen_string_literal: true

require 'minitest/autorun'
require 'tempfile'
require_relative '../../../lib/vivlio_starter/cli/common'
require_relative '../../../lib/vivlio_starter/cli/prism_lines'

module VivlioStarter
  module CLI
    # PrismLinesCommands は Prism.js コードブロックへ行番号を付与し、
    # コメントトークン内の [!] マーカーを赤強調（codered）へ変換する。
    # [!] 変換は旧 post_replace_list.yml から移設した処理で、コメント記号を保持し
    # [!] とその前後の空白 1 つを除去する。
    class PrismLinesTest < Minitest::Test
      # HTML を一時ファイルに書いて execute_prism_lines を通し、結果文字列を返す。
      def process(html)
        Tempfile.create(['vs_prism_test_', '.html']) do |f|
          f.write(html)
          f.flush
          PrismLinesCommands.execute_prism_lines(f.path)
          return File.read(f.path, encoding: 'utf-8')
        end
      end

      def pre_with(comment_html)
        <<~HTML
          <pre class="language-ruby"><code class="language-ruby"><span class="token comment">#{comment_html}</span>
          puts "hi"</code></pre>
        HTML
      end

      # =============================================================
      # [!] 赤強調
      # =============================================================

      def test_should_add_codered_and_strip_alert_marker
        out = process(pre_with('# [!] 注意'))

        assert_match(/<span class="token comment codered">#\s*注意</, out)
        refute_includes out, '[!]'
      end

      def test_should_preserve_slash_comment_symbol
        out = process(pre_with('// [!] warn'))

        assert_match(%r{<span class="token comment codered">//\s*warn}, out)
        refute_includes out, '[!]'
      end

      def test_should_preserve_sql_comment_symbol
        out = process(pre_with('-- [!] note'))

        assert_match(/<span class="token comment codered">--\s*note/, out)
      end

      def test_should_preserve_block_comment_symbol
        out = process(pre_with('/* [!] block'))

        assert_match(%r{<span class="token comment codered">/\*\s*block}, out)
      end

      def test_should_preserve_html_comment_symbol
        # Nokogiri のテキストノードではデコード済みの <!-- になる
        out = process(pre_with('&lt;!-- [!] html'))

        assert_includes out, 'codered'
        assert_includes out, '&lt;!--'
        refute_includes out, '[!]'
      end

      def test_should_not_touch_comment_without_alert_marker
        out = process(pre_with('# 普通のコメント'))

        refute_includes out, 'codered'
        assert_includes out, '# 普通のコメント'
      end

      def test_should_not_highlight_inside_language_markdown_pre
        html = <<~HTML
          <pre class="language-markdown"><code class="language-markdown"><span class="token comment"># [!] 記法説明の例</span></code></pre>
        HTML
        out = process(html)

        refute_includes out, 'codered'
        assert_includes out, '[!]'
      end

      # =============================================================
      # 行番号付与と共存
      # =============================================================

      def test_should_add_line_numbers_alongside_alert_highlight
        out = process(pre_with('# [!] 注意'))

        assert_includes out, 'line-numbers-rows'
        assert_includes out, 'codered'
      end
    end
  end
end
