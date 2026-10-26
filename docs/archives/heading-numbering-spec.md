# 見出しの番号を振るかどうかを選べるようにする

> 関連: `direct-build-spec.md`（章が一つの配布資料には章番号を振らない。改善案 #84）、`chapter-reference-spec.md`（`@chapref`）、`multivolume-spec.md`（巻をまたぐ番号・全巻目次）

## 0. 背景

vivlio-starter は、本文の章に「第N章」、付録に「付録 A」、節（`##`）に「N-M」「A-1」の番号を振る。番号は章扉・節の見出し・目次・柱・図表番号・`@chapref` に出る。

spiral-ruby（2026-10-26・ユーザー）では、著者が見出しに番号を書いている。

```markdown
# 第1部　基礎編
## 課題33　素数
```

そこへ vivlio-starter が番号を足すので、目次と章扉で「第1章　第1部　基礎編」「1-33　課題33　素数」と番号が二重になる。
課題の番号（課題 1〜180）は巻をまたいで通しで振られていて、章ごとに 1 から数える節番号では表せない。

内部には、章番号を振らない作りがすでにある（`HeadingProcessor.chapter_numbering?`。章が一つだけの配布資料のため。改善案 #84）。ただ著者が選ぶ手段は無く、節番号は「1, 2, …」として残る。

## 1. 指針

**番号を振るかどうかを、著者が選べるようにする。番号の名前（「第N章」）を変える手段は設けない。**

名前を自由に付けられる形（「第{n}部」など）は採らない（2026-10-26 ユーザーと決定）。

- spiral-ruby の課題の番号は、名前を変えられても自動では作れない（巻をまたぐ通し番号）。節の番号はどのみち切ることになる。
- 自由な名前が要る本は、番号を切って見出しに書けば、「序章」「第1部」「課題33」のように何でも書ける。
- 「第N章」は、章扉・目次の CSS・`@chapref` の文字・全巻目次・EPUB と Kindle（Kindle は CSS の数え上げを読まない）に散らばっている。名前を差し替えられるようにすると、手を入れる所が多い。
- 「部」は、章をまとめる単位（部の中扉）としてすでに使っている。章の名前を「第1部」にすると紛らわしい。

## 2. 要件

### R1: `page.heading_numbering` で選ぶ

```yaml
page:
  heading_numbering: chapter_and_section  # 見出しに番号を振るか
                                          # chapter_and_section … 章「第1章」と節「1-1」に振る（既定）
                                          # chapter             … 章にだけ振る
                                          # none                … 振らない（見出しに自分で番号を書く本）
```

- 置き場所は、同じく紙面の構成を決める `page.toc_depth` の隣。
- 節にだけ振る値（`section`）は設けない。使う本が描けない（2026-10-26 ユーザーと決定）。
- 解釈できない値は警告を出して既定値で組む（`index.reference_style` と同じ扱い）。
- `config_keys.rb` に登録し、`config-key-criteria-guidelines.md` の 5 本の軸で確かめる（軸 1「手法パラメータ」には当たらない。本の書き方で答えが変わり、著者が理由を持って選ぶ値である）。

### R2: 値ごとの出方

| 出る所 | `chapter_and_section`（今まで） | `chapter` | `none` |
| :--- | :--- | :--- | :--- |
| 本文の章扉（h1） | 第3章 | 第3章 | 出さない |
| 付録の扉（h1） | 付録 A | 付録 A | 出さない |
| 節の見出し（h2） | 3-2・A-1 | 出さない | 出さない |
| 目次の章・付録 | 第 3 章・付録A: | 第 3 章・付録A: | 出さない |
| 目次の節 | 3-2・A-1 | 出さない | 出さない |
| 全巻目次（`multivolume-spec.md` §9） | 目次と同じ | 目次と同じ | 目次と同じ |
| 柱（`string(chapter-number)`） | 第3章　章題 | 第3章　章題 | 章題 |
| 図表番号 | 図 3-2・表 A-1 | 図 3-2・表 A-1 | 図 2（章ごとに 1 から） |
| `@chapref` | 第3章「章題」 | 第3章「章題」 | 「章題」 |

- `none` の図表番号と `@chapref` は、今の「章番号を振らない」作り（`chapter_numbering?` が偽）と同じ出方にする。
- 部の中扉は今も番号を振っていないので、変わらない。
- 前書き・後書きは今も番号を持たないので、変わらない。

### R3: 目次の番号は、ビルドのたびに作る CSS で切る

目次の番号は HTML ではなく `toc.css` の CSS カウンタで振っている（`content: "第 " counters(toc-list-counter, "-") " 章"` など）。
`toc.css` は著者の本に写される雛形の CSS なので、ここを直すと `vs upgrade` するまで効かない（2026-10-25 に、古い `glossary.css` のままの本で用語集の区切りが崩れた。改善案 #117）。

