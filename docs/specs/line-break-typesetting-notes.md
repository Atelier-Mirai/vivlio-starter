# 原稿の改行が組版でどうなるか（VFM hardLineBreaks と CJK 連結）

> 作成日: 2026-08-07
> ステータス: **知見メモ（恒久参照）**
> 対象: Markdown 原稿中の改行が PDF/EPUB でどう組まれるか。とくに **段落内の改行が半角空白に化ける**現象と、その回避が `hardLineBreaks: true` に依存していること。
> 関連: `vfm-config-flow-notes.md`（VFM 設定がどこで効くかの流れはあちらが正典。本メモは**組版された結果**を扱う）, `vivliostyle-css-pitfalls-notes.md`
> 実測環境: Vivliostyle cli 11.0.2 / core 2.43.2, VFM (`vfm` CLI), macOS

---

## 0. 一行で

**Vivliostyle は段落内の改行を半角空白にする。CJK 文字間でも削除しない。**
日本語の本文を複数行に分けて書くと、行の継ぎ目ごとに空白が入る。
本プロジェクトがこれを踏まないのは `hardLineBreaks: true`（改行を `<br>` にする）が既定だから。

---

## 1. いつ引くか

- 日本語の本文に**身に覚えのない半角空白**が入っている
- 「一文一行で書きたい」「原稿を git の差分で読みやすくしたい」と考えたとき
- `hardLineBreaks` を `false` にしようとしているとき
- 原稿の末尾に半角スペース 2 つを打つ流儀を採るか迷ったとき

---

## 2. 実測: 4 通りのビルド結果

`vs build` で PDF を作り、pdf-reader で本文を抽出した実測。原稿は 3 文を 3 行に分けたもの。

| | 末尾スペースなし | 末尾スペース 2 つ |
|---|---|---|
| `hardLineBreaks: true` | 3 行に改行 | 3 行に改行（**同一**） |
| `hardLineBreaks: false` | **1 行に連結・間に半角空白** | 3 行に改行 |

```
true_nospace / true_space / false_space
  |吾輩は猫である。|
  |名前はまだ無い。|
  |どこで生れたか頓と見当がつかぬ。|

false_nospace
  |吾輩は猫である。 名前はまだ無い。 どこで生れたか頓と見当がつかぬ。|
```

### 2.1 `true` のとき末尾スペース 2 つは完全に無意味

普通の改行・末尾スペース 2 つ・行末バックスラッシュの 3 通りが、すべて同じ `<br>` になる。
二重の `<br>` にもならず、スペースが残ることもない。
VFM のヘルプにも `--hard-line-breaks: Add <br> ... without needing spaces` とある。

**原稿の書き方として末尾スペース 2 つを推奨する理由はない**（`true` では無効果、`false` では意味を持つ）。

### 2.2 `false` でも明示的な改行手段は生きている

`false` は「改行できないモード」ではなく「**改行を明示するモード**」。

- 末尾スペース 2 つ → `<br>`（CommonMark 標準）
- 行末バックスラッシュ → `<br>`

---

## 3. 空白は実在する（抽出の副作用ではない）

pdf-reader は字間の空きから空白を推測するため、抽出結果の空白だけでは実在の証明にならない。
同じ 3 文を**ソース上 1 行**に書いた対照をビルドして切り分けた。

| 原稿 | 抽出結果 | 文字数 | 空白 |
|---|---|---:|---:|
| ソースも 1 行 | `吾輩は猫である。名前はまだ無い。…` | 32 | **0** |
| ソースは 3 行（`false`） | `吾輩は猫である。 名前はまだ無い。 …` | 34 | **2** |

同一パイプライン・同一抽出器で、違いはソースの改行だけ。**ソースの改行 1 つにつき空白 1 個**が増えている。

---

## 4. 原因は改行そのもの（インデントではない）

VFM は HTML を整形して出力するため、段落内が改行＋インデントで繋がる。

```html
<p>
        吾輩は猫である。
        名前はまだ無い。
      </p>
```

「インデントの空白が残っているのでは」と疑えるが、**違う**。
Vivliostyle へ最小 HTML を 3 種類そのまま渡して切り分けた。

| HTML | 空白 |
|---|---:|
| `<p>あ。い。</p>`（改行なし） | **0** |
| `<p>あ。\nい。</p>`（**裸の改行**・インデントなし） | **2** |
| `<p>\n  あ。\n  い。\n</p>`（VFM の整形出力と同形） | **2** |

裸の改行でも空白になる。**インデントは無関係で、改行そのものが空白に変換されている。**

### 4.1 これは仕様どおりではない

CSS Text Level 3 §4.1.2「Segment Break Transformation Rules」には、
**改行の前後が East Asian Wide/Fullwidth なら改行を削除する**（空白にしない）という規定がある。
実測ではこれが適用されていない。

**したがって `--disable-format-html` では直らない。** HTML の整形をやめても改行は残るため。
`hardLineBreaks: true` で改行を `<br>` に変えてしまう（＝連結を発生させない）のが唯一の回避策。

---

## 5. 日本語の本で `false` を選ぶ理由がない

`false` が `true` と違う結果になるのは、段落の途中に改行があるときだけ。

| 原稿の書き方 | `false` の結果 |
|---|---|
| 段落を 1 行で書く | `true` と**同一の出力**（設定する意味がない） |
| 段落を複数行で書く | 継ぎ目ごとに**不要な半角空白**（設定すると悪化する） |

一文一行（semantic line breaks）で書きたい著者にとって `false` は一見魅力的だが、
日本語では §3 の空白が入るため成立しない。**`false` が優れているケースが存在しない。**

英文主体の本ではこの空白が正しい挙動なので `false` は意味を持つが、
日本語の技術書という本ツールの前提からは外れる。

---

## 6. 現在の実装（2026-08-07 時点）

- 既定値 `true` は `Common.default_vfm`（`lib/vivlio_starter/cli/common.rb`）が供給する
- `book.yml` の `vfm.hard_line_breaks` は **2026-08-07 に削除**した（既定と同値・`false` に選ぶ理由がないため）
- 章ごとの上書きは今も可能。フロントマターに `vfm: { hardLineBreaks: false }` と書けば効く
  （`FrontmatterGenerator#merge_frontmatter` が `value.merge(existing)` で著者の記述を優先する）
- `book.yml`（snake_case `hard_line_breaks`）と VFM フロントマター（camelCase `hardLineBreaks`）で
  キー名が異なる。配線は `FrontmatterGenerator#book_hard_line_breaks?`

---

## 7. 再現手順

```bash
# 4 通りの原稿を作って vs build に通す
printf -- '---\nvfm:\n  hardLineBreaks: false\n---\n\n# 実験\n\n吾輩は猫である。\n名前はまだ無い。\n' > t.md
vs build t.md

# PDF から本文を抽出して空白を数える
ruby -rpdf-reader -e 'puts PDF::Reader.new("t.pdf").pages.first.text'

# エンジン単体で切り分けるなら HTML を直接渡す
vivliostyle build bare.html -o bare.pdf
```
