# S3 を終えて決めること（Fable への相談）

> 作成日: 2026-11-15
> ステータス: **相談中**
> 出自: S3（`css-layer-restructure-spec.md` §8・§10.5〜§10.10）の完了。S3 の実装で仕様と違えたことのうち、S4・S6 の仕様に響くもの

Fable のセッションに、次の「---」より下をそのまま渡す。

---

2.0 の S3（平らな CSS の生成と、出力先の規則の集約）が終わりました。S3 の実装で仕様と違えたことの中に、S4（出力先の宣言と `epub_builder.rb` の分割）と S6（テーマの仕組み）の仕様の前提を変えるものがあります。S4 に着手する前に、次の 5 つを判断してください。

コードの書き換えはしないでください。読む資料は次のとおりです。

1. `css-layer-restructure-spec.md` §0（決定の一覧）・§4.4（リテラル化）・§10.5〜§10.10（S3 の実装記録。各節の「仕様と違えたこと」だけでも足りる）
2. `theme-contract-spec.md` §3.1・§3.2・§3.5・§5.2
3. `v2-architecture-spec.md` §4.3・§4.4・§8 の S4
4. `v2-migration-plan.md` §3.2・§4.1・§7 の論点 6
5. `kindle-css-compatibility-notes.md` §2.1（Kindle Previewer の中間生成物の読み方と、S3-4 で変わったもの）

## 1. S3 で起きたこと（要点）

| 小段階 | 結果 | 仕様と違えたことのうち、後の段階に響くもの |
| :--- | :--- | :--- |
| S3-1 `flat` | EPUB と Kindle が層を外した CSS を読む。`sanitize_epub_css!` を消した | 層の順が保てない組の扱いを相談し、案 A（詳細度で決まると割り切る）に決まった（`v2-flat-cascade-consultation.md`） |
| S3-2 規則の集約 | `body.vs-epub`・`body.vs-kindle` の 82 規則を `stylesheets/targets/` へ移した | target のファイルを**ページの種類ごとに分けた**（`epub.css`・`kindle.css` に加えて `kindle-preface.css`・`kindle-index.css`・`kindle-glossary.css`・`kindle-colophon.css`）。奥付の `body.vs-kindle { … }` のような規則は、1 枚に集めると本文のページにも当たるため |
| S3-3a `flat_literal` | `LiteralResolver` が `var()`・`calc()`・`color-mix()`・`:is()` を値に解く。`book-settings-kindle.css` を無くした | 変数の定義は値を解いて残す（Techbook が差し込む `<style>` が `var()` を読むため） |
| S3-3b `custom.css` | 層ありで勝ち、平らな CSS で負ける `custom.css` の宣言に、生成が `!important` を付ける | **HTML の書き換えが全部終わった後に、本の全部の HTML と CSS を見て CSS と HTML の両方を書き直す段**になった（`style` 属性にも `!important` を付ける。ユーザー決定）。`Css::Bundle.prioritize_author_css!` |
| S3-4 部品の値を Kindle へ | どの層の宣言も値に解いて Kindle に届ける | (1) 本文の字の大きさ・行送り・書体を**端末任せ**にした（`targets/kindle-tokens.css`。`body.vs-kindle` で `--base-font-size: 1em`・`--base-line-height: normal`、書体のトークンは `serif`・`sans-serif`・`monospace`）。(2) 紙の寸法（`clamp(…, calc(var(--paper-scale) * …), …)`）は解かず、Kindle では宣言ごと落ちる。Kindle の寸法は `targets/kindle*.css` の em の規則のまま |

数字は §10 の各節にある。S3-4 の後の B1 は、PDF の画素が S3-3b と差 0、EPUB の CSS が S3-3b と同一、Kindle は変換が Supported・エラー 0、要素ごとの判定の残りが 0 組である。

## 2. 問い

### 2.1 テーマの値のうち、Kindle に届くものの範囲

`theme-contract-spec.md` §3.2 は、配色のテーマについて「`standard` を土台に、12 色とは別の配色・**書体**の組を配る」「値は CSS の生成がリテラルに解くので、Kindle でも必ず通る」と書いている。S3-4 の後は、これが書体と本文の字の大きさ・行送りについて成り立たない。

- `kindle-tokens.css` は target 層（いちばん上の層）で `body.vs-kindle` に書くので、テーマ（theme 層）と `custom.css` の `:root` の定義は、Kindle の本文に届かない。`custom.css` に `body.vs-kindle { --base-font-size: … }` と書けば届く（`literal_resolver_test.rb` で確かめている）。
- 端末任せにした理由: 書体の名前が届くと、Kindle Previewer は Mac に入っている書体（HackGen）で描き、端末と違う画面になった。Kindle には書体を埋め込まない。本文の字の大きさと行送りは、読者が端末で変える値である。
- S6 で変数の名前を `--book-*` に変え、今の名前を別名にする（`css-layer-restructure-spec.md` §7.2）。`kindle-tokens.css` が書くのは今の名前（`--base-font-size`・`--font-*`）である。

