---
link:
- rel: stylesheet
  href: stylesheets/theme.css
- rel: stylesheet
  href: stylesheets/appendix.css
lang: ja
---

# 簡易文法リファレンス（Ruby / HTML / CSS）

:::{.chapter-lead}
よく使う構文だけを表形式で最短ルックアップできるようにまとめました。詳細は Appendix-B の公式ドキュメントを参照してください。
:::


:::{.section-lead}
この付録は「最短で書き方を思い出す」ための逆引きです。
- まず目的の言語（Ruby / HTML / CSS）の表を開く
- 用途カラムから該当行を見つけ、例をコピペ→最小改変
- 詳細は Appendix-B の公式ドキュメントへ
:::


## Ruby

| 機能 | 構文 | 例 | 備考 |
|---|---|---|---|
| 変数/定数 | `var`, `CONST` | `name = "Alice"`, `PI = 3.14` | 定数は慣習的に大文字 |
| 配列/ハッシュ | `[]`, `{key: value}` | `[1,2,3]`, `{a: 1, b: 2}` | シンボルキーが定番 |
| 文字列 | シングル/ダブル | `'a'`, "hello #{name}" | 展開はダブルのみ |
| 条件 | `if ... elsif ... else end` | `if n > 0 ... end` | 後置: `do_something if cond` |
| 反復 | `times`, `each` | `3.times { |i| ... }`, `arr.each { |x| ... }` | ブロック `{}`/`do..end` |
| メソッド | `def name(args) ... end` | `def add(a,b) a+b end` | 返り値は最後の式 |
| クラス/モジュール | `class C; end`, `module M; end` | `class User < Base; end` | `include`/`extend` |
| 例外 | `begin ... rescue ... ensure end` | `rescue StandardError => e` | `raise` で送出 |
| 正規表現 | `/pattern/` | `/^a.+z$/ =~ str` | `=~`, `match` |
| 実行 | `ruby file.rb` |  | shebang で実行可 |

## HTML

| 要素 | 目的 | 例 | 備考 |
|---|---|---|---|
| 文書型/言語 | HTML5 宣言/言語 | `<!doctype html>`, `<html lang="ja">` | 先頭に宣言 |
| メタ | 文字コード/viewport | `<meta charset="utf-8">`, `<meta name="viewport" content="width=device-width, initial-scale=1">` | UTF-8 推奨 |
| 見出し/段落 | 構造化 | `<h1>..</h1>`, `<p>..</p>` | 見出しは階層順 |
| リンク/画像 | ナビ/画像 | `<a href="/">`, `<img src="a.png" alt="">` | `alt` は必須 |
| リスト | 箇条書き | `<ul><li>..</li></ul>`, `<ol>` | 入れ子可 |
| セクション | 意味分割 | `<header> <nav> <main> <section> <footer>` | セマンティック HTML |
| フォーム | 入力 | `<form><input type="text"></form>` | `label` と関連付け |
| スクリプト/スタイル | JS/CSS 取込 | `<script src="app.js" defer></script>`, `<link rel="stylesheet" href="app.css">` | `defer` 推奨 |

## CSS

<div class="table-rotate">
<table>
  <thead>
    <tr>
      <th>機能</th>
      <th>構文</th>
      <th>例</th>
      <th>備考</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td>セレクタ</td>
      <td>要素/クラス/ID</td>
      <td><code>h1 {}</code>, <code>.btn {}</code>, <code>#main {}</code></td>
      <td>優先度: ID &gt; クラス &gt; 要素</td>
    </tr>
    <tr>
      <td>子/子孫/隣接</td>
      <td><code>&gt;</code>, 空白, <code>+</code>, <code>~</code></td>
      <td><code>.card &gt; img</code>, <code>.nav a</code>, <code>h2 + p</code></td>
      <td>関係で範囲制御</td>
    </tr>
    <tr>
      <td>プロパティ</td>
      <td><code>prop: value;</code></td>
      <td><code>color: #333;</code>, <code>margin: 1rem;</code></td>
      <td>終端セミコロン推奨</td>
    </tr>
    <tr>
      <td>変数</td>
      <td><code>--var</code> と <code>var()</code></td>
      <td><code>:root { --gap: 8px } .g { gap: var(--gap) }</code></td>
      <td>カスケード変数</td>
    </tr>
    <tr>
      <td>メディア</td>
      <td><code>@media</code></td>
      <td><code>@media (min-width: 768px) { ... }</code></td>
      <td>レスポンシブ</td>
    </tr>
    <tr>
      <td>フォント</td>
      <td><code>@font-face</code></td>
      <td><code>@font-face { font-family: X; src: url(x.woff2) format('woff2'); }</code></td>
      <td>表示最適化に注意</td>
    </tr>
    <tr>
      <td>アニメーション</td>
      <td><code>@keyframes</code> と <code>animation</code></td>
      <td><code>@keyframes fade{...} .el{animation: fade 1s}</code></td>
      <td>簡易トランジションは <code>transition</code></td>
    </tr>
    <tr>
      <td>変換/配置</td>
      <td><code>transform</code>, <code>flex</code>, <code>grid</code></td>
      <td><code>display: grid; gap: 1rem;</code></td>
      <td>レイアウトの基本</td>
    </tr>
  </tbody>
</table>
</div>
