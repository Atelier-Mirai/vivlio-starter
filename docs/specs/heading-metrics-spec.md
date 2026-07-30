# heading-metrics-spec

見出し（章題 h1・章リード・節題 h2）と扉絵・節絵の**寸法指定を mm から文字数へ移し**、折返しの品質を上げ、節絵の帯を約半分の高さに縮め、見出しの帰属が読めるよう前後の余白比を正す。**PDF・EPUB・Kindle の全ターゲットを対象**とする。

- 状態: **仕様（実装待ち）**
- 起点: `section_page_break: false` の不具合調査（2026-07-30）で判明した設計上の歪み 4 点
- 前提の実測: すべて A4 210×297mm・`theme.style: image`・`--paper-scale: 1.0` での実測値。実験は `stylesheets/custom.css` に一時上書きを置いて `vs build 12` で確認し、確認後に破棄した

## フェーズ分割

装飾の実現方式が PDF と EPUB で根本的に違う（PDF は CSS の箱＋`@page` 背景、EPUB は**飾りと見出しを 1 枚に焼いた合成画像**）ため、2 段に分ける。

| | 対象 | 内容 |
|---|---|---|
| **Phase 1** | PDF | §1〜§4 の設計を CSS と生成 CSS で実現する。EPUB / Kindle は**見た目を変えない**（設定キー改名への追随のみ） |
| **Phase 2** | EPUB / Kindle | §5。Phase 1 で決まった設定値（`heading_chars` / `lead_chars`）と余白比を合成画像側にも通し、PDF と同じ意匠へ揃える |

**Phase 1 でも EPUB のコードに手が入る**。`EpubBuilder#frontispiece_lead_ratio` は `theme.frontispiece.lead_width ÷ page.width` を読んでいるため、キーを改名すると参照先を失って EPUB が縮退する。Phase 1 では「新キーから従来と同じ比率を導く」最小限の追随だけを行い、見た目は据え置く（§5-1）。

---

## 0. なぜ直すのか（現状の実測）

### 0-1 いまの寸法系は「解釈が 3 通り」混在している

`config/book.yml` の `theme.frontispiece` に並ぶ 3 つの設定は、同じ mm 表記なのに効き方が違う。

| 設定 | 現在の解釈 | A4 | B5 | A5 |
|---|---|---|---|---|
| `padding: 5mm` | **リテラル**（紙端から 5mm） | 5mm | 5mm | 5mm |
| `lead_width: 108mm` | **リテラル**（そのまま幅・上限ガード無し） | 108mm | 108mm | 108mm ← 版面幅と同値で余白が消える |
| `heading_width: 128mm` | **上限のみ**（実幅は `paper-scale × 96mm`） | 96mm | 83.1mm | 67.7mm |

`heading_width` だけが `clamp()` の**第 3 引数**に置かれている（`stylesheets/image-header.css:39-43, 90-94`）。`clamp(最小, 希望, 最大)` の実幅を決めるのは真ん中の希望値なので、`heading_width` を希望値より大きくしても何も起こらない。原稿 `contents/42-frontispiece.md:269-277` は「最大幅」と正しく書いてあるが、`book.yml` のコメントは `# 幅の調整` で両方向に効くと読める。

### 0-2 章題は「どの紙でも 1 行 7.4 字」に固定されている

箱幅と文字サイズの両方に同じ `paper-scale` が掛かるため、紙を変えても 1 行の字数がほぼ変わらない。

| 紙 | `paper-scale` | 版面幅 | 章題の箱 | 文字サイズ | 1 字の送り | 1 行に入る字数 |
|---|---|---|---|---|---|---|
| A4 210×297 | 1.0000 | 162.0mm | 96.0mm | 48Q = 12mm | 12.96mm | **7.4 字** |
| B5 182×257 | 0.8653 | 137.0mm | 83.1mm | 41.5Q = 10.4mm | 11.23mm | **7.4 字** |
| A5 148×210 | 0.7048 | 108.0mm | 67.7mm | 34Q = 8.5mm（下限） | 9.18mm | **7.4 字** |

`paper-scale` は `min(紙幅/210, 紙高/297)` を 0.5〜1.0 に丸めた値（`CssUpdater.calculate_paper_scale`）。1 字の送りは字幅 1em ＋ `letter-spacing: 0.08em`。

つまり「クイックスタート」（8 字）は **A4 でも B5 でも A5 でも折り返す**。版面幅は A4 で 162mm あるのに、章題は 96mm しか使っていない。

