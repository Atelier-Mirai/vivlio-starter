## vivlio-starter 索引・用語集 統合仕様書

本仕様書は、索引（Index）および用語集（Glossary）機能を一元的に管理するための責務・データ構造・ワークフローを定義する。

---

## 1. 目的と設計原則

| 項目 | 詳細 |
| --- | --- |
| UX一元化 | 索引の整理と用語集の執筆を `_index_glossary_review.md` という単一ファイルで完結させる |
| 階層的フラグ | `[ig]` や `[i]` などのフラグにより、単語ごとの役割を著者が直感的に制御する |
| シングルソース | 確定データは `config/*.yml` に保持し、ビルド時に HTML/CSS で最終出力を生成する |
| 柔軟なパース | インデントやフラグの順不同（`ig`/`gi`）を許容し、著者の執筆リズムを妨げない |

---

## 2. ファイル構成

```
config/
  index_terms.yml        # 承認済み索引辞書
  glossary_terms.yml     # 承認済み用語集辞書（説明文含む）
  index_glossary_rejected.yml  # リジェクト済み（索引・用語集）
contents/*.md            # 本文ソース
_index_glossary_review.md # 著者が編集する UI（索引・用語集兼用）
_index_matches.yml       # スキャン結果のデータ
_indexpage.html          # 生成された索引ページ
_glossarypage.html       # 生成された用語集ページ
```

---

## 3. レビュー UI（`_index_glossary_review.md`）仕様

### 3.1 チェックボックス・フラグ

`[ ]` 内の文字の有無で、その用語の役割を決定する。文字は順不同。

| フラグ | 意味 | 処理内容 |
| --- | --- | --- |
| `i` | Index | 索引として登録。本文中に `<span>` を埋め込み、索引ページに掲載 |
| `g` | Glossary | 用語集として登録。用語集ページに説明文付きで掲載 |
| `ig` / `gi` | Both | 索引と用語集の両方に登録 |
| `r` | Reject | 索引・用語集の両方の候補から除外（リジェクトリスト入り、説明文も退避） |
| `-i` | Reject Index | 索引から削除（用語集には残す）|
| `-g` | Reject Glossary | 用語集から削除（索引には残す） |
| `-ig / -gi` | Reject | `r` と同じ |
| `[ ]` | 保留 | 何もしない。次回の `vs index:auto` で再度候補として出現 |

### 3.2 説明文（Definition）の記述ルール

* 用語集（`g`）として登録する場合、用語行の直後にインデント（スペース2つ以上）を空けてテキストを記述する。
* 次の用語行（`- [`）が始まるまでの全行を説明文として取得する。
* インデントはパース時にトリミングされる。
* Markdown 記法（例: `*強調*`, `` `コード` ``）の使用を許容する。
* 出現箇所は `- 章スラッグ: 文脈` 形式で列挙し、ダブルクォートは付けない。
* 出現箇所のリストと説明文の間には、インデント付きの空行を 1 行挿入する。空行が無い場合、説明文境界が判別できず UI が崩れる。

例:

```markdown
- [ig] **非同期処理** (ひどうきしょり) - スコア: 295.6
  - 00-preface: 楽しいプログラミングの世界へようこそ。 非同期処理は「JavaScript」を日々利用して
  - 01-life: サイトを見たり、書類作成など仕事に活用したり、「プログラミング」では、非同期処理を行ないます。JavaScriptでは

  処理の完了を待たずに*次のタスクを実行*する方式。
  `JavaScript`の`Promise`などで利用されます。
```

その他の仕様は、現行の成果物 `_index_review.md` に従う。
(仕様の詳細は、現行コードや docs/specs/indexing_plan.md や docs/specs/indexing_implementation_spec.md 参照のこと)

---

## 4. ワークフロー

### 4.1 `vs index:auto`（抽出フェーズ）

1. **スキャン**: 本文から `[用語|読み]` 記法および MeCab による自動抽出を実施。
2. **推論**:
   * 定義表現（「〜とは」）を伴う場合は `[ig]` とし、その一文を説明文候補として挿入。
   * それ以外は `[i]` とする。
