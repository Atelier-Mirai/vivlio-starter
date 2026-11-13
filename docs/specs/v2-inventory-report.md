# 2.0 の設計に向けた棚卸し

`v2-design-research-brief.md` §4 の棚卸しの結果。Fable がパイプラインの責務分割・拡張点・移行計画を設計するときに、大きなファイルを読まずに済むよう、コードと生成物から数えた事実だけを並べる。判断は書かない（判断は Fable の仕様書で行う）。

- 調べた日: 2026-11-13（master b88011b3）
- 生成物の測り方: 本書の写しを `targets: epub`・`--no-clean` で組み（43.3 秒）、`.cache/vs/build/html/` の 39 ファイルを Nokogiri で数えた。数え方のスクリプトは記録の末尾（§8）に載せる
- 数は本書で使っている記法の範囲のもの。本書で使っていない記法のクラスは、生成物の数に入らない

---

## 1. 段の一覧

`build/pipeline.rb` の `full_mode_step_table` は、すでに 1 枚の宣言的な表になっている。各行は `[ラベル, ハンドラ, 実行条件, 相, 単位]` の 5 つ組で、条件はビルド開始時に `targets` から決まる。

- **相**: `:shared` → (`:pdf` ∥ `:epub`) → `:join` の順に評価する。`:pdf` と `:epub` は fork で並列に走る（`VIVLIO_BUILD_PARALLEL=0` で逐次）
- **単位**: `:chapter`（1 章だけで答えが出る）か `:whole_book`（全章がそろわないと答えが出ない）。単章ビルドは `:chapter` の行だけを、`SINGLE_MODE_SKIP` を除いて走らせる

### 1.1 full モードの段

| 段 | 相 | 単位 | 実行条件 | 中身 |
|---|---|---|---|---|
| clean | shared | chapter | 常に | 前回の生成物を消す |
| optimize images | shared | chapter | 常に | 画像の最適化 |
| prepare theme images | shared | chapter | 常に | 扉絵・節絵の画像を用意する |
| prepare cover assets | shared | whole_book | 表紙が要るとき | 表紙の資産（両枝が読む） |
| preprocess sections | shared | chapter | 常に | 章ごとの Markdown の前処理（§1.2）。全章の後で相互参照を一度だけ解く |
| index scan and build | shared | chapter | 常に（`index_glossary.enabled: false` なら中で戻る） | 索引語の走査と索引・用語集ページ |
| convert sections html | shared | chapter | 常に | VFM で HTML にし、章ごとの後処理（§1.3） |
| generate part title pages | shared | whole_book | 常に | 部扉 |
| generate whole toc | shared | whole_book | 分冊のとき | 全巻目次 |
| generate front and back matter html | shared | whole_book | 常に | 扉・権利ページ・奥付の HTML |
| techbook post-process | shared | chapter | 常に（`output.pdf.techbook` で中が有効） | Type 3 対策（絵文字の画像化・囲み数字など）。単章では走らせない |
| generate toc html | shared | whole_book | 常に | 目次 |
| build overall pdf | pdf | whole_book | `pdf` か導出の `print_pdf` | Vivliostyle で本文を組む |
| extract rotate table images | pdf | whole_book | `kindle` と PDF を同時に作るとき | Kindle 用に回転表をページ画像にする |
| generate entries.js | pdf | whole_book | `print_pdf` だけで導出しないとき | |
| shrink oversized images | pdf | whole_book | PDF のどちらか | 実効解像度を測って縮小版へ |
| backlink dedup | pdf | whole_book | PDF のどちらか | 索引の重複を除いて組み直す |
| build front and back matter | pdf | whole_book | `pdf` か導出 | 前付・奥付の予備の組版 |
| merge all pdfs | pdf | whole_book | `pdf` | 結合 |
| apply outline to output pdf | pdf | whole_book | `pdf` | しおり（PDF プロバイダ経由） |
| shorten destination names | pdf | whole_book | `pdf` | 名前付きの宛先を短くする |
| check chapter leads | pdf | whole_book | `pdf` | 章扉からはみ出したリードを調べる |
| compress, rename and final clean | pdf | whole_book | `pdf` だけのとき | |
| compress and rename | pdf | whole_book | `pdf` とほかを作るとき | |
| print pdf | pdf | whole_book | `print_pdf` | 入稿用 PDF（導出か組み直し） |
| check type 3 fonts | pdf | whole_book | PDF のどちらか | Type 3 の混入を調べる |
| generate epub | epub | whole_book | `epub` か `kindle` | §1.4 |
| final clean | join | whole_book | `pdf` だけ以外 | ワークスペースを消す |

