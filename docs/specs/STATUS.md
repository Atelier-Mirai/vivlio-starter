# Status（仕様書の実装進捗）

> 💡 **運用のルール**
> - 実装が完了したら本ファイルから該当行を削除し、仕様書ファイルは `git mv docs/specs/xxx.md docs/archives/` で移動する（`docs/specs/archives/` ではなく `docs/archives/` が既存の置き場所）。
> - まだ仕様化していないアイデア段階のものは本ファイルではなく `PLANNED.md` に置く。仕様書を書いた時点で本ファイルへ移す。
> - 知見メモ（`*-notes.md`）とガイドラインは本ファイルではなく `NOTES.md` の索引に置く。`docs/specs/` に足したら、あちらへ 1 行足す。
> - 状態が変わったら都度その場で更新する。放置すると `PLANNED.md` に実装済み項目が残り続ける事故が起きる（2026-07-08 に実例あり: `terminal-literal-spec` 完了後も未完了項目として残っていた）。
> - 「メモ（依存関係・実装順序）」に書くのは**実装待ちの仕様書どうしの依存**（「A を先に入れると B が楽」等）だけ。**完了報告は書かない**——それは `CHANGELOG.md` の役目で、両方に書くと必ず片方が stale になる。実装して分かった落とし穴は**その仕様書自身の「実装記録」節**へ書いてから `docs/archives/` へ送る。やり残した作業は `PLANNED.md`（将来対応）か `KNOWN_ISSUES.md`（未解消の不具合・制限）へ移す。

---

## 一覧

| 仕様書 | 内容 |
|---|---|
| `index-main-reference-section-spec.md` | 主要参照を節へ降ろす（章扉を指してしまう問題）／節指定 `21#見出し`／推測を 65% へ／`[igm33]` 記法とフラグ解析の集約。**Phase 1〜3（節へ降ろす・節指定 `21#見出し`・推測 65% と全語への候補）は実装済み**。残りは Phase 4（`[igm33]` 記法とフラグ解析の集約） |

---

## 参考メモ

知見メモ・ガイドライン・検討メモの索引は `NOTES.md` に移しました（本ファイルは「実装済みか？」に専念します）。

---

## メモ（依存関係・実装順序）

`index-code-protection-unification-spec.md`（先行実施ぶん）は **2026-08-02 に実装完了**し `docs/archives/` へ移した。索引のタグ付け結果が実際に動いた（4 章 7 件）ので、以降の 2 本で索引語数の増減を見るときは**その後の状態を基準**にすること。

`chapter-rename-followers-spec.md` は **2026-08-03 に実装完了**し `docs/archives/` へ移した。章名を保持する設定を今後足すときは `ChapterRename::FOLLOWERS` へ登録すること（`config-extension-guidelines.md` §4 の隣）。

`index-term-selection-spec.md` と `index-main-reference-spec.md` は **2026-08-03 に実装完了**し `docs/archives/` へ移した。索引・用語集の仕上げ（RC 対象・仕様書 3 本）はこれで全て終わっている。残るのは**実機目視**だけで、`PLANNED.md`「Kindle Previewer 実機確認の積み残し」に 4 件たまっている。

実装済みの内容は `CHANGELOG.md`、実装時に判明した落とし穴は各仕様書（`docs/archives/`）の「実装記録」節を参照してください。ビルドの枝をまたぐ処理を書くときの前提は `build-pipeline-pitfalls-notes.md` に移しました。
