# 生成 SVG と Type 3 フォント（`<img>` 参照の独立文書にフォントが届かない）

> 作成日: 2026-08-07
> ステータス: **知見メモ（恒久参照）**
> 対象: PDF へ Type 3 フォントが混入する経路——(A) `<img>` 参照の生成 SVG（§2〜§5）・(B) 疑似太字の合成（§6）・本の書体に無い字（§8・§10）・字の縁取り（§11）——の原因・切り分け手順・採った対策。
> 関連: `fixtures/type3/README.md`（Type 3 を避ける理由と文字別の対策一覧はあちらが正典）, `explanatory-diagram-spec.md`, `mermaid-diagram-spec.md`
> 実測環境: Vivliostyle cli 11.0.2 / core 2.43.2, macOS
> 注記（2026-10-12）: 同梱書体は Zen Old Mincho / Zen Kaku Gothic New から Noto Serif JP / Noto Sans JP（Google Fonts 配信の静的 TTF）へ替えた。以下の実測と例は、当時の Zen の名前のまま残している。

---

## 0. 一行で

**Chromium は「実体のない字面」を Type 3 で埋め込む。** 経路は 2 つ。

- **(A) 生成 SVG**: `<img>` 参照の SVG は独立文書で @font-face が届かず、OS フォントへ落ちる（§2〜§5）
  → 対策: SVG 自身にサブセットフォントを data: URI で持たせる
- **(B) 疑似太字**: Bold 字面の無い書体に太字を要求すると合成される（§6）
  → 対策: 実 Bold を取得し、`font-synthesis-weight: none` で合成を止める

**本の書体の名前のまま Type 3 になっていたら、字の縁取り（`stroke`）を疑う**（§11）。

---

## 1. いつ引くか

- 入稿用 PDF に Type 3 フォントが混入している
- 生成 SVG（showcase / mermaid / 数式）の中の文字だけ書体が違って見える
- `<img>` 参照の SVG に外部リソースを読ませたい

---

## 2. 症状と実測

`techbook: true` の全章ビルドでも Type 3 が **32 件・7 ページ**残っていた（`false` は 186 件・66 ページ）。
`fixtures/type3/README.md` は「混入しない」前提で書かれていたが、実態は違った。

内訳は showcase のラベル 14 件・mermaid の図中テキスト 18 件で、**全件が生成 SVG 由来**。
本文（Zen Kaku Gothic New / Zen Old Mincho）は CID TrueType で正しく埋まっており、faux-bold 合成でもなかった。

---

## 3. 混入源の特定手順

Type 3 フォントの **`FontDescriptor.FontName`** を見れば一目でわかる。ここが OS のフォント名なら
「どこかで書体解決に失敗して OS フォントへ落ちた」が確定する。

```ruby
d = page.objects.deref(ref)                       # Subtype == :Type3 のもの
page.objects.deref(d[:FontDescriptor])[:FontName] # => :"IAAAAA+HiraginoSans-W4"
```

どの文字かは `ToUnicode` の `beginbfchar` を展開する。

```ruby
tu  = page.objects.deref(d[:ToUnicode])
raw = tu.unfiltered_data
raw.scan(/<[0-9A-Fa-f]+>\s*<([0-9A-Fa-f]{4})>/) { [$1.to_i(16)].pack('U') }
```

**⚠️ ToUnicode の逆引きは信用しすぎない。** 今回 `白` が `⽩`（U+2F69 康熙部首）として出た。
Hiragino が字形を共有しているためで、**原稿側に康熙部首があるわけではなかった**。
「原稿に変な文字が混ざっている」と早合点しないこと（実際に一度そう読み違えた）。

---

## 4. 原因: `<img>` 参照の SVG は独立文書

showcase も mermaid も、SVG をファイルへ書き出して `<figure><img src="…svg">` で参照する。
この形では本文 HTML の @font-face が届かない。同梱フォントは
`stylesheets/fonts/` に置いてあるだけで**システムにはインストールされていない**ため、
`font-family` に何を書いても解決せず、OS 既定（macOS なら Hiragino Sans）へ落ちる。

### 4.1 効かなかった案（実測）

| 案 | 結果 |
| :--- | :--- |
| `font-family` に書体名を明記する | **効かない**（フォント自体が届いていない） |
| SVG 内の @font-face を**相対パス**で書く | **効かない**（外部リソースを読めない） |

`showcase` の SVG が元画像を base64 data: URI で埋め込んでいるのも同じ制約が理由。

### 4.2 効いた案

| 案 | Type 3 | SVG サイズ | 依存 |
| :--- | :--- | :--- | :--- |
| @font-face を **data: URI**（フォント丸ごと） | 0 になる | 1.6MB → **4.5MB** | なし |
| @font-face を **data: URI（サブセット）** | **0 になる** | **+1〜5KB** | なし（ttfunk） |
| inkscape でテキストをパス化 | 0 になる | +1KB | inkscape・字形は OS フォント |

