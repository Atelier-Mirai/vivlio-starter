# 索引ページ番号重複排除 および 索引・用語集統合 仕様書

## 1. 概要

本仕様書は以下の2つの機能を定義する。

1. **索引ページ番号の重複排除**: Playwright + Vivliostyle preview による DOM 解析で、索引ページ（`_indexpage.html`）の同一ページ番号重複を排除する
2. **索引・用語集機能の統合**: 機能的に類似する索引と用語集の実装を統合し、コードベースを簡潔にする

---

## 2. 索引ページ番号の重複排除

### 2.1 現状の問題

現在の索引は `HierarchicalIndex#deduplicate_same_page!` で「同一 HTML ファイル（章）内の最初の出現のみ」を残す方式で重複を排除している。しかし、1つの章が複数ページにまたがる場合、実際には異なるページに配置された索引語が排除されてしまう。

```
現在の索引ページ出力:
  コンピュータ    i, 1, 5
  プログラミング  i, 2, 11, 19
  ブラウザ        4
```

「コンピュータ」は 00-preface（p.i）、01-life（p.1, 2, 3）、08-web（p.5, 8, 15）に出現するが、章単位の重複排除により各章1件ずつ（計3件）しか掲載されない。

```
期待する索引ページ出力:
  コンピュータ    i, 1, 2, 3, 5, 8, 15
  プログラミング  i, v, 2, 11, 15, 19, 20
  ブラウザ        4, 5, 8, 11, 12, 13
```

同一ページ内の重複のみを排除し、異なるページへの参照はすべて掲載する。

### 2.2 技術的制約（用語集と共通）

Vivliostyle の `target-counter` は**レンダリング時**にページ番号を解決するため：
- ❌ HTML 生成時点では実際のページ番号が不明
- ❌ 「同一ページ」を HTML 生成時に判断できない
- ✅ Playwright でレンダリング済み DOM を解析すれば、正確なページ配置を取得可能

### 2.3 用語集バックリンク重複排除との比較

| 項目 | 用語集（実装済み） | 索引（本仕様で実装） |
| :--- | :--- | :--- |
| **対象 HTML** | `_glossarypage.html` + 本文 HTML | `_indexpage.html` + 本文 HTML |
| **本文側の要素** | `<a class="glossary-link" id="gls-src-...">` | `<dfn id="idx-...">` / `<span id="idx-...">` |
| **ページ側の要素** | `<a class="glossary-backlink">` | `<a href="...#idx-...">` |
| **重複判定キー** | `(spine_index, page_index, glossary_href)` | `(spine_index, page_index)` per term |
| **本文の†削除** | あり（同一ページ内の2件目以降） | 不要（索引語は本文に視覚的マークなし） |

---

## 3. 実装アーキテクチャ

### 3.1 概要

用語集バックリンク重複排除（Step 8）の既存インフラを拡張し、索引の重複排除を同一パスで実行する。

```
Step 7  → 全体PDF生成（1回目・通常ビルド）
Step 8  → 重複排除（用語集 + 索引を統合処理）
  ├─ Phase 1: vivliostyle preview + Playwright でページマッピング取得
  │           （glossary-link + index-term の両方を収集）
  ├─ Phase 2: Nokogiri で HTML 浄化
  │   ├─ _glossarypage.html: バックリンク重複排除（既存）
  │   ├─ 本文 HTML: †リンク重複排除（既存）
  │   └─ _indexpage.html: ページ番号リンク重複排除（新規）
  └─ Phase 3: 浄化済み HTML で PDF 再ビルド
Step 9  → 表紙・奥付PDF生成（以降は通常どおり）
```

### 3.2 Phase 1: ページマッピング抽出の拡張

`extract_page_mapping.mjs` を拡張し、`.index-term`（`<dfn>` / `<span>`）の配置情報も収集する。

