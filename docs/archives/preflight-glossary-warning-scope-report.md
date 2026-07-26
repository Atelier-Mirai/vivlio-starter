# `vs preflight <章>` で用語集警告が大量に出る問題に関する調査報告

> 作成日: 2026-07-25
> 発端: 章別サマリー実装（`preflight-chapter-summary-spec.md`）の実機確認中に、`vs preflight 24` で
> 🟡 が 14 件流れた直後に「✅ Preflight 完了: 良好な状態です」と出る食い違いを発見した
> ステータス: **対応済み（2026-07-26）** — 案 A・案 C ＋ build との挙動統一（§6.5）／索引スキャン高速化（§6.6）を実施
> 関連: `docs/specs/KNOWN_ISSUES.md`「索引・用語集スキャンの警告が章別サマリーに載らない」
> 対象コード: `lib/vivlio_starter/cli/index/unified_index_manager.rb:415-443`（`warn_unmatched_glossary_terms`＝R4）,
> `lib/vivlio_starter/cli/build/pipeline.rb:429`（`run_step4_index_processing`）,
> `lib/vivlio_starter/cli/index.rb:46`（`process_index_for_build!`）

---

## 1. 要約

- `vs preflight 24` のように**章を絞ると**「🟡 用語集語がビルド対象章に出現しません」が最大 14 件出る。
  原稿には何の問題もない。**警告件数は指定した章の数に反比例する**（実測: 1 章→14 件 / 5 章→5 件 /
  17 章→1 件 / 全 28 章→0 件）。つまりこれは**原稿の欠陥ではなく実行範囲の副作用**である。
- 原因は R4 警告（`warn_unmatched_glossary_terms`）が「用語集語（16 語）が**今回スキャンした章**に
  出現したか」で判定していること。スキャン範囲＝preflight の対象章なので、範囲を狭めれば
  当然ほとんどの語が「出現しない」側に落ちる。
- 併発して**メッセージの文言そのものが誤り**である。「**catalog 外**の 00-preface, … に出現」と
  言うが、これらは `catalog.yml` に**登録済み**の章で、単に今回の実行対象外なだけ（§4 で実証）。
- 発生するのは **`vs preflight <targets>` だけ**。`vs build <章>`（single mode）は Step 4 索引処理を
  実行しないため無関係、全章 `vs build` / `vs preflight` では 0 件になる（§3.3）。
- 章別サマリーへのブリッジ（`IssueRegistry`）を**この警告に対して先に行ってはいけない**。
  現状のまま積むと部分実行が毎回「警告 14 件」と報告され、ノイズが最終判定にまで昇格する。
  **まず本報告の §6 で範囲由来の警告を止め、その後にブリッジする**という順序が必要。

---

## 2. 再現手順と実測

```bash
vs preflight 24        # → 🟡 14 件 ＋ 「✅ Preflight 完了: 良好な状態です」
vs preflight           # → 🟡 0 件
```

対象章数と警告件数（2026-07-25・本リポジトリの原稿 28 章 / 用語集語 16 語で実測）:

| 実行 | 対象章数 | 用語集警告 |
|---|---|---|
| `vs preflight 24` | 1 | **14 件** |
| `vs preflight 21-25` | 5 | 5 件 |
| `vs preflight 11-33` | 17 | 1 件 |
| `vs preflight`（全章） | 28 | 0 件 |

用語集語（`config/index_glossary_terms.yml` の `g` フラグ・全 153 語中 16 語）:
CLI, CSS, CSS組版, EPUB, HTML, Kindle, Markdown, MeCab, PDF, QueryStream, Ruby, SVG, VFM,
Vivliostyle, YAML, トンボ

`vs preflight 24` で警告されなかったのは 24 章に実際に出現する CSS と Markdown の 2 語だけで、
残り 14 語がすべて警告になる。**16 - 14 = 2** という関係がそのまま出ている。

---

## 3. 機構

### 3.1 判定は「今回のスキャン結果」に対して行われる

`unified_index_manager.rb`:

```ruby
def build_index!(chapters)
  scanner = IndexMatchScanner.new(defer_warnings: true)
  scanner.scan_all_chapters!(chapters, read_only: false)   # ← chapters = 対象章のみ
  ...
  warn_unmatched_glossary_terms(glossary, scanner.glossary_backlinks, chapters)
end

def warn_unmatched_glossary_terms(glossary_terms, glossary_backlinks, chapters)
  missing = glossary_terms.reject { glossary_backlinks.key?(it['term']) }   # ← ここ
  ...
end
```

`glossary_backlinks` は**今回スキャンした章から作られたリンク集**なので、対象章が 1 章なら
その章に出ない語はすべて `missing` に入る。R4 のコメントは「ビルド対象章に 1 回も出現しない
用語集語を警告する」と書いてあり、**実装は仕様どおり**である。問題は「ビルド対象章」が
**全章のつもりで書かれている**こと（`vs build` 前提の設計）に尽きる。

### 3.2 対象章の供給元

```
PreflightCommand#call
  └ UnifiedBuildPipeline (mode: :preflight)
      └ run_step4_index_processing            # pipeline.rb:429
          chapter_targets = entries.any? ? basenames.sort : (contents/*.md 全部)
          └ IndexCommands.process_index_for_build!(chapter_targets)   # index.rb:46
              └ UnifiedIndexManager#build_index!(chapters)
```

`entries` は CLI 引数から解決された**対象章そのもの**。引数なしのときだけ全章になるため、
「引数を付けたら警告が増える」という直感に反する挙動になる。

### 3.3 影響範囲は preflight に限られる

| 実行 | Step 4 索引処理 | R4 警告 | 対応後（§6.5） |
|---|---|---|---|
| `vs preflight`（全章） | 実行する | 出ない（全章がスキャン対象） | 変化なし |
| `vs preflight <章>` | 実行する | **出る（本件）** | **索引処理ごとスキップ**→出ない |
| `vs build`（全章） | 実行する（`full_mode_step_table`） | 出ない | 変化なし |
| `vs build <章>` | **実行しない**（`register_single_mode_steps` に無い） | 出ない | 変化なし |
| `vs index:build <章>` | 実行する（`resolve_chapters`） | 出る（同根・未検証） | R4 ガードで出ない |

`vs build 24` が静かなのは偶然の産物（単章ビルドは索引ページを作らない設計）で、
R4 が「部分実行に弱い」こと自体は共通の性質である。
→ 対応後は「章を絞ったら索引処理をしない」を preflight にも適用し、両者の挙動を揃えた（§6.5)。

---

## 4. 併発する文言の誤り（「catalog 外」）

`unified_index_manager.rb:433-441`:

```ruby
build_targets = chapters.map { File.basename(it.to_s, '.md') }
found = all_contents.keys.select { all_contents[it].include?(name) }
outside = found - build_targets                      # ← 「ビルド対象外」の意味
hint = if outside.any?
         "catalog 外の #{outside.join(', ')} に出現"  # ← 「catalog 外」と言ってしまう
```

`outside` は `found - build_targets` なので**ビルド対象外**の集合であり、catalog 登録の有無とは
無関係。全章ビルドでは「対象外＝catalog 外」がたまたま一致するため誤りが露見しなかった。

実証（`vs preflight 24` が「catalog 外」と呼んだ 7 章はすべて catalog 登録済み）:

```
00-preface:   catalog 登録済み ← 「catalog 外」表記は誤り
12-quickstart: catalog 登録済み ← 同
13-new / 44-build / 51-doctor / 61-developer / 92-install: いずれも登録済み
```

著者は「catalog.yml から漏れている章がある」と読むため、**存在しない問題の調査に誘導する**。
これは §6 の方針と独立に**単独で修正できる**（`outside.any?` の分岐で catalog 集合と実際に
突き合わせるか、文言を「ビルド対象外の…」に直す）。

---

## 5. 影響評価

- **著者体験**: 章を絞った preflight は「速く 1 章だけ確かめる」ための機能なのに、毎回 14 行の
  無関係な 🟡 が出る。慣れると 🟡 全体を読み飛ばすようになり、**本物の警告が埋もれる**のが最大の害。
- **章別サマリーとの関係**: 現在この警告は `IssueRegistry` に積んでいないため、最終行は
  「✅ 良好な状態です」になる。画面に 🟡 が並ぶのと矛盾して見えるが、**件数として積む方が
  現状では有害**（部分実行が常に「警告 14 件」になる）。順序として §6 が先。
