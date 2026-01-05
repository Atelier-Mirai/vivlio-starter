# vivlio-starter 索引機能 実装仕様書

## 1. 概要

本仕様書は、vivlio-starter に索引生成機能を追加するための実装方針とアルゴリズムを定義する。

### 1.1 設計原則

- **段階的実装**: MVP（手動辞書）→ 自動抽出 → 高度化の順で段階的に機能追加
- **既存パイプラインとの統合**: pre_process / post_process の枠組みを活用
- **著者フレンドリー**: YAML ベースの設定で、エンジニアに親しみやすい UX
- **Vivliostyle 連携**: CSS `target-counter` でページ番号を自動挿入

### 1.2 技術スタック

- **Ruby 4.0.0+**（Set の組み込み化と機能強化を活用）
- Nokogiri（HTML パース）
- YAML（設定ファイル）
- CSS Paged Media（ページ番号表示）

---

## 2. アーキテクチャ

### 2.1 全体フロー

```
[Phase 1: 解析・タグ付け]
  contents/*.md
    ↓ pre_process (新機能: IndexMatchScanner)
  *.md (ID付きマークアップ)
    ↓ Vivliostyle
  *.html (ID付きHTML)

[Phase 2: 索引生成]
  *.html
    ↓ post_process (新機能: IndexPageBuilder)
  _indexpage.html (索引ページ)
    ↓ Vivliostyle (再ビルド)
  output.pdf (索引付き)
```

### 2.2 モジュール構成

```
lib/vivlio/starter/cli/
├── index.rb                           # 索引機能オーケストレーター
└── index/
    ├── index_term_scanner.rb          # 索引語スキャン・ID付与
    ├── index_page_builder.rb          # 索引ページHTML生成
    ├── yomi_inferrer.rb               # MeCab による読み推測
    ├── term_extractor.rb              # 自動抽出（Phase 2）
    ├── scoring_engine.rb              # スコアリング（Phase 2）
    └── hierarchical_index.rb          # 階層化索引・重複排除（Phase 3）
```

---

## 3. Phase 1: MVP実装（手動辞書ベース）

### 3.1 手動記法: `[用語|読み]`

著者が Markdown 内で索引語を明示的に指定する記法。

#### 3.1.1 記法仕様

**完全形（読み付き）**:
```markdown
[レスポンシブデザイン|れすぽんしぶでざいん]とは、画面サイズに応じて...

[引数|ひきすう]を渡すことで、関数に値を...
```

**簡略形（読み省略）**:
```markdown
[基本情報技術者]試験は、IT業界で...

[レスポンシブデザイン]の基本原則です。
```

**読み省略時の動作**:
- MeCab で読みを自動推測
- `vs index:match` で `index-candidates.yml` に出力
- 著者が読み間違いを確認・修正

#### 3.1.2 設計思想

- `{漢字|ふりがな}` に倣った記法で、著者にとって違和感なく使える
- 脚注 `[^1]` と同様に `[]` で囲む形式で、Markdown に親和的
- **読みは省略可能**: 日本人なら読める語句（「基本情報技術者」など）は `[用語]` で OK
- **読み間違いしやすい語句**: 「引数（ひきすう）」などは `[引数|ひきすう]` と明示
- **MeCab で読み自動推測**: 省略された読みは MeCab で推測し、`vs index:match` で確認可能

#### 3.1.3 HTML 変換ルール

**初出箇所（1回目）**:
```html
<dfn id="idx-responsive-design-1" class="index-term" data-yomi="れすぽんしぶでざいん">レスポンシブデザイン</dfn>
```

**2回目以降**:
```html
<span id="idx-responsive-design-2" class="index-term" data-yomi="れすぽんしぶでざいん">レスポンシブデザイン</span>
```

**理由**: HTML 仕様上、`<dfn>` は「その用語がその文書内で初めて登場し、定義される場所」に使うのが適切。Ruby 側で同一用語の出現順を追跡し、自動で切り替える。

### 3.2 設定ファイル: `config/index_terms.yml`（辞書ベース）

