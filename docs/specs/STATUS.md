# Status（仕様書の実装進捗）

> 💡 **運用のルール**
> - 実装が完了したら本ファイルから該当行を削除し、仕様書ファイルは `git mv docs/specs/xxx.md docs/archives/` で移動する（`docs/specs/archives/` ではなく `docs/archives/` が既存の置き場所）。
> - まだ仕様化していないアイデア段階のものは本ファイルではなく `PLANNED.md` に置く。仕様書を書いた時点で本ファイルへ移す。
> - 状態が変わったら都度その場で更新する。放置すると `PLANNED.md` に実装済み項目が残り続ける事故が起きる（2026-07-08 に実例あり: `terminal-literal-spec` 完了後も未完了項目として残っていた）。
> - 「メモ（依存関係・実装順序）」に書くのは**実装待ちの仕様書どうしの依存**（「A を先に入れると B が楽」等）だけ。**完了報告は書かない**——それは `CHANGELOG.md` の役目で、両方に書くと必ず片方が stale になる。実装して分かった落とし穴は**その仕様書自身の「実装記録」節**へ書いてから `docs/archives/` へ送る。やり残した作業は `PLANNED.md`（将来対応）か `KNOWN_ISSUES.md`（未解消の不具合・制限）へ移す。

---

## 一覧

`build-target-parallelization-spec.md`
: 共通前段のあと PDF 枝と EPUB/Kindle 枝を並列に走らせる。EPUB 枝 130.5 秒がまるごと PDF 枝 406.5 秒の陰に隠れる（実測 −23.6%）。
  状態: 仕様（実装待ち）
  次のアクション: §3.3（`_colophon.html` の読み書き競合）は `front-back-matter-single-render-spec.md` の実装で解消済み。残る §3.1（workspaceDir の分離）と §3.2（カバー生成の共通前段への引き上げ）から着手する

`kindle-rotate-table-image-spec.md`
: Kindle で回転テーブルが回転せず素の表に戻る（KFX が `transform` / `position: absolute` を解さない）ため、画像へ劣化させて 90 度回転・中央配置で見せる。
  状態: 仕様（実装待ち）
  次のアクション: §3 案 A（生成済み PDF の該当ページを切り出す）で着手。`PdfPageMapExtractor` が任意 id を引ける入口を持つかの確認が最初の作業。切り出し元は §7 のとおり **dedup 前の 1 回目のレンダ**にすること

---

## 参考メモ

`release-1.0-considerations.md`
: RC版 → 正式版（1.0.0）へ移行するにあたっての検討事項メモ。
  状態: 検討メモ
  次のアクション: RC版完成後に再検討

`furigana-level-spec.md`
: 漢字レベル L0〜L4 の定義（`vs metrics` と将来の `vs furigana` で共通）。定義自体は `vs metrics` で実装・稼働済みで、本書はそれを記録し `vs furigana` を作るときの論点を添えたもの。
  状態: 仮（定義の記録）。配当表の 2020 年度施行版への更新と `KanjiLevels.grade_of` の追加は 2026-07-28 に完了
  次のアクション: `vs furigana` を起こすときに §3 を出発点にする（レベル定義側でやり残しは無い）

`inline-footnote-collision-notes.md`
: インライン脚注 `^[短い補足]` が脚注にならない不具合の一次資料。VFM 自体は対応しており前処理が犯人であること、疑っている箇所と切り分け手順、影響範囲（記法として案内済み）を記録したもの。
  状態: 症状の確認のみ（原因未特定）
  次のアクション: §3 の手順で犯人を特定してから仕様書を起こす。回避策（参照形式 `[^label]`）があるため急がない

`print-pdf-full-bleed-notes.md`
: print_pdf のフチなし（full_bleed）要素対応についての設計メモ。写真集・爪見出しなど紙の端まで達するデザイン要素を持つ本を将来作る際の判断材料として、導出方式と個別レンダー方式の違いを整理したもの。
  状態: 設計メモ・実装保留
  次のアクション: フチなし要素のある本が実際に企画されるまで着手しない

---

## メモ（依存関係・実装順序）

実装待ちの 2 本はビルド高速化で連なっており、**上から順に実装する**のが最短経路。
前提の 1 本（`front-back-matter-single-render-spec.md`・−71s）は 2026-08-01 に実装済みで
`docs/archives/` にある。

1. **`build-target-parallelization-spec.md`**（−130s）
   前提工程が §3.3 の枝間依存（`_colophon.html` の読み書き競合）を既に解消している。
   残る関門は §3.1 の `workspaceDir` 分離と §3.2 のカバー生成の引き上げ。
2. **`kindle-rotate-table-image-spec.md`**
   実装済み仕様が作った「レンダ済み PDF からアンカー ID のページを引く」入口
   （`PdfPageMapExtractor#document_first_pages`）と qpdf のページ範囲操作をそのまま使える。
   1 のあとに入れると、枝間の依存（§7 のラッチ）を最初から並列構造の上に設計できる。

**`/Dests` を新しい用途に使うときは注意**——書き出されるのは「リンクの飛び先になっている id」
だけで、id を持つだけの要素は出てこない（実装済み仕様 §3.4 に実測表）。回転テーブルの
ラッパ id も、誰からもリンクされないなら同じ落とし穴を踏む。

実装済みの内容は `CHANGELOG.md`、実装時に判明した落とし穴は各仕様書（`docs/archives/`）の「実装記録」節を参照してください。
