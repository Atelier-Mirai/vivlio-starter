# frozen_string_literal: true

# ================================================================
# robustness: lint --fix 実行中に Ctrl+C を受けても元ファイルが壊れない
# ================================================================
# 対応する堅牢性テスト仕様書項目:
#   - 5-6-2 (L231): --fix 実行中に Ctrl+C
#                   → 元ファイルが textlint-disable に置換されたまま
#                     残る可能性を懸念していた
#   docs/specs/vivlio_starter_robustness_test_spec.md
#
# 結論（回帰テストによる明文化）:
#   現行実装 (`lib/vivlio_starter/cli/lint.rb`) の `convert_vs_lint_comments`
#   は元ファイルを **一切書き換えず**、変換後の内容は `Tempfile` に書き出し、
#   textlint にはその一時ファイルを渡す。`call` メソッドの `ensure` 節で必ず
#   `cleanup_temp_files` を呼ぶため、中断（Interrupt / StandardError）発生時でも
#   「元ファイルが `textlint-disable` に置換されたまま残る」シナリオは **発生しない**。
#
# 検証観点:
#   A. 正常終了時に元ファイルが変更されていないこと
#   B. `Open3.capture3` で Interrupt を受けても元ファイルが変更されないこと
#   C. `Open3.capture3` で StandardError を受けても同様に保護されること
#   D. どのパスでも一時ファイル (/tmp/textlint_*.md) が残らないこと
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'stringio'
require 'tempfile'
require 'open3'
require 'vivlio_starter/cli/lint'

