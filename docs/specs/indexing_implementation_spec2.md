# 索引システム実装仕様書 v2.0

**最終更新**: 2026-01-05  
**ステータス**: 設計フェーズ

---

## 1. 概要

### 1.1 目的

著者が**執筆に集中し、最小限の確認作業だけで高品質な索引を自動生成**できるシステムを提供する。

### 1.2 設計方針

- **自動化優先**: 高スコア候補は自動承認
- **効率的なレビュー**: Markdownファイルで一括編集
- **シンプルなコマンド**: `vs index:auto` 1コマンドで完結
- **柔軟性**: 必要に応じて細かい調整が可能

---

## 2. システムアーキテクチャ

### 2.1 コンポーネント構成

```
UnifiedIndexManager (統合マネージャー)
├── IndexCandidateExtractor (候補抽出)
├── IndexMatchScanner (本文スキャン)
├── IndexPageBuilder (索引ページ生成)
├── IndexTermsManager (用語辞書管理)
└── ReviewMarkdownGenerator (レビューファイル生成)
```

### 2.2 ファイル構成

```
config/
  ├── index_terms.yml          # 確定済み用語辞書（自動更新）
  ├── index_review_queue.yml   # レビュー待ち候補
  └── index_rejected.yml       # リジェクト済み候補（再表示しない）

_index_review.md                # レビュー用Markdown（一時ファイル）
_index_matches.yml              # 内部キャッシュ
_indexpage.html                 # 生成された索引ページ
```

---

## 3. コアコンポーネント

### 3.1 UnifiedIndexManager

**責務**: 索引生成プロセス全体を統括

#### 3.1.1 主要メソッド

##### `auto_process!(chapters)`

全自動索引生成。スコア閾値は `book.yml` から読み取る。

```ruby
def auto_process!(chapters)
  # 設定読み込み
  config = load_index_config
  auto_threshold = config['auto_approve_threshold'] || 200
  review_threshold = config['review_threshold'] || 150
  
  # 1. 候補抽出
  candidates = extract_candidates(chapters)
  
  # 2. 既存の承認済み用語とリジェクト済み用語を除外
  existing_terms = @terms_manager.load_existing_terms.map { |t| t['term'] }
  rejected_terms = load_rejected_terms
  candidates = candidates.reject do |c|
    existing_terms.include?(c['term']) || rejected_terms.include?(c['term'])
  end
  
  # 3. 高スコア候補を自動承認
  auto_approved = candidates.select { |c| c['score'] >= auto_threshold }
  @terms_manager.merge_terms!(auto_approved)
  
  # 4. 中スコア候補をレビューキューへ
  review_queue = candidates.select do |c|
    c['score'] >= review_threshold && c['score'] < auto_threshold
  end
  save_review_queue(review_queue)
  
  # 5. 本文スキャン＆索引生成
  @scanner.scan_all_chapters!(chapters)
  @builder.build!
  
  # 6. 結果レポート
  report_results(auto_approved, review_queue, auto_threshold, review_threshold, rejected_terms.size)
end

private

def load_index_config
  config = Common::CONFIG || {}
  config['index'] || {}
end

def report_results(auto_approved, review_queue, auto_threshold, review_threshold, rejected_count)
  Common.log_success("候補抽出完了")
  Common.log_info("自動承認: #{auto_approved.size}件 (スコア≥#{auto_threshold})")
  Common.log_info("レビュー待ち: #{review_queue.size}件 (#{review_threshold}≤スコア<#{auto_threshold})")
  
  if rejected_count > 0
    Common.log_info("リジェクト設定により #{rejected_count} 件の候補を除外しました")
    Common.log_info("確認: vs index:rejected")
  end
  
  if review_queue.any?
    Common.log_info("レビュー: vs index:review")
  end
end
```

**処理フロー**:
```
設定読込 → 候補抽出 → 除外(承認済み・リジェクト済み) → 自動承認(≥auto_approve_threshold) → レビュー待ち(review_threshold以上) → スキャン → 索引生成 → レポート(リジェクト除外数を含む)
```

**注意事項**:
- リジェクト設定により除外された候補数をレポートで通知
- 著者がリジェクトを忘れている場合の気付きを促す

