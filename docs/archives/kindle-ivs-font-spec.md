# Kindle の異体字（異体字セレクタ）を 1 字書体で出す 仕様書（案）

> **状態**: 実装済み（2026-10-12）。Kindle Previewer 4 で確認済み（§8）。
> 関連: `kindle-inline-math-textify-spec.md`（画像では文字の大きさに追従できない、という同じ制約から出発した前例）、
> `type3-font-embedding-notes.md`（TTFunk によるサブセットの作り方）、`kindle-css-compatibility-notes.md`。

## 0. 結論（先出し）

- **Kindle（KFX）は異体字セレクタを読まない。** `禰󠄀`（U+79B0 U+E0100・ネ偏）は、文字のまま組まれる場所（本文・コラム・リスト・h3 以下）ではすべて親字の示偏に戻る。
  画像になる h1・h2 は Mac の書体で焼かれるので正しく出る（§1）。
- **原稿に出てくる「親字＋セレクタ」の字形だけを集めた小さな書体を作り、Kindle 用の出力にだけ埋め込む。**
  この書体では**セレクタの付かない親字そのものが異体の字形を指す**。本文の該当箇所はセレクタを外した親字を
  `<span class="vs-variant-N">` で囲み、その書体を当てる（§2）。
- 文字のままなので、**文字の大きさの変更・ダークモード・検索に自然に従う**。画像（SVG）案は大きさに追従できないので採らない（§6）。
- **PDF とクリーン EPUB は変えない。** どちらも異体字セレクタのまま正しく出ている（PDF は同梱 Noto、Apple Books は OS の書体が読む）。
- 書体に字形が無い組（文字情報基盤のセレクタなど）は、**ビルド時に出現箇所つきで警告する**（§4）。
- 読者が Kindle の書体を「ゴシック」に切り替えても、この字は本文書体（明朝）のまま残る。**許容する**（2026-10-12 決定・§1.2）。

## 1. 現状（2026-10-12 の確認）

`variation-selector-sample.md`（未追跡の確認用原稿）を 1 章だけのプロジェクトで組み、Kindle Previewer 4 と Apple Books で見た。

| 場所 | PDF | クリーン EPUB（Apple Books） | Kindle（KPF） |
|---|---|---|---|
| h1・h2（合成画像） | ネ偏 | ネ偏 | ネ偏（変換機の書体で焼かれる） |
| h3 | ネ偏 | ネ偏 | **示偏** |
| 本文・コラム・リスト | ネ偏 | ネ偏 | **示偏** |

EPUB の XHTML には U+E0100 が 20 か所とも残っている。Kindle が組むときに捨てている。

### 1.1 試作

Kindle 用の中間 EPUB を手で書き換えて KPF を作り、Kindle Previewer 4（phone）で確かめた。

1. Noto Serif JP / Noto Sans JP（Regular・Bold）の cmap format 14 から `U+79B0 U+E0100` の字形 ID を引き、
   TTFunk で「U+79B0 → その字形」だけを持つ書体を作った（1 本約 1.8KB）。
2. 本文の `禰󠄀` 6 か所を `<span class="vs-ivs">禰</span>` に置き換え、book-settings.css に `@font-face` と規則を足した。

結果: h3・本文・コラム・リストともネ偏で出た。**文字の大きさ 1〜5 に追従した。** KPF の増分は約 11KB。

### 1.2 試作で分かった制限

- 読者が書体をゴシックに切り替えても、この字は明朝のまま残る。埋め込み書体は Kindle の書体設定に従わないため。
  1 字だけの違いで、形の正しさのほうが大事なので**許容する**（2026-10-12 決定）。
- 目次（ナビゲーション）は Vivliostyle が見出しから作る。ここは本文の書き換えが届かないので親字のまま出る（§7）。

## 2. 方式

### 2.1 対象とする並び

```ruby
VARIATION_SEQUENCE = /(\p{Han})([\u{FE00}-\u{FE0D}\u{E0100}-\u{E01EF}])/
```

