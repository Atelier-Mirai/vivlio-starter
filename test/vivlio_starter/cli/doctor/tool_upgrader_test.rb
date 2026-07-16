# frozen_string_literal: true

# ================================================================
# Test: tool_upgrader_test.rb
# ================================================================
# テスト対象:
#   ToolUpgrader モジュール（lib/vivlio_starter/cli/doctor/tool_upgrader.rb）
#   `vs upgrade` の外部ツール更新フェーズ
#   （docs/archives/doctor-tool-upgrade-spec.md §3 のテスト項目 1〜6）。
#
# 検証内容:
#   1. 計画生成: brew/npm outdated のスタブ JSON から更新計画が正しく組まれる
#   2. 連動規則: node が更新対象なら @vivliostyle/cli が必ず計画に入る
#   3. 失敗継続: 途中のツールが失敗しても後続が実行され、終了コード 1
#   4. 確認プロンプト: --yes なしで n 応答 → 何も実行せず 0、--yes で即実行
#   5. オフライン検知: brew update 失敗 → 中断・終了コード 1
#   6. 新版お知らせ: Ruby の新版検出と導入経路別の案内
#   7. スキップ: 非 macOS / --dry-run では更新を実行せず終了コード 0
#
# テスト環境:
#   - 外部コマンド・ネットワーク・端末入力はすべて Deps（DI）で注入し、実行しない
#   - 再診断（DoctorCommands.execute_doctor）はスタブ化する
# ================================================================

require 'test_helper'
require 'stringio'
require 'json'
require 'vivlio_starter/cli'
require 'vivlio_starter/cli/doctor'