### 0-3 泣き別れの真因は `word-break: keep-all`

`base.css:21-31` が h1〜h6 に `word-break: keep-all` を掛けているため、CJK 文字間の通常の分割点が消える。残るのは `.chapter-title` の `overflow-wrap: anywhere`（`image-header.css:97`）による緊急分割だけで、**入るところまで詰めて 1 字だけ落とす**（「クイックスター/ト」）。節題（h2 `.section-title`）は同じ罠を踏んで `word-break: normal` へ戻してある（`image-header.css:168-180`）が、**章題には同じ手当てが入っていない**。

### 0-4 節絵の帯がページ高の 23% を占めている

h2 は `aspect-ratio: 239/100`（`image-header.css:137`）。A4 の版面幅 162mm では **68mm ＝ ページ高 297mm の 23%**。飾りが左上と右下に**対角配置**されているため、飾り 1 つ分（約 35mm）の高さが 2 段ぶん必要になっている。

節絵アセットの正体: 同梱の正方形素材（`stylesheets/images/bundled/sakura.webp` 等 12 種）を `ImageGenerator.generate_diagonal_variant` が**対角線で 2 枚の三角形に割り、目標アスペクト比のキャンバスへ左上・右下に置き直して**生成している（`sakura_landscape.webp` = 2880×1205 = 2.39:1）。飾りが対角に出るのはこの生成方式の帰結。

---

## 1. 用語の見直し

### 1-1 `padding` → **`edge_inset`**（推奨）

`padding` は 1 箇所でしか使われていない。

```css
/* theme.css:79 */
--frontispiece-background-size: auto calc(100% - 2 * var(--frontispiece-padding));
/* image-header.css:20-26 */
@page :nth(1) { background-size: var(--frontispiece-background-size); }
```

`100%` はページの高さ。つまり実体は「**扉絵をページ端からどれだけ引っ込めるか**」で、本文の余白（`page.use` プリセットの `margin_*`）とは無関係。A4・himawari（2880×4152）での実数:

| 値 | 画像の高さ | 画像の幅（自動追従） | 紙 210×297mm に対して |
|---|---|---|---|
| 5mm | 287mm | 199.1mm | 左右に 5.5mm ずつ |
| 10mm（既定） | 277mm | 192.1mm | 左右に 9.0mm ずつ |

候補と評価:

| 候補 | 評価 |
|---|---|
| **`edge_inset`** | ◎ 推奨。CSS の `inset` と同義で「端からの引っ込み」が一意。`padding`（内側の詰め物）との混同が起きない |
| `edge_margin` | ○ 平易だが `margin` が本文余白と紛れる |
| `inset` | △ 短いが「何からの」が読み取れない |
| `page_edge_gap` | △ 説明的だが長く、`gap` は Grid/Flex の語と衝突 |

**併せて直す**: 現在は高さ基準の計算なので、上下は指定どおり Nmm 空くが左右はそれより広くなる（縦長画像では上下が拘束軸になるため）。`BookSettingsCss` はページ寸法を知っており画像の実寸も `magick identify` で取れるので、**両軸を見て `background-size` をリテラル 2 値で焼き込む**（`@page { size }`・綴じオフセットと同じ P3 方式）。これで「紙端から Nmm」が拘束軸側で正確に成立し、横長の自作画像を指定したときの左右はみ出し（現在は無警告で切れる）も防げる。

### 1-2 `heading_width` / `lead_width` → **`heading_chars` / `lead_chars`**（推奨）

mm をやめて**文字数（全角換算）**で指定する。§0-2 のとおり文字サイズは `paper-scale` で紙に追従するので、**文字数指定なら「A4 の 128mm」と「A5 の 128mm」の意味が違う問題がそもそも消える**——8 文字はどの紙でも 8 文字。

| 候補 | 評価 |
|---|---|
| **`heading_chars` / `lead_chars`** | ◎ 推奨。短く、単位が自明。`chars` は全角換算の文字数 |
| `heading_line_chars` / `lead_line_chars` | ○ より明示的だが冗長 |
| `heading_length` / `lead_length` | △ `length` は CSS の長さ（mm）と読める |
| `heading_jizume` | △ 「字詰め」は組版の正式用語だが英字キーとして通りが悪い |

```yaml
theme:
  frontispiece:
    image: himawari
    edge_inset: 5mm      # 紙の端から内側へ引っ込める量
    heading_chars: 10    # 章題を 1 行に何文字入れるか（全角換算）
    lead_chars: 24       # 章リード文を 1 行に何文字入れるか
  ornament:
    image: sakura
    heading_chars: 12    # 節題を 1 行に何文字入れるか
```

