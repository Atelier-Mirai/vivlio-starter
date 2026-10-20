# 章の種類を、catalog.yml のどの区分に書いたかで決める

> 状態: 未実装
> 発端: `vivlio-starter-multivolume-request.md` §2.5（巻ごとの前書き）。2026-10-20 の検討で、区分を番号より**常に**優先し（分冊の本に限らない）、番号と区分の食い違いは知らせると決めた。
> 後続: `multivolume-spec.md` はこの仕様を前提にする。

## 1. いまの姿

- 原稿の種類（前書き・本文の章・付録・後書き）は、**ファイル名の番号の範囲**で決まる（`00` 前書き・`01`〜`89` 本文・`90`〜`98` 付録・`99` 後書き）。
  - `TokenResolver#instantiate_entry`（`token_resolver.rb:280`）は、番号の範囲を先に見て、区分は範囲に当たらないときの予備にしか使わない。番号は 00〜99 のどれかなので、目次に載った原稿で区分が使われることはない。
  - 予備の `section_to_kind` は `"CHAPTERS"` を `:chapters`、`"APPENDICES"` を `:appendices` と複数形のまま返す。`KIND_RANGES` の `:chapter`・`:appendix` と食い違っているが、上の理由で表に出ていない。
- `catalog.yml` に書いた区分の情報は、`CatalogLoader::CatalogEntry` の `section` として `TokenResolver` まで届いている。
- 番号の範囲を直接見ている箇所は 11 ファイル・45 か所ある。中身は次の 3 種類。
  1. **組み立ての順**（4 か所）: `pdf_builder.rb`・`toc_generator.rb`・`epub_builder.rb`・`section_builder.rb`。どれも範囲の定数（`PREFACE_RANGE` など）を持ち、`ChapterConfig.htmls_for_range` で「前書き → 本文 → 付録 → 後書き」の順に HTML を集める。区分の中はファイル名の順（＝番号の順）に並ぶ。
  2. **1 章ずつの判定**（10 か所前後）: `HeadingProcessor` の `main_chapter_token?`・`resolve_main_chapter_display_number`・付録の記号、`CrossReferenceProcessor` の `display_chapter_number_for_filename`・`appendix_letter_for`・`chapter_number_text_for`、`Common.appendix_number_to_letter`、`OutlineExtractor`、`EpubBuilder`（`epub_builder.rb:1336`）。
  3. **範囲の定数を定義し直しているだけの行**（残り）。
- 前書きの番号は `00`、後書きの番号は `99` の一つずつしかない。番号は原稿を見分ける軸なので（`DuplicateNumberCheck`）、`00` の原稿を二つ置けない。巻ごとの前書きを置く方法がない。
- `CatalogUpdater.rename_chapter`（`vs rename`）は、新しい番号の範囲から区分を選び直し、区分が変わるなら行を消して別の区分へ足す。

## 2. 規則

### 2.1 種類の決め方

- `catalog.yml` に載っている原稿は、**書かれた区分**で種類が決まる。`PREFACE` は前書き、`CHAPTERS` は本文の章、`APPENDICES` は付録、`POSTFACE` は後書き。
- 載っていない原稿（目次に入れる前の草稿を `vs build 15` で組むときなど）は、今までどおり番号の範囲で決まる。
- 番号は原稿を見分けるためのもので、重なってはならない。これは今と同じ。
- 同じ原稿を二つの区分に書いたら、どちらの種類か決められないので止める（🔴）。

### 2.2 例

| 原稿 | 書いた区分 | 種類 | 今との違い |
| :--- | :--- | :--- | :--- |
| `00-preface` | `PREFACE` | 前書き | 同じ |
| `20-vol2-intro` | `PREFACE` | 前書き | 今は本文の章として組まれる |
| `98-afterword-vol1` | `POSTFACE` | 後書き | 今は付録として組まれる |
| `90-how-to-ask` | `CHAPTERS` | 本文の章（🟡 を出す） | 今は付録として組まれる |
| `05-glossary` | `APPENDICES` | 付録（🟡 を出す） | 今は本文の章として組まれる |

### 2.3 区分の中の並び

区分の中は、今と同じく**番号の順**に並べる。`catalog.yml` に書いた順ではない。並びの規則まで変えると、今ある本の組み上がりが変わるためである（§7 論点 2）。

前書きを二つ以上置く場合（全体の前書き `00-preface` と、そのすぐ後の `01-howto-read` など）も番号の順になる。

### 2.4 番号の付け方の慣習（マニュアルに書く）

- 前書き・後書きに `00`・`99` 以外の番号を使うときは、**その原稿を置きたい場所のすぐ近くの空き番号**を選ぶ。分冊の本なら、巻の最初の章の一つ前の番号を使う（下巻の章が `21` からなら、下巻の前書きは `20-vol2-intro`）。`contents/` を名前の順に並べたとき、巻の区切りが見える。
- 本文の章の番号は「第 N 章」の N とは別のものである。N は目次での並び順から数えるので、`20` を前書きに使っても、本文の章番号は飛ばない。

## 3. 番号と区分の食い違いを知らせる

### 3.1 知らせる場合

**`CHAPTERS` または `APPENDICES` に、ほかの区分の番号の原稿が書かれているとき**に 🟡 を出す。

- `CHAPTERS` に `00`・`90`〜`98`・`99` の原稿がある
- `APPENDICES` に `00`〜`89`・`99` の原稿がある

`PREFACE`・`POSTFACE` に `00`・`99` 以外の番号を書いた場合は知らせない。前書き・後書きの番号は一つずつしかないので、範囲の外の番号を使う書き方は、巻ごとの前書き（§2.4）のための正しい用法だからである。本文と付録は番号の範囲が十分に広いので、範囲の外の番号を使う理由がほぼない。食い違いは書き間違いか、この変更の前に書いた目次の名残である。

