# 索引・用語集の整合性仕様書 — 辞書と出現情報の分離・context 鮮度・catalog 変更への追従

> 作成日: 2026-07-16
> ステータス: **確定仕様・実装待ち**
> 元報告: [index-context-staleness-report.md](index-context-staleness-report.md)（context stale 化の実測・原因・設計案比較。本書はそれを包含して昇格）
> 対象: (1) 索引辞書 `config/index_glossary_terms.yml` の `context:` が原稿推敲に追従しない問題、(2) `vs index:auto` が黙って辞書へ書き込む問題、(3) **著者が catalog.yml で章を追加・削除（コメントアウト）したときの索引・用語集の整合性**（起票時にユーザー追加の論点。例: 61-developer.md を全章版 pdf には含め、印刷版 print_pdf では除く運用）
> 決定事項:
> - **設計原則**: 辞書は「語彙の一次データ」（語・読み・flags・定義・承認状態）だけを持ち、**出現情報（頁番号・バックリンク・context）は原稿とビルド対象章から毎回導出する**。索引ページは既にこの原則で動いており（ビルド毎スキャン）、逸脱している 2 箇所（辞書内 `backlink_sources`・温存される `contexts`）を原則側へ寄せる
> - context 鮮度は報告書の**案 A**（`enrich` で stale を捨てて補充）＋ §5.1（複数章対応）を採用
> - バックリンクは辞書への永続化を**廃止**し、スキャン中間ファイル（ワークスペース）へ移す
> - 用語集の掲載対象は現状維持（g フラグ全語）とし、**ビルド対象章に出現しない g 語は警告**で可視化する（除外はしない——定義は書籍の語彙資産であり、外すか否かは著者が flags で決める）
> - 章の追加検知のため、`index:auto` が走査した章集合を辞書に記録し（`scanned_chapters`）、ビルド時に未走査の章を検出したら案内を出す
> - `[用語]`（読みなし）手動マークアップは **ASCII のみ 2 文字以下を登録対象外**にする（単位 `[eV]` `[Hz]`・フラグ解説 `[g]` の誤登録を根治）
> - `vs index:auto` が辞書へ書いた変更は**既定ログレベルで必ず要約表示**する
> 関連: `lib/vivlio_starter/cli/index/unified_index_manager.rb`, `index_match_scanner.rb`, `unified_terms_manager.rb`, `unified_page_builder.rb`, `index_candidate_extractor.rb`, `lib/vivlio_starter/cli/build/pipeline.rb`（Step 4）, `config/index_glossary_terms.yml`, `config/catalog.yml`

## 0. 背景と設計原則

索引・用語集は 3 種のデータでできている:

| 種別 | 例 | あるべき置き場 |
|---|---|---|
| **語彙（一次データ）** | 語・読み・flags（i/g）・定義・承認/棄却 | 辞書 `config/index_glossary_terms.yml`（git 管理・著者の資産） |
| **出現情報（派生データ）** | 頁番号・節アンカー・バックリンク・本文抜粋（context） | 原稿＋そのビルドの対象章から**毎回導出**（ワークスペース `.cache/vs/build/`） |
| **ビルド対象** | どの章を本に含めるか | `config/catalog.yml`（コメントアウトで除外） |

この分離が守られていれば、**catalog をどう変えても索引・用語集は自動的に整合する**——
出現情報は「そのビルドに実在する本文」からしか作られないからである。実際、索引ページは
既にこの原則で動いている（ビルド毎に `IndexMatchScanner` が対象章を走査し、出現ゼロの語は
ページに載らず、頁番号は常にそのビルドのもの）。

問題は、原則から逸脱している 2 箇所と、運用を黙って狂わせる 2 つの副作用である（§1）。
本仕様はこれらを原則側へ寄せ、あわせて「章の追加・削除」の期待動作を確定する。

## 1. 現状の実装事実（2026-07-16 調査・行番号は当日時点）

### 1.1 章リストの決まり方（すでに一貫している）

- `vs index:auto`（引数なし）: `CatalogLoader.load_existing_basenames`（`index.rb:61-82`）＝ **catalog 準拠**。
- `vs build` Step 4: pipeline の Entry（＝catalog）から basename（`pipeline.rb:437-447`）＝ **catalog 準拠**。
- catalog でコメントアウトされた章は、両者から単に消える。**章リストの解釈に不整合はない**。