`theme.ornament` は現在スカラー（画像名のみ）なので、`frontispiece` と同じマッピング形も受け付けるようにする（スカラーは画像名だけの短縮形として維持）。

**実装は em 換算 1 行**（実測で成立を確認・§0 実験 3）:

```css
body.vs-header-image h1 .chapter-title {
  inline-size: calc(var(--frontispiece-heading-chars) * 1.08em); /* 1em 字幅 + 0.08em アキ */
  max-inline-size: 100%;                                        /* 版面を超えない保険 */
}
```

`em` は要素自身の font-size 基準で、その font-size は既に `paper-scale` で紙に追従しているため、**紙サイズ非依存**になる。係数 1.08 は `letter-spacing: 0.08em` 由来なので、`letter-spacing` を変えるルールと同じ場所で 1 箇所に持つ（変数化する）。

リード文と節題も同様（リードは `letter-spacing: var(--letter-spacing)` 既定 0 なので係数 1.0、節題は h2 の `letter-spacing` に合わせる）。

**`max-inline-size: 100%` は必須**。`.chapter-lead` には現在これが無く（`image-header.css:48-52`）、版面より大きい値を書くと無警告で余白へはみ出す。

**既定値は版面幅から導出する**。現在は `theme.css` の 108mm/88mm 固定 ＋ `paper-scale` の掛け算という二重制御になっている。未指定時は `BookSettingsCss` が「版面幅 ÷ 1 字の送り」から文字数を出してリテラルで焼き込めば、紙を変えても既定が自動追従し、二重制御を解消できる。

**版面に収まらない指定は 🟡 で案内する**（`warning-messages-actionable` の方針どおり before→after 付き）:

```
🟡 theme.frontispiece.heading_chars: 16 は A5 の版面に収まりません（最大 11 文字）
        heading_chars: 11 をお試しください
```

---

## 2. 折返しの品質

### 2-1 `word-break: auto-phrase` を見出しに使う（実測で有効）

Chromium 119+ の `word-break: auto-phrase` は日本語を**文節単位**で分割する。Vivliostyle（Chromium 149）で動作することを実測確認した。

| 対象 | `keep-all`（現状の h1） | `normal`（現状の h2） | `auto-phrase` |
|---|---|---|---|
| クイックスタート | クイックスター / **ト** | クイック / スタート | クイックスター / **ト** |
| Ruby のインストール | （分割点なしで溢れる） | Ruby のイ / ンストール | **Ruby の / インストール** |
| Vivlio Starter のインストール | 〃 | Vivlio Starter / のインス / トール | **Vivlio Starter / のインストール** |
| 新規プロジェクトの作成 | 〃 | 新規プロジェ / クトの作成 | **新規プロジェクトの / 作成** |

読み取れること:

- **`auto-phrase` は語中で割らない**。`normal` の「のイ/ンストール」「新規プロジェ/クトの作成」が消える。MeCab を持ち込まずに「切りの良いところ」が得られる
- **`auto-phrase` でも 1 語が箱に入らなければ救えない**。「クイックスタート」は全体が 1 語なので分割点が無く、`overflow-wrap: anywhere` の緊急分割に落ちて泣き別れが残る → **§1-2 の文字数指定（箱を広げる）と組み合わせて初めて解決する**
- したがって採用順は **(1) 文字数指定で箱を確保 → (2) `auto-phrase` で割り位置を正す → (3) それでも溢れる場合だけ自動縮小**

`auto-phrase` 非対応環境では `normal` に劣化するだけなので、`word-break: normal` を先に書いて `auto-phrase` で上書きする 2 段書きにする（EPUB リーダー向けの安全策）。

### 2-2 1〜2 字あふれの自動縮小

`auto-phrase` でも分割点が無く、かつ設定文字数を **1〜2 字だけ**超える見出しは、行を割るより**全体を少し縮めて 1 行に収める**方が読みやすい。CSS 単体では「入るまで縮める」が書けないため、**ビルド時に Ruby で係数を決めて属性で渡す**。

