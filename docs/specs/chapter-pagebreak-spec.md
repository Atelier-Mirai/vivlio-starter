# 章の改丁を任意化する（`page.chapter_pagebreak`）仕様書

> 作成日: 2026-07-31
> ステータス: **仕様（実装待ち）**
> 対象: 章・目次・部扉・付録・用語集・後書き・索引の「右ページ始まり（改丁）」を著者が選べるようにする。併せて `page.section_page_break` を `page.section_pagebreak` へ改名する
> 決定事項:
> - **キーは `page.chapter_pagebreak`（既定 `recto`）**。値は `recto` / `verso` / `any` の 3 つで、`@pagebreak` 記法の値集合（裸＝`any` / `:recto` / `:verso`）とちょうど一致させる。「原稿に書けばその場だけ、book.yml に書けば本全体」で説明が済む
> - **裸の `pagebreak:` は採らない**。`section_pagebreak` の隣に置くと「改ページ全般のスイッチ」に見え、節（h2）の改ページまで面指定が効くと誤解される
> - **`section_pagebreak` と値の語彙は共用しない**。2 つは違う問いを立てている（節＝改ページ**するか**／章＝**どちら側の面か**）。共用すると `chapter_pagebreak: none` という構造上あり得ない値が構文上は書けてしまう（§0.3）
> - **原稿中の `@pagebreak:recto` / `:verso` は本設定より優先**する。局所は大域を上書きするのが一般則であり、記法が黙って効かなくなる事故も避けられる
> - **後方互換は取らない**。`section_page_break` は一般公開中のベータ版には存在しないキーなので、旧キーの受け入れも移行告知も不要
> 関連: `stylesheets/chapter-common.css:8`・`toc.css:26`・`part-title.css:29`・`glossary.css:21`・`index.css:21`・`postface.css:10`・`simple-header.css:24`（`break-before: recto` の 7 箇所）, `lib/vivlio_starter/cli/build/pdf_merger.rb:166`（奥付前の空白ページ挿入）, `lib/vivlio_starter/cli/pre_process/book_settings_css.rb`（生成 CSS の出力先・P3 の条件付き書込みセマンティクス）, `page-break-control-spec.md`（`section_page_break` の導入経緯・改名対象）, `at-directive-tier1-spec.md`（`@pagebreak` 記法）

## 0. 背景・問題

### 0.1 現状

章・目次・部扉・付録・用語集・後書き・索引は、**必ず右ページ（奇数）から始まる**。製本した本の体裁としては正しいが、ページ数は確実に増える。

実測（本書 `vivlio_starter_v1.0.0.pdf`・368 ページ）では、**完全な白紙が 20 枚**あった。全体の 5.4% である。

```
白紙ページ: 7, 23, 25, 31, 49, 135, 177, 179, 191, 209,
            243, 255, 265, 305, 313, 321, 329, 335, 355, 366
```

ページ単価で刷る同人誌・部数の決まった配布資料では、この 20 枚は切りたい。`page.section_pagebreak: false`（節を続けて組む）と同じ動機である。

### 0.2 現状の実現方法

右ページ強制は 8 箇所に分かれている。

| # | 箇所 | セレクタ | 対象 |
|---|---|---|---|
| 1 | `chapter-common.css:8` | `body` | 章・付録 |
| 2 | `toc.css:26` | `body.toc` | 目次 |
| 3 | `part-title.css:29` | `.part-title` | 部扉 |
| 4 | `glossary.css:21` | `body` | 用語集 |
| 5 | `index.css:21` | `body` | 索引 |
| 6 | `postface.css:10` | `body` | 後書き |
| 7 | `simple-header.css:24` | `body.vs-header-simple h1` | simple スタイルの章題 |
| 8 | `pdf_merger.rb:166` | （Ruby） | 奥付を偶数ページ（左）に置くための空白挿入 |

1・4・5・6 は別ファイルだがセレクタはいずれも素の `body` なので、**打ち消しに必要な相異なるセレクタは 4 つ**（`body` / `body.toc` / `body.vs-header-simple h1` / `.part-title`）である。

### 0.3 値の語彙を `section_pagebreak` と共用しない理由

8 通りを検討した結果、共用すると成立しないマスが出る。

| 値 | `section_pagebreak`（節・h2） | `chapter_pagebreak`（章ほか） |
|---|---|---|
| `none` | ○ 改ページしない。本文に続けて組む | **× 構造上あり得ない** |
| `any` | ○ 改ページする。面は問わない（既定） | ○ 本仕様で追加する挙動 |
| `recto` | △ 節ごとに改丁。定義可能だが用途が狭い | ○ 既定 |
| `verso` | △ ほぼ用途なし | △ 用途は限られる |

**`chapter_pagebreak: none` が不可能なのは、章が別文書として組まれているから**である。PDF は章ごとに 1 本ずつ生成して `PdfMerger.merge_all_pdfs!` で連結し、EPUB は 1 章 = 1 XHTML が spine に並ぶ。章が前ページの途中から続くという状態を作れない。共用すると「構文上は書けるがビルド時に 🟡 で拒否するしかない値」が生まれ、設定ファイルとして良くない。

