# 生成 SVG と Type 3 フォント（`<img>` 参照の独立文書にフォントが届かない）

> 作成日: 2026-08-07
> ステータス: **知見メモ（恒久参照）**
> 対象: PDF へ Type 3 フォントが混入する 2 つの経路——(A) `<img>` 参照の生成 SVG（§2〜§5）と (B) 疑似太字の合成（§6）——の原因・切り分け手順・採った対策。
> 関連: `fixtures/type3/README.md`（Type 3 を避ける理由と文字別の対策一覧はあちらが正典）, `explanatory-diagram-spec.md`, `mermaid-diagram-spec.md`
> 実測環境: Vivliostyle cli 11.0.2 / core 2.43.2, macOS

---

## 0. 一行で

**Chromium は「実体のない字面」を Type 3 で埋め込む。** 経路は 2 つ。

- **(A) 生成 SVG**: `<img>` 参照の SVG は独立文書で @font-face が届かず、OS フォントへ落ちる（§2〜§5）
  → 対策: SVG 自身にサブセットフォントを data: URI で持たせる
- **(B) 疑似太字**: Bold 字面の無い書体に太字を要求すると合成される（§6）
  → 対策: 実 Bold を取得し、`font-synthesis-weight: none` で合成を止める

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

### 5.1 結果

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