##### `markdown_review!`

Markdownベースのレビューファイル生成。

```ruby
def markdown_review!
  queue = load_review_queue
  
  if queue.empty?
    Common.log_info('レビュー待ちの候補がありません')
    return
  end
  
  # ガードレール: 編集中ファイルの上書き防止
  review_file = '_index_review.md'
  if File.exist?(review_file)
    Common.log_warn("編集中のレビューファイルが存在します: #{review_file}")
    Common.log_warn('先に vs index:apply を実行するか、ファイルを削除してください')
    Common.log_info('強制的に上書きする場合: vs index:review --force')
    return unless @options[:force]
  end
  
  generator = ReviewMarkdownGenerator.new
  generator.generate!(queue)
end
```

##### `apply_markdown_review!`

Markdownファイルから承認・リジェクトを適用。

```ruby
def apply_markdown_review!
  generator = ReviewMarkdownGenerator.new
  approved = generator.parse_approved    # [x] でマーク
  rejected = generator.parse_rejected    # [r] でマーク
  
  if approved.empty? && rejected.empty?
    Common.log_warn('承認またはリジェクトされた候補がありません')
    return
  end
  
  # 用語辞書へマージ
  @terms_manager.merge_terms!(approved) if approved.any?
  
  # リジェクト済みリストへ追加
  save_rejected_terms!(rejected) if rejected.any?
  
  # レビューキューから削除（承認＋リジェクト両方）
  clear_review_queue((approved + rejected).map { |a| a['term'] })
  
  # 再スキャン＆ビルド
  chapters = resolve_all_chapters
  @scanner.scan_all_chapters!(chapters)
  @builder.build!
  
  Common.log_success("承認: #{approved.size}件、リジェクト: #{rejected.size}件")
  Common.log_success('索引を更新しました')
  
  # 一時ファイル削除
  FileUtils.rm_f('_index_review.md')
end
```

##### `interactive_review!`

対話形式のレビュー（少数候補向け）。

```ruby
def interactive_review!
  queue = load_review_queue
  approved = []
  rejected = []
  
  queue.each do |candidate|
    puts "\n用語: #{candidate['term']}"
    puts "読み: #{candidate['yomi']}"
    puts "スコア: #{candidate['score']}"
    puts "文脈: #{candidate['contexts'].first[:context][0..80]}..."
    
    choice = prompt("採用? [y/n/e(編集)/r(リジェクト)/s(スキップ)]")
    
    case choice
    when 'y'
      approved << candidate
    when 'e'
      edited = edit_candidate(candidate)
      approved << edited
    when 'r'
      rejected << candidate
    when 's', 'n'
      next
    end
  end
  
  @terms_manager.merge_terms!(approved) if approved.any?
  save_rejected_terms!(rejected) if rejected.any?
  clear_review_queue((approved + rejected).map { |a| a['term'] })
  
  Common.log_success("承認: #{approved.size}件、リジェクト: #{rejected.size}件")
end
```

##### `list_rejected_terms`

リジェクト済み候補の一覧表示。

```ruby
def list_rejected_terms
  rejected = load_rejected_terms_with_metadata
  
  if rejected.empty?
    Common.log_info('リジェクト済み候補はありません')
    return
  end
  
  puts "\nリジェクト済み候補:"
  rejected.each_with_index do |term, idx|
    puts "#{idx + 1}. #{term['term']} (#{term['yomi']})"
  end
end
```

##### `unreject_term!(term_or_number)`

リジェクト済み候補を解除。

```ruby
def unreject_term!(term_or_number)
  rejected = load_rejected_terms_with_metadata
  
  # 番号または用語名で検索
  target = if term_or_number.match?(/^\d+$/)
    idx = term_or_number.to_i - 1
    rejected[idx]
  else
    rejected.find { |t| t['term'] == term_or_number }
  end
  
  unless target
    Common.log_error("「#{term_or_number}」が見つかりません")
    return
  end
  
  # リジェクトリストから削除
  rejected.delete(target)
  save_rejected_terms_data(rejected)
  
  Common.log_success("「#{target['term']}」をリジェクトから解除しました")
  Common.log_info('次回の vs index:auto で再び候補として表示されます')
end
```

