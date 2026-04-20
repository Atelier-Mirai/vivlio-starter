# config/book.yml リファレンス

:::{.chapter-lead}
`config/book.yml` は Vivlio Starter プロジェクトの中心となる設定ファイルです。書籍情報からビルド設定、テーマ、出力形式まで、プロジェクト全体の挙動をここで管理します。
:::

## book — 書籍情報

書籍のメタデータを設定します。タイトルページ・奥付・EPUB メタデータに反映されます。

```yaml
book:
  main_title: "初めてのアプリ開発"
  subtitle: "ゲームを創ろう"
  subtitle_style: wave   # wave / bar / none
  series: "技術書典20 新刊"
  release: "令和八年四月一日"
  publisher: "出版社名"
  contact: "contact@example.com"
  author: "著者名"
  language: "ja"
  isbn: ''
```

## project — プロジェクト情報

出力ファイル名のベースとバージョンを設定します。

```yaml
project:
  name: "mybook"       # 出力ファイル名のベース（例: mybook_v1.0.0.pdf）
  version: "1.0.0"
```

## theme — テーマ設定

章扉のスタイル・アクセントカラー・扉絵・装飾画像を設定します。

```yaml
theme:
  style: simple        # image: 扉絵あり / simple: 扉絵なし

  color: blue          # アクセントカラー（下記から選択）
                       # yellow / orange / red / magenta
                       # purple / indigo / navy / blue
                       # cyan / teal / green / lime
                       # '#ff0000' のような HEX 記法も可

  preface_color: indigo   # 前書き・後書き専用カラー（省略時は color と同じ）
  appendix_color: yellow  # 付録専用カラー（省略時は color と同じ）

  frontispiece:           # 章扉の背景画像
    image: asagao         # stylesheets/images/ 内の画像名
    padding: 10mm
    heading_width: 108mm
    lead_width: 88mm

  ornament: sakura        # 節見出しの装飾画像

  markers:
    h3: ♣               # 目見出しの記号
    h4: ♦               # 号見出しの記号
```

## page — ページ設定

用紙サイズ・余白・文字サイズなどの版面設定を `config/page_presets.yml` のプリセットから選択します。

```yaml
page:
  use: b5_airy    # a5_standard / a5_airy / a5_compact
                  # b5_standard / b5_airy / b5_compact
                  # a4_standard / a4_airy / a4_compact
```

## typography — タイポグラフィ設定

本文・見出し・コード・ページ番号のフォントを設定します。

```yaml
typography:
  body:
    font: Noto Serif JP
  heading:
    font: Noto Sans JP
  column:
    font: Zen Maru Gothic
    font_size: 8pt
  code:
    font: hackgen35
  folio:
    font: Noto Sans JP
    placement: sides    # center / sides
```

## output — 出力設定

出力フォーマット・ファイル名・PDF プレビュー・表紙・圧縮などを設定します。

```yaml
output:
  targets: pdf          # pdf / print_pdf / epub（カンマ区切りや配列も可）

  filename:
    include_version: true   # true: mybook_v1.0.0.pdf / false: mybook.pdf

  pdf_preview:              # macOS のみ
    close_existing_windows: true
    window_bounds: "{0, 0, 1024, 768}"

  cover: light              # カバーテーマ名（light / dark / master など任意のスラッグ）

  pdf:
    combined: true          # true: 表紙を PDF に結合
    compress: false         # true: ビルド後に自動圧縮（処理時間増加）

  print_pdf:
    bleed: 3mm
    crop_marks: true

  epub:
    embed: true             # true: 楽天/Apple向け / false: Kindle向け
    layout: reflowable
```

## vfm — Markdown 設定

```yaml
vfm:
  hardLineBreaks: true    # true: 改行をそのまま改行として処理
```

## index_glossary / index / glossary — 索引・用語集設定

索引・用語集機能の有効化と各種パラメータを設定します。詳細は「索引・用語集機能」の章を参照してください。

## metrics — メトリクス基準値

`vs metrics` コマンドの評価基準を設定します。詳細は「Metrics」の章を参照してください。

```yaml
metrics:
  use: standard    # compact / standard / commercial / author_custom
  exclude_chapters: [00, 90-98, 99]
```

## lint / spellcheck — 文章校正設定

`vs lint` の既定設定を管理します。詳細は「Textlint」の章を参照してください。

```yaml
lint:
  config: config/.textlintrc.yml
  format: stylish

spellcheck:
  extra_words:
    - vivliostyle
  ignore_words:
    - htmx
  check_code_blocks: false
```

## pdf_read — PDF 読み取り設定

`vs pdf:read` のテキスト抽出領域・OCR 設定を管理します。詳細は「PDF 読み取りコマンドの使い方」の章を参照してください。

## legal — 免責・商標

奥付に掲載する免責事項と商標に関する文面を設定します。

```yaml
legal:
  disclaimer: |
    本書は教育目的で作成された入門書です…
  trademark: |
    本書に登場するシステム名や製品名は…
```
