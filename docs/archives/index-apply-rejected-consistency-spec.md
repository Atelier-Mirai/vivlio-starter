# `vs index:apply` が登録済みの語を定義文ごと消す不具合の修正

**状態**: 実装済み（2026-08-21・§8）
**発端**: 2026-08-21、原稿の加筆に合わせて `vs index:auto` → `vs index:apply` を実行したところ、**手書きの定義文を持つ用語集の語が 3 件（`CSS`・`EPUB`・`Ruby`）辞書から消えた**。

---

## 0. 何が起きたか

登録するつもりで実行した `apply` が、**登録していない語を消した**。

```
実行前  terms 171 語（CSS・EPUB・Ruby は flags=g・定義文あり）
実行後  terms 172 語（新規 4 語が入り、上の 3 語が消えた）
```

消えた 3 語は `rejected_terms` へ移ったのでもなく、**単に無くなった**。復旧は Git 履歴からの手作業になった。

**利用者から見た深刻さは高い。** 用語集の定義文は著者が 1 件ずつ手で書いた資産で、機械が作り直せない。しかも `apply` は「辞書を更新しました（索引 172 件・用語集 40 件）」と成功を報告するだけで、消したことを一言も言わない。

---

## 1. 原因は 2 つあり、順に作用する

### 1.1 `[-i]` / `[-g]` が、残す語を除外リストへ書き込む

`unified_index_manager.rb` の「索引のみリジェクト」フェーズ:

```ruby
if index_rejected.any?
  index_rejected.each { @terms_manager.remove_flag!(it['term'], 'i') }
  @queue_manager.save_rejected_terms(index_rejected)   # ← ここ
  changes_made = true
end
```

`[-i]` の意味は「**索引から外す。用語集には残す**」である。レビューファイル自身がそう書いている。

> **説明箇所がない**（書名・副題そのものなど、本全体が主題である語）
> → `[-i]` のまま。指す先のない主要参照は目印になりません。
> **フラグに `g` があれば用語集には残る**ので、ページ番号を並べる代わりに定義文で説明を届けられます

ところが実装は `i` フラグを外したうえで、**その語を `rejected_terms` にも登録する**。結果、`CSS` は

- `terms` に `flags: g`・定義文つきで在籍
- `rejected_terms` にも在籍

という**矛盾した状態**になる。`[-g]` も同じ形をしている。

### 1.2 「Section 4 同期」が、矛盾を「削除」で解決する

同ファイルの最終フェーズ:

```ruby
confirmed_rejected = rejected_section_all.select { ['', ' '].include?(it['flag']) }
                                         .reject { unreject_names.include?(it['term']) }

confirmed_rejected.each do |entry|
  term_name = entry['term']
  next unless @terms_manager.term_names.include?(term_name)

  @terms_manager.remove_term!(term_name)   # ← 定義文ごと消える
end
```

レビューファイルの 4 節「除外済みリスト」に並ぶ語のうち、**チェックが入っていないもの**（＝既定の `[ ]`）を走査し、`terms` にも居たら**エントリごと削除**する。

`[ ]` は 78 件すべての既定値なので、この掃除は**毎回・全件に対して**走る。1.1 で矛盾に落ちた語は、次の `apply` で必ず殺される。

### 1.3 つまり時限式である

| 回 | 操作 | 結果 |
|---|---|---|
| 1 回目 | `[-i]` を適用 | `CSS` は `flags: g` になり、同時に `rejected_terms` へ入る（**矛盾の発生**） |
| 2 回目以降 | 何であれ `apply` | Section 4 同期が `CSS` を `terms` から削除（**定義文の消失**） |

**1 回目は何も壊れていないように見える。** 用語集にも紙面にも `CSS` は出続ける。壊れるのは次回で、そのとき著者は「今回いじっていない語」が消えたことに気づけない。

### 1.4 同じファイルの中で方針が食い違っている

「孤立データ除去」フェーズには、まさにこの事故を避けるための除外がある。

```ruby
# 明示的にリジェクトされた用語は孤立除去の対象外
# （[-i] で i を除去した後に残る g を誤って除去しないため）
explicitly_rejected = (index_rejected + glossary_rejected + both_rejected).map { it['term'] }.uniq
```

`[-i]` した語の `g` を守る意図がコメントで明記されている。**その 20 行後に、Section 4 同期が同じ語を丸ごと消している。**

---

## 2. 決めるべきこと

### 2.1 `terms` と `rejected_terms` は排他である

同じ語が両方に載る状態は**存在してはならない**。載っているなら、それはどちらかの書き込みが間違っている。

### 2.2 除外リストは「候補に出さない語」の記録であって、削除指示ではない