3. **UI 生成**: 抽出結果を `_index_glossary_review.md` に書き出す。

### 4.2 `vs index:apply`（反映フェーズ）

1. **パース**: `_index_glossary_review.md` の全行を走査し、フラグと説明文を解析。
2. **辞書更新**:
   * `i` を含む → `index_terms.yml` を更新。
   * `g` を含む → `glossary_terms.yml` を更新（説明文を保存）。
   * `r` または `-ig` を含む → 用語・読み・説明文ごと `index_glossary_rejected.yml` へ移動し、著者が必要に応じて復活できるようにする。
   * `-i` を含む → `index_terms.yml` から削除。`index_glossary_rejected.yml` へ移動。
   * `-g` を含む → `glossary_terms.yml` から削除。`index_glossary_rejected.yml` へ移動。
   * `-ig` を含む → `index_terms.yml` から削除、`glossary_terms.yml` から削除。`index_glossary_rejected.yml` へ移動。
3. **クリーンアップ**: 反映済みの `_index_glossary_review.md` を削除、またはリネームして保管。

### 4.3 `vs build`（ビルドフェーズ）

1. **Pre-process**: `index_terms.yml` に基づき、本文に `<dfn>`, `<span>` を自動挿入。
2. **Page-gen**:
   * `index_terms.yml` から `_indexpage.html` を生成。
   * `glossary_terms.yml` から `_glossarypage.html` を生成。
3. **Vivliostyle**: ページ番号を CSS `target-counter` で解決。

> 出力順序（PDF 結合時の基本シーケンス）
>
> 1. 扉（Titlepage）
> 2. 権利表記（Legalpage）
> 3. 前書（Preface）
> 4. 本文（Chapters）
> 5. 付録（Appendix）
> 6. 用語集（Glossary）
> 7. 後書（Postface）
> 8. 索引（Index）
> 9. 奥付（Colophon）

索引と用語集は、本文と付録の直後に連続して差し込み、最終的な PDF では上記の順番でマージされる。

### 4.4 用語集リンク自動化

1. **本文 → 用語集リンク**
   * Pre-process で `g` フラグ付き語を検出した際、索引用 `<span>` の直後に用語集リンクを挿入する。
   * リンクは上付きの `†`（ダガー）記号で表示し、クリックで用語集ページへジャンプする。
   * HTML 構造: `<a id="gls-src-{chapter}-{n}" class="glossary-link" href="_glossarypage.html#gls-{slug}"><sup>†</sup></a>`
   * `†` 記号は `GLOSSARY_INDICATOR = '†'` としてハードコーディングされ、設定による変更は不可。
   * 複数回登場する語でも、`gls-src-<chapter>-<n>` 形式のアンカー ID を本文側に埋め込み、一意に識別する。

2. **用語集 → 本文リンク（バックリンク）**
   * `_glossarypage.html` 生成時に各語へ `id="gls-${slug}"` を付与し、`glossary_terms.yml` に保存された `backlink_sources`（章番号・出現序数）を基に本文アンカーへのリンク一覧を表示する。
   * 表記例: `→ p.1, 5, 12`（ページ番号のみ、重複排除・昇順ソート）。
   * ページ番号は CSS `target-counter()` で解決する。

3. **データ連携**
   * `vs index:auto` は候補抽出時に章番号・段落位置を `_index_matches.yml` に記録する。
   * `vs index:apply` は `g` 指定の語について `glossary_terms.yml` に `backlink_sources` を追記し、`vs build` が利用できるようにする。

4. **スタイルと PDF 対応**
   * `.glossary-link` と `.glossary-backlinks` を CSS で装飾し、PDF/HTML 双方でリンクが視認できるようにする。
   * Vivliostyle でリンク遷移できることを確認し、印刷時にはページ番号表示で代替できるよう target-counter を併用する。

---

## 5. 辞書データ構造（YAML）

### 5.1 `config/glossary_terms.yml`

