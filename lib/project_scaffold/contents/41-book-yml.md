# config/book.yml リファレンス

:::{.chapter-lead}
`config/book.yml` は Vivlio Starter プロジェクトの中心となる設定ファイルです。書籍情報からテーマ、出力形式、各機能の詳細パラメータまで、プロジェクト全体の挙動をここで一元管理します。

本章では、設定項目を「**必ず設定する**」「**必要に応じて調整する**」「**機能別の詳細設定**」の三層に分けて解説します。
:::

---

## はじめに — 設定項目の全体像

`book.yml` の設定セクションは、大きく三種類に分けられます。

| 種別 | セクション | 説明 |
| :--- | :--- | :--- |
| 必ず設定する | `book` `project` `theme` `page` | 書籍ごとに異なる基本情報 |
| 必要に応じて調整する | `typography` `output` `vfm` `legal` | 既定値で動くが、カスタマイズしたい場合に |
| 機能別の詳細設定 | `index_glossary` `metrics` `lint` `spellcheck` `pdf_read` | 各機能を使う場合のみ設定 |

---

## 必ず設定する項目

### book — 書籍情報

書籍のメタデータを設定します。タイトルページ・奥付・EPUB メタデータに自動反映されます。

```yaml
book:
  main_title: "初めてのアプリ開発"
  subtitle: "ゲームを創ろう"
  subtitle_style: wave   # 副題の装飾: wave / bar / none
  series: "技術書典20 新刊"
  release: "令和八年四月一日"
  publisher: "出版社名"
  contact: "contact@example.com"
  author: "著者名"
  language: "ja"
  isbn: ''               # 独自 ISBN 取得の場合のみ記入
```

`subtitle_style` は副題の表示スタイルを指定します。`wave` は波線、`bar` は横棒、`none` は装飾なしです。

### project — プロジェクト情報

出力ファイル名のベースとなる `name` と、ファイル名に付加される `version` を設定します。

```yaml
project:
  name: "mybook"     # 出力例: mybook_v1.0.0.pdf
  version: "1.0.0"
```

### theme — テーマ設定

章扉のスタイル・アクセントカラー・扉絵・装飾画像をまとめて設定します。

```yaml
theme:
  style: simple      # image: 扉絵あり / simple: 扉絵なし

  color: blue        # アクセントカラー（下記カラーパレットから選択）
  preface_color: indigo   # 前書き・後書き専用カラー（省略時は color と同じ）
  appendix_color: yellow  # 付録専用カラー（省略時は color と同じ）

  frontispiece:      # 章扉の背景画像（style: image のときのみ有効）
    image: asagao
    padding: 10mm
    heading_width: 108mm
    lead_width: 88mm

  ornament: sakura   # 節見出しの装飾画像（style: image のときのみ有効）

  markers:
    h3: ♣            # 目見出し（h3）の先頭記号
    h4: ♦            # 号見出し（h4）の先頭記号
```

**カラーパレット**

| 系統 | 選択肢 |
| :--- | :--- |
| 暖色 | `yellow` `orange` `red` |
| ピンク・紫 | `magenta` `purple` `indigo` |
| 青・緑 | `navy` `blue` `cyan` `teal` `green` `lime` |
| カスタム | `'#ff0000'` のような HEX 記法も指定可 |

`style: simple` のときは `frontispiece` と `ornament` の設定は無視されます。扉絵なしのシンプルなデザインで十分な場合は `simple` を指定してください。

### page — ページ設定

用紙サイズ・余白・文字サイズなどの版面設定を、`config/page_presets.yml` のプリセットから選択します。

```yaml
page:
  use: b5_airy    # a5_standard / a5_airy / a5_compact / a5_custom
                  # b5_standard / b5_airy / b5_compact / b5_custom
                  # a4_standard / a4_airy / a4_compact / a4_custom
```

`airy` は行間が広めの読みやすいレイアウト、`compact` はより多くの文字を詰めたレイアウトです。`custom` を選ぶと `page_presets.yml` で独自の版面を定義できます。

---

## 必要に応じて調整する項目

### typography — タイポグラフィ設定

本文・見出し・コード・ページ番号のフォントを設定します。既定のフォントで問題なければ変更不要です。

```yaml
typography:
  body:
    font: Noto Serif JP      # 本文（明朝体）
  heading:
    font: Noto Sans JP       # 見出し（ゴシック体）
  column:
    font: Zen Maru Gothic    # コラム（丸ゴシック体）
    font_size: 8pt
  code:
    font: hackgen35          # コードブロック
  folio:
    font: Noto Sans JP       # ページ番号
    placement: sides         # center: 中央 / sides: 左右
```

標準添付書体は、明朝体（Noto Serif JP）・ゴシック体（Noto Sans JP）・丸ゴシック体（Zen Maru Gothic）・プログラミング用フォント（hackgen35）の四種類です。

### output — 出力設定

出力フォーマット・ファイル名規則・表紙設定・PDF/EPUB の詳細オプションをまとめて管理します。

