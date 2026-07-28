# `vs metrics` 章別「表現が単調／やや難解」警告 仕様書

> 作成日: 2026-07-12
> ステータス: **確定仕様・未着手**
> 対象: PLANNED.md [Medium]「`vs metrics` の章別『表現が単調／やや難解』警告」。`labels.monotonous`/`too_complex`（本機能のために用意されたキー・現状は詳細分析の表示文言のみ）を、分量警告（`too_short`/`too_long`）と同様に章別リストの警告ラベルへ昇格させる
> 決定事項（PLANNED の要設計 3 点への回答）:
> - **(1) しきい値: 専用のしきい値は設けない**。「詳細分析が『表現が単調』『やや難解』と評価する条件と**完全に同一の条件**」で警告を発火させる（単一の真実。二重のしきい値は必ず乖離事故を生む）。具体的には monotonous = MATTR の既存バンド（formatter.rb:341 の `..0.5`）、too_complex = 建石式 RS ラベルが `Professional`（= score < `metrics.readability.standard`・既定 40）。**RS 側の調整は既存キーで可能なため新設定キーはゼロ**
> - **(2) 統合点: `WarningChecker` に `quality_warnings(analysis)` を新設**する。分量警告（`ChapterParser` 段階・文字数のみで算出）と品質警告（`ChapterAnalysis` 段階・MATTR/RS が必要）は**算出タイミングが構造的に異なる**ため、chapter 構造体の `warning` フィールドへは統合せず、表示時に合成する（§2.2）
> - **(3) 誤検知対策: exclude_chapters（既存ガード流用）＋統計的安定性ガード**（MATTR は総トークン数が `mattr_window` 未満の章、RS は 10 文未満の章では発火させない・§2.1）
> - **警告はキャッシュに保存しない**（表示時に毎回算出）。しきい値・labels 変更が再解析なしで即反映され、キャッシュ `schema_version` にも触れない
> 関連: `lib/vivlio_starter/cli/metrics/formatter.rb:341`（MATTR バンド `..0.5` → monotonous）・`:349-357`（RS Professional → too_complex）・`:361-412`（`WarningChecker`・`has_warning?`:383）・`:149-158`（`format_chapter_line` の警告表示）, `lib/vivlio_starter/cli/metrics/runner.rb:91`（章別リスト出力・analysis が手元にある）・`:512-521`（`--warn` フィルタ `analysis_visible?`）・`:777`（構造化出力 `analysis_to_stat_hash`）, `lib/vivlio_starter/cli/metrics/config_loader.rb`（`DEFAULT_LABELS`・`readability_thresholds`:95・`mattr_window`:90・`exclude_chapters`:79）, `lib/vivlio_starter/cli/metrics/chapter_parser.rb:42`（分量警告の算出点）

## 0. 背景・現状

- 章別リストの 🟡 警告は**分量のみ**: `ChapterParser.parse`（chapter_parser.rb:42）が文字数から `too_short`/`too_long` を判定し chapter 構造体の `warning` に格納 → `format_chapter_line`（formatter.rb:151）が表示
- 語彙多様度（MATTR）と読解難度（建石式 RS）は後段の `Runner#analyze_chapter` が `ChapterAnalysis`（vocab / readability）として算出。`monotonous`/`too_complex` のラベル文言は**詳細分析の評価文**（`mattr_evaluation`・`readability_description`）にだけ現れ、章別リストには出ない
- そのため「どの章が単調か／難解か」を知るには章ごとの詳細を目視で追う必要がある。分量警告と同じ一覧性を与えるのが本機能

## 1. 著者向け仕様

### 1.1 章別リストの表示

```
📚 章別の解析結果
   10 はじめに        ████████░░  8,234 文字
   21 画像            ██████████ 15,890 文字 🟡 やや長い・表現が単調
   35 数式            ████░░░░░░  4,120 文字 🟡 やや難解
```

- 分量警告と品質警告は `・` で連結して同じ 🟡 行に表示（章単位・最大 3 ラベル）
- 発火条件（詳細分析の評価と**常に一致**する）:

| ラベル | 条件 | 調整方法 |
|---|---|---|
| `表現が単調`（monotonous） | 章の MATTR ≤ 0.5（詳細分析で「表現が単調」と評価される帯） | 文言は `metrics.labels.monotonous`。帯は固定（§5） |
| `やや難解`（too_complex） | 章の建石式 RS ラベルが Professional（score < `metrics.readability.standard`） | しきい値は既存 `metrics.readability.standard`（既定 40）、文言は `metrics.labels.too_complex` |

