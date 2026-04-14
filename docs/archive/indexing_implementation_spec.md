# vivlio-starter 索引システム実装仕様書

本書は 索引機能に関する単一の仕様ソースとして管理する。今後の変更は必ず本書に反映させること。

---

## 1. 目的と設計原則

| 目的 | 詳細 |
| --- | --- |
| 著者体験 | Markdown の軽微なマークアップと `_index_review.md` の編集のみで高品質な索引を維持できる |
| 自動化 | スコアベースで候補を分類し、高スコアは自動承認、残りは Markdown レビューで処理 |
| パイプライン統合 | `vs build` に自然に組み込み、pre_process / post_process を再利用 |
| シングルソース | 確定済み用語は `config/index_terms.yml` にのみ保持し、他はキャッシュや UI 用ファイル |
| Vivliostyle 連携 | CSS `target-counter` でページ番号を解決し、HTML は軽量な構造を維持 |

### 1.1 使用技術
- Ruby 4.x（Set リテラル・Time 強化・Samovar CLI）
- Nokogiri / Psych / YAML
- MeCab + natto（読み推測、名詞抽出）
- Vivliostyle + CSS paged media

---

## 2. ファイル構成とデータフロー

```
config/
  index_terms.yml        # 承認済み辞書
  index_rejected.yml     # リジェクト済み語
contents/*.md            # pre_process 後の本文
_index_review.md         # 著者が編集する UI
_index_matches.yml       # 用語と出現位置のキャッシュ
_indexpage.html          # Vivliostyle に読み込ませる索引ページ
```

### 2.1 ライフサイクル

1. `vs index:auto`
   - IndexCandidateExtractor: 手動マークアップ + 自動抽出
   - ScoringEngine: 候補にスコア付与
   - UnifiedIndexManager: 閾値に応じて自動承認 or レビュー待ちに仕分け
   - IndexMatchScanner: 本文へ `<dfn>/<span>` を埋め込み `_index_matches.yml` を生成
   - ReviewMarkdownGenerator: `_index_review.md` を生成
2. 著者が `_index_review.md` を編集（`[ ]→[x]/[r]`、読み修正）
3. `vs index:apply`
   - ReviewMarkdownGenerator が編集内容を解析
   - IndexTermsManager / ReviewQueueManager / IndexMatchScanner / IndexPageBuilder が連携し辞書と HTML を更新
4. `vs build`
   - pre_process/post_process 内で `_indexpage.html` を取り込み、Vivliostyle でページ番号を最終確定

### 2.2 手動マークアップ記法

| 記法 | 説明 | HTML 変換 |
| --- | --- | --- |
| `[用語|読み]` | 読み付き明示。初出推奨 | `<dfn ... data-yomi="読み">用語</dfn>`（初出） |
| `[用語]` | 読み省略。MeCab で補完 | `<dfn/span ... data-yomi="推測読み">` |

コードフェンスや `[リンク](URL)` を誤検出しないよう正規表現で除外する。リンクは `](` が続くことで判定。コードブロックは ````` で囲まれた範囲をスキップする。

---

## 3. ワークフローとユーザー体験

### 3.1 推奨シーケンス

```bash
# 1. 候補抽出とレビュー UI 生成
vs index:auto

# 2. _index_review.md を編集（または vs index:review --interactive）

# 3. 承認結果の反映
vs index:apply

# 4. ビルド
vs build
```

### 3.2 `_index_review.md` の仕様
- ラベル: `` `NEW!` ``（今回初登場）、`` `Today` ``（当日承認・追加）。`index_terms.yml` の `approved_at` と `timezone` で判定。
- 操作: `[ ]→[x]` で承認、`[ ]→[r]` でリジェクト。`(読み)` を直接編集すると `index_terms.yml` に反映。
- セクション順: Terms → High Candidates → Low Candidates → Rejected。High/Low の件数は `high_candidates_ratio`（既定 0.25）で決定し、境界スコアと同値は High に含める。
- Rejected セクションで `[r]` を付けるとリジェクト解除（次回候補に復帰）。

### 3.3 しきい値

`config/book.yml` より以下を読み取る:

```yaml
index:
  enabled: true
  auto_discovery: true
  title: '索引'
  auto_approve_threshold: 300    # 以上で自動承認
  review_threshold: 150          # 以上でレビュー待ち
  high_candidates_ratio: 0.25
  context_width: 40
  smart_context_cutting: true
  use_mecab: true
  timezone: 'Asia/Tokyo'
