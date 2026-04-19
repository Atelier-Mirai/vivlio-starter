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
| `replace-list.css` | `config/post_replace_list.yml` の置換ルールで付与される隠れクラス（`.kaiwa` `.aokome` `.akakome` `.codered-right` `.hen-comment` `.figure-guides` 等）のスタイル |
| `page-settings.css` | 用紙サイズ・マージン設定 |
| `toc.css` | 目次のスタイル |
| `preface.css` | 前書きページのスタイル |
| `postface.css` | 後書きページのスタイル |
| `appendix.css` | 付録ページのスタイル |
| `colophon.css` | 奥付のスタイル |
| `titlepage.css` | タイトルページのスタイル |

## カスタマイズ

テーマカラーや扉絵などのデザイン設定は `config/book.yml` の `theme` セクションで行います。`theme.css` はビルド時に自動生成されるため、直接編集しても次回ビルド時に上書きされます。

CSS の仕組みや内部構造については「開発者向けガイド」の章を参照してください。

## fonts/ と images/

- `fonts/` — 埋め込みフォントファイル。`config/page_presets.yml`で指定されたフォントが配置されます。
- `images/` — 扉絵・装飾画像など CSS から参照する画像。著者が独自に用意した扉絵や装飾画像を使いたい場合もここに配置します。`config/book.yml` の `theme.frontispiece` や `theme.ornament` で参照できます。