```yaml
# 索引語辞書（prh 方式）
terms:
  - term: レスポンシブデザイン
    yomi: れすぽんしぶでざいん
    pattern: /レスポンシブ[・\s]?デザイン/
    enabled: true

  - term: HTML
    yomi: えいちてぃーえむえる
    pattern: /HTML/
    # 解説箇所のみ抽出（定義表現パターンマッチング）
    auto_index_pattern: /HTML(?=とは|について|の)/
    enabled: true

  - term: CSS
    yomi: しーえすえす
    pattern: /CSS/
    auto_index_pattern: /CSS(?=とは|について|の)/
    enabled: true

# 索引生成設定
config:
  chapter_number: 99                    # 索引の章番号
  title: 索引                           # 索引ページタイトル
  auto_extract: false                   # Phase 2で実装
  score_threshold: 150                  # Phase 2で実装
  use_mecab: false                      # Phase 3で実装（形態素解析）
```

### 3.2 IndexMatchScanner（pre_process）

#### 3.3.1 責務

1. `config/index_terms.yml` を読み込み
2. 各 Markdown ファイルをスキャン
3. **`[用語|読み]` 記法を検出**し、初出は `<dfn>`、2回目以降は `<span>` に変換
4. 辞書パターンマッチした箇所に ID 付きタグを挿入
5. マッチ情報を `_index_matches.yml` に保存

#### 3.3.2 処理フロー

```ruby
# Ruby 4.0.0 を活用した実装
class IndexMatchScanner
  def initialize
    # Ruby 4.0.0: Set が組み込みになり require "set" 不要
    @seen_terms = Set[]  # Set リテラル構文
    @term_occurrence = Hash.new(0)
    @index_data = Hash.new { |h, k| h[k] = Set[] }
  end
  
  def scan_and_tag!(markdown_path, context)
    terms = load_terms('config/index_terms.yml')
    content = context.content
    matches = []
    file_basename = File.basename(markdown_path, '.md')
    
    # Step 1: [用語|読み] または [用語] 記法を処理
    content.gsub!(/\[([^|\]\n]+)(?:\|([^\]\n]+))?\](?!\()/) do |match|
      term_text = $1
      yomi = $2 || infer_yomi_with_mecab(term_text)  # 読みがなければ MeCab で推測
      
      # ID の生成（ハッシュベースで一意性を保証）
      @term_occurrence[term_text] += 1
      anchor_id = "idx-#{term_text.hash.abs.to_s(36)}-#{@term_occurrence[term_text]}"
      
      # Set で初出判定（O(1) の高速検索）
      is_first = !@seen_terms.include?(term_text)
      @seen_terms << term_text if is_first
      
      tag_name = is_first ? 'dfn' : 'span'
      
      # 索引データの蓄積（Set で重複を自動排除）
      @index_data[term_text] << {
        yomi: yomi,
        link: "#{file_basename}.html##{anchor_id}",
        file: file_basename,
        is_definition: is_first
      }
      
      matches << {
        id: anchor_id,
        term: term_text,
        yomi: yomi,
        file: file_basename,
        matched_text: term_text,
        is_definition: is_first
      }
      
      "<#{tag_name} id=\"#{anchor_id}\" class=\"index-term\" data-yomi=\"#{yomi}\">#{term_text}</#{tag_name}>"
    end
    
    # Step 2: 辞書パターンマッチ（auto_index_pattern がある場合のみ）
    terms.each do |term|
      next unless term[:enabled] && term[:auto_index_pattern]
      
      pattern = Regexp.new(term[:auto_index_pattern])
      content.gsub!(pattern) do |matched|
        @term_occurrence[term[:term]] += 1
        is_first = (@term_occurrence[term[:term]] == 1)
        
        anchor_id = "idx-#{term[:term].parameterize}-#{@term_occurrence[term[:term]]}"
        tag_name = is_first ? 'dfn' : 'span'
        
        matches << {
          id: anchor_id,
          term: term[:term],
          yomi: term[:yomi],
          file: File.basename(markdown_path, '.md'),
          matched_text: matched,
          is_definition: is_first
        }
        
        "<#{tag_name} id=\"#{anchor_id}\" class=\"index-term\" data-yomi=\"#{term[:yomi]}\">#{matched}</#{tag_name}>"
      end
    end
    
    context.content = content
    save_matches(matches, '_index_matches.yml')
  end
  
  private
  
  # MeCab で読みを推測
  def infer_yomi_with_mecab(term)
    return term unless mecab_available?
    
    mecab = Natto::MeCab.new
    yomi_parts = []
    
    mecab.parse(term) do |node|
      # 読み情報を取得（feature の 8 番目）
      features = node.feature.split(',')
      reading = features[7]  # カタカナ読み
      
      if reading && reading != '*'
        # カタカナをひらがなに変換
        yomi_parts << katakana_to_hiragana(reading)
      else
        yomi_parts << node.surface
      end
    end
    
    yomi_parts.join('')
  end
  
  def katakana_to_hiragana(str)
    str.tr('ァ-ヶ', 'ぁ-ゖ')
  end
  
  def mecab_available?
    @mecab_available ||= begin
      require 'natto'
      true
    rescue LoadError
      false
    end
  end
end
```

