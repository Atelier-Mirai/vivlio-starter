# 索引システム実装仕様書 v3.0

**最終更新**: 2026-01-06  
**ステータス**: 設計完了・実装フェーズ

---

## 1. 概要

### 1.1 目的
著者が執筆に集中し、最小限の確認作業（Markdownの編集）だけで高品質な索引を生成・維持できるワークフローを提供する。

### 1.2 設計方針
- **シングルソース管理**: 確定した用語は `config/index_terms.yml` のみが保持する。
- **直感的なレビューUI**: Markdownのチェックボックスとシンタックスハイライト（バッククォート）を活用。
- **学習型エンジンの導入**: 著者が一度修正した「読み」をシステムが記憶し、次回以降の抽出に再利用する。

---

## 2. ファイル構成と役割

### 2.1 マスターデータ (config/)
- **`index_terms.yml`**: 確定済み用語辞書。手動マークアップ分および承認済み候補をすべて集約。
- **`index_rejected.yml`**: リジェクト済みリスト。自動抽出対象から除外する用語を保持。

### 2.2 作業用・出力ファイル
- **`_index_review.md`**: 著者が編集する唯一のインターフェース。
- **`_index_matches.yml`**: 本文内の出現箇所（章・行・文脈）を保持する。
- **`_indexpage.html`**: _index_matches.ymlを元に最終的に生成される索引ページ。

### 2.3 ファイル構成

```
├── config/
│   ├── index_terms.yml         # 承認済み・確定済みの索引語
│   └── index_rejected.yml      # 二度と候補に出さない用語
├── _index_review.md             # 人間が編集するマークダウン
├── _index_matches.yml           # 単語と出現箇所の対応表
├── _indexpage.html              # _index_matches.ymlから生成された索引ページ
└── project_files...             # pre_process済みの本文原稿（.md）などが自動配備される
```

---

## 3. ワークフロー

1.  **抽出 (`vs index:auto`)**
    - 本文中の手動マークアップ `[用語|読み]` も検出し、`index_terms.yml` に自動登録。
    - 本文中の手動マークアップ `[用語]` も検出し、`index_terms.yml` に自動登録。
    - 本文から候補を抽出する。
        - 候補が既存の `index_terms.yml` に登録されているものであれば、`index_terms.yml` の「修正済みの読み」を優先適用。
        - 候補が新出であれば、MeCabによる読み推測を適用。
    - スコアに基づき「自動承認」「推奨候補」「一般候補」に分類。
    - `_index_review.md` を生成。
    - `_index_review.md`を編集するように促すメッセージを出力して完了。
2.  **確認 (Manual Review)**
    - 著者が `_index_review.md` を開き、新着項目（` `NEW!` `）を中心に確認。
    - 必要に応じて読みを修正、または棄却マーク `[r]` を記入。
3.  **反映 (`vs index:apply`)**
    - Markdownの変更内容を `index_terms.yml` および `index_rejected.yml` に反映。
        (vs index:apply実行時に、索引語と、その読みが決定される)
    - 新出用語については `approved_at`を更新する。（既存の索引語についてはそのまま）
    - 作業ファイルをクリア。

    **注**: `vs index:apply` は内部で `vs index:build` を実行しません。索引ページの更新は次回の `vs build` 実行時に自動的に行われます。
    
4.  **ビルド (`vs build`)**
    - ビルド時に自動的に `vs index:build` が実行され、`_index_matches.yml` と `_indexpage.html` が生成されます。
    - 開発者のデバッグ用に `vs index:build` を手動実行することも可能ですが、利用者には非公開です。

---

## 4. Markdownレビュー仕様 (`_index_review.md`)

### 4.1 視覚的ラベル
シンタックスハイライトを効かせるため、状態をバッククォートで囲む。
- `` `NEW!` `` : 今回の実行で初めて抽出された候補。
- `` `Today` `` : 本日（0:00以降）に承認・追加された用語。

`index_terms.yml` の `approved_at` を見て判定を行なう。
タイムゾーンは `config/book.yml` の `timezone` に従う。

### 4.2 編集ルール
- **`[ ]` → `[x]`**: 用語を承認し、索引に採用する。
- **`[ ]` → `[r]`**: 用語をリジェクトし、以降の自動抽出からも除外する。
- **`(読み)`**: カッコ内のテキストを書き換えることで読みを修正。

### 4.3 リジェクト解除の操作
`_index_review.md` の 「4. 除外済みリスト」セクションで、
`[ ]` → `[r]` にマークすると、
その用語は `index_rejected.yml` から削除され、
次回 `vs index:auto` 実行時に再び候補として表示されます。