module VivlioStarter
  module CLI
    class LintFixInterruptTest < Minitest::Test
      ORIGINAL_CONTENT = <<~MD
        # テスト章

        <!-- vs-lint-disable-next-line -->
        これは故意にルールを破る文章で御座います。

        <!-- vs-lint-disable -->
        一つ目の壊れた段落。
        二つ目の壊れた段落。
        <!-- vs-lint-enable -->

        通常段落。
      MD

      def setup
        @original_pwd = Dir.pwd
        @tmpdir = Dir.mktmpdir('lint-fix-interrupt-')
        Dir.chdir(@tmpdir)
        setup_project_structure
        @target_path = File.join('contents', '11-target.md')
        File.write(@target_path, ORIGINAL_CONTENT, encoding: 'UTF-8')

        @env_backup = ENV['VIVLIO_TEXTLINT_BIN']
        ENV['VIVLIO_TEXTLINT_BIN'] = 'textlint'
      end

      def teardown
        ENV['VIVLIO_TEXTLINT_BIN'] = @env_backup
        Dir.chdir(@original_pwd)
        FileUtils.remove_entry(@tmpdir) if @tmpdir && File.exist?(@tmpdir)
      end

      # ----------------------------------------------------------------
      # A. 正常終了時に元ファイルが変更されていない
      # ----------------------------------------------------------------
      def test_original_file_is_untouched_on_normal_completion
        fake_status = Struct.new(:success?, :exitstatus).new(true, 0)

        with_stubbed_textlint_available do
          Open3.stub(:capture3, ->(*_args) { ['', '', fake_status] }) do
            capture_io { LintCommands.execute_lint(['11-target'], fix: true) }
          end
        end

        assert_equal ORIGINAL_CONTENT, File.read(@target_path, encoding: 'UTF-8'),
                     '正常終了時でも元ファイルは変更されないこと'
        assert_empty stale_textlint_tempfiles,
                     '一時ファイルが残ってはならない'
      end

      # ----------------------------------------------------------------
      # B. Interrupt 発生時も元ファイルは保護される
      # ----------------------------------------------------------------
      def test_original_file_is_untouched_when_interrupt_raised
        with_stubbed_textlint_available do
          Open3.stub(:capture3, ->(*_args) { raise Interrupt }) do
            assert_raises(Interrupt) do
              capture_io { LintCommands.execute_lint(['11-target'], fix: true) }
            end
          end
        end

        assert_equal ORIGINAL_CONTENT, File.read(@target_path, encoding: 'UTF-8'),
                     'Ctrl+C で中断しても元ファイルは変更されないこと（5-6-2 回帰）'
        assert_empty stale_textlint_tempfiles,
                     'Interrupt 後も一時ファイルは残ってはならない'
      end

      # ----------------------------------------------------------------
      # C. 予期せぬ StandardError が発生しても元ファイルは保護される
      # ----------------------------------------------------------------
      def test_original_file_is_untouched_when_standard_error_raised
        with_stubbed_textlint_available do
          Open3.stub(:capture3, ->(*_args) { raise StandardError, 'pipe broken' }) do
            assert_raises(StandardError) do
              capture_io { LintCommands.execute_lint(['11-target'], fix: true) }
            end
          end
        end

        assert_equal ORIGINAL_CONTENT, File.read(@target_path, encoding: 'UTF-8'),
                     '予期せぬ例外発生時も元ファイルは変更されないこと'
        assert_empty stale_textlint_tempfiles,
                     '例外発生後も一時ファイルは残ってはならない'
      end

      # ----------------------------------------------------------------
      # D. textlint に渡されるパスは元ファイルではなく Tempfile であること
      # ----------------------------------------------------------------
      # 現状実装の安全性の根拠を明示する確認テスト。
      def test_textlint_receives_tempfile_not_original_path
        fake_status = Struct.new(:success?, :exitstatus).new(true, 0)
        received_args = nil

        with_stubbed_textlint_available do
          Open3.stub(:capture3, ->(*args) do
            received_args = args
            ['', '', fake_status]
          end) do
            capture_io { LintCommands.execute_lint(['11-target'], fix: true) }
          end
        end

        # 最後の引数群に --fix があり、ファイルパスが元ファイルではないことを検証
        assert_includes received_args, '--fix',
                        '--fix フラグが渡されていること'

        path_args = received_args.reject { |a| a.start_with?('-') || a == 'textlint' }
        passed_md_paths = path_args.select { |a| a.to_s.end_with?('.md') }
        refute_empty passed_md_paths, 'Markdown パスが渡されていること'
        passed_md_paths.each do |p|
          refute_equal File.expand_path(@target_path), File.expand_path(p),
                       '元ファイルパスを textlint に直接渡してはならない（tempfile 経由であるべき）'
        end
      end

      # ----------------------------------------------------------------
      # ヘルパー
      # ----------------------------------------------------------------
      private

      # Lint が使う tempdir (Dir.tmpdir) 配下に
      # textlint_*.md という名前のファイルが残っていないかを返す
      def stale_textlint_tempfiles
        Dir.glob(File.join(Dir.tmpdir, 'textlint_*.md'))
      end

      def with_stubbed_textlint_available
        runner = LintCommands::LintRunner
        original = runner.instance_method(:ensure_textlint_available!)
        runner.define_method(:ensure_textlint_available!) { nil }
        yield
      ensure
        runner.define_method(:ensure_textlint_available!) do |*args, &block|
          original.bind(self).call(*args, &block)
        end
      end

      def setup_project_structure
        FileUtils.mkdir_p('contents')
        FileUtils.mkdir_p('config/textlint_dictionaries')
        File.write('config/.textlintrc.yml', "rules: {}\n")
        File.write('config/textlint_allowlist.yml', "allow: []\n")
        File.write('config/textlint_prh.yml', "rules: []\n")
        File.write('config/catalog.yml', "CHAPTERS:\n  - 11-target\n")
        File.write('config/textlint_dictionaries/prh.yml', "version: 1\nrules: []\n")
        File.write('config/textlint_dictionaries/icsmedia.yml', "version: 1\nrules: []\n")
        File.write('config/textlint_dictionaries/js_primer.yml', "version: 1\nrules: []\n")
      end
    end
  end
end
