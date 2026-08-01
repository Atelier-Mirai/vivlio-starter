# PDF のコード行番号を論理行へ対応させる（F 案の PDF 展開）

> 作成日: 2026-08-01
> ステータス: **実装完了**（2026-08-01 / 寸法の是正は 2026-08-02 → §5）
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
  padding-left: 2.4em;
  text-indent: -2.4em;   /* 1 行目だけ左へ戻す＝番号が行頭・折返し行はコード開始位置へ揃う */
  counter-increment: linenumber;
}
pre[class*="language-"].line-numbers > code > .vs-code-line::before {
  content: counter(linenumber);
  display: inline-block;
  width: 2.4em; padding-right: 0.6em;  /* border-box なので width が総幅（§5.1） */
  text-indent: 0;                      /* 親の負の text-indent を番号自体に効かせない */
}
```

**`::before` の総幅は `padding-left` と厳密に一致させる。** `box-sizing: border-box` が効いているので `width` が総幅である（§5.1 に経緯）。

`counter-reset: linenumber` は既存の `pre.line-numbers` の規則をそのまま使うので、範囲 include（`data-start` のインライン `counter-reset`）による開始番号の上書きも従来どおり効く。

絶対配置ガターの規則は**残す**——行ブロック化に失敗して `pre` が素のまま残ったときの安全網（EPUB 側の A 案残置と同じ考え方）。

## 4. 検証（2026-08-01）

- 折返しのある論理行に番号が 1 つだけ付き、続きはコード開始位置へぶら下がる（目視・22 章 p.6）
- 折返しの後ろの論理行にも正しく番号が付く（以前は最終行の番号が消えていた）
- 全書ビルドで 22 章のコード 70 件を行ブロック化、変換失敗 0 件
- EPUB は `vs-code-epub` / `vs-code-line`（F 案）のまま・`line-numbers-rows` の混入なし
- `rake test` 2159 runs / 0 failures、`rubocop` no offenses

## 5. 追補（2026-08-02）— 寸法と box-sizing

初回実装後の実機確認で 3 点の指摘があり、いずれも寸法まわりだったので記録する。

### 5.1 折返し行が 1 行目と揃わない真因は `box-sizing: border-box`

`base.css` が `*, *::before, *::after { box-sizing: border-box }` を掛けている。
したがって番号欄の `width` / `inline-size` は**padding を含んだ総幅**である。

| | 記述 | 実際の総幅 | `padding-left` | ずれ |
| :--- | :--- | ---: | ---: | ---: |
| PDF（初回実装） | `width:3em` ＋ `padding-right:0.8em` | 3em | 3.8em | 0.8em |
| クリーン EPUB（従来） | `inline-size:2.5em` ＋ `padding-inline-end:0.6em` | 2.5em | 3.1em | 0.6em |

content-box のつもりで「数字幅 ＋ 余白」と足し算していたため、総幅が `padding-left`
より狭くなり、**1 行目の本文開始位置だけが左へ寄っていた**（折返し行が右にずれて
見えるが、実際にずれているのは 1 行目のほう）。PDF・EPUB で症状が同型だったのは
同じ足し算をしていたため。

**総幅を `padding-left` と同値にする**（PDF・EPUB とも 2.4em）。これは
`epub-code-line-numbers-spec.md` の F 案が最初から抱えていた欠陥で、PDF への
展開で初めて 2 ターゲット同時に露見した。

### 5.2 Kindle は桁数を固定する

Kindle は `::before` を解さないため番号を実テキストで注入する（`vs-code-ln`）。
桁数を**ブロックごとの最大値**に合わせていたので、番号欄の実幅がブロックごとに
変わり、CSS の `padding-left`（固定値）と対応しなかった。**3 桁固定**（＋区切り
1 文字 ＝ 4 文字）に変更し、等幅で 2.4em に対応させる。PDF・クリーン EPUB が
常に 2.4em の番号欄を確保するのとも揃う。

### 5.3 `pre` のガター用余白と縦罫を外す

- `pre.line-numbers { padding-left: 3.8em }` は絶対配置ガター時代の名残。行ブロックが
  自前で番号欄を持つので**二重の余白**になり、コードの開始位置が版面の内側へ大きく
  寄っていた（「行番号の幅が広すぎる」の実体）。撤去した。
- 番号の右の縦罫（`border-right`）は `::before` にしか付かない＝**各論理行の 1 行目に
  しか出ない**ため、折り返すと罫が途切れて見える。EPUB / Kindle は元から罫なしなので、
  PDF も罫なしへ揃えた。

行番号欄は 2.4em（等幅 3 桁＋区切り）で 3 ターゲット共通になった。