---

## 5. ロジック詳細

### 5.1 候補の優先順位付け
レビュー時の負担軽減のため、候補を以下の比率でセクション分けする。
1.  **High Candidates**: レビュー対象のうちスコア上位25%（既定値）。
2.  **Low Candidates**: 残りの75%。

分割比率は `config/book.yml` の `high_candidates_ratio` で調整可能です。

### 5.1.1 分割ロジックの定義

1. **ソート**: 全候補（`review_threshold` 以上 `auto_approve_threshold` 未満）をスコアの降順で並べる。
2. **基準インデックスの算出**: 
   - 基準位置 = `(全候補数 * 0.25).ceil`（切り上げ）
   - ※候補が1〜3件の場合でも少なくとも1件は High に分類される。
3. **境界スコアの決定**: 
   - 境界スコア = [基準位置]番目の候補のスコア
4. **セクション振り分け**:
   - **High Candidates**: スコアが 境界スコア 以上
   - **Low Candidates**: スコアが 境界スコア 未満

**NOTE**: 同スコアの扱い  
境界スコアと同じ値を持つ候補が複数ある場合、それらはすべて High に含める。

**NOTE**: `_index_review.md`への表示順の扱い  
手順1によるソートは、High/Lowのセクション分け算出の為のものであり、`_index_review.md`への表示順とは関係ありません。

`_index_review.md`の表示順は、以下のセクション順で行います:
1. 登録済み用語の確認 (Terms)
2. 推奨候補 (High Candidates)
3. 一般候補 (Low Candidates)
4. 除外済みリスト (Rejected)

それぞれのカテゴリ内では、`NEW!`、`Today`、最初に出現した順に表示します。

### 5.1.2 候補のスコア付け
既存コードによるスコア付けを維持する。(indexing_implementation_spec.md や indexing_implementation_spec2.md参照)

### 5.1.3 設定値の取得

以下の設定値は `config/book.yml` より取得します:

```yaml
# ========================================
# 索引設定
# ========================================
index:
  # 索引機能を有効化
  enabled: true
  
  # 索引ページのタイトル
  title: '索引'
  
  # MeCab による読み自動推測を使用
  use_mecab: true
  
  # 自動承認スコア閾値（この値以上は自動的に index_terms.yml へ追加）
  auto_approve_threshold: 300
  
  # レビュー対象スコア閾値（この値以上でレビュー待ちキューへ）
  review_threshold: 150

  # タイムゾーン (索引レビュー時の新着判定に利用)
  # 既定値: 'Asia/Tokyo'（省略可能）
  timezone: 'Asia/Tokyo'

  # 推奨候補の分割比率（上位何%をHighとするか）
  # 既定値: 0.25（25%）
  high_candidates_ratio: 0.25

  # 文脈抽出の幅（キーワード前後の文字数）
  # 小さな画面なら 20、大画面なら 60 など調整可能
  # 既定値: 40
  context_width: 40

  # 文脈抽出時に形態素境界で賢く文脈を引用するか
  # 既定値: true
  smart_context_cutting: true
```

### 5.2 読みの自動補正

`index:auto` 実行時、以下の優先順位で読みを決定する。
1.  `index_terms.yml` に既に存在する単語の読み（過去の修正が反映済みである）。
2.  MeCab による形態素解析と読み推測。

### 5.3 正規表現の生成
`index_terms.yml` の `pattern` 生成時、`Regexp.escape` を使用し、英単語の場合は `\b`（単語境界）を自動付与する。

---

## 6. データ構造例 (`index_terms.yml`)

```yaml
terms:
  - term: 演算子
    yomi: えんざんし
    pattern: "/演算子/"
    approved_at: '2026-01-06 14:00:00'
    auto_approved: false
    source: manual_markup  # または auto_extracted
```

**`source` フィールドについて**:  
`source` フィールドは以下の用途を想定していますが、現在の実装では未使用です:
- レポート生成時の統計情報
- 手動マークアップと自動抽出の区別
- 将来的な機能拡張のための情報

## 7. `_index_review.md` の出力仕様

### 7.1 基本フォーマット

二回目以降に`vs index:auto`を実行する場合、`index_terms.yml`に登録されている索引語については、著者の利便性向上のため、`[x]`で表示されるようにします。

### 7.2 出力サンプル