```javascript
// 既存: glossary-link の収集
pageEl.querySelectorAll('.glossary-link').forEach(link => { ... });

// 新規: index-term の収集
pageEl.querySelectorAll('.index-term').forEach(el => {
  const anchorId = el.getAttribute('id') || '';
  if (anchorId.startsWith('idx-')) {
    indexMappings.push({
      anchor_id: anchorId,
      page_index: pageIndex,
      spine_index: spineIndex
    });
  }
});
```

**出力 JSON の拡張:**
```json
{
  "mappings": [ ... ],
  "backlink_mappings": [ ... ],
  "index_mappings": [
    { "anchor_id": "idx-ah5dgi14g1ji-1", "page_index": 0, "spine_index": 0 },
    { "anchor_id": "idx-ah5dgi14g1ji-5", "page_index": 3, "spine_index": 1 },
    ...
  ],
  "total_pages": 42,
  "extracted_at": "2026-02-07T14:00:00.000Z"
}
```

### 3.3 Phase 2: 索引ページの重複排除

`BacklinkDeduplicator` を拡張し、`_indexpage.html` の処理を追加する。

**`_indexpage.html` の現在の構造:**
```html
<dt>コンピュータ</dt>
<dd>
  <a href="00-preface.html#idx-ah5dgi14g1ji-1" class="frontmatter"></a>
  <a href="01-life.html#idx-ah5dgi14g1ji-5"></a>
  <a href="08-web.html#idx-ah5dgi14g1ji-19"></a>
</dd>
```

現在は章ごとに1件のみだが、本仕様では**全出現箇所のリンクを生成**した上で、Playwright のページマッピングを用いて同一ページの重複を排除する。

**処理フロー:**
1. `_indexpage.html` の各 `<dd>` 内の `<a>` を走査
2. 各 `<a>` の `href` から `anchor_id` を抽出（`#` 以降）
3. `index_mappings` から `(spine_index, page_index)` を取得
4. 同一用語について同じ `(spine_index, page_index)` を指す `<a>` の2件目以降を削除

### 3.4 Phase 1 の前提: 全出現リンクの生成

Phase 2 で重複排除を行うためには、`_indexpage.html` に**全出現箇所**へのリンクが含まれている必要がある。

**変更箇所:** `HierarchicalIndex#deduplicate_same_page!` を廃止し、`IndexPageBuilder#generate_page_links` が全リンクを出力するようにする。重複排除は Phase 2（Playwright ベース）に一元化する。

```
変更前: IndexPageBuilder が章単位で重複排除 → 3件のリンク
変更後: IndexPageBuilder が全リンクを出力 → 25件のリンク → Phase 2 で重複排除 → 7件のリンク
```

### 3.5 Phase 3: PDF 再ビルド

既存の Phase 3 と同一。浄化済み HTML で `vivliostyle build` を再実行し、`_sections.pdf` を上書きする。

---

## 4. 索引・用語集機能の統合

### 4.1 機能比較

| 項目 | 用語集 (Glossary) | 索引 (Index) |
| :--- | :--- | :--- |
| **本文の表示** | あり（†記号） | なし（透明アンカー） |
| **リンク機能** | あり（†→用語解説） | なし |
| **バックリンク** | あり（用語→本文） | あり（索引語→本文） |
| **ページ番号表示** | あり（`target-counter`） | あり（`target-counter`） |
| **説明文** | あり | なし |
| **重複排除** | Playwright ベース（実装済み） | Playwright ベース（本仕様） |

用語集と索引は「本文中の†表示」と「説明文の有無」を除けば、ほぼ同一の機能である。

### 4.2 統合の方針

#### 4.2.1 データモデルの統一

現在、索引と用語集は別々のデータファイルを持つ：
- `config/index_terms.yml` — 索引語辞書
- `config/index_glossary_terms.yml` — 用語集辞書（説明文・バックリンク含む）

**統合後:** `index_glossary_terms.yml` を拡張し、索引専用語も同一ファイルで管理する。

