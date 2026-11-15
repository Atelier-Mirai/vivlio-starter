# スタイルシートの再編（層の順序・ファイルの分け方・EPUB と Kindle 用の平らな CSS の生成）

> 作成日: 2026-11-14
> ステータス: **実装済み**（S2-1〜S2-3 は 2026-11-14、S2-4・S3-1・S3-2・S3-3a・S3-3b・S3-4 は 2026-11-15 に完了・実装記録は §10）
> 対象: `stylesheets/` の 27 ファイル・約 6,200 行を、見た目を変えずに cascade layers（`@layer`）で作り直す。合わせて、EPUB と Kindle に渡す「層を外した CSS」をビルドのときに生成する
> 出自: `PLANNED.md` の「Version 2.0 構想」にあった「スタイルシートの構造を整理し直す」の五案（層で優先順位を宣言する・Kindle 用の CSS を別に生成する・値を一か所に集める・ページの種類の差を body のクラスと値で出す・`chapter-common.css` を部品ごとに分ける）の具体化。本書を書いた時点で、同項目は `PLANNED.md` から外した。事実は `v2-inventory-report.md` §2.4・§3・§6 と `v2-feasibility-notes.md` §1・§2・§6
> 組になる仕様書: `v2-architecture-spec.md`（出力先の `css_form`・Kindle 向けの劣化の集約）・`theme-contract-spec.md`（テーマの層・公開する変数）・`v2-migration-plan.md`（段階 S2・S3）

---

## 0. 決定の一覧

| 問い | 決定 | 節 |
| :--- | :--- | :--- |
| 層の順序 | `reset` → `base` → `tokens` → `parts` → `pages` → `theme` → `utilities` → `settings` → `target`。`custom.css` は層の外 | §2 |
| 層の付け方 | ページの種類ごとの入口の CSS をビルドのときに生成し、`@import url(...) layer(...)` で層に入れる。HTML が読む CSS は入口の 1 枚だけにする | §2.3 |
| `!important` | 層の中では使わない。今の 18 か所は、層の位置で解く | §2.4 |
| ファイルの分け方 | `base/`・`parts/`・`pages/`・`targets/` に分ける。`chapter-common.css` は部品ごとに分ける。色と飾りはテーマへ移す | §3 |
| 平らな CSS を何で生成するか | Ruby で書く。CSS の読み取りには gem の `crass`（MIT・純 Ruby・依存なし）を使う。Node の道具は使わない | §4.1 |
| 平らな CSS の形 | 三つ: `layered`（PDF）・`flat`（クリーン EPUB）・`flat_literal`（Kindle） | §4.2 |
| 層を外しても結果が変わらないことの保証 | 平らにした CSS で PDF を組み、層ありの PDF と全ページの画素を比べる。加えて、結果が変わりうる規則の組を静的に検査する | §4.3 |
| Kindle 用の規則 | `stylesheets/targets/` に集める（本文のページは `epub.css`・`kindle.css`、そのページの種類だけの規則は種類ごとの 1 枚）。色と寸法のリテラル化は生成が行う | §5 |
| Kindle に届く値の範囲 | 本文の字の大きさ・行送り・書体は端末任せ（`targets/kindle-tokens.css`）。紙の寸法（`clamp()`・`min()`・`max()` の宣言）は届けず、生成が理由を付けて落とす（S6 の最初から）。テーマも出力先の CSS を持てる（`v2-post-s3-consultation.md` §5.2〜§5.4） | §4.4・§4.5・§5 |
| 平らな CSS で層の順が保てない組 | 層の順を詳細度に置き換える仕組みは入れない。テーマは変数か部品と同じ選択子で書く。`custom.css` は生成が勝たせる。検査は組み上がった HTML の要素ごとに勝つ宣言を比べる | §2.1・§4.3・§7.1 |
| 縦書きに向けた物理方向の書き直し | 層に分ける段階では行わない。縦書きの小説の段階（S8）で、縦書きの本が読む部品だけを直す | §6 |
| 1.x の `custom.css` | 書き換えなくても効く。層の外なので、今と同じく最優先になる | §7 |
| 1.x の小さな版で出すか | 出さない。すべて `v2` ブランチで行う | §8 |

---

## 1. 今の構造と、直したい点

`v2-inventory-report.md` §2.4・§6 による。

- 各ページの HTML は `theme.css` → `{種類}.css` → `book-settings.css`（生成物）→ `custom.css` の順に `link` で読む。`{種類}.css` が部品を `@import` する。
- 優先順位は、読み込みの順と詳細度だけで決まっている。部品の規則をページの種類の規則で上書きするために、詳細度を上げるか `!important`（18 か所）を使っている。
- `preface.css`・`postface.css` は `chapter-common.css` を読まず、段落・引用・字間の規則を別に持つ。
- `body.vs-kindle` の規則が 10 ファイル・124 か所、`body.vs-epub` の規則が 4 ファイル・28 か所に散っている。PDF はこれらを読むが使わない。
- Kindle 向けの色のリテラル化は、静的な CSS の直書き・`BookSettingsCss` の書き出し・組み上がった EPUB の CSS の書き換えに分かれている。
- `chapter-common.css` が 1,066 行ある。

確定している事実（`v2-feasibility-notes.md`）:

- Vivliostyle（core 2.45.1）は `@layer` を仕様どおりに扱う。層の順・層の外・`!important` の逆転・`@import url() layer()`・層の中の `@page` と余白の箱・層の中の名前付きの文字列の 6 項目を確かめた。
- KFX は `@layer` のブロックを中身ごと捨てる。
- Apple Books は `@layer` を仕様どおりに扱う。Kobo と Google Play Books は確かめられていない。
- 層の中の `@font-face` は確かめていない（§2.2 で、層の外に置くことで確かめを不要にする）。

---

## 2. 層

### 2.1 層の順序

```css
@layer reset, base, tokens, parts, pages, theme, utilities, settings, target;
```

後の層が前の層に勝つ。層の外の規則は、どの層にも勝つ。

| 層 | 中身 | 置き場 | 誰が書くか |
| :--- | :--- | :--- | :--- |
| `reset` | 全要素の初期化 | `stylesheets/base/reset.css` | vs |
| `base` | 要素の基本（画像・見出しの折り返しなど）、エンジンの癖の回避、判型と余白と余白の箱の骨格（`@page`） | `stylesheets/base/` | vs |
| `tokens` | 公開する変数の既定値（`theme-contract-spec.md` §5）、今の名前の別名（§7.2） | `stylesheets/tokens.css`・`tokens-legacy.css` | vs |
| `parts` | vs が作る構造に結びつく部品（脚注・行番号・並べ方・索引の語の印・相互参照・囲みの骨格など） | `stylesheets/parts/` | vs |
| `pages` | 本文以外のページ（目次・索引・用語集・奥付・扉・権利ページ・部扉・全巻目次）の構造 | `stylesheets/pages/` | vs |
| `theme` | テーマ（色・書体・飾り・章扉・見出しの見た目・柱とノンブルの見た目） | `themes/<名前>/` | テーマ |
| `utilities` | 著者が原稿で明示した指定（位置・余白・改ページ・回転・置換の規則のクラス） | `stylesheets/utilities/` | vs |
| `settings` | `book.yml` から生成する規則（判型・テーマのオプション・書体・見出しの番号・改ページの方針） | `.cache/vs/book-settings.css`（生成物） | vs（生成） |
| `target` | 出力先ごとの規則（`body.vs-epub`・`body.vs-kindle`）。出力先の束にだけ入れる | `stylesheets/targets/`・テーマの出力先の CSS（`epub.css`・`kindle.css` など。`theme-contract-spec.md` §3.1） | vs・テーマ |
| （層の外） | `custom.css`、章の frontmatter で著者が足した CSS | `stylesheets/custom.css` | 著者 |

順序の理由:

- `theme` が `parts` と `pages` の上にあるのは、テーマが部品とページの見た目を変えられるようにするためである。層が上なら、詳細度が低い規則でも勝つ。テーマは詳細度を上げたり `!important` を使ったりせずに済む。ただし、これは層ありの CSS を読む PDF の話である。EPUB と Kindle は層を外した平らな CSS を読むので（§4）、詳細度が同じなら層の順で勝ち、低ければ負ける。部品の見た目を変えるテーマの規則は、**変数で変えるか、部品の規則と同じ選択子で書く**（平らな CSS で層の順を詳細度に置き換える仕組みは入れない。`v2-flat-cascade-consultation.md` §5.3）。
- `utilities` が `theme` の上にあるのは、著者が原稿に書いた `{.text-right}` や `@pagebreak` が、テーマの `p { text-align: justify; }` のような規則に負けないようにするためである。EPUB と Kindle では詳細度で決まるのは theme と同じで、同梱の CSS では、組み上がった HTML で入れ替わる組が無いことを要素ごとの判定で確かめる（§4.3）。
- `settings` が `theme` と `utilities` の上にあるのは、`book.yml` の設定（判型・テーマ色・見出しの番号）が、テーマの既定値より優先されるためである。
- `target` が `settings` の上にあるのは、Kindle で使えない組み方を置き換える規則が、テーマや設定に負けると表示が崩れるためである。
- `custom.css` を層の外に置くのは、1.x の「最後に読み込まれるので最優先」という約束を、著者が層を知らなくても保てるようにするためである（§7.1）。

テーマは `theme` 層の中に、自分の下位の層（`theme.base`・`theme.main` など）を作ってよい。`extends:` のあるテーマでは、土台のテーマを `theme.base`、自分を `theme.main` に入れる。

### 2.2 層の外に置くもの

- **`@font-face`**: `stylesheets/fonts.css` にまとめ、入口から層を付けずに読む。`@font-face` は要素に当たる規則ではなく、層に入れる利益が無い。層の中での挙動を確かめていない（§1）ので、外に置いて確かめを不要にする。
- **`custom.css`** と、章の frontmatter の `link` で著者が足した CSS。

### 2.3 入口の CSS

層は `@import url(...) layer(...)` で付ける（`<link>` では層を指定できない）。そのため、HTML が読む CSS を「入口の 1 枚」にし、入口の中で全部を `@import` する。

入口は、ページの種類ごとに、ビルドのときに生成する。置き場は `book-settings.css` と同じ `.cache/vs/` とする（`stylesheets/` への相対パスが同じになる）。

```css
/* .cache/vs/entry-chapter.css（生成物） */
@charset "utf-8";
@layer reset, base, tokens, parts, pages, theme, utilities, settings, target;
@import url("../../stylesheets/fonts.css");
@import url("../../stylesheets/base/reset.css") layer(reset);
@import url("../../stylesheets/base/elements.css") layer(base);
@import url("../../stylesheets/base/page.css") layer(base);
@import url("../../stylesheets/tokens.css") layer(tokens);
@import url("../../stylesheets/parts/heading.css") layer(parts);
/* … parts … */
@import url("../../themes/standard/theme.css") layer(theme);
@import url("../../stylesheets/utilities/align.css") layer(utilities);
/* … utilities … */
@import url("book-settings.css") layer(settings);
@import url("../../stylesheets/custom.css");
```

- 生成するのは `lib/vivlio_starter/cli/css/entry_writer.rb`。どのページの種類がどのファイルを読むかは、1 枚の表（`EntryWriter::IMPORTS`）に置く。テーマの CSS は `theme.yml` の `styles:` から足す。
- 生成の時点は、今 `book-settings.css` を生成している段と同じ（フル・単章・preflight のどのモードでも走る）。
- `pre_process/frontmatter_generator.rb` の `build_base_frontmatter` は、`link` を入口の 1 枚にする。章の frontmatter に著者が書いた `link` は、今と同じく残す。
- PDF の出力先は、この入口をそのまま読む（`css_form: :layered`）。EPUB と Kindle は、入口から平らな CSS を作って読む（§4）。
- 本文のページ（章・付録・前書き・後書き）は同じ部品の組を読む。本文以外のページは、`reset`・`base`・`tokens`・自分の `pages` のファイル・`theme`・`settings`・`custom.css` を読む。ページの種類ごとに入口を分けるのは、`@page` の規則がページの種類で違うためである（今と同じ分け方を保ち、名前付きページへの統合はしない。結果が変わる危険に見合う利益が無い）。

### 2.4 `!important` を層の中で使わない

層の中の `!important` は、層の順が逆になる（前の層の `!important` が後の層の `!important` に勝つ）。層の順で優先を決める設計と逆向きに働くので、vs の CSS とテーマの CSS では使わない。

今の 18 か所の直し方:

| 場所 | 今の目的 | 直し方 |
| :--- | :--- | :--- |
| `chapter-common.css` 468–469（改ページを打ち消す指定） | 詳細度の高い規則に勝つ | `utilities` 層へ移す |
| `preface.css` 238–251（`text-align` と `text-indent` の 6 か所） | 段落の規則に勝つ | `utilities` 層へ移す（本文のページで共通の指定にする） |
| `components.css` 139・178・211・234（`display` の 4 か所） | 出力先での表示の切り替え | 出力先の規則なら `target` 層へ。部品の中の切り替えなら、選ぶ対象を絞って `parts` 層で解く |
| `components.css` 402 と `image-header.css` 269–270 | 互いに `!important` で打ち消している | 章扉の規則はテーマ、部品の規則は `parts` になる。どちらが勝つべきかを決め、勝つ側を上の層に置く |
| `toc.css` 177（`content: none`） | 目次の中で印を消す | `pages` 層は `parts` 層の上なので、`!important` なしで勝つ |

- 検査: `css_layer_test.rb` が、`stylesheets/`（`custom.css` を除く）と同梱のテーマに `!important` が無いことを確かめる。
- 著者の `custom.css` の `!important` は、層の外なので今と同じに働く。

---

## 3. ファイルの分け方

### 3.1 新しい配置

```
stylesheets/
  custom.css                 著者（層の外）
  fonts.css                  @font-face（層の外）               ← page-settings.css の書体の定義
  tokens.css                 公開する変数の既定値               ← theme.css の変数のうちテーマに依らないもの
  tokens-legacy.css          今の名前の別名（§7.2）
  base/
    reset.css                                                   ← base.css
    elements.css             画像・見出しの基本、エンジンの癖の回避 ← base.css
    page.css                 @page（余白・余白の箱の骨格）      ← page-settings.css
  parts/
    heading.css              見出しの構造（番号・印の置き場）   ← chapter-common.css
    prose.css                段落・引用・強調                   ← chapter-common.css・preface.css
    list.css                 リスト・定義リスト                 ← chapter-common.css
    figure.css               図・キャプション・絵文字の画像     ← chapter-common.css
    box.css                  囲み（コラム・注意書き・出力例）   ← components.css
    talk.css                 会話                               ← components.css・chapter-common.css
    code.css  prism.css                                         ← code.css・prism.css
    table.css                                                   ← table.css
    footnote.css             脚注                               ← chapter-common.css
    reference.css            相互参照・用語集と索引へのリンク   ← chapter.css・chapter-common.css
    layout.css               並べ方（side-by-side・写真の列など）← layout-utils.css
  pages/
    toc.css index.css glossary.css colophon.css titlepage.css legalpage.css part-title.css whole-toc.css
  utilities/
    align.css                位置（align-*・text-*）            ← layout-utils.css・preface.css
    spacing.css                                                 ← spacing.css
    pagebreak.css                                               ← pagebreak.css・chapter-common.css
    replace-list.css                                            ← replace-list.css
  targets/
    epub.css                 本文のページの body.vs-epub の規則（S3-2 で 21 規則＋2）
    kindle.css               本文のページの body.vs-kindle の規則（38 規則）
    kindle-preface.css       前書き・後書きだけの body.vs-kindle の規則（1）
    kindle-index.css  kindle-glossary.css  kindle-colophon.css   そのページだけの規則（6・6・10）
themes/standard/             theme-contract-spec.md §4
```

- `chapter.css`・`appendix.css`・`preface.css`・`postface.css` は無くなる。入口は生成物になり、中身（本文のページに固有の規則）は部品かテーマへ移る。
- `stylesheets/_README.md` を、新しい配置と層の説明に書き直す。
- 1 ファイルは 400 行を超えないことを目安にする。`layout-utils.css`（694 行）は `parts/layout.css` と `utilities/align.css` に分けても超えるなら、並べ方ごとにさらに分ける。
- エンジンの癖の実測の記録は、CSS のコメントから `vivliostyle-css-pitfalls-notes.md` へ移す。CSS のコメントには、その規則がなぜ要るかを 1〜2 行で書き、詳しい経緯は同メモの節の番号で指す。

### 3.2 部品とテーマの線引き

`parts`・`pages` に置く規則と、テーマに置く規則は、次の問いで分ける。

> その規則を消したとき、部品が働かなくなるか、読めなくなるか。

| 答え | 置き場 | 例 |
| :--- | :--- | :--- |
| 働かなくなる・読めなくなる | `parts`・`pages` | `display`・`grid` の列の定義・`float: footnote`・カウンタ・`string-set`・`break-*`・疑似要素で出す番号や印・回転・画像の最大の寸法 |
| 読めるが、飾りが無くなる | テーマ | 色・背景・罫・角の丸み・書体・太さ・字の大きさ・余白の大きさ・章扉・見出しの飾り・柱とノンブルの書体と位置 |

- 部品の規則が色や書体を必要とするときは、公開する変数（`--book-*`）を読む。値はテーマが入れる。
- 迷う規則は部品の側に置く。テーマは上の層なので、後から上書きできる。逆（テーマに置いた構造の規則を、別のテーマが持っていない）は、部品が働かなくなる。
- この線引きを当てるのは、テーマを切り出す段階（S6）である。層に分ける段階（S2）では、今のファイルを部品ごとに分けるところまでを行い、色と飾りの規則も `parts` に置いたままにする。段階を分けるのは、画素の比較で差が出たときに、原因が「層の位置」か「規則の移動」かを切り分けられるようにするためである。

### 3.3 前書き・後書きを本文の部品にそろえる

