# lint コマンド TokenResolver 対応仕様書

---

## 1. 目的

- `vs lint` が他コマンドと同一の章指定解釈ロジック（TokenResolver）を利用し、章番号・スラッグ・範囲指定・システムファイルを一元的に扱えるようにする。
- 章番号の曖昧入力（ゼロ埋め/ハイフン/カンマ区切りなど）を TokenResolver に委譲し、既存の独自実装を廃止する。
- lint のターゲット解決結果を TokenResolver::Entry ベースに置き換えることで将来的な機能追加（catalog.yml 準拠の並び順、システムファイル lint 等）に備える。

## 2. 背景

- TokenResolver は `build` / `create` / `delete` / `rename` / `renumber` / `metrics` が既に利用しており、章指定 UI/UX を統一している。
- `lint` のみ `TargetResolver` クラス（@lib/vivlio/starter/cli/lint.rb#317-408）が独自で数値レンジ展開・ファイル探索を行っており、以下の課題がある:
  - ゼロ埋めや降順レンジなど TokenResolver が担保する仕様が未反映。
  - catalog.yml に存在しない章指定時の振る舞いが他コマンドと異なる。
  - Resolver ロジックが重複し保守コストが高い。

## 3. 対象範囲

- `lib/vivlio/starter/cli/lint.rb` 内 `TargetResolver` の置換。
- `LintCommands.execute_lint` から `TargetResolver#resolve` の呼び出し部分。
- `docs/specs/cli_token_resolver_spec.md` に準拠した挙動確認。
- 付随するテスト（存在する場合は更新／なければ追加）。
- CLI オプション・ヘルプ文言に変更は不要（挙動のみ統一）。

## 4. 現行仕様の整理