---

## 5. 採った対策

`SvgFontEmbedder`（`lib/vivlio_starter/cli/pre_process/svg_font_embedder.rb`）が、
**SVG に出る字だけ**に絞ったフォントを作って @font-face で抱かせる。

- サブセット化は **ttfunk**（Prawn 経由で既に入っている MIT ライブラリ・新規依存なし）
- 8 文字で 3.3KB。和文フォント丸ごと（2〜4MB）と違い SVG は実質太らない
- `base64` gem は Ruby 4.0 で標準添付から外れたので **`[data].pack('m0')`** を使う

呼び出し側で使い分けがある。

- **mermaid**: SVG が既に書体名を名指ししているので、**同名**の @font-face を注げば解決する（テキストの書き換え不要）
- **showcase**: `font-family` が汎用名（`sans-serif`）で @font-face を当てられないため、専用ファミリ名（`vs-showcase-label`）を与える

フォントを解決できない環境では `nil` を返して**従来どおり組む**（Type 3 は残るがビルドは止めない）。

### 5.1 書体の実体を探す場所は 2 つある（2026-08-08 に発見・修正）

`heading_font_path` が `stylesheets/fonts/<slug>/` しか見ていなかった。**Google Fonts は
`stylesheets/fonts/google/<slug>/` に置かれる**（`FontManager#google_fonts_dir`）ため、
同梱以外の書体を指定した瞬間にサブセットを埋め込めず、生成 SVG が OS の和文フォント
（Hiragino）へ落ちて Type 3 が戻っていた。

**ファイル名の規則も違う。**

| | 置き場 | ファイル名 | 太字の見分け方 |
| :--- | :--- | :--- | :--- |
| 同梱書体 | `fonts/<slug>/` | `ZenKakuGothicNew-Bold.ttf` | 接尾辞 `-Bold` |
| Google Fonts | `fonts/google/<slug>/` | `Klee-One-600.ttf` | 末尾のウェイト数値（400 は数値なし） |

`*Bold.ttf` の glob は Google 側に当たらないので、**両方の規則で探す**。実測（`Klee One` で
22 章を単章ビルド）は修正前 27 件 → 修正後 22 件。残る 22 件は同梱書体でも同数出るので
単章ビルド（`:single` モード）固有のもので、この経路とは無関係。

回帰は 2 段で押さえる。`svg_font_embedder_test.rb`（実フォント不要・`rake test` に入る）が
探索規則そのものを、`google_fonts_type3_test.rb`（`rake test:type3`）が全章ビルドでの
Type 3 = 0 を見る。

**書体をキャッシュ鍵に含めること。** showcase は画像・切り抜き・注釈だけで鍵を作っていたため、
著者が `typography.heading.font` を変えても SVG が作り直されず、古い書体を抱えたまま残った
（mermaid は最初から `font_family` を鍵に含めていた）。スキーマ版を `v1`→`v2` へ上げて是正済み。
この取りこぼしは検証も歪める——書体を替えたつもりのビルドが前の書体のキャッシュを再利用し、
「対策が効いている」ように見えてしまう。

### 5.2 生成 SVG は独立文書なので合成禁止も届かない（2026-08-08）

`showcase_svg_builder.rb` はラベルを `font-weight="700"` で組むが、SVG に埋め込む
`@font-face` は 1 面だけ＝ウェイト指定なし＝**400 扱い**。本文側の
`body { font-synthesis-weight: none }` はこの独立文書に届かないので、
太字を持たない書体では faux-bold が合成されて Type 3 になる。

対策は本文と同じ。SVG の `<style>` にも `svg{font-synthesis-weight:none}` を出す
（showcase・mermaid の両方）。

### 5.3 合成禁止は疑似要素へ継承されない（2026-08-08）

`chapter-common.css` の `.outline-list ol > li::before` は
`content: counters(vs-outline, ".") ". "` を **`font-weight: 700`** で描く。
`font-synthesis-weight` は継承プロパティなので `body` の指定で足りるはずだが、
**Vivliostyle では `::before` / `::after` の生成ボックスに届かなかった**。
実測（`Yusei Magic` で 22 章を単章ビルド）で `1.` `2.` `3.` が Type 3 になっていた
（ToUnicode で数字＋ピリオドと確認）。

そこで `body` だけでなく疑似要素まで明示する。

```css
body, body *, body *::before, body *::after { font-synthesis-weight: none; }
```

「CSS は正しいのに効かない」の一例なので `vivliostyle-css-pitfalls` にも一行入れてある。

### 5.4 結果