##### `reset_rejected_terms!`

リジェクト履歴を全てクリア。

```ruby
def reset_rejected_terms!
  rejected_file = 'config/index_rejected.yml'
  
  unless File.exist?(rejected_file)
    Common.log_info('リジェクト済み候補はありません')
    return
  end
  
  FileUtils.rm_f(rejected_file)
  Common.log_success('リジェクト履歴をクリアしました')
end
```

---

### 3.2 IndexTermsManager

**責務**: `config/index_terms.yml` の管理

#### 3.2.1 主要メソッド

##### `merge_terms!(new_terms)`

新しい用語を辞書にマージ。

```ruby
def merge_terms!(new_terms)
  existing = load_existing_terms
  
  new_terms.each do |term|
    # 重複チェック
    unless existing.any? { |t| t['term'] == term['term'] }
      existing << {
        'term' => term['term'],
        'yomi' => term['yomi'],
        'pattern' => "/#{Regexp.escape(term['term'])}/",
        'auto_approved' => true,
        'approved_at' => Time.now.strftime('%Y-%m-%d %H:%M:%S')
      }
    end
  end
  
  save_terms!(existing)
  Common.log_success("#{new_terms.size} 件の用語を追加しました")
end
```

##### `load_existing_terms`

既存の用語辞書を読み込み。

```ruby
def load_existing_terms
  return [] unless File.exist?(CONFIG_FILE)
  data = YAML.load_file(CONFIG_FILE)
  data['terms'] || []
end
```

##### `save_terms!(terms)`

用語辞書を保存（読み順でソート）。

```ruby
def save_terms!(terms)
  data = {
    'terms' => terms.sort_by { |t| t['yomi'] }
  }
  File.write(CONFIG_FILE, data.to_yaml, encoding: 'utf-8')
end
```

---

### 3.3 ReviewMarkdownGenerator

**責務**: レビュー用Markdownファイルの生成・解析

#### 3.3.1 主要メソッド

##### `generate!(candidates)`

レビュー用Markdownを生成。

```ruby
def generate!(candidates)
  content = build_markdown(candidates)
  File.write(REVIEW_FILE, content, encoding: 'utf-8')
  Common.log_success("レビュー用ファイルを生成: #{REVIEW_FILE}")
  Common.log_info("ファイルを編集後、vs index:apply を実行してください")
end
```

##### `parse_approved`

Markdownから承認済み候補を抽出。

```ruby
def parse_approved
  return [] unless File.exist?(REVIEW_FILE)
  
  content = File.read(REVIEW_FILE, encoding: 'utf-8')
  approved = []
  
  # [x] でマークされた行を抽出
  content.scan(/^- \[x\] \*\*(.+?)\*\* \((.+?)\)/) do |term, yomi|
    approved << { 'term' => term, 'yomi' => yomi }
  end
  
  approved
end
```

##### `parse_rejected`

Markdownからリジェクト候補を抽出。

```ruby
def parse_rejected
  return [] unless File.exist?(REVIEW_FILE)
  
  content = File.read(REVIEW_FILE, encoding: 'utf-8')
  rejected = []
  
  # [r] でマークされた行を抽出
  content.scan(/^- \[r\] \*\*(.+?)\*\* \((.+?)\)/) do |term, yomi|
    rejected << { 'term' => term, 'yomi' => yomi }
  end
  
  rejected
end
```

##### `build_markdown(candidates)`

Markdown形式を構築。

```ruby
def build_markdown(candidates)
  <<~MARKDOWN
    # 索引候補レビュー
    
    生成日時: #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}
    候補数: #{candidates.size}件
    
    ---
    
    ## 使い方
    
    1. 採用する候補の `[ ]` を `[x]` に変更
    2. リジェクトする候補の `[ ]` を `[r]` に変更（次回以降表示しない）
    3. 読みを修正する場合は、カッコ内を直接編集
    4. 保存後、`vs index:apply` を実行
    
    **注意**: `[ ]` のままスキップした候補は、次回も表示されます
    
    ---
    
    ## 候補リスト
    
    #{build_candidate_list(candidates)}
  MARKDOWN
end
```

##### `build_candidate_list(candidates)`

候補リストを整形。

