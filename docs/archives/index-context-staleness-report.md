# 報告書：索引辞書の context が原稿推敲に追従せず stale 化する

対象: `vs index:auto`（`config/index_glossary_terms.yml` の `context:` 抜粋の鮮度）
起票: 2026-07-16（post-replace-list-retirement の残作業——旧 22 章の `post_replace_list.yml` 引用が辞書に残る——を調査中に判明）
位置づけ: **調査・設計案の報告。実装は未着手**。仕様確定は本書のレビュー後。

> **2026-07-16 追記**: レビュー完了・仕様書へ昇格済み →
> [index-glossary-consistency-spec.md](index-glossary-consistency-spec.md)。
> 案 A（§4.2）＋ §5.1 の複数章修正を採用し、§5.2（index:auto の黙った書き込み）も
> 別チケットとせず同仕様へ統合した。昇格時の追加調査で、**catalog.yml の章追加・削除への
> 整合性**（ユーザー起票の新論点）と、本書に無かった逸脱——`vs build` が辞書へ
> `backlink_sources` を書き込み、出現しなかった語は前回値のまま残る（幽霊バックリンク）——
> および `[用語]` 単独記法が単位 `[eV]`/`[Hz]`・フラグ解説 `[g]` を誤登録する機構の特定を
> 加えた。実装は仕様書を正とする。本書は調査記録として保存。

---

## 1. 要旨

`config/index_glossary_terms.yml` の各語が持つ `contexts:`（`chapter` ＋本文抜粋）は、
**索引レビュー画面（`_index_glossary_review.md`）に「この語が本文でどう使われているか」を
著者へ見せるための表示専用データ**である。索引ページの頁番号はビルド時に
`IndexMatchScanner` が実原稿を走査して得るので、この `context` はビルド出力に一切影響しない。

ところがこの `context` は、**原稿を推敲・書き換えても自動では更新されない**。
`UnifiedIndexManager#enrich_terms_with_context` が「**context が空の語だけ**本文から再抽出する」
設計（`unless enriched['contexts']&.any?`）のため、いったん埋まった context は
古くなっても温存され、`vs index:auto` → `apply` を何度往復しても保存されるだけである。

結果、原稿を推敲するほど辞書の context が現実と乖離し、著者は**レビュー画面で嘘の使用例**を
見ることになる。2026-07-16 時点で実測 **15/724 件（2.1%）が stale** だった。

本書は (1) 実害、(2) なぜ起きるか、(3) context の位置づけ（なぜ捨ててよいのか）、
(4) 設計案 3 つの比較と推奨、(5) 調査中に見つかった隣接問題、(6) 移行・テストを報告する。

> 今回（2026-07-16）は辞書側の stale 15 件を機械的に除去して急場をしのいだ（コミット `d25a5a27`）。
> だがこれは対症療法で、**次に原稿を推敲すればまた溜まる**。本書は恒久対策の設計を扱う。

---

## 2. 実害（実測値・2026-07-16 時点）

### 2.1 stale の規模

辞書の全 `context`（724 件）について「抜粋の空白除去版が、参照章の本文（空白除去版）に
含まれるか」を照合したところ、**15 件が現原稿に存在しない**（2.1%）。内訳:

| 由来 | 件数 | 例 |
|---|---|---|
| post-replace-list-retirement | 4 | 「設定ファイル」→ `❷ \`post_replace_list.yml\` を編集する`（22 章の当該行は `custom.css` へ差し替え済み） |
| 編集者コメント節の廃止 | 1 | 「コメント」→ `### 編集者コメント \`@comment ... @commend\``（節ごと削除済み） |
| 他の推敲・機能変更 | 10 | 「CMYK」「ImageMagick」「バックリンク」など（doctor 診断表・入稿表紙節などの文言変更に由来） |

つまり stale は特定タスクの取り残しではなく、**原稿へ手を入れるたびに生じる恒常的なドリフト**である。
今回たまたま `post_replace` を含む 4 件が最初に目についただけで、根は辞書全体にある。

### 2.2 著者が見る画面

レビュー画面「## 1. 登録済み用語の確認」節は、辞書の `context` をそのまま最大 2 件表示する
（`review_markdown_generator.rb:488-493`）。stale なら、著者は**もう存在しない本文**を
「この語の使用例」として提示される。索引に載せるか判断する材料が誤っているということ。

