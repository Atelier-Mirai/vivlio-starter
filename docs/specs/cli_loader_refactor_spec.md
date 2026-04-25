# CLI ロード構造・ヘルプ周辺 リファクタリング 仕様書

**対象バージョン**: Vivlio Starter v0.38.0（予定）〜 1.0.0 リリース準備  
**作成日**: 2026-04-11（**改訂**: 2026-04-11）  
**優先度**: Medium  
**関連**: `CHANGELOG.md`（CLI ロード構造のリファクタリング Planned 項）

---

## 1. 概要

本仕様は、リリース前に実施する **CLI の require 構造の整理**、**デッドコード化した `help.rb` の削除**、**`new` 実装の配置の統一** を対象とする。

**方針（前提）**

- **後方互換性は求めない**（未リリースのため）。旧 `require` パスや旧名前空間を維持するための **薄いラッパーは設けない**。呼び出し元・テストは **正規のパスへ追従して修正** する。
- **コマンド一覧データの専用ファイル（`command_catalog.rb` 等）は新設しない**（現時点では `HelpCommand` が唯一の利用者のため）。一覧は `help_command.rb` 内の定数（現行の `COMMAND_CATEGORIES` 等）に **単一化** する。将来、ヘルプ以外からも同じ一覧が必要になった段階で、ファイル分割を検討すればよい。

目的は次のとおりである。

- **責務の分離**: エントリポイント（`CLI.start`）、Samovar コマンドのロード、ドメイン実装（build / pre_process 等）の一括ロードを、読み手が追いやすい単位に分割する。
- **ヘルプの単一化**: `cli/help.rb`（`HelpCommands`）を **削除** し、チートシートの内容は **`samovar/help_command.rb` にのみ** 存在させる（重複定義の解消）。
- **実行経路の統一**: `bin/vs` と `bin/vivlio-starter` が **同一の `CLI.start` 実装**（同一の例外処理を含む）を参照する（§2.6）。
- **`new` の配置統一**: `lib/vivlio/starter/commands/new.rb` を廃止し、**`build` と同型の `cli/` 傘下配置**に集約する（§3.5）。

---

## 2. 現状の実装（調査結果）

### 2.1 エントリポイントと `CLI.start` の二重定義

| 経路 | 読み込み | `CLI.start` の定義元 | 備考 |
|---|---|---|---|
| `bin/vs` | `require 'vivlio/starter/cli'` | `lib/vivlio/starter/cli.rb` | `RootCommand.parse` → `command.call`。`Samovar::InvalidInputError` を捕捉し `--help` 相当を表示。 |
| `bin/vivlio-starter` | `require 'vivlio/starter'` | `lib/vivlio/starter.rb` 内の `Vivlio::Starter::CLI` | `RootCommand.call` のみ。`InvalidInputError` 用のハンドラなし。 |

`lib/vivlio/starter/cli.rb` は `Vivlio::Starter::CLI` を **定義** し、`lib/vivlio/starter.rb` は同名モジュールを **再オープンして `start` を上書き** する。`require` 順によって **最後に読み込まれた `start` が有効** になり、挙動が依存しうる。

### 2.2 `lib/vivlio/starter/cli.rb` の責務混在

`cli.rb` は、ドメイン実装の連結 require、`cli/samovar`、`CLI.start` / `print_usage_for_invalid_input` を **1 ファイルに集約** している。整理後は §3.1 の **正式ファイル名** に分割する。

### 2.3 `lib/vivlio/starter/cli/help.rb`（`HelpCommands`）

- `HelpCommands::HELP_MESSAGE` / `print_help` は **他の Ruby コードから参照されていない**。
- 実際の表示は `lib/vivlio/starter/cli/samovar/help_command.rb` の `HelpCommand` が担当。
- `COMMAND_CATEGORIES` と `HELP_MESSAGE` は **同型の重複**。

**対応**: ファイル **削除**。`samovar.rb` の `require_relative 'help'` も **削除**。

### 2.4 `lib/vivlio/starter/commands/new.rb`

`lib/vivlio/starter.rb` が `vivlio/starter/commands/new` を読み込むが、**`vs new` のルーティングは `SamovarCommands::NewCommand`** である。`Vivlio::Starter::Commands::New` は CLI 本体と **別ディレクトリ・別名前空間** に置かれており、配置が他コマンドと揃っていない。

