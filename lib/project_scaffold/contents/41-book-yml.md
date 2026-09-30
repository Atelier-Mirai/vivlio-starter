# config/book.yml リファレンス

:::{.chapter-lead}
`config/book.yml` には、本のタイトルや著者名だけでなく、紙面のデザイン、出力形式、校正などの設定を集めている Vivlio Starter プロジェクトの中心となる設定ファイルです。制作中に何をどこで変えられるかを知っておくと、書籍の姿を調整しやすくなります。

本章では項目を「**必ず設定する**」「**必要に応じて調整する**」「**機能別の詳細設定**」の三つに分け、設定を探しやすい順に紹介します。
:::

## はじめに — 設定項目の全体像

まず全体を見渡しておきます。`book.yml` の設定セクションは、次の三種類です。

| 種別 | セクション | 説明 |
| :--- | :--- | :--- |
| 必ず設定する | `book` `project` `theme` `page` | 書籍ごとに異なる基本情報 |
| 必要に応じて調整する | `typography` `output` `verify` `legal` | 既定値で動くが、カスタマイズしたい場合に |
| 機能別の詳細設定 | `index_glossary` `index` `glossary` `metrics` `lint` `spellcheck` `pdf_read` | 各機能を使う場合のみ設定 |

## 必ず設定する項目

### book — 書籍情報

書籍の基本情報を記入します。ここで指定したタイトルや著者名は、タイトルページ・奥付・EPUB のメタデータへ反映されるため、刊行前にもう一度確認してください。

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

生成するファイルの名前は、`name` と `version` で決まります。書籍名とは別に、配布ファイルを見分けやすい名前を付けてください。

```yaml
project:
  name: "vivlio_starter"     # 出力例: vivlio_starter_v1.0.0.pdf
  version: "1.0.0"
```

### theme — テーマ設定

章扉のスタイルやアクセントカラー、扉絵、節見出しの装飾画像をここで選びます。まず `style` を決めると、必要な項目が見通しやすくなります。

```yaml
theme:
  style: simple      # image: 扉絵あり / simple: 扉絵なし

  color: blue        # アクセントカラー（下記カラーパレットから選択）
  preface_color: indigo   # 前書き・後書き専用カラー（省略時は color と同じ）
  appendix_color: yellow  # 付録専用カラー（省略時は color と同じ）

  frontispiece:      # 章扉の背景画像（style: image のときのみ有効）
    image: asagao
    edge_inset: 10mm      # 扉絵を紙の端から引っ込める量
    heading_offset: 15mm  # 見出しブロック（章番号〜リード）を下げる量
    heading_chars: 8      # 章題を 1 行に何文字入れるか
    lead_chars: 20        # リード文を 1 行に何文字入れるか

  ornament:          # 節見出しの装飾画像（style: image のときのみ有効）
    image: sakura
    heading_chars: 14     # 節題を 1 行に何文字入れるか

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

`style: simple` を選ぶと、`frontispiece` と `ornament` の設定は使われません。扉絵を使わずに仕上げたい本なら、この設定から始められます。

### page — ページ設定

用紙サイズ・余白・文字サイズを含む版面は、`config/page_presets.yml` のプリセットから選びます。書き始める段階では近いものを選び、組み上がった紙面を見て調整しても構いません。

```yaml
page:
  use: b5_airy    # a5_standard / a5_airy / a5_compact / a5_custom
                  # b5_standard / b5_airy / b5_compact / b5_custom
                  # a4_standard / a4_airy / a4_compact / a4_custom
  section_pagebreak: true   # 節（##）をページの先頭から始めるか
  chapter_pagebreak: recto  # 章などをどちら側の面から始めるか
```

`airy` は行間が広めの読みやすいレイアウト、`compact` はより多くの文字を詰めたレイアウトです。`custom` を選ぶと `page_presets.yml` で独自の版面を定義できます。

#### `section_pagebreak` — 節で改ページするか

節見出し（`##`）でページを改めるかどうかの選択です。既定の `true` では節ごとに新しいページが始まります。`false` にすると節が本文の流れの中に続けて組まれ、ページ数を抑えられます。ページ数の上限が決まっている配布資料や、章あたりの節が多い本で効果的です。

#### `chapter_pagebreak` — 章をどちら側の面から始めるか

