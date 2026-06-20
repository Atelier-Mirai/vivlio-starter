# SVG Luster / Type 3 Font Bugfix Technical Notes

## 1. 目的

`svg_luster_bugfix_spec.md` に基づき、Vivlio Starter (`vs`) の PDF 生成において Chromium / Vivliostyle が混入させる Type 3 フォントを排除し、同時に画像化した記号・絵文字の見た目を保つために行った調査・実装の記録である。

後日同種の問題を再調査するときに、以下をすばやく確認できるようにする。

- Type 3 フォント混入時の調査手順
- 根本原因の分類
- 実装で重要だったポイント
- 検証コマンドと結果の読み方

## 2. Investigation: PDF構造の調査結果

### 2.1 使用した主なコマンド

```sh
pdffonts vivlio_starter_v1.0.0.pdf
pdffonts _sections.pdf
pdffonts _titlepage_legalpage.pdf
pdffonts _colophon.pdf
pdffonts _toc.pdf

qpdf --qdf --object-streams=disable vivlio_starter_v1.0.0.pdf vivlio_starter_v1.0.0.qdf.pdf
grep -an "Subtype /Type3\|beginbfchar\|beginbfrange\|<301C>" vivlio_starter_v1.0.0.qdf.pdf

pdfimages -list vivlio_starter_v1.0.0.pdf
pdftotext -layout vivlio_starter_v1.0.0.pdf vivlio_starter_v1.0.0.txt
```

`pdffonts` は PDF 実体に Type 3 が残っているかを最も簡潔に確認できる。macOS Preview の「文書のプロパティ」はキャッシュや表示差があるため、最終判断は `pdffonts` と Acrobat Reader の結果を優先した。

### 2.2 確認された Type 3 の典型パターン

調査中に確認した Type 3 には以下の種類があった。

| Type 3化した要素 | PDF内部の手がかり | 主な原因 |
|---|---|---|
| h3/h4 マーカー記号 | `♣`, `♦` 相当 | CSS custom property / generated content が `EmojiReplacer` を通らない |
| タイトル・奥付の波線装飾 | ToUnicode に `U+301C` / `U+FF5E` 系 | CSS `content` / custom property による文字装飾 |
| 囲み数字 | `①`〜`⑤` など | 通常テキストまたは属性・見出し由来の特殊記号 |
| セクション番号の縁取り | ToUnicode で `1`〜`9`, `-` | `-webkit-text-stroke` による Chromium の描画変換 |
| code fallback | `Osaka` Type 3 | `--code-font` 未定義時のOS既定 monospace fallback |

最終確認時点では、`pdffonts vivlio_starter_v1.0.0.pdf` は以下のように CID TrueType のみとなり、Type 3 は存在しないことを確認した。

```text
name                                 type              encoding         emb sub uni object ID
------------------------------------ ----------------- ---------------- --- --- --- ---------
AAAAAA+ZenKakuGothicNew-Bold         CID TrueType      Identity-H       yes yes yes     99  0
BAAAAA+ZenOldMincho-Regular          CID TrueType      Identity-H       yes yes yes    100  0
AAAAAA+ZenKakuGothicNew-Bold         CID TrueType      Identity-H       yes yes yes    108  0
BAAAAA+ZenOldMincho-Regular          CID TrueType      Identity-H       yes yes yes    109  0
CAAAAA+ZenOldMincho-Bold             CID TrueType      Identity-H       yes yes yes    110  0
DAAAAA+HackGen35-Regular             CID TrueType      Identity-H       yes yes yes    111  0
EAAAAA+ZenKakuGothicNew-Regular      CID TrueType      Identity-H       yes yes yes    112  0
FAAAAA+HackGen35-Bold                CID TrueType      Identity-H       yes yes yes    319  0
CAAAAA+ZenOldMincho-Bold             CID TrueType      Identity-H       yes yes yes   2518  0
AAAAAA+ZenKakuGothicNew-Bold         CID TrueType      Identity-H       yes yes yes   2519  0
BAAAAA+ZenOldMincho-Regular          CID TrueType      Identity-H       yes yes yes   2520  0
```

### 2.3 `-webkit-text-stroke` の追加検証

一度 Techbook 注入CSSで `.section-topic h2 .section-number` の `-webkit-text-stroke` を無効化したところ Type 3 は消えた。

その後、検証のため無効化を解除すると、以下の Type 3 が再現した。

```text
AAAAAA+ZenKakuGothicNew-Bold         Type 3            Custom           yes yes yes    296  0
AAAAAA+ZenKakuGothicNew-Bold         Type 3            Custom           yes yes yes    297  0
```

このため、`-webkit-text-stroke` は Type 3 発生要因であると判断した。

最終方針としては、見た目差をすべての出力形式で揃えるため、`image-header.css` 側の `-webkit-text-stroke` 自体を削除せずコメントアウトした。

## 3. Root Cause Analysis: 根本原因分析

### 3.1 CSS generated content は `EmojiReplacer` をバイパスする

`EmojiReplacer` は HTML テキストノードを対象に絵文字・記号を画像化する。一方、CSS の以下のような文字列は HTML テキストノードではない。