- **終了コード**: 影響なし（R4 は `log_warn` のみで `any_issues?` に無関係）。
- **全章実行**: 影響なし。R4 は全章では本来の役割（辞書に残った死語の検出）を果たしている。

---

## 6. 対応の選択肢

### 案 A: 部分実行では R4 を出さない（推奨・最小）

`build_index!` に渡された `chapters` が catalog 全章の**真部分集合**なら R4 をスキップする。
判定材料は既にある（`Build::CatalogLoader.load_existing_basenames`＝`index.rb:72` で使用中）。

```ruby
# R4 は「辞書に残った死語の検出」であり、全章を走査して初めて意味を持つ。
# 部分実行では出現しないのが当然なので黙る（誤検知を構造的に無くす）。
def full_scope?(chapters)
  catalog = Build::CatalogLoader.load_existing_basenames
  catalog.any? && (catalog - chapters.map { File.basename(it.to_s, '.md') }).empty?
end
```

- 長所: 誤検知が原理的に消える。全章実行の挙動は不変。変更 1 ファイル・数行。
- 短所: 部分実行では死語検出が働かない（→ 全章 preflight / build で拾えるので実害は小さい）。
- 補足: 黙るのではなく `log_info`（`--log` 時のみ表示）へ降格する案も同等に妥当。
  「対象章を絞ったため用語集の照合はスキップしました」の 1 行を info で出すと親切。

### 案 B: 辞書の `scanned_chapters` / 既存バックリンクと突き合わせる

今回のスキャン結果ではなく、`config/index_glossary_terms.yml` に蓄積された出現情報
（`vs index:auto` が書く `scanned_chapters` 等）を根拠に「原稿のどこにも無い語」だけを警告する。

- 長所: 部分実行でも死語検出が働く。判定が「原稿の状態」に基づくため意味が正しい。
- 短所: 辞書の鮮度に依存する（`vs index:auto` 未実行・stale な辞書では誤判定）。
  実装量も案 A より大きい。**index-context-staleness の知見**（既存 context は stale でも
  温存される）を踏まえた設計が必要。

### 案 C: 文言のみ修正して警告は残す

「catalog 外の…」→「ビルド対象外の…」に直し、件数はそのまま出す。

- 長所: 最小の変更で誤読は消える。
- 短所: 14 件のノイズは残る。**単独では採らない**（案 A と併せて行う修正として位置づける）。

### 推奨

**案 A ＋ 案 C の文言修正を 1 コミットで行う**。案 B は「部分実行でも死語を検出したい」という
要望が出た時点で、辞書の鮮度問題（`index-context-staleness`）と併せて検討する。

その後、あらためて索引系警告の `IssueRegistry` ブリッジ（`:index` カテゴリ）を行う。
このとき積むべきは「原稿の欠陥」に分類される警告だけである（§7）。

---

## 6.5 実施した対応（2026-07-26）

「`vs preflight` と `vs build` で挙動が異なるのが気になる。preflight は原稿のエラーを素早く
確認するための機能なので同じ挙動にしたい」という判断により、**案 A・案 C に加えて
「揃える」対応（下記 (1)(2)）を実施した**。

### (1) 章を絞った preflight は索引処理を行わない（parity）

`UnifiedBuildPipeline#run_step4_index_processing` に**走査範囲の判定**を足し、対象章が
catalog 全章を覆っていなければ索引処理そのものをスキップする（`full_catalog_scope?`）。
`vs build <章>`（single mode）が Step 4 を持たないことと揃い、§3.3 の表の食い違いが解消する。

- `vs preflight 24` → 索引処理なし（`vs build 24` と同一）・R4 の 14 件は**構造的に消える**
- `vs preflight` → 従来どおり索引処理あり（`vs build` 全章と同一）
- スキップ理由は `--log` で表示（既定では黙る＝build と同じ静けさ）
- 副次効果として実行時間が 1.35–1.57s → 1.15s（索引無効時の 1.14s とほぼ同じ＝索引処理の分だけ短縮）

### (2) preflight が握り潰していた索引の案内を表示する（parity）