| | Type 3 |
| :--- | ---: |
| 修正前 `techbook: false` | 186 件・66 ページ |
| 修正前 `techbook: true` | 32 件・7 ページ |
| showcase 修正のみ | 18 件・2 ページ |
| **showcase + mermaid 修正** | **0 件・0 ページ** |

回帰は `rake test:type3` が押さえる（`TRUE_TYPE3_CEILING = 0`）。

---

## 6. もう一つの経路: 疑似太字（faux-bold）

§2〜§5 は「生成 SVG」の話。**Type 3 にはもう一つ、フォント設定に起因する経路がある。**

### 6.1 症状

`typography.body.font` / `heading.font` に **Google Fonts の書体**を指定すると Type 3 が出る。
実測（2026-08-07・1 章のサンプルビルド 25 ページ）: **Type 3 が 195 件・22 ページ**。

RC 以前の `book.yml` は `body: Noto Serif JP` / `heading: Noto Sans JP` で、
このとき Type 3 が判明して急遽ラスタライズで凌いだ経緯がある。

### 6.2 原因は「書体」ではなく「取得したウェイト」

`fetch_google_css` が `family=<名前>` だけで要求していたため、Google は
**既定の 400 を 1 面返すだけ**だった。見出しや `**強調**` は太字を要求するので、
Bold 字面が無い → Chromium が faux-bold を合成 → Type 3。

同梱書体は Regular/Bold の 2 面を持つので踏まない。ディレクトリを並べると分かる。

```
stylesheets/fonts/Zen_Kaku_Gothic_New/          ← 同梱: 2 面
  ZenKakuGothicNew-Regular.ttf / -Bold.ttf
stylesheets/fonts/google/Noto_Sans_JP/          ← 旧: 1 面しかない
  Noto-Sans-JP.ttf
```

### 6.3 日本語 Google Fonts 55 書体の調査（2026-08-07 実測）

| 観点 | 結果 |
| :--- | :--- |
| アウトライン | **55 書体すべて静的 TrueType**（`glyf` あり・`CFF `/`fvar` なし） |
| 太字（600 以上）を持つ | **24 書体** |
| 太字が無い（400 のみ） | **31 書体** |

装飾書体（`Dela Gothic One` `Hachi Maru Pop` `Yusei Magic` `DotGothic16` `Yuji Syuku` 等）は
そもそも太さのバリエーションを持たない設計で、**過半数が Regular 1 面だけ**。

**太字のウェイトは書体ごとに違う。** `700` 決め打ちは通用しない。

```
Klee One             400, 600            ← 700 が無い（600 が太字）
M PLUS 1p            100, 300, 400, 500, 700, 800, 900   ← 600 が無い
Zen Kaku Gothic New  300, 400, 500, 700, 900
```

`wght@400;700` を要求しても Google は**エラーにせず 400 だけ返す**ので、欠落に気づけない。

**全書体が静的 TrueType なのは、`perform_get` の User-Agent がブラウザでないことに依存している**
（Google は未知の UA に旧来の静的 TTF を配信する）。可変フォント主体の書体（Inter / Roboto Flex /
Recursive）でも静的インスタンスが返る。この前提が変わると全書体が一斉に Type 3 化しうるため、
ダウンロード後にテーブルを検査して見張っている（`warn_unless_static_truetype`）。

### 6.4 採った対策

1. `family:wght@100;…;900` で要求し、**返ったウェイトを列挙**する
2. **400 と「600 以上で 700 に最も近いもの」の 2 面だけ**を残して落とす
   （全ウェイトだと和文 1 書体で数十 MB になる）
3. `body { font-synthesis-weight: none; }` を常時出力し、合成そのものを止める。
   **実 Bold がある書体には影響しない**——実体があるとき合成は起きないため
4. 3 だけだと強調が標準の太さになって埋もれるので、**本文書体に太字が無いときに限り**
   `strong, b { font-family: var(--font-header); }` を足す。
   明朝の強調にゴシックを当てるのは和文組版の作法でもある
5. 太字を持たない書体が選ばれたら、代用が起きる理由とともに警告する

同梱書体は 2 面あるので 4 は発動せず、既存の本の見た目は変わらない。

### 6.5 font-synthesis の実測

| ケース | Type 3 | 使われたフォント |
| :--- | ---: | :--- |
| 一面のみ + `font-weight: 700` | 7 件 | Type3 NotoSansJP-Regular |
| 一面のみ + `font-synthesis-weight: none` | **0 件** | Type0 NotoSansJP-Regular（太くならない） |
| 二面あり + `font-synthesis-weight: none` | **0 件** | Type0 NotoSansJP-**Bold** |

本文強調をゴシックへ振った場合も 0 件で、かつ**強調が視覚的に成立する**（合成禁止だけだと埋もれる）。