```ruby
def build_candidate_list(candidates)
  candidates.map do |c|
    contexts = c['contexts'].first(2).map do |ctx|
      snippet = ctx[:context].gsub("\n", ' ').strip[0..50]
      "  - 文脈: #{ctx[:chapter]} - \"#{snippet}...\""
    end.join("\n")
    
    "- [ ] **#{c['term']}** (#{c['yomi']}) - スコア: #{c['score']}\n#{contexts}"
  end.join("\n\n")
end
```

---

### 3.4 ReviewQueueManager

**責務**: レビュー待ち候補の管理

#### 3.4.1 主要メソッド

##### `save_queue(candidates)`

レビューキューを保存。

```ruby
def save_queue(candidates)
  data = {
    'generated_at' => Time.now.strftime('%Y-%m-%d %H:%M:%S'),
    'pending_count' => candidates.size,
    'candidates' => candidates
  }
  File.write(QUEUE_FILE, data.to_yaml, encoding: 'utf-8')
end
```

##### `load_queue`

レビューキューを読み込み。

```ruby
def load_queue
  return [] unless File.exist?(QUEUE_FILE)
  data = YAML.load_file(QUEUE_FILE)
  data['candidates'] || []
end
```

##### `clear_approved(approved_terms)`

承認済み候補をキューから削除。

```ruby
def clear_approved(approved_terms)
  queue = load_queue
  remaining = queue.reject { |c| approved_terms.include?(c['term']) }
  save_queue(remaining)
end
```

##### `save_rejected_terms(rejected_terms)`

リジェクト済み候補を保存。

```ruby
def save_rejected_terms(rejected_terms)
  rejected_file = 'config/index_rejected.yml'
  
  # 既存のリジェクト済みリストを読み込み
  existing = if File.exist?(rejected_file)
    data = YAML.load_file(rejected_file)
    data['rejected_terms'] || []
  else
    []
  end
  
  # 新規リジェクトを追加
  rejected_terms.each do |term|
    unless existing.any? { |t| t['term'] == term['term'] }
      existing << {
        'term' => term['term'],
        'yomi' => term['yomi'],
        'rejected_at' => Time.now.strftime('%Y-%m-%d %H:%M:%S')
      }
    end
  end
  
  # 保存
  data = {
    'rejected_at' => Time.now.strftime('%Y-%m-%d %H:%M:%S'),
    'rejected_terms' => existing
  }
  File.write(rejected_file, data.to_yaml, encoding: 'utf-8')
end
```

##### `load_rejected_terms`

リジェクト済み用語名のリストを取得。

```ruby
def load_rejected_terms
  rejected_file = 'config/index_rejected.yml'
  return [] unless File.exist?(rejected_file)
  
  data = YAML.load_file(rejected_file)
  terms = data['rejected_terms'] || []
  terms.map { |t| t['term'] }
end
```

---

### 3.5 既存コンポーネント（継続利用）

#### IndexCandidateExtractor

候補抽出（TF-IDF、定義パターン、専門用語パターン）。

#### IndexMatchScanner

本文スキャン、`[用語|読み]` 記法の検出、自動タグ付け。

**重要**: 手動マークアップが自動マッチより優先されます。

```ruby
def scan_and_tag!(markdown_path, context)
  content = context.content
  
  # 1. 手動マークアップを先に処理（優先）
  content = process_manual_markup(content)
  
  # 2. 自動マッチは、手動マークアップ済みの箇所を回避
  content = process_auto_match(content, skip_tagged: true)
  
  context.content = content
end
```

#### IndexPageBuilder

`_index_matches.yml` から索引HTMLページを生成。

---

## 4. CLIコマンド（Samovar）

### 4.1 `vs index:auto`

**説明**: 索引を全自動生成（推奨コマンド）

**オプション**: なし（設定は `book.yml` から読み取る）

**実装**:

```ruby
command 'auto' do
  def call
    chapters = resolve_all_chapters
    manager = UnifiedIndexManager.new
    manager.auto_process!(chapters)
  end
end
```

**使用例**:

