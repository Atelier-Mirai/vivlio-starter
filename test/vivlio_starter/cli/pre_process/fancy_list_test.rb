# frozen_string_literal: true

# ================================================================
# Test: pre_process/fancy_list_test.rb
# ================================================================
# テスト対象:
#   MarkdownTransformer.convert_fancy_lists
#   （lib/vivlio_starter/cli/pre_process/markdown_transformer.rb）
#
# 検証内容（nested-list-notation-spec.md §8-1）:
#   - 13 様式それぞれの <ol> クラス / type / start 出力
#   - 開始値オフセット（C. → start="3"、(iv) → counter-reset: vs-fancy 3）
#   - 大文字＋ピリオドの 2 スペース規則（B. Russell 誤爆防止）
#   - エスケープ \(1) → 無変換＋ \ 除去
#   - コードフェンス / インラインコード内の不変性
#   - 標準リストのみのブロックの完全無変換（バイト一致）
#   - ネスト混在（1. 親＋ (a) 子）の構造と属性
#   - ul 混在時に ul が無加工なこと
#   - 様式混在時の警告（log_warn）と先頭様式継続
# ================================================================

require 'minitest/autorun'
require_relative '../../../../lib/vivlio_starter/cli/pre_process/markdown_transformer'

module VivlioStarter
  module CLI
    module PreProcessCommands
      class FancyListTest < Minitest::Test
        # log_warn の呼び出しを捕捉する（出力は抑止）
        def setup
          @warnings = warnings = []
          @saved_log_warn = Common.method(:log_warn)
          Common.define_singleton_method(:log_warn) do |msg, detail: nil|
            warnings << [msg, detail]
          end
        end

        def teardown
          Common.define_singleton_method(:log_warn, @saved_log_warn)
        end

        def convert(md, source_filename: nil)
          MarkdownTransformer.convert_fancy_lists(md, source_filename:)
        end

        # =================================================================
        # 13 様式のクラス / type / start 出力（§2.1 対応表）
        # =================================================================
        def test_should_convert_all_thirteen_fancy_styles
          {
            "a. 項目\n"   => ['vs-list-lower-alpha',        'type="a"'],
            "A.  項目\n"  => ['vs-list-upper-alpha',        'type="A"'],
            "i. 項目\n"   => ['vs-list-lower-roman',        'type="i"'],
            "I.  項目\n"  => ['vs-list-upper-roman',        'type="I"'],
            "a) 項目\n"   => ['vs-list-lower-alpha-paren',  'type="a"'],
            "A) 項目\n"   => ['vs-list-upper-alpha-paren',  'type="A"'],
            "i) 項目\n"   => ['vs-list-lower-roman-paren',  'type="i"'],
            "I) 項目\n"   => ['vs-list-upper-roman-paren',  'type="I"'],
            "(1) 項目\n"  => ['vs-list-decimal-paren2',     nil],
            "(a) 項目\n"  => ['vs-list-lower-alpha-paren2', 'type="a"'],
            "(A) 項目\n"  => ['vs-list-upper-alpha-paren2', 'type="A"'],
            "(i) 項目\n"  => ['vs-list-lower-roman-paren2', 'type="i"'],
            "(I) 項目\n"  => ['vs-list-upper-roman-paren2', 'type="I"']
          }.each do |md, (klass, type_attr)|
            out = convert(md)

            assert_includes out, "class=\"vs-fancy-list #{klass}\"", "#{md.strip} は #{klass} になる"
            assert_includes out, '<li>項目', "#{md.strip} の項目本文が li に入る"
            if type_attr
              assert_includes out, type_attr, "#{md.strip} は #{type_attr} を持つ"
            else
              refute_includes out, 'type=', 'decimal に type 属性は付かない'
            end
          end
        end

        def test_should_render_period_style_without_counter_reset
          out = convert("a. 項目\n")

          refute_includes out, 'counter-reset', 'ピリオド様式はネイティブマーカーなので counter-reset 不要'
        end

        def test_should_render_paren_styles_with_counter_reset
          assert_includes convert("a) 項目\n"), 'style="counter-reset: vs-fancy 0"'
          assert_includes convert("(a) 項目\n"), 'style="counter-reset: vs-fancy 0"'
        end

        # =================================================================
        # 開始値オフセット（§2.2）
        # =================================================================
        def test_should_start_from_marker_value_for_period_style
          out = convert("E.  五番目から\nF. 六番目\n")

          assert_includes out, 'start="5"', 'E. は 5 から始まる'
          assert_includes out, 'type="A"'
        end

        def test_should_prefer_roman_over_alpha_for_single_letter
          out = convert("C.  ローマ数字を優先\n")

          assert_includes out, 'vs-list-upper-roman', '単文字 C はローマ数字 100 と解釈される（§2.2-2）'
          assert_includes out, 'start="100"'
        end

        def test_should_start_from_roman_value_with_counter_reset
          out = convert("(iv) 四番目から\n(v) 五番目\n")

          assert_includes out, 'start="4"', '(iv) はローマ数字の値 4 を start に持つ'
          assert_includes out, 'style="counter-reset: vs-fancy 3"', 'カウンタは開始値 - 1 で初期化'
        end

        def test_should_not_emit_start_attribute_when_starting_at_one
          out = convert("(1) 項目\n")

          refute_includes out, 'start=', '開始値 1 のとき start 属性は付かない'
          assert_includes out, 'counter-reset: vs-fancy 0'
        end

        # =================================================================
        # 大文字＋ピリオドの 2 スペース規則（§2.2）
        # =================================================================
        def test_should_leave_single_space_uppercase_period_as_prose
          md = "B. Russell は偉大な哲学者です。\n"

          assert_equal md, convert(md), '1 スペースの大文字＋ピリオドは地の文のまま'
        end

        def test_should_convert_double_space_uppercase_period_as_list
          out = convert("B.  項目\n")

          assert_includes out, 'vs-list-upper-alpha'
          assert_includes out, 'start="2"', 'B は 2 から始まる'
        end

        def test_should_accept_single_space_after_list_context_established
          out = convert("A.  一番目\nB. 二番目\n")

          assert_equal 2, out.scan('<li>').size, '2 項目目以降は 1 スペースで可'
          assert_empty @warnings
        end

        # =================================================================
        # エスケープ（§2.2）
        # =================================================================
        def test_should_unescape_escaped_fancy_marker_to_prose
          out = convert("\\(1) 地の文として書きたい行。\n")

          assert_equal "(1) 地の文として書きたい行。\n", out, '\\ を除去して地の文にする'
          refute_includes out, '<ol'
        end

        # =================================================================
        # コード保護
        # =================================================================
        def test_should_not_convert_inside_code_fence
          md = "```markdown\n(a) コード例なので変換しない\n```\n"

          assert_equal md, convert(md)
        end

        def test_should_not_convert_inside_inline_code_line
          md = "`(a) インラインコード` の説明です。\n"
          out = convert(md)

          refute_includes out, '<ol'
        end

        # =================================================================
        # 標準リストの素通し（§4.1-2）
        # =================================================================
        def test_should_pass_through_standard_list_byte_identical
          md = "1. 項目その一\n2. 項目その二\n   - 子の箇条書き\n3. 項目その三\n"

          assert_equal md, convert(md), 'fancy を含まないブロックはバイト一致で素通し'
        end

        def test_should_pass_through_loose_standard_list_byte_identical
          md = "1. 項目その一\n\n2. 項目その二\n"

          assert_equal md, convert(md), 'ルーズ形式の標準リストもバイト一致で素通し'
        end

        # =================================================================
        # ネスト混在（§2.3）
        # =================================================================
        def test_should_convert_nested_fancy_under_standard_parent
          md = "1. 概要\n   (a) 選択肢イ\n   (b) 選択肢ロ\n2. インストール方法\n"
          out = convert(md)

          # 親は標準のまま（クラスなし <ol>）、子は fancy クラス付き
          assert_includes out, '<ol>', '標準の親 ol は無加工'
          assert_includes out, 'vs-list-lower-alpha-paren2', '子の (a) は fancy 化される'
          assert_includes out, '<li>選択肢イ'
          assert_includes out, '<li>インストール方法'
        end

        def test_should_resolve_nested_style_per_level
          md = "a. 親その一\n   I.  子その一\n   II. 子その二\nb. 親その二\n"
          out = convert(md)

          assert_includes out, 'vs-list-lower-alpha', '親レベルは小英字'
          assert_includes out, 'vs-list-upper-roman', '子レベルは大ローマ数字'
        end

        # =================================================================
        # ul 混在（§8-1）
        # =================================================================
        def test_should_leave_ul_untouched_in_mixed_block
          md = "(a) 項目\n    - 子の箇条書き\n    - もう一つ\n(b) 項目\n"
          out = convert(md)

          assert_includes out, '<ul>', 'ul にクラス・属性は注入されない'
          refute_match(/<ul [^>]*class=/, out)
          assert_includes out, 'vs-list-lower-alpha-paren2'
        end

        # =================================================================
        # 様式混在（§2.2・警告して先頭様式で続行）
        # =================================================================
        def test_should_warn_and_continue_with_head_style_on_style_change
          md = "(a) 一番目\n(b) 二番目\n3) 三番目\n"
          out = convert(md, source_filename: '10-sample.md')

          assert_equal 1, @warnings.size, '様式変更はリストごとに 1 回警告'
          msg, detail = @warnings.first

          assert_includes msg, '10-sample.md', '警告に出現箇所（ファイル名）を含める'
          assert_includes detail, '3) 三番目', '警告に該当行を含める'
          assert_equal 1, out.scan('<ol').size, 'リストは分裂せず先頭様式で続行'
          assert_equal 3, out.scan('<li>').size
          assert_includes out, 'vs-list-lower-alpha-paren2'
        end

        # 空行を挟んだ様式変更は別リストの開始（Pandoc と同じ分裂挙動・警告なし）
        def test_should_split_into_separate_lists_on_style_change_after_blank
          md = "a. 小英字\nb. 二番目\n\n(1) 数字両括弧\n(2) 二番目\n"
          out = convert(md)

          assert_empty @warnings, '空行で区切った別様式は正当な書き方（警告しない）'
          assert_equal 2, out.scan('<ol').size, '2 つの独立したリストになる'
          assert_includes out, 'vs-list-lower-alpha'
          assert_includes out, 'vs-list-decimal-paren2'
        end

        # =================================================================
        # 複数行項目・地の文の境界
        # =================================================================
        def test_should_join_continuation_lines_with_hard_break
          md = "(a) 一行目の本文\n    二行目の続き\n(b) 次の項目\n"
          out = convert(md)

          assert_includes out, '<br', '継続行は hardLineBreaks に合わせ <br> になる'
          assert_includes out, '二行目の続き'
        end

        def test_should_stop_block_at_plain_prose
          md = "(a) 項目\n\n地の文の段落です。\n"
          out = convert(md)

          assert_includes out, 'vs-list-lower-alpha-paren2'
          assert_includes out, "地の文の段落です。\n", '後続の地の文はリストに取り込まれない'
          refute_includes out, '<li>地の文'
        end

        def test_should_not_treat_multi_letter_alpha_as_marker
          md = "aa. これはリストにならない\n"

          assert_equal md, convert(md), '複数英字＋ピリオドは対象外（§2.2-4）'
        end
      end
    end
  end
end