| コマンド | TokenResolver 利用状況 | 備考 |
| --- | --- | --- |
| `vs create` | 使用 (@lib/vivlio/starter/cli/create.rb#52-90) | 章生成前に Entry 化し重複チェック |
| `vs delete` | 使用 (@lib/vivlio/starter/cli/delete.rb#153-187) | Entry から Markdown/画像ディレクトリ削除 |
| `vs rename` / `renumber` | 使用 (@lib/vivlio/starter/cli/rename.rb#292-399) | 旧新トークンを Entry 化 |
| `vs metrics` | 使用 (@lib/vivlio/starter/cli/metrics.rb#102-150) | Entry→path で統計対象抽出 |
| `vs build` | 使用 (@lib/vivlio/starter/cli/build/utilities.rb#100-122) | keep/entries の解決で利用 |
| `vs lint` | **未使用** (@lib/vivlio/starter/cli/lint.rb#317-408) | 独自 TargetResolver |

## 5. 要件

1. `vs lint` の章指定引数は TokenResolver::Resolver を使用して解決する（仕様書 7.1「Normalization」と完全整合）。
2. TokenResolver の `Entry` が提供する述語（`valid?`, `exists?`, `in_catalog?`）を利用し、ファイル存在チェックやバリデーションを行う。
3. lint 対象は `Entry#path` が `contents/` 配下にある Markdown (`*.md`) かつ `exists?` が真のものに限定する。
4. 引数未指定時は `resolver.resolve([])` により catalog.yml に存在する全章を対象にし、欠落ファイルは warn してスキップする。
5. 解決不能（invalid）の Entry が含まれていれば lint 実行前にエラー終了し、原因メッセージを出力する。
6. 既存の `TargetResolver` によるドメイン固有メッセージ（例: `見つかりません`）は TokenResolver 版でも維持する。

## 6. 仕様詳細

### 6.1 新 TargetResolver

- `TokenResolver::Resolver` を内部に保持し、`resolve_targets`（仮称）で Entry 配列を取得。
- 返却値: 既存通り、プロジェクトルートからの相対 Markdown パスの配列。
- 処理フロー：
  1. `entries = resolver.resolve(raw_targets)`
  2. `invalid_entries = entries.reject(&:valid?)` → 存在時は `Common.log_error` で一覧表示し `exit 1`。
  3. `paths = entries.map(&:path)`
  4. `existing, missing = paths.partition { File.exist?(it) }`
  5. missing を `Common.log_warn("見つかりません: #{path}")` で通知。
  6. existing を `Pathname` で相対化し、ソートして返却。

### 6.2 章指定なしの扱い

- `raw_targets.empty?` の場合、TokenResolver に空配列を渡し catalog 全章 Entry を取得。
- 章ファイルが欠落している場合は `missing` 配列として警告し、他ファイルは lint 継続。

### 6.3 範囲指定

- TokenResolver が担うため、`TargetResolver` 側での `range_pattern?` 等は削除。
- TokenResolver は降順レンジ、カンマ区切り、`contents/` プレフィクス除去など既存 lint 独自仕様を superset でカバーする。

### 6.4 システムファイル

- lint の対象外。TokenResolver が返すシステム Entry（`number: nil`, `slug: _toc` 等）は `Entry#number.nil?` や `entry.path.start_with?(Common::CACHE_DIR)` を条件に除外する。

### 6.5 エラーハンドリング

- `invalid_entries` が存在する場合は lint を実行せず終了コード 1。
- `entries.empty?` になった場合（例: すべて missing）は `Common.log_warn('対象ファイルがありません')` を出して終了コード 0 とする（現行挙動に合わせる）。

### 6.6 contents/ 配下限定フィルタ

- TokenResolver 内部設計 (docs/design/cli_token_resolver_internal.md) の「コマンド別フィルタ条件」に基づき、lint 専用のフィルタを定義する。
- 実装案：
  1. `entries = resolver.resolve(raw_targets)`
  2. `content_entries = entries.select { |e| e.exists? && e.path.start_with?(Common::CONTENTS_DIR) }`
  3. `missing = entries.select { |e| e.path.start_with?(Common::CONTENTS_DIR) && !e.exists? }`
  4. `Common.log_warn("見つかりません: #{path}")` を missing に対して実行。
- これにより、TokenResolver が返す `_toc` などシステム Entry は自動的に範囲外となり、利用者原稿のみを lint できる。

## 7. 実装方針

1. `TargetResolver` を TokenResolver ベースに書き換える。
   - `initialize(raw_targets)` にて `@resolver = TokenResolver::Resolver.new`。
   - 新メソッド `resolve_entries` / `resolve_existing_paths` を追加。
2. `resolve` メソッドは TokenResolver 結果を path に変換して返却する API として維持。
3. 既存の正規表現ヘルパーは削除。
4. 共通ログメッセージ（`Common.log_warn("見つかりません: ...")`）を TokenResolver 版に移植。
5. 既存 spec/test を追加・更新：
   - TokenResolver を利用した lint ターゲット解決の単体テストを `test/vivlio/starter/cli/lint_target_resolver_test.rb` などに追加し、`vs lint 1-3` がゼロ埋めされること、`vs lint contents/01-life.md` が解決されること等を検証。

## 8. 移行ステップ

1. 既存 `TargetResolver` 実装のバックアップとしてコメントまたは Git 履歴で参照できる状態を保持（コード上には残さない）。
2. 新実装に置き換え後、`bundle exec ruby -Itest test/vivlio/starter/cli/lint_*` 等で回帰確認。
3. `docs/specs/cli_token_resolver_spec.md` に lint を TokenResolver 対応済みコマンドとして追記（別タスクでも可）。
4. CHANGELOG への記載: 「lint コマンドの章指定解釈を TokenResolver に統一」。

## 9. 検証項目

- [ ] `vs lint 1-foo` が `01-foo` に正規化され、存在しないファイルなら警告のみ。
- [ ] `vs lint 1-3,5` が catalog.yml の登録順で展開される。
- [ ] lint 対象は `contents/` 配下の利用者原稿 (`*.md`) に限定されること。
- [ ] エラー: `vs lint foo` で invalid トークンを検出し終了コード 1。
- [ ] 引数なしで catalog.yml の全章が lint 対象になる。
- [ ] metrics 等他コマンドと同一 Resolver 実装であることをコードレビューで確認。

## 10. 影響範囲とリスク

- TokenResolver に依存するため、catalog.yml の欠落や破損時に lint も同様の失敗モードとなる（既存コマンド同様）。
- resolver.resolve([]) が空配列を返す場合、lint はターゲットなしで終了するため CI 等で早期検知が可能。
- 独自レンジ実装を削除することでバグは減るが、挙動差分（例: 降順レンジやゼロ埋め）に伴う CLI ユーザー向けアナウンスが必要な場合がある。

## 11. 今後の拡張余地

- TokenResolver Entry 情報を活用し、lint 結果レポートに章ラベル（例: 「歴史篇」）を表示する。
- 章指定の共通テストスイート化（TokenResolver Contract Test）を lint でも利用可能。

## 12. 参考資料

- [docs/specs/cli_token_resolver_spec.md](./cli_token_resolver_spec.md): TokenResolver 全体仕様（対応コマンド一覧、正規化ルール、catalog.yml 構造）
- [docs/design/cli_token_resolver_internal.md](../design/cli_token_resolver_internal.md): Entry データ構造と Resolver 内部フェーズの設計思想
