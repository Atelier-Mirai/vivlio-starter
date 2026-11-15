# S3 を終えて決めること（Fable への相談）

> 作成日: 2026-11-15
> ステータス: **答え済み（§5）**（2026-11-15。仕様書への反映は S4 の最初に行う・§5.8）
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

---

## 5. 答え（Fable・2026-11-15）

### 5.1 決めたこと

| # | 問い | 決定 |
| :--- | :--- | :--- |
| 2.1 | Kindle に届くテーマの値 | 本文の字の大きさ・行送り・書体は、Kindle では**読者と端末が決める**ことを契約にする。テーマが渡せるのは、明朝・ゴシック・等幅の区別（総称の名前）と色。配色のテーマのために `theme.yml` に `kindle_tokens:` を足す（5.2） |
| 2.2 | テーマの寸法と Kindle | 案 (a)。紙の寸法は Kindle に届かない。Kindle の寸法は、出力先の CSS に em で書く。`clamp()` などの宣言は、生成が理由を付けて落とす（今は下流が捨てるのに任せている）。知らせるのは `vs theme:check` だけで、検査するテーマ自身のファイルに限る（5.3） |
| 2.3 | テーマの出力先の CSS | 案 (b)。vs の `targets/` と同じ名前の決まり（`epub.css`・`kindle.css`・`kindle-<種類>.css`）を、テーマにも認める。`standard` への移動では選択子を変えない（5.4） |
| 2.4 | 本全体の段 | `OutputTarget` に `finalizers`（変換の後・梱包の前に走る、本全体の段の並び）を足す。置き場は `build/finalizers/`（5.5） |
| 2.5 | 比べる基準 | 案 (a)。S3-4 のコミットで基準を作り直し、版を付ける（r2）。見た目を変える変更は、段階と段階の間に、別のコミットで入れる（5.6） |
| 3 | CSS を 1.x へ取り込むか（見立て） | 取り込まないことを勧める（5.7） |

### 5.2 Kindle に届くテーマの値（問い 2.1）

**契約にする理由。** 実測（書体の名前が届くと、読む環境に入っている書体で描かれる）に加えて、リフローの Kindle では、字の大きさ・行送り・書体は読者が端末で選ぶ値である。テーマが PDF 用の 10.5pt を届けると、読者の設定と掛け合わさって意図しない大きさになる。S3-3a で 26,310 要素が変わったのは、この形だった。「テーマは Kindle の本文の組み方を決めない」と決めておけば、テーマを作る人が端末ごとの確かめを負わずに済む。

1. **契約の文。** `theme-contract-spec.md` §3.2 の表の配色のテーマの行を、次のように直す。例は「12 色とは別の配色・書体の組を配る」のまま。Kindle の列は「色は必ず通る。書体は明朝・ゴシック・等幅の区別だけが届く。本文の字の大きさと行送りは届かない」。§5.2 の表に「Kindle」の列を足し、分類ごとに次の値を書く。

   | 分類 | Kindle |
   | :--- | :--- |
   | テーマ色・色・見出しの印・会話 | 届く |
   | 書体 | 総称の名前に置き換わる（`kindle-tokens.css`） |
   | 版面のうち `--book-font-size`・`--book-line-height` | 端末任せ（`1em`・`normal`） |
   | 版面の残り（余白・`--book-letter-spacing`・`--book-paper-scale`）・柱とノンブル | 届かない（Kindle に紙面が無い） |

2. **テーマが Kindle の値を変える道。** 二つ認める。
   - 配色のテーマ（CSS を持たない）のために、`theme.yml` に `kindle_tokens:` を足す。書き方は `tokens:` と同じで、vs が target 層の `kindle-tokens.css` の直後に `body.vs-kindle { … }` として書き出す。使い道は、見出しを明朝にする（`font-heading: serif`）、リンクの色を Kindle で指定どおりに描かれる `#222` 以上にする、など。
   - 組版のテーマは、`kindle.css` に `body.vs-kindle { … }` で書いてもよい。
   - どちらでも、書体の値は総称の名前（`serif`・`sans-serif`・`monospace`）だけとし、`--book-font-size`・`--book-line-height` は書かない。`vs theme:check` が、それ以外の値を 🟡 で示す（「Kindle では読者が選ぶ値です」と、消すことを案内する）。ビルドは止めない。
   - 著者の `custom.css` の `body.vs-kindle { … }` は、今のとおり何でも書ける。著者は自分の本と自分の端末で確かめられるので、知らせない。

