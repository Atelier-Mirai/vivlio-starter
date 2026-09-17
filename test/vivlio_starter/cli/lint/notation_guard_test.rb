# frozen_string_literal: true

# ================================================================
# Test: notation_guard_test.rb
# ================================================================
# テスト対象:
#   Lint::NotationGuard（lib/vivlio_starter/cli/lint/notation_guard.rb）
#
# 検証内容:
#   - G1 機械データ・ブロック（:::{.showcase} / .output / .terminal）の空行化と、未終了時の据え置き
#   - G2 コンテナのマーカー行の空行化（内部の地の文は残す）
#   - G3 ふりがな記法（親文字は地の文なので残す）
#   - G4 クラス属性記法の除去
#   - G6 fancy list のマーカーを標準リストへ読み替える（字下げの保存・誤爆防止）
#   - コード領域（フェンス・インラインコード）を 1 文字も変えないこと
#   - I1 行数の保存
#
# 仕様: lint-notation-guard-spec.md §3
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

        # 実行結果・ログは機械が出した文字列なので、著者が直せる指摘にならない。
        # 同じ文字列がすぐ上のフェンスにも書かれることが多く（記法とその表示例）、
        # 外さないと**フェンスの外に置いた片方だけ**が指摘される
        def test_should_blank_out_output_and_terminal_blocks
          source = <<~MD
            次のように表示されます。

            :::{.output}
            @ruby-sample は、Ruby で画面表示を行うサンプルコードです
            :::

            :::{.terminal}
            $ vs build
            :::

            以上です。
          MD

          result = NotationGuard.strip_notation(source)

          refute_includes result, 'サンプルコード', '出力例は地の文として読ませない'
          refute_includes result, 'vs build', 'ターミナルの入力例も同じ'
          assert_includes result, '次のように表示されます。', '地の文はそのまま残す'
          assert_equal source.lines.size, result.lines.size, 'I1 行数の保存'
        end

        # 普通の文章を書く囲みは対象外。一律に外すと本物の誤りを見逃す
        def test_should_keep_prose_containers_visible
          source = ":::{.column}\nここは普通の文章です。\n:::\n"

          assert_includes NotationGuard.strip_notation(source), 'ここは普通の文章です。'
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
        # G6: fancy list のマーカー
        # ----------------------------------------------------------------
        # textlint のパーサは Pandoc 由来のマーカーを知らず、リストを段落として読む。
        # 標準の `-` へ読み替えて、箇条書きのための検査（ListItem の除外）へ載せる。
        def test_should_rewrite_fancy_list_markers_as_standard_list_items
          source = "(1) 括弧付き数字の項目\n(2) 二番目の項目\na. 英字の項目\n(iv) ローマ数字の項目\n"

          assert_equal "- 括弧付き数字の項目\n- 二番目の項目\n- 英字の項目\n- ローマ数字の項目\n",
                       NotationGuard.strip_notation(source)
        end

        # 入れ子は字下げで表すので、字下げを保ったまま読み替える。
        def test_should_keep_indent_of_nested_fancy_list_markers
          source = "1. 概要\n   (a) 選択肢イ\n   (b) 選択肢ロ\n2. インストール方法\n"

          assert_equal "1. 概要\n   - 選択肢イ\n   - 選択肢ロ\n2. インストール方法\n",
                       NotationGuard.strip_notation(source)
        end

        # 大文字＋ピリオドに空白 1 つは前処理もリストにしない（`B. Russell` 誤爆防止）。
        # 判定に迷う行はガードしない＝素のまま渡す。
        def test_should_not_rewrite_a_sentence_that_begins_like_an_uppercase_marker
          source = "B. Russell は哲学者です。\n"

          assert_equal source, NotationGuard.strip_notation(source)
        end

        def test_should_not_rewrite_fancy_list_markers_inside_code_fence
          source = "書き方は次のとおりです。\n\n```markdown\n(1) 括弧付き数字の項目\n```\n"

          assert_equal source, NotationGuard.strip_notation(source),
                       'フェンス内の記法解説は 1 文字も変えないこと'
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

        # 値つきの属性記法は機械データであって地の文ではない（G5）。放置すると
        # `{width=20%}` の半角 % が「全角にせよ」と指摘され、`--fix` が当たれば
        # `{width=20％}` になって**画像の幅指定が効かなくなる**（実測: 本書の前書きで 4 件）。
        def test_should_neutralize_value_attributes_in_the_analysis_path
          stripped = NotationGuard.strip_notation("![](logo.webp){width=20%}\n")

          refute_includes stripped, 'width=20%', '幅指定は地の文として読ませない'
          assert_includes stripped, '![](logo.webp)', '画像記法そのものは残す'
        end

        # クラスと幅を併記した形（どちらの順でも）も対象にする
        def test_should_neutralize_value_attributes_written_with_a_class
          ['![](a.webp){.bordered width=20%}', '![](a.webp){width=20% .bordered}'].each do |line|
            refute_includes NotationGuard.strip_notation("#{line}\n"), 'width=20%', line
          end
        end

        # ふりがな `{親文字|ふりがな}` を属性と取り違えない（親文字は地の文なので残す・I3）
        def test_should_not_mistake_furigana_for_an_attribute
          stripped = NotationGuard.strip_notation("{難読|なんどく}な字。\n")

          assert_equal "難読な字。\n", stripped
        end

        # 修正パスは退避して守る。strip_notation は非可逆なので --fix では使えず、
        # 目印へ逃がして戻すしかない
        def test_should_mask_and_restore_value_attributes_for_the_fix_path
          src = "![](logo.webp){width=20%}\n地の文の 20% は直されるべきです。\n"
          masked, spans = NotationGuard.mask_for_fix(src)

          refute_includes masked, 'width=20%', '属性は目印へ退避される'
          assert_includes masked, '地の文の 20% は', '地の文の % は残す（本物の指摘を消さない）'
          assert_equal 1, spans.size
          assert_equal src, NotationGuard.restore_masked(masked, spans), '往復で原文に戻る'
        end

        # 修正パスは数式と属性を同時に守る（どちらも 1 つの spans で戻せる）
        def test_should_mask_both_math_and_attributes_for_the_fix_path
          src = "$(4/3)πr³$ の図です。\n\n![](sphere.webp){width=50%}\n"
          masked, spans = NotationGuard.mask_for_fix(src)

          assert_equal 2, spans.size
          assert_equal src, NotationGuard.restore_masked(masked, spans)
        end

        # 数式は日本語の文ではない。放置すると数式の中の半角括弧が prh に「全角にせよ」と
        # 指摘され、`--fix` が当たれば `$(4/3)πr³$` が `$（4/3）πr³$` になって壊れる。
        # コードスパンは textlint が Code ノードとして飛ばすのに、数式は素の文として読まれていた。
        def test_should_mask_math_from_the_linter
          src = "球の体積は $(4/3)πr³$ です。地の文の (4/3) は直されるべきです。\n"
          masked, spans = NotationGuard.mask_math(src)

          refute_includes masked, '(4/3)πr³', '数式は目印へ退避される'
          assert_includes masked, '地の文の (4/3) は', '地の文の括弧は残す（本物の指摘を消さない）'
          assert_equal 1, spans.size
          assert_equal src, NotationGuard.restore_masked(masked, spans), '往復で原文に戻る'
        end

        # 行数を保存する（I1）。複数行のディスプレイ数式でも指摘の行番号がずれない。
        def test_should_preserve_line_count_when_masking_multi_line_display_math
          src = "前。\n\n$$\n面積 = π × r²\n= πr²\n$$\n\n後。\n"
          masked, spans = NotationGuard.mask_math(src)

          assert_equal src.lines.size, masked.lines.size
          assert_equal src, NotationGuard.restore_masked(masked, spans)
        end

        # コード領域の中の数式らしい綴りは触らない（記法を解説する行を壊さない）。
        def test_should_not_mask_math_inside_code
          src = "インライン数式は `$x^2$` と書きます。\n"
          masked, spans = NotationGuard.mask_math(src)

          assert_equal src, masked
          assert_empty spans
        end

        # strip_notation（解析パス）にも効いている。
        def test_strip_notation_should_neutralize_math
          stripped = NotationGuard.strip_notation("球の体積は $(4/3)πr³$ です。\n")

          refute_includes stripped, '(4/3)'
        end
      end
    end
  end
end
