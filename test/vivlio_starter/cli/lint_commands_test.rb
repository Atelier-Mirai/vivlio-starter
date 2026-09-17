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

      # 独自ルール（交ぜ書き・対比）は「日本語校正」の一部なので、textlint を切ると
      # 一緒に止まり、スペルチェックだけを求めたときには出てこない。
      # 仕様: lint-japanese-prose-rules-spec.md §5
      def test_prose_rules_follow_the_japanese_lint_scope
        File.write('contents/11-install.md', "だ円の面積を求めます。\n")

        stdout, = capture_io { LintCommands.execute_lint(['11-install'], { spellcheck_only: true }) }
        refute_match(/mazegaki/, stdout, '--spellcheck-only では日本語校正を走らせない')

        fake_status = Struct.new(:success?).new(true)
        def fake_status.exitstatus = 0

        with_stubbed_textlint_available do
          Open3.stub(:capture3, ->(*_args) { ['[]', '', fake_status] }) do
            stdout, = capture_io { LintCommands.execute_lint(['11-install'], { textlint_only: true }) }
            assert_match(/\[mazegaki\] だ円 => 楕円/, stdout, '--textlint-only では走る')
          end
        end
      end

      # 交ぜ書きは 1 対 1 の置換なので --fix で直す。対比は文脈依存なので直さない。
      def test_fix_option_rewrites_mazegaki_in_place
        path = 'contents/11-install.md'
        File.write(path, "だ円について、Ractor はスレッドと同様に共有しない。\n")

        fake_status = Struct.new(:success?).new(true)
        def fake_status.exitstatus = 0

        with_stubbed_textlint_available do
          Open3.stub(:capture3, ->(*_args) { ['[]', '', fake_status] }) do
            capture_io { LintCommands.execute_lint(['11-install'], { fix: true }) }
          end
        end

        assert_equal "楕円について、Ractor はスレッドと同様に共有しない。\n", File.read(path)
      end

      # 検査の実装が textlint と独自ルールに分かれているのは都合であって、著者から見れば
      # 同じ「日本語校正」。1 ファイル 1 ブロックにまとめ、件数順に混ぜて並べる
      # （分けて出すと同じ原稿の見出しが 2 度現れ、どちらを先に直すのか読み取れない）
      def test_prose_findings_share_one_block_with_textlint
        path = 'contents/11-install.md'
        File.write(path, "だ円を描きます。\nだ円を測ります。\n全て正しい。\n")

        json = JSON.generate([{ 'filePath' => File.expand_path(path),
                                'messages' => [{ 'ruleId' => 'prh', 'message' => '全て => すべて', 'line' => 3 }] }])
        fake_status = Struct.new(:success?).new(false)
        def fake_status.exitstatus = 1

        stdout = nil
        with_stubbed_textlint_available do
          Open3.stub(:capture3, ->(*_args) { [json, '', fake_status] }) do
            stdout, = capture_io { LintCommands.execute_lint(['11-install'], { textlint_only: true }) }
          end
        end

        assert_equal 1, stdout.scan("📄 #{path}").size, '同じ原稿の見出しは 1 度だけ'
        assert_match(/📄 .*\(日本語校正\)/, stdout, 'ラベルは完了サマリーの内訳と同じ語')
        assert_operator stdout.index('[mazegaki]'), :<, stdout.index('[prh]'),
                        '2 件の独自校正が 1 件の textlint より先に出る（混ぜて件数順に並ぶ）'
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
      # no-op になる。lint-notation-guard-spec.md §2.3）。
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
      # `<!-- vs-lint-disable-next-line -->` は textlint 側で効かない
      # （textlint-filter-rule-comments v1.3.0 に -next-line の実装が無い）。
      # 原稿は「一行だけ除外」を案内しているので、出力段で行ごと落として辻褄を合わせる
      def test_next_line_suppression_targets_only_the_following_line
        text = <<~MD
          # 見出し

          <!-- vs-lint-disable-next-line -->
          この行は抑止される。
          この行は抑止されない。

          <!-- vs-lint-disable-next-line -->
          ここも抑止される。
        MD

        runner = LintCommands::LintRunner.new([], {})

        assert_equal Set[4, 8], runner.send(:next_line_suppressions, text)
      end

      # フェンスの中のコメントは記法の例示であって指示ではない
      # （Tokenizer / ProseChecker と同じ扱い）
      def test_next_line_suppression_ignores_comments_inside_code_fences
        text = <<~MD
          ````markdown
          <!-- vs-lint-disable-next-line -->
          ````

          この行は抑止されない。
        MD

        runner = LintCommands::LintRunner.new([], {})

        assert_empty runner.send(:next_line_suppressions, text)
      end

      # 囲む形（disable / enable）は textlint 側が処理するので、こちらは拾わない
      def test_next_line_suppression_ignores_the_range_form
        text = "<!-- vs-lint-disable -->\n囲まれた行。\n<!-- vs-lint-enable -->\n"

        runner = LintCommands::LintRunner.new([], {})

        assert_empty runner.send(:next_line_suppressions, text)
      end

      # 原稿ごとに、textlint が見る一時ファイルのパスへ紐づける
      def test_suppressed_lines_map_keys_on_the_temp_file
        Dir.mktmpdir do |dir|
          original = File.join(dir, '11-install.md')
          tmp      = File.join(dir, 'textlint_tmp.md')
          File.write(original, "<!-- vs-lint-disable-next-line -->\n抑止される行。\n")
          FileUtils.touch(tmp)

          runner = LintCommands::LintRunner.new([], {})
          map = runner.send(:suppressed_lines_map, [original], [tmp])

          assert_equal Set[2], map[File.expand_path(tmp)]
        end
      end

      # 独自ルールで置き換えた textlint のルールは、著者の設定に依らず常に切る。
      # 上限（lint.sentence_length_max）は ProseChecker が book.yml から直接受け取るので、
      # 実行時 textlintrc へ書き戻すものは無い
      def test_generate_runtime_config_disables_superseded_rules
        Dir.mktmpdir do |dir|
          base = File.join(dir, '.textlintrc.yml')
          preset = { 'sentence-length' => { 'max' => 80 } }
          File.write(base, { 'rules' => { 'preset-ja-technical-writing' => preset,
                                          'prh' => { 'rulePaths' => ['./textlint_rewrite.yml'] } } }.to_yaml)

          runner = LintCommands::LintRunner.new([], {})
          path = runner.send(:generate_runtime_config, base)

          cfg = YAML.safe_load_file(path)
          assert_equal false, cfg.dig('rules', 'preset-ja-technical-writing', 'sentence-length'),
                       '著者が上限を書いていても切る（独自ルールと二重に指摘しない）'
          assert_equal false, cfg.dig('rules', 'preset-ja-technical-writing', 'ja-no-mixed-period')
          assert_includes cfg.dig('rules', 'prh', 'rulePaths'), './textlint_rewrite.yml', '既存設定を保持'
          assert_equal dir, File.dirname(path), '元設定と同じディレクトリに生成（相対パス保持）'
        end
      end

      # 1.0 より前の雛形は preset-japanese を併用していた。更新していないプロジェクトでも
      # 二重に指摘されないよう、同じルールを持つ両方のプリセットへ当てる
      def test_generate_runtime_config_disables_superseded_rules_in_legacy_preset
        Dir.mktmpdir do |dir|
          base = File.join(dir, '.textlintrc.yml')
          File.write(base, { 'rules' => { 'preset-ja-technical-writing' => {}, 'preset-japanese' => true } }.to_yaml)

          runner = LintCommands::LintRunner.new([], {})
          cfg = YAML.safe_load_file(runner.send(:generate_runtime_config, base))

          assert_equal false, cfg.dig('rules', 'preset-ja-technical-writing', 'sentence-length')
          assert_equal false, cfg.dig('rules', 'preset-japanese', 'sentence-length')
          assert_equal false, cfg.dig('rules', 'preset-japanese', 'no-kanji-lookalikes'),
                       '独自ルール kanji-lookalike と二重に指摘しない'
        end
      end

      # 設定に無いプリセットは足さない。足すと、著者が外したプリセットが丸ごと読み込まれる
      def test_generate_runtime_config_does_not_add_unconfigured_presets
        Dir.mktmpdir do |dir|
          base = File.join(dir, '.textlintrc.yml')
          File.write(base, { 'rules' => { 'preset-ja-technical-writing' => {} } }.to_yaml)

          runner = LintCommands::LintRunner.new([], {})
          cfg = YAML.safe_load_file(runner.send(:generate_runtime_config, base))

          refute cfg['rules'].key?('preset-japanese')
          refute cfg['rules'].key?('preset-ja-spacing')
          assert_equal false, cfg.dig('rules', 'preset-ja-technical-writing', 'sentence-length')
        end
      end

      # 雛形の .textlintrc.yml は preset-japanese を読まない（11 ルールが重複していたため）。
      # 文体の混在検出は preset-ja-technical-writing 側を自動判定にして引き継ぐ
      def test_scaffold_textlintrc_loads_each_rule_once
        cfg = YAML.safe_load_file(File.expand_path('../../../config/.textlintrc.yml', __dir__))
        rules = cfg['rules']

        refute rules.key?('preset-japanese')
        mix = rules.dig('preset-ja-technical-writing', 'no-mix-dearu-desumasu')
        assert_equal %w[preferInBody preferInHeader preferInList].to_h { [it, ''] },
                     mix.slice('preferInBody', 'preferInHeader', 'preferInList')
      end

      # book.yml の値から :off / 数値 / nil への解釈
      def test_sentence_length_max_interprets_zero_as_off
        runner = LintCommands::LintRunner.new([], {})
        original = Common::CONFIG

        # nil は「書かなかった」と同じなので既定値（ConfigKeys の 100）が入る。
        # '' は明示的な空文字なので既定値に戻らず、blank? として nil に落ちる。
        default = ConfigKeys::KEYS[%i[lint sentence_length_max]].default
        { 0 => :off, '0' => :off, 80 => 80, '80' => 80, nil => default, '' => nil }.each do |raw, expected|
          merged = Common.merge_hardcoded_defaults(lint: { sentence_length_max: raw })
          Common.install_configuration!(Common.wrap_config(merged).freeze)

          assert_equal expected, runner.send(:sentence_length_max), "入力 #{raw.inspect}"
        end
      ensure
        Common.install_configuration!(original)
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
        File.write('config/textlint_rewrite.yml', "rules: []\n")
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