決めてほしいこと:

1. 「本文の字の大きさ・行送り・書体は Kindle では端末任せ」を契約にするか。するなら、§3.2 の表と §5.2（公開する変数の一覧）に、Kindle に届かない変数をどう示すか
2. テーマが Kindle の書体や字の大きさを変えたい場合に、テーマの `kindle.css` で `body.vs-kindle` に書くことを認めるか（著者は `custom.css` でそれができる）
3. S6 の名前の変更で、`kindle-tokens.css` が書く名前を `--book-*` にするか、今の名前（別名）のままにするか

### 2.2 テーマの寸法と Kindle

S3-4 で、紙の寸法を `clamp()` で書いた宣言は Kindle で落ちると分かった。見出し・前書き・奥付の大きさと余白は、Kindle では `targets/kindle*.css` の em の規則が受け持つ。S6 では、`standard` の寸法をテーマへ移す（`css-layer-restructure-spec.md` §4.4 の「解く層」）。

- 今のビルドは、解けずに落とした宣言を、`custom.css` と章の frontmatter の CSS のものだけ 🟡 で知らせ、vs の CSS のものは `--log=debug` に出す（`Css::Bundle`）。`theme-contract-spec.md` §3.5 は「範囲の外の書き方は、その宣言か規則を落として 🟡」としている。
- `standard` をそのまま切り出すと、テーマの CSS に `clamp()` の宣言が多く入る。同梱でないテーマにも 🟡 を出すなら、`standard` を `extends:` したテーマの作り手は、自分が書いていない宣言の 🟡 を受け取ることになる。

決めてほしいこと:

1. テーマの寸法の Kindle での扱い。(a) 紙の寸法は Kindle に届かないものとし、Kindle の寸法はテーマの `kindle.css` に em で書く、(b) `LiteralResolver` が `clamp()` を解く（Kindle での基準の値を決める必要がある）、(c) ほかの形
2. テーマの CSS で落ちた宣言を、ビルドと `vs theme:check` のどちらで、どの水準で知らせるか（`standard` と `extends:` の先の宣言を含めるか）

### 2.3 テーマの `kindle.css` の形

`theme-contract-spec.md` §3.1 のテーマのディレクトリには、Kindle だけに当てる `kindle.css` が 1 枚ある。S3-2 では、vs の target の規則を 1 枚にまとめられず、ページの種類ごとに分けた（§1 の表）。また、EPUB と Kindle の両方に当てる規則（`targets/epub.css`）が要った。

決めてほしいこと:

1. テーマの出力先の CSS を、(a) `kindle.css` 1 枚にし、ページの種類で変える規則は `body.vs-kindle.colophon` のように選択子で絞る、(b) vs と同じく種類ごとのファイル（`kindle-<種類>.css`）を認める、(c) ほかの形、のどれにするか
2. テーマに `epub.css`（EPUB と Kindle の両方）を認めるか
3. (a) の場合、選択子で絞ると詳細度が上がる。案 A（平らな CSS は詳細度で決まる）のもとで、`standard` の target の規則（`targets/` の 7 枚）をテーマの側へ移すときの扱い

### 2.4 S4 の分割に、本全体を見て CSS と HTML を書き直す段を入れる

`v2-architecture-spec.md` §4.3 の (2) は、`runner.rb` が 1 ページの HTML を一度だけ読み、変換を順に当て、一度だけ書く形である。S3 で、ページごとの変換の**後**に、本の全部のページと CSS を見て書き直す段が三つ入った。

| 段（今の名前） | 読むもの | 書き直すもの |
| :--- | :--- | :--- |
| `prioritize_author_css_for_epub!`（`Css::Bundle.prioritize_author_css!`） | 書き換えの終わった全部の HTML と、平らな CSS の規則の列 | CSS（`!important` を付ける）と HTML（`style` 属性に `!important` を付ける） |
| `report_flat_css_inversions!`（`--log=debug` のときだけ） | 同上（付けた後のもの） | なし（報告だけ） |
| `apply_variant_glyph_fonts_for_kindle!`（Kindle だけ） | 全部の HTML | 平らな CSS の末尾に規則を足す |