`rejected_terms` の役割は、`index:auto` が候補を並べるときに**再び提示しない**ことである（レビューファイル 4 節の「一度外した語は候補には現れず、末尾の除外済みリストに集まります」）。

登録済みの語を消す権限はここにない。**消すのは著者が `[r]` と書いたときだけ**である。

### 2.3 迷ったら `terms` を残す

`terms` のエントリは著者が書いた定義文・読み・主要参照を抱えている。`rejected_terms` は語と読みとスコアだけである。**情報量の多い側を正とする。**

---

## 3. 修正

### 3.1 `[-i]` / `[-g]` は除外リストへ書かない（1.1 の修正）

フラグを 1 つ外しても語は残るのだから、除外リストへ入れる理由がない。

```ruby
# --- Phase: 索引のみリジェクト（[-i]） ---
if index_rejected.any?
  index_rejected.each { @terms_manager.remove_flag!(it['term'], 'i') }
  changes_made = true
end
```

`save_rejected_terms` の呼び出しを外す。`[-g]` も同様。

**フラグを全部失った語だけは除外リストへ送る。** `[-i]` を `flags: i` の語に当てるとフラグが空になり、`terms` に居残る意味がない。この場合に限り `remove_term!` ＋ `save_rejected_terms` とする（＝ `[r]` と同じ扱い）。

### 3.2 Section 4 同期は、矛盾の解消を「除外リストからの削除」で行う（1.2 の修正）

`terms` に居る語を消すのをやめ、逆に `rejected_terms` の側を掃除する。

```ruby
confirmed_rejected.each do |entry|
  term_name = entry['term']
  next unless @terms_manager.term_names.include?(term_name)

  # 登録済みの語が除外リストにも居る＝過去の書き込みが残した矛盾。
  # 定義文を持つ terms 側を正とし、除外リストから落とす（§2.3）。
  @queue_manager.unreject_term_by_name!(term_name)
  Common.log_debug("除外リストの矛盾を解消: #{term_name}（登録済みのため除外リストから外す）")
end
```

**これは既存データの自動修復も兼ねる。** 手元の本のように既に矛盾を抱えたプロジェクトが、次の `apply` で黙って正しい状態へ寄る。

### 3.3 `[r]` の経路は変えない

著者が明示的に `[r]` と書いたときだけ `remove_term!` が走る。ここは意図どおりなので触らない。

### 3.4 定義文を持つ語を消すときは、消す前に言う

`remove_term!` が定義文を持つ語に当たるときは、既定のログレベルで 1 行出す。

```
🟡 用語集の定義文ごと登録を解除します: CSS
   → 戻すには _index_glossary_review.md の 4 節で [g] を入れて vs index:apply
```

**この修正の要はここにある。** §3.1・§3.2 は今回の経路を塞ぐが、`remove_term!` を呼ぶ経路が将来また増えたときに、同じ事故が黙って起きる。**取り返しのつかない削除は黙って行わない**という規律のほうが、個別の分岐より長持ちする。警告には出現箇所と戻し方を添える（`notation-implementation-guide.md` §6 の流儀）。

---

## 4. 実装するもの

| ファイル | 変更 |
|---|---|
| `cli/index/unified_index_manager.rb` | §3.1（`[-i]` / `[-g]` の除外リスト書き込みを外す・全フラグ喪失時のみ送る）／§3.2（Section 4 同期を反転）／§3.4（削除前の警告） |
| `cli/index/unified_terms_manager.rb` | `remove_term!` が消したエントリを返すようにする（警告の判定に定義文の有無が要る） |

`review_queue_manager.rb` は変更しない。`unreject_term_by_name!` が既に「除外リストから 1 語外す」を持っている。

---

## 5. テスト

`test/vivlio_starter/cli/index/unified_index_manager_test.rb`（無ければ新設）。

| ID | 内容 |
|---|---|
| IA-01 | `[-i]` を `flags: ig` の語へ適用 → `flags: g` になり、**`rejected_terms` に入らない** |
| IA-02 | `[-i]` を `flags: i` の語へ適用 → `terms` から消え、`rejected_terms` に入る（全フラグ喪失） |
| IA-03 | `[-g]` について IA-01 / IA-02 と同型 |
| IA-04 | **回帰の要。** `terms` に `flags: g`・定義文つきで在籍し、かつ `rejected_terms` にも居る語に対して `apply` → **`terms` に残り、定義文も保たれ、`rejected_terms` から外れる** |
| IA-05 | `[r]` は従来どおり `remove_term!` ＋ 除外リストへ登録 |
| IA-06 | 定義文を持つ語を `[r]` で消すとき、既定ログレベルで警告が出る |
| IA-07 | 冪等。同じレビューファイルで `apply` を 2 回走らせても 2 回目に削除が起きない（**1.3 の時限式を直接固定する**） |