- **発火しない章**（誤検知対策）:
  - `metrics.exclude_chapters`（既定 `[00, 90-98, 99]`）の章——分量警告と同じ既存ガード
  - 総トークン数が `metrics.mattr_window`（既定 100）未満の章は monotonous を判定しない（窓に満たない短文の MATTR は不安定）
  - 10 文未満の章は too_complex を判定しない（数文の RS は不安定）
- 節（section）には品質警告を出さない（MATTR/RS は章単位でのみ算出している。節単位は母数不足で誤検知源になる・§5）

### 1.2 `--warn` フィルタとの統合

`vs metrics --warn` が品質警告のみの章も拾うようになる（現状は分量警告章のみ）。「単調・難解と評価された章だけを一覧して推敲対象を決める」ワークフローが成立する。

### 1.3 構造化出力（`--json` / `--yaml`）

各章の `stats` エントリに `warnings` 配列を**追加**する（既存キーは不変・後方互換）:

```json
{ "path": "contents/21-images.md", "chars": 15890, …,
  "warnings": ["やや長い", "表現が単調"] }
```

警告なし・除外章は空配列（「常にキーを備える」の既存方針・runner.rb:719 のコメントに従う）。

## 2. 実装

### 2.1 `WarningChecker#quality_warnings`（formatter.rb:361 のクラスに追加）

```ruby
# 品質警告（語彙多様度・読解難度）を判定する。分量警告と違い
# ChapterAnalysis（vocab/readability）が必要なため、表示時に呼ぶ。
# 発火条件は詳細分析の評価バンドと同一（metrics-quality-warnings-spec §1.1）。
# @param analysis [Runner::ChapterAnalysis]
# @return [Array<String>] 該当ラベルの配列（該当なし・除外章は空）
def quality_warnings(analysis)
  return [] if excluded?(analysis.chapter.chapter_num)

  warnings = []
  warnings << labels[:monotonous] if monotonous?(analysis.vocab)
  warnings << labels[:too_complex] if too_complex?(analysis.readability)
  warnings
end

private

# MATTR が「表現が単調」帯（詳細分析と同一バンド）。
# 窓に満たない章は MATTR が不安定なため判定しない。
def monotonous?(vocab)
  vocab.total_tokens >= @mattr_window && vocab.mattr <= Formatter::MATTR_MONOTONOUS_MAX
end

# 建石式 RS が Professional（= readability.standard 未満）。
# 文数が少ない章は RS が不安定なため判定しない。
MIN_SENTENCES_FOR_COMPLEXITY = 10

def too_complex?(readability)
  readability.sentences >= MIN_SENTENCES_FOR_COMPLEXITY && readability.label == 'Professional'
end
```

- コンストラクタで `@mattr_window = config_loader.mattr_window` を追加取得
- **バンドの単一定義**: formatter.rb:341 の `in ..0.5` を定数 `MATTR_MONOTONOUS_MAX = 0.5` に抽出し、`mattr_evaluation` と `monotonous?` の双方が参照する（表示文言と警告の乖離を構造的に防ぐ——本仕様の決定事項 (1) の実装形）
- too_complex 側は `Readability.label(score, thresholds)` の結果（`ChapterAnalysis.readability.label`）を参照するだけ——しきい値は `readability_thresholds` 経由で既に一元化されている
- `readability` 構造体に文数が無い場合は `analysis.basic.sentences` を使う（実装時に `ChapterAnalysis` のフィールド構成を確認し、`quality_warnings(analysis)` 内で `analysis.basic` から取るのが素直なら引数を analysis のままにして内部で分配する）

### 2.2 表示への合成（runner / formatter）

品質警告は chapter 構造体の `warning`（分量・chapter_parser.rb:42 で確定済み）へは**書き戻さない**。表示直前に合成する:

- `runner.rb:91` / `output_chapter_line`（:462）: `analysis` が手元にあるので
  `formatter.format_chapter_line(chapter, max_chars, show_sections?, extra_warnings: warning_checker.quality_warnings(analysis))` へ拡張
- `formatter.rb:149` `format_chapter_line`: `extra_warnings: []` キーワードを追加し、
  `all = [chapter.warning, *extra_warnings].compact` → `warning = all.empty? ? '' : " 🟡 #{all.join('・')}"`
  （節側 `sec_warning` は従来どおり分量のみ・変更なし）

### 2.3 `--warn` フィルタ（runner.rb:512 `analysis_visible?`）

`has_warning?`（formatter.rb:383）に `analysis:` キーワードを追加:

```ruby
def has_warning?(chapter_num, chars, sections, analysis: nil)
  return true if chapter_warning(chapter_num, chars)
  return true if analysis && quality_warnings(analysis).any?

  sections.any? { section_warning(it.chars, chapter_num:) }
end
```

呼び出し元（runner.rb:518）は `analysis:` を渡すだけ（chapter_num 等は従来どおり——既存テストへの影響を最小化するため位置引数は変えない）。

### 2.4 構造化出力（runner.rb:777 `analysis_to_stat_hash`）

```ruby
basic_stats_to_structured_hash(basic).merge(
  'path' => chapter.path,
  'warnings' => [chapter.warning, *warning_checker.quality_warnings(analysis)].compact
)
```

### 2.5 キャッシュとの関係（変更なしの確認）

品質警告は `ChapterAnalysis` の既存フィールド（vocab.mattr / vocab.total_tokens / readability.label / basic.sentences）だけから毎回導出する。キャッシュ（`.cache/metrics/{章}.yml`・schema v2）には**一切保存しない**ため、schema_version 変更・キャッシュ無効化は発生しない。`metrics.readability.standard` や `labels.*` を変えた著者は再解析なしで新しい警告を得る。

## 3. テスト

Minitest・ruby-coding-rules skill 適用。`test/vivlio_starter/cli/metrics/` 配下。

1. **`formatter_test.rb`（WarningChecker）**:
   - monotonous: MATTR 0.45／tokens ≥ window → 発火。MATTR 0.55 → 非発火。**境界 0.5 → 発火**（`..0.5` と `<= MATTR_MONOTONOUS_MAX` の一致確認）。tokens < window → 非発火
   - too_complex: label 'Professional'／sentences ≥ 10 → 発火。'Standard' → 非発火。sentences 9 → 非発火
   - 両方同時 → 2 ラベル。exclude_chapters の章（'00' 等）→ 空配列
   - `has_warning?(…, analysis:)`: 分量なし・品質ありで true／analysis: nil で従来挙動
   - `format_chapter_line`: `extra_warnings` が `・` 連結で 1 つの 🟡 に載る／分量警告のみ・品質のみ・両方・なしの 4 態
   - **表示との一致（回帰ゲート）**: `mattr_evaluation` が `labels[:monotonous]` を返す MATTR 値でのみ `monotonous?` が真になること（バンド定数の共有を固定）
2. **`runner_test.rb`**:
   - `--warn` で品質警告のみの章が一覧に残る／警告なし章が消える
   - 構造化出力: stats 各章に `warnings` キーが常に在り、該当章に文言が入る・既存キー不変
3. **`config_loader_test.rb`（追加不要の確認）**: `labels.monotonous` のカスタム文言が警告表示に反映される（既存 labels マージ機構の消費テストとして 1 ケース）

## 4. 手順（実装順序）

1. `MATTR_MONOTONOUS_MAX` 定数抽出（挙動不変・単独コミット可）
2. `WarningChecker#quality_warnings` ＋テスト 1
3. 表示合成（§2.2）・`--warn`（§2.3）・構造化出力（§2.4）＋テスト 2
4. ドキュメント: `contents/` の metrics 章（警告の種類一覧に 2 ラベルを追記・発火条件と調整キーを明記）→ `ruby copy_to_scaffold.rb`
5. `rake test` ＋ 実プロジェクトで `vs metrics` / `vs metrics --warn` / `--json` の目視確認

## 5. スコープ外・設計判断の記録

- **MATTR バンドの設定キー化**（`metrics.mattr_bands` 等）: 見送り。バンドは実用書原稿の実測分布で較正した値（formatter.rb:339 コメント）であり、RS と違って著者が対象読者別に動かす動機が薄い。要望が出たら config-extension-guidelines の 3 ステップで追加（その際も警告と表示は同一値を参照する構造を維持すること）
- **節単位の品質警告**: 対象外。MATTR/RS は章単位でのみ算出しており、節の母数（数百字）では両指標とも不安定
- **「平易すぎる」側の警告**（RS が easy 超・MATTR 非常に豊富）: 対象外。推敲で直すべき欠点ではない（対象読者次第の特性）
- **語彙難度（漢字比率・平均語長）の警告化**: 対象外。`difficulty_evaluation`（formatter.rb:328）の「やや難解」は語彙難度の 5 段階評価で、本件の too_complex（読解難度 RS）とは別指標。両方を警告にするとラベル文言が衝突して紛らわしいため、警告は RS 側に一本化する（詳細分析では従来どおり両方見られる）
