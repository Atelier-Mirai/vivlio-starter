# 本文の右に短い表を並べる記法（`.text-table`）の仕様書

> 作成日: 2026-11-05
> ステータス: **仕様確定**（§8 の論点はすべて 2026-11-05 に決定。実装待ち）
> 対象: 32 章の見直しで出た案「短い表は、`text3-img` のように本文の右へ置けばページを節約できる」（2026-11-05 ユーザー提案）
> 決定事項:
> - **記法は `:::{.text-table}` の一つ。** 本文と表を囲むと、本文を左、表を右に並べる。`text-img` 系のような比率の変種（2・3）は作らない。表の列は**表の自然な幅**で、本文が残りの幅を使う。版面の半分程度までを目安としてマニュアルに書き、CSS には本文の列を守る安全弁（表の列は版面の 3 分の 2 まで）だけを置く（§2.2・§3）
> - **grid ではなく flex で組む。** grid の囲みは、前のページに収まる高さでも次のページへ送られることがある（`.side-by-side`・`.pictures` と同じ理由）（§2.2）
> - **行数の上限は設けない。** 並べたブロックはページの途中で分かれないので、表が長いほどページ末で空きが大きくなる。目安（10 行程度まで）をマニュアルに書き、判断は紙面で著者が行う（§3）
> - **表のキャプション（`**…**`・ラベル付きの `**… @label**`）は表と一緒に右の列へ置く**（§2.1）
> - **EPUB・Kindle では、本文、表の順に縦に並べる**（`.side-by-side` と同じ）（§4）
> - **囲みの中に表が無い・二つ以上あるときは、build と preflight で 🟡 を出す**（§5）。先に、原稿の中身の検査（コードフェンス・コンテナの開閉・未知のクラス）を build でも走らせる作業を行い、`.text-table` の検査もそこへ載せる（§7.1）
> 関連: `stylesheets/layout-utils.css`（`.text-img` 系・`.side-by-side`）, `stylesheets/table.css`（表と、ラベルのないキャプション `p:has(> strong:only-child):has(+ table)`）, `lib/vivlio_starter/cli/post_process.rb`（`wrap_img_text_blocks!`・`wrap_side_by_side_column`）, `lib/vivlio_starter/cli/pre_process/cross_reference_processor.rb`（ラベル付きの表を包む `div.cross-ref-table`）, `lib/vivlio_starter/cli/guards/container_scanner.rb`・`container_class_check.rb`, `notation-implementation-guide.md`（【A】CSS 型＋【B】の後処理）, `vivliostyle-css-pitfalls-notes.md`

## 0. 背景

2〜3 列で数行の表（32 章の漢字比率・MATTR・`relative` の倍率など）は、版面の中央に組むと左右が大きく空く。本文の段落も表も短いので、縦に積むと、両方の高さの和だけ紙面を使う。

```
本文（3 行）
                 ┌────┬────┐
                 │範囲│評価│   ← 左右が空く
                 ├────┼────┤
                 │ …  │ …  │   （6 行）
                 └────┴────┘
```

本文を左、表を右に並べれば、使う高さは両者の大きいほう（多くは表の高さ）で済む。画像には同じ目的の `.text-img` 系がある。表にはそれが無い。

```
本文（左の列で 4 行に折り返す）  ┌────┬────┐
                                 │範囲│評価│
                                 ├────┼────┤
                                 │ …  │ …  │
                                 └────┴────┘
```

## 1. 記法

本文の段落と表を `:::{.text-table}` で囲む。本文と表の順は問わない（表は必ず右の列に組む）。

```markdown
:::{.text-table}
本文に占める漢字の割合から、文章の硬さを見ます。技術書では 25〜35% を理想的な範囲としていますが、読者層や扱う分野によって適切な値は変わります。

| 範囲 | 評価 |
|------|------|
| 20% 未満 | 平易 |
| 20〜25% | やや平易 |
| 25〜35% | 適切 |
| 35〜45% | やや難解 |
| 45% 超 | 難解 |
:::
```

- 本文側には、段落・箇条書き・インラインの記法を書ける。複数の段落も書ける。
- 表の直前に `**…**` だけの段落を置くと、表のキャプションになる（今の表と同じ）。ラベル付き（`**漢字比率の評価 @tbl-kanji**`）も書ける。
- 囲みの外側を `::::` にする必要はない（中にコンテナを入れないため）。

## 2. 組み方（PDF）

### 2.1 HTML の形

VFM はコンテナの中身をそのまま並べる。

```html
<div class="text-table">
  <p>本文…</p>
  <p><strong>漢字比率の評価</strong></p>   ← キャプション（任意）
  <table>…</table>
</div>
```

