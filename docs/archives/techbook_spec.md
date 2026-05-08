# Techbook モード仕様書

- バージョン: 0.1.0
- 作成日: 2026-04-29
- 対象: Vivlio Starter

---

## 1. 概要

技術書典向け印刷用 PDF 生成において、Chromium の PDF エンジンに起因する以下の問題を回避するための専用処理モードを定義する。

| 問題 | 原因 | 本仕様での対処 |
|------|------|--------------|
| カラー絵文字の Type 3 フォント化 | Chromium がカラービットマップグリフを CIDFont として埋め込めない | SVG img タグへの差し替え |
| 可変フォント（Variable Font）の PDF 出力不正 | Chromium の PDF エンジンが font-variation-settings を正しく処理できない | CSS への静的インスタンス指定の自動注入 |

本モードは `book.yml` の `output.pdf.techbook: true` で有効化する。
`vs build` コマンドの追加オプションは不要。

---

## 2. 有効化設定

```yaml
# book.yml
output:
  pdf:
    techbook: true
    emoji_credit: true   # 省略時デフォルト: true（奥付へのクレジット表記）
```

### 設定項目

| キー | 型 | デフォルト | 説明 |
|------|----|-----------|------|
| `techbook` | Boolean | false | Techbook モードの有効/無効 |
| `emoji_credit` | Boolean | true | 奥付への Twemoji クレジット表記の自動挿入 |

---

## 3. 処理① カラー絵文字 SVG 差し替え

### 3.1 処理タイミング

Markdown → HTML 変換時の前処理として実行する。
Vivliostyle によるビルド前に完了していること。

### 3.2 対象絵文字

Twemoji が提供する全絵文字（約 3,800 種）を対象とする。
SVG ファイルが存在する絵文字はすべて差し替え、存在しない場合はそのままスルーする。

ハードコードされた絵文字リストは持たない。SVG ファイルの有無のみで判定する。

### 3.3 SVG ファイルの配置

Twemoji SVG ファイルは Gem に同梱する。
絵文字は CSS と共に HTML に埋め込まれるスタイル資産であるため、`stylesheets/` 配下に配置する。

```
vivlio_starter/
  stylesheets/
    themes/          # 既存
    twemoji/
        2705.svg     # ✅
        274c.svg     # ❌
        1f534.svg    # 🔴
        1f4da.svg    # 📚
        ...（約 3,800 ファイル、合計 約 380KB）
```

ネットワーク接続なしでビルドできることを保証するため、CDN 参照は行わない。
Twemoji の SVG を追加・更新した場合は Gem のバージョンアップで対応する。

### 3.4 差し替え後の HTML

```html
<!-- 差し替え前 -->
✅ 正常です

<!-- 差し替え後 -->
<img src="[vivlio_starter gem path]/stylesheets/twemoji/2705.svg"
     alt="✅"
     class="emoji vs-emoji"
     width="1em"
     height="1em"
     style="vertical-align: -0.15em;">
 正常です
```

`src` は絶対パスで出力する（HTML ファイルの配置場所に依存しないよう）。

### 3.5 CSS

以下のスタイルを自動注入する。

```css
/* Vivlio Starter: techbook emoji style */
img.vs-emoji {
  display: inline;
  width: 1em;
  height: 1em;
  vertical-align: -0.15em;
}
```

### 3.6 クレジット表記

`emoji_credit: true`（デフォルト）のとき、奥付 HTML に以下を自動挿入する。

```html
<p class="vs-emoji-credit">
  絵文字画像: <a href="https://twemoji.twitter.com">Twemoji</a>
  © Twitter, Inc. (CC BY 4.0)
</p>
```

---

## 4. 処理② 可変フォント静的インスタンス指定

### 4.1 問題の背景

Chromium の PDF エンジンは `font-variation-settings` を PDF 出力時に正しく処理できない。
可変フォント（Variable Font）を CSS でそのまま指定すると、PDF 上でフォントの描画が崩れる場合がある。

### 4.2 処理方針

Vivlio Starter のテーマ CSS（および `vivlio_starter.yml` で指定されたカスタム CSS）に可変フォントが含まれる場合、
静的インスタンスを明示する `@font-face` 宣言を自動注入する。

### 4.3 検出条件

以下のいずれかを含む `@font-face` 宣言を可変フォントと判定する。

- `font-variation-settings` プロパティが指定されている
- `format("woff2-variations")` または `format("truetype-variations")` が指定されている
- `font-weight` にレンジ指定（例: `100 900`）が含まれている

### 4.4 注入する CSS

検出した可変フォントに対し、以下のような静的インスタンス指定を追加注入する。

```css
/* Vivlio Starter: techbook variable font static instance */
@font-face {
  font-family: "MyFont-Regular";
  src: url("MyVariableFont.woff2") format("woff2");
  font-weight: 400;
  font-style: normal;
  font-variation-settings: "wght" 400;
}

@font-face {
  font-family: "MyFont-Bold";
  src: url("MyVariableFont.woff2") format("woff2");
  font-weight: 700;
  font-style: normal;
  font-variation-settings: "wght" 700;
}
```

