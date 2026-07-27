# frozen_string_literal: true

require 'test_helper'
require 'stringio'
require 'vivlio_starter/cli/common'

module VivlioStarter
  module CLI
    # TTY を模した出力先。tty? だけを差し替え、書き込み内容は StringIO に貯める
    class FakeTty < StringIO
      def tty? = true
    end

    class SpinnerTest < Minitest::Test
      def setup
        @original_level = Common.log_level
        Common.log_level = Common::DEFAULT_LOG_LEVEL
      end

      def teardown
        Common.log_level = @original_level
        Spinner.active = nil
        ENV.delete('VS_NO_SPINNER')
      end

      # --- 表示条件を満たさない場合は完全に無音 ---

      def test_should_stay_silent_and_pass_through_the_block_when_not_a_tty
        out = StringIO.new
        result = Spinner.while('ビルド中', output: out) { :done }

        assert_equal :done, result
        assert_empty out.string, 'TTY でなければ何も出力しないはずです'
      end

      def test_should_stay_silent_when_the_log_level_is_raised
        Common.log_level = Common::LEVELS['info']
        out = FakeTty.new

        Spinner.while('ビルド中', output: out) { :done }

        assert_empty out.string, '--log 指定時は逐次ログと干渉するため出さないはずです'
      end

      def test_should_stay_silent_when_disabled_by_environment
        ENV['VS_NO_SPINNER'] = '1'
        out = FakeTty.new

        Spinner.while('ビルド中', output: out) { :done }

        assert_empty out.string, 'VS_NO_SPINNER=1 で無効化できるはずです'
      end

      # --- 表示条件を満たす場合 ---

      def test_should_draw_frames_and_clear_the_line_afterwards
        out = FakeTty.new

        Spinner.while('ビルド中: convert … (5/14)', output: out) { sleep(Spinner::INTERVAL * 2) }

        assert_match(/ビルド中: convert … \(5\/14\)/, out.string, 'ラベルを描画するはずです')
        assert_includes Spinner::FRAMES, out.string[/[#{Spinner::FRAMES.join}]/], 'フレーム文字を描画するはずです'
        assert out.string.end_with?(Spinner::CLEAR_LINE), '終了時に行を消去するはずです'
      end

      def test_should_return_the_block_value
        assert_equal 42, Spinner.while('ビルド中', output: FakeTty.new) { 42 }
      end

      # 例外で抜けてもスピナーの残骸を残さない（🔴 メッセージを汚さないため）
      def test_should_clear_the_line_even_when_the_block_raises
        out = FakeTty.new

        assert_raises(RuntimeError) do
          Spinner.while('ビルド中', output: out) do
            sleep(Spinner::INTERVAL)
            raise 'boom'
          end
        end

        assert out.string.end_with?(Spinner::CLEAR_LINE), '例外時も行を消去するはずです'
        assert_nil Spinner.active, '例外時もアクティブ登録を解除するはずです'
      end

      def test_should_release_the_active_registration_after_running
        out = FakeTty.new

        Spinner.while('ビルド中', output: out) do
          assert_instance_of Spinner, Spinner.active, '実行中はアクティブなスピナーを公開するはずです'
        end

        assert_nil Spinner.active
      end

      # --- ログ出力との干渉 ---

      # ログを出す直前に行を消さないと、スピナーの残骸とログが同じ行に重なる
      def test_should_clear_the_drawn_line_when_a_log_interrupts
        out = FakeTty.new
        spinner = Spinner.new('ビルド中', output: out)
        spinner.send(:draw, Spinner::FRAMES.first)

        Spinner.active = spinner
        Spinner.clear_active_line

        assert out.string.end_with?(Spinner::CLEAR_LINE), 'ログ出力前に行を消去するはずです'
      end

      def test_should_do_nothing_when_no_spinner_is_active
        Spinner.active = nil

        assert_nil Spinner.clear_active_line
      end
    end
  end
end
