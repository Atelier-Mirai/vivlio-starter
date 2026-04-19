# vivliostyle警告メッセージの解消に関する仕様書

## 警告メッセージ
vs build 実行を実行すると、以下のような警告メッセージが表示される場合がある。


```
[viewer warning] Unknown pseudo-element ::-moz-selection       # × 4
[viewer warning] Unknown pseudo-element ::selection            # × 4
[viewer warning] E_INVALID_PROPERTY -moz-user-select: none     # × 1
[viewer warning] E_INVALID_PROPERTY_VALUE inline-size: min(26em,max-content)  # × 3
[viewer warning] F_UNEXPECTED_STATE ,                          # × 約600（全ページ分）
  ※ ページごとに上記 4種の警告セットが繰り返される（全6ページ分）

Error: page.evaluate: Error: Timeout: レンダリング完了を 300000ms 以内に確認できませんでした
    at eval (eval at evaluate (:1:1), <anonymous>:4:16)

🔍 リンク・画像検証の結果:
   画像: 5 件の問題（存在しない画像: 5）
   外部URL到達性チェック: スキップ（--verify-links で有効化）

📚 janken_v0.1.0.pdf を作成しました。
```

## 警告メッセージの種類と意味

1. Unknown pseudo-element （CSS警告）

::-moz-selection、::selection — Firefox固有の古い擬似要素
Vivliostyleが未対応なだけで、無視して問題なし

2. E_INVALID_PROPERTY / E_INVALID_PROPERTY_VALUE （CSS警告）

-moz-user-select: none — Firefox固有プロパティ
inline-size: min(26em, max-content) — CSS比較関数の未対応
どちらもレンダリングに致命的な影響はなし

3. F_UNEXPECTED_STATE ,（大量）

最も数が多い警告（各ページで数十〜百件以上）
CSSパーサーがカンマ区切りの値を解析中に想定外の状態に遭遇
min(26em, max-content) のカンマが原因の可能性が高い

## 対策

これらの警告はレンダリングに影響を与えることはないが、見ていて気持ちの良いものではないため、以下の通り修正を行う。

### 1. Unknown pseudo-element ::-moz-selection / ::selection

**原因**: テーマCSSに含まれているブラウザ固有の擬似要素。Vivliostyleは印刷エンジンなので無意味。

**対処**: テーマCSSから該当ルールを削除する。

```css
/* 削除する */
::-moz-selection { background: #b3d4fc; }
::selection      { background: #b3d4fc; }
```

**EPUB視点での評価**: EPUBリーダー（Kindle、楽天Kobo、Apple Books等）は独自の選択色スタイルを持っており、CSSで上書きしてもほぼ無視される。EPUBの仕様にも含まれないため、削除して良い。

---

### 2. E_INVALID_PROPERTY -moz-user-select: none

**原因**: Firefox固有ベンダープレフィックス。印刷PDFには不要。

**対処**: `user-select` は現在では主要ブラウザすべてでベンダープレフィックスなしが標準化されているため、`-webkit-` / `-moz-` / `-ms-` の3種すべてを削除し、標準構文 `user-select: none` のみ残す。

```css
/* 変更前 */
-webkit-user-select: none;
-moz-user-select: none;
-ms-user-select: none;
user-select: none;

/* 変更後 */
user-select: none;
```

**対象ファイル**:
- `stylesheets/prism.css`
- `lib/project_scaffold/stylesheets/prism.css`

**EPUB視点での評価**: EPUBリーダーはFirefoxエンジンで動いているわけではない。テキスト選択の制御もリーダー側が主導権を持つため、削除して良い。

---

### 3. E_INVALID_PROPERTY_VALUE inline-size: min(26em, max-content)

**原因**: CSS比較関数 `min()` の中に `max-content` キーワードを含む書き方をVivliostyleが未対応。元コードの意図は「最大 26em 幅に収める／内容が短ければ内容幅に縮む」ことだった。

