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
  状態: 設計・実装前レビュー待ち（レビュー可能になった）
  次のアクション: **着手前に現行コードとの突合レビューが必須**。本仕様は §7 で
  「移設 → ①print_pdf 導出」の順を想定していたが、実際は①②が先に実装された
  （2026-07-10・5f7406cf）ため前提コードが変わっている。特に `print_pdf_builder.rb` は
  導出フローへ全面改稿済みで、§1.1 の「CMYK カバーを印刷 PDF へ結合」は現行と不一致
  （カバーは結合せず別ファイル入稿・`ensure_cover_files_for_build!` を呼ぶのみ）。
  §4 の変更ファイル一覧を現行コードと突合して改稿 → 実装、の 2 段で進める

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

- **generated-assets-cache-relocation-spec は print-pdf-derivation-spec（実装済み）と `cover.rb` / `print_pdf_builder.rb` を共有する。**
  ①の実装が完了した（2026-07-10）ため、現行コードを前提にレビュー・改稿できる。

- **table-colspan-spec と explanatory-diagram-spec は互いに独立。** どちらから着手してもよい。どちらも `markdown_preprocessor.rb` の変換ステップに新規フックを挿入する点は共通するため、同時期に着手する場合はフック挿入順序（既存ステップとの前後関係）の衝突に注意。