ラベル付きの表は、相互参照の前処理が `div.cross-ref-table`（`p.table-caption` と `table`）に包む。

後処理で、表の側（キャプションの段落と `table`、または `div.cross-ref-table`）を `div.text-table-table` に、それ以外を `div.text-table-body` に包み、子を二つにする。`wrap_img_text_blocks!`（`img-text-body`）と同じ型で、`post_process.rb` の同じ並びに置く。

```html
<div class="text-table">
  <div class="text-table-body"><p>本文…</p></div>
  <div class="text-table-table"><p><strong>…</strong></p><table>…</table></div>
</div>
```

CSS だけで列に振り分けない理由: 本文の段落が複数あると、grid の自動配置では表が本文の 2 段落目の行に入る。flex では、子が 3 つ以上あると 3 列になる。包んでおけば、本文の段落の数によらず 2 列になる。

### 2.2 CSS（`layout-utils.css`）

```css
.text-table {
  display: flex;
  gap: 1rem;
  align-items: flex-start;
  margin-block: 0.5lh;
}

/* 本文は残りの幅をすべて使う。min-inline-size: 0 が無いと、長い語が列を押し広げる */
.text-table > .text-table-body {
  flex: 1 1 0;
  min-inline-size: 0;
}

/* 表は自然な幅。目安は版面の半分（マニュアルに書く）。CSS の上限は本文の列を守る安全弁で、
   横に広い表を囲んでも本文が 1 字ずつ折り返すほど細くならないよう、3 分の 2 で止める */
.text-table > .text-table-table {
  flex: 0 0 auto;
  max-inline-size: calc(100% * 2 / 3);
}

/* 列の上端をそろえる（表の上の余白と、本文の最初・最後の段落の余白を消す） */
.text-table table { margin-block: 0; }
.text-table-body > :first-child { margin-block-start: 0; }
.text-table-body > :last-child { margin-block-end: 0; }
```

- **flex で組む。** grid の囲みは、前のページに収まる高さでも次のページへ送られることがある（`layout-utils.css` の `.side-by-side` のコメント・`vivliostyle-css-pitfalls-notes.md`）。
- **列幅は表の自然な幅（`flex: 0 0 auto`）。** 画像は列の幅に合わせて縮むので比率で決められるが、表の幅は中身で決まる。比率で決めると、狭すぎて表のセルが折り返したり、広すぎて表の横に空きが出たりする。著者が比率を選ぶ手間も無くなる。
- **版面の半分は目安、3 分の 2 は安全弁。** 目安を数 % 超える表は、自然な幅のまま並べられる（CSS で半分に切ると、その分がセルの折り返しになる）。3 分の 2 を超える表は、セルの中で折り返して 3 分の 2 に収まる（`td { overflow-wrap: anywhere }`）。安全弁が無いと、横に広い表を囲んだとき本文の列が数文字幅まで細くなる（§3）。
- キャプションは、今の規則（`table.css` の `p:has(> strong:only-child):has(+ table)` で中央寄せ、`.table-caption`）がそのまま効く。列の中で中央に寄る。

### 2.3 改ページ

並べたブロック（`.text-table`）は、ページの途中で分かれない。収まらなければ、ブロックごと次のページへ送られる。

- 見出しの直後に置いたときは、見出しの `break-after: avoid` で見出しも一緒に送られる（今の段落や表と同じ）。
- `.text-table` の前の段落とは結び付けない。結び付けると、前の段落ごと送られて空きが広がる。

## 3. 向いている表・向かない表

**行数の上限は設けない**（実装でも検査でも）。7 行・8 行の表でも組める。

並べたブロックはページの途中で分かれないので、ページの終わりに来たときは、最大でブロックの高さの分だけ前のページが空く。縦に積んだ 7 行以上の表はページをまたいで分かれる（両側に 2 行以上残す規則・`table.css`）ので、空きは数行で済む。表が長いほど、並べて節約できる行数は増えるが、ページ末での空きも大きくなる。空くかどうかは原稿の位置で決まるので、組んだ紙面で判断するしかない。

マニュアルには目安として次のように書く。

- 10 行程度までの、列の少ない表に向く。
- 表の幅は版面の半分程度までが目安。少し超える表はそのまま並ぶ。版面の 3 分の 2 を超える分は、セルの中で折り返す。
- ページの終わりに来て大きく空いたときは、`:::{.text-table}` を外して通常の表に戻す。

`.long-table`・`.rotate-table` は囲みの中に入れない（長い表・横長の表のための記法で、目的が逆）。

## 4. EPUB・Kindle

縦に並べる。本文、表の順（原稿で表を先に書いた場合も、PDF と同じく本文を先に読ませる）。