- 見出しの文字数は前処理・後処理の時点で確定している（`heading_processor` が `.chapter-title` / `.section-title` の span を構築する）
- `超過 = 見出しの全角換算長 − 設定文字数`
  - `超過 <= 0` … 何もしない
  - `1 <= 超過 <= 2` … `style="--heading-fit: 0.875"` 相当（係数 = 設定文字数 ÷ 見出し長）を span に載せ、CSS 側で `font-size: calc(1em * var(--heading-fit, 1))`
  - `超過 >= 3` … 縮小せず `auto-phrase` の折返しに任せる（縮めすぎると本文との階層感が壊れる）
- 閾値（2 字）と最小係数（例 0.8）は定数で持ち、`book.yml` のキーは増やさない

**MeCab は使わない**。`auto-phrase` が文節分割を担い、縮小判定は文字数だけで足りるため。`vs metrics` / `vs index` / `vs pdf:read` が既に MeCab を任意依存として持っているが、組版の折返しをそれに依存させると **MeCab の有無で PDF の見た目が変わる**（同じ原稿が環境で違う本になる）ので採らない。

---

## 3. 節絵の帯をコンパクトにする

飾りを左上／右下の**対角配置から左右並び**へ変え、帯の高さを約半分にする（`h2_compact.png` の意図）。

### 3-1 新規アセット不要の 2 層スプライトで実現できる（実測）

`h2::before` 1 層で節絵全体を描いている現状を、**左半分・右半分の 2 層**に分ける。各層は要素の半分の幅を持ち、`background-size` を 150% にして「自分の側の飾り」だけを見せる。

```css
body.vs-header-image .section-topic h2::before,
body.vs-header-image .section-topic h2::after {
  content: "";
  position: absolute;
  inset-block: 0;
  inline-size: 50%;
  background-image: var(--section-bg-image);
  background-repeat: no-repeat;
  background-size: 150% auto;
  z-index: -1;
}
body.vs-header-image .section-topic h2::before { inset-inline-start: 0; background-position: left top; }
body.vs-header-image .section-topic h2::after  { inset-inline-end: 0;  background-position: right bottom; }
```

節絵アセットは左上と右下に飾りを持つ 2.39:1 の画像なので、`left top` は左上の飾り、`right bottom` は右下の飾りをそれぞれ切り出す。**アセットを作り直さないので 12 種の同梱画像と著者の自作画像がそのまま使える**（`ImageGenerator` にも手を入れない）。

飾りの表示サイズは `background-size` の % で決まる（各層は要素の半幅を基準にするので、150% なら画像幅は帯の 75%）。帯の高さは h2 の `aspect-ratio` で決める。

### 3-2 余白は「飾りの最大張り出し」ではなく「本文行の位置での輪郭」で決める

飾りは角飾り（三角形）なので、**帯の上端付近で最も張り出し、中央へ向かって細くなる**。節題は帯の垂直中央に置かれるため、最大張り出しに合わせて `padding-inline` を取ると横幅を大きく無駄にする。

`sakura_landscape.webp` から `::before` が実際に見せる領域（左上 81mm×30mm 相当）を切り出してアルファ輪郭を計測した結果:

| 帯の上端からの高さ | 飾りの右端 |
|---|---|
| 0.0mm | 15.2mm |
| 4.0mm | **26.3mm（最大）** |
| 8.1mm | 21.9mm |
| 12.1mm | 10.5mm |
| **15.0mm（垂直中央）** | **8.4mm** |
| 20.2mm | 6.1mm |
| 22.2mm | 7.1mm |

最大 26.3mm に対し、垂直中央では **8.4mm**。最大値に合わせると **約 20mm を捨てる**ことになる。したがって `padding-inline` は「1〜2 行の節題が占める行範囲での最大値」から決める（2 行なら上端寄りの行も使うため、中央値そのままには寄せられない）。

### 3-3 右の飾りをわずかに下げる

帯の高さを飾り 1 つ分より少し高く取り、左を `left top`（上寄せ）・右を `right bottom`（下寄せ）にすると、**差分がそのまま右飾りの下がり量になる**。専用の宣言を足さずに済む。

- 帯 33.8mm − 飾り約 26mm = **約 7.7mm 下がる**（実測でも右飾りが左より約 5mm 低く出る）

### 3-4 実測結果（`vs build 12`・A4・節 4 つ）

