# 開発者向けガイド

:::{.chapter-lead}
本章は Vivlio Starter をフォークして改造・拡張したい開発者に向けた案内です。著者として執筆するだけであれば読む必要はありません。各コマンドの使い方はそれぞれの章にあります。ここでは「どこに何があるか」と「手を入れるならどこを触るか」に絞って述べます。
:::

## 全体像

Vivlio Starter は Vivliostyle CLI を厚くラップした Ruby gem です。CLI フレームワークには Samovar を採用しています。

```
bin/vs / bin/vivlio-starter
  └─ lib/vivlio_starter/cli/startup.rb   # CLI.start・無効入力時のヘルプ
       └─ cli/loader.rb                  # ドメイン + Samovar の一括 require
            └─ SamovarCommands::RootCommand
                 └─ 各コマンド（build / lint / metrics / ...）

lib/vivlio_starter/cli.rb                # ライブラリからフル CLI を読む場合（startup を経由）
```

`CLI.start(ARGV)` の定義と無効オプション時の `--help` 誘導は `cli/startup.rb` に単一定義されています。ドメインから Samovar までの `require` 順は `cli/loader.rb` に集約されています。

### 二層構造

各コマンドは**Samovar エントリ**（`cli/samovar/` 配下）と**ドメイン実装**（`cli/` 配下）の二層に分かれています。前者が引数とオプションの受け取り・ヘルプ表示を担い、後者が実際の処理を持ちます。

```
lib/vivlio_starter/
  cli.rb                    # フル CLI 読み込み
  cli/
    startup.rb              # CLI.start 単一定義
    loader.rb               # require の順序
    common.rb               # CONFIG・ログ・パス定数
    config_keys.rb          # book.yml のキーと既定値の宣言（1 表）
    token_resolver.rb       # 章番号・スラッグの解決
    masking.rb              # コード領域解釈の唯一の実装
    samovar/                # Samovar CLI コマンド定義
      root_command.rb       # コマンドルーティング
      build_command.rb
      ...
    build/                  # ビルドパイプライン
      pipeline.rb           # ステップ表・相・並列実行
      epub_flow.rb          # EPUB / Kindle の生成フロー
      ...
    pre_process/            # Markdown 前処理
    post_process/           # HTML 後処理
    index/                  # 索引・用語集
    metrics/                # メトリクス分析
    lint/                   # 校正補助
    pdf/                    # PDF 読み取り・プロバイダ
    guards/                 # 実行前提条件の検査
```

この分離のおかげで、CLI の見た目を変えずに処理を差し替えたり、処理を変えずにオプションを足したりできます。

### コマンドとファイルの対応

置き場所は規則的です。コマンド `foo` に対して、Samovar エントリは `cli/samovar/foo_command.rb`、ドメイン実装は `cli/foo.rb` に置かれます。`new`・`import`・`doctor`・`upgrade`・`clean`・`create`・`delete`・`rename`・`lint`・`metrics`・`cover`・`resize` はこの形です。

規則から外れるものだけを挙げます。

| コマンド | 置き場所 |
|---------|---------|
| `renumber` | `rename_command.rb` の `RenumberCommand`。実装は `cli/rename.rb` を共用 |
| `index:auto` / `index:apply` | `index_command.rb` ＋ `cli/index/` 配下 |
| `pdf:read` / `pdf:compress` | `pdf_command.rb` ＋ `cli/pdf/` 配下 |
| `open` | `open_command.rb` ＋ `cli/pdf.rb` の `PdfOpener` |
| `preflight` | `preflight_command.rb` ＋ `cli/build/pipeline.rb` |
| `build` | `build_command.rb` ＋ `cli/build/` 配下 |

`create:titlepage`・`create:colophon`・`create:legalpage`・`create:cover` は、ビルドパイプラインから呼ばれる内部コマンドです。通常は直接実行しません。

### ワークスペース

ビルドの中間生成物はすべて `.cache/vs/` の下に置かれ、原稿ディレクトリを汚しません。

```
.cache/vs/
  build/
    html/   pdf/   epub/   kindle/
  math/   mermaid/   showcase/
  covers/   theme-images/
  book-settings.css
```

