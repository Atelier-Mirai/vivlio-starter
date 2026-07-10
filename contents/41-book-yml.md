# config/book.yml リファレンス

:::{.chapter-lead}
`config/book.yml` は Vivlio Starter プロジェクトの中心となる設定ファイルです。書籍情報からテーマ、出力形式、各機能の詳細パラメータまで、プロジェクト全体の挙動をここで一元管理します。

本章では、設定項目を「**必ず設定する**」「**必要に応じて調整する**」「**機能別の詳細設定**」の三層に分けて解説します。
:::

## はじめに — 設定項目の全体像

`book.yml` の設定セクションは、大きく三種類に分けられます。

| 種別 | セクション | 説明 |
| :--- | :--- | :--- |
| 必ず設定する | `book` `project` `theme` `page` | 書籍ごとに異なる基本情報 |
| 必要に応じて調整する | `typography` `output` `vfm` `legal` `build` | 既定値で動くが、カスタマイズしたい場合に |
| 機能別の詳細設定 | `index_glossary` `index` `glossary` `metrics` `lint` `spellcheck` `pdf_read` | 各機能を使う場合のみ設定 |

## 必ず設定する項目

### book — 書籍情報

書籍のメタデータを設定します。タイトルページ・奥付・EPUB メタデータに自動反映されます。

```yaml
book:
  main_title: "はじめての技術書づくり"
  subtitle: "Vivlio Starter 実践ガイド"
  subtitle_style: wave   # 副題の装飾: wave / bar / none
  series: "「技術書典20 新刊」"
  release: "令和八年四月二十六日"
  publisher: "アトリヱ未來"
  contact: "contact@atelier-mirai.net"
  author: "早乙女 遙香"
  language: "ja"
  isbn: ''               # 独自 ISBN 取得の場合のみ記入（Kindle は ASIN が自動割り当てされる）
```

`subtitle_style` は副題の表示スタイルを指定します。`wave` は波線、`bar` は横棒、`none` は装飾なしです。副題が不要な場合には省略して構いません。

### project — プロジェクト情報

出力ファイル名のベースとなる `name` と、ファイル名に付加される `version` を設定します。

```yaml
project:
  name: "vivlio_starter"     # 出力例: vivlio_starter_v1.0.0.pdf
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
| 暖色 | `yellow` `orange` `red` `magenta` |
| 寒色 | `purple` `indigo` `navy` `blue` |
| 中間色 | `cyan` `teal` `green` `lime` |
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

## 必要に応じて調整する項目

### typography — タイポグラフィ設定

本文・見出し・コード・ページ番号のフォントを設定します。既定のフォントで問題なければ変更不要です。

```yaml
typography:
  body:
    font: Zen Old Mincho        # 本文（明朝体）
  heading:
    font: Zen Kaku Gothic New   # 見出し（ゴシック体）
  column:
    font: Zen Maru Gothic       # コラム（丸ゴシック体）
    font_size: 8pt
  code:
    font: HackGen35 Console NF  # コードブロック
  folio:
    font: Zen Kaku Gothic New   # ページ番号
    placement: sides            # center: 中央 / sides: 左右
```

標準添付書体は、明朝体（Zen Old Mincho）・ゴシック体（Zen Kaku Gothic New）・丸ゴシック体（Zen Maru Gothic）・プログラミング用フォント（HackGen35 Console NF）の四種類です。これ以外のフォント名を指定すると、Google Fonts からの自動取得を試みます。

### output — 出力設定

出力フォーマット・ファイル名規則・表紙設定・PDF/EPUB の詳細オプションをまとめて管理します。

```yaml
output:
  targets: pdf          # 出力形式: pdf / print_pdf / epub / kindle
                        # 複数指定: pdf, print_pdf  または  [pdf, epub, kindle]

  filename:
    include_version: true   # true: mybook_v1.0.0.pdf / false: mybook.pdf

  cover: light              # カバーテーマ: light / dark（標準添付 SVG）
                            # master または独自スラッグ（covers/frontcover_master.png 等、著者用意の画像）

  pdf:
    combined: true          # true: 表紙を本文 PDF に結合する
    compress: false         # true: ビルド後に自動圧縮（処理時間が増加）
    techbook: false         # true: 技術書典向け Techbook モード（絵文字を Twemoji SVG 画像に自動差し替え）

  print_pdf:                # 印刷入稿用 PDF の設定
    bleed: 3mm              # 塗り足し幅（既定: 3mm）
    crop_marks: true        # トンボを付けるか（既定: true）
    full_bleed: false       # 本文にフチなし（塗り足しまで届く）要素があるか（既定: false）

  epub:                     # 楽天 Kobo / Apple Books 向けクリーン EPUB
    embed: true             # true: 表紙を埋め込む（楽天/Apple Books 推奨）
    layout: reflowable      # reflowable: リフロー型（fixed: 固定レイアウト型は将来対応）

  kindle:                   # Amazon Kindle 向け（KPF へ自動変換）
    embed: false            # false: KDP で別途アップロードするため埋め込まない（既定・推奨）
    layout: reflowable      # reflowable: リフロー型（fixed: 固定レイアウト型は将来対応）