```css
:root {
  --h3-marker: "♣";
  --h4-marker: "♦";
}

h4::before {
  content: var(--h4-marker, "◆");
}
```

このため、`♣` / `♦` は `EmojiReplacer` の置換対象にならず、Chromium が文字として描画しようとする。その結果、PDF 内で Type 3 フォントとして埋め込まれることがあった。

### 3.2 フロントページ生成順序による置換漏れ

通常章の HTML は Step 5c の Techbook post-process で処理される。しかし、タイトルページ・リーガルページ・奥付は Step 9 で後から再生成される。

このため、Step 5c だけでは `_titlepage.html`, `_legalpage.html`, `_colophon.html` に対する波ダッシュ置換や絵文字画像化が漏れる。

対策として、Step 9 の特殊ページHTML生成直後にも Techbook post-process を再実行するようにした。

### 3.3 汎用 `img` border が絵文字画像にも適用される

`chapter-common.css` には著者図版向けの汎用 `img` 枠線がある。

```css
img {
  max-inline-size: 100%;
  border: solid 0.5mm var(--color-border);
}
```

絵文字を `<img>` に置換すると、この枠線が絵文字にも適用され、灰色のノイズになる。

対策として、絵文字画像には `vs-emoji` class を付け、Techbook CSS で `border: none !important` を指定した。

### 3.4 CSS text stroke は Chromium PDF で Type 3 化しやすい

`image-header.css` のセクション番号には、視認性向上のため `-webkit-text-stroke` が使われていた。

```css
.section-topic h2 .section-number {
  -webkit-text-stroke: 0.3mm rgba(0, 0, 0, .30);
}
```

検証の結果、このプロパティを有効にすると `ZenKakuGothicNew-Bold` の Type 3 が再発した。

削除はせず、将来必要に応じて戻せるようコメントアウトした。

## 4. Implementation Details: 実装詳細

### 4.1 Techbook 後処理の集約

`Vivlio::Starter::CLI::Techbook::Processor` に `post_process_html_files!` を追加し、以下を一括実行するようにした。

1. Techbook 用 WebP アセット生成
2. HTML内 SVG 参照の WebP 参照化
3. h3 マーカー span の正規化
4. 旧CSS丸数字 span の WebP 画像化
5. 波ダッシュ置換・丸数字画像化・絵文字画像化
6. CSS 注入

CSS注入は既存ブロックを置換するため、複数回実行しても二重注入されない。

### 4.2 CSS注入の冪等化

注入CSSは以下のコメントで囲む。

```html
<!-- Vivlio Starter Techbook CSS BEGIN -->
<style>
...
</style>
<!-- Vivlio Starter Techbook CSS END -->
```

再実行時はこの範囲を正規表現で削除してから新しいCSSを注入する。

```ruby
TECHBOOK_CSS_BLOCK_REGEX = /\n?<!-- Vivlio Starter Techbook CSS BEGIN -->.*?<!-- Vivlio Starter Techbook CSS END -->\n?/m
```

### 4.3 h3 マーカーの正規化

`HeadingProcessor` は h3 に以下のような marker span を生成する。

```html
<span class="subsection-marker">♣</span>
```

Techbook mode では、この中身を空にして CSS background image で描画する。

```html
<span class="subsection-marker" aria-hidden="true" role="presentation"></span>
```

正規化には以下の意図がある。

- `♣` をHTMLテキストとして残さない
- `img alt="♣"` も残さない
- 表示は WebP 背景画像に一本化する

### 4.4 h3/h4 マーカーの色付き WebP 化

`stylesheets/twemoji/2663.svg` と `2666.svg` を読み、`fill` を `theme.color` に対応する HEX 色へ置換した上で、`vs-techbook` ディレクトリへ専用SVGとして出力する。

- `stylesheets/twemoji/vs-techbook/marker-h3.svg`
- `stylesheets/twemoji/vs-techbook/marker-h3.webp`
- `stylesheets/twemoji/vs-techbook/marker-h4.svg`
- `stylesheets/twemoji/vs-techbook/marker-h4.webp`

CSSでは `mask-image` ではなく `background-image` を使う。mask は別の PDF 描画問題を誘発する可能性があるため避けた。

### 4.5 丸数字の WebP 化

`①`〜`⑳` はテキストのまま残すと Type 3 化しやすいため、Techbook mode では画像に置換する。

例:

```html
<img src="stylesheets/twemoji/vs-techbook/circled-1.webp" alt="1" aria-label="1" class="emoji vs-emoji vs-circled-number" width="1em" height="1em" style="vertical-align: -0.12em;">
```

CSSで円を描く方式も試したが、文字位置が微妙にずれ、美観面で不採用とした。現在は SVG source を生成して WebP にラスタライズする方式を採っている。

### 4.6 subtitle wave の WebP 化

`titlepage.css` / `colophon.css` の `.subtitle--wave` は CSS custom property に波線文字を持っていた。

```css
.subtitle--wave {
  --subtitle-prefix: "～";
  --subtitle-suffix: "～";
}
```

