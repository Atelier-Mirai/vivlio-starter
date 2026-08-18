# frozen_string_literal: true

# ================================================================
# Test: upgrade_commands_test.rb
# ================================================================
# テスト対象:
#   UpgradeCommands（lib/vivlio_starter/cli/upgrade.rb）
#   ScaffoldLock（lib/vivlio_starter/cli/scaffold_lock.rb）
#
# 検証内容（project-upgrade-command-spec.md §3）:
#   - §1.2 の分類（追加/更新/競合/最新/保持）× lock あり/なし
#   - 著者データ領域（contents/・著者辞書）が計画に載らず触られない
#   - 著者辞書が無い場合は「空の辞書」を追加（雛形サンプルは配らない）
#   - 上書き前のバックアップ（スキップ分は退避されない）
#   - lock の生成・更新（適用分だけハッシュが進む・スキップ分は旧ハッシュのまま）
#   - --dry-run はファイルシステムに一切書き込まない（lock 含む）
#
# 3-way マージ（upgrade-three-way-merge-spec.md §8）:
#   - 別の場所を変えた競合は質問されず合流する／同じ場所なら従来どおり尋ねる
#   - 祖先の調達 2 経路（旧版 gem・保存基準）とその不在・git 不在のフォールバック
#   - 保存基準は lock と歩調を合わせる（スキップした競合の祖先を進めない）
#
# 三段オーケストレーション（upgrade-unification-spec.md）:
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
require 'open3'
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

      # --- 競合: diff にどちらが自分のファイルか示す凡例が出る ---

      # `-` / `+` だけでは「gem 側が ○○ でプロジェクト側が ××」が読み取れない。
      # 記号の意味と「適用するとどうなるか」を毎回添える（2026-08-12 の実測より）
      def test_should_show_which_side_is_mine_in_conflict_diff
        within_project do |scaffold|
          write(scaffold, 'stylesheets/custom.css', NEW_CSS)
          write('.', 'stylesheets/custom.css', CUSTOM_CSS)
          write_lock(scaffold_overrides: { 'stylesheets/custom.css' => OLD_CSS })

          out, = with_stdin("n\n") { capture_io { run_upgrade(scaffold) } }

          assert_includes out, 'いまのあなたのファイル'
          assert_includes out, '新しい雛形'
          assert_includes out, '適用すると + の側になります'
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
          write(scaffold, 'config/spellcheck_allowlist.yml', %(- "vivliostyle"\n- "kindle"\n))
          write_lock

          out, = capture_io { run_upgrade(scaffold, yes: true) }

          assert_match(/追加\s+config\/index_glossary_terms\.yml.*空の辞書/, out)
          terms = YAML.safe_load_file('config/index_glossary_terms.yml')
          assert_equal [], terms['terms'], '空の辞書が用意されるべき（雛形サンプルは配らない）'
          refute_includes File.read('config/spellcheck_allowlist.yml'), 'vivliostyle',
                          'スペルチェックの除外リストも空で用意されるべき'
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

      # ================================================================
      # 競合レビューの見せ方（upgrade-conflict-review-spec.md）
      # ================================================================

      # --- §3(a) 双方が同じ内容に到達したものは競合ではない ---

      # lock だけが取り残された状態。diff は空になるので y/n のどちらを選んでも
      # 結果が変わらない——問いを立てること自体が誤りである
      def test_should_not_ask_when_current_and_scaffold_already_agree
        within_project do |scaffold|
          write(scaffold, 'stylesheets/custom.css', NEW_CSS)
          write('.', 'stylesheets/custom.css', NEW_CSS)
          write_lock(scaffold_overrides: { 'stylesheets/custom.css' => OLD_CSS })

          out, = capture_io { run_upgrade(scaffold, dry_run: true) }

          refute_match(/競合/, out, '中身が同じものを競合として尋ねるべきではない')
          refute_match(%r{stylesheets/custom\.css}, out)
        end
      end

      # --- §3(b) ハンク分割 ---

      # 事故の真因。分割しないと最初の変更から最後の変更までが 1 塊になり、
      # 間の無変更行が肝心の変更をプレビュー外へ押し出す（2026-08-12 の実測）
      def test_should_split_distant_changes_into_separate_hunks
        mine, theirs = two_sided_change(mine_at: 4, theirs_at: 34)

        lines = diff_lines(mine, theirs)

        assert_equal 2, lines.grep(/@@/).size, '離れた 2 箇所は別々のハンクになるべき'
        refute_includes lines, '    line 20', 'ハンクの間の無変更行は出ないべき'
        assert_includes lines, '   -わたしの 5 行目', '著者の変更が消える側として見えるべき'
        assert_includes lines, '   +雛形の 35 行目'
      end

      # 文脈で埋まる程度の隙間なら 1 つに残す（標準の unified diff と同じ規則）
      def test_should_merge_nearby_changes_into_one_hunk
        mine, theirs = two_sided_change(mine_at: 9, theirs_at: 13)

        lines = diff_lines(mine, theirs)

        assert_equal 1, lines.grep(/@@/).size, '間が CONTEXT_LINES × 2 以下なら 1 ハンクにまとまるべき'
      end

      # ハンク見出しの行番号は著者の現物基準。追加行では行数を進めない
      def test_should_number_hunks_by_the_authors_current_file
        mine, theirs = two_sided_change(mine_at: 4, theirs_at: 34)

        lines = diff_lines(mine, theirs)

        assert_includes lines, '   @@ 3 行目付近 @@'
        assert_includes lines, '   @@ 33 行目付近 @@'
      end

      # --- §3(c) 要約と切り詰め警告 ---

      def test_should_summarize_hunk_count_and_line_delta_before_the_prompt
        mine, theirs = two_sided_change(mine_at: 4, theirs_at: 34)

        lines = diff_lines(mine, theirs)

        assert_equal '   変更 2 箇所（+2 / -2 行）', lines.first, '要約は diff の先頭（prompt より前）に出るべき'
      end

      # 「残り N 行」だけでは「読まなくてよい続き」と読めてしまう。
      # 実際に、見ていない変更が y で承認された
      def test_should_warn_that_y_applies_to_hidden_hunks_when_truncated
        mine   = (1..200).map { "line #{it}" }
        theirs = mine.dup
        (0...10).each { theirs[it * 20] = "雛形の変更 #{it}" }
        diff = diff_lines("#{mine.join("\n")}\n", "#{theirs.join("\n")}\n")

        out, = capture_io { UpgradeCommands.send(:print_diff, diff, limit: UpgradeCommands::DIFF_PREVIEW_LINES) }

        assert_match(/未表示 \d+ 箇所/, out, '見えていないハンクが何箇所あるか示すべき')
        assert_match(/\[y\] は表示していない箇所にも適用されます/, out)
      end

      # 切れてはいるが、隠れているのが文脈行だけの場合。警告を出すと狼少年になり、
      # 本当に変更が隠れている場面での警告まで軽く扱われる（実測で踏んだ: 21 行の
      # diff がプレビュー上限 20 行を 1 行だけ超え、その 1 行が文脈行だった）
      def test_should_not_warn_when_only_context_lines_are_hidden
        mine, theirs = two_sided_change(mine_at: 4, theirs_at: 34)
        diff = diff_lines(mine, theirs)

        out, = capture_io { UpgradeCommands.send(:print_diff, diff, limit: diff.size - 1) }

        assert_match(/残り 1 行/, out, '切り詰めたこと自体は伝えるべき')
        refute_match(/表示していない箇所/, out, '隠れているのが文脈行だけなら警告すべきではない')
      end

      def test_should_not_warn_about_hidden_changes_when_the_diff_fits
        mine, theirs = two_sided_change(mine_at: 4, theirs_at: 34)
        diff = diff_lines(mine, theirs)

        out, = capture_io { UpgradeCommands.send(:print_diff, diff, limit: UpgradeCommands::DIFF_PREVIEW_LINES) }

        refute_match(/表示していない箇所/, out, '全部見えているときに警告を出すべきではない')
      end

      # --- §3(d) 色付け ---

      # 色は「diff の生成」ではなく「出力」の関心事。生成側が素のままだから、
      # diff の中身を検査する上のテスト群が色の有無に影響されない
      def test_should_keep_generated_diff_plain_and_colorize_only_on_output
        mine, theirs = two_sided_change(mine_at: 4, theirs_at: 34)

        diff = diff_lines(mine, theirs)

        assert_empty diff.grep(/\e\[/), 'unified_diff の戻り値は色を持たないべき'
        assert_equal "\e[31m   -x\e[0m", UpgradeCommands.send(:paint_diff_line, '   -x', enabled: true)
        assert_equal "\e[32m   +x\e[0m", UpgradeCommands.send(:paint_diff_line, '   +x', enabled: true)
        assert_equal '   -x', UpgradeCommands.send(:paint_diff_line, '   -x', enabled: false)
      end

      # 記号の判定に lstrip を使うと、CSS のカスタムプロパティを含む文脈行が
      # 削除行に化けて赤く塗られる。位置（添字 3）で判定していることの回帰テスト
      def test_should_not_mistake_a_custom_property_context_line_for_a_deletion
        context = '    --preface-h3-marker: "📚 ";'

        assert_equal context, UpgradeCommands.send(:paint_diff_line, context, enabled: true)
      end

      def test_should_respect_no_color_and_dumb_terminal_even_on_a_tty
        tty = FakeIO.new(tty: true)

        assert UpgradeCommands.send(:diff_color_enabled?, tty, {})
        refute UpgradeCommands.send(:diff_color_enabled?, tty, { 'NO_COLOR' => '1' }), 'NO_COLOR があれば色を付けないべき'
        refute UpgradeCommands.send(:diff_color_enabled?, tty, { 'TERM' => 'dumb' }), 'TERM=dumb では色を付けないべき'
        refute UpgradeCommands.send(:diff_color_enabled?, FakeIO.new(tty: false), {}), 'パイプ・リダイレクト先には付けないべき'
      end

      # ================================================================
      # 3-way マージ（upgrade-three-way-merge-spec.md）
      # ================================================================

      # --- §8-1 自動合流: 別の場所を変えた競合は尋ねずに両立する ---
      def test_should_merge_changes_on_different_places_without_asking
        within_project do |scaffold|
          base, mine, theirs = three_way_sources
          write(scaffold, 'stylesheets/custom.css', theirs)
          write('.', 'stylesheets/custom.css', mine)
          write_base('stylesheets/custom.css', base)
          write_lock(scaffold_overrides: { 'stylesheets/custom.css' => base })

          out, = capture_io { run_upgrade(scaffold, yes: true) }

          merged = File.read('stylesheets/custom.css')
          assert_includes merged, 'わたしの 1 行目', '著者の変更が残るべき'
          assert_includes merged, '雛形の 12 行目', '雛形の変更が取り込まれるべき'
          assert_match(/合流\s+stylesheets\/custom\.css/, out)
          refute_match(/競合\s+stylesheets\/custom\.css/, out, '合流できたものは競合として出さない')
        end
      end

      # --- §8-2 真の競合: 同じ場所を変えていれば従来どおり尋ねる ---
      def test_should_still_ask_when_both_changed_the_same_place
        within_project do |scaffold|
          base = "line 1\nline 2\nline 3\n"
          write(scaffold, 'stylesheets/custom.css', "line 1\n雛形の 2 行目\nline 3\n")
          write('.', 'stylesheets/custom.css', "line 1\nわたしの 2 行目\nline 3\n")
          write_base('stylesheets/custom.css', base)
          write_lock(scaffold_overrides: { 'stylesheets/custom.css' => base })

          out, = with_stdin("n\n") { capture_io { run_upgrade(scaffold) } }

          assert_match(/競合\s+stylesheets\/custom\.css/, out)
          assert_includes out, '同じ場所を変えています', '合流できない理由を名指しするべき'
          assert_equal "line 1\nわたしの 2 行目\nline 3\n", File.read('stylesheets/custom.css')
        end
      end

      # --- §8-3 祖先の調達 A: インストール済みの旧版 gem の雛形が使われる ---
      def test_should_use_old_gem_scaffold_as_ancestor
        within_project do |scaffold|
          base, mine, theirs = three_way_sources
          write(scaffold, 'stylesheets/custom.css', theirs)
          write('.', 'stylesheets/custom.css', mine)
          write_lock(scaffold_overrides: { 'stylesheets/custom.css' => base })
          gem_home = write_gem_base(File.join(Dir.tmpdir, "vs-gem-#{Process.pid}"), 'stylesheets/custom.css', base)

          begin
            capture_io { run_upgrade(scaffold, yes: true, gem_paths: [gem_home]) }
          ensure
            FileUtils.rm_rf(gem_home)
          end

          merged = File.read('stylesheets/custom.css')
          assert_includes merged, 'わたしの 1 行目'
          assert_includes merged, '雛形の 12 行目'
        end
      end

      # --- §8-4 祖先の調達 B: 保存基準だけでも合流できる（旧 gem が消えていても） ---
      def test_should_use_saved_base_as_ancestor_when_no_old_gem_exists
        within_project do |scaffold|
          base, mine, theirs = three_way_sources
          write(scaffold, 'stylesheets/custom.css', theirs)
          write('.', 'stylesheets/custom.css', mine)
          write_base('stylesheets/custom.css', base)
          write_lock(scaffold_overrides: { 'stylesheets/custom.css' => base })

          capture_io { run_upgrade(scaffold, yes: true, gem_paths: []) }

          assert_includes File.read('stylesheets/custom.css'), '雛形の 12 行目'
        end
      end

      # --- 祖先の照合: 中身が lock と食い違う候補は祖先として採らない ---

      # 版の取り違えや古い保存基準を、経路ごとの場合分けではなく内容そのもので弾く。
      # 祖先を間違えたマージは「衝突なく合流した」顔で誤った中身を書く
      def test_should_reject_ancestor_whose_digest_does_not_match_the_lock
        within_project do |scaffold|
          base, mine, theirs = three_way_sources
          write(scaffold, 'stylesheets/custom.css', theirs)
          write('.', 'stylesheets/custom.css', mine)
          write_base('stylesheets/custom.css', "まったく別の版の中身\n")
          write_lock(scaffold_overrides: { 'stylesheets/custom.css' => base })

          out, = with_stdin("n\n") { capture_io { run_upgrade(scaffold) } }

          assert_match(/競合\s+stylesheets\/custom\.css/, out, '照合できない祖先は使わず 2-way へ落とすべき')
          refute_includes out, '同じ場所を変えています', '祖先が無い競合で「同じ場所」とは断定できない'
          assert_equal mine, File.read('stylesheets/custom.css')
        end
      end

      # --- §8-5 祖先なし: 例外にせず 2-way の競合へ落ちる ---
      def test_should_fall_back_to_two_way_conflict_when_no_ancestor_is_available
        within_project do |scaffold|
          _base, mine, theirs = three_way_sources
          write(scaffold, 'stylesheets/custom.css', theirs)
          write('.', 'stylesheets/custom.css', mine)
          write_lock(scaffold_overrides: { 'stylesheets/custom.css' => "むかしの中身\n" })

          out, = with_stdin("n\n") { capture_io { run_upgrade(scaffold) } }

          assert_match(/競合\s+stylesheets\/custom\.css/, out)
          assert_equal mine, File.read('stylesheets/custom.css')
        end
      end

      # --- §8-6 git なし: マージできない環境でも 2-way へ落ちる ---
      def test_should_fall_back_to_two_way_conflict_when_git_is_missing
        within_project do |scaffold|
          base, mine, theirs = three_way_sources
          write(scaffold, 'stylesheets/custom.css', theirs)
          write('.', 'stylesheets/custom.css', mine)
          write_base('stylesheets/custom.css', base)
          write_lock(scaffold_overrides: { 'stylesheets/custom.css' => base })

          out = nil
          Open3.stub(:capture3, ->(*_args) { raise Errno::ENOENT, 'git' }) do
            out, = with_stdin("n\n") { capture_io { run_upgrade(scaffold) } }
          end

          assert_match(/競合\s+stylesheets\/custom\.css/, out)
          assert_equal mine, File.read('stylesheets/custom.css')
        end
      end

      # --- 合流の適用: バックアップを取り、lock は新しい雛形まで進む ---
      def test_should_back_up_and_advance_lock_when_merging
        within_project do |scaffold|
          base, mine, theirs = three_way_sources
          write(scaffold, 'stylesheets/custom.css', theirs)
          write('.', 'stylesheets/custom.css', mine)
          write_base('stylesheets/custom.css', base)
          write_lock(scaffold_overrides: { 'stylesheets/custom.css' => base })

          capture_io { run_upgrade(scaffold, yes: true) }

          backups = Dir.glob('.cache/vs/upgrade-backup/*/stylesheets/custom.css')
          assert_equal 1, backups.size, '合流も上書きなので退避されるべき'
          assert_equal mine, File.read(backups.first), '退避されるのは合流前の著者のファイル'

          lock = ScaffoldLock.read('.')
          assert_equal digest(theirs), lock[:files]['stylesheets/custom.css'], '合流分の lock は新しい雛形まで進むべき'
          assert_equal theirs, File.read('.cache/vs/scaffold-base/stylesheets/custom.css'), '次回の祖先も新しい雛形になるべき'
        end
      end

      # --- 保存基準は lock と歩調を合わせる ---

      # スキップした競合の基準まで新版で上書きすると、次回は祖先＝新版となり、
      # 「雛形は何も変えていない」ことになって**雛形側の変更を黙って捨てる**合流が起きる
      def test_should_not_advance_saved_base_for_a_skipped_conflict
        within_project do |scaffold|
          write(scaffold, 'stylesheets/custom.css', NEW_CSS)
          write('.', 'stylesheets/custom.css', CUSTOM_CSS)
          write(scaffold, 'stylesheets/improved.css', NEW_CSS)
          write('.', 'stylesheets/improved.css', OLD_CSS)
          write_lock(scaffold_overrides: { 'stylesheets/custom.css' => OLD_CSS,
                                           'stylesheets/improved.css' => OLD_CSS })

          with_stdin("n\n") { capture_io { run_upgrade(scaffold, yes: true) } }

          refute_path_exists '.cache/vs/scaffold-base/stylesheets/custom.css',
                             'スキップした競合の基準を進めてはならない'
          assert_equal NEW_CSS, File.read('.cache/vs/scaffold-base/stylesheets/improved.css'),
                       '適用したファイルの基準は進むべき'
        end
      end

      # --- §8-7 バイナリ・生成物は基準の複製対象に入らない ---

      # 雛形 7,749 件のうち 7,445 件は twemoji の SVG/WebP で、著者が編集して
      # 競合することはない。テキストだからと SVG まで抱えると保存量が桁で変わる
      def test_should_not_copy_binaries_or_generated_assets_into_the_base
        within_project do |scaffold|
          write(scaffold, 'stylesheets/custom.css', OLD_CSS)
          write(scaffold, 'stylesheets/twemoji/1f600.svg', "<svg/>\n")
          write(scaffold, 'stylesheets/fonts/sample.ttf', "\x00\x01binary")
          write(scaffold, 'contents/10-sample.md', "# 原稿\n")
          write('.', 'stylesheets/custom.css', OLD_CSS)
          write_lock

          capture_io { run_upgrade(scaffold, yes: true) }

          assert_path_exists '.cache/vs/scaffold-base/stylesheets/custom.css'
          refute_path_exists '.cache/vs/scaffold-base/stylesheets/twemoji/1f600.svg'
          refute_path_exists '.cache/vs/scaffold-base/stylesheets/fonts/sample.ttf'
          refute_path_exists '.cache/vs/scaffold-base/contents/10-sample.md'
        end
      end

      # --- 合流は全体確認に含める（個別の y/n/d は競合だけ） ---
      def test_should_include_merges_in_the_single_bulk_confirmation
        within_project do |scaffold|
          base, mine, theirs = three_way_sources
          write(scaffold, 'stylesheets/custom.css', theirs)
          write('.', 'stylesheets/custom.css', mine)
          write_base('stylesheets/custom.css', base)
          write_lock(scaffold_overrides: { 'stylesheets/custom.css' => base })

          out, = with_stdin("y\n") { capture_io { run_upgrade(scaffold) } }

          assert_includes out, '合流 1 件'
          refute_includes out, '[y]適用', '合流は個別の y/n/d を出さない'
          assert_includes File.read('stylesheets/custom.css'), '雛形の 12 行目'
        end
      end

      # --- --dry-run では合流も書き込まない ---
      def test_should_not_write_merged_content_on_dry_run
        within_project do |scaffold|
          base, mine, theirs = three_way_sources
          write(scaffold, 'stylesheets/custom.css', theirs)
          write('.', 'stylesheets/custom.css', mine)
          write_base('stylesheets/custom.css', base)
          write_lock(scaffold_overrides: { 'stylesheets/custom.css' => base })

          out, = capture_io { run_upgrade(scaffold, dry_run: true) }

          assert_includes out, '合流 1 件'
          assert_equal mine, File.read('stylesheets/custom.css'), '--dry-run は現物を書き換えないべき'
        end
      end

      private

      # 色付け判定（diff_color_enabled?）の DI 用スタブ
      FakeIO = Data.define(:tty) do
        def tty? = tty
      end

      # 著者と雛形が別の場所を変えた 2 つの内容を作る（添字は 0 起点）
      def two_sided_change(mine_at:, theirs_at:, size: 40)
        mine   = (1..size).map { "line #{it}" }
        theirs = mine.dup
        mine[mine_at]     = "わたしの #{mine_at + 1} 行目"
        theirs[theirs_at] = "雛形の #{theirs_at + 1} 行目"
        ["#{mine.join("\n")}\n", "#{theirs.join("\n")}\n"]
      end

      # 表示行を得る（unified_diff は 雛形パス・現物パス の順で受ける）
      def diff_lines(current, scaffold_new)
        Dir.mktmpdir do |dir|
          File.write(File.join(dir, 'new'), scaffold_new)
          File.write(File.join(dir, 'current'), current)
          UpgradeCommands.send(:unified_diff, File.join(dir, 'new'), File.join(dir, 'current'))
        end
      end

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

      # 雛形追従フェーズだけを検証する（自己更新はフラグで、ツール更新はスタブで遮断）。
      # gem_paths は既定で空——実際にインストール済みの gem を祖先の候補にすると、
      # 開発機に何が入っているかでテストの結果が変わる
      def run_upgrade(scaffold, dry_run: false, yes: false, gem_paths: [])
        UpgradeCommands.scaffold_source = scaffold
        ScaffoldBase.gem_paths = gem_paths
        DoctorCommands::ToolUpgrader.stub(:run!, 0) do
          UpgradeCommands.run_from_command(FakeCmd.new(options: { dry_run:, yes:, skip_self_update: true }))
        end
      ensure
        UpgradeCommands.scaffold_source = nil
        ScaffoldBase.gem_paths = nil
      end

      # 祖先・著者・雛形の 3 つを作る。著者は先頭・雛形は末尾を変える（＝離れた変更）
      def three_way_sources(size: 12)
        base   = (1..size).map { |n| "line #{n}" }
        mine   = base.dup
        theirs = base.dup
        mine[0]          = 'わたしの 1 行目'
        theirs[size - 1] = "雛形の #{size} 行目"
        [base, mine, theirs].map { "#{it.join("\n")}\n" }
      end

      # 共通祖先をプロジェクト内の保存基準（経路 B）として置く
      def write_base(relative, content)
        write(File.join('.cache', 'vs', 'scaffold-base'), relative, content)
      end

      # 旧版 gem を模した GEM_HOME を作り、その雛形へ祖先を置く（経路 A）
      def write_gem_base(gem_home, relative, content)
        write(File.join(gem_home, 'gems', 'vivlio-starter-0.9.0', 'lib', 'project_scaffold'), relative, content)
        gem_home
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
