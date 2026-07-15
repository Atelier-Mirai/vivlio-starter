# frozen_string_literal: true

# ================================================================
# robustness: lint --fix の書き戻しと、中断時の原稿保護
# ================================================================
# 対応する堅牢性テスト仕様書項目:
#   - 5-6-2 (L231): --fix 実行中に Ctrl+C
#                   → 元ファイルが textlint-disable に置換されたまま
#                     残る可能性を懸念していた
#   docs/specs/vivlio_starter_robustness_test_spec.md
#
# 現行実装の設計（docs/specs/lint-notation-guard-spec.md §2.3）:
#   `convert_vs_lint_comments` は元ファイルを書き換えず、変換後の内容を `Tempfile`
#   に書き出して textlint へ渡す。--fix 指定時は「修正パス → 解析パス」の 2 段構成で、
#   修正パスが一時ファイルを textlint に直させ、**textlint プロセスの正常終了後にのみ**
#   vs-lint コメント形へ逆変換して原稿へ書き戻す。書き戻しは rename による
#   アトミック置換なので、原稿は「旧内容のまま」か「新内容へ完全置換済み」の
#   どちらかにしかならない。よって 5-6-2 の懸念（`textlint-disable` に置換された
#   まま残る）は発生しない。
#
# 検証観点:
#   A-1. --fix なしの正常終了では原稿が変更されないこと
#   A-2. --fix ありで textlint が修正した場合、原稿へ反映され、かつ
#        vs-lint コメント形へ逆変換されていること
#   A-3. textlint が何も修正しなかった場合、原稿へ書き戻さないこと（mtime 不変）
#   B. `Open3.capture3` で Interrupt を受けても原稿が変更されないこと
#   C. `Open3.capture3` で StandardError を受けても同様に保護されること
#   D. どのパスでも一時ファイル (/tmp/textlint_*.md) が残らないこと
#   E. textlint へ渡すのは常に一時ファイルであり、原稿を直接掴ませないこと
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

      # textlint --fix が一時ファイルへ書き込む「修正後の内容」を模したもの。
      # 一時ファイルの中身は textlint ネイティブ形のコメントになっているため、
      # 修正結果もこの形で返る（＝書き戻し時に逆変換が要る）。
      TEXTLINT_FIXED_CONTENT = <<~MD
        # テスト章

        <!-- textlint-disable-next-line -->
        これは故意にルールを破る文章でございます。

        <!-- textlint-disable -->
        一つ目の壊れた段落。
        二つ目の壊れた段落。
        <!-- textlint-enable -->

        通常段落。
      MD

      # 原稿へ書き戻された結果の期待値。修正が反映され、コメントは vs-lint 形へ戻る。
      EXPECTED_AFTER_FIX = <<~MD
        # テスト章

        <!-- vs-lint-disable-next-line -->
        これは故意にルールを破る文章でございます。

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
      # A-1. --fix なしの正常終了では原稿が変更されない
      # ----------------------------------------------------------------
      def test_should_not_touch_original_file_without_fix_option
        with_stubbed_textlint(fix_result: TEXTLINT_FIXED_CONTENT) do
          capture_io { LintCommands.execute_lint(['11-target'], fix: false) }
        end

        assert_equal ORIGINAL_CONTENT, File.read(@target_path, encoding: 'UTF-8'),
                     '--fix なしなら原稿は変更されないこと'
        assert_empty stale_textlint_tempfiles,
                     '一時ファイルが残ってはならない'
      end

      # ----------------------------------------------------------------
      # A-2. --fix ありで textlint が修正した内容が原稿へ反映される
      # ----------------------------------------------------------------
      def test_should_write_back_fixes_with_vs_lint_comments_restored
        with_stubbed_textlint(fix_result: TEXTLINT_FIXED_CONTENT) do
          capture_io { LintCommands.execute_lint(['11-target'], fix: true) }
        end

        assert_equal EXPECTED_AFTER_FIX, File.read(@target_path, encoding: 'UTF-8'),
                     '--fix の正常終了では修正が原稿へ反映され、コメントは vs-lint 形へ戻ること'
        assert_empty stale_textlint_tempfiles,
                     '一時ファイルが残ってはならない'
        assert_empty stale_write_back_tempfiles,
                     '書き戻し用の一時ファイルが contents/ へ残ってはならない'
      end

      # ----------------------------------------------------------------
      # A-3. textlint が何も修正しなければ原稿へ書き戻さない
      # ----------------------------------------------------------------
      def test_should_not_write_back_when_textlint_fixed_nothing
        past = Time.now - 3600
        File.utime(past, past, @target_path)

        with_stubbed_textlint(fix_result: nil) do
          capture_io { LintCommands.execute_lint(['11-target'], fix: true) }
        end

        assert_equal ORIGINAL_CONTENT, File.read(@target_path, encoding: 'UTF-8'),
                     '修正が無ければ原稿の内容は不変であること'
        assert_equal past.to_i, File.mtime(@target_path).to_i,
                     '修正が無ければ原稿へ書き込まないこと（mtime 不変）'
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
      # E. textlint に渡されるパスは元ファイルではなく Tempfile であること
      # ----------------------------------------------------------------
      # 中断時に原稿が壊れない根拠（textlint に原稿を直接掴ませない）を明示する。
      # --fix 時は修正パス（--fix つき）と解析パス（--format json）の 2 回呼ばれる。
      def test_textlint_receives_tempfile_not_original_path
        calls = nil
        with_stubbed_textlint(fix_result: TEXTLINT_FIXED_CONTENT) do |recorded|
          capture_io { LintCommands.execute_lint(['11-target'], fix: true) }
          calls = recorded
        end

        assert_equal 2, calls.size, '修正パスと解析パスで 2 回実行されること'
        assert(calls.any? { |args| args.include?('--fix') },
               '修正パスでは --fix が渡されること')
        refute(calls.last.include?('--fix'),
               '解析パスでは --fix を渡さないこと（一時ファイルを直して捨てる no-op になるため）')

        calls.each do |args|
          md_paths = markdown_paths(args)
          refute_empty md_paths, 'Markdown パスが渡されていること'
          md_paths.each do |path|
            refute_equal File.expand_path(@target_path), File.expand_path(path),
                         '元ファイルパスを textlint に直接渡してはならない（tempfile 経由であるべき）'
          end
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

      # 書き戻し用の一時ファイル（原稿と同一ディレクトリに作る）が残っていないか
      def stale_write_back_tempfiles
        Dir.glob(File.join('contents', '.vs-lint-fix-*'))
      end

      def markdown_paths(args)
        args.select { |a| a.to_s.end_with?('.md') }
      end

      # textlint 実行を差し替える。fix_result を渡すと、--fix つきの呼び出しで
      # 一時ファイルへその内容を書き込む（textlint が修正した状況を模す）。
      # ブロックには記録された呼び出し引数の配列を渡す。
      def with_stubbed_textlint(fix_result:)
        fake_status = Struct.new(:success?, :exitstatus).new(true, 0)
        calls = []
        stub = lambda do |*args|
          calls << args
          if args.include?('--fix') && fix_result
            markdown_paths(args).each { |path| File.write(path, fix_result, encoding: 'UTF-8') }
          end
          ['', '', fake_status]
        end

        with_stubbed_textlint_available do
          Open3.stub(:capture3, stub) { yield calls }
        end
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
