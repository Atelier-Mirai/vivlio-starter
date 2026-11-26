# 文字の色・コメントの色・蛍光ペンの記法の仕様書

> 作成日: 2026-11-26
> ステータス: **仕様確定・未実装**（1.1.0 に入れる）
> 対象: 本文や表のセルの一部の字に色を付ける記法、コードのコメントの `[!]` の色、蛍光ペン（`PLANNED.md`「文字の色を変えるインライン記法」を仕様にしたもの）
> 決定事項（2026-11-26 ユーザー決定）:
> - **文字の色は 2 通り。** `[文字]{.red}` は**この本のテーマ色**（テーマ色の 12 色と `accent`。`red` は `#dc2626`）。`[文字]{color=red}` は **CSS の色そのもの**（`red` は `#ff0000`。`#3a9d5d` のような値も書ける）（§1.1）
> - **コメントの `[!]` は既定の赤のまま、`[!]{.blue}`・`[!]{color=#…}` で色を選べる**（§1.2）
> - **蛍光ペンは `==文字==`。** 下半分を塗る。既定は黄色。`==文字=={.green}` はテーマ色を淡くした色、塗る色の値は `==文字=={background=#fff3a0}`（`color=` は字の色の意味で統一する）。淡さの割合は実装の後に紙面を見て決める（§1.3）
> - **v2 の `InlineSpanTransformer`（行内の属性 `[文字]{.class}`）を同じパス・同じ形で master へ写して作る。** 2.0 の傍点 `{.sesame}`・縦中横 `{.tcy}` と同じ仕組みに載る。v2 のセッションと整合を確認済み（§8）
> - **11/17 の決定を改める。** `v2-migration-plan.md` §6.3（色の記法は 1.1.0 を出さず v2 で作る・master には作らない）を、ユーザーが 11/26 に改めた。§6.3 の書き換えは、取り込みのときに v2 のセッションが行う（§8.3）
> 関連: `notation-implementation-guide.md`（【B】前処理変換型＋【A】CSS 型）, `lib/vivlio_starter/cli/index_markup.rb`, `lib/vivlio_starter/cli/prism_lines.rb`（`[!]`）, `lib/vivlio_starter/cli/guards/container_class_check.rb`, `lib/vivlio_starter/cli/theme_color.rb`, `lib/vivlio_starter/cli/pre_process/book_settings_css.rb`（`kindle_accent_rules`）, `stylesheets/theme.css`（`--accent-*`）, `stylesheets/code.css`（`.codered`）, `kindle-css-compatibility-notes.md`（`linear-gradient` は KFX で描かれない）, `vivliostyle-css-pitfalls-notes.md`（`background` の `calc()`+`var()`）, v2 の `inline_span_transformer.rb`・`novel-vertical-spec.md` §5.1・`v2-architecture-spec.md` §7.1

## 0. 背景

字の一部に色を付ける記法が無いので、著者は生の HTML を書いている。

| 本 | 箇所 | 今の書き方 | 色の出どころ |
|---|---|---|---|
| vivlio-starter | 41 章のテーマ色の見本（12 色） | `<span style="color: #dc2626">■</span>` | テーマ色の 12 色（`ThemeColor::PALETTE`）と同じ値 |
| haruka_mirai | 15 章の HP のゲージの色の表 | `<span style="color: #3a9d5d">緑</span>` | 作例のプログラムの `style.css` の値（テーマ色ではない） |
| vivlio-starter | 22 章の `[!]` の表 | 「`# コメント`（赤色）」と文字で書く | コメントの強調の赤 `#eb0000` |

テーマ色は名前で呼べると楽で（12 色の値は少しずつ調整してあり、覚えて書くのは大変）、作例と同じ色は値で書けなければならない。両方を受ける。

コードのコメントの `[!]` は赤だけで、色を選べない。蛍光ペンの記法も無い。

## 1. 記法

### 1.1 文字の色

| 書き方 | 意味 | 例 |
|---|---|---|
| `[文字]{.名前}` | この本のテーマ色 | `[■]{.red}` は `#dc2626`・`[注意]{.accent}` は本のテーマ色 |
| `[文字]{color=値}` | CSS の色そのもの | `[■]{color=red}` は `#ff0000`・`[緑]{color=#3a9d5d}` |