```yaml
# config/index_glossary_terms.yml（統合後）
terms:
  - term: コンピュータ
    yomi: こんぴゅーた
    flags: ig          # i=索引, g=用語集, ig=両方
    definition: ''     # 索引のみの場合は空
    backlink_sources:
      - chapter: 00-preface
        occurrence: 1
        anchor_id: gls-src-00-preface-コンピュータ-1
      ...
  - term: CSS
    yomi: CSS
    flags: i           # 索引のみ
    definition: ''
    backlink_sources: []
```

`flags` フィールドにより、各用語が索引・用語集・両方のいずれに属するかを明示する。

#### 4.2.2 ページ生成の統一

| 生成物 | 現在の実装 | 統合後 |
| :--- | :--- | :--- |
| `_indexpage.html` | `IndexPageBuilder` | `UnifiedPageBuilder#build_index!` |
| `_glossarypage.html` | `GlossaryPageBuilder` | `UnifiedPageBuilder#build_glossary!` |

共通処理（読み順ソート、五十音グループ化、`target-counter` リンク生成、バックリンク構築）を `UnifiedPageBuilder` に集約する。

#### 4.2.3 本文タグ付けの統一

`IndexMatchScanner` が索引タグ（`<dfn>` / `<span>`）と用語集リンク（`<a class="glossary-link">`）の両方を生成する現在の方式を維持する。`flags` に基づいて出力を制御する。

| flags | 本文出力 |
| :--- | :--- |
| `i` | `<span class="index-term">` のみ |
| `g` | `<span class="index-term">` + `<a class="glossary-link">†</a>` |
| `ig` | `<span class="index-term">` + `<a class="glossary-link">†</a>` |

> 注: `g` のみ（索引なし・用語集のみ）の場合でも、`<span class="index-term">` は生成する。これは用語集バックリンクのアンカーとして機能するためである。ただし `_indexpage.html` には掲載しない。

#### 4.2.4 重複排除の統一

`BacklinkDeduplicator` が用語集と索引の両方の重複排除を一括で処理する。

```ruby
class BacklinkDeduplicator
  def deduplicate!
    anchor_to_page = build_anchor_to_page_lookup

    # 用語集の重複排除（既存）
    deduplicate_glossary_backlinks!(anchor_to_page)
    deduplicate_body_glossary_links!(anchor_to_page)

    # 索引の重複排除（新規）
    deduplicate_index_page_links!(index_anchor_to_page)

    build_result
  end
end
```

### 4.3 統合のスコープ

#### Phase A（索引重複排除 — 実装済み）
- `extract_page_mapping.mjs` に `.index-term` の収集を追加
- `BacklinkDeduplicator` に `_indexpage.html` の重複排除を追加
- `IndexPageBuilder` から `deduplicate_same_page!` を廃止し、全リンクを出力
- `PageMappingExtractor` の Ruby 側で `index_mappings` を処理

#### Phase B（索引・用語集統合 — 実装済み）
- `index_terms.yml` の内容を `index_glossary_terms.yml` に `flags: i` で移行（自動マイグレーション）
- `UnifiedTermsManager` で統合用語辞書を一元管理
- `IndexMatchScanner` が `index_glossary_terms.yml` から `flags` ベースで用語をロード
- `UnifiedPageBuilder` が `_indexpage.html` と `_glossarypage.html` の両方を生成
- `UnifiedIndexManager` が `UnifiedTermsManager` + `UnifiedPageBuilder` を使用
- `index.rb` の require と呼び出しを統合モジュールに更新

### 4.4 Phase B 統合データモデル

```yaml
# config/index_glossary_terms.yml（統合辞書）
terms:
  - term: コンピュータ
    yomi: こんぴゅーた
    flags: ig              # i=索引, g=用語集, ig=両方
    definition: '...'      # g フラグ時のみ使用
    pattern: "/コンピュータ/"
    source: auto_extracted  # 登録元（auto_extracted / manual_markup / review / unreject）
    score: 250.5           # 自動抽出時のスコア
    approved_at: '2026-02-07 22:00:00'
    backlink_sources:
      - chapter: 00-preface
        occurrence: 1
        anchor_id: gls-src-00-preface-こんぴゅーた-1
```