| 項目 | 現状 | 最大張り出しに合わせた場合 | **採用案（対角へ寄せる）** |
|---|---|---|---|
| h2 の `aspect-ratio` | 239/100 | 540/100 | **480/100** |
| 帯の高さ | 68mm（ページ高の 23%） | 約 30mm | **約 33.8mm（11%）** |
| `background-size`（各層） | — | 150% | **150%**（飾り約 26mm） |
| `padding-inline` | 10mm | 30mm 28mm | **16mm 18mm** |
| 節題に使える幅 | 142mm | 104mm | **128mm** |
| 「1-1 Ruby のインストール」 | 1 行 | 2 行に割れる | **1 行** |
| 「1-3 新規プロジェクトの作成」 | 1 行 | 2 行に割れる | **1 行** |
| 章の総ページ数 | 7 | 6 | **6（−14%）** |

対角へ寄せることで、帯を半分に縮めながら**従来と同じ節題の字数を保てる**ことを実測で確認した（`padding-inline` を最大張り出しに合わせると 2 行に割れてしまう節題が、採用案では 1 行に収まる）。飾りの表示サイズは `background-size` の % で調整できる（150% で約 26mm・200% で約 35mm）。

なお節番号（`.section-number`）は飾りの薄い部分（葉や茎）に少しかかるが、実測の見た目では自然に読める。`margin-inline-start` の 6〜10mm は `padding-inline` へ吸収するため 0 にする。

### 3-5 将来: `shape-outside` で輪郭そのものに流す

理想は矩形の `padding` ではなく飾りの輪郭に沿ってテキストを流すこと（`float` ＋ `shape-outside`）。Vivliostyle の対応状況が未確認なので本仕様では採らないが、対応が確認できれば §3-2 の輪郭データをそのまま `polygon()` に落とせる。

### 3-6 EPUB / Kindle 側

EPUB は `h2::before` を無効化し（`components.css:258-260`）、`EpubBuilder` が合成画像の節絵を `<img>` として注入する別経路。**Phase 1 では触らず、Phase 2（§5-3）で同じ意匠へ揃える**。

---

## 4. 見出しの帰属を余白で示す（近接の原則）

### 4-1 現状は余白が逆になっている

`h2_margin.png` の実測（コンパクト帯を適用した `vs build 12` の 3 ページ目）。節題「1-3 新規プロジェクトの作成」の上下の空きは:

| 位置 | 視覚上の空き | 出所 |
|---|---|---|
| 節題の**上**（前節の末尾コードブロックとの間） | **約 4.4mm** | `pre { margin-block: 3mm }`（`code.css:18`）だけ。**`.section-topic` に `margin-block-start` が無い** |
| 節題の**下**（自分の節の本文との間） | **約 12.3mm** | `.section-topic { margin-block-end: 1em }`（`image-header.css:118`）＋後続段落の余白 |

見出しは**自分が率いる内容に近く、前の内容から遠く**あるべきなのに、比が **1 : 3** で完全に逆になっている。結果として「前節の最後の段落＋コードブロック＋次節の見出し」が 1 つの塊に見え、節の切れ目が読めない。帯を半分に縮めたことで前後の空きの差が相対的に目立ち、症状が顕在化した。

### 4-2 方針: 前後比を約 3 : 1 にする

| 対象 | 現状 | 案 |
|---|---|---|
| `.section-topic` の `margin-block-start` | なし（実質 3mm） | **12mm 程度**（約 2rlh） |
| `.section-topic` の `margin-block-end` | `1em`（約 3.7mm）＋後続余白 | **4mm 程度**（約 0.7rlh）。後続段落側の余白と二重に効かないよう、`.section-topic + *` で後続の `margin-block-start` を打ち消す |
| `.section-lead` の `margin-block-start`（帯との間） | grid `gap: 8mm` ＋ `16mm !important` | **grid `gap` を 4mm 程度へ縮め、`16mm` の押し下げは撤去**（この押し下げは固定 150px 行からのはみ出しを見込んだ補正で、`section_page_break: false` の是正で既に不要になっている） |

数値は実装時に実測で追い込む。**守るべきは絶対値ではなく比**（前 ≫ 後）で、`h2 → 節リード → 本文`が 1 つの群に見えることが受入条件。

### 4-3 実装上の注意

- **前の余白の持ち主は `.section-topic` にする**。「前の節の末尾に余白を足す」形（`section.level2 { margin-block-end }`）でも見た目は同じだが、余白の持ち主が 2 箇所に分かれると「章の最初の節」「`---` で改ページした直後の節」で挙動が食い違う。見出し側が自分の前後の空きを持つのが唯一の owner になる
- **ページ先頭では前の余白を捨てる**。既定（`section_page_break: true`）と章扉保護では h2 がページ先頭に来るため、12mm の先頭余白がそのまま残ると帯が下がる。`margin-break: discard` を併記する（`chapter-common.css:94` に既存の使用例あり）
- **`simple` スタイルにも同じ比を適用する**。`body.vs-header-simple h2`（`simple-header.css:113-160`）は罫線で区切る意匠だが、近接の原則は装飾の有無と無関係。値は意匠に合わせて別に持つ
- **`.section-lead` が無い節**（同梱原稿では多数）では帯の直後が本文段落になる。`.section-topic + *` の打ち消しはリード有無の両方で成立させる

