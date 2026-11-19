# frozen_string_literal: true

# ================================================================
# Test: pre_process/inline_span_transformer_test.rb
# ================================================================
# テスト対象:
#   PreProcessCommands::InlineSpanTransformer（行内の属性 `[文字]{.class}` → span）
#   と、前処理の段の並びの中での働き（MarkdownPreprocessor の transform_inline_spans!）。
#
# 検証内容:
#   - 傍点・縦中横・複数のクラス・索引語を中に入れた形を span にする
#   - コード・画像・インライン脚注・`\[`・クラス以外の属性・行末の段落の寄せは読まない
#   - 原稿を読む検査（each_span）は、変換と同じ箇所を拾う
#   - 中を Kramdown で組む段（会話）より前に走り、会話の中でも span になる
# ================================================================

require 'test_helper'
require 'vivlio_starter/cli/pre_process/inline_span_transformer'
require 'vivlio_starter/cli/pre_process/markdown_preprocessor'

module VivlioStarter
  module CLI
    module PreProcessCommands
      class InlineSpanTransformerTest < Minitest::Test
        def test_should_turn_bracketed_text_with_classes_into_span
          assert_equal '本文<span class="sesame">傍点</span>と<span class="tcy">12</span>。',
                       InlineSpanTransformer.transform('本文[傍点]{.sesame}と[12]{.tcy}。')
          assert_equal '<span class="sesame red">強く</span>', InlineSpanTransformer.transform('[強く]{.sesame .red}')
        end

        # 中の Markdown（索引語・強調・ルビ）は span の中にそのまま残し、後の段が読む
        def test_should_keep_inner_markdown_for_later_steps
          assert_equal '<span class="sesame">[用語]と**強調**と{漢字|かんじ}</span>',
                       InlineSpanTransformer.transform('[[用語]と**強調**と{漢字|かんじ}]{.sesame}')
        end

        def test_should_leave_code_images_footnotes_and_other_attributes_as_written
          source = <<~MD
            `[a]{.b}` ![図](x.png){.c} 注^[本文]{.d} \\[e]{.f} [g]{#id} [h]{width=50%}
            ```
            [i]{.j}
            ```
          MD

          assert_equal source, InlineSpanTransformer.transform(source)
        end

        # 行末の `{.text-right}` などは段落の寄せの記法（transform_text_right_inlines!）
        def test_should_leave_paragraph_align_at_line_end
          assert_equal "右に寄せる[用語]{.text-right}\n", InlineSpanTransformer.transform("右に寄せる[用語]{.text-right}\n")
          assert_equal "途中の<span class=\"text-right\">語</span>は span\n",
                       InlineSpanTransformer.transform("途中の[語]{.text-right}は span\n")
        end

        def test_each_span_should_find_the_same_places_as_transform
          spans = InlineSpanTransformer.each_span('`[a]{.b}` [傍点]{.sesame .x} 右[用語]{.text-right}')

          assert_equal [['傍点', %w[sesame x], '[傍点]{.sesame .x}']], spans.map { [it.text, it.classes, it.source] }
        end

        # 会話の中は Kramdown で HTML にする。その段より前に span にしておくと、会話の中でも働く
        def test_preprocessor_should_run_before_talk_blocks
          names = MarkdownPreprocessor::STEPS.map(&:first)

          assert_operator names.index(:transform_inline_spans!), :<, names.index(:transform_talk!)
          assert_operator names.index(:transform_inline_spans!), :<, names.index(:transform_text_align_containers!)
          assert_operator names.index(:transform_inline_spans!), :<, names.index(:strip_index_markup!)
        end
      end
    end
  end
end
