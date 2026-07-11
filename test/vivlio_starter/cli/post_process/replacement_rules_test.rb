# frozen_string_literal: true

require 'minitest/autorun'
require 'tempfile'
require_relative '../../../../lib/vivlio_starter/cli/post_process/replacement_rules'

module VivlioStarter
  module CLI
    module PostProcessCommands
      # ReplacementRules は旧 config/post_replace_list.yml の組み込み置換ルールを
      # HtmlReplacer エンジン経由で適用する。グループごとの入出力スナップショットで
      # 移植後の挙動を固定し、順序・保護モードの回帰を防ぐ。
      class ReplacementRulesTest < Minitest::Test
        # HTML を一時ファイルに書いて ALL ルールを適用し、結果文字列を返す。
        def apply(html)
          Tempfile.create(['vs_rr_test_', '.html']) do |f|
            f.write(html)
            f.flush
            ReplacementRules.apply_builtin!(f.path)
            return File.read(f.path, encoding: 'utf-8')
          end
        end

        # =============================================================
        # コンテナ（:::{.class} → <div>）
        # =============================================================

        def test_should_convert_container_open_and_close
          out = apply("<p>:::{.column}</p>\n<p>本文。</p>\n<p>:::</p>")

          assert_includes out, '<div class="column">'
          assert_includes out, '</div>'
          refute_includes out, ':::'
        end

        def test_should_flatten_multiple_container_classes
          out = apply("<p>:::{.a .b .c}</p>\n<p>本文。</p>\n<p>:::</p>")

          assert_includes out, '<div class="a b c">'
        end

        def test_should_flatten_four_container_classes
          out = apply("<p>:::{.a .b .c .d}</p>\n<p>本文。</p>\n<p>:::</p>")

          assert_includes out, '<div class="a b c d">'
        end

        def test_should_not_convert_container_inside_pre
          html = <<~HTML
            <pre><code class="language-markdown">:::{.memo}
            1 行クラス付き。
            :::</code></pre>
            <p>:::</p>
          HTML
          out = apply(html)

          assert_includes out, ':::{.memo}'
          pre_body = out[%r{<pre>.*?</pre>}m]
          assert_includes pre_body, ':::'
          # <pre> の外側の ::: は </div> になる
          assert_match(%r{</pre>\s*</div>}m, out)
        end

        # =============================================================
        # 余白マクロ
        # =============================================================

        def test_should_expand_vspace_with_unit_before_bare
          out = apply('<p>@vspace:1.5lh の余白。</p>')

          assert_includes out, '<div style="margin-top:1.5lh"></div>'
        end

        def test_should_complete_mm_for_bare_vspace
          out = apply('<p>@vspace:10 の余白。</p>')

          assert_includes out, '<div style="margin-top:10mm"></div>'
        end

        def test_should_expand_negative_vspace
          out = apply('<p>@vspace:-2lh を詰める。</p>')

          assert_includes out, '<div style="margin-top:-2lh"></div>'
        end

        # @nega/@posi（後方互換別名）・@comment/@commend（編集者コメント）は廃止済みで変換されない
        def test_should_not_expand_retired_macros
          out = apply('<p>@nega:5 と @posi:5 と @comment:メモ@commend。</p>')

          refute_includes out, 'margin-top:-5mm'
          refute_includes out, 'hen-comment'
          assert_includes out, '@nega:5'
          assert_includes out, '@comment:メモ@commend'
        end

        def test_should_not_expand_macro_inside_pre
          html = <<~HTML
            <pre><code class="language-markdown">@vspace:10
            〘Enter〙</code></pre>
          HTML
          out = apply(html)

          assert_includes out, '@vspace:10'
          refute_includes out, 'margin-top:10mm'
        end

        # =============================================================
        # リスト装飾
        # =============================================================

        def test_should_decorate_aokome_list_item
          out = apply('<li>▶青コメ項目</li>')

          assert_includes out, '<li class="aokome">青コメ項目</li>'
        end

        def test_should_decorate_akakome_list_item
          out = apply('<li>❶赤コメ項目</li>')

          assert_includes out, '<li class="akakome"><span>❶</span>赤コメ項目</li>'
        end

        def test_should_decorate_akakome_boundary_circled_number
          out = apply('<li>⓴境界の囲み数字</li>')

          assert_includes out, '<li class="akakome"><span>⓴</span>境界の囲み数字</li>'
        end

        # =============================================================
        # コード見出し h6
        # =============================================================

        def test_should_add_codetitle_class_to_h6
          out = apply('<h6 id="x">コード見出し</h6>')

          assert_includes out, '<h6 id="x" class="codetitle"><span>'
        end

        # =============================================================
        # kbd
        # =============================================================

        def test_should_convert_kbd_markers
          out = apply('<p>保存は 〘Ctrl〙 + 〘S〙 です。</p>')

          assert_includes out, '<kbd>Ctrl</kbd>'
          assert_includes out, '<kbd>S</kbd>'
        end

        def test_should_not_convert_kbd_inside_pre
          html = <<~HTML
            <pre><code class="language-markdown">〘Ctrl〙</code></pre>
          HTML
          out = apply(html)

          pre_body = out[%r{<pre>.*?</pre>}m]
          assert_includes pre_body, '〘Ctrl〙'
          refute_includes pre_body, '<kbd>'
        end

        # =============================================================
        # ねじれ修正・空段落除去
        # =============================================================

        def test_should_unwrap_p_around_div
          out = apply('<p><div class="box">中身</div></p>')

          assert_includes out, '<div class="box">中身</div>'
          refute_match(%r{<p><div}, out)
        end

        def test_should_remove_empty_paragraphs
          out = apply("<p></p>\n<p>   </p>\n<p>\u{200B}\u{00A0}&nbsp;</p>")

          refute_match(%r{<p>\s*</p>}, out)
          refute_includes out, '&nbsp;'
        end

        def test_should_classify_aki_paragraph
          out = apply('<p>ここで空ける{.aki}</p>')

          assert_includes out, '<p class="aki">ここで空ける</p>'
        end

        def test_should_classify_aki2_paragraph
          out = apply('<p>もっと空ける{.aki2}</p>')

          assert_includes out, '<p class="aki2">もっと空ける</p>'
        end

        # =============================================================
        # 廃止した記法（会話記法）は変換されない
        # =============================================================

        def test_should_not_convert_retired_kaiwa_notation
          out = apply('<p>【先生A】こんにちは。</p>')

          assert_includes out, '<p>【先生A】こんにちは。</p>'
          refute_includes out, 'kaiwa'
        end

        # =============================================================
        # 属性値保護（text_only モード）
        # =============================================================

        def test_should_not_substitute_macro_inside_attribute_value
          out = apply('<h3 data-heading="余白 @vspace:10">本文の @vspace:10。</h3>')

          assert_includes out, 'data-heading="余白 @vspace:10"'
          assert_includes out, '本文の <div style="margin-top:10mm"></div>。'
        end

        # =============================================================
        # ALL の順序検証（グループ連結順の回帰防止）
        # =============================================================

        def test_should_keep_all_in_yml_group_order
          expected = ReplacementRules::CONTAINER_RULES +
                     ReplacementRules::PAGEBREAK_RULES +
                     ReplacementRules::SPACING_MACRO_RULES +
                     ReplacementRules::LIST_DECORATION_RULES +
                     ReplacementRules::CODE_HEADING_RULES +
                     ReplacementRules::KBD_RULES +
                     ReplacementRules::PARAGRAPH_CLEANUP_RULES +
                     ReplacementRules::SPACING_CLASS_RULES

          assert_equal expected, ReplacementRules::ALL
          # 旧 yml 34 ルールから @nega/@posi/@comment の 3 本を撤去して 31 本
          assert_equal 31, ReplacementRules::ALL.size
        end

        def test_should_apply_multiline_mode_to_all_patterns
          ReplacementRules::ALL.each do |rule|
            assert (rule.pattern.options & Regexp::MULTILINE).positive?,
                   "MULTILINE 欠如: #{rule.pattern.source.inspect}"
            assert_includes %i[text_only tag_aware], rule.mode
          end
        end
      end
    end
  end
end