### 3.2 文面

原稿の場所（`catalog.yml` の行）を指す指摘なので 🟡 にし、`vs build` と `vs preflight` の両方で同じものを出す。直し方は、二つの意図のそれぞれについて書く。

```
🟡 config/catalog.yml:38 に、付録の番号の原稿 90-how-to-ask が CHAPTERS に書かれています。本文の章として組みます。
   付録にするなら: この行を APPENDICES の下へ移す
   本文の章にするなら: vs renumber 90-how-to-ask 13-how-to-ask
```

番号を変える案内なので、`vs rename` ではなく別名の `vs renumber` を添える（動きは同じ）。`ChapterNames.rename_command` は `vs rename` を返すので、そのまま使わない。添える番号は、書かれた区分の空き番号（`CatalogLoader.free_number_in_section`）を使う。

### 3.3 置き場所

`Guards::CatalogSectionCheck`（新設・`BaseCheck` の子）。`build_command.rb:81` と `preflight_command.rb:81` の検査の並びに、`DuplicateNumberCheck` と並べて登録する。§2.1 の「二つの区分に書いた」場合の 🔴 も、この検査が出す。

## 4. 変える所

### 4.1 `TokenResolver`

- 目次に載った原稿は、区分から種類を決める。`section_to_kind` を `{ 'PREFACE' => :preface, 'CHAPTERS' => :chapter, 'APPENDICES' => :appendix, 'POSTFACE' => :postface }` の対応表に直す（§1 の複数形の食い違いも、ここで解消する）。
- 目次に載っていない原稿は、今と同じく `KIND_RANGES` から決める。

### 4.2 組み立ての 4 か所

`ChapterConfig.htmls_for_range(base_dir, RANGE, keep_numbers)` を、種類で集める `htmls_for_kind(base_dir, kind, keep_numbers)` に置き換える。HTML の basename を `TokenResolver` で `Entry` にし、`kind` で選ぶ。並びは番号の順（§2.3）。

4 つのファイルがそれぞれ持っている範囲の定数は消す。

### 4.3 1 章ずつの判定

「本文の章か」「付録か」は `Entry#kind` で見る。番号の範囲を見てよいのは、次の所だけにする。

- `TokenResolver::KIND_RANGES`（目次に載っていない原稿の既定）
- **新しい番号を選ぶ所**: `CatalogLoader.free_number_in_section`、`CatalogLoader.section_for_chapter_number`（`vs create` が足す区分）、`ConfigSalvager`（目次を失ったときに `contents/` から組み直す）、`vs create` の雛形選び、`rename.rb` の付録の名前

付録の記号（`Common.appendix_number_to_letter`）は、付録の中での並びの位置から振る。今の規則と同じだが、番号が `90`〜`98` に収まっていることを前提にしない。記号は A〜Z まで振れるようにする（今は `('a'..'i')`）。

### 4.4 `vs rename` と区分

`CatalogUpdater.rename_chapter` は次のように動く。

- 古い番号が書かれた区分の範囲に**合っていた**原稿（`05-x` が `CHAPTERS` にある）は、今と同じく新しい番号の区分へ移す（`vs rename 05-x 92-x` で `APPENDICES` へ移る）。
- 範囲の**外の**番号で書かれていた原稿（`20-vol2-intro` が `PREFACE` にある）は、区分を動かさず、行の名前だけ書き換える。著者が区分を選んで書いたものだからである。

### 4.5 変えない所

- `vs create` は、今と同じく番号から区分と雛形を選ぶ。`vs create 20-vol2-intro` は本文の章の雛形で `CHAPTERS` に足されるので、前書きにするなら著者が行を `PREFACE` へ移す（2 巻目以降の前書きの雛形は `multivolume-spec.md` §10）。
- `DuplicateNumberCheck` は変えない。

## 5. 試験

- `PREFACE` に `20-x` を書いた本で、次を確かめる: 「第 N 章」の数に入らない・本文の前に組まれる・`body` に前書きのクラスが付く・目次と EPUB の nav で前書きの位置に出る・図表番号が章番号で始まらない。
- `CHAPTERS` に `90-x` を書いた本で、本文の章として組まれ、§3.2 の 🟡 が `catalog.yml` の行番号つきで `vs build` と `vs preflight` の両方に出る。
- 同じ原稿を `PREFACE` と `CHAPTERS` に書くと 🔴 で止まる。
- 目次に載っていない原稿を `vs build 15` で組むと、番号の範囲で種類が決まる。
- `vs rename`（`vs renumber`）の §4.4 の 2 通り。
- 回帰: 本書と雛形の全章ビルドで、変更の前後のページ数・目次・PDF のしおりが一致する（どちらも食い違いのない目次なので、何も変わらないはず）。`rake test:standard` も通す。

## 6. 公開

`CHANGELOG.md` に「`PREFACE`・`POSTFACE` に書いた原稿は、番号によらず前書き・後書きになる」ことと、§3 の 🟡 を書く。今の目次に食い違いがある本は組み上がりが変わる（`90-x` を `CHAPTERS` に書いていれば、付録から本文の章になる）ことも書く。

## 7. 論点

| # | 論点 | 推す案 | 代わりの案 |
| :--- | :--- | :--- | :--- |
| 1 | `PREFACE`・`POSTFACE` に範囲外の番号を書いたとき | 知らせない（§3.1） | 💡 で知らせる。正しい用法にも毎回出るので、慣れて読み飛ばされる |
| 2 | 区分の中の並び | 番号の順のまま（§2.3） | `catalog.yml` に書いた順。今ある本の組み上がりが変わりうるので、別の変更として扱う |