3. **名前。** S6 で、`kindle-tokens.css` は `--book-*` の名前で書く。部品が読む名前が `--book-*` になるので、同じ名前で置き換えるのが変数の表の解き方（`body` に近い定義が勝つ）に合う。今の名前（`--base-font-size` など）を `body.vs-kindle` に書いた `custom.css` は、2.0 がまだ公開されていないので世の中に無い。`vs upgrade` の置き換え（`css-layer-restructure-spec.md` §7.2）は、選択子を問わず `custom.css` の全部の定義に当てる。S6 の完了の条件に「Kindle の中間生成物が、名前の変更の前後で差 0」を足す。

### 5.3 テーマの寸法と Kindle（問い 2.2）

1. **(a) にする理由。** 紙の寸法（mm と `--paper-scale`）は、判型に対する比で決めた値で、判型の無い端末では基準が無い。(b) は Kindle での基準の値を新しく決めることになり、決めた値は 1.x と S3-4 の画面（確かめ済み）を変える。Kindle の寸法が em で `targets/kindle*.css` に書いてある今の形は、1.x からの実績がある。
2. **落とし方を明示にする。** 今は `clamp()` の宣言が Kindle 用の CSS に残り、KFX と Kindle Previewer の前処理が捨てるのに任せている。下流の二つが同じに捨てることに頼る形なので、`LiteralResolver` が `clamp()`・`min()`・`max()` を含む宣言を、理由（`:paper_dimension`）を付けて落とす。Kindle 用の CSS に `clamp(` が残らないことを、§8 の S3-3 の (a) の並びに足す。確かめは、Kindle の中間生成物が前後で差 0（今も届いていないので、変わらないはずである）。入れるのは S6 の最初（寸法をテーマへ移す前）。
3. **契約の文。** `theme-contract-spec.md` §3.5 の表に 1 行足す: 「紙の寸法（`clamp()`・`min()`・`max()` を使う宣言） — Kindle には届かない。Kindle での大きさと余白は、`kindle.css` に em で書く」。mm や pt をそのまま書いた宣言（図の枠 0.5mm・引用の線 2mm など）は今も届いて崩れていないので、単位では検査しない。
4. **知らせ方。**

   | 場面 | 何を出すか |
   | :--- | :--- |
   | `vs build` | テーマの CSS で落ちた宣言は知らせない（`--log=debug` だけ）。著者には直せないためである。`custom.css` と章の CSS は今のまま 🟡 |
   | `vs theme:check <名前>` | 検査するテーマ自身のファイルの宣言だけを見る。`extends:` の先と vs の部品は含めない。紙の寸法で落ちた宣言は、場所を挙げずに件数を 1 行で示す（💡。意図した書き方で、直す対象ではない）。それ以外で落ちた宣言（深い要素の変数・`:has()`・単位の混ざる `calc()`・srgb 以外の混色）は、ファイル名と行番号つきの 🟡 |
   | `rake test`（同梱のテーマ） | 紙の寸法のほかに落ちる宣言を、理由つきの許可の表で持つ（今は会話の `--talk-accent` など 3 種類）。表に無い宣言が落ちたら失敗 |

### 5.4 テーマの出力先の CSS（問い 2.3）

1. **(b) にする理由。** (a) は選択子にクラスを 1 つ足すので詳細度が上がり、平らな CSS では勝ち負けが変わりうる（`v2-flat-cascade-consultation.md` §5.3 の 5「`standard` は選択子を変えずに切り出す」に反する）。奥付の `body.vs-kindle { … }` のように `body` そのものを選ぶ規則は、種類のクラスを足す以外に絞りようが無く、足すと別の規則になる。ファイルで分ける形は、vs の `EntryWriter::TARGET_IMPORTS`（種類ごと・出力先ごとの表）がそのまま読める。
2. **名前の決まり。** テーマのディレクトリの直下に、次の名前で置く（どれも任意）。`theme.yml` には書かない（`styles:` は theme 層に入る CSS だけを並べる）。

   | ファイル | 読む束 |
   | :--- | :--- |
   | `epub.css` | クリーン EPUB と Kindle の、全部の種類 |
   | `epub-<種類>.css` | 同、その種類だけ |
   | `kindle.css` | Kindle の、全部の種類 |
   | `kindle-<種類>.css` | Kindle の、その種類だけ |

   `<種類>` は入口の 11 種類の名前。`epub.css` が Kindle にも入るのは vs の `targets/epub.css` と同じで、§3.1 の説明に「EPUB の枝（クリーン EPUB と Kindle）」と書く。
