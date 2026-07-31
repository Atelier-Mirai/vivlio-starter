# kindle-rotate-table-image-spec

Kindle で回転テーブル（`.rotate-table`）を**画像に劣化させ、90 度回転してページ中央に**表示する。

- 状態: **仕様（実装待ち）**
- 起点: 2026-07-31、実機確認で Kindle だけ回転が効いていないことが判明（`kindle_rotate_table.png`）
- 対象: Kindle（KFX）のみ。PDF・クリーン EPUB は現状のまま

---

## 1. 症状

| ターゲット | 表示 |
|---|---|
| PDF | 専用ページに 90 度回転して中央配置（意図どおり） |
| クリーン EPUB | 90 度回転してページ中央（意図どおり） |
| **Kindle** | **回転せず通常の表**。列幅が詰まって「スキルレベル」「リモート勤務」が折り返され、横に長い表は見切れる |

## 2. 原因

`.rotate-table > table` は `position: absolute` ＋ `transform: translate(...) rotate(-90deg) scale(...)` で回転している（`stylesheets/table.css`）。**KFX は `transform` と `position: absolute` のいずれも解さない**ため、宣言ごと無視されて素の表に戻る。

これは `kindle-css-compatibility-notes.md` に並ぶ既知の制約（`var()` / `color-mix()` / flex / 擬似要素が効かない）と同じ性質で、CSS では解決できない。**Kindle 向けには画像へ劣化させる**——本プロジェクトが数式（SVG）・mermaid（PNG）・章扉/節絵（合成 JPEG）で既に採っている方針をそのまま適用する。

## 3. 方式の候補

### 案 A: 生成済み PDF のページを切り出す（推奨）

回転テーブルは PDF では**専用ページ**に組まれる（`.rotate-table { break-before: page; break-after: page }`）。そのページを画像化すれば、**PDF と完全に同じ見た目**が手に入る。

1. `TableConverter` が `.rotate-table` ラッパへ一意の `id`（例 `rot-<章スラッグ>-<連番>`）を振る
2. Vivliostyle は id を持つ要素の named destination を PDF に書き出す。`PdfPageMapExtractor`（`build/pdf_page_map_extractor.rb`）が既にこの仕組みで「アンカー ID → 通しページ番号」を取っているので、同じ経路で回転テーブルのページを引く
3. `pdftoppm -r <dpi> -f N -l N` でそのページを PNG 化し、ノンブル・柱を含む余白を切り落とす（`print_geometry` の版面寸法から算出できる）
4. `EpubBuilder` の Kindle フレーバで `.rotate-table` の中身を `<img>` へ置換する（数式・mermaid と同じ差し替え位置）

**利点**: レンダラを新たに用意しない。PDF と寸分違わぬ結果。回転・センタリング・scale の追い込みが 1 箇所（PDF 側）で完結する。

**制約**: `output.targets` に `pdf` が含まれないビルドでは PDF が無い。その場合は
- (a) Kindle 用に内部的に PDF を 1 本作る（重い）
- (b) 画像化を諦めて現状の素の表へ縮退し、🟡 で「PDF を同時に出力すると回転表を画像化できます」と案内する ← **こちらを採る**（`warning-messages-actionable` の方針）

### 案 B: 表だけを別レンダリングして画像化

回転テーブルの HTML 断片を単体の HTML に組み、Vivliostyle か Chromium で 1 ページだけ描画して画像化する。

**利点**: PDF の有無に依存しない。
**欠点**: レンダラの起動が表の数だけ増える（`node26-puppeteer-extract-hang` の教訓どおり Chromium 起動は高コスト）。フォント・CSS の読み込み経路を別途用意する必要があり、PDF と 1 対 1 の見た目を保証しにくい。

### 案 C: ImageMagick で表を描く

**採らない**。セル結合・ルビ・アイコンなど本文の表現力を再現できない。

## 4. 実装メモ（案 A）