そこで、番号を切る規則は、ビルドのたびに作り直す `book-settings.css`（`BookSettingsCss`）に出す。`book-settings.css` は各 CSS の後に読むので、`toc.css` の規則に勝つ。`chapter_and_section` では何も出さない（今の紙面のまま）。

### R4: 章扉・節の見出しは、番号の要素を作らない

`HeadingProcessor` は、番号を振らない見出しに `.chapter-number`・`.section-number` の要素を作らない（`data-chapter-number-display` も付けない）。CSS で隠すのではなく、作らない。

- **EPUB の章扉のファクシミリ合成（`EpubBuilder#inject_frontispiece_headings!`）は、番号が無くても作る。** 今は `data-chapter-number-display` が空の h1 を飛ばして章扉と見なさない（`next if number.empty?`）。そのままだと `none` の本では、全章の EPUB の章扉から合成画像が消え、PDF と違う紙面になる。章扉かどうかは番号ではなく章の種類（本文の章）で決め、番号の行を空けて題とリードだけを焼き込む（`epub-frontispiece-facsimile-spec.md`）。
- 内部の `chapter_numbering?` は「章に番号を振るか」、新しく足す `section_numbering?` は「節に番号を振るか」を返す。どちらも `page.heading_numbering` から決める。
- 章が一つだけの配布資料（直接ビルド・改善案 #84）は、今までどおり章番号を振らない（`heading_numbering` が `chapter_and_section` でも）。節番号は `heading_numbering` に従う。

### R5: 分冊の本

- 巻をまたいで番号を続ける仕組み（`chapter_start`・`appendix_start`）は、番号を振る値のときだけ意味を持つ。`none` の本に書いてあっても止めない（使われないだけ）。
- 全巻目次は、詳しい目次と同じく `heading_numbering` に従う。

## 3. 実装の見取り図

- `ConfigKeys`: `%i[page heading_numbering] => Spec[default: 'chapter_and_section']`。
- `HeadingProcessor`: `chapter_numbering?`・`section_numbering?` を `page.heading_numbering` から決める（直接ビルドの #84 の上書きは残す）。`build_h1_number_text` は付録の「付録 A」も `chapter_numbering?` に従わせる。`build_h2_number_text` は `section_numbering?` が偽なら nil を返し、番号の要素を作らない。
- `CrossReferenceProcessor`: 図表番号・`@chapref`・全巻目次の番号（`heading_number_context_for`）は `chapter_numbering?` を見ている。付録の記号（表 A-1）も `none` では外す。
- `BookSettingsCss`: 目次の章・付録・節の番号を切る規則（R3）。
- `Toc`: 必要なら、章の項目のクラスを変えずに済むかを確かめる（CSS だけで切れるなら HTML は今のまま）。
- `EpubBuilder#inject_frontispiece_headings!`: 章扉の判定を番号から章の種類へ。番号の行が空のときの合成画像の組み方（`heading_image_src`）。
- EPUB / Kindle: Kindle は CSS のカウンタを読まないので、目次の番号を文字で入れている所が無いかを確かめる（`kindle-css-compatibility-notes.md`）。
- 文書: `config/book.yml`（`page.toc_depth` の隣）、`contents/41-book-yml.md`、CHANGELOG、雛形の同期（`ruby scripts/copy_to_scaffold.rb`）。

## 4. テスト

- `HeadingProcessor`: 3 つの値で、h1 の「第N章」「付録 A」と h2 の番号の要素があるか・無いか。直接ビルドの章が一つの資料は、`chapter_and_section` でも章番号を振らない。
- `CrossReferenceProcessor`: `chapter` で図表番号が「図 3-2」、`none` で「図 2」。`@chapref` の文字。
- `BookSettingsCss`: `chapter_and_section` では規則を出さない。`chapter` で節の番号を、`none` で章・付録・節の番号を切る規則を出す。
- 全巻目次: `none` で番号が出ない。
- EPUB の章扉: `none` でも本文の章に合成画像が入る。付録・前書き・後書きには入らない（今まで）。
- 解釈できない値で警告と既定値。
- 実際の本で確かめる: spiral-ruby を `none` で組み、目次・章扉・節・柱・図表番号を見る。本書を `chapter` で組み、節の番号だけが消えることを見る。EPUB と Kindle（Kindle Previewer）の目次も見る。

## 5. 決めたこと

