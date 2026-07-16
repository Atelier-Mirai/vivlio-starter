# frozen_string_literal: true

# ================================================================
# Test: upgrade_commands_test.rb
# ================================================================
# テスト対象:
#   UpgradeCommands（lib/vivlio_starter/cli/upgrade.rb）
#   ScaffoldLock（lib/vivlio_starter/cli/scaffold_lock.rb）
#
# 検証内容（docs/archives/project-upgrade-command-spec.md §3）:
#   - §1.2 の分類（追加/更新/競合/最新/保持）× lock あり/なし
#   - 著者データ領域（contents/・著者辞書）が計画に載らず触られない
#   - 著者辞書が無い場合は「空の辞書」を追加（雛形サンプルは配らない）
#   - 上書き前のバックアップ（スキップ分は退避されない）
#   - lock の生成・更新（適用分だけハッシュが進む・スキップ分は旧ハッシュのまま）
#   - --dry-run はファイルシステムに一切書き込まない（lock 含む）
#
# 三段オーケストレーション（docs/archives/upgrade-unification-spec.md）:
#   - 自己更新: 新版なし/dry-run/非対話/更新失敗 の各分岐（exec は relaunch! を検知）
#   - プロジェクト外では雛形追従だけをスキップし、ツール更新は実行される
#   - 終了コードは各フェーズの悪い方（max）
#
# テスト環境:
#   - Dir.mktmpdir にミニ雛形とプロジェクトを組み、scaffold_source を DI で差し替え
#   - ネットワーク・外部コマンドは tool_deps（Deps）を DI で差し替えて遮断
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'stringio'
require 'samovar'
require 'vivlio_starter/cli/samovar'