```yaml
terms:
  - term: 非同期処理
    yomi: ひどうきしょり
    definition: |
      処理の完了を待たずに次のタスクを実行する方式。
      JavaScriptのPromiseなどで利用されます。
    backlink_sources:
      - chapter: "03"
        occurrence: 1
      - chapter: "07"
        occurrence: 2
    approved_at: '2026-01-23 10:00:00'
```

---

## 6. book.yml の設定項目

索引・用語集の振る舞いは `config/book.yml` の設定で制御する。共通設定は `index_glossary` セクションに、個別設定は `index` / `glossary` セクションに配置する。

### 6.1 `index_glossary` セクション（共通設定）

索引と用語集で共有する設定項目。個別セクションの同名キーで上書き可能。

| キー | 説明 | 既定値 |
| --- | --- | --- |
| `enabled` | 索引・用語集機能の ON/OFF | `true` |
| `use_mecab` | 読み推測に MeCab を利用するか | `true` |
| `timezone` | `_index_glossary_review.md` の新着判定に使うタイムゾーン | `'Asia/Tokyo'` |
| `context_width` | レビュー UI で表示する前後文脈の文字幅 | `40` |
| `smart_context_cutting` | 形態素境界で文脈をトリミングするか | `true` |

```yaml
# book.yml 例
index_glossary:
  use_mecab: true
  timezone: 'Asia/Tokyo'
  context_width: 40
  smart_context_cutting: true
```

### 6.2 `index` セクション（索引固有）

| キー | 説明 | 既定値 |
| --- | --- | --- |
| `auto_discovery` | MeCab 等で自動候補抽出を行うか | `true` |
| `title` | 索引ページのタイトル | `'索引'` |
| `auto_approve_threshold` | スコアが閾値以上なら自動で `index_terms.yml` に追加 | `300` |
| `review_threshold` | レビュー対象スコア閾値 | `150` |
| `high_candidates_ratio` | 候補を High/Low に分割する比率 | `0.25` |

### 6.3 `glossary` セクション（用語集固有）

| キー | 説明 | 既定値 |
| --- | --- | --- |
| `title` | 用語集ページのタイトル | `'用語集'` |
| `require_definition` | `g` フラグで説明文未記入ならエラーにするか | `false` |
| `max_definition_length` | 説明文の最大文字数（超過で警告） | `200` |

> **注意**: 旧仕様の `link_label` オプションは廃止されました。本文中の用語集リンクは常に上付きの `†` 記号で表示され、アクセント色（`book.yml` の `color` 設定に連動）でスタイリングされます。

---

## 7. 将来の拡張性

* **AI Assist**: `vs index:auto --ai` 実行時に、`g` 候補の説明文を AI がドラフト生成。
* **Apple Intelligence**: macOS 環境でローカルリソースを利用した本文要約型の用語説明生成をサポート。

---

## 8. テストおよびドキュメント運用

1. **リンク機能の回帰テスト**
   * `test/vivlio/starter/cli/build_integration_test.rb` に Glossary リンク往復のシナリオを追加し、複数出現語でも本文⇄用語集のアンカーが生成されることを確認する。
   * `test/vivlio/starter/cli/index/index_page_builder_test.rb` 等で `_glossarypage.html` に `gls-<slug>` と `glossary-backlinks` が含まれること、ページ番号/章名が正しく表記されることを検証する。
   * `test/vivlio/starter/cli/post_process/heading_processor_test.rb` など Pre-process で `<a class="glossary-link">` が挿入されるパターンを追加し、`link_label` 設定や `backlink_links` フラグの On/Off を網羅する。

2. **既存仕様との整合**
   * 本書に明記していない挙動は、`docs/specs/indexing_plan.md` / `docs/specs/indexing_implementation_spec.md` に記された従来仕様を踏襲する。
   * 新機能を実装する際は、両ドキュメントと本書の差分を確認し、必要に応じて相互参照を更新する。

