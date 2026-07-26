# frozen_string_literal: true

require 'test_helper'
require 'vivlio_starter/cli/samovar'

module VivlioStarter
  module CLI
    # ログレベルは起動時に 1 回だけ解決してモジュールが保持する
    class LogLevelResolutionTest < Minitest::Test
      def teardown
        Common.log_level = nil
      end

      def test_should_default_to_warn_when_no_option_is_given
        assert_equal Common::LEVELS['warn'], resolve_for(['build'])
      end

      # `=` 区切りでも空白区切りでも同じ結果になること
      def test_should_resolve_the_same_level_for_both_notations
        assert_equal Common::LEVELS['debug'], resolve_for(['build', '--log=debug'])
        assert_equal Common::LEVELS['debug'], resolve_for(['build', '--log', 'debug'])
      end

      # 従来は `--log=DEBUG` だけ downcase され、`--log DEBUG` は info に落ちていた
      def test_should_downcase_the_value_in_both_notations
        assert_equal Common::LEVELS['debug'], resolve_for(['build', '--log=DEBUG'])
        assert_equal Common::LEVELS['debug'], resolve_for(['build', '--log', 'DEBUG'])
      end

      # 値なし `--log` は正規化器が info へ開く
      def test_should_treat_a_bare_log_flag_as_info
        assert_equal Common::LEVELS['info'], resolve_for(['build', '--log'])
      end

      def test_should_resolve_every_documented_level
        Common::LOG_LEVEL_NAMES.each do |name|
          assert_equal Common::LEVELS[name], resolve_for(['build', "--log=#{name}"]), "--log=#{name} が解決できるはずです"
        end
      end

      # タイプミスでビルドは止めないが、黙って既定へ落とさず 🟡 で知らせる
      def test_should_warn_and_fall_back_to_info_on_an_unknown_level
        level = nil
        out, = capture_io { level = resolve_for(['build', '--log=verbose']) }

        assert_equal Common::LEVELS['info'], level
        assert_match(/🟡/, out)
        assert_match(/--log=verbose/, out)
        assert_match(%r{error / warn / info / debug}, out, '指定できる値を案内するはずです')
      end

      # --log を宣言していないコマンドでは、閾値も上がらない（従来の捻れの解消）。
      # 解析自体が 🔴 になるため、ログレベルだけ効くという非対称が消える。
      def test_should_not_raise_the_threshold_for_commands_without_a_log_option
        assert_raises(Samovar::InvalidInputError) { SamovarCommands::RootCommand.parse(['lint', '--log=debug']) }
        assert_equal Common::LEVELS['warn'], Common.current_log_level
      end

      private

      def resolve_for(argv)
        Common.log_level = nil
        Common.apply_log_level!(SamovarCommands::RootCommand.parse(argv))
        Common.current_log_level
      end
    end

    # ログレベルは ARGV ではなくモジュールの状態で決まる
    class LogLevelStateTest < Minitest::Test
      def teardown
        Common.log_level = nil
      end

      def test_should_be_controllable_without_touching_argv
        before = ARGV.dup

        Common.log_level = Common::LEVELS['debug']

        assert_equal Common::LEVELS['debug'], Common.current_log_level
        assert_equal before, ARGV, 'ログレベルの切り替えで ARGV を汚さないはずです'
      end

      def test_should_fall_back_to_the_default_when_cleared
        Common.log_level = Common::LEVELS['debug']
        Common.log_level = nil

        assert_equal Common::DEFAULT_LOG_LEVEL, Common.current_log_level
      end

      # module_function されたメソッドは include 先からも呼ばれるため、
      # インスタンス変数ではなくモジュールの状態を見ていることを確かめる
      def test_should_share_the_level_with_including_objects
        includer = Class.new { include VivlioStarter::CLI::Common }.new

        Common.log_level = Common::LEVELS['debug']

        assert_equal Common::LEVELS['debug'], includer.send(:current_log_level)
      end

      def test_should_control_whether_info_logs_are_printed
        Common.log_level = Common::LEVELS['warn']
        quiet, = capture_io { Common.log_info('隠れるはずの情報') }

        assert_empty quiet

        Common.log_level = Common::LEVELS['info']
        loud, = capture_io { Common.log_info('見えるはずの情報') }

        assert_match(/🔵 見えるはずの情報/, loud)
      end
    end
  end
end
