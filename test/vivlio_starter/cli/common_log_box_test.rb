# frozen_string_literal: true

# =============================================================================
# test/vivlio_starter/cli/common_log_box_test.rb
#
# Common.log_box: 1 度読めばよい大事な案内を枠で囲む。
# 日本語は 2 桁なので、右の縦線がそろうこと・色を付けない場面で色を付けないことを確かめる。
# =============================================================================

require 'test_helper'
require 'stringio'
require 'vivlio_starter/cli/common'

module VivlioStarter
  module CLI
    class CommonLogBoxTest < Minitest::Test
      TTY = Class.new(StringIO) { def tty? = true }

      def test_should_align_the_right_edge_with_wide_characters
        rows = box(io: StringIO.new)

        widths = rows.map { Common.display_width(it) }
        assert_equal 1, widths.uniq.size, "右の縦線がそろわない:\n#{rows.join("\n")}"
        assert rows.first.start_with?('╭─ 💡 見出し ')
        assert rows.last.start_with?('╰')
      end

      def test_should_not_color_when_not_a_terminal
        rows = box(io: StringIO.new)

        refute rows.any? { it.include?("\e[") }, 'パイプやファイルへは色を付けない'
      end

      def test_should_color_frame_yellow_and_emphasis_green_on_a_terminal
        rows = box(io: TTY.new)

        assert rows.first.start_with?("\e[33m╭"), '枠は黄色'
        assert rows.any? { it.include?("\e[32m「許可」\e[0m") }, '押すものは緑'
      end

      def test_should_respect_no_color
        rows = box(io: TTY.new, env: { 'NO_COLOR' => '1' })

        refute rows.any? { it.include?("\e[") }
      end

      def test_should_count_wide_characters_as_two_columns
        assert_equal 4, Common.display_width('許可')
        assert_equal 2, Common.display_width('💡')
        assert_equal 3, Common.display_width('a→b'), '矢印は 1 桁（macOS の端末の既定）'
      end

      private

      def box(io:, env: {})
        rows = []
        Common.with_emit_sink(rows) do
          Common.log_box('💡 見出し',
                         ['macOS の確認が出たら「許可」を押してください。', '', '  → お使いのターミナル（またはエディタ）'],
                         emphasis: ['「許可」'], io:, env:)
        end
        rows
      end
    end
  end
end