| 場所 | 内容 |
|------|------|
| `build/html/` | 前処理済み Markdown と変換後 HTML。すべての出力の原本 |
| `build/pdf/` | PDF 用に加工したコピー。破壊的な書き換えはここに閉じる |
| `build/epub/` ・ `build/kindle/` | フレーバごとの消費者ディレクトリ |
| `math/` `mermaid/` `showcase/` | 生成資産のキャッシュ。final clean を生き延びる |
| `covers/` `theme-images/` | 表紙・テーマ画像 |
| `book-settings.css` | `book.yml` から生成した CSS |

`html/` を原本とし、出力ごとにコピーへ加工するのが要点です。PDF 用の書き換えが EPUB へ漏れないのは、この構造そのものが保証しています。生成資産のキャッシュは通常のクリーンでは消えず、`vs clean --cache` が対象にします。

## ビルドパイプライン

`vs build` は `Build::UnifiedBuildPipeline` が実行します。実装は `cli/build/pipeline.rb` です。

### 三つのモード

| モード | 起動 | 内容 |
|-------|------|------|
| full | `vs build` | 全章。出力ターゲットに応じて全ステップを評価 |
| single | `vs build 11-workflow` | 単章。閲覧用 PDF のみ生成 |
| preflight | `vs preflight` | 原稿の検査のみ。HTML 変換・PDF 生成を行わない |

単章ビルドが閲覧用 PDF だけを作るのは意図的です。入稿用 PDF・EPUB・Kindle は全章がそろってはじめて意味を持つ成果物なので、単章では中途半端な出力を避けています。

:::{.note}
単章ビルドでは索引スキャンが走りません。索引語の初出を包む `<dfn>` が付かないため、索引・用語集に関わる見え方は全章ビルドでしか確認できません。
:::

### 相と並列実行

full モードのステップは四つの**相**に属します。

```
:shared  ── 両方の出力が読む中間物を作る（HTML・目次・索引・表紙資産）
   │
   ├── :pdf    ── 閲覧用 PDF・入稿用 PDF の枝
   └── :epub   ── EPUB・Kindle の枝
   │
:join    ── 両枝の完了後。ワークスペースの掃除
```

`:pdf` と `:epub` は互いに独立なので、両方に仕事があるときは並列に走ります。EPUB 枝のログは合流時にまとめて出るため、分岐直後に予告を 1 行表示します。`VIVLIO_BUILD_PARALLEL=0` を与えると逐次実行に落とせます。並列を疑うときの切り分け手順は `build-pipeline-pitfalls-notes.md` にまとまっています。

### ステップ表

full モードのステップは、条件つきの 1 枚の表として宣言されています（`full_mode_step_table`）。**ステップ番号は持ちません。**実行条件によって並びが変わると番号は意味を失い、ドキュメントとログの表記がずれていくためです。代わりに**ラベル**が、ログ・計時・本章の共通語彙になっています。

| 相 | ラベル | 実行条件 |
|---|-------|---------|
| shared | `clean` | 常時 |
| shared | `optimize images` | 常時 |
| shared | `prepare theme images` | 常時 |
| shared | `prepare cover assets` | 表紙が要るとき |
| shared | `preprocess sections` | 常時 |
| shared | `index scan and build` | 常時 |
| shared | `convert sections html` | 常時 |
| shared | `generate part title pages` | 常時 |
| shared | `generate front and back matter html` | 常時 |
| shared | `techbook post-process` | 常時 |
| shared | `generate toc html` | 常時 |
| pdf | `build overall pdf` | 閲覧用 PDF が要るとき |
| pdf | `extract rotate table images` | 回転テーブルがあるとき |
| pdf | `generate entries.js` | 入稿用のみ・非導出のとき |
| pdf | `backlink dedup` | PDF 系ターゲットのとき |
| pdf | `build front and back matter` | 閲覧用 PDF が要るとき |
| pdf | `merge all pdfs` | `pdf` ターゲット |
| pdf | `apply outline to output pdf` | `pdf` ターゲット |
| pdf | `compress, rename and final clean` | `pdf` 単独のとき |
| pdf | `compress and rename` | 他ターゲット併存のとき |
| pdf | `print pdf` | `print_pdf` ターゲット |
| epub | `generate epub` | `epub` / `kindle` ターゲット |
| join | `final clean` | 掃除を延期したとき |