## 5. Phase 2: EPUB / Kindle へ反映する

### 5-0 前提: EPUB の見出しは「飾り＋文字を焼いた 1 枚の画像」

リフロー型 EPUB（特に Kindle）は背景画像・固定寸法・`position` の重ね合わせが不安定なため、`theme.style: image` の EPUB では `HeadingImageComposer` が **飾り画像＋見出し文字を合成 SVG に組み、JPEG へラスタライズして `<img>` で配る**（`math-frontispiece-svg-spec.md §B`）。したがって Phase 1 の CSS はそのままでは効かず、**同じ設計を合成側のパラメータとして通す**必要がある。

**重要な発見: §1-2 の「文字数指定」と §2-2 の「自動縮小」は、EPUB 側に既に実装されている**。ただしハードコードされた比率で動いており、PDF 側と数値を共有していない。

| 概念 | PDF（Phase 1 で新設） | EPUB（既存・`heading_image_composer.rb`） |
|---|---|---|
| 1 行の文字数 | `heading_chars`（`calc(N * 1.08em)`） | `capacity = ORNAMENT_TEXT_WIDTH(0.88) × width ÷ font_size` |
| 基準フォント | `clamp(34Q, paper-scale × 48Q, 50Q)` | `ORNAMENT_FONT_RATIO(0.14) × height` |
| あふれ時の縮小 | §2-2（1〜2 字なら係数を焼く） | **8% ずつ縮小**（`ORNAMENT_MAX_LINES = 2` に収まるまで・下限 `height × 0.09`） |
| リード幅 | `lead_chars` | `lead_ratio = lead_width ÷ page.width`（0.40〜0.75 にクランプ） |
| リードの縮小 | （未実装） | **8% ずつ縮小**（`LEAD_BOTTOM_RATIO` に収まるまで） |

つまり**同じ原稿が PDF と EPUB で違う行分割になる**のは、両者が別のパラメータ体系で独立に動いているため。Phase 2 の本質は意匠の移植より **「設定値を両経路の唯一の入口にする」** ことにある。

### 5-1 Phase 1 で必要になる最小限の追随（見た目は変えない）

`EpubBuilder#frontispiece_lead_ratio` / `#lead_ratio_from` は `theme.frontispiece.lead_width` を直接読む。§1-2 で `lead_chars` へ改名した時点でここが壊れるため、**Phase 1 のうちに新キーから同じ比率を導く形へ差し替える**（`lead_chars × 1 字の送り ÷ page.width`）。値が従来と一致することをテストで固定し、EPUB の見た目は Phase 1 では動かさない。

`edge_inset`（§1-1）は `@page` 背景の話なので **EPUB には概念が存在しない**（合成画像は通常フローの `<img>`）。追随不要。

### 5-2 文字数と縮小の一本化

- `heading_chars` / `lead_chars` を `HeadingImageComposer` の `capacity` の**唯一の決定源**にする。`ORNAMENT_TEXT_WIDTH` と `ORNAMENT_FONT_RATIO` は「capacity から逆算してフォントサイズを決める」形へ反転させる（現在は逆にフォントサイズから capacity を出している）
- 既存の 8% 縮小ループは残す。ただし §2-2 と**判定条件を揃える**（1〜2 字あふれなら縮小、3 字以上なら折り返す）。両者がずれると同じ見出しが PDF では 2 行・EPUB では縮小 1 行になる
- 半角換算（`char_display_width` = 半角 0.55 / 全角 1.0）は EPUB 側の既存実装を**正典**とし、§2-2 の Ruby 側もこれを共有する（実装を 2 つ持つと必ずずれる）

### 5-3 コンパクト帯を合成 SVG でも実現する

PDF の 2 層スプライト（§3-1）の SVG 版は `clipPath` で書ける。`rsvg-convert` は `clipPath` に対応している。