---

## 7. 落とし穴

- **`vs build` はインストール済み gem を使う。** `lib/` を直しても反映されないので、
  検証は `ruby -Ilib bin/vs build`（テストの `VsBuilder.repo_vs_command` と同じ）か `rake reinstall` の後で行う。
  これを踏むと「修正したのに数字が変わらない」で長く迷う。
- **生成物は `GeneratedAssetCache` に永続キャッシュされる。** SVG の作り方を変えたら
  `.cache/vs/showcase` `.cache/vs/mermaid` を消してから確かめる（キーは図ソースのハッシュなので、
  生成ロジックを変えてもキーは変わらない）。
- **広い `rescue StandardError` は実装ミスを隠す。** 今回 `Annotation` に無い `label` を呼ぶ
  NoMethodError を握り潰し、「静かに埋め込まれない」状態を作った。純関数側に単体テストを置いて
  ラベル収集を固定してある（`showcase_svg_builder_test.rb`）。

---

## 8. もう一つの経路: 同梱書体に無い文字（2026-08-21）

**症状**: 全章ビルドで Type 3 が 1 件。`pdffonts -f 303 -l 303` が
`TAAAAA+.SFNS-Regular  Type 3` を出す——**macOS のシステム書体**である。

`.SFNS-Regular` が出たら、この経路を疑う。SVG でも疑似太字でもなく、
**同梱書体が持っていない文字を Chromium が OS の書体へフォールバックさせた**結果である。

### 見つけ方

font名が `.SFNS`（macOS）や `DejaVu`（Linux）のような**システム書体**なら、原稿に
「その書体で出せない文字」がある。当該ページの本文から候補の文字を拾い、`ttfunk` で
cmap を引けば確定する。

```ruby
require "ttfunk"
cmap = TTFunk::File.open("stylesheets/fonts/hackgen35/HackGen35ConsoleNF-Regular.ttf").cmap.unicode.first
cmap[0x2099].to_i.zero?   # true なら ₙ を持っていない
```

### 実例

`92-latex-cheatsheet.md` の下付きの例に ``` ``aₙ`` ``` と書いていた。`ₙ`（U+2099）は
**HackGen35 Console にも ZenOldMincho にも無い**。数字の下付き（`₀`〜`₉`）・`ₐ`・`ₑ`・`ₓ`
はあるが、`ᵢ` `ₖ` `ₙ` は無い——**「下付き文字は全部ある」と思い込まないこと。**

### なぜ数式では起きないか

`$a_n$` や `` `aₙ` ``（1 重バッククォート）は**数式と判定されて SVG になる**ので、
グリフではなくパスで描かれ、書体の対応に依存しない。踏むのは
**2 重バッククォート（記法をそのまま見せる形）と地の文**だけである。
記法解説書はまさにそこを書くので、この本は構造的に踏みやすい。

### 対策

原稿側で**同梱書体が持つ文字に置き換える**（`aₙ` → `a₁`）。書体を足す方向は採らない——
1 文字のために配布物が重くなるうえ、`vs new` した著者の環境でも同じ判断が要る。

> **2026-10-29 に方針を改めた（§10）。** spiral-ruby で、コードと図の 14 か所に同じ型の字が出た。
> 著者に 1 字ずつ書き換えさせるのは重く、コードの `sᵢ₊₁` のように書き換えると意味が変わる字もある。
> 予備の書体（DejaVu Sans Mono・DejaVu Sans）を同梱し、字はそのまま組むことにした。

**単章ビルドでは出ないことがある。** 判定は全章ビルドで行う（§3 と同じ）。

---

## 9. 三つめの経路: 著者が `images/` へ置いた SVG 図版（2026-09-10）

§2〜§5 は showcase / mermaid の**生成** SVG の話で、対策もそこにしか入っていなかった。
**著者が自分で描いて `images/` へ置いた SVG は素通りだった。**

### 9.1 症状

`vs build 22-extentions`（単章）で組んだ 22 章の PDF に、`HiraKakuProN-W3` の
Type 3 が 16 ページ目だけで **17 件**。原因は `images/22-extentions/permille-coordinates.svg` で、
中は `font-family: sans-serif` の 1 行だった。独立文書では汎用名は何も解決せず、
OS 既定（Hiragino）へ落ちる——§4 とまったく同じ話である。

### 9.2 なぜ全章ビルドでは見えなかったか

`techbook: true` の全章ビルドでは、`ImageOptimizer.optimize_images!` が `images/` の SVG を
rsvg-convert で 350 DPI の WebP へ焼き、`Techbook::Processor#rewrite_svg_references!` が
`<img src="…svg">` を `.webp` へ差し替えていた。Type 3 は出ないが、**ベクタが失われる**。

