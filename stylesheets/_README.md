# stylesheets/ — スタイルシートディレクトリ

書籍のレイアウトとデザインを定義する CSS ファイルを配置するディレクトリです。

## 読み込まれ方

各ページは、ページの種類ごとに生成される入口の CSS（`.cache/vs/entry-<種類>.css`）を 1 枚だけ読みます。入口は、このディレクトリの CSS を層（`@layer`）に分けて読み込みます。後の層が前の層に勝ち、層の外に置いた CSS は、どの層にも勝ちます。

| 層 | 置き場 | 中身 |
|----|--------|------|
| `reset` | `base/reset.css` | 全要素の初期化 |
| `base` | `base/elements.css`・`base/page.css` | 要素の基本と、ページの枠組み（`@page`）。判型の値は `config/book.yml` の `page` で決まります |
| `tokens` | `tokens.css` | テーマ色や見出しの寸法などの CSS 変数（`custom.css` で上書きできる変数の一覧） |
| `parts` | `parts/` | 見出し・段落・リスト・図版・囲み・コード・表・会話・脚注・並べ方などの部品。本文のページ（章・付録・前書き・後書き）はみな同じ部品を読み、前書き・後書きは最後に `parts/preface.css`（前書きの見た目）を読みます |
| `pages` | `pages/` | 目次・索引・用語集・奥付・扉・権利ページ・部扉と、本文のページの種類ごとの設定（章の扉絵・付録の色・前書きと後書きのノンブル） |
| `utilities` | `utilities/` | 原稿で指定する位置・余白・改ページ・横並びの間隔と、置換の規則が付けるクラス |
| `settings` | （生成物） | `config/book.yml` から生成する規則 |
| （層の外） | `fonts.css`・`custom.css` | 同梱書体の定義（`@font-face`）と、著者独自のスタイル |

## カスタマイズ

テーマカラーや扉絵などのデザイン設定は `config/book.yml` の `theme` セクションで行ってください。
**著者独自のスタイルは `custom.css` に書いてください。** `custom.css` は層の外に置かれるので、詳細度に関係なく、他のどの CSS よりも優先されます。

ほかの CSS は `vs upgrade` で新しい雛形へ更新されます。直接編集すると、雛形が変わるたびに手元の変更との突き合わせが必要になります。

## 書き方の約束（雛形の CSS）

- 規則の中のプロパティは、配置（`display`・`position`・`float`・`break-*`）→ 大きさ（`width`・`inline-size`）→ 余白（`margin`→`padding`）→ 文字（`font-*`・`line-height`・`text-*`）→ 揃え（`text-align`・`align-*`）→ 見た目（`color`・`background`・`border`）→ カウンタと内容（`counter-*`・`string-set`・`content`）の順に書きます。
- 余白や大きさは、論理プロパティ（`margin-inline` など）を優先します。

## fonts/ と images/ と twemoji/

- `fonts/` — 埋め込みフォントファイル。`config/book.yml` の `typography` で指定した書体が置かれます。同梱書体（Noto Serif JP・Noto Sans JP・Zen Maru Gothic・HackGen35 Console NF）以外を指定すると Google Fonts から `fonts/google/` へ自動取得されます。
- `images/` — 扉絵・装飾画像など CSS から参照する画像。著者が独自に用意した扉絵や装飾画像を使いたい場合もここに配置します。`config/book.yml` の `theme.frontispiece.image` や `theme.ornament.image` で参照できます。
- `twemoji/` — 絵文字の画像。
