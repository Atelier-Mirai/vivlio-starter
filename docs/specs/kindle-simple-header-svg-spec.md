# Kindle 向け simple ヘッダーの SVG 画像化 仕様（将来タスク）

> 作成日: 2026-06-20
> ステータス: **将来やりたいこと（未着手）**
> 対象: Kindle（`target=kindle`）における **付録など simple スタイルの章/節見出し**の装飾。
> 関連: `epub-kindle-target-split-spec.md`（ターゲット分離）, `math-frontispiece-svg-spec.md`（本文の扉絵/節絵 SVG→JPEG 化・③-a）, `stylesheets/simple-header.css`

---

## 0. 背景

本文章（01–89）の扉絵（h1）・節絵（h2）は、`HeadingImageComposer` が「飾り画像＋見出し文字」を 1 枚の合成 SVG に組み、Kindle 用に **平坦 JPEG へラスタライズ**して `<img>` 注入することで、Kindle の CSS 制約に左右されず確実に描画している（③-a）。

一方、**付録（90–98）は `theme.style=simple` 扱い**で、背景画像を持たず `stylesheets/simple-header.css` の CSS 装飾（枠・リボン・番号バッジ）で見出しを飾る。この CSS は `var()` / `display:grid` / `clamp()` / `calc()` / `::before(position:absolute)` / `linear-gradient` を多用しており、**Kindle KFX ではすべて解されず崩れて素テキスト化**する。

現状（2026-06-20 時点）は **`body.vs-kindle` 配下に具体値の CSS フォールバック**（`stylesheets/simple-header.css` 末尾）を置いて、付録見出しに枠付きの装飾を与えている。これで「一応OK」だが、本文章の画像見出しとはレンダリング系統が異なり、見た目の統一感・確実性に差がある。

## 1. 目的

付録など simple スタイルの章/節見出しも、本文章の扉絵/節絵と**同じ「合成画像」方式**で描画し、Kindle 上で **CSS 非依存にデザインを保証**する。背景写真の代わりに、simple-header のデザイン（枠・リボン・番号バッジ・タイトル）を**ベクター描画した合成 SVG → JPEG ラスタライズ**して `<img>` 注入する。

## 2. 方針

- **適用条件**: `flavor == :kindle` かつ simple スタイルの章/節（当面は付録 `APPX_RANGE`。前付/後付の扱いは要検討）。
  - クリーン EPUB（`:epub`・Kobo/Apple Books）は従来どおり `simple-header.css`（CSS 装飾）を使う。これらの閲覧器は `var()`/`grid` を解すため画像化は不要で、テキスト見出しのほうが再流動・検索・アクセシビリティで有利。
- **描画**: `HeadingImageComposer` に simple 用テンプレートを追加する。
  - `simple_frontispiece_svg(number, title, accent, ...)` … 角丸の枠＋上下リボン＋章番号（小）＋タイトル（大）を中央寄せで描く（`simple-header.css` の h1 デザインの再現）。
  - `simple_ornament_svg(number, title, accent, ...)` … 左帯＋番号バッジ＋タイトルの横並び（h2 デザインの再現）。
  - 背景画像（`<image xlink:href="data:...">`）は不要で、`<rect>`/`<text>`/`<linearGradient>` だけのピュアベクター。Kindle 非対応の base64 画像問題も無い。
  - 色は `theme.appendix_color`（既定 yellow 系）等から解決。フォントは `epub_heading_font_family`。
- **注入**: `inject_heading_images_for_epub!` を simple 章/節にも対応させる。
  - `main_chapter_file?`（1..89）の判定を拡張し、付録（90..98）も対象にして simple テンプレートで `heading_image_src(kind: :simple_frontispiece / :simple_ornament, flavor: :kindle)` を呼ぶ。
  - 既存と同様、合成失敗（rsvg/magick 不在）時は注入せず simple 縮退（CSS フォールバック）に戻す（§B-5 と同じ設計）。
- **クリーン EPUB**: 何もしない（CSS のまま）。`heading_image_src` の `flavor: :epub` は simple についても画像化しない。

## 3. ファイル名 / キャッシュ

- `images/headings/simple-frontispiece-<hash>.jpg` / `simple-ornament-<hash>.jpg`。
- ハッシュ鍵に `flavor` / `kind` / `number` / `title` / `font` / `color` を含める（既存 `heading_image_src` と同様）。

## 4. テスト方針

- ユニット: `inject_heading_images_for_epub!(flavor: :kindle)` で付録 h1/h2 が `<img class="vs-image-heading-img">` へ置換され、`alt` に番号＋タイトルが入ること。`flavor: :epub` では付録は**テキストのまま**（画像化しない）こと。
- 縮退: rsvg/magick 不在時に simple 縮退（CSS フォールバック）へ戻ること（DI でツール存在を差し替え）。
- 統合（opt-in）: Kindle 変換で付録見出しが画像として表示され、画像系警告ゼロであること。

## 5. 留意点 / トレードオフ

- 画像見出しは**固定サイズ**で再流動しない。読み上げ・TOC・検索は `<img alt>` と `<title>`（nav）に依存する（本文章の扉絵/節絵と同じ割り切り）。
- 付録の節が多いと画像点数・EPUB サイズが増える。JPEG 品質・解像度は本文章の節絵と同等の設定を流用する。
- 現状の CSS フォールバック（`simple-header.css` の `body.vs-kindle` ブロック）は、本方式の導入後は **Kindle では不発**（見出しが `<img>` になり h1/h2 のテキスト装飾規則に当たらない）になる。合成失敗時の縮退先として**残す**のが安全。

## 6. 決定事項 / 残論点

- 付録のみを対象にするか、前付（00）・後付（99）など他の simple ページも画像化するか（前付/後付は preface.css 系の別装飾。要検討）。
- simple テンプレートのデザインを `simple-header.css` のどこまで忠実に再現するか（リボンのグラデーション等は JPEG ラスタライズで再現可能）。