今は `preface.css` が `chapter-common.css` を読まず、段落・引用・字間の規則を別に持つ（五案のうち「ページの種類の差を body のクラスと値で出す」）。

- 本文のページ（章・付録・前書き・後書き）は、同じ `parts` と `utilities` を読む。
- 前書きと後書きに固有の見た目（色・見出しの形・罫）は、テーマの `body.preface`・`body.postface` の規則にする。
- 字間・段落・引用の規則は 1 か所になる。
- 今の前書きは `chapter-common.css` の規則を受けていないので、そろえると前書きに新しい規則が当たる。当たって見た目が変わる規則は、選ぶ対象を `body.chapter`・`body.appendix` に絞るか、テーマの `body.preface` で今の見た目に戻す。前書きと後書きのページの画素が変わらないことを、この作業の完了の条件にする（§8 の S2-4）。

---

## 4. 平らな CSS の生成

### 4.1 何で生成するか

Ruby で書く。置き場は `lib/vivlio_starter/cli/css/`。

| ファイル | 責務 |
| :--- | :--- |
| `entry_writer.rb` | 入口の CSS を生成する（§2.3） |
| `stylesheet.rb` | CSS を読み、規則の列にする（`crass` を包む） |
| `flattener.rb` | `@import` を解き、層の順に並べ、1 枚の CSS にする（§4.2 の 1〜3） |
| `target_filter.rb` | 出力先が扱えない規則を落とす（§4.2 の 4） |
| `literal_resolver.rb` | `var()`・`color-mix()`・`calc()`・`:is()` を解く（§4.4） |
| `inversion_check.rb` | 層を外すと結果が変わりうる規則の組を報告する（§4.3） |
| `bundle.rb` | 出力先とページの種類を受けて、上を順に呼び、出力先のワークスペースへ書き出す |

`crass` を選ぶ理由と、Node の道具を使わない理由:

- `crass` は CSS Syntax Level 3 の読み取りだけを行う gem で、MIT・純 Ruby・依存なしである。2026-11-14 に、`@layer` の宣言・`@layer` のブロック・`@import url() layer()` が、それぞれ規則として読めることを確かめた（ブロックの中は `Crass::Parser.parse_rules` でもう一度読む）。`vivlio-starter.gemspec` に依存を足す。
- lightningcss は層を外す変換を持たない。PostCSS の `@csstools/postcss-cascade-layers` は、層の順を `:not(#\#)` を重ねた詳細度に置き換える方式で、KFX がこの選択子を解するかが分からない（KFX は `:is()` を含む規則を捨てる）。変数を解く PostCSS のプラグインも、`:root` の定義しか見ない。
- 必要な変換（層の順に並べる・`body.<種類>` の変数を解く・出力先で規則を落とす）は vs に固有で、道具を組み合わせても自前の処理が残る。Ruby なら、色の計算（`ThemeColor`）と相対パスの引き直し（`BookSettingsCss.rebase_relative`）を再利用でき、著者の本の `package.json` に依存を足さずに済む。
- CSS の入れ子（`&`）は、`crass` では読めない。`stylesheets/` は今入れ子を使っていない（2026-11-14 に確認）。vs の CSS とテーマの CSS では入れ子を使わない決まりにする（`theme-contract-spec.md` §3.5）。入れ子を見つけたら、その規則を落として 🟡 で知らせる。

### 4.2 三つの形と処理の順

| 形 | 出力先 | 処理 |
| :--- | :--- | :--- |
| `layered` | `pdf`・`print_pdf` | 入口をそのまま読む。生成しない |
| `flat` | `epub` | 1 → 2 → 3 → 4 |
| `flat_literal` | `kindle` | 1 → 2 → 3 → 4 → 5 |

1. **読み込み**: 入口を読み、`@import` を再帰的に解く。各規則に「層の名前」と「出現の順」を付ける。`layer()` の無い `@import` と、層の外の規則は「層の外」とする。`url()` の相対パスは、出力するファイルの位置から引き直す。
2. **並べ替え**: 層の宣言の順に層を並べ、最後に層の外を置く。同じ層の中は出現の順を保つ。入れ子の層（`theme.base`・`theme.main`）は宣言の順。`@layer` の囲みと宣言は出力しない。
3. **検査**: 層の中の `!important` と入れ子を報告する。§4.3 の検査を行う。
4. **出力先のフィルタ**:
   - `epub`・`kindle`: `@page` の中の余白の箱（`@top-left` など）を落とす（今の `sanitize_epub_css!` と同じ）。`target` 層には `targets/epub.css` を入れる。
   - `kindle`: さらに、WebP を指す `url()` を含む宣言を落とす。`target` 層に `targets/kindle.css` とテーマの出力先の CSS を入れる（順は §5）。
   - `pdf` 用の束には `target` 層を入れない。
5. **リテラル化**（§4.4）。

出力は、出力先のワークスペース（`epub/`・`kindle/`）の中に、ページの種類ごとに 1 枚（`styles/chapter.css` など）とする。出力先の変換（L4）の最初の段が、HTML の `link` をこの 1 枚に付け替える。今の `bundle_book_settings_for_epub!` は、この仕組みに置き換わって無くなる。

### 4.3 層を外しても結果が変わらないことの保証

層を外して層の順に並べると、同じ詳細度の規則どうしでは、層ありと同じ結果になる（後に書いた規則が勝つ）。結果が変わるのは、**下の層の規則のほうが詳細度が高く、同じ要素の同じプロパティを、上の層の規則と取り合う**場合だけである。層ありでは上の層が勝ち、平らにすると詳細度の高い下の層が勝つ。

二つの方法で確かめる。

**(1) 画素の比較（正の確かめ）**

開発用の環境変数 `VS_CSS_FORM=flat` を用意し、PDF の出力先に平らな CSS を読ませる（余白の箱を落とすフィルタは掛けない）。同じ本を `layered` と `flat` で組み、全ページの画素を比べる。一致すれば、PDF で使われる規則については、層を外しても結果が変わらないと言える。`VS_CSS_FORM` は確かめのためだけのもので、文書には載せない（`VIVLIO_BUILD_PARALLEL` と同じ扱い）。

**(2) 検査（`Css::InversionCheck`）**

PDF で使われない規則（`target` 層）と、本書で使っていない記法の規則は、(1) では確かめられない。そこで二つの判定を持つ（`v2-flat-cascade-consultation.md` §5.4。S3-2 で入れた）。

- **静的な判定（HTML なし）**: 結果が変わりうる規則の組を挙げる。二つの宣言が、(a) 同じプロパティで、(b) 下の層の規則の詳細度が上の層の規則より高く、(c) 選ぶ対象が重なりうる。(c) は、選択子の最後の複合選択子（対象の要素を表す部分）が、同じクラスを含むか、どちらもクラスを持たず同じ要素名である、で判定する。これは保証ではなく、vs の CSS を書き換えたときの早めの警報である。`css_layer_test.rb` が、許可の表（理由つき）の外に組が無いことを確かめる。(c) を広げると許可の表が読めない大きさ（842 組）になるので、広げない。
- **要素ごとの判定（HTML あり）**: 組み上がった HTML の要素ごとに、当たる宣言の全部から、層ありで勝つ宣言と平らな CSS で勝つ宣言を求め、二つが違い、値の意味も違うものを挙げる。組で比べると、同じ要素に当たる第三の宣言（どちらの形でも勝つもの）を見ないので、誤って挙げる（`v2-flat-cascade-consultation.md` §5.2 の部扉の `break-before`）。候補は (c) のクラスの条件を外した広い組で絞る。媒体（screen・print）ごとに比べ、疑似要素は同じ疑似要素の宣言どうしで比べる。疑似要素・動的な疑似クラスは外して Nokogiri で当て、読めない選択子は当たらないものとして扱って一覧に出す。ビルドでは `--log=debug` のときだけ動き、段階の確かめでは B1・B4 の EPUB と Kindle 用 EPUB で 0 組（または理由つきの記録）であることを確かめる。
- 扱い（S6 以降）: 著者が入れたテーマでは、`vs build` が要素ごとの判定で、層ありで勝つ側が theme 層の組を 🟡 で示す。`vs theme:check` は静的な判定で「起きうる組」を示し、確定は `vs build` が行うと書く。層の外（`custom.css`）の組は知らせず、生成で解く（§7.1）。
- 直し方: 下の層の規則の詳細度を下げる、上の層の規則の選択子を下の層と同じ形にする、のどちらか。

### 4.4 リテラル化（`flat_literal`）

KFX は `var()`・`calc()`・`color-mix()` を解さず、`:is()` を含む規則を捨てる（`kindle-css-compatibility-notes.md` §2）。Kindle 用の CSS では、これらを生成のときに解く。

**解く層**

- どの層の規則も解く（S3-4・2026-11-15）。部品・ページの層の色・枠・書体の指定は、PDF と同じ変数で Kindle に届く。変数の定義も、値を解いて残す（HTML の中の `<style>` が `var()` で読むため）。
- PDF 向けの本文の字の大きさと行送り（`--base-font-size`・`--base-line-height`）は、Kindle のどの種類の束も target 層の最初に読む `targets/kindle-tokens.css` が、`body.vs-kindle` で `1em`・`normal` に置き換える（`EntryWriter::TARGET_FOUNDATION`）。`body` の定義は変数の表で `:root` の定義に勝つので、`custom.css` の `:root` で PDF 用に変えた値も Kindle の本文には届かない。Kindle の字の大きさを変えるなら、`custom.css` に `body.vs-kindle` で同じ変数を書く。
- **S6 で、`kindle-tokens.css` は `--book-*` の名前で書く**（`v2-post-s3-consultation.md` §5.2 の 3）。部品が読む名前が `--book-*` になるので、同じ名前で置き換えるのが変数の表の解き方（`body` に近い定義が勝つ）に合う。今の名前（`--base-font-size` など）を `body.vs-kindle` に書いた `custom.css` は、2.0 がまだ公開されていないので世の中に無い。`vs upgrade` の置き換え（§7.2）は、選択子を問わず `custom.css` の全部の定義に当てる。名前の変更の前後で、Kindle の中間生成物が差 0 であることを確かめる（`theme-contract-spec.md` §9 の S6 の条件 9）。
- テーマが Kindle の値を変える道（`theme.yml` の `kindle_tokens:` と、テーマの `kindle.css` の `body.vs-kindle`）と、書ける値の範囲は `theme-contract-spec.md` §3.5 に書く。`kindle_tokens:` の書き出しは、target 層の `kindle-tokens.css` の直後に置く（§5 の順）。
- 見出し・前書き・奥付などの紙の寸法は、`clamp(…mm, calc(var(--paper-scale) * …mm), …mm)` の形で書いてある。紙の寸法は判型に対する比で決めた値で、判型の無い端末では基準が無いので、Kindle には届けない（`v2-post-s3-consultation.md` §5.3）。Kindle の寸法は、`targets/kindle*.css` の em の規則が決める。
- 今は、`calc()` の外の `clamp()` を解かずに残し、KFX と Kindle Previewer の前処理が宣言ごと捨てるのに任せている。下流の二つが同じに捨てることに頼る形なので、**S6 の最初（寸法をテーマへ移す前）に、`LiteralResolver` が `clamp()`・`min()`・`max()` を含む宣言を、理由（`:paper_dimension`）を付けて落とす**（下の「関数と選択子」）。確かめは、Kindle の中間生成物が前後で差 0（今も届いていないので、変わらないはずである）。
- 経緯: S3-3a では、解く層を target 層・settings 層・層の外に限った（2026-11-15 ユーザー決定）。Kindle Previewer の前処理も `var()` を含む宣言を捨てており、全部を解くと本文が端末の既定の 16px から PDF 用の 10.5pt に変わり、中間生成物で 26,335 要素のうち 26,310 の値が変わったためである。S3-4 で、本文の字の大きさと行送りを `kindle-tokens.css` で置き換えてから全部の層を解いた（§10.10）。

**変数**

- ページの種類ごとに、変数の表を作る。集めるのは、選択子が `:root`・`html`・`body`・`body.<クラス>` の規則の、変数の定義である。`body.<クラス>` は、そのページの種類の `body` に付くクラス（ページの種類・`vs-vertical`・`vs-fixed`・テーマのオプションのクラス・`vs-epub`・`vs-kindle`）だけを含むものを採る。`:root:lang(ja)` のような言語の指定は、本の言語（`Common.book_language`）で判定する。
- 優先は、`body` に近い定義が勝つ（`body.<クラス>` > `body` > `html`・`:root`）。同じ近さなら、平らにした後で後に来る定義が勝つ。
- `var(--x)` を表の値で置き換える。値の中の `var()` は、繰り返して解く（深さの上限を設け、循環は解かない）。`var(--x, 代わりの値)` は、表に無ければ代わりの値を使う。
- それより深い要素（`.talk` など）で定義された変数は解けない。その変数を読む宣言は落とす。今の KFX も `var()` を含む宣言を無視するので、Kindle での結果は今と同じになる。落とした宣言は `--log=debug` で一覧にし、`vs theme:check` では 🟡 で示す。
- `chapter-first` のように、ページごとに付くクラスの下で定義された変数は、解けないものとして扱う。

**関数と選択子**

| 書き方 | 処理 |
| :--- | :--- |
| `color-mix(in srgb, A p%, B)` | 計算して 16 進の色にする（`ThemeColor` を一般化する。今は白との混色だけ）。`transparent` との混色は `rgb(r g b / a)` ではなく、KFX が解する形で書く（解せる形が無ければ落とす）。`srgb` 以外の色空間は落とす |
| `calc()` | 単位のそろった加減と、数との乗除は計算する。単位が混ざるもの（`100% - 2mm`）は落とす |
| `:is(a, b) c`・`:where(a, b) c` | 選択子の並びに展開する（`a c, b c`）。`:where()` の詳細度が 0 であることは保てないので、§4.3 の検査の対象にする |
| `:has()` | 解けない。規則を落とす |
| `clamp()`・`min()`・`max()` | 解かない。含む宣言を、理由 `:paper_dimension`（紙の寸法）を付けて落とす（S6 の最初に入れる。それまでは宣言が残り、下流が捨てる）。mm や pt をそのまま書いた宣言は落とさない（単位では判定しない） |

落とした宣言と規則は、理由を付けて記録し、§4.5 のとおりに報告する。紙の寸法で落とした宣言は、意図した書き方なので、ほかの理由と分けて扱う。

**今の仕組みとの入れ替え**

`BookSettingsCss` の `kindle_accent_rules`・`kindle_custom_color_rules`・`h4_marker_kindle_rule`（`body.vs-kindle` の規則を、テーマ色をリテラルにして書き出す 8 メソッド）は、リテラル化が同じ結果を出すことを確かめてから消す（§8 の S3-3）。`custom.css` の色を Kindle に渡す仕組みも、`custom.css` が平らな CSS に入って変数が解かれるので、別の処理が要らなくなる。

### 4.5 報告のしかた

| 相手 | 出し方 |
| :--- | :--- |
| vs の開発（同梱の CSS とテーマ） | テストで落とす（`css_layer_test.rb`）。Kindle 用に落ちる宣言は、紙の寸法のほかを、理由つきの許可の表で持つ（今は会話の `--talk-accent` など 3 種類）。表に無い宣言が落ちたら失敗とする。ビルドでは `--log=debug` だけ |
| テーマを作る人 | `vs theme:check <名前>` が、検査するテーマ自身のファイルの宣言だけを見る（`extends:` の先と vs の部品は含めない）。紙の寸法で落ちた宣言は、場所を挙げずに件数を 1 行で示す（💡。意図した書き方で、直す対象ではない）。それ以外で落ちた宣言（深い要素の変数・`:has()`・単位の混ざる `calc()`・srgb 以外の混色）は、ファイル名と行番号つきの 🟡 で、何が Kindle に届かないか、どう書き直すかを示す |
| 著者（テーマの CSS） | `vs build` は、テーマの CSS で落ちた宣言を知らせない（`--log=debug` だけ）。著者には直せないためである |
| 著者（`custom.css`） | `vs build` で `targets` に `kindle` があるときだけ、Kindle に届かない宣言を 🟡 で示す（今の `warn_unconvertible_custom_colors` と同じ場面）。平らな CSS で vs の規則に負ける宣言は知らせず、生成が解く（§7.1）。解けなかった宣言だけを、場所を示して 🟡 で知らせ、vs の選択子は見せない |

---

## 5. Kindle と EPUB の規則を集める

