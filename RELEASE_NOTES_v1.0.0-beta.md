# Vivlio Starter v1.0.0-beta リリースノート

**リリース日**: 2026-04-26

1.0.0 正式リリースに向けたベータ版です。主要機能はすべて実装済みですが、既知の不具合が若干残っているため、ベータ版としてリリースします。

---

## ハイライト

### 堅牢性の大幅強化
18 項目の堅牢性テストを `test/vivlio/starter/robustness/` に集約し、セキュリティ・安全性を体系的に検証しました。

- 外部コマンド不在時のユーザー向け案内メッセージ
- SIGINT / SIGTERM の graceful handling
- `vs new` 中断時の部分展開クリーンアップ
- `lint --fix` 中断時の元ファイル保全
- 不正な SVG XML に対する堅牢化
- catalog.yml YAML anchors / aliases 悪用対策
- 原稿内の危険スキーム（`file://` / `javascript:`）検出
- QueryStream データファイルの YAML safe_load 化
- ディレクトリトラバーサル / HTML 特殊文字への耐性
- 並列ビルドの排他ロック（`BuildLock`）

### ログ出力の全面改修
`docs/specs/logging_spec.md` に基づき、ログ出力を統一・構造化しました。

- `log_warn` / `log_error` / `log_summary` に `detail:` キーワード引数を追加
- `Common` のログ出力メソッドを整理（`log_always`, `log_summary`, `log_inspection`, `log_result` を新設）
- 各コマンドの `puts` / `warn` を `Common.log_*` に統一

### HtmlReplacer の抜本的修正
`post_replace_list.yml` の置換ルールがコードブロック内や HTML 属性値にまで適用されてしまう重大な不具合を修正しました。ルール分類器（`rule_mode`）を導入し、`:code_aware` / `:text_only` / `:tag_aware` の3モードで安全に適用します。

### `vs preflight` コマンドの新設
`vs build`（約600秒）の前に原稿のエラーチェックだけを約6秒で行う高速チェックコマンドを追加しました。

---

## 主な新機能（Added）

- **`long-table` / `table-scroll` コンテナの pre_process 変換**: VFM がコンテナ内のパイプテーブルを変換しないケースに対応
- **`vs preflight` コマンド**: 画像不在・コードインクルードファイル不在・QueryStream 展開エラー・クロスリファレンス未定義ラベルを高速検出
- **`book.yml` 主要キーのバリデーション**: `book.main_title` / `book.author` / `project.name` の欠落を警告
- **`<!-- vs-lint-disable -->` 未クローズ時の警告**
- **フロントマター未クローズ時の警告**
- **並列ビルドの排他ロック（`BuildLock`）**

---

## 主な変更（Changed）

- クロスリファレンスのエラー・警告出力を整形（ラベルID重複・孤立ラベルの表示改善）
- `vs preflight` / `vs build` のコードインクルードエラー表示を改善
- `vs preflight` 完了メッセージから所要時間を削除しシンプル化
- `vs build` 完了メッセージに所要時間を統合（`📚 12-quickstart.pdf を作成しました (4.6s)`）
- Ctrl+C / SIGTERM 受信時のスタックトレース抑止と UNIX 規約の終了コード対応
- テーマカラーの選択肢を17色から12色に削減
- コード内コメント強調の記法を `←` から `[!]` マーカー方式に変更
- `.column` / `.memo` / `.tip` のデザインを刷新
- RuboCop 違反の追加クリーンアップ（888 → 860）

---

## 主な修正（Fixed）

- `:::` コンテナ記法でスペースがあると変換されない問題
- `:::` フェンス内の画像が検証から漏れる問題
- `.img-text` / `.text-img` 系コンテナで横並びにならない問題
- 付録の章番号レター（A/B/C...）が catalog.yml の順番と一致しない問題
- コードブロック内の `include:` 記法・`:::` コンテナ記法の誤検出
- `language-markdown` コードブロック内の `[!]` コメント強調の誤適用
- 画像・ソースコード・裸URL 検出の行番号ずれ
- 脚注URLの重複表示・不正な脚注参照
- `vs new` の YAML プレースホルダエスケープ
- 4バッククォート以上のコードブロック内でのクロスリファレンス誤検出
- 前書き章の単章ビルドで PDF が削除される問題
- `.sideimage-left` の画像幅指定の誤解釈
- 脚注番号の二重表示
- `.text-right` が無効になっていた問題
- 目次のレイアウト崩れ
- Vivliostyle ビューア警告の解消
- `book.yml` 更新時に特殊ページ・カバーが再生成されない不具合
- `vs renumber` でスラッグが脱落する不具合
- `vs new --help` が動作しない問題
- QueryStream 展開エラー時の各種問題改善
- Step 8（backlink dedup）の Playwright 完了検知改善

---

## セキュリティ / 堅牢性（Security / Robustness）

- 外部コマンド不在時のユーザー向け案内メッセージ（OS 別インストール手順付き）
- SIGINT / SIGTERM の graceful handling 回帰テスト
- `vs new` 中断時の部分展開クリーンアップ
- `lint --fix` 中断時の元ファイル保全
- 不正な SVG XML に対する堅牢化
- プロジェクトルート書き込み不可時の堅牢性確認
- catalog.yml 欠落ファイルの警告検証
- 画像パスのディレクトリトラバーサル / HTML 特殊文字堅牢性
- catalog.yml YAML anchors / aliases 悪用対策
- 原稿内の危険スキーム（`file://` / `javascript:`）検出（常時有効）
- QueryStream データファイルの YAML safe_load 化
- 堅牢性テスト専用ディレクトリ `test/vivlio/starter/robustness/` を新設

---

## 既知の不具合

- **sideimage 内の脚注URLが重複表示される**: sideimage コンテナ内のリンクから生成された脚注URLが、PDF上で複数回表示される。Vivliostyle の `float: footnote` の挙動が原因。
- **画像の配置（`align=left` / `align=center` / `align=right`）が乱れる**: `align=left` による float が後続の画像に干渉し、レイアウトが崩れる。
- **テーブル内リンクの脚注URLが重複表示される**: テーブルセル内のリンク記法で脚注化されたURLが複数回重複して表示される。

---

## アップグレード方法

```bash
gem install vivlio-starter-1.0.0.pre.beta.gem
```

## 前バージョンからの移行

- コード内コメント強調の記法が `←` から `[!]` マーカー方式に変更されています。既存の `#←` / `//←` 記法は `# [!]` / `// [!]` に書き換えてください。
- テーマカラーから `amber`, `peach`, `coral`, `plum`, `mint` が削除されました。これらを使用している場合は、残りの12色から選択してください。