module VivlioStarter
  module CLI
    module DoctorCommands
      # ToolUpgrader のユニットテスト
      class ToolUpgraderTest < Minitest::Test
        # 対話端末を装う入力（確認プロンプトのテスト用。素の StringIO は tty? が
        # false のため非対話扱いとなり、プロンプト経路に到達しない）
        class TtyStringIO < StringIO
          def tty? = true
        end

        NO_OUTDATED = '{"formulae":[],"casks":[]}'

        # 全 brew formula が導入済みの brew list --versions 出力
        BREW_LIST_ALL = <<~LIST
          node 22.11.0
          qpdf 12.1.0
          poppler 25.1.0
          ghostscript 10.04.0
          imagemagick 7.1.1
          librsvg 2.59.1
          vips 8.16.0
          tesseract 5.5.0
          tesseract-lang 4.1.0
          mecab 0.996
          mecab-ipadic 2.7.0
        LIST

        CASK_LIST_ALL = "inkscape 1.4.0\nkindle-previewer 3.104.0\n"

        NPM_LS_ALL = {
          dependencies: {
            '@vivliostyle/cli' => { version: '11.0.0' },
            'textlint' => { version: '14.0.0' },
            'mathjax-full' => { version: '3.2.2' }
          }
        }.to_json

        # ------------------------------------------------------------
        # 1. 計画生成
        # ------------------------------------------------------------

        # brew outdated のスタブ JSON から「対象・現在版・最新版・系統」が正しく組まれる
        def test_should_build_upgrade_plan_from_outdated_json
          brew_outdated = {
            formulae: [{ name: 'qpdf', installed_versions: ['12.1.0'], current_version: '12.2.1' }],
            casks: []
          }.to_json
          npm_outdated = { '@vivliostyle/cli' => { current: '11.0.0', wanted: '11.0.0', latest: '11.2.0' } }.to_json
          deps = stub_deps(capture: capture_map(brew_outdated:, npm_outdated:))

          plan = DoctorCommands.stub(:pdf_plugin_installed?, false) { ToolUpgrader.build_plan(deps) }

          qpdf = plan.entries.find { it.label == 'qpdf' }
          assert_pattern { qpdf => { kind: :brew, action: :upgrade, current: '12.1.0', latest: '12.2.1' } }
          vivliostyle = plan.entries.find { it.label == 'vivliostyle CLI' }
          assert_pattern { vivliostyle => { kind: :npm, action: :upgrade, current: '11.0.0', latest: '11.2.0' } }
          node = plan.entries.find { it.label == 'node' }
          assert_equal :current, node.action, '最新の formula は更新対象にならない'
          assert_equal ['qpdf', 'vivliostyle CLI'], plan.updates.map(&:label).sort
        end

        # 更新対象外ツール（waifu2x / rouge）は「対象外（手動）」として計画に明示される
        def test_should_mark_manual_tools_as_out_of_scope
          deps = stub_deps(capture: capture_map)

          plan = DoctorCommands.stub(:pdf_plugin_installed?, false) { ToolUpgrader.build_plan(deps) }

          manuals = plan.entries.select { it.action == :manual }.map(&:label)
          assert_includes manuals, 'waifu2x'
          assert_includes manuals, 'rouge'
          refute_includes plan.updates.map(&:label), 'waifu2x'
        end

        # すべて最新なら更新対象が空になる
        def test_should_produce_empty_updates_when_everything_latest
          deps = stub_deps(capture: capture_map)

          plan = DoctorCommands.stub(:pdf_plugin_installed?, false) { ToolUpgrader.build_plan(deps) }

          assert_empty plan.updates
        end

        # プラグイン gem は導入済みなら計画に載り、新版があれば更新対象になる
        def test_should_plan_plugin_gem_upgrade_when_newer_release_exists
          url = format(ToolUpgrader::RUBYGEMS_LATEST_URL, 'vivlio-starter-pdf')
          deps = stub_deps(capture: capture_map, fetch: { url => '{"version":"1.4.2"}' })

          plan = DoctorCommands.stub(:pdf_plugin_installed?, true) do
            ToolUpgrader.stub(:installed_gem_version, '1.4.0') { ToolUpgrader.build_plan(deps) }
          end

          plugin = plan.entries.find { it.label == 'vivlio-starter-pdf' }
          assert_pattern { plugin => { kind: :gem, action: :upgrade, current: '1.4.0', latest: '1.4.2' } }
        end

        # プラグイン gem が最新なら更新対象にならない
        def test_should_keep_plugin_gem_when_already_latest
          url = format(ToolUpgrader::RUBYGEMS_LATEST_URL, 'vivlio-starter-pdf')
          deps = stub_deps(capture: capture_map, fetch: { url => '{"version":"1.4.0"}' })

          plan = DoctorCommands.stub(:pdf_plugin_installed?, true) do
            ToolUpgrader.stub(:installed_gem_version, '1.4.0') { ToolUpgrader.build_plan(deps) }
          end

          assert_equal :current, plan.entries.find { it.label == 'vivlio-starter-pdf' }.action
        end

        # プラグイン未導入なら gem 行は計画に載らない
        def test_should_omit_plugin_gem_when_not_installed
          deps = stub_deps(capture: capture_map)

          plan = DoctorCommands.stub(:pdf_plugin_installed?, false) { ToolUpgrader.build_plan(deps) }

          assert_nil plan.entries.find { it.label == 'vivlio-starter-pdf' }
        end

        # ------------------------------------------------------------
        # 2. 連動規則（node → vivliostyle CLI）
        # ------------------------------------------------------------

        # node が更新対象のとき、@vivliostyle/cli が最新でも必ず計画に入る（spec §1.3）
        def test_should_force_vivliostyle_upgrade_when_node_upgrades
          brew_outdated = {
            formulae: [{ name: 'node', installed_versions: ['22.11.0'], current_version: '26.0.0' }],
            casks: []
          }.to_json
          deps = stub_deps(capture: capture_map(brew_outdated:))

          plan = DoctorCommands.stub(:pdf_plugin_installed?, false) { ToolUpgrader.build_plan(deps) }

          vivliostyle = plan.updates.find { it.label == 'vivliostyle CLI' }
          refute_nil vivliostyle, 'node 更新時は vivliostyle CLI も計画に入る'
          assert_includes vivliostyle.note.to_s, 'node'
        end

        # node がバージョン付き別名（node@20）で導入されていても連動規則が働く
        def test_should_match_versioned_node_formula
          brew_outdated = {
            formulae: [{ name: 'node@20', installed_versions: ['20.10.0'], current_version: '20.19.0' }],
            casks: []
          }.to_json
          brew_list = BREW_LIST_ALL.sub('node 22.11.0', 'node@20 20.10.0')
          deps = stub_deps(capture: capture_map(brew_outdated:, brew_list:))

          plan = DoctorCommands.stub(:pdf_plugin_installed?, false) { ToolUpgrader.build_plan(deps) }

          node = plan.updates.find { it.label == 'node' }
          assert_pattern { node => { action: :upgrade, package: 'node@20' } }
          refute_nil plan.updates.find { it.label == 'vivliostyle CLI' }
        end

        # ------------------------------------------------------------
        # 3. 失敗継続
        # ------------------------------------------------------------

        # 2 番目のツールが失敗しても 3 番目以降が実行され、終了コード 1
        def test_should_continue_after_failure_and_exit_nonzero
          brew_outdated = {
            formulae: [
              { name: 'qpdf', installed_versions: ['12.1.0'], current_version: '12.2.1' },
              { name: 'ghostscript', installed_versions: ['10.0.0'], current_version: '10.4.0' }
            ], casks: []
          }.to_json
          npm_outdated = { 'mathjax-full' => { current: '3.2.2', latest: '3.2.5' } }.to_json
          executed = []
          deps = stub_deps(capture: capture_map(brew_outdated:, npm_outdated:),
                           run_ok: { 'brew upgrade ghostscript' => false },
                           input: '', executed:)

          code = run_upgrader(deps, yes: true)

          assert_equal 1, code, '1 件でも失敗したら終了コード 1'
          assert_includes executed, 'brew upgrade qpdf'
          assert_includes executed, 'brew upgrade ghostscript'
          assert executed.any? { it.include?('mathjax-full@latest') },
                 '失敗したツールの後続（npm）も実行される'
        end

        # 全成功＋再診断 OK なら終了コード 0
        def test_should_exit_zero_when_all_updates_succeed
          brew_outdated = {
            formulae: [{ name: 'qpdf', installed_versions: ['12.1.0'], current_version: '12.2.1' }], casks: []
          }.to_json
          executed = []
          deps = stub_deps(capture: capture_map(brew_outdated:), input: '', executed:)

          code = run_upgrader(deps, yes: true)

          assert_equal 0, code
          assert_includes executed, 'brew upgrade qpdf'
        end

        # 再診断が NG（必要ツールの不足が残る）なら全更新成功でも終了コード 1
        def test_should_exit_nonzero_when_rediagnosis_fails
          brew_outdated = {
            formulae: [{ name: 'qpdf', installed_versions: ['12.1.0'], current_version: '12.2.1' }], casks: []
          }.to_json
          deps = stub_deps(capture: capture_map(brew_outdated:), input: '')

          code = run_upgrader(deps, yes: true, rediagnosis: false)

          assert_equal 1, code
        end

        # ------------------------------------------------------------
        # 4. 確認プロンプト
        # ------------------------------------------------------------

        # --yes なしで n 応答 → 更新コマンドは何も実行せず終了コード 0
        def test_should_execute_nothing_when_user_declines
          brew_outdated = {
            formulae: [{ name: 'qpdf', installed_versions: ['12.1.0'], current_version: '12.2.1' }], casks: []
          }.to_json
          executed = []
          deps = stub_deps(capture: capture_map(brew_outdated:), input: "n\n", executed:)

          code = run_upgrader(deps, yes: false)

          assert_equal 0, code
          refute executed.any? { it.start_with?('brew upgrade') }, 'n 応答では何も更新しない'
        end

        # --yes 指定時はプロンプトなしで即実行される
        def test_should_execute_immediately_with_yes_option
          brew_outdated = {
            formulae: [{ name: 'qpdf', installed_versions: ['12.1.0'], current_version: '12.2.1' }], casks: []
          }.to_json
          executed = []
          # --yes なら stdin は読まれない（読むと EOF で nil → 実行されないことで検出できる）
          deps = stub_deps(capture: capture_map(brew_outdated:), input: '', executed:)

          code = run_upgrader(deps, yes: true)

          assert_equal 0, code
          assert_includes executed, 'brew upgrade qpdf'
        end

        # 非対話（tty でない）かつ --yes なしでは安全側に倒して実行しない
        def test_should_decline_on_non_tty_without_yes
          brew_outdated = {
            formulae: [{ name: 'qpdf', installed_versions: ['12.1.0'], current_version: '12.2.1' }], casks: []
          }.to_json
          executed = []
          deps = stub_deps(capture: capture_map(brew_outdated:), input: StringIO.new("y\n"), executed:)

          code = run_upgrader(deps, yes: false)

          assert_equal 0, code
          refute executed.any? { it.start_with?('brew upgrade') }
        end

        # ------------------------------------------------------------
        # 5. オフライン検知
        # ------------------------------------------------------------

        # brew update の失敗（オフライン）を検知したら中断・終了コード 1
        def test_should_abort_when_brew_update_fails
          executed = []
          deps = stub_deps(capture: capture_map,
                           run_ok: { 'brew update >/dev/null 2>&1' => false },
                           input: '', executed:)

          code = run_upgrader(deps, yes: true)

          assert_equal 1, code
          refute executed.any? { it.start_with?('brew upgrade') }, '中途半端な更新をしない'
        end

        # npm outdated が JSON でない出力を返した（ネットワーク異常）場合も中断する
        def test_should_abort_when_npm_outdated_returns_garbage
          deps = stub_deps(capture: capture_map(npm_outdated: 'npm ERR! network unreachable'), input: '')

          code = run_upgrader(deps, yes: true)

          assert_equal 1, code
        end

        # ------------------------------------------------------------
        # 6. 新版お知らせ（spec §1.4）
        # ------------------------------------------------------------

        RELEASES_YAML = <<~YAML
          - version: 4.1.0
            date: 2026-12-25
          - version: 4.0.5
            date: 2026-06-01
          - version: 4.0.3
            date: 2026-02-04
        YAML

        # 同一 patch 系列の新版があれば、導入経路（rbenv）に応じた手順と
        # gem 再インストールの注意が案内に含まれる
        def test_should_notice_new_ruby_patch_with_rbenv_steps
          deps = stub_deps(fetch: { ToolUpgrader::RUBY_RELEASES_URL => RELEASES_YAML })

          lines = ToolUpgrader.ruby_update_notice(deps, current: '4.0.3', route: :rbenv)

          assert lines.any? { it.include?('4.0.5') && it.include?('4.0.3') }, '新旧バージョンを明示する'
          assert lines.any? { it.include?('rbenv install 4.0.5') && it.include?('rbenv global 4.0.5') }
          assert lines.any? { it.include?('gem install vivlio-starter') && it.include?('再インストール') },
                 'gem 再インストールの注意を必ず添える'
        end

        # 最新なら何も出ない
        def test_should_stay_silent_when_ruby_is_latest
          deps = stub_deps(fetch: { ToolUpgrader::RUBY_RELEASES_URL => RELEASES_YAML })

          assert_empty ToolUpgrader.ruby_update_notice(deps, current: '4.0.5', route: :rbenv)
        end

        # マイナー/メジャー差（4.0 → 4.1）は案内しない（同一 patch 系列のみ対象）
        def test_should_not_notice_minor_or_major_ruby_updates
          yaml = "- version: 4.1.0\n  date: 2026-12-25\n"
          deps = stub_deps(fetch: { ToolUpgrader::RUBY_RELEASES_URL => yaml })

          assert_empty ToolUpgrader.ruby_update_notice(deps, current: '4.0.5', route: :rbenv)
        end

        # 取得失敗（タイムアウト/不通）でもお知らせは黙ってスキップされる
        def test_should_skip_notice_silently_on_fetch_failure
          deps = stub_deps(fetch: {}) # fetch は常に nil

          assert_empty ToolUpgrader.ruby_update_notice(deps, current: '4.0.3', route: :rbenv)
        end

        # 導入経路の判別: 起動中 Ruby の prefix パスから判定する
        def test_should_detect_ruby_route_from_prefix
          assert_equal :rbenv, ToolUpgrader.detect_ruby_route('/Users/author/.rbenv/versions/4.0.3')
          assert_equal :mise, ToolUpgrader.detect_ruby_route('/Users/author/.local/share/mise/installs/ruby/4.0.3')
          assert_equal :homebrew, ToolUpgrader.detect_ruby_route('/opt/homebrew/Cellar/ruby/4.0.3')
          assert_equal :unknown, ToolUpgrader.detect_ruby_route('/usr/lib/ruby')
        end

        # ------------------------------------------------------------
        # 7. スキップ（非 macOS / --dry-run）
        # ------------------------------------------------------------

        # 非 macOS ではエラーにせずスキップして 0 を返す（vs upgrade の
        # 他フェーズ——本体更新・雛形追従——を巻き添えにしない）
        def test_should_skip_on_non_macos_without_error
          executed = []
          deps = stub_deps(capture: capture_map, input: '', executed:)

          code = run_upgrader(deps, yes: true, host_os: 'linux-gnu')

          assert_equal 0, code
          assert_empty executed, '非 macOS では外部コマンドを一切実行しない'
        end

        # --dry-run は計画提示のみで、更新コマンドも再診断も実行しない
        def test_should_present_plan_without_executing_on_dry_run
          brew_outdated = {
            formulae: [{ name: 'qpdf', installed_versions: ['12.1.0'], current_version: '12.2.1' }], casks: []
          }.to_json
          executed = []
          deps = stub_deps(capture: capture_map(brew_outdated:), input: '', executed:)

          rediagnosed = false
          code = run_upgrader(deps, yes: false, dry_run: true, rediagnosis_probe: -> { rediagnosed = true })

          assert_equal 0, code
          refute executed.any? { it.start_with?('brew upgrade') }, 'dry-run では更新しない'
          refute rediagnosed, 'dry-run では再診断（--fix 委譲）もしない'
        end

        private

        # run! を macOS 前提＋再診断スタブ＋ログ抑制つきで実行する
        def run_upgrader(deps, yes:, dry_run: false, rediagnosis: true, host_os: 'darwin', rediagnosis_probe: nil)
          code = nil
          rediagnose = lambda do |*_args|
            rediagnosis_probe&.call
            rediagnosis
          end
          with_host_os(host_os) do
            stub_logging do
              DoctorCommands.stub(:execute_doctor, rediagnose) do
                DoctorCommands.stub(:pdf_plugin_installed?, false) do
                  capture_io { code = ToolUpgrader.run!({ yes:, dry_run:, verbose: false }, deps:) }
                end
              end
            end
          end
          code
        end

        # 注入用 Deps を組み立てる。
        # capture: コマンド → [出力, 成否]、run_ok: コマンド → 成否（未指定は true）、
        # fetch: URL → 応答文字列（未指定は nil）、input: 端末入力（String は tty 扱い）
        def stub_deps(capture: {}, run_ok: {}, fetch: {}, input: '', executed: [])
          stdin = input.is_a?(String) ? TtyStringIO.new(input) : input
          ToolUpgrader::Deps.new(
            run: lambda { |cmd|
              executed << cmd
              run_ok.fetch(cmd, true)
            },
            capture: ->(cmd) { capture.fetch(cmd, ['', true]) },
            fetch: ->(url) { fetch[url] },
            stdin:
          )
        end

        # 一括問い合わせの標準スタブ（既定は「全ツール導入済み・すべて最新」）
        def capture_map(brew_outdated: NO_OUTDATED, cask_outdated: NO_OUTDATED, npm_outdated: '{}',
                        brew_list: BREW_LIST_ALL, cask_list: CASK_LIST_ALL, npm_ls: NPM_LS_ALL)
          q = ToolUpgrader::QUERIES
          {
            q[:brew_outdated] => [brew_outdated, true],
            q[:cask_outdated] => [cask_outdated, true],
            q[:npm_outdated] => [npm_outdated, false],
            q[:brew_list] => [brew_list, true],
            q[:cask_list] => [cask_list, true],
            q[:npm_ls] => [npm_ls, true]
          }
        end

        # 指定した host_os を一時的に設定（doctor_commands_test と同型）
        def with_host_os(value)
          original = RbConfig::CONFIG['host_os']
          RbConfig::CONFIG['host_os'] = value
          yield
        ensure
          RbConfig::CONFIG['host_os'] = original
        end

        # ログ出力を抑制
        def stub_logging(&block)
          apply = lambda do |methods|
            return block.call if methods.empty?

            Common.stub(methods.first, nil) { apply.call(methods[1..]) }
          end
          apply.call(%i[log_always log_info log_warn log_error log_action])
        end
      end
    end
  end
end
