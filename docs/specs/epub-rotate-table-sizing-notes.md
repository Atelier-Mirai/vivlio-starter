# epub-rotate-table-sizing-notes

クリーン EPUB で回転テーブル（`.rotate-table`）をどの大きさで組むべきかの検討資料。
**一度実装して差し戻した**ので、そのときのコードと実測、失敗の原因を残す。

- 状態: **検討メモ**（実装は差し戻し済み・2026-08-01）
- 対象: クリーン EPUB のみ。PDF と Kindle（PDF ページの画像化）は決着済みで対象外
- 関連: `table-colspan-spec.md` §6.2（版面自動フィット）、
  `kindle-rotate-table-image-spec.md`（Kindle は画像へ劣化させる）

---

## 1. 何が問題か

回転テーブルは PDF では**専用ページ**に組まれ、版面いっぱいまで拡大される
（`table-colspan-spec.md` §6.2・2026-08-01 に上限を等倍から `SCALE_MAX = 2.0` へ変更）。
その倍率はインラインの CSS 変数として HTML に焼き込まれ、**クリーン EPUB も同じ値を使う**。

```html
<div class="rotate-table" style="--rotate-table-height:174.0mm; --rotate-table-scale:130%;">
```

```css
.rotate-table > table {
  position: absolute; top: 50%; left: 50%;
  transform: translate(-50%, calc(-50% + var(--rotate-table-shift-y, 0%)))
             rotate(-90deg) scale(var(--rotate-table-scale, 70%));
  inline-size: max-content;
}
body.vs-epub .rotate-table { block-size: 88vh; max-block-size: 88vh; }
```

**箱は画面に追従するのに、中の表は追従しない。** `transform` はレイアウトに参加せず、
`position: absolute` で流れからも外れているため、箱が `88vh` でも表の見かけの大きさは
制限されない。そして `scale()` が取るのは「表の自然な大きさの何倍か」なので、
結果は絶対値（本書の表なら 168.5mm ≒ 637px）に固定される。

| 端末（縦） | 箱 88vh | 表 637px が占める割合 |
|---|---|---|
| iPhone SE（375×667） | 587px | **108%（はみ出す）** |
| iPhone 15（393×852） | 750px | 85% |
| 旧 iPad（768×1024） | 901px | 71% |
| iPad Pro 13"（1024×1366） | 1202px | **53%（広いページに小さな表）** |

表の文字自体は本文と同程度（約 16.5 CSS px）で読める。崩れているのは**ページに対する比率**。

## 2. なぜ「表の高さを 88vh に」と書けないのか

回転後の高さを `88vh` にするには `scale(88vh ÷ 129.6mm)` が要るが、
**CSS の `calc()` は長さ÷長さで無次元数を作れない**（仕様上許されていない）。
`scale()` は数値かパーセントしか受け取らないので、この一点で行き止まりになる。

表側に `height: 88vh` を書いても効かない。`rotate(-90deg)` 後の**見かけの高さを決めるのは
表の「幅」**だからである。

## 3. 試した実装（差し戻し済み）

**長さ÷長さは書けないが、長さ÷数値なら書ける**——これを使う。前処理が
「表の幅はフォントサイズの何倍か」を**無次元数**で渡し、CSS 側は `font-size` を
画面高から導く。`scale()` は使わない。

### 3.1 前処理（`TableConverter`）

```ruby
# クリーン EPUB のセル左右パディング（em・片側）。リフローには版面が無いので、
# 余白も mm 固定ではなく文字サイズへ追従させる。
CELL_PAD_EM = 0.3

# 表の幅がフォントサイズの何倍か（無次元）。
def em_width(table)
  column_widths_em(table).sum + (table.alignments.size * 2 * CELL_PAD_EM)
end

# estimate_rotate_style の戻り値へ 2 つ足す
height.merge('rotate-table-scale'    => "#{(scale * 100).round}%",
             'rotate-table-em-width' => em_width(table_model).round(1).to_s,
             'rotate-table-max-font' => "#{(font_mm * SCALE_MAX).round(2)}mm")
```

`column_widths_em` は `table_dimensions_mm` から列幅計算を切り出したもの（両者で共用）。

出力される HTML:

```html
<div class="rotate-table" style="--rotate-table-height:174.0mm; --rotate-table-scale:130%;
     --rotate-table-em-width:36.2; --rotate-table-max-font:6.7mm;">
```

### 3.2 CSS（`components.css`）

