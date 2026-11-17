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
| `v2-architecture-spec.md` | 2.0 の構造。本の種類（`book.type`＝軸の既定値の組）・パイプラインの五つの層と契約 HTML・出力先の宣言（`OutputTarget`）と `epub_builder.rb` の分割・設定の持ち方・記法の型の追加 | 一部実装済み（S4・S5 は 2026-11-16 に完了）。残りは段階 S8〜S10 |
| `theme-contract-spec.md` | テーマの契約。vs が保証する HTML・`theme.yml`・公開する変数（`--book-*`）・公式テーマの取り込み・テーマの置き場と `vs theme:*` | 実装中（S1 は 2026-11-14、S6-1〜S6-9b は 2026-11-17 までに完了・実装記録は §11。残りは S6-10・S7a・S7b。S6-9b の Apple Books の確かめは未実施） |
| `css-layer-restructure-spec.md` | CSS を `@layer` で作り直す。層の順序・ファイルの分け方・EPUB と Kindle 用の平らな CSS の生成・Kindle の規則の集約 | 実装済み（S2-1〜S2-3 は 2026-11-14、S2-4・S3-1・S3-2・S3-3a・S3-3b・S3-4 は 2026-11-15 に完了・実装記録は §10） |
| `v2-migration-plan.md` | 2.0 の段階 S0〜S11 の順序・共通の確かめ方（基準と比較の道具）・既存の本の移行（`vs upgrade`）・1.x との並行 | 実装中（S0〜S5・S6-1〜S6-9 完了・実装記録は §8。段階の表は 2026-11-17 に引き直した。残りは S6 の残り・S7a・S7b・S8〜S10・S8b・S8c・S11a〜S11d） |
| `novel-vertical-spec.md` | 縦書きの小説。縦書きの経路・テーマ `novel`・判型のプリセット（文庫・B6・新書・四六）・傍点と縦中横・投稿サイトの記法・小説の lint・雛形 `scaffolds/novel/` | 仕様済み・着手待ち（段階 S8。S7a の後） |
| `cover-size-independence-spec.md` | 表紙を判型に依らない作りにする。表紙のコードの判型の表を無くして寸法を判型のプリセットから引く・比の違う画像の扱い・同梱の SVG のひな形を縦長の判型に合わせる・下敷きの画像 | 仕様済み・着手待ち（段階 S8-3 の中で行う。S9-1 でも通る） |
| `cover-spread-spec.md` | 背表紙とくるみ表紙（表 4・背・表 1 を 1 枚に。背幅・背の中身・左右の綴じ） | 骨格だけ（段階 S8b の最初に書き足す） |
| `furigana-spec.md` | `vs furigana`（半自動の振り仮名。`furigana:auto` → `furigana:apply` の 2 段） | 骨格だけ（段階 S8c の最初に書き足す） |
| `picture-book-spec.md` | 絵本（固定レイアウト）。原稿の形（`@page`・`@spread`・文字の箱）・寸法と見開き・四つの出力先（Kindle は閲覧用 PDF のページの画像）・テーマ `picture-book`・雛形 `scaffolds/picture_book/` | 仕様済み・着手待ち（段階 S9。S9-0 の KDP の確かめは S8 の間に行える） |
| `video-spec.md` | 動画（どの種類の本でも使う記法と、出力先ごとの置き換え） | 骨組みだけ（段階 S10 の最初に中身を書く） |

新しく仕様書を書いたら、ここへ 1 行足してください。

---

## 参考メモ

知見メモ・ガイドライン・検討メモの索引は `NOTES.md` に移しました（本ファイルは「実装済みか？」に専念します）。

---

## メモ（依存関係・実装順序）

- 2.0 の仕様書は組で読む。段階の番号と順序の正典は `v2-migration-plan.md` §2。同じことが二つの仕様書に関わるときは、下の「正典である範囲」の側に書き、もう一方は節の番号で指すだけにする（2026-11-17・`v2-plan-review-consultation.md` §4.9）。

  | 仕様書 | 役目 | 正典である範囲 |
  | :--- | :--- | :--- |
  | `v2-migration-plan.md` | 段階の順・共通の確かめ方・基準の版・移行・1.x との並行 | 段階の番号と順序（§2）・全段階に共通の決まりと判断の線（§4.1）・「S11b で直す原稿」の一覧（§4.5） |
  | `v2-architecture-spec.md` | 本の種類と軸・パイプライン・出力先の宣言・設定 | 軸と `BookProfile`・`OutputTarget`・段の表の条件・キーの増減 |
  | `theme-contract-spec.md` | 契約 HTML・テーマの形・公開する変数・公式テーマ | 保証するクラス・`theme.yml`・`--book-*`・`vs theme:*`・S6 と S7 の小段階 |
  | `css-layer-restructure-spec.md` | 層・ファイルの分け方・平らな CSS | 層の順・Kindle 用の CSS の作り方（実装済み。S8-1 の物理方向の表だけが残る） |
  | `novel-vertical-spec.md` | 縦書きの経路・テーマ `novel`・小説の記法と lint・雛形 | S8 の小段階と完了の条件 |
  | `cover-spread-spec.md`（骨格） | 背表紙とくるみ表紙 | S8b |
  | `furigana-spec.md`（骨格） | `vs furigana`（対象の水準は `furigana-level-spec.md`） | S8c |
  | `picture-book-spec.md` | 固定レイアウトの経路・原稿の形・テーマ `picture-book`・雛形 | S9 の小段階と完了の条件 |
  | `video-spec.md`（骨組み） | 動画の記法と、出力先ごとの置き換え | S10 |

- 残りの着手の順は S6-10 → r3 → 節リードの判断 → S11a → S7a → S8 → S7b → S8b・S8c（S8 の後、S11b の前ならどこでも）→ S9 → S10 → S11b → S11c → S11d。
- 実装記録は仕様書から分けない。仕様書は、その段階が全部終わったら archives へ移る（`theme-contract-spec.md` は S7b の後）。