#### 3.3.3 注意点

- **コードブロック内を除外**: `` ``` `` で囲まれた範囲はスキップ
- **既存マークアップとの競合回避**: `<dfn>` / `<span>` 内部は再マッチしない
- **Markdown 構文の保護**: リンク `[text](url)` と `[用語|読み]` を区別（`|` の有無で判定）
- **出現順の追跡**: ファイルをまたいで同一用語の出現回数を追跡（グローバルカウンタ）

### 3.3 IndexPageBuilder（post_process）

#### 3.3.1 責務

1. `_index_matches.yml` を読み込み（または IndexMatchScanner の @index_data を直接利用）
2. 用語ごとにマッチ箇所を集約（Ruby 4.0.0 の Set で自動的に重複排除）
3. 読み順でソート
4. 五十音の「行」ごとにグループ化
5. `99-index.html` を生成

#### 3.3.2 索引ページ生成ロジック（Ruby 4.0.0 流）

```ruby
class IndexPageBuilder
  def initialize(index_data)
    @index_data = index_data  # Hash { term => Set[occurrences] }
  end
  
  def generate_index_page
    # 用語を「読み」の昇順でソート
    sorted_terms = @index_data.sort_by { |term, occurrences| occurrences.first[:yomi] }
    
    # 「あ行」「か行」などのグループ化
    groups = sorted_terms.group_by do |term, occurrences|
      determine_kana_row(occurrences.first[:yomi])
    end
    
    # HTML の組み立て
    build_html(groups)
  end
  
  private
  
  def determine_kana_row(yomi)
    # 読みの先頭一文字から行を判定
    case yomi[0]
    when /[あ-お]/ then "あ"
    when /[か-ご]/ then "か"
    when /[さ-ぞ]/ then "さ"
    when /[た-ど]/ then "た"
    when /[な-の]/ then "な"
    when /[は-ぽ]/ then "は"
    when /[ま-も]/ then "ま"
    when /[や-よ]/ then "や"
    when /[ら-ろ]/ then "ら"
    when /[わ-ん]/ then "わ"
    when /[a-e]/i then "A"
    when /[f-j]/i then "F"
    when /[k-o]/i then "K"
    when /[p-t]/i then "P"
    when /[u-z]/i then "U"
    else "その他"
    end
  end
  
  def build_html(groups)
    # ERB テンプレートまたは Nokogiri で HTML を構築
  end
end
```

#### 3.3.3 HTML 出力形式

```html
<!DOCTYPE html>
<html lang="ja">
<head>
  <meta charset="UTF-8">
  <title>索引</title>
  <link rel="stylesheet" href="stylesheets/index.css">
</head>
<body>
  <section class="index">
    <h1>索引</h1>
    
    <div class="index-section" data-initial="あ">
      <h2>あ</h2>
      <dl class="index-list">
        <dt>アクセサー</dt>
        <dd>
          <a href="11-basics.html#idx-0-1"></a>,
          <a href="12-advanced.html#idx-0-5"></a>
        </dd>
      </dl>
    </div>
    
    <div class="index-section" data-initial="れ">
      <h2>れ</h2>
      <dl class="index-list">
        <dt>レスポンシブデザイン</dt>
        <dd>
          <a href="21-layout.html#idx-1-0"></a>
        </dd>
      </dl>
    </div>
  </section>
</body>
</html>
```

#### 3.3.3 CSS: `stylesheets/index.css`

```css
/* ページ番号を target-counter で自動挿入 */
.index-list a::after {
  content: target-counter(attr(href), page);
  margin-left: 0.5em;
}

/* 複数ページ番号をカンマ区切り */
.index-list a:not(:last-child)::after {
  content: target-counter(attr(href), page) ", ";
}

/* 五十音見出し */
.index-section h2 {
  font-size: 1.5em;
  margin-top: 2em;
  border-bottom: 2px solid var(--theme-color);
}