### 4.5 Phase B 実装ファイル

| ファイル | 役割 |
| :--- | :--- |
| `unified_terms_manager.rb` | 統合用語辞書の CRUD、flags 管理、マイグレーション |
| `unified_page_builder.rb` | `_indexpage.html` + `_glossarypage.html` 生成 |
| `unified_index_manager.rb` | オーケストレーター（統合マネージャー経由） |
| `index_match_scanner.rb` | `index_glossary_terms.yml` から flags ベースで用語ロード |
| `index.rb` | エントリポイント（統合モジュールを require） |

旧ファイル（`index_terms_manager.rb`, `glossary_terms_manager.rb`, `index_page_builder.rb`, `glossary_page_builder.rb`）およびそのテストファイルは削除済み。

---

## 5. ファイル構成

### 5.1 変更対象ファイル

```
lib/vivlio/starter/cli/build/
  ├─ extract_page_mapping.mjs       # 変更: .index-term の収集を追加
  ├─ page_mapping_extractor.rb      # 変更: index_mappings の処理を追加
  ├─ backlink_deduplicator.rb       # 変更: _indexpage.html の重複排除を追加
  └─ backlink_dedup_orchestrator.rb # 変更: 索引重複排除のフロー追加

lib/vivlio/starter/cli/index/
  ├─ index_page_builder.rb          # 変更: 全リンク出力に変更
  └─ hierarchical_index.rb          # 変更: deduplicate_same_page! を廃止

test/
  └─ test_backlink_deduplicator.rb  # 変更: 索引重複排除のテストを追加
```

### 5.2 新規ファイル

なし。既存ファイルの拡張のみで実現する。

---

## 6. 設定

`config/book.yml` で制御可能（既存設定を流用）:

```yaml
index_glossary:
  enabled: true        # false で索引・用語集機能全体を無効化

glossary:
  backlink_dedup: true # false で用語集の重複排除を無効化（デフォルト: true）

index:
  backlink_dedup: true # false で索引の重複排除を無効化（デフォルト: true）
```

`index_glossary.enabled: false` の場合は索引・用語集の重複排除を含む全機能がスキップされる。

---

## 7. DOM 構造の対応表

### 7.1 本文 HTML

```html
<!-- 索引語（index-term） -->
<dfn id="idx-ah5dgi14g1ji-1" class="index-term" data-yomi="こんぴゅーた">コンピュータ</dfn>

<!-- 用語集リンク（glossary-link）— [ig] の場合のみ -->
<a id="gls-src-00-preface-コンピュータ-1" class="glossary-link"
   href="_glossarypage.html#gls-コンピュータ"><sup>†</sup></a>
```

### 7.2 索引ページ（`_indexpage.html`）

```html
<dt>コンピュータ</dt>
<dd>
  <!-- 全出現箇所へのリンク（Phase 2 で重複排除） -->
  <a href="00-preface.html#idx-ah5dgi14g1ji-1" class="frontmatter"></a>
  <a href="00-preface.html#idx-ah5dgi14g1ji-2"></a>
  <a href="01-life.html#idx-ah5dgi14g1ji-5"></a>
  ...
</dd>
```

### 7.3 用語集ページ（`_glossarypage.html`）

```html
<dt id="gls-コンピュータ" class="glossary-term">
  <ruby>コンピュータ<rp>(</rp><rt>こんぴゅーた</rt><rp>)</rp></ruby>
</dt>
<dd class="glossary-definition">
  <p class="glossary-backlinks">
    <a href="00-preface.html#gls-src-00-preface-コンピュータ-1" class="glossary-backlink frontmatter"></a>
    <a href="01-life.html#gls-src-01-life-コンピュータ-5" class="glossary-backlink"></a>
    ...
  </p>
</dd>
```

---

## 8. Playwright ページマッピングの重複判定

### 8.1 用語集（既存）

**重複判定キー:** `(spine_index, page_index, glossary_href)`
- 同一ページ内で同じ用語への†が複数ある場合、2件目以降を削除

