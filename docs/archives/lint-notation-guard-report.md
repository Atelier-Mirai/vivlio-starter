# 報告書：lint の記法ガード機構（Notation Guard）

対象: `vs lint`（textlint + スペルチェック）
起票: 2026-07-16（図解注釈記法 `:::{.showcase}` の実装中に判明）
位置づけ: **調査・設計案の報告。実装は未着手**。仕様確定は本書のレビュー後。

> **2026-07-16 追記**: レビュー完了・仕様書へ昇格済み → [lint-notation-guard-spec.md](lint-notation-guard-spec.md)。
> §7 の未決事項はすべて仕様書 §5 で決定した（案 A 採用・`Lint::NotationGuard` 新設・
> `--fix` 修復を Phase 0 として先行）。実装は仕様書を正とする。本書は調査記録として保存。

---

## 1. 要旨

`vs lint` は、原稿中の **VFM 記法（機械データ）を日本語の文として読んでしまう**。
現状これを `config/textlint_allowlist.yml` の「VFM 記法」エントリで抑え込んでいるが、
allowlist は本来「語彙（書籍名・固有名詞）の除外リスト」であり、**記法の抑止に流用するのは
誤用**である。記法を知っているのは lint システム自身なのだから、システム内部で
ガードすべきである。

本書は (1) 現状の実害、(2) allowlist 流用の何が問題か、(3) 既存アーキテクチャに
どう接げばよいか、(4) 設計案 3 つの比較と推奨、(5) 移行手順を報告する。

> **付随して既存バグを 1 件発見した（§4.1）**: `vs lint --fix` は一時ファイルを修正して
> 捨てており、**原稿が一切変更されない no-op** になっている。ガードと同じ前段に絡むため、
> **ガードより先に単独で直すこと**を推奨する。

---

## 2. 実害（実測値・2026-07-16 時点）

### 2.1 図解注釈ブロックの誤検出

`:::{.showcase}` の注釈行は座標とオプションの機械データだが、textlint はこれを地の文として扱う。

```markdown
:::{.showcase}
![バイオリンを弾くアインシュタイン](Einstein.webp)
rect:1 530, 335, 175, 165 {pos=bottom} 愛用のバイオリン
pointer:2 490, 130 {label="白髪"} くしゃくしゃの白髪
:::
```

これに対して出る指摘:

| ルール | 何を誤認したか |
|---|---|
| `japanese/sentence-length` | ブロック全体に句点が無いため**1 文とみなし**、座標込みで文長を数える（実測 125〜173 文字） |
| `ja-technical-writing/max-comma` | **座標のカンマ**を読点として数える（`530, 335, 175, 165` で上限 3 超過） |

実測（現行の原稿 2 章）:

| ファイル | showcase ブロック数 | ブロック内の指摘 |
|---|---|---|
| `contents/22-extentions.md` | 8 | 7 件 |
| `contents/94-sample.md` | 1 | 2 件 |

**合計 9 件。すべて誤検出**（ブロック内に地の文は無く、著者コメントは出力もされない）。
著者が showcase を 1 つ書くたびに 1〜2 件の偽陽性が増える構造で、記法の普及に比例して悪化する。

### 2.2 既に allowlist で抑え込んでいる分

`config/textlint_allowlist.yml` 冒頭の 5 エントリを外して計測すると、上記 2 ファイルで
**指摘が 426 件 → 502 件（+76 件）** に増える。つまり現在 **76 件を allowlist が肩代わり**している。

```yaml
# VFM（Vivliostyle Flavored Markdown）の記法
- ":::"                        # カスタムコンテナの開始/終了
- "/:::$/"                     # ::: で終わる行
- "/^:::\\{/"                  # :::{.class} 形式
- "/\\{[^}]+\\|[^}]+\\}/"      # ふりがな記法 {本文|ふりがな}
- "/\\{\\.[-\\w]+\\}/"         # クラス属性記法 {.classname}
```

これらは「記法を語彙として登録する」ことで誤検出を消しており、症状は消えるが原因は残っている。

---

## 3. allowlist 流用の何が問題か

