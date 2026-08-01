# 索引語の選別仕様書 — スコアの是正・閾値の規模非依存化・一般語の除外提案

> 作成日: 2026-08-02
> ステータス: **実装待ち**
> 対象: 「どの語を索引に載せるか」の決まり方。スコア式（`IndexCandidateExtractor`）、採否の閾値、登録済み語の見直し導線
> 前提: `index-code-protection-unification-spec.md` を先に実装すること（タグ付け結果が変わるため、混ぜると切り分けができない）
> 決定事項:
> - **スコアは出現由来の派生データである**。辞書には永続化せず、実行のたびに導出する（`index-glossary-consistency-spec.md` §0 の原則の延長。`backlink_sources` を辞書から外したのと同じ扱い）
> - 現行スコアは **TF を三重に計上**しており、「頻出＝高スコア＝自動承認」になっている。ボーナスを出現ごとの加算から**語ごと 1 回**へ改め、TF-IDF 本体も**対数 TF**にする
> - 採否の閾値は**絶対値から順位比率へ**移す。絶対値は書籍の規模・語彙量に依存して破綻する（既存の `high_candidates_ratio` と同じ思想）。旧キーが書かれていればそちらを優先し、既存 `book.yml` はそのまま読める
> - 本の広い範囲に散らばる語（**一般語**）は、レビューファイルで `[-i]` を**あらかじめ付けた状態**で提示する。外すか残すかの判断は著者が行う（自動では外さない）
> - 「広さ」の判定は**章数の比率**で行う。絶対章数だと薄い本と厚い本で意味が変わる
> 関連: `lib/vivlio_starter/cli/index/index_candidate_extractor.rb`, `scoring_engine.rb`, `unified_index_manager.rb`, `unified_terms_manager.rb`, `review_markdown_generator.rb`, `config/book.yml`, `index-main-reference-spec.md`（本仕様の `TermSpread` を使う）

## 0. 背景 — 索引の質は「載せる語」で決まる

索引の使い勝手は「参照の出し方」より前に「**どの語を載せるか**」でほぼ決まる。
「ファイル」「ページ」「コード」が索引にあれば、どれだけ体裁を整えても読者は引けない。

本書はその選別を扱う。参照の出し方（主要参照・太字・ページ範囲）は
`index-main-reference-spec.md` の担当で、**本仕様を先に入れる**——語が絞られてはじめて、
主要参照を指定すべき語の数が現実的になるためである。

## 1. 現状の実装事実（2026-08-02 実測・全 27 章 / 索引語 153 語）

### 1.1 レビュー帯が空である

| 帯 | 語数 |
|---|---|
| `score >= 300`（自動承認） | **127 語** |
| `150 <= score < 300`（レビュー対象） | **0 語** |
| `score < 150` | 26 語（すべて score 0 ＝ ライブラリ取込・手動マークアップ由来） |

スコアの中央値は 469、最大 7,728。`auto_approve_threshold: 300` は
**実質すべてを自動承認する値**になっており、著者が選別する機会が存在しない。

### 1.2 原因 — TF が三重に計上されている

スコアは 4 つの経路で加算されるが、**そのうち 3 つが出現ごとの加算**である。

| 経路 | コード | 加算 |
|---|---|---|
| 定義パターン | `index_candidate_extractor.rb:157` | `@term_scores[term] += 30` を **`scan` の各マッチで** |
| 専門用語パターン | 同 `:179` | `+= 15` を **各マッチで** |
| 名詞連続 | 同 `:231` | `+= 10` を **各出現で** |
| TF-IDF | 同 `:255` | `tfidf = tf * idf * 5` を**文書ごとに合算** ＝ `5 * idf * Σtf` |

4 経路すべてが出現数に線形なので、**スコアはほぼ出現数の写し**になる。
「専門用語パターン」はカタカナ 3 文字以上にも当たるため、「ファイル」は
371 回 × 15 = 5,565 点をここだけで得る。

結果、スコア上位は索引語として最悪の語で占められる:

```
PDF 7728 / ファイル 5269 / ビルド 3301 / コマンド 3153 / EPUB 3126 / ページ 2873 …
```

逆に索引語として優秀な「特殊相対性理論」「形態素解析」「ニュートン」は score 0 である
（自動抽出では拾われず、手で入れた語）。**索引語としての価値とスコアが逆相関している。**

### 1.3 語の広がり（実測）

| 出現章数 / 全章数 | 語数 | 性格 |
|---|---|---|
| **0.50 以上** | **20 語** | ファイル(23/27), Markdown(22), コマンド(21), ビルド(20), コード(20), PDF(20), プロジェクト(19), ページ(19), 技術書(17), インストール(17), データ(17), オプション(16), ディレクトリ(16), ブロック(16), コードブロック(15), スタイル(15), ツール(15), 章番号(14), Ruby(14), レイアウト(14) |
| 0.33 以上 0.50 未満 | 38 語 | 主要参照の指定が要る帯（`index-main-reference-spec.md` の担当） |
| 0.33 未満 | 95 語 | そのままで索引として機能する |