```xml
<svg viewBox="0 0 W H">              <!-- H = W / 4.8（PDF の aspect-ratio 480/100 と一致させる） -->
  <clipPath id="l"><rect x="0" y="0" width="W/2" height="H"/></clipPath>
  <clipPath id="r"><rect x="W/2" y="0" width="W/2" height="H"/></clipPath>
  <image clip-path="url(#l)" x="0"  y="0"      width="W*0.75" .../>   <!-- 左上の飾り -->
  <image clip-path="url(#r)" x="..." y="..."   width="W*0.75" .../>   <!-- 右下の飾り・§3-3 のぶん下げる -->
  <text .../>                                                         <!-- 番号＋節題 -->
</svg>
```

- `viewBox` の縦横比・飾りサイズ（`W*0.75` ＝ CSS の `background-size: 150%` と等価）・右飾りの下げ量は **PDF 側の値と同じ定数から導く**。CSS とハードコード定数の二重管理を避けるため、比率は 1 箇所（Ruby 定数）に置き、`BookSettingsCss` が CSS 側へ焼き込む形が望ましい
- 扉絵（`frontispiece_svg`）も `title_size = width * 0.085`（コメント「11 字まで 1 行に収まる大きさに抑える」）というマジックナンバーで幅を決めている。これを `heading_chars` 由来へ置き換える
- **`LAYOUT_VERSION` を +1 する**（現在 2）。`EpubBuilder` が生成キャッシュのキーに混ぜているため、上げないと旧レイアウトの合成画像が使い回される

### 5-4 余白の前後比（§4）を EPUB にも適用する

EPUB 側も現状は前後が対称かむしろ逆で、同じ「一体化して見える」問題を持つ。

| セレクタ | 現状 | 案 |
|---|---|---|
| `h1.vs-image-heading-epub, h2.vs-image-heading-epub`（`components.css:207`） | `margin-block: 0.5rem`（**前後対称**） | 前 ≫ 後（例 `1.6rem 0.4rem`） |
| `article.vs-section-topic-epub`（`components.css:230`） | `margin-block-end: 1em` のみ | 前の余白を持たせ、後ろは縮める |
| `body.vs-epub .section-lead`（`components.css:271`） | `margin-block: 0.5em 1em` | 見出しに近づける |

リフローなので `mm` ではなく `rem` / `em` で持つ。**守るのは §4-2 と同じ「前 : 後 ≒ 3 : 1」の比**。

### 5-5 揃えられないもの（明示）

**`word-break: auto-phrase`（§2-1）は EPUB では使えない**。合成画像の中では折返しを Ruby（`split_by_display_width`）が決めており、CSS のテキスト整形は関与しない。したがって**同じ節題の割り位置が PDF と EPUB で一致しない**場合がある。

- 対策は「割らずに済ませる」こと。`heading_chars` を適切に設定すれば大半の見出しは 1 行に収まり、割り位置の差が現れない
- Ruby 側に文節分割を実装して合わせる案は採らない（§2-2 と同じ理由で MeCab に依存させない。ルールベースの簡易実装は CSS の `auto-phrase` と結果が一致せず、「揃えたつもりでずれる」ほうが悪い）
- この非対称は既知の制限として `KNOWN_ISSUES.md` へ記録する

なお合成画像は**ビルド機のフォントで文字を焼く**方式（`math-frontispiece-svg-spec.md §B-7` で字形差は許容済み）なので、字形レベルの一致はもともと目標にしていない。

## 6. テスト

### Phase 1（PDF）

1. **`book_settings_css_test`**: `edge_inset` / `heading_chars` / `lead_chars` が変数として出力される。未指定時に版面幅から導出した既定が焼き込まれる。版面に収まらない値で 🟡 が出る
2. **`image_header_css` の回帰**: `.chapter-title` / `.section-title` に `word-break` の 2 段書きと `max-inline-size: 100%` が実在する（`SECTION_PAGE_BREAK_SELECTORS` と同じ「前提を固定する」型のテスト）
3. **余白の前後比の回帰**: `.section-topic` の `margin-block-start` が `margin-block-end` より大きいことを CSS ソースに対して固定する（数値そのものではなく**比の向き**を検査する。逆転が再発したら落ちる）
4. **自動縮小のユニットテスト**: 見出し長 × 設定文字数の組で係数を検証（`超過 0 / 1 / 2 / 3` の境界。全角換算なので半角英数・約物の数え方も固定する）
5. **`page_layout`（`rake test:layout`）**: A4 / B5 / A5 の 3 プリセットで章題が 1 行に収まること・帯の高さ・総ページ数。ページ先頭の節で先頭余白が捨てられていること（帯の上端が版面上端に来る）
6. **`lead_ratio` の値保存**（§5-1）: `lead_chars` から導いた比率が改名前の `lead_width` 由来の値と一致すること。**Phase 1 で EPUB の見た目が動いていないことの担保**