module VivlioStarter
  module CLI
    # UpgradeCommands の統合テスト
    class UpgradeCommandsTest < Minitest::Test
      FakeCmd = Data.define(:options)

      OLD_CSS = "body { color: black; }\n"
      NEW_CSS = "body { color: navy; }\n"
      CUSTOM_CSS = "body { color: hotpink; }\n"

      # --- §1.2 分類（lock あり）: 追加/更新/競合/最新/保持が正しく提示される ---
      def test_should_classify_files_with_lock_using_three_way_comparison
        within_project do |scaffold|
          # 追加: 雛形にだけある新規ファイル
          write(scaffold, 'stylesheets/new.css', NEW_CSS)
          # 更新: 雛形が改良・プロジェクトは展開時のまま
          write(scaffold, 'stylesheets/improved.css', NEW_CSS)
          write('.', 'stylesheets/improved.css', OLD_CSS)
          # 競合: 雛形も著者も変更
          write(scaffold, 'stylesheets/custom.css', NEW_CSS)
          write('.', 'stylesheets/custom.css', CUSTOM_CSS)
          # 最新: 雛形が変わっていない
          write(scaffold, 'stylesheets/same.css', OLD_CSS)
          write('.', 'stylesheets/same.css', OLD_CSS)
          # 保持: 著者データ領域（雛形側が変わっても対象外）
          write(scaffold, 'contents/10-sample.md', "# 新しいサンプル\n")
          write('.', 'contents/10-sample.md', "# 著者の原稿\n")
          write_lock(scaffold_overrides: {
                       'stylesheets/improved.css' => OLD_CSS,
                       'stylesheets/custom.css' => OLD_CSS,
                       'contents/10-sample.md' => "# 旧サンプル\n"
                     })

          out, = capture_io { run_upgrade(scaffold, dry_run: true) }

          assert_match(/追加\s+stylesheets\/new\.css/, out)
          assert_match(/更新\s+stylesheets\/improved\.css/, out)
          assert_match(/競合\s+stylesheets\/custom\.css/, out)
          assert_match(/保持\s+contents\/10-sample\.md/, out)
          refute_match(/stylesheets\/same\.css/, out, '最新のファイルは計画に載らないべき')
        end
      end

      # --- §1.2 分類（lock なし）: 一致は最新扱い・不一致はすべて競合 ---
      def test_should_treat_all_diffs_as_conflicts_when_lock_is_missing
        within_project do |scaffold|
          write(scaffold, 'stylesheets/changed.css', NEW_CSS)
          write('.', 'stylesheets/changed.css', OLD_CSS)
          write(scaffold, 'stylesheets/same.css', OLD_CSS)
          write('.', 'stylesheets/same.css', OLD_CSS)
          write(scaffold, 'stylesheets/new.css', NEW_CSS)

          out, = capture_io { run_upgrade(scaffold, dry_run: true) }

          assert_match(/scaffold\.lock が見つかりません/, out)
          assert_match(/競合\s+stylesheets\/changed\.css/, out)
          assert_match(/追加\s+stylesheets\/new\.css/, out)
          refute_match(/stylesheets\/same\.css/, out)
        end
      end

      # --- 適用: 追加＋更新はバックアップの上で適用され、lock のハッシュが進む ---
      def test_should_apply_add_and_update_with_backup_and_lock_progress
        within_project do |scaffold|
          write(scaffold, 'stylesheets/new.css', NEW_CSS)
          write(scaffold, 'stylesheets/improved.css', NEW_CSS)
          write('.', 'stylesheets/improved.css', OLD_CSS)
          write_lock(scaffold_overrides: { 'stylesheets/improved.css' => OLD_CSS })

          capture_io { run_upgrade(scaffold, yes: true) }

          assert_equal NEW_CSS, File.read('stylesheets/new.css'), '追加ファイルがコピーされるべき'
          assert_equal NEW_CSS, File.read('stylesheets/improved.css'), '未カスタムの更新は自動適用されるべき'

          backups = Dir.glob('.cache/vs/upgrade-backup/*/stylesheets/improved.css')
          assert_equal 1, backups.size, '上書き前の現物が退避されるべき'
          assert_equal OLD_CSS, File.read(backups.first)

          lock = ScaffoldLock.read('.')
          assert_equal digest(NEW_CSS), lock[:files]['stylesheets/improved.css'], '適用分の lock ハッシュが進むべき'
        end
      end

      # --- 競合: n でスキップ → 現物は無傷・退避されず・lock は旧ハッシュのまま ---
      def test_should_skip_conflict_and_keep_old_lock_hash_when_user_declines
        within_project do |scaffold|
          write(scaffold, 'stylesheets/custom.css', NEW_CSS)
          write('.', 'stylesheets/custom.css', CUSTOM_CSS)
          write_lock(scaffold_overrides: { 'stylesheets/custom.css' => OLD_CSS })

          with_stdin("n\n") { capture_io { run_upgrade(scaffold) } }

          assert_equal CUSTOM_CSS, File.read('stylesheets/custom.css'), 'スキップした競合は無傷であるべき'
          assert_empty Dir.glob('.cache/vs/upgrade-backup/**/*.css'), 'スキップ分は退避されないべき'
          lock = ScaffoldLock.read('.')
          assert_equal digest(OLD_CSS), lock[:files]['stylesheets/custom.css'], 'スキップ分の lock は旧ハッシュのままであるべき（次回また競合になる）'
        end
      end

      # --- 競合: y で適用 → バックアップの上で雛形版に置き換わる ---
      def test_should_apply_conflict_with_backup_when_user_confirms
        within_project do |scaffold|
          write(scaffold, 'stylesheets/custom.css', NEW_CSS)
          write('.', 'stylesheets/custom.css', CUSTOM_CSS)
          write_lock(scaffold_overrides: { 'stylesheets/custom.css' => OLD_CSS })

          out, = with_stdin("y\n") { capture_io { run_upgrade(scaffold) } }

          assert_match(/競合 stylesheets\/custom\.css/, out)
          assert_match(/-body \{ color: hotpink; \}/, out, '現物側の行が - で表示されるべき')
          assert_match(/\+body \{ color: navy; \}/, out, '雛形側の行が + で表示されるべき')
          assert_equal NEW_CSS, File.read('stylesheets/custom.css')

          backups = Dir.glob('.cache/vs/upgrade-backup/*/stylesheets/custom.css')
          assert_equal CUSTOM_CSS, File.read(backups.first), '上書き前の著者版が退避されるべき'
        end
      end

      # --- 著者データ領域: 雛形と差分があっても計画に載らず、絶対に触られない ---
      def test_should_never_touch_author_data_areas
        within_project do |scaffold|
          write(scaffold, 'contents/10-sample.md', "# 新サンプル\n")
          write('.', 'contents/10-sample.md', "# 著者の原稿\n")
          write(scaffold, 'config/index_glossary_terms.yml', "terms:\n- term: sample\n")
          write('.', 'config/index_glossary_terms.yml', "terms:\n- term: 著者の用語\n")
          write_lock

          capture_io { run_upgrade(scaffold, yes: true) }

          assert_equal "# 著者の原稿\n", File.read('contents/10-sample.md')
          assert_includes File.read('config/index_glossary_terms.yml'), '著者の用語', '著者辞書は上書きされてはならない'
          assert_empty Dir.glob('.cache/vs/upgrade-backup/**/*'), '著者データは退避（＝上書き）対象にならないべき'
        end
      end

      # --- 著者辞書が無い場合: 雛形サンプルではなく「空の辞書」を追加する ---
      def test_should_add_empty_dictionary_when_author_dictionary_is_missing
        within_project do |scaffold|
          write(scaffold, 'config/index_glossary_terms.yml', "terms:\n- term: 開発リポジトリの用語\n")
          write(scaffold, 'config/user_words.txt', "vivliostyle\nkindle\n")
          write_lock

          out, = capture_io { run_upgrade(scaffold, yes: true) }

          assert_match(/追加\s+config\/index_glossary_terms\.yml.*空の辞書/, out)
          terms = YAML.safe_load_file('config/index_glossary_terms.yml')
          assert_equal [], terms['terms'], '空の辞書が用意されるべき（雛形サンプルは配らない）'
          refute_includes File.read('config/user_words.txt'), 'vivliostyle', 'user_words も空で用意されるべき'
        end
      end

      # --- --dry-run: lock 含めファイルシステムに一切書き込まない ---
      def test_should_write_nothing_on_dry_run
        within_project do |scaffold|
          write(scaffold, 'stylesheets/new.css', NEW_CSS)
          write(scaffold, 'stylesheets/improved.css', NEW_CSS)
          write('.', 'stylesheets/improved.css', OLD_CSS)

          before = Dir.glob('**/*', File::FNM_DOTMATCH).sort
          capture_io { run_upgrade(scaffold, dry_run: true) }

          assert_equal before, Dir.glob('**/*', File::FNM_DOTMATCH).sort, 'dry-run で新規ファイルが増えてはならない'
          refute File.exist?('config/scaffold.lock'), 'dry-run で lock を書いてはならない'
          assert_equal OLD_CSS, File.read('stylesheets/improved.css')
        end
      end

      # --- lock なしで全ファイル一致: lock を記録して「最新」扱いになる ---
      def test_should_record_lock_for_legacy_project_when_everything_matches
        within_project do |scaffold|
          write(scaffold, 'stylesheets/same.css', OLD_CSS)
          write('.', 'stylesheets/same.css', OLD_CSS)

          out, = capture_io { run_upgrade(scaffold) }

          assert_match(/最新/, out)
          lock = ScaffoldLock.read('.')
          refute_nil lock, '旧プロジェクトでも一致確認後に lock が記録されるべき'
          assert_equal digest(OLD_CSS), lock[:files]['stylesheets/same.css']
        end
      end

      # ==============================================================
      # 三段オーケストレーション（本体更新 → 雛形追従 → ツール更新）
      # ==============================================================

      GEM_LATEST_URL = format(DoctorCommands::ToolUpgrader::RUBYGEMS_LATEST_URL, 'vivlio-starter')

      # --- プロジェクト外: 雛形追従だけスキップされ、ツール更新は実行される ---
      def test_should_skip_scaffold_sync_outside_project_but_still_run_tool_upgrade
        Dir.mktmpdir do |dir|
          Dir.chdir(dir) do
            UpgradeCommands.tool_deps = stub_tool_deps
            tools_called = false
            out, = capture_io do
              DoctorCommands::ToolUpgrader.stub(:run!, lambda { |*|
                tools_called = true
                0
              }) do
                UpgradeCommands.run_from_command(FakeCmd.new(options: { dry_run: false, yes: true }))
              end
            end

            assert_match(/プロジェクト外のため、雛形の追従はスキップ/, out)
            assert tools_called, 'プロジェクト外でもツール更新フェーズは実行されるべき'
            refute File.exist?('config/scaffold.lock'), 'プロジェクト外で lock を書いてはならない'
          end
        ensure
          UpgradeCommands.tool_deps = nil
        end
      end

      # --- 終了コード: ツール更新フェーズの失敗（1）が全体の終了コードに反映される ---
      def test_should_propagate_tool_phase_failure_to_exit_code
        within_project do |scaffold|
          UpgradeCommands.scaffold_source = scaffold
          code = nil
          capture_io do
            DoctorCommands::ToolUpgrader.stub(:run!, 1) do
              code = UpgradeCommands.run_from_command(
                FakeCmd.new(options: { dry_run: false, yes: true, skip_self_update: true })
              )
            end
          end

          assert_equal 1, code
        ensure
          UpgradeCommands.scaffold_source = nil
        end
      end

      # --- 自己更新: 最新なら何もしない ---
      def test_self_update_should_do_nothing_when_gem_is_latest
        deps = stub_tool_deps(fetch: { GEM_LATEST_URL => '{"version":"1.0.0"}' })

        result = UpgradeCommands.self_update!({ yes: true }, deps, current: '1.0.0')

        assert_equal :none, result
      end

      # --- 自己更新: --dry-run は新版の案内のみ ---
      def test_self_update_should_announce_only_on_dry_run
        executed = []
        deps = stub_tool_deps(fetch: { GEM_LATEST_URL => '{"version":"2.0.0"}' }, executed:)

        result = nil
        out, = capture_io { result = UpgradeCommands.self_update!({ dry_run: true }, deps, current: '1.0.0') }

        assert_equal :skipped, result
        assert_match(/2\.0\.0 が公開されています/, out)
        assert_empty executed, 'dry-run では gem update を実行しない'
      end

      # --- 自己更新: 非対話（tty でない）かつ --yes なしでは案内してスキップ ---
      def test_self_update_should_skip_with_guidance_when_non_interactive
        deps = stub_tool_deps(fetch: { GEM_LATEST_URL => '{"version":"2.0.0"}' })

        result = nil
        out, = capture_io { result = UpgradeCommands.self_update!({ yes: false }, deps, current: '1.0.0') }

        assert_equal :skipped, result
        assert_match(/gem update vivlio-starter/, out, '手動更新コマンドを必ず案内する')
      end

      # --- 自己更新: gem update 失敗は警告して続行（:failed） ---
      def test_self_update_should_continue_as_failed_when_gem_update_fails
        executed = []
        deps = stub_tool_deps(fetch: { GEM_LATEST_URL => '{"version":"2.0.0"}' },
                              run_ok: { 'gem update vivlio-starter' => false }, executed:)

        result = nil
        capture_io { result = UpgradeCommands.self_update!({ yes: true }, deps, current: '1.0.0') }

        assert_equal :failed, result
        assert_includes executed, 'gem update vivlio-starter'
      end

      # --- 自己更新: 成功したら新しい版の vs upgrade --skip-self-update へ引き継ぐ ---
      def test_self_update_should_relaunch_with_skip_flag_after_successful_update
        executed = []
        deps = stub_tool_deps(fetch: { GEM_LATEST_URL => '{"version":"2.0.0"}' }, executed:)
        relaunched_with = nil

        capture_io do
          UpgradeCommands.stub(:relaunch!, ->(options) { relaunched_with = options }) do
            UpgradeCommands.self_update!({ yes: true }, deps, current: '1.0.0')
          end
        end

        assert_includes executed, 'gem update vivlio-starter'
        refute_nil relaunched_with, '更新成功後は新しい版で再実行されるべき'
      end

      private

      # ミニ雛形＋プロジェクトディレクトリを用意し、プロジェクト直下で yield する
      def within_project
        Dir.mktmpdir do |dir|
          scaffold = File.join(dir, 'scaffold')
          project  = File.join(dir, 'project')
          # プロジェクトの目印（著者データ領域なので upgrade は触らない）
          write(scaffold, 'config/book.yml', "book:\n  main_title: \"{{MAIN_TITLE}}\"\n")
          write(project, 'config/book.yml', "book:\n  main_title: \"わたしの本\"\n")
          Dir.chdir(project) { yield scaffold }
        end
      end

      # 雛形追従フェーズだけを検証する（自己更新はフラグで、ツール更新はスタブで遮断）
      def run_upgrade(scaffold, dry_run: false, yes: false)
        UpgradeCommands.scaffold_source = scaffold
        DoctorCommands::ToolUpgrader.stub(:run!, 0) do
          UpgradeCommands.run_from_command(FakeCmd.new(options: { dry_run:, yes:, skip_self_update: true }))
        end
      ensure
        UpgradeCommands.scaffold_source = nil
      end

      def write(root, relative, content)
        path = File.join(root, relative)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, content, encoding: 'utf-8')
      end

      def digest(content) = "sha256:#{Digest::SHA256.hexdigest(content)}"

      # 展開時点の lock を組み立てる。既定では「現在の現物＝展開時の雛形」とみなし、
      # scaffold_overrides で「展開時の雛形はこの内容だった」を上書き指定できる。
      def write_lock(scaffold_overrides: {})
        files = Dir.glob('**/*', base: '.').select { File.file?(it) }.to_h { [it, digest(File.read(it))] }
        scaffold_overrides.each { |relative, content| files[relative] = digest(content) }
        ScaffoldLock.write('.', version: '0.9.0', files:)
      end

      def with_stdin(input)
        $stdin = StringIO.new(input)
        yield
      ensure
        $stdin = STDIN
      end

      # ツール更新・自己更新用の Deps スタブ（ネットワーク・外部コマンドを遮断）。
      # 素の StringIO は tty? が false のため、既定で非対話環境として振る舞う。
      def stub_tool_deps(fetch: {}, run_ok: {}, executed: [])
        DoctorCommands::ToolUpgrader::Deps.new(
          run: lambda { |cmd|
            executed << cmd
            run_ok.fetch(cmd, true)
          },
          capture: ->(_cmd) { ['', false] },
          fetch: ->(url) { fetch[url] },
          stdin: StringIO.new
        )
      end
    end
  end
end