/* 索引項目 */
.index-list dt {
  font-weight: bold;
  margin-top: 0.5em;
}

.index-list dd {
  margin-left: 2em;
}
```

---

## 4. Phase 2: 自動抽出とスコアリング

### 4.1 IndexCandidateExtractor（自動候補抽出）

#### 4.1.1 抽出ロジック

```ruby
class IndexCandidateExtractor
  # レイヤー1: 構造的抽出
  def extract_from_structure(markdown)
    candidates = []
    
    # 見出しから抽出（MeCab で名詞のみ）
    markdown.scan(/^##?\s+(.+)$/) do |heading|
      candidates << extract_nouns_with_mecab(heading[0])
    end
    
    # 強調から抽出
    markdown.scan(/\*\*(.+?)\*\*/) do |bold|
      candidates << bold[0]
    end
    
    # コードスパンから抽出
    markdown.scan(/`([^`]+)`/) do |code|
      candidates << code[0] if looks_like_term?(code[0])
    end
    
    # [用語|読み] 記法から抽出（最優先）
    markdown.scan(/\[([^|\]]+)\|([^\]]+)\]/) do |term, yomi|
      candidates << { term: term, yomi: yomi, source: 'manual' }
    end
    
    candidates.flatten.uniq
  end
  
  # レイヤー3: 文脈抽出（定義表現パターンマッチング）
  def extract_from_context(markdown)
    candidates = []
    
    # 定義表現パターン
    definition_patterns = [
      /([ぁ-んァ-ヶー\w]+)(?:とは、)/,
      /([ぁ-んァ-ヶー\w]+)(?:を.{0,10}と定義します)/,
      /([ぁ-んァ-ヶー\w]+)(?:という概念は、)/,
      /([ぁ-んァ-ヶー\w]+)(?:について解説します)/
    ]
    
    definition_patterns.each do |pattern|
      markdown.scan(pattern) do |term|
        candidates << { term: term[0], source: 'definition_pattern' }
      end
    end
    
    candidates.uniq
  end
  
  # MeCab による名詞抽出と複合名詞化
  def extract_nouns_with_mecab(text)
    return [] unless @mecab_enabled
    
    mecab = Natto::MeCab.new
    nouns = []
    current_compound = []
    
    mecab.parse(text) do |node|
      if node.feature.start_with?('名詞')
        current_compound << node.surface
      else
        if current_compound.any?
          nouns << current_compound.join('')
          current_compound = []
        end
      end
    end
    
    nouns << current_compound.join('') if current_compound.any?
    nouns
  end
end
```

### 4.2 ScoringEngine（スコアリング）

#### 4.2.1 スコア計算

```ruby
class ScoringEngine
  SCORE_RULES = {
    manual_markup: 200,              # [用語|読み] 記法（最優先）
    in_heading: 100,
    in_dfn_tag: 100,
    in_dict_with_context: 80,        # 辞書 + 定義表現パターン
    has_definition_pattern: 70,      # 定義表現パターンのみ
    in_technical_dict: 50,           # 専門用語辞書に一致
    tf_idf_high: 40,                 # TF-IDF スコアが高い
    in_dict_plain: 20,
    co_occurrence_match: 15,         # 近傍語マッチ
    single_occurrence: 5
  }.freeze
  
  def calculate_score(term, context)
    score = 0
    
    # 手動マークアップは最優先
    score += SCORE_RULES[:manual_markup] if context[:manual_markup]
    
    score += SCORE_RULES[:in_heading] if context[:in_heading]
    score += SCORE_RULES[:in_dfn_tag] if context[:in_dfn_tag]
    score += SCORE_RULES[:has_definition_pattern] if context[:has_definition_pattern]
    score += SCORE_RULES[:in_technical_dict] if context[:in_technical_dict]
    score += SCORE_RULES[:co_occurrence_match] if context[:co_occurrence_match]
    
    if context[:in_dictionary]
      if context[:has_definition_pattern]
        score += SCORE_RULES[:in_dict_with_context]
      else
        score += SCORE_RULES[:in_dict_plain]
      end
    end
    
    # TF-IDF スコアを加算
    if context[:tf_idf_score]
      score += SCORE_RULES[:tf_idf_high] if context[:tf_idf_score] > 0.5
    end
    
    score += SCORE_RULES[:single_occurrence] if context[:occurrence_count] == 1
    
    score
  end
  
  def should_auto_register?(score, threshold = 150)
    score >= threshold
  end
end
```

