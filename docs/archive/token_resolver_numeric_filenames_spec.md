# TokenResolver 数字のみファイル対応仕様

## 1. 背景
- 既存の `contents/` 配下は `1-install.md`, `2-customize.md` のように「番号 + スラッグ」形式を前提としている。
- 小説など章タイトルを外部で管理するケースでは、`1.md`, `2.md` のように数字のみで Markdown を執筆したいというニーズがある。
- 現行の `TokenResolver` は `\A\d+(?:[-_].+)?\z` を前提に正規化・照合しており、数字だけのファイル名はファイルシステム探索の対象外になっている。
- 本仕様では **番号のみファイル**（以下「数字ファイル」）を正式にサポートし、CLI からの章指定やファイル自動補完で扱えるようにする。

## 2. ゴール
1. `contents/01.md` など、番号以外のスラッグを持たない Markdown を CLI 全体で扱えるようにする。
2. `vs build 1` や `vs delete 3` といった番号指定が、数字ファイルを確実に解決する。
3. カタログ (`config/catalog.yml`) にも番号のみエントリを記述でき、Resolver は slug なしの `Entry` を生成する。
4. 既存の `番号 + スラッグ` ファイルやシステムファイルとの互換性を維持する。

## 3. 用語
- **数字ファイル**: `contents/NN.md`（例: `contents/02.md`）。スラッグを持たない。
- **従来ファイル**: `contents/NN-slug.md`。現在の既定形式。
- **Entry.slug**: スラッグ文字列。数字ファイルでは `nil`。

## 4. 現状と課題
| 項目 | 現状 | 課題 |
| --- | --- | --- |
| ファイル探索 | `Dir.glob(contents_dir, "#{token_num}-*.md")` のみ | `02.md` を検出できない |
| Entry 生成 | `basename =~ /(\d+)(?:[-_](.+))?/` に依存 | マッチしても slug が `nil` の場合を考慮していない |
| catalog.yml | `01-life` のように slug 前提 | `01` だけだと `instantiate_invalid_entry` になる |
| CLI UX | `vs build 1` で `02.md` が存在しても `slug=nil` の Entry を返せず新規扱い | 既存ファイルを重複作成するリスク |

## 5. 変更方針
1. **ファイルシステム探索の拡張**  
   - `contents/NN.md` も探索対象にする。
   - 優先順位: 同じ番号で `NN-slug.md` と `NN.md` が共存する場合はスラッグ付きファイルを優先。
2. **Entry 生成ロジックの拡張**  
   - `basename` が `NN` の場合でも `Entry` を生成し、`slug: nil`、`basename` は `number` のみ。
   - `path` には `contents/NN.md` をセット。
3. **catalog.yml 記法の拡張**  
   - `- 02` のように番号だけのエントリを許容する。`extract_from_yaml` → `instantiate_entry` のパスで slug を `nil` として扱う。
4. **トークン正規化の維持**  
   - CLI 入力はこれまで通りゼロ埋め (`1` → `01`) を行う。slug を強制せず、数字のみでも `Entry` が解決できるようにする。
5. **ログ / エラーメッセージ**  
   - 既存の文言を維持。数字ファイルであることを特別扱いする必要はない。

## 6. 詳細仕様
### 6.1 Normalization
- `Resolver#normalize` は従来どおり。追加処理は不要。
- `contents/01.md` のように拡張子だけを落として `01` となる既存処理で十分。

### 6.2 Filesystem Matching
- `match_entry` 内の番号のみ分岐を以下のように拡張する。
  1. `token_num = format("%02d", token.to_i)` を得る。
  2. `Dir.glob(File.join(contents_dir, "#{token_num}-*.md"))` を評価し、ヒットすれば従来どおり slug を補完する。
  3. ヒットしなければ `File.exist?(File.join(contents_dir, "#{token_num}.md"))` をチェックし、存在すれば slug `nil` の Entry を返す。
  4. それでも無ければ従来どおり番号のみの新規 Entry を生成。

### 6.3 catalog.yml の取り扱い
- `instantiate_entry` にて `basename` が `NN` の場合を許容し、`slug=nil` を保持。
- `extract_from_yaml` で `"02"` のような値を見つけたときは `basename: "02"`、`label` はセクション名で従来どおり。
- `Entry#basename` は `slug` が `nil` のとき `number` のみ返すため、章ファイル名との整合性が取れる。

### 6.4 exists フラグ
- 数字ファイルを `File.exist?("contents/NN.md")` で検知し、`Entry.exists? == true` になるようにする。
- スラッグ付きファイルの存在チェックより後に評価することで、共存時の優先順位を維持。

### 6.5 kind の推定
- `kind` 判定は章番号のみを参照しているため追加変更は不要。
- `slug` が `nil` でも `Entry.kind` は既存ロジックで算出される。
- `0`（あるいは `00`）は従来どおりゼロ埋め後に `:preface` として扱う。
- `99` は従来どおり `:postface` に分類され、番号のみファイルでも同様。

### 6.6 CLI への影響
- `vs build`, `vs metrics`, `vs delete`, `vs create`, `vs rename` などすべての Resolver 利用コマンドで数字ファイルが自然に解決される。
- `vs create 2` のように slug なしで新規作成するケースも許容し、Resolver は `number: "02", slug: nil` の `Entry` を返す。
  - `vs create 2` 実行時に `contents/02.md` が生成される（slug なし）。
  - 既に `02.md` または `02-*.md` が存在する場合は従来どおりバリデーションで弾かれる。

## 7. テスト計画