- `body.vs-kindle` の規則を `stylesheets/targets/kindle.css` へ、`body.vs-epub` の規則（`body.vs-epub` と `body.vs-kindle` を並べた規則を含む）を `stylesheets/targets/epub.css` へ移す。
- **ページの種類ごとに分ける（S3-2 で決めた）。** 移す前の規則は、そのページの種類が読むファイルにあった。奥付の `body.vs-kindle { … }` や前書きの `body.vs-kindle h1` を 1 枚に集めると、本文のページにも当たる。そこで、本文のページ（章・付録・前書き・後書き）が読む部品の規則は `epub.css`・`kindle.css` に、前書きの部品（`parts/preface.css`）とページのファイル（`pages/index.css`・`glossary.css`・`colophon.css`）の規則は `kindle-preface.css`・`kindle-index.css`・`kindle-glossary.css`・`kindle-colophon.css` に置く。どの種類がどれを読むかは `Css::EntryWriter::TARGET_IMPORTS` の 1 枚の表に置く。
- 移すときは、選択子（`body.vs-kindle` の前置きを含む）と宣言を変えず、元のファイルの読み込みの順と、ファイルの中の順を保つ。
- **`book-settings.css` の Kindle の規則も target 層へ移す（S3-2 で決めた）。** `BookSettingsCss` の Kindle 用のリテラルの色（`kindle_accent_rules`・`kindle_custom_color_rules`・話者の色）と、`page.section_pagebreak: false` の Kindle の節見出しの打ち消しは、`stylesheets/` の Kindle の規則を同じ選択子で後から覆う作りである。Kindle の規則だけを target 層（settings 層の上）へ移すと、覆う側が負ける（本書の Kindle の囲みの枠がテーマ色から灰色になった）。覆う側を `.cache/vs/book-settings-kindle.css` に分けて生成し、Kindle の束の target 層の最後で読む。S3-3 でリテラル化が入ると、この生成物は無くなる。
- **PDF だけに当てる規則（`body:not(.vs-epub)`）は、選ぶ対象を外して部品に残す。** target 層は PDF の束に入らないので、`:not(.vs-epub)` の規則は移せない。`parts/simple-header.css` の節リードの余白と `parts/table.css` の長い表の見出しの折り返しの 2 規則が該当する。`:not(.vs-epub)` を外し、EPUB と Kindle の値は `targets/epub.css` が target 層で決める（節リードは既にある規則が勝つ。見出しの折り返しは `white-space: normal` の規則を足した）。あわせて、`parts/footnote.css` の印刷の媒体で控えの脚注を描かない規則と同じものを `targets/epub.css` に足した（EPUB の脚注の `display: block` が target 層で勝つようになるため）。
- `targets/kindle.css` の中は、元の部品の名前の見出し（`/* --- parts/box.css --- */`）で区切る。
- 移した後、リテラルの色を直書きしている規則のうち、テーマ色から決まるもの（前書きの藍色の直書きなど）は、`var(--book-…)` に書き直す。リテラル化が解くので、テーマ色に追従するようになる（今は `BookSettingsCss` が後から上書きして追従させている）。この書き直しは S3-3 で行う。
- `targets/epub.css` は、クリーン EPUB と Kindle の両方の束に入る（Kindle の `body` にも `vs-epub` が付くため。今と同じ）。
- **target 層の中の順（S6 から。`v2-post-s3-consultation.md` §5.4 の 3）。** テーマも出力先の CSS を持てる（`theme-contract-spec.md` §3.1）。target 層には、次の順で入れる。
  1. `targets/kindle-tokens.css`（Kindle だけ。`EntryWriter::TARGET_FOUNDATION`）
  2. `theme.yml` の `kindle_tokens:` の書き出し（Kindle だけ。`body.vs-kindle { … }`）
  3. vs の `targets/`（`epub.css` → `kindle.css` → 種類の 1 枚。`EntryWriter::TARGET_IMPORTS`）
  4. `extends:` の先のテーマの出力先の CSS（`epub.css` → `epub-<種類>.css` → `kindle.css` → `kindle-<種類>.css`）
  5. テーマ自身の出力先の CSS（同じ順）
- **`standard` へ移す規則（S6）。** `targets/` の規則のうち、劣化させる相手の部品がテーマへ移るもの（`image-header.css`・`simple-header.css`・扉絵と節絵）だけを `themes/standard/` の出力先の CSS へ移す。vs の部品（囲み・コード・表・索引・用語集・奥付）の規則は `stylesheets/targets/` に残す。選択子と宣言は変えない。移すと vs の規則との前後が変わり（上の 3 から 5 へ）、詳細度が同じ組では勝つ側が入れ替わりうるので、移動の前後で EPUB の計算値と Kindle の中間生成物が差 0 であることを確かめる（`theme-contract-spec.md` §9 の S6 の条件 8）。
- PDF の束には `target` 層を入れない。PDF が読む CSS から、出力先の規則が無くなる。
- 新しい囲みの記法を足すときの手順（`.claude/CLAUDE.md` の「Kindle degradation convention」・`notation-implementation-guide.md` §3 の 3）は、「`targets/kindle.css` に、構造の違いだけを書く。色は変数のままでよい」に変わる。S3 の完了のときに、両方の文書を直す。

---

## 6. 縦書きに向けた物理方向の扱い

`v2-inventory-report.md` §3.1 の物理方向 72 か所と、`@page :left/:right` の 9 か所について。

| 対象 | 決定 | 理由 |
| :--- | :--- | :--- |
| `@page :left`・`:right` の余白（ノドと小口） | 変えない | 見開きの内側がノドであることは、綴じの向きに依らない（`v2-feasibility-notes.md` §3.1） |
| `@page :left`・`:right` の余白の箱（柱とノンブルの左右） | 変えない | 左ページの外側は左、右ページの外側は右で、これも綴じの向きに依らない。変わるのは「奇数ページが左右のどちらか」だけで、CSS の `:left`・`:right` はその結果に対して働く |
| 余白の箱の中の文字の向き | 縦書きのテーマが、余白の箱に `writing-mode: horizontal-tb` を指定する | 縦書きでは余白の箱の文字も縦に組まれる（同上） |
| 「奇数ページ」を前提にした規則（`:nth()`・章の始まりの側） | 論理名（`recto`・`verso`）で書いてあるものは変えない。奇数・偶数で書いてあるものがあれば、S8 で `:recto`・`:verso` に直す | `:recto`・`:verso` は Vivliostyle で使える（同上） |
| 部品の中の物理方向（`margin-left`・`left:`・`float: left`・`text-align: left` など 72 か所） | 層に分ける段階（S2）では変えない。S8 で、縦書きの本が読む部品について、論理方向（`margin-inline-start` など）へ直す | S2 の確かめを「層の位置だけが原因」に保つ。横書きでは物理方向と論理方向は同じ結果になるので、S8 で直しても本書の画素は変わらない（これを S8 の確かめにする） |
| `width`・`height`（50 か所） | 部品ごとに判断する。画像の `width=50%` は「行の長さに対する割合」の意味なので、縦書きでは挿絵を `writing-mode: horizontal-tb` の `figure` に入れて、意味を保つ | `v2-feasibility-notes.md` §3.1 の全面の挿絵の実験 |

KFX は `margin-inline: auto` を 0 に解く（`kindle-css-compatibility-notes.md` §2）。論理方向へ直すときは、`auto` を使う箇所を `targets/kindle.css` で物理方向に書き直す（今の回避策と同じ）。

---

## 7. 既存の本との互換

### 7.1 `custom.css`

- 層の外に置くので、`custom.css` の規則は、詳細度に関係なく vs とテーマのどの規則にも勝つ。1.x では、詳細度の高い vs の規則には `custom.css` が負けることがあった。2.0 では負けなくなる。
- EPUB と Kindle が読む平らな CSS でも同じに勝たせる。平らな CSS で vs の規則に負ける `custom.css` の宣言にだけ、生成が `!important` を付ける（著者の `custom.css` は書き換えない。層の中に `!important` は無いので、付けた宣言は必ず勝つ）。付けた結果、`custom.css` の宣言どうしの勝ち負けが変わる要素があれば、層ありで勝つ側にも付け、全部の要素でそろうまで繰り返す。著者が自分で `!important` を付けた宣言（と vs の `!important`）と取り合う場合は付けず、「EPUB（Kindle）では効かない」と場所だけを 🟡 で知らせる。付ける宣言が、`style` 属性で同じプロパティを指定している要素にも当たる場合は、その要素の `style` 属性の同じプロパティにも `!important` を付ける（`style` 属性が勝つという PDF の勝ち負けを保つ。2026-11-15 ユーザー決定。§10.9 の「仕様と違えたこと」の 1）。S3-3b で入れた（`v2-flat-cascade-consultation.md` §5.7）。
- 1.x で「効かないので `!important` を付けた」規則は、付けたままでも同じに働く。
- 逆に、1.x で詳細度が足りずに効いていなかった規則が、2.0 で効くようになる。`custom.css` に、効いていない規則を残している本では、見た目が変わる。`v2-migration-plan.md` §5 の移行の手順で、移行の前後の PDF を比べて確かめる。

### 7.2 変数の名前

公開する変数は `--book-*` に変わる（`theme-contract-spec.md` §5.2）。1.x の `custom.css` が今の名前を使っていても動くよう、二つの向きの別名を用意する。

| 向き | 場面 | 仕組み |
| :--- | :--- | :--- |
| 今の名前を**読む** | `custom.css` に `color: var(--theme-accent);` と書いてある | `stylesheets/tokens-legacy.css`（`tokens` 層）が、今の名前を新しい名前の別名として定義する（`--theme-accent: var(--book-color-accent);`） |
| 今の名前に**値を入れる** | `custom.css` に `:root { --color-link: #1a73e8; }` と書いてある | ビルドのときに `custom.css` の `:root` の定義を読み（今の `BookSettingsCss.root_variables` と同じ読み方）、今の名前の定義があれば、`settings` 層に `--book-color-link: var(--color-link);` を書き出す |

- 二つを同時に使っても循環しない。`custom.css` が今の名前に値を入れた場合、その定義は層の外なので `tokens-legacy.css` の別名に勝ち、今の名前は値そのものになる。
- 今の名前を `custom.css` で使っている本には、`vs build` と `vs preflight` が 💡 で、`vs upgrade` で新しい名前に直せることを知らせる（原稿の場所を指す指摘ではないので 💡。`terminal-output-notes.md`）。
- `vs upgrade` は、`custom.css` の中の今の名前を新しい名前へ置き換える。置き換える行を全部見せてから確認を取り、いいえなら何も変えない。
- 別名は 2.x の間は残す。対応の表は `lib/vivlio_starter/cli/css/legacy_tokens.rb` に 1 枚で置き、`tokens-legacy.css` と `settings` 層の書き出しと `vs upgrade` の置き換えが、同じ表を読む。

### 7.3 著者が直した雛形の CSS

1.x の本で、`custom.css` 以外の `stylesheets/` のファイルを著者が直している場合の扱いは、`v2-migration-plan.md` §5.3 に書く。ファイルの分け方が変わるので、三方向のマージは使えない。

---

## 8. 段階ごとの完了の条件と確かめ方

段階の番号と順序は `v2-migration-plan.md` §2 による。比較の方法は同 §3。どの段階も `rake test` と `bundle exec rubocop` が通ること、`ruby scripts/copy_to_scaffold.rb` で雛形へ同期することを含む。

1.x の小さな版では出さない。理由は三つある。(1) `stylesheets/` は著者の本に複製されるので、ファイルの分け方を変えると `vs upgrade` で全ファイルが入れ替わる。見た目が同じでも、1.x の利用者に大きな更新を求めることになる。(2) master は技術書典の 6 冊を組むのに使っており、CSS の全面の作り直しを入れる時期ではない。(3) 層に分ける作業は、テーマの切り出し（S6）と続けて行うほうが、ファイルの移動が一度で済む。

### S2 層に分ける（PDF の見た目を変えない）

| 小段階 | 作るもの | 完了の条件 |
| :--- | :--- | :--- |
| S2-1 入口と層 | `Css::EntryWriter`・`@font-face` を `fonts.css` へ・今のファイルを**分けずに**、1 ファイルを 1 つの層へ入れる（`base.css`→`base`、`theme.css`→`tokens`、`page-settings.css`→`base`、部品のファイル→`parts`、`{種類}.css` の固有の規則→`pages`、`spacing.css`・`pagebreak.css`・`replace-list.css`→`utilities`、`book-settings.css`→`settings`）。`frontmatter_generator.rb` の `link` を入口の 1 枚にする | 本書の PDF の全ページの画素が S0 の基準と一致する。一致しないページは、層の位置で勝ち負けが変わった規則が原因なので、規則を正しい層へ移して解く |
| S2-2 ファイルの分割 | §3.1 の配置（`targets/` と `themes/` を除く）。`chapter-common.css` を部品ごとに分ける。実測の記録を `vivliostyle-css-pitfalls-notes.md` へ移す | 画素が一致する。どのファイルも 400 行を目安に収まる |
| S2-3 `!important` を無くす | §2.4 の表 | 画素が一致する。`css_layer_test.rb` の `!important` の検査が通る |
| S2-4 前書き・後書きをそろえる | §3.3。巻末脚注の節の規則を消す（下の注） | 前書きと後書きのページを含め、画素が一致する。字間・段落・引用の規則が 1 か所にある |

- **S2-4 の巻末脚注の節（2026-11-14 に決定）。** `base/elements.css` の末尾の `section.footnotes` の 6 規則（1.x の `page-settings.css` から写したもの）を消す。後処理の `FootnoteConverter` が、章の HTML のすべてで巻末の節から脚注を取り出してページ脚注に変え、節そのものを消すので、組み上がった HTML に節は残らない（本書の HTML 43 枚・B4 の EPUB とも 0 件）。1.x でも当たる場面の無い規則だった。S2-1 で base 層に入ったため、`section.footnotes li p { text-indent: 0 }` は parts 層の `p { text-indent: 1em }` に負ける形になったが、当たらないので出力は変わらない。脚注の段落を字下げしない決まりは、紙面に出るページ脚注（`parts/footnote.css` の `.page-footnote { text-indent: 0 }`）が受け持つ。確かめは、`css_cascade_diff.rb` で、なくなった規則がこの 6 つだけであることと、PDF の画素と Kindle の中間生成物が変わらないこと。

- S2 の間、EPUB と Kindle は「入口の `@import` を解いて、今と同じ順に並べた CSS」を読ませる（S3 の `Flattener` の読み込みと並べ替えを、先に作って使う）。S2-1 の時点で `Css::Stylesheet` と `Css::Flattener` の 1・2 が要る。
- 確かめ方: 小段階ごとに、本書の写しを `targets: pdf, print_pdf, epub, kindle` で組み、S0 の基準と比べる。PDF は全ページの画素。EPUB と Kindle は S3 まで「Kindle Previewer の画面で、章扉・囲み・コード・索引・前書きの 5 か所を見比べて同じ」とする。
- 単章のビルド（`vs build 21`）と `vs preflight` が通ることも確かめる（入口の生成が、どのモードでも走ること）。
- `theme.style: simple` の写しと、`page.section_pagebreak: true`・`chapter_pagebreak: recto` の写しでも、PDF の画素を比べる（`settings` 層の規則が、設定の組み合わせで正しく勝つこと）。

### S3 平らな CSS と、出力先の規則の集約

| 小段階 | 作るもの | 完了の条件 |
| :--- | :--- | :--- |
| S3-1 `flat` | `Css::Flattener` の 3・`TargetFilter`・`InversionCheck`・`Bundle`・`VS_CSS_FORM`。`sanitize_epub_css!` と `bundle_book_settings_for_epub!` を無くす | (a) 本書を `VS_CSS_FORM=flat` で組んだ PDF の全ページの画素が、`layered` と一致する。(b) `InversionCheck` の報告が 0（または許可の表に理由つきで載っている）。(c) クリーン EPUB が EPUBCheck でエラー・警告とも 0 で、Apple Books の画面が S0 の基準と見比べて同じ。(d) EPUB の中の CSS に `@layer` と `@import` が無い |
| S3-2 規則の集約 | §5 の移動（`targets/epub.css`・`targets/kindle.css`）。§4.3 の要素ごとの判定 | (a) `stylesheets/`（`targets/` を除く）と同梱のテーマに `vs-kindle`・`vs-epub` が無い。(b) PDF の画素が一致する。(c) Kindle 用の EPUB の中の CSS で、`body.vs-kindle` の規則の数と中身が、移動の前と同じ（規則を選択子で並べて差分を取る）。(d) B1・B4 の EPUB と Kindle 用 EPUB で、`--log=debug` の要素ごとの判定の報告が 0 組か、理由つきで記録されている |
| S3-3 `flat_literal` | `LiteralResolver`。`BookSettingsCss` の `kindle_*` の 8 メソッドと `custom.css` の色の書き出しを無くす（`book-settings-kindle.css` も無くなる）。§5 のリテラルの直書きを変数に戻す。§7.1 の `custom.css` を平らな CSS でも勝たせる生成 | (a) Kindle 用の EPUB の中の CSS に `var(`・`calc(`・`color-mix(`・`:is(`・`:where(`・`:has(`・`@layer` が無い。(b) KPF の変換で Enhanced Typesetting が Supported・エラー 0。(c) Kindle Previewer の変換の中間生成物（`preprocessed/*.xhtml` の `computedstyle`。`kindle-css-compatibility-notes.md` §2.1 の 3）を、変更の前後で比べ、色と寸法の値が同じ。(d) `theme.color` を別の色に変えた写しで、Kindle の囲み・見出し・前書きの色が追従する。(e) `custom.css` で色の変数を変えた写しで、Kindle に色が届く。(f) `custom.css` に `h2 { margin-block-start: 2em; }` と `table { inline-size: 80%; }` を書いた写し（簡素な見出し・`.long-table` を含む）で、EPUB の計算値と Kindle の中間生成物が PDF と同じ値になる。`custom.css` が空の本で、平らな CSS が変わらない |