章・目次・部扉・付録・用語集・後書き・索引は、既定では**必ず右ページ（奇数ページ）から始まります**。これは「改丁」と呼ばれる組み方で、一般的な書籍の章立てにもよく見られます。前の章が奇数ページで終わった場合は、次を右ページから始めるために白紙ページを一つ挟みます。そのぶん、本全体のページ数も増えます。

| 値 | 意味 |
|---|---|
| `recto` | 右ページ（奇数）から始める。必要なら白紙が 1 枚入る（既定） |
| `any` | どちらの面からでもよい。白紙が入らずページ数が減る |
| `verso` | 左ページ（偶数）から始める |

改丁のための白紙ページを入れたくない場合は、`any` を選びます。本書を `recto` のまま組んだときは、**全体の約 5% が白紙**でした。ページ単価で刷る同人誌や、ページ数の上限がある配布資料では、この差が効いてきます。本書は `section_pagebreak: false` と併用することで、**ページ数が 1 割以上減りました**。

原稿中に書いた `@pagebreak:recto` / `@pagebreak:verso` は、**この設定より優先されます**。「本全体はどちらでもよいが、この章の扉だけは必ず右から」といった使い分けができます。

:::{.memo}
`chapter_pagebreak` は**PDF だけに効きます**。EPUB・Kindle はリフロー型で「右ページ／左ページ」という概念がなく、そもそも 1 章が 1 ファイルとして独立しているため、章の始まりでは常にページが改まります。EPUB のファイルサイズやページ数は変わりません。
:::

## 必要に応じて調整する項目

### typography — タイポグラフィ設定

本文・見出し・コード・ページ番号の書体を指定します。既定の組み合わせで読みやすければ、そのまま使えます。

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

標準添付書体は、明朝体（Zen Old Mincho）・ゴシック体（Zen Kaku Gothic New）・丸ゴシック体（Zen Maru Gothic）・プログラミング用フォント（HackGen35 Console NF）の四種類です。これ以外のフォント名を指定すると、Google Fonts からの自動取得を試みます。Google Fonts の書体を選べば、本の雰囲気に合わせた紙面を作れます。

### output — 出力設定

`output.targets` で、目的に合う出力形式を指定します。閲覧・配布用なら `pdf`、印刷所への入稿用なら `print_pdf`、電子書籍なら `epub` や `kindle` を選びます。このセクションでは、出力ファイル名や表紙の扱いも設定できます。

```yaml
output:
  targets: pdf          # 出力形式: pdf / print_pdf / epub / kindle
                        # 複数指定: pdf, print_pdf  または  [pdf, epub, kindle]

  include_version: true     # true: mybook_v1.0.0.pdf / false: mybook.pdf

  cover: master             # covers/ に置いた著者用意の画像を使う（既定）
                            # light / dark … 標準添付の SVG テンプレート

  pdf:
    combined: true          # true: 表紙を本文 PDF に結合する
    compress: false         # true: ビルド後に自動圧縮（処理時間が増加）
    techbook: true          # true: 絵文字を Twemoji の SVG 画像へ差し替える（既定）

  print_pdf:                # 印刷入稿用 PDF の設定
    bleed: 3mm              # 塗り足し幅（既定: 3mm）
    crop_marks: true        # トンボを付けるか（既定: true）
    full_bleed: false       # 本文にフチなし（塗り足しまで届く）要素があるか（既定: false）
    cover_bleed: scale      # 表紙の塗り足し: scale（拡大して流用・既定）/ keep（拡大しない）
    icc_profile:            # CMYK 変換の ICC プロファイル（空なら同梱の Japan Color 2001 Coated）

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

:::{.note}
**`epub` と `kindle` の違い**

同じ電子書籍でも、配信先によって最適な作り方が異なります。Vivlio Starter は両者を別ターゲットとして分離しています。

- **`epub`（クリーン EPUB）**: 楽天 Kobo・Apple Books 向け。WebP 画像・SVG 化した扉絵や数式をそのまま活かした、高品質な EPUB を生成します。
- **`kindle`（KPF）**: Amazon Kindle 向け。Kindle の表示エンジン（KFX）の制約に合わせて画像形式やレイアウトを調整した中間 EPUB を作り、`kindle previewer` で `.kpf` に変換します。KDP（Kindle Direct Publishing）にはこの `.kpf` をアップロードします。

両方を同時に出力したい場合は `targets: epub, kindle` のように指定します。
:::

`cover` に指定するスラッグは `vs cover` コマンドで生成したカバーのテーマ名と対応します。詳細は @chapref:ch-cover を参照してください。

PDF を作るとき、Vivlio Starter は Vivliostyle で原稿を組版し、Vivliostyle は Chromium（ブラウザ）を使って PDF に書き出します。その過程で、絵文字が Type 3 フォント[^type3-font]として埋め込まれることがあります。`pdf.techbook` を有効にすると、絵文字をカラーの SVG 画像へ差し替えるので、「技術書典」など Type 3 を受け付けない入稿先への納入も可能になります。既定で有効ですが、詳細は @chapref:ch-build を参照してください。

[^type3-font]: Type 3 は、文字の形を PDF 内の描画命令で定義するフォント形式です。

:::{.note}
**`print_pdf.full_bleed` — 入稿用 PDF の生成方式**

既定（`false`）では、入稿用 PDF は閲覧用 PDF から高速に導出されます。本文が閲覧用とまったく同じレンダリング由来になるため、ページずれや内容差が起きず、ビルド時間も大幅に短くなります。

ただし、閲覧用 PDF は仕上がりサイズで裁たれていて塗り足し（裁ち落とし）部分を復元できません。**紙の端まで届く画像や背景（フチなし要素）が本文にある本**では `full_bleed: true` を指定してください。入稿用 PDF を塗り足し付きで組み直すので、フチなし要素が白フチ（裁ち落とし事故）になるのを防げます。
:::

#### `pdf_preview` — ビルド後に開く PDF の位置（macOS のみ）

`pdf_preview` セクションでは、`vs build` 後に自動表示する PDF のウィンドウ位置を設定できます。デュアルモニター環境でサブモニターに表示させたい場合などに便利です。

```yaml
output:
  pdf_preview:
    close_existing_windows: true
    window_bounds: "{0, 0, 1280, 960}"