調査中に判明した**別の非対称**: `IndexCommands.flush_post_build_messages` は
`build_command.rb` の 2 箇所からしか呼ばれておらず、**preflight は一度も flush していなかった**。
そのため Step 4 が積む R7（`vs index:auto` 未実施の章の案内）と「索引語辞書が見つかりません」は
preflight では**表示されないまま捨てられていた**。つまり従来の preflight の索引処理は
「誤検知（R4）だけを見せ、有用な案内は捨てる」状態だった。preflight でも flush するようにした。

### (3) 案 A: R4 は全章走査時のみ

`warn_unmatched_glossary_terms` の冒頭で走査範囲を判定し、部分走査なら黙る。
(1) で preflight からは到達しなくなるが、`vs index:build <章>`（内部用）など**他の入口**が
同じ罠を踏まないよう R4 自身にもガードを置く（多層防御）。catalog を読めない場合は
従来どおり警告する（判定材料が無いのに黙るのは危険）。

### (4) 案 C: 文言修正

`catalog 外の …` → **`catalog 未登録の …`**。(3) のガードにより、この分岐へ来る章は
「contents/ にはあるが catalog.yml に載っていない原稿」に限られることが保証されるため、
より具体的で行動につながる表現にした。既存テストの期待値 1 箇所を追随更新
（`unified_index_manager_test.rb#test_warn_unmatched_glossary_terms_hints_outside_chapter`）。

### 残った差分（意図的）

`vs preflight <章>` では索引・用語集の検査が一切行われない。R7 の案内も出ない。
これは `vs build <章>` と同じ挙動であり、索引まわりの確認は**全章実行**（`vs preflight` /
`vs build`）で行う、という役割分担にした。部分実行でも索引を検査したい場合は案 B が必要になる。

### テスト

- `test/vivlio_starter/cli/build/index_step_scope_test.rb`（3 件）: 部分実行でスキップ／
  全章実行で実行／entries 空のフォールバックも全章扱い
- `test/vivlio_starter/cli/index/glossary_warning_scope_test.rb`（4 件）: 部分走査で黙る／
  全章走査で警告／`catalog 未登録の …` の文言／どこにも無い語の文言

---

## 6.6 索引スキャン自体の高速化（2026-07-26・§6.5 の続き）

「全章実行なら検査できるとはいえ、辞書を直して再確認するには重い」という指摘を受け、
スキャン本体を最適化した。**新しいコマンドは作らず**、既存の `vs preflight` /
`vs build` が速くなる形にした。

### ボトルネックの実測

| 項目 | 実測 |
|---|---|
| 走査規模 | 地の文 7,421 行 × 用語 153 語 = **1,135,413 反復** |
| スループット | 約 120 KB/s（481KB に 4.05s・**線形**で O(n²) ではない） |
| うち保護 gsub 4 本 | 約 1.77s |
| うち `Regexp` 生成 | 約 0.54s |

`apply_auto_indexing` / `apply_glossary_only_linking` は**行ごと・用語ごとに**
「4 本の保護 gsub → `Regexp.new` → 置換 → 復元」を繰り返していた。
なお `@yomi_inferrer.infer` も同じ位置で呼ばれていたが、辞書にほぼ全語 `yomi` があるため
実際の呼び出しは全走査で 1 回だけだった（MeCab は問題ではなかった）。

### 施した最適化

1. **用語パターン・読みを初回だけ組み立てる**（`@index_patterns` / `@literal_patterns` /
   `@term_yomis`）。辞書由来で不変なので結果は同一。用語集のみの用語は従来どおり
   `pattern` を使わず完全一致で当てる（この差を潰さないよう別キャッシュにした）。
2. **退避を行ごとに 1 回へ**（新設 `LineMask`）。生成したタグは即座に退避し、後続の用語から
   隠す。従来は次の用語の保護 gsub が同じ範囲を 1 トークンへ退避していたため**遮蔽の粒度は
   等価**。用語の処理順と LIFO 復元も維持した（順序が結果を決めるため）。
3. トークンを `[[HTML_TOKEN_n]]` → NUL 区切りへ変更。旧形式は文字列 "HTML" を含み、
   辞書の用語「HTML」が自己マッチしうる形だった（直後の `_` が単語文字で `\b` が
   成立しないため**偶然**無事だった）。NUL 区切りなら構造的に起こらない。

### 結果（実測）

