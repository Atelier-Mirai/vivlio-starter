# frozen_string_literal: true

# ================================================================
# robustness: 外部コマンド不在時の案内メッセージ
# ================================================================
# 対応する堅牢性テスト仕様書項目:
#   - 4-1-1 (L176): `vivliostyle` コマンド不在 → vs doctor --fix 案内
#   - 4-1-2 (L177): `inkscape` 不在でカバー生成
#   - 4-1-3 (L178): `imagemagick` 不在
#   docs/specs/vivlio_starter_robustness_test_spec.md
#
# 期待される挙動:
#   "command not found" の生ログではなく、`vs doctor` / `vs doctor --fix`
#   への誘導を含む、人間に読めるエラーメッセージを出す。
#
# 本テストの対象:
#   Common モジュールに新設された共通ヘルパー
#     - Common.external_command_available?(cmd)
#     - Common.missing_external_command_message(cmd, purpose:)
#     - Common.ensure_external_command!(cmd, purpose:)
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'vivlio_starter/cli/common'

module VivlioStarter
  module CLI
    class MissingExternalCommandTest < Minitest::Test
      # ----------------------------------------------------------------
      # external_command_available?
      # ----------------------------------------------------------------

      def test_available_returns_true_for_command_on_path
        with_fake_path do |bin_dir|
          create_executable(File.join(bin_dir, 'fakevivliostyle'))
          assert Common.external_command_available?('fakevivliostyle')
        end
      end

      def test_available_returns_false_for_missing_command
        with_fake_path do
          refute Common.external_command_available?('definitely-not-installed-xyz')
        end
      end

      def test_available_returns_false_for_blank_or_nil
        refute Common.external_command_available?('')
        refute Common.external_command_available?('   ')
        refute Common.external_command_available?(nil)
      end

      def test_available_accepts_absolute_path
        Dir.mktmpdir('vs-cmd-abs-') do |dir|
          path = File.join(dir, 'tool')
          create_executable(path)
          assert Common.external_command_available?(path)

          # 存在しない絶対パスは false
          refute Common.external_command_available?(File.join(dir, 'missing'))
        end
      end

      def test_available_rejects_directory
        Dir.mktmpdir('vs-cmd-dir-') do |dir|
          refute Common.external_command_available?(dir),
                 'ディレクトリを実行ファイルと誤認してはいけない'
        end
      end

      # ----------------------------------------------------------------
      # missing_external_command_message
      # ----------------------------------------------------------------

      def test_message_includes_command_name
        msg = Common.missing_external_command_message('vivliostyle')
        assert_includes msg, 'vivliostyle'
      end

      def test_message_guides_to_vs_doctor_fix
        msg = Common.missing_external_command_message('vivliostyle')
        assert_includes msg, 'vs doctor',
                        '案内に vs doctor が含まれるべき'
        assert_includes msg, 'vs doctor --fix',
                        '案内に vs doctor --fix が含まれるべき'
      end

      def test_message_is_not_raw_command_not_found
        # 仕様: "command not found" の生ログは不可
        msg = Common.missing_external_command_message('magick')
        refute_match(/\Acommand not found\z/i, msg.lines.first.to_s.chomp,
                     '生の command not found はメッセージ先頭に出してはならない')
        refute_match(/\A\s*sh:\s/i, msg)
      end

      def test_message_embeds_purpose_when_given
        msg = Common.missing_external_command_message('inkscape', purpose: 'カバー画像生成')
        assert_includes msg, 'カバー画像生成'
        assert_includes msg, 'inkscape'
      end

      def test_message_omits_purpose_when_blank
        msg_default = Common.missing_external_command_message('vivliostyle')
        msg_empty   = Common.missing_external_command_message('vivliostyle', purpose: '')
        msg_nil     = Common.missing_external_command_message('vivliostyle', purpose: nil)
        # 空 / nil / 省略 は同一扱い
        assert_equal msg_default, msg_empty
        assert_equal msg_default, msg_nil
      end

      # ----------------------------------------------------------------
      # ensure_external_command!
      # ----------------------------------------------------------------

      def test_ensure_does_not_raise_when_command_exists
        with_fake_path do |bin_dir|
          create_executable(File.join(bin_dir, 'fakevivliostyle'))
          # 例外が出ないことを確認（Minitest 慣例: assert_silent は stderr も見るので pass チェック）
          Common.ensure_external_command!('fakevivliostyle')
          pass
        end
      end

      def test_ensure_raises_with_vs_doctor_guidance_when_missing
        with_fake_path do
          err = assert_raises(StandardError) do
            Common.ensure_external_command!('definitely-not-installed-xyz')
          end
          assert_includes err.message, 'definitely-not-installed-xyz'
          assert_includes err.message, 'vs doctor --fix',
                          '例外メッセージに vs doctor --fix 案内が必要'
        end
      end

      # 4-1-1: vivliostyle 不在を模擬
      def test_ensure_raises_for_missing_vivliostyle
        with_fake_path do
          err = assert_raises(StandardError) do
            Common.ensure_external_command!('vivliostyle', purpose: 'PDF ビルド')
          end
          assert_includes err.message, 'vivliostyle'
          assert_includes err.message, 'PDF ビルド'
          assert_includes err.message, 'vs doctor'
        end
      end

      # 4-1-2: inkscape 不在を模擬
      def test_ensure_raises_for_missing_inkscape
        with_fake_path do
          err = assert_raises(StandardError) do
            Common.ensure_external_command!('inkscape', purpose: 'カバー画像生成')
          end
          assert_includes err.message, 'inkscape'
          assert_includes err.message, 'カバー画像生成'
          assert_includes err.message, 'vs doctor'
        end
      end

      # 4-1-3: imagemagick (magick) 不在を模擬
      def test_ensure_raises_for_missing_imagemagick
        with_fake_path do
          err = assert_raises(StandardError) do
            Common.ensure_external_command!('magick', purpose: '画像変換')
          end
          assert_includes err.message, 'magick'
          assert_includes err.message, '画像変換'
          assert_includes err.message, 'vs doctor'
        end
      end

      private

      # 実行可能ファイルを作る（所有者のみ rwx）
      def create_executable(path)
        File.write(path, "#!/bin/sh\nexit 0\n")
        File.chmod(0o755, path)
        path
      end

      # PATH を一時ディレクトリだけに絞って yield する。
      # 既存の PATH にある同名コマンドが混入するのを防ぐ。
      # @yieldparam bin_dir [String] 一時 bin ディレクトリの絶対パス
      def with_fake_path
        Dir.mktmpdir('vs-fake-path-') do |bin_dir|
          original = ENV.fetch('PATH', nil)
          ENV['PATH'] = bin_dir
          yield bin_dir
        ensure
          ENV['PATH'] = original
        end
      end
    end
  end
end
