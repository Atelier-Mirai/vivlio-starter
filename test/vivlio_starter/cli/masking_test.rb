# frozen_string_literal: true

# ================================================================
# Test: masking_test.rb
# ================================================================
# テスト対象:
#   CLI::Masking（Markdown コード領域解釈の唯一実装）
#   - each_prose_line: コード外の行だけを行番号つきで走査
#   - strip_code: コード除去（行数維持・インライン空白化）
#   - protect_code / restore_code: 退避→復元の往復同一性
#
# 回帰ゲート:
#   入れ子フェンス（````markdown の中の ```）・~~~・include: 除外・
#   インラインコード・行番号維持を横断的に固定する。
# ================================================================

require 'test_helper'
require 'vivlio_starter/cli/masking'

module VivlioStarter
  module CLI
    class MaskingTest < Minitest::Test
      # --- each_prose_line ------------------------------------------------

      def test_each_prose_line_skips_fenced_code
        md = <<~MD
          本文A
          ```ruby
          code_line
          ```
          本文B
        MD

        prose = Masking.each_prose_line(md).map { |line, _| line.chomp }

        assert_equal %w[本文A 本文B], prose
      end

      def test_each_prose_line_preserves_line_numbers
        md = <<~MD
          本文A
          ```
          code
          ```
          本文B
        MD

        pairs = Masking.each_prose_line(md).map { |line, lineno| [lineno, line.chomp] }

        assert_equal [[1, '本文A'], [5, '本文B']], pairs
      end

      # ````markdown の中の ``` は入れ子フェンスとして閉じない（本文が誤ってコード外化しない）。
      def test_each_prose_line_handles_nested_longer_outer_fence
        md = <<~MD
          外の本文
          ````markdown
          ```
          inner_code
          ```
          ````
          後の本文
        MD

        prose = Masking.each_prose_line(md).map { |line, _| line.chomp }

        assert_equal %w[外の本文 後の本文], prose
        refute_includes prose, 'inner_code'
      end

      def test_each_prose_line_recognizes_tilde_fence
        md = <<~MD
          本文A
          ~~~
          tilde_code
          ~~~
          本文B
        MD

        prose = Masking.each_prose_line(md).map { |line, _| line.chomp }

        assert_equal %w[本文A 本文B], prose
      end

      # ```include: は単一行のインクルード指令でありフェンスではない。
      def test_each_prose_line_treats_include_directive_as_prose
        md = <<~MD
          ```include: codes/sample.rb
          後続の本文
        MD

        prose = Masking.each_prose_line(md).map { |line, _| line.chomp }

        assert_equal ['```include: codes/sample.rb', '後続の本文'], prose
      end

      def test_each_prose_line_returns_enumerator_without_block
        assert_kind_of Enumerator, Masking.each_prose_line("a\n")
      end

      # --- strip_code -----------------------------------------------------

      def test_strip_code_removes_fenced_block_keeping_line_count
        md = "本文A\n```\ncode\n```\n本文B\n"

        stripped = Masking.strip_code(md)

        refute_includes stripped, 'code'
        assert_includes stripped, '本文A'
        assert_includes stripped, '本文B'
        # 行数維持（コード行は空行に置換）
        assert_equal md.each_line.count, stripped.each_line.count
      end

      def test_strip_code_blanks_inline_code
        stripped = Masking.strip_code('設定は `config_key` を使います。')

        refute_includes stripped, 'config_key'
      end

      # 地の文中のインライン ``` がフェンス対をズラさない（内外反転しない）。
      def test_strip_code_inline_triple_backtick_does_not_shift_fences
        md = <<~MD
          コードブロック（` ``` ` で囲んだ部分）は分析から除きます。

          ```
          [##########  ] 2,500 文字
          ```

          ```json
          { "exclude": [00, 90-98, 99] }
          ```
        MD

        stripped = Masking.strip_code(md)
        brackets = stripped.scan(/\[([^\]\n]+)\]/).map { it.first }

        assert_empty brackets, "コード内の [] が残っている: #{brackets.inspect}"
      end

      # --- protect_code / restore_code ------------------------------------

      def test_protect_and_restore_round_trip_identity
        text = +''
        5.times { |i| text << "段落#{i} `inline#{i}`\n\n```\ncode #{i}\n```\n\n" }
        text << "`open\n```\nfenced\n```\nclose`\n"

        protected_text, spans = Masking.protect_code(text)

        assert_equal text, Masking.restore_code(protected_text, spans)
      end

      def test_protect_code_masks_inline_and_fenced
        text = "見出し `foo`\n```\nbar\n```\n"
        protected_text, spans = Masking.protect_code(text)

        refute_includes protected_text, '`foo`'
        refute_includes protected_text, 'bar'
        assert_includes spans.values, '`foo`'
        assert(spans.values.any? { it.include?('bar') })
      end

      # 入れ子（フェンスを内包する行跨ぎインライン）でも LIFO 復元でプレースホルダが残らない。
      def test_protect_restore_lifo_for_nested_placeholders
        text = "`a\n```ruby\nx\n```\nb`\n"
        protected_text, spans = Masking.protect_code(text)

        assert_operator spans.size, :>=, 2
        restored = Masking.restore_code(protected_text, spans)

        assert_equal text, restored
        refute_match(/__VS_CODE_SPAN__\d+__/, restored)
      end

      def test_protect_code_leaves_prose_untouched
        text = 'No code spans here'
        protected_text, spans = Masking.protect_code(text)

        assert_equal text, protected_text
        assert_empty spans
      end

      # --- 意味論統一の回帰ゲート -----------------------------------------
      # lint / metrics / index の各経路が共有する状態機械が、入れ子フェンスを含む
      # 原稿に対し「コードとみなす行の集合」を一致させることを固定する。
      def test_code_line_set_is_consistent_across_paths
        md = <<~MD
          地の文1
          ````markdown
          ```ruby
          nested = [inner]
          ```
          ````
          地の文2 `inline`
          ~~~
          tilde
          ~~~
          地の文3
        MD

        prose_lines = Masking.each_prose_line(md).map { |_, lineno| lineno }.sort
        # strip_code の残存行（空行でない行）＝地の文行に一致するはず
        kept = []
        Masking.send(:scan_lines, md) { |_line, lineno, in_code| kept << lineno unless in_code }

        assert_equal prose_lines, kept.sort
        assert_equal [1, 7, 11], prose_lines
      end
    end
  end
end