- **id の付与**は `TableConverter` の `.rotate-table` 生成箇所。著者が `@id` を書いていればそれを使い、無ければ自動採番（クロスリファレンスの `@auto` と同じ考え方で、本文からは参照しない内部 ID）
- **ページ引き**は `PdfPageMapExtractor::PageMapping` をそのまま使えるか要確認。現在は用語集バックリンク（`gls-src-*`）と索引に限定して集めている可能性があるため、任意 id を引ける入口が要る
- **切り出し元の PDF は「1 回目のレンダ（dedup 前）」の出力**とする。理由と待ち時間への影響は §7
- **切り出し解像度**は Kindle の端末幅（1072px 以上）を満たす値。`HeadingImageComposer::RENDER_WIDTH`（1400）と揃えるのが自然
- **生成物のキャッシュ**は `GeneratedAssetCache` に内容アドレスで置く（章扉・節絵・mermaid と同じ）。鍵には「表の HTML＋scale/shift-y＋版面寸法」を混ぜる
- **alt テキスト**は表のプレーンテキスト（読み上げ・検索のフォールバック）。数式画像が alt に TeX を入れているのと同じ扱い
- **クリーン EPUB は据え置く**。現状 90 度回転が効いており、画像化すると拡大時に劣化する

## 5. テスト

1. `TableConverter`: `.rotate-table` に id が付くこと・著者指定の `@id` を尊重すること
2. ページ引き: 既知の id から通しページ番号が取れること（`pdf_page_map_extractor_test` の拡張）
3. `EpubBuilder`: Kindle フレーバでのみ `<img>` へ置換されること・クリーン EPUB は不変であること
4. 縮退: PDF が無いターゲット構成で 🟡 が出て、素の表のまま落ちること
5. 手動: Kindle Previewer で回転・センタリング・可読性を確認

## 6. スコープ外

- **クリーン EPUB の画像化**: 現状の回転が効いているため不要
- **横長の表全般の自動画像化**: 対象は `.rotate-table` を明示した表のみ。著者が「回して見せたい」と宣言したものだけを扱う

---

## 7. 並列ビルドとの関係（2026-08-01 追記）

`build-target-parallelization-spec.md` は、共通前段のあと **PDF 枝と EPUB/Kindle 枝を
並列に走らせる**（実測 −130.5s）。案 A は「生成済み PDF のページを切り出す」方式なので、
実装すると **Kindle が PDF 枝の成果物に依存し、枝の独立性が崩れる**。

壁時計への影響は、**どちらのレンダを切り出し元にするか**で大きく変わる。

| 切り出し元 | Kindle 枝が待つ時刻 | 影響 |
|---|---|---|
| dedup 後の `_sections.pdf` | 16.19 + 148.06 + 153.43 = **317.7s** | Kindle の作業がここから始まり、PDF 枝（422.7s）と競る |
| **1 回目の `build overall pdf` の出力** | 16.19 + 148.06 = **164.3s** | 余裕を持って PDF 枝の陰に収まる |

**1 回目のレンダを使う。** dedup が消すのは用語集・索引のバックリンクと本文の † マークで、
**回転テーブルの中身は 1 文字も変わらない**。変わるのはページ番号だけだが、
「id → ページ番号」を引くのと「そのページを切り出す」のを**同じ PDF に対して**行う限り、
ずれようがない。dedup 後の PDF を待つ理由は無い。

したがって実装時は次を守る。

1. 切り出し元は **dedup 前の 1 回目のレンダ出力**（`build overall pdf` の成果物）
2. **ページ引きと切り出しは必ず同一の PDF に対して行う**。片方を dedup 後にすると
   ページがずれ、しかも「隣のページを切り出した」ことに気付けない
3. 並列化後は、Kindle 枝がこの PDF の生成完了を待つラッチを持つ

**実装順序は「並列化 → 回転テーブル」が安全**である。逆順だと、依存を後から
並列構造へねじ込むことになる。並列化より先に着手する場合は、上記 1〜3 を満たしておけば
あとから枝へ載せられる。

なお §3 案 A の縮退条件（`output.targets` に `pdf` が無いビルドでは素の表へ落として 🟡 で案内）は
並列化後も変わらない。**PDF 枝が存在しないビルドではラッチも存在しない**だけである。