```bash
$ vs index:auto

✓ 候補抽出完了
✓ 自動承認: 45件 (スコア≥200) ← book.yml の auto_approve_threshold
✓ レビュー待ち: 12件 (150≤スコア<200) ← book.yml の review_threshold
ℹ️  リジェクト設定により 8件の候補を除外しました
ℹ️  確認: vs index:rejected
✓ 索引生成完了

📝 レビュー: vs index:review
```

---

### 4.2 `vs index:review`

**説明**: レビュー待ち候補を確認

**オプション**:
- `--interactive` - 対話形式で実行（デフォルト: Markdownファイル生成）

**実装**:

```ruby
command 'review' do
  option '-i', '--interactive', 'インタラクティブモード', default: false
  option '-f', '--force', '既存ファイルを強制上書き', default: false
  
  def call
    manager = UnifiedIndexManager.new
    
    if @options[:interactive]
      manager.interactive_review!
    else
      manager.markdown_review!
    end
  end
end
```

**使用例（Markdownモード）**:

```bash
$ vs index:review

✓ レビュー用ファイルを生成しました: _index_review.md
📝 ファイルを開いて [ ] を [x] または [r] に変更してください
   完了したら: vs index:apply

# 編集中に再度実行すると警告
$ vs index:review

⚠️  編集中のレビューファイルが存在します: _index_review.md
⚠️  先に vs index:apply を実行するか、ファイルを削除してください
ℹ️  強制的に上書きする場合: vs index:review --force
```

**使用例（対話モード）**:

```bash
$ vs index:review --interactive

用語: レスポンシブデザイン
読み: れすぽんしぶでざいん
スコア: 178.5
文脈: ...画面サイズに応じて...

採用? [y/n/e/s] y
✓ 承認しました

...

✓ 8件を承認、4件をスキップしました
```

---

### 4.3 `vs index:apply`

**説明**: Markdownレビューを適用

**実装**:

```ruby
command 'apply' do
  def call
    manager = UnifiedIndexManager.new
    manager.apply_markdown_review!
  end
end
```

**使用例**:

```bash
$ vs index:apply

✓ 承認: 28件、リジェクト: 5件
✓ 索引を更新しました
```

---

### 4.4 `vs index:rejected`

**説明**: リジェクト済み候補の一覧表示

**実装**:

```ruby
command 'rejected' do
  def call
    manager = UnifiedIndexManager.new
    manager.list_rejected_terms
  end
end
```

**使用例**:

```bash
$ vs index:rejected

リジェクト済み候補:
1. マージソート (まーじそーと)
2. ヒープソート (ひーぷそーと)
3. 選択ソート (せんたくそーと)
```

---

### 4.5 `vs index:unreject`

**説明**: リジェクト済み候補を解除

**引数**:
- `TERM` - 用語名または番号

**実装**:

```ruby
command 'unreject' do
  argument :term, '用語名または番号'
  
  def call
    manager = UnifiedIndexManager.new
    manager.unreject_term!(@term)
  end
end
```

**使用例**:

```bash
# 用語名で指定
$ vs index:unreject マージソート
✓ 「マージソート」をリジェクトから解除しました
✓ 次回の vs index:auto で再び候補として表示されます

# 番号で指定
$ vs index:unreject 1
✓ 「マージソート」をリジェクトから解除しました
```

---

### 4.6 `vs index:reset-rejected`

**説明**: リジェクト履歴を全てクリア

**実装**:

```ruby
command 'reset-rejected' do
  def call
    manager = UnifiedIndexManager.new
    manager.reset_rejected_terms!
  end
end
```

**使用例**:

```bash
$ vs index:reset-rejected
✓ リジェクト履歴をクリアしました
```

---

## 5. ワークフロー

### 5.1 基本ワークフロー（推奨）

```bash
# 1. 執筆
$ vim contents/01-computer-journey.md

# 2. 索引自動生成
$ vs index:auto

✓ 自動承認: 45件
✓ レビュー待ち: 12件

# 3. 必要に応じてレビュー
$ vs index:review
# _index_review.md を編集

$ vs index:apply
✓ 28件を承認

# 4. ビルド
$ vs build
```

### 5.2 大量候補のレビュー