- **S3-4 Kindle に部品の値を届ける（2026-11-15 に足した段）。** `RESOLVED_LAYERS` を部品の層まで広げ、PDF 向けの値（本文の pt・mm の余白・字下げ）は `targets/kindle*.css` で打ち消すか em へ書き直す。層ごと・部品ごとに広げ、Kindle Previewer の画面で確かめる。完了の条件は、広げた層の `var()` などの宣言が Kindle に届き、画面で崩れが無いこと。S6 でテーマへ寸法を移す前に済ませる（§4.4 の「解く層」）。部品の層を解くと、S3-3a で Kindle に届かなくなった custom.css の 3 色（`--color-link`・`.column h5` の `--color-mark`・`.diagram` の枠の `--color-border-weak`。§10.7 の「仕様と違えたこと」の 6）も届く。その 3 色が届くことを S3-4 の完了の条件に含める。**2026-11-15 に完了（§10.10）。**
- **S3-3 は二つの段に分けた（2026-11-15）。** S3-3a は `LiteralResolver` と `BookSettingsCss` の Kindle 用の生成の撤去・リテラルの直書きの変数への書き直し（完了の条件の (a)〜(e)）。S3-3b は §7.1 の `custom.css` を平らな CSS でも勝たせる生成（(f)）。S3-3a は CSS を書き出す段で完結するが、S3-3b は HTML の書き換えが終わった後の要素ごとの判定を使うので、ビルドの流れの組み替えが要る。確かめの基準も違い（S3-3a は中間生成物が前と同じ、S3-3b は `custom.css` を書いた写しで PDF と同じ値）、一つの段にすると差が出たときに原因を切り分けられないため、分けた。
- **(a) の並びに `clamp(`・`min(`・`max(` を足す（S6 の最初から。`v2-post-s3-consultation.md` §5.3 の 2）。** S3 の完了の時点では、紙の寸法の `clamp()` の宣言が Kindle 用の CSS に残り、下流（KFX と Kindle Previewer の前処理）が捨てている。S6 の最初に `LiteralResolver` が理由を付けて落とすようにし（§4.4）、それ以降は Kindle 用の EPUB の中の CSS に `clamp(`・`min(`・`max(` が無いことも (a) に含める。確かめは、Kindle の中間生成物が前後で差 0（`theme-contract-spec.md` §9 の S6 の条件 7）。
- (a) の `VS_CSS_FORM=flat_literal` での PDF の比較は、参考にとどめる。`calc()` の中の `em` をリテラルにすると、箱の幅が約 1/16 px 変わる箇所がある（`vivliostyle-css-pitfalls-notes.md` §2.18）ので、画素は一致しない。比べるなら、行の位置（`pdftotext -bbox` の行の座標が 0.05pt 以内）で比べる。
- S3 の完了のときに、`.claude/CLAUDE.md` の「Kindle degradation convention」と `notation-implementation-guide.md` §3 を直し、`kindle-css-compatibility-notes.md` §5.1 に、規則の置き場が変わったことを書く。

---

## 9. 論点（未決）

| # | 論点 | 答えが要る時点 | 設計での扱い |
| :--- | :--- | :--- | :--- |
| 1 | `transparent` との `color-mix()`（前書きの見出しの背景）を、KFX が解する形で書けるか | S3-3 | **S3-3a で落とすことにした。** 本書で当たるのは前書きの `h2` の背景と `h3` の下線で、どちらも `in oklab` なので、色空間の決まり（srgb 以外は落とす）で先に落ちる。KFX が透明度つきの色を解すかは確かめていない。srgb の透明との混色も、確かめるまでは落とす |
| 2 | Kindle 用に、論理方向のプロパティを物理方向へ書き直す処理を `LiteralResolver` に持たせるか | S8 | 2.0 では `targets/kindle.css` に手で書く。縦書きの Kindle で論理方向が正しく解されるかを S8 で確かめ、崩れるなら生成で書き直す |
| 3 | 章の frontmatter で著者が足した CSS（層の外になり、`custom.css` と同じ強さになる） | S2-1 | 今より強くなる。使っている本は少ないと見て、移行の手引きに 1 行書く |

---

## 10. 実装記録

### 10.1 S2-1 入口と層（2026-11-14）

#### 作ったもの

- `lib/vivlio_starter/cli/css/`: `stylesheet.rb`（crass を包み、`@import`・`@layer` の宣言と囲み・それ以外の規則の 4 種類の項目にする）・`flattener.rb`（§4.2 の 1・2）・`entry_writer.rb`（§2.3）。`vivlio-starter.gemspec` に `crass ~> 1.0` を足した（入ったのは 1.0.8）。
- 入口は 11 種類（`chapter`・`appendix`・`preface`・`postface`・`toc`・`index`・`glossary`・`colophon`・`titlepage`・`legalpage`・`part-title`）。`EntryWriter::IMPORTS` は、1.x の `{種類}.css` の `@import` の顔ぶれと順をそのまま写した。前書き・後書きは `spacing.css` を読まず、付録は `image-header.css` を読まない（S2-4 でそろえる）。
- 入口を書くのは `Build::ImageOptimizer.prepare_theme_images!` の最初。`book-settings.css` の生成は `theme:` 節が無い本では飛ばされるが、入口は HTML が読む唯一の CSS なので、`theme:` 節の有無に関わらず書く。
- `stylesheets/`: 種類ごとの CSS と `chapter-common.css` から `@import` を外した。`page-settings.css` の `@font-face` と Google Fonts の `@import` を `fonts.css` へ移した。
- HTML の `link` は入口の 1 枚になった（`FrontmatterGenerator`・`TocDocumentBuilder`・索引と用語集の `UnifiedPageBuilder`）。frontmatter の `stylesheet:` が種類の CSS の名前（全巻目次の `toc.css`）なら、その種類の入口を読む。種類の CSS でない名前は、入口の後に層の外で足す。

#### 仕様と違えたこと

1. **予備の書体の面を `book-fonts.css` へ分けた。** `book-settings.css` は、本の書体にも HackGen にも無い字のための `@font-face`（改善案 #127）を含む。そのまま settings 層で読むと、§2.2 の「`@font-face` を層に入れない」に反する。`BookSettingsCss.render_fonts` が `.cache/vs/book-fonts.css` へ書き、入口が `fonts.css` の直後に層の外で読む。同じ書体名の面は後の面が優先されるので、HackGen の面（`fonts.css`）の後に置く順は 1.x と同じである。
2. **`bundle_book_settings_for_epub!` を S2-1 で置き換えた。** §4.2 では S3-1 で無くす予定だった。S2-1 で HTML が `book-settings.css` を直接読まなくなり、働く場所が無くなったためである。代わりの `bundle_flat_css_for_epub!` は、入口を平らにした 1 枚を消費者 dir の `styles/<種類>.css` に書き、`link` を付け替える。`url()` は、`stylesheets/` の中のものを `../stylesheets/…`、`.cache/vs/` の中のもの（`theme-images/`）を `../theme-images/…` へ引き直す。Kindle の異体字の 1 字書体の規則（`apply_variant_glyph_fonts_for_kindle!`）は、`book-settings.css` の写しではなく `styles/` の全部の CSS へ足す。`stylesheets/` の CSS の写しは、今までどおりパッケージに入る（使われないが、外すのは S3-1 で行う）。
3. **改丁の打ち消しを `book-settings.css` の側へ移した。** `page.chapter_pagebreak` が `verso`・`any` のとき、`book-settings.css` は素の `body` に `break-before` を出す。1.x では、本扉・権利ページ・奥付の CSS が `body.titlepage { break-before: auto; }` などで打ち消していた（詳細度で勝つ）。層に入れると、settings 層の素の `body` が、詳細度に関係なく pages 層の打ち消しに勝つ。これは §4.3 の「層を外すと結果が変わる」と同じ形の、層を付けたことによる勝ち負けの逆転である。打ち消しを `BookSettingsCss.chapter_pagebreak_css` へ移し（`CHAPTER_PAGEBREAK_EXEMPT_SELECTORS`）、同じ層の中で改丁の規則より後に置いた。ページの CSS の側の打ち消しは消した。B1〜B3 は `any`・`recto` で、`verso` は通らないので、`verso` の写しを 1.x（基準のソース）と S2-1 で組んで比べた（下の結果）。

#### 確かめた結果

写しの本は、作業ツリーをそのまま写した（作業ツリーの `images/` を雛形の写し `lib/project_scaffold/images/` で埋め、素材が基準のソースと差 0 になるようにした）。出力は `../vivlio-starter-v2-baseline/check/s2-1-*/`。

| 確かめ | 結果 |
| :--- | :--- |
| B1 の閲覧用 PDF・印刷用 PDF | 283 ページ・281 ページとも、違うページ 0 |
| B2（`theme.style: simple`） | 279 ページ、違うページ 0 |
| B3（節で改ページ・章は右の面・`b5_standard`） | 450 ページ、違うページ 0 |
| B4（book_ai_web_starter の上巻）の PDF | 317 ページ、違うページ 0。本の `stylesheets/*.css` は雛形と同じ中身だったので、写しの CSS を作業ツリーのものに差し替えて組んだ（手を入れていない雛形の本に `vs upgrade` を掛けたのと同じ形） |
| `chapter_pagebreak: verso` の写し | 基準のソースの `bin/vs` で組んだ同じ写しと比べ、304 ページ、違うページ 0 |
| EPUBCheck | B1 の EPUB・Kindle 用 EPUB、B4 の EPUB の 3 つとも、エラー・警告 0 |
| EPUB の中の CSS | `styles/` の 8 枚（本書の EPUB が使う種類）に `@layer`・`@import` が無い |
| Kindle の変換の記録 | Enhanced Typesetting: Supported・Success・エラー 0・品質の問題 0。注意は S1 と同じ W14016 の 1 件だけ |
| Kindle の中間生成物 | 36 ファイル・26,335 要素。変換が書いた `style` 属性（Kindle が表示に使う値）は、画像の幅と高さを除いて S1 と全部一致。`computedstyle` は、位置と箱の大きさを除いた値が全部一致し、位置と大きさは 9,198 要素で違う（下の注） |
| Kindle Previewer の画面 | §3.2 の 10 か所すべてで、S1 の画面と画素まで一致（差 0） |
| 単章のビルド（`vs build 21`）・`vs preflight` | どちらも通る（🔴 0）。preflight の後に入口が 11 枚ある |
| `rake test`・`rake test:standard`・`rake test:layout`・rubocop | 4,298 件・4,298 件・7 件とも失敗 0（`rake test` のスキップ 1 は基準と同じ）。rubocop の違反 0 |

**注（Kindle の `computedstyle` の位置と大きさ）。** 変換の前処理が組んで測った位置と大きさが、平らにした CSS で変わる。たとえば `94-further-inspiration` の book-card の画像は、S1 では `body.vs-kindle .book-card img` の `max-height: 13em` が効いて高さ 208px、S2-1 では縦横比どおりの 290px になる。一方、同じ XHTML と CSS を Chromium 155 で組むと、S1 と S2-1 のどちらも 182px で同じになる（CSS の勝ち負けは変わっていない）。前処理の書いた `style` 属性にはどちらにも `max-height` が無い。

この違いが表示に出るかは、位置と大きさの差が大きかった章の画面を、S1 と S2-1 の KPF で同じ Location に移動して撮って比べた。21 章（1300・1450・1600）・42 章（6500〜6800 の 6 か所。前処理の測った章の高さは 6977px → 9846px）・付録 E の book-card（9325・9330）・付録 F（9400〜9980 の 15 か所。book-card の 9930・9950 を含む）の計 26 か所で、画素まで一致した（差 0）。26 枚は互いに別の画面で、着いた場所は画面で確かめた。前処理が測る値のこの違いは、Kindle の表示には出ていない。S3 では `computedstyle` を比べるので、そこで原因（前処理が 1 枚の大きな CSS をどう扱うか）を確かめる。

**確かめ方について分かったこと。**

- `build_copy.rb --kindle-record` は、前の記録を消さずに同じ置き場へ書いていた。中間生成物の名前には変換ごとのハッシュが付くので、二回分が混ざる。記録を取る前に置き場を消すよう直した。
- Kindle の中間生成物の比べ方（使い捨てのスクリプト）: ファイル名の `0_1_<16 進>_<16 進>-` を外して突き合わせ、要素の出現の順に `computedstyle` と `style` 属性を並べて比べる。`computedstyle` は位置（`top` など）と箱の大きさを外した比べと、外さない比べの両方を行う。S0 と S1 の記録で、奥付の要素が 1 つ増えた差（17 要素）を拾うことを確かめた。S3 で道具にする。

### 10.2 S2-2 ファイルの分割（2026-11-14）

#### 作ったもの

- `stylesheets/` を §3.1 の配置に分けた（`targets/`・`themes/`・`tokens-legacy.css` を除く）。規則の文字列は変えずに、元のファイルの行の範囲を写した。どのファイルも 400 行以下（最長は `parts/box.css` の 376 行）。

  | 元のファイル | 分けた先 |
  | :--- | :--- |
  | `base.css` | `base/reset.css`・`base/elements.css` |
  | `page-settings.css` | `base/page.css`（巻末脚注の節の規則だけ `base/elements.css`） |
  | `theme.css` | `tokens.css` |
  | `chapter-common.css` | `parts/heading.css`・`prose.css`・`list.css`・`figure.css`・`box.css`、`utilities/align-chapter.css` |
  | `components.css` | `parts/book-card.css`・`footnote.css`・`math.css`・`epub-reflow.css`・`talk.css`・`reference.css` |
  | `layout-utils.css` | `parts/layout.css`・`sideimage.css`・`side-by-side.css`、`utilities/align.css`・`gap.css` |
  | `toc.css` | `pages/toc.css`・`pages/whole-toc.css` |
  | `prism.css`・`code.css`・`table.css`・`simple-header.css`・`image-header.css` | `parts/` へそのまま |
  | `spacing.css`・`pagebreak.css`・`replace-list.css` | `utilities/` へそのまま |
  | 種類ごとの CSS（`chapter`・`appendix`・`preface`・`postface`）と本文以外のページの CSS | `pages/` へそのまま |

- `EntryWriter::IMPORTS` を新しい配置にした。各ページの種類が読む規則の集合と、層の中の並びは S2-1 と同じにした（下の「確かめた結果」の 1）。
- `scripts/css_cascade_diff.rb`: 二つの版（既定は `HEAD` と作業ツリー）の入口を平らにし、ページの種類ごとに (1) 規則の増減、(2) 層を移った規則、(3) 勝ち負けの入れ替わり（同じ要素に当たりうる二つの宣言で、勝つ側が前後で変わった組）を数える。`--html` に組み上がった HTML・EPUB を渡すと、(3) を「両方の選択子に当たる要素がある組」に絞る（§4.3 (2) の絞り込みと同じ考え方）。PDF の画素では確かめられない Kindle・EPUB の規則と、本書で使っていない記法の規則を確かめるために作った。S2-3・S2-4 でも使い、S3-1 の `InversionCheck` の下書きにする。
- CSS のコメントにあったエンジンの癖の実測の記録（6 件）を `vivliostyle-css-pitfalls-notes.md` §2.19〜§2.23 へ移し、CSS には理由と節の番号を残した。同メモの早見表の修正先は今のファイル名にした。
- Ruby の側でファイル名を読んでいた 2 か所（`ThemeColor::THEME_CSS`・`EpubBuilder#read_theme_heading_assets`）を `tokens.css` にした。コメントとテストの中の古いファイル名も直した。`stylesheets/_README.md` を層の説明に書き直した。

#### 仕様と違えたこと

着手の前にユーザーに確かめ、1〜3 の扱いに決めた（2026-11-14）。

1. **読むページの種類が違う規則は、一つのファイルにまとめなかった。** §3.1 の「←」は、読むページの種類が違うファイルを合わせる形になっている（`chapter-common.css` は章と付録だけ、`components.css`・`layout-utils.css` は前書き・後書きも、`chapter.css` は章だけが読む）。そのまま合わせると、前書き・後書き・付録に今は当たっていない規則が当たる。S2-2 では読む規則の集合を変えず、出どころごとにファイルを分けた。そのため、`parts/` は「本文のページがみな読む」ものと「章・付録だけが読む」もの（`heading`・`prose`・`list`・`figure`・`box`）に分かれ、`utilities/align-chapter.css`（章・付録だけが読む `.text-*` の段落の規則）ができた。合わせるのは S2-4 で行う。
   - 実物の置き場も §3.1 と違った。囲み（`.column`・`.tip`・`.output` など）は `components.css` ではなく `chapter-common.css` にあり、`box.css` はそこから作った。脚注は `components.css`（`.page-footnote`）と `page-settings.css`（`section.footnotes`）にあった。`chapter-common.css` には会話（`talk`）と脚注の規則が無かった。
   - 参考書籍のカード・数式・EPUB のリフローの直しは §3.1 の表に無いので、`parts/book-card.css`・`math.css`・`epub-reflow.css` にした。`epub-reflow.css` の中身（`body.vs-epub` の規則と EPUB だけに出るマークアップの規則）は S3-2 で `targets/epub.css` へ移る。
2. **ページの種類ごとの CSS は無くさず、`pages/` へ移した。** `chapter.css`・`appendix.css`・`preface.css`・`postface.css` は、素の選択子（`:root`・`body`・`h1`・`p`）で書かれ、そのページの種類でしか読めない。前書き・後書きの規則は S2-4、付録の色（`:root` の変数）と用語集の印（`.glossary-link`）は S6 で、テーマか部品へ移す。`simple-header.css`・`image-header.css` は §3.1 の表に無い（S6 でテーマへ移る）ので、`parts/` に置いた。
3. **位置の指定のうち、`utilities` 層へ移したのは位置そのものの規則だけにした。** `.align-left`・`.align-center`・`.align-right` の既定（`display: block`・`margin-block: 0.5em`・`text-align: inherit` の 1 規則）は `parts/layout.css` に残した。最初はこの規則も `utilities/align.css` へ移したが、`css_cascade_diff.rb --html` が、本書で実際に当たる入れ替わりを 11 組挙げた（`.column.align-right` の上下 8mm・6mm と、`.output` の最初と最後の子の余白 0 が、既定の 0.5em に負ける）。このとき組んだ PDF は、基準と 8 ページ違った。既定の余白は著者が書いた位置ではなく、囲みの余白に負けるのが正しいので、parts 層に戻した。既定に勝つための図版の 4mm（`figure:is(.align-*)`）も、`parts/figure.css` の元の位置に戻した。
   - `utilities` へ移したのは、左右の位置揃え（`.align-*` の `text-align`・`margin-inline`・回り込み）・`.text-*`・`.clear-*`・グリッドの中の位置（`.align-top` など）・横並びの間隔（`.gap-*`）の 25 規則。
   - 横並びの間隔（`.gap-s`・`.gap-m`・`.gap-l`）は、§3.1 の表に無い `utilities/gap.css` にした。1.x では「ファイルの最後に置けば、同じ詳細度のコンテナの `gap` に勝つ」で効かせていた。層に入れると、置く位置に頼らずに勝つ。`layout.css` を 400 行に収めるために並べ方を 3 つのファイルに分けたので、最後に置くことができなくなったためでもある。
4. **`tokens-legacy.css` は作らなかった。** 今の名前を新しい名前の別名にするファイル（§7.2）で、変数の名前を変える S6 で作る。