ステップを足すときは、この表に 1 行足して相を選びます。分岐を書き足す必要はありません。

`vs build --log=debug` を実行すると、各ステップの開始・終了と所要時間が同じラベルで出力されます。

### 入稿用 PDF の導出

入稿用 PDF は、既定では閲覧用 PDF の中間成果物から導出されます（`derive_print?`）。本文を二度組まないぶん速く、閲覧用で確認した本文がそのまま入稿物になります。本文に紙端まで届く要素があり `full_bleed: true` を指定した場合のみ、塗り足し込みで個別にレンダリングします。

導出のときは `print_pdf` 単独指定でも閲覧用の中間 PDF を作ります。表の実行条件が `need_viewing_pdf` で連動しているのはこのためです。

### 本文ガード

本文 PDF を生成するステップには**本文ガード**が入っています。入稿用の本文はトンボ・塗り足し付きのもっとも重いレンダリングで、Chrome の一過性の失敗により本文が数ページに縮退することがありました。そこで生成後にページ数を検証し、本文相応に満たなければ再ビルドし、規定回数で回復しなければビルドを明示的に中断します。黙って本文の欠けた PDF を出荷しないための仕組みです。

### 前処理・変換・後処理

`:shared` 相の中身は、大きく三段に分かれます。

**前処理**（`cli/pre_process/`）は `MarkdownPreprocessor#run` が担い、フロントマター生成・データ展開・画像パス正規化・コードインクルード・コンテナ変換・数式や図の生成・リンクの脚注化などを順に適用します。原稿ファイルは一切変更せず、加工結果をワークスペースへ書き出します。

**変換**（`cli/convert.rb`）は VFM（Vivliostyle Flavored Markdown）を呼び出して Markdown を HTML にします。

**後処理**（`cli/post_process/`）は、生成された HTML に対して `<body>` へのクラス付与・組み込み置換・見出しのラップ・脚注のページ脚注化・行番号付与・見出し番号の付与などを適用します。

:::{.tip}
処理をどの段に置くかは「Markdown の構造を見たいか、HTML の構造を見たいか」で決まります。ブロックの切り出しやコード領域の保護が要るものは前処理、要素の入れ子や属性を触るものは後処理が向いています。
:::

## EPUB と Kindle の生成

`output.targets` に `epub` または `kindle` があると、`:epub` 相で `Build::EpubFlow` が動きます。

### フレーバ分離

`epub`（楽天 Kobo・Apple Books 向けのクリーン EPUB）と `kindle`（Amazon 向け）は、同じ `EpubBuilder` を**フレーバ**で切り替えて作ります。中心は `generate_epub_entries!(dir, entries, flavor:)` です。

- **共通**: EPUB マーカー `vs-epub` の付与、索引・用語集の後処理、脚注 id の整理、テーブルの `align` 正規化、絵文字の復元、扉絵・節絵の注入
- **Kindle 限定**: WebP から JPEG/PNG への変換、`vs-kindle` マーカーの付与、画像サイズの制約、数式の単位変換、コードブロックの調整、囲みボックスへの実ラベル注入

`vs-epub` は「リフロー文脈である」ことを示す両フレーバ共通の印、`vs-kindle` は「Kindle 向けに劣化させた」ことを示す印です。**Kindle の `<body>` は両方を持ちます。**クリーン EPUB だけに当てたい CSS は `body.vs-epub:not(.vs-kindle)` と書く必要があります。

フレーバごとに消費者ディレクトリ（`epub/` と `kindle/`）が分かれているため、相互汚染は構造的に起こりません。表紙画像だけは両枝が同じ場所へ書くので、共通前段の `prepare cover assets` が一度だけ作ります。

### KPF 変換

`kindle` ターゲットでは、中間 EPUB を作ったあと `convert_epub_to_kpf!` が `kindlepreviewer`（Kindle Previewer 3 同梱の CLI）を呼んで `.kpf` を生成します。未インストールなら中間 EPUB を残して変換だけスキップし、警告に留めます。Kindle を使わない利用者のビルドを止めないためです。変換ログのエラー・警告コードは集計して要約表示します。

### KFX の CSS 制約

Kindle の表示エンジン（KFX）は、EPUB で広く使える CSS の一部を解しません。`body.vs-kindle` 配下のフォールバックを書くときは、以下を避けて具体値で記述します。

