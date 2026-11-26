# frozen_string_literal: true

# ================================================================
# Test: pre_process/web_novel_mark_transformer_test.rb
# ================================================================
# テスト対象:
#   PreProcessCommands::WebNovelMarkTransformer（投稿サイトの書き方 → vs の記法。
#   novel-vertical-spec.md §5.4）と、前処理の段の並びの中での位置と条件。
#
# 検証内容:
#   - 縦棒のルビ（半角・全角）は、親文字と読みの字の種類を問わずルビにする
#   - 縦棒の無いルビは、親文字が漢字の並びで読みが仮名だけのときに限る
#   - 傍点 `《《文字》》` は行内の属性の傍点にする
#   - 打ち消し `|《` は `《` を字のまま残す
#   - 行頭の全角空白は 1 つだけ落とす（lint の読み替えでは落とさない）
#   - コード・vs のルビ・表の区切りの縦棒は読まない
#   - 段は notation.web_novel が有効な本でだけ走り、行内の属性の段より前にある
# ================================================================

require 'test_helper'
require 'vivlio_starter/cli/pre_process/web_novel_mark_transformer'
require 'vivlio_starter/cli/pre_process/markdown_preprocessor'

module VivlioStarter
  module CLI
    module PreProcessCommands
      class WebNovelMarkTransformerTest < Minitest::Test
        def transform(text, **) = WebNovelMarkTransformer.transform(text, **)

        def test_should_turn_bar_ruby_into_vs_ruby_whatever_the_letters
          assert_equal '吾輩は{猫|ねこ}である。{名前|なまえ}は{魔導書|グリモワール}。二{疋|ひき}',
                       transform('吾輩は|猫《ねこ》である。｜名前《なまえ》は|魔導書《グリモワール》。二｜疋《ひき》')
        end

        # 小説家になろうの自動のルビと同じ条件。読みに漢字があれば、地の文の《》として残す
        def test_should_turn_bare_ruby_only_when_the_reading_is_kana
          assert_equal '{東京|とうきょう}と{佐々木|ササキー}と{〆切|しめきり}と{三ヶ月|さんかげつ}',
                       transform('東京《とうきょう》と佐々木《ササキー》と〆切《しめきり》と三ヶ月《さんかげつ》')
          assert_equal '題名《本の題》・ひらがな《かな》', transform('題名《本の題》・ひらがな《かな》')
        end

        def test_should_turn_double_angle_brackets_into_sesame
          assert_equal '[強く]{.sesame}言った。{漢字|かんじ}', transform('《《強く》》言った。漢字《かんじ》')
        end

        def test_should_keep_escaped_angle_bracket_as_written
          assert_equal '題は《禁書》と読める。漢字《かな》', transform('題は|《禁書》と読める。漢字｜《かな》')
        end

        def test_should_drop_one_leading_ideographic_space
          source = "　一つ目の段落。\n「会話」\n　　二つの空白。\n文中の　空白。\n"

          assert_equal "一つ目の段落。\n「会話」\n　二つの空白。\n文中の　空白。\n", transform(source)
          assert_equal source, transform(source, drop_indent: false), 'lint の読み替えは字下げを残す'
        end

        def test_should_leave_code_vs_ruby_and_table_separators
          source = <<~MD
            `|猫《ねこ》` と {漢字|かんじ}《ルビ》と {漢字|かん}は。
            ```
            　|猫《ねこ》
            ```
            | 列 | 漢字《かんじ》 |
          MD
          expected = <<~MD
            `|猫《ねこ》` と {漢字|かんじ}《ルビ》と {漢字|かん}は。
            ```
            　|猫《ねこ》
            ```
            | 列 | {漢字|かんじ} |
          MD

          assert_equal expected, transform(source)
        end

        # 読み替えの結果は行数が変わらない（lint の行番号がずれない）
        def test_should_keep_the_line_count
          source = "　|猫《ねこ》\n《《傍点》》\n\n　地の文\n"

          assert_equal source.count("\n"), transform(source).count("\n")
        end

        # 傍点を [文字]{.sesame} にするので、行内の属性を span にする段より前に走る。
        # 有効にすると既存の本の出力が変わるので、notation.web_novel が有効な本でだけ走る
        def test_preprocessor_should_run_only_for_web_novel_books_before_inline_spans
          names = MarkdownPreprocessor::STEPS.map(&:first)
          _method, _kind, condition = MarkdownPreprocessor::STEPS.assoc(:transform_web_novel_marks!)
          plan = BuildPlan.resolve

          assert_operator names.index(:transform_web_novel_marks!), :<, names.index(:transform_inline_spans!)
          refute condition.call(plan.with(features: plan.features.with(web_novel: false)))
          assert condition.call(plan.with(features: plan.features.with(web_novel: true)))
        end
      end
    end
  end
end
