# frozen_string_literal: true

# ================================================================
# robustness: 不正 SVG XML を外部変換コマンドに渡したときの挙動
# ================================================================
# 対応する堅牢性テスト仕様書項目:
#   - 7-1 (L253): SVG が不正な XML
#                 → ⚠️ rsvg/inkscape のエラーメッセージを整形して表示
#   docs/specs/vivlio_starter_robustness_test_spec.md
#
# 検証観点:
#   A. 外部コマンドが exit != 0 で失敗したとき、Common.log_error が
#      ユーザー向けに整形されたメッセージを出力する
#   B. exit 0 でも出力ファイルが生成されなかった場合は失敗として扱う
#   C. stderr の出力がある場合、メッセージ本文に stderr のダイジェストが含まれる
#   D. stderr が長大 (>12 行) の場合、中略表示される
#   E. コマンド自体が見つからない (Errno::ENOENT) 場合は専用メッセージ
#   F. 成功時は true を返し、余計なログを出さない
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'open3'
require 'vivlio_starter/cli/common'

module VivlioStarter
  module CLI
    class InvalidSvgTest < Minitest::Test
      def setup
        @tmpdir = Dir.mktmpdir('invalid-svg-')
        @input  = File.join(@tmpdir, 'broken.svg')
        @output = File.join(@tmpdir, 'out.pdf')
        File.write(@input, '<svg><unclosed-tag>', encoding: 'utf-8')
      end

      def teardown
        FileUtils.remove_entry(@tmpdir) if @tmpdir && File.exist?(@tmpdir)
      end

      # ----------------------------------------------------------------
      # A. exit != 0 のとき、人間向けメッセージが出力される
      # ----------------------------------------------------------------
      def test_logs_user_friendly_error_when_converter_exits_non_zero
        fake_status = Struct.new(:success?, :exitstatus).new(false, 1)
        stderr_text = "Error: XML parse error: couldn't parse <svg> tag"

        logged_errors = []
        Open3.stub(:capture3, ->(*_args) { ['', stderr_text, fake_status] }) do
          Common.stub(:log_error, ->(msg) { logged_errors << msg }) do
            result = Common.run_svg_converter!(
              ['rsvg-convert', '-f', 'pdf', '-o', @output, @input],
              input_path: @input, output_path: @output, purpose: 'テスト変換'
            )
            refute result, '失敗時は false を返すこと'
          end
        end

        assert_equal 1, logged_errors.size, '失敗時にエラーが 1 件記録されること'
        msg = logged_errors.first
        assert_includes msg, 'SVG 変換に失敗しました', '整形メッセージを含むこと'
        assert_includes msg, '（テスト変換）', 'purpose がメッセージに含まれること'
        assert_includes msg, @input, '入力パスが含まれること'
        assert_includes msg, 'rsvg-convert', '実行コマンド名が含まれること'
        assert_includes msg, '終了コード: 1', 'exit code が含まれること'
        assert_includes msg, 'XML parse error', 'stderr のダイジェストが含まれること'
      end

      # ----------------------------------------------------------------
      # B. exit 0 でも出力ファイルが生成されていない場合は失敗扱い
      # ----------------------------------------------------------------
      def test_fails_when_exit_zero_but_output_file_missing
        fake_status = Struct.new(:success?, :exitstatus).new(true, 0)

        logged_errors = []
        Open3.stub(:capture3, ->(*_args) { ['', '', fake_status] }) do
          Common.stub(:log_error, ->(msg) { logged_errors << msg }) do
            # @output は生成しないまま exit 0 を返すスタブ
            result = Common.run_svg_converter!(
              ['rsvg-convert', '-o', @output, @input],
              input_path: @input, output_path: @output
            )
            refute result, 'exit 0 でも出力ファイル未生成なら false を返すこと'
          end
        end

        assert_equal 1, logged_errors.size
        assert_includes logged_errors.first, '出力ファイルが生成されませんでした'
      end

      # ----------------------------------------------------------------
      # C. stderr が空の場合はその旨を記載
      # ----------------------------------------------------------------
      def test_digest_indicates_empty_stderr
        fake_status = Struct.new(:success?, :exitstatus).new(false, 2)

        logged_errors = []
        Open3.stub(:capture3, ->(*_args) { ['', '', fake_status] }) do
          Common.stub(:log_error, ->(msg) { logged_errors << msg }) do
            Common.run_svg_converter!(
              ['rsvg-convert', '-o', @output, @input],
              input_path: @input
            )
          end
        end

        assert_includes logged_errors.first, '（出力なし）',
                        'stderr が空でも欠落ではなく明示されること'
      end

      # ----------------------------------------------------------------
      # D. stderr が長大 (>12 行) の場合、中略表示される
      # ----------------------------------------------------------------
      def test_digest_truncates_long_stderr
        fake_status = Struct.new(:success?, :exitstatus).new(false, 1)
        long_stderr = (1..30).map { |i| "line #{i}" }.join("\n")

        logged_errors = []
        Open3.stub(:capture3, ->(*_args) { ['', long_stderr, fake_status] }) do
          Common.stub(:log_error, ->(msg) { logged_errors << msg }) do
            Common.run_svg_converter!(
              ['rsvg-convert', '-o', @output, @input],
              input_path: @input
            )
          end
        end

        msg = logged_errors.first
        assert_includes msg, 'line 1',  '先頭行が含まれること'
        assert_includes msg, 'line 30', '末尾行が含まれること'
        assert_includes msg, '... (中略) ...', '長大な stderr は中略されること'
        refute_includes msg, 'line 15', '中間行は省略されること'
      end

      # ----------------------------------------------------------------
      # E. コマンド自体が見つからない場合 (Errno::ENOENT)
      # ----------------------------------------------------------------
      def test_logs_friendly_message_when_command_not_found
        logged_errors = []
        Open3.stub(:capture3, ->(*_args) { raise Errno::ENOENT, 'rsvg-convert' }) do
          Common.stub(:log_error, ->(msg) { logged_errors << msg }) do
            result = Common.run_svg_converter!(
              ['rsvg-convert', '-o', @output, @input],
              input_path: @input, output_path: @output
            )
            refute result
          end
        end

        assert_equal 1, logged_errors.size
        assert_includes logged_errors.first, 'SVG 変換コマンドが見つかりません'
        assert_includes logged_errors.first, 'rsvg-convert'
      end

      # ----------------------------------------------------------------
      # F. 成功時は true を返し、ログは出さない
      # ----------------------------------------------------------------
      def test_returns_true_on_success_without_logging
        fake_status = Struct.new(:success?, :exitstatus).new(true, 0)

        logged_errors = []
        Open3.stub(:capture3, ->(*_args) do
          # 出力ファイルを実際に作成したことにする
          File.write(@output, 'dummy', encoding: 'utf-8')
          ['', '', fake_status]
        end) do
          Common.stub(:log_error, ->(msg) { logged_errors << msg }) do
            result = Common.run_svg_converter!(
              ['rsvg-convert', '-o', @output, @input],
              input_path: @input, output_path: @output
            )
            assert result, '成功時は true を返すこと'
          end
        end

        assert_empty logged_errors, '成功時には Common.log_error を呼ばないこと'
      end

      # ----------------------------------------------------------------
      # G. output_path 未指定の場合は exit ステータスだけで判定
      # ----------------------------------------------------------------
      def test_skips_output_file_check_when_output_path_not_given
        fake_status = Struct.new(:success?, :exitstatus).new(true, 0)

        Open3.stub(:capture3, ->(*_args) { ['', '', fake_status] }) do
          result = Common.run_svg_converter!(
            ['rsvg-convert', '-o', @output, @input],
            input_path: @input # output_path は渡さない
          )
          assert result, 'output_path 未指定なら exit 成功だけで true を返すこと'
        end
      end

      # ----------------------------------------------------------------
      # H. format_converter_stderr のエッジケース
      # ----------------------------------------------------------------
      def test_format_converter_stderr_handles_nil_and_blank
        assert_equal 'stderr: （出力なし）', Common.format_converter_stderr(nil)
        assert_equal 'stderr: （出力なし）', Common.format_converter_stderr('')
        assert_equal 'stderr: （出力なし）', Common.format_converter_stderr("   \n  ")
      end
    end
  end
end