- `:is()` セレクタ（**ルールごと破棄される**。複合セレクタは展開して書く）
- `var()` / `calc()` / `clamp()` などの CSS 関数
- `display: grid`、`linear-gradient()`、`::before` の絶対配置
- WebP 画像
- 改ページは `break-before: page` より旧来の `page-break-before: always` が確実

対応状況の一覧と回避策は `kindle-css-compatibility-notes.md` が正典です。

## 主要サブシステム

### 索引・用語集

Vivliostyle の `target-counter` はレンダリング時にページ番号を解決するため、Ruby のビルド時点では実際のページ番号が分かりません。そこで「**Ruby がリンク構造を作り、CSS がページ番号を流し込む**」設計を採っています。

本文中の索引語は `<dfn id="idx-...">`（初出）または `<span id="idx-...">`（二度目以降）に変換され、索引ページの `<a href="chapter.html#idx-...">` が `target-counter(attr(href), page)` でページ番号を描きます。

索引と用語集は `config/index_glossary_terms.yml` の単一ファイルで管理し、各語の `flags` で所属を決めます。

| flags | 掲載先 | 本文への挿入 |
|-------|--------|------------|
| `i` | 索引のみ | `<span class="index-term">` |
| `g` | 用語集のみ | `<span>` ＋ `<a class="glossary-link">†</a>` |
| `ig` | 両方 | `<span>` ＋ `<a class="glossary-link">†</a>` |

索引の主要参照（その語を説明している章）は太字で先頭に置き、副次参照を後ろに続けます。同じページを指す重複は `backlink dedup` が排除します。組み上がった PDF の named destinations を読んで「アンカー ID からページ番号」を得るので、章が複数ページにまたがっても正確です。

著者向けの記法と運用は「索引・用語集機能」の章にあります。

:::{.note}
索引語は本文に埋め込まれる透明なアンカーです。初出を包む `<dfn>` はブラウザ既定で斜体になるため、打ち消しを `stylesheets/base.css` に置いています。索引語が現れるのは本文・見出し・目次のすべてなので、全ページが読む CSS でなければ届きません。
:::

### QueryStream

`data/*.yml` のデータと `templates/_book.md` などのテンプレートを組み合わせ、原稿の 1 行を一覧へ展開する機能です。実装は `query-stream` gem として独立しており、`cli/pre_process/data_render.rb` が呼び出します。

`QueryStreamParser` が `= books | tags=ruby | :full` をパースし、`DataResolver` がデータファイルを探し（`book` と書いても複数形に補完します）、`FilterEngine` が絞り込みと並べ替えを行い、`TemplateCompiler` がテンプレートへ流し込みます。

テンプレートは `templates/_<単数形>.<スタイル>.md` の規約で解決されるため、`_book.mystyle.md` を置くだけで `= books | :mystyle` が有効になります。`data/elements.yml` と `templates/_element.md` を置けば、設定を変えずに `= elements` が使えます。新しいデータ種別を足すのに、コードを書く必要はありません。

記法の詳しい説明は「データ展開機能の使い方」の章にあります。

### CrossReference

図・表・コードリストに「章番号＋連番」を自動付与し、本文から参照リンクを張る機能です。実装は `cli/pre_process/cross_reference_processor.rb` で、前処理の中で全章を一括して処理します。

1. **ラベルの収集** — `LabelCollectorContext` が全章を走査してラベルマップを構築。重複 ID はエラーとして記録
2. **ブロックの変換** — `CaptionedBlockTransformer` がキャプション行と直後のブロックを HTML にし、`id` と章番号付きの連番を埋め込む
3. **参照の置換** — `ReferenceReplacer` が本文の参照をラベルマップと照合し、番号付きリンクへ置き換え

全章のラベルを集めてから置換する必要があるため、この処理だけは章ごとではなく一括で走ります。

見出しに付けたラベルのアンカーは、見出しの**内側**に空要素として置きます。外に置くと `break-before: page` でアンカーだけが前ページに落ち、参照先のページ番号が 1 つずれるためです。

### `@` ディレクティブの二トラック

`@` で始まる記法は、実装される場所がふたつに分かれています。