### 4.3 TF-IDF 計算エンジン

#### 4.3.1 TF-IDF の実装

```ruby
class TfIdfCalculator
  def initialize(chapters)
    @chapters = chapters
    @term_frequencies = calculate_term_frequencies
    @document_frequencies = calculate_document_frequencies
  end
  
  # TF (Term Frequency): その章での出現頻度
  def tf(term, chapter)
    count = @term_frequencies[chapter][term] || 0
    total = @term_frequencies[chapter].values.sum
    count.to_f / total
  end
  
  # IDF (Inverse Document Frequency): 全章での希少性
  def idf(term)
    df = @document_frequencies[term] || 0
    return 0 if df.zero?
    
    Math.log(@chapters.size.to_f / df)
  end
  
  # TF-IDF スコア
  def tf_idf(term, chapter)
    tf(term, chapter) * idf(term)
  end
  
  private
  
  def calculate_term_frequencies
    # 各章ごとに用語の出現回数をカウント
  end
  
  def calculate_document_frequencies
    # 各用語が何章に出現するかをカウント
  end
end
```

### 4.4 近傍語（Co-occurrence）解析

#### 4.4.1 関連語辞書

```yaml
# config/co_occurrence_patterns.yml
patterns:
  HTML:
    related_terms: [構造, 要素, タグ, 言語, マークアップ]
    unrelated_terms: [書く, 開く, 保存]
    
  CSS:
    related_terms: [スタイル, デザイン, プロパティ, セレクタ]
    unrelated_terms: [書く, 開く, 保存]
```

#### 4.4.2 近傍語スコアリング

```ruby
class CoOccurrenceAnalyzer
  WINDOW_SIZE = 50  # 前後50文字を検査
  
  def analyze(term, context_text, patterns)
    related_count = 0
    unrelated_count = 0
    
    patterns[:related_terms].each do |related|
      related_count += 1 if context_text.include?(related)
    end
    
    patterns[:unrelated_terms].each do |unrelated|
      unrelated_count += 1 if context_text.include?(unrelated)
    end
    
    # 関連語が多く、非関連語が少ないほど高スコア
    related_count > unrelated_count
  end
end
```

### 4.5 専門用語辞書との照合

#### 4.5.1 辞書ファイル

```yaml
# config/technical_terms.yml
terms:
  - レスポンシブデザイン
  - HTML
  - CSS
  - JavaScript
  - DOM
  # Wikipedia のタイトル一覧や IT 用語辞典から抽出
```

#### 4.5.2 照合ロジック

```ruby
class TechnicalDictionary
  def initialize(dict_path)
    @terms = YAML.load_file(dict_path)['terms']
  end
  
  def include?(term)
    @terms.include?(term)
  end
end
```

### 4.6 候補YAML生成: `vs index:match`

#### 4.6.1 実行例

```bash
$ vs index:match
索引候補を抽出中...
  ✓ 11-basics.md から 15 件の候補を抽出
  ✓ 12-advanced.md から 23 件の候補を抽出
  
読みを MeCab で自動推測しました。
候補リストを config/index_candidates.yml に保存しました。

⚠️  読み間違いがないか確認してください：
  - 引数: ひきすう (推測: ひきすう) ✓
  - 基本情報技術者: きほんじょうほうぎじゅつしゃ (推測: きほんじょうほうぎじゅつしゃ) ✓
  - HTML: えちてぃーえむえる (推測: HTML) ⚠️  要修正

不要な項目を削除し、読みを確認・修正してから vs build を実行してください。
```

#### 4.6.2 MeCab による読み推測の流れ

1. **[用語] 形式を検出**
2. **MeCab で形態素解析**
   - 各形態素の読み情報（カタカナ）を取得
   - カタカナをひらがなに変換
3. **結合して読みを生成**
   - 例: 「基本情報技術者」→ 「きほんじょうほうぎじゅつしゃ」
4. **`index-candidates.yml` に出力**
5. **著者が確認・修正**
   - アルファベット語は手動修正（例: HTML → えいちてぃーえむえる）
   - 読み間違いがあれば修正

#### 4.3.1 出力形式: `config/index_candidates.yml`