**対処**: `min()` を使わずに同等の挙動を実現する。さらに、用紙サイズ（A5/B5/A4）によって最大幅を変えるため、既存の CSS カスタムプロパティ書き換えインフラ（`lib/vivlio/starter/cli/pre_process/css_updater.rb`）を利用する。

#### 3-1. CSS 側: `min()` を廃止し、`max-inline-size` + `fit-content` に分離

```css
/* 変更前（stylesheets/layout-utils.css） */
.align-left:not(:is(.figure, figure, img, svg)) {
  margin-inline-start: 0;
  margin-inline-end: auto;
  inline-size: min(26em, max-content);
}

/* 変更後 */
.align-left:not(:is(.figure, figure, img, svg)) {
  margin-inline-start: 0;
  margin-inline-end: auto;
  max-inline-size: var(--align-max-width);
  inline-size: fit-content;
}
```

同様の変更を `.align-center` / `.align-right` の 3 ルールに適用する。

#### 3-2. CSS 側: 既定値を `page-settings.css` に追加

```css
/* stylesheets/page-settings.css */
:root {
  --page-width:       210mm;
  --page-height:      297mm;
  --paper-scale:      1.0;
  --align-max-width:  40em;  /* A4=40em, B5=36em, A5=26em（前処理から上書き） */
  /* ... */
}
```

#### 3-3. Ruby 側: `css_updater.rb` で判型ごとに上書き

既存の `build_css_variable_mappings` に 1 行追加:

```ruby
# lib/vivlio/starter/cli/pre_process/css_updater.rb
['--align-max-width',       page_cfg[:align_max_width]],
```

`normalize_page_config`（`calculate_paper_scale` と同じ場所）で判型別の値を算出:

```ruby
# 用紙幅から align_max_width を算出
# （A5=148mm → 26em, B5=182mm → 36em, A4=210mm → 40em）
def calculate_align_max_width(width)
  w_mm = parse_to_mm(width)
  return '40em' unless w_mm
  return '26em' if w_mm <= 155  # A5 相当（148mm）
  return '36em' if w_mm <= 190  # B5 相当（182mm / 176mm）
  '40em'                        # A4 以上
end
```

**方式選定の理由**: プロジェクトには既に `css_updater.rb` が `--page-width` / `--page-height` / `--paper-scale` などを `page.use` に応じて上書きするインフラを持っており、`page-settings.css` のコメントでも「前処理から上書き」を明示している。新変数 `--align-max-width` を同じ仕組みに乗せることで、(1) 新しい前処理を追加する必要がない、(2) テーマ側で `--align-max-width: 30em` と上書きする拡張も自然に可能、(3) 既存方式と一貫する。

**EPUB視点での評価**: EPUB3のCSSはモダンCSSに対応しつつあるが、リーダーごとの実装差が大きい。`min()` 関数は対応しているリーダーが多いが、`max-content` キーワードとの組み合わせは怪しい。Vivliostyleが警告を出しているくらいなので、EPUBリーダーでも同様に無視される可能性が高い。`max-inline-size` + `fit-content` の組み合わせはどちらも基礎的な CSS3 仕様で、互換性が高い。

---

### 4. F_UNEXPECTED_STATE ,（大量）

**原因**: 上記3の `min(26em, max-content)` のカンマをCSSパーサーが誤って解釈し、連鎖的に大量発生している。

**対処**: 3を修正すれば、これも大半は消える。

---

## 方針まとめ

| 項目 | PDF | EPUB | 対処 |
|------|-----|------|------|
| `::selection` 系 | 不要 | 不要 | 削除 |
| `-moz-user-select` | 不要 | 不要 | 削除 |
| `min(26em, max-content)` | 不要 | 危険 | `26em` に置換 |

将来的にEPUB対応を視野に入れるなら、むしろ今のうちに修正しておく方が後々楽である。