```

※ `auto_discovery: false` の場合、索引用語登録フローは完全に手動マークアップ由来のみとし、自動抽出候補は出力されず `_index_review.md` にも載らない。

---

## 4. コンポーネント詳細

### 4.1 UnifiedIndexManager

- `auto_process!`: 設定読込→候補抽出→既存/リジェクト除外→自動承認→レビューキュー保存→本文スキャン→索引ページ生成→結果レポート。
- `markdown_review!`: `_index_review.md` を生成。既存ファイルがあれば警告し `--force` で上書き。
- `apply_markdown_review!`: Markdown から `[x]/[r]` を解析し、辞書更新→リジェクト保存→レビューキュー削除→再スキャン→ `_index_review.md` 削除。
- `interactive_review!`: CLI で 1 つずつ承認/編集/棄却。
- `list_rejected_terms` / `unreject_term!` / `reset_rejected_terms!`: リジェクト管理。

### 4.2 IndexCandidateExtractor

レイヤー構成:
1. 構造抽出（見出し、強調、コードスパン、`[用語|読み]`、`[用語]`）。
2. MeCab で名詞 / 複合名詞を抽出。`[用語]` は読みを推測。
3. 定義表現パターン（「〜とは」「〜を…と定義」など）を正規表現で検知。
4. 近傍語（Co-occurrence）辞書と照合し、関連度を評価。
5. 専門用語辞書（`config/technical_terms.yml`）とマッチ。

### 4.3 ScoringEngine

| ルール | 加点 |
| --- | --- |
| 手動マークアップ `[用語|読み]` | +200 |
| 見出し | +100 |
| `<dfn>` による定義 | +100 |
| 定義表現パターン | +70 |
| 辞書 + 文脈一致 | +80 |
| 辞書のみ | +20 |
| 専門用語辞書 | +50 |
| TF-IDF 高スコア | +40 |
| 近傍語一致 | +15 |
| 単発出現 | +5 |

スコア ≥ `auto_approve_threshold` で自動承認、`review_threshold ≤ score < auto_approve_threshold` でレビュー待ち。それ以外は破棄。

### 4.4 IndexMatchScanner

- `[用語|読み]` を優先的に処理し `<dfn>/<span>` を挿入。
- 手動処理済み範囲を記録し、自動マッチは該当範囲を除外。
- `_index_matches.yml` に `{id, term, yomi, file, line, context, is_definition}` を保存。
- コードブロックやリンクを除外。Ruby 4.0 の `Set[]` を活用して初出判定を O(1) にする。

### 4.5 IndexPageBuilder

- `_index_matches.yml` を読み込み、`yomi` の先頭で「あ行〜わ行」「A〜Z」「その他」に分類。
- HTML テンプレートを ERB/Nokogiri で生成し、CSS `target-counter(attr(href), page)` でページ番号を描画。
- 同一ページ内重複は Phase1 では許容、将来的に JS or YAML で重複排除予定。

### 4.6 IndexTermsManager & ReviewQueueManager

- `merge_terms!` で新語を `index_terms.yml` にマージ（読みでソート、`pattern` は `Regexp.escape`。英単語は `\b` を付与）。
- ReviewQueueManager は `config/index_review_queue.yml` を管理し、承認済み/リジェクト済み語をキューから除外。

### 4.7 ReviewMarkdownGenerator

- `_index_review.md` を生成し、候補を Markdown チェックリストで表現。
- `parse_approved` / `parse_rejected` で `[x]/[r]` を解析。
- 文脈抜粋は `context_width`・`smart_context_cutting` に従う。

---

## 5. CLI コマンド仕様

| コマンド | 役割 | 備考 |
| --- | --- | --- |
| `vs index:auto` | 抽出 → 自動承認 → レビュー待ち → `_index_review.md` 生成 | 設定は `book.yml` から取得 |
| `vs index:review [-i|--interactive] [--force]` | Markdown 生成 or 対話モード | 編集済みファイルがある場合は警告 |
| `vs index:apply` | `_index_review.md` の編集内容を辞書へ反映 | |
| `vs index:build` | `_index_matches.yml` / `_indexpage.html` を再生成 | `vs build` 実行時に内部的に呼ばれる |

`vs clean` は `_index_review.md`・`_index_matches.yml`・`_indexpage.html` を削除する。中間成果を残したい場合は `vs build --no-clean` を利用する。

---

## 6. データフォーマット

### 6.1 `config/index_terms.yml`
```yaml
terms:
  - term: レスポンシブデザイン
    yomi: れすぽんしぶでざいん
    pattern: "/レスポンシブデザイン/"
    auto_approved: true
    approved_at: '2026-01-05 21:35:00'
    source: manual_markup