単章ビルドは `SINGLE_MODE_SKIP` で techbook 後処理を飛ばすため（Type 3 対策は入稿の関心事で
プレビューには要らない、という判断）、差し替えが走らず素の SVG が Chromium へ渡る。
**「単章だけ Type 3 が出る」のはこの差**であって、書体設定の問題ではない。

### 9.3 採った対策

`DerivedSvg`（`lib/vivlio_starter/cli/build/derived_svg.rb`）が、pdf/ のステージング時に
**書体を抱かせた複製**を `.cache/vs/derived/pdf/` へ作り、`<img src>` をそちらへ向ける。
`DerivedImage`（ラスタの派生）と同じ流儀で、**素材には触れない**。

生成 SVG と違い、著者の図版は何の書体を何面使うか決め打ちできない。そこで:

| 図の書き方 | 派生でどうなるか |
| :--- | :--- |
| `font-family="Noto Sans JP", …`（実体のある書体が先頭） | **並べ替えない**。同名の @font-face を注ぐだけ |
| `font-family="Hiragino Sans", "Noto Sans JP", …`（実体のある書体の手前に OS の書体） | 実体のある書体を先頭へ出す。手前のままだと書いた人の PC のヒラギノが選ばれ Type 3 になる（2026-10-12・37 章の図 2 枚で 45 件） |
| `font-family: sans-serif` | 先頭へ見出し書体を足す（`Noto Sans JP, sans-serif`） |
| `font-family: serif` | 先頭へ本文書体 |
| `font-family: monospace` | 先頭へコード書体 |
| 指定なし | `svg{font-family:…}` を注いで見出し書体へ寄せる |

太字は **400 と 700 を別々に埋める**。生成 SVG は 1 面で足りていた（ラベルの太さが揃う）が、
著者の図版は本文と同じように太字を混ぜるためである。

### 9.4 実測（22 章・単章ビルド）

| | Type 3 |
| :--- | ---: |
| 対策前 | 40 件（うち `HiraKakuProN` 35 件・6 ページ） |
| **対策後** | **5 件（すべて `AppleColorEmoji`）** |

残る 5 件は単章で techbook 後処理を飛ばしているぶんの絵文字で、この経路とは無関係
（全章ビルドでは Twemoji 画像へ差し替わる）。図版の書体は本文と同じ
`ZenKakuGothicNew-Regular` / `-Bold` の CID TrueType として埋まる。

### 9.5 副産物: コード書体の実体が引けていなかった

`font_path` は `fonts/<slug>/` を見るが、`HackGen35 Console NF` の実体は
**`fonts/hackgen35/`** に置かれている（page-settings.css が実ファイルを直に指しているだけで、
slug 規則には従っていない）。slug で引けないときは中身のファイル名から引き当てるようにした。
これが無いと、等幅で組んだ図だけサブセットを作れず Type 3 が残る。

### 9.6 EPUB へも同じ派生を配る（2026-09-10）

当初 `DerivedSvg` は PDF 枝に閉じていたが、調べると **EPUB の図はもっと悪い状態だった**。

#### ラスタライズでは書体が運べない

`rsvg-convert`（librsvg）は **data: URI の @font-face を読まない**。素材 SVG と書体を
埋め込んだ派生 SVG をラスタライズした PNG が、バイト単位で一致する。

```
44b31d453e59fa00a4fe8f06f647dbd8a19eb624  A-raw.png       ← 素材（font-family: sans-serif）
44b31d453e59fa00a4fe8f06f647dbd8a19eb624  B-embedded.png  ← 派生（@font-face を data: URI で内包）
```

**macOS では fontconfig に登録しても見えない。** `stylesheets/fonts/` を `FONTCONFIG_FILE` で
登録すると `fc-match "Zen Kaku Gothic New"` は実体を返すが、同じ設定で rsvg-convert の出力は
1 バイトも変わらない（Homebrew の pango が CoreText を使うため）。`font-family` 自体は効いている
——`Courier New` は別出力になる——ので、**OS にインストール済みの書体しか使えない**が正しい。

その結果、**焼いた図には「そのとき使った機械の既定書体」が焼き付く**。著者の SVG（techbook の
WebP）も、mermaid / showcase の対ラスタも Hiragino で描かれていた。別の Mac で組めば別の書体、
Linux の CI なら DejaVu になる。**成果物が再現しない。**

#### EPUB は本文書体を埋め込まない

`EpubBuilder#embed_fonts?` は `false` を返す。EPUB の本文は読者が選んだ書体で組まれるので、
「図を本文と揃える」という目標が EPUB には最初から存在しない。図が拠れる書体は
**図自身が持つものだけ**である。

#### 採った方針

