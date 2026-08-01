# PDF のコード行番号を論理行へ対応させる（F 案の PDF 展開）

> 作成日: 2026-08-01
> ステータス: **実装完了**（2026-08-01）
> 対象: PDF のコードブロック行番号。EPUB / Kindle は `epub-code-line-numbers-spec.md` で解決済み
> 関連: `lib/vivlio_starter/cli/code_line_blocks.rb`（新規・正典）, `lib/vivlio_starter/cli/build/pdf_builder.rb`, `stylesheets/prism.css`

## 1. 症状

論理行が折り返すと、続きの表示行が**次の番号を貰って**しまい、以降が 1 つずつ繰り上がって最後の論理行の番号が消える。

```
1  :::{.notice}
2  `--force` オプションは既存ファイルを上書きします。実行     ← 論理行 2
3  前にバックアップを取ってください。                          ← 同じ論理行 2 の折返しが「3」を取る
   :::                                                        ← 論理行 3 に番号が無い
```

原稿は 3 行なのに、番号と行の対応が崩れる。EPUB では同じ原稿が正しく組まれていた。

## 2. 原因 — 先行仕様の前提が誤っていた

`epub-code-line-numbers-spec.md` §0 は現状整理でこう書いていた:

> **PDF**: Prism `.line-numbers-rows`（絶対配置ガター）。ページ幅固定のため崩れない。**本仕様の変更対象外**。

**この前提が成り立っていない。** 「ページ幅が固定」であることと「行が折り返さない」ことは別で、`code.css:23` が全 `pre` に `white-space: pre-wrap`（＋`line-break: anywhere`）を掛けているため、PDF でも版面幅を超えた行は折り返す。

`.line-numbers-rows` は**固定行高の `<span>` を論理行の数だけ絶対配置で並べる**だけなので、コード側が折返しで背高になると番号列と噛み合わなくなる。クリーン EPUB で解決済みだった「長行折返しで番号がずれる」問題（同 §0）と**同一の症状**が、PDF に残っていた。

## 3. 修正 — EPUB と同じ F 案を PDF にも敷く

「1 論理行 = 1 ブロック要素＋ぶら下げインデント」。折返しはブロック内で完結するので、番号は必ず論理行の先頭に付く。

### 3.1 構造（`pre` は残す）

PDF では `pre` を残し、`code` の中身だけを組み直す。枠・背景・フォントの既存 CSS をそのまま活かすため（EPUB は `pre` ごと `div.vs-code-epub` へ置換する。リフロー側は `pre` の `overflow` がページ送りを妨げるという別事情がある）。

```html
<pre class="language-markdown line-numbers"><code class="language-markdown line-numbers"
  ><span class="vs-code-line">Vivliostyle は …</span><span class="vs-code-line">…</span></code></pre>
```

変換は `PdfBuilder#convert_code_lines_for_pdf!` が **`pdf/` のコピーにだけ**掛ける（`stage_workspace_htmls!` から呼ぶ）。`html/` の原本は `pre.line-numbers` のままなので、そこを読む EPUB 経路は影響を受けない。単章ビルドも `stage_workspace_htmls!` を通るので同じ経路に乗る。

### 3.2 分割の意味論は共有する（`CodeLineBlocks`）

トークン `span` が行を跨ぐケース（複数行コメント・文字列）があるため、`\n` で素朴に割ると色が壊れる。行ごとに開いている `span` を閉じ、次行の冒頭で開き直す必要がある。この処理は EPUB 側に既にあったので、**`cli/code_line_blocks.rb` へ引き上げて両者で共有**した（`notation-implementation-guide.md` §2「同じ責務のコードを書き始めたら基盤側に API を足すサイン」）。`EpubBuilder#split_code_into_lines` は委譲するだけになり、道連れで不要になったエスケープ補助 2 つを撤去した。

### 3.3 寸法（番号欄の幅は厳密に一致させる）

```css
pre[class*="language-"].line-numbers > code > .vs-code-line {
  display: block;
  padding-left: 3.8em;
  text-indent: -3.8em;   /* 1 行目だけ左へ戻す＝番号が行頭・折返し行はコード開始位置へ揃う */
  counter-increment: linenumber;
}
pre[class*="language-"].line-numbers > code > .vs-code-line::before {
  content: counter(linenumber);
  display: inline-block;
  width: 3em; padding-right: 0.8em;   /* 合計 3.8em ＝ padding-left と一致させること */
  text-indent: 0;                      /* 親の負の text-indent を番号自体に効かせない */
}
```

**`::before` の総幅（`width` ＋ `padding-right`）は `padding-left` と厳密に一致させる。** 最初 `margin-right: 0.4em` を足して 4.2em にしたところ、折返し行の頭が 1 行目の本文開始位置より 0.4em 左にずれた（実測）。

`counter-reset: linenumber` は既存の `pre.line-numbers` の規則をそのまま使うので、範囲 include（`data-start` のインライン `counter-reset`）による開始番号の上書きも従来どおり効く。

絶対配置ガターの規則は**残す**——行ブロック化に失敗して `pre` が素のまま残ったときの安全網（EPUB 側の A 案残置と同じ考え方）。

## 4. 検証（2026-08-01）

- 折返しのある論理行に番号が 1 つだけ付き、続きはコード開始位置へぶら下がる（目視・22 章 p.6）
- 折返しの後ろの論理行にも正しく番号が付く（以前は最終行の番号が消えていた）
- 全書ビルドで 22 章のコード 70 件を行ブロック化、変換失敗 0 件
- EPUB は `vs-code-epub` / `vs-code-line`（F 案）のまま・`line-numbers-rows` の混入なし
- `rake test` 2159 runs / 0 failures、`rubocop` no offenses
