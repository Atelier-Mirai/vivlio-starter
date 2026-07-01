# frozen_string_literal: true

# ================================================================
# Test: index/code_block_stripper_test.rb
# ================================================================
# テスト対象:
#   IndexCommands::CodeBlockStripper（コード除去ユーティリティ）
# ================================================================

require 'test_helper'
require 'vivlio_starter/cli/index/code_block_stripper'

module VivlioStarter
  module CLI
    module IndexCommands
      class CodeBlockStripperTest < Minitest::Test
        def test_strips_fenced_code_block
          md = <<~MD
            本文の [用語] です。
            ```ruby
            arr = [not_a_term]
            ```
            続きの [別語] です。
          MD

          stripped = CodeBlockStripper.strip(md)

          refute_includes stripped, 'not_a_term'
          assert_includes stripped, '[用語]'
          assert_includes stripped, '[別語]'
        end

        # 回帰: 地の文中のインライン ``` が余分なフェンスと誤認され、以降の
        # フェンス対がズレて後続コードブロックが地の文化するのを防ぐ。
        def test_inline_triple_backtick_does_not_shift_fence_pairing
          md = <<~MD
            コードブロック（` ``` ` で囲んだ部分）は分析から除きます。

            ```
            📚 章別の解析結果
            第1章 はじめに  [##########  ] 2,500 文字
            ```

            ```json
            { "exclude": [00, 90-98, 99] }
            ```
          MD

          stripped = CodeBlockStripper.strip(md)
          brackets = stripped.scan(/\[([^\]\n]+)\]/).map { it.first }

          assert_empty brackets, "コード内の [] が残っている: #{brackets.inspect}"
        end

        # ```` の中の ``` は入れ子フェンスとして閉じない（コード本文扱い）。
        def test_nested_shorter_fence_stays_inside_block
          md = <<~MD
            ````markdown
            ```
            [inner_code]
            ```
            ````
            外の [用語] です。
          MD

          stripped = CodeBlockStripper.strip(md)

          refute_includes stripped, 'inner_code'
          assert_includes stripped, '[用語]'
        end

        def test_strips_inline_code
          stripped = CodeBlockStripper.strip('設定は `[config_key]` を使います。')

          refute_includes stripped, 'config_key'
        end

        # ```include: は単一行のインクルード指令でありフェンスではない。
        def test_include_directive_is_not_a_fence
          md = <<~MD
            ```include: codes/sample.rb
            後続の [用語] は本文として残る。
          MD

          stripped = CodeBlockStripper.strip(md)

          assert_includes stripped, '[用語]'
        end
      end
    end
  end
end