#### 確かめた結果

写しの本は作業ツリーをそのまま写した。出力は `../vivlio-starter-v2-baseline/check/s2-2-*/`・`runs/s2-2-*/`。

| 確かめ | 結果 |
| :--- | :--- |
| 1. 規則の集合（`css_cascade_diff.rb`。`HEAD`＝S2-1 と比べる） | 11 種類の入口のどれも、規則の数が同じで、なくなった規則・増えた規則とも 0。層を移った規則は 25（すべて parts → utilities） |
| 2. 勝ち負けの入れ替わり（同） | 本書の PDF 用 HTML（43 枚）・EPUB・Kindle 用 EPUB と B4 の EPUB の計 138 文書で、両方の選択子に当たる要素がある組は 0。当たる要素の無い組が 460 あり、ほとんどは utilities へ移した位置の指定（`.text-*`・`:is(img, svg).align-*` の回り込み・`.gap-*` など）が、同じ要素に付いたときに部品の規則に勝つようになったもの（§2.1 の utilities 層の狙いのとおり）。残りの 4 組は、同じ要素に付かないクラスの組か、値が同じ意味の組（`bold` と `700` など） |
| B1 の閲覧用 PDF・印刷用 PDF | 283 ページ・281 ページとも、違うページ 0 |
| B2（`theme.style: simple`） | 279 ページ、違うページ 0 |
| B3（節で改ページ・章は右の面・`b5_standard`） | 450 ページ、違うページ 0 |
| B4（book_ai_web_starter の上巻）の PDF | 317 ページ、違うページ 0（S2-1 と同じく、本の CSS を作業ツリーのものに差し替えて組んだ） |
| 単章のビルド（`vs build 21`）・`vs preflight` | どちらも 🔴 0。単章の PDF は S2-1 と 15 ページとも違うページ 0。preflight の後に入口が 11 枚ある |
| EPUB（S2-1 と比べる） | B1 の EPUB・Kindle 用 EPUB・B4 の EPUB とも、XHTML の差 0。違うのは、パッケージに入る `stylesheets/` の写しのファイルの名前（使われないファイル。外すのは S3-1）と、平らにした `styles/*.css` の規則の並び（規則の集合は同じ）、OPF の manifest のその分だけ |
| EPUBCheck | B1 の EPUB・Kindle 用 EPUB、B4 の EPUB の 3 つとも、エラー・警告 0 |
| Kindle の変換の記録 | Enhanced Typesetting: Supported・Success・エラー 0・品質の問題 0。注意は S2-1 と同じ W14016 の 1 件だけ |
| Kindle の中間生成物 | 36 ファイル・27,263 要素で、`computedstyle` は位置と大きさも含めて S2-1 と全部一致。`style` 属性は 1 要素（22 章の `.column.text-right`）で宣言の並び順だけが違い、値は同じ |
| Kindle Previewer の画面 | §3.2 の 10 か所（§8 の 5 か所を含む）すべてで、S2-1 の画面と画素まで一致（差 0）。10 枚は互いに別の画面 |
| `rake test`・`rake test:standard`・`rake test:layout`・rubocop | 4,298 件・4,298 件・7 件とも失敗 0（`rake test` のスキップ 1 は S2-1 と同じ）。rubocop の違反 0 |

### 10.3 S2-3 `!important` を無くす（2026-11-14）

#### 作ったもの

- `stylesheets/` の `!important` 18 か所を全部外した（`stylesheets/` の中は 0 か所。コメントにも残していない）。外しただけでは勝ち負けが変わる組を `scripts/css_cascade_diff.rb` で洗い、次のように解いた。

  | 場所（S2-2 の後の名前） | 外すと何に負けるか | 直し方 |
  | :--- | :--- | :--- |
  | `parts/heading.css` の `h2.vs-break-merged`（2 か所） | 本書には無い形。`page.section_pagebreak: false` の image の本で、章の最初の節の直前に `@pagebreak:recto` を書くと、settings 層の章扉の保護（`body.vs-header-image:not(.vs-epub) section.level2:first-of-type > .section-topic h2`）が勝ち、改ページが二重になる | 規則を `utilities/pagebreak.css` へ移した（parts 層の h2 の改ページには層で勝つ）。settings 層に勝てない分は、章扉の保護の選択子に `:not(.vs-break-merged)` を足して、取り合わないようにした（`BookSettingsCss#chapter_frontispiece_guard_rule`） |
  | `pages/preface.css` の `.text-*`（6 か所） | utilities 層の `.align-*`・`.text-*` の `text-align` に負ける（同じ要素に両方を付けたとき） | 章の `utilities/align-chapter.css` と中身が同じだったので、二つを `utilities/align.css` の末尾の 1 組にまとめ、`align-chapter.css` を消した。前書き・後書きも同じ組を読む（§2.4 の「本文のページで共通の指定にする」）。`.align-*` の `text-align` より後に置く順は、章で 1.x から効いていた順と同じ |
  | `parts/footnote.css` の `display`（4 か所） | 実際に取り合うのは、印刷の媒体での控えの aside の非表示（`aside.page-footnote[data-footnote-anchored]`）と `body.vs-epub aside.page-footnote { display: block }` の 1 組だけ（EPUB を印刷の媒体で組んだときに控えが出る）。ほかの 3 か所は、同じ要素に当たる相手が詳細度か順で既に負けている | 控えの非表示の選択子の先頭に `body` を足して詳細度をそろえ、後に置いた側が勝つようにした |
  | `parts/epub-reflow.css` の節リード（1 か所）と `parts/image-header.css` の節リード（2 か所） | 1.x では両方に `!important` があり、詳細度で image の側（上下 0）が勝っていた。EPUB の側（上下 0.3em・1em）が効いていたのは simple の見出しのときだけで、simple の見出しの PDF 用の余白（`parts/simple-header.css`）に `!important` で勝っていた。外すと、simple の見出しの EPUB で PDF 用の余白が勝つ | 今の結果を選ぶ対象で明示した。EPUB の上下の余白は `body.vs-epub:not(.vs-header-image) .section-lead` に、simple の見出しの PDF 用の余白は `body.vs-header-simple:not(.vs-epub) …` にし、どの組も同じ要素で取り合わないようにした。image の側は詳細度で今のまま見出しの部品の負の余白に勝つ |
  | `pages/toc.css` の `content: none`（1 か所） | 取り合う相手が無い（li の `::after` に値を入れる規則は無く、目次の番号は `.toc-title::after`） | 外すだけ |

- `test/vivlio_starter/cli/css/css_layer_test.rb`: `stylesheets/`（`custom.css` を除く）と `themes/` の CSS の、コメントの外に `!important` が無いことを確かめる。検査が空振りしないことのテストも置いた。
- `scripts/css_cascade_diff.rb`: 宣言を突き合わせる鍵から `!important` を外した。`!important` を外した宣言を前後で同じ宣言として扱い、外したことで勝ち負けが変わる組を数えるためである。

#### 仕様と違えたこと

1. **§2.4 の表の「`utilities` 層へ移す」だけでは足りない箇所があった。** `h2.vs-break-merged` が勝つべき相手には、settings 層（`book-settings.css`）の章扉の保護が含まれる。utilities 層は settings 層の下なので、settings 層の側の選択子を絞った。S2-1 の改丁の打ち消し（§10.1 の 3）と同じく、下の層の打ち消しが上の層の規則に負ける形である。
2. **節リードは「勝つ側を上の層に置く」ではなく、選ぶ対象を絞って取り合わないようにした。** EPUB の規則のコメントは「image-header の上下 0 に勝つため」としていたが、1.x の実際の出力では image の側が勝っていた。S2 は見た目を変えない段階なので、実際の出力（image の見出しの EPUB では節リードの上下が 0）を保った。EPUB の規則は S3-2 で target 層（parts と theme の上）へ移るので、層の位置に頼ると、そこで image の見出しの EPUB の見た目が変わる。選ぶ対象で明示しておけば、S3-2・S6 で規則が別の層へ移っても結果が変わらない。image の見出しの EPUB でも節リードを見出しに近づけるか（コメントの元の意図）は、見た目を変える判断なので、S2 の後に決める。**決める時点は、S6 の完了の後、S7 の前とした（2026-11-15・`v2-post-s3-consultation.md` §5.6 の 3）。** この規則は `image` の見出しに掛かる EPUB の規則で、S6 で `themes/standard/epub.css` へ移る。移動を差 0 で終えてから、見た目を変える変更の手順（`v2-migration-plan.md` §4.1）で扱う。今の出力と、節リードを見出しに近づけた出力を、Apple Books と Kindle Previewer の画面で並べ、ユーザーが選ぶ。判断の目安は、PDF の `image` の見出しでの節リードと見出しの間隔に EPUB をそろえるかどうかである。
3. **`align-chapter.css` を S2-3 で無くした。** S2-2 では S2-4 で `align.css` へまとめる予定だった（§10.2 の 1）。前書きの `!important` を utilities 層で解くには、前書きも同じ規則を読む必要があり、まとめるのが最も簡単だったため、S2-3 で行った。前書き・後書きが `spacing.css` を読まない差は S2-4 に残る。
4. **`book-settings.css` の `!important` 1 か所は残した。** `BookSettingsCss#h4_marker_kindle_rule` が、Kindle の h4 の印を、Techbook の `<style>` の `!important` に勝たせるために `!important` で書き出す。生成物で `stylesheets/` の外なので、§2.4 の 18 か所に入っていない。S3-3 でこのメソッドごと無くす（§4.4 の「今の仕組みとの入れ替え」）。

#### 確かめた結果

写しの本は作業ツリーをそのまま写した。比べる相手は S2-2 の出力（`../vivlio-starter-v2-baseline/runs/s2-2-*/`・`check/s2-2-b1/`）。S2-3 の出力は `runs/s2-3-*/`・`check/s2-3-*/`。

| 確かめ | 結果 |
| :--- | :--- |
| 1. 勝ち負けの入れ替わり（`css_cascade_diff.rb`。`HEAD`＝S2-2 と比べる） | 本書の PDF 用 HTML・EPUB・Kindle 用 EPUB、B2 の PDF 用 HTML・EPUB、B4 の EPUB の計 214 文書で、両方の選択子に当たる要素がある組は 0。当たる要素の無い組が 221 あり、読んで確かめた。別の要素どうしの組（li の `::after` と `.toc-title::after`、脚注の span と aside など）か、著者の指定（`.aki`・`.aki2`）が部品に勝つようになった組（§2.1 の utilities 層の狙いのとおり）である。`vs-break-merged` と章扉の保護の組は、道具が読む `book-settings.css` が古い選択子のもの |
| 2. EPUB の計算値（§8.4 の比べ方） | B1 の EPUB（37 文書・24,408 要素）・Kindle 用 EPUB（36・26,283）・B2 の EPUB（37・24,988）・B4 の EPUB（26・32,595）に、S2-2 と S2-3 の平らな CSS を当てた。画面と印刷の両方の媒体で、違う要素 0 |
| B1 の閲覧用 PDF・印刷用 PDF | 283 ページ・281 ページとも、違うページ 0 |
| B2（`theme.style: simple`） | 279 ページ、違うページ 0 |
| B3（節で改ページ・章は右の面・`b5_standard`） | 450 ページ、違うページ 0 |
| B4（book_ai_web_starter の上巻）の PDF | 317 ページ、違うページ 0（本の CSS を作業ツリーのものに差し替えて組んだ） |
| `@pagebreak:recto` の直後の節（本書に無い形） | 12 章の最初の二つの節の前に書き足した写しを、S2-2 と S2-3 で単章で組んだ。`section_pagebreak: false`（印 1 件・9 ページ）・`true`（印 2 件・10 ページ）とも、違うページ 0 |
| 単章のビルド（`vs build 21`）・`vs preflight` | どちらも 🔴 0。単章の PDF は S2-2 と 15 ページとも違うページ 0。preflight の後に入口が 11 枚ある |
| EPUBCheck | B1 の EPUB・Kindle 用 EPUB、B4 の EPUB の 3 つとも、エラー・警告 0 |
| Kindle の変換の記録 | Enhanced Typesetting: Supported・Success・エラー 0・品質の問題 0 |
| Kindle の中間生成物 | 36 ファイル・27,263 要素で、`computedstyle`（26,335 要素）は位置と大きさも含めて S2-2 と全部一致。`style` 属性も全部一致。同じ比べ方で S1 と比べると既知の 9,198 要素の差が出るので、比べ方は差を拾う |
| Kindle Previewer の画面 | 撮っていない。変換が組んだ計算値と `style` 属性が全要素で S2-2 と一致したので、画面の差は出ないと判断した |
| `rake test`・`rake test:standard`・`rake test:layout`・rubocop | 4,300 件・4,300 件・7 件とも失敗 0（`rake test` のスキップ 1 は S2-2 と同じ。増えた 2 件は `css_layer_test.rb`）。rubocop の違反 0 |

### 10.4 S2-4 前書き・後書きをそろえる（2026-11-15）

#### 作ったもの

- `EntryWriter::IMPORTS`: 本文のページ（章・付録・前書き・後書き）が、同じ部品（`BODY_PARTS`）と同じ著者の指定（`BODY_UTILITIES`）を読むようにした。前書き・後書きに `heading`・`prose`・`list`・`figure`・`box` と `spacing.css`、付録に `image-header.css` が足された。見出しの 2 種（`simple-header`・`image-header`）は body の `vs-header-*` のクラスで選ぶので、どちらのクラスも付かない前書き・後書きと、`vs-header-simple` だけが付く付録の `image-header` には当たらない。
- 扉絵の `@page :nth(1)`（`--frontispiece-image` の全面背景）を、`parts/image-header.css` から `pages/chapter.css` へ移した。`@page` は body のクラスで絞れないので、付録・前書き・後書きが `image-header.css` を読むと、最初のページに扉絵が出る。章では parts 層から pages 層へ移ったことになるが、`@page :nth(1)` の背景を取り合うのは settings 層（`book-settings.css` の綴じのずれ）だけなので、勝ち負けは変わらない。
- `stylesheets/parts/preface.css`（新規・前書きと後書きだけが parts 層の最後に読む）: `pages/preface.css` から、見出し・段落・箇条書き・リンク・強調・ルビ・水平線・引用・表の規則を移した。`prose.css` と同じ宣言（字間の 2 規則・段落の字下げ・引用の中の段落の字下げと間・リンクの色と下線）は消し、字間・段落・引用の規則は `prose.css` の 1 か所になった。後半に、1.x の前書きの見た目を保つ打ち消しを置いた（下の「仕様と違えたこと」の 2）。
- `pages/preface.css` には、変数（`:root`）と本文の組み方・ノンブルの種類（`body`）だけを残した。
- 巻末脚注の節の 6 規則（`base/elements.css` の末尾の `section.footnotes`）を消した（§8 の注）。
- `test/vivlio_starter/cli/css/entry_writer_test.rb`: 本文のページが同じ部品と著者の指定を読むこと（前書き・後書きは最後に `parts/preface.css`）と、扉絵の `@page :nth(1)` を章のほかが読まないことを確かめる 2 件を足した。

#### 仕様と違えたこと

着手の後、前書きに新しく当たる規則を数えてからユーザーに確かめ、1 と 3 の扱いに決めた（2026-11-15）。2 は 1 を成り立たせるための置き場である。

1. **1.x の前書きで素のまま組まれていた記法は、章と同じ見た目にした。** 1.x の前書き・後書きは `chapter-common.css` を読まなかったので、囲み（`.tip` など）・h4〜h6・図のキャプション・強意の下線・定義リスト・タスクリスト・節リードなどは、前書きでは規則の当たらない素の要素として組まれていた。§3.3 の「当たって見た目が変わる規則は … 今の見た目に戻す」を当てると、これらを素のまま残す打ち消しが数十規則要る。記法が前書きで働かないのは 1.x の不具合なので、戻さずに章と同じ見た目にした。本書の前書きにはこの種の記法が無く画素は変わらない。B4 の前書きの `:::{.tip}` だけが、枠と地色の付いた囲みになる（下の「確かめた結果」）。
2. **前書きの見た目の規則を、pages 層でなく parts 層の最後に置いた。** §3.3 は前書きの固有の見た目を、テーマの `body.preface` の規則（theme 層）にするとしている。層が部品より上だと、前書きの素の `p { margin-block-end: … }` が、詳細度に関係なく `.tip p`・`.talk-body p`・`.strong-heading` などの記法の規則に勝ち、1 で章と同じ見た目にした記法が崩れる。1.x では前書きの CSS が部品の後に層なしで読まれ、詳細度で競っていた。parts 層の最後に置くと同じ形になる。S6 でテーマへ移すときも、この競い方を保つ必要がある（テーマの下位の層を parts の直後に置くか、選択子で記法を外す）。
3. **1.x の前書きだけの見た目を、打ち消しで保った。** 前書きが章の部品を読むと、本書の前書きの箇条書き（章は太字で上下に半行あく）・図（章は上下 4mm で画像に枠）・章リード（章は大きく太め）が変わる。この 3 つと、前書きの CSS が自分で形を決めている h1〜h3（章の部品の字間の詰め・h3 の高さと行送り）は、前書きの見た目として `parts/preface.css` の後半で打ち消した（ユーザーの決定）。打ち消しは、打ち消す部品の規則と同じ詳細度で書いた。記法の規則（`.pictures figure`・`figure.vs-math-display`・`img.vs-bordered` など）には今までどおり負ける。
   - 図の `position: relative`（図中の注釈の記法を働かせる部品の規則）は打ち消していない。ずらしの指定が無いので組みは変わらないが、計算値は変わる（下の「確かめた結果」の 2）。
   - 切り抜いた画像の枠の打ち消しは、`figure :is(img, svg)` と別の規則にした。KFX は `:is()` を含む規則を丸ごと捨てるので、一つにまとめると Kindle で打ち消しが消え、章の `figure img.vs-cropped` の枠だけが残る。