**対応**: §3.5 のとおり `cli/` 傘下へ統合し、`commands/` 階層は廃止する。

### 2.6 二つのバイナリ: `bin/vivlio-starter` と `bin/vs`

**両方とも残す**（役割が異なるため）。

| バイナリ | 役割 |
|---|---|
| `bin/vivlio-starter` | **RubyGems の正式名と一致**する executable。`gemspec` の `executables` に列挙され、`gem install` 利用者が期待するエントリ。 |
| `bin/vs` | **ユーザー向けの主コマンド**。ドキュメント・マニュアルが `vs build` 等の形で記述されているため、削除しない。 |

**現状の差分（リファクタで解消する対象）**

1. **終了コード**: `bin/vivlio-starter` は `exit Vivlio::Starter::CLI.start(ARGV)` だが、`bin/vs` は戻り値のみで **プロセスの exit ステータスがシェルに伝わらない** 可能性がある。  
2. **`require` 先**: §2.1 のとおり、`start` の実装が経路ごとに食い違いうる。

**リファクタ後の理想形**

- 両バイナリとも **`require 'vivlio/starter/cli/startup'`**（§3.1 の **正式名**）を経由し、**同一の `Vivlio::Starter::CLI.start` 実装**を使う。  
- 両方とも **`exit Vivlio::Starter::CLI.start(ARGV)`** で終了コードを統一する。  
- **`bin/vs` 先頭の警告抑制・re-exec ロジック**は `vs` 固有のため **そのまま残す**（`bin/vivlio-starter` には不要）。

これにより §2.1 の問題は解消する。Phase 1 はこの形を直接のゴールとする。

---

## 3. 目標アーキテクチャ

### 3.1 責務の分割と **正式ファイル名**（仮称を持ち越さない）

本仕様で採用する **正式名称** は次のとおり。実装・ドキュメント・DoD はこれに合わせる。

| 層 | 責務 | **正式パス** |
|---|---|---|
| **Startup** | `CLI.start(argv)`、終了コード、`Samovar::InvalidInputError` 等、`ENV['VS_DEBUG']` に応じたバックトレース | **`lib/vivlio/starter/cli/startup.rb`** |
| **Loader** | CLI 全機能利用時の require 順（ドメイン → samovar）。`cli.rb` はこれを `require_relative` するだけにできる。 | **`lib/vivlio/starter/cli/loader.rb`** |
| **Samovar 集約** | `samovar` gem、各 `*_command.rb`、`SamovarCommands` | `lib/vivlio/starter/cli/samovar.rb` |

**命名の経緯**: 当初案だった `launcher.rb` / `all.rb` のうち、本仕様では **`startup.rb`**（起動処理の意図が明確）と **`loader.rb`**（ロード責務が一語で伝わる）を正式名称とする。

`cli.rb` は **正規の「ライブラリからフル CLI を読む」エントリ**として、`startup.rb` と `loader.rb` を読み込み、**極力薄く** 留める（互換用の二重ファイルは作らない）。

### 3.2 ヘルプ文言の単一化（`command_catalog` は置かない）

- **単一ソース**: `HelpCommand` 内の定数（現行の `COMMAND_CATEGORIES` およびヘッダー／フッター文字列）を **正** とする。
- **`lib/vivlio/starter/cli/help.rb`**: **削除**（デッドコードのため）。
- **将来**: 一覧をヘルプ以外からも参照する必要が出たとき初めて、共通モジュールやファイル分割を検討する。現仕様では **新規ファイルは追加しない**。

### 3.3 `vivlio/starter.rb` と `CLI.start` の一本化

- `Vivlio::Starter::CLI.start` の実装は **1 箇所のみ**（`startup.rb`）。
- `lib/vivlio/starter.rb` は **`CLI` モジュールを再オープンして `start` を上書きしない**。`startup`（および gem エントリに必要な最小の `require`）により一度だけ定義される。
- **`bin/vivlio-starter` と `bin/vs` は §2.6** のとおり同一 `startup` を経由する。

### 3.4 `samovar.rb` の整理