```

### 6.2 `config/index_review_queue.yml`
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
```

### 6.3 `config/index_rejected.yml`
```yaml
rejected_terms:
  - term: マージソート
    yomi: まーじそーと
    rejected_at: '2026-01-05 22:30:00'
```

### 6.4 `_index_matches.yml`
```yaml
matches:
  - id: idx-responsive-design-1
    term: レスポンシブデザイン
    yomi: れすぽんしぶでざいん
    file: 21-layout
    line: 45
    context: "...レスポンシブデザインとは..."
    is_definition: true
    source: manual_markup   # manual_markup / auto_approved
```

### 6.5 `_index_review.md`（抜粋）
```markdown
# 索引レビュー
※ [x]で承認、[r]で棄却。読みの修正は ( ) 内を編集してください。

## 1. 登録済み用語の確認 (Terms: 152語)
- [x] `Today` **演算子** (えんざんし)

## 2. 推奨候補 (High Candidates: 12語)
- [ ] `NEW!` **非同期処理** (ひどうきしょり) - スコア: 210.0
```

---

## 7. 実装計画（フェーズ）

| フェーズ | 内容 |
| --- | --- |
| Phase 1 (MVP) | `IndexMatchScanner`・`IndexPageBuilder`・辞書スキーマ・`vs build` 連携 |
| Phase 2 (自動抽出) | `IndexCandidateExtractor`・`ScoringEngine`・TF-IDF・`vs index:auto` |
| Phase 3 (レビュー UI) | `_index_review.md`・`vs index:review`・`vs index:apply` |
| Phase 4 (対話/リジェクト) | `--interactive`・`index_rejected.yml` 管理 CLI |
| Phase 5 (高度化) | 読み学習、High/Low 比率、`NEW!/Today`、UnifiedIndexManager 仕上げ |

---

## 8. テスト戦略

### 8.1 ユニットテスト
- IndexMatchScanner: `[用語|読み]` → `<dfn>/<span>`、コードブロック除外
- IndexCandidateExtractor: 構造/MeCab/定義パターン/近傍語
- ScoringEngine: ルール加点
- ReviewMarkdownGenerator: `[x]/[r]` の解析

### 8.2 統合テスト
```ruby
IndexMatchScanner.scan_all_chapters!(['11-basics'])
matches = YAML.load_file('_index_matches.yml')
assert matches['matches'].size > 0

IndexPageBuilder.build!('_index_matches.yml', '99-index.html')
assert File.exist?('99-index.html')
```

### 8.3 手動確認
1. `_index_review.md` を編集して `vs index:apply`。
2. `vs index:rejected` / `vs index:unreject` / `vs index:reset-rejected` の挙動を確認。
3. `vs clean` が `_index_review.md` / `_index_matches.yml` / `_indexpage.html` を削除するか確認。

---

## 9. 既知の制約と改善案

| 課題 | 現状対応 | 将来案 |
| --- | --- | --- |
| ページ番号確定 | CSS `target-counter` に委譲 | PDF 後処理で冪等チェック |
| 同一ページ内重複 | Phase1 は許容 | Phase3 で JS/変換ロジックによる重複排除 |
| MeCab 依存 | `vs doctor --fix` で mecab / natto を導入、未導入なら警告 | NEologd / 英単語辞書を同梱 |
| `[用語|読み]` とリンクの衝突 | `|` + `](` 判定で回避 | Markdown AST 解析へ拡張 |

---

## 10. 参考リソース

- `lib/vivlio/starter/cli/index/*.rb` … 実装コード
- `test/vivlio/starter/cli/index/*_test.rb` … テストスイート
- `book-vivlio-starter/20-indexing.md` … 著者向けマニュアル
- `_index_review.md` テンプレート … ReviewMarkdownGenerator 内で生成

本仕様書を唯一の真実ソースとし、機能追加・設計変更・CLI 拡張時は必ず本書の該当セクションを更新すること。