3. **著者向けガイドの更新**
   * 著者向けの運用手順は `/Users/mirai/projects/vivlio-starter/book-vivlio-starter/20-indexing.md` を更新して提供する。索引＋用語集の共通レビュー手順やリンク機能の使い方などを同ガイドに追記する。
   * 当該ガイドは、本仕様書の変更に合わせて随時アップデートし、著者が CLI 操作と `_index_glossary_review.md` 編集手順を迷わないようにする。

4. **CLI の整理**
   * 旧 `vs glossary` コマンドは即時削除し、索引系フロー（`vs index:auto` → `_index_glossary_review.md` 編集 → `vs index:apply` → `vs build`）へ統合する。

---

## 9. 実装上の考慮事項

### 9.1 `_index_glossary_review.md` パーサーとデータ構造

* インデント（スペース 2 つ以上）で説明文を抽出し、次の `- [` 行までを範囲として扱う。Markdown のコードブロックや引用と衝突しないよう、ブロック種別を判定する。
* `-i` / `-g` / `-ig` フラグを `[i]` / `[g]` / `[r]` と同列に解析し、索引・用語集それぞれの許可/拒否を判定する状態遷移表を実装する。
* `glossary_terms.yml` には `backlink_sources`（章番号・出現序数の配列）を保存し、`_index_matches.yml` と同じフォーマットで統一しておく。
* `index_glossary_rejected.yml` には `kind`（index / glossary / both）を付与し、復活時の戻し先を判別できるようにする。

### 9.2 リンク自動化の詳細

* 本文側アンカーは `gls-src-<chapter>-<occurrence>` 形式で発行し、章ごとに出現回数をカウントしてから ID を割り振ることで衝突を避ける。
* Vivliostyle の `target-counter()` は PDF 生成時のみ有効なため、HTML プレビューでは `_index_matches.yml` のファイル名＋行番号などデバッグ用の補助表示を用意する。
* `<dfn>` / `<span>` と `<a class="glossary-link">` のネスト順序を決め、CSS セレクタや Vivliostyle のレンダリングに影響しない構造をドキュメント化する。

### 9.3 バリデーションとエラーハンドリング

* `require_definition: true` の場合、`vs index:apply` で説明文が空だった用語名と行番号をエラー出力に含め、著者が即座に修正できるようにする。
* `max_definition_length` のチェックはレンダリング後の文字数を基準とし、Markdown の装飾を除去した結果で評価する。

### 9.4 既存機能との統合

* `vs index:auto` の `IndexCandidateExtractor` に「〜とは」検出ロジックを追加する際、否定表現（「〜とは限らない」など）を誤検出しないよう前後文脈を解析する。
* `vs index:apply` では `i` / `g` / `ig` / `-i` / `-g` / `r` の組み合わせごとに辞書更新手順を明示し、状態遷移図を作成して実装する。
* Pre-process / Post-process が `<dfn>` / `<span>` を挿入する箇所にリンクを追加する際、HTML 構造が壊れないかを既存テンプレートで検証する。

### 9.5 テスト計画補足

1. `_index_glossary_review.md` パーサー単体テスト（説明文抽出・フラグ判定）。
2. `glossary_terms.yml` 更新テスト（`backlink_sources` の保存とリジェクト処理）。
3. `_glossarypage.html` 生成テスト（アンカー ID / 戻りリンク / ページ番号表記）。
4. Pre-process で本文リンク（`†` 記号）を挿入するテスト。
5. Vivliostyle ビルドを含む統合テスト（PDF 内でのリンク遷移確認）。
6. エッジケース: 同一用語が 10 回以上登場する章、説明文に表/リストが含まれる場合、複数読みの用語などをカバーする。

### 9.6 ドキュメントとマイグレーション

* 著者向けガイド（`book-vivlio-starter/20-indexing.md`）には `_index_glossary_review.md` のサンプルやインデントルール、フラグの使い分け図を掲載する。
* `vs glossary` 削除に伴い、Samovar コマンド定義・README・`--help` の記述を一括更新し、`git grep "vs glossary"` で残骸が無いかチェックする。