4. **付録も `image-header.css` を読むようにした。** §10.1 の「付録は `image-header.css` を読まない（S2-4 でそろえる）」の分。付録の body には `vs-header-simple` が付くので、`body.vs-header-image` で絞った 16 規則は当たらない。

#### 確かめた結果

写しの本は作業ツリーをそのまま写した。比べる相手は S2-3 の出力（`../vivlio-starter-v2-baseline/runs/s2-3-*/`・`check/s2-3-b1/`）。S2-4 の出力は `runs/s2-4-*/`・`check/s2-4-b1/`。

| 確かめ | 結果 |
| :--- | :--- |
| 1. 規則の集合（`css_cascade_diff.rb`。`HEAD`＝S2-3 と比べる） | 章は規則の数が同じで、増減 0（扉絵の `@page :nth(1)` の位置が変わっただけ）。付録は `body.vs-header-image` で絞った 16 規則が増えた。前書き・後書きは 4 規則がなくなり（`prose.css` と重なる宣言を消した段落・リンク・引用の段落と、中身の無い `h1 + p` の規則）、178 規則が増えた。本文以外のページは 7 種類とも増減 0 |
| 2. 勝ち負けの入れ替わり（同） | 本書の HTML 117 文書で、両方の選択子に当たる要素がある組は 44。どれも、記法の規則（`.talk-body p`・`.book-title`・表の見出しの段落・EPUB の扉絵の見出しなど）が、前書きの素の要素の規則（`p`・`h1`・`h2`・`strong`）に勝つようになった組で、仕様と違えたことの 1・2 のとおり |
| 3. 計算値（§8.5 の比べ方） | 本書の PDF 用 HTML（39 枚・層ありと平ら）・EPUB（39 枚・画面と印刷）・Kindle 用 EPUB（39 枚）に、S2-3 と S2-4 の CSS を当てた。違うのは前書きの図 5 つの `position`（`static` → `relative`）だけ。B2 の PDF 用 HTML と EPUB（78 文書）も同じ。B4 の EPUB（28 枚）は、前書きの図の `position` と、囲み（`.tip`）の中身（枠・地色・見出し札と、中の段落の字下げ 0）だけ |
| 4. 章の部品を当てた前書き（本書に無い記法） | 本書の章・付録の HTML 26 枚の body を前書きのクラスに付け替えて、S2-3 と S2-4 の CSS を当てた。h1〜h3・段落・箇条書き・リンク・強調・引用・図・章リードは前書きの見た目のまま（図の `position` を除く）。囲み・h4〜h6・キャプション・強意・定義リスト・タスクリスト・番号の形・節リードなどは、章と同じ見た目になった |
| B1 の閲覧用 PDF・印刷用 PDF | 283 ページ・281 ページとも、違うのは 1 ページ（22 章の `@today` の日付。ビルドした日が違う）だけ。前書き・後書きのページを含め、CSS による差は 0 |
| B2（`theme.style: simple`） | 279 ページ、違うのは `@today` の 1 ページだけ |
| B3（節で改ページ・章は右の面・`b5_standard`） | 450 ページ、違うのは `@today` の 1 ページだけ |
| B4（book_ai_web_starter の上巻）の PDF | 317 ページで同じ。違うのは前書きの 3 ページ（p7〜p9）。`:::{.tip}` が枠と見出し札の付いた囲みになり、分割しない囲みなので次のページへ送られ、前書きの後ろの部分がその分送られた。前書きは p9 で終わり、h3（📚 の印）などほかの見た目は変わらない（仕様と違えたことの 1） |
| 単章のビルド（`vs build 21`）・`vs preflight` | どちらも 🔴 0。単章の PDF は S2-3 と 15 ページとも違うページ 0。preflight の後に入口が 11 枚ある |
| EPUB の XHTML（S2-3 と比べる） | B1 の EPUB・Kindle 用 EPUB とも、違うのは生成した画像の名前（写しの場所から作られる・§3.4 の無視する差）と `@today` の日付だけ |
| Kindle の変換の記録 | Enhanced Typesetting: Supported・Success・エラー 0・品質の問題 0。注意は W14016 の 1 件だけ |
| Kindle の中間生成物 | 36 ファイル・26,335 要素で、`computedstyle` は位置と大きさも含めて S2-3 と全部一致。`style` 属性（変換が書き出した指定）は前書き 41・後書き 13 要素で違い、どれも計算値が前と同じになる指定だった（段落の `text-align: justify`・箇条書きと索引語の `font-weight: normal`・章リードの `text-indent: 0`・幅を指定した図の `margin-right: auto`・切り抜いた画像の `border: none`。残りは宣言の並び順だけ） |
| Kindle Previewer の画面 | 中間生成物は KFX の描画が捨てる規則を映さないので（`kindle-css-compatibility-notes.md` §2）、前書き（Location 2・30・60・90・120・140）と後書き（9960・9975・9985）の 9 か所を S2-3 と S2-4 の KPF で撮って比べた。9 か所とも画素まで一致（差 0）。9 枚は互いに別の画面。撮った画面は `check/s2-4-b1/screens/` |
| `rake test`・`rake test:standard`・`rake test:layout`・rubocop | 4,302 件・4,302 件・7 件とも失敗 0（`rake test` のスキップ 1 は S2-3 と同じ。増えた 2 件は `entry_writer_test.rb`）。rubocop の違反 0 |

### 10.5 S3-1 `flat`（2026-11-15）

#### 作ったもの

- `lib/vivlio_starter/cli/css/`:
  - `selector.rb`（選択子の詳細度と選ぶ対象・Nokogiri で数えるための書き換え）・`cascade.rb`（宣言をロングハンドへ展開した列と、層ありと平らのそれぞれの強さ）。S2 の確かめの道具 `scripts/css_cascade_diff.rb` の中にあった処理を移した。道具はこの二つを使うようにし、書き換えの前後で、S2-2 のコミットと比べた出力（6,295 行）が一致することを確かめた。
  - `target_filter.rb`（§4.2 の 4）: EPUB と Kindle で `@page` の余白の箱と `@footnote` を落とし、書体を埋め込まないときは `@font-face` を落とす（keyfont と異体字の 1 字書体の面は残す）。Kindle では、さらに WebP の `url()` と data URI を含む宣言を落とす。
  - `inversion_check.rb`（§4.3 の (2)）: 層ありと平らとで勝つ側が入れ替わる宣言の組を挙げ、組み上がった HTML で「両方の選択子に当たる要素がある組」に絞る。
  - `bundle.rb`: 入口（`EntryWriter.render`・出力先の target 層つき）→ `Flattener.pieces` → 入れ子の規則の知らせ → `TargetFilter` → `InversionCheck`（`--log=debug` のときだけ）→ `Flattener.render` の順に呼び、EPUB と Kindle の消費者 dir の `styles/` へ書く。`VS_CSS_FORM=flat` のときは、PDF の入口のファイル（`.cache/vs/entry-*.css`）を平らな CSS で置き換える（余白の箱は落とさない）。
- `Flattener`（§4.2 の 3）: 規則の列（`pieces`）と 1 枚の CSS にする段（`render`）を分け、入口の中身を文字列で渡せるようにした。入れ子（`&`）の規則は crass が宣言の位置の `:error` として返すので、`Stylesheet::Rule#nested` の印を付けて列に残し、`render` は出力しない。`Bundle` が 🟡 で、ファイル名と選択子と、入れ子を開いた書き方を示す（種類をまたいで一度だけ）。今の同梱の CSS と生成物には、読めない規則は 0 件。
- `EntryWriter::TARGET_IMPORTS`: EPUB の束は `targets/epub.css`、Kindle の束は `targets/epub.css` と `targets/kindle.css` を target 層で読む。PDF の入口のファイルには書かない。`targets/` は S3-2 で作るので、今は読むファイルが無く、何も入らない。
- `EpubBuilder`: `sanitize_epub_css!`（組み上がった EPUB を開いて CSS を書き換える）と、それだけが使っていた定数・`drop_unresolvable_font_imports!`・`strip_unbundled_font_faces` を消した。`bundle_flat_css_for_epub!` は `Css::Bundle.write_epub!` を呼ぶ形にし、章の frontmatter の `stylesheet:` が足した CSS（層の外）も、同じフィルタを掛けて `styles/stylesheets/…` へ写して `link` を付け替える。パッケージには `stylesheets/` の CSS を運ばない（`localized_stylesheet?`）。
- `ImageOptimizer.prepare_theme_images!`: 入口を書き、`book-settings.css` などを生成した後で `Css::Bundle.write_pdf_entries!` を呼ぶ（`VS_CSS_FORM=flat` のときだけ働く）。生成の本体は `prepare_theme_assets!` に分けた。
- テスト: `css/target_filter_test.rb`（1.x の `sanitize_epub_css!` のテストが確かめていた 5 点を移した）・`css/bundle_test.rb`・`css_layer_test.rb` に層を外したときの検査と、検査が空振りしないことのテスト・`flattener_test.rb` に文字列から読む口と入れ子の 2 件。`epub_builder_sanitize_test.rb` と `epub_kindle_variant_glyph_test.rb` から、消した処理を呼ぶ 6 件を外した。
- `scripts/kfx_probe.rb`: 詳細度を測る 3 項目（`spec-control`・`spec-repeat`・`spec-not`）を足した（`v2-flat-cascade-consultation.md` §2.3）。

#### 仕様と違えたこと

1. **`InversionCheck` の判定は §4.3 (c) のとおりにしたが、(c) は実際に起きる組を見落とす。** (c) は「同じクラスを含むか、どちらもクラスを持たず同じ要素名」で、片方だけがクラスを持つ組（`.part-title` と `body`）を挙げない。片方がクラスを持たない組まで広げると、静的には 842 組になり、ほとんどは著者の指定（utilities 層）と詳細度の高い部品の組である。組み上がった HTML（本書の PDF 用 HTML・EPUB・Kindle 用 EPUB、B4 の EPUB）で絞ると 4 組で、utilities 層の組は 0 だった。そのうち部扉と目次の `break-before: recto`（pages 層）が、層ありの PDF では S2-1 から settings 層の `body { page-break-before: always }` に負けている（画素は変わっていない）。判定の広さと、平らな CSS で層の順を保つかは、設計の問いとして `v2-flat-cascade-consultation.md` で Fable に相談している。S3-1 は EPUB と Kindle の見た目を変えないので、答えを待たずに完了とした。**（2026-11-15 訂正）部扉と目次の 2 組は誤検出だった。** 本書の `page.chapter_pagebreak: any` では、settings 層の規則の選択子の並びが `.part-title` と `body.toc` も含み（`CHAPTER_PAGEBREAK_SELECTORS`）、層ありでも平らでも同じ settings の宣言が勝つ。組で比べたので、この第三の宣言を見なかった。1.x と結果は同じで、「S2-1 から settings が勝っている」も誤り（`v2-flat-cascade-consultation.md` §5.2）。判定は S3-2 で要素ごとの比べに変えた（§4.3）。
2. **同梱の CSS の静的な検査は、許可の表つきにした。** (c) で静的に挙がる 8 組（3 種類）は、用語集の印とコードの中の要素・`body` とコードの中の要素・表の題の段落と `.text-*` の組で、どれも実際の本では起きないか、1.x の EPUB と同じ結果になる。理由を書いて `css_layer_test.rb` の `ALLOWED_INVERSIONS` に載せた。`book-settings.css` は本の設定から生成されるので、テストの対象に含めない（ビルドの `--log=debug` が出す）。
3. **入口の中身は、ファイルでなく `EntryWriter.render` から作る。** `VS_CSS_FORM=flat` で PDF の入口のファイルを上書きしても、EPUB の束が影響を受けないようにするためである。
4. **frontmatter が足した CSS も平らにして写す。** §4.2 に無い。パッケージに `stylesheets/` の CSS を運ばなくしたので、写さないと参照が切れる。

#### 確かめた結果

写しの本は作業ツリーをそのまま写した。比べる相手は S2-4 の出力（`../vivlio-starter-v2-baseline/check/s2-4-b1/`・`runs/s2-4-b4/`）。S3-1 の出力は `runs/s3-1-*/`・`check/s3-1-*/`。

| 確かめ | 結果 |
| :--- | :--- |
| (a) `VS_CSS_FORM=flat` の PDF と層ありの PDF | B1 の閲覧用 PDF 283 ページ、違うページ 0。入口のファイルに `@layer`・`@import` が無いこと（平らな CSS が読まれたこと）を確かめた |
| 層ありの PDF（S2-4 と比べる） | B1 の閲覧用 PDF 283 ページ・印刷用 PDF 281 ページとも、違うページ 0 |
| (b) `InversionCheck` | 同梱の CSS の静的な検査は、許可の表の外の組 0。B1 の EPUB と Kindle 用 EPUB の HTML で絞った組は、Kindle だけの 2 種類（`body.vs-kindle strong` の色と `p:has(…) strong`・付録の `h2` の改ページ）。どちらも Kindle が S2 の前から平らな CSS で表示している勝ち負けで、S3-2 で target 層へ移すと層でも同じ側が勝つ |
| (c) EPUBCheck | B1 の EPUB・Kindle 用 EPUB とも、エラー・警告 0 |
| (d) EPUB の中の CSS | `styles/` の 8 枚だけで、`@layer`・`@import` が無い。`stylesheets/` の CSS の写し（43 枚）は入らなくなった |
| EPUB の CSS（S2-4 と比べる） | B1 の EPUB・Kindle 用 EPUB とも、8 枚の全部で規則の集合と並びが同じ（コメントと空白を外し、規則の単位で比べた）。S2-4 は組み上がった後に後片付けした CSS、S3-1 は生成の段で落とした CSS で、結果は同じになった。比べ方が差を拾うことは、クリーン EPUB と Kindle 用 EPUB の差（WebP と data URI の宣言の 2 規則）で確かめた |
| EPUB の XHTML と OPF（S2-4 と比べる） | XHTML は全部同じ（生成した画像の名前を除く）。OPF は、`stylesheets/` の CSS 43 枚の項目が無くなったことと、更新の日時だけが違う |
| Kindle の変換の記録 | Enhanced Typesetting: Supported・Success・エラー 0・品質の問題 0 |
| Kindle の中間生成物 | 36 ファイル・26,335 要素で、`computedstyle`・`style` 属性とも S2-4 と差 0 |
| Apple Books・Kindle Previewer の画面 | 撮っていない。EPUB の CSS と XHTML が S2-4 と規則の単位で同じで、Kindle の中間生成物も差 0 のため |
| B4（book_ai_web_starter の上巻）の EPUB | EPUBCheck のエラー・警告 0。CSS は `styles/` の 7 枚だけで、`@layer`・`@import` が無く、S2-4 と規則の単位で差 0。ビルドの 🟡 は S2-4 と同じ（原稿の画像の余白と索引の候補） |
| 単章のビルド（`vs build 21`）・`vs preflight` | どちらも 🔴 0。単章の PDF は S2-4 と 15 ページとも違うページ 0。preflight の後に入口が 11 枚ある |
| `rake test`・`rake test:standard`・`rake test:layout`・rubocop | 4,310 件・4,310 件・7 件とも失敗 0（`rake test` のスキップ 1 は S2-4 と同じ。足した 14 件・外した 6 件で、定義した数と実行された数が合う）。rubocop の違反 0 |

### 10.6 S3-2 規則の集約（2026-11-15）

#### 作ったもの

- `stylesheets/targets/`: `stylesheets/` の `body.vs-epub`・`body.vs-kindle` の 82 規則を移した（`epub.css` 21・`kindle.css` 38・`kindle-preface.css` 1・`kindle-index.css` 6・`kindle-glossary.css` 6・`kindle-colophon.css` 10）。選択子と宣言は変えず、元のファイルの読み込みの順とファイルの中の順を保ち、元の部品の名前の見出しで区切った。規則の直前に付いていたコメントは一緒に移し、元の場所に取り残された見出しのコメント（囲みの Kindle 用ラベル）も移した。「上の」「このファイル」のような位置で指すコメントは、元のファイルの名前で指すように直した。
- `EntryWriter::TARGET_IMPORTS`: ページの種類ごと・出力先ごとに、target 層で読むファイルの表にした。Kindle の束は、どの種類でも最後に `.cache/vs/book-settings-kindle.css` を読む。
- `BookSettingsCss.render_kindle`: Kindle にだけ当てる設定の規則（テーマ色のリテラル・`custom.css` で変えた色・話者の色・`page.section_pagebreak: false` の Kindle の節見出しの打ち消し）を `book-settings.css` から分け、`book-settings-kindle.css` に書く（§5）。`book-settings.css` には `vs-kindle` が残らない。
- PDF だけの 2 規則（`body:not(.vs-epub)`）は `:not()` を外して部品に残し、`targets/epub.css` に EPUB と Kindle の値（長い表の見出しの `white-space: normal`）と、印刷の媒体で控えの脚注を描かない規則を足した（§5）。
- `InversionCheck.inversions`（§4.3 の要素ごとの判定）。`pairs` は静的な判定として残し、`wide:` で (c) のクラスの条件を外せるようにした。`present`（組で絞る判定）は消した。
- ビルドの判定（`--log=debug`）を、HTML の書き換えが全部終わった後へ移した（`EpubBuilder#report_flat_css_inversions!` → `Css::Bundle.report_epub_inversions!`）。下の「仕様と違えたこと」の 3。
- 文書: `.claude/CLAUDE.md` の「Kindle degradation convention」・`notation-implementation-guide.md` §3・`kindle-css-compatibility-notes.md`（§4 の表の置き場・§5.1 の置き場の説明）・`stylesheets/_README.md`（target 層の行）。`v2-flat-cascade-consultation.md` §5.5 の仕様の文の直しを §2.1・§4.3・§4.5・§7.1 と `theme-contract-spec.md` §3.5 に入れ、相談文は archives へ送った。
- `scripts/css_computed_diff.rb`: EPUB と Kindle の HTML には、出力先の target 層を足した入口から平らにした CSS を当てる（それまでは target 層なしで、S3-1 以降の EPUB の CSS と違っていた）。`--after-settings DIR` で、後の側にだけ別の `book-settings*.css` を使える。
- テスト: `css_layer_test.rb` に、`targets/` の外に出力先の規則が無いこと（S3-2 の (a)。空振りしないことも確かめた）と、要素ごとの判定の 2 件・静的な判定の許可の表に 5 行。`entry_writer_test.rb` に target の表の 2 件、`bundle_test.rb` に debug のときだけ判定を出す 1 件、`book_settings_css_test.rb` に Kindle の規則を分けた 2 件。既存のテストは、読むファイルとメソッドの名前（`render` → `render_kindle`・`talk_class_rules` → `talk_kindle_rules`）を付け替えた。