3. **層と順。** テーマの出力先の CSS は target 層に入れる。順は `kindle-tokens.css` → `kindle_tokens:` の書き出し → vs の `targets/`（`epub.css` → `kindle.css` → 種類の 1 枚）→ `extends:` の先のテーマ → テーマ自身（それぞれ `epub.css` → `epub-<種類>.css` → `kindle.css` → `kindle-<種類>.css`）。
4. **`standard` へ移す規則。** `targets/` の規則のうち、劣化させる相手の部品がテーマへ移るもの（`image-header.css`・`simple-header.css`・扉絵と節絵）だけを `themes/standard/` へ移す。vs の部品（囲み・コード・表・索引・用語集・奥付）の規則は `stylesheets/targets/` に残す。選択子と宣言は変えない。移すと vs の規則との前後が変わり、詳細度が同じ組では勝つ側が入れ替わりうるので、S6 の完了の条件に「EPUB の計算値（`css_computed_diff.rb`）と Kindle の中間生成物（`kindle_record_diff.rb`）が、移動の前後で差 0」を足す。

### 5.5 本全体の段（問い 2.4）

1. **`finalizers` を足す。** `OutputTarget` の項目を一つ増やす。

   ```ruby
   OutputTarget = Data.define(
     :id, :branch, :workspace, :body_classes,
     :transforms,   # 1 ページの HTML だけを見て書き換える段の並び
     :css_form,
     :finalizers,   # 本の全部のページと CSS を見る段の並び（変換の後・梱包の前）
     :assets, :packager
   )
   ```

   - `transforms` に入れない理由: 変換は「1 ページだけを見る」ことを決まりにする。この決まりがあるから、`runner.rb` は 1 ページを一度読んで一度書く形にでき、後でページごとに並べて走らせる余地も残る。本全体を見る段を混ぜると、決まりが崩れる。
   - `css_form` に付けない理由: 三つのうち一つ（異体字の 1 字書体）は CSS の形と関係が無く、一つ（`custom.css` を勝たせる）は HTML も書き直す。
   - 置き場は `build/finalizers/`。`author_priority.rb`・`variant_glyph_fonts.rb`・`inversion_report.rb` の 3 枚で、どれも `Css::Bundle` などを呼ぶ薄い段にする。形は `call(book, ctx)`。`book` は、ページのパスの並びと、平らな CSS の表（href → `Css::Bundle::Sheet`）を持ち、段が CSS を書き直したら表を差し替えて返す。
   - 宣言は、`epub` が `[AuthorPriority, InversionReport]`、`kindle` が `[AuthorPriority, VariantGlyphFonts, InversionReport]`（今の順のまま）。固定レイアウトの宣言は S9 で決める。
2. **流れの順を仕様に書く。** `v2-architecture-spec.md` §4.3 に、出力先の流れを次の順で書く。(1) ワークスペースと素材、(2) 平らな CSS を書いて `link` を付け替える（`css_form`。今の `bundle_flat_css_for_epub!`。置き場は `epub/stylesheets.rb`）、(3) `transforms`、(4) `finalizers`、(5) `packager`。(2) が (3) の前にあるのは今と同じで、判定が (3) の後でなければならないことは、(4) に置くことで保証する。
3. **ファイルで読み書きする。** 第二段階でも、`finalizers` はページを書き終えたファイルから読み、書き直したページだけを書く。全部のページの `doc` を持ち回す形にはしない。「一度だけ読み、一度だけ書く」は `transforms` の決まりとし、`finalizers` の書き直しはその外に置く。書き直しが起きるのは `custom.css` が負ける本だけで、本書（`custom.css` が空）では 0 ページである。
4. **完了の条件。** S4 の条件 3 は、分割の前後を同じ入力で比べるので、`style` 属性の `!important` は両側に同じに出る。条件の文はそのままでよい。ただし B1 は `finalizers` が何も書き直さない本なので、S3-3b の確かめ (f) の写し（`custom.css` に 2 行を足した本）を条件 3 に加え、EPUB と Kindle 用 EPUB を同じ基準（第一段階はバイト単位、第二段階は属性の順と空白を除く）で比べる。「属性の順」は属性どうしの順のことで、`style` 属性の値は中の宣言の順まで一致を求める。
5. **S4 の前に直す仕様の文。** `v2-architecture-spec.md` の次の箇所。
   - §4.1 の型と §4.3 のファイルの一覧（上の 1・2）。
   - §4.2 の表の「共通の 11 段」「Kindle の 18 段」と §4.3 の「3,858 行・177 メソッド」。S3 で段とメソッドが増減したので、数え直す。
   - §4.4 の表（相談文 §2.4 のとおり）。「二つを読めば分かる」の二つに、`targets/kindle-tokens.css` を含む `targets/kindle*.css` と書く。
   - §8 の S4 の条件 3 の「S0 の基準」（5.6 の 1）。