| 記法 | 処理する場所 | 実装 |
| :--- | :--- | :--- |
| `@pageref:id` ／ 見出しラベル | 前処理（全章一括） | `CrossReferenceProcessor` |
| `@qr:URL` | 前処理（章ごと・画像生成を伴う） | `QrTransformer` |
| `@vspace` `@hspace` `@pagebreak` `@version` `@title` `@today` | 後処理（HTML への文字列置換） | `ReplacementRules` |

後処理の置換は PDF・EPUB・Kindle が共有する HTML に一度だけ効きます。**出力ごとの差は Ruby ではなく CSS のカスケードで吸収します。** `target-counter()` や `break-before: recto` を解さないリーダーは、その宣言だけを捨ててフォールバックを採るためです。

`@version` / `@title` / `@today` は値が `book.yml` とビルド時刻に依存するため、凍結定数ではなく適用のたびに組み立てられます。定数にすると設定を読み直したあとも古い値を差し込んでしまいます。

### PDF プロバイダの二系統

隠しノンブルの埋め込みと PDF アウトラインの付与は、`VivlioStarter::Pdf.provider`（`cli/pdf/provider.rb`）が選ぶ実装に委ねられています。

| プロバイダ | 置き場所 | ライセンス | 機能 |
|-----------|---------|-----------|------|
| `StandardProvider` | 本体（`cli/pdf/standard_provider.rb`） | MIT（Prawn + CombinePDF） | ノンブルのみ。アウトラインは警告して何もしない |
| `EnhancedProvider` | 別 gem `vivlio-starter-pdf` | AGPL-3.0（HexaPDF） | ノンブル＋アウトライン |

AGPL のライブラリを本体から切り離すための構造です。`vivlio-starter-pdf` が gem としてインストールされていれば自動的に Enhanced が選ばれ、`VIVLIO_PDF_PLUGIN=disable` を与えると常に Standard になります。`vs pdf:read` の画像抽出・OCR も同じ切り分けです。

:::{.notice}
プラグインを入れた開発機では、ビルドは Enhanced 経路を通ります。`StandardProvider` だけを直しても実ビルドの挙動は変わりません。両方を直し、プラグイン側は `gem build` とバージョン更新を経て入れ直してください。
:::

## 拡張の手引き

### 著者向けの記法を足す