- **名前**（クラス）は、テーマ色の 12 色 `yellow` `orange` `red` `magenta` `purple` `indigo` `navy` `blue` `cyan` `teal` `green` `lime` と、本のテーマ色 `accent`（`book.yml` の `theme.color`）の 13 個。値は `stylesheets/theme.css` の `--accent-*`・`--theme-accent` から取る。`book.yml` の `theme:` と同じ語なので、一覧を一つ覚えれば済む。
- **値**（`color=`）は、CSS の色の名前（`red`・`rebeccapurple` など 148 個）と、`#rgb`・`#rrggbb`。大文字・小文字は問わない。`rgb()`・`hsl()`・`#rrggbbaa` は、まず受けない（§2.3。受ける範囲を広げるのは後からできるが、狭めると原稿の意味が変わる）。
- 名前と値を両方書いたとき（`{.red color=#000}`）は、値が勝つ（style 属性のため）。書く理由が無いので、文書では触れない。

### 1.2 コードのコメントの `[!]`

```ruby
puts total   # [!] 今までどおりの赤（#eb0000・太字）
puts total   # [!]{.blue} テーマ色の青（#0186d8・太字）
puts total   # [!]{color=#3a9d5d} 値で指定（太字）
```

- `[!]` だけのときは、今までどおり。`{…}` の書き方と意味は §1.1 と同じ（名前はテーマ色、`color=` は CSS の色）。
- 紙面からは `[!]{…}` ごと取り除く。コメントの記号（`#`・`//`・`--`・`/*`・`<!--`）は残す（今と同じ）。
- 太字は色によらず付ける（白黒印刷で強調が残るように。今の `[!]` と同じ）。

### 1.3 蛍光ペン

```markdown
==大事なところ==                      既定（黄色の蛍光ペン）
==大事なところ=={.green}              テーマ色の緑を淡くした色
==大事なところ=={background=#fff3a0}  塗る色を値で指定
```

- 字の背の**下半分**を塗る（手で引いた蛍光ペンに近い形）。Kindle は背の全体を塗る（§5.2）。
- `{.名前}` は §1.1 と同じ 13 個。蛍光ペンでは「ペンの色」の意味になり、その色を白と混ぜて淡くした色で塗る。字の色は変えない。
- `{background=値}` は、塗る色を CSS の色そのもので指定する（値の書き方は §1.1 の `color=` と同じ）。淡くはしない。著者が書いた色で塗る。
- `color=` は書けない（§2.3 で 🟡）。字の色も変えたいときは、中に `[文字]{…}` を入れる（`==[注意]{.red}==`）。`color=` が字の色、`background=` が地の色、という CSS の名前のとおりに保つ。
- **淡さの割合**（既定の黄色の値と、テーマ色を白と混ぜる割合）は、実装の後に 2〜3 通り組んで、ユーザーが紙面を見て決める（§9）。

### 1.4 組み合わせ

| 書き方 | 結果 |
|---|---|
| `**[注意]{.red}**`・`[**注意**]{.red}` | 赤の太字（どちらの順でも赤になる。§4.1） |
| `[`# コメント`]{.red}` | 中のコードも赤（§4.1） |
| `[[用語]]{.red}` | 索引の語 `[用語]` を赤に。索引に載せないなら `[用語]{.red}` |
| `[{漢字|かんじ}]{.red}` | ルビつきの字を赤に（ルビも赤） |
| `==[注意]{.red}==` | 蛍光ペンの中の字を赤に |
| `[文字]{.red .small}` などクラスを並べる | 並べたクラスが全部付く（2.0 の `.sesame` と重ねると、傍点も字と同じ色。§8.2） |

表のセルでも、前処理が表を HTML にする前に置き換えるので、同じように書ける。

## 2. 読み方（前処理）

### 2.1 行内の属性 `[文字]{…}`

v2 の `lib/vivlio_starter/cli/pre_process/inline_span_transformer.rb` を**同じパス・同じ形で**写し（v2 の S8-2 の `c10caaf5`・`6ae0cc78`）、`{…}` の中に `color=` を足す。写すときに同じにする部分:

- `PATTERN`（`(?<![!^\\])\[…\]\{…\}`・角かっこの 1 段の入れ子）・`Span`・`each_span`
- 行末の段落のクラス `PARAGRAPH_CLASSES`（`…[用語]{.aki}` の `{.aki}` は段落に付けるクラスなので読まない）と `paragraph_attribute?`
- `Masking.protect_code` で守る範囲（コードの中は置き換えない）
- 前処理の段の位置（`transform_inline_spans!`。会話・寄せ・fancy list・book-card が中の Markdown を Kramdown で HTML にする段より前）

読まないもの（v2 と同じ）: 画像 `![…]{…}`・インライン脚注 `^[…]`・`\[` で始まるもの・コードの中。コメントの `[!]{…}` はコードブロックの中なので、この変換は触らない（§2.4 の後処理が読む）。地の文に書いた `[!]{.blue}` は、ほかの字と同じく青い「!」になる（記法の説明はインラインコードの中に書くので、紙面に出ることは無い）。

`{…}` の中の文法:

```
{ 項目 ( 空白 項目 )* }
項目 := .クラス名 | color=値
値   := 空白と } を含まない字の並び
```

`[…]{…}` の `{…}` が、この文法に合わない（`{#id}`・`{width=40%}`・`{foo=bar}`）ときは、変換しない（v2 と同じく、知らない形は字のまま残す）。`foo=` のような知らないキーは §2.3 で 🟡。

### 2.2 蛍光ペン `==文字==`

同じ `InlineSpanTransformer` の中で読み、`{…}` を読む部分を共有する（行末の段落のクラスの扱い・§2.3 の検査が一度に揃う）。

- `==` の**内側の両端が空白でない**ものだけを読む（`a == b`・`x == y == z` は読まない）。1 行の中で閉じるものだけ。
- 読まないもの: コードの中（Masking）、数式の中（`$a == b$`。Masking が数式を守らないなら、数式の範囲を除く）、`=` だけの行（Setext 見出しの下線）。
- 後ろの `{…}` で使える項目は `.クラス名` と `background=値`。
- 原稿の確認（2026-11-26・v2 のセッション）: 本体の原稿の `==` は 2 か所とも（14 章・26 章の表）バッククォートの中。

### 2.3 検査（build と preflight で 🟡）

v2 の `ContainerClassCheck#inline_warnings`（行内の属性の未知のクラス）を写し、次を足す。どれも出現位置（`ファイル:行`）と直し方を添える（`Common.log_warn` の流儀）。

| 原稿 | 警告 | 直し方の案 |
|---|---|---|
| `[字]{.rde}` | 未知のクラス（CSS に無い） | 近い名前 `[字]{.red}` |
| `[字]{color=rde}` | 読めない色の値 | 近い CSS の色の名前 `color=red` |
| `[字]{color=rgb(0,0,0)}` | まだ受けない書き方 | `color=#000000` |
| `[字]{foo=bar}`・`[字]{background=…}` | 知らないキー（文字の色の `[…]` では `color=` だけ） | `==字=={background=…}` の案内 |
| `==字=={color=red}` | 蛍光ペンでは `color=` を書けない | `==[字]{color=red}==` |

v2 の `inline_warnings` は、CSS に無いクラスを「知らないクラス」とする（`stylesheets/**/*.css` から集める）。`.red` などは §4 で CSS に書くので許可される。

### 2.4 `[!]` の色（後処理）

`prism_lines.rb` の `ALERT_COMMENT_PATTERN` を `[!]` の後ろの `{…}` まで読むように広げる。

- `{…}` の文法は §2.1 と同じ（`.クラス名` は §1.1 の 13 個だけ、`color=値`）。
- 色は Ruby の側で値に直し、コメントの span に `style="color: …"` で書く（`codered` のクラスは太字のために残す）。名前は `ThemeColor::PALETTE`、`accent` は `book.yml` の `theme.color`、`color=` は書いた値。値で書くので Kindle にもそのまま届く。
- 読めない名前・値は、色を付けずに既定の赤にし、🟡 で示す（前処理の検査で、コードブロックの中の `[!]{…}` を見る）。
- 記法の説明（`language-markdown` の `<pre>` の中）は今までどおり対象外。

## 3. 出力（中間の HTML）