### 8.2 索引（新規）

**重複判定キー:** `(spine_index, page_index)` per term
- `_indexpage.html` の各 `<dd>` 内で、同じページを指すリンクの2件目以降を削除
- 用語ごとに独立して判定（異なる用語が同じページにあっても、それぞれ1件ずつ残す）

### 8.3 判定フロー

```
_indexpage.html の <dd> 内:
  <a href="01-life.html#idx-ah5dgi14g1ji-5">  → page (1, 3)  ✅ 残す
  <a href="01-life.html#idx-ah5dgi14g1ji-6">  → page (1, 3)  ❌ 削除（同一ページ）
  <a href="01-life.html#idx-ah5dgi14g1ji-7">  → page (1, 4)  ✅ 残す（別ページ）
  <a href="01-life.html#idx-ah5dgi14g1ji-8">  → page (1, 4)  ❌ 削除（同一ページ）
  <a href="08-web.html#idx-ah5dgi14g1ji-19">  → page (2, 0)  ✅ 残す
```

---

## 9. 実装上の注意

- **Playwright の起動は1回のみ**: 用語集と索引の重複排除で preview サーバーを共有し、DOM 解析も1回のパスで完了させる
- **`index_mappings` が空の場合**: 索引機能が無効、または索引語が存在しない場合はスキップ
- **`frontmatter` クラスの保持**: 前付け（`00-preface` 等）へのリンクには `class="frontmatter"` を保持し、CSS でローマ数字表示を維持する
- **エラー時のフォールバック**: Playwright の実行に失敗した場合は、従来の章単位重複排除にフォールバックし、ビルド全体を止めない
- **Ruby 4.x**: `Data.define`、`it` パラメータ、エンドレスメソッドを積極活用
- **Nokogiri**: DOM 操作は Nokogiri で行い、正規表現による HTML 操作は避ける

---

## 10. テスト計画

### 10.1 ユニットテスト

1. **`BacklinkDeduplicator` の索引重複排除テスト**
   - 同一ページの索引リンクが正しく排除されること
   - 異なるページの索引リンクが保持されること
   - `frontmatter` クラスが保持されること
   - 索引マッピングが空の場合にスキップされること

2. **`IndexPageBuilder` の全リンク出力テスト**
   - 章単位の重複排除が行われないこと
   - 全出現箇所のリンクが生成されること

### 10.2 統合テスト

1. `vs build` 実行後の `_indexpage.html` に重複ページ番号がないこと
2. 用語集と索引の重複排除が同一パスで正しく動作すること
3. Playwright 失敗時に従来方式にフォールバックすること

---

## 11. マイグレーション

### 11.1 Phase A（索引重複排除）

1. `extract_page_mapping.mjs` に `.index-term` 収集を追加
2. `PageMappingExtractor` で `index_mappings` を処理
3. `BacklinkDeduplicator` に `deduplicate_index_page_links!` を追加
4. `IndexPageBuilder` から `deduplicate_same_page!` 呼び出しを削除し、全リンクを出力
5. テスト追加・既存テスト更新
6. `vs build` で動作確認

### 11.2 Phase B（索引・用語集統合 — 実装済み）

1. ✅ `UnifiedTermsManager` 作成 — `flags` フィールドで索引/用語集を統合管理
2. ✅ `migrate_from_index_terms!` — `index_terms.yml` → `index_glossary_terms.yml` 自動移行
3. ✅ `IndexMatchScanner` — `index_glossary_terms.yml` から `flags` ベースで用語ロード
4. ✅ `UnifiedPageBuilder` — `_indexpage.html` + `_glossarypage.html` 統合生成
5. ✅ `UnifiedIndexManager` — `UnifiedTermsManager` + `UnifiedPageBuilder` に接続
6. ✅ `index.rb` — require と呼び出しを統合モジュールに更新
7. ✅ テスト更新 — 全14ファイル 171テスト 430アサーション合格
8. ✅ 警告メッセージ・コメントを `index_glossary_terms.yml` 参照に更新