1. **`none` の本で、ほかの章の図表を指しても、「図 2」のまま出す（2026-10-26）。**
   - 図表番号は章ごとに 1 から数える。なので、ほかの章の図表を参照（`@ラベル`）で指すと、読者はどの章の図 2 かわからない。ほかの章を指すときだけ「「章題」の図 2」と章題を添える案があった。
   - 今回は作らない。spiral-ruby には、図表を指す参照が一つも無かった（図表のラベル 0・節のラベル 0・参照 0。2026-10-26 に数えた）。画像はあるが、キャプションもラベルも付いていない。使う本が無いうちに作っても、確かめようがない。
   - ほかの章の図表を指す本が出てきたら、その本の実物を見て決める。この件は PLANNED.md「記法・置換ルール」に積んである。

## 6. 実装記録（2026-10-26）

1. **値は `HeadingProcessor.heading_numbering` が読み、`chapter_numbering?`・`section_numbering?` の二つに分けて各所へ渡す。** `chapter_numbering?` は「#84 の上書きが無く、かつ `none` でない」、`section_numbering?` は「`chapter_and_section`」。解釈できない値は既定へ倒すだけで、警告は `BookSettingsCss#heading_numbering_rule` がビルドに 1 回だけ出す（`chapter_pagebreak` と同じ分け方。`heading_numbering` は章ごと・参照ごとに呼ばれる）。テストは `HeadingProcessor.heading_numbering=` で値を差し替える。
2. **付録の記号は、記号を求める所で `chapter_numbering?` を見る。** `HeadingProcessor.build_heading_context` と `CrossReferenceProcessor.heading_number_context_for` は、章番号を振らないとき `appendix_letter` を空にする。`build_h1_number_text` は手を入れずに「付録 A」を出さなくなり、`@chapref`・全巻目次も同じ材料を使うのでそろう。
3. **§3 の見取り図に無かった所が二つあった。**
   - **PDF のしおり（`OutlineExtractor`）。** 章扉に番号が無いと、原稿の番号から「第N章」を補っていた（`resolve_chapter_number_display`）。`none` のまま組むと「第1章 第1部　基礎編」になる。付録には「付録A」を足していた（`appendix_label_for_basename`。ページを探す語にも使う）。どちらも `chapter_numbering?` が偽なら足さない。
   - **全巻目次の節（`WholeTocGenerator#section_list`）。** 番号が nil だと `CGI.escapeHTML(nil)` で落ちるので、番号の要素を作らない形にした。
4. **目次の項（`###`）の番号「3-2-1」も、`chapter` で切る。** R2 の表に項の行が無かったが、項の番号は節の番号を含む。`book-settings.css` の規則は `#toc` を前置し、`toc.css` の付録の節の規則（`li.toc-chapter-appendix > ul .toc-section::before`）にも特異度で勝つ。節の行の字下げ（番号の欄）は残る。
5. **EPUB の章扉の合成画像は、本文の章にだけ入る（R4・§4 の「付録」は誤り）。** 付録は前から simple 版で（`inject_heading_images_into_file!` の `main_chapter_file?`）、R4 と §4 を直した。`inject_frontispiece_headings!` は `next if number.empty?` をやめ、番号も題も無い h1 だけを飛ばす。`HeadingImageComposer` は番号が空なら番号の行を描かないので、合成側は変えていない。
6. **EPUB・Kindle の目次は変わらない。** EPUB は `_toc` を載せず、目次（nav）は各章の `<title>` から作る。目次の番号を文字で入れている所は無かった。
7. **実際の本で確かめた。**
   - spiral-ruby 第1分冊を `none` で組んだ（作業用の写しで）。しおりの「第1章 第1部　基礎編」「付録A 付録　…」が「第1部　基礎編」「付録　…」に、目次の「1-1 課題1」が「課題1」になった。紙面に「第N章」「付録 X」「N-M 題」は 0 件（既定で組むと 200 件・55 件）。章扉は番号の行が空き、柱は「第1部　基礎編」だけ。索引の別の巻の案内は「第3分冊 第6章」が「第3分冊「第6部　数論と暗号編」」になった（`index-other-volume-main-spec.md` の「章番号の無い章は章題」のとおり）。ページ数は既定と同じ 368。
   - 本書を `chapter` で組んだ。行頭の節番号は 214 行から 0 行（残る 10 行は本文の「01-89」などと色の表）。「第N章」は残り、ページ数は既定と同じ 319。
   - spiral-ruby 第1分冊を `none` で EPUB・Kindle（KPF）にも組んだ。本文の章（11・12）の h1 は合成画像になり、alt は「第1部　基礎編 …」と番号が無い。節絵の alt も「課題1　こんにちは 世界」。付録は今までどおり simple 版。目次（nav）にも番号は無い。Kindle Previewer での見た目は確かめていない。
