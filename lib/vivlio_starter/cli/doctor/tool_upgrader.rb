# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/doctor/tool_upgrader.rb
# ================================================================
# 責務:
#   `vs upgrade` の外部ツール更新フェーズ。導入済み外部ツールの現在/最新
#   バージョン取得・更新計画の提示・確認・一括更新・結果集計を担う
#   （docs/archives/doctor-tool-upgrade-spec.md、統合の経緯は
#   docs/archives/upgrade-unification-spec.md）。
#
# 設計の要点:
#   - --fix の上位互換: 導入済みツールの更新に加え、未導入分は
#     更新後の再診断（execute_doctor を fix: true で呼ぶ）へ委譲して一括導入する
#   - 最新版の取得は brew outdated / npm outdated を各 1 回だけ実行してまとめて
#     行う（ツールごとの問い合わせは遅いためしない・spec §2.2）
#   - ツール単位で失敗しても続行し、最後に失敗一覧と手動復旧コマンドを提示する
#   - 非 macOS / Homebrew 不在は「スキップ（終了コード 0）」——vs upgrade の
#     一フェーズであり、他フェーズ（本体更新・雛形追従）を巻き添えにしない
#   - Ruby 本体は自動更新しない（新版の検出と更新手順の案内のみ）。
#     vivlio-starter 本体の更新は UpgradeCommands の自己更新フェーズが担う
#   - 外部コマンド・ネットワーク・端末入力は Deps として注入可能（テスト用 DI）
#
# 依存:
#   - Common: ログ出力
#   - DoctorCommands: 再診断（execute_doctor）・プラグイン導入判定
# ================================================================

require 'rbconfig'
require 'open3'
require 'json'
require 'yaml'
require 'date'
require 'net/http'
require 'uri'
require 'shellwords'

require_relative '../common'
require_relative '../../version'

