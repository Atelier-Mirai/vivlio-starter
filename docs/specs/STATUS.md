# Status（仕様書の実装進捗）

> 💡 **運用のルール**
> - 実装が完了したら本ファイルから該当行を削除し、仕様書ファイルは `git mv docs/specs/xxx.md docs/archives/` で移動する（`docs/specs/archives/` ではなく `docs/archives/` が既存の置き場所）。
> - まだ仕様化していないアイデア段階のものは本ファイルではなく `PLANNED.md` に置く。仕様書を書いた時点で本ファイルへ移す。
> - 知見メモ（`*-notes.md`）とガイドラインは本ファイルではなく `NOTES.md` の索引に置く。`docs/specs/` に足したら、あちらへ 1 行足す。
> - 状態が変わったら都度その場で更新する。放置すると `PLANNED.md` に実装済み項目が残り続ける事故が起きる（2026-07-08 に実例あり: `terminal-literal-spec` 完了後も未完了項目として残っていた）。
> - 「メモ（依存関係・実装順序）」に書くのは**実装待ちの仕様書どうしの依存**（「A を先に入れると B が楽」等）だけ。**完了報告は書かない**——それは `CHANGELOG.md` の役目で、両方に書くと必ず片方が stale になる。実装して分かった落とし穴は**その仕様書自身の「実装記録」節**へ書いてから `docs/archives/` へ送る。やり残した作業は `PLANNED.md`（将来対応）か `KNOWN_ISSUES.md`（未解消の不具合・制限）へ移す。

---

## 一覧

| 仕様書 | 内容 | 状態 |
| :--- | :--- | :--- |
| `chapter-lead-size-spec.md` | 章リードの文字の大きさ（`theme.lead_size`・章扉だけの上書き `theme.frontispiece.lead_size`）・章扉からのはみ出しの検出・EPUB の章扉を横長の扉絵に（改善案 #125） | 実装済み（2026-10-28） |
| `v2-architecture-spec.md` | 2.0 の構造。本の種類（`book.type`＝軸の既定値の組）・パイプラインの五つの層と契約 HTML・出力先の宣言（`OutputTarget`）と `epub_builder.rb` の分割・設定の持ち方・記法の型の追加 | 設計済み・実装待ち（段階 S4・S5・S8〜S10） |
| `theme-contract-spec.md` | テーマの契約。vs が保証する HTML・`theme.yml`・公開する変数（`--book-*`）・公式テーマの取り込み・テーマの置き場と `vs theme:*` | 設計済み・実装待ち（段階 S1・S6・S7） |
| `css-layer-restructure-spec.md` | CSS を `@layer` で作り直す。層の順序・ファイルの分け方・EPUB と Kindle 用の平らな CSS の生成・Kindle の規則の集約 | 設計済み・実装待ち（段階 S2・S3） |
| `v2-migration-plan.md` | 2.0 の段階 S0〜S11 の順序・共通の確かめ方（基準と比較の道具）・既存の本の移行（`vs upgrade`）・1.x との並行 | 計画済み・着手待ち（段階 S0・S11） |

新しく仕様書を書いたら、ここへ 1 行足してください。

---

## 参考メモ

知見メモ・ガイドライン・検討メモの索引は `NOTES.md` に移しました（本ファイルは「実装済みか？」に専念します）。

---

## メモ（依存関係・実装順序）

- 2.0 の 4 本（`v2-architecture-spec.md`・`theme-contract-spec.md`・`css-layer-restructure-spec.md`・`v2-migration-plan.md`）は組で読む。段階の番号（S0〜S11）と順序の正典は `v2-migration-plan.md` §2。
- 着手の順は S0（基準と比較の道具）→ S1（契約 HTML）→ S2・S3（CSS の層と平らな CSS）→ S4（出力先の分割）→ S6（テーマ）。S5（種類・軸・設定）は S2〜S4 と独立で、S6 より前に終える。
- 縦書きの小説・絵本・動く絵本の個別の仕様は、S8・S9・S10 の最初に書く（まだ無い）。