順序には意味がある。判定は Kindle の印（`vs-kindle`）と、EPUB 用に足す要素（合成画像の見出し・コードの行ブロックなど）が付いた後でないと、Kindle の規則を見落とす（S3-2 で見つかった。§10.6 の「仕様と違えたこと」の 3）。

決めてほしいこと:

1. この「本全体の段」を `OutputTarget` のどの項目に置くか（`transforms` の後の別の並び・`css_form` に付く処理・`packager` の前段など）。§4.1 の型と §4.3 のファイル構成への足し方
2. S4 の (2) の完了の条件（「HTML の差が属性の順と空白だけ」）に、この段が書き直す `style` 属性をどう扱うか

あわせて、`v2-architecture-spec.md` §4.4 の表は S3 の前の書き方で、`book-settings-kindle.css` と `kindle_*` のメソッドの行が S3 の結果と合わない。この直しは Opus が S4 の最初に行う。ほかに S4 の前に直すべき仕様の文があれば挙げてほしい。

### 2.5 比べる基準の置き直しと、見た目を変える変更の扱い

`v2-migration-plan.md` は、S1〜S7 の完了の条件を「技術書の出力が S0 の基準と変わらない」としている。S3 の間に、ユーザーの判断で出力を変えた変更が二つ入った。

| 変更 | 変わった出力 |
| :--- | :--- |
| 改善案 #132（付録のページは、テーマ色で塗るものを全部付録の色で塗る。1.x の不具合） | PDF の付録のページの画素。Kindle の付録の囲みの色 |
| S3-4（部品の値を Kindle へ届ける） | Kindle の見出しの書体（ゴシック）・コードの書体（端末の等幅）・図のキャプションの字の大きさ（0.9em → 1em）・図の枠・引用の線・テキストの図の枠の色など 46 種類 |

S3-2 以降の確かめは、S0 の基準ではなく、直前の小段階の出力（`../vivlio-starter-v2-baseline/check/s3-*/`）と比べている。S4 の §8 の条件 3 は「S0 の基準と比べて」と書いているので、このままでは S4 の完了を言えない。

また、見た目を変える判断を後に回したものが一つある。S2-3 の節リード（`css-layer-restructure-spec.md` §10.3 の「仕様と違えたこと」の 2）で、`image` の見出しの EPUB でも節リードを見出しに近づけるか（元のコメントの意図）は「S2 の後に決める」としてある。

決めてほしいこと:

1. S4 以降の比べる相手。(a) S3-4 の出力を新しい基準にする（`VERSIONS.md` にコミットと理由を書く）、(b) S0 の基準と比べ、許す差を表にする、(c) ほかの形
2. S1〜S7 の間に見た目を変える変更（1.x の不具合の直し・Kindle の改善・節リードのような元の意図の回復）を入れる決まり。入れる段階・基準の作り直し・ユーザーの確認の取り方
3. 節リードをいつ決めるか（S6 の `standard` の切り出しと一緒に、など）

## 3. あわせて意見がほしいこと（決めるのはユーザー）

`v2-migration-plan.md` §7 の論点 6「`v2` で整理した CSS を 1.x へ取り込むか」は、答えが要る時点を「S3 の後」としている。取り込むかはユーザーが決める。判断の材料として、取り込む場合の範囲と負担についての見立てを書いてほしい。

材料になる事実:

- S2・S3 は CSS だけでなく Ruby も変えた（`lib/vivlio_starter/cli/css/` の 10 ファイル・2,162 行、`crass` の依存の追加、`EpubBuilder` と `BookSettingsCss` の書き換え）。
- S2 は著者の本の `stylesheets/` を全部入れ替える（`css-layer-restructure-spec.md` §8 の理由の 1）。
- S3-4 と #132 は、1.x の利用者から見て見た目が変わる（§2.5 の表）。「見た目が変わる変更は 2.0 で入れる」方針（`v2-design-research-brief.md` §5）との関係。#132 は 1.x の不具合なので、master で直すこともできる。
- S1（HTML に `role` を足す）は 2.0 に限る方針である。`stylesheets/` に `role` を選ぶ規則は無い（0 件）ので、CSS は `role` に依らない。ただし S1 は奥付を `section` で包み、`section-topic` を常に付けたので、S2・S3 の確かめは S1 の HTML の上で行っている。
- 技術書典の 6 冊（登録の締切 2026-12-06）は 1.x で組んでいる。

## 4. 答えの形

- §2 の各問いの決定と理由を、`v2-flat-cascade-consultation.md` §5 と同じく、この文書の末尾に「答え」の節として書く。
- 決定を移す先の仕様書と節を挙げる（移すのは Opus が S4 の最初に行う）。
- §3 は見立てだけでよい。
