# frozen_string_literal: true

# ================================================================
# Test: notation_guard_test.rb
# ================================================================
# テスト対象:
#   Lint::NotationGuard（lib/vivlio_starter/cli/lint/notation_guard.rb）
#
# 検証内容:
#   - G1 機械データ・ブロック（:::{.showcase}）の空行化と、未終了時の据え置き
#   - G2 コンテナのマーカー行の空行化（内部の地の文は残す）
#   - G3 ふりがな記法（親文字は地の文なので残す）
#   - G4 クラス属性記法の除去
#   - コード領域（フェンス・インラインコード）を 1 文字も変えないこと
#   - I1 行数の保存
#
# 仕様: docs/specs/lint-notation-guard-spec.md §3
# ================================================================

require 'test_helper'
require 'vivlio_starter/cli/lint/notation_guard'

module VivlioStarter
  module CLI
    module Lint
      class NotationGuardTest < Minitest::Test
        # ----------------------------------------------------------------
        # G1: 機械データ・ブロック
        # ----------------------------------------------------------------
        def test_should_blank_out_whole_showcase_block
          source = <<~MD
            この画面の操作を説明します。

            :::{.showcase}
            ![バイオリンを弾くアインシュタイン](Einstein.webp)
            rect:1 530, 335, 175, 165 {pos=bottom} 愛用のバイオリン
            pointer:2 490, 130 {label="白髪"} くしゃくしゃの白髪
            :::

            以上です。
          MD

          # ブロック（3〜7 行目）は全行が空行になり、地の文と行数はそのまま残る。
          # 空行だけの期待値は heredoc だと読めないので明示的に組み立てる。
          expected = "この画面の操作を説明します。\n" + ("\n" * 7) + "以上です。\n"

          assert_equal expected, NotationGuard.strip_notation(source)
        end

        def test_should_leave_unterminated_showcase_block_untouched
          # 閉じの無いブロックは ShowcaseTransformer が消費せず本文として残るため、
          # ガードが先に消すと実在する文が textlint の目から消えてしまう。
          source = <<~MD
            :::{.showcase}
            ![図](shot.png)
            rect:1 530, 335, 175, 165 {pos=bottom} 保存ボタン
          MD

          result = NotationGuard.strip_notation(source)

          assert_includes result, 'rect:1 530, 335, 175, 165',
                          '未終了ブロックの中身はブロックとして落とさないこと'
        end

        def test_should_treat_declared_container_as_machine_data_block
          # 記法追加時の変更点が MACHINE_DATA_CONTAINERS の 1 語で済むことの担保。
          refute_includes NotationGuard::MACHINE_DATA_CONTAINERS, 'column'
          refute_match NotationGuard::MACHINE_BLOCK_OPEN, ":::{.column}\n"
          assert_match NotationGuard::MACHINE_BLOCK_OPEN, ":::{.showcase}\n"
          assert_match NotationGuard::MACHINE_BLOCK_OPEN, "::: { .showcase }\n"
          refute_match NotationGuard::MACHINE_BLOCK_OPEN, ":::{.showcase} 説明文\n",
                       '行末に本文が続く形は ShowcaseTransformer が消費しないためブロック扱いしない'
        end

        # ----------------------------------------------------------------
        # G2: コンテナのマーカー行
        # ----------------------------------------------------------------
        def test_should_blank_container_markers_but_keep_inner_prose
          source = <<~MD
            :::{.column}
            コラムの本文です。
            :::

            ::::{.note}
            入れ子のマーカーも落とします。
            ::::
          MD

          result = NotationGuard.strip_notation(source)

          assert_includes result, 'コラムの本文です。', 'コンテナ内部の地の文は検査対象のまま残すこと'
          assert_includes result, '入れ子のマーカーも落とします。'
          refute_includes result, ':::', 'マーカー行は残さないこと'
        end

        def test_should_not_blank_commented_out_container_closer
          # 94 章の実害の回帰テスト。コメントアウトされた表 `<!--::: {.long-table}` 〜
          # `:::-->` の閉じ行を「::: で始まるからマーカー」と誤認して空行化すると、
          # `-->` が消えて HTML コメントが永久に閉じず、その中身（表・数式）を読んだ
          # textlint が暴走する（CPU 99% で戻らない）。
          source = <<~MD
            本文です。

            <!--::: {.long-table}
            | 名称 | 記号 |
            |---|---|
            | 質量 | $\\text{kg}$ |
            :::-->

            本文の続きです。
          MD

          result = NotationGuard.strip_notation(source)

          assert_includes result, ":::-->\n", 'コメントの閉じを含む行はマーカー扱いせず素のまま残すこと'
          assert_includes result, '本文の続きです。'
        end

        def test_should_not_blank_marker_like_line_with_trailing_text
          source = "::: 説明文が続く行はマーカーではありません\n"

          result = NotationGuard.strip_notation(source)

          assert_includes result, '説明文が続く行はマーカーではありません',
                          'コロンの後に本文が続く行は空行化しないこと（地の文を落とさない）'
        end

        # ----------------------------------------------------------------
        # G3: ふりがな記法
        # ----------------------------------------------------------------
        def test_should_keep_base_text_of_furigana
          source = "{Albert Einstein|アルバート・アインシュタイン}が語った言葉です。\n"

          assert_equal "Albert Einsteinが語った言葉です。\n", NotationGuard.strip_notation(source)
        end

        # ----------------------------------------------------------------
        # G4: クラス属性記法
        # ----------------------------------------------------------------
        def test_should_remove_class_attribute_but_keep_surrounding_prose
          source = "この段落は右寄せにします。{.text-right}\n"

          assert_equal "この段落は右寄せにします。\n", NotationGuard.strip_notation(source)
        end

        # ----------------------------------------------------------------
        # コード領域の保全
        # ----------------------------------------------------------------
        def test_should_not_touch_notation_inside_code_fence
          # 22-extentions.md は ```markdown フェンスの中に showcase の「書き方の例」を含む。
          source = <<~MD
            書き方は次のとおりです。

            ```markdown
            :::{.showcase}
            ![図](shot.png)
            rect:1 530, 335, 175, 165 {pos=bottom} 保存ボタン
            :::
            ```

            以上です。
          MD

          assert_equal source, NotationGuard.strip_notation(source),
                       'フェンス内の記法は 1 文字も変えないこと'
        end

        def test_should_not_touch_notation_inside_inline_code
          source = "クラス属性は `{.aki}` のように書き、ルビは `{漢字|かんじ}` と書きます。\n"

          assert_equal source, NotationGuard.strip_notation(source),
                       '記法を解説しているインラインコードは壊さないこと'
        end

        # ----------------------------------------------------------------
        # I1: 行数の保存
        # ----------------------------------------------------------------
        def test_should_preserve_line_count
          sources = [
            "本文\n:::{.showcase}\n![図](a.png)\nrect:1 1, 2, 3, 4 コメント\n:::\n本文\n",
            "本文だけ\n",
            ":::{.column}\n本文\n:::\n",
            "```ruby\nputs 'hi'\n```\n",
            "末尾に改行が無い{.aki}"
          ]

          sources.each do |source|
            result = NotationGuard.strip_notation(source)
            assert_equal source.lines.count, result.lines.count,
                         "行数が保存されること: #{source.inspect}"
          end
        end

        def test_should_preserve_last_line_without_trailing_newline
          source = ":::{.showcase}\n![図](a.png)\n:::"

          result = NotationGuard.strip_notation(source)

          assert_equal "\n\n", result, '末尾に改行が無い最終行は空文字にして末尾の形状を変えないこと'
        end
      end
    end
  end
end