| # | 問題 | 具体例 |
|---|---|---|
| 1 | **責務違反** | allowlist は「この“語”は正しい日本語として扱え」という語彙辞書。記法は語彙ではない。ファイル冒頭の自己申告（「書籍名、資格名称、専門用語など」）とも食い違う |
| 2 | **利用者へ漏れる** | scaffold で配られ、著者が編集する設定ファイル。著者にとって `"/^:::\\{/"` は意味不明の呪文で、消すと壊れる（何が壊れるかも分からない） |
| 3 | **効きすぎる（グローバル）** | 正規表現がファイル全体・全ルールに効く。`/\{\.[-\w]+\}/` は本文中の `{.aki}` の話をしている**地の文の指摘まで**巻き込んで消す。抑止範囲を記法の出現位置に限定できない |
| 4 | **構造を見ない** | allowlist はマッチした**文字列**を消すだけで、「この行はブロックの中だ」という文脈を持てない。§2.1 の `sentence-length` は**ブロック全体を 1 文と数えた結果**なので、行の一部を allowlist しても文長は縮まらない——実際 §2.1 の 9 件は allowlist では消せていない |
| 5 | **記法追加のたびに増える** | 記法を 1 つ足すたびに、実装とは別の設定ファイルへ「呪文」を追記する運用になる。今回の showcase がまさにその圧力を生んだ |
| 6 | **二重管理** | スペルチェック側は `Masking` で機械的にコードを除外している。同じ「機械データを読ませない」目的が、textlint 側だけ設定ファイルにあり、実装が二本立てになっている |

**結論**: 記法の知識は lint システムの内部に置くべきで、設定ファイルへ逃がすべきではない。
allowlist は本来の用途（書籍名・資格名称などの語彙）に戻す。

---

## 4. 現状のアーキテクチャ（接続点は既にある）

調査の結果、**vs lint は既に「textlint に渡す前に原稿へ手を入れる」段を持っている**。
ガード機構は新しい層を足すのではなく、この既存の段を素直に育てればよい。

```
contents/*.md
   │
   │  ① 前段: Lint#convert_vs_lint_comments  ★ここが接続点
   │       rewrite_vs_lint_to_textlint で <!-- vs-lint-* --> を
   │       <!-- textlint-* --> へ置換し、Tempfile へ書き出す
   ▼
一時ファイル ──► textlint（外部 node プロセス・--format json）
   │                                    │
   │  path_map で元ファイル名へ復元 ◄────┘
   ▼
   │  ② 後段: TextlintFormatter.aggregate_json  ★もう一つの接続点
   │       book.yml の lint.disabled_rules / disabled_terms /
   │       trim_long_vowel に該当する指摘を落として集約
   ▼
表示（ルール単位で「N 件 / 行: …」）

【スペルチェック側】
contents/*.md ──► Lint::Tokenizer ──► Masking.each_prose_line で
                                       コード行を除外して英単語を抽出
```

重要な事実:

- **前段 ①** は既に「原稿を書き換えた一時ファイルを textlint に食わせる」方式。
  ここで記法を中和すれば、textlint 本体にもその設定にも手を入れずに済む。
- **後段 ②** は既に「vs 側の都合で指摘を落とす」責務を持っている（`disabled_rules`）。
  行範囲による除外を足す先としても筋が通る。
- **スペルチェック側**は `Masking`（「コード領域解釈の唯一実装」）に judgement を委ねている。
  記法の知識も同じ場所に置けば、textlint とスペルチェックで**判定が一本化**される。
- `Masking.strip_code` は既に **「フェンスを空行に置換して行数を保つ」** 実装を持つ。
  ガードが必要とする不変条件（後述）は、この既存手法で満たせる。

---

## 4.1 【重要】調査中に発見した既存バグ: `vs lint --fix` が無効

前段①を追ううちに判明した。**`--fix` は一時ファイルを修正して捨てており、著者の原稿は
一切変更されない。** 本件（ガード機構）とは独立した既存バグだが、ガードを同じ前段へ入れる
以上、先に決着させるべきなので報告する。

原因は経路が単純に繋がっていないこと:

```ruby
def run_textlint(files)
  converted_files = convert_vs_lint_comments(files)   # ← 必ず Tempfile を作る（無条件）
  ...
  run_textlint_aggregated(converted_files, path_map)  # ← textlint に渡すのは一時ファイル
ensure
  cleanup_temp_files(converted_files)                 # ← --fix の結果ごと削除される
end

def build_command(files, format: 'json')
  cmd = [textlint_command, '--config', effective_config_path]
  cmd << '--fix' if options[:fix]                     # ← 一時ファイルに対して --fix
  ...
end
```

再現（2026-07-16 実測）:

```bash
$ printf '# テスト章\n\nここに気を付けると良いです。\n詳しくは下さいと書きます。\n' > contents/97-fixtest.md
$ md5 -q contents/97-fixtest.md
190033f06c66b37671a9a76dd920a835

$ vs lint --textlint-only 97
    1件  [prh] 付ける => つける
    1件  [prh] 良い => よい
    1件  [prh] 下さい => ください
💡 そのうち3箇所は自動修正可能です。
   vs lint --fix

$ vs lint --fix --textlint-only 97
    1件  [prh] 付ける => つける      # ← 修正されず、同じ指摘が出続ける
    ...
$ md5 -q contents/97-fixtest.md
190033f06c66b37671a9a76dd920a835     # ← 原稿は 1 バイトも変わっていない
```

- 影響: `--fix` は**完全な no-op**。しかも出力は「自動修正可能です → `vs lint --fix`」と
  案内し続けるため、著者は修正されたと誤認しうる。
- 混入時期: `convert_vs_lint_comments` を含む形になったのは `9a1bfc2b`（2026-05-21・
  名前空間フラット化）まで遡る。それ以前の経路がどうだったかは未調査。

#### 4.1.1 【要注意】既存テストがこのバグを「仕様」として固定している

`test/vivlio_starter/robustness/lint_fix_interrupt_test.rb` が**この挙動を assert している**。
修正時は必ずこのテストの見直しが要る（気づかず「テストが通っているから正しい」と
判断してしまう罠）。

```ruby
def test_original_file_is_untouched_on_normal_completion
  capture_io { LintCommands.execute_lint(['11-target'], fix: true) }
  assert_equal ORIGINAL_CONTENT, File.read(@target_path, encoding: 'UTF-8'),
               # ↑ fix: true なのに「元ファイルが変わらないこと」を期待している
```

ファイル冒頭のコメントも、no-op を**是**として結論づけている:

> 現行実装 (`lib/vivlio_starter/cli/lint.rb`) の `convert_vs_lint_comments` は
> 元ファイルを **一切書き換えず**、…「元ファイルが `textlint-disable` に置換されたまま
> 残る」シナリオは **発生しない**。

**なぜこうなったか**: このテストは堅牢性の観点（5-6-2「`--fix` 実行中に Ctrl+C を受けたら、
元ファイルが `textlint-disable` に置換されたまま残るのでは？」）から書かれている。
その懸念自体は正当で、**中断時に原稿が壊れないこと**は今後も守るべき性質である。
しかし「一切書き換えない」ことを**正常終了時にも**期待してしまったため、
安全性の確認が no-op の固定に化けた。

**修正時の切り分け**:

| テスト | 修正後の期待値 |
|---|---|
| `test_original_file_is_untouched_on_normal_completion` | **要変更**。`fix: true` の正常終了では元ファイルが**修正済みになる**こと。`fix` 無しなら不変のままであること（テストを分けるのが妥当） |
| `test_original_file_is_untouched_when_interrupt_raised` | **維持**。中断時に原稿が壊れない性質は守る |
| `test_original_file_is_untouched_when_standard_error_raised` | **維持**。同上 |
| `test_textlint_receives_tempfile_not_original_path` | **要検討**。ガード（案 A）を入れるなら一時ファイル経由は維持されるが、`--fix` 時にどう書き戻すかで前提が変わる |
- 想定される直し方（未検証）: `--fix` 時は textlint の結果を一時ファイルから読み戻して
  元ファイルへ書く。ただし**ガード（案 A）を入れると一時ファイルは記法が中和済み**なので、
  そのまま書き戻せない。「fix 結果の差分だけを元ファイルへ適用する」か、
  「`--fix` 時はガードを外して素の原稿を直接 fix させる」かの設計判断が要る（§7 論点 1）。
- **本件はガードより先に単独で直すことを推奨**する（別チケット）。ガードの設計が
  `--fix` の直し方に依存するため。

---

## 5. 設計案

### 5.1 不変条件（どの案でも守るべきこと）