上の 20 語の大半は、**索引から外すべき語**である（「Markdown」「PDF」のように
本の主題そのもので残したい語も混ざるため、自動では外さない）。

## 2. 設計原則 — スコアは派生データ

`index-glossary-consistency-spec.md` §0 は、辞書を「**語彙の一次データ**」（語・読み・flags・
定義・承認状態）に限り、**出現情報は原稿から毎回導出する**と定めた。
`backlink_sources` を辞書から外したのはこの原則による。

`score` は出現回数と出現章数から算出される、まぎれもない**出現情報**である。
にもかかわらず辞書に永続化されており（`unified_terms_manager.rb:279`）、
原稿を推敲してもスコアは古いまま残る。`context` が stale 化したのと同じ構造である。

したがって本仕様では **`score` を辞書から外す**。副次的な利点として、
スコア式を変えても**移行問題が起きない**（旧スケールの値が残らない）。

## 3. 要件

### R1: ボーナスを「出現ごと」から「語ごと 1 回」へ

`extract_definition_patterns!` / `extract_technical_terms!` / `process_noun_sequence` の
加算を、その語について**一度だけ**にする。

```ruby
# 各抽出メソッドは「この語にこの性質がある」という事実だけを記録する
@term_flags[term] << :definition   # Set
@term_flags[term] << :technical
@term_flags[term] << :noun_sequence
```

集計時に一度だけ重みを掛ける:

```ruby
BONUS = { definition: 30, technical: 15, noun_sequence: 10 }.freeze
bonus = @term_flags[term].sum { BONUS[it] }
```

**context の記録は現状どおり出現ごとに続ける**（レビュー表示に使うため）。
変えるのはスコアへの加算だけである。

### R2: TF-IDF を対数 TF にする

```ruby
# 現行（index_candidate_extractor.rb:240-263）
#   @documents.each_value { tf = ...; @term_scores[term] += tf * idf * 5 }
#   ＝ 5 * idf * Σtf （TF に線形）
#
# 新
def calculate_tfidf_scores!
  return if @documents.empty?

  doc_count = @documents.size
  @term_scores.each_key do |term|
    tf = @documents.each_value.sum { it.scan(term).size }
    next if tf.zero?

    df  = @documents.each_value.count { it.include?(term) }
    idf = Math.log((doc_count + 1.0) / (df + 1.0)) + 1.0
    @term_scores[term] += (1 + Math.log(tf)) * idf * TFIDF_SCALE
  end
end
```

`TFIDF_SCALE` の既定は **30**。実データ（全 27 章 / 索引語 153 語）でのシミュレーション結果:

| | 新スコア | (tf, df) |
|---|---|---|
| アインシュタイン | **429** | (70, 4) |
| CommonMark | 405 | (15, 1) |
| 物理学 | 366 | (16, 2) |
| 用語集ページ | 353 | (14, 2) |
| … | | |
| コード | 232 | (151, 20) |
| コマンド | 231 | (182, 21) |
| プロジェクト | 228 | (108, 19) |
| Markdown | 208 | (122, 22) |

順位が正しく反転する（分布: min 109 / p25 249 / median 282 / p75 308 / max 429）。

**注意**: `ScoringEngine`（`scoring_engine.rb`）は同種の重み表を持つが、
`IndexCandidateExtractor` からは使われていない（`@term_scores` への直接加算のみ）。
本仕様では **`ScoringEngine` を正典化して `IndexCandidateExtractor` から使う**形に寄せ、
重み・スケール定数の定義箇所を 1 つにする。二重管理は `PLANNED.md`「既定値の二重管理」で
既に事故が報告されている形なので、ここで潰しておく。

### R3: 採否の閾値を順位比率へ

絶対値の閾値は、書籍の規模・語彙量・章数で意味が変わる。実際 §1.1 のとおり
既定値 300 は本書ではまったく機能していない。既存の `high_candidates_ratio: 0.25` が
既に比率で切っているので、そちらへ揃える。

```yaml
index:
  # 候補をスコア順に並べたときの位置で採否を決める（規模に依存しない）
  auto_approve_ratio: 0.10   # 上位 10% は自動承認
  review_ratio: 0.60         # 上位 60% までをレビュー対象（10%〜60% が対象帯）
  high_candidates_ratio: 0.25 # 既存: レビュー対象のうち上位 25% を「推奨候補」へ
```

判定順序（`unified_index_manager.rb:59-60` を差し替える）:

1. `auto_approve_threshold` が `book.yml` に**明示されていれば**絶対値で切る（旧挙動）
2. なければ `auto_approve_ratio` で切る
3. `review_threshold` / `review_ratio` も同様

**比率既定値の確定は R6 の実測後に行う**。上の 0.10 / 0.60 は暫定値であり、
候補総数の実測（`vs index:auto --dry-run`）を見てから確定する。
候補総数が数千件なら 10% でも数百語が自動承認されてしまうため、
実測なしに既定値を決めてはならない。

**提示しなかった候補は黙らせない**（`no silent caps`）:

```
ℹ️ スコア下位 1,842 件は候補として提示していません（review_ratio: 0.6）
   すべて見るには book.yml の index.review_ratio を上げてください
```

### R4: `score` を辞書から外す

- `unified_terms_manager.rb`
  - `build_term_entry`: `entry['score'] = term['score'] if term['score']` を**削除**
  - `merge_term_data`: `merged['score'] = …` を**削除**
  - `save_terms!`: `it.except('backlink_sources')` → `it.except('backlink_sources', 'score')`
    （旧辞書に残る値を保存の機会に黙って捨てる。R3 の前例と同じ扱い）
- `unified_index_manager.rb#enrich_terms_with_context`: 候補側で算出したスコアを
  表示用に合流させる（`candidates.find { it['term'] == term['term'] }&.dig('score')`）。
  原稿から消えた語はスコアが取れないので `- [出現なし]` と表示する
- レビュー md の表示は現状の書式のまま（`- スコア: 429.0`）

### R5: 一般語を `[-i]` 付きで提示する

#### 5.1 判定 — `TermSpread`

新設: `lib/vivlio_starter/cli/index/term_spread.rb`

```ruby
# 語が本のどれだけ広い範囲に散らばっているかを測る。
# 索引語としての価値は「広く出ること」ではなく「特定の箇所で説明されていること」なので、
# spread が大きい語ほど索引項目としては引きにくい。
#
# 判定は章数の比率で行う。絶対章数だと 5 章の薄い本と 50 章の本で意味が変わる。
TermSpread = Data.define(:term, :chapter_count, :total_chapters) do
  def ratio = total_chapters.zero? ? 0.0 : chapter_count.fdiv(total_chapters)
end
```

- 数え方は辞書の `pattern`（無ければ語の完全一致）を各章の本文へ当て、**1 章 1 回**と数える
- 本文は `CodeBlockStripper.strip` を通す（コード例の出現で膨らませない）
- **章数の下限**: 全章数が `MIN_CHAPTERS_FOR_SPREAD = 6` 未満の本では判定しない。
  5 章の本では 3 章に出るだけで比率 0.6 になり、誤検出しかしない
- **絶対下限**: `chapter_count < 3` の語は比率がいくつでも一般語としない

#### 5.2 提示 — レビュー md のサブセクション

`## 1. 登録済み用語の確認` の**内側**に置く。セクション番号を増やさないので、
`review_markdown_generator.rb` の既存パーサ（`## 4. 除外済みリスト` を境界に使う実装）に
影響しない。

```markdown
## 1. 登録済み用語の確認 (Terms: 153語)

### 一般語（索引から外すことを推奨・20語）

本の広い範囲に散らばっている語です。索引から引いても読者が「どこを読めばよいか」を
判断できないため、外すことを推奨します。
- 外す場合: [-i] のまま `vs index:apply`
- 残す場合: [i] に戻したうえで `主要参照:` を指定してください（未指定だとビルド時に警告されます）

- [-i] **ファイル** (ふぁいる) - 一般語: 23/27 章（85%）に出現
- [-i] **Markdown** (まーくだうん) - 一般語: 22/27 章（81%）に出現
…

### 登録語 (133語)

- [i] **アインシュタイン** (あいんしゅたいん) - スコア: 429.0
…
```

**行の書式は既存と同一**にする。追加情報は `- スコア: …` と同じ**行末の位置**へ置く
——`- [-i] ` と `**用語** (読み)` の間に何かを差し込むと、
`parse_index_rejected` ほか 6 つのパーサの正規表現
（`^- \[-i\](?: \`(?:NEW!|Today)\`)? \*\*(.+?)\*\* \(([^)]+)\)`）が**軒並みマッチしなくなる**。

`[-i]` は `parse_index_rejected` が拾い、`apply_markdown_review!` が
`remove_flag!(term, 'i')` ＋ `save_rejected_terms` を行う。**既存経路がそのまま使える**ので、
`apply` 側の変更は不要である。

#### 5.3 自動では外さない

「Markdown」「PDF」は本書の主題そのもので、著者が残したい語でありうる。
判断は著者に委ねる——`quantity-is-not-necessity` と同じ立場で、
機械は「広く散らばっている」という事実だけを示し、価値判断はしない。