```css
body.vs-epub .text-table,
body.vs-kindle .text-table {
  display: block;
}

body.vs-epub .text-table-table,
body.vs-kindle .text-table-table {
  max-inline-size: none;
}
```

- EPUB は読者の画面の幅が分からず、狭い画面では左右とも読めなくなる。Kindle は flex を解さない（`.side-by-side` と同じ理由）。
- 本文、表の順にするのは、後処理で包むときに `text-table-body` を先、`text-table-table` を後に並べ直すことで実現する（縦に積む `display: block` では、CSS の `order` で順を変えられない）。
- 枠もラベルも無いので、Kindle 劣化対策の 3 点セット（`ADMONITION_LABELS` など）は要らない。

## 5. 検査（build と preflight の 🟡）

`ContainerScanner` で `:::{.text-table}` の範囲を取り、中の表を数える（表の行は、`|` で始まり、次の行が区切り行 `|---|` のもの）。

| 状態 | 出すもの |
|---|---|
| 表が無い | 🟡 `contents/32-metrics.md:158 - :::{.text-table} の中に表がありません。本文の右に並べる表を囲みの中に書くか、囲みを外してください` |
| 表が二つ以上 | 🟡 `contents/32-metrics.md:158 - :::{.text-table} の中に表が 2 つあります。右に並べられるのは 1 つだけです。囲みを表ごとに分けてください` |
| `.long-table`・`.rotate-table` が中にある | 🟡 `… :::{.text-table} の中では :::{.long-table} を使えません。短い表だけを囲んでください` |

- 新しい `Guards::TextTableCheck`。§7.1 で build と preflight の両方が走らせる「原稿の中身の検査」の並びに加える。
- 縮退: 検査で 🟡 が出ても、ビルドは止めない。表が無ければ本文だけが全幅で組まれる。表が二つ以上あれば、最初の表（とキャプション）を右の列へ、残りは本文の列へ置く。
- 行数・幅は検査しない（§3）。

## 6. 原稿・文書

| 対象 | 内容 |
|---|---|
| `contents/22-extensions.md` の「表のレイアウト」（@table-layout） | `### .text-table — 本文の右に短い表を並べる` を `.long-table` の前に足す。原稿と組み上がりを示し、§3 の目安を書く |
| `contents/90-notation-cheatsheet.md` の「表」 | 1 行足す（「短い表を本文の右に並べる」→ `:::{.text-table}` で本文と表を囲む） |
| `templates/markdown_snippet.md` の「表」 | 見本を 1 つ足す（早見表と見本帳の整合テスト SC-01 が、クラス名の照合で求める） |
| `contents/32-metrics.md` | 漢字比率・MATTR・`relative` の倍率の表を `.text-table` にする（効果の確かめを兼ねる・§10） |
| `contents/21-markdown-tutorial.md` | 表の節の終わりの「Vivlio Starter では…にも対応しています」に `.text-table` を足す |

原稿と CSS を直したら `ruby scripts/copy_to_scaffold.rb` で雛形へ同期する。

## 7. 実装

| ファイル | 変更 |
|---|---|
| `stylesheets/layout-utils.css` | §2.2・§4 の規則（`.text-img` 系の後ろ、`.side-by-side` の近くに置く） |
| `lib/vivlio_starter/cli/post_process.rb` | `wrap_text_table_blocks!`（§2.1）。`wrap_img_text_blocks!` の隣で呼ぶ。ラベル付きの表の `div.cross-ref-table` ができた後に走ることを確かめ、順の理由をコメントに書く |
| `lib/vivlio_starter/cli/guards/text_table_check.rb` | §5 の検査（新規） |
| `lib/vivlio_starter/cli/samovar/preflight_command.rb`・build の検査（§7.1） | `Guards::TextTableCheck.new` を `ContainerClassCheck` の後に足す |

### 7.1 先に行う作業 — 原稿の中身の検査を build でも走らせる（2026-11-05 実装済み）

コードフェンスの閉じ忘れ（`CodeFenceCheck`）・コンテナの開閉（`ContainerFenceCheck`）・未知のクラス（`ContainerClassCheck`）は preflight だけで走り、`vs build` では何も出ない（2026-11-05 に写しの本で確認。閉じ忘れた `:::{.memo}` と `:::{.notion}` を入れた 32 章を組んで、build は無言、preflight は 🔴 と 🟡）。「場所を指す指摘は build と preflight で同じものを出す」方針に合わせ、build でも同じ指摘を出す。