### 1.2 索引ページ（原則どおり・変更不要）

`IndexMatchScanner.scan_all_chapters!` が対象章を走査し、結果を中間 YAML
`INDEX_MATCHES_FILE`（`.cache/vs/build/_index_matches.yml`・`common.rb:60-62`、
「ルート無汚染」原則 P4b §2.5）へ書き、`UnifiedPageBuilder.build_index!` がそこから
ページを組む。出現ゼロの語は載らない。**ビルド単位で自己整合**。

### 1.3 【逸脱 1】バックリンクが辞書に永続化され、出現しなかった語は古いまま残る

`scan_all_chapters!` の最後に `save_glossary_backlinks!`（`index_match_scanner.rb:116-140`）が
**git 管理の一次データ `config/index_glossary_terms.yml` を直接書き換える**。しかも:

```ruby
terms.each do |term|
  next unless @glossary_backlinks.key?(term_name)   # ★今回出現した語だけ更新
  term['backlink_sources'] = @glossary_backlinks[term_name]
end
```

今回のビルドで出現しなかった g 語の `backlink_sources` は**前回ビルドの値のまま**残る。
用語集ページはこれを読む（`unified_page_builder.rb:429-430`）ため、§2 の運用で
**存在しない章への幽霊バックリンク**が印字され得る。加えて `vs build` のたびに
git 作業ツリーが汚れる（backlink 差分＋`updated_at`）。
なお書籍間持ち運び（`index_library.rb:12`）は既に「backlink_sources は書籍固有情報として
含めない」と定めており、**辞書スキーマから外す方針と整合する前例**がある。

### 1.4 【逸脱 2】context が空のときだけ再抽出され、stale が温存される

報告書 §3 のとおり。`enrich_terms_with_context`（`unified_index_manager.rb:564-581`）の
`unless enriched['contexts']&.any?` が原因で、原稿推敲に追従しない（実測 15/724 件が stale
だった。2026-07-16 に辞書側を掃除済み＝`d25a5a27`。恒久対策が本仕様）。
再抽出に使う `find_context_for_term`（`:613-627`）は**最初にヒットした 1 章で return** するため、
このままでは複数章で使われる語の使用例が 1 件に痩せる（報告書 §5.1）。

### 1.5 【副作用 1】`vs index:auto` が黙って辞書へ書き込む

`auto_process!` は実行時に (a) 手動マークアップ `[語|読み]` の登録（`:60`）、
(b) 高スコア候補の自動承認（`:96`）で `merge_terms!` を呼び、**レビュー前に辞書を書き換える**。
結果レポート（`report_auto_results` `:847-858`）は `log_info`/`log_success` のため
既定ログレベル（warn）では**コンソールに何も出ない**。実測: 無出力のまま 5 語
（manual_markup 1 語＋auto_extracted 4 語）が辞書へ入った。

### 1.6 【副作用 2】`[用語]`（読みなし）記法が単位・フラグ表記を誤登録する

手動マークアップの第二パターン `/\[([^\]|]+)\](?!\()/`（`unified_index_manager.rb:468`）は
URL と脚注 `[^1]` しか除外しない。コード退避（`CodeBlockStripper`）は効いているが、
**地の文・表セルの角括弧**は防げない。実測の誤登録:

| 原稿 | 誤登録 |
|---|---|
| `contents/33-index-glossary.md:42` の表セル「書籍間で持ち運ぶ用語集**[g]**・reject・読み」 | 語 `g`（読み `g`・pattern `/\bg\b/`＝本文中の英字 g 全部に索引タグが付く爆弾） |
| `contents/94-sample.md:136` の表ヘッダー「仕事関数 φ **[eV]** \| しきい周波数 **[Hz]**」 | 語 `eV`・`Hz`（単位表記） |

### 1.7 print_pdf の章セット（現状の制約）