- **IVS（U+E0100〜E01EF）** と、CJK 互換漢字の**標準異体字シーケンス（U+FE00〜FE0D）**。
- 絵文字の表示切替（U+FE0E・FE0F）は対象外。数学記号の SVS（`≩︀` など）も、親字を `\p{Han}` に限ることで外す。
- 探すのは `<body>` の中の**テキストノードだけ**。`id`・`alt`・`data-*` などの属性と `<title>` は変えない
  （アンカーの一致と読み上げを壊さないため）。`<script>`・`<style>` の中も見ない。

### 2.2 字形の引き方（cmap format 14）

書体の cmap format 14 を読み、組ごとに次のどれかに分ける。

| 種類 | 意味 | Kindle での扱い |
|---|---|---|
| 非既定（non-default UVS） | 親字と違う字形 ID が割り当ててある | **1 字書体へ入れ、置き換える** |
| 既定（default UVS） | 親字と同じ字形を使う | 何もしない（Kindle は親字を出す＝正しい形） |
| 無し | 書体がこの組を知らない | 何もしない。**警告する**（§4） |

同梱の Noto（Serif・Sans とも同じ）は非既定 1,468 組・親字 1,215 字を持つ。うち 200 字は異体を 2 つ以上持つ（例: 邉は E0101〜E010E）。

TTFunk は format 14 を解さないので、cmap テーブルを自前で読む（format 14 の読み取りは 60 行ほど）。

### 2.3 字形の取り元

役割ごとに取り元の書体を決める。

| 役割 | 使う場所 | 取り元 | 太さ |
|---|---|---|---|
| 本文 | h1〜h6 の外 | `typography.body.font` | Regular（400）・Bold（700） |
| 見出し | h1〜h6 の中 | `typography.heading.font` | Regular（400）・Bold（700） |

- 書体の実体は `SvgFontEmbedder.font_path` と同じ規則で探す（同梱 `fonts/<slug>/`・Google Fonts `fonts/google/<slug>/`）。
- **設定の書体が format 14 を持たない（または非既定が 1 組も無い）ときは、同梱の Noto へ寄せる。**
  本文は Noto Serif JP、見出しは Noto Sans JP。Google Fonts の静的 TTF は異体の表を持たないことがあるため。
- 寄せた先にも字形が無ければ「無し」として警告する。同梱の Noto 自体が消されているときも同じ。
- Regular と Bold が同じファイルなら 1 面だけ作る（`face_paths` と同じ考え方）。

### 2.4 書体の割り振り

1 本の書体の中では、1 つの親字に 1 つの字形しか割り当てられない。

- 原稿に出た非既定の組を、出現順に**番号の小さい書体から**詰める。同じ親字がすでに入っている書体には入れず、次の書体へ回す。
- ほとんどの本は 1 本（`vs-variant-1`）で済む。同じ本に `邉󠄁` と `邉󠄂` が両方出たときだけ 2 本になる。
- 本数 × 役割（本文・見出し）× 太さ（2 面）の TTF を作る。見出しの書体と本文の書体が同じなら、見出し用は作らない。

### 2.5 本文の書き換え

```html
<!-- 前 -->
<p>竈門禰󠄀豆子</p>
<!-- 後 -->
<p>竈門<span class="vs-variant-1">禰</span>豆子</p>
```

- セレクタを外した親字を `span` で囲む。親字のままなので、検索で「禰」が当たる。
- 既定・無しの組は書き換えない（セレクタも残す）。

### 2.6 書体と CSS の置き場

- TTF: Kindle 用の消費者ディレクトリ直下の `fonts/vs-variant-1.ttf`・`fonts/vs-variant-1-bold.ttf`・
  `fonts/vs-variant-1-heading.ttf`・`fonts/vs-variant-1-heading-bold.ttf`。書く前に `fonts/vs-variant-*` を消す
  （`--no-clean` の残りで古い書体が混ざらないように）。
- CSS: 同じディレクトリの `book-settings.css`（共通フェーズで同梱済み）の末尾へ足す。新しい `<link>` は要らない。

