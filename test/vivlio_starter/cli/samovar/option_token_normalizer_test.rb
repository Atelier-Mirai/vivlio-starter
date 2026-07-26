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

        # 並べ替えの仕分けには値を取らないフラグも要る。BooleanFlag は alternatives に
        # `--no-xxx` を持つため、否定形も文字列一致で拾えること
        def test_should_discover_every_flag_name_including_negated_forms
          flags = BuildCommand.all_option_flags

          assert_includes flags, '--clean'
          assert_includes flags, '--no-clean'
          assert_includes flags, '--high'
          assert_includes flags, '-h'
          assert_includes flags, '--theme'
        end

        # 寄せる向きは宣言順から決まる（build は many が先・lint は options が先）
        def test_should_derive_the_reordering_direction_from_the_declaration_order
          refute_predicate BuildCommand, :options_declared_first?
          assert_predicate LintCommand, :options_declared_first?
          assert_predicate PdfPagesCommand, :options_declared_first?, 'pdf 系は options 先へ是正済みのはずです'
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

        # 綴り間違いを黙ってオプション扱いしない（従来どおり Samovar に弾かせる）
        def test_should_still_reject_unknown_options
          assert_raises(Samovar::InvalidInputError) { BuildCommand.new(['--no-cleen', '10']) }
        end

        # 値を取らないフラグへの `=` 付き指定は誤用なので通さない
        def test_should_reject_an_equals_value_on_a_flag_that_takes_none
          assert_raises(Samovar::InvalidInputError) { BuildCommand.new(['--no-clean=1']) }
        end
      end

      # 著者はオプションを位置引数の前後どちらに置いてもよい
      class OptionPositionFreedomTest < Minitest::Test
        def test_should_accept_options_before_or_after_targets_on_build
          after = BuildCommand.new(['10', '--no-clean'])
          before = BuildCommand.new(['--no-clean', '10'])

          assert_equal ['10'], after.targets
          assert_equal ['10'], before.targets
          assert_equal false, after.options[:clean]
          assert_equal false, before.options[:clean]
        end

        # lint は options を先に宣言しているため、従来は `lint 10 --fix` が 🔴 だった
        def test_should_accept_options_before_or_after_files_on_lint
          after = LintCommand.new(['10', '--fix'])
          before = LintCommand.new(['--fix', '10'])

          assert_equal ['10'], after.files
          assert_equal ['10'], before.files
          assert_equal true, after.options[:fix]
          assert_equal true, before.options[:fix]
        end

        # 値を取るオプションは値ごと移動する（値が位置引数と誤認されない）
        def test_should_move_a_value_option_together_with_its_value
          command = BuildCommand.new(['--theme', 'blue', '10', '20'])

          assert_equal 'blue', command.options[:theme]
          assert_equal ['10', '20'], command.targets
        end

        # 位置引数どうしの相対順序は保つ（vs rename 11 12 の 11 と 12 は順序に意味がある）
        def test_should_preserve_the_relative_order_of_positional_arguments
          assert_equal ['11', '12'], RenameCommand.new(['11', '12', '--force']).arguments
          assert_equal ['11', '12'], RenameCommand.new(['--force', '11', '12']).arguments
        end

        # オプションが位置引数を挟んで分かれていても両方効く
        def test_should_accept_options_split_around_positional_arguments
          command = LintCommand.new(['--fix', 'a.md', '--register'])

          assert_equal ['a.md'], command.files
          assert_equal true, command.options[:fix]
          assert_equal true, command.options[:register]
        end

        # 従来 🔴 だった代表例（[B] 型の one を持つコマンド）
        def test_should_accept_a_positional_argument_before_options_on_one_style_commands
          assert_equal 'foo.pdf', OpenCommand.new(['foo.pdf', '--verbose']).target
          assert_equal 'images', ResizeCommand.new(['images', '--high']).dir
        end

        # 全公開コマンドで「オプションの位置によって解析結果が変わらない」ことを機械的に確かめる。
        # 新しいコマンドを足したときに宣言順を取り違えても、ここで気づける。
        def test_should_parse_identically_regardless_of_option_position_across_all_commands
          mismatches = RootCommand.public_commands.filter_map do |name, klass|
            next unless positional_keys(klass).any?

            after = parse_snapshot(klass, ['x', '--help'])
            before = parse_snapshot(klass, ['--help', 'x'])
            "#{name}: #{before.inspect} != #{after.inspect}" unless before == after
          end

          assert_empty mismatches, 'オプションを前後どちらに置いても同じ解析結果になるはずです'
        end

        private

        def positional_keys(klass)
          klass.table.merged.each.to_a
               .select { it.is_a?(Samovar::Many) || it.is_a?(Samovar::One) }
               .map(&:key)
        end

        # options と位置引数の値をまとめて取り、解析結果の同一性を比較できるようにする
        def parse_snapshot(klass, argv)
          command = klass.new(argv)
          [command.options.to_h, positional_keys(klass).map { command.public_send(it) }]
        rescue StandardError => e
          "🔴 #{e.message}"
        end
      end

      # 公開コマンドは例外なく --help で使い方を表示できる
      class CommandHelpContractTest < Minitest::Test
        def test_should_accept_help_flags_on_every_public_command
          missing = RootCommand.public_commands.flat_map do |name, klass|
            ['--help', '-h'].filter_map do |flag|
              "#{name} #{flag}" unless help_flag_recognized?(klass, flag)
            end
          end

          assert_empty missing, '公開コマンドはすべて --help / -h を受け付けるはずです'
        end

        private

        def help_flag_recognized?(klass, flag)
          klass.new([flag]).options[:help] == true
        rescue StandardError
          false
        end
      end
    end
  end
end
