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
        # 水平アキ @hspace（at-directive-tier1-spec §1.5 / §2.2）
        # =============================================================

        # 単位なしの既定は em（@vspace の既定 mm とは意図的に非対称）
        def test_should_complete_em_for_bare_hspace
          out = apply('<p>@hspace:2 ここから字下げ。</p>')

          assert_includes out, '<span class="vs-hspace" style="margin-left:2em"></span>'
        end

        def test_should_expand_hspace_with_unit_before_bare
          out = apply('<p>@hspace:10mm の水平アキ。</p>')

          assert_includes out, '<span class="vs-hspace" style="margin-left:10mm"></span>'
        end

        def test_should_expand_negative_hspace
          out = apply('<p>@hspace:-0.5 で詰める。</p>')

          assert_includes out, '<span class="vs-hspace" style="margin-left:-0.5em"></span>'
        end

        def test_should_not_expand_hspace_inside_pre
          out = apply("<pre><code class=\"language-markdown\">@hspace:2</code></pre>\n")

          assert_includes out, '@hspace:2'
          refute_includes out, 'vs-hspace'
        end

        # =============================================================
        # 改ページ @pagebreak（at-directive-tier1-spec §1.2 / §2.2）
        # =============================================================

        def test_should_convert_pagebreak_recto_and_verso
          out = apply("<p>@pagebreak:recto</p>\n<p>@pagebreak:verso</p>")

          assert_includes out, '<div class="vs-break-recto"></div>'
          assert_includes out, '<div class="vs-break-verso"></div>'
        end

        # 引数なしの裸 @pagebreak は単純改ページ（--- と等価）
        def test_should_convert_bare_pagebreak_to_simple_break
          out = apply('<p>@pagebreak</p>')

          assert_includes out, '<div class="vs-break-page"></div>'
        end

        # 不正引数は @pagebreak 部分も含めて丸ごと素通しする（否定先読みの回帰ゲート）。
        # ここで部分置換されると ":left" だけが紙面に残る。検知は前処理側の責務。
        def test_should_leave_invalid_pagebreak_argument_untouched
          out = apply('<p>@pagebreak:left</p>')

          assert_includes out, '@pagebreak:left'
          refute_includes out, 'vs-break'
        end

        # =============================================================
        # ビルド時定数 @version / @title / @today（at-directive-tier1-spec §2.3）
        # =============================================================

        # CONFIG は DI で差し替える（グローバル定数を書き換えない）
        def stub_config(version: '1.2.3', main_title: 'テスト書名')
          VivlioStarter::CLI::Common.wrap_config(
            project: { version: }, book: { main_title: }
          )
        end

        def test_should_expand_version_and_title_from_config
          rules = ReplacementRules.value_macro_rules(stub_config)
          out = Tempfile.create(['vs_rr_value_', '.html']) do |f|
            f.write('<p>本書 @title は v@version です。</p>')
            f.flush
            HtmlReplacer.process_html_file(f.path, rules)
            File.read(f.path, encoding: 'utf-8')
          end

          assert_includes out, '本書 テスト書名 は v1.2.3 です。'
        end

        # \b により @titlepage のような続き文字には反応しない
        def test_should_not_expand_macro_with_trailing_word_characters
          rules = ReplacementRules.value_macro_rules(stub_config)
          out = Tempfile.create(['vs_rr_value_', '.html']) do |f|
            f.write('<p>@titlepage と @versionup。</p>')
            f.flush
            HtmlReplacer.process_html_file(f.path, rules)
            File.read(f.path, encoding: 'utf-8')
          end

          assert_includes out, '@titlepage'
          assert_includes out, '@versionup'
        end

        # 値の $ は置換エンジンの $1〜$9 展開に食われるため無害化し、< > は HTML エスケープする
        def test_should_sanitize_dollar_and_html_in_config_values
          rules = ReplacementRules.value_macro_rules(stub_config(main_title: '<b>$1 の本</b>'))
          out = Tempfile.create(['vs_rr_value_', '.html']) do |f|
            f.write('<p>@title</p>')
            f.flush
            HtmlReplacer.process_html_file(f.path, rules)
            File.read(f.path, encoding: 'utf-8')
          end

          assert_includes out, '&lt;b&gt;&#36;1 の本&lt;/b&gt;'
          refute_includes out, '<b>'
        end

        def test_should_expand_today_in_japanese_date_format
          rules = ReplacementRules.value_macro_rules(stub_config)
          out = Tempfile.create(['vs_rr_value_', '.html']) do |f|
            f.write('<p>@today 更新</p>')
            f.flush
            HtmlReplacer.process_html_file(f.path, rules)
            File.read(f.path, encoding: 'utf-8')
          end

          assert_match(/\d{4}年\d{1,2}月\d{1,2}日 更新/, out)
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
          # 旧 yml 34 ルールから @nega/@posi/@comment の 3 本を撤去して 31 本。
          # そこへ @hspace（2 本）・@pagebreak（2 本）を追加して 35 本
          # （@version/@title/@today は CONFIG 依存のため ALL ではなく value_macro_rules）。
          assert_equal 35, ReplacementRules::ALL.size
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
