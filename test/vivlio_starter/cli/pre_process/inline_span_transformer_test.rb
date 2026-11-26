# frozen_string_literal: true

# ================================================================
# Test: pre_process/inline_span_transformer_test.rb
# ================================================================
# テスト対象:
#   PreProcessCommands::InlineSpanTransformer（行内の属性 `[文字]{…}` → span・蛍光ペン `==文字==` → mark）
#   と、前処理の段の並びの中での働き（MarkdownPreprocessor の transform_inline_spans!）。
#   v2 の同じテストを写し、色の記法（inline-color-mark-spec.md §11 の 1〜3）を足したもの。
#
# 検証内容:
#   - §3 の表の全部（クラス・color=・background=・theme・==…==・並べた形）
#   - エスケープ・大文字の値・後ろの値が勝つ・読めない値は色を付けない
#   - コード・数式・画像・インライン脚注・`\[`・知らないキー・行末の段落のクラス・`a == b`・`=` の行は読まない
#   - 原稿を読む検査（each_span）は、変換と同じ箇所を拾い、知らないキーを書いたものも拾う
#   - 中を Kramdown で組む段（会話・表）より前に走る
# ================================================================

require 'test_helper'
require 'vivlio_starter/cli/pre_process/inline_span_transformer'
require 'vivlio_starter/cli/pre_process/markdown_preprocessor'
require 'vivlio_starter/cli/token_resolver'
require 'tmpdir'