```css
@font-face { font-family: "vs-variant-1"; font-weight: 400; src: url("fonts/vs-variant-1.ttf"); }
@font-face { font-family: "vs-variant-1"; font-weight: 700; src: url("fonts/vs-variant-1-bold.ttf"); }
@font-face { font-family: "vs-variant-1-heading"; font-weight: 400; src: url("fonts/vs-variant-1-heading.ttf"); }
@font-face { font-family: "vs-variant-1-heading"; font-weight: 700; src: url("fonts/vs-variant-1-heading-bold.ttf"); }
.vs-variant-1 { font-family: "vs-variant-1"; }
h1 .vs-variant-1, h2 .vs-variant-1, h3 .vs-variant-1,
h4 .vs-variant-1, h5 .vs-variant-1, h6 .vs-variant-1 { font-family: "vs-variant-1-heading"; }
```

- KFX は `:is()` と `var()` を解さないので、セレクタを並べて書く。
- `sanitize_epub_css!` は非埋め込み時に keyfont 以外の `@font-face` を消す。**`vs-variant-` で始まるファミリも残す**よう、
  残す条件（`KEYFONT_FACE_PATTERN`）を広げる。消すと書体の実体だけ残り、置き換えた字が親字に戻る。

### 2.7 書体の名前（ライセンス）

同梱の Noto は SIL OFL 1.1。Noto Sans JP には予約名 `Source` がある。

- 作った書体の name テーブルは**作り直す**。ファミリ名・フル名・PostScript 名は `VS Variant Glyphs 1` 系にし、
  `Noto`・`Source` を含めない（OFL 第 3 条: 改変版は予約名を名乗れない）。
- 著作権表示（name ID 0）とライセンス（ID 13・14）は元の書体から**写す**（OFL 第 2 条: 機械可読のメタデータでの同梱を認めている）。
- 商標（ID 7）など他の名前は落とす。

### 2.8 パイプラインでの位置

`EpubBuilder.generate_epub_entries!` の Kindle 専用フェーズの**最後**（`replace_rotate_tables_for_kindle!` の後）に
`apply_variant_glyph_fonts_for_kindle!(chapter_htmls, base_dir)` を置く。

- ほかの書き換え（会話文の組み替え・ラベル注入・数式のテキスト化）でテキストノードが動き終わった後に走らせるため。
- 組が 1 つも無い本では cmap を読まずに抜ける（書体ファイルも CSS も作らない）。

## 3. 実装の分け方

| 部品 | 置き場 | 役目 |
|---|---|---|
| `Build::VariantGlyphFont` | `lib/vivlio_starter/cli/build/variant_glyph_font.rb`（新規） | cmap format 14 の読み取り・割り振り（§2.4）・TTF の生成と name テーブルの作り直し |
| `EpubBuilder.apply_variant_glyph_fonts_for_kindle!` | `epub_builder.rb` | テキストノードの走査と置き換え・TTF と CSS の書き出し・警告 |
| `KEPT_FACE_PATTERN` | `epub_builder.rb` | `KEYFONT_FACE_PATTERN` を置き換え、`vs-variant-` も残す |

書体の実体探しは `SvgFontEmbedder.font_path` を使う（同じ規則を二重に持たない）。

## 4. 警告

字形の無い組が 1 つでもあれば、ビルドごとに 1 回まとめて出す（`warning-messages-actionable` の作法）。

```
🟡 [Kindle] 異体字の字形が書体にないため、Kindle では親字の形で表示されます（2 組）
     邉󠄏（U+9089 U+E010F）… 21-markdown.html「渡邉󠄏さん」ほか 1 か所
     → 書体 Noto Serif JP がこの異体を持っていません。PDF でも親字の形になります。
       字形が要るなら、その字だけ画像にするか、この異体を持つ書体を typography.body.font に指定してください。
```

- 組ごとに、最初の出現箇所（ファイル名と前後数文字）と残りの件数を出す。
- 既定（default UVS）の組は警告しない。親字の形が正しい形なので。

## 5. テスト