print_pdf は**閲覧用 PDF からの導出**（`pipeline.rb:106` `derive_print?`・print-pdf-derivation-spec）
であり、**章セットを pdf と変える機構は存在しない**。よって「pdf は全章・print_pdf は
61-developer 抜き」を実現する現実の運用は **catalog.yml を切り替えて 2 回ビルドする**
（トグル運用）。§2 はこの前提で期待動作を定める。ターゲット別章セット機構そのものは
スコープ外（§8）だが、本仕様の導出原則が立てば将来それを導入しても索引・用語集は
自動的に追従する。

## 2. ユーザーシナリオと期待動作（本仕様のゴール）

シナリオ: 全章（61-developer 含む）で索引・用語集を作った後、
**(A)** catalog から 61-developer をコメントアウトして print_pdf を作る →
**(B)** 戻して pdf を作る。逆順（後から章を追加）も同様。

| 観点 | 現状の帰結 | 本仕様適用後 |
|---|---|---|
| 索引ページ | ✅ (A) では 61-developer 由来の項目・頁が消え、(B) で戻る（既に導出的） | 同じ（変更なし） |
| 用語集のバックリンク | ❌ (A) で 61-developer にしか出ない g 語のバックリンクが**前回値のまま印字**（存在しない章への参照） | ✅ バックリンクはそのビルドのスキャン結果から導出。(A) では空になり、(B) で復活 |
| 用語集の掲載 | g 語は無条件掲載（本文に登場しない語も定義だけ載る） | 掲載は維持しつつ、**「ビルド対象章に出現しない用語集語」を 🟡 警告**（除外するなら著者が `-g` を付ける） |
| 辞書（git） | ❌ ビルドのたびに backlink_sources と updated_at で汚れる（トグルで往復差分） | ✅ **ビルドは辞書を書かない**（読み取り専用）。トグルしても git はクリーン |
| 章を後から追加 | ❌ 新章にしか出ない語は辞書に無く、索引から黙って漏れる | ✅ ビルドが「索引候補抽出が未実施の章」を検出して案内（→ `vs index:auto`） |
| 章の削除（コメントアウト） | 辞書の語・context はそのまま | ✅ 語彙は温存（catalog へ戻せば完全復活）。context も「catalog 外だが実在する章」の分は温存（§4.3） |

**整合性の定義（本仕様が保証する性質）**: どのビルドでも、索引・用語集ページの
頁番号・バックリンクは**そのビルドに実在する本文**だけを指す。辞書はビルドで変化しない。

## 3. 要求仕様

| # | 要件 |
|---|---|
| R1 | `vs build`（索引スキャン）は `config/index_glossary_terms.yml` を**一切書き換えない** |
| R2 | 用語集バックリンクはビルド毎にスキャン結果から導出し、ワークスペースの中間ファイル経由で `UnifiedPageBuilder` へ渡す。辞書の `backlink_sources` キーは廃止（読み手からも除去） |
| R3 | 既存辞書（root・scaffold・著者の既存プロジェクト）に残る `backlink_sources` は、辞書を次に保存する機会（`index:auto`/`apply` 等の `save_terms!`）で**黙って捨てる**（無害な残置は許容・ビルドは読まないので実害なし） |
| R4 | ビルド対象章に 1 回も出現しない g 語があれば、用語集生成時に 🟡 警告で列挙する（語名＋「catalog 外の章に出現があるならその章名」を添える。掲載自体は維持） |
| R5 | `enrich_terms_with_context` は「現原稿に無い context を捨て、空になったら本文から**複数章ぶん**補充」する（報告書 案 A ＋ §5.1。stale 判定は §4.3 の 1 実装に集約） |
| R6 | stale 判定・補充は**今回読み込んだ章**（引数または catalog）に対してのみ行い、それ以外の章（catalog 外だが `contents/` に実在・部分実行 `vs index:auto 21-23` の対象外章）を参照する context は温存する |
| R7 | `index:auto` が走査した章集合を辞書トップレベル `scanned_chapters:` に**和集合**で記録し、ビルド Step 4 は「ビルド対象 − scanned_chapters」が非空なら既存の post_build_message 機構で `vs index:auto` の実行を案内する（`scanned_chapters` キーが無い旧辞書では判定をスキップ） |
| R8 | `index:auto` が辞書へ書いた変更（手動マークアップ登録 N 語・自動承認 M 語・語名）は、**既定ログレベルで表示されるチャネル**（`log_summary`/`log_always` 相当）で必ず要約表示する |
| R9 | `[用語]`（読みなし）手動マークアップは **ASCII のみかつ 2 文字以下の語を登録しない**（`[g]` `[eV]` `[Hz]` 対策）。意図的に登録したい場合は読み付き `[eV\|いーぶい]` を使う（この逃げ道をドキュメントに明記） |
| R10 | 上記すべてで索引・用語集ページの出力（§2 で変わると明記した点以外）と `rake test` の互換を保つ |