---

## 3. なぜ起きるか（原因の特定）

### 3.1 再抽出は「context が空のときだけ」

`vs index:auto` は登録済み全語に文脈を付けてからレビュー md を生成する
（`unified_index_manager.rb:106` → `enrich_terms_with_context`）。その本体:

```ruby
# lib/vivlio_starter/cli/index/unified_index_manager.rb:564-581
def enrich_terms_with_context(terms, chapters)
  terms.map do |term|
    enriched = term.dup
    ...
    # 文脈がない場合は本文から抽出
    unless enriched['contexts']&.any?          # ★ここが原因
      context = find_context_for_term(term['term'], chapters)
      enriched['contexts'] = context ? [context] : []
    end
    enriched
  end
end
```

`contexts` が 1 件でもあれば `find_context_for_term` は呼ばれない。**既存 context の鮮度は
一度も検証されない**。原稿がどう変わろうと、初回に書かれた抜粋がそのまま残り続ける。

### 3.2 context の書き込み経路（どこで焼き付くか）

| 経路 | 実装 | いつ |
|---|---|---|
| 候補抽出時 | `index_candidate_extractor.rb:161,183,236`（`@term_contexts[term] << {chapter, context}`） | 語が初めて候補になったとき。複数章で出れば複数 context を蓄積 |
| 辞書マージ時 | `unified_terms_manager.rb:244`（`merged['contexts'] = new_data['contexts'] if new_data['contexts']`） | 上記候補が承認され辞書へ入るとき |
| apply 往復時 | `review_markdown_generator.rb:291-294`（レビュー md の出現行を再パースして `contexts` へ） | `vs index:apply` がレビュー md を辞書へ書き戻すとき |

いずれも「**書いた時点の原稿**」のスナップショットで、更新のトリガは存在しない。
apply はレビュー md に表示されていた（＝古いかもしれない）抜粋をそのまま焼き直すだけなので、
往復は鮮度を回復しない。

### 3.3 位置づけ：context はビルドに使われない派生データ

重要なのは、**context がビルド出力に一切影響しない**ことである（調査で確認済み）:

- 索引ページの頁番号・バックリンクは `IndexMatchScanner` が**実原稿を走査**して求める
  （`context` は参照しない）。`lib/` 全体で `index/` 以外に `contexts` の読み手は 0 件。
- `context` の唯一の消費者はレビュー md 生成（`review_markdown_generator.rb`）の表示だけ。

つまり context は「本文から導出できる表示用キャッシュ」であって、辞書が保持すべき一次情報ではない。
であれば **stale を恐れて温存する理由がなく、いつでも本文から再計算してよい**。これが設計案の前提になる。

---

## 4. 設計案

### 4.1 不変条件（どの案でも守るべきこと）

| # | 不変条件 | 理由 |
|---|---|---|
| I1 | context 以外の辞書内容（`term`/`yomi`/`flags`/`definition`/`score`/`approved_at` 等）を変えない | context は表示用。語の同一性・承認状態には触れない |
| I2 | 索引ビルド出力（頁番号・用語集）を変えない | context 非依存なので自明に成立するが、回帰で担保する |
| I3 | 複数章の使用例を失わない | 現状 context は複数章ぶん持てる（§3.2）。再計算で 1 件に痩せさせない（§5.1 の既存バグと関連） |
| I4 | 辞書 YAML の diff を最小に保つ | 語の並び・キー順を保存し、context 更新以外の差分を出さない（レビューしやすさ・git 履歴の意味を守る） |

### 4.2 案 A: `enrich` で「stale を捨ててから足りない分を再抽出」（推奨）

`enrich_terms_with_context` を「空なら抽出」から「**現原稿に無い context を落とし、
不足分を補充**」へ変える。stale 判定は §2.1 で実証した照合（抜粋の空白除去版が
参照章本文の空白除去版に含まれるか）を使う。

```ruby
def enrich_terms_with_context(terms, chapters)
  terms.map do |term|
    enriched = term.dup
    enriched['in_index']    = term['flags'].to_s.include?('i')
    enriched['in_glossary'] = term['flags'].to_s.include?('g')

    fresh = Array(enriched['contexts']).select { |c| context_live?(c, chapters) }  # ★stale を除去
    fresh = collect_contexts_for_term(term['term'], chapters) if fresh.empty?      # ★空になったら補充
    enriched['contexts'] = fresh
    enriched
  end
end
```

