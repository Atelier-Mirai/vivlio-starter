# frozen_string_literal: true

# ================================================================
# Test: lint_commands_test.rb
# ================================================================
# テスト対象:
#   LintCommands（lib/vivlio_starter/cli/lint.rb）
#
# 検証内容:
#   - Markdown ファイル未検出時の警告
#   - textlint 実行結果の解析
#   - 終了コードの適切な設定
#
# テスト環境:
#   - VIVLIO_TEXTLINT_BIN をスタブ化
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'yaml'
require 'vivlio_starter/cli/lint'

module VivlioStarter
  module CLI
    # LintCommands のユニットテスト
    class LintCommandsTest < Minitest::Test
      def setup
        @original_pwd = Dir.pwd
        @tmpdir = Dir.mktmpdir('textlint-test')
        Dir.chdir(@tmpdir)
        setup_project_structure
        @textlint_bin = ENV['VIVLIO_TEXTLINT_BIN']
        ENV['VIVLIO_TEXTLINT_BIN'] = 'textlint'
      end

      def teardown
        ENV['VIVLIO_TEXTLINT_BIN'] = @textlint_bin
        Dir.chdir(@original_pwd)
        FileUtils.remove_entry(@tmpdir) if @tmpdir && File.exist?(@tmpdir)
      end

      def test_runner_warns_when_no_markdown_found
        FileUtils.rm_rf('contents')

        status = nil
        logged_warnings = []
        with_stubbed_textlint_available do
          Common.stub :log_warn, ->(msg) { logged_warnings << msg } do
            capture_io { status = LintCommands.execute_lint([], {}) }
          end
        end
        assert status.zero?, "ステータスは 0 であること"
        assert logged_warnings.any? { it.include?('検査対象となる Markdown ファイルが見つかりません。') },
               "Markdown 未検出の警告が出力されること: #{logged_warnings.inspect}"
      end

      def test_runner_invokes_textlint_with_resolved_targets
        FileUtils.touch('contents/11-install.md')
        FileUtils.touch('contents/21-customize.md')

        expected_command = nil
        fake_status = Struct.new(:success?).new(true)
        def fake_status.exitstatus
          0
        end

        returned_status = nil
        with_stubbed_textlint_available do
          Open3.stub(:capture3, ->(*args) do
            expected_command = args
            ['STDOUT', 'STDERR', fake_status]
          end) do
            stdout, stderr = capture_io do
              returned_status = LintCommands.execute_lint(['11-install'], {})
            end
            # 出力は常に json 集約。'STDOUT' は不正 json なので生出力へフォールバックして表示される
            assert_match(/STDOUT/, stdout)
            assert_match(/✏️ 文章の品質チェックが完了しました/, stdout)
            assert_equal 'STDERR', stderr
          end
        end
        assert_equal 0, returned_status

        # vs-lint コメント変換により一時ファイルが使用されるため、
        # 一時ファイルのパスパターンをチェック（出力は常に --format json）
        assert_equal 'textlint', expected_command[0]
        assert_equal '--config', expected_command[1]
        # ベースの .textlintrc.yml か、book.yml の lint 設定で生成される
        # 実行時設定（.textlintrc-runtime-*.yml）か、いずれも config/ 配下の textlintrc。
        # 利用者の book.yml(lint設定) にテストを結合させないため、パスパターンで検証する。
        config_dir = Regexp.escape(File.expand_path('config'))
        assert_match %r{\A#{config_dir}/\.textlintrc(-runtime-[\w-]+)?\.yml\z}, expected_command[2],
                     '--config に config/ 配下の textlintrc が渡されること'
        assert_equal '--format', expected_command[3]
        assert_equal 'json', expected_command[4]
        assert_match %r{/textlint_.*\.md\z}, expected_command[5], '一時ファイルのパスが渡されること'
      end

      def test_runner_returns_non_zero_status_on_failure
        FileUtils.touch('contents/11-install.md')

        failure_status = Struct.new(:success?).new(false)
        def failure_status.exitstatus
          3
        end

        returned_status = nil
        with_stubbed_textlint_available do
          stdout, stderr = capture_io do
            Open3.stub(:capture3, ->(*_) { ['', '', failure_status] }) do
              returned_status = LintCommands.execute_lint([], {})
            end
          end
          assert_match(/✏️ 文章の品質チェックが完了しました/, stdout)
          assert_empty(stderr)
        end
        assert_equal 3, returned_status
      end

      # --fix は「修正パス（--fix つき）→ 解析パス（--format json）」の 2 回実行になる。
      # 解析パスに --fix を付けてはならない（解析用の一時ファイルを直して捨てるだけの
      # no-op になる。docs/specs/lint-notation-guard-spec.md §2.3）。
      def test_fix_option_runs_fix_pass_then_analysis_pass
        FileUtils.touch('contents/11-install.md')

        commands = []
        fake_status = Struct.new(:success?).new(true)
        def fake_status.exitstatus
          0
        end

        returned_status = nil
        with_stubbed_textlint_available do
          Open3.stub(:capture3, ->(*args) do
            commands << args
            ['STDOUT', 'STDERR', fake_status]
          end) do
            stdout, = capture_io do
              returned_status = LintCommands.execute_lint(['11-install'], { fix: true })
            end
            # 'STDOUT' は不正 json なので生出力へフォールバックして表示される
            assert_match(/STDOUT/, stdout)
            assert_match(/✏️ 文章の品質チェックが完了しました/, stdout)
          end
        end
        assert_equal 0, returned_status

        assert_equal 2, commands.size, '修正パスと解析パスで 2 回実行されること'
        fix_pass, analysis_pass = commands
        assert_includes fix_pass, '--fix', '修正パスには --fix が渡ること'
        refute_includes fix_pass, '--format', '修正パスは json 集約を取得しないこと'
        refute_includes analysis_pass, '--fix', '解析パスには --fix を渡さないこと'
        assert_includes analysis_pass, '--format', '解析パスは json 集約を取得すること'
      end

      # 一時ファイルは textlint の実行が終わるまで生存しなければならない。
      # Tempfile.new でパス文字列だけ保持すると、Tempfile オブジェクトの GC が
      # ファイナライザ経由でファイルを削除し、textlint が存在しないパスを黙って
      # 無視する（＝一部ファイルだけ検査されない）事故が実際に起きた。
      def test_converted_tempfiles_survive_garbage_collection
        FileUtils.touch('contents/11-install.md')
        FileUtils.touch('contents/21-customize.md')

        runner = LintCommands::LintRunner.new([], {})
        paths  = runner.send(:convert_vs_lint_comments, %w[contents/11-install.md contents/21-customize.md])
        GC.start

        paths.each do |path|
          assert File.exist?(path), "GC 後も一時ファイルが存在すること: #{path}"
        end
      ensure
        paths&.each { FileUtils.rm_f(it) }
      end

      def test_chapter_number_only_resolution
        setup_catalog(%w[91-appendix-a 93-appendix-d])
        FileUtils.touch('contents/91-appendix-a.md')
        FileUtils.touch('contents/92-appendix-c.md')
        FileUtils.touch('contents/93-appendix-d.md')

        expected_command = nil
        fake_status = Struct.new(:success?).new(true)
        def fake_status.exitstatus
          0
        end

        returned_status = nil
        with_stubbed_textlint_available do
          Open3.stub(:capture3, ->(*args) do
            expected_command = args
            ['STDOUT', 'STDERR', fake_status]
          end) do
            stdout, stderr = capture_io do
              returned_status = LintCommands.execute_lint(['91', '93'], {})
            end
            assert_match(/\ASTDOUT/, stdout)
            assert_equal 'STDERR', stderr
          end
        end
        assert_equal 0, returned_status

        # vs-lint コメント変換により一時ファイルが使用されるため、
        # 一時ファイルの数が正しいことを確認
        temp_files = expected_command.select { it.match?(%r{/textlint_.*\.md\z}) }
        assert_equal 2, temp_files.length, '2つの一時ファイルが渡されること'
      end

      def test_numeric_only_chapter_resolution
        setup_catalog(%w[15])
        FileUtils.touch('contents/15.md')

        expected_command = nil
        fake_status = Struct.new(:success?).new(true)
        def fake_status.exitstatus
          0
        end

        returned_status = nil
        with_stubbed_textlint_available do
          Open3.stub(:capture3, ->(*args) do
            expected_command = args
            ['STDOUT', 'STDERR', fake_status]
          end) do
            stdout, stderr = capture_io do
              returned_status = LintCommands.execute_lint(['15'], {})
            end
            assert_match(/STDOUT/, stdout)
            assert_equal 'STDERR', stderr
          end
        end

        assert_equal 0, returned_status
        # vs-lint コメント変換により一時ファイルが使用される
        temp_files = expected_command.select { it.match?(%r{/textlint_.*\.md\z}) }
        assert_equal 1, temp_files.length, '1つの一時ファイルが渡されること'
      end

      def test_range_specification_resolution
        setup_catalog(%w[11-install 12-setup 13-build 21-customize])
        FileUtils.touch('contents/11-install.md')
        FileUtils.touch('contents/12-setup.md')
        FileUtils.touch('contents/13-build.md')
        FileUtils.touch('contents/21-customize.md')

        expected_command = nil
        fake_status = Struct.new(:success?).new(true)
        def fake_status.exitstatus
          0
        end

        returned_status = nil
        with_stubbed_textlint_available do
          Open3.stub(:capture3, ->(*args) do
            expected_command = args
            ['STDOUT', 'STDERR', fake_status]
          end) do
            stdout, stderr = capture_io do
              returned_status = LintCommands.execute_lint(['11-13'], {})
            end
            assert_match(/\ASTDOUT/, stdout)
            assert_equal 'STDERR', stderr
          end
        end
        assert_equal 0, returned_status

        # vs-lint コメント変換により一時ファイルが使用される
        # 11-13 の範囲なので3つのファイル
        temp_files = expected_command.select { it.match?(%r{/textlint_.*\.md\z}) }
        assert_equal 3, temp_files.length, '3つの一時ファイルが渡されること'
      end

      def test_mixed_target_resolution
        setup_catalog(%w[11-install 12-setup 21-customize 91-appendix-a])
        FileUtils.touch('contents/11-install.md')
        FileUtils.touch('contents/12-setup.md')
        FileUtils.touch('contents/21-customize.md')
        FileUtils.touch('contents/91-appendix-a.md')

        expected_command = nil
        fake_status = Struct.new(:success?).new(true)
        def fake_status.exitstatus
          0
        end

        returned_status = nil
        with_stubbed_textlint_available do
          Open3.stub(:capture3, ->(*args) do
            expected_command = args
            ['STDOUT', 'STDERR', fake_status]
          end) do
            stdout, stderr = capture_io do
              returned_status = LintCommands.execute_lint(['11-install', '91', '11-12'], {})
            end
            assert_match(/\ASTDOUT/, stdout)
            assert_equal 'STDERR', stderr
          end
        end
        assert_equal 0, returned_status

        # vs-lint コメント変換により一時ファイルが使用される
        # 11-install, 91, 11-12(11と12) の指定
        # TokenResolver が重複を除去するかどうかに依存するため、
        # 一時ファイルが渡されていることだけを確認
        temp_files = expected_command.select { it.match?(%r{/textlint_.*\.md\z}) }
        assert temp_files.length >= 3, "少なくとも3つの一時ファイルが渡されること (実際: #{temp_files.length})"
      end

      def test_target_resolver_zero_pads_single_digit
        setup_catalog(%w[01-life])
        FileUtils.touch('contents/01-life.md')

        resolver = LintCommands::LintRunner::TargetResolver.new(['1'])
        result = resolver.resolve

        assert_equal [File.join('contents', '01-life.md')], result
      end

      def test_target_resolver_handles_descending_range
        setup_catalog(%w[03-c 04-d 05-e])
        FileUtils.touch('contents/03-c.md')
        FileUtils.touch('contents/04-d.md')
        FileUtils.touch('contents/05-e.md')

        resolver = LintCommands::LintRunner::TargetResolver.new(['5-3'])
        result = resolver.resolve

        assert_equal [
          File.join('contents', '03-c.md'),
          File.join('contents', '04-d.md'),
          File.join('contents', '05-e.md')
        ], result
      end

      def test_target_resolver_handles_comma_separated
        setup_catalog(%w[01-a 03-c 05-e])
        FileUtils.touch('contents/01-a.md')
        FileUtils.touch('contents/03-c.md')
        FileUtils.touch('contents/05-e.md')

        resolver = LintCommands::LintRunner::TargetResolver.new(['1,3,5'])
        result = resolver.resolve

        assert_equal [
          File.join('contents', '01-a.md'),
          File.join('contents', '03-c.md'),
          File.join('contents', '05-e.md')
        ], result
      end

      def test_target_resolver_warns_missing_file
        setup_catalog(%w[01-life])
        # ファイルを作成しない → missing 警告

        logged_warnings = []
        resolver = LintCommands::LintRunner::TargetResolver.new(['1'])
        Common.stub :log_warn, ->(msg) { logged_warnings << msg } do
          capture_io { resolver.resolve }
        end

        assert logged_warnings.any? { it.include?('見つかりません') },
               "missing 警告が出力されること: #{logged_warnings.inspect}"
      end

      def test_target_resolver_excludes_system_files
        setup_catalog(%w[01-life])
        FileUtils.touch('contents/01-life.md')

        # _toc はシステムファイルなので lint 対象外
        resolver = LintCommands::LintRunner::TargetResolver.new(['01-life', '_toc'])

        logged_errors = []
        result = Common.stub(:log_error, ->(_msg) { logged_errors << _msg }) do
          resolver.resolve
        end

        assert_empty logged_errors
        assert_equal [File.join('contents', '01-life.md')], result
      end

      def test_target_resolver_rejects_invalid_token
        resolver = LintCommands::LintRunner::TargetResolver.new(['foo'])

        logged_errors = []
        Common.stub :log_error, ->(msg) { logged_errors << msg } do
          capture_io do
            error = assert_raises(SystemExit) { resolver.resolve }
            assert_equal 1, error.status
          end
        end
        assert logged_errors.any? { it.include?('不正な章指定') },
               "不正な章指定エラーが出力されること: #{logged_errors.inspect}"
      end

      # sentence_length_max 指定時に、上限を上書きした一時 textlintrc を生成する
      def test_generate_runtime_config_overrides_sentence_length_max
        Dir.mktmpdir do |dir|
          base = File.join(dir, '.textlintrc.yml')
          File.write(base, { 'rules' => { 'prh' => { 'rulePaths' => ['./textlint_prh.yml'] } } }.to_yaml)

          runner = LintCommands::LintRunner.new([], {})
          path = runner.send(:generate_runtime_config, base, sentence_max: 80)

          cfg = YAML.safe_load_file(path)
          assert_equal 80, cfg.dig('rules', 'preset-ja-technical-writing', 'sentence-length', 'max')
          assert_includes cfg.dig('rules', 'prh', 'rulePaths'), './textlint_prh.yml', '既存設定を保持'
          assert_equal dir, File.dirname(path), '元設定と同じディレクトリに生成（相対パス保持）'
        end
      end

      # スペース許容指定時に、preset-ja-spacing の該当ルールを設定レベルで無効化する
      def test_generate_runtime_config_allows_spacing
        Dir.mktmpdir do |dir|
          base = File.join(dir, '.textlintrc.yml')
          File.write(base, { 'rules' => { 'preset-ja-spacing' => { 'jaSpacing' => true } } }.to_yaml)

          runner = LintCommands::LintRunner.new([], {})
          path = runner.send(:generate_runtime_config, base, allow_code_space: true, allow_ja_en_space: true)

          spacing = YAML.safe_load_file(path).dig('rules', 'preset-ja-spacing')
          assert_equal false, spacing['ja-space-around-code']
          assert_equal false, spacing['ja-space-between-half-and-full-width']
          assert_equal true, spacing['jaSpacing'], '既存の設定は保持'
        end
      end

      private

      def setup_project_structure
        FileUtils.mkdir_p('contents')
        FileUtils.mkdir_p('config/textlint_dictionaries')

        File.write('config/.textlintrc.yml', "rules: {}\n")
        File.write('config/textlint_allowlist.yml', "allow: []\n")
        File.write('config/textlint_prh.yml', "rules: []\n")
        File.write('config/catalog.yml', "CHAPTERS:\n  - 11-install\n")

        File.write('config/textlint_dictionaries/prh.yml', "version: 1\nrules: []\n")
        File.write('config/textlint_dictionaries/icsmedia.yml', "version: 1\nrules: []\n")
        File.write('config/textlint_dictionaries/js_primer.yml', "version: 1\nrules: []\n")
      end

      # テスト用 catalog.yml を指定された章リストで生成する
      def setup_catalog(chapters)
        yaml = "CHAPTERS:\n" + chapters.map { "  - #{it}" }.join("\n") + "\n"
        File.write('config/catalog.yml', yaml)
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
    end
  end
end