`font-variation-settings` の軸（axis）と値は、検出した CSS の定義から自動導出する。
自動導出が困難な場合は `book.yml` での明示指定にフォールバックする（将来仕様）。

### 4.5 現バージョンの制約

可変フォントの自動検出・注入は複雑度が高いため、初期実装では以下のスコープとする。

- **実装する**: `book.yml` に明示指定されたフォントへの静的インスタンス注入
- **実装しない**: CSS ファイルの自動スキャンによる可変フォント検出

```yaml
# book.yml での明示指定（初期実装の対象）
output:
  pdf:
    techbook: true
    variable_fonts:
      - family: "MyFont"
        src: "fonts/MyVariableFont.woff2"
        instances:
          - weight: 400
            settings: '"wght" 400'
          - weight: 700
            settings: '"wght" 700'
```

---

## 5. 実装クラス構成

```
lib/vivlio_starter/
  techbook/
    processor.rb          # Techbook モードのエントリポイント
    emoji_replacer.rb     # 絵文字 SVG 差し替え処理
    variable_font_injector.rb  # 可変フォント静的インスタンス注入
    credit_inserter.rb    # クレジット表記挿入
```

### Processor（エントリポイント）

```ruby
# lib/vivlio_starter/techbook/processor.rb

module VivlioStarter
  module Techbook
    class Processor
      def initialize(config)
        @config     = config
        @techbook     = config.dig("output", "pdf", "techbook")
        @emoji_credit = config.dig("output", "pdf", "emoji_credit") != false
      end

      def enabled? = @techbook == true

      def process(html)
        return html unless enabled?

        html = EmojiReplacer.new.process(html)
        html = CreditInserter.new.process(html) if @emoji_credit
        html
      end

      def inject_css
        return "" unless enabled?
        VariableFontInjector.new(@config).css
      end
    end
  end
end
```

### EmojiReplacer

EMOJI_MAP のハードコードは持たない。
HTML 中のすべての絵文字コードポイントを検出し、SVG ファイルが存在するものだけ差し替える。
SVG ファイルが存在しない絵文字はそのままスルーするため、Twemoji が将来絵文字を追加した際も自動対応できる。

```ruby
# lib/vivlio_starter/techbook/emoji_replacer.rb

module VivlioStarter
  module Techbook
    class EmojiReplacer
      def initialize
        @emoji_dir = Pathname(__dir__).join("../../../stylesheets/twemoji")
      end

      def process(html)
        html.gsub(/\p{Emoji}/) do |char|
          codepoint = emoji_codepoint(char)
          svg = @emoji_dir.join("#{codepoint}.svg")
          svg.exist? ? build_img_tag(char, svg) : char
        end
      end

      private

      # 絵文字のコードポイントを Twemoji のファイル名形式に変換する
      # 例: "✅" -> "2705"、"❤️" -> "2764-fe0f"
      def emoji_codepoint(char)
        char.codepoints.map { _1.to_s(16) }.join("-")
      end

      def build_img_tag(char, src)
        %(<img src="#{src}" alt="#{char}" ) \
        + %(class="emoji vs-emoji" ) \
        + %(width="1em" height="1em" ) \
        + %(style="vertical-align:-0.15em;">)
      end
    end
  end
end
```

---

## 6. ビルドパイプライン上の位置づけ

```
book.yml 読み込み
  ↓
techbook: true を検出
  ↓
Markdown → HTML 変換
  ↓  ← EmojiReplacer がここで動く
HTML（絵文字 SVG 差し替え済み）
  ↓  ← VariableFontInjector が CSS を注入
Vivliostyle / Chromium によるビルド
  ↓
PDF（Type 3 絵文字なし）
```

Ghostscript による後処理（`vs press`）は本モードの対象外とする。
`vs press` は将来、入稿品質向上のための別コマンドとして実装する。

---

## 7. テスト方針

| テスト項目 | 確認内容 |
|-----------|---------|
| `techbook: false`（デフォルト） | 絵文字差し替えが行われないこと |
| `techbook: true` / 代表的な絵文字（✅ ❌ 🔴 📚） | 各絵文字が `<img>` タグに変換されること |
| `techbook: true` / Twemoji 未収録の文字 | 差し替えをスキップし、元の文字のまま出力されること |
| `techbook: true` / 同一絵文字が複数箇所 | すべて差し替えられること |
| `techbook: true` / 絵文字を含まない HTML | 変換なしで同一内容が出力されること |
| `emoji_credit: true` | 奥付に Twemoji クレジットが挿入されること |
| `emoji_credit: false` | クレジットが挿入されないこと |

---

## 8. 残存する制約（既知事項）

- カラー絵文字を SVG img に差し替えた場合、PDF 上でテキストとしてコピーできない（絵文字単体の制約、本文テキストには影響なし）
- 可変フォントの自動検出は将来仕様。初期実装は `book.yml` 明示指定のみ
- カラー絵文字以外の一般グリフの Type 3 化は `vs press`（Ghostscript 後処理）で対処（別仕様）
