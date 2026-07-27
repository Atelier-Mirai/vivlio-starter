# frozen_string_literal: true

require 'test_helper'
require 'stringio'
require 'vivlio_starter/cli/common'

module VivlioStarter
  module CLI
    # 破壊的操作の確認プロンプトは Common.confirm? に集約されている
    # （各コマンドが独自に print していると絵文字も表記も揃わないため）
    class ConfirmTest < Minitest::Test
      def test_should_accept_yes_answers
        assert ask('y')
        assert ask('yes')
        assert ask('Y'), '大文字も受け付けるはずです'
        assert ask(' y '), '前後の空白は無視するはずです'
      end

      def test_should_reject_no_and_unrecognized_answers
        refute ask('n')
        refute ask('no')
        refute ask('abc'), '解釈できない入力は安全側（いいえ）に倒すはずです'
      end

      # Enter だけの応答は既定値に従う
      def test_should_fall_back_to_the_default_on_an_empty_answer
        refute ask('')
        assert ask('', default: true)
      end

      # 入力が閉じている（パイプ・CI）場合も既定値に倒れる
      def test_should_fall_back_to_the_default_when_input_is_closed
        refute ask(nil)
        assert ask(nil, default: true)
      end

      def test_should_show_the_question_mark_icon_and_the_default_in_brackets
        assert_equal '❓ 削除しますか？ [y/N]:', prompt_for(default: false)
        assert_equal '❓ 削除しますか？ [Y/n]:', prompt_for(default: true)
      end

      private

      def ask(answer, **)
        capture_prompt(answer, **).last
      end

      def prompt_for(**)
        capture_prompt('y', **).first.strip
      end

      def capture_prompt(answer, **)
        input = StringIO.new(answer.nil? ? '' : "#{answer}\n")
        result = nil
        out, = capture_io { result = Common.confirm?('削除しますか？', input: input, **) }
        [out, result]
      end
    end
  end
end
