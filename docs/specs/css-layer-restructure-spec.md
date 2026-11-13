# スタイルシートの再編（層の順序・ファイルの分け方・EPUB と Kindle 用の平らな CSS の生成）

> 作成日: 2026-11-14
> ステータス: **設計済み・実装待ち**
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
| Kindle 用の規則 | `stylesheets/targets/kindle.css` に集める。色と寸法のリテラル化は生成が行う | §5 |
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
| `target` | 出力先ごとの規則（`body.vs-epub`・`body.vs-kindle`）。出力先の束にだけ入れる | `stylesheets/targets/`・テーマの `kindle.css` | vs・テーマ |
| （層の外） | `custom.css`、章の frontmatter で著者が足した CSS | `stylesheets/custom.css` | 著者 |

順序の理由:

- `theme` が `parts` と `pages` の上にあるのは、テーマが部品とページの見た目を変えられるようにするためである。層が上なら、詳細度が低い規則でも勝つ。テーマは詳細度を上げたり `!important` を使ったりせずに済む。
- `utilities` が `theme` の上にあるのは、著者が原稿に書いた `{.text-right}` や `@pagebreak` が、テーマの `p { text-align: justify; }` のような規則に負けないようにするためである。
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
    epub.css                 body.vs-epub の規則（28 か所）
    kindle.css               body.vs-kindle の規則（124 か所）
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
   - `kindle`: さらに、WebP を指す `url()` を含む宣言を落とす。`target` 層に `targets/kindle.css` とテーマの `kindle.css` を入れる。
   - `pdf` 用の束には `target` 層を入れない。
5. **リテラル化**（§4.4）。

出力は、出力先のワークスペース（`epub/`・`kindle/`）の中に、ページの種類ごとに 1 枚（`styles/chapter.css` など）とする。出力先の変換（L4）の最初の段が、HTML の `link` をこの 1 枚に付け替える。今の `bundle_book_settings_for_epub!` は、この仕組みに置き換わって無くなる。

### 4.3 層を外しても結果が変わらないことの保証

層を外して層の順に並べると、同じ詳細度の規則どうしでは、層ありと同じ結果になる（後に書いた規則が勝つ）。結果が変わるのは、**下の層の規則のほうが詳細度が高く、同じ要素の同じプロパティを、上の層の規則と取り合う**場合だけである。層ありでは上の層が勝ち、平らにすると詳細度の高い下の層が勝つ。

二つの方法で確かめる。

**(1) 画素の比較（正の確かめ）**

開発用の環境変数 `VS_CSS_FORM=flat` を用意し、PDF の出力先に平らな CSS を読ませる（余白の箱を落とすフィルタは掛けない）。同じ本を `layered` と `flat` で組み、全ページの画素を比べる。一致すれば、PDF で使われる規則については、層を外しても結果が変わらないと言える。`VS_CSS_FORM` は確かめのためだけのもので、文書には載せない（`VIVLIO_BUILD_PARALLEL` と同じ扱い）。

**(2) 静的な検査（`Css::InversionCheck`）**

PDF で使われない規則（`target` 層）と、本書で使っていない記法の規則は、(1) では確かめられない。そこで、結果が変わりうる規則の組を静的に挙げる。

- 挙げる条件: 二つの宣言が、(a) 同じプロパティで、(b) 下の層の規則の詳細度が上の層の規則より高く、(c) 選ぶ対象が重なりうる。(c) は、選択子の最後の複合選択子（対象の要素を表す部分）が、同じクラスを含むか、どちらもクラスを持たず同じ要素名である、で判定する。
- 絞り込み: ビルドのときは、挙がった組について、出力先の HTML に「両方の選択子に当たる要素」があるかを Nokogiri で調べ、ある組だけを報告する。疑似要素・疑似クラスは外して調べる。
- 扱い: 同梱の CSS とテーマでは、`css_layer_test.rb` が組の数が 0 であることを確かめる（直せない組は、理由を書いた許可の表に載せる）。著者が入れたテーマでは、`vs theme:check` と `vs build` が 🟡 で、どの規則とどの規則かを示す。
- 直し方: 下の層の規則の詳細度を下げる、上の層の規則の選択子を下の層と同じ形にする、のどちらか。

