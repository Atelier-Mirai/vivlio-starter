# Status（仕様書の実装進捗）

> 💡 **運用のルール**
> - 実装が完了したら本ファイルから該当行を削除し、仕様書ファイルは `git mv docs/specs/xxx.md docs/archives/` で移動する（`docs/specs/archives/` ではなく `docs/archives/` が既存の置き場所）。
> - まだ仕様化していないアイデア段階のものは本ファイルではなく `PLANNED.md` に置く。仕様書を書いた時点で本ファイルへ移す。
> - 状態が変わったら都度その場で更新する。放置すると `PLANNED.md` に実装済み項目が残り続ける事故が起きる（2026-07-08 に実例あり: `terminal-literal-spec` 完了後も未完了項目として残っていた）。

---

## 一覧

| Spec | 状態 | 次のアクション |
|---|---|---|
| print-pdf-derivation-spec.md | 確定仕様・未着手（①） | Phase 0 から実装。ステップ6で②の変更範囲に踏み込む点に注意（→メモ） |
| backlink-dedup-pdf-map-spec.md | 確定仕様・未着手（②） | ①と合わせて着手（→メモ） |
| print-pdf-full-bleed-notes.md | 設計メモ・実装保留 | フチなし要素のある本が実際に企画されるまで着手しない |
| cover-cmyk-color-management-spec.md | 未着手・別タスク | full-bleed notes の表紙ジオメトリ議論が固まってから着手 |
| generated-assets-cache-relocation-spec.md | 設計・実装前レビュー待ち | ①の実装方針が固まってからレビュー（→メモ） |
| table-colspan-spec.md | 確定仕様・未着手 | Phase 0（TableConverter コア）から実装 |
| explanatory-diagram-spec.md | 確定仕様・未着手 | Phase 0（showcase_svg_builder コア）から実装 |
| code-include-line-number-spec.md | 確定仕様・未着手 | 実装 |
| epub-code-line-numbers-spec.md | 将来タスク・一部未解決 | 方式決定待ち（優先度低） |
| kindle-simple-header-svg-spec.md | 将来タスク・未着手 | 優先度低 |
| release-1.0-considerations.md | 検討メモ | RC版完成後に再検討 |

---

## メモ（依存関係・実装順序）

- **① print-pdf-derivation-spec と ② backlink-dedup-pdf-map-spec はセットで着手する。**
  ①の実装ステップ6（`pipeline.rb` の dedup 再レンダ条件を `t.pdf || derive_print` にする）が②の変更範囲に直接踏み込むため、順序をバラバラに進めると手戻りが出る。①→②の順で着手し、①の Phase 0〜5 を終えた時点で②に着手する。両仕様書の冒頭に「①」「②」の相互リンクあり。

- **print-pdf-full-bleed-notes は実装対象ではない。**
  「フチなし要素のある本」が実際に企画されるまで保留（本文§0・§5に明記）。①（print-pdf-derivation-spec）の `full_bleed` 設定（§2.6）自体は①側の実装で完結するので、full-bleed-notes を待つ必要はない。

- **cover-cmyk-color-management-spec は print-pdf-full-bleed-notes の表紙ジオメトリ議論が発端。**
  full-bleed 側が動くまでは着手の実益が薄い。

- **generated-assets-cache-relocation-spec は print-pdf-derivation-spec（Phase 0〜）と `cover.rb` / `print_pdf_builder.rb` を共有する。**
  ①を先に実装すると、キャッシュ移設の対象コードが変わる可能性があるため、①の実装方針が確定してからレビューする方が手戻りが少ない。

- **table-colspan-spec と explanatory-diagram-spec は互いに独立。** どちらから着手してもよい。どちらも `markdown_preprocessor.rb` の変換ステップに新規フックを挿入する点は共通するため、同時期に着手する場合はフック挿入順序（既存ステップとの前後関係）の衝突に注意。
