# frozen_string_literal: true

# ================================================================
# robustness: プロジェクトルートへの書き込み権限なし
# ================================================================
# 対応する堅牢性テスト仕様書項目:
#   - 1-3-1 (L77): プロジェクトルートへの書き込み権限なし
#                  → ⚠️ PDF 出力段階で明示的エラー
#   docs/specs/vivlio_starter_robustness_test_spec.md
#
# 期待される挙動:
#   書き込み不可のディレクトリで Ruby 側のファイル作成が発生した場合、
#   握り潰さずに Errno::EACCES / Errno::EPERM / Errno::EROFS を送出し、
#   人間が状況を理解できるメッセージを表示する。
#
# 検証対象:
#   A. Common.ensure_cache_dir! が書き込み不可ディレクトリで明示エラー
#   B. NewCommands.expand_scaffold が書き込み不可ディレクトリで明示エラー
#      （新設の cleanup_partial_scaffold が元例外を握り潰さないこと）
#
# 副作用安全策:
#   - Dir.mktmpdir のブロック形式を使用
#   - ensure で必ず chmod 0o755 に復旧してから mktmpdir ブロックを抜ける
#   - root 実行時は chmod が効かないため skip
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'stringio'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/new'

module VivlioStarter
  module CLI
    class ReadonlyProjectRootTest < Minitest::Test
      def setup
        skip 'root 権限下では chmod が効かないためスキップ' if Process.uid.zero?
      end

      # ----------------------------------------------------------------
      # A. Common.ensure_cache_dir!
      # ----------------------------------------------------------------

      def test_ensure_cache_dir_raises_eacces_in_readonly_root
        in_readonly_project do |_root|
          err = assert_raises(SystemCallError) do
            Common.ensure_cache_dir!
          end
          assert_permission_error(err)
        end
      end

      # ----------------------------------------------------------------
      # B. NewCommands.expand_scaffold
      # ----------------------------------------------------------------

      def test_expand_scaffold_raises_permission_error_in_readonly_parent
        in_readonly_project do |_root|
          project = 'locked-book'
          refute File.exist?(project)

          capture_stdout do
            err = assert_raises(SystemCallError) do
              NewCommands.send(:expand_scaffold, nil, project, NewCommands::DEFAULT_ANSWERS.dup)
            end
            assert_permission_error(err)
          end

          refute File.exist?(project),
                 '書込不可時は project ディレクトリも作成されないこと'
        end
      end

      # cleanup_partial_scaffold は元例外を握り潰してはいけない
      # ※ 事前に project dir を作ってから親を read-only にし、
      #   FileUtils.cp を EACCES で失敗させる。rm_rf は親が read-only なので失敗するが、
      #   それでも元の SystemCallError が raise され続けるべき。
      def test_cleanup_failure_does_not_mask_original_error
        in_readonly_project do |_root|
          project = 'pre-created'
          # 既存ディレクトリでない扱いにするため、先に作らない
          # 代わりに FileUtils.cp 経由で EACCES にする

          stub_proc = ->(*_a, **_k) { raise Errno::EACCES, 'disk read-only' }

          capture_stdout do
            err = assert_raises(SystemCallError) do
              FileUtils.stub(:cp, stub_proc) do
                NewCommands.send(:expand_scaffold, nil, project, NewCommands::DEFAULT_ANSWERS.dup)
              end
            end
            assert_permission_error(err)
          end
        end
      end

      # ----------------------------------------------------------------
      # ヘルパー
      # ----------------------------------------------------------------

      private

      # 書込不可の一時ディレクトリを作り、その中で yield する。
      # 権限の付け替えは mktmpdir の **内部** だけで行い、
      # ensure で必ず 0o755 に戻してから mktmpdir に削除を任せる。
      def in_readonly_project
        Dir.mktmpdir('vs-ro-root-') do |root|
          Dir.chdir(root) do
            begin
              File.chmod(0o555, root) # r-x r-x r-x
              # Ruby の chmod は即反映される。書込できないことを一応自己検証する。
              skip '一時ディレクトリの chmod が効いていないためスキップ' if writable_now?(root)

              yield root
            ensure
              File.chmod(0o755, root) # mktmpdir のクリーンアップが成功するよう復旧
            end
          end
        end
      end

      # 実際に書き込みができないか試す（macOS の特殊 FS 対策）
      def writable_now?(dir)
        probe = File.join(dir, ".vs-writable-probe-#{rand(1_000_000)}")
        File.write(probe, 'x')
        File.delete(probe)
        true
      rescue SystemCallError
        false
      end

      # Errno::EACCES / EPERM / EROFS のいずれかで、
      # 人間可読なメッセージ（Permission denied 相当）を含むこと
      def assert_permission_error(err)
        assert_kind_of SystemCallError, err
        acceptable = [Errno::EACCES, Errno::EPERM, Errno::EROFS]
        assert(acceptable.any? { |klass| err.is_a?(klass) },
               "想定外の errno: #{err.class} (#{err.message})")
        # エラーメッセージに空の文字列ではなく、何らかの説明が含まれていること
        refute_empty err.message, 'エラーメッセージが空であってはならない'
      end

      def capture_stdout
        original = $stdout
        io = StringIO.new
        $stdout = io
        yield
        io.string
      ensure
        $stdout = original
      end
    end
  end
end
