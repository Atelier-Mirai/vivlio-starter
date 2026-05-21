# frozen_string_literal: true

require 'minitest/autorun'
require 'tempfile'
require_relative '../../../../lib/vivlio_starter/cli/post_process/html_replacer'

module VivlioStarter
  module CLI
    module PostProcessCommands
      # HtmlReplacer は config/post_replace_list.yml の置換ルールを HTML に適用する。
      # その際、<pre>…</pre>（フェンス付きコードブロック）および <code>…</code>
      # （インラインコード）は「書き方の説明」の一部なので置換対象から除外される。
      # ただし Prism ハイライト出力（<span class="token ...">）を明示的に狙う
      # ルールは例外として <pre> 内にも適用される。
      class HtmlReplacerTest < Minitest::Test
        def with_html(html)
          Tempfile.create(['vs_replacer_test_', '.html']) do |f|
            f.write(html)
            f.flush
            yield f.path
            File.read(f.path, encoding: 'utf-8')
          end
        end

        def run_rules(html, rules)
          with_html(html) do |path|
            HtmlReplacer.process_html_file(path, rules)
          end
        end

        # =============================================================
        # <pre> 保護
        # =============================================================

        def test_preserves_content_inside_pre_blocks
          html = <<~HTML
            <p>@posi:10 を書くと下に余白を入れます。</p>
            <pre><code class="language-markdown">本文の流れ。

            @posi:10

            次の段落を 10mm 下げて始めたい。
            </code></pre>
          HTML
          rules = [{ 'f' => '@posi:(\\d+)', 'r' => '<div style="margin-top:$1mm"></div>' }]

          out = run_rules(html, rules)

          # <pre> の外側は置換される
          assert_match(%r{<p><div style="margin-top:10mm"></div> を書くと下に余白を入れます。</p>}, out)
          # <pre> の中身は「書かれたそのまま」
          assert_includes out, '@posi:10'
          refute_match(%r{<pre>.*?<div style="margin-top:10mm"></div>.*?</pre>}m, out)
        end

        def test_preserves_multiple_macros_inside_pre
          html = <<~HTML
            <pre><code class="language-markdown">@div:memo
            1 行だけクラス付き div で囲みたいとき。
            @divend
            </code></pre>
            @divend
          HTML
          rules = [
            { 'f' => '@div:([a-z0-9_\\- ]+)', 'r' => '<div class="$1">' },
            { 'f' => '@divend', 'r' => '</div>' }
          ]

          out = run_rules(html, rules)

          # <pre> 内の @div:memo / @divend は原文のまま残る
          assert_includes out, '@div:memo'
          pre_body = out[/<pre>.*?<\/pre>/m]
          assert_includes pre_body, '@divend'
          # <pre> の外の @divend は置換される
          refute_match(/<\/pre>\s*@divend/m, out)
          assert_match(%r{</pre>\s*</div>}m, out)
        end

        def test_preserves_full_width_kbd_markers_inside_pre
          html = <<~HTML
            <pre><code class="language-markdown">保存は 〘Ctrl〙 + 〘S〙 で行います。
            </code></pre>
            <p>保存は 〘Ctrl〙 + 〘S〙 で行います。</p>
          HTML
          rules = [
            { 'f' => '〘', 'r' => '<kbd>' },
            { 'f' => '〙', 'r' => '</kbd>' }
          ]

          out = run_rules(html, rules)

          # <pre> 内は原文維持
          pre_body = out[/<pre>.*?<\/pre>/m]
          assert_includes pre_body, '〘Ctrl〙'
          refute_includes pre_body, '<kbd>'
          # <pre> 外は置換される
          assert_match(%r{<p>保存は <kbd>Ctrl</kbd> \+ <kbd>S</kbd> で行います。</p>}, out)
        end

        # =============================================================
        # インライン <code> 保護
        # =============================================================

        def test_preserves_inline_code_content
          html = '<p>本文中で <code>@clear</code> と書くと、段組を解除します。</p>'
          rules = [{ 'f' => '@clear', 'r' => '<div class="floatclear"></div>' }]

          out = run_rules(html, rules)

          # インラインコードは温存
          assert_includes out, '<code>@clear</code>'
          refute_includes out, '<code><div class="floatclear"></div></code>'
        end

        # =============================================================
        # Prism ハイライト狙いルールは <pre> 内も適用される
        # =============================================================

        def test_prism_token_targeting_rule_still_reaches_inside_pre
          html = <<~HTML
            <pre><code class="language-ruby"><span class="token comment">#← 強調したいコメント</span>
            puts "hello"</code></pre>
          HTML
          rules = [{
            'f' => '<span class="token comment"([^>]*)>#←',
            'r' => '<span class="token comment codered"$1>'
          }]

          out = run_rules(html, rules)

          # コードブロックの中であっても、Prism の token span を狙うルールは適用される
          assert_includes out, '<span class="token comment codered">'
          refute_includes out, '#←'
        end

        # =============================================================
        # タグ定義（属性値を含む）の内側では置換しない
        # =============================================================

        # `@clear` などのマクロが HeadingProcessor によって data-heading 属性に
        # コピーされた後、HtmlReplacer 最終パスが属性値内の `@clear` を
        # 置換してしまい、`data-heading="... <div class=\"floatclear\"></div> ..."`
        # となって属性値内の `"` で HTML 解析が破綻する事故を防ぐ。
        def test_text_only_rule_does_not_substitute_inside_attribute_values
          html = '<h3 id="x" data-heading="回り込みの解除 @clear" data-h3="回り込みの解除 @clear">回り込みの解除 <code>@clear</code></h3>'
          rules = [{ 'f' => '@clear', 'r' => '<div class="floatclear"></div>' }]

          out = run_rules(html, rules)

          assert_includes out, 'data-heading="回り込みの解除 @clear"'
          assert_includes out, 'data-h3="回り込みの解除 @clear"'
          assert_includes out, '<code>@clear</code>'
        end

        def test_text_only_rule_substitutes_plain_text_only
          html = '<h3 data-heading="回り込みの解除 @clear">回り込みの解除 <code>@clear</code></h3><p>本文中の @clear は展開される。</p>'
          rules = [{ 'f' => '@clear', 'r' => '<div class="floatclear"></div>' }]

          out = run_rules(html, rules)

          assert_includes out, 'data-heading="回り込みの解除 @clear"'
          assert_includes out, '<code>@clear</code>'
          assert_match(%r{<p>本文中の <div class="floatclear"></div> は展開される。</p>}, out)
        end

        def test_text_only_rule_does_not_confuse_attribute_with_similar_text
          # 属性値に `:::` が入っていても text-only ルールは触れない
          html = '<div data-note=":::">内容 :::</div>'
          rules = [{ 'f' => ':{3,}', 'r' => '</div>' }]

          out = run_rules(html, rules)

          assert_includes out, 'data-note=":::"'
          assert_includes out, '内容 </div>'
        end

        # =============================================================
        # 既存の挙動（テキストノードの置換）が壊れていないこと
        # =============================================================

        def test_no_op_when_no_match
          html = '<p>ただの段落。</p>'
          rules = [{ 'f' => '@nonexistent', 'r' => '<span>x</span>' }]
          out = run_rules(html, rules)
          assert_equal html, out
        end

        def test_returns_changed_false_when_only_protected_matches
          # <pre>/<code>/属性値 内だけにマッチするルールは、実質「無変更」で返る
          html = "<p data-x=\"@clear\">普通の段落</p>\n<pre><code>@clear</code></pre>\n"
          rules = [{ 'f' => '@clear', 'r' => '<div class="floatclear"></div>' }]

          result = nil
          with_html(html) do |path|
            result = HtmlReplacer.process_html_file(path, rules)
          end

          assert_equal({ changed: false, replacements: 0 }, result)
        end

        # =============================================================
        # rule_mode 判定
        # =============================================================

        def test_rule_mode_classification
          assert_equal :code_aware,
                       HtmlReplacer.rule_mode('<span class="token comment"([^>]*)>#←')
          assert_equal :text_only, HtmlReplacer.rule_mode('@clear')
          assert_equal :text_only, HtmlReplacer.rule_mode('@posi:(\\d+)')
          assert_equal :text_only, HtmlReplacer.rule_mode(':{3,}')
          assert_equal :text_only, HtmlReplacer.rule_mode('〘')
          assert_equal :tag_aware, HtmlReplacer.rule_mode('<p[^>]*>【先生([^】]+)】')
          assert_equal :tag_aware, HtmlReplacer.rule_mode('<hr>')
          assert_equal :tag_aware, HtmlReplacer.rule_mode('<p></p>')
        end
      end
    end
  end
end