```css
body.vs-epub .rotate-table > table {
  font-size: clamp(8px,
                   calc(88vh * 0.95 / var(--rotate-table-em-width, 40)),
                   var(--rotate-table-max-font, 2em));
  /* 追従させるので scale は外す。translate と rotate はそのまま */
  transform: translate(-50%, calc(-50% + var(--rotate-table-shift-y, 0%))) rotate(-90deg);
}

body.vs-epub .rotate-table :is(th, td) {
  padding: 0.3em;   /* TableConverter::CELL_PAD_EM と対 */
}
```

`clamp()` が「下限 8px（可読性）／画面高に追従／上限は本文の 2 倍」を 1 行で表す。
上限は PDF の `SCALE_MAX` と同じ値を前処理から渡すので、同じ本で PDF と EPUB の
上限が食い違わない。`0.95` は幅推定の安全率（`TableConverter::SAFETY` と同値）。

### 3.3 計算上はうまくいっていた

```
本文 12.7px / 上限 25.3px（本文の 2 倍）

  iPhone SE    88vh= 587px  font=15.4px (1.22倍)  表の高さ=558px  箱の  94%
  iPhone 15    88vh= 750px  font=19.7px (1.55倍)  表の高さ=712px  箱の  95%
  旧 iPad      88vh= 901px  font=23.6px (1.87倍)  表の高さ=856px  箱の  95%
  iPad Pro 13" 88vh=1202px  font=25.3px (2.00倍)  表の高さ=917px  箱の  76%
```

小さい端末でははみ出さなくなり、大きい端末では `SCALE_MAX` で頭打ちになる。
どの端末でも前回（637px 固定）より**大きくなる**はずだった。

## 4. なぜ差し戻したか

### 4.1 実機では前回より小さく見えた

著者の実機確認で「前回の実装のほうがページ全体に大きく表示されていた」。
計算とは逆の結果である。

**最有力の原因: リーダーが `vh` または `clamp()` を解していない。** その場合
`font-size` の宣言ごと無効になり、表は**倍率なしの本文サイズ**で組まれる——
`scale(130%)` があった従来より確実に小さくなる。

`vh` のリーダー依存性は `88vh` を導入した時点から未検証項目として残っていた
（CHANGELOG「実機での確認が必要（`vh` の解釈はリーダー依存）」）。
**そこに全体重を預ける設計にしたのが判断ミス**だった。しかも縮退は
「黙って小さくなるだけ」で、壊れたことに気づけない形をしている。

### 4.2 著者の `scale=` が EPUB で効かなくなった

`:::{.rotate-table scale=60%}` は `--rotate-table-scale` を通じて PDF と EPUB の
両方に効いていた。EPUB の `transform` から `scale()` を外したことで、
**EPUB だけ著者指定を無視する**ようになった。記法の説明と食い違う退行である。

## 5. 次に検討するなら

### 5.1 先に確かめるべきこと

**リーダーが `vh` をどう解釈するか**が全ての前提である。ここが未検証のまま設計を
選ぶと、また同じ失敗をする。確かめ方の案:

- 検証用の小さな EPUB（`88vh` の色付きブロックと `calc(88vh/40)` の文字）を作り、
  実機のリーダーで見てもらう
- ページ送り型のリーダーでは `vh` が「画面の高さ」なのか「ページ枠の高さ」なのかも
  同時に見る（この 2 つは一致しないことがある）

### 5.2 設計の選択肢

| 案 | 内容 | 長所 | 短所 |
|---|---|---|---|
| **現状維持** | `scale()` のまま（差し戻した状態） | 著者の `scale=` が効く。PDF と同じ見た目 | 大画面では小さく、小画面でははみ出す |
| **`@supports` で切替** | §3 を `@supports` で囲み、解さないリーダーは現状のまま | 縮退しても従来と同じ | `vh` の「対応」と「正しく解釈」は別物なので保証にならない |
| **表幅を `88vh`** | `inline-size: 88vh` にして `scale()` を外す | 2 行で済み、常にぴったり収まる | 文字は本文サイズのまま列だけ伸び、大画面で間延びする |
| **EPUB も画像化** | Kindle と同じく PDF ページを切り出す | 見た目が完全に一致し、端末非依存 | 文字が選択できず、拡大で劣化する（クリーン EPUB の利点を捨てる） |

### 5.3 やらないと決めたこと

- **メディアクエリで段階的に縮める案**。小画面のはみ出ししか解けず、大画面で小さくなる
  ほうの問題を放置する。刻みの閾値も本ごとに変わるので保守しにくい。

## 6. 参考: 差し戻した差分

`git show e7ff7f20` 時点へ戻した。試作の全差分は
`scratchpad/reflow-attempt.diff`（143 行）に退避してあるが、本メモの §3 に
要点は転記済みなので、再着手時はこちらを見れば足りる。