### 5.6 比べる基準と、見た目を変える変更（問い 2.5）

1. **基準を作り直す（r2）。**
   - `6aabe1cb`（S3-4）で B1〜B5 を組み直し、`../vivlio-starter-v2-baseline/r2/` に置く。S0 の基準は `r1` として残す。確かめの出力（`check/s3-4-*`）を基準に流用しない。`s3-4-b1` の Kindle は書体のトークンを足す前の出力で、`s3-4-b1k` と分かれており、B2〜B5 は #132 の後に組んでいないためである。
   - B1 は二度組み、PDF の差 0 ページ・EPUB の差が「無視する差」だけであることを、もう一度確かめる（S0 の条件 2）。S3 で入った生成（`AuthorPriority`・`LiteralResolver`）が、組むたびに同じ出力を返すことの確かめを兼ねる。
   - Kindle Previewer と Apple Books の 10 か所の画面を撮り直す。Location は S3-4 で動いたので、着いた頁を文字で確かめて表を作り直す。
   - `VERSIONS.md` に、r1 から r2 で変わったものを書く: #132（PDF の付録のページ・Kindle の付録の囲みの色）と S3-4（Kindle の 46 種類）。r2 は「r1 に、説明のついた差だけを足したもの」であり、その鎖は S3 の各小段階の記録（§10.5〜§10.10）が支えている。
   - (b) を採らない理由: 画素の比べは許容 0 を原則にしており（`v2-migration-plan.md` §3.3）、許す差を表で持つと、付録のページでは新しい差を見分けられなくなる。
   - `v2-migration-plan.md` §3.2 に基準の版の決まりを足し、各仕様書の「S0 の基準」を「その時点の基準」に読み替える 1 文を §4.1 に置く。
2. **S1〜S7 の間に見た目を変える変更を入れる決まり。** `v2-migration-plan.md` §4.1 に足す。
   - **段階の中では入れない。** 段階（小段階）の完了のコミットは、基準と差 0 のものだけにする。見た目を変える変更は、完了のコミットの後、次の段階の前に、**別のコミット**で入れる（#132 がこの形だった）。
   - **手順。** 変更の前後の紙面か画面をユーザーに見せて了承を得る → コミット → 変わった出力先の基準だけを組み直して版を上げる（r3…）→ `VERSIONS.md` に変わった箇所を書く。
   - **種類ごとの入れ先。** 1.x の不具合は master で直して `v2` へマージするのが原則（流れは一方向）。2.0 の作りでしか直せないもの・2.0 の作りで良くなったもの（S3-4）・元の意図の回復（節リード）は `v2` だけに入れる。
   - **一覧を持つ。** `v2-migration-plan.md` §5 に「2.0 で見た目が変わる箇所」の表を置き、入れるたびに 1 行足す。S11 の移行の手引きと `CHANGELOG.md` の素材になる。今の時点の行は #132 と S3-4 の二つ。
   - **S11 の条件を直す。** §4.3 の条件 1 は「PDF の全ページの画素が、同じ本を 1.0.x で組んだものと一致する」としているが、雛形の本には付録があり、#132 で一致しなくなった。「上の表の箇所を除いて一致する」に直す。#132 を master にも入れるなら、この例外は要らなくなる（5.7 の 4）。
3. **節リード。** S6 の完了の後、S7 の前に決める。この規則は `image` の見出しに掛かる EPUB の規則で、S6 で `themes/standard/epub.css` へ移る。移動を差 0 で終えてから、上の 2 の手順で扱う。Opus が、今の出力と、節リードを見出しに近づけた出力を、Apple Books と Kindle Previewer の画面で並べ、ユーザーが選ぶ。判断の目安は、PDF の `image` の見出しでの節リードと見出しの間隔に EPUB をそろえるかどうかである。

