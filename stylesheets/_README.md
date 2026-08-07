# stylesheets/ — スタイルシートディレクトリ

書籍のレイアウトとデザインを定義する CSS ファイルを配置するディレクトリです。

## 主要ファイル

| ファイル | 役割 |
|----------|------|
| `theme.css` | 色・フォント・全体テーマの定義（カスタマイズの起点） |
| `base.css` | 基本レイアウト・余白・フォントサイズ |
| `chapter.css` | 章ページのスタイル |
| `chapter-common.css` | 章共通スタイル |
| `code.css` | コードブロックのスタイル |
| `table.css` | 表のスタイル |
| `components.css` | コラム・注意書きなどのコンポーネント |
| `replace-list.css` | post_process の組み込み置換ルールで付与される隠れクラス（`.aokome` `.akakome` 等）のスタイル |
| `page-settings.css` | 用紙サイズ・マージン設定 |
| `toc.css` | 目次のスタイル |
| `preface.css` | 前書きページのスタイル |
| `postface.css` | 後書きページのスタイル |
| `appendix.css` | 付録ページのスタイル |
| `colophon.css` | 奥付のスタイル |
| `titlepage.css` | タイトルページのスタイル |

## カスタマイズ

テーマカラーや扉絵などのデザイン設定は `config/book.yml` の `theme` セクションで行ってください。
**著者独自のスタイルは `custom.css` に書いてください。** 最後に読み込まれるので、他のどの CSS よりも優先されます。

## fonts/ と images/

- `fonts/` — 埋め込みフォントファイル。`config/book.yml` の `typography` で指定した書体が置かれます。同梱書体（Zen 3 種・HackGen35 Console NF）以外を指定すると Google Fonts から `fonts/google/` へ自動取得されます。
- `images/` — 扉絵・装飾画像など CSS から参照する画像。著者が独自に用意した扉絵や装飾画像を使いたい場合もここに配置します。`config/book.yml` の `theme.frontispiece` や `theme.ornament` で参照できます。
