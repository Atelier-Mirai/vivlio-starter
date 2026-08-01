# 脚注を参照と同一ページに組む（錨を段落末尾から参照位置へ）

> 作成日: 2026-08-01
> ステータス: **実装完了**（2026-08-01）
> 対象: PDF（Vivliostyle）のページ脚注。EPUB / Kindle は対象外（リフローに脚注ページの概念がない）
> 関連: `lib/vivlio_starter/cli/post_process/footnote_converter.rb`, `stylesheets/components.css`

## 1. 症状

参照は p.83 にあるのに、脚注本体が p.84 の下部に組まれていた。ページ下部には**空きがあった**（次のブロックが `break-inside: avoid` で入らず余白が残っていた）ので「ページが一杯だから」ではない。

## 2. 切り分け

**「インライン脚注 `^[…]` だから送られる」のではない。** 参照形式とインライン形式の**順序を入れ替えて実測**したところ、送られるのは常に**後ろの 1 件**だった。

| 原稿の順序 | p.83 | p.84 |
| :--- | :--- | :--- |
| 参照形式 → インライン形式 | 参照形式 | **インライン形式** |
| インライン形式 → 参照形式 | インライン形式 | **参照形式** |

最終 HTML では両者は同型の `<aside class="page-footnote page-footnote-print">` になり、由来の区別は残らない。組版側が形式を区別することは原理的にない。

段落を 2 つに割っても解消しなかった（`aside` の隣接が原因ではない）。直後の `.memo`（`break-inside: avoid`）を外しても解消しなかった。

## 3. 原因

`aside` は**段落の直後**に置かれる。`<aside>` はブロック要素なので `<p>` の中には置けない、という HTML の制約による配置である。

```html
<p>…<a class="footnote-ref">1</a><span class="page-footnote-inline" id="fn1">本文</span>。
   …<a class="footnote-ref">2</a><span class="page-footnote-inline" id="fn2">本文</span>。</p>
<aside class="page-footnote-print" id="fn1">…</aside>   ← float: footnote
<aside class="page-footnote-print" id="fn2">…</aside>   ← float: footnote
```

`float: footnote` の錨は要素の位置なので、**錨は「参照のある行」ではなく「段落の末尾」**になる。段落がページ末尾に掛かると、1 件目を脚注領域へ降ろした時点で残りが尽き、2 件目以降が次ページへ送られる。

## 4. 修正

**錨を参照位置へ移す。** 参照直後には既に `span#fnN`（同内容・画面では非表示）が置かれているので、これを脚注フロートにする。参照のある行に紐づくため、入りきらないときは**行ごと**次ページへ送られ、参照と脚注が離れない。

```css
@media print {
  span.page-footnote.page-footnote-inline {
    display: inline !important;
    float: footnote;
  }
  span.page-footnote.page-footnote-inline::before { content: attr(data-footnote-number) ". "; }
  /* 参照番号は既存の <a class="footnote-ref"><sup>N</sup></a> が描く。
     自動生成の呼び出し／マーカーを消さないと番号が二重になる（実測「11」「22」）。 */
  span.page-footnote.page-footnote-inline::footnote-call,
  span.page-footnote.page-footnote-inline::footnote-marker { content: none; }

  aside.page-footnote[data-footnote-anchored] { display: none !important; }
}
```

`span` は番号を持っていなかったので `data-footnote-number` を付与した（`build_inline_footnote_node`）。

### 4.1 `aside` は消さずに隠す

`aside` を DOM から削らないのは、後処理（`process_sideimage_footnotes!` の URL 突合、`renumber_footnotes_by_document_order!` の出現順再番号付け）が `aside` を辿るため。**span を伴う `aside` にだけ** `data-footnote-anchored="1"` を付け、それを CSS で隠す。

**一律に隠してはならない。** `append_unused_footnotes_to_body!` が本文末尾へ足す sideimage 由来の `aside` には対応する span が無く、隠すと脚注が消える（実測: 本書に 1 件、`00-preface` の `https://vivliostyle.org/`）。属性が付くのは span を必ず挿入する 2 経路（`insert_print_footnote_after_paragraph!` / `insert_print_footnote_after_anchor!`）だけ。

クラスでなく `data-` 属性にしたのは `img[data-vs-raster]` と同じフック方式に揃えるため（既存テストが `class="page-footnote page-footnote-print"` を厳密一致で見ている事情もある）。

## 5. 検証（2026-08-01）

- 該当箇所: 参照 p.83 / 脚注 p.83 の**同一ページ**（2 件とも）
- 全書の脚注 19 件すべてが PDF に描画される（span 18＋非 anchored aside 1）
- sideimage 由来の脚注（span なし）は従来どおり `aside` 自身が描く（p.7 に掲載を確認）
- `rake test` 2159 runs / 0 failures、`rubocop` no offenses
- EPUB / Kindle は `@media print` の外なので影響なし（EPUB の脚注参照数に変化なし）