ほかのモード:

- **single**（単章）: 上の表の `:chapter` の行（`techbook post-process` を除く）＋ `entries.js + pdf`・`shorten single pdf destination names`・`check chapter leads`・`rename output pdfs`・`final clean`。出力は閲覧用 PDF だけ
- **preflight**: `optimize images`・`prepare theme images`・`preprocess sections`・`index scan and build`・`estimate chapter leads`。HTML 変換も組版もしない

### 1.2 前処理（`MarkdownPreprocessor#run`）

章ごとに、Markdown の文字列に対して 38 段を順に当てる。段と段の間の形はどれも Markdown の文字列で、書き出すのは最後の `write_output!` だけ。

| 種類 | 段 |
|---|---|
| 検査（原稿の行番号で指摘） | `validate_directives!`・`validate_image_borders!`・`validate_image_trims!`・`validate_qr_codes!`・`validate_links!`・`validate_images!`・`detect_plain_math!`・`warn_missing_glyphs!`・`warn_stroked_figures!` |
| frontmatter | `apply_frontmatter!`（ページの種類ごとの CSS の `link` をここで決める・§2.3） |
| 記法の変換 | `transform_terminal_blocks!`・`process_data_streams!`・`transform_image_borders!`・`transform_qr_codes!`・`transform_showcases!`・`transform_mermaid!`・`transform_talk!`・`process_code_includes!`・`transform_math!`・`transform_text_right_inlines!`・`transform_spacing_markers!`・`transform_text_align_containers!`・`transform_book_cards!`・`transform_tables!`・`transform_fancy_lists!`・`transform_links!` |
| 正規化 | `strip_html_comments!`・`normalize_image_paths!`・`delimit_bare_urls!`・`normalize_code_languages!`・`normalize_html_block_boundaries!`・`escape_inline_code_html!`・`normalize_container_fences!`・`mark_definition_continuations!`・`expose_container_footnotes!`・`strip_index_markup!` |

全章の前処理の後、`PreProcessCommands.execute_cross_references` が一度だけ走り、相互参照を解く。

### 1.3 HTML 変換と後処理

`convert_single_chapter!` は、VFM による変換（`ConvertCommands.execute_convert`）の後に `PostProcessCommands.execute_post_process` を呼ぶ。後処理は約 30 段で、多くの段が HTML ファイルを読み、Nokogiri か正規表現で書き換えて、ファイルへ書き戻す。段と段の間の形は HTML ファイルである。

主な段の順: `BodyClassInjector`（body のクラス）→ 端末の出力 → 置換規則 → `article.section-topic` で h2 を包む（`theme.style: image` のとき）→ 横の画像・画像の組・写真の列・画像と文・`text-table` の包み → 文中の画像の幅 → キーの組み合わせ → 章末の脚注をページ脚注へ → 脚注の番号の振り直し → Prism の行番号 → 定義リスト → 表の中のコードの `|` → 相互参照のコード → コードのキャプション → 強調の見出し → 行内の画像 → 改行の機会 → 見出しの印・見出し番号 → 最後の掃除 → `PageBreakNormalizer`。

`HeadingProcessor` の章の順は、モジュールの変数にキャッシュされる。並列のスレッドより前に `chapter_tokens_override` で注入している（`section_builder.rb`）。

### 1.4 EPUB の枝（`build/epub_flow.rb`）

フレーバ（`:epub` と `:kindle`）ごとに、次を逐次に行う。

1. `html/` を消費者のディレクトリ（`epub/` か `kindle/`）へ写す
2. `generate_epub_entries!`: HTML の書き換え（§5）と `entries.js` の生成
3. 参照する資産をパッケージの中へ写す（localize）
4. 著者の SVG を書体入りの派生へ差し替える（Kindle は PNG・JPEG へ焼く）
5. クリーン EPUB だけ: PNG・JPEG を WebP へ
6. 参照の切れた画像を回収する
7. EPUB 用の `vivliostyle.config.js` を生成する
8. Vivliostyle で EPUB を作る
9. 組み上がった EPUB の CSS から `@page` の余白の箱を消す（Kindle は WebP の `url()` も）
10. `content.opf` の数字で始まる id を直す
11. Kindle だけ: 目次の文書の自分へのリンクに飛び先を付ける
12. EPUB の識別子を安定させる
13. Kindle だけ: KPF へ変換する