**IA-07 が本丸である。** 今回の不具合は「1 回目は正常に見え、2 回目で壊れる」形だったので、1 回だけ走らせるテストでは捕まらない。

---

## 6. 検証

1. 本書の `config/index_glossary_terms.yml` を退避し、`[-i]` を含むレビューを 2 回続けて `apply` する。語数が変わらないこと
2. `vs build` で用語集ページに `CSS`・`EPUB`・`Ruby` が定義文つきで出ること
3. `rejected_terms` に `terms` との重複が 0 件であること

```bash
ruby -ryaml -e '
t = YAML.load_file("config/index_glossary_terms.yml")["terms"].map { it["term"] }
r = YAML.load_file("config/index_glossary_rejected.yml")["rejected_terms"].map { it["term"] }
puts "重複: #{(t & r).inspect}"'
```

**この 1 行を検証手順に残す。** 矛盾は紙面に出るまで気づけないので、機械が見る形にしておく。

---

## 7. 手元のデータについて（2026-08-21 に対処済み）

発覚時点で本書は既に矛盾を抱えていた（`CSS`・`EPUB`・`Ruby` が両方に在籍）。3 語を `terms` へ復元し、`rejected_terms` から外した（78 → 75 件）。コミット `3b2f1a3a`。

**同じ状態のプロジェクトが他にもありうる。** §3.2 の修正が入れば次の `apply` で自動的に解消されるので、移行手順は要らない。

---

## 8. 実装記録（2026-08-21）

§3 のとおり実装した。設計を変えた箇所は無い。

### 8.1 変更したもの

| ファイル | 変更 |
|---|---|
| `unified_terms_manager.rb` | `remove_term!` が削除したエントリを返す。`remove_flag!` は**用語ごと消えたときだけ**そのエントリを返す（残ったときは `nil`） |
| `unified_index_manager.rb` | `[-i]` / `[-g]` は `filter_map` で「消えた語」だけを除外リストへ送る／Section 4 同期を `remove_term!` から `unreject_term_by_name!` へ反転／`[r]` は `remove_term_aloud!` 経由 |

**`remove_flag!` の戻り値を「消えたときだけエントリ」にしたのが要点。** 呼び出し側が `filter_map` を書くだけで「全フラグを失った語だけ除外リストへ」が表現でき、フラグの残数を外から数え直す必要がない。

### 8.2 Section 4 同期で踏んだこと

矛盾を解消したあとに `save_rejected_terms(confirmed_rejected)` をそのまま呼ぶと、**いま除外リストから外した語をその場で書き戻してしまう**。`confirmed_rejected` は除外リスト由来なので、解消した語を除いてから渡す。

```ruby
still_rejected = confirmed_rejected.reject { resolved.include?(it['term']) }
@queue_manager.save_rejected_terms(still_rejected) if still_rejected.any?
```

### 8.3 テストの設定で 2 回つまずいた（実装のバグではない）

**1 度目**: IA-04 を「terms と rejected に居る／レビューの 1 節には無い」で書いたら、Section 4 同期ではなく**孤立データ除去**で消えた。登録済みの語は 1 節に必ず並ぶので、その形が実態と違っていた。

**2 度目**: 1 節へ `[g]` で並べたら、今度は定義文が空になった。ヘルパー `write_review_with_rejected_items` が**説明文の行を書いていなかった**ためで、実物の生成器は書く。`merge_terms!` が空の定義文で上書きするのは正しい動作である。ヘルパーに `definition:` を足して実態へ寄せた。

**再現条件を実物へ寄せないと、直したい経路に到達しない。** どちらも「テストは落ちているが、落ちている理由が違う」形だった。

### 8.4 検証

**修正を一時的に戻すと、新しいテスト 60 件のうち 4 件が落ちる**（IA-01・IA-03・IA-04・IA-07）。戻すと 0 件。テストが不具合を捕まえていることを確かめた。

実データでも §6 の手順を実行した。本書の辞書（175 語・定義文 42 件）で **`vs index:apply` を 2 回続けて実行し、語数・定義文の件数とも不変**、`terms` と `rejected` の重複 0 件。修正前ならここで 3 語が消えていた。

```
1 回目: 175 語 / 定義文 42 件 / rejected 75 件 / 重複 0
2 回目: 175 語 / 定義文 42 件 / rejected 75 件 / 重複 0
```

`config/` の差分は実行時刻の行だけで、内容に変化は無かった（時刻以外の差分 0 行）。
