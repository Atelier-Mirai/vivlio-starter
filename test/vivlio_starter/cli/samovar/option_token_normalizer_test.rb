# frozen_string_literal: true

require 'test_helper'
require 'vivlio_starter/cli/samovar'

module VivlioStarter
  module CLI
    module SamovarCommands
      # 値を取るオプションの自動導出（options 定義が唯一の情報源であること）
      class OptionTokenNormalizerFlagDiscoveryTest < Minitest::Test
        def test_should_discover_value_flags_from_the_options_definition
          assert_equal ['--theme', '--log'], BuildCommand.value_option_flags
          assert_equal ['--log'], PreflightCommand.value_option_flags
          assert_equal ['--dpi', '--quality', '--pages', '--output'], PdfPagesCommand.value_option_flags
        end

        # `--high` や `--[no]-clean` のような値を取らないフラグは正規化の対象外
        def test_should_exclude_flags_that_take_no_value
          refute_includes BuildCommand.value_option_flags, '--high'
          refute_includes BuildCommand.value_option_flags, '--clean'
          refute_includes PdfRasterizeCommand.value_option_flags, '--clean'
        end

        # 短縮形も対象に含める（`-s=3` を通すため）
        def test_should_include_short_flag_alternatives
          assert_equal ['-s', '--step'], RenameCommand.value_option_flags
        end

        # 継承したオプションも拾う（RenumberCommand は RenameCommand を継承する）
        def test_should_discover_inherited_value_flags
          assert_equal ['-s', '--step'], RenumberCommand.value_option_flags
        end
      end

      # `--opt=value` 記法が CLI 全体で揃っていること
      class OptionTokenNormalizerEqualsFormTest < Minitest::Test
        def test_should_accept_equals_separated_values_across_commands
          assert_equal 'blue', BuildCommand.new(['x.md', '--theme=blue']).options[:theme]
          assert_equal 'debug', PreflightCommand.new(['--log=debug']).options[:log_level]
          assert_equal 'debug', NewCommand.new(['mybook', '--log=debug']).options[:log_level]
          assert_equal '1,3,5-8', PdfPagesCommand.new(['a.pdf', '--pages=1,3,5-8']).options[:pages]
        end

        # type: Integer のオプションは正規化後に Samovar が型変換する
        def test_should_convert_typed_values_after_normalization
          assert_equal 200, PdfPagesCommand.new(['a.pdf', '--dpi=200']).options[:dpi]
          assert_equal 80, PdfRasterizeCommand.new(['a.pdf', '--quality=80']).options[:quality]
          assert_equal 2, RenameCommand.new(['--step=2']).options[:step]
        end

        def test_should_accept_equals_form_on_short_flags
          assert_equal 3, RenameCommand.new(['-s=3']).options[:step]
        end

        def test_should_accept_equals_form_on_inherited_options
          assert_equal 5, RenumberCommand.new(['--step=5']).options[:step]
        end

        # `#` を含むテーマ色が `=` 以降で欠けないこと
        def test_should_keep_the_whole_value_after_the_first_equals
          assert_equal '#e91e63', BuildCommand.new(['x.md', '--theme=#e91e63']).options[:theme]
        end

        def test_should_keep_space_separated_values_working
          command = BuildCommand.new(['x.md', '--theme', 'blue'])

          assert_equal 'blue', command.options[:theme]
          assert_equal ['x.md'], command.targets
        end
      end

      # 値が省略されたときの扱い
      class OptionTokenNormalizerBareFlagTest < Minitest::Test
        # 既定値を持つのは --log だけ（bare `--log` = info）
        def test_should_fill_the_default_value_only_for_log
          assert_equal 'info', BuildCommand.new(['--log']).options[:log_level]
          assert_equal 'info', PreflightCommand.new(['--log']).options[:log_level]
          assert_nil BuildCommand.new(['x.md', '--theme']).options[:theme]
        end

        # `--theme=` は空値のまま渡し、色名の妥当性判定はコマンド側に委ねる
        def test_should_pass_an_empty_value_through_for_flags_without_a_default
          assert_equal '', BuildCommand.new(['x.md', '--theme=']).options[:theme]
        end

        # 回帰: 値の続かない --log の直後にあるオプションを取りこぼさない
        # （preflight には 2026-04-13 の複製以来このバグが残っていた）
        def test_should_not_swallow_the_option_following_a_bare_log
          preflight = PreflightCommand.new(['--log', '--no-verify'])

          assert_equal 'info', preflight.options[:log_level]
          assert_equal false, preflight.options[:verify], '--log の次のオプションが失われないはずです'

          build = BuildCommand.new(['10-intro', '--log', '--no-clean'])

          assert_equal 'info', build.options[:log_level]
          assert_equal false, build.options[:clean]
        end
      end

      # 正規化が触ってはいけないもの
      class OptionTokenNormalizerPassThroughTest < Minitest::Test
        # `=` を含む位置引数はオプションではないので素通しする
        def test_should_pass_through_positional_arguments_containing_equals
          assert_equal ['a=b.md'], BuildCommand.new(['a=b.md']).targets
        end

        def test_should_keep_unrelated_options_and_their_order
          command = BuildCommand.new(['10-intro', '--no-clean', '--high', '--log=debug'])

          assert_equal ['10-intro'], command.targets
          assert_equal false, command.options[:clean]
          assert_equal true, command.options[:high]
          assert_equal 'debug', command.options[:log_level]
        end

        # Samovar の Nested#parse は親と同じ配列を子へ渡し、親は「空になったか」で
        # 未解釈トークンを検出する。正規化で別配列に差し替えると親が誤検出する。
        def test_should_consume_the_shared_argv_when_dispatched_from_the_root_command
          argv = ['build', '10-intro', '--log=debug', '--no-clean']

          RootCommand.new(argv)

          assert_empty argv, '親コマンドと共有する配列が消費し切られているはずです'
        end
      end
    end
  end
end
