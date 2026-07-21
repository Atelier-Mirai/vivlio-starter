# frozen_string_literal: true

# ================================================================
# Test: build_command_direct_mode_test.rb
# ================================================================
# 検証内容（docs/archives/direct-build-spec.md §3-1, §3-2）:
#   - 直接モードの発動条件と排他（.md 1 件のみ / 混在・複数・不在は 🔴）
#   - projectless? が .md 指定時のみ真になり、ensure_project_context! が
#     Common.ensure_configured! を呼ばないこと
#   - 直接ビルドで無効なオプションの案内、通常ビルドでの --theme の案内
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'vivlio_starter/cli/samovar'
require 'vivlio_starter/cli/samovar/build_command'

module VivlioStarter
  module CLI
    module SamovarCommands
      class BuildCommandDirectModeTest < Minitest::Test
        def setup
          @tmpdir = Dir.mktmpdir('direct-mode-test-')
          File.write(File.join(@tmpdir, 'myawesome.md'), "# 見出し\n")
        end

        def teardown
          FileUtils.remove_entry(@tmpdir)
        end

        # ------------------------------------------------------------
        # 発動条件と排他（spec §1.3）
        # ------------------------------------------------------------

        def test_should_enter_direct_mode_only_for_md_targets
          refute BuildCommand.new([]).projectless?, '引数なしは従来のフルビルドです'
          refute BuildCommand.new(['10-intro']).projectless?, '章トークンは従来どおり catalog 解決です'
          refute BuildCommand.new(%w[10 12]).projectless?, '番号指定は従来どおり catalog 解決です'
          assert BuildCommand.new(['myawesome.md']).projectless?, '.md 指定は直接ビルドです'
          assert BuildCommand.new(['contents/00-preface.md']).projectless?, 'プロジェクト内のパスも直接ビルドです'
        end

        def test_should_reject_multiple_md_targets
          out = run_build(%w[a.md b.md])

          assert_equal 1, out[:status]
          assert_match(/1 ファイルのみ指定できます/, out[:stdout])
        end

        def test_should_reject_mixing_md_path_and_chapter_token
          out = run_build(['myawesome.md', '10-intro'])

          assert_equal 1, out[:status]
          assert_match(/同時に使えません/, out[:stdout])
        end

        # 従来解釈（basename 解決）へはフォールバックしない
        def test_should_reject_missing_md_file
          out = run_build(['nothere.md'])

          assert_equal 1, out[:status]
          assert_match(/ファイルが見つかりません/, out[:stdout])
        end

        # ------------------------------------------------------------
        # プロジェクト文脈の解除（spec §2.2）
        # ------------------------------------------------------------

        def test_should_skip_ensure_configured_for_direct_build
          root = RootCommand.new(['build', 'myawesome.md'])
          called = false

          Common.stub(:ensure_configured!, -> { called = true }) do
            root.send(:ensure_project_context!, root.command)
          end

          refute called, '直接ビルドでは book.yml の読み込みを要求しないはずです'
        end

        def test_should_require_configuration_for_chapter_build
          root = RootCommand.new(%w[build 10-intro])
          called = false

          Common.stub(:ensure_configured!, -> { called = true }) do
            root.send(:ensure_project_context!, root.command)
          end

          assert called, '従来のビルドでは book.yml を要求するはずです'
        end

        # ------------------------------------------------------------
        # オプションの案内（spec §1.4, §2.1）
        # ------------------------------------------------------------

        def test_should_warn_that_project_options_are_ignored
          command = BuildCommand.new(['myawesome.md', '--no-clean', '--verify-links'])
          out = capture_io { command.send(:warn_ignored_options!) }

          assert_match(/無視されます/, out.join)
          assert_match(/--no-clean/, out.join)
          assert_match(/--verify-links/, out.join)
        end

        def test_should_warn_that_theme_option_needs_direct_build
          command = BuildCommand.new(['10-intro', '--theme', 'blue'])
          out = capture_io { command.send(:warn_theme_option_ignored) }

          assert_match(/直接ビルド（.md 指定）専用/, out.join)
          assert_match(/theme\.color/, out.join)
        end

        private

        # 直接モードの排他判定だけを見たいので、Node チェックは通過させる
        def run_build(targets)
          command = BuildCommand.new(targets)
          status = nil
          stdout = capture_io do
            Guards::NodeCheck.stub(:new, PassingCheck.new) do
              Dir.chdir(@tmpdir) { status = command.call }
            end
          end.join

          { status: status, stdout: stdout }
        end

        class PassingCheck
          def validate = []
        end
      end
    end
  end
end