```yaml
# 自動抽出された索引候補
# enabled: false にすると索引に含まれません
# yomi を修正して五十音順を調整できます

candidates:
  - term: レスポンシブデザイン
    yomi: れすぽんしぶでざいん
    score: 200
    reason: [用語|読み] 記法で明示的にマークアップ
    occurrences: 3
    files: [21-layout.md, 22-media.md]
    enabled: true

  - term: HTML
    yomi: えいちてぃーえむえる
    score: 150
    reason: 辞書登録語 + 定義表現パターン + 専門用語辞書
    occurrences: 12
    files: [11-basics.md, 12-advanced.md, 21-layout.md]
    tf_idf_score: 0.65
    source: dictionary
    mecab_inferred_yomi: HTML  # MeCab の推測結果（要修正）
    enabled: true
    note: "⚠️  MeCab の読み推測が不正確なため、手動で 'yomi' を設定済み"

  - term: DOM
    yomi: どむ
    score: 90
    reason: 見出し + 専門用語辞書 + 近傍語マッチ
    occurrences: 5
    files: [12-advanced.md]
    tf_idf_score: 0.82
    enabled: true

  - term: ブラウザ
    yomi: ぶらうざ
    score: 25
    reason: 辞書登録語（通常出現）
    occurrences: 8
    files: [11-basics.md, 13-tools.md]
    tf_idf_score: 0.12
    enabled: false  # 著者が false に変更

---

## 5. CLI コマンド仕様

### 5.1 `vs index:match`

索引候補を自動抽出し、YAML を生成する。

```bash
vs index:match [OPTIONS]

OPTIONS:
  --threshold SCORE    自動登録の閾値（デフォルト: 150）
  --output FILE        出力先（デフォルト: config/index_candidates.yml）
  --merge              既存の index_terms.yml とマージ
  --verbose, -v        詳細ログ表示
```

### 5.2 `vs index:build`

索引ページのみを再生成する（デバッグ用）。

```bash
vs index:build [OPTIONS]

OPTIONS:
  --preview            ブラウザでプレビュー
  --verbose, -v        詳細ログ表示
```

### 5.3 `vs build` への統合

既存の `vs build` に索引生成を組み込む。

```ruby
# lib/vivlio/starter/cli/build/unified_build_pipeline.rb

def execute_step_4a_index_scan
  return unless index_enabled?
  
  Common.log_step('Step 4a', '索引語スキャン')
  IndexMatchScanner.scan_all_chapters!(configured_chapters)
end

def execute_step_8a_index_page
  return unless index_enabled?
  
  Common.log_step('Step 8a', '索引ページ生成')
  IndexPageBuilder.build!('_index_matches.yml', '99-index.html')
end
```

---

## 6. データ構造

### 6.1 マッチ情報: `_index_matches.yml`

```yaml
matches:
  - id: idx-responsive-design-1
    term: レスポンシブデザイン
    yomi: れすぽんしぶでざいん
    file: 21-layout
    matched_text: レスポンシブデザイン
    line: 45
    context: "...レスポンシブデザインとは、画面サイズに応じて..."
    is_definition: true
    tag_type: dfn

  - id: idx-responsive-design-2
    term: レスポンシブデザイン
    yomi: れすぽんしぶでざいん
    file: 22-media
    matched_text: レスポンシブデザイン
    line: 12
    context: "...レスポンシブデザインの基本原則は..."
    is_definition: false
    tag_type: span
```

### 6.2 集約データ（内部）

```ruby
# Ruby 4.0.0: Set を活用したデータ構造
{
  "レスポンシブデザイン" => Set[
    { yomi: "れすぽんしぶでざいん", link: "21-layout.html#idx-...", file: "21-layout", is_definition: true },
    { yomi: "れすぽんしぶでざいん", link: "22-media.html#idx-...", file: "22-media", is_definition: false }
  ],
  "HTML" => Set[
    { yomi: "えいちてぃーえむえる", link: "11-basics.html#idx-...", file: "11-basics", is_definition: true },
    { yomi: "えいちてぃーえむえる", link: "11-basics.html#idx-...", file: "11-basics", is_definition: false },
    { yomi: "えいちてぃーえむえる", link: "12-advanced.html#idx-...", file: "12-advanced", is_definition: false }
  ]
}

# 五十音順にソートして行ごとにグループ化
sorted_terms = @index_data.sort_by { |term, occurrences| occurrences.first[:yomi] }
groups = sorted_terms.group_by do |term, occurrences|
  determine_kana_row(occurrences.first[:yomi])