| 原稿 | HTML |
|---|---|
| `[字]{.red}` | `<span class="red">字</span>` |
| `[字]{.red .small}` | `<span class="red small">字</span>` |
| `[字]{color=#3A9D5D}` | `<span class="vs-color" style="color: #3a9d5d">字</span>` |
| `[字]{.small color=red}` | `<span class="small vs-color" style="color: red">字</span>` |
| `==字==` | `<mark>字</mark>` |
| `==字=={.green}` | `<mark class="green">字</mark>` |
| `==字=={background=#fff3a0}` | `<mark style="--vs-mark-color: #fff3a0">字</mark>`（§4.2） |

- クラス名は書いたとおりに出す（`{.x}` は `class="x"`。v2 の D 型の決まり）。接頭辞は付けない。公式テーマ 7 種（bunko 3.1.1・epub3j 2.1.0・techbook 3.1.1・base 3.1.0・academic・slide・gutenberg 3.1.1）と v2・master の CSS に、13 個の名前と `vs-color` の重なりが無いこと、`mark` の規則を持つテーマが無いことを確かめた（2026-11-26）。epub3j（電書協）の `.color-red`（`#ff0000`）・`.bg-red`・`.em-sesame` は接頭辞つきで、名前が違うので共存する。
- `vs-color` は「値で色を付けた span」の目印で、中のコードに色を受け継がせる規則（§4.1）が使う。
- 値は小文字にそろえて出す。属性値はエスケープする。

## 4. CSS（`stylesheets/chapter-common.css` に節を一つ足す）

### 4.1 文字の色

```css
.yellow  { color: var(--accent-yellow); }
/* … 12 色 … */
.accent  { color: var(--theme-accent); }

/* 中のコード・太字に色を受け継がせる（コードは code.css で、太字はテーマ色で、それぞれ色を持つ） */
:is(.vs-color, .yellow, …, .accent) :is(code, strong) { color: inherit; }
```

- 13 個のクラスは `mark` には当てない（`mark` では淡い地の色を決める。§4.2）。`:not(mark)` を付けるか、`mark:is(…)` で字の色を戻す。
- `.accent` は `--theme-accent`（`book.yml` の `theme.color` で決まる）を読む。

### 4.2 蛍光ペン

```css
mark {
  --vs-mark-color: #fff3a0;           /* 既定の黄色（値は §9 で決める） */
  color: inherit;
  background: linear-gradient(transparent 55%, var(--vs-mark-color) 55%);  /* 55% は §9 で決める */
  box-decoration-break: clone;
}
mark.green { --vs-mark-color: color-mix(in srgb, var(--accent-green) 35%, white); }  /* 割合は §9 */
/* … 12 色と accent … */
```

- 塗る位置の割合は素の `%` で書く。`calc()` と `var()` を `background` の宣言で混ぜない（Vivliostyle が捨てる。`vivliostyle-css-pitfalls-notes.md`）。`linear-gradient` の色の位置の `var()` は効くかを実装で確かめ、効かなければ色ごとに宣言を書き分ける。
- `{background=値}` は `style="--vs-mark-color: 値"` で出す（上の規則がそのまま使う）。
- 行をまたぐ蛍光ペンで、塗りが行ごとに切れるか（`box-decoration-break` を Vivliostyle が扱うか）を紙面で確かめる。

### 4.3 白黒印刷・読みやすさ

- 色の違いは濃さの違いしか残らない（23 章「白黒印刷でも読めるようにする」）。強調したいときは `**…**` と重ねる、と 22 章で案内する。自動で太字にはしない。
- `yellow`・`cyan`・`lime` などの明るい色は、字の色にすると白い紙で読みにくい。22 章で「字には濃い色を」と一言添える。CSS の `red`（`#ff0000`）も白地とのコントラストが 4.0:1 で、`[!]` の赤を `#eb0000` にした理由と同じく少し薄い。選ぶのは著者に任せ、警告はしない。

## 5. EPUB と Kindle

### 5.1 クリーン EPUB

中間の HTML と CSS がそのまま使われる。追加の処理は無い。

### 5.2 Kindle

KFX は `var()`・`color-mix()`・`linear-gradient()` を描かない（`kindle-css-compatibility-notes.md`）。