**`section_pagebreak: recto`（節ごとに改丁）は既に局所記法で実現できる**。節見出しの前に `@pagebreak:recto` と書けばよく、「直後が h2 なら recto 指定が優先される」正規化も入っている（`page-break-control-spec.md` §2.1-4）。稀な要求は局所記法で、本全体の方針は book.yml で、と役割が分かれる。

したがって値の型が違う（真偽値 / 列挙）のは不整合ではなく、**問いが違うことの表れ**である。

## 1. 著者向け仕様

### 1.1 `page.chapter_pagebreak`

```yaml
page:
  use: a4_compact

  # 節（## 見出し）をページの先頭から始めるか
  #   true  … 節ごとにページを改める（既定）
  #   false … 節を本文の流れの中に続けて組む（ページ数を抑えたい本・配布資料向け）
  section_pagebreak: true

  # 章・目次・部扉・付録・用語集・後書き・索引を、どちら側の面から始めるか
  #   recto … 右ページ（奇数）から。いわゆる改丁。必要なら白紙が 1 枚入る（既定）
  #   any   … どちらでもよい。白紙が入らずページ数が減る
  #   verso … 左ページ（偶数）から
  # 原稿中の @pagebreak:recto / :verso は、この設定より優先されます
  chapter_pagebreak: recto
```

対象は次の 7 種。いずれも「章と同格の、目次に最上位で並ぶまとまり」である。

- 章（`01`〜`89`）・付録（`90`〜`98`）
- 前書き（`00`）・後書き（`99`）
- 目次・部扉・用語集・索引

### 1.2 `section_page_break` → `section_pagebreak` へ改名

`@pagebreak` 記法が `pagebreak` を一語として定義している以上、`section_page_break` だけが `page_break` と割れているのは不整合である。1.0 前の今のうちに揃える。

**旧キーは受け付けない**。一般公開中のベータ版に `section_page_break` は存在しないため、救済すべき既存プロジェクトが無い。

### 1.3 局所記法が優先される

```markdown
<!-- book.yml: chapter_pagebreak: any -->

@pagebreak:recto

## この節だけは必ず右ページから
```

`@pagebreak:recto` / `:verso` は本設定に関わらず効く。実装上も自然に分かれる——打ち消すのは §0.2 の 4 セレクタだけで、記法が付ける `.vs-break-recto` / `.vs-break-verso`（`chapter-common.css:312-318`）には触れないためである。

### 1.4 ターゲット別の効き方

| ターゲット | 効くか |
|---|---|
| PDF（閲覧用・入稿用） | ○ 本仕様の主対象 |
| クリーン EPUB | — 実質無関係。リフロー型に recto / verso の概念が無く、1 章 = 1 XHTML なので元から章頭で改まる |
| Kindle（KFX） | — 同上 |

**本設定は事実上 PDF 専用**である。book.yml のコメントには書かないが、`41-book-yml.md` には明記する（「EPUB のページ数が減らない」という問い合わせを未然に防ぐ）。

## 2. 実装

### 2.1 スキーマ（`common.rb`）

`default_config_schema` の `page` セクションへ既定値を足す。

```ruby
page: { use: nil, section_pagebreak: true, chapter_pagebreak: 'recto' },
```

### 2.2 生成 CSS（`BookSettingsCss`）

`section_page_break_rule` と同じ「既定では何も出さない」方式を採る（P3 のセマンティクス）。生成物 `book-settings.css` は link 順 `[theme.css, {種別}.css, book-settings.css, custom.css]` の 3 番目に置かれるため、**同特異度なら後勝ちできる**（`frontmatter_generator.rb:146`）。

```ruby
# §0.2 の 7 箇所を覆う 4 セレクタ。元ルールのセレクタをそのまま複製する——
# セレクタがずれると特異度負けして黙って効かなくなる（§4 の回帰テストで固定）。
CHAPTER_PAGEBREAK_SELECTORS = [
  'body',                        # chapter-common.css / glossary.css / index.css / postface.css
  'body.toc',                    # toc.css
  'body.vs-header-simple h1',    # simple-header.css
  '.part-title'                  # part-title.css
].freeze
```

| 値 | 出力 |
|---|---|
| `recto`（既定）・未設定 | **何も出さない**。テーマ CSS の `break-before: recto` がそのまま生きる |
| `any` | `break-before: page; page-break-before: always;` |
| `verso` | `break-before: verso;` |

`any` の置換先を `auto` ではなく `page` にするのは、`.part-title` と `body.vs-header-simple h1` が**文書内の要素**であり、`auto` にすると前の内容に流れ込んでしまうためである。`body` に対する `page` は文書の先頭なので実害が無い（Vivliostyle は分割フローの先頭での break を抑止する）。

`verso` には legacy の `page-break-before` に対応する値が無いので併記しない。KFX はいずれにせよ解さない。

### 2.3 奥付前の空白ページ（`PdfMerger`）

