# 中扉（Part Title Page）仕様

## 1. 概要

書籍を複数の「部」（Part）に分ける場合、各部の先頭に **中扉**（part title page）を挿入する。
中扉は見開きの右ページ（奇数ページ）に部タイトルのみを印刷し、裏面（偶数ページ・左ページ）は白紙とする。

中扉の情報源は `config/catalog.yml` の部タイトル（Hash キー）であり、著者が明示的にファイルを作成する必要はない。

---

## 2. catalog.yml との関係

```yaml
CHAPTERS:
  - 歴史篇:
      - 01-life
      - 08-web
  - 実践篇:
      - 21-html
      - 31-netlify
```

上記の場合、`歴史篇` と `実践篇` が部タイトルとして認識され、それぞれに対応する中扉が生成される。

- **部タイトルの検出**: `CHAPTERS`（および `APPENDICES` 等）の配列要素が Hash の場合、そのキーを部タイトルとして扱う。
- **部番号の割り当て**: 出現順に 1, 2, 3, … と自動付番する。
- **部タイトルが存在しない場合**: 中扉は生成しない（フラットな章リストのみの場合）。

---

## 3. 内部ファイル

中扉は既存の特殊ページ（`_titlepage`, `_colophon` 等）と同様に、アンダースコア始まりの内部ファイルとして扱う。

### 3.1 ファイル名規則

| 部番号 | Markdown | HTML | 備考 |
|:---:|:---|:---|:---|
| 1 | `_part1.md` | `_part1.html` | 歴史篇 |
| 2 | `_part2.md` | `_part2.html` | 実践篇 |
| N | `_part{N}.md` | `_part{N}.html` | N 番目の部 |

### 3.2 生成場所

- Markdown: `.cache/vs/_part{N}.md`（システムページと同じキャッシュディレクトリ）
- HTML: プロジェクトルート直下 `_part{N}.html`（ビルド中間ファイル）

### 3.3 Markdown テンプレート

```markdown
---
class: part-title
title: 歴史篇
---

# 歴史篇
```

- frontmatter の `class: part-title` で CSS を適用する。
- frontmatter の `title` は PDF アウトラインに使用する。
- 本文は `# 部タイトル` のみ。

---

## 4. CSS（`stylesheets/part-title.css`）

中扉専用のスタイルシートを新規作成する。初期実装はシンプルに保つ。

```css
/* 中扉（Part Title Page） */
.part-title {
  break-before: recto;       /* 常に右ページ（奇数ページ）から開始 */
  break-after: left;         /* 裏面を白紙にする（次の章は右ページから） */
  page: part-title;
}

@page part-title {
  @top-left { content: none; }
  @top-right { content: none; }
  @bottom-center { content: none; }
  margin: 0;
  padding: 0;
}

.part-title h1 {
  margin-block-start: 30%;   /* 上部 30% の位置 */
  text-align: center;
  font-size: 1.8rem;
  font-weight: bold;
  letter-spacing: 0.1em;
}
```

### 4.1 設計方針

- ノンブル（ページ番号）は非表示。
- 柱（ランニングヘッダー）も非表示。
- 将来的に装飾（罫線、画像、サブタイトル等）を追加できるよう、クラス名で分離しておく。

---

## 5. ビルドパイプラインへの統合

### 5.1 中扉の生成タイミング

中扉の Markdown/HTML 生成は **Step 5（convert sections html）の直後** に行う。
具体的には、Step 5 と Step 6 の間に中扉生成のサブステップを挿入する。

```
Step 5:  convert sections html
Step 5b: generate part title pages（中扉 Markdown → HTML 変換）
Step 6:  generate toc and pdf
```

もしくは Step 5 の末尾で中扉生成を実行する（新しいステップ番号を増やさない方針の場合）。

### 5.2 entries.js への組み込み

Step 7 で `entries.js` を生成する際、各部の先頭章の直前に中扉の HTML を挿入する。

```
書籍構成順序:
  00-preface.html
  _toc.html
  _part1.html          ← 中扉（歴史篇）
  01-life.html
  08-web.html
  _part2.html          ← 中扉（実践篇）
  21-html.html
  31-netlify.html
  _glossarypage.html
  _indexpage.html
  99-postface.html
```

