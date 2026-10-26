# catalog.yml に書いた順に組む

> 実装済み（2026-10-26）。実装記録は §6。

> 関連: `catalog-section-kind-spec.md`（§2.3・§7 論点 2 で「別の変更」として残した並びの規則）、`multivolume-book-matter-spec.md`（R3 の並び）、`multivolume-spec.md`（巻をまたぐ番号・合本）

## 0. 背景

今は、本の並びを二つの決まりで決めている。

1. 区分の順（前書き → 本文 → 付録 → 後書き）。区分は `catalog.yml` に書いた区分で決まる（`catalog-section-kind-spec.md`）。
2. 区分の中は、原稿の番号の順（`ChapterConfig.htmls_for_kind` の `.sort`）。

一方で、部の見出し・全巻目次・「前の章」の検査は `catalog.yml` に書いた順で見る。書いた順と番号の順が違うと、目次と紙面がずれる。

二つの決まりが混ざったのは、原稿の番号が「種類」と「並び」の二役を持っていたからである。前書きの番号は `00` の一つしかないので、分冊の巻ごとの前書きは本文の番号を借りる（`01-volume-1`・`20-vol2-intro`）。そこで種類は区分で決めるようにした。このとき番号の「種類」の役は外れたが、「並び」の役は番号に残った。

その結果、たとえば本全体の前書きを `50-preface` にすると、上巻では巻の前書き `01-volume-1` の後ろに載る。しかも、どの検査も知らせない（2026-10-26 に確かめた）。

番号の順だけにそろえることはできない。番号と区分がいつも一致していなければならず、前書きを `00` の一本しか書けなくなるからである。

## 1. 指針

**`catalog.yml` に書いた順に組む。** 区分の順は今と同じで、区分の中は書いた順にする（2026-10-26 ユーザーと決定）。

- 紙面・目次・部の見出し・全巻目次・しおり・章番号・付録の記号・相互参照が、すべて `catalog.yml` と同じ並びになる。並びの食い違いが、作りの上で起きなくなる。
- 番号の役は、原稿を指す名前（`vs build 12`・`vs rename`）と、`contents/` の中のファイルの並びだけになる。
- 手元の本 5 冊（この本・spiral-ruby など）は、書いた順と番号の順が同じである（`CatalogOrderCheck` で確かめた）。組み上がりは変わらない。

## 2. 要件

### R1: 本の並び

本の並びは、組む範囲（一冊の本・選んだ巻・合本）の目次を、次の順に読んだものにする。

1. `PREFACE` → `CHAPTERS` → `APPENDICES` → `POSTFACE`
2. 区分の中は、書いた順に読む。部の中も同じ。
3. 同じ原稿が二度現れたら、最初の一度だけを残す（合本の共通の付録など。今の `Volumes.merged_sections` と同じ）。

組む範囲の目次は、今の `CatalogLoader.load_catalog`（`Volumes.view`）が返すものである。

### R2: 分冊の本

- **最初の巻の前書きは、本全体の `PREFACE` に書いた順 → 巻の `PREFACE` に書いた順。** 最後の巻の後書きは、巻の `POSTFACE` → 本全体の `POSTFACE`。`multivolume-book-matter-spec.md` R3 の表の「→」を、そのまま紙面の並びとする（2026-10-26 の改訂「→ は所属だけ」を取り消す）。今の `Volumes.sections_of` が返す並びである。
- **合本の本文の章と付録は、巻の順に、巻の中は書いた順。** 後から上巻に足した `26-x` は、合本でも上巻の章の後ろ、下巻の章の前に載る。章番号もこの並びで数える（`26-x` が第3章なら、下巻の最初の章は第4章）。

### R3: 並びを使うものを、すべて R1 にそろえる

今、番号の順に並べ直している所（2026-10-26 に数えた）:

| 所 | 使い道 | 今の並べ方 |
| :--- | :--- | :--- |
| `ChapterConfig.htmls_for_kind` | PDF・EPUB・目次に組む原稿の順 | ファイル名の順 |
| `TocGenerator.generate_toc_html!`・`Toc` の `@targets` | 目次 | 種類 → ファイル名の順 |
| `HeadingProcessor.discovered_main_chapter_tokens` | 章扉の「第N章」 | 番号の順 |
| `CrossReferenceProcessor.main_chapters_from_catalog` | `@chapref` の章番号・図表番号の頭 | 番号の順 |
| `Common.appendix_number_to_letter` | 付録の記号（分冊でない本） | 番号の順 |
| `Volumes.appendix_numbers` | 付録の記号（分冊の本） | 番号の順 |
| `SectionBuilder.chapter_order_from` | しおりの章の順 | 番号の順 |
| `WholeTocGenerator#volume_items` | 全巻目次の前書き・後書き | 名前の順（2026-10-26 に足した） |
| `PreflightCommand#chapter_summary_rows` | `vs preflight` の章ごとの表 | 番号の順 |

すでに書いた順で見ている所（変えない）: 部の見出しと部扉の差し込み（`CatalogLoader.load_part_titles`）・全巻目次の本文の章・「前の章」の検査（`Volumes.reading_order`・`catalog_entries`）・巻の章番号の始まり（`Volumes.chapter_starts`）。

並べ方は一か所で決め、上の所はそれを使う。番号で並べ直す処理は残さない。

### R4: 目次に載っていない原稿

組む HTML の中に R1 の並びに無い原稿があれば、その種類の最後に番号の順で置く。ふつうは起きない（組むのは目次に載った原稿だけ）。並びから黙って落とさないための備えである。

### R5: 単章ビルド・選択ビルド

`vs build 12 11` のように章を選んで組むときも、R1 の並びの順に組む。指定した順ではない（今も指定の順ではなく、番号の順）。章扉の「第N章」は、今までどおり選んだ章の中で数える。

### R6: 番号と並びの食い違いの 🟡 をやめる

`Guards::CatalogOrderCheck`（2026-10-26 に足した。未公開）を外す。書いた順に組むので、食い違いは起きない。

### R7: 目次の書き換え

- `vs create`: 足す行の場所は今までどおり、番号が一つ前の原稿の後ろ。並びを変えたければ、著者が行を移す。
- `vs rename`・`vs renumber`: 同じ区分の中では行をその場で書き換えるので、並びは変わらない（今と同じ）。番号を変えても紙面の並びは動かない、という点が今と違う。
- `vs renumber` を「書いた順に番号を振り直す」ものにするかは、この仕様の外とする（§5 の 1）。

### R8: 文書

- 41 章「config/catalog.yml — 章の構成」: 「載せる順に並べます」に戻す。「区分の中は原稿の番号の順に組みます。並びを変えるときは番号を付け替えます」と、並びの 🟡 の文を、「書いた順に組みます。並びを変えるときは行を移します」に改める。「本全体の前書き・後書き」の節の「番号の順で載ります」を、「本全体の前書きを先に、巻の前書きをその後に」に改める。
- 12 章の「先頭の数字で章の並び順を表します」を、番号はファイルの並びを表し、本の並びは `catalog.yml` で決まる、と改める。
- 24 章で、並び順に触れている所（`catalog.yml` の役目の表など）を確かめる。
- CHANGELOG: `Changed` に並びの決まりを書く。未公開の `Added` の 2 項目（本全体の前書き・後書きの「番号の順で載る」、並びの 🟡）を直す。
- `catalog-section-kind-spec.md` §2.3 と `multivolume-book-matter-spec.md` R3 の改訂注に、この仕様で改めたことを添える。
- 雛形の `config/catalog.yml` の Tips に並びの説明があれば直し、`ruby scripts/copy_to_scaffold.rb` で同期する。

## 3. 実装の見取り図

- **並びを一か所で決める**: `CatalogLoader.book_order`（仮の名前）が、組む範囲の目次から R1 の並びの basename を返す。`Volumes.view` の結果を区分の順に `flatten_section` し、`uniq` する。
- **並べ替えの道具**: 並びに無いものを最後に番号の順で置く比べ方（R4）を、同じ所に置く。R3 の表の所は、`sort`・`sort_by { number }` をこれに置き換える。
- `htmls_for_kind` は種類で選ぶところまでを今のまま残し、並びだけを変える。`keep_numbers` による絞り込みも今のまま。
- `Volumes.appendix_numbers`: 書いた順（`uniq` だけ）にする。
- `WholeTocGenerator#volume_items`: 前書き・後書きの `.sort` を外す（`sections_of` が R2 の並びを返す）。
- `CatalogOrderCheck` と、そのテスト・`build`/`preflight` への登録を外す。
- 前処理の時点（HTML が無い）と後処理の時点（HTML がある）で、同じ並びを使うこと。今は、前処理が catalog から、後処理が `html/` から、別々に起こしている（`cross_reference_processor.rb` のコメント）。どちらも `book_order` に寄せ、組んだ章で絞る。