```

### legal — 免責・商標

奥付に載せる免責事項と商標の文面を指定します。既定の文章を使う場合も、自分の本の内容や権利表記に合っているかを確認してください。

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

### verify — 原稿の検証

`vs build` と `vs preflight` は、画像の参照先と裸 URL（Markdown のリンク記法で書いていない URL）を毎回確かめます。ここで選べるのは、外部 URL に実際にアクセスして確かめるかどうかです。公開前のリンク確認に使います。

```yaml
verify:
  external_links: false  # 外部 URL の HTTP 到達性チェック（既定: false。--verify-links で有効化）
  timeout: 10            # HTTP チェックのタイムアウト秒数
  max_concurrency: 5     # HTTP チェックの最大同時接続数
```

外部 URL の確認は時間がかかるので、既定では行いません。毎回確かめるなら `external_links: true` にします。その場かぎり確かめるときは `vs build --verify-links` を使います。詳細は @chapref:ch-build を参照してください。

## 機能別の詳細設定

ここからは、索引、文章分析、校正など、機能ごとの設定です。必要になった項目から確認できるよう、それぞれの用途と参照先をまとめます。

### index_glossary / index / glossary — 索引・用語集

索引・用語集を有効にするか、候補をどの程度拾うかを指定します。主な設定は次のとおりです。主要参照の出し方などを含む全体と、索引語の選び方は @chapref:ch-index-glossary で説明しています。

```yaml
index_glossary:
  enabled: true          # false にすると索引・用語集の両方が無効になる
  use_mecab: true        # MeCab による読み自動推測を使用するか
  timezone: 'Asia/Tokyo'
  context_width: 40      # キーワード前後の文脈抽出幅（文字数）

index:
  auto_discovery: true   # 手動登録以外の語句を自動で探索・提案するか
  title: '索引'
  target_terms: light    # 索引語数の目安: light / standard / thorough / 数値で直接指定
  candidate_pool: 3.0    # 目安語数の何倍までを候補として提示するか
  auto_approve: false    # true: 推奨候補を自動で辞書へ登録する

glossary:
  title: '用語集'
  require_definition: false   # true: 説明文がないとエラー
  max_definition_length: 500
```

索引ライブラリ（用語集の `[g]` と棄却語を書籍間で持ち運ぶ仕組み）に設定は要りません。`vs index:export` / `vs index:import` は既定で `index_library.yml` を読み書きし、別の場所を使いたいときは `vs index:export ~/vivlio/shared.yml` のように引数でパスを渡します。

### metrics — メトリクス基準値

`vs metrics` が章や節の分量を比べる基準を指定します。`use` でプリセットを選ぶと、本の規模に合った分量目安に切り替わります。語彙難度・語彙多様度・読解難度の基準はプリセットと独立しているため、必要に応じて別に調整できます。

```yaml
metrics:
  use: standard                      # 下の表から選ぶ
  exclude_chapters: [00, 90-98, 99]  # 警告と比較から外す章番号
