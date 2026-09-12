# frozen_string_literal: true

require_relative '../../../test_helper'
require 'vivlio_starter/cli/import/re_inline'

module VivlioStarter
  module CLI
    module Import
      # インライン命令（@<name>{…}）の変換
      class ReInlineTest < Minitest::Test
        def setup
          @report = ReReport.new
          @context = ReInline::Context.new(report: @report, file: 'chap.re', line: 1,
                                           words: { 'RE' => 'Re:VIEW' })
        end

        def convert(text) = ReInline.transform(text, @context)

        # ================================================================
        # 引数の切り出し（re-direct-import-spec.md §2.5）
        # ================================================================
        def test_should_read_braced_argument
          assert_equal '`puts 1`', convert('@<code>{puts 1}')
        end

        # Starter のスキャナは `@<name>{` でだけ入れ子を数え、裸の `{` は数えない。
        # だから「開いていない `}`」を \} でエスケープする書き方が成立する
        def test_should_unescape_closing_brace
          assert_equal '**var x = {a: 1};**', convert('@<b>{var x = {a: 1\\};}')
        end

        def test_should_read_fenced_argument
          assert_equal '**パイプ記法**', convert('@<b>|パイプ記法|')
          assert_equal '**ドル記法**', convert('@<b>$ドル記法$')
        end

        # Starter はインライン命令を入れ子にできる
        def test_should_resolve_nested_commands
          assert_equal '**強い*斜め***', convert('@<b>{強い@<i>{斜め}}')
        end

        # インラインコードの中では Markdown の装飾記号が効かないので中身だけ残す
        def test_should_strip_decoration_inside_code
          assert_equal '`func(arg)`', convert('@<code>{func(@<b>{@<i>{arg}})}')
        end

        def test_should_widen_fence_when_body_has_backtick
          assert_equal '`` `x` ``', convert('@<code>{`x`}')
        end

        def test_should_leave_plain_text_untouched
          assert_equal 'メール@example.com は命令ではありません', convert('メール@example.com は命令ではありません')
        end

        # ================================================================
        # 個々の命令（同 §3.3）
        # ================================================================
        def test_should_convert_link_with_and_without_text
          assert_equal '[サイト](https://example.com)', convert('@<href>{https://example.com, サイト}')
          assert_equal '<https://example.com>', convert('@<href>{https://example.com}')
        end

        def test_should_convert_ruby_footnote_and_math
          assert_equal '{漢字|かんじ}', convert('@<ruby>{漢字, かんじ}')
          assert_equal '[^note1]', convert('@<fn>{note1}')
          assert_equal '$x^2$', convert('@<m>{x^2}')
        end

        # `@<b>` は Re:VIEW では「太字だけ（ゴシックにならない）」。Vivlio の強調は
        # 色も付くので、寄せたことを 🔵 で伝える（著者の作業は要らない）
        def test_should_note_that_bold_becomes_strong
          assert_equal '**太字**', convert('@<b>{太字}')

          finding = @report.findings.first
          assert_equal :note, finding.level
          assert_equal '@<b>', finding.kind
        end

        # `@<B>`（＝`@<strong>`）はもともと強調なので、何も言わない
        def test_should_convert_strong_without_note
          assert_equal '**強調**', convert('@<B>{強調}')
          assert_empty @report.findings
        end

        def test_should_convert_reference_to_at_label
          assert_equal '@hello を参照', convert('@<list>{hello} を参照')
        end

        def test_should_convert_keyboard_and_index
          assert_equal '〘Ctrl〙', convert('@<kbd>{Ctrl}')
          assert_equal '[索引語]', convert('@<idx>{索引語}')
        end

        def test_should_convert_small_to_span
          assert_equal '<span class="small">(補足)</span>', convert('@<small>{(補足)}')
        end

        def test_should_expand_word_from_dictionary
          assert_equal 'Re:VIEW と **Re:VIEW**', convert('@<w>{RE} と @<wb>{RE}')
        end

        def test_should_convert_uchar_to_character
          assert_equal '①', convert('@<uchar>{2460}')
        end

        # ================================================================
        # 通知（同 §4）
        # ================================================================
        # 対応概念が無い記法は原文を残す——黙って消さない
        def test_should_keep_original_for_unsupported_command
          assert_equal '@<balloon>{吹き出し}', convert('@<balloon>{吹き出し}')
          assert_equal :unsupported, @report.findings.first.level
        end

        def test_should_report_unknown_command_as_typo
          assert_equal '@<if>{誤記}', convert('@<if>{誤記}')

          finding = @report.findings.first
          assert_equal :unsupported, finding.level
          assert_includes finding.message, '誤記の可能性'
        end

        # 装飾は移せないが、中身は残す
        def test_should_degrade_decoration_keeping_body
          assert_equal '下線', convert('@<u>{下線}')
          assert_equal :degraded, @report.findings.first.level
        end

        def test_should_report_missing_word_dictionary_entry
          assert_equal '@<w>{UNKNOWN}', convert('@<w>{UNKNOWN}')
          assert_equal :unsupported, @report.findings.first.level
        end
      end
    end
  end
end