```

**`targets` と出力物の関係**

| targets の値 | 生成されるもの |
| :--- | :--- |
| `pdf` | 閲覧用 PDF（表紙結合） |
| `print_pdf` | 入稿用 PDF（トンボ・塗り足し付き） |
| `epub` | 電子書籍（クリーン EPUB。楽天 Kobo / Apple Books 向け） |
| `kindle` | Amazon Kindle 用ファイル（KPF。中間 EPUB から自動変換） |

:::{.column}
**`epub` と `kindle` の違い**

同じ電子書籍でも、配信先によって最適な作り方が異なります。Vivlio Starter は両者を別ターゲットとして分離しています。

- **`epub`（クリーン EPUB）**: 楽天 Kobo・Apple Books 向け。WebP 画像・SVG 化した扉絵や数式をそのまま活かした、高品質な EPUB を生成します。
- **`kindle`（KPF）**: Amazon Kindle 向け。Kindle の表示エンジン（KFX）の制約に合わせて画像形式やレイアウトを調整した中間 EPUB を作り、`kindlepreviewer` で `.kpf` に変換します。KDP（Kindle Direct Publishing）にはこの `.kpf` をアップロードします。

両方を同時に出力したい場合は `targets: epub, kindle` のように指定します。
:::

`cover` に指定するスラッグは `vs cover` コマンドで生成したカバーのテーマ名と対応します。詳細は「カバー画像の生成」の章を参照してください。

`pdf.techbook` は、技術書典などの即売会向けに絵文字をカラー SVG 画像へ自動差し替えるモードです。Chromium の PDF エンジンが絵文字を Type 3 フォントとして埋め込む問題を回避し、印刷入稿に適した PDF を生成します。詳細は「ビルド（vs build）」の章を参照してください。

:::{.column}
**`print_pdf.full_bleed` — 入稿用 PDF の生成方式**

既定（`false`）では、入稿用 PDF は閲覧用 PDF から高速に導出されます。本文が閲覧用とまったく同じレンダリング由来になるため、ページずれや内容差が起きず、ビルド時間も大幅に短くなります。

ただし、閲覧用 PDF は仕上がりサイズで裁たれていて塗り足し（裁ち落とし）部分を復元できません。**紙の端まで届く画像や背景（フチなし要素）が本文にある本**では `full_bleed: true` を指定してください。従来どおり塗り足し付きで個別にレンダリングされ、フチなし要素が白フチ（裁ち落とし事故）になるのを防げます。
:::

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
  hard_line_breaks: true # true:  エンターキーの改行をそのまま改行として処理
                         # false: 改行はスペース扱い（空行か<br>で改行）
```