module VivlioStarter
  module CLI
    module PreProcessCommands
      class InlineSpanTransformerTest < Minitest::Test
        def transform(source) = InlineSpanTransformer.transform(source)

        # --- phase: クラス（v2 と同じ） ---

        def test_should_turn_bracketed_text_with_classes_into_span
          assert_equal '本文<span class="sesame">傍点</span>と<span class="tcy">12</span>。',
                       transform('本文[傍点]{.sesame}と[12]{.tcy}。')
          assert_equal '<span class="red small">字</span>', transform('[字]{.red .small}')
        end

        # 中の Markdown（索引語・強調・ルビ）は span の中にそのまま残し、後の段が読む
        def test_should_keep_inner_markdown_for_later_steps
          assert_equal '<span class="red">[用語]と**強調**と{漢字|かんじ}</span>',
                       transform('[[用語]と**強調**と{漢字|かんじ}]{.red}')
          assert_equal '<span class="red">[用語]</span>', transform('[[用語]]{.red}')
        end

        # --- phase: 文字の色（§1.1・§3） ---

        def test_should_write_css_color_values_as_style
          assert_equal '<span class="vs-color" style="color: #3a9d5d">緑</span>', transform('[緑]{color=#3A9D5D}')
          assert_equal '<span class="vs-color" style="color: rebeccapurple">字</span>', transform('[字]{color=RebeccaPurple}')
          assert_equal '<span class="small vs-color" style="color: red">字</span>', transform('[字]{.small color=red}')
          assert_equal '<span class="vs-text-theme">字</span>', transform('[字]{color=theme}')
        end

        # 同じキーを 2 回書いたら後ろの値。読めない値は色を付けない（🟡 は ContainerClassCheck）
        def test_should_use_last_value_and_drop_unreadable_color
          assert_equal '<span class="vs-color" style="color: blue">字</span>', transform('[字]{color=red color=blue}')
          assert_equal '<span>字</span>', transform('[字]{color=rde}')
          assert_equal '<span>字</span>', transform('[字]{color=rgb(0,0,0)}')
          assert_equal '<span class="red">字</span>', transform('[字]{.red color="><script>}')
        end

        # --- phase: 蛍光ペン（§1.3・§3） ---

        def test_should_turn_double_equals_into_mark
          assert_equal '大事な<mark>ところ</mark>です', transform('大事な==ところ==です')
          assert_equal '<mark class="green">字</mark>', transform('==字=={.green}')
          assert_equal '<mark style="--_mark-color: #fff3a0">字</mark>', transform('==字=={background=#FFF3A0}')
          assert_equal '<mark class="vs-color" style="color: red">字</mark>', transform('==字=={color=red}')
          assert_equal '<mark class="theme">字</mark>', transform('==字=={background=theme}')
        end

        # `[…]{background=…}` も同じ蛍光ペン。`[…]` のクラスは字の色なので、中の span に付ける
        def test_should_turn_bracket_with_background_into_mark
          assert_equal '<mark style="--_mark-color: #fff3a0">字</mark>', transform('[字]{background=#fff3a0}')
          assert_equal '<mark class="theme">字</mark>', transform('[字]{background=theme}')
          assert_equal '<mark class="vs-color" style="color: red; --_mark-color: yellow">字</mark>',
                       transform('[字]{color=red background=yellow}')
          assert_equal '<mark style="--_mark-color: yellow"><span class="red">字</span></mark>',
                       transform('[字]{.red background=yellow}')
        end

        def test_should_nest_colored_text_inside_mark
          assert_equal '<mark><span class="red">注意</span></mark>', transform('==[注意]{.red}==')
          assert_equal '<mark><code>x</code></mark>', transform('==<code>x</code>==')
        end

        # 内側の両端が空白のもの・`=` だけの行（Setext 見出しの下線）・`\==` は読まない
        def test_should_leave_comparisons_and_setext_underlines
          source = "a == b と x == y == z\n見出し\n======\n\\==字==\n"

          assert_equal source, transform(source)
        end

        # --- phase: 読まないもの ---

        def test_should_leave_code_math_images_footnotes_and_other_attributes_as_written
          source = <<~MD
            `[a]{.b}` `==c==` ![図](x.png){.c} 注^[本文]{.d} \\[e]{.f} [g]{#id} [h]{width=50%} [i]{foo=bar}
            $a==b==c$ と $$[x]{.y}$$
            ```
            [i]{.j} ==k==
            ```
          MD

          assert_equal source, transform(source)
        end

        # 行末の `{.text-right}`・`{.aki}` などは段落に付けるクラスの記法
        def test_should_leave_paragraph_attribute_at_line_end
          assert_equal "右に寄せる[用語]{.text-right}\n", transform("右に寄せる[用語]{.text-right}\n")
          assert_equal "空ける[用語]{.aki}\n", transform("空ける[用語]{.aki}\n")
          assert_equal "途中の<span class=\"text-right\">語</span>は span\n", transform("途中の[語]{.text-right}は span\n")
          assert_equal "<mark>大事</mark>{.aki}\n", transform("==大事=={.aki}\n")
        end

        # --- phase: 検査の走査 ---

        def test_each_span_should_find_spans_marks_and_unknown_keys
          line = '`[a]{.b}` [傍点]{.sesame .x} [字]{foo=bar} ==字=={colour=red} ==字== 右[用語]{.text-right}'
          spans = InlineSpanTransformer.each_span(line)

          assert_equal [['[傍点]{.sesame .x}', %w[sesame x], []],
                        ['[字]{foo=bar}', [], [%w[foo bar]]],
                        ['==字=={colour=red}', [], [%w[colour red]]]],
                       spans.map { [it.source, it.classes, it.pairs] }
          assert_equal '[字]{color=bar}', spans[1].with_item('foo=bar', 'color=bar')
        end

        # まだ受けない書き方を #rrggbb へ直した形（🟡 の候補）
        def test_should_convert_unsupported_color_forms_to_hex
          assert_equal '#000000', InlineSpanTransformer.hex_of_unsupported('rgb(0,0,0)')
          assert_equal '#ffff00', InlineSpanTransformer.hex_of_unsupported('#ffff0080')
          assert_equal '#aabbcc', InlineSpanTransformer.hex_of_unsupported('#abcf')
          assert_nil InlineSpanTransformer.hex_of_unsupported('hsl(0,0%,0%)')
        end

        # HTML ブロックの境目に空行を入れる段（normalize_html_block_boundaries!）は、文の途中の
        # `</span>**` を割らない。行全体が HTML の行と `</small>## 見出し` は今までどおり割る
        def test_html_block_boundaries_should_keep_inline_span_in_paragraph
          Dir.mktmpdir do |dir|
            path = File.join(dir, '50-sample.md')
            File.write(path, "# 見出し\n")
            entry = CLI::TokenResolver::Entry.new(number: '50', slug: 'sample', kind: :chapter, label: 'サンプル',
                                                  path:, exists: true, in_catalog: true, valid: true)
            pre = MarkdownPreprocessor.new(path, entry)
            pre.context.content = "太字 **#{transform('[注意]{.red}')}**・[字]{.red}-b\n" \
                                  "<span class=\"x\">a</span>## 見出し\n<small>注</small>## 節\n"
            pre.send(:normalize_html_block_boundaries!)

            assert_equal "太字 **<span class=\"red\">注意</span>**・[字]{.red}-b\n" \
                         "<span class=\"x\">a</span>\n\n## 見出し\n<small>注</small>\n\n## 節\n", pre.context.content
          end
        end

        # --- phase: 前処理の段の並び ---

        # 会話・表の中は Kramdown で HTML にする。その段より前に span にしておくと、中でも働く。
        # 索引の印を外す段より前なので、`[[用語]]{.red}` の `[用語]` は索引に載る
        def test_preprocessor_should_run_before_kramdown_steps
          file, line = MarkdownPreprocessor.instance_method(:run).source_location
          body = File.readlines(file)[line..].take_while { it.strip != 'end' }.map(&:strip)

          %w[transform_talk! transform_text_align_containers! transform_tables! transform_book_cards!
             transform_fancy_lists! strip_index_markup!].each do |step|
            assert_operator body.index('transform_inline_spans!'), :<, body.index(step), step
          end
          assert_operator body.index('transform_terminal_blocks!'), :<, body.index('transform_inline_spans!')
        end
      end
    end
  end
end