module VivlioStarter
  module CLI
    module DoctorCommands
      # vs upgrade の外部ツール更新フェーズの実装。
      # 更新対象の列挙・現在/最新バージョンの取得・計画提示・実行・結果集計を担う。
      module ToolUpgrader
        module_function

        # ツール定義。checks は doctor.rb の診断ラベル（missing 判定との突き合わせ用）。
        # brew formula / npm パッケージ名の正典はこの表であり、--fix のインストール処理も
        # brew_install_packages 経由でここを参照する（doctor.rb 側と二重管理しない・spec §4-1）。
        Tool = Data.define(:label, :kind, :package, :checks) do
          # brew の導入記録との突き合わせ。node はバージョン付き別名（node@20 等）で
          # 導入されていることがあるため前方一致相当で拾う
          def matches_formula?(name)
            return name.match?(/\Anode(@\d+)?\z/) if package == 'node'

            name == package
          end
        end

        # textlint と推奨ルール一式（npm -g）。--fix のインストールと --upgrade の更新で共用する
        TEXTLINT_NPM_PACKAGES = %w[
          textlint
          textlint-rule-preset-ja-technical-writing
          textlint-rule-preset-japanese
          textlint-rule-prh
          textlint-filter-rule-node-types
          textlint-filter-rule-allowlist
          textlint-filter-rule-comments
          textlint-rule-no-dropping-the-ra
          textlint-rule-max-ten
          textlint-rule-ja-no-mixed-period
          textlint-rule-no-doubled-conjunction@3.0.0
          textlint-rule-no-doubled-joshi
          textlint-rule-ja-no-successive-word
          textlint-rule-preset-ja-spacing
          textlint-rule-spellcheck-tech-word
          textlint-rule-no-dead-link
          textlint-rule-ng-word
        ].freeze

        TOOLS = [
          Tool.new(label: 'node', kind: :brew, package: 'node', checks: %w[node]),
          Tool.new(label: 'vivliostyle CLI', kind: :npm, package: '@vivliostyle/cli', checks: %w[vivliostyle]),
          Tool.new(label: 'textlint 一式', kind: :npm, package: :textlint_set, checks: %w[textlint]),
          Tool.new(label: 'mathjax-full', kind: :npm, package: 'mathjax-full', checks: %w[mathjax]),
          Tool.new(label: 'mermaid-cli', kind: :npm, package: '@mermaid-js/mermaid-cli', checks: %w[mermaid]),
          Tool.new(label: 'qpdf', kind: :brew, package: 'qpdf', checks: %w[qpdf]),
          Tool.new(label: 'poppler', kind: :brew, package: 'poppler', checks: %w[pdfinfo pdftoppm]),
          Tool.new(label: 'ghostscript', kind: :brew, package: 'ghostscript', checks: %w[gs]),
          Tool.new(label: 'imagemagick', kind: :brew, package: 'imagemagick', checks: %w[imagemagick]),
          Tool.new(label: 'librsvg', kind: :brew, package: 'librsvg', checks: %w[rsvg-convert]),
          Tool.new(label: 'vips', kind: :brew, package: 'vips', checks: %w[vips]),
          Tool.new(label: 'tesseract', kind: :brew, package: 'tesseract', checks: %w[tesseract]),
          Tool.new(label: 'tesseract-lang', kind: :brew, package: 'tesseract-lang', checks: %w[tesseract-lang]),
          Tool.new(label: 'mecab', kind: :brew, package: 'mecab', checks: %w[mecab]),
          Tool.new(label: 'mecab-ipadic', kind: :brew, package: 'mecab-ipadic', checks: %w[mecab]),
          Tool.new(label: 'inkscape', kind: :cask, package: 'inkscape', checks: %w[inkscape]),
          Tool.new(label: 'kindle-previewer', kind: :cask, package: 'kindle-previewer', checks: %w[kindlepreviewer]),
          # Enhanced Mode プラグイン（gem 名は provider.rb / doctor.rb と同値。導入済みの場合のみ更新対象）
          Tool.new(label: 'vivlio-starter-pdf', kind: :gem, package: 'vivlio-starter-pdf', checks: []),
          Tool.new(label: 'waifu2x', kind: :manual, package: nil, checks: []),
          Tool.new(label: 'rouge', kind: :manual, package: nil, checks: [])
        ].freeze

        # 更新対象外（:manual）の理由（計画表の注記）
        MANUAL_NOTES = {
          'waifu2x' => '導入経路が多様',
          'rouge' => '本 gem の依存として Bundler 管理'
        }.freeze

        # 一括問い合わせコマンド。ツールごとの個別問い合わせはしない（遅いため・spec §2.2）。
        # npm outdated は「差分あり」でも exit 1 を返すため、成否ではなく JSON の解釈で判断する
        QUERIES = {
          brew_outdated: 'brew outdated --json',
          cask_outdated: 'brew outdated --cask --json',
          npm_outdated: 'npm outdated -g --json 2>/dev/null',
          brew_list: 'brew list --versions',
          cask_list: 'brew list --cask --versions',
          npm_ls: 'npm ls -g --depth=0 --json 2>/dev/null'
        }.freeze

        # 新版お知らせ（spec §1.4）の取得元。
        # Ruby は ruby-lang.org 公式のリリースデータを使う——rbenv install --list は
        # 手元の ruby-build 定義依存で古い版しか返さないため使わない
        RUBY_RELEASES_URL = 'https://raw.githubusercontent.com/ruby/www.ruby-lang.org/master/_data/releases.yml'
        RUBYGEMS_LATEST_URL = 'https://rubygems.org/api/v1/versions/%s/latest.json'

        # 計画 1 行分。action は :upgrade（更新あり）/ :current（最新）/
        # :missing（未導入→再診断の --fix 委譲で導入）/ :manual（対象外）
        PlanEntry = Data.define(:label, :kind, :package, :current, :latest, :action, :note)

        # 更新計画（全ツール分の行を表示順で保持する）
        Plan = Data.define(:entries) do
          def updates = entries.select { it.action == :upgrade }
        end

        # 1 ツールの更新結果
        UpdateResult = Data.define(:entry, :ok)

        # 実行依存の注入点（テストで外部コマンド・ネットワーク・端末入力を遮断するための DI）。
        # run:     ->(cmd)  { Boolean }           system 相当
        # capture: ->(cmd)  { [String, Boolean] } 標準出力と成否
        # fetch:   ->(url)  { String | nil }      HTTP GET（タイムアウト 2 秒・失敗は nil）
        # stdin:   IO                              確認プロンプト入力
        Deps = Data.define(:run, :capture, :fetch, :stdin)

        def default_deps
          Deps.new(
            run: ->(cmd) { Kernel.system(cmd) },
            capture: lambda do |cmd|
              out, status = Open3.capture2(cmd)
              [out, status.success?]
            rescue StandardError
              ['', false]
            end,
            fetch: ->(url) { http_get(url) },
            stdin: $stdin
          )
        end

        # 外部ツール更新の一連の流れ（計画提示 → 確認 → 実行 → 再診断 → 集計 → お知らせ）を統率する。
        # @param options [Hash] { yes:, dry_run:, verbose:, ... }
        # @return [Integer] 終了コード（全成功＋再診断 OK / スキップ → 0、失敗あり/再診断 NG/中断 → 1）
        def run!(options, deps: default_deps)
          # --- Phase: 前提確認（--fix と同じく macOS + Homebrew のみ対応・spec §0）---
          # 非対応環境はエラーではなくスキップ——vs upgrade の他フェーズ（本体更新・
          # 雛形追従）はプラットフォーム非依存で、ここで全体を止める理由がない
          unless RbConfig::CONFIG['host_os'] =~ /darwin/i
            Common.log_warn('外部ツールの更新は macOS + Homebrew のみ対応のためスキップします（診断は vs doctor で実行できます）。')
            return 0
          end
          unless deps.run.call('which brew >/dev/null 2>&1')
            Common.log_warn('Homebrew が見つからないため外部ツールの更新をスキップします。vs doctor --fix で導入するか、https://brew.sh/ を参照してください。')
            return 0
          end

          # --- Phase: 最新情報の取得（オフラインなら中断——中途半端な更新をしない・spec §2.2）---
          Common.log_always('🔍 外部ツールのバージョンを確認しています…')
          unless deps.run.call('brew update >/dev/null 2>&1')
            Common.log_error('最新版の確認ができません（オフライン？）。ネットワーク接続を確認して再実行してください。')
            return 1
          end
          plan = build_plan(deps)
          return 1 unless plan

          # --- Phase: 計画提示 → 確認 ---
          present_plan(plan)
          if options[:dry_run]
            Common.log_always('--dry-run のためツール更新は実行しません。') if plan.updates.any?
            return 0
          end
          if plan.updates.empty?
            Common.log_always('✅ すべて最新です')
          elsif !confirm_upgrade?(options, deps)
            Common.log_always('更新をスキップしました。--yes を付けると確認なしで実行できます。')
            return 0
          end

          # --- Phase: 実行（1 ツールの失敗で全体を中断しない・spec §2.3）---
          results = plan.updates.map { execute_update(it, deps) }

          # --- Phase: 再診断（未導入分のインストールは既存 --fix へ委譲＝上位互換・spec §1.2）---
          Common.log_always('🩺 更新後の診断を実行します…')
          rediagnosis_ok = DoctorCommands.execute_doctor(
            { options: { fix: true, yes: options[:yes], verbose: options[:verbose] } }
          )

          # --- Phase: 集計 → 新版お知らせ ---
          failed = results.reject(&:ok)
          Common.log_always("✅ 更新完了: #{results.count(&:ok)} 件成功 / #{failed.size} 件失敗") if results.any?
          report_failures(failed)
          announce_new_versions(deps)

          failed.empty? && rediagnosis_ok ? 0 : 1
        end

        # ============================================================
        # 計画の生成（spec §2.2）
        # ============================================================

        # 全ツールの計画行を生成する。npm の最新版確認に失敗（オフライン疑い）した場合は
        # nil を返し、呼び出し元が中断する。
        # @return [Plan, nil]
        def build_plan(deps)
          # --- Phase: 一括取得 ---
          formula_outdated = parse_brew_outdated(deps.capture.call(QUERIES[:brew_outdated]).first, 'formulae')
          cask_outdated    = parse_brew_outdated(deps.capture.call(QUERIES[:cask_outdated]).first, 'casks')
          npm_outdated     = parse_json_hash(deps.capture.call(QUERIES[:npm_outdated]).first)
          if npm_outdated.nil?
            Common.log_error('npm の最新版確認に失敗しました（オフライン？）。ネットワーク接続を確認して再実行してください。')
            return nil
          end
          formula_versions = parse_brew_versions(deps.capture.call(QUERIES[:brew_list]).first)
          cask_versions    = parse_brew_versions(deps.capture.call(QUERIES[:cask_list]).first)
          npm_versions     = parse_npm_versions(deps.capture.call(QUERIES[:npm_ls]).first)

          # --- Phase: ツールごとの行生成 ---
          entries = TOOLS.filter_map do |tool|
            case tool.kind
            when :brew then brew_entry(tool, formula_versions, formula_outdated)
            when :cask then brew_entry(tool, cask_versions, cask_outdated)
            when :npm  then npm_entry(tool, npm_versions, npm_outdated)
            when :gem  then gem_entry(tool, deps)
            when :manual then manual_entry(tool)
            end
          end

          Plan.new(entries: apply_node_link_rule(entries))
        end

        # node を更新する場合は @vivliostyle/cli も必ず最新へ連動更新する（spec §1.3）。
        # Node 26 × vivliostyle 10.6 の Chrome 展開デッドロックのような
        # 「バージョン組み合わせ起因の実害」を再発させないための規則。
        def apply_node_link_rule(entries)
          node = entries.find { it.label == 'node' }
          return entries unless node && node.action == :upgrade

          entries.map do |entry|
            next entry unless entry.label == 'vivliostyle CLI'

            case entry.action
            when :current then entry.with(action: :upgrade, latest: '最新', note: 'node と連動')
            when :upgrade then entry.with(note: 'node と連動')
            else entry
            end
          end
        end

        def brew_entry(tool, versions, outdated)
          outdated_name  = outdated.keys.find { tool.matches_formula?(it) }
          installed_name = versions.keys.find { tool.matches_formula?(it) }
          if outdated_name
            installed, latest = outdated[outdated_name]
            PlanEntry.new(label: tool.label, kind: tool.kind, package: outdated_name,
                          current: installed || versions[outdated_name], latest:, action: :upgrade, note: nil)
          elsif installed_name
            PlanEntry.new(label: tool.label, kind: tool.kind, package: installed_name,
                          current: versions[installed_name], latest: nil, action: :current, note: nil)
          else
            PlanEntry.new(label: tool.label, kind: tool.kind, package: tool.package,
                          current: nil, latest: nil, action: :missing, note: nil)
          end
        end

        def npm_entry(tool, versions, outdated)
          names = tool.package == :textlint_set ? TEXTLINT_NPM_PACKAGES.map { npm_base_name(it) } : [tool.package]
          current = versions[names.first]
          outdated_name = names.find { outdated.key?(it) }
          info = outdated_name ? outdated[outdated_name] : nil
          info = nil unless info.is_a?(Hash)

          if outdated_name
            # textlint 一式は複数パッケージの束のため、単一の最新版表示はしない
            latest = tool.package == :textlint_set ? nil : info&.fetch('latest', nil)
            PlanEntry.new(label: tool.label, kind: :npm, package: tool.package,
                          current: current || info&.fetch('current', nil), latest:, action: :upgrade, note: nil)
          elsif current
            PlanEntry.new(label: tool.label, kind: :npm, package: tool.package,
                          current:, latest: nil, action: :current, note: nil)
          else
            PlanEntry.new(label: tool.label, kind: :npm, package: tool.package,
                          current: nil, latest: nil, action: :missing, note: nil)
          end
        end

        # Enhanced Mode プラグイン（導入済みの場合のみ更新対象・spec §1.2）。
        # 現在版のパース失敗・最新版の取得失敗でも更新対象に含める——gem update は
        # 冪等で「更新して害はない」ため（spec §2.2）
        def gem_entry(tool, deps)
          return nil unless DoctorCommands.pdf_plugin_installed?

          current = installed_gem_version(tool.package)
          latest = latest_gem_version(deps, tool.package)
          up_to_date = current && latest &&
                       Gem::Version.correct?(current) &&
                       Gem::Version.new(latest) <= Gem::Version.new(current)
          PlanEntry.new(label: tool.label, kind: :gem, package: tool.package,
                        current: current || '不明', latest:,
                        action: up_to_date ? :current : :upgrade, note: nil)
        end

        def manual_entry(tool)
          PlanEntry.new(label: tool.label, kind: :manual, package: nil, current: nil, latest: nil,
                        action: :manual, note: MANUAL_NOTES[tool.label])
        end

        # インストール済み gemspec の走査で現在版を得る（pdf_plugin_installed? と同じ手法）。
        # `gem list` の子プロセスは Bundler 配下（bundle exec 経由の実行）だと Gemfile に
        # 拘束され、Gemfile に無いプラグインが見えないため使わない
        def installed_gem_version(gem_name)
          Gem.path
             .flat_map { Dir.glob(File.join(it, 'specifications', "#{gem_name}-*.gemspec")) }
             .filter_map { File.basename(it, '.gemspec').delete_prefix("#{gem_name}-") }
             .select { Gem::Version.correct?(it) }
             .map { Gem::Version.new(it) }
             .max&.to_s
        rescue StandardError
          nil
        end

        # --fix（不足分の新規インストール）が使う brew formula 名の対応表。
        # doctor.rb 側にパッケージ名を再列挙せず、この TOOLS を正典とする（spec §4-1）。
        # node は node@20 優先の特例があるため対象外（doctor.rb 側で個別処理）。
        # @param missing [Array<String>] doctor 診断ラベルの不足一覧
        # @return [Array<String>] インストールすべき brew formula 名
        def brew_install_packages(missing)
          TOOLS.select { it.kind == :brew && it.package != 'node' && it.checks.intersect?(missing) }
               .map(&:package)
        end

        # ============================================================
        # 計画の提示と確認（spec §1.1）
        # ============================================================

        KIND_LABELS = { brew: 'brew', cask: 'brew cask', npm: 'npm', gem: 'gem' }.freeze

        def present_plan(plan)
          Common.log_always('📋 更新計画:')
          width = plan.entries.map { it.label.length }.max + 2
          plan.entries.each { Common.log_always("   #{it.label.ljust(width)}#{describe_entry(it)}") }
          return unless plan.entries.any? { it.action == :missing }

          Common.log_always('   ※ 未導入のツールは、更新後の再診断で不足を確認のうえ自動インストールします（--fix 相当）')
        end

        def describe_entry(entry)
          origin = [KIND_LABELS[entry.kind], entry.note].compact.join('・')
          case entry.action
          when :upgrade then "#{(entry.current || '不明').ljust(10)} → #{entry.latest || '最新'}  (#{origin})"
          when :current then "#{entry.current.to_s.ljust(10)} → 変更なし  (#{origin}・最新)"
          when :missing then "未導入（不足していれば再診断で自動導入・#{origin}）"
          when :manual  then "対象外（手動#{entry.note ? "・#{entry.note}" : ''}）"
          end
        end

        # 更新実行の最終確認。--yes で即実行、非対話（パイプ/CI）では安全側に倒して実行しない。
        def confirm_upgrade?(options, deps)
          return true if options[:yes]
          return false unless deps.stdin.tty?

          $stdout.print('更新を実行しますか？ [y/N]: ')
          ans = deps.stdin.gets
          !ans.nil? && ans.strip.downcase == 'y'
        end

        # ============================================================
        # 実行と集計（spec §2.3）
        # ============================================================

        def execute_update(entry, deps)
          Common.log_always("⬆️  #{entry.label} を更新中…")
          ok = run_update_command(entry, deps)
          Common.log_always(ok ? "✅ #{entry.label}: 更新しました" : "❌ #{entry.label}: 更新に失敗しました")
          UpdateResult.new(entry:, ok:)
        end

        def run_update_command(entry, deps)
          case entry
          in { kind: :cask, package: 'inkscape' }
            # 半壊 cask（app 本体欠落）は通常の upgrade が失敗するため --force 再インストールへ
            # フォールバックする（doctor.rb の install_inkscape_macos! と同じ知見）
            deps.run.call('brew upgrade --cask inkscape') ||
              deps.run.call('brew reinstall --cask --force inkscape')
          in { kind: :cask } then deps.run.call("brew upgrade --cask #{entry.package}")
          in { kind: :brew } then deps.run.call("brew upgrade #{entry.package}")
          in { kind: :npm }  then deps.run.call(npm_upgrade_command(entry))
          in { kind: :gem }  then run_gem_command("gem update #{entry.package}", deps)
          end
        rescue StandardError => e
          Common.log_warn("#{entry.label} の更新でエラー: #{e.class}: #{e.message}")
          false
        end

        # Bundler 配下（bundle exec 経由の実行）だと gem サブプロセスが Gemfile に拘束され、
        # Gemfile に無いプラグインを更新できないため、素の環境で実行する
        def run_gem_command(cmd, deps)
          defined?(Bundler) ? Bundler.with_unbundled_env { deps.run.call(cmd) } : deps.run.call(cmd)
        end

        # 版ピン付きパッケージ（例: textlint-rule-no-doubled-conjunction@3.0.0）はピンを維持し、
        # それ以外は @latest を明示して更新する
        def npm_upgrade_command(entry)
          packages = entry.package == :textlint_set ? TEXTLINT_NPM_PACKAGES : [entry.package]
          specs = packages.map { it.match?(/.@/) ? it : "#{it}@latest" }
          "npm install --loglevel=error -g #{specs.map { Shellwords.escape(it) }.join(' ')}"
        end

        # 失敗ツールの手動復旧コマンドをまとめて提示する
        # （warning-messages の方針: 具体的な対処を必ず添える）
        def report_failures(failed)
          return if failed.empty?

          detail = failed.map { "#{it.entry.label}: #{manual_recovery_command(it.entry)}" }.join("\n")
          Common.log_warn('更新に失敗したツールがあります。以下のコマンドで手動更新を試してください:', detail:)
        end

        def manual_recovery_command(entry)
          case entry
          in { kind: :cask, package: 'inkscape' } then 'brew reinstall --cask --force inkscape'
          in { kind: :cask } then "brew upgrade --cask #{entry.package}"
          in { kind: :brew } then "brew upgrade #{entry.package}（解決しない場合は brew doctor で環境を点検）"
          in { kind: :npm }  then npm_upgrade_command(entry)
          in { kind: :gem }  then "gem update #{entry.package}"
          end
        end

        # ============================================================
        # Ruby 本体の新版お知らせ（spec §1.4・検出＋案内のみ）
        # vivlio-starter 本体の更新は UpgradeCommands の自己更新フェーズが担う
        # ============================================================

        # 取得失敗（タイムアウト/不通）は無言でスキップし、終了コードにも影響させない
        # ——お知らせは付加情報であり、ツール更新本体を妨げない
        def announce_new_versions(deps)
          lines = ruby_update_notice(deps)
          return if lines.empty?

          Common.log_always('')
          Common.log_always('📣 お知らせ:')
          lines.each { Common.log_always("   #{it}") }
        end

        # 起動中の Ruby と同一 patch 系列（X.Y.*）の新版があれば、導入経路に合った
        # 更新手順を案内する。マイナー/メジャー更新は gemspec の required_ruby_version との
        # 整合確認を伴うため対象外（リリースノートの責務・spec §1.4）
        # @return [Array<String>] お知らせ行（新版がなければ空）
        def ruby_update_notice(deps, current: RUBY_VERSION, route: nil)
          latest = latest_ruby_patch(deps, current)
          return [] unless latest

          route ||= detect_ruby_route
          heading = if route == :unknown
                      "Ruby #{latest} が公開されています（現在 #{current}）:"
                    else
                      "Ruby #{latest} が公開されています（現在 #{current}）。#{route} 環境の更新手順:"
                    end
          [heading] + ruby_route_lines(route, latest)
        end

        # ruby-lang.org 公式リリースデータから、current と同一 patch 系列の最新版を返す。
        # 新版がない・取得やパースに失敗した場合は nil（無言スキップ）。
        def latest_ruby_patch(deps, current)
          body = deps.fetch.call(RUBY_RELEASES_URL)
          return nil unless body

          series = current.split('.').first(2).join('.')
          top = YAML.safe_load(body, permitted_classes: [Date, Time], aliases: true)
                    .filter_map { it['version'] if it.is_a?(Hash) }
                    .select { it.is_a?(String) && it.start_with?("#{series}.") && Gem::Version.correct?(it) }
                    .map { Gem::Version.new(it) }
                    .reject(&:prerelease?)
                    .max
          top && top > Gem::Version.new(current) ? top.to_s : nil
        rescue StandardError
          nil
        end

        # 起動中の Ruby の導入経路を判別する。which での存在確認ではなく RbConfig の
        # prefix パスを見る——rbenv がインストールされていてもシステム Ruby で動いている
        # ケースを誤案内しないため（spec §1.4）。
        def detect_ruby_route(prefix = RbConfig::CONFIG['prefix'])
          case prefix
          when %r{/\.rbenv/}   then :rbenv
          when %r{/\.rvm/}     then :rvm
          when %r{/\.asdf/}    then :asdf
          when %r{/mise/}      then :mise
          when %r{\A/opt/homebrew/}, %r{\A/usr/local/Cellar/} then :homebrew
          else :unknown
          end
        end

        # 経路別の更新手順。Ruby はバージョンごとに gem 領域が分かれるため、
        # 切替後の gem 再インストール（vs が見つからなくなる事故の予防）を必ず添える
        def ruby_route_lines(route, latest)
          gem_note = '  gem install vivlio-starter   # Ruby 切替後は gem の再インストールが必要です'
          steps = case route
                  when :rbenv then "  brew upgrade ruby-build && rbenv install #{latest} && rbenv global #{latest}"
                  when :rvm   then "  rvm install #{latest} && rvm --default use #{latest}"
                  when :asdf  then "  asdf install ruby #{latest} && asdf global ruby #{latest}"
                  when :mise  then "  mise use --global ruby@#{latest}"
                  when :homebrew then '  brew upgrade ruby'
                  else '  導入経路を判別できませんでした。https://www.ruby-lang.org/ja/downloads/ を参照してください。'
                  end
          [steps, gem_note]
        end

        def latest_gem_version(deps, gem_name)
          body = deps.fetch.call(format(RUBYGEMS_LATEST_URL, gem_name))
          return nil unless body

          version = JSON.parse(body)['version']
          Gem::Version.correct?(version) ? version : nil
        rescue StandardError
          nil
        end

        # ============================================================
        # パーサ・低レベルヘルパー
        # ============================================================

        # JSON をハッシュとして解釈する。空文字列は {}（差分なし）、
        # パース不能は nil（オフライン疑いの信号）を返す
        def parse_json_hash(text)
          stripped = text.to_s.strip
          return {} if stripped.empty?

          data = JSON.parse(stripped)
          data.is_a?(Hash) ? data : nil
        rescue JSON::ParserError
          nil
        end

        # brew outdated --json の出力から { formula名 => [導入版, 最新版] } を作る
        def parse_brew_outdated(text, section)
          data = parse_json_hash(text)
          return {} unless data.is_a?(Hash)

          Array(data[section]).filter_map do |item|
            next unless item.is_a?(Hash) && item['name']

            [item['name'], [Array(item['installed_versions']).last, item['current_version']]]
          end.to_h
        end

        # brew list --versions（"名前 版 [版...]" 形式）から { 名前 => 最新導入版 } を作る
        def parse_brew_versions(text)
          text.to_s.lines.filter_map do |line|
            name, *versions = line.split
            [name, versions.last] if name && !versions.empty?
          end.to_h
        end

        # npm ls -g --depth=0 --json から { パッケージ名 => 版 } を作る
        def parse_npm_versions(text)
          data = parse_json_hash(text)
          return {} unless data.is_a?(Hash)

          (data['dependencies'] || {}).filter_map do |name, info|
            [name, info['version']] if info.is_a?(Hash) && info['version']
          end.to_h
        end

        # 版ピン付き npm 指定（pkg@3.0.0）からパッケージ名部分を取り出す。
        # スコープ付き（@vivliostyle/cli）は先頭 @ が区切りではないためそのまま返す
        def npm_base_name(spec) = spec.start_with?('@') ? spec : spec.split('@').first

        # タイムアウト 2 秒の HTTP GET。失敗はすべて nil（お知らせ系は無言スキップ・spec §2.2）
        def http_get(url, timeout: 2)
          uri = URI.parse(url)
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = uri.scheme == 'https'
          http.open_timeout = timeout
          http.read_timeout = timeout
          response = http.get(uri.request_uri)
          response.is_a?(Net::HTTPSuccess) ? response.body : nil
        rescue StandardError
          nil
        end
      end
    end
  end
end
