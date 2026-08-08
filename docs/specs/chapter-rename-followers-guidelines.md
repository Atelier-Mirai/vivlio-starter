# 章名を保持するデータを足すときの指針

対象: 章の basename（`21-markdown-tutorial` 等）を保存する設定・データを追加する開発者
策定日: 2026-08-08（`config-extension-guidelines.md` から分離）

---

## 0. この文書の位置づけ

`vs rename` / `vs renumber` で章の番号やスラッグが変わると、その名前を**どこかに写して
持っているデータ**は取り残される。取り残されても実行時エラーにはならないため、
**黙って壊れる**のが厄介なところである。

`config-extension-guidelines.md`（キーの足し方）とも
`config-retirement-guidelines.md`（キーのやめ方）とも主題が違うので分けた。

---

## 1. 追随処理を登録する

設定やデータが章の basename を保持する場合は、`ChapterRename::FOLLOWERS`
（`lib/vivlio_starter/cli/chapter_rename.rb`）へ追随処理を登録する。

```ruby
FOLLOWERS = [
  Follower.new(label: catalog.yml, handler: method(:follow_catalog)),
  Follower.new(label: 索引辞書,     handler: method(:follow_index_dictionary))
].freeze
```

`label` は失敗したときに「何が追随できなかったか」を著者へ伝えるために使う。
1 つが空振りしても他の追随は進むので、label が無いと何が落ちたか分からなくなる。

---

## 2. 章番号で書く設定は登録しない — 案内も出さない

`metrics.exclude_chapters: [00, 90-98, 99]` のように**章番号**で書く設定は、
追随の対象にしない。そして**改番後の案内も出さない**。

`vs renumber` は区分の内側でしか番号を振らないためである。

```ruby
# token_resolver.rb
KIND_RANGES = { preface: 0..0, chapter: 1..89, appendix: 90..98, postface: 99..99 }.freeze
```

通常章は 89 を超えないよう刻み幅が自動調整され（`rename.rb#effective_step_for`）、
付録は 90..98 の中で詰められる。前書 00 と後書 99 は改番対象から外れている。
**区分を指す範囲は、改番で動きようがない。**

なお、単一章の指定（`vs rename 80 90`）は区分をまたげる。本文のつもりで書き始めた章を
付録へ移す、は普通に起きるので、通常の y/N 確認だけで通す。

### 撤回した R4

`chapter-rename-followers-spec.md` R4 は「番号で書かれた設定があれば改番後に案内する」と
定めていたが、**2026-08-08 に撤回した**（コミット `ee615cea`）。理由は 3 つ。

1. 見ていたのが `metrics.exclude_chapters`——`vs metrics` が分量の提案を出さない章を
   決めるキーで、改番とは無関係だった
2. もう 1 件の `chapters` は `book.yml` にも既定値スキーマにも無い。一度も発火しない
3. 「著者が明示的に書いたときだけ案内する」という条件が成立しない。
   詳細は `config-retirement-guidelines.md` §3

---

## 3. 追随を足したら結合テストを書く

単体で `follow!` を検証しても、**呼び出し側が呼び忘れていれば意味がない**。
R4 の起票がまさに「呼ばれていなかった」問題だった。
`test/vivlio_starter/cli/chapter_rename_test.rb` に、`vs rename` を通した検証を置く。
