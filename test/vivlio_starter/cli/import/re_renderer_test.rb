# frozen_string_literal: true

require_relative '../../../test_helper'
require 'vivlio_starter/cli/import/re_renderer'
require 'tmpdir'
require 'fileutils'

module VivlioStarter
  module CLI
    module Import
      # 記法の対応表（re-direct-import-spec.md §3）
      class ReRendererTest < Minitest::Test
        B5_TEXT_MM = 137.0

        def setup
          @tmpdir = Dir.mktmpdir('re_renderer_test')
          @report = ReReport.new
        end

        def teardown
          FileUtils.rm_rf(@tmpdir) if @tmpdir && Dir.exist?(@tmpdir)
        end

        # .re を Markdown へ通しで変換する（パーサとレンダラは常に対で使う）
        def convert(source)
          path = File.join(@tmpdir, 'chap.re')
          File.write(path, source, encoding: 'utf-8')
          nodes = ReParser.parse(path, report: @report)
          ReRenderer.new(report: @report, file: 'chap.re', text_width_mm: B5_TEXT_MM).render(nodes).strip
        end

        # ================================================================
        # 行頭構造（同 §3.1）
        # ================================================================
        def test_should_convert_headings_with_label
          assert_equal "# 章\n\n## 節 @sec-a", convert("= 章\n\n=={sec-a} 節\n")
        end

        def test_should_wrap_column_in_div
          result = convert("===[column] 題\nコラム本文。\n===[/column]\n")

          assert_equal ":::{.column}\n**題**\n\nコラム本文。\n\n:::", result
        end

        def test_should_convert_unordered_list_with_indent
          assert_equal "- 項目1\n    - 入れ子", convert(" * 項目1\n ** 入れ子\n")
        end

        # `-` は番号つきリスト。標準の番号リストと fancy list へ落とす
        def test_should_convert_ordered_list_to_markdown_standard
          assert_equal "1. 最初\n2. 次", convert(" - 1. 最初\n - 2. 次\n")
          assert_equal "(A) 甲\n(B) 乙", convert(" - (A) 甲\n - (B) 乙\n")
        end

        # Re:VIEW は「用語の次の行に説明」、Vivlio は「用語の次の行に `: 説明`」
        def test_should_convert_definition_list
          assert_equal "用語\n: 説明1。\n  説明2。", convert(" : 用語\n    説明1。\n    説明2。\n")
        end

        # ================================================================
        # 段落内の改行（同 §3.1.1）
        # ================================================================
        # 文末で終わる行の改行は残す（著者は一文一行で書いている）
        def test_should_keep_line_break_after_sentence_end
          assert_equal "一文目。\n二文目。", convert("一文目。\n二文目。\n")
        end

        # 文の途中で折り返した行は連結する（Re:VIEW はそう組んでいた）
        def test_should_join_lines_broken_mid_sentence
          assert_equal '文字列として扱うため、C言語は苦手です。', convert("文字列として扱うため、\nC言語は苦手です。\n")
        end

        def test_should_insert_space_only_between_latin_letters
          assert_equal 'Hello world', convert("Hello\nworld\n")
        end

        # ================================================================
        # コード・端末・実行結果（同 §3.2）
        # ================================================================
        # 言語名は Rouge の推定に委ねるので、ここではキャプションと本文だけを見る
        def test_should_convert_list_with_caption_and_label
          result = convert("//list[hello][あいさつ]{\nputs 1\n//}\n")

          assert_includes result, '** あいさつ @hello **'
          assert_includes result, "\nputs 1\n```"
        end

        # キャプションがファイル名に見えるときはフェンスの情報文字列へ入れる
        def test_should_put_filename_caption_into_fence
          result = convert("//list[][hello.c]{\nint main(){}\n//}\n")

          assert_includes result, '```c:hello.c'
          refute_includes result, '**'
        end

        # 外部ファイル参照は include へ。codes/ を単一の置き場所として保つ
        def test_should_convert_file_option_to_include
          result = convert("//list[][hello.c][file=source/star1/hello.c,1]{\nint main(){}\n//}\n")

          assert_equal "```include:star1/hello.c\n```", result
        end

        def test_should_wrap_terminal_and_output
          assert_includes convert("//terminal[][端末]{\n$ ls\n//}\n"), ":::{.terminal}\n```zsh"
          assert_includes convert("//output[][結果]{\nok\n//}\n"), ":::{.output}\n```text"
        end

        # 逐語ブロックの中でもインライン命令は展開する（装飾は付けない）
        def test_should_expand_inline_inside_verbatim_block
          assert_includes convert("//terminal{\n$ @<userinput>{brew install git}\n//}\n"), '$ brew install git'
        end

        # ================================================================
        # 囲み・画像・表
        # ================================================================
        def test_should_convert_boxes_to_div
          assert_includes convert("//abstract{\n導入。\n//}\n"), ':::{.chapter-lead}'
          assert_includes convert("//tip[題]{\n本文。\n//}\n"), ":::{.tip}\n**題**"
          assert_includes convert("//quote{\n引用。\n//}\n"), '> 引用。'
        end

        def test_should_convert_image_with_width_and_border
          result = convert("//image[fig1][図の説明][width=40%,border=on]\n")

          assert_includes result, '** 図の説明 @fig1 **'
          assert_includes result, '![](fig1.webp){.bordered width=40%}'
        end

        # Re:VIEW の mm 指定は版面幅に対する比率へ直す
        def test_should_convert_sideimage_width_to_percent
          result = convert("//sideimage[pic][30mm][sep=5mm,side=R]{\n脇の本文。\n//}\n")

          assert_includes result, ':::{.sideimage-right}'
          assert_includes result, '![](pic.webp){width=22%}'
        end

        # ヘッダは `-` か `=` を並べた行で区切る。セルの区切りはタブ
        def test_should_convert_tab_separated_table
          result = convert("//table[tbl1][表]{\n列A\t列B\n--------------\n値1\t値2\n//}\n")

          assert_includes result, '** 表 @tbl1 **'
          assert_includes result, "| 列A | 列B |\n| --- | --- |\n| 値1 | 値2 |"
        end

        def test_should_convert_csv_table_and_empty_cell
          result = convert("//table[][表][csv=on]{\n列A, 列B\n============\n値1, .\n//}\n")

          assert_includes result, "| 値1 |  |"
        end

        # ================================================================
        # 余白・脚注・会話
        # ================================================================
        def test_should_convert_pagebreak_and_vspace
          assert_includes convert("本文。\n\n//clearpage\n"), '@pagebreak'
          assert_includes convert("本文。\n\n//vspace[latex][7mm]\n"), '@vspace:7mm'
        end

        # //blankline は直前の段落末へ {.aki}
        def test_should_attach_aki_to_previous_paragraph
          assert_equal '本文。{.aki}', convert("本文。\n//blankline\n")
        end

        def test_should_move_footnote_definition_to_chapter_end
          result = convert("本文 @<fn>{fn1} です。\n//footnote[fn1][脚注の本文]\n")

          assert_equal "本文 [^fn1] です。\n\n[^fn1]: 脚注の本文", result
        end

        # `//talk[アイコン][名前][発話]`。名前が空ならアイコン名を話者キーにする
        def test_should_convert_talk_list
          result = convert("//talklist{\n//talk[][クラリス]{\nこんにちは。\n//}\n//talk[avatar-g]{\nどうも。\n//}\n//}\n")

          assert_includes result, ":::{.talk}\nクラリス: こんにちは。\navatar-g: どうも。\n:::"
        end

        # ================================================================
        # 落とす・残す（同 §3.4・§3.5）
        # ================================================================
        def test_should_keep_original_for_unsupported_block
          assert_equal '//hr', convert("//hr\n")
          assert_equal :unsupported, @report.findings.first.level
        end

        def test_should_report_dropped_command
          assert_empty convert("//needvspace[latex][6zw]\n")
          assert_equal :degraded, @report.findings.first.level
        end

        def test_should_report_silently_dropped_command
          assert_empty convert("//noindent\n")
          assert_equal :note, @report.findings.first.level
        end

        # 章をまたがない限りラベルはそのまま。収集だけしておく
        def test_should_collect_labels_for_later_unification
          path = File.join(@tmpdir, 'chap.re')
          File.write(path, "//image[fig1][図]\n\n=={sec-a} 節\n", encoding: 'utf-8')
          renderer = ReRenderer.new(report: @report, file: 'chap.re', text_width_mm: B5_TEXT_MM)
          renderer.render(ReParser.parse(path, report: @report))

          assert_equal %w[fig1 sec-a], renderer.labels.sort
        end
      end
    end
  end
end