| 記法 | Kindle での扱い |
|---|---|
| `[字]{.red}` など 12 色 | `body.vs-kindle .red { color: #dc2626; }` のように値で書いた規則を足す。12 色の値は `ThemeColor::PALETTE` で決まっているので、`book_settings_css.rb` で生成する |
| `[字]{.accent}` | `kindle_accent_rules` に `body.vs-kindle .accent { color: <テーマ色>; }` を足す |
| `[字]{color=…}` | style 属性の値がそのまま届く。何もしない |
| `==字==` | 背の全体を塗る（下半分の塗りは描けない）。`body.vs-kindle mark { background: <既定の黄色>; }` |
| `==字=={.green}` | テーマ色を白と混ぜた値（`ThemeColor.mix_with_white`）で、色ごとの規則を足す |
| `==字=={background=…}` | `EpubBuilder` の Kindle の変換で、`mark` の `style="--vs-mark-color: 値"` を `style="background-color: 値"` に書き換える |
| `[!]{…}` | style 属性の値がそのまま届く。何もしない |

- `custom.css` で `--accent-red` などを書き換えた本は、`CUSTOM_CSS` の仕組み（`root_variables`）に 13 個を足し、書き換えた値を Kindle にも届ける。
- これらの Kindle 用の規則は、`book_settings_css.rb` の中の一つのメソッドにまとめ、ほかの規則と混ぜない。v2 では LiteralResolver が部品の層の `var()`・`color-mix()` を値へ解くので不要になり、取り込みのときに外す（§8.1）。
- `<mark>` が KFX で描かれるか（背の色が付くか）は、Kindle Previewer で確かめる。描かれなければ `<span class="vs-mark">` に書き換えるなどの手を、実装のときに決める。

## 6. 索引との関係

`IndexMarkup` に、v2 の `INLINE_ATTRIBUTE_AHEAD`（`]` の直後が行内の属性なら、`[…]` を索引の語として読まない）を写す。v2 は `\{\.` で始まるものだけを除くので、**`\{(?:\.|color=)` へ広げる**（広げないと `[緑]{color=#3a9d5d}` の「緑」が索引の語として拾われる）。行末の段落のクラス（`PARAGRAPH_CLASSES`）は今までどおり索引の語として読む。

`index_match_scanner.rb` にも同じ前提の箇所がある（`IndexMarkup` を使わずに `[…]` を見ているところ）。合わせて確かめる。

## 7. ほかの道具

- **`vs lint`**: `[字]{.red}`・`==字==` の記号を、校正の規則（記号の個数・強調の記法の点検など）が誤って指摘しないか、本体の原稿と haruka_mirai で前後の指摘を突き合わせる（grep で絞らず、全部の指摘を比べる）。`{…}` の中は文ではないので、校正の対象から外す。
- **`vs metrics`**: 字数に `{…}`・`==` を数えない（強調の記号と同じ扱い）。
- **索引の候補の抽出・用語の点検**: `{…}` の中を語として拾わない。

## 8. v2 との関係

v2 のセッション（vivlio-starter-v2-dd）に相談し、整合を確認した（2026-11-26）。

### 8.1 取り込みの手順

- `inline_span_transformer.rb` は、master と v2 の両方で足したファイルとして衝突する。v2 の版を土台にし、master で足した `color=`・`background=`・`==…==` の部分を手で写す。
- 一緒に写すもの: `ContainerClassCheck#inline_warnings`・`IndexMarkup::INLINE_ATTRIBUTE_AHEAD`（§6 で広げた形）・前処理の段の位置。
- CSS は master の `chapter-common.css` に書き、取り込みのときに v2 の `parts/inline.css` へ手で写す（`v2-migration-plan.md` §6.2 の表の扱い）。
- §5.2 の Kindle 用の規則は、v2 では外す（LiteralResolver が解く）。
- 出し方（`style="color: …"`）は、v2 の AuthorPriority（style 属性の同じプロパティにも `!important` を付ける・11/15 ユーザー決定）と合う。

### 8.2 v2 でだけ働くこと

- 縦書きでは、蛍光ペンの「下半分」は字の**左半分**になる（under 側。傍点・ルビは右に付くので重ならない）。`linear-gradient` の向きは物理方向なので、縦書きのページでだけ読み込む `base/vertical.css` に `to left` などの上書きを置く。master は横書きだけなので、横書きの宣言だけで足りる。
- 傍点 `{.sesame}` と色を重ねると、点も字と同じ色になる（CSS の既定どおり。`text-emphasis-color` は指定しない。ユーザー決定）。
- 縦中横の自動（後処理）は `mark` の中も対象。`==12日==` の 12 が塗りの中で縦中横になるかは、v2 の紙面で確かめる。

