# 用語集バックリンク重複排除 仕様書

## 1. 概要

同一ページ内で同じ用語が複数回出現した場合、**最初の出現のみ**にバックリンクを表示し、重複するページ番号を排除する機能を実装する。

## 2. 現状の問題

### 2.1 現在の動作

```
用語集ページのバックリンク:
  p.i, v, 2, 4, 4, 5, 5, 10, 11, 11, 11, 15
```

- 同じページに同じ用語が複数回出現すると、それぞれにバックリンクが生成される
- 同一ページへの重複リンクが発生する

### 2.2 期待する動作

```
用語集ページのバックリンク:
  p.i, v, 2, 4, 5, 10, 11, 15
```

- 同じページ内で同じ用語が複数回出現しても、バックリンクは各ページにつき1件のみ

### 2.3 概要と技術的制約

#### 2.3.1 問題
- 同じ章内で用語が複数回出現 → バックリンクが `p.4, 4` と重複
- 本文中にも各出現に†が付与される

#### 2.3.2 現状の技術的制約
Vivliostyleの`target-counter`は**レンダリング時**にページ番号を解決するため：
- ❌ HTML生成時点では実際のページ番号が不明
- ❌ 「同一ページ」を100%正確に判断できない
- ✅ 「同一章（ファイル）」の判断は可能

となる。よって、glossary-linkについてCSSで同一ページの重複を排除する方法は不可能。

## 3. 実装アーキテクチャ（2パス方式）

### 3.1 概要

Vivliostyle のレンダリング済み DOM から実際のページ配置を取得し、HTML を浄化してから PDF を再生成する。

```
Step 8  → 全体PDF生成（1回目・通常ビルド）
Step 8b → バックリンク重複排除
  ├─ Phase 1: vivliostyle preview + Playwright でページマッピング取得
  ├─ Phase 2: Nokogiri で HTML 浄化（_glossarypage.html + 本文HTML）
  └─ Phase 3: 浄化済み HTML で PDF 再ビルド（Step 8c）
Step 9  → 表紙・奥付PDF生成（以降は通常どおり）
```

### 3.2 Phase 1: ページマッピング抽出

vivliostyle preview でレンダリングすると、次のような DOM が生成される。
（[raw.html](./raw.html)より抜粋）

```html
<div data-vivliostyle-page-container="true"
     data-vivliostyle-page-index="0"
     data-vivliostyle-spine-index="0">
  <a id="gls-src-08-web-ウェブサイト-4" class="glossary-link"
     href="_glossarypage.html#gls-ウェブサイト"><sup>†</sup></a>
</div>
<div data-vivliostyle-page-container="true"
     data-vivliostyle-page-index="1"
     data-vivliostyle-spine-index="0">
  <a id="gls-src-08-web-ウェブサイト-5" class="glossary-link"
     href="_glossarypage.html#gls-ウェブサイト"><sup>†</sup></a>
</div>
```

**処理フロー:**
1. `vivliostyle preview --no-open-viewer --port 13100` をバックグラウンドで起動
2. Playwright（ヘッドレス Chromium）で preview URL にアクセス
3. 全ページの `data-vivliostyle-page-container` が安定するまでポーリング待機
4. 各ページコンテナ内の `.glossary-link` と `.glossary-backlink` を走査
5. `{ anchor_id, href, page_index, spine_index }` のマッピングを JSON で出力
6. preview サーバーを停止

**重複判定キー:** `(spine_index, page_index)` の組み合わせ。
同じ page_index でも spine_index が異なれば別ページとして扱う。

### 3.3 Phase 2: HTML 浄化

Nokogiri を使用して以下の加工を行う。

**用語集ページ（`_glossarypage.html`）:**
- `<p class="glossary-backlinks">` 内の `<a class="glossary-backlink">` を走査
- href から anchor_id を抽出し、ページマッピングと照合
- 同一 (spine_index, page_index) を指すバックリンクの2件目以降を DOM から削除
- 前後の不要な空白テキストノードも除去

**本文 HTML（`08-web.html` 等）:**
- `<a class="glossary-link" id="gls-src-...">` を走査
- `(spine_index, page_index, glossary_href)` の3つ組で一意性を判定
- 同一ページ内・同一用語の2件目以降の†リンクを DOM から削除

### 3.4 Phase 3: PDF 再ビルド

浄化済み HTML で `vivliostyle build` を再実行し、`_sections.pdf` を上書きする。

## 4. ファイル構成

```
lib/vivlio/starter/cli/build/
  ├─ extract_page_mapping.mjs       # Node.js: Playwright でページマッピング取得
  ├─ page_mapping_extractor.rb      # Ruby: preview 起動/停止 + スクリプト実行
  ├─ backlink_deduplicator.rb       # Ruby: Nokogiri で HTML 浄化
  ├─ backlink_dedup_orchestrator.rb # Ruby: ワークフロー全体の統括
  └─ pipeline.rb                    # Step 8b として統合
test/
  └─ test_backlink_deduplicator.rb  # Minitest: HTML 浄化のユニットテスト
```

## 5. 設定

`config/book.yml` で制御可能:
```yaml
glossary:
  backlink_dedup: true   # false で無効化（デフォルト: true）
```

索引・用語集機能自体が無効（`index_glossary.enabled: false`）の場合は自動的にスキップ。

## 6. 実装上の注意

- anchor_id と HTML 要素を正確に対応させること
- ページ番号はローマ数字（i, ii..）・算用数字（1, 2..）のどちらでも対応可能（target-counter がレンダリング時に解決するため、HTML 浄化時にはページ番号自体を扱わない）
- Ruby 4.x の `Data.define`、`it` パラメータ、エンドレスメソッドを積極活用
- Nokogiri で DOM 操作、Playwright でヘッドレスブラウザ自動化
- エラー発生時は重複排除をスキップし、既存 PDF で続行する（ビルド全体を止めない）