```yaml
output:
  targets: pdf          # 出力形式: pdf / print_pdf / epub
                        # 複数指定: pdf, print_pdf  または  [pdf, epub]

  filename:
    include_version: true   # true: mybook_v1.0.0.pdf / false: mybook.pdf

  cover: light              # カバーテーマ: light / dark / master（または独自スラッグ）

  pdf:
    combined: true          # true: 表紙を本文 PDF に結合する
    compress: false         # true: ビルド後に自動圧縮（処理時間が増加）

  print_pdf:                # 印刷入稿用 PDF の設定
    bleed: 3mm              # 塗り足し幅（既定: 3mm）
    crop_marks: true        # トンボを付けるか（既定: true）

  epub:
    embed: true             # true: 楽天/Apple Books 向け / false: Kindle 向け
    layout: reflowable      # reflowable: リフロー型 / fixed: 固定レイアウト型
```

**`targets` と出力物の関係**

| targets の値 | 生成されるもの |
| :--- | :--- |
| `pdf` | 閲覧用 PDF（表紙結合） |
| `print_pdf` | 入稿用 PDF（トンボ・塗り足し付き） |
| `epub` | 電子書籍（EPUB 形式） |

`cover` に指定するスラッグは `vs cover` コマンドで生成したカバーのテーマ名と対応します。詳細は「カバー画像の生成」の章を参照してください。

:::{.column}
**PDF プレビュー設定（macOS のみ）**

`pdf_preview` セクションでは、`vs build` 後に自動表示する PDF のウィンドウ位置を設定できます。デュアルモニター環境でサブモニターに表示させたい場合などに便利です。

```yaml
output:
  pdf_preview:
    close_existing_windows: true
    window_bounds: "{4096, 0, 5120, 2160}"
```
:::

### vfm — Markdown 設定

VFM（Vivliostyle Flavored Markdown）の挙動を設定します。

```yaml
vfm:
  hardLineBreaks: true   # true:  エンターキーの改行をそのまま改行として処理
                         # false: 改行はスペース扱い（空行か<br>で改行）
```

日本語の技術書では `true` が扱いやすい設定です。

### legal — 免責・商標

奥付に掲載する免責事項と商標に関する文面を設定します。既定のテキストで問題なければ変更不要です。

```yaml
legal:
  disclaimer: |
    本書は教育目的で作成された入門書です。内容の正確性には万全を期しておりますが、
    本書の内容を参考にした結果生じた損害について、著者および関係者は一切の責任を負いかねます。
  trademark: |
    本書に登場するシステム名や製品名は、関係各社の商標または登録商標です。
    本書では ™、®、© などのマークは省略しています。
```

---

## 機能別の詳細設定

以下のセクションは、各機能を使う場合のみ設定が必要です。使わない機能のセクションは、既定値のままで問題ありません。

### index_glossary / index / glossary — 索引・用語集

索引・用語集機能の有効化と、自動抽出のパラメータを設定します。

```yaml
index_glossary:
  enabled: true          # false にすると索引・用語集の両方が無効になる
  use_mecab: true        # MeCab による読み自動推測を使用するか
  timezone: 'Asia/Tokyo'
  context_width: 40      # キーワード前後の文脈抽出幅（文字数）

index:
  auto_discovery: true   # 手動登録以外の語句を自動で探索・提案するか
  title: '索引'
  auto_approve_threshold: 300   # このスコア以上は自動的に承認
  review_threshold: 150         # このスコア以上はレビュー候補に

glossary:
  title: '用語集'
  require_definition: false   # true: 説明文がないとエラー
  max_definition_length: 500
```

詳細なワークフローは「索引・用語集機能」の章を参照してください。

### metrics — メトリクス基準値

`vs metrics` コマンドの評価基準を設定します。プリセットを選ぶだけで、章・節の分量目安や語彙難度の判定基準を一括設定できます。

```yaml
metrics:
  use: standard    # compact / standard / commercial / author_custom
  exclude_chapters: [00, 90-98, 99]   # 評価から除外する章番号
```

| プリセット | 想定する本の規模 |
| :--- | :--- |
| `compact` | 20〜50 ページ程度の薄い本 |
| `standard` | 100〜200 ページ程度の同人誌・技術書 |
| `commercial` | 200 ページ以上の商業出版レベル |
| `author_custom` | 自分で基準値を定義したい場合 |

詳細な基準値のカスタマイズは「Metrics」の章を参照してください。

### lint / spellcheck — 文章校正

`vs lint` の既定設定とスペルチェックの辞書を管理します。

```yaml
lint:
  config: config/.textlintrc.yml   # 使用する textlint 設定ファイル
  format: stylish                   # 出力フォーマット

spellcheck:
  extra_words:             # プロジェクト固有の正しい語（誤検知防止）
    - vivliostyle
    - vivlio-starter
  ignore_words:            # 抑制したい単語
    - htmx
  check_code_blocks: false # コードブロック内をチェック対象にするか
```

詳細は「Textlint」の章を参照してください。

### pdf_read — PDF 読み取り設定

`vs pdf:read` でテキストを抽出する際の範囲と OCR 設定を管理します。

```yaml
pdf_read:
  text_area:
    top_margin: 18       # 上端からの除外幅（mm）
    bottom_margin: 20    # 下端からの除外幅（mm）
    inner_margin: 15     # 綴じ側の除外幅（mm）
    outer_margin: 12     # 小口側の除外幅（mm）
  page_separator: false  # true: "---" でページ区切りを挿入する

  ocr:
    mode: auto           # auto / force / disable
    languages:
      - japanese
    dpi: 300
    psm: 3
```

詳細は「PDF 読み取りコマンドの使い方」の章を参照してください。
