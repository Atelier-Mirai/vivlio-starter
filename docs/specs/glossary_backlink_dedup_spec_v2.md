# 用語集バックリンク重複排除仕様書（第2版）

## 1. アプローチの変更

**新方針**: HTML生成時の「章レベル重複排除」+ Vivliostyleレンダリング後の「ページレベル微調整」を組み合わせたハイブリッド方式

### 1.1 背景

- `data-vivliostyle-page`属性や`vivliostyle_post_render`イベントは公式ドキュメントで未確認
- JavaScriptのみの解決策は、本文中の†記号の重複やCSS生成カンマの削除に限界がある
- 実装上安全な「章レベル重複排除」を基本とし、ページレベル検出はフォールバックとして用意

---

## 2. 実装アーキテクチャ

### Phase 1: HTML生成時（Ruby側）- 必須実装

```ruby
# IndexMatchScanner#build_glossary_link
@glossary_seen_in_chapter = Hash.new { |h, k| h[k] = Set.new }

def build_glossary_link(term_text, file_basename, occurrence_num)
  return nil unless @glossary_terms.key?(term_text)
  
  slug = generate_glossary_slug(term_text)
  is_first_in_chapter = !@glossary_seen_in_chapter[file_basename].include?(term_text)
  
  if is_first_in_chapter
    @glossary_seen_in_chapter[file_basename] << term_text
    gls_src_id = "gls-src-#{file_basename}-#{slug}"
    @glossary_backlinks[term_text] << {
      'chapter' => file_basename,
      'anchor_id' => gls_src_id,
      'data-glossary-dedup' => true  # 重複排除対象マーカー
    }
  end
  
  # 初出のみ†を表示、2回目以降は非表示リンク
  display_indicator = is_first_in_chapter ? '†' : ''
  anchor_id = is_first_in_chapter ? 
    "gls-src-#{file_basename}-#{slug}" : 
    "gls-ref-#{file_basename}-#{slug}-#{occurrence_num}"
  
  dedup_attr = is_first_in_chapter ? 'data-glossary-dedup="true"' : ''
  
  %(<a #{dedup_attr} id="#{anchor_id}" class="glossary-link" href="_glossarypage.html#gls-#{slug}"><sup>#{display_indicator}</sup></a>)
end
```

### Phase 2: レンダリング後（JavaScript側）- オプション実装

```javascript
// pub-jsとして追加（存在する場合のみ実行）
(function() {
  // Vivliostyleのレンダリング完了を監視
  function deduplicateGlossaryBacklinks() {
    const seen = new Map(); // term -> Set(pageNumbers)
    
    // data-glossary-dedup属性を持つバックリンクを対象に
    document.querySelectorAll('a[data-glossary-dedup].glossary-backlink').forEach(link => {
      const term = link.getAttribute('href');
      const pageAttr = link.getAttribute('data-vivliostyle-page');
      
      // 属性がない場合はスキップ（Phase 1の段階で既に重複排除済みとみなす）
      if (!pageAttr) return;
      
      const pageNum = parseInt(pageAttr, 10);
      if (!seen.has(term)) seen.set(term, new Set());
      
      if (seen.get(term).has(pageNum)) {
        // 同一ページの重複を非表示
        link.style.display = 'none';
        // CSS生成のカンマは削除不可（制限事項）
      } else {
        seen.get(term).add(pageNum);
      }
    });
  }
  
  // 複数のトリガーで実行を試行
  if (typeof vivliostyle !== 'undefined' && vivliostyle.postRender) {
    // 仮想的なVivliostyle API
    vivliostyle.postRender(deduplicateGlossaryBacklinks);
  } else {
    // フォールバック: DOMContentLoaded + 遅延実行
    window.addEventListener('DOMContentLoaded', () => {
      setTimeout(deduplicateGlossaryBacklinks, 1000);
    });
  }
})();
```

---

## 3. データ構造

### glossary_terms.yml（変更後）

```yaml
terms:
  - term: ウェブサイト
    backlink_sources:
      - chapter: 08-web
        anchor_id: gls-src-08-web-ウェブサイト
        data_glossary_dedup: true  # 重複排除対象フラグ
```

---

## 4. CSS調整

```css
/* 重複排除対象のバックリンク */
.glossary-backlink[data-glossary-dedup] {
  /* JavaScriptでの動的処理対象 */
}

/* 2回目以降の用語リンク（†なし） */
.glossary-link:not(:has(sup)) {
  display: none; /* または visibility: hidden */
}
```

---

## 5. 実装ステップ

1. **Phase 1実装（必須）**
   - `@glossary_seen_in_chapter`導入
   - `data-glossary-dedup`属性付与
   - 2回目以降の†非表示

2. **Phase 2実装（オプション）**
   - pub-jsの追加
   - `data-vivliostyle-page`検出ロジック

3. **検証**
   - 同一章複数出現のテスト
   - PDF出力でのページ番号確認

---

## 6. 制限事項

- **カンマ区切り**: CSS `content`で生成されるため、JavaScriptでの削除は不可能
- **data属性依存**: `data-vivliostyle-page`が存在しない場合、Phase 1の章レベル重複排除にフォールバック
- **本文の†**: Phase 1で制御（2回目以降は非表示リンクとして生成）