`:::{.class}` の囲み、```` ```mermaid ```` のようなフェンス、インライン記法、生成資産（SVG・画像）を新設するときは `notation-implementation-guide.md` に手順があります。最初に読むべきは §2 の**再実装禁止リスト**です。

| 基盤 | 責務 |
|---|---|
| `Masking` | コード領域解釈の唯一の実装。フェンスとインラインコードの解釈は必ずここを通す |
| `IndexMarkup` | 索引マークアップ `[用語]` の綴りの唯一の定義。`[…]` と綴る記法を足したら除外を 1 項目足す |
| `MarkdownUtils` | `extract_code_spans` と `restore_code_spans`。コードを退避して処理し復元する標準手順 |
| `GeneratedAssetCache` | 生成資産の永続キャッシュ |
| `MarkdownTransformer` | `convert_container_blocks` が `:::{.class}` をタグへ変換 |
| `ToolUpgrader::TOOLS` | 外部ツールの正典。`doctor --fix` と `vs upgrade` が共用 |

これらと同じ責務のコードを書き始めたら、それは基盤側に API を足すサインです。

囲みボックスを新設するときは Kindle 劣化の三点セットを併せて行います。`EpubBuilder::ADMONITION_LABELS` へラベルを足し、`chapter-common.css` に `body.vs-kindle` 配下の規則を**リテラル色**で書き、レイアウトテストにラベルの検査を足します。KFX は `::before` と `var()` を無視するため、この三つがそろってはじめて Kindle でも囲みとして読めます。

### ビルドステップを足す

`full_mode_step_table` に `[ラベル, ハンドラ, 実行条件, 相]` を 1 行足します。相の選び方が設計判断のすべてです。

- 両方の出力が読む中間物を作るなら `:shared`
- PDF だけが要るなら `:pdf`、EPUB・Kindle だけなら `:epub`
- 両枝の完了を待つ必要があるなら `:join`

`:shared` に置いたステップは並列化の恩恵を受けませんが、`:pdf` と `:epub` に同じ処理を二度書くよりは安全です。逆に、両枝が同じファイルへ書くステップを枝側に置くと競合します（表紙資産を `:shared` に置いているのはこのためです）。

### 設定キーを足す・やめる

`book.yml` のキーと既定値は `cli/config_keys.rb` の 1 表が正典です。ただし手を動かす前に `config-key-criteria-guidelines.md` の五つの判断軸を読んでください。「そのキーは設定であるべきか」を問うもので、足す手順より先に立ちます。足す手順は `config-extension-guidelines.md`、やめる手順は `config-retirement-guidelines.md` にあります。

章の basename を保持する設定やデータを足すときは `ChapterRename::FOLLOWERS` への登録が要ります。登録を忘れると `vs rename` が黙って参照を壊します。

### スキャフォールドを同期する

`lib/project_scaffold/` は `vs new` が展開する雛形です。**その正本はプロジェクトルートにあります。** `contents/`・`stylesheets/`・`images/`・`config/`・`templates/` などはルート側で開発・検証し、`ruby copy_to_scaffold.rb` で雛形へ複製します。

```bash
# ルートの stylesheets/ を編集してから
ruby copy_to_scaffold.rb
```

`lib/project_scaffold/` を直接編集すると、次の同期で黙って消えます。逆に、ルートを直して同期を忘れると、著者の手元にだけ古いものが配られます。CSS を触ったら同期する、と覚えてください。

### 知見メモを引く

「CSS は正しいはずなのに効かない」「Kindle だけ崩れる」「並列ビルドで再現しない」といった、原因がエンジン側や基盤側にある問題は、たいてい一度は誰かが踏んでいます。`docs/specs/NOTES.md` がその索引です。

| 索引の区分 | 内容 |
|---|---|
| 恒常ガイドライン | 記法を足す・設定キーを足す/やめる・章名を保持するデータを足すときの規範 |
| 知見メモ | CSS の落とし穴、Kindle の制約、ビルドの枝をまたぐ処理、Type 3 フォント、端末出力、組版の改行 |
| 検討メモ | まだ決めていないことの記録。着手するときの出発点 |

**索引の各項目は「いつ引くか」で書かれています。**探しものの名前ではなく、症状から引いてください。新しく `-notes.md` や `-guidelines.md` を書いたら、ここへ 1 行足すのが運用です。

実装済みの仕様書は `docs/archives/` へ移ります。「実装されているか」の答えは `docs/specs/STATUS.md` が持っており、置き場所から判断するものではありません。

## テスト

Minitest を使っています。実ビルドを伴う重いスイートは専用タスクに分かれています。

```bash
bundle exec rake test
```

いずれも `rake` に続けて実行します。

| タスク | 内容 |
|--------|------|
| `test` | 通常のユニットテスト（実ビルドなし） |
| `test:standard` | MIT 経路（`StandardProvider`）を強制実行 |
| `test:versions` | 対応する複数の Ruby で実行 |
| `test:layout` | 判型・ページレイアウトの統合テスト |
| `test:targets` | 出力ターゲットの整合性（単体・複合を突き合わせ） |
| `test:type3` | Type 3 フォントの混入検証 |
| `test:kindle` | Kindle 変換の検証 |
| `test:manual` | マニュアル実ビルドの回帰検査 |
| `test:package` | パッケージング E2E（gem build から隔離インストールまで） |
| `test:canary` | 依存カナリア（Vivliostyle CLI 最新版での破壊検知） |
| `test:release` | リリース前の総点検（上記を一括実行） |

外部ツールに依存するテストはモックしており、ツール未導入の環境でも実行できます。

:::{.notice}
`vivlio-starter-pdf` を入れた開発機では `rake test` は Enhanced 経路しか通りません。MIT 経路の回帰を捉えるには `rake test:standard` を併せて実行してください。本体のテストが AGPL の HexaPDF に依存しないよう、PDF は Prawn で作り pdf-reader で検査します。
:::

### 堅牢性テスト

「想定外の入力・環境・操作」に対する振る舞いは `test/vivlio_starter/robustness/` に集約しています。カタログに登録済みのファイルがない場合の継続、パストラバーサルを含む画像パス、`vs new` 中断時の後始末、`vs lint --fix` 中断時のファイル保全、YAML の危険なタグの拒否、SIGINT/SIGTERM の終了コード、並列ビルドの排他などが対象です。

環境依存のテスト（書き込み権限・外部コマンド不在・シグナル送信）は、条件を満たさないときは理由を示して `skip` します。

## 堅牢性・セキュリティ設計

執筆プラットフォームとして、想定外の入力に対して「静かに壊れる」のではなく**明示的に通知して安全に停止する**ことを原則としています。

### 防衛線の階層

| 層 | 担当範囲 | 代表的な機構 |
|:---|:---|:---|
| 入力検証 | `book.yml` / `catalog.yml` / `data/*.yml` | `Common.validate_book_config!`、各ローダの `safe_load` |
| 静的解析 | 原稿 Markdown | `LinkImageValidator.scan_dangerous_schemes`（`file://` / `javascript:`） |
| 実行前提 | コマンド実行の前提条件 | `cli/guards/` の Guard と Check |
| 外部コマンド | `vivliostyle` / `rsvg-convert` / ImageMagick ほか | `Common.ensure_external_command!`、`Common.run_svg_converter!` |
| 同時実行制御 | 同一プロジェクトの多重ビルド | `BuildLock`（`flock` ベース） |
| シグナル | Ctrl+C / SIGTERM | `CLI.start` の三段 rescue |
| 副作用保護 | `vs new` 展開中 / `vs lint --fix` 中の中断 | 展開のクリーンアップ、一時ファイル経由の非破壊書き換え |

### YAML の扱い

すべての YAML 読み込みで `YAML.safe_load` 系のみを使い、`permitted_classes` を明示します。`catalog.yml` は空（最小）、`data/*.yml` は実用に必要な範囲に限ります。`aliases: true` はプリセットの継承に使うため許可しています。`Psych::DisallowedClass` は素通しせず、ファイルパスとタグ名を含む日本語のメッセージへ変換して通知します。

### 常時有効とオプトアウトの区別

危険なスキームの検出は `--no-verify` でも無効化されません。ビルドを速くするために画像の存在確認や裸 URL の検出は切れますが、**セキュリティ保護は選択肢から外す**ことで、うっかり無効化による事故を防いでいます。

### 堅牢化を足すときの指針

1. **上流で例外を変換する**。生のスタックトレースではなく、原因と次の一手を含む日本語のメッセージにする
2. **原因特定に必要な情報を含める**。ファイルパス・行番号・該当値・推奨アクション
3. **回帰テストを `robustness/` に置く**
4. **常時有効か、オプトアウト可能かを区別する**。セキュリティは常時有効、品質チェックは選択可能
5. **環境依存のテストは理由付きで `skip` する**

## 検証済みの動作環境

| 項目 | 対応範囲 |
|------|---------|
| Ruby | 3.4 以上（3.4.10 / 4.0.6 で検証） |
| Node.js | 26 系 |
| OS | macOS（`--fix` による自動導入は Homebrew 前提） |

Vivliostyle 関連のパッケージは `package.json` で管理しています。

| パッケージ | バージョン | 役割 |
|-----------|-----------|------|
| `@vivliostyle/cli` | 11.0.2 | CSS 組版エンジン CLI。`vs build` から呼び出す |
| `@vivliostyle/vfm` | 2.7.0 | Markdown から HTML への変換 |
| `@vivliostyle/core` | 2.43.2 | レンダリングエンジン（CLI に内包） |

`vs build` はグローバルに導入された `vivliostyle` コマンドを呼びます（`vs doctor --fix` が導入します）。11 系では脚注まわりの組版が大きく改善されています。最新版は[npmjs.com/@vivliostyle/cli](https://www.npmjs.com/package/@vivliostyle/cli)で確認できます。

外部ツール（Ghostscript・ImageMagick・Inkscape・qpdf・MeCab ほか）の要否と導入は `vs doctor` が診断します。入稿用 PDF の導出には qpdf 11 以上が必要です。

:::{.note}
本章で触れた設計の意図や実装の経緯は `docs/specs/` の仕様書と知見メモに記録されています。公開リポジトリの[docs/specs](https://github.com/Atelier-Mirai/vivlio-starter/tree/master/docs/specs)から読めます。フォークして開発するときは、変更前に該当する文書を確認し、実装後は `CHANGELOG.md` を更新してください。
:::
