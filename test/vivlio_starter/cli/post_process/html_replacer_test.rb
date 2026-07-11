# frozen_string_literal: true

require 'minitest/autorun'
require 'tempfile'
require_relative '../../../../lib/vivlio_starter/cli/post_process/replacement_rules'

module VivlioStarter
  module CLI
    module PostProcessCommands
      # HtmlReplacer は ReplacementRules の組み込みルール（Rule 配列）を HTML に適用する
      # エンジン。<pre>…</pre>（コードブロック）と <code>…</code>（インラインコード）、
      # および全タグ定義は「書き方の説明」の一部なので、保護モードに応じて置換対象から
      # 除外される。ここではエンジンの保護挙動を Rule 単位で検証する。
      class HtmlReplacerTest < Minitest::Test
        Rule = ReplacementRules::Rule

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
            <p>@vspace:10 を書くと下に余白を入れます。</p>
            <pre><code class="language-markdown">本文の流れ。

            @vspace:10

            次の段落を 10mm 下げて始めたい。
            </code></pre>
          HTML
          rules = [Rule.new(/@vspace:(\d+)/m, '<div style="margin-top:$1mm"></div>', :text_only)]

          out = run_rules(html, rules)

          # <pre> の外側は置換される
          assert_match(%r{<p><div style="margin-top:10mm"></div> を書くと下に余白を入れます。</p>}, out)
          # <pre> の中身は「書かれたそのまま」
          assert_includes out, '@vspace:10'
          refute_match(%r{<pre>.*?<div style="margin-top:10mm"></div>.*?</pre>}m, out)
        end

        def test_preserves_multiple_macros_inside_pre
          html = <<~HTML
            <pre><code class="language-markdown">:::{.memo}
            1 行だけクラス付き div で囲みたいとき。
            :::
            </code></pre>
            :::
          HTML
          rules = [
            Rule.new(%r{:{3,}\s*\{\.?([a-z0-9.\-_\s]+)\}}m, '<div class="$1">', :text_only),
            Rule.new(%r{:{3,}}m, '</div>', :text_only)
          ]

          out = run_rules(html, rules)

          # <pre> 内の :::{.memo} / ::: は原文のまま残る
          assert_includes out, ':::{.memo}'
          pre_body = out[%r{<pre>.*?</pre>}m]
          assert_includes pre_body, ':::'
          # <pre> の外の ::: は置換される
          refute_match(%r{</pre>\s*:::}m, out)
          assert_match(%r{</pre>\s*</div>}m, out)
        end

        def test_preserves_full_width_kbd_markers_inside_pre
          html = <<~HTML
            <pre><code class="language-markdown">保存は 〘Ctrl〙 + 〘S〙 で行います。
            </code></pre>
            <p>保存は 〘Ctrl〙 + 〘S〙 で行います。</p>
          HTML
          rules = [
            Rule.new(/〘/m, '<kbd>', :text_only),
            Rule.new(/〙/m, '</kbd>', :text_only)
          ]

          out = run_rules(html, rules)

          # <pre> 内は原文維持
          pre_body = out[%r{<pre>.*?</pre>}m]
          assert_includes pre_body, '〘Ctrl〙'
          refute_includes pre_body, '<kbd>'
          # <pre> 外は置換される
          assert_match(%r{<p>保存は <kbd>Ctrl</kbd> \+ <kbd>S</kbd> で行います。</p>}, out)
        end

        # =============================================================
        # インライン <code> 保護
        # =============================================================

        def test_preserves_inline_code_content
          html = '<p>本文中で <code>@vspace:10</code> と書くと、下に余白を入れます。</p>'
          rules = [Rule.new(/@vspace:10/m, '<div style="margin-top:10mm"></div>', :text_only)]

          out = run_rules(html, rules)

          # インラインコードは温存
          assert_includes out, '<code>@vspace:10</code>'
          refute_includes out, '<code><div style="margin-top:10mm"></div></code>'
        end

        # =============================================================
        # タグ定義（属性値を含む）の内側では置換しない
        # =============================================================

        # `@vspace` などのマクロが HeadingProcessor によって data-heading 属性に
        # コピーされた後、text_only ルールが属性値内の `@vspace:10` を置換してしまい、
        # `data-heading="... <div style=\"margin-top:10mm\"></div> ..."` となって
        # 属性値内の `"` で HTML 解析が破綻する事故を防ぐ。
        def test_text_only_rule_does_not_substitute_inside_attribute_values
          html = '<h3 id="x" data-heading="余白の調整 @vspace:10" data-h3="余白の調整 @vspace:10">余白の調整 <code>@vspace:10</code></h3>'
          rules = [Rule.new(/@vspace:10/m, '<div style="margin-top:10mm"></div>', :text_only)]

          out = run_rules(html, rules)

          assert_includes out, 'data-heading="余白の調整 @vspace:10"'
          assert_includes out, 'data-h3="余白の調整 @vspace:10"'
          assert_includes out, '<code>@vspace:10</code>'
        end

        def test_text_only_rule_substitutes_plain_text_only
          html = '<h3 data-heading="余白の調整 @vspace:10">余白の調整 <code>@vspace:10</code></h3><p>本文中の @vspace:10 は展開される。</p>'
          rules = [Rule.new(/@vspace:10/m, '<div style="margin-top:10mm"></div>', :text_only)]

          out = run_rules(html, rules)

          assert_includes out, 'data-heading="余白の調整 @vspace:10"'
          assert_includes out, '<code>@vspace:10</code>'
          assert_match(%r{<p>本文中の <div style="margin-top:10mm"></div> は展開される。</p>}, out)
        end

        def test_text_only_rule_does_not_confuse_attribute_with_similar_text
          # 属性値に `:::` が入っていても text_only ルールは触れない
          html = '<div data-note=":::">内容 :::</div>'
          rules = [Rule.new(/:{3,}/m, '</div>', :text_only)]

          out = run_rules(html, rules)

          assert_includes out, 'data-note=":::"'
          assert_includes out, '内容 </div>'
        end

        # =============================================================
        # 既存の挙動（テキストノードの置換）が壊れていないこと
        # =============================================================

        def test_no_op_when_no_match
          html = '<p>ただの段落。</p>'
          rules = [Rule.new(/@nonexistent/m, '<span>x</span>', :text_only)]
          out = run_rules(html, rules)
          assert_equal html, out
        end

        def test_returns_changed_false_when_only_protected_matches
          # <pre>/<code>/属性値 内だけにマッチするルールは、実質「無変更」で返る
          html = "<p data-x=\"@vspace:10\">普通の段落</p>\n<pre><code>@vspace:10</code></pre>\n"
          rules = [Rule.new(/@vspace:10/m, '<div style="margin-top:10mm"></div>', :text_only)]

          result = nil
          with_html(html) do |path|
            result = HtmlReplacer.process_html_file(path, rules)
          end

          assert_equal({ changed: false, replacements: 0 }, result)
        end

        # =============================================================
        # tag_aware モード: <pre> のみ退避して全体に適用
        # =============================================================

        def test_tag_aware_rule_applies_outside_pre_only
          html = "<p><div class=\"box\">\n<pre><code class=\"language-html\">&lt;p&gt;&lt;div class=\"x\"&gt;</code></pre>"
          rules = [Rule.new(%r{<p>\s*(<div class="[^"]+">)}m, '$1', :tag_aware)]

          out = run_rules(html, rules)

          # <pre> の外の <p><div ...> は裸の div になる
          assert_match(%r{^<div class="box">}, out)
          refute_match(%r{<p>\s*<div class="box">}, out)
          # <pre> 内の実体参照テキストは不変
          assert_includes out, '&lt;p&gt;&lt;div class="x"&gt;'
        end
      end
    end
  end
end