### 5.3 PDF 結合への影響

中扉は `_sections.pdf` の一部として本文 PDF に含まれるため、Step 10（PDF 結合）への変更は不要。

### 5.4 PDF アウトライン

中扉の `<h1>` は PDF アウトライン（しおり）に含める。
`OutlineExtractor` は `_part{N}.html` の見出しも抽出対象とする。

### 5.5 print_pdf（入稿用 PDF）

中扉は本文 PDF の一部であるため、print_pdf でも自動的に含まれる。追加の対応は不要。

---

## 6. CatalogLoader の拡張

### 6.1 部タイトル情報の取得

`CatalogLoader` に部タイトルと配下の章番号を返すメソッドを追加する。

```ruby
# catalog.yml から部タイトル情報を抽出
# @return [Array<Hash>] 部情報の配列
#   各要素: { number: 1, title: "歴史篇", first_chapter: "01", chapters: ["01-life", "08-web"] }
def load_part_titles
  catalog = load_catalog
  items = catalog['CHAPTERS']
  return [] unless items.is_a?(Array)

  parts = []
  part_number = 0

  items.each do |item|
    next unless item.is_a?(Hash)

    item.each do |title, sub_items|
      part_number += 1
      chapter_basenames = flatten_section(sub_items)
      first_chapter_num = chapter_basenames.first&.then { extract_chapter_number(it) }

      parts << {
        number: part_number,
        title: title.to_s,
        first_chapter: first_chapter_num,
        chapters: chapter_basenames
      }
    end
  end

  parts
end
```

### 6.2 SPECIAL_PAGES への追加

`CatalogLoader::SPECIAL_PAGES` に `_part` プレフィックスのファイルを追加する。
ただし、部の数は動的に変わるため、パターンマッチで判定する。

```ruby
# 特殊ページ判定の拡張
def special_page?(basename)
  SPECIAL_PAGES.include?(basename) || basename.match?(/\A_part\d+\z/)
end
```

---

## 7. TokenResolver の対応

### 7.1 Entry の kind 拡張

`TokenResolver::Entry` の `kind` に `:part_title` を追加する必要はない。
中扉は `catalog.yml` のメタ情報から自動生成されるシステムページであり、TokenResolver の解決対象外とする。

### 7.2 影響範囲

- `vs build`: 中扉は catalog.yml の部タイトルから自動生成されるため、TokenResolver への変更は不要。
- `vs build 21-25`: 単章ビルドでは中扉を生成しない（フルビルドのみ）。

---

## 8. `vs create` コマンドの改良

### 8.1 部タイトルへの自動挿入

`vs create 10-internet` が実行された場合、`CatalogUpdater` は以下のロジックで適切な部に挿入する。

#### 判定ロジック

1. `catalog.yml` の `CHAPTERS` に部タイトル（Hash）が存在するか確認する。
2. 部タイトルが存在する場合、各部の章番号範囲を調べる。
3. 新しい章番号が、どの部の章番号範囲に属するかを判定する。

```ruby
# 部タイトルへの挿入判定
# @param chapter_num [Integer] 新しい章の章番号
# @param parts [Array<Hash>] load_part_titles の返り値
# @return [String, nil] 挿入先の部タイトル（nil なら CHAPTERS 直下）
def find_part_for_chapter(chapter_num, parts)
  parts.each_with_index do |part, idx|
    part_min = part[:chapters].filter_map { CatalogLoader.extract_chapter_number(it) }.min
    part_max = part[:chapters].filter_map { CatalogLoader.extract_chapter_number(it) }.max
    next_part_min = parts[idx + 1]&.dig(:chapters)
                      &.filter_map { CatalogLoader.extract_chapter_number(it) }&.min

    # 章番号がこの部の範囲内、または次の部の開始より前なら、この部に属する
    if chapter_num >= (part_min || 0) && (next_part_min.nil? || chapter_num < next_part_min)
      return part[:title]
    end
  end

  nil # どの部にも属さない場合
end
```

#### 具体例