### R6: `vs index:auto --dry-run`

辞書を書かずに、候補抽出とスコアリングの結果だけを表示する。

```
$ vs index:auto --dry-run
候補抽出: 2,431 件
スコア分布: min 88 / p25 190 / median 244 / p75 291 / max 429

  自動承認となる帯 (上位 10%):    243 件  スコア >= 305
  レビュー対象の帯 (10%〜60%):  1,215 件  スコア 221 〜 305
  提示しない帯     (下位 40%):    973 件  スコア < 221

一般語（登録済み 153 語のうち）: 20 語
  ファイル(23/27) Markdown(22/27) コマンド(21/27) …

※ --dry-run のため辞書・レビューファイルは変更していません
```

- `auto_process!` に `dry_run:` を足し、`merge_terms!` / `record_scanned_chapters!` /
  `@markdown_generator.generate!` をスキップする
- **R3 の比率既定値はこの出力を見てから確定する**
- 著者にとっても、閾値をいじった効果を辞書を壊さずに試せる導線になる

## 4. `book.yml` スキーマ差分

```yaml
index:
  auto_discovery: true
  title: "索引"

  # 採否（順位比率・規模非依存）
  auto_approve_ratio: 0.10
  review_ratio: 0.60
  high_candidates_ratio: 0.25

  # 一般語の判定（章数の比率）
  common_term_ratio: 0.50

  # 旧キー（書かれていれば比率より優先・後方互換）
  # auto_approve_threshold: 300
  # review_threshold: 150
```

`common.rb` の CONFIG スキーマ（`:247`）へ
`auto_approve_ratio` / `review_ratio` / `common_term_ratio` を追加する。
`PLANNED.md`「既定値の二重管理」の指摘どおり、**既定値はコード側（スキーマ）を正とし、
同梱 `book.yml` はサンプル値**という役割分担を守る。

## 5. テスト

### 5.1 単体

| 対象 | 検証 |
|---|---|
| `IndexCandidateExtractor` | 同じ語が定義パターンに 5 回当たってもボーナスは 30 点 1 回だけ（R1） |
| 同上 | tf=100/df=1 の語が tf=400/df=20 の語より高スコア（R2 の反転を固定する） |
| `ScoringEngine` | 重み表が唯一の定義元であること（extractor が独自定数を持たない） |
| `TermSpread` | 比率計算・全章数 6 未満で判定しない・`chapter_count < 3` を除外・コード内の出現を数えない |
| `UnifiedTermsManager` | `save_terms!` が旧辞書の `score` を落とす／`build_term_entry` が `score` を書かない（R4） |
| `UnifiedIndexManager` | 絶対値キーが書かれていれば比率より優先される（R3 の後方互換） |
| `ReviewMarkdownGenerator` | 一般語サブセクションの行が `parse_index_rejected` で拾える（R5.2 の書式固定） |

### 5.2 回帰

- 既存の `unified_index_manager_test.rb` / `review_markdown_generator_test.rb` が
  スコア値をハードコードしている箇所は、**順位の検証へ書き換える**（絶対値は本仕様で変わる）
- `rake test` と `rake test:standard` の両方

### 5.3 実データでの受け入れ確認

1. `vs index:auto --dry-run` で分布を確認し、R3 の既定値を確定する
2. 確定後に `vs index:auto` → 一般語 20 語の提示を目視 → 残す語を `[i]` へ戻す
3. `vs index:apply` → 辞書の索引語が 153 → 130 前後になること
4. `vs build` → 索引ページの `<dt>` 数がそれに一致すること

## 6. 実装フェーズ

| Phase | 内容 | 検証 |
|---|---|---|
| 1 | R6 `--dry-run` を先に入れる | 現行スコアの分布が見える（次フェーズの土台） |
| 2 | R1 + R2（スコア式）+ `ScoringEngine` 正典化 | 単体テスト。`--dry-run` で反転を確認 |
| 3 | R3（比率化）— 既定値は Phase 2 の実測で確定 | 後方互換テスト |
| 4 | R4（`score` を辞書から外す） | 辞書 diff で `score:` が消えること |
| 5 | R5（`TermSpread` ＋ 一般語提示） | 実データ受け入れ（§5.3） |

Phase 1〜4 は辞書の内容を変えない（`--dry-run` と表示・保存形式のみ）。
辞書が実際に痩せるのは Phase 5 の `apply` 実行時である。

## 7. 完了時の作業

- `PLANNED.md` から「提案 E / 提案 D / 閾値調整」に相当する記述を削除する
- 本ファイルを `docs/archives/` へ `git mv` し、`STATUS.md` の該当行を削除する
- `contents/33-index-glossary.md` に「一般語の提示」「スコアの意味」の解説を追記し、
  `ruby copy_to_scaffold.rb` で雛形へ同期する