| ターゲット | 形式 | 書体 | 決定論 |
| :--- | :--- | :--- | :--- |
| PDF | SVG（ベクタ） | 書籍の書体（サブセット内包） | ○ |
| EPUB（Kobo / Apple） | 同じ派生 SVG | 書籍の書体（同上） | ○ |
| Kindle | PNG / JPEG | OS 書体 | × |

EPUB 3.3 で `image/svg+xml` はコアメディアタイプで、Apple Books と Kobo は WebKit 系なので
data: URI の @font-face を解する。効かない端末に当たっても**端末既定の書体で字は出る**
——対策前と同じ状態に戻るだけで、壊れ方が穏やかである。

Kindle だけは KFX が SVG を扱えないので `stage_author_svg_for_epub!` が焼く。書体が OS 依存に
なるのは見出し画像（`heading_image_src`）が既に受け入れている割り切りと同じで、この経路で
新たに悪くなるものはない。形式は透過があれば PNG・無ければ JPEG（WebP 経路と同じ規則）。
**Kindle まで決定論にしたければ Chromium で焼くしかない**（`rotate_table_images.rb` が
「組み上がったページを pdftoppm で画像化する」同じ手口を使っている）。図の枚数ぶんレンダを
回す重さと引き換えなので、必要になった時点で判断する。

#### 併せて外したもの

- `ImageOptimizer.optimize_images!` の SVG ラスタライズ対象から `images/` を外した（絵文字だけ残す）
- `Techbook::Processor#rewrite_svg_references!` を `stylesheets/` の生成物に限定した
  ——著者の `images/` を拾うと、過去のビルドが残した `.webp` を掴んで元の挙動へ戻ってしまう

副産物として、機械が `images/` へ書き込むことがなくなった（`image-format-per-target-spec.md` §3.5）。

#### 実測（全章ビルド・PDF + EPUB）

| | 結果 |
| :--- | :--- |
| PDF の Type 3 | **0 件** |
| EPUB 内の図版 | `images/_epub_assets/*.svg` 14 枚、**全件が `data:font/ttf` を内包** |
| 差し替えた元 SVG | パッケージから落ちている（文字を持たないロゴ・QR は素材のまま） |

---

## 10. 本の書体に無い字を予備の書体で組む（2026-10-29・改善案 #127）

§8 の字（`ₙ`・`ᵢ`・`⌃`・`⟹` など）と、図の SVG で図の書体に無い字（`≒`・`ⁿ`・`∛`）を、原稿を
書き換えずに組む。予備の書体の並びは `SvgFontEmbedder::FALLBACK_FONTS` の 1 か所で決める:
**HackGen → DejaVu Sans Mono → DejaVu Sans**。

### 10.1 同じ書体名の面を足し、unicode-range で絞る

書体の並び（`font-family`）は書き換えない。予備の書体を、**補いたい書体と同じ書体名**の
`@font-face` として後ろに足し、`unicode-range` をその書体に無い字だけに絞る。同じ名前の面が
重なる字は後の面が優先されるので、補った字だけが予備の書体で組まれる。

- 本文の HTML: book-settings.css が `"HackGen35 Console NF"` の名前で DejaVu の面を出す。HackGen を
  並びに含む本文・見出し・コラム・コード・ノンブルのすべてで、HackGen の次に DejaVu が探される。
  雛形の page-settings.css を書き換えないので、`vs upgrade` で CSS を上げなくても効く（書体のファイルは
  雛形と一緒に届く。ファイルが無ければ面を出さない）
- 図の SVG: DerivedSvg が、図に埋める書体ごとに、その書体の名前で予備の書体の部分集合を足す
  （`SvgFontEmbedder.fallback_face_rules`）。図の `font-family` を書ける 3 か所とルートの既定を
  直さずに済む

並びを書き換える方法を採らなかったのは、書ける場所が多く（CSS 変数・著者の CSS・図の 3 か所）、
著者が書体を差し替えたときに予備が外れるからである。

### 10.2 書体の選び方（実測）

候補を、HackGen に無い字がどれだけ拾えるかと字幅で比べた（spiral-ruby の 6 字 `⌃ ᵢ ₙ ᵖ ⟹ ⟺`）。

| 書体 | 6 字 | 字幅 | 太字 | 大きさ |
| :--- | :--- | :--- | :--- | ---: |
| DejaVu Sans Mono | `⌃ ᵢ ₙ ᵖ`（長い矢印なし） | 0.6 字（HackGen の半角と同じ） | あり | 2 面で 0.7MB |
| DejaVu Sans | 6 字すべて | 字ごとに違う（`⟹` は 1.43 字） | あり | 2 面で 1.4MB |
| STIX Two Math | `⌃ ⟹ ⟺` | — | **なし** | 1.5MB |
| Noto Sans Math | `⟹ ⟺` | — | **なし** | 1.0MB |