- `require_relative 'help'` を **削除** する。
- Samovar コマンドが実際に参照する依存のみを残す。

### 3.5 `new` 実装の `cli/` 傘下への統合（**配置の決定**）

他コマンドとの **既存パターン**（`build` を代表例とする）:

- **Samovar 層**: `lib/vivlio/starter/cli/samovar/build_command.rb` — サブコマンドのエントリ・オプション定義。
- **ドメイン層**: `lib/vivlio/starter/cli/build.rb` および `lib/vivlio/starter/cli/build/*.rb` — 処理本体。

`new` についても **同型** とする。

| 役割 | **正式パス（本仕様の決定）** |
|---|---|
| Samovar コマンド（`vs new` のエントリ） | **`lib/vivlio/starter/cli/samovar/new_command.rb`**（既存を維持・必要なら整理のみ） |
| ドメイン実装（雛形生成・対話等の処理本体） | 第一候補: **`lib/vivlio/starter/cli/new.rb`** の **`Vivlio::Starter::CLI::NewCommands`**（**既存ファイル**）。`commands/new.rb` にのみ存在していたロジックはここへ **統合** する。 |
| 行数増大時の分割 | **`lib/vivlio/starter/cli/new/*.rb`** を追加し、`cli/new.rb` が `require_relative 'new/...'` で読み込む（`cli/build/` と同じ分割パターン）。 |

**廃止するもの**

- **`lib/vivlio/starter/commands/new.rb`** および **`Vivlio::Starter::Commands::New`** 名前空間。
- 空になった **`lib/vivlio/starter/commands/`** ディレクトリ。

**DoD での判定**: `commands/` がリポジトリに存在しないこと、`grep` で `Vivlio::Starter::Commands::New` が残っていないこと、`NewCommand` が **`CLI::NewCommands`（および必要なら `cli/new/` 配下）のみ** を参照していること。

---

## 4. 破壊的変更と非目標

### 4.1 許容する破壊的変更

- `require` パス・ファイル配置の変更（**旧パスへの薄いラッパーは置かない**）。
- `Vivlio::Starter::Commands::*` の削除または名前空間変更（`new` 統合に伴う）。
- テスト・内部スクリプトの `require` の **一括更新**。

### 4.2 非目標（本仕様では必須としない）

- 全ファイルへの `autoload` 化（採用する場合は別仕様で理由とスレッドセーフ方針を明記する）。
- CLI のユーザー向け文言の意図的な変更（移設は **機械的な同一内容の維持** を原則とする）。
- **`bin/vs` または `bin/vivlio-starter` のどちらか一方の削除**（§2.6）。

---

## 5. 実装フェーズ（推奨順序）

### Phase 1: `CLI.start` の単一化と二バイナリの揃え

1. `lib/vivlio/starter/cli/startup.rb` を実装し、`start` / `print_usage_for_invalid_input` を集約する。  
2. `lib/vivlio/starter.rb` から `CLI.start` の重複定義をなくす。  
3. **`bin/vivlio-starter` と `bin/vs` の双方**で `require 'vivlio/starter/cli/startup'` と **`exit Vivlio::Starter::CLI.start(ARGV)`** を満たす（`vs` の re-exec・警告抑制ブロックは維持）。  
4. テストの `require` 順・二重定義依存を解消する（`help_behavior_test.rb` / `help_spec_test.rb` 等）。

### Phase 2: `help.rb` 削除と Samovar 整理

1. `HelpCommand` 内の定数のみを単一ソースとし、`cli/help.rb` を **削除**。  
2. `samovar.rb` から `require_relative 'help'` を **削除**。  
3. `vs --help` / `vs help` の出力が意図せず変わっていないことを確認する。

### Phase 3: `commands/new.rb` の廃止と `cli/` への統合

1. `Vivlio::Starter::Commands::New` の処理を **`CLI::NewCommands`（`cli/new.rb`）に統合**し、`commands/new.rb` を削除する。  
2. `SamovarCommands::NewCommand` の参照先を更新する。  
3. `lib/vivlio/starter.rb` の `require 'vivlio/starter/commands/new'` および誤ったコメントを削除または修正する。  
4. 必要に応じ `cli/new/` へ分割する（§3.5）。

### Phase 4: require 構造の整理