| # | 不変条件 | 理由 |
|---|---|---|
| I1 | **行番号が保存されること** | 表示が `行: 418, 491` 形式のため。ガードで行が増減すると全指摘の行番号がずれて実用に耐えない。`Masking.strip_code` と同じ「空行置換」で満たせる |
| I2 | 列番号は保存しなくてよい | `print_textlint_aggregated` はルール名と行番号しか出さない。行内の文字列置換は自由に行える |
| I3 | **地の文は 1 文字も落とさない** | ガードは誤検出を消すためのもので、検査の穴を作ってはならない。特にルビの親文字（`{Albert Einstein\|アルバート…}` の前半）は**地の文であり検査対象**。記法だけを外し、親文字は残す |
| I4 | `--fix` を壊さない | textlint の自動修正は元ファイルに対して行う。ガードが一時ファイルにしか効かないなら、`--fix` 経路ではガードを適用しないか、fix 対象から除外する必要がある（**要検討・§7**） |
| I5 | 記法の知識を 1 箇所に持つ | 記法が増えるたびに複数ファイルを直す状況を作らない |

### 5.2 ガードの対象（記法の分類）

| 分類 | 例 | 扱い | 根拠 |
|---|---|---|---|
| **機械データ・ブロック** | `:::{.showcase}` の `rect` / `pointer` 行 | 行ごと空行化 | 座標とオプション。地の文が無い |
| **コンテナのマーカー行** | `:::{.column}` / `:::` | 空行化 | 記法であって文ではない |
| **インライン記法（親文字あり）** | `{Albert Einstein\|アルバート・アインシュタイン}` | 親文字だけ残す → `Albert Einstein` | 親文字は地の文（I3） |
| **インライン記法（親文字なし）** | `{.aki}` / `{.text-right}` / `{width=50%}` | 除去 | 属性であって文ではない |
| **コード** | フェンス・インラインコード | 既存 `Masking` のまま | 現状で解決済み |

※ コンテナ**内部**の地の文（`.column` の本文など）は当然に検査対象のまま。
空行化するのはマーカー行だけである。ブロックごと落とすのは「機械データ・ブロック」に限る。

### 5.3 案の比較

#### 案 A: 前段でマスクした一時ファイルを textlint に渡す（推奨）

`rewrite_vs_lint_to_textlint` の隣に記法の中和を足す。textlint は「記法が消え、行数はそのままの
原稿」を読む。

- ✅ 既存の一時ファイル方式にそのまま乗る（新しい層が要らない）
- ✅ `Masking` に記法の知識を集約でき、スペルチェック側と judgement を共有できる（I5）
- ✅ **§2.1 の `sentence-length` を根治できる**——textlint がブロックを見なくなるので、
  文長の数え方そのものが正しくなる（案 B では消せるが直せない。§5.4 参照）
- ✅ 外部依存が増えない（node 側に手を入れない）
- ⚠️ `--fix` との関係整理が要る（I4）

#### 案 B: 後段で行範囲フィルタ（`TextlintFormatter` を拡張）

textlint には素の原稿を食わせ、返ってきた JSON から「ガード範囲内の行の指摘」を落とす。
`disabled_rules` の隣に `guarded_ranges` を足す形。

- ✅ 実装が最小。行番号ずれの心配が原理的に無い（I1 が自明に成立）
- ✅ `--fix` に影響しない
- ❌ **対症療法**。textlint は依然ブロックを 1 文として数えるため、
  「ブロックを含む段落」の文長が誤ったまま残る。ブロック内の指摘は消せるが、
  ブロックが**周囲の文の解析に与える汚染**は消えない
- ❌ 消した理由が利用者から見えにくい（allowlist と同じ不透明さを別の場所へ移すだけ）

#### 案 C: 独自 textlint filter rule（JavaScript）を作る

`textlint-filter-rule-vs-notation` を自作し `.textlintrc.yml` の `filters` に足す。

- ✅ textlint の設計思想には最も忠実（AST ノード単位で除外できる）
- ❌ **JS パッケージを 1 つ抱える**（配布・バージョン・テストが Ruby 側と分断）
- ❌ 記法の知識が Ruby（`Masking`）と JS の**二箇所**に分かれる（I5 に反する）
- ❌ 結局 `.textlintrc.yml`（scaffold で配る設定ファイル）に記述が要り、
  「設定ファイルへ逃がさない」という本件の主旨と衝突する

#### 推奨: **案 A**。`--fix` の扱い（I4）だけ先に決める必要がある

案 B は案 A の劣化版だが、**移行期の保険**としては有用。案 A の実装後に
「取りこぼしが出たら B を足す」ではなく、まず A を入れて実測することを勧める。

### 5.4 案 A と案 B の違いが出る具体例

```markdown
この画面の操作を説明します。

:::{.showcase}
![](shot.png)
rect:1 530, 335, 175, 165 {pos=bottom} 保存ボタン
:::
```