```yaml
CHAPTERS:
  - 歴史篇:          # 章番号 01-08
      - 01-life
      - 08-web
  - 実践篇:          # 章番号 21-41
      - 21-html
      - 31-netlify
```

| コマンド | 章番号 | 判定 | 挿入先 |
|:---|:---:|:---|:---|
| `vs create 10-internet` | 10 | 10 < 21（実践篇の最小） | **歴史篇** の末尾 |
| `vs create 05-binary` | 5 | 5 は歴史篇の範囲内 | **歴史篇** の章番号順位置 |
| `vs create 25-css` | 25 | 25 >= 21（実践篇の最小） | **実践篇** の章番号順位置 |
| `vs create 50-advanced` | 50 | 50 >= 21 かつ次の部なし | **実践篇** の末尾 |

### 8.2 CatalogUpdater の変更

現在の `insert_basename_to_section` は、部タイトル（Hash）が存在する場合にフラット化してしまう問題がある。
これを修正し、部タイトル構造を保持したまま適切な部に挿入するようにする。

```ruby
def insert_basename_to_section(catalog, section, basename)
  items = catalog[section] ||= []
  num = CatalogLoader.extract_chapter_number(basename) || 0

  # 部タイトル（Hash）が存在する場合
  if items.any? { it.is_a?(Hash) }
    parts = CatalogLoader.load_part_titles
    target_part_title = find_part_for_chapter(num, parts)

    if target_part_title
      # 該当する部の配下に挿入
      part_hash = items.find { it.is_a?(Hash) && it.key?(target_part_title) }
      if part_hash
        sub_items = part_hash[target_part_title] ||= []
        insert_sorted!(sub_items, basename, num)
        return
      end
    end
  end

  # 部タイトルがない場合、またはどの部にも属さない場合
  insert_sorted!(items, basename, num)
end

def insert_sorted!(items, basename, num)
  insert_index = items.find_index do |item|
    item_num = CatalogLoader.extract_chapter_number(item.to_s) || 0
    item_num > num
  end

  insert_index ? items.insert(insert_index, basename) : items << basename
end
```

---

## 9. クリーンアップ

### 9.1 clean コマンド

`CleanCommands` のクリーンアップ対象に以下を追加する。

- `.cache/vs/_part*.md`（中扉 Markdown）
- `_part*.html`（中扉 HTML）

### 9.2 .gitignore

中扉の中間ファイルは `.gitignore` に追加する（既存の `_*.html` パターンでカバーされている場合は不要）。

---

## 10. 実装手順

1. **`CatalogLoader` に `load_part_titles` メソッドを追加**
   - catalog.yml から部タイトル情報を抽出する。

2. **中扉 Markdown/HTML 生成モジュールを作成**
   - `Build::PartTitleGenerator` として新規モジュールを作成。
   - `.cache/vs/_part{N}.md` を生成し、VFM 変換で `_part{N}.html` を出力。

3. **`stylesheets/part-title.css` を作成**
   - 中扉用の CSS を定義。

4. **`PdfBuilder.build_overall_pdf_from_dir!` を修正**
   - `entries.js` 生成時に、各部の先頭章の直前に `_part{N}.html` を挿入。

5. **`CatalogUpdater.insert_basename_to_section` を修正**
   - 部タイトル構造を保持したまま、適切な部に章を挿入。

6. **`CleanCommands` に中扉ファイルのクリーンアップを追加**

7. **テスト**
   - `CatalogLoader.load_part_titles` の単体テスト。
   - `vs create` で部タイトルへの自動挿入が正しく動作するか確認。
   - フルビルドで中扉が正しい位置に挿入されるか確認。

---

## 11. 将来拡張

- **中扉のカスタマイズ**: `book.yml` に `parts` セクションを追加し、部ごとにサブタイトルや画像を指定可能にする。
- **部単位のビルド**: `vs build --part 1` で特定の部のみビルドする機能。
- **目次への部見出し挿入**: 目次に「第 I 部 歴史篇」のようなエントリを追加する。
- **PDF アウトラインの階層化**: 部タイトルを親ノードとし、配下の章を子ノードとする。