```bash
$ vs index:auto

✓ 自動承認: 32件 (スコア≥200)
✓ レビュー待ち: 58件 (150≤スコア<200)

$ vs index:review
# _index_review.md で一括編集
# [ ] を [x] に変更、読みも修正可能

$ vs index:apply
✓ 45件を承認
```

### 5.3 少数候補の対話レビュー

```bash
$ vs index:auto

✓ レビュー待ち: 5件

$ vs index:review --interactive

用語: フレームワーク
採用? [y/n/e/r/s] e
読みを編集: ふれーむわーく → フレームワーク
✓ 編集して承認

用語: マージソート
採用? [y/n/e/r/s] r
✓ リジェクト

...

✓ 承認: 3件、リジェクト: 1件
```

### 5.4 リジェクト候補の管理

```bash
# 1. マージソートを軽く触れただけなのでリジェクト
$ vs index:review
# _index_review.md で [r] マーク

$ vs index:apply
✓ リジェクト: 1件（マージソート）

# 2. 後日、マージソートについて詳しく加筆

# 3. リジェクト解除（方法1: 直接編集）
$ vim config/index_rejected.yml
# マージソートの行を削除またはコメントアウト

# 3. リジェクト解除（方法2: CLIコマンド）
$ vs index:rejected
リジェクト済み候補:
1. マージソート (まーじそーと)
2. ヒープソート (ひーぷそーと)

$ vs index:unreject 1
✓ 「マージソート」をリジェクトから解除しました

# 4. 再度自動処理
$ vs index:auto
✓ レビュー待ち: 1件（マージソート）

$ vs index:review
# 今度は [x] で承認

$ vs index:apply
✓ 承認: 1件（マージソート）
```

---

## 6. 設計上の重要な決定事項

### 6.1 手動マークアップ vs 自動マッチの優先度

**原則**: 手動マークアップが優先されます。

**理由**: 
- 著者が `[アルゴリズム|あるごりずむ]` と明示的に書いた場合、それは著者の意図を反映
- `index_terms.yml` の自動マッチよりも、手動マークアップの方が確実

**実装**:
```ruby
# IndexMatchScanner
def scan_and_tag!(markdown_path, context)
  content = context.content
  
  # 1. 手動マークアップを先に処理
  content, manual_positions = process_manual_markup(content)
  
  # 2. 自動マッチは手動マークアップ済み箇所を回避
  content = process_auto_match(content, exclude_positions: manual_positions)
  
  context.content = content
end
```

**例**:
```markdown
# 本文
アルゴリズムは重要です。[アルゴリズム|あるごりずむ]を学びましょう。

# 処理後
アルゴリズムは重要です。<dfn id="idx-algorithm-1">アルゴリズム</dfn>を学びましょう。
                                    ↑ 手動マークアップが優先
```

### 6.2 リジェクト除外の可視化

**原則**: リジェクト設定により除外された候補数を必ずレポートする。

**理由**:
- 著者がリジェクトを忘れている場合の気付きを促す
- 「なぜか自動抽出されない」という誤解を防ぐ

**出力例**:
```bash
✓ 候補抽出完了
✓ 自動承認: 45件
✓ レビュー待ち: 12件
ℹ️  リジェクト設定により 8件の候補を除外しました
ℹ️  確認: vs index:rejected
```

### 6.3 レビューファイルの上書き防止

**原則**: 編集中の `_index_review.md` が存在する場合、警告を出して停止する。

**理由**:
- 著者が編集中の内容を誤って上書きする事故を防ぐ
- 安全性を優先

**実装**:
```ruby
def markdown_review!
  if File.exist?('_index_review.md')
    Common.log_warn('編集中のレビューファイルが存在します')
    Common.log_warn('先に vs index:apply を実行するか、ファイルを削除してください')
    Common.log_info('強制的に上書き: vs index:review --force')
    return unless @options[:force]
  end
  # ...
end
```

---

## 7. ファイルフォーマット

### 7.1 `config/index_terms.yml`

確定済み用語辞書（自動更新）。

```yaml
terms:
  - term: アルゴリズム
    yomi: あるごりずむ
    pattern: /アルゴリズム/
    auto_approved: true
    approved_at: 2026-01-05 21:30:00
  
  - term: レスポンシブデザイン
    yomi: れすぽんしぶでざいん
    pattern: /レスポンシブデザイン/
    auto_approved: false
    approved_at: 2026-01-05 21:35:00
```