## 4. テスト

- 一冊の本: `CHAPTERS` を `[13-c, 11-a, 12-b]` と書くと、組む順（`htmls_for_kind`）・目次・第N章・`@chapref` の番号・図表番号の頭・しおりの章の順が、すべて 13 → 11 → 12 になる。
- 付録: `APPENDICES` を `[92-y, 91-x]` と書くと、92 が付録 A、91 が付録 B。分冊の本でも同じ（`Volumes.appendix_letter`）。
- 分冊: 本全体の `PREFACE` が `[50-preface]`、最初の巻が `[01-volume-1]` なら、最初の巻は 50 → 01 の順。合本で、上巻に `26-z` を足すと 11・12・26・21・22 の順で、`26-z` が第3章。
- 部: 部の中の章を書いた順に組み、部扉が部の最初の章の前に入る（部の最初の章が、部の中で一番小さい番号でなくても）。
- R4: 目次に無い HTML は、その種類の最後に番号の順で置かれる。
- R5: `vs build 12 11` は 11 → 12（書いた順が 11 → 12 なら）。
- 既存のテストで、番号の順を前提にしたものは、書いた順と番号の順が同じ並びで書かれているかを確かめる（期待値を変えるものは個別に見る）。
- 実際の本: この本と spiral-ruby（合本・vol1）を組み、変更の前と後でしおりと目次の項目が同じことを確かめる（手元の本は書いた順と番号の順が同じため）。

## 5. 未決

1. **`vs renumber` を書いた順に振り直すものにするか。** 今は番号の範囲（01〜89・90〜98）ごとに、今の番号の順で振り直す。書いた順に組むようになると、「`contents/` の並びを本の並びにそろえる」道具として、書いた順に振る方が役に立つ。ただ、分冊の巻の前書き（`01-volume-1`）を本文の範囲の番号として振り直してしまう、という今の問題も一緒に考えることになる。この仕様では変えず、PLANNED.md に積むことを提案する。

   → **2026-10-26 ユーザーと決定**: この仕様では変えず、PLANNED.md「開発者体験 / CLI UX」に積んだ。

## 6. 実装記録（2026-10-26）

1. **並びは `CatalogLoader.book_order` と `in_book_order` の二つで決める。** `book_order` は `load_catalog`（`Volumes.view`）を区分の順に `flatten_section` して `uniq` したもの。`in_book_order(items, order) { basename }` は並びの位置で並べ、並びに無いものを最後に名前の順で置く（R4）。§2 R3 の表の 9 か所は、どれも `sort`・`sort_by { number }` をこれに置き換えた。`Volumes.appendix_numbers` は `.sort` を外すだけで書いた順になった。
2. **選んで組む章（R5）は、`HeadingProcessor.main_chapter_order` と `CrossReferenceProcessor.main_chapter_order` の両方で並べる。** どちらも `chapter_tokens_override` を指定の順のまま使っていた。
3. **既存のテストで期待値を変えたのは 6 件。** うち 2 件は、番号の順の方が誤っていた。しおりの並びで、`APPENDICES` に書いた `05-glossary` が本文の章の間に入っていた（`catalog_section_kind_test`）。部の中に書いた章が、部をまたいで番号の順に数えられていた（下巻の「応用編」の `21-final` より後ろの部の `02-basics` が先。`volumes_test`）。残りの 4 件は付録の記号・全巻目次の前書きの並びで、書いた順に改めた。
4. **手元の本 5 冊（この本・spiral-ruby の 6 巻と合本など）は、どの巻・どの区分でも書いた順と番号の順が同じだった。** 並べる処理だけを変えたので、組み上がりは変わらない。
