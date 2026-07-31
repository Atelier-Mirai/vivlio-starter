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