**フィールド**:
- `term`: 用語
- `yomi`: 読み（五十音順ソートに使用）
- `pattern`: マッチングパターン（正規表現）
- `auto_approved`: 自動承認されたか
- `approved_at`: 承認日時

---

### 7.2 `config/index_review_queue.yml`

レビュー待ち候補。

```yaml
generated_at: 2026-01-05 21:30:00
pending_count: 12
candidates:
  - term: レスポンシブデザイン
    yomi: れすぽんしぶでざいん
    score: 178.5
    contexts:
      - chapter: 01-computer-journey
        context: "画面サイズに応じて..."
      - chapter: 03-ai-overview
        context: "モバイル対応として..."
  
  - term: フレームワーク
    yomi: ふれーむわーく
    score: 165.2
    contexts:
      - chapter: 02-person
        context: "Reactなどの..."
```

---

### 7.3 `config/index_rejected.yml`

リジェクト済み候補（再表示しない）。

```yaml
rejected_at: 2026-01-05 22:30:00
rejected_terms:
  - term: マージソート
    yomi: まーじそーと
    rejected_at: 2026-01-05 22:30:00
  
  - term: ヒープソート
    yomi: ひーぷそーと
    rejected_at: 2026-01-05 22:35:00
```

**編集方法**:

1. **直接編集（上級者向け）**: ファイルを開いて該当行を削除またはコメントアウト
2. **CLIコマンド（初心者向け）**: `vs index:unreject <用語名または番号>`

---

### 7.4 `_index_review.md`

レビュー用Markdown（一時ファイル）。

```markdown
# 索引候補レビュー

生成日時: 2026-01-05 21:53:00
候補数: 12件

---

## 使い方

1. 採用する候補の `[ ]` を `[x]` に変更
2. リジェクトする候補の `[ ]` を `[r]` に変更（次回以降表示しない）
3. 読みを修正する場合は、カッコ内を直接編集
4. 保存後、`vs index:apply` を実行

**注意**: `[ ]` のままスキップした候補は、次回も表示されます

---

## 候補リスト

- [ ] **レスポンシブデザイン** (れすぽんしぶでざいん) - スコア: 178.5
  - 文脈: 01-computer-journey - "画面サイズに応じて..."
  - 文脈: 03-ai-overview - "モバイル対応として..."

- [x] **アルゴリズム** (あるごりずむ) - スコア: 245.8
  - 文脈: 01-computer-journey - "効率的な処理手順..."
  - 文脈: 03-ai-overview - "機械学習の基礎..."

- [ ] **フレームワーク** (ふれーむわーく) - スコア: 165.2
  - 文脈: 02-person - "Reactなどの..."

- [r] **マージソート** (まーじそーと) - スコア: 155.3
  - 文脈: 01-computer-journey - "安定ソートの代表例..."
```

**編集方法**:
- `[ ]` → `[x]`: 候補を採用
- `[ ]` → `[r]`: 候補をリジェクト（次回以降表示しない）
- `(読み)` を直接編集: 読みを修正
- `[ ]` のまま: スキップ（次回も表示）

---

### 7.5 `_index_matches.yml`

内部キャッシュ（自動生成）。

```yaml
generated_at: '2026-01-05T21:30:00+09:00'
total_matches: 156
terms:
  アルゴリズム:
    - chapter: 01-computer-journey
      yomi: あるごりずむ
      locations:
        - line: 45
          context: "効率的な処理手順..."
    - chapter: 03-ai-overview
      yomi: あるごりずむ
      locations:
        - line: 123
          context: "機械学習の基礎..."
```

---

### 7.6 `_indexpage.html`

生成された索引ページ。

```html
<!DOCTYPE html>
<html lang="ja">
<head>
  <meta charset="UTF-8">
  <title>索引</title>
</head>
<body>
  <h1>索引</h1>
  
  <section class="index-group">
    <h2>あ行</h2>
    <dl>
      <dt>アルゴリズム</dt>
      <dd>
        <a href="#01-computer-journey-45">01章</a>,
        <a href="#03-ai-overview-123">03章</a>
      </dd>
    </dl>
  </section>
  
  <!-- ... -->
</body>
</html>
```