Techbook mode ではこれを空にし、`wave.webp` を背景画像として表示する。

### 4.7 `img.vs-emoji` の border 打ち消し

絵文字画像は通常図版とは異なるため、以下で枠線を必ず無効化する。

```css
img.vs-emoji {
  display: inline;
  width: 1em;
  height: 1em;
  vertical-align: -0.15em;
  border: none !important;
  box-shadow: none;
  background: transparent;
  padding: 0;
  margin: 0;
}
```

`!important` を付けているのは、汎用 `img` セレクタや図版用セレクタより確実に勝たせるためである。

### 4.8 `--code-font` fallback の修正

`code.css` は `var(--code-font)` を参照するが、定義側は `--font-code` だった。

これによりOS既定 monospace fallback が入り、環境によって `Osaka` が Type 3 化する可能性があった。

Techbook CSS で以下を注入する。

```css
:root {
  --code-font: var(--font-code);
}

code,
pre,
code[class*="language-"],
pre[class*="language-"] {
  font-family: var(--font-code), monospace !important;
  text-shadow: none !important;
}
```

### 4.9 `-webkit-text-stroke` のコメントアウト

全出力形式で見た目差を出さないため、Techbook専用CSSで無効化するのではなく、元CSS側をコメントアウトした。

対象:

- `stylesheets/image-header.css`
- `lib/project_scaffold/stylesheets/image-header.css`

コメントアウト後:

```css
.section-topic h2 .section-number {
  font-size: calc(1em * 1.1);
  font-weight: 900;
  color: var(--section-number-color);
  /* Type 3 font avoidance: Chromium PDF can emit stroked text as Type 3.
     Keep the former visual treatment here for future reference.
     -webkit-text-stroke: 0.3mm rgba(0, 0, 0, .30); */
  white-space: nowrap;
  flex-shrink: 0;
  margin-inline-start: clamp(6mm, calc(var(--paper-scale) * 8mm), 10mm);
}
```

## 5. Verification: 検証

### 5.1 テスト

```sh
ruby -c lib/vivlio/starter/cli/techbook/processor.rb
bundle exec ruby -Itest test/vivlio/starter/cli/techbook/processor_test.rb
bundle exec ruby -Itest test/vivlio/starter/cli/techbook/emoji_replacer_test.rb
```

確認済み結果:

```text
Syntax OK
14 runs, 76 assertions, 0 failures, 0 errors, 0 skips
9 runs, 24 assertions, 0 failures, 0 errors, 0 skips
```

### 5.2 PDFフォント確認

```sh
pdffonts vivlio_starter_v1.0.0.pdf
```

Type 3 が残っている場合は `type` 列に `Type 3` が出る。修正後は CID TrueType のみになる。

中間PDFも確認する。

```sh
pdffonts _sections.pdf
pdffonts _titlepage_legalpage.pdf
pdffonts _colophon.pdf
pdffonts _toc.pdf
```

### 5.3 PDF内部調査

Type 3 が残る場合は QDF 化して ToUnicode を見る。

```sh
qpdf --qdf --object-streams=disable vivlio_starter_v1.0.0.pdf vivlio_starter_v1.0.0.qdf.pdf
grep -an "Subtype /Type3\|beginbfchar\|beginbfrange\|<301C>" vivlio_starter_v1.0.0.qdf.pdf
```

ToUnicode に `0031`〜`0039` や `002D` が出る場合、数字やハイフンが何らかの特殊描画で Type 3 化している可能性が高い。

`301C` が出る場合、波ダッシュ系の文字列がまだCSSまたはHTMLに残っている可能性がある。

## 6. 注意点

### 6.1 Preview のフォント表示だけで判断しない

macOS Preview はPDFを開きっぱなしにしていると古いフォント情報を表示することがある。Type 3 の有無は以下で確認する。

1. `pdffonts`
2. Acrobat Reader
3. 必要に応じて QDF 解析

### 6.2 `lib` 変更後は gem reinstall が必要

ローカル開発中の `lib` 変更は、インストール済み `vs` コマンドには自動反映されない。

```sh
rake reinstall
vs clean --all
vs build --no-clean --log=debug > build.log
```

### 6.3 SVGを直接PDFへ渡さない

SVG内の `<path>` / `<text>` は Chromium PDF で Type 3 相当の構造を生むことがある。Techbook mode では、SVG source を生成しても最終HTML/PDFでは WebP を参照する。

## 7. まとめ

今回の修正の肝は以下である。

- CSS generated content は HTML テキスト置換をバイパスするため、CSS由来の記号は別途画像化する。
- フロントページは Step 5c より後に生成されるため、Step 9 後にも Techbook post-process を再実行する。
- 絵文字画像と著者図版を `img.vs-emoji` で区別し、絵文字だけ枠線を消す。
- 丸数字・波線・h3/h4マーカーは WebP 画像に置換する。
- `-webkit-text-stroke` は Type 3 を再発させるため、全出力形式でコメントアウトする。
- `pdffonts` と Acrobat Reader を基準に検証する。