- ✅ **`vs index:auto` を回すだけで鮮度が回復する**（著者の通常フローに乗る。専用操作不要）
- ✅ 生きている context はそのまま残す＝I4（無関係な diff を出さない）
- ✅ 「空なら抽出」の既存意図を包含する上位互換
- ⚠️ stale 判定を `enrich` と（今回の）掃除スクリプトで二重に持たないよう、判定を 1 メソッドに集約する
- ⚠️ §5.1 の「再抽出が 1 件しか返さない」既存バグを直さないと、全 context が stale だった語で複数章の例が 1 件に痩せる（I3）。**案 A は §5.1 の修正とセットにする**

### 4.3 案 B: context を辞書に永続化せず、毎回本文から計算する

`context` を辞書スキーマから外し（保存しない）、レビュー md 生成時に全語ぶん本文から計算する。
「派生データは保存しない」という §3.3 の帰結に最も忠実。

- ✅ stale が**原理的に発生しない**（常に本文が真実）
- ✅ 辞書 YAML が大幅に軽くなる（724 context 行が消える）。編集事故も減る
- ❌ 破壊的: 辞書スキーマ変更＋ apply のパース経路（`review_markdown_generator.rb:291`）改修。
  既存辞書からの移行（context キー一括除去）が要る
- ❌ `vs index:auto` は既に全章を走査しているので追加コストは小さいが、
  章を絞った `vs index:auto 21-23` では**対象外の章の語の context が作れない**問題が新たに出る
  （現状は保存済みを使い回すので絞り込みでも表示できる）

### 4.4 案 C: 掃除を独立コマンド化（`vs index:refresh` など）

stale 除去を `enrich` に混ぜず、明示的な保守コマンド（または `vs doctor` のチェック）にする。

- ✅ `vs index:auto` の挙動を変えない（副作用を増やさない）
- ✅ いつ辞書が書き換わるか著者に明示できる
- ❌ **新コマンドを覚えないと stale は消えない**（結局忘れられて溜まる。今回の再発と同じ構図）
- ❌ コマンド追加のコスト（CLI・ヘルプ・テスト）が案 A より大きい

### 4.5 推奨：**案 A（＋ §5.1 の同時修正）**

context は「本文から導出できる表示キャッシュ」なので、著者が必ず通る `vs index:auto` で
自動的に鮮度が回復するのが最も素直（案 A）。案 B は理想だが破壊的で、章絞り込み時の
context 欠落という新たな穴を開ける。案 C は「忘れられて溜まる」今回の失敗を繰り返す。

案 A は「空なら抽出」を「stale を捨てて補充」へ広げるだけで、**既存の通常フローに乗る**のが決め手。
ただし単独では I3（複数章の使用例）を守れないため、§5.1 を同時に直す前提とする。

---

## 5. 調査中に見つかった隣接問題（本件と同じ層）

### 5.1 【要修正・案 A の前提】再抽出が 1 章ぶんの context しか返さない

`find_context_for_term`（`unified_index_manager.rb:613-627`）は**最初にヒットした 1 章で
`return` する**。一方 context は本来複数章ぶん持てる（§3.2 の候補抽出は全章で蓄積）。
現状は「空のときだけ」呼ばれるので影響が限定的だが、案 A で「stale を捨てて再抽出」を
始めると、**複数章で使われる語の使用例が 1 件に痩せる**（I3 違反）。

→ 案 A の実装時に `collect_contexts_for_term`（全章を走査して複数 context を返す版）へ
差し替える。候補抽出側（`index_candidate_extractor.rb`）に既にある多章蓄積ロジックと
判定を揃えられるか検討する（記法の知識を 1 箇所に寄せる）。

### 5.2 【別チケット候補】`vs index:auto` が黙って辞書へ書き込む

`vs index:auto` は「レビュー md を生成するだけ（辞書は apply で書く）」と受け取られがちだが、
実際は実行時に **`merge_terms!` で辞書を書き換える**:

- 手動マークアップ `[語|読み]` の登録（`unified_index_manager.rb:60`）
- 高スコア候補の自動承認（同 `:96`）