```markdown
# 索引レビュー
※ [x]で承認、[r]で棄却。読みの修正は ( ) 内を編集してください。

## 1. 登録済み用語の確認 (Terms: 152語)

- [x] `Today` **演算子** (えんざんし)
  - 09-first-javascript - "変数・演算子・条件分岐・繰り返しといった基本文法"

## 2. 推奨候補 (High Candidates: 12語)

- [ ] `NEW!` **数学者** (すうがくしゃ) - スコア: 223.5
  - 01-computer-journey - "イギリス人数学者チャールズ・バベッジが設計した"
  - 02-person - "イギリスの数学者。詩人バイロン卿の娘であり"

- [ ] `NEW!` **非同期処理** (ひどうきしょり) - スコア: 210.0
  - 15-async - "JavaScriptの強力な武器である非同期処理を"

## 3. 一般候補 (Low Candidates: 35語)

- [ ] **プロトタイプ** (ぷろとたいぷ) - スコア: 185.2
  - 12-object - "プロトタイプ継承という独自のオブジェクト指向"

## 4. 除外済みリスト (Rejected: 28語)
※ 間違えて除外したものは [r] を入れると、候補(Candidates)に復帰します。

- [ ] **処理** (しょり) - スコア: 223.5
  - 05-logic - "〜したとき、処理を中断します。"
- [ ] **こと** (こと) - スコア: 123.5
  - 01-intro - "大切なことは、まず手を動かす"
```

### 7.3 文脈抽出の仕様

- **セクション見出し**: 各セクションに `(XX語)` という形式で件数を表示します。
- **文脈の抽出**: キーワード前後から指定文字数を抽出し、改行文字は除去します。
- **既定値**: 
  - `context_width`: 40文字
  - `smart_context_cutting`: true

#### 7.3.1 `smart_context_cutting` の動作

**`true` の場合（既定値）**:  
たとえ `context_width` を超過する場合でも、形態素境界でカットされます。

例: `「イギリス人数学者チャールズ・バベッジが設計した」`

**`false` の場合**:  
厳密に `context_width` 幅に従い、単語の途中であってもカットされます。

例: `「ギリス人数学者チャールズ・バベッジが設」`

#### 7.3.2 設定のカスタマイズ

`context_width` と `smart_context_cutting` の設定については、§5.1.3 を参照してください。

## 8. コマンド一覧

### 8.1 新コマンド
| コマンド | 主な役割 | 入力 | 出力 |
| --- | --- | --- | --- |
| `vs index:auto` | 抽出・分類・UI作成 | 本文, `index_terms.yml`, `index_rejected.yml` | `_index_review.md`|
| `vs index:apply` | 承認・反映・更新 | `_index_review.md` | `index_terms.yml`, `index_rejected.yml`|
| `vs index:build` | 静的ファイル生成（vs build実行時に呼ばれる内部コマンド扱い。利用者には非開示） | `index_terms.yml` | `_index_matches.yml`, `_indexpage.html` |

`vs index:build` コマンドについては、`vs build` 実行時に呼ばれる内部コマンド扱いです。
index_terms.yml の内容を元に、出現位置を格納している `_index_matches.yml` を生成します。
そして、`_index_matches.yml`を元に索引ページ`_indexpage.html`を生成します。
（デバック時の利便性を図る為、`vs index:build` コマンドを実行することで、索引ページを生成することができますが、利用者には非公開です）

### 8.2 旧コマンドの扱い

以前は以下のようなコマンドが用意されていました:

```
vs index
索引機能のコマンド:
  vs index:auto           - 全自動索引生成（推奨）
  vs index:review         - レビュー待ち候補を確認
  vs index:apply          - レビュー結果を適用
  vs index:rejected       - リジェクト済み一覧
  vs index:unreject       - リジェクト解除
  vs index:reset-rejected - リジェクト履歴クリア

内部コマンド（通常は使用不要）:
  vs index:match          - 手動マークアップをスキャン
  vs index:build          - 索引ページを生成
  vs index:candidate      - 索引候補を抽出
```

**廃止方針**:  
新コマンド（8.1参照）に用意されているものを除き、全て廃止します。後方互換性は不要です。不要となるコードを取り除き、シンプルに保つこととします。

※内部的に必要なコードの使用は許容しますが、外部へは非公開とします。

## 9. クリーンアップとビルドオプション

### 9.1 `vs clean` コマンド

作業用ファイルを削除します。`_`で始まる特殊ファイル（`_titlepage`, `_legalpage`など）と同様に、以下のファイルも削除されます:

- `_index_review.md`
- `_index_matches.yml`
- `_indexpage.html`

### 9.2 `vs build --no-clean` オプション

通常、`vs build` 実行時に `vs clean` が自動的に実行されます。

しかし、索引ページやその他の中間ファイルを残しておきたい場合、`vs build --no-clean` を実行することで、`vs clean` をスキップすることができます。