## 4. 実装設計

### 4.1 Phase 1（先行・小粒）: 可視化と誤登録ガード — R8, R9

以降のフェーズの検証を安全にするため最初に入れる。

1. **R8**: `auto_process!` で `merge_terms!` を呼んだ直後に、登録内容の要約を既定レベルで出す。
   例: `📝 辞書を更新しました: 手動マークアップ 2 語（特殊相対性理論, 重力）・自動承認 1 語（クロスリファレンス）`。
   `report_auto_results` の総括行（候補数・レビューファイル案内）も既定レベルへ昇格する。
   何も書かなかった実行では「辞書は変更していません」を出す必要はない（無言＝無変更が成立する）。
2. **R9**: 第二パターンのループ（`unified_index_manager.rb:468-481`）に
   `next if term.match?(/\A[\x21-\x7E]{1,2}\z/)`（ASCII 可視文字のみ 2 文字以下）を追加し、
   スキップ時は 🟡 警告で「`[eV]` は単位・記号表記とみなし索引登録しません → 索引に載せる場合は `[eV|いーぶい]`」
   の形で章名つき案内を出す（警告親切方針: before→after ＋出現箇所）。
   既に誤登録済みの `g` 等は本仕様では触らない（著者がレビュー画面で `[r]` 棄却できる。
   同梱原稿の辞書は実装時に棄却しておく）。

### 4.2 Phase 2（本丸）: バックリンクの導出データ化 — R1〜R4

1. `save_glossary_backlinks!` を「辞書へ書く」から「**中間 YAML へ書く**」に変更する。
   置き場は既存の `INDEX_MATCHES_FILE`（`.cache/vs/build/_index_matches.yml`）に
   `glossary_backlinks:` セクションを同居させる（書き手・読み手・ライフサイクルが
   `matches` と完全に同じため。ルート無汚染 P4b とも整合）。
2. `UnifiedPageBuilder` は `term['backlink_sources']`（`:429-430`）ではなく、
   ロード済み中間ファイルの `glossary_backlinks[term_name]` を読む。
   `build_index!`（`unified_index_manager.rb:349`）の「scan 後に backlink_sources が
   更新されるためリロード」の `clear_cache!` は不要になる（削除）。
3. 辞書スキーマから `backlink_sources` を撤去: `unified_terms_manager.rb` の
   `update_backlink_sources!`（:204）を削除、`merge_term_data`（:242）と
   `build_term_entry`（:263）の該当行を削除。**`save_terms!` は未知キーを書き出さない
   構造になる**ため、既存辞書の残置キーは次回保存時に自然消滅する（R3）。
   一括掃除スクリプトは作らない（残っていても誰も読まない）。
4. **R4 の警告**: 用語集生成時、`glossary_terms` のうち今回の `glossary_backlinks` に
   無い語を集め、`🟡 用語集語がビルド対象章に出現しません: PDF/X-1a（catalog 外の 61-developer に出現）`
   の形で列挙する。catalog 外での出現は `contents/*.md` 全体を軽く走査して探す
   （既存 `find_context_for_term` の走査と同じ要領。見つからなければ「原稿のどこにも
   出現しません（語の変更・削除？）」と添える）。
5. root/scaffold 同梱の `config/index_glossary_terms.yml` から `backlink_sources` を
   実装時に除去し（`vs index:auto` 一回で自然に消えるが、配布物は明示的に綺麗にする）、
   `ruby copy_to_scaffold.rb` で同期する。

### 4.3 Phase 3: context 鮮度（報告書 案 A ＋ §5.1） — R5, R6

