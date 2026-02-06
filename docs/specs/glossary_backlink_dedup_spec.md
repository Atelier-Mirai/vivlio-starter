# 用語集バックリンク重複排除仕様書

## 1. 概要と技術的制約

### 1.1 問題
- 同じ章内で用語が複数回出現 → バックリンクが `p.4, 4` と重複
- 本文中にも各出現に†が付与される

### 1.2 技術的制約（重要）
Vivliostyleの`target-counter`は**レンダリング時**にページ番号を解決するため：
- ❌ HTML生成時点では実際のページ番号が不明
- ❌ 「同一ページ」を100%正確に判断できない
- ✅ 「同一章（ファイル）」の判断は可能

### 1.3 妥協案：章レベルでの重複排除
同じ章での同じ用語の出現は、統計的に同じページにある可能性が高い。章レベルでの重複排除を行うことで、実用的な解決を図る。

---

## 2. 改修対象モジュール

### 2.1 IndexMatchScanner

`lib/vivlio/starter/cli/index/index_match_scanner.rb`の`build_glossary_link`を修正：

```ruby
# initialize: 章ごとの追跡用Setを初期化
@glossary_seen_in_chapter = Hash.new { |h, k| h[k] = Set.new }

def build_glossary_link(term_text, file_basename, occurrence_num)
  return nil unless @glossary_terms.key?(term_text)

  slug = generate_glossary_slug(term_text)
  is_first_in_chapter = !@glossary_seen_in_chapter[file_basename].include?(term_text)

  if is_first_in_chapter
    @glossary_seen_in_chapter[file_basename] << term_text
    # バックリンク記録（章のみ、occurrenceなし）
    gls_src_id = "gls-src-#{file_basename}-#{slug}"
    @glossary_backlinks[term_text] << {
      'chapter' => file_basename,
      'anchor_id' => gls_src_id
    }
  end

  # リンク生成（初出のみ†を表示）
  display_indicator = is_first_in_chapter ? GLOSSARY_INDICATOR : ''
  anchor_id = is_first_in_chapter ? 
    "gls-src-#{file_basename}-#{slug}" : 
    "gls-ref-#{file_basename}-#{slug}-#{occurrence_num}"

  %(<a id="#{anchor_id}" class="glossary-link" href="_glossarypage.html#gls-#{slug}"><sup>#{display_indicator}</sup></a>)
end
```

### 2.2 GlossaryPageBuilder

`lib/vivlio/starter/cli/index/glossary_page_builder.rb`の`build_backlinks`を修正：

```ruby
def build_backlinks(term)
  sources = term['backlink_sources']
  return '' unless sources&.any?

  # 章番号で昇順ソート（既に一意化済みの前提）
  sorted_sources = sources.sort_by do |source|
    chapter = source['chapter'] || source[:chapter]
    chapter_num = chapter.to_s[/\A(\d+)/, 1]&.to_i || 999
    chapter_num
  end

  links = sorted_sources.map do |source|
    chapter = source['chapter'] || source[:chapter]
    anchor_id = source['anchor_id'] || source[:anchor_id]
    classes = ['glossary-backlink']
    classes << 'frontmatter' if chapter.to_s.start_with?('00-')

    %(<a href="#{chapter}.html##{anchor_id}" class="#{classes.join(' ')}"></a>)
  end

  <<~HTML.chomp
    <p class="glossary-backlinks">#{links.join(' ')}</p>
  HTML
end
```

---

## 3. データ構造変更

### 3.1 glossary_terms.yml

**現状**（重複あり）:
```yaml
terms:
  - term: ウェブサイト
    backlink_sources:
      - chapter: 08-web
        occurrence: 1
        anchor_id: gls-src-08-web-ウェブサイト-1
      - chapter: 08-web
        occurrence: 2
        anchor_id: gls-src-08-web-ウェブサイト-2
```

**改修後**（章単位で一意）:
```yaml
terms:
  - term: ウェブサイト
    backlink_sources:
      - chapter: 08-web
        anchor_id: gls-src-08-web-ウェブサイト
      - chapter: 09-css
        anchor_id: gls-src-09-css-ウェブサイト
```

### 3.2 本文中のマークアップ

**現状**:
```html
<span>ウェブサイト</span><a id="gls-src-08-web-ウェブサイト-4" class="glossary-link" href="..."><sup>†</sup></a>
<span>ウェブサイト</span><a id="gls-src-08-web-ウェブサイト-5" class="glossary-link" href="..."><sup>†</sup></a>
```

**改修後**:
```html
<!-- 初出：バックリンク対象、†付き -->
<span>ウェブサイト</span><a id="gls-src-08-web-ウェブサイト" class="glossary-link" href="..."><sup>†</sup></a>

<!-- 2回目以降：バックリンク対象外、†なし -->
<span>ウェブサイト</span><a id="gls-ref-08-web-ウェブサイト-2" class="glossary-link" href="..."></a>
```

---

## 4. 実装ステップ

1. **IndexMatchScanner**: `@glossary_seen_in_chapter`導入、初出チェック追加
2. **GlossaryPageBuilder**: occurrenceなしのデータ構造に対応
3. **テスト**: 同一章での複数出現テストケース追加
4. **CSS**: `.glossary-link`の空コンテンツ対応（必要に応じて）

---

## 5. 検証項目

| 項目 | 期待結果 |
|------|----------|
| 同一章内2回出現 | バックリンク1つ、†も1つ |
| 異なる章各1回 | バックリンク2つ、各章に†1つ |
| 既存データ互換 | occurrence付きの旧データも正常表示 |

---

## 6. 制限事項

- **章単位の重複排除**: 章が複数ページにわたる場合、異なるページへのバックリンクが欠落する可能性がある
- **同一ページの近似性**: 実際のページ番号ではなく、章で判断するため、異なるページを同一とみなす場合がある

### 将来の改善案（Vivliostyle連携）

Vivliostyleの出力を解析し、実際のページ番号マップを取得する2パス処理：
1. 初回ビルド：glossary_terms.ymlに全出現を記録
2. Vivliostyle実行：interim PDF生成
3. ページマップ解析：各アンカーの実ページ番号を取得
4. 重複排除：同一ページのアンカーを統合
5. 最終ビルド：整理されたバックリンクで再生成

この2パスアプローチはビルド時間を増加させるため、現時点では推奨しない。