end

# groups の構造例
{
  "あ" => [["アクセサー", Set[...]], ...],
  "れ" => [["レスポンシブデザイン", Set[...]], ...],
  "え" => [["HTML", Set[...]], ...]
}
```

---

## 7. 実装順序

### 7.1 Phase 1: MVP（2〜3週間）

1. **Week 1**: 基盤整備
   - `config/index_terms.yml` スキーマ定義
   - `IndexMatchScanner` 基本実装
   - _index_matches.yml から索引データを読み込み

2. **Week 2**: 索引ページ生成
   - `IndexPageBuilder` 実装
   - `stylesheets/index.css` 作成
   - 五十音ソート実装

3. **Week 3**: 統合・テスト
   - `vs build` パイプラインへの組み込み
   - サンプル書籍での動作確認
   - ドキュメント整備

### 7.2 Phase 2: 自動化（2〜3週間）

1. `IndexCandidateExtractor` 実装
2. `ScoringEngine` 実装
3. `vs index:match` コマンド追加
4. 候補YAML生成・マージ機能

### 7.3 Phase 3: 高度化（4〜6週間）

1. **Week 1-2**: MeCab 連携
   - natto gem 導入
   - 複合名詞抽出
   - 読み自動取得（mecab-ipadic-NEologd）

2. **Week 3**: TF-IDF エンジン
   - TfIdfCalculator 実装
   - スコアリングへの統合

3. **Week 4**: 近傍語解析
   - CoOccurrenceAnalyzer 実装
   - 関連語辞書整備

4. **Week 5**: 専門用語辞書
   - Wikipedia タイトル一覧の取り込み
   - IT 用語辞典との照合

5. **Week 6**: 高度機能
   - 階層化索引（親カテゴリ・子カテゴリ）
   - 同一ページ内重複排除（JavaScript）

---

## 8. Ruby 4.0.0 の Set 機能活用のメリット

### 8.1 パフォーマンス向上

- **O(1) の高速検索**: `@seen_terms.include?(term)` が定数時間で実行
- **重複自動排除**: Set に追加するだけで重複が自動的に排除される
- **メモリ効率**: 内部的に最適化されたハッシュテーブル実装

### 8.2 コードの簡潔性

**従来（Ruby 3.x）**:
```ruby
require 'set'

@seen_terms = Set.new
@index_data = Hash.new { |h, k| h[k] = Set.new }
```

**Ruby 4.0.0**:
```ruby
# require 不要
@seen_terms = Set[]
@index_data = Hash.new { |h, k| h[k] = Set[] }
```

### 8.3 依存関係の削減

- `require "set"` が不要になり、標準ライブラリへの依存が明示的に不要に
- Gemfile への記載も不要

### 8.4 実装例の比較

**初出判定の高速化**:
```ruby
# Ruby 3.x: Array での実装（O(n)）
if @seen_terms.include?(term)  # 配列の線形探索
  # ...
end

# Ruby 4.0.0: Set での実装（O(1)）
if @seen_terms.include?(term)  # ハッシュテーブルの定数時間探索
  # ...
end
```

**データ蓄積の簡潔化**:
```ruby
# Ruby 3.x: 重複チェックが必要
@index_data[term] ||= []
@index_data[term] << occurrence unless @index_data[term].include?(occurrence)

# Ruby 4.0.0: Set が自動で重複排除
@index_data[term] << occurrence  # Set が自動的に重複を排除
```

---

## 9. テスト戦略

### 8.1 ユニットテスト

```ruby
# test/vivlio/starter/cli/index/term_dictionary_test.rb
class TermDictionaryTest < Minitest::Test
  def test_load_terms
    dict = TermDictionary.new('test/fixtures/index_terms.yml')
    assert_equal 3, dict.terms.size
  end
  
  def test_pattern_matching
    dict = TermDictionary.new('test/fixtures/index_terms.yml')
    matches = dict.find_matches('HTMLとは何か')
    assert_equal 1, matches.size
    assert_equal 'HTML', matches[0][:term]
  end
