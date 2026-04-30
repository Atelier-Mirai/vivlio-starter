# 絵文字 SVG 差し替えテスト

:::{.chapter-lead}
Techbook モードの絵文字 SVG 差し替えが正しく動作するかを確認するためのテストページです。Chromium の PDF エンジンはカラー絵文字を Type 3 フォントとして埋め込んでしまうため、Twemoji の SVG 画像に差し替えることで印刷品質を確保します。
:::

## 基本的な絵文字

:::{.section-lead}
Twemoji に収録されている代表的な絵文字が `<img>` タグに差し替えられることを確認します。
:::

以下の絵文字はすべて Twemoji に SVG が用意されています。

- ✅ チェックマーク（U+2705）
- ❌ バツ印（U+274C）
- 🔴 赤丸（U+1F534）
- 📚 本の山（U+1F4DA）
- ⭐ 星（U+2B50）
- 🎉 パーティー（U+1F389）

## 文中の絵文字

:::{.section-lead}
テキストの途中に絵文字が出現した場合、絵文字だけが差し替えられ、前後のテキストが保全されることを確認します。
:::

Techbook モードが有効な場合、この文中の ✅ や ❌ が `<img>` タグに差し替えられます。周囲のテキストはそのまま残り、レイアウトが崩れることはありません。

ビルドが ✅ 成功すると、PDF に Type 3 フォントが含まれなくなります。もし ❌ 失敗した場合は、`book.yml` の `output.pdf.techbook` 設定を確認してください。

## 同一絵文字の複数出現

:::{.section-lead}
同じ絵文字が複数箇所に出現した場合、すべての出現箇所が漏れなく差し替えられることを確認します。
:::

✅ 第一項目、✅ 第二項目、✅ 第三項目。すべての ✅ が差し替えられるべきです。

## 表の中の絵文字

:::{.section-lead}
HTML の `<td>` 要素内に絵文字が含まれる場合でも、表の構造を壊さずに差し替えが行われることを確認します。
:::

| 状態 | アイコン | 説明 |
|:-----|:--------|:-----|
| 成功 | ✅ | テスト通過 |
| 失敗 | ❌ | テスト不合格 |
| 警告 | ⚠️ | 要確認 |
| 情報 | ℹ️ | 参考情報 |
| 進行中 | 🔴 | 作業中 |

## 複合絵文字（ZWJ シーケンス）

:::{.section-lead}
Zero Width Joiner（ZWJ）で結合された複合絵文字のコードポイント変換が正しく行われることを確認します。
:::

ZWJ シーケンスは複数のコードポイントを U+200D で結合した絵文字です。Twemoji のファイル名はハイフン結合（例: `1f468-200d-1f4bb.svg`）となります。

- 👨‍💻 技術者（U+1F468 U+200D U+1F4BB）
- 👩‍🔬 科学者（U+1F469 U+200D U+1F52C）
- 🏳️‍🌈 レインボーフラグ

## 絵文字を含まないテキスト

:::{.section-lead}
絵文字が含まれない段落が、Techbook モード有効時でも一切変更されないことを確認します。
:::

この段落には絵文字が含まれていません。Techbook モードが有効でも、このテキストはそのまま出力されるべきです。HTML の特殊文字（&amp; &lt; &gt;）やリンク [Vivlio Starter](https://github.com) も影響を受けません。

## Twemoji 未収録の絵文字

:::{.section-lead}
Twemoji に SVG ファイルが存在しない絵文字が、差し替えをスキップされてそのまま残ることを確認します。
:::

以下は比較的新しい Unicode バージョンで追加された絵文字です。Twemoji に SVG が用意されていなければ、元の文字がそのまま出力されます。

🫠 溶ける顔（Unicode 14.0）

## コードブロック内の絵文字

:::{.section-lead}
コードブロック内に絵文字が含まれる場合の挙動を確認します。
:::

```ruby
# コードブロック内の絵文字
puts "✅ テスト通過"
puts "❌ テスト失敗"
```

> **注意**: 現在の実装では、コードブロック内の絵文字も差し替え対象になります。将来的にコードブロック内を除外する場合は、HTML パーサーとの連携が必要です。

## SVG ロゴ画像の Type 3 検証

:::{.section-lead}
著者が `![](logo.svg)` のように SVG 画像を参照した場合、Chromium が SVG 内のパスデータを Type 3 フォントとして PDF に埋め込むかどうかを検証します。`docs/logos/` 配下の全 SVG ロゴを表示します。
:::

### awesome_book

![awesome_book](awesome_book.svg)

### bookyml

![bookyml](bookyml.svg)

### chaptercss

![chaptercss](chaptercss.svg)

### vsbuild

![vsbuild](vsbuild.svg)

### vivlio_starter_logo_outline

![vivlio_starter_logo_outline](vivlio_starter_logo_outline.svg)

### vivlio_starter_logo_outline_stacked

![vivlio_starter_logo_outline_stacked](vivlio_starter_logo_outline_stacked.svg)

### vivlio_starter_logo_text

![vivlio_starter_logo_text](vivlio_starter_logo_text.svg)

### vivlio_starter_logo_text_stacked

![vivlio_starter_logo_text_stacked](vivlio_starter_logo_text_stacked.svg)

### vs_logo_outline

![vs_logo_outline](vs_logo_outline.svg)

### vs_logo_outline_garnish

![vs_logo_outline_garnish](vs_logo_outline_garnish.svg)

### vs_logo_text_garnish

![vs_logo_text_garnish](vs_logo_text_garnish.svg)

### vs_vivlio_starter_logo_outline

![vs_vivlio_starter_logo_outline](vs_vivlio_starter_logo_outline.svg)

### vs_vivlio_starter_logo_outline_stacked

![vs_vivlio_starter_logo_outline_stacked](vs_vivlio_starter_logo_outline_stacked.svg)

### vs_vivlio_starter_logo_text

![vs_vivlio_starter_logo_text](vs_vivlio_starter_logo_text.svg)

### vs_vivlio_starter_logo_text_stacked

![vs_vivlio_starter_logo_text_stacked](vs_vivlio_starter_logo_text_stacked.svg)
