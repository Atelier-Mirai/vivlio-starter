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

      # =============================================================
      # 開始行マーカー（figcaption 末尾の #L 記法・code-include-line-number-spec §3.2）
      # =============================================================

      def figure_with(caption, code_lines = "line22\nline23\nline24\nline25")
        <<~HTML
          <figure class="language-ruby"><figcaption>#{caption}</figcaption><pre class="language-ruby"><code class="language-ruby">#{code_lines}</code></pre></figure>
        HTML
      end

      def test_should_consume_start_line_marker_from_figcaption
        out = process(figure_with('prime.rb#L22-L25'))

        assert_includes out, 'data-start="22"', 'pre に data-start が付く'
        assert_includes out, 'counter-reset: linenumber 21', '開始値 N-1 の counter-reset がインライン style に載る'
        assert_includes out, '<figcaption>prime.rb</figcaption>', 'figcaption はパスのみへ戻る（R8）'
        assert_equal 4, out.scan('<span></span>').size, 'ガター span の個数は行数どおり'
      end

      def test_should_keep_default_numbering_without_marker
        out = process(figure_with('prime.rb'))

        refute_includes out, 'data-start'
        refute_includes out, 'counter-reset'
        assert_includes out, '<figcaption>prime.rb</figcaption>'
      end

      def test_should_keep_default_numbering_for_bare_pre
        out = process(<<~HTML)
          <pre class="language-ruby"><code class="language-ruby">x = 1</code></pre>
        HTML

        refute_includes out, 'data-start'
        assert_includes out, 'line-numbers-rows'
      end

      # =============================================================
      # 行番号の免除枠（.output / .terminal / .diagram）
      # 実行結果・端末転写・テキストの図は「コードの提示」ではないため行番号を付けない。
      # =============================================================
      def test_should_not_number_pre_inside_output
        out = process('<div class="output"><pre><code>実行結果の行</code></pre></div>')

        refute_includes out, 'line-numbers-rows', '.output 内の <pre> には行番号を付けない'
      end

      def test_should_not_number_pre_inside_terminal
        out = process('<div class="terminal"><pre><code>$ ls -l</code></pre></div>')

        refute_includes out, 'line-numbers-rows', '.terminal 内の <pre> には行番号を付けない'
      end

      def test_should_not_number_pre_inside_diagram
        out = process('<div class="diagram"><pre><code>┌─┐\n└─┘</code></pre></div>')

        refute_includes out, 'line-numbers-rows', '.diagram 内の <pre>（図・アスキーアート）には行番号を付けない'
      end

      # 複数クラスの div（class="output foo"）でも免除される
      def test_should_exempt_pre_when_class_has_extra_tokens
        out = process('<div class="foo diagram bar"><pre><code>art</code></pre></div>')

        refute_includes out, 'line-numbers-rows'
      end

      # 免除枠の外にある通常のコードブロックには従来どおり行番号を付ける
      def test_should_still_number_pre_outside_exempt_containers
        out = process(<<~HTML)
          <div class="diagram"><pre><code>図</code></pre></div>
          <pre class="language-ruby"><code class="language-ruby">x = 1</code></pre>
        HTML

        assert_includes out, 'line-numbers-rows', '免除枠の外の <pre> には行番号が付く'
      end

      def test_should_append_counter_reset_to_existing_style
        out = process(<<~HTML)
          <figure class="language-ruby"><figcaption>prime.rb#L5</figcaption><pre class="language-ruby" style="margin: 0"><code class="language-ruby">x = 1</code></pre></figure>
        HTML

        assert_includes out, 'margin: 0; counter-reset: linenumber 4', '既存 style へ ; 連結で追記される'
      end

      def test_should_interpret_only_trailing_marker_for_path_with_hash
        out = process(figure_with('dir#1/prime.rb#L22-L25'))

        assert_includes out, 'data-start="22"', '末尾アンカーで最後のマーカーのみ解釈する'
        assert_includes out, '<figcaption>dir#1/prime.rb</figcaption>'
      end

      def test_should_drop_invalid_zero_start_marker
        out = process(figure_with('prime.rb#L0'))

        refute_includes out, 'data-start', '開始値 0 は不正としてマーカー除去のみ行う'
        refute_includes out, 'counter-reset'
        assert_includes out, '<figcaption>prime.rb</figcaption>', '不正でもマーカーは表示から除去される'
      end
    end
  end
end
