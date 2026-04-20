# frozen_string_literal: true

# ================================================================
# Test: build_lock_test.rb
# ================================================================
# 検証内容:
#   - 通常のロック取得・解放（ブロック実行後にファイル削除）
#   - 二重取得時に AlreadyLockedError が送出される
#   - ブロック内で例外発生時でもロックが解放される
#   - ロックファイルに PID が記録される
# ================================================================

require_relative '../../../../test_helper'
require 'tmpdir'
require 'fileutils'
require 'vivlio/starter/cli/build/build_lock'

module Vivlio
  module Starter
    module CLI
      module BuildCommands
        class BuildLockTest < Minitest::Test
          BL = BuildLock

          def setup
            @orig_dir = Dir.pwd
            @tmpdir = Dir.mktmpdir
            Dir.chdir(@tmpdir)
            FileUtils.mkdir_p('.cache/vs')
          end

          def teardown
            Dir.chdir(@orig_dir)
            FileUtils.remove_entry(@tmpdir)
          end

          def lock_path
            File.join(Dir.pwd, '.cache/vs/.build.lock')
          end

          # 通常のロック取得・解放
          def test_acquires_and_releases_lock
            executed = false
            BL.with_lock { executed = true }
            assert executed, 'ブロックが実行されるべき'
            refute File.exist?(lock_path), 'ロックファイルが削除されるべき'
          end

          # ブロックの戻り値が返る
          def test_returns_block_value
            assert_equal 42, BL.with_lock { 42 }
          end

          # ブロック内で例外発生時もロックは解放される
          def test_releases_lock_on_exception
            assert_raises(RuntimeError) do
              BL.with_lock { raise 'boom' }
            end
            refute File.exist?(lock_path), '例外時もロックファイルが削除されるべき'

            # 再取得できることを確認
            executed = false
            BL.with_lock { executed = true }
            assert executed
          end

          # 既にロック中のプロジェクトでは AlreadyLockedError が出る
          def test_raises_when_already_locked
            # 手動で lock_path を開いて flock を掛ける
            holder = File.open(lock_path, File::RDWR | File::CREAT, 0o644)
            holder.flock(File::LOCK_EX | File::LOCK_NB)

            err = assert_raises(BL::AlreadyLockedError) do
              BL.with_lock { flunk '実行されてはいけない' }
            end

            assert_match(/vs build/, err.message)
            assert_match(/ロックファイル/, err.message)
          ensure
            holder&.flock(File::LOCK_UN)
            holder&.close
          end

          # ロックファイルに PID が記録される
          def test_writes_pid_to_lock_file
            recorded_content = nil
            BL.with_lock do
              recorded_content = File.read(lock_path)
            end
            assert_match(/pid=#{Process.pid}/, recorded_content)
            assert_match(/started=/, recorded_content)
          end
        end
      end
    end
  end
end
