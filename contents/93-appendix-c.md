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

:::{.table-rotate}
| 機能 | 構文 | 例 | 備考 |
|---|---|---|---|
| セレクタ | 要素/クラス/ID | `h1 {}`, `.btn {}`, `#main {}` | 優先度: ID > クラス > 要素 |
| 子/子孫/隣接 | `>`, 空白, `+`, `~` | `.card > img`, `.nav a`, `h2 + p` | 関係で範囲制御 |
| プロパティ | `prop: value;` | `color: #333;`, `margin: 1rem;` | 終端セミコロン推奨 |
| 変数 | `--var` と `var()` | `:root { --gap: 8px } .g { gap: var(--gap) }` | カスケード変数 |
| メディア | `@media` | `@media (min-width: 768px) { ... }` | レスポンシブ |
| フォント | `@font-face` | `@font-face { font-family: X; src: url(x.woff2) format('woff2'); }` | 表示最適化に注意 |
| アニメーション | `@keyframes` と `animation` | `@keyframes fade{...} .el{animation: fade 1s}` | 簡易トランジションは `transition` |
| 変換/配置 | `transform`, `flex`, `grid` | `display: grid; gap: 1rem;` | レイアウトの基本 |
:::