- 閉じ忘れ（コードフェンス・コンテナ）は preflight と同じく 🔴 で止める（`terminal-output-notes.md` の「このままでは正しく出ない」）。ほか（未知のクラス・改ページの取り残し）は 🟡。
- 章を指定したときは、組む章だけを調べる（2026-11-05 ユーザー判断）。全章を調べると、`vs build 12` が書きかけの 45 章の閉じ忘れで止まる。preflight も同じ範囲にそろえる。
- 検査の並びは `Guards.manuscript_checks` の 1 か所に置き、build と preflight は `VsCommand#run_manuscript_checks!` から呼ぶ。`TextTableCheck` はここへ足す。
- 実装で、記法の通しテストのフィクスチャ（`test/vivlio_starter/fixtures/notation/02-vivlio.md`）にあった、閉じのある 2 行の取り込み（```` ```include: codes/sample.rb ```` の次の行に ```` ``` ````）が見つかった。マニュアルに無い書き方で取り込まれず、閉じの ```` ``` ```` が後ろの節をコードにしていた。マニュアルどおりの 1 行の形に直した。
- 所要時間は 3 つ合わせて 0.03〜0.07 秒（本書 28 章・3 回測定）。章を指定したビルドでも全章を読むが、ビルド全体から見れば無視できる。

- クラスの許可は自動（`ContainerClassCheck` は CSS のクラスセレクタを拾う）。`PREPROCESSED_CLASSES` への登録は要らない。
- 中身は普通の文章なので、`NotationGuard::MACHINE_DATA_CONTAINERS` への登録は要らない。

## 8. 決まったこと（2026-11-05 ユーザー判断）

1. **名前は `.text-table`。**（2026-11-05 決定）`text-img` にそろえた。比率の変種（`text2-table` など）は作らない（§2.2）。
2. **表を左に置く `.table-text` は作らない。**（2026-11-05 決定）`.text-table` だけにする。
3. **版面の半分は目安、CSS には 3 分の 2 の安全弁。**（2026-11-05 決定）数 % はみ出す表も並べられるよう、CSS では 50% に切らず、マニュアルに「版面の半分程度まで」と書く。本文の列が極端に細くならないよう、表の列の上限は版面の 3 分の 2 にする（§2.2）。
4. **検査は build と preflight の両方で出す。**（2026-11-05 決定）先に原稿の中身の検査を build でも走らせる作業（§7.1）を行い、`.text-table` の検査もそこへ載せる。

## 9. テスト計画

1. **後処理**: 本文 1 段落＋表 → `text-table-body`・`text-table-table` の 2 子になる。本文 2 段落・箇条書き入りでも 2 子。キャプション（`**…**`）は表の側へ入る。ラベル付き（`div.cross-ref-table`）はそのまま表の側へ入る。表を先に書いても、本文が先・表が後に並ぶ。
2. **縮退**: 表が無ければ包まない（本文だけ）。表が 2 つなら、最初の表だけが表の側へ入る。
3. **検査**: §5 の 3 通りで 🟡 と行番号。コードフェンスの中の `:::{.text-table}`（記法の解説）は対象にしない（`ContainerScanner` が飛ばす）。
4. **EPUB**: `body.vs-epub`・`body.vs-kindle` で縦に並ぶ規則があること（`epub_kindle_layout_test` の流儀）。
5. **早見表と見本帳**: SC-01 が通る（見本帳に `.text-table` がある）。

## 10. 検証（実装後）

- 32 章の 3 つの表を `.text-table` にして組み、ページ数と、各ブロックで減った行数を数える（本文の段落と表の高さを `pdftotext -bbox` で測る）。
- ページの終わりにブロックが来る位置を、試験用の章で作り、送られたときの空きを確かめる（§2.3）。
- 版面の半分を少し超える表（自然な幅のまま並ぶ）と、3 分の 2 を超える表（セルが折り返す）で、本文の列の幅を見る。
- EPUB と Kindle Previewer で、本文、表の順に縦に並ぶことを見る。

## 11. 考慮した代替案（不採用）

- **`text-img` 系を表にも効かせる**（`.text3-img` の子に `table` を許す）: 名前が画像を指すので、表に使うと原稿が読みにくい。比率で列幅を決めるのも表に合わない（§2.2）。
- **grid で組む**: 前のページに収まる高さでも送られることがある（§2.2）。
- **float で表を右に寄せ、本文を回り込ませる**: 本文が短いと、次の見出しまで表の左に回り込む。見出しに `clear` を掛ける必要があり、ほかの記法（囲み・図）にも影響が広がる。ページをまたぐ float の組み方も Vivliostyle では読みにくい。
- **行数の上限（6 行など）を設けて検査する**: 空くかどうかは行数ではなく原稿の位置で決まる。7〜8 行でも、ページの途中なら並べるほうが得になる（§3）。