`test/vivlio_starter/cli/build/variant_glyph_font_test.rb`（新規）と `epub_kindle_layout_test.rb`（追記）。
同梱の Noto を使うテストは、ファイルが無い環境では skip する。

1. **字形の引き当て**: 同梱 Noto Serif JP で `禰 + E0100` が非既定、`禰 + E0101` が既定、`禰 + E0105` が無しになる。
2. **作った書体**: U+79B0 の字形が元の書体の非既定字形と同じ輪郭になる（字形 ID ではなく glyf の中身で比べる）。
   name テーブルに `Noto`・`Source` が無く、ID 0・13 が元と同じ。
3. **割り振り**: `邉󠄁`（E0101）と `邉󠄂`（E0102）が両方あると書体が 2 本に分かれる。`禰󠄀` と `邉󠄁` だけなら 1 本。
4. **書き換え**: テキストノードだけ置き換わり、`id`・`alt`・`data-heading`・`<title>` のセレクタは残る。
   h3 の中の字は `-heading` のファミリが当たる CSS になっている。
5. **組が無い本**: HTML も book-settings.css も変わらず、`fonts/vs-variant-*` を作らない。
6. **サニタイズ**: `sanitize_epub_css!` が `vs-variant-` の `@font-face` を残し、それ以外（keyfont を除く）は従来どおり消す。
7. **警告**: 字形の無い組で 1 回だけ警告し、出現箇所を含む。既定の組では警告しない。
8. **クリーン EPUB**: `flavor: :epub` では何も変わらない（span も書体も無い）。

## 6. 採らなかった案

| 案 | 採らない理由 |
|---|---|
| 段落ごと画像にする | 本文が画像になり、文字の大きさ・検索・読み上げがすべて効かなくなる |
| 異体の字だけ SVG / PNG にする | KFX は画像の大きさを em で指定できない（`kindle-inline-math-textify-spec.md` §0）。読者が文字を大きくするとその字だけ取り残される。ダークモードで黒い字が沈むおそれもある |
| 私用領域（PUA）の符号へ割り当てる | 1 本の書体で済むが、本文の字が親字でなくなり、検索とコピーが壊れる |
| 本文書体を丸ごと埋め込む | 和文書体は 1 面 4〜5MB。Kindle の配信料（容量課金）が増え、読者の書体設定も効かなくなる |
| クリーン EPUB にも入れる | Apple Books は OS の書体で正しく出る。Kobo などで出ない例を確かめてから考える（§7） |

## 7. 残すこと

- **目次（ナビゲーション）**: Vivliostyle が見出しの文字から作るので、ここでは親字のまま出る。
- **クリーン EPUB**: Kobo などで異体字セレクタが効かない例が見つかったら、同じ仕組みを `flavor: :epub` にも広げる。
- **数式の記号**（ユーザー提案・2026-10-12 に確かめて**見送り**）: テキスト化した数式が出す 91 字を 1 章に並べ、
  Kindle Previewer 4 で見た。□ や ？ になる字も、まわりから浮く字も無く、文字の大きさ 1〜5 に追従した。
  書体を埋め込む必要は無い。なお 91 字のうち 13 字（⋅ ⟨ ⟩ ∘ ∼ ↦ ϑ ϖ ϱ ϕ ≒・結合文字の U+0302・細い空白）は
  同梱の Noto にも無いので、もし要るときは Noto から抜く方法では足りず、数式用の書体から取ることになる。
  Previewer は読者の書体に無い字を Code2000 で描く（`Resources/fonts/kss` の割り当て）。
- **PDF の警告**: 書体に字形が無い組は PDF でも親字になる。今回は Kindle ビルドでだけ警告する。PDF 側で知らせるかは別に決める。

## 8. 確認手順（実装後）

1. `variation-selector-sample.md` を 1 章だけのプロジェクトで `targets: kindle` にして `vs build`。
2. Kindle Previewer 4 で h3・本文・コラム・リストの `禰󠄀` がネ偏になること、文字の大きさ 1〜5 に追従することを見る。
3. 中間 EPUB（`--no-clean`）を epubcheck に通し、エラーが増えないことを確かめる。