---

## 8. 実装計画

### Phase 1: コアコンポーネント（1-2週間）

- [ ] `UnifiedIndexManager` 実装
- [ ] `IndexTermsManager` 実装
- [ ] `ReviewQueueManager` 実装
- [ ] 既存コンポーネントとの統合

### Phase 2: Markdownレビュー（1週間）

- [ ] `ReviewMarkdownGenerator` 実装
- [ ] `vs index:review` コマンド（Markdown生成）
- [ ] `vs index:apply` コマンド

### Phase 3: 自動化コマンド（1週間）

- [ ] `vs index:auto` コマンド実装
- [ ] スコアリング閾値の調整
- [ ] レポート機能

### Phase 4: 対話モード（数日）

- [ ] `vs index:review --interactive` 実装
- [ ] プロンプト処理
- [ ] 編集機能

### Phase 5: テスト・ドキュメント（数日）

- [ ] ユニットテスト
- [ ] 統合テスト
- [ ] ユーザーガイド作成

---

## 9. 技術仕様

### 8.1 使用技術

- **Ruby**: 3.x以上
- **CLI Framework**: Samovar（既存）
- **YAML Parser**: Psych（標準ライブラリ）
- **MeCab**: 読み推測（オプション）

### 8.2 依存関係

```ruby
# Gemfile（既存の依存関係を利用）
gem 'samovar'  # 既にインストール済み
gem 'natto', require: false  # MeCab（オプション）
```

### 8.3 ファイルパス

```ruby
# 設定ファイル
CONFIG_DIR = 'config'
INDEX_TERMS_FILE = "#{CONFIG_DIR}/index_terms.yml"
REVIEW_QUEUE_FILE = "#{CONFIG_DIR}/index_review_queue.yml"

# 一時ファイル
REVIEW_MARKDOWN = '_index_review.md'
INDEX_CACHE = '_index_matches.yml'

# 出力ファイル
INDEX_PAGE = '_indexpage.html'
```

---

## 10. エラーハンドリング

### 9.1 ファイル不在

```ruby
unless File.exist?(INDEX_TERMS_FILE)
  Common.log_warn("#{INDEX_TERMS_FILE} が見つかりません")
  Common.log_info("初回実行時は自動生成されます")
end
```

### 9.2 MeCab未インストール

```ruby
def mecab_available?
  @mecab_available ||= begin
    require 'natto'
    true
  rescue LoadError
    Common.log_warn('MeCab が利用できません。読みは手動で確認してください')
    false
  end
end
```

### 9.3 YAML解析エラー

```ruby
begin
  data = YAML.load_file(file_path)
rescue Psych::SyntaxError => e
  Common.log_error("YAML解析エラー: #{e.message}")
  return []
end
```

---

## 11. パフォーマンス考慮

### 10.1 大規模プロジェクト対応

- **候補数**: 1000件以上でも処理可能
- **章数**: 100章以上に対応
- **メモリ**: ストリーミング処理で省メモリ

### 10.2 最適化

```ruby
# 候補抽出の並列化（将来的に）
candidates = chapters.map do |chapter|
  Thread.new { extract_from_chapter(chapter) }
end.map(&:value).flatten

# キャッシュ活用
@yomi_cache ||= {}
@yomi_cache[term] ||= infer_yomi(term)
```

---

## 12. セキュリティ

### 11.1 ファイル操作

- 相対パスのみ許可
- ディレクトリトラバーサル対策

```ruby
def safe_path(path)
  Pathname.new(path).cleanpath.to_s
end
```

### 11.2 正規表現

- ReDoS対策
- パターン長の制限

```ruby
def safe_pattern(pattern)
  return nil if pattern.length > 100
  Regexp.new(pattern, Regexp::FIXEDENCODING)
rescue RegexpError
  nil
end
```

---

## 13. 参考資料

- [MeCab 公式ドキュメント](https://taku910.github.io/mecab/)
- [Samovar GitHub](https://github.com/ioquatix/samovar)
- [TF-IDF アルゴリズム](https://ja.wikipedia.org/wiki/Tf-idf)

---

**END OF SPECIFICATION**
