# Roadmap

本プロジェクト（Rake ベースの Vivliostyle ビルドシステム）の改良計画を記録します。

## TODO
- [ ] help に pdf:compress を追加
- [ ] titlepage / colophon の自動生成
- [ ] 

## 目標（ゴール）
- ビルドの安定性と再現性の向上（設定の一元管理と検証）
- ログとエラー報告の改善（原因特定しやすさの向上）
- タスク体系の明確化（名前空間・エイリアスの整理とドキュメント同期）
- パフォーマンス最適化（不要処理の削減・並列化の検討）

## マイルストーン（案）
- M1: 2025-09 ビルドの安定化と開発者 UX 向上
  - 失敗時のリカバリ提案・詳細ログ・中間生成物のトレース
  - `help`/`README`/`Rakefile` コメントの整合性自動チェック
- M2: 2025-10 パフォーマンス改善
  - 差分ビルド、キャッシュ戦略（HTML/画像/entries/toc）
  - 並列実行（独立タスクの並列化）検討
- M3: 2025-11 配布・運用
  - Docker/Devcontainer、CI（Lint/テスト/ビルド）
  - リリース手順・CHANGELOG 整備

## 改良候補（Backlog）
- 設定/引数処理
  - `config/book.yml` のスキーマ検証（必須フィールド・型チェック）
  - `BookBuild.Options` の引数パース整理（重複排除・単体テスト追加）
  - `VERBOSE` 以外の共通フラグ（`DRY_RUN` 等）導入の検討
- タスク体系／機能
  - `code:` 名前空間の拡張（例: `code:include`, `code:extract`, `code:lint`）
  - `vivliostyle:` まわりの操作性強化（`vivliostyle:preview` 等の検討）
  - `open` の出力先・ビューア選択を設定化（マルチ OS 対応含む）
  - 章テンプレートの拡充（`rake create` の雛形選択）
- 変換・前処理
  - HTML 生成の差分適用（再生成対象の最小化）
  - `<body>` クラス付与ロジックの拡張（appendix/postface/colophon の網羅テスト）
  - Prism.js 行番号・テーマの切替（設定化）
- 品質・テスト
  - 重要ヘルパ（`generate_frontmatter`, `process_args`）の単体テスト
  - サンプル章によるエンドツーエンド（E2E）テスト（最小データセット）
  - エラー時のヒント表示（例: vfm/vivliostyle 未インストール、パス誤り）
- ドキュメント
  - `README` のスクリーンショット/サンプル PDF 追加
  - `HELP` と `rake -T` 表示の自動同期（生成スクリプト化）
  - `CONTRIBUTING.md`, `CHANGELOG.md` 追加
- 配布・環境
  - Docker/Devcontainer での再現環境提供
  - GitHub Actions/CI でのビルド検証
- ライセンス・著者表記
  - 分離ライセンスの明記継続（コード: MIT / 本文: CC BY-NC-SA 4.0）
  - 著者名の統一「アトリヱ未來」の自動検査（pre-commit）

## リスク・検討事項
- ARGV 操作の副作用（タスクチェーンへの影響）
- 外部 CLI（vfm / vivliostyle）依存のバージョン固定と更新戦略
- OS 差異（mac / Linux / Windows）における `open` コマンド挙動

## 直近のアクション（Next）
- `help` と `README` の一覧を自動生成/検証する小タスク追加
- `config/book.yml` スキーマの最小バリデーション導入
- `generate_frontmatter` と `process_args` に基本テストを用意

## 近々（Short-term）
- [ ] Vivliostyleのページ番号制御の調査・整備
  - vivliostyle.config.js にページカウンタ設定オプションがあるか確認し、前書きを負の値（例: -10）から開始し、本文開始で 1 にリセットする要件を実装。
  - CSSカウンタ（@page counter-reset/counter-increment）の現行設定の見直しと検証。
- [ ] 奥付（colophon）の自動生成
  - 発行者、発行日、著者名等を含むHTML（例: `colophon.html`）を生成するRakeタスクを追加。
  - Frontmatterとビルドへの組み込み。
- [ ] 段落のクラス付与（.aki / .aki2）の安定化
  - `_postReplaceList.json` は現在 `{.aki}` と `{.aki2}` のみサポート。現状はこれで確定運用。
  - 生成HTMLの回帰チェック（クラス属性の引用符・バックスラッシュ混入の再発防止）。
- [ ] リストの体裁改善（lower-alpha 等）
  - Markdownでは `a.`/`b.` がリストとして解釈されないため、必要箇所は `<ol type="a">` の生HTMLを採用。
  - 必要であれば `ol.lower-alpha { list-style-type: lower-alpha; }` 用のユーティリティCSSを追加。
- [ ] CSS Lintの整理
  - `stylesheets/page_settings_a4.css` の警告（`text-spacing`、`@bottom-center` など）を精査。
  - Paged Media（Vivliostyle）特有の拡張の扱い方をドキュメント化し、一般的なCSS Lintとの共存方針を決定。
- [ ] VFMコンテナの複数クラス対応（`text-2dan gap-s`）
   - `:::{.text-2dan .gap-s}` を正しく HTML に反映（`class="text-2dan gap-s"`）できるようにする。
   - 対応案:
     1) VFM の設定/バージョン確認（複数クラス付与の既定動作の把握）
     2) 変換後ポストプロセスでの補正（必要なら fenced container を検出して class を統合）
     3) ドキュメント・使用例の更新（`contents/11-gift.md` の例で `gap-s` が効くことを確認）
   - 受入基準: `text-2dan gap-s` の併用で段組とギャップユーティリティが同時に適用される。

## 中期（Mid-term）
- [ ] Post-processingの単体テスト整備
  - `_postReplaceList.json` の主要ルール（段落クラス付与、見出し・bodyクラス、各種クレンジング）のスナップショットテストを追加。
  - 想定外パターン（複数ブレース、引用符・バックスラッシュ混入等）の回帰防止。
- [ ] Markdown → HTML 変換の拡張設計
  - 段落以外（blockquote, list, figure）へのクラス付与要件を洗い出し、必要なら生HTMLか前処理で対応方針を策定。
- [ ] ビルドログ整備
  - Rakeの各タスクに要約出力とエラーヒントを追加。

## 長期（Long-term）
- [ ] スタイルガイドの整備
  - 章タイプ別（preface/chapter/appendix/postface）スタイルの設計指針、ユーティリティクラス（`.aki`, `.aki2`, ほか）一覧、使用例をドキュメント化。
- [ ] 自動検証パイプライン（CI）
  - 最小サンプルでのビルド、Lint、HTMLポスト処理テストの自動実行。

## メモ
- Frontmatter生成は `generate_frontmatter` の併合ロジックにより安定化済み。
- `<body>` のファイルタイプ自動クラス付与は導入済み（スタイル適用の基盤として継続利用）。
