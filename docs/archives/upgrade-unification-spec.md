# vs upgrade 統合仕様（本体 gem・雛形・外部ツールの一括最新化）

- 状態: 実装済み（2026-07-17）
- 前提仕様: [project-upgrade-command-spec.md](project-upgrade-command-spec.md)（雛形追従）・[doctor-tool-upgrade-spec.md](doctor-tool-upgrade-spec.md)（ツール更新）

## 0. 背景と動機

雛形追従の `vs upgrade` とツール更新の `vs doctor --upgrade` を別コマンドとして
設計した結果、環境を完全に最新化する手順が三段構え
（① `gem update vivlio-starter` → ② `vs upgrade` → ③ `vs doctor --upgrade`）になり、
利用者がこの順序を覚えて実行する必要があった。実利用で「ツール更新の前に
本体更新と雛形追従を先にやってください」と案内される二度手間が発生したため、
`vs upgrade` 1 コマンドへ統合する（`vs doctor --upgrade` は未リリースだったため
互換考慮なしで廃止し、doctor は診断＋ `--fix` に純化）。

## 1. 要求仕様

### 1.1 三段構成と実行順

`vs upgrade` は次の 3 フェーズを順に実行する。

| フェーズ | 内容 | 実装 |
|---|---|---|
| ① 本体 gem 更新 | 新版検出 → 確認 → `gem update` → 新版で exec 再起動 | `UpgradeCommands.self_update!` |
| ② 雛形追従 | 三者比較による 追加/更新/競合/保持 の計画と適用 | `UpgradeCommands.sync_scaffold!`（従来の run_from_command 本体） |
| ③ 外部ツール更新 | 計画提示 → 確認 → 一括更新 → 再診断 | `DoctorCommands::ToolUpgrader.run!` |

順序の理由:

- **①が最初**: 古い gem の雛形で②を済ませると、本体更新後にもう一度 upgrade が
  必要になる（二度手間の再生産）。①の更新が走った場合は exec で新しい版に
  置き換わるため、②③は必ず新しい版の vs が実行する。
- **②が③より先**: 対話（競合の y/n/d 確認）を前半へ集め、時間のかかる
  brew/npm 更新を無人で流せるようにする。③の再診断（--fix 委譲の設定ファイル
  復元）が同期済みプロジェクトを見られる副次効果もある。

### 1.2 自己更新（フェーズ①）

- RubyGems API で最新版を取得（タイムアウト 2 秒・失敗は無言スキップ）。
- 新版があれば確認プロンプト（`--yes` でスキップ）。非対話（tty でない）かつ
  `--yes` なしでは**安全側に倒して更新せず**、手動コマンドを案内して続行。
- `gem update vivlio-starter` は Bundler 非拘束（`with_unbundled_env`）で実行。
- 成功したら `exec $0 upgrade --skip-self-update [--yes]` で新版へ引き継ぐ。
  `--skip-self-update` は**再帰防止と更新オプトアウトを兼ねる**公開オプション。
- 失敗は警告して現在の版のまま続行（②③の価値は残る）。gem update は旧版を
  残すため、失敗しても実行中プロセス・次回起動とも壊れない——旧仕様
  （doctor-tool-upgrade-spec §1.4）が自己更新を避けた「失敗時に復旧を案内する
  主体が失われる」懸念はこの性質で緩和されると判断した。
- `--dry-run` は新版の案内のみ（更新しない）。

### 1.3 フェーズのスキップ規則（部分実行）

| 状況 | 動作 |
|---|---|
| `--skip-self-update` | ①をスキップ |
| プロジェクト外（`config/book.yml` なし） | ②だけスキップ（①③は実行）。従来の ProjectRootCheck ガードは撤去 |
| 非 macOS / Homebrew 不在 | ③だけスキップ（警告・終了コード 0。旧仕様のエラー終了から変更——他フェーズを巻き添えにしない） |
| オフライン（brew update / npm outdated 失敗） | ③を中断（終了コード 1）。①は無言スキップ、②はネットワーク不要のため実行される |

終了コードは各フェーズの最悪値（①失敗=1・②の従来コード・③の従来コード の max）。

### 1.4 vs doctor の純化

- `--upgrade` オプションは削除（未リリースのため互換措置なし）。
- doctor は「診断＋不足分の導入（`--fix`）」専任。ヘルプ・原稿 51 章・README は
  `vs upgrade` への参照に置き換え。
- `ToolUpgrader::TOOLS` を `--fix` のインストール処理と共用する構造
  （doctor-tool-upgrade-spec §4-1）は不変。
- ToolUpgrader の「📣 お知らせ」から vivlio-starter 本体の新版通知を除去
  （①が実更新として担うため）。Ruby 本体の新版案内は従来どおり残す。

## 2. テスト

- `test/vivlio_starter/cli/upgrade_commands_test.rb`: 三段オーケストレーション
  （自己更新の :none/:skipped/:failed/relaunch 分岐・プロジェクト外スキップ・
  終了コード伝搬）。ネットワーク・外部コマンドは `tool_deps`（Deps DI）で遮断。
- `test/vivlio_starter/cli/doctor/tool_upgrader_test.rb`: 旧仕様のテスト項目 1〜6 に
  加え、非 macOS スキップ（終了コード 0）と `--dry-run`（計画のみ・再診断なし）。