1. **stale 判定の 1 実装**（報告書 §5.3 で実証済み）: `context_live?(ctx, loaded_chapters)`
   — context 文字列と参照章本文の**両方から全空白を除去**し部分文字列一致で判定。
   参照章が今回読み込んだ集合に無ければ**判定せず温存**（R6。catalog 外・部分実行・
   印刷トグル運用を壊さない）。参照章が `contents/` にも実在しない（章削除・改名）
   場合は stale として捨てる。
2. `enrich_terms_with_context` を「stale を捨てる → 空になったら補充」へ:

   ```ruby
   fresh = Array(enriched['contexts']).select { context_live?(it, loaded) }
   fresh = collect_contexts_for_term(term['term'], chapters) if fresh.empty?
   enriched['contexts'] = fresh
   ```

3. `find_context_for_term`（1 章で return）を `collect_contexts_for_term` に置き換える:
   全対象章を走査し、出現する章ごとに 1 context（既存の
   `extract_surrounding_context` → `smart_context_cut` を流用）を返す。
   上限は候補抽出側の実態に合わせる（レビュー表示は先頭 2 件なので、章数上限 5 程度で
   打ち切ってよい——**実装時に候補抽出側の蓄積数と揃えること**）。
4. レビュー md の「登録済み用語」表示で、catalog 外の章の context には
   `（catalog 外）` を添える（判断材料の誤解を防ぐ。表示のみ・辞書は変えない）。
5. 更新された context が辞書へ焼き直されるのは従来どおり `apply` 経由
   （`review_markdown_generator.rb:291-294` のパース→保存）。auto 単体では
   レビュー md にのみ反映され、辞書の context は apply まで変わらない——
   ただし R8 の可視化により、auto が辞書へ書くのは語の登録だけであることが
   ログからも明確になる。

### 4.4 Phase 4: 章追加の検知 — R7

1. `auto_process!` の末尾で `scanned_chapters` を更新:
   `(既存の記録 ∪ 今回の chapters) ∩ contents に実在する章`（改名・削除の残骸は落とす）。
   辞書トップレベルへ保存（`generated_at` の隣）。
2. ビルド Step 4（`run_step4_index_processing`）で
   `chapter_targets - scanned_chapters` が非空なら、既存の
   `IndexCommands.add_post_build_message` 機構（`INDEX_TERMS_MISSING_MESSAGE` と同じ出口）で
   `🟡 索引候補の抽出が未実施の章があります: 61-developer → vs index:auto を実行してください` を出す。
   `scanned_chapters` キーが無い（旧辞書）なら何も出さない（R7）。
3. これによりトグル運用は無警告で通る（61-developer は過去に走査済み＝和集合に残る）。
   警告が出るのは「本当に新しい章」だけ。

### 4.5 スコープ外にする変更（しないこと）

- 索引ページ生成（§1.2）——既に原則どおり。
- 用語集から未出現語を**除外**する動作変更（警告のみ。除外は著者の flags 操作）。
- `auto_discovery`・スコア閾値・承認フロー本体。
- 案 B（context を辞書に持たない全面導出化）——破壊的で章絞り込み時に穴が開く（報告書 §4.3）。

## 5. エッジケース

| ケース | 期待動作 |
|---|---|
| catalog から 61-developer をコメントアウトして `vs build print_pdf` | 索引: 61-developer の頁・項目なし。用語集: 同章にしか出ない g 語はバックリンクなしで掲載＋🟡 警告（「catalog 外の 61-developer に出現」）。辞書: 無変更 |
| その後 catalog を戻して `vs build`（pdf） | すべて全章版に完全復元。git 差分なし |
| 新章 71-appendix.md を catalog へ追加してビルド | 既存語の出現は索引に載る（スキャンは毎回）。ビルド末尾に「索引候補の抽出が未実施: 71-appendix」の案内 → `vs index:auto` で候補抽出 |
| 章ファイルを改名（10-intro → 15-intro） | 旧章名を参照する context は「実在しない章」として stale 除去→補充。`scanned_chapters` の旧名も次回 auto で掃除される |
| `vs index:auto 21-23`（部分実行） | 21-23 の context のみ鮮度検証・他章参照の context は温存。`scanned_chapters` へ 21-23 を和集合追加 |
| 原稿の一文を推敲して `vs index:auto` | 該当 context だけが新しい抜粋に置き換わる（レビュー md 上。apply で辞書へ） |
| 表ヘッダー「仕事関数 φ [eV]」 | 登録されず 🟡 警告（読み付き `[eV\|いーぶい]` の案内つき） |
| `[特殊相対性理論|とくしゅそうたいせいりろん]`（正当な手動マークアップ） | 従来どおり登録＋R8 の要約に語名が出る |
| 旧プロジェクト（辞書に backlink_sources 残置・scanned_chapters なし） | ビルドは残置キーを読まず正常動作・章追加警告はスキップ。次回 auto/apply の保存で残置キーが自然消滅 |
| 索引機能無効（`index_glossary.enabled: false`） | 従来どおり全スキップ（本仕様の警告類も出ない） |