- 案 B: `rect` 行の指摘は消える。しかし textlint は依然ブロックを 1 文として読むため、
  文長・読点数の勘定は狂ったまま。ブロックに隣接する段落の判定にも影響が残りうる。
- 案 A: textlint はブロックを空行として読む。**そもそも誤った文が存在しない**ので、
  文長も読点数も正しくなる。

---

## 6. 案 A の実装スケッチ（確定仕様ではない）

### 6.1 置き場所

記法の知識は **`Masking`**（既に「コード領域解釈の唯一実装」を名乗る）に置く。
名前が実態と合わなくなるなら `Masking` の責務を「機械データ領域の解釈」へ広げるか、
`Lint::NotationGuard` を新設して `Masking` を内部で使う。**要判断（§7）**。

```ruby
# 記法を中和したテキストを返す（行数は保存する = I1）。
# コードは Masking の既存実装に委ね、その上に記法の中和を重ねる。
def strip_notation(text)
```

### 6.2 接続

```ruby
# lint.rb — 既存の前段に 1 行足すだけで textlint 側は完結する
def rewrite_vs_lint_to_textlint(source)
  guarded = Masking.strip_notation(source)   # ★追加
  guarded
    .gsub(/<!--\s*vs-lint-disable-next-line\s*-->/, '<!-- textlint-disable-next-line -->')
    ...
end
```

スペルチェック側は `Tokenizer` が既に `Masking.each_prose_line` を呼んでいるため、
`Masking` が記法を機械データとして扱えば**自動的に恩恵を受ける**（変更不要）。

### 6.3 検証方法

```bash
# ガード前後で「誤検出だけが減り、地の文の指摘は 1 件も減っていない」ことを確かめる
npx textlint -c config/.textlintrc.yml -f compact contents/22-extentions.md | grep -c "line "
```

- 期待: §2.1 の 9 件（showcase ブロック内）が 0 になる
- 期待: allowlist の VFM 記法エントリを撤去しても、+76 件が**再発しない**
- 回帰の目印: **地の文に対する指摘の総数が変わらないこと**（I3）。
  ガードが効きすぎて検査に穴が開いていないかは、この数字で見る

---

## 7. 未決事項（レビューで決めたいこと）

| # | 論点 | 補足 |
|---|---|---|
| 1 | **`--fix` の扱い**（I4） | textlint の `--fix` は元ファイルを書き換える。ガード済み一時ファイルを fix すると結果を元ファイルへ戻せない。現状の `--fix` 経路がどう動いているか（一時ファイルを fix して捨てていないか）の確認込みで要調査 |
| 2 | 置き場所 | `Masking` の責務を広げるか、`Lint::NotationGuard` を新設するか（§6.1） |
| 3 | ガードの粒度 | 「機械データ・ブロック」を記法ごとにハードコードするか、`:::{.showcase}` のように**宣言的な一覧**（機械データを持つコンテナ名の定数）で持つか。後者を推す——記法追加時の変更点が 1 行になる |
| 4 | allowlist の撤去範囲 | VFM 記法 5 エントリは全部消せるか。`":::"` は素の `:::` 文字列への指摘も消しているため、撤去して初めて分かる残渣がある可能性 |
| 5 | scaffold 同期 | `lib/project_scaffold/config/textlint_allowlist.yml` も同時に更新が要る |
| 6 | 著者向けの逃げ道 | ガードが効きすぎたときのために `<!-- vs-lint-disable -->` は残す（既存機能なので変更不要） |

---

## 8. 参考: 関連する既存実装

| ファイル | 関係 |
|---|---|
| `lib/vivlio_starter/cli/lint.rb` | `convert_vs_lint_comments` / `rewrite_vs_lint_to_textlint`（前段①）・`run_textlint_aggregated` |
| `lib/vivlio_starter/cli/textlint_formatter.rb` | `aggregate_json`（後段②）・`disabled_message?` |
| `lib/vivlio_starter/cli/masking.rb` | `each_prose_line` / `strip_code`（**行数保存の既存手法**）/ `protect_code` |
| `lib/vivlio_starter/cli/lint/tokenizer.rb` | スペルチェック側。既に `Masking` 依存 |
| `config/textlint_allowlist.yml` | 撤去対象の「VFM 記法」5 エントリ |
| `config/.textlintrc.yml` | `filters.comments: true`（`<!-- textlint-disable -->` が効く根拠） |
| `docs/specs/explanatory-diagram-spec.md` | 本件の発端（図解注釈記法） |