#### 仕様と違えたこと

1. **target のファイルを、ページの種類ごとに分けた。** §3.1 は `epub.css`・`kindle.css` の 2 枚だった。奥付の `body.vs-kindle { … }` や前書きの `body.vs-kindle h1` は、1 枚に集めると本文のページにも当たる（§5）。
2. **`book-settings.css` の Kindle の規則も target 層へ移した。** §5 は `stylesheets/` の規則だけを移すと書いていた。移しただけでは、覆う側の生成の規則が settings 層に残って負け、計算値の比べで、Kindle の 21 文書・89 要素が変わった。囲みの枠（59 個）がテーマ色 `#15803d` から灰色 `#888` に、付録の節見出し（30 個）の `break-before` が `auto` から `page` になった。S3-3 のリテラル化までのつなぎで、そのときに消える。
3. **ビルドの判定は、S3-1 から Kindle の規則を見ていなかった。** 判定は CSS を平らにする段で走っており、その時点の HTML には `vs-kindle` の印も、EPUB 用に足す要素（合成画像の見出し・コードの行ブロックなど）も無い。S3-1 の記録の「Kindle だけの 2 種類」は、ビルドではなく、組み上がった HTML に当てた別の道具で数えたものだった。判定を書き換えの後へ移した。
4. **PDF だけの規則は移さず書き換えた。** §5 は「選択子を変えない」としていたが、target 層は PDF に入らないので、`:not(.vs-epub)` の規則は移せない（§5）。

#### 確かめた結果

写しの本は作業ツリーをそのまま写した（B4 は S3-1 の写しの CSS を作業ツリーのものに差し替えた）。比べる相手は S3-1 の出力（`../vivlio-starter-v2-baseline/check/s3-1-*/`・`runs/s3-1-*/`）。S3-2 の出力は `runs/s3-2-*/`・`check/s3-2-*/`。

| 確かめ | 結果 |
| :--- | :--- |
| (a) `targets/` の外の出力先の規則 | `stylesheets/`（`targets/` を除く）の規則の選択子に `vs-kindle`・`vs-epub` は 0（テストで確かめる）。コメントの中の 4 か所も、ファイルの名前で指すように直した。同梱のテーマはまだ無い |
| 計算値（`css_computed_diff.rb`。S3-1 の B1 の HTML に、`HEAD` と作業ツリーの CSS を当てる） | EPUB・Kindle 用 EPUB・PDF 用の 117 文書、312 組（媒体 2 × PDF は層ありと平らの 2 形）で、違う要素 0。上の 2 を直す前は、Kindle の 21 文書・89 要素で、囲みの枠の色と付録の節見出しの改ページが違っていた。B4 の EPUB（28 文書・56 組）も違う要素 0 |
| (b) PDF の画素（S3-1 と比べる） | B1 の閲覧用 283 ページ・印刷用 281 ページとも、違うページ 0 |
| (c) Kindle 用 EPUB の `body.vs-kindle` の規則 | 選択子を 1 つずつにほどいて「ファイル・@media・選択子・宣言」で比べ、前後とも 833 件で差 0。`vs-epub` の規則は、PDF だけの 2 規則の書き換えと、足した 2 規則の分だけ違う（意図したもの）。クリーン EPUB の CSS は、Kindle の規則が入らなくなり 3,518 件から 2,729 件になった |
| (d) 要素ごとの判定（`--log=debug`） | B1 の EPUB と Kindle 用 EPUB、B4 の EPUB の全部の種類で 0 組（ビルドの判定は 3 を直した後に B4 で確かめた。B1 は直す前のビルドだったので、組み上がった HTML に同じ判定を当てた）。HTML に当てると Kindle の章で 1 組残る: `body.vs-kindle strong { color }`（`book-settings-kindle.css`）と `p:has(> strong:only-child):has(+ table) strong`（parts）。KFX は `:has()` の規則を捨てるので画面は設定の色で、S3-3 で Kindle の CSS から `:has()` の規則を落とすと消える（§4.4）。層の中の `!important` は `book-settings-kindle.css` の h4 の印の 1 規則（S3-3 で消える） |
| EPUBCheck | B1 の EPUB・Kindle 用 EPUB、B4 の EPUB とも、エラー・警告 0 |
| Kindle の変換 | Enhanced Typesetting: Supported・Success・エラー 0・品質の問題 0 |
| Kindle の中間生成物 | 36 ファイル・26,335 要素で、`computedstyle` は S3-1 と差 0。`style` 属性は 14 章の表の見出し 4 つに `white-space:normal` が増えた（足した規則が書き出された。計算値は前と同じ `normal`） |
| B4 のビルド | 🟡 は S3-1 と同じ（原稿の画像の余白と索引の候補） |
| 単章のビルド（`vs build 21`）・`vs preflight` | どちらも 🔴 0。単章の PDF は S3-1 と 15 ページとも違うページ 0。preflight の後に入口が 11 枚と `book-settings.css`・`book-settings-kindle.css` がある |
| Apple Books・Kindle Previewer の画面 | 撮っていない。Kindle の中間生成物の `computedstyle` と、EPUB の計算値が S3-1 と差 0 のため |
| `rake test`・`rake test:standard`・`rake test:layout`・rubocop | 4,317 件・4,317 件・7 件とも失敗 0（`rake test` のスキップ 1 は S3-1 と同じ。足した 7 件で、定義した数と実行された数が合う）。rubocop の違反 0 |
| 雛形の同期 | `ruby scripts/copy_to_scaffold.rb` で `lib/project_scaffold/stylesheets/` へ写した（`targets/` を含む） |

### 10.7 S3-3a `flat_literal`（2026-11-15）

S3-3 は二つの段に分けた（§8 の注）。S3-3a は §4.4 のリテラル化と、`BookSettingsCss` の Kindle 用の生成の撤去。

#### 作ったもの

- `lib/vivlio_starter/cli/css/literal_resolver.rb`（§4.4）: ページの種類ごとの変数の表（`:root`・`html`・`body`・`body.<クラス>`。`body` の定義が勝ち、同じ段の中は `!important`・詳細度・順）で `var()` を解き、`calc()`（単位のそろった加減と数との乗除。中の `clamp()`・`min()`・`max()` も単位がそろえば計算する）と `color-mix(in srgb …)` を計算し、`:is()`・`:where()` を並べた選択子に、`:not(:is(a, b))` を `:not(a):not(b)` に展開し、`:has()` の選択子を落とす。深い要素の上・ページごとのクラス（`chapter-first`）の下・HTML の `style` 属性で定義された変数を読む宣言は落とす。値に解くのは target 層・settings 層・層の外だけ（下の「仕様と違えたこと」の 1）。
- `Css::Bundle`: Kindle の束でリテラル化を呼ぶ（`literalize`・`kindle_scope`）。変数の表の範囲は、その種類を読む HTML に共通の `body` のクラス（`HtmlContract` のページの種類・組方向・レイアウト・テーマのオプション・出力先の分類）に `vs-epub`・`vs-kindle` を足したもの。著者の CSS（`custom.css`・章が足した CSS）で解けなかった宣言だけを 🟡 で、場所と直し方を添えて知らせる。章が足した CSS は、本文の束の変数も表に入れて解く。要素ごとの判定（`--log=debug`）は、リテラル化した規則で行う。`Selector.expand_matches` を足した。
- `BookSettingsCss`: `render_kindle` と、それが呼ぶ 20 のメソッドと定数（`kindle_accent_rules`・`kindle_custom_color_rules`・`h4_marker_kindle_rule`・`talk_kindle_rules`・`section_pagebreak_kindle_rule` など）を消した。`book-settings-kindle.css` は作らず、`EntryWriter` も読まない。`page.section_pagebreak: false` のときは `:root` に `--section-break-before`・`--section-page-break-before` を書き、`targets/kindle.css` の簡素な節見出しが読む。話者の色は `.talk-c-<key> .talk-name, .talk-c-<key> .talk-sep, .talk-item.talk-c-<key> strong { color: var(--talk-c-<key>) }` を書く（下の 3）。
- `stylesheets/targets/kindle*.css`: リテラルの色（簡素な見出しの `#b8860b`・前書きの `#4f46e5`・索引・用語集・奥付の `#333`）を、部品と同じ変数（`--heading-accent`・`--color-preface-accent`・`--theme-accent`）に書き直した。`book-settings-kindle.css` が後から覆っていた色は、同じ選択子・同じ値になる変数の規則として入れた（強調・下線・h3 と h4 の印・囲みの枠とラベル・コラムの地・前書きの線とリンク・用語集の帯と h4）。
- テスト: `css/literal_resolver_test.rb`（20 件。解き方の決まり 12 件と、同梱の `stylesheets/` から Kindle の束を組んでテーマ色・付録の色・前書きの色・h4 の印・節の改ページ・custom.css の色が届くことを確かめる 8 件。1.x の `render_kindle` のテストの目的を引き継いだ）。`book_settings_css_test.rb` から消したメソッドのテスト 13 件を外し、節の改ページの変数の 1 件を足し、話者の色のテストを直した。`epub_kindle_layout_test.rb` の「Kindle の規則に `:is()`・`var()` を使わない」を「`targets/` の Kindle の規則が全部解ける」に替えた（解けない変数を書くと検出することを確かめた）。`css_layer_test.rb` は Kindle の束をリテラル化して静的な判定を行い、`!important` の検査に h4 の印の 1 行の許可を足した。`entry_writer_test.rb`・`epub_builder_test.rb` を直した。
- `scripts/css_computed_diff.rb`: Kindle の HTML には、その版に `LiteralResolver` があればリテラル化した CSS を当てる。ページの種類の判定の誤りを直した（下の「確かめた結果」の注）。
- 文書: `.claude/CLAUDE.md` の「Kindle degradation convention」・`notation-implementation-guide.md` §3・`kindle-css-compatibility-notes.md`（§2.1 に前処理も `var()` を捨てること、§5.1 の書き方と置き場）。

#### 仕様と違えたこと

1. **値に解くのを target 層・settings 層・層の外に限った（ユーザー決定）。** はじめは §4.4 のとおり全部の層を解いた。Kindle Previewer の前処理も `var()` を含む宣言を捨てていたため、部品の層の `var()`・`calc()` の宣言（章の CSS で 159）は S3-2 まで Kindle に届いておらず、解くと中間生成物で 26,335 要素のうち 26,310 の値が変わった（本文が 16px から 10.5pt＝14px に、行送り・字下げ・余白も PDF の値に）。下の層の `var()` などを含む宣言と `:is()`・`:where()`・`:has()` を含む規則は、今の KFX と同じく落とす。部品の値を Kindle に届けるのは S3-4 に回した（§4.4 の「解く層」・§8）。
2. **変数の定義は、値を解いて残した。** §4.4 は定義の扱いを決めていない。はじめは出力しなかったが、Techbook が HTML に差し込む `<style>` の `pre { font-family: var(--font-code) … !important }` が解けなくなり、Chromium で組むとコードが明朝になった。定義は KFX が読まないので害が無い。
3. **話者の色は、settings 層の規則で `:root` の変数を読ませた。** `--talk-accent` は話者の要素の上で定義する変数で、§4.4 の決まりでは解けない（宣言を落とす）。1.x は `talk_kindle_rules` が Kindle だけに焼いていた。`.talk-name` などの色は PDF でも `--talk-accent`（＝`--talk-c-<key>`）なので、同じ値の規則を全出力に書いた（PDF・クリーン EPUB の計算値は差 0）。
4. **`targets/kindle.css` に `!important` を 1 か所残した。** h4 の印。Techbook の `<style>` の `content: "" !important` に勝つためで、1.x の `book-settings-kindle.css` と同じ。target 層は PDF の束に入らず平らな CSS でだけ読まれるので、層の中の `!important` の逆転は起きない。`css_layer_test.rb` の許可の表に理由つきで載せた。
5. **Kindle の色は 1.x と同じ値を保った。PDF と食い違う箇所が残る。** 付録の `.note`・`.notice` の枠は Kindle ではテーマ色（PDF は付録の色）、付録の `.tip`・`.memo`・`.column` のラベルは Kindle では付録の色（PDF のタブはテーマ色）。見た目の変更なので、作りの入れ替えと分けた。**（2026-11-15 追記）ユーザーの判断で、PDF でも Kindle でも、付録のページはテーマ色で塗るものを全部、付録の色（`theme.appendix_color`。無ければテーマ色）で塗ることにした。1.x の不具合として改善案 #132 に書き、S3-3a の後のコミットで直した**（`pages/appendix.css` の割り当てを広げ、`book-settings.css` が `--color-strong`・`--color-em-underline` を書き直すのをやめた。PDF の付録のページの画素が変わる）。
6. **custom.css の色のうち 3 つが Kindle に届かなくなった。** 1.x の `kindle_custom_color_rules` は、custom.css で変えたときだけ `body.vs-kindle a`（`--color-link`）・`.column h5`（`--color-mark`）・`.diagram` の枠（`--color-border-weak`）の規則を書いていた。2.0 では部品の層を解かないので、これらは届かない。Kindle の規則を足して届けると、custom.css を書いていない本でも Kindle の既定の見た目が変わる（リンクが黒・`.column h5` がテーマ色・`.diagram` の枠が #888 から #ddd）。S3-4 で部品の層を解くと届く。**（2026-11-15 ユーザーの判断）S3-4 で届ける**（S3-4 の注）。
7. **§9 の論点 1（`transparent` との混色）は落とすことにした**（§9 の表）。

#### 確かめた結果

写しの本は作業ツリーをそのまま写した。比べる相手は S3-2 の出力（`../vivlio-starter-v2-baseline/check/s3-2-b1/`）。S3-3a の出力は `runs/s3-3a-*`・`check/s3-3a-*`。

| 確かめ | 結果 |
| :--- | :--- |
| (a) Kindle 用の EPUB の CSS | `styles/` の 8 枚とも、`var(`・`calc(`・`color-mix(`・`:is(`・`:where(`・`:has(`・`@layer`・`@import` が 0 |
| (b) Kindle の変換 | Enhanced Typesetting: Supported・Success・エラー 0・品質の問題 0 |
| (c) Kindle の中間生成物 | 36 ファイル・26,335 要素で、`computedstyle`・`style` 属性とも S3-2 と差 0 |
| (d)(e) 色を変えた写し（`theme.color: red`・custom.css の `:root` で `--color-strong: #1a73e8`・`--color-column-border: #7c3aed`） | 中間生成物で、`strong` 319 個がすべて #1a73e8、`.memo` の枠 18 個が #7c3aed、`.tip` の枠 6 個が赤（#dc2626）、コラムの地 6 個が赤と白の混色（#fadede）。Kindle 用の EPUB の CSS で、付録の簡素な見出しは付録の色（cyan）、前書きの下線は前書きの色（teal）、索引の下線と h4 の印は赤。変換は Supported・エラー 0 |
| PDF の画素（S3-2 と比べる） | 閲覧用 283 ページ・印刷用 281 ページとも、違うページ 0 |
| クリーン EPUB の CSS（S3-2 と規則の単位で比べる） | 8 枚とも、増えたのは節の改ページの変数の `:root` と話者の色の 4 規則だけ。計算値（`css_computed_diff.rb`。S3-2 の B1 の HTML に `HEAD` と作業ツリーの CSS を当てる）は EPUB・PDF とも差 0。B4 の EPUB（28 文書・56 組）も差 0 |
| EPUBCheck | EPUB・Kindle 用 EPUB とも、エラー・警告 0 |
| B1 のビルド | 🔴 0・🟡 0 |
| 単章のビルド（`vs build 21`）・`vs preflight` | どちらも 🔴 0。単章の PDF は S3-2 と 15 ページとも違うページ 0。preflight の後に入口が 11 枚と `book-settings.css` があり、`book-settings-kindle.css` は無い |
| `rake test`・`rake test:standard`・`rake test:layout`・rubocop | 4,325 件・4,325 件・7 件とも失敗 0（`rake test` のスキップ 1 は S3-2 と同じ。足した 21 件・外した 13 件で、4,317 から定義した数と実行された数が合う）。rubocop の違反 0 |
| Kindle Previewer の画面 | 撮っていない。中間生成物の `computedstyle`・`style` が S3-2 と差 0 のため |
| 雛形の同期 | `ruby scripts/copy_to_scaffold.rb` で `lib/project_scaffold/stylesheets/` へ写した（`test:layout` の後） |

- **`css_computed_diff.rb` は S3-2 から、どの HTML も章の CSS で組んでいた。** S3-2 で `flat/` のファイル名に出力先を付けた（`kindle-chapter.css`）とき、ページの種類の一覧をファイル名から作る処理を直さなかった。S3-2 の計算値の比べ（§10.6）は、章以外のページを章の CSS で比べたものになる。S3-2 の Kindle の中間生成物の比べ（差 0）と規則の単位の比べは、この道具を使っていないので影響しない。今回の比べは直した後の道具で行った。

### 10.8 付録の色をそろえる（2026-11-15・改善案 #132）

S3-3a の確かめで、付録のページの塗り分けが PDF と Kindle の両方で混ざっていることが分かった（§10.7 の「仕様と違えたこと」の 5）。ユーザーの判断で、付録のページはテーマ色で塗るものを全部、付録の色（`theme.appendix_color`。無ければテーマ色）で塗る。1.x の不具合として改善案 #132 に書いた。