---

## 2. HTML の構造

### 2.1 body のクラス

`post_process/body_class_injector.rb` が付ける。本書で出たのは 14 種。

| クラス | 出現 | ページ |
|---|---|---|
| `chapter` | 20 | 本文の章 |
| `vs-header-image` / `vs-header-simple` | 20 / 6 | 章扉の形（`theme.style`。付録は常に simple） |
| `appendix` | 6 | 付録 |
| `part-title` | 5 | 部扉 |
| `preface` / `postface` | 1 / 1 | 前書き・後書き |
| `chapter-first` | 1 | 最初の章 |
| `colophon`・`glossary-page`・`index-page`・`legalpage`・`titlepage`・`toc` | 各 1 | 奥付・用語集・索引・権利ページ・扉・目次 |

EPUB の枝では、さらに全 body に `vs-epub` を、Kindle では `vs-kindle` も付ける（両方が同居する）。

### 2.2 要素とクラス

- 生成物に出るクラスは、Prism のトークンと `language-*` を除いて **146 種**（要素とクラスの組では 249 種）
- CSS が参照するクラスは **238 種**（うち `prism.css` が 39 種）
- CSS にあって本書の HTML に出ないクラスは 77 種。内訳は、body のクラス（§2.1。数え方の都合で HTML 側に入っていない）、EPUB の枝だけで付くクラス（`vs-epub`・`vs-kindle`・`vs-adm-label` など）、本書で使っていない記法（`vs-list-upper-roman` などのリストの型・`rotate-table`・`sideimage-left`）、全巻目次（`whole-toc-*`）
- HTML にあって CSS が参照しないクラスは 23 種（`level1`〜`level4`・`index-term`・`talk-c-*` など。スクリプトや後段の処理の目印）

数の多いもの（Prism を除く）:

| クラス | 数 | 付ける処理 |
|---|---|---|
| `span.index-term` / `dfn.index-term` | 2,539 / 200 | 索引 |
| `span.vs-nobr` | 555 | 改行しない範囲 |
| `section.level1`〜`level4` | 34 / 144 / 314 / 33 | VFM |
| `h1`〜`h3.vs-h-marker`・`span.subsection-marker`・`span.subsection-title` | 37 / 147 / 314 | 見出しの印 |
| `article.section-topic` | 144 | h2 の包み（`theme.style: image`） |
| `pre.line-numbers` ほか | 272 | Prism の行番号 |
| `a.glossary-link`・`a.glossary-backlink`・`a.main-ref`・`a.cross-ref-link`・`a.pageref` | 264 / 106 / 234 / 164 / 124 | 用語集・索引・相互参照 |
| `img.vs-emoji` | 205 | 絵文字の画像化 |
| `div.output` | 134 | 出力例の囲み |
| `div.side-by-side` | 47 | 左右に並べる囲み |

### 2.3 section の入れ子と role 属性

section の入れ子は VFM の `section.levelN` のままで、vs は h2 を `article.section-topic` で包むだけ。

| 入れ子 | 数 |
|---|---|
| `level1 > level2 > level3` | 304 |
| `level1 > level2` | 144 |
| `level1` | 34 |
| `level1 > level2 > level3 > level4` | 33 |
| `level1 > level3`（h2 を飛ばした章） | 10 |

role 属性は、VFM の脚注（`a[role=doc-noteref]` 20・`aside[role=doc-footnote]` 18）と、目次（`nav[role=doc-toc]`）・用語集（`section[role=doc-glossary]`）だけに付く。章・前書き・付録・奥付・索引には付かない。

### 2.4 ページの種類と CSS の読み込み

`pre_process/frontmatter_generator.rb` が、各ページに `theme.css` → `{種類}.css` → `book-settings.css`（生成物）→ `custom.css` の順で `link` を書く。`{種類}.css` が部品を `@import` する。