## 6. テスト計画

- **`index_match_scanner_test.rb`**: スキャンが辞書ファイルを変更しないこと（R1・ファイル内容の前後比較）。バックリンクが中間 YAML に書かれること。
- **`unified_page_builder_test.rb`**: バックリンクを中間ファイルから描画すること。前回ビルドの残骸（辞書に backlink_sources を残したフィクスチャ）を**読まない**こと（幽霊リンク回帰）。
- **`unified_index_manager_test.rb`**:
  - 生存 context 温存・stale 除去・空時の複数章補充（R5）。
  - 対象外章（catalog 外・部分実行）の context 温存（R6）。
  - `scanned_chapters` の和集合更新と実在フィルタ（R7）。
  - `[g]`/`[eV]`/`[Hz]` が登録されず警告が出る／`[eV|いーぶい]` は登録される（R9）。
  - 登録要約が既定レベルで出力される（R8・`capture_io`）。
- **`unified_terms_manager_test.rb`**: `save_terms!` が `backlink_sources` を書き出さないこと（R3）。
- **統合（手動）**: §5 の 61-developer トグルを実プロジェクトで実施——(a) 除外ビルドの用語集 HTML に 61-developer への `<a>` が 1 件も無い、(b) `git status` が汚れない、(c) 戻して全章ビルドで完全復元、を確認。`rake test` / `rake test:standard` / `rubocop`。

## 7. 受け入れ条件

- [ ] R1〜R10 をすべて満たす。
- [ ] §5 のトグル運用（除外ビルド → 復帰ビルド）で、幽霊バックリンクゼロ・辞書の git 差分ゼロ。
- [ ] `vs build` 後に `git status` が索引起因で汚れない（R1 の実地確認）。
- [ ] 実原稿での stale 率 0%（報告書 §6.3 の照合スクリプトで検証）。
- [ ] `vs index:auto` 実行で、辞書へ書いた語がコンソールに必ず表示される。
- [ ] 同梱原稿の誤登録（`g`）を棄却済みにし、`[eV]`/`[Hz]` が再登録されないことを確認。
- [ ] root 辞書・scaffold 辞書から `backlink_sources` が除去され、`ruby copy_to_scaffold.rb` 同期済み。
- [ ] CHANGELOG（Fixed: 幽霊バックリンク・context stale・誤登録／Changed: ビルドの辞書読み取り専用化・auto の可視化）。

## 8. スコープ外（将来）

- **ターゲット別章セット**（book.yml で `print_pdf.exclude_chapters` 等）: 現状 print_pdf は
  閲覧用 PDF の導出（§1.7）であり、章を変えるには印刷用の独立レンダリングが要る（別仕様）。
  本仕様の導出原則により、導入時の索引・用語集は追加実装なしで整合する。
- 案 B（context の全面導出化・辞書スキーマからの撤去）: 報告書 §4.3。R5/R6 で実害が
  解消しなかった場合の次段。
- 用語集の掲載を「出現語のみ」へ絞る動作変更: R4 の警告運用で不足が出たら再検討。
- `index:auto` の書き込みをレビュー承認後（apply 時）へ全面移行する構造変更: 影響が広く、
  R8 の可視化で当面の驚きは解消できるため見送り。