### 7.1 TokenResolver 単体テスト

1. **Filesystem Completion**  
   - `contents_dir` に `02.md` のみ存在する状態で `resolver.resolve(['2'])` を呼び、`slug == nil`、`exists? == true` を確認。
2. **Catalog Entry Without Slug**  
   - `catalog.yml` に `- 03` を記述し、`resolver.resolve([])` で `slug == nil` の Entry が得られること。
3. **Range Expansion with Numeric Files**  
   - `contents/02.md`, `contents/03.md` を配置して `resolver.resolve(['2-3'])` が両方 `exists? == true` になること。
4. **Create Command without Slug**  
   - Resolver が `vs create 2` で `slug: nil` の Entry を返し、コマンドが `contents/02.md` を生成するフローを検証。
5. **Invalid Input Regression**  
   - `!!!` など非数字トークンが引き続き invalid Entry を返すことを確認。
6. **Slug-named File Priority**  
   - 同一番号で `02.md` と `02-history.md` が共存する場合、`resolver.resolve(['2'])` がスラッグ付きを優先して返すことを確認。
7. **Kind Detection for Numeric Files**  
   - `00.md`, `01.md`, `90.md`, `99.md` がそれぞれ `:preface`, `:chapter`, `:appendix`, `:postface` を返すことを確認。

### 7.2 CLIコマンド統合テスト

各コマンドが数字ファイル（`NN.md`）を `slug: nil` の Entry として正しく扱えることを確認する。  
テストは既存の `test/vivlio/starter/cli/` 配下の各コマンドテストに追記する。

#### vs build
- `contents/02.md` が存在する状態で `vs build 2` を実行し、ビルドが正常完了することを確認。
- `vs build`（引数なし）で `catalog.yml` に `- 02` を含む場合、`02.md` がビルド対象に含まれることを確認。
- 従来ファイル（`01-install.md`）と数字ファイル（`02.md`）が混在するカタログで `vs build 1-2` が両方をビルドすることを確認。

#### vs create
- `vs create 2` で `contents/02.md` が新規生成されることを確認（slug なし）。
- `vs create 2` 実行時に `02.md` が既存の場合、重複作成エラーになることを確認。
- `vs create 2` 実行時に `02-history.md` が既存の場合も、重複作成エラーになることを確認。

#### vs delete
- `contents/02.md` が存在する状態で `vs delete 2` を実行し、ファイルが削除されることを確認。
- 数字ファイルの削除後、`catalog.yml` から該当エントリ（`- 02`）が除去されることを確認（catalog 管理コマンドと連動する場合）。

#### vs rename
- `contents/02.md` を `vs rename 2 history` で `contents/02-history.md` にリネームできることを確認。
- `vs rename 2 history` 実行後、`catalog.yml` のエントリが `- 02` から `- 02-history` に更新されることを確認。

#### vs renumber
- `contents/02.md` を `vs renumber 2 5` で `contents/05.md` にリナンバーできることを確認（slug なし維持）。
- 数字ファイルと従来ファイルが混在する連番の繰り上げ・繰り下げが正しく動作することを確認。

#### vs lint
- `catalog.yml` に `- 02` を記述し、`contents/02.md` が存在する場合に lint エラーが出ないことを確認。
- `catalog.yml` に `- 02` を記述し、`contents/02.md` が存在しない場合に「ファイル未生成」警告が出ることを確認。

#### vs metrics
- `contents/02.md` が存在する状態で `vs metrics 2` を実行し、文字数・段落数等の統計が正しく出力されることを確認。
- `vs metrics` （引数なし）で数字ファイルを含む全章の統計が出力されることを確認。

## 8. マイグレーション / 互換性
- 既存の `NN-slug.md` を変更する必要はない。
- 追加の設定やフラグは不要。`TokenResolver` の内部ロジックのみで完結する。
- `catalog.yml` で番号のみを使用する場合、生成される `Entry` が slug を持たないことを前提に呼び出し側で `entry.basename` を参照すること。

## 9. 実装対象
- `lib/vivlio/starter/cli/token_resolver.rb`
  - `match_entry` の番号のみ分岐
  - `instantiate_entry` のフォーマット許容範囲
  - 既存コメントのアップデート
- `test/vivlio/starter/cli/token_resolver_test.rb`
  - 7.1 に沿った単体テストの追加
- `test/vivlio/starter/cli/build_test.rb`
  - 数字ファイルのビルド対象確認テストの追加
- `test/vivlio/starter/cli/create_test.rb`
  - slug なし新規作成・重複エラーテストの追加
- `test/vivlio/starter/cli/delete_test.rb`
  - 数字ファイル削除テストの追加
- `test/vivlio/starter/cli/rename_test.rb`
  - 数字ファイルへのリネームテストの追加
- `test/vivlio/starter/cli/renumber_test.rb`
  - 数字ファイルのリナンバーテストの追加
- `test/vivlio/starter/cli/lint_test.rb`
  - 数字ファイルの lint 検証テストの追加
- `test/vivlio/starter/cli/metrics_test.rb`
  - 数字ファイルの統計出力テストの追加
- ドキュメント更新
  - 本仕様書
  - 既存の `docs/specs/cli_token_resolver_spec.md` に数字ファイル許容を追記（別タスクで反映）

## 10. リスクとオープン課題
- 同じ番号で slug あり/なしファイルが併存する場合の明確な優先順位を実装コメントに記述すること（本仕様では slug ありを優先）。
- 将来的に `contents/NN/` ディレクトリ構成を導入する際は、同様のロジック拡張が必要になる可能性がある。