| `{種類}.css` | 読み込む部品 |
|---|---|
| `chapter.css` | base・theme・page-settings・simple-header・image-header・prism・code・table・spacing・layout-utils・components・replace-list・chapter-common（→ pagebreak） |
| `appendix.css` | 上から image-header を除いたもの |
| `preface.css` / `postface.css` | `chapter-common.css` を読まない（段落・引用・字間の規則を別に持つ） |
| `colophon.css`・`legalpage.css`・`titlepage.css`・`part-title.css`・`index.css`・`glossary.css`・`toc.css` | base・theme・page-settings と自分の規則 |

---

## 3. 横書きの前提

### 3.1 CSS

コメントを除いて数えた（`stylesheets/*.css`）。

| 書き方 | 数 |
|---|---|
| 論理方向（`inline-*`・`block-*`・`inset-inline/block`・`inline-size`・`block-size`） | 259 |
| `margin` / `padding` / `border` の `-left` / `-right` | 35 |
| `text-align: left` / `right` | 20 |
| `left:` / `right:`（位置） | 10 |
| `float: left` / `right` | 7 |
| `width` 系 / `height` 系 | 31 / 19 |

物理方向（上の 2〜5 行目・72 か所）が多いのは `components.css`（11）・`layout-utils.css`（10）・`chapter-common.css`（9）・`prism.css`（8）・`page-settings.css`（7）・`colophon.css` / `glossary.css`（各 5）。

`writing-mode` は 0 件。

### 3.2 綴じと見開き

- **ノドと小口の割り当ては綴じの向きに依らない**: `page-settings.css` は `@page :left` で `margin-left: 小口`・`margin-right: ノド`、`@page :right` でその逆を指定する。見開きの内側がノドであることは、右綴じでも左綴じでも変わらない
- **「奇数ページが右」の前提**: 右綴じでは奇数ページ（recto）が左に来る。この前提を持つ箇所:
  - `build/nombre_stamper.rb:126`: 隠しノンブルを、奇数ページは左端（ノド）、偶数ページは右端に描く
  - `page-settings.css`・`toc.css`・`titlepage.css`・`colophon.css`・`legalpage.css` の `@page :left/:right`（9 か所）: 柱・ノンブルの左右の置き場
- **論理名で書いてある箇所**: `@pagebreak:recto` / `:verso`（`post_process/replacement_rules.rb`・`page_break_normalizer.rb`）、`page.chapter_pagebreak: recto`、`book.yml` の `margin_inner` / `margin_outer`。綴じの向きが変わっても意味が保たれる
- **寸法の意味**: 画像の `width=50%` は「行の長さに対する割合」のつもりで書かれている。縦書きでは行の長さは高さになるので、`width` で指定した値の意味が変わる

### 3.3 EPUB

`lib/` に `page-progression-direction`・`primary-writing-mode`・`rendition:layout` の記述は 0 件。

---

## 4. 技術書に寄った機能と設定キー

`book.yml` は 471 行・最上位 17 節。

| 機能 | 設定キー | 使われる段 | 今の切り替え |
|---|---|---|---|
| 索引・用語集 | `index_glossary`・`index`・`glossary` | `index scan and build`・`backlink dedup`・EPUB の `post_process_index_glossary_for_epub!`・`index.css`・`glossary.css` | `index_glossary.enabled` で無効にできる |
| 文章の lint | `lint`・`spellcheck` | `vs lint`（ビルドの段ではない） | 規則は技術文書向けの一組だけ |
| 分量の計測 | `metrics` | `vs metrics`（ビルドの段ではない） | |
| コード | `typography.code` | 前処理の `process_code_includes!`・`normalize_code_languages!`、後処理の Prism の行番号、EPUB の `convert_code_blocks_for_epub!`、Kindle のコードの 3 段 | 常に有効（コードが無ければ空振り） |
| 章扉・節の飾り | `theme.color`・`style`・`frontispiece`・`ornament`・`markers` | `prepare theme images`・後処理の `section-topic`・EPUB の `inject_heading_images_for_epub!` | `theme.style: simple` で画像を外せる |
| 章番号の範囲 | （キーなし。ファイル名の番号で決まる） | `TokenResolver` が全体で使う | `00` 前書き・`01–89` 章・`90–98` 付録・`99` 後書き |
| 見出し番号 | `page.heading_numbering` | 後処理の見出し番号 | |
| 免責・商標 | `legal` | `generate front and back matter html` | |
| Type 3 対策 | `output.pdf.techbook` | `techbook post-process` | キーの名前は「技術書」だが、中身は PDF の書体の対策 |
| リンクの検査 | `verify` | `--verify-links` | |
| PDF の読み取り | `pdf_read` | `vs pdf:read`（ビルドの段ではない） | |

