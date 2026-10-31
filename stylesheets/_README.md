# stylesheets/ — スタイルシートディレクトリ

書籍のレイアウトとデザインを定義する CSS ファイルを配置するディレクトリです。

## ファイル一覧

| ファイル | 役割 |
|----------|------|
| `custom.css` | 著者独自のスタイル（下の「カスタマイズ」を参照） |
| `theme.css` | テーマ色や見出しの寸法などの CSS 変数（`custom.css` で上書きできる変数の一覧） |
| `base.css` | 全要素の初期化と、画像・見出しの基本設定 |
| `chapter.css` | 章ページのスタイル |
| `chapter-common.css` | 章共通スタイル |
| `code.css` | コードブロックのスタイル |
| `table.css` | 表のスタイル |
| `components.css` | コラム・注意書きなどのコンポーネント |
| `replace-list.css` | post_process の組み込み置換ルールで付与される隠れクラス（`.aokome` `.akakome` 等）のスタイル |
| `page-settings.css` | ページの枠組み（`@page`）と同梱書体の定義。判型の値は `config/book.yml` の `page` で決まります |
| `simple-header.css` | 画像なしの章ヘッダー（`theme.style: simple` と付録） |
| `image-header.css` | 画像ありの章ヘッダー（`theme.style: image`） |
| `prism.css` | コードの色分け（Prism） |
| `spacing.css` | 余白のユーティリティ（`{.aki}` など） |
| `layout-utils.css` | 写真グリッドなどのレイアウトのユーティリティ |
| `pagebreak.css` | 改ページ記法（`---`・`@pagebreak`） |
| `toc.css` | 目次のスタイル |
| `preface.css` | 前書きページのスタイル |
| `postface.css` | 後書きページのスタイル |
| `appendix.css` | 付録ページのスタイル |
| `colophon.css` | 奥付のスタイル |
| `titlepage.css` | タイトルページのスタイル |
| `legalpage.css` | 免責・商標ページのスタイル |
| `part-title.css` | 部扉のスタイル |
| `index.css` | 索引ページのスタイル |
| `glossary.css` | 用語集ページのスタイル |

## カスタマイズ

テーマカラーや扉絵などのデザイン設定は `config/book.yml` の `theme` セクションで行ってください。
**著者独自のスタイルは `custom.css` に書いてください。** 最後に読み込まれるので、他のどの CSS よりも優先されます。

## fonts/ と images/ と twemoji/

- `fonts/` — 埋め込みフォントファイル。`config/book.yml` の `typography` で指定した書体が置かれます。同梱書体（Noto Serif JP・Noto Sans JP・Zen Maru Gothic・HackGen35 Console NF）以外を指定すると Google Fonts から `fonts/google/` へ自動取得されます。
- `images/` — 扉絵・装飾画像など CSS から参照する画像。著者が独自に用意した扉絵や装飾画像を使いたい場合もここに配置します。`config/book.yml` の `theme.frontispiece.image` や `theme.ornament.image` で参照できます。
- `twemoji/` — 絵文字の画像。
