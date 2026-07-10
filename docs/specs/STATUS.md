# Status（仕様書の実装進捗）

> 💡 **運用のルール**
> - 実装が完了したら本ファイルから該当行を削除し、仕様書ファイルは `git mv docs/specs/xxx.md docs/archives/` で移動する（`docs/specs/archives/` ではなく `docs/archives/` が既存の置き場所）。
> - まだ仕様化していないアイデア段階のものは本ファイルではなく `PLANNED.md` に置く。仕様書を書いた時点で本ファイルへ移す。
> - 状態が変わったら都度その場で更新する。放置すると `PLANNED.md` に実装済み項目が残り続ける事故が起きる（2026-07-08 に実例あり: `terminal-literal-spec` 完了後も未完了項目として残っていた）。

---

## 一覧

`print-pdf-full-bleed-notes.md`
: print_pdf のフチなし（full_bleed）要素対応についての設計メモ。写真集・爪見出しなど紙の端まで達するデザイン要素を持つ本を将来作る際の判断材料として、導出方式と個別レンダー方式の違いを整理したもの。
  状態: 設計メモ・実装保留
  次のアクション: フチなし要素のある本が実際に企画されるまで着手しない

`cover-cmyk-color-management-spec.md`
: 表紙の CMYK カラーマネジメント改善についての仕様メモ。
  状態: 仕様メモ（未確定）・未着手
  次のアクション: 移設（generated-assets）完了後に着手。実装の前に調査・方針決定が必要:
  (1) Japan Color 2001 Coated ICC の入手経路（gem 同梱の再配布可否をライセンス調査／
  ユーザー用意＋doctor 検出／設定キー指定のいずれか）(2) PDF/X-1a 化まで行うか docs を
  実態に合わせるか。選択肢を調査・提示してユーザーが決定 → 仕様確定 → 実装の順。
  ※ 旧ゲート「full-bleed ジオメトリ議論待ち」は撤廃（本文§留意点どおりジオメトリと独立）

`generated-assets-cache-relocation-spec.md`
: covers 生成物・テーマ画像バリアントなど、ビルド時生成資産の置き場所を `.cache` へ移設する仕様。
  状態: 確定仕様・実装待ち（2026-07-10 に現行コード突合レビュー・全面改稿済み）
  次のアクション: §4 の変更ファイル一覧に沿って実装。突合での主な改稿点:
  (1) print_pdf_builder.rb は変更不要（①導出化でカバー結合が消滅・covers パス参照なし）
  (2) EPUB 表紙は「ソース相対＝パッケージ内相対」の偶然一致に依存していたため
  config の cover: 行とローカライズ先を分離（§3.2）(3) CMYK 生成は cover.rb（PNG 経由）と
  create.rb（light/dark SVG 経由）の 2 経路あり、ルート複製ヘルパは両方から呼ぶ（§3.4）
  (4) 扉絵合成の `resolve_theme_image_file` の cache 解決分岐が初版で漏れていた（§3.2）
  (5) 同名ファイルのソース/生成物衝突に対する探索規則を §3.5 に新設

`table-colspan-spec.md`
: テーブルの横結合（colspan）と複数行ヘッダーに対応する仕様（PHP Markdown Extra / Backlog 風の記法拡張）。
  状態: 確定仕様・未着手
  次のアクション: Phase 0（TableConverter コア）から実装

`explanatory-diagram-spec.md`
: 図解注釈記法（Explanatory Diagram Syntax）の仕様。スクリーンショット等の画像に矩形囲み・矢印（pointer）などの注釈を SVG で重ねる記法を追加する。
  状態: 確定仕様・未着手
  次のアクション: Phase 0（showcase_svg_builder コア）から実装

`code-include-line-number-spec.md`
: コードインクルード範囲指定時の行番号を、元ファイルでの実際の行番号に合わせる仕様。現状は常に 1 から振り直されてしまう。
  状態: 確定仕様・未着手
  次のアクション: 実装

`epub-code-line-numbers-spec.md`
: EPUB/Kindle のコードブロックにおける行番号表示と折返しについての仕様検討（リフロー環境での行番号ずれ対策）。
  状態: 将来タスク・一部未解決
  次のアクション: 方式決定待ち（優先度低）

`kindle-simple-header-svg-spec.md`
: Kindle 向け simple ヘッダーを SVG 画像化する仕様。
  状態: 将来タスク・未着手
  次のアクション: 優先度低

`release-1.0-considerations.md`
: RC版 → 正式版（1.0.0）へ移行するにあたっての検討事項メモ。
  状態: 検討メモ
  次のアクション: RC版完成後に再検討

---

## メモ（依存関係・実装順序）

- **① print-pdf-derivation-spec と ② backlink-dedup-pdf-map-spec は 2026-07-10 に実装完了し `docs/archives/` へ移動した。**
  実装時の追加知見（qpdf `--overlay` が宛先 TrimBox に合わせて縮小配置する仕様と、手順順序 3a→4→5→3b への変更）は①仕様書 §3.8 に追記済み。

- **print-pdf-full-bleed-notes は実装対象ではない。**
  「フチなし要素のある本」が実際に企画されるまで保留（本文§0・§5に明記）。①（print-pdf-derivation-spec）の `full_bleed` 設定（§2.6）自体は①側の実装で完結するので、full-bleed-notes を待つ必要はない。

- **cover-cmyk-color-management-spec は print-pdf-full-bleed-notes の表紙ジオメトリ議論が発端。**
  full-bleed 側が動くまでは着手の実益が薄い。

- **generated-assets-cache-relocation-spec の突合レビュー・改稿は 2026-07-10 完了。**
  ①導出化により print_pdf 側のカバー結合が消えたため、PDF 経路の変更は pdf_merger.rb
  1 箇所に減り、print_pdf_builder.rb は変更不要になった（仕様 §7 改訂）。

- **table-colspan-spec と explanatory-diagram-spec は互いに独立。** どちらから着手してもよい。どちらも `markdown_preprocessor.rb` の変換ステップに新規フックを挿入する点は共通するため、同時期に着手する場合はフック挿入順序（既存ステップとの前後関係）の衝突に注意。