### 4.4 リテラル化（`flat_literal`）

KFX は `var()`・`calc()`・`color-mix()` を解さず、`:is()` を含む規則を捨てる（`kindle-css-compatibility-notes.md` §2）。Kindle 用の CSS では、これらを生成のときに解く。

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

落とした宣言と規則は、変数と同じに報告する。

**今の仕組みとの入れ替え**

`BookSettingsCss` の `kindle_accent_rules`・`kindle_custom_color_rules`・`h4_marker_kindle_rule`（`body.vs-kindle` の規則を、テーマ色をリテラルにして書き出す 8 メソッド）は、リテラル化が同じ結果を出すことを確かめてから消す（§8 の S3-3）。`custom.css` の色を Kindle に渡す仕組みも、`custom.css` が平らな CSS に入って変数が解かれるので、別の処理が要らなくなる。

### 4.5 報告のしかた

| 相手 | 出し方 |
| :--- | :--- |
| vs の開発（同梱の CSS とテーマ） | テストで落とす（`css_layer_test.rb`）。ビルドでは `--log=debug` だけ |
| テーマを作る人 | `vs theme:check` が 🟡 で、ファイル名と行番号、何が Kindle に届かないか、どう書き直すかを示す |
| 著者（`custom.css`） | `vs build` で `targets` に `kindle` があるときだけ、Kindle に届かない宣言を 🟡 で示す（今の `warn_unconvertible_custom_colors` と同じ場面） |

---

## 5. Kindle と EPUB の規則を集める

- `body.vs-kindle` の規則（10 ファイル・124 か所）を `stylesheets/targets/kindle.css` へ、`body.vs-epub` の規則（4 ファイル・28 か所）を `stylesheets/targets/epub.css` へ移す。
- 移すときは、選択子（`body.vs-kindle` の前置きを含む）と宣言を変えず、元のファイルの読み込みの順と、ファイルの中の順を保つ。これで、Kindle の束の中での結果が変わらない。
- `targets/kindle.css` の中は、元の部品の名前の見出しで区切る（囲み・並べ方・コード・索引・用語集・奥付・前書き・見出し）。
- 移した後、リテラルの色を直書きしている規則のうち、テーマ色から決まるもの（前書きの藍色の直書きなど）は、`var(--book-…)` に書き直す。リテラル化が解くので、テーマ色に追従するようになる（今は `BookSettingsCss` が後から上書きして追従させている）。この書き直しは S3-3 で行う。
- `targets/epub.css` は、クリーン EPUB と Kindle の両方の束に入る（Kindle の `body` にも `vs-epub` が付くため。今と同じ）。
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
| S2-4 前書き・後書きをそろえる | §3.3 | 前書きと後書きのページを含め、画素が一致する。字間・段落・引用の規則が 1 か所にある |

- S2 の間、EPUB と Kindle は「入口の `@import` を解いて、今と同じ順に並べた CSS」を読ませる（S3 の `Flattener` の読み込みと並べ替えを、先に作って使う）。S2-1 の時点で `Css::Stylesheet` と `Css::Flattener` の 1・2 が要る。
- 確かめ方: 小段階ごとに、本書の写しを `targets: pdf, print_pdf, epub, kindle` で組み、S0 の基準と比べる。PDF は全ページの画素。EPUB と Kindle は S3 まで「Kindle Previewer の画面で、章扉・囲み・コード・索引・前書きの 5 か所を見比べて同じ」とする。
- 単章のビルド（`vs build 21`）と `vs preflight` が通ることも確かめる（入口の生成が、どのモードでも走ること）。
- `theme.style: simple` の写しと、`page.section_pagebreak: true`・`chapter_pagebreak: recto` の写しでも、PDF の画素を比べる（`settings` 層の規則が、設定の組み合わせで正しく勝つこと）。