### Phase 2（EPUB / Kindle）

7. **`heading_image_composer_test`**: `heading_chars` / `lead_chars` が `capacity` の決定源になっていること。縮小の発火条件が §2-2（PDF 側）と一致すること（同じ見出し・同じ設定で「PDF は 2 行／EPUB は縮小 1 行」に分かれない）
8. **半角換算の共有**: `char_display_width` を PDF 側の文字数判定と共有していること（実装が 2 つ無いこと）
9. **`LAYOUT_VERSION` の更新**: 定数が上がっていること（上げ忘れると旧レイアウトの合成画像がキャッシュから使い回される）
10. **`epub_kindle_layout_test`**: 節絵の合成画像の縦横比が PDF の帯と一致すること・余白の前後比が §5-4 の向きであること
11. **手動**: Kindle Previewer で扉絵・節絵の実機確認（合成画像は端末幅 1072px 以上での可読性が要件）

---

## 7. 実装順序

`heading_chars` は `auto-phrase` の前提（§2-1）なので順序を守る。

### Phase 1: PDF

1. **§1-1 `padding` → `edge_inset`** 単独で入る。旧キーは残さない（後方互換を持たない方針）。`book.yml` コメント・42 章・`copy_to_scaffold.rb` 同期まで一括
2. **§1-2 文字数指定**（`heading_chars` / `lead_chars` ＋ `max-inline-size` ＋ 既定の版面導出 ＋ 🟡 警告）。**あわせて §5-1 の EPUB 追随を必ず同時に入れる**（改名だけ入れると `frontispiece_lead_ratio` が参照先を失って EPUB の扉絵リードが崩れる）
3. **§2-1 `auto-phrase`** 2 段書きを `.chapter-title` / `.section-title` へ
4. **§3 コンパクト帯**（`aspect-ratio` ＋ 2 層スプライト ＋ `padding-inline`）
5. **§4 余白の前後比**。帯を縮めた後でないと適正値が測れないため 4 の直後に必ず続ける（4 だけ入れて止めると前後比の逆転が目立つ状態で残る）
6. **§2-2 自動縮小**。1〜5 を入れた後に「まだ泣き別れる見出し」が実原稿にどれだけ残るかを見てから判断する。残らなければ実装しない

### Phase 2: EPUB / Kindle

7. **§5-2 文字数と縮小の一本化**。ここで PDF と EPUB のパラメータ体系が 1 つになる。§2-2 を実装しなかった場合は、EPUB 側の既存 8% 縮小を正典として PDF 側の判定を合わせる
8. **§5-3 コンパクト帯の合成 SVG 版**（`clipPath` ＋ `viewBox` 比 ＋ `LAYOUT_VERSION` +1）
9. **§5-4 余白の前後比**（`components.css` の EPUB 用ルール）
10. **§5-5 の非対称を `KNOWN_ISSUES.md` へ記録**

Phase 1 の 1〜5 はどれも**既存書籍の PDF 組版を変える**（章題の折返し位置・節絵の帯の高さ・節の前後の空き・ページ数）。Phase 2 は**既存書籍の EPUB / Kindle の見た目を変える**（合成画像の縦横比・行分割）。RC 公開との前後関係は別途判断。

---

## 8. スコープ外

- **`simple` スタイル**: 扉絵・節絵を持たないため §1-1・§3・§5 は無関係。§1-2・§2・**§4（余白の前後比）**は `body.vs-header-simple` 側にも同型で入れられる。§4 だけは意匠と無関係の原則なので同時に直す（§4-3 参照）
- **`page_presets.yml` への字詰め指定**: 本文の 1 行字数を直接指定する機能（`chars_per_line`）は本仕様の対象外。見出し側を文字数指定にすると本文側との非対称が目に付くようになるので、必要になったら別仕様で起こす
- **付録（`appendix`）の見出し**: 常に `vs-header-simple` のため対象外
- **MeCab による折返し**: §2-2 の理由により採らない（EPUB 側も §5-5 で同じ判断）
- **PDF と EPUB で割り位置を一致させること**: §5-5 のとおり構造的に不可能。「割らずに済ませる」ことで実害を消す方針
