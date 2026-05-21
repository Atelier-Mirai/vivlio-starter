# Vivlio Starter 堅牢性テスト

このディレクトリには、`docs/specs/vivlio_starter_robustness_test_spec.md` の
**🔴 High priority かつ 🆕 未ガード（もしくは第一段階で実装済みの対応）** 項目を
Minitest として実装した回帰テストを配置します。

通常のユニットテスト（`test/vivlio_starter/cli/**` 配下）とは目的が異なり、
「想定外の入力・環境・操作に対して Vivlio Starter がどう振る舞うか」を検証する
**ロバストネステスト** として独立管理します。

## 実行方法

```sh
# このディレクトリ配下のみ実行
bundle exec rake test TEST='test/vivlio_starter/robustness/**/*_test.rb'

# 個別テスト
bundle exec ruby -Ilib -Itest test/vivlio_starter/robustness/<filename>_test.rb
```

環境依存テスト（書き込み権限・外部コマンド不在・シグナル送信など）は
`skip` を用いて CI 環境で安全にスキップされるよう実装しています。

## テスト一覧

| 仕様書 # | テストファイル | 検証内容 | ステータス |
|:---|:---|:---|:---:|
| [1-2-1](../../../../docs/specs/vivlio_starter_robustness_test_spec.md#L68) | `catalog_missing_file_test.rb` | `catalog.yml` に登録済みだが `contents/` にファイルがない場合、`Entry.exists=false` として扱われ、build は警告のみで全体は成功する | ✅ |
| [1-3-1](../../../../docs/specs/vivlio_starter_robustness_test_spec.md#L77) | `readonly_project_root_test.rb` | プロジェクトルートへの書き込み権限がない場合、`Errno::EACCES` が自然送出され、ユーザーが原因特定可能 | ✅ |
| [2-3-4](../../../../docs/specs/vivlio_starter_robustness_test_spec.md#L116) | `malicious_image_path_test.rb` | 画像パスに `../../etc/passwd` 等のパストラバーサルが含まれる場合、Markdown としては単に「画像が無い」扱いになり、外部プロセスは起動しない | ✅ |
| [3-1-8](../../../../docs/specs/vivlio_starter_robustness_test_spec.md#L146) | `vs_new_interrupt_test.rb` | `vs new` でプロンプト途中に Ctrl+C を送ったとき、中途半端な `プロジェクト名/` ディレクトリが残留しないこと（`expand_scaffold` の `ensure` クリーンアップ） | ✅ |
| [3-2-1](../../../../docs/specs/vivlio_starter_robustness_test_spec.md#L155) | `yaml_placeholder_escape_test.rb` | 著者名に `'`（シングルクォート）を含めても `book.yml` が壊れず、`YAML.safe_load` に成功する（`yaml_escape_double_quoted` ヘルパー） | ✅ |
| [3-2-2](../../../../docs/specs/vivlio_starter_robustness_test_spec.md#L156) | `yaml_placeholder_escape_test.rb` | 著者名に改行（ペースト事故）が含まれても `book.yml` が壊れず、`YAML.safe_load` に成功する | ✅ |
| [4-1-1](../../../../docs/specs/vivlio_starter_robustness_test_spec.md#L176) | `missing_external_command_test.rb` | `vivliostyle` コマンド不在時、`Common.ensure_external_command!` 経由で `vs doctor --fix を実行してください` と案内される | ✅ |
| [4-1-2](../../../../docs/specs/vivlio_starter_robustness_test_spec.md#L177) | `missing_external_command_test.rb` | `inkscape` 不在でカバー生成時、明示的エラー + `vs doctor` 案内が出る | ✅ |
| [4-1-3](../../../../docs/specs/vivlio_starter_robustness_test_spec.md#L178) | `missing_external_command_test.rb` | `imagemagick` 不在時、明示的エラー + `vs doctor` 案内が出る | ✅ |
| [4-3-1](../../../../docs/specs/vivlio_starter_robustness_test_spec.md#L201) | `build/build_lock_test.rb` | 同一プロジェクトで `vs build` を並列実行すると `BuildLock::AlreadyLockedError` により 2 本目以降が即座にエラー終了する | ✅ |
| [4-3-2](../../../../docs/specs/vivlio_starter_robustness_test_spec.md#L202) | `interrupt_handling_test.rb` | ビルド中に `Interrupt` が伝播した場合、スタックトレースではなく `⚠️ 処理が中断されました（Ctrl+C）` が出力され、終了コード 130 で終わる | ✅ |
| [5-6-2](../../../../docs/specs/vivlio_starter_robustness_test_spec.md#L231) | `lint_fix_interrupt_test.rb` | `vs lint --fix` 中に中断されても、原稿ファイルが `textlint-disable` 表記で破壊されない（`Tempfile` ベースの非破壊設計） | ✅ |
| [7-1](../../../../docs/specs/vivlio_starter_robustness_test_spec.md#L263) | `invalid_svg_test.rb` | 不正な SVG XML を `rsvg-convert` / ImageMagick に渡したとき、`Common.run_svg_converter!` が整形済みエラーメッセージをログ出力する | ✅ |
| [8-1](../../../../docs/specs/vivlio_starter_robustness_test_spec.md#L275) | `interrupt_handling_test.rb` | SIGINT 受信時に `⚠️ 処理が中断されました` を表示し、終了コード 130（128+SIGINT）で終わる | ✅ |
| [8-2](../../../../docs/specs/vivlio_starter_robustness_test_spec.md#L276) | `interrupt_handling_test.rb` | SIGTERM 受信時に `⚠️ 処理が中断されました` を表示し、終了コード 143（128+SIGTERM）で終わる | ✅ |
| [9-7](../../../../docs/specs/vivlio_starter_robustness_test_spec.md#L289) | `catalog_yaml_safety_test.rb` | `catalog.yml` の `!ruby/object` 等のタグを `Psych::DisallowedClass` として拒否し、人間向けメッセージに変換する | ✅ |
| [11-1](../../../../docs/specs/vivlio_starter_robustness_test_spec.md#L306) | `dangerous_scheme_detection_test.rb` | 原稿内の `<img src="file:///etc/passwd">` / `javascript:` スキームを `LinkImageValidator.scan_dangerous_schemes` で検出し警告（`--no-verify` でも常時有効） | ✅ |
| [11-2](../../../../docs/specs/vivlio_starter_robustness_test_spec.md#L307) | `data_render_yaml_safety_test.rb` | `data/*.yml` の `!ruby/object` タグを `QueryStream::DataLoadError` に変換して通知（query-stream 1.2.1 以降の `safe_load_file`） | ✅ |

**凡例**:
- ✅ 実装とテストの両方が完了済み（1.0.0-alpha リリース時点）

1.0.0-alpha リリース時点で � 高優先度 18 項目すべて（4-3-1 の `build/` サブディレクトリ含む）を回帰テスト化完了。

## ガイドライン

1. **純粋なユニットテストは `test/vivlio_starter/cli/**` に置く**
   `robustness/` は「想定外」「攻撃的入力」「環境欠落」に特化する。
2. **環境依存は `skip` でフォールバック**
   root 権限やコマンド削除が必要なケースは、状況を満たさないなら明確なメッセージ付きで `skip`。
3. **prod コードに副作用を残さない**
   一時ディレクトリ (`Dir.mktmpdir`)、`ENV` 一時書き換え、`$stdout`/`$stderr` の退避を徹底。
4. **仕様書とテストを両方向リンク**
   各テストの冒頭コメントに仕様書の行番号（`docs/specs/vivlio_starter_robustness_test_spec.md:<line>`）を記載し、
   仕様書の表にも該当テストファイル名を追記していく（次フェーズ以降の運用）。