1. ドメイン require を **`lib/vivlio/starter/cli/loader.rb`** に集約し、`cli.rb` を薄く保つ。  
2. 開発者向けドキュメント（例: `contents/80-developer.md`、`lib/project_scaffold/contents/80-developer.md`）の **旧記述を本仕様に合わせて更新** する。

---

## 6. テスト方針

| 観点 | 内容 |
|---|---|
| エントリ | `vivlio/starter` のみ、`vivlio/starter/cli` のみ、いずれでも **`CLI.start` が同一実装** であること |
| 未知オプション | `Samovar::InvalidInputError` 時に `print_usage` が呼ばれ、終了コードが仕様どおりであること |
| ヘルプ | `vs --help`、`vs help`、代表サブコマンドの `--help` が移設前と同等であること |
| `new` | `vs new` および `NewCommands` のテストが通ること |
| 回帰 | `samovar_smoke_test.rb`、build / doctor 等でロードエラーが出ないこと |
| **全体** | **`bundle exec rake test`（またはプロジェクト標準の `rake test`）がエラー・失敗なく完了すること**（§8）。 |

---

## 7. リスクと緩和

| リスク | 緩和 |
|---|---|
| `CLI.start` の上書き順に依存したテスト | Phase 1 で単一定義にし、テストの `require` を明示的に修正 |
| `Commands::New` の隠れた参照 | 移設前にリポジトリ全体を grepし、参照を洗い出す |
| 文言の空白差 | 移設前後でヘルプ出力を diff する |

---

## 8. 完了条件（Definition of Done）

- **`bundle exec rake test`（リポジトリで定義されている標準テストタスク）が、エラー・失敗なくすべてグリーンであること。**  
- `lib/vivlio/starter/cli/help.rb` が **存在しない**（`HelpCommands` 削除済み）。  
- `samovar.rb` に `require_relative 'help'` が **ない**。  
- コマンド一覧のデータは **`help_command.rb` にのみ** 存在する（重複なし）。  
- `Vivlio::Starter::CLI.start` の実装が **`startup.rb` に 1 箇所** にあり、`bin/vs` と `bin/vivlio-starter` が **§2.6** のとおり同一経路・`exit` 方針で動作する。  
- `lib/vivlio/starter/commands/` が **存在しない**（`new` は §3.5 の配置どおり `cli/` 傘下のみ）。  
- `Vivlio::Starter::Commands::New` がコードベースに **残っていない**。  
- 旧 `require` パス用の **薄いラッパーファイルを増やしていない**。  
- `CHANGELOG.md` の Planned 項を Resolved または該当リリースノートへ移行できる。

---

## 9. 参考ファイル一覧

| パス | 役割（改訂前の状態） |
|---|---|
| `bin/vs` | `vivlio/starter/cli` 読み込み（Phase 1 以降は `cli/startup` + `exit` 統一） |
| `bin/vivlio-starter` | `vivlio/starter` 読み込み（Phase 1 以降は `cli/startup` に揃える） |
| `lib/vivlio/starter.rb` | gem エントリ、`CLI.start` の重複定義あり |
| `lib/vivlio/starter/cli.rb` | フル require + `CLI.start` |
| **`lib/vivlio/starter/cli/startup.rb`** | **新設（正式名）** — `CLI.start` 単一定義 |
| **`lib/vivlio/starter/cli/loader.rb`** | **新設（正式名）** — ドメイン〜samovar の一括 require |
| `lib/vivlio/starter/cli/samovar.rb` | Samovar 集約（`help` require あり） |
| `lib/vivlio/starter/cli/samovar/root_command.rb` | ルーティング |
| `lib/vivlio/starter/cli/samovar/help_command.rb` | チートシート表示（単一ソース化の正） |
| `lib/vivlio/starter/cli/samovar/new_command.rb` | `vs new`（Samovar 層） |
| `lib/vivlio/starter/cli/new.rb` | `NewCommands`（ドメイン層・統合先） |
| `lib/vivlio/starter/cli/help.rb` | **削除対象**（デッドコード） |
| `lib/vivlio/starter/commands/new.rb` | **削除対象**（`cli` へ統合） |
| `test/vivlio/starter/cli/help_behavior_test.rb` | エントリ挙動のテスト |
