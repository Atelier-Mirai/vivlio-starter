# frozen_string_literal: true

# ================================================================
# robustness: vs new プロンプト途中・展開途中の Ctrl+C
# ================================================================
# 対応する堅牢性テスト仕様書項目:
#   - 3-1-8 (L146): プロンプト途中で Ctrl+C
#   docs/specs/vivlio_starter_robustness_test_spec.md
#
# 期待される挙動:
#   中途半端な `プロジェクト名/` ディレクトリが残らないこと。
#
# 検証シナリオ:
#   A. プロンプト段階（$stdin.gets 中）で Interrupt
#      → expand_scaffold がまだ呼ばれていないためディレクトリは作成されていない。
#   B. expand_scaffold の中（ファイルコピー中）で Interrupt
#      → 新設の cleanup_partial_scaffold が走り、部分展開ディレクトリを削除する。
#   C. expand_scaffold 中の想定外例外
#      → 同じく部分展開ディレクトリを削除する。
#   D. 既存ディレクトリに展開中の中断（--add-missing 相当）
#      → ユーザーの既存ファイルを壊さないため **削除しない**。
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'stringio'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/new'

module VivlioStarter
  module CLI
    class VsNewInterruptTest < Minitest::Test
      # ----------------------------------------------------------------
      # A. プロンプト途中の Ctrl+C
      # ----------------------------------------------------------------

      def test_prompt_interrupt_before_expand_leaves_no_directory
        within_tmp do
          # $stdin.gets が Interrupt を投げる状況を模擬
          with_stubbed_stdin_interrupt do
            assert_raises(Interrupt) do
              NewCommands.send(:prompt, '書籍名を入力してください', 'default')
            end
          end
          refute File.exist?('any-project'),
                 'プロンプト段階で中断された場合、project ディレクトリは作成されない'
        end
      end

      # ----------------------------------------------------------------
      # B. expand_scaffold の展開中に Interrupt が発生
      # ----------------------------------------------------------------

      def test_expand_scaffold_cleans_up_on_interrupt_during_copy
        within_tmp do
          project = 'my-newbook'
          refute File.exist?(project)

          captured = capture_stdout do
            with_fileutils_cp_raising(Interrupt) do
              assert_raises(Interrupt) do
                NewCommands.send(:expand_scaffold, nil, project, NewCommands::DEFAULT_ANSWERS.dup)
              end
            end
          end

          refute File.exist?(project),
                 '中断時に部分展開ディレクトリが残ってはならない'
          assert(captured.any? { it.include?('削除しました') },
                 'クリーンアップの警告が出るべき')
        end
      end

      # ----------------------------------------------------------------
      # C. expand_scaffold 中の想定外例外
      # ----------------------------------------------------------------

      def test_expand_scaffold_cleans_up_on_unexpected_error
        within_tmp do
          project = 'my-brokenbook'

          capture_stdout do
            with_fileutils_cp_raising(StandardError, 'disk full') do
              err = assert_raises(StandardError) do
                NewCommands.send(:expand_scaffold, nil, project, NewCommands::DEFAULT_ANSWERS.dup)
              end
              assert_equal 'disk full', err.message
            end
          end

          refute File.exist?(project),
                 '想定外例外時も部分展開ディレクトリは削除されるべき'
        end
      end

      # ----------------------------------------------------------------
      # D. 既存ディレクトリへ不足ファイル追加中の中断は削除しない
      # ----------------------------------------------------------------

      def test_expand_scaffold_preserves_pre_existing_directory_on_interrupt
        within_tmp do
          project = 'existing-book'
          FileUtils.mkdir_p(project)
          precious = File.join(project, 'precious.txt')
          File.write(precious, 'keep me')

          capture_stdout do
            with_fileutils_cp_raising(Interrupt) do
              assert_raises(Interrupt) do
                NewCommands.send(:expand_scaffold, nil, project, NewCommands::DEFAULT_ANSWERS.dup)
              end
            end
          end

          assert File.exist?(project),
                 '既存ディレクトリは削除してはならない（--add-missing のユースケース）'
          assert File.exist?(precious),
                 '既存ユーザーファイルは保護されるべき'
          assert_equal 'keep me', File.read(precious)
        end
      end

      # ----------------------------------------------------------------
      # cleanup_partial_scaffold の単体テスト
      # ----------------------------------------------------------------

      def test_cleanup_skips_when_created_root_false
        within_tmp do
          project = 'preserve-me'
          FileUtils.mkdir_p(project)
          File.write(File.join(project, 'x.txt'), 'x')

          capture_stdout do
            NewCommands.send(:cleanup_partial_scaffold, project, false)
          end

          assert File.exist?(project), 'created_root=false の場合は削除しない'
        end
      end

      def test_cleanup_removes_directory_when_created_root_true
        within_tmp do
          project = 'remove-me'
          FileUtils.mkdir_p(project)
          File.write(File.join(project, 'x.txt'), 'x')

          capture_stdout do
            NewCommands.send(:cleanup_partial_scaffold, project, true)
          end

          refute File.exist?(project), 'created_root=true の場合は削除する'
        end
      end

      def test_cleanup_is_safe_when_directory_already_missing
        within_tmp do
          # ディレクトリが存在しなくても例外を投げない
          capture_stdout do
            NewCommands.send(:cleanup_partial_scaffold, 'nonexistent', true)
          end
          pass
        end
      end

      private

      # テスト用の一時カレントディレクトリで yield
      def within_tmp
        Dir.mktmpdir('vs-new-interrupt-') do |dir|
          Dir.chdir(dir) { yield }
        end
      end

      # FileUtils.cp が指定例外を投げるように Minitest stub で一時的に置換する。
      # ensure 不要で自動復元されるのでテスト間汚染がない。
      # @param error_class [Class]
      # @param message [String, nil]
      def with_fileutils_cp_raising(error_class, message = nil)
        stub_proc = lambda do |*_args, **_kwargs|
          raise message ? error_class.new(message) : error_class
        end
        FileUtils.stub(:cp, stub_proc) { yield }
      end

      def with_stubbed_stdin_interrupt
        original = $stdin
        fake = Object.new
        def fake.gets = raise Interrupt
        $stdin = fake
        yield
      ensure
        $stdin = original
      end

      def capture_stdout
        original = $stdout
        io = StringIO.new
        $stdout = io
        yield
        io.string.lines.map(&:chomp)
      ensure
        $stdout = original
      end
    end
  end
end