しかも結果レポートは `log_info`/`log_success`（`report_auto_results`・`:847-858`）で、
既定ログレベル `warn` では**コンソールに何も出ない**。実際、今回の調査で `vs index:auto` は
無出力のまま辞書へ 5 語（`g`/`閲覧用`/`バイオリン`/`プロンプト`/`ヘッダー`）を自動承認していた
（`g` は 33 章が索引記法 `[g]` を**解説している**例文を実マークアップと誤認したもの）。

「生成コマンドが黙って一次データを書き換える」のは驚き最小の原則に反する。本件（context 鮮度）とは
独立だが、辞書を触るコマンドという意味で同じ層なので記録する。**別チケットで**「index:auto は
辞書書き込み時に要約を必ず表示する」「`g` のような記法解説の誤登録を弾く」を検討したい。

### 5.3 stale 判定の実装メモ（案 A/掃除で共用する）

今回の掃除で実証した判定は次のとおり。案 A でもこの 1 実装を共用すべき:

- 各 context の `context` 文字列と、参照章（`chapter`）本文の**両方から全空白を除去**し、
  前者が後者に部分文字列として含まれれば「生存」、含まれなければ stale。
- 根拠: 保存される抜粋は `extract_surrounding_context` → `smart_context_cut`
  （`unified_index_manager.rb:648,678`）で「改行→空白化・前後を語境界で切り詰め」した
  **本文の連続スライス**なので、空白無視の部分一致で厳密に判定できる（今回 15 件検出→除去後 0 件で確認）。
- 参照章がそもそも存在しない場合（章削除）も stale とみなす。

---

## 6. 移行・テスト

### 6.1 移行

- 案 A なら辞書スキーマは不変。初回 `vs index:auto` 実行時に stale が落ち、diff は
  「stale context の削除＋生存 context の据え置き（＋補充）」だけになる（I4）。
- 既に今回 15 件は除去済みなので、案 A 実装直後の初回実行での差分は小さいはず（回帰確認に使える）。

### 6.2 テスト（`unified_index_manager_test.rb` へ追加）

- 生きている context は保持され、参照章に無い context は落ちる。
- 全 context が stale の語で、本文から**複数章ぶん**再補充される（§5.1・I3）。
- context 以外のフィールド（flags/score/definition/approved_at）が不変（I1）。
- 参照章が削除された語の context が落ちる。
- 索引ビルド（頁番号）が context 変更の前後で不変（I2）。
- `vs index:auto 21-23` の章絞り込みで、対象外章の既存 context を案 A がどう扱うかを固定
  （案 A は「対象外章の本文を読まないので stale 判定できない」→ その章の context は温存が安全。
  この方針をテストで明示する）。

### 6.3 受け入れ確認

- 原稿を 1 箇所推敲 → `vs index:auto` → 該当語の古い context が消え新しい抜粋になる。
- `rake test` / `rake test:standard` / `rubocop` 通過。
- 全語 context の stale 率が実測 0%（§2.1 の照合スクリプトを検証に流用）。

---

## 7. 参考：関連する既存実装

| ファイル | 関係 |
|---|---|
| `lib/vivlio_starter/cli/index/unified_index_manager.rb` | `enrich_terms_with_context`（:564 本件の中心）・`find_context_for_term`（:613 §5.1）・`extract_surrounding_context`/`smart_context_cut`（:648/:678 抜粋生成）・`report_auto_results`（:847 §5.2）・`merge_terms!` 呼び出し（:60,:96 §5.2） |
| `lib/vivlio_starter/cli/index/index_candidate_extractor.rb` | 候補抽出時の多章 context 蓄積（:161,:183,:236。§5.1 の「複数章」の出所） |
| `lib/vivlio_starter/cli/index/unified_terms_manager.rb` | `merge_term_data` の context 上書き（:244）・`save_terms!`（:284 素の `to_yaml`・往復同一） |
| `lib/vivlio_starter/cli/index/review_markdown_generator.rb` | context の表示（:488-493）・apply 時の再パース（:291-294） |
| `lib/vivlio_starter/cli/index/index_match_scanner.rb` | 索引頁番号の実原稿走査（context 非依存の根拠・I2） |
| `config/book.yml` | `index_glossary.context_width`（:338）・`smart_context_cutting`（:341） |
| `config/index_glossary_terms.yml` | 対象の辞書（`terms[].contexts[]`） |
| メモ `index-context-staleness`（Claude 記憶） | 本件の要点と再現手順 |