太字の無い書体は、太字の所で疑似太字になって Type 3 に戻る（§6）ので外した。Mono を先に置くと、
コードの桁がそろう。長い矢印は等幅の書体に無いので、DejaVu Sans で組まれ、その字の所だけ桁がずれる。

### 10.3 補わない字

絵文字（`\p{Extended_Pictographic}`）は補わない（`FALLBACK_EXCLUDED`）。DejaVu は `✌` などを白黒の字で
持つが、techbook は地の文の絵文字を twemoji の色付きの画像で組むので、それとそろえる。
図の SVG の中の絵文字は、中身が絵文字だけの `<text>` を twemoji の図形に差し替えて組む（`FigureEmoji`）。
色付きの絵文字の書体を埋める方法は採らなかった。Apple Color Emoji が Type 3 になったのと同じく、色付きの字形は
Type 3 で書き出される見込み（COLR の書体では確かめていない）。
`GlyphCoverageCheck` も、予備の書体の絵文字は「ある」と数えない。

### 10.4 実測（spiral-ruby）

`vs preflight` の「本の書体にない字」は 14 件 → 0 件（図の中の絵文字 `✊✌✋` は FigureEmoji で twemoji の図形に）。単章ビルドの
11・32・51・52・53 章の PDF に Type 3 と OS の書体は無く、DejaVuSansMono・DejaVuSans が
埋め込まれた。コードの `sᵢ₊₁ = sᵢ² − 2` は 1 字 0.6 字の幅のまま組まれ、上の行と `=` の位置がそろう。

### 10.5 本の書体にない漢字（外字）は、字の形を図形にする（2026-10-30）

予備の書体は記号を受け持つが、漢字（`祖暅` の `暅`）は持たない。外字の書体を足していくと切りがないので、
その字を持つ書体から字の形を取り出し、PDF に入れる HTML の中でインラインの `<svg>` に替える（`Gaiji`）。

- 字の形を取る書体: OFL の書体（著者が入れた思源宋体など）と、macOS 付属の書体のうち埋め込みを許すもの。
  macOS Tahoe 26 の使用許諾 第 2 条 E は、文書への埋め込みを「当該フォントに付属する埋め込み制限で
  許可されている場合のみ」認める。宋体・ヒラギノは fsType が「編集可」（0x0008）、宋体 SC Black だけ
  「埋め込み不可」（0x0002）。第 2 条 N（複製・二次的著作物の禁止）に配慮し、付属の書体の形は
  プロジェクトに保存しない
- 付属の 3 書体（宋体 SC・TC、ヒラギノ角ゴ簡体中文）で、統合漢字 20,992 字・拡張 A 6,592 字をすべて持つ
- 輪郭の読み取り（`GlyphOutline`）: CFF は TTFunk の `Cff::Charstring#path`。TrueType は TTFunk が
  `glyf` の座標を読まないので、flags と座標の差分を自前で読み、曲線の外の点が続く所は中点を補って
  2 次ベジェにする。複合の字形（部品を組み合わせた字）は読まず、次の書体を探す
- 宋体は字面の枠が日本の書体と違う（860〜-140）うえ、字の形が枠の中で下寄りなので、字の黒い部分の
  上下の中心を字面の中心にそろえる
- 図形は `fill="currentColor"` で周りの字の色に従う。`<img>` にすると色が付かない（太字の強調は色付き）

### 10.6 数学用英数字（`𝔽`・`ℝ`）は数式に包む（2026-10-30・改善案 #130）

数学用英数字（996 字）は、本の書体の並びに 180 字しか無い。地の文の字は前処理で `$…$` に包み、MathJax に
図形として描かせる（`MathLetterWrapper`）。MathJax は Unicode の数学用英数字をそのまま読む（`$𝔽$` と
`$\mathbb{F}$` は同じ形）。ただし MathJax の書体に無い字が 308 字あり、包んでも数式の画像の中に `<text>` の
まま残る。これらは包まず、PDF では `Gaiji` が STIX Two Math（macOS 付属・OFL）から字の形を取る。
描けるかどうかの判定は、1 字ずつ `$…$` で組んで SVG に `<text>` が残るかで測った（`MATHJAX_MISSING`）。
mathjax-full の版を上げたら測り直す。

---

## 11. 字の縁取りは、書体を埋めていても Type 3 になる（2026-10-30・改善案 #129）

図のラベルの白い縁取り（`stroke`・`paint-order="stroke"`）は、字が本の書体にあり、図に書体を埋めていても
Type 3 になる。§9・§10 の経路とは違い、書体の解決は成功している。

### 11.1 見分け方

`pdffonts` で、**同じ書体名が Type 3 と CID TrueType の両方に出る**。