---

## 5. `EpubBuilder` の分類

`build/epub_builder.rb` は 3,858 行・177 メソッド。`generate_epub_entries!` の中で、HTML の書き換えが 2 つの相に分かれている。

**両フレーバ共通（11 段）**: `mark_body_for_epub!`・`bundle_book_settings_for_epub!`・`strip_inline_footnote_ids_for_epub!`・`rewrite_table_align_for_epub!`・`restore_plain_emoji_for_epub!`・`inject_heading_images_for_epub!`（クリーンは SVG・Kindle は JPEG）・`localize_showcase_images!`・`shrink_side_by_side_figures_for_epub!`・`convert_code_blocks_for_epub!`・`decorate_footnotes_for_epub!`・`post_process_index_glossary_for_epub!`

**Kindle 専用（18 段）**: `decorate_talk_for_kindle!`・`transcode_webp_images_for_epub!`・`strip_webp_inline_styles_for_kindle!`・`mark_body_for_kindle!`・`restore_h3_markers_for_kindle!`・`constrain_layout_images_for_epub!`・`compose_pictures_for_kindle!`・`textify_simple_math_for_kindle!`・`rasterize_display_math_for_kindle!`・`convert_math_units_for_epub!`・`keep_cell_math_inline_for_kindle!`・`align_code_cells_for_kindle!`・`inject_code_line_numbers_for_kindle!`・`decorate_admonitions_for_epub!`・`decorate_list_markers_for_epub!`・`layout_index_columns_for_kindle!`・`replace_rotate_tables_for_kindle!`・`apply_variant_glyph_fonts_for_kindle!`

メソッド名の `_for_epub!` は、Kindle 専用の相で呼ばれるものも含む。名前からはどちらの相かを判別できない。

ファイルの中の区切り（コメントの見出し）: 消費者のディレクトリ・索引と用語集・脚注の id・表の `align`・絵文字・扉絵と節絵・WebP の変換・著者の SVG・参照の切れた画像の回収・Kindle のレイアウトの是正（約 850 行）・回転表の画像化（約 360 行）・異体字の書体（約 200 行）・CSS のサニタイズ・`content.opf` の書き換え・KPF の変換。

---

## 6. Kindle 向けの劣化

`v2-design-research-brief.md` §2 では三か所としたが、四か所あった。

| 場所 | 中身 | 量 |
|---|---|---|
| 静的な CSS の `body.vs-kindle` | 枠や背景をリテラルの色で描き直す・flex や grid の代わりの組み方・ラベルの余白 | 10 ファイル・124 か所（`layout-utils.css` 46・`chapter-common.css` 29・`components.css` 10・`colophon.css` 10・`glossary.css` 7・`simple-header.css` 7・`code.css` 6・`index.css` 6・`table.css` 2・`preface.css` 1） |
| `pre_process/book_settings_css.rb` が書き出す規則 | テーマ色を `var()` からリテラルへ焼き込む。`kindle_accent_rules`（本文・索引と用語集・付録・前書き）、`kindle_custom_color_rules`（`custom.css` の色）、`h4_marker_kindle_rule` | 8 メソッド |
| `EpubBuilder` の DOM の組み替え | §5 の Kindle 専用 18 段 | |
| 組み上がった EPUB の CSS の書き換え | `sanitize_epub_css!`: `@page` の余白の箱を消す（両フレーバ）・WebP の `url()` を消す（Kindle） | 1 メソッド |

参考: クリーン EPUB 用の `body.vs-epub` の規則は 4 ファイル・28 か所（`components.css` 14・`code.css` 7・`layout-utils.css` 6・`table.css` 1）。

---

## 7. 公式テーマ

`npm pack` で 7 パッケージを取得して読んだ（スクリプトは実行していない）。