`insert_blank_page_before_colophon`（`pdf_merger.rb:166`）は、奥付が偶数ページ（左）に来るよう必要なら空白を 1 枚挟む。**`any` のときはこの挿入を行わない**。

```ruby
def insert_blank_page_before_colophon(files)
  return files if chapter_pagebreak_any?   # ← 追加
  ...
```

`recto` / `verso` では現行どおり。奥付を左ページに置くのは改丁とは別の慣習だが、「面を問わない」と宣言した本で白紙が残るのは一貫しないため `any` に紐づける。

`print_pdf_builder.rb:224` も同じメソッドを呼ぶので、メソッド内に置けば入稿用 PDF にも同時に効く。

### 2.4 値の検証

列挙値なので、綴り間違いが既定へ黙って戻るのは避ける。`BookSettingsCss.generate!`（ビルド Step 2 で必ず通る唯一の接続先）で一度だけ検証し、🟡 を出して `recto` へ倒す。

```
🟡 config/book.yml の page.chapter_pagebreak の値が不正です（rect）
   使える値: recto / verso / any
   before: chapter_pagebreak: rect
   after : chapter_pagebreak: recto
   今回は既定の recto で処理しました。
```

文面は `warning-messages-actionable` の方針（具体的な before→after ＋ 出現箇所）に従う。`@pagebreak` の不正引数チェック（`markdown_preprocessor.rb:127`）と同じ形である。

### 2.5 改名の置換箇所

`section_page_break` → `section_pagebreak`。

| 種別 | ファイル |
|---|---|
| コード | `common.rb:218`（スキーマ） |
| | `book_settings_css.rb`（`section_page_break_rule` / `section_page_break_disabled?` / `page_cfg[:section_page_break]`） |
| | `page_break_normalizer.rb`（`section_page_break_enabled?` / `CONFIG.page.section_page_break`） |
| 設定 | `config/book.yml:135` → `ruby copy_to_scaffold.rb` |
| 原稿 | `contents/41-book-yml.md:99,104`・`contents/22-extentions.md:1311` → 同期 |
| テスト | `book_settings_css_test.rb`・`page_break_normalizer_test.rb` |

**`CHANGELOG.md` と `docs/archives/` の 2 本（`page-break-control-spec.md` / `heading-metrics-spec.md`）は書き換えない。** 当時の実装を記録した文書なので、名前を遡って直すと記録が嘘になる。改名は今回の CHANGELOG エントリに書く。

## 3. 著者向けドキュメント

- **`config/book.yml`** — §1.1 のコメント。`section_pagebreak` の改名も反映
- **`contents/41-book-yml.md`** — `page` セクションの解説に `chapter_pagebreak` を追加。§1.4 の「PDF 専用」を明記し、白紙 20 枚 / 368 ページの実測値を添えて効果の目安を示す
- **`contents/22-extentions.md`** — `@pagebreak` の節（1264 行〜）に「本全体の既定は `page.chapter_pagebreak` で変えられる。原稿の `@pagebreak:recto` はそれより優先される」を 1 段落追加。1311 行の `section_page_break` を改名
- **`contents/90-notation-cheatsheet.md`** — 変更不要（記法の表であり book.yml の表ではない）
- いずれも `ruby copy_to_scaffold.rb` で scaffold へ同期する

## 4. テスト

1. **`book_settings_css_test`**
   - `recto` / 未設定 → 空文字（既定では何も出さない）
   - `any` → 4 セレクタすべてと `break-before: page` / `page-break-before: always` を含む
   - `verso` → 4 セレクタすべてと `break-before: verso` を含み、`page-break-before` を**含まない**
   - 不正値 → 🟡 が出て、出力は `recto` と同じ（空文字）
2. **セレクタ実在の回帰テスト** — `CHAPTER_PAGEBREAK_SELECTORS` の 4 つが `stylesheets/` に実在すること。既存の `section_page_break` 版と同じ趣旨で、セレクタがずれて特異度負けする事故を固定する
3. **`PdfMerger`** — `any` で `insert_blank_page_before_colophon` が空白を挟まないこと。`recto` では従来どおり挟むこと
4. **改名の回帰** — `page_break_normalizer_test` / `book_settings_css_test` が新キーで通ること。旧キー `section_page_break` を書いても**無視される**こと（互換を取らない仕様の明示）
5. **結合（`rake test:layout`・任意）** — `chapter_pagebreak: any` で全体ビルドし、白紙ページが 0 に近づくこと。`recto` との差分ページ数を記録する

## 5. スコープ外

- **左右非対称な余白（ノド 22mm / 小口 18mm）とノンブル・柱の左右振り分け**（`page-settings.css` の `@page :left` / `@page :right`）は変更しない。本設定は「どちら側の面から始めるか」だけを扱う。片面印刷向けに版面まで均一化したい要求は別仕様とする
- **表紙・裏表紙の結合**（`output.pdf.combined`）は無関係
- **`section_pagebreak` の列挙化** — §0.3 のとおり採らない
- **旧キーの受け入れ** — §1.2 のとおり不要