日本語の技術書では `true` が扱いやすい設定です。ここでの設定は本全体に適用されます。
特定の章だけ変えたい場合は、その章のフロントマターに `vfm: hardLineBreaks: false` を
書くと章単位で上書きできます（フロントマター側のキー名は VFM の仕様により camelCase です）。

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
  twemoji: |
    本書で使用している絵文字画像は Twemoji (https://twemoji.twitter.com) を利用しています。
    Copyright © Twitter, Inc and other contributors. Licensed under CC BY 4.0
    (https://creativecommons.org/licenses/by/4.0/).
```

`twemoji` は、奥付にクレジット表記として挿入されるテキストです。`output.pdf.techbook: true` にして絵文字を Twemoji SVG に差し替える場合は、ライセンス表記としてここに設定してください（未設定なら何も挿入されません）。

### build — ビルド時の検証

`vs build` 実行時に行う、画像パス・URL の検証設定です。

```yaml
build:
  verify:
    images: true          # 画像パスの存在チェック（既定: true）
    bare_urls: true        # 裸 URL（Markdown リンク記法でない URL）の検出と警告（既定: true）
    external_links: false  # 外部 URL の HTTP 到達性チェック（既定: false。--verify-links で有効化）
    timeout: 10             # HTTP チェックのタイムアウト秒数
    max_concurrency: 5      # HTTP チェックの最大同時接続数
```

`images`/`bare_urls` は Markdown 前処理の中で常時チェックされます。`external_links` は `vs build --verify-links` を指定したときのみ実行される重い検証で、ここでは既定の挙動と並列数・タイムアウトだけを設定します。`vs build --no-verify` で `images`/`bare_urls`/`external_links` をまとめて無効化できます。詳細は「ビルド（vs build）」の章を参照してください。

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
  smart_context_cutting: true   # 文脈抽出時に形態素境界を考慮して賢く切り出すか（既定: true）

  # 索引ライブラリ（用語集の[g]・reject を書籍間で持ち運ぶ vs index:export/import 用）
  library:
    path: "index_library.yml"   # export/import 共通の既定パス
    # export_to:   "index_library.yml"          # 書き出し先だけ変える場合（省略可）
    # import_from: "~/vivlio/index_library.yml" # 共有ライブラリから取り込む場合（省略可）

index:
  auto_discovery: true   # 手動登録以外の語句を自動で探索・提案するか
  title: '索引'
  auto_approve_threshold: 300   # このスコア以上は自動的に承認
  review_threshold: 150         # このスコア以上はレビュー候補に
  high_candidates_ratio: 0.25   # レビュー候補のうちスコア上位何割を優先候補(High)にするか（既定: 0.25）

glossary:
  title: '用語集'
  require_definition: false   # true: 説明文がないとエラー
  max_definition_length: 500
```

詳細なワークフローは「索引・用語集機能」の章を参照してください。索引ライブラリの持ち運び（`vs index:export` / `vs index:import`）についても同章で解説しています。

### metrics — メトリクス基準値

`vs metrics` コマンドの評価基準を設定します。`use` でプリセットを選ぶと、本の規模に応じて章・節の分量目安が切り替わります。語彙難度・語彙多様度・読解難度の基準は、プリセットとは独立した共通設定として調整します。

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

`use` で選んだプリセット（`compact`/`standard`/`commercial`/`author_custom`）が切り替えるのは、`chapter`/`section` の分量基準だけです。語彙難度（`kanji_ratio`・`word_length`）・語彙多様度（`mattr_window`）・読解難度（`readability`）・警告メッセージの文言（`labels`）は、プリセットの外側に置く共通設定で、どのプリセットを選んでも同じ値が使われます。詳細な基準値のカスタマイズは「Metrics」の章を参照してください。

### lint / spellcheck — 文章校正

`vs lint` の既定設定とスペルチェックの辞書を管理します。

```yaml
lint:
  config: config/.textlintrc.yml   # 使用する textlint 設定ファイル
  disabled_rules: []               # 丸ごと無効化したい textlint ルール ID
  disabled_terms: []               # 無効化したい表記揺れの指摘語（prh 等の個別無効化）
  sentence_length_max: 100         # 一文の最大文字数（sentence-length ルール）
  trim_long_vowel: false           # true: 「サーバ」等、末尾長音を省く文体の指摘を黙らせる
  allow_space_around_code: false   # true: インラインコードと和文の間のスペースを許容
  allow_space_between_ja_en: false # true: 全角と半角（英数・記号）の間のスペースを許容

spellcheck:
  extra_dictionaries: []   # オンデマンドダウンロード辞書（例: ada）
  extra_words:             # プロジェクト固有の正しい語（誤検知防止）
    - vivliostyle
    - vivlio-starter
  ignore_words:            # 抑制したい単語
    - htmx
  check_code_blocks: false # コードブロック内をチェック対象にするか
```

詳細は「文章校正」の章を参照してください。

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
    inline_image_text: include   # include / exclude / captionize（イラスト内テキストの扱い）
```

詳細は「PDF 読み取りコマンドの使い方」の章を参照してください。