end
```

### 8.2 統合テスト

```ruby
# test/vivlio/starter/cli/index_integration_test.rb
class IndexIntegrationTest < Minitest::Test
  def test_full_index_generation
    # 1. スキャン
    IndexMatchScanner.scan_all_chapters!(['11-basics'])
    
    # 2. マッチ確認
    matches = YAML.load_file('_index_matches.yml')
    assert matches['matches'].size > 0
    
    # 3. 索引ページ生成
    IndexPageBuilder.build!('_index_matches.yml', '99-index.html')
    
    # 4. HTML検証
    assert File.exist?('99-index.html')
    html = Nokogiri::HTML(File.read('99-index.html'))
    assert html.css('.index-list dt').size > 0
  end
end
```

---

## 10. 既知の制約と対応

### 9.1 ページ番号の取得

**制約**: Ruby ビルド時にはページ番号が未確定

**対応**: CSS `target-counter` で Vivliostyle レンダリング時に自動挿入

### 9.2 同一ページ内の重複

**制約**: 同じ語が1ページに複数回出現すると、ページ番号も重複表示される

**対応**: 
- Phase 1: そのまま表示（許容）
- Phase 3: JavaScript で後処理して重複排除

### 9.3 読みの自動取得

**制約**: 日本語の読みを自動判定するには形態素解析が必要

**対応**:
- **Phase 1**: `[用語|読み]` 記法で著者が明示的に指定
- **Phase 1**: `[用語]` 記法（読み省略）で MeCab が自動推測
  - 日本人なら読める語句（「基本情報技術者」など）は省略 OK
  - MeCab で推測し、`vs index:match` で確認・修正
- **Phase 2**: 辞書に手動で `yomi` を記載
- **Phase 3**: アルファベット語の読み自動判定（辞書ベース）

### 9.4 MeCab の依存関係

**制約**: MeCab は外部ライブラリで、インストールが必要

**対応**:
- **索引機能では MeCab を必須とする**（`[用語]` 形式の読み自動推測に必要）
- Gemfile に `natto` を直接追加（optional ではなく必須）
- MeCab がインストールされていない場合はエラーメッセージを表示

```ruby
# Gemfile
gem 'natto', '~> 1.2'  # MeCab バインディング（索引機能に必須）
```

**インストール手順**:
```bash
# macOS
brew install mecab mecab-ipadic

# Ubuntu/Debian
sudo apt-get install mecab libmecab-dev mecab-ipadic-utf8

# gem のインストール
bundle install
```

### 9.5 `[用語|読み]` と `[リンク](URL)` の区別

**制約**: Markdown のリンク記法と混同される可能性

**対応**:
- `|` の有無で判定（リンクは `](` が続く）
- 正規表現で明確に区別: `/\[([^|\]]+)\|([^\]]+)\]/`

---

## 11. 依存関係とバージョン要件

### 11.1 Gemfile

```ruby
# Gemfile
ruby '>= 4.0.0'  # Ruby 4.0.0 以上を必須とする

gem 'vivliostyle', '~> 2.0'
gem 'nokogiri', '~> 1.15'
gem 'samovar', '~> 2.3'  # CLI フレームワーク（thor から移行済み）

# 索引機能で必須（[用語] 形式の読み自動推測に使用）
gem 'natto', '~> 1.2'  # MeCab バインディング
```

### 11.2 .ruby-version

```
4.0.0
```

### 11.3 README への記載

```markdown
## 必要要件

- Ruby 4.0.0 以上
- Vivliostyle CLI
- （オプション）MeCab（索引語の自動抽出を使用する場合）

## インストール

\`\`\`bash
# Ruby 4.0.0 のインストール（rbenv の場合）
rbenv install 4.0.0
rbenv local 4.0.0

# 依存 gem のインストール
bundle install
\`\`\`
```

---

## 12. 参考資料

- [CSS Paged Media Module Level 3](https://www.w3.org/TR/css-page-3/)
- [Vivliostyle Documentation](https://vivliostyle.org/ja/documents/)
- [prh (proofreading helper)](https://github.com/prh/prh)
- [textlint](https://textlint.github.io/)
- [MeCab: Yet Another Part-of-Speech and Morphological Analyzer](https://taku910.github.io/mecab/)
- [natto gem](https://github.com/buruzaemon/natto)

---

## 13. 変更履歴

| 日付       | バージョン | 変更内容                     |
|------------|------------|------------------------------|
| 2025-12-28 | 1.0.0      | 初版作成                     |
| 2025-12-28 | 1.1.0      | Ruby 4.0.0 の Set 機能強化を反映 |
| 2025-12-28 | 1.2.0      | thor 削除、[用語] 形式サポート、MeCab 読み自動推測機能追加 |