#### 作ったもの

- `pages/appendix.css`: `:root` で、`--heading-accent`・`--color-mark` に加えて `--color-strong`・`--color-em-underline`・`--color-column-border`・`--color-column-bg` を付録の色にする。`--theme-accent` を直に読む `.tip` の枠とタブ、会話の既定の色（`.talk` の `--talk-accent`）は、部品と同じ選択子で付録の色にする（pages 層なので、層ありでも平らでも勝つ）。
- `BookSettingsCss#theme_declarations`: `--color-strong`・`--color-em-underline` を書かない。`tokens.css` の既定と同じ値を settings 層で書き直していたため、付録の割り当てを打ち消していた。テーマの指定も打ち消すことになる。
- `targets/kindle.css`: 付録の `.note`・`.notice` をテーマ色に戻す規則と、付録のラベルを付録の色にする規則を消し、`.tip` の枠とラベルを付録の色にする規則（`body.appendix.vs-kindle .tip`）だけを足した。ほかは同じ変数で書いてあるので、付録の束で付録の色に解ける。
- テスト: `literal_resolver_test.rb` の付録の 1 件を、付録の強調・囲みの枠・地・ラベルが付録の色になり、章は変わらないことを確かめる形にした。`book_settings_css_test.rb` は、強調の色を書かず `tokens.css` の既定に任せることを確かめる形にした。

#### 確かめた結果

S3-3a の出力（`check/s3-3a-b1/`）と比べた。出力は `runs/apx-b1`・`check/apx-b1`。

| 確かめ | 結果 |
| :--- | :--- |
| PDF の画素 | 閲覧用 283 ページのうち 20 ページ（印刷用も同じ 20 ページ）が違い、どれも付録 C〜F のページ。目で見て、強調とコラムの枠・タブ・地がテーマ色から付録の色に変わっただけで、組み方は同じ |
| Kindle の中間生成物 | `computedstyle` の差 0。`style` の差 61 件は、付録の 3 ファイル（92・93・95）の `strong` の色と囲みの枠・地の色が緑から付録の色（cyan）に変わったものだけ |
| `rake test`・`rake test:standard`・`rake test:layout` | 4,325 件・4,325 件・7 件とも失敗 0（件数は S3-3a と同じ）。rubocop の違反 0。雛形を同期した |

### 10.9 S3-3b `custom.css` を平らな CSS でも勝たせる（2026-11-15）

§7.1 と `v2-flat-cascade-consultation.md` §5.7 の生成。S3-3 の完了の条件の (f)。

#### 作ったもの

- `lib/vivlio_starter/cli/css/author_priority.rb`（`Css::AuthorPriority`）: 組み上がった HTML の要素ごとに、層の外の宣言（`custom.css`・章の frontmatter が足した CSS）が当たる要素・ロングハンド・媒体・疑似要素の組で、当たる宣言の全部から層ありで勝つ宣言と平らな CSS で勝つ宣言を求める（§4.3 の要素ごとの判定と同じ比べ方。`InversionCheck` の `matched`・`in_media?`・`meaning` を使う）。層ありで勝つのが層の外の宣言で、平らな CSS では負けるとき、その宣言に `!important` を付ける。付けた結果、層の外の宣言どうしの勝ち負けが変わる要素があれば層ありで勝つ側にも付け、変わらなくなるまで繰り返す。付けた宣言が `!important` の宣言（著者が付けたもの・vs の h4 の印）に勝ってしまうときは付けるのをやめ、付けられない宣言として返す。読む CSS の組（章が足した CSS を読む章は、本文の束と足した CSS の 2 枚）ごとに判定し、付ける場所は「CSS の鍵・規則の位置・値の終わりの位置」で指す。
- `Css::Cascade::Decl#pos`: 規則の文字列の中で、宣言の値が終わる位置。crass の字句の位置は `@media` の中を読み直しても元の文字列の中の位置のままなので、そこへ ` !important` を差し込む。関数（`calc(…)`）は字句の位置を持たないので、中の最後の字句で求める。
- `Css::Bundle`: `write_epub!`・`write_epub_extra!` は、書いたパスと規則の列（`Sheet`）を返す。`prioritize_author_css!` が、その列と書き換えの終わった HTML で `AuthorPriority` を呼び、付けた CSS だけを書き直す。層の外の宣言が無ければ何もしない。付けられなかった宣言は 🟡 で、`custom.css` の行・原稿の場所・取り合う著者の `!important` の宣言を示す（vs の選択子は見せない）。`report_epub_inversions!` は、組み直さずに同じ列（付けた後のもの）で判定する。
- `EpubBuilder`: `bundle_flat_css_for_epub!` が `Sheet` の表（`styles/…` の href ごと）を返し、HTML の書き換え（Kindle 専用のものを含む）が全部終わった後で `prioritize_author_css_for_epub!` を呼ぶ。Kindle の異体字の 1 字書体（平らな CSS の末尾へ規則を足す）は、その後へ移した。`STYLES_HREF_PATTERN` は章が足した CSS の href も拾う。
- テスト: `css/author_priority_test.rb`（6 件: 負ける宣言にだけ付ける・custom.css が無いか負けなければ変えない・custom.css どうしの繰り返し・著者の `!important` と取り合うものは付けない・style 属性にも付ける・疑似要素と章が足した CSS）。`bundle_test.rb` に 4 件（書き直す・負けなければ書き直さない・🟡 の文言と場所・style 属性を直した HTML を書き直す）を足し、要素ごとの判定のテストを `Sheet` で呼ぶ形に直した。

#### 仕様と違えたこと

1. **`style` 属性に当たる宣言も付け、要素の `style` 属性の同じプロパティにも `!important` を付ける（2026-11-15 ユーザー決定）。** §5.7 は「付ける宣言が `style` 属性で同じプロパティを指定している要素にも当たるときは、付けずに 🟡」としていた。確かめ (f) で、Kindle の写真の並び（`book-card`・`img-text`・`sideimage-right`）を vs が表に組み替えるときに付ける `style="width: 100%…"` に `table { inline-size: 80% }` が当たり、章の束では、ふつうの表（`.long-table` の 3 個）にも付かなくなった。この表は PDF にも原稿にも無いので、🟡 の直し方は著者に打てない。`style` 属性の `!important` は CSS のどの `!important` にも勝つので、`style` 属性が勝つという PDF の勝ち負けをそのまま保てる。HTML の書き換えは EPUB と Kindle 用の HTML だけで、PDF には響かない。
2. **付けられない場合の 🟡 は、出力先ごとに出す。** §5.7 は「EPUB と Kindle では効かない」の一文としていた。EPUB と Kindle は別の枝で組み、片方だけで起きる（vs の h4 の印は Kindle だけ）ので、「Kindle では効きません」のように出力先の名前を出す。

#### 確かめた結果

比べる相手は S3-3a の後の出力（`../vivlio-starter-v2-baseline/check/apx-b1/`）。S3-3b の出力は `runs/s3-3b-*`・`check/s3-3b-*`。

| 確かめ | 結果 |
| :--- | :--- |
| `custom.css` が空の本（B1）の EPUB・Kindle 用 EPUB | `styles/` の CSS 8 枚とも、どちらも同一。XHTML の違いは OPF の日時と合成画像の名前のハッシュだけ |
| B1 の PDF の画素 | 閲覧用 283 ページ・印刷用 281 ページとも、違うページ 0 |
| B1 の Kindle の中間生成物 | 26,335 要素で、`computedstyle`・`style` とも差 0 |
| B1 のビルド | 🔴 0・🟡 0 |
| (f) `custom.css` に `h2 { margin-block-start: 2em; }` と `table { inline-size: 80%; }` を書いた写し（付録は簡素な見出し・`.long-table` は 7 ファイルにある）・EPUB | 組み上がった HTML に Chromium を当て（PDF は層ありの入口を print で、EPUB は平らな CSS を screen で）、EPUB に入るページの h2 175 個がすべて `margin-top` = 字の大きさの 2 倍で PDF と同じ。表 130 個のうち 127 個が親の内側の幅の 80% で PDF と同じ。残る 3 個は `.text-table` の表で、勝つ宣言はどちらも 80% だが、PDF は表を横並びの片側（中身で幅の決まる flex の列）に置くので Chromium では % が循環して幅 0 になる（EPUB は上下に積む）。`custom.css` が空の B1 では、表 41 個が PDF と食い違っていた |
| (f) Kindle の中間生成物 | h2 177 個の `style` がすべて `margin-top:2em`。表 136 個のうち 130 個が `width:80%`、6 個は vs が組み替えた写真の並びの表で `width:100%`（`style` 属性の値のまま） |
| (f) のビルド（`--log=debug`） | 🔴 0・🟡 0。EPUB・Kindle とも、要素ごとの判定で残る組は全部の種類で 0（直す前は Kindle の章の束に `.long-table table` の 1 組）。`!important` を付けたのは章・付録・索引の束で 5 か所（Kindle も 5 か所）と、Kindle の 2 ファイルの `style` 属性 |
| (f) の Kindle の変換 | Enhanced Typesetting: Supported・Success・エラー 0・品質の問題 0 |
| (f) の EPUBCheck | EPUB・Kindle 用 EPUB とも、エラー・警告 0 |
| `rake test`・`rake test:standard`・`rake test:layout`・rubocop | 4,335 件・4,335 件・7 件とも失敗 0（`rake test` のスキップ 1 は S3-3a と同じ。足した 10 件で、4,325 から定義した数と実行された数が合う）。rubocop の違反 0 |
| Kindle Previewer の画面 | 撮っていない。中間生成物の `style` に、付けた値（80%・2em）と `style` 属性の値（100%）がそのまま出ているため |
| 単章のビルド・`vs preflight` | 走らせていない。変えたのは EPUB と Kindle の枝だけで、単章のビルドと preflight は通らない |
| 雛形の同期 | 不要（`stylesheets/` を変えていない） |

### 10.10 S3-4 Kindle に部品の値を届ける（2026-11-15）

§4.4 の「解く層」と §8 の S3-4 の注。部品の層まで値に解き、S3-3a で Kindle に届かなくなった custom.css の 3 色も届ける。

#### 作ったもの

- `LiteralResolver`: 解く層を限る仕組み（`RESOLVED_LAYERS`・`UNSUPPORTED_SELECTOR`・`resolve` の `layers:`・落とした理由の `:lower_layer`）を消し、どの層の規則も解く。`Bundle.literalize` から、解かない層の件数の知らせを消した。
- `stylesheets/targets/kindle-tokens.css`（新規）: `body.vs-kindle` で、本文の字の大きさと行送り（`--base-font-size: 1em`・`--base-line-height: normal`）と、書体のトークン（`--font-main-text`・`--font-body` は `serif`、`--font-title`・`--font-header`・`--font-column`・`--font-folio` は `sans-serif`、`--font-code` は `monospace`）を書く。`EntryWriter::TARGET_FOUNDATION` で、Kindle のどの種類の束も target 層の最初に読む。
- `stylesheets/targets/kindle.css`: `.diagram` の枠を `#888` から `var(--color-border-weak)` に（太さは 1px のまま）。`body.vs-kindle .column { background }` は `parts/box.css` と同じ規則になったので消した。「Kindle では `var()` が消える」と書いていた注記（`kbd`・囲み・`.output`・`.terminal`）を、今の理由に直した。
- `--color-output-border`（2026-11-15 ユーザー判断）: 実行結果（`.output`）とテキストの図（`.diagram`）の枠の色を、custom.css で変えられる変数にした。`tokens.css` で `var(--color-border-weak)` と定義し、`parts/box.css` と `targets/kindle.css` の `.output`・`.diagram` が読む。PDF は変わらない。Kindle の `.output` の枠は `#888` の直書きから、PDF と同じ既定の `#ddd` になる（`.diagram` とそろう）。原稿の 46 章の変数の表と `theme-contract-spec.md` §5.2 に足した。
- 原稿の 46 章: 変数の表の `--color-figure-border` の「※ PDF・EPUB のみ」を外した。部品の層が届くようになり、Kindle でも画像に枠が付き、custom.css で変えた色も届く（Kindle 用の CSS で確かめた）。
- テスト: `literal_resolver_test.rb` の「解かない層は落とす」を「どの層も解く」に替え、本文の字の大きさ・行送り・書体が端末任せになること（custom.css の `:root` は届かず、`body.vs-kindle` は届く）と、custom.css の 3 色が届くことの 2 件を足した。コラムの地のテストは `parts/box.css` の規則を見るように直した。`entry_writer_test.rb` は Kindle の束の先頭に `kindle-tokens.css` があることを確かめる形にした。
- 文書: `.claude/CLAUDE.md` の「Kindle degradation convention」・`kindle-css-compatibility-notes.md`（§2.1 に S3-4 で変わったものと Location の注意、§5.1 に部品の値も届くこと）。

#### 仕様と違えたこと

1. **部品の寸法は打ち消さなかった。** §8 の注は「PDF 向けの値は `targets/kindle*.css` で打ち消すか em へ書き直す」としていた。全部の層を解いて中間生成物を比べると、見出し・前書き・奥付などの紙の寸法は `clamp(…, calc(var(--paper-scale) * …), …)` の形で、`calc()` の外の `clamp()` は解かない（§4.4 の「関数と選択子」）ので値が `clamp()` のまま残り、Kindle Previewer の前処理が宣言ごと捨てていた（`style` にも `computedstyle` にも出ない）。PDF 向けの値で Kindle に届くのは本文の字の大きさと行送りだけだったので、その 2 つをトークンで置き換えた。
2. **書体のトークンも置き換えた。** 部品の `font-family: var(--font-header)` などが届くと、Kindle Previewer は Mac に入っている HackGen を前書きの見出しの英字に使った（Noto Sans JP は Previewer から見えない）。Kindle には書体を埋め込まないので、書体の名前は読む端末に依存する。明朝・ゴシック・等幅の区別だけを総称の名前で渡す。
3. **層ごとに分けて組まなかった。** §8 の注は「層ごと・部品ごとに広げ」としていた。全部の層を解いた写しを一度組み、中間生成物の差を宣言の出どころ（層・ファイル・選択子）に対応づけて読んだ。届いた宣言は 217 で、差の出た種類は 46 と少なく、出どころごとに判断できたため。

#### 確かめた結果

写しの本は作業ツリーをそのまま写した。比べる相手は S3-3b の出力（`../vivlio-starter-v2-baseline/check/s3-3b-b1/`）。S3-4 の出力は `check/s3-4-b1`（四出力）・`check/s3-4-b1k`（書体のトークンを足した後の Kindle）・`check/s3-4-c`（custom.css で 3 色を変えた写し）。全部の層を解いただけの実験は `check/s3-4-x1`。

| 確かめ | 結果 |
| :--- | :--- |
| 広げた層の宣言が Kindle に届く | 部品・ページ・base 層の `var()` などを含む宣言のうち、新しく値に解けたのは 217。解けずに落ちるのは、要素の上で定義する変数（会話の `--talk-accent` など）・どこにも定義の無い変数（前書きの `--color-header` など。PDF でも同じく効かない）・`:has()` の選択子だけ。Kindle 用の EPUB の CSS 8 枚とも `var(`・`calc(`・`color-mix(`・`:is(`・`:where(`・`:has(`・`@layer`・`@import` が 0 |
| Kindle の中間生成物（S3-3b と比べる） | `computedstyle` の差は図のキャプション 86 個の字の大きさ（0.9em → 1em）だけ。`style` の差は 46 種類: 見出し 618 個が `sans-serif`・コード 4,709 個が `monospace`・本文のリンク 533 個が `#000`（`--color-link`）・用語のリンクの上付きの印がテーマ色・表と h4 が `1em`・図のキャプションが `parts/figure.css` の値（1em・本文の色）・図の枠（0.5mm・#ccc）・引用の線（2mm・#ddd）・用語集の見出しの線・テキストの図の枠が #888 → #ddd・中央寄せのブロックの `margin: auto`（`utilities/align.css` の `:is()` の規則が届いた）。本文の `html` の字の大きさと行送りは前と同じ（16px・`normal`） |
| Kindle Previewer の画面 | 前書き・章扉・節見出し・テキストの図・図の節・コラム（付録 F）・コード・付録の表・用語集・索引・奥付を撮り、崩れは無い。見出しが PDF と同じゴシックになり、コードの書体が端末の等幅になった。本文のリンクは、`style` が `#000` でも画面では Kindle の青で描かれる（custom.css で `--color-link` を変えると、その色で描かれる）。`scripts/kfx_probe.rb link` で確かめると、`#111` 以下の黒に近い色が Kindle の青になり、`#222` から指定どおりだった（`kindle-css-compatibility-notes.md` §2 の表） |
| custom.css の 3 色（`--color-link: #1a73e8`・`--color-mark: #7c3aed`・`--color-border-weak: #e11d74`。95 章の末尾に `.column` の h5 を足した写し） | 中間生成物で、本文と相互参照のリンク 445 個が #1a73e8、コラムの h5 が #7c3aed、テキストの図 9 個の枠が #e11d74。画面でも、リンク・h3 の印・コラムの h5・テキストの図の枠がその色で描かれる |
| Kindle の変換 | 3 つの写しとも Enhanced Typesetting: Supported・Success・エラー 0・品質の問題 0 |
| PDF の画素（S3-3b と比べる） | 閲覧用 283 ページ・印刷用 281 ページとも、違うページ 0 |
| クリーン EPUB の CSS | `styles/` の 8 枚とも S3-3b と同一 |
| EPUBCheck | EPUB・Kindle 用 EPUB とも、エラー・警告 0 |
| B1 のビルド（`--log=debug`） | 🔴 0・🟡 0。要素ごとの判定で残る組は、EPUB・Kindle の全部の種類で 0。層の中の `!important` は h4 の印の 1 規則（§10.7 の 4） |