### 8.3 v2 の仕様の書き換え（取り込みのとき、v2 のセッションが行う）

- `v2-migration-plan.md` §6.3: 11/17 の箇条を「文字の色・コメントの `[!]` の色・蛍光ペンの記法は 1.1.0 で master に作る（2026-11-26 ユーザー決定。11/17 の決定を改めた）。v2 の `inline_span_transformer.rb` の形を master へ写して作り、取り込みでは v2 の版を土台に、master で足した分を写す。1.x に入れる修正の基準の例外とする」の趣旨へ。「v2 → master へ戻さない」はコミットの流れの決まりとして残す。
- `novel-vertical-spec.md` §5.1・`v2-architecture-spec.md` §7.1: 「`{…}` はクラスだけ」を「クラスと `color=`」へ。`==…==` を D 型の記法として足す。
- `theme-contract-spec.md` §2.5: 色のクラス・`vs-color`・`mark` を表に足す。

### 8.4 v2 へ伝えた未解決の点

v2 の `ContainerClassCheck` は、本の `stylesheets/` の CSS だけからクラスを集める。epub3j のテーマで組む本で `[字]{.color-red}`（電書協のクラス）と書くと、効くのに 🟡 が出るおそれがある。公式テーマの CSS がどこから読まれるか（S7a の作り）次第なので、v2 で確かめてもらう（2026-11-26 に伝えた）。master は公式テーマで組まないので関係しない。

## 9. 実装の後にユーザーと決めること

紙面（PDF）と Kindle Previewer で 2〜3 通り組み、ユーザーに見てもらって決める。

- 既定の黄色の値（`#fff3a0` 前後）
- テーマ色を白と混ぜる割合（30〜40% 前後）
- 塗る高さ（下から 40〜50% 前後）

## 10. 文書

| 対象 | 内容 |
|---|---|
| `contents/22-extensions.md` | 節「文字の色と蛍光ペン」を足す（文字の色 2 通り・蛍光ペン・白黒印刷の注意）。`[!]` の節に `{.blue}`・`{color=…}` を足し、表の「（赤色）」を実際の色で見せる |
| `contents/41-book-yml.md` | テーマ色の見本の `<span style=…>■</span>` を `[■]{.red}` などへ |
| `contents/90-notation-cheatsheet.md` | 早見表に文字の色・蛍光ペン・`[!]{…}` を足す |
| `templates/markdown_snippet.md` | 見本帳に足す |
| `CHANGELOG.md` | Added に 3 つ（文字の色・`[!]` の色・蛍光ペン） |

本のページ数が変わるかを確かめる（22 章は 28 ページ・本全体は 283 ページ）。原稿を直したら `ruby scripts/copy_to_scaffold.rb`。haruka_mirai の 15 章の書き換えは、1.1.0 を公開した後に haruka_mirai のセッションへ伝える。

## 11. 確かめ方

**テスト**（Minitest）:

1. 変換: §3 の表の全部。エスケープ・大文字の値・クラスと `color=` の並び。
2. 読まないもの: コード・数式・画像・インライン脚注・`\[`・行末の段落のクラス・`a == b`・`=` だけの行・記法の説明のフェンスの中。
3. 組み合わせ: `[[用語]]{.red}`（索引に載り、赤）・`[緑]{color=#3a9d5d}`（索引に載らない）・表のセル・会話文と `:::{.memo}` の中。
4. `[!]`: 既定・`{.blue}`・`{.accent}`・`{color=…}`・読めない値（既定の赤と 🟡）・`language-markdown` の中は対象外。
5. 検査: §2.3 の表の全部。
6. Kindle: §5.2 の規則が `book-settings.css` に出る・`{background=…}` の書き換え。

**紙面**:

- 本体の本で PDF・EPUB・Kindle の KPF を組む。epubcheck でエラー・警告とも 0。
- Kindle Previewer で、12 色・`accent`・値の色・`mark`（既定・色・値）・`[!]` の色を見る。
- `vs lint` の指摘を前の版と突き合わせる（本体・haruka_mirai）。
- `rake test`・`rake test:standard`。