```

選ぶ目安は**本全体の本文字数**（コードと記法を除いた地の文の量）です。ページ数は判型・余白・書体・図版の量で変わるため、参考値として併記しています。

| プリセット | 本全体の本文字数 | 想定する本の規模 |
| :--- | :--- | :--- |
| `compact` | 〜3.5 万字 | 20〜50 ページ程度の薄い本 |
| `handy` | 3.5〜6.5 万字 | 50〜100 ページ程度の手に取りやすい技術書 |
| `standard` | 6.5〜9 万字 | 100〜200 ページ程度の同人誌・技術書 |
| `commercial` | 9〜15 万字 | 200〜350 ページの商業出版レベル |
| `heavy` | 15 万字〜 | 350 ページ以上の大部の本 |
| `author_custom` | — | 自分で基準値を定義したい場合 |
| `relative` | — | その本自身の章の中央値と比べたい場合（詳細は @chapref:ch-metrics） |

`use` で選んだプリセットが切り替えるのは、`chapter`/`section` の分量基準だけです。語彙難度（`kanji_ratio`・`word_length`・`ttr`）・読解難度（`readability`）・警告メッセージの文言（`labels`）は、プリセットの外側に置く共通設定で、どのプリセットを選んでも同じ値が使われます。詳細な基準値のカスタマイズは @chapref:ch-metrics を参照してください。

`exclude_chapters` に挙げた章は、分量の警告（✅ 💡）と文章の質の警告（🤔）、章間のばらつきの比較から外れます。章別の一覧には表示されますが、印は付きません。前書き・付録・後書きのように、短いことに意味がある章を外すための設定です。既定は `[00, 90-98, 99]`（前書き・付録・後書き）で、章番号と `90-98` のような範囲で書きます。本文の章を外したいときも、ここへ番号を足します。

### lint / spellcheck — 文章校正

`vs lint` に書籍の文体を反映し、スペルチェックで使う追加辞書を指定します。指摘が多すぎると感じたときは、どの規則が本の方針と合わないかを見てから調整します。

```yaml
lint:
  disabled_rules: [arabic-kanji-numbers]  # 丸ごと無効化したい textlint ルール ID
  sentence_length_max: 100                # 一文の最大文字数（0 で検査しない。かっこの中は数えない）
  parenthetical_length_max: 60            # かっこ内の補足の最大文字数（0 で検査しない）
  trim_long_vowel: true                   # 「サーバ」等、末尾長音を省く文体
  allow_space_around_code: true           # インラインコードと和文の間のスペースを許容
  allow_space_between_ja_en: true         # 全角と半角の間のスペースを許容
  line_links: compact                     # 指摘の「行:」をクリックで開く（compact / path / off）

spellcheck:
  extra_dictionaries: []   # オンデマンドダウンロード辞書（例: ada）
  check_code_blocks: false # コードブロック内をチェック対象にするか
```

上の値がいずれも既定です。技術書では和欧間のスペースを入れる書き方が普通なので、`allow_space_*` は最初から許容してあります。`arabic-kanji-numbers`（`一つ → 1つ`）を切ってあるのは、逆を向く `kansuji-counter-suffix`（`1つ → 一つ`）と指摘がぶつかるためです。既定では、数を漢数字で書く側に合わせています。

ここに置くのは**文体の選択**だけです。校正ルールそのものは `config/.textlintrc.yml` を直接編集し、個別の語を指摘させたくないときは専用の除外ファイルに書きます。

| したいこと | 書く場所 |
| :--- | :--- |
| ルールの追加・削除、閾値の変更 | `config/.textlintrc.yml` |
| この語句は指摘しないでほしい（日本語校正） | `config/textlint_allowlist.yml` |
| この語は綴り誤りではない（スペルチェック） | `config/spellcheck_allowlist.yml` |
| この表記に統一したい | `config/textlint_rewrite.yml` |

詳細は @chapref:ch-lint を参照してください。

### pdf_read — PDF 読み取り設定

`vs pdf:read` で PDF からテキストを取り出す範囲と、画像内の文字を読む OCR の設定を指定します。

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

詳細は @chapref:ch-pdf-read を参照してください。