### 5.7 CSS を 1.x へ取り込むか（見立て）

**取り込まないことを勧める。** 決めるのはユーザーである。

1. **取り込んでも、1.x の利用者の紙面は良くならない。** S2・S3 は「出力を変えない」ことを完了の条件にした作り直しである。変わるのは Kindle の見た目（S3-4）と、`custom.css` が EPUB と Kindle でも勝つこと（S3-3b）で、どちらも 1.x の保守の中身（不具合の修正と依存の更新）を超える。
2. **著者の本が二度入れ替わる。** 今取り込むと、1.x の利用者の `stylesheets/` が全部入れ替わる。その後 S6 で、`theme.css`・見出しの CSS・画像が `themes/standard/` へ移り、変数の名前が `--book-*` に変わるので、2.0 への `vs upgrade` でもう一度入れ替わる。雛形の CSS を直している著者は、退避と付け直しを二度行うことになる。取り込むなら一度で済む時点（S6 の後）しか無く、それは 2.0 の基盤を 1.x の名前で出すことと同じである。
3. **切り出せる単位が無い。** S2 だけでは EPUB と Kindle が組めない（層を外す `Flattener` が要る）。S3 までを一組にすると、Ruby 2,162 行・`crass` の依存・`EpubBuilder` と `BookSettingsCss` の書き換えが付いてくる。確かめは S1 の HTML の上で行ったので、1.x の HTML（`section-topic` の付き方が違う）で B1〜B5 と Kindle の画面を全部やり直す必要がある。技術書典の 6 冊を master で組んでいる 12/6 までは、入れる時期でもない。
4. **取り込みで得るのは、master の CSS の修正を `v2` へ手で写す手間が無くなること。** これは、1.x の CSS の修正を不具合に限れば小さく保てる。写し先は S2-2 の記録（`css-layer-restructure-spec.md` §10.2 の対応）で引ける。個別に 1.x へ入れる価値があるのは #132 で、1.x の不具合とユーザーが判断したものなので、master に手で写せる（`chapter-common.css` などの元のファイルに対する小さな修正になる）。入れるかは、1.0.x の利用者の付録の色が変わることを踏まえて決めてほしい。

**ユーザーの判断（2026-11-15）。** CSS は 1.x へ取り込まず、2.0 の完成まで待つ。#132 は master にも入れ、1.0.1 として出す（改善案 #132）。master に入れば、5.6 の 2 の「S11 の条件を直す」の #132 の例外は要らなくなり、「2.0 で見た目が変わる箇所」の表の行は S3-4 だけになる。

### 5.8 決定を移す先（Opus が S4 の最初に行う）

| 決定 | 移す先 |
| :--- | :--- |
| 5.2 | `theme-contract-spec.md` §3.1（`kindle_tokens:`）・§3.2 の表・§3.5（`body.vs-kindle` の定義と検査）・§5.2（Kindle の列）・§9 の S6（名前の変更の前後で中間生成物が差 0）。`css-layer-restructure-spec.md` §4.4「解く層」（`--book-*` で書く） |
| 5.3 | `css-layer-restructure-spec.md` §4.4「関数と選択子」（`clamp()`・`min()`・`max()` の行）・§4.5 の表・§8 の S3-3 の (a)。`theme-contract-spec.md` §3.5 の表・§7.2（`vs theme:check` の報告）・§9 の S6 |
| 5.4 | `theme-contract-spec.md` §3.1 のディレクトリ・§4（`standard` へ移す規則の線引き）・§9 の S6。`css-layer-restructure-spec.md` §5（target 層の順） |
| 5.5 | `v2-architecture-spec.md` §4.1・§4.2・§4.3・§4.4・§8 の S4 |
| 5.6 | `v2-migration-plan.md` §3.2（基準の版）・§4.1（見た目を変える変更の決まり）・§4.3 の条件 1・§5（見た目が変わる箇所の表）。`css-layer-restructure-spec.md` §10.3 の 2（節リードを決める時点） |
| 5.7 | `v2-migration-plan.md` §7 の論点 6（2026-11-15 に閉じた） |

S4 に入る前の作業の順は、(1) 5.8 の仕様の直し、(2) 基準 r2 の作成、(3) S4 の第一段階、とする。