| 対象 | 前 | 後 |
|---|---|---|
| 索引スキャン（全 28 章） | 3.92s | **0.47s**（8.3 倍） |
| `index scan and build` ステップ | 5.32s | **0.95s**（5.6 倍） |
| 全章 `vs preflight` | 10.8s | **6.3s** |

### 精度の担保（黄金マスタ比較）

改修前に全 28 章のタグ付け結果・`_index_matches.yml`・用語集バックリンクを保存し、
改修後と全比較した。**`_matches.yml` と用語集バックリンクは完全一致**
（アンカーID・出現番号・初出の dfn/span 判定まで不変）。タグ付け結果の差分は 3 章 × 1 行のみで、
**いずれも改修前が壊れていた箇所**だった:

`replaced_line.gsub!(token, original)` の置換文字列中の `` \` `` が Ruby の特殊参照
（マッチ前の文字列）として解釈され、`` `\` `` を含む行で**行頭が重複して混入**していた。
実害は `21-markdown-tutorial`（`` `\` `` が消える）・`61-developer`・
`90-notation-cheatsheet`（表のセルに行頭が二重に入る）の 3 行で、毎回のビルドで発生していた。
復元をブロック形式（`gsub(token) { content }`）に変え、逐語で戻るようにした。

### 追加した回帰テスト

- `index_match_scanner_test.rb`: `\` を含むインラインコードが逐語復元されること
  （**改修前のコードでは失敗する**ことを確認済み）／生成タグが後続の用語に食われないこと
- 既存の「保護トークン残留」検査 2 件は旧トークン形式のみを見ていて空振りになるため、
  現行の NUL 区切りも見る `refute_leftover_token` へ寄せた（意図は不変）。

---

## 7. 索引系警告の分類（ブリッジ設計の下敷き）

`lib/vivlio_starter/cli/index/` 配下の `log_warn` は約 28 箇所ある。ブリッジ時は一律に積まず、
以下の 3 分類で扱いを分ける。

| 分類 | 例 | 章別サマリーへの扱い |
|---|---|---|
| **原稿の欠陥** | 用語の説明文が上限超過（`:321`）、短い ASCII 語のスキップ案内（`:581`）、`_index_glossary_review.md` 不在（`:148`） | 積む（`:index`・章が特定できるものは章付き） |
| **実行範囲由来** | R4 用語集語の未出現（`:441`）、`スキップ (Markdown が見つかりません)`（`index_match_scanner.rb:129`）、索引候補抽出のスキップ（`index_candidate_extractor.rb:83`） | **積まない**（そもそも §6 で出さない方向） |
| **環境・設定** | natto/MeCab 不在（`yomi_inferrer.rb:74-82`）、辞書の読み込み失敗（`:111`）、未知の library version（`index_library.rb:137`） | 積まない（章と無関係。`vs doctor` の領分） |

---

## 8. 再現・確認用スニペット

```bash
# 対象章数と警告件数の関係（表 §2 の再現）
for scope in 24 21-25 11-33 ""; do
  n=$(vs preflight $scope --no-resize 2>&1 | grep -c "用語集語がビルド対象章に出現しません")
  echo "targets='${scope:-all}' → $n 件"
done

# 「catalog 外」と呼ばれた章が実際は catalog 登録済みであることの確認
ruby -Ilib -e '
require "vivlio_starter/cli/token_resolver"
c = VivlioStarter::CLI::TokenResolver::Resolver.new.resolve.select(&:in_catalog?).map(&:basename)
%w[00-preface 12-quickstart 44-build].each { |b| puts "#{b}: #{c.include?(b) ? "登録済み" : "外"}" }'

# 用語集語（g フラグ）の一覧
ruby -ryaml -e '
t = YAML.safe_load_file("config/index_glossary_terms.yml")["terms"]
puts t.select { |x| x["flags"].to_s.include?("g") }.map { |x| x["term"] }.join(", ")'
```

---

## 9. スコープ外（本報告では扱わない）

- 辞書の stale な `context:` 抜粋の追従（→ `index-context-staleness` の既知課題）
- `vs index:build <章>` の同根挙動（§3.3 の表に記載のみ・未検証）
- 索引系警告の `IssueRegistry` ブリッジそのもの（§6 の修正後に別タスクで実施）