```text
AAAAAA+f9c564_NotoSansJP-Regular     Type 3            Custom           yes yes yes
AAAAAA+f9c564_NotoSansJP-Regular     CID TrueType      Identity-H       yes yes yes
```

`f9c564_` は TTFunk が部分集合の書体名の頭に付ける印で、図に埋めた書体であることを示す
（`Type3FontCheck::FIGURE_SUBSET_NAME`）。本文の書体にはこの印が無い。

### 11.2 4 通りの比較（lives-mathematics の `liuhui-polygons.svg`・ラベル 10 個）

| 描き方 | Type 3 | 図 1 枚の PDF | `pdftotext` の字 | 縁の形 |
| :--- | :--- | :--- | :--- | :--- |
| 元の図（`<text stroke paint-order>`） | 2 件 | 105 KB | 2 回ずつ | 元の形 |
| 縁だけの `<text fill="none" stroke>` と本体の `<text>` に分ける | 2 件 | 105 KB | 2 回ずつ | 元の形 |
| 塗りだけの字を 16 方向へずらして重ねる | 0 件 | 16 KB | 4 回ずつ | 波打つ |
| **字の輪郭の `<path>` に stroke を掛け、本体の `<text>` を重ねる** | **0 件** | 31 KB | **1 回ずつ** | 元の形 |

字を分けるだけでは直らない。stroke の掛かった字が 1 つでも `<text>` にあると Type 3 になる。
4 番目を採った（`StrokedText`）。字の本体は `<text>` のままなので、PDF の検索と字の抜き出しは元より良くなる。
ずらす案は縁の精度を方向の数でしか上げられず、検索にも余分に当たる。

### 11.3 決めたこと

- **PDF の派生の中だけで組み替える**（`DerivedSvg.prepare_for_pdf`・`.cache/vs/derived/svg-pdf/`）。Type 3 は PDF だけの
  問題で、Kindle は図を OS の書体で焼く（§9.6）ので、本の書体の輪郭の縁では字とずれることがある。縁取りの
  無い図は EPUB と同じ派生を指し、書体を 2 回埋めない
- **字の送りを足すだけで位置が合う**。図に埋める部分集合（`TTFunk::Subset`）は GPOS を持たないので、図の字に
  kern は当たらない（本文の `FontMetrics#kern` とは事情が違う）。新旧の PDF を 200 dpi で比べて、見て分かる差は無かった
- **`stroke-linejoin` などは著者の値を写す**。既定は `miter` で、字の角に尖りが出るが、元の見た目を変えない
- **`<style>` の規則の縁取りも組み替える**（`StrokedText::Cascade`）。規則どうしは書いた順だけを見て、詳細度は見ない
- **字の位置を読めないものは組み替えず、知らせる**（`<tspan>`・`dx`/`dy`・`x` の複数指定・`letter-spacing`・
  `dominant-baseline`・`em` の大きさ・`stroke-dasharray`・書体が見つからない字・複合の字形）。preflight と build が
  図の名前と字を添えて 🟡 で知らせ（`GlyphCoverageCheck.stroked_figures`）、`Type3FontCheck` は重ねて言わない
- 複合の字形（TrueType の部品の組み合わせ）を `GlyphOutline` は読まない。同梱の Noto Sans JP・Noto Serif JP・HackGen の
  見本に複合の字形は無く、DejaVu の `é`・`½` などだけが当たる。読めない字のあるラベルは知らせに回る

### 11.4 PDF の確かめの案内

`Type3FontCheck` は書体の名前で「本の書体のまま Type 3」を見分け、「本の書体にある字に置き換える」ではなく
縁取りを外す案内を出す。図の縁取りは組み替えるので、ここへ来るのは組み替えの外の経路（原稿に直に書いた `<svg>`・
CSS の `-webkit-text-stroke`）で、図の名前は分からない。疑似太字も同じ書体名で出るので、案内に併記した。

### 11.5 実測（lives-mathematics・3 巻の全章ビルド・2026-10-30）

| 巻 | Type 3（前） | Type 3（後） | ページ数 | PDF の大きさ |
| :--- | :--- | :--- | :--- | :--- |
| 上巻 | 3 | 0 | 213 → 213 | 30.15 MB → 30.05 MB |
| 中巻 | 4 | 0 | 233 → 233 | 36.70 MB → 36.65 MB |
| 下巻 | 5 | 0 | 193 → 193 | 26.53 MB → 26.48 MB |

10 枚の図の 54 個のラベルをすべて組み替え、preflight の知らせは 0 件。Type 3 のあった 10 ページを新旧で描いて
比べた（200 dpi）。差は 1 ページあたり最大 90 画素相当で、拡大しても縁と字の位置は重なった。