### S3 平らな CSS と、出力先の規則の集約

| 小段階 | 作るもの | 完了の条件 |
| :--- | :--- | :--- |
| S3-1 `flat` | `Css::Flattener` の 3・`TargetFilter`・`InversionCheck`・`Bundle`・`VS_CSS_FORM`。`sanitize_epub_css!` と `bundle_book_settings_for_epub!` を無くす | (a) 本書を `VS_CSS_FORM=flat` で組んだ PDF の全ページの画素が、`layered` と一致する。(b) `InversionCheck` の報告が 0（または許可の表に理由つきで載っている）。(c) クリーン EPUB が EPUBCheck でエラー・警告とも 0 で、Apple Books の画面が S0 の基準と見比べて同じ。(d) EPUB の中の CSS に `@layer` と `@import` が無い |
| S3-2 規則の集約 | §5 の移動（`targets/epub.css`・`targets/kindle.css`） | (a) `stylesheets/`（`targets/` を除く）と同梱のテーマに `vs-kindle`・`vs-epub` が無い。(b) PDF の画素が一致する。(c) Kindle 用の EPUB の中の CSS で、`body.vs-kindle` の規則の数と中身が、移動の前と同じ（規則を選択子で並べて差分を取る） |
| S3-3 `flat_literal` | `LiteralResolver`。`BookSettingsCss` の `kindle_*` の 8 メソッドと `custom.css` の色の書き出しを無くす。§5 のリテラルの直書きを変数に戻す | (a) Kindle 用の EPUB の中の CSS に `var(`・`calc(`・`color-mix(`・`:is(`・`:where(`・`:has(`・`@layer` が無い。(b) KPF の変換で Enhanced Typesetting が Supported・エラー 0。(c) Kindle Previewer の変換の中間生成物（`preprocessed/*.xhtml` の `computedstyle`。`kindle-css-compatibility-notes.md` §2.1 の 3）を、変更の前後で比べ、色と寸法の値が同じ。(d) `theme.color` を別の色に変えた写しで、Kindle の囲み・見出し・前書きの色が追従する。(e) `custom.css` で色の変数を変えた写しで、Kindle に色が届く |

- (a) の `VS_CSS_FORM=flat_literal` での PDF の比較は、参考にとどめる。`calc()` の中の `em` をリテラルにすると、箱の幅が約 1/16 px 変わる箇所がある（`vivliostyle-css-pitfalls-notes.md` §2.18）ので、画素は一致しない。比べるなら、行の位置（`pdftotext -bbox` の行の座標が 0.05pt 以内）で比べる。
- S3 の完了のときに、`.claude/CLAUDE.md` の「Kindle degradation convention」と `notation-implementation-guide.md` §3 を直し、`kindle-css-compatibility-notes.md` §5.1 に、規則の置き場が変わったことを書く。

---

## 9. 論点（未決）

| # | 論点 | 答えが要る時点 | 設計での扱い |
| :--- | :--- | :--- | :--- |
| 1 | `transparent` との `color-mix()`（前書きの見出しの背景）を、KFX が解する形で書けるか | S3-3 | 書けなければ落とす。今の Kindle は、この背景を `targets` の規則で単色に置き換えているので、結果は今と同じになる見込み |
| 2 | Kindle 用に、論理方向のプロパティを物理方向へ書き直す処理を `LiteralResolver` に持たせるか | S8 | 2.0 では `targets/kindle.css` に手で書く。縦書きの Kindle で論理方向が正しく解されるかを S8 で確かめ、崩れるなら生成で書き直す |
| 3 | 章の frontmatter で著者が足した CSS（層の外になり、`custom.css` と同じ強さになる） | S2-1 | 今より強くなる。使っている本は少ないと見て、移行の手引きに 1 行書く |