| パッケージ | 版 | ライセンス | category | 中身 |
|---|---|---|---|---|
| `@vivliostyle/theme-base` | 3.0.1 | Apache-2.0・CC0-1.0・MIT | | 部品の集まり。`theme.css`（reset・変数の既定・基本のタグ）と、`/page`・`/section`・`/footnote`・`/figure`・`/table`・`/toc`・`/math`・`/listing`・`/citation`・`/sidenote`・`/theorem`・`/endnote`・`/appendix`・`/equation`・`/prism` の部品 |
| `@vivliostyle/theme-bunko` | 3.1.0 | CC0-1.0 | novel | `theme.css` 199 行。theme-base の部品を全部 import し、変数を設定する |
| `@vivliostyle/theme-epub3j` | 2.1.0 | CC0-1.0 | novel | 電書協 EPUB 3 制作ガイド ver.1.1.3 付属の CSS 5 本＋`theme.css` 134 行。theme-base に依存しない |
| `@vivliostyle/theme-techbook` | 3.1.0 | CC0-1.0 | misc | `theme.css` 164 行。theme-base の上の層 |
| `@vivliostyle/theme-academic`・`theme-gutenberg`・`theme-slide` | 3.1.0 | CC0-1.0 | | |

`package.json` の `vivliostyle` 欄は `theme`（`name`・`style`・`category`・`topics`・`i18n`）と `template`（雛形の原稿の場所）を持つ。`peerDependencies` は `@vivliostyle/cli >=11.3.1`（vs は 11.3.3）。

### 7.1 テーマが前提とする HTML

theme-base・bunko・epub3j・techbook の CSS から数えた。

- **主に role 属性で要素を選ぶ**: `role=doc-toc`（9）・`doc-footnote`（7）・`doc-endnotes`（7）・`doc-appendix`（6）・`doc-bibliography`（5）・`doc-chapter`・`doc-part`・`doc-colophon`（各 2）・`doc-preface`・`doc-introduction`・`doc-index`・`doc-glossary`・`doc-foreword`・`doc-epilogue`・`doc-prologue`（各 1）
- **クラスは少ない**: `footnote`（16）・`vrtl`（11）・`footnote-ref`（7）・`appendix`（6）・`equation`（6）と、図表の番号の `fig`・`tbl`・`lst`・`*-caption`、縦中横の `tcy`、傍点の `sesame`・`sesame_dot` など
- **`data-ref`** で相互参照の種類（`sec`・`tbl`・`thm`・`sidenote`）を示す
- vs の生成物は、§2.3 のとおり章・前書き・付録・奥付・索引に role 属性を持たない

### 7.2 変数と `@layer`

- 設定はすべて CSS 変数。theme-base・bunko・epub3j・techbook が定義する変数は延べ 477・異なり 325。名前は `--vs-*`（全体）・`--vs--*`（要素）・`--vs-page--*`（ページ）・`--vs-theme-bunko--*`（テーマ固有）の形
- theme-base の `css/basic.css` だけで `var(` が 893 か所ある。KFX は `var()` を解さないので、Kindle ではそのままでは使えない
- 7 パッケージのどれも `@layer` を使っていない
- bunko の判型は、1 ページの行数（15）と 1 行の字数（39）から `calc()` で求める。縦中横は `.tcy`、縦書きは変数 `--vs-writing-mode: vertical-rl` で指定する

### 7.3 vs の変数との関係

- vs の CSS が定義する変数は 72、Ruby が書き出す変数は 43、合わせて 99。接頭辞は `--color`（16）・`--accent`（12）・`--font`（7）・`--frontispiece`（7）・`--page`（6）・`--folio`（5）・`--talk`（4）などで、そろっていない
- vs の変数で `--vs-` で始まるものは無く、公式テーマと同じ名前の変数は 0。衝突が起きうるのは、vs の公開変数に `--vs-` を付ける場合
- vs のクラスは `vs-*`（`vs-epub`・`vs-h-marker` など）を使う。公式テーマに `.vs-*` のクラスは無い

---

## 8. 数え方

- 生成物: `html_contract.rb`（body のクラス・要素とクラス・role・`data-*`・section の入れ子）と `html_classes.rb`（Prism を除くクラスの一覧）。どちらも `.cache/vs/build/html/*.html` を Nokogiri の HTML5 で読む
- CSS: `css_classes.rb`。コメント・`url()`・文字列を除き、宣言の中身を消してからセレクタのクラスを拾う。最初の版は `body.chapter` のような要素名に続くクラスを取りこぼしていたので直した
- 公式テーマ: `theme_selectors.rb`
- スクリプトはリポジトリに入れていない。数え直すときは同じ方法で書き直す
