# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/build/build_lock.rb
# ================================================================
# 責務:
#   同一プロジェクトで vs build が多重実行されないよう排他ロックを提供する。
#   .cache/vs/.build.lock を File::LOCK_EX | File::LOCK_NB で取得し、
#   取得できない場合は AlreadyLockedError を送出する。
#
# 設計判断:
#   - NB（非ブロッキング）にすることで、既にビルド中のプロジェクトに対して
#     「ビルド中につきスキップ」を即座に報告できる（待機せず即エラー）。
#   - ロックファイルに PID と開始時刻を書き込むため、残存ロックの原因調査が
#     可能。ensure で LOCK_UN してから rm_f するので正常終了時は残らない。
#   - kill -9 等で強制終了された場合ロックファイルは残るが、flock は
#     プロセス終了時に OS が解放するため、次回起動時の取得は可能。
# ================================================================

require 'fileutils'
require 'time'

require_relative '../common'

module VivlioStarter
  module CLI
    module BuildCommands
      # 同一プロジェクトでの vs build 多重実行を防ぐ排他ロック機構。
      # .cache/vs/.build.lock に対し File::LOCK_EX | File::LOCK_NB で
      # フロックを取得し、競合時は AlreadyLockedError を送出する。
      module BuildLock
        LOCK_FILENAME = '.build.lock'

        # 既に別プロセスがロックを保持しているときに送出される例外
        class AlreadyLockedError < RuntimeError; end

        module_function

        # ロックを取得してブロックを実行する。終了時に自動で解放する。
        # @yield ロック取得中に実行するブロック
        # @return [Object] ブロックの戻り値
        # @raise [AlreadyLockedError] 既にロックが取得されている場合
        def with_lock
          lock_path = File.join(VivlioStarter::CLI::Common.ensure_cache_dir!, LOCK_FILENAME)
          # ブロック形式は flock を yield 越しに保持できないため使用しない
          file = File.open(lock_path, File::RDWR | File::CREAT, 0o644) # rubocop:disable Style/FileOpen

          unless file.flock(File::LOCK_EX | File::LOCK_NB)
            existing = read_lock_info(file)
            file.close
            raise AlreadyLockedError, build_conflict_message(lock_path, existing)
          end

          write_lock_info(file)

          begin
            yield
          ensure
            file.flock(File::LOCK_UN)
            file.close
            FileUtils.rm_f(lock_path)
          end
        end

        def read_lock_info(file)
          file.rewind
          file.read
        rescue StandardError
          ''
        end

        def write_lock_info(file)
          file.truncate(0)
          file.rewind
          file.write("pid=#{Process.pid}\nstarted=#{Time.now.iso8601}\n")
          file.flush
        end

        def build_conflict_message(lock_path, existing)
          hint = existing.to_s.strip
          hint_section = hint.empty? ? '' : "\n  既存ロック情報:\n#{hint.lines.map { "    #{it}" }.join}"
          <<~MSG.strip
            別の vs build プロセスがこのプロジェクトで実行中です。
              ロックファイル: #{lock_path}#{hint_section}
              完了を待ってから再実行するか、該当プロセスを終了してください。
          MSG
        end
      end
    end
  end
end
