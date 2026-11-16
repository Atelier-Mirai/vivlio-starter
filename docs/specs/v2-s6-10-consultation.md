# S6-10 の前に決めること — 改ページの打ち消し・テーマの層の組の 🟡・雛形から消えたテーマのファイル（Fable への相談）

> 作成日: 2026-11-17
> ステータス: **答え済み**（§4。2026-11-17・Fable。仕様への反映は Opus が S6-9b の最初に行う）
> 出自: S6-9 の完了（`theme-contract-spec.md` §11.13・`35f111dc`）。S6-10（配色のテーマと `kindle_tokens:`・S6 の完了の確かめ）に入る前に、`theme-contract-spec.md` §10 の論点 6・7・8 を決める

Fable のセッションに、次の「---」より下をそのまま渡す。

---

2.0 の S6（テーマの仕組みと `standard` の切り出し）は、S6-1〜S6-9 が終わりました。残りは S6-10（配色のテーマと `kindle_tokens:`・S6 の完了の確かめ）だけです。S6-7〜S6-9 の実装の中で、仕様に答えの無い点が 3 つ出て、`theme-contract-spec.md` §10 に論点 6・7・8 として残しました。論点 6 は S6 の完了の条件 2 を満たすのに要るので、S6-10 の前に決める必要があります。論点 7・8 は答えの要る時点が S7・S8 ですが、S6 の中で済ませるか後へ回すかを今決めておきたいので、一緒に相談します。

コードの書き換えはしないでください。読む資料は次のとおりです。

1. `theme-contract-spec.md` §3.1（テーマの形・出力先の CSS）・§3.3（オプション）・§3.4（組み込みの機能と、`standard` の 15 個のキーの振り分け）・§4（標準のテーマ）・§7.2・§7.3（コマンドと `vs upgrade`）・§9 の S6（完了の条件 1〜10 と小段階の表）・§10（論点）・§11.11〜§11.13（S6-7〜S6-9 の実装記録）
2. `css-layer-restructure-spec.md` §2.1（層の順序）・§4.3（層を外しても結果が変わらないことの保証）・§4.5（報告のしかた）・§7.1（`custom.css`）
3. `chapter-pagebreak-spec.md`・`page-break-control-spec.md` §2.2（改ページの設定の元の仕様）
4. `v2-migration-plan.md` §3.6（設定の組み合わせ）・§4.1（r3 の作り方）
5. 実物: `lib/vivlio_starter/cli/pre_process/book_settings_css.rb` の 420〜560 行（改ページの打ち消し）・`post_process/page_break_normalizer.rb`・`build/chapter_lead_check.rb`・`themes/standard/`（`theme.yml`・`simple-header.css`・`image-header.css`・`kindle.css`）・`lib/vivlio_starter/cli/upgrade.rb`（`stale_system_pages`）

## 1. 今の状態（S6-9 の後）

| 項目 | 今 |
| :--- | :--- |
| 基準 | r2。S6 の完了も r2 と比べる。r3 は S6 の完了のコミットの後、S7 の前に 1 回だけ作る（`v2-migration-plan.md` §4.1） |
| テーマ | `themes/standard/`（`theme.yml`・`simple-header.css`・`image-header.css`・`epub.css`・`kindle.css`・`images/`）。`options:` と `features: [frontispiece, ornament]` を宣言済み。`style` の値で機能を入り切りする（§3.4 の決め 2） |
| 完了の条件 2 | `BodyClassInjector` は済み（`body_class:` の宣言から付ける）。`BookSettingsCss` のうち、オプションの書き出し・機能の変数・扉絵の `@page` は済み。**改ページの打ち消しだけが `vs-header-*` を直接書いている**（下の 2.1） |
| コマンド | `vs theme`・`theme:add`（同梱の名前・ディレクトリ・zip）・`theme:check`・`theme:new`（S6-8） |
| `vs upgrade` | 雛形の `themes/` のうち、lock に記録のあるテーマだけを更新する。lock に記録の無いテーマは「著者が入れたテーマ」として触らず、契約の版だけを 🟡 で見る（S6-9） |
| テスト | `rake test` 4,483 件が通っている |

S6-10 で作るもの（小段階の表のとおり。今回の問いの前提）:

- `kindle_tokens:` の書き出し（target 層の `kindle-tokens.css` の直後に `body.vs-kindle { … }`）。
- 材料の配色のテーマ `standard-mono`（`test/vivlio_starter/fixtures/themes/standard-mono/`。`extends: standard` と `tokens:`・`kindle_tokens:` だけ）。
- S6 の完了の確かめ: 完了の条件 4・10、全部の比べ（B1 の四つの出力先・B2・B3・B4・単章・preflight）、`rake test:layout`・`rake test:standard`・`rake test:release`。

## 2. 問い

### 2.1 改ページの打ち消しが写すテーマの選択子（論点 6）

**今の作り。** `book.yml` の二つの設定は、テーマや部品の CSS が書いた改ページの規則を、settings 層の規則で打ち消して働く。打ち消しは「元の規則の選択子をそのまま写す」形で、テーマの選択子が `BookSettingsCss` の定数に入っている。

| 設定 | 打ち消しの選択子（`BookSettingsCss` の定数） | そのうちテーマのもの |
| :--- | :--- | :--- |
| `page.section_pagebreak: false`（節で改ページしない） | `SECTION_PAGEBREAK_SELECTORS` の 3 つ: `body.vs-header-image .section-topic h2`（`image-header.css`）・`body.vs-header-simple h2`（`simple-header.css`）・`article.vs-section-topic-epub`（vs の `parts/epub-reflow.css`） | 2 つ |
| 同上の章扉の保護（扉絵の章で、最初の節だけは次のページから始める） | `body.vs-header-image:not(.vs-epub) section.level2:first-of-type > .section-topic h2:not(.vs-break-merged)` | 1 つ（扉絵の機能に固有） |
| 同上の Kindle | 規則ではなく変数。`:root` に `--section-break-before: auto`・`--section-page-break-before: auto` を書き、`themes/standard/kindle.css` の `body.vs-header-simple.vs-kindle h2` が `break-before: var(--section-break-before, page)` で読む（この選択子は詳細度が高く、規則では打ち消せないため） | 変数の名前が `--book-*` でない（公開する変数の一覧に無い） |
| `page.chapter_pagebreak: any`・`verso`（章などを右ページ始まりにしない） | `CHAPTER_PAGEBREAK_SELECTORS` の 5 つ: `body`・`body.toc`・`body.whole_toc`・`.part-title`（vs の `parts/`・`pages/`）と `body.vs-header-simple h1`（`simple-header.css`） | 1 つ |

- 選択子を写すのは、平らな CSS（EPUB と Kindle）で詳細度が勝ち負けを決めるためである。PDF（層あり）では settings 層が theme 層より上なので、詳細度に関係なく勝つ。`chapter_pagebreak` は PDF だけに効く（EPUB には面の区別が無い）。`section_pagebreak` は PDF・EPUB・Kindle の全部に効く。
- 本書（B1）は `section_pagebreak: false`・`chapter_pagebreak: any` で、打ち消しの規則が出力に入っている。B2（`style: simple`）も同じ。B3 は `true`・`recto` で、打ち消しを出さない。
- 原稿の `@pagebreak`（utilities 層）は settings 層より下にある。今の打ち消しは記法のクラス（`.vs-break-*`）を選ばないので、記法の指定が設定に勝つ。章扉の保護は、記法の改ページに一本化した `h2`（`vs-break-merged`）を選ぶ対象から外している（`css-layer-restructure-spec.md` §2.4）。

**`BookSettingsCss` の外にも、同じ前提のコードがある。** 完了の条件 2 が名指ししているのは `BodyClassInjector` と `BookSettingsCss` だけだが、次の 2 か所も `vs-header-image` を直接読んでいる。どちらも「この頁は扉絵の章扉か」を body のクラスで判定している（付録は `style: image` でも `vs-header-simple` なので、設定ではなくクラスを見る）。

| ファイル | していること |
| :--- | :--- |
| `post_process/page_break_normalizer.rb`（82 行） | `section_pagebreak: false` のとき、章扉の保護が効く頁（`vs-header-image`）では章の最初の節の前の `@pagebreak` を一本化し、それ以外の頁では一本化しない（`chapter_frontispiece_guard_rule` と対） |
| `build/chapter_lead_check.rb`（117 行） | 扉絵の章扉に載る章リードの長さを検査する。章を選ぶのに `vs-header-image` を見る（機能が有効かは S6-7 から `BuildPlan.features.frontispiece` で見ている） |

**S8 との関係。** `bunko`（縦書きの小説の既定のテーマ）は、章の改丁と節の改ページを自分の CSS に書くはずで、そのとき同じ問題がテーマの数だけ起きる。テーマを作る人は Ruby を書けないので、今の形のままだと、`page.section_pagebreak` と `page.chapter_pagebreak` は `standard` でしか働かない。

**候補（どれにも確かめていない点がある）。**

- (a) **テーマが打ち消す選択子を宣言する。** `theme.yml` に、例えば `pagebreaks: { section: [<選択子>…], chapter: [<選択子>…] }` を書き、vs がそれを写して打ち消す。今の仕組みのまま一般化できる。テーマを作る人は「自分の CSS のどの規則が改ページか」を二重に書くことになり、ずれても誤りにならない（設定が効かなくなるだけ）。`vs theme:check` で、宣言した選択子がテーマの CSS に `break-before` を持つ規則としてあるかは検査できる。
- (b) **テーマの CSS が、改ページを公開する変数で読む。** `break-before: var(--book-section-break, page)` のように書き、settings 層が変数の値だけを書く。Kindle はすでにこの形（`--section-break-before`）で、`LiteralResolver` が解く。選択子を写す必要が無くなる。**未確認:** Vivliostyle が `break-before` の `var()` を改ページに使うか（PDF）。クリーン EPUB は `var()` のまま読者の処理系に渡るので、Apple Books などが `break-before` の `var()` を解すか。`page-break-before`（Kindle 向けの古い書き方）は値の組が違う（`always`・`auto`）ので、変数が 2 つ要る。Opus が 1 章の確かめで 30 分ほどで調べられる。
- (c) **改ページの規則をテーマから vs の部品へ移す。** 章の改丁と節の改ページは vs が契約 HTML の要素（`section.level1 > h1`・`section.level2 > h2` など、テーマのクラスを含まない選択子）で書き、テーマは改ページを書かない。vs は自分の選択子を知っているので、打ち消しは今の形のまま書ける。章扉の保護は、`@page :nth(1)` と同じく機能 `frontispiece` の骨格として vs が持つ（§3.4 の決め 3 と同じ理屈）。テーマにできることは減る（「この見た目の節見出しでは改ページしない」をテーマが決められない）。`standard` の 3 つの規則を parts 層へ移すと、詳細度が同じ組で勝つ側が入れ替わりうるので、S6-4 と同じ比べが要る。
- (d) **平らな CSS の生成で、settings 層の打ち消しを勝たせる。** S3-3b で `custom.css` に入れた仕組み（平らな CSS でも層の外の規則を勝たせる）を settings 層の改ページの宣言にも当て、打ち消しを契約 HTML の要素だけの選択子で書く。選択子を写す必要が無くなる。広い選択子で書くと、今は選ばずに済んでいる要素（`@pagebreak` の記法・扉絵の章の最初の節）を除く条件を、打ち消しの側で書き足すことになる。

**決めてほしいこと:**

1. テーマの改ページを、設定（`section_pagebreak`・`chapter_pagebreak`）がどう打ち消すか。上の候補か、ほかの形。
2. 章扉の保護（扉絵の章の最初の節）と、`PageBreakNormalizer`・`ChapterLeadCheck` の「この頁は扉絵の章扉か」の判定を、どこが持つか。機能 `frontispiece` が、自分の効くページの種類（章だけで、付録は含まない）を宣言する形にするか。今の機能の有効は本全体で一つ（`BuildPlan.features.frontispiece`）で、ページの種類ごとの有効は持っていない。
3. 1・2 の作業を S6-10 に入れるか、S6-10 の前に別の小段階（S6-9b など）を置くか。改ページの規則は B1・B2 の出力に入っているので、どの形でも前後の比べ（PDF の画素・EPUB の計算値・Kindle の中間生成物）が要る。
4. Kindle の変数 `--section-break-before`・`--section-page-break-before` の名前。公開する変数（`--book-*`）にするか、vs の内部の変数（`--_*`）にするか、今の名前のままにするか（§5.1 の決まりとの関係。今は `themes/standard/kindle.css` というテーマのファイルが、vs の書き出す変数を読んでいる）。

### 2.2 `vs build` が著者の入れたテーマの層の組を 🟡 にする時期（論点 7）

**今の作り。** `css-layer-restructure-spec.md` §4.3 の「扱い（S6 以降）」は、「著者が入れたテーマでは、`vs build` が要素ごとの判定で、層ありで勝つ側が theme 層の組を 🟡 で示す」としている。S6-8 では作っていない（小段階の表に無かった）。今の `vs build` は、テーマに依らず `--log=debug` のときだけ要素ごとの判定を行い、組を `log_debug` に出す（`Css::Bundle.report_epub_inversions!`・`build/finalizers/inversion_report.rb`）。

- 「著者が入れたテーマ」は、S6-9 から `config/scaffold.lock` に記録が無いテーマとして見分けられる。
- `vs theme:check` は、静的な判定で「起きうる組」を 💡 で示している（S6-8 の決め 1。`standard` では 39 組で、どれも同じ要素にならない組）。
- 要素ごとの判定に掛かる時間は測っていない。今は B1・B4 の確かめで `--log=debug` のときに走らせているだけで、所要時間を記録していない。
- `css-layer-restructure-spec.md` §4.5 は、著者に対して「テーマの CSS で Kindle に落ちた宣言は知らせない（著者には直せないため）」としている。層の組の 🟡 も、著者が直せるものではない（直すのはテーマの CSS）。一方、著者が自分で書いて自分の本で使うテーマ（`vs theme:new`）では、著者がテーマを作る人でもある。
- 🔴/🟡/💡 は「原稿の場所を指すか」で選ぶ、という vs の決まりがある（場所を指す指摘は 🟡）。テーマの組は原稿の場所を指さない。

**決めてほしいこと:**

1. `vs build` で知らせるか。知らせるなら、誰に（同梱でないテーマの全部か、`vs theme:new` で作ったテーマだけか、など）、何の印（🟡 か 💡 か）で、何を示すか（テーマの規則の場所・相手の vs の規則・直し方）。
2. 入れる時期: S6-10・S7（`theme:add` で git・npm のテーマを入れられるようになる時点）・2.0 の後、のどれか。知らせないなら、§4.3 の「扱い（S6 以降）」をどう書き直すか。
3. 所要時間を先に測る必要があるか（あるなら、どの本で・何を上限とするか）。

### 2.3 雛形から消えたテーマのファイル（論点 8）

**今の作り。** `vs upgrade` は、雛形から消えたファイルを本から消さない。lock から記録が消えるだけである（S6-9 の決め 6。雛形のほかのファイルと同じ扱い）。

- テーマのディレクトリでは、これが効き目の違いになる。`styles:` に並べる CSS は、`theme.yml` から外れれば読まれない。しかし出力先の CSS（`epub.css`・`epub-<種類>.css`・`kindle.css`・`kindle-<種類>.css`）は、`theme.yml` に書かず「置けば読まれる」（§3.1）。雛形がこれを消しても、本に残って効き続ける。画像は残っても害は無い。
- `vs theme:add` で同じ名前のテーマを入れ直すときは、本の側にだけあるファイルを「削除」として確認の一覧に出し、ディレクトリごと置き換える（S6-8 の決め 5）。`vs upgrade` とは扱いが違う。
- `vs upgrade` には、残っていると紙面を誤解させるファイルを、退避してから消す前例がある（`contents/` に残った扉・免責・奥付の原稿。`upgrade.rb` の `stale_system_pages`・改善案 #114）。
- 今の同梱のテーマは `standard` だけで、ファイルを消す予定は今のところ無い。S8 で `bunko` を書くときに、`standard` の規則を動かす（§10 の論点 5）可能性がある。

**決めてほしいこと:**

1. 雛形から消えたテーマのファイルを、`vs upgrade` が本から消すか。消すなら、どの条件で（lock に記録があり、本の側で変えていないファイルだけ・出力先の CSS だけ・全部、など）、どう見せるか（確認の一覧に「削除」として出す・退避する）。
2. 著者が変えたファイルが雛形から消えた場合の扱い。
3. 作る時期: S6-10・同梱のテーマからファイルを消す変更をするとき・S11（1.x の本を上げる手順）のどれか。

## 3. 答えの形

- §2 の各問いの決定と理由を、`v2-s6-consultation.md` §4 と同じく、この文書の末尾に「答え」の節として書く。
- §2.1 で小段階を足すなら、`theme-contract-spec.md` §9 の S6 の小段階の表と同じ形（「小段階・作るもの・確かめ」の 3 列）で書く。確かめには、比べる出力（B1・B2 など）と比べ方（PDF の画素・EPUB の計算値・Kindle の中間生成物）を書く。
- §2.1 の候補 (b) を選ぶ場合など、決める前に確かめが要るなら、確かめる内容と、結果ごとの手（成り立たなければどうするか）を書く。確かめは Opus が行う。
- 決定を移す先の仕様書と節を挙げる（移すのは Opus が行う）。

---

## 4. 答え（Fable・2026-11-17）

仕様書のほかに、実物（`book_settings_css.rb` の改ページの節・`page_break_normalizer.rb`・`chapter_lead_check.rb`・`themes/standard/`・`stylesheets/pages/chapter.css`・`utilities/pagebreak.css`）を読んで決めた。リポジトリのコードは書き換えていない。候補 (b) の未確認の点は、scratchpad の小さな HTML で確かめた（4.2）。

### 4.1 決めたこと

| # | 問い | 決定 |
| :--- | :--- | :--- |
| 2.1-1 | 打ち消しの形 | 候補 (b)。テーマの CSS は、章と節の改ページを公開する変数で読む。settings 層は変数の値だけを書き、テーマの選択子を写さない。vs 自身の規則（`body`・`body.toc`・`body.whole_toc`・`.part-title`・`article.vs-section-topic-epub`）の打ち消しは今の形のまま残す（4.3） |
| 2.1-2 | 章扉の保護と「扉絵の章扉か」の判定 | 機能 `frontispiece` が持つ。効くページの種類は `chapter` だけで、機能の側に定数で書く。判定は「機能が有効」かつ「`body` に `chapter` がある」。テーマのクラスは読まない（4.4） |
| 2.1-3 | 入れる場所 | S6-10 の前に小段階 S6-9b を置く（4.5） |
| 2.1-4 | 変数の名前 | 公開する変数にする。`--book-section-break-before`・`--book-section-page-break-before`・`--book-chapter-break-before`。別名は置かない（4.3） |
| 2.2 | `vs build` の 🟡 | 作らない。`vs build` は今のまま `--log=debug` のときだけ組を出す。§4.3 の「扱い（S6 以降）」を書き直す。所要時間は測らなくてよい（4.6） |
| 2.3 | 雛形から消えたテーマのファイル | `vs upgrade` が消す。条件は「lock に記録のあるテーマ」の「lock に記録のあるファイル」で「本の側の中身が lock の記録と同じ」。退避してから消し、計画に「削除」として出す。著者が変えたファイルは残して 🟡。S6-10 で作る（4.7） |

### 4.2 確かめた結果（候補 (b) の未確認の点）

Vivliostyle（cli 11.3.3・core 2.45.1。作業ツリーの `node_modules`）で、層つきの CSS を持つ 1 枚の HTML を組んだ。tokens 層の `:root` に既定値、theme 層に `body.x h2 { break-before: var(--book-section-break-before); }` と `body.x h1 { break-before: var(--book-chapter-break-before); }`、settings 層の `:root` に値を置いた。

| settings 層の値 | 結果 |
| :--- | :--- |
| 無し（既定は節 `page`・章 `recto`） | 7 ページ。h1 は奇数ページ（白紙を挟む）、h2 ごとに改ページ |
| 節 `auto` | 5 ページ。h2 は続けて組まれ、h1 は奇数ページ |
| 節 `auto`・章 `page` | 3 ページ。白紙なし |
| 章 `verso` | 6 ページ。h1 は偶数ページ |

`var()` の値は、`page`・`auto`・`recto`・`verso` のどれも改ページに使われた。層をまたぐ定義（tokens 層の既定を settings 層が上書き）も働いた。この結果は `vivliostyle-css-pitfalls-notes.md` に「使える書き方」として 1 項足す（Opus）。

確かめていない点は一つ残る。クリーン EPUB は `var()` のまま読者の処理系に渡る。Apple Books（WebKit）は `var()` をどのプロパティでも計算値の段で解くので働くはずだが、実物では見ていない。S6-9b の確かめに入れた（4.5）。クリーン EPUB は色も書体も `var()` に頼っているので、`var()` を解さない処理系への新しい依存は増えない。

### 4.3 改ページを変数で読む（問い 2.1 の 1・4）

**決定。** テーマは、章と節の改ページを次の 3 つの公開する変数で書く。既定値は vs の `stylesheets/tokens.css` に置く。

| 変数 | 既定値 | settings 層が書く値 |
| :--- | :--- | :--- |
| `--book-section-break-before` | `page` | `page.section_pagebreak: false` のとき `auto` |
| `--book-section-page-break-before`（Kindle 向けの古い書き方の値） | `always` | 同、`auto` |
| `--book-chapter-break-before` | `recto` | `page.chapter_pagebreak` が `any` のとき `page`、`verso` のとき `verso` |

- 「書かない条件では宣言しない」は今と同じにする（`true`・`recto`・未設定では何も書かない）。
- `standard` の書き換えは 4 か所。`simple-header.css` の `body.vs-header-simple h1` の `break-before: recto` → `var(--book-chapter-break-before)`、同 `body.vs-header-simple h2` と `image-header.css` の `body.vs-header-image .section-topic h2` の `break-before: page` → `var(--book-section-break-before)`、`kindle.css` の `body.vs-header-simple.vs-kindle h2` の 2 つの変数の名前。選択子は変えない。`kindle.css` の `var()` の予備の値（`, always`・`, page`）は、既定値が `tokens.css` に入るので外す。
- `BookSettingsCss` からは、`SECTION_PAGEBREAK_SELECTORS` の前の 2 つと、`CHAPTER_PAGEBREAK_SELECTORS` の `body.vs-header-simple h1` を消す。vs 自身の選択子は定数に残し、今のとおり規則で打ち消す。vs が自分の規則の選択子を知っているのは契約の内側で、変数に直すと `book-settings.css` と部品の両方の字面が変わり、比べる対象が増えるだけである。
- `any` のとき `body.vs-header-simple h1` に書いていた `page-break-before: always` は無くなる。PDF では `break-before: page` と同じ意味で、Kindle は `kindle.css` の `body.vs-header-simple.vs-kindle h1` がもともと `always` を書いている。Kindle の中間生成物に差が出たら、差の中身を記録して相談する（黙って規則を足さない）。
- **名前。** 公開する変数にする理由は、テーマの CSS が読むからである（§5.1 の表の「誰が読むか」）。`--_*` はテーマが読めない決まりなので使えない。今の `--section-break-before` は S3-3a で v2 に入れた名前で、1.x の公開版には無い。`Css::LegacyTokens` に載せず、別名も置かない。
- **理由。** (a) の宣言は、テーマを作る人に同じ選択子を CSS と `theme.yml` の 2 か所に書かせ、ずれても誤りにならない。Kindle の高い詳細度の規則は (a) では打ち消せず、今すでに変数を併用している。(c) はテーマが改ページを決められなくなり、`standard` の 3 規則を parts 層へ移す入れ替わりの確かめも要る。(d) は、今は選ばずに済んでいる要素を除く条件を打ち消しの側に書き足すことになり、`@pagebreak` の記法との勝ち負けを作り直すことになる。(b) は、選択子も詳細度も関係が無くなり、PDF・EPUB・Kindle の 3 つが同じ仕組みになる。
- **テーマの `tokens:` で既定を変えられる。** 公開する変数なので、節で改ページしないテーマは `tokens:` に `section-break-before: auto` を書ける。ただし、雛形の `book.yml` は `section_pagebreak: true` を書いており、今の決まりでは `true` は何も書き出さないので、テーマの値が通る（著者が `true` と書いても改ページしない）。この食い違いは `standard` では起きない。`bunko` の既定の決め方（`BookProfile` の種類の既定値で `false` にするか、`true` のときも値を書き出すか）は S8 の仕様で決める。S6 では決めない。
- **`vs theme:check` に足す検査。** テーマの `styles:` の CSS で、最後の複合選択子が `h1` か `h2` の規則に、`var()` を使わない `break-before`（`avoid`・`auto` を除く）があれば 🟡。出力先の CSS（`epub*.css`・`kindle*.css`）では `h2` だけを見る（章の改丁は PDF だけの設定で、Kindle の章見出しは値を固定してよい）。文面は「`page.section_pagebreak`（または `chapter_pagebreak`）の設定が、このテーマでは効きません」と、書き直した 1 行を示す。`vs theme:new` の組版のテーマの雛形の注釈にも、変数で書く例を入れる。

### 4.4 章扉の保護と、扉絵の章扉の判定（問い 2.1 の 2）

- **扉絵の効くページの種類は `chapter` だけで、vs が決めている。** 扉絵の `@page :nth(1)` は、章だけが読む `stylesheets/pages/chapter.css` にある（§3.4 の決め 3）。付録に扉絵が出ないのは、テーマが `vs-header-simple` を付けるからではなく、この置き場による。`Theme::Features::Frontispiece` に `PAGE_KINDS = %i[chapter]` を置き、「このページは扉絵の章扉か」は「機能が有効（`BuildPlan.features.frontispiece`）」かつ「`body` のクラスに `chapter` がある」で判定する。`chapter` は契約 HTML が保証するページの種類のクラスである（§2.2）。窓口は機能の側に 1 つ作る（例 `Theme::Features::Frontispiece.page?(body_classes)`）。
- `standard` では、この判定は今の `vs-header-image` と同じページを選ぶ（`chapter` の `body_class:` が値で決まり、`image` のときだけ機能が有効なため）。`PageBreakNormalizer#breaking_h2_scope` と `ChapterLeadCheck#collect_leads` をこの窓口に替える。
- **章扉の保護は、機能 `frontispiece` が settings 層に書く。** 今の `chapter_frontispiece_guard_rule` を `Theme::Features::Frontispiece` へ移し（`page_rule` と同じ並び）、選択子の `body.vs-header-image` を `body.chapter` に替える。出す条件は今と同じ（`section_pagebreak: false`）に、機能が有効であることを足す。
  - テーマの CSS に置かない理由: 保護は「全面の扉絵のページに本文を流し込まない」という機能の骨格で、扉絵を使うテーマの全部に要る。テーマごとに書かせると、書き忘れたテーマで扉絵に本文が重なる。
  - settings 層に残す理由: pages 層に置くと、theme 層の `var()`（値は `auto`）に負ける。settings 層なら PDF で詳細度に関係なく勝つ。`:not(.vs-epub)` で PDF に限るので、平らな CSS の詳細度は関係しない。`:not(.vs-break-merged)` は今のまま要る（settings 層は utilities 層より上）。
- 機能が「効くページの種類」を `theme.yml` で宣言する形は作らない。2 つの機能はどちらも vs のコードで、効く場所は vs の CSS の置き場で決まっている。テーマが変えられないものを宣言させない。`ornament` は判定を読むコードが無いので、定数も足さない。

### 4.5 小段階（問い 2.1 の 3）

S6-10 の前に S6-9b を置く。S6-10 は S6 の完了の確かめで、そこに出力の字面を変える変更を混ぜると、差が出たときに原因を分けられない。

| 小段階 | 作るもの | 確かめ |
| :--- | :--- | :--- |
| S6-9b 改ページを変数で読む | `tokens.css` に 3 つの変数。`themes/standard/` の 4 か所（4.3）。`BookSettingsCss` の定数からテーマの選択子を消し、変数を書く。章扉の保護を `Theme::Features::Frontispiece` へ（選択子は `body.chapter`）。`Frontispiece::PAGE_KINDS` と判定の窓口、`PageBreakNormalizer`・`ChapterLeadCheck` の置き換え。`vs theme:check` の検査と `vs theme:new` の注釈（4.3）。§5.2 の一覧に 3 行 | `lib/vivlio_starter` に `vs-header-` を書いた行（注釈を除く）が 0。B1（`false`・`any`・`image`）の四つの出力先、B2（`simple`）と B3（`true`・`recto`）の `pdf` を組む。PDF は r2 と全ページの画素が一致（既知の日付の行を除く）。契約 HTML は前後でバイト単位で同じ（`PageBreakNormalizer` の結果が変わらない）。`book-settings.css` の前後の差が改ページの節だけ。EPUB の計算値（`css_computed_diff.rb`）と Kindle の中間生成物（`kindle_record_diff.rb`）が差 0。`InversionCheck` の要素ごとの判定が 0 組。`themes/standard/` に `vs theme:check` で 🟡 0。`rake test`・`rake test:layout` |
| S6-10 | 今の表のとおり。4.7 の「雛形から消えたテーマのファイル」を足す | 今の表のとおり。4.7 の確かめを足す |

S6-9b で、仕様に無いので次のように決める。

1. **B2 の設定のクリーン EPUB を 1 回組む。** `simple` のクリーン EPUB だけが、節の改ページを theme 層の規則（`body.vs-header-simple h2`）で行う（`image` は vs の `article.vs-section-topic-epub`）。B2 は `pdf` だけの基準なので、S6-9b の前後のコミットでそれぞれ組み、計算値が差 0 であることを見る。あわせて後の側を Apple Books で開き、節見出しの前で改ページしない（`false`）ことを 2〜3 か所で見る。`true` に替えた写しでも 1 回見る。働かなければ、`simple-header.css` の h2 の宣言の前に予備の `break-before: page;` を 1 行足す形（`var()` を解さない処理系が前の行を使う）を試し、結果を持って相談する。
2. **計算値の比べで差が出る場合の扱い。** `break-before` の計算値は前後で同じはずである（`auto`・`page`・`recto`）。違ったら直さずに記録して相談する。
3. **完了の条件 2 の文面。** 「`BodyClassInjector` と `BookSettingsCss` に」を「`lib/vivlio_starter` の Ruby に」へ広げる（注釈と、テストの材料を除く）。S6-9b の後は `PageBreakNormalizer`・`ChapterLeadCheck` も満たす。

### 4.6 `vs build` の層の組の 🟡（問い 2.2）

**作らない。** `css-layer-restructure-spec.md` §4.3 の「扱い（S6 以降）」を、次の中身に書き直す。

- `vs build` は、テーマに依らず、層の組を `--log=debug` のときだけ出す（今のまま）。
- テーマを作る人は、`vs theme:check` の 💡（起きうる組）を見て、自分の本を `vs build --log=debug` で組んで確定する。`vs theme:check` の 💡 の文面に、この手順を 1 行で示す（今の文面のまま足りていれば変えない）。
- 層の外（`custom.css`）の組は知らせず、生成で解く（今のまま）。

理由:

- §4.5 の決まり（著者が直せないものは `vs build` で知らせない）と食い違う。テーマの規則が部品の規則に負けるのを直せるのはテーマを作る人で、その人には `vs theme:check` がある。lock に記録が無いことは「著者が入れた」ことしか示さず、「著者が作った」ことは示さない。
- 🟡 は原稿の場所を指す指摘の印で、この組は原稿のどこも指さない。毎回のビルドで消せない 🟡 が出ると、ほかの 🟡 が読まれなくなる。
- 起きても、ビルドは通り、PDF は正しい。EPUB と Kindle でテーマの飾りが 1 つ効かないだけで、組み上がりを見れば分かる。
- 入れないので、所要時間は測らなくてよい。

**S7 で見直す条件を一つ置く。** 公式テーマ（`theme-bunko` など）は、平らな CSS で読まれる前提で書かれていない。S7 の入口の実験の確かめに「実験の本の EPUB で、要素ごとの判定の組の数と中身を記録する」を足す。組が多く、取り込みの変換（§6.2）で直せないと分かったときに限り、「`vs theme:add` が入れた時点で 1 回知らせる」形を S7 の仕様で決める。ビルドのたびに知らせる形には戻さない。§10 の論点 7 は、この文面に替えて「答えが要る時点: S7 の入口の実験」とする。

### 4.7 雛形から消えたテーマのファイル（問い 2.3）

**`vs upgrade` が消す。** テーマのディレクトリは、置いたファイルが読まれる（出力先の CSS）ので、「雛形と同じ中身である」ことに意味がある。`vs theme:add` の入れ直し（S6-8 の決め 5）とそろえる。

| 本の側のファイル | 扱い |
| :--- | :--- |
| lock に記録のあるテーマの、lock に記録のあるファイルで、今の雛形に無く、本の中身が lock の記録と同じ | 計画に「削除」として出し、全体の確認が「はい」なら `.vs-backup/upgrade/` へ退避してから消す。lock の記録も消す |
| 同、本の中身が lock の記録と違う（著者が変えた） | 消さない。lock の記録は消す。`vs upgrade` の最後に 🟡「雛形から無くなったファイルですが、変更があるので残しました」とパスを示す。出力先の CSS（`epub*.css`・`kindle*.css`）なら「置いてあるかぎり読まれます。要らなければ削除してください」を添える。それ以外は「読まれません」を添える（`styles:` に無い CSS・画像） |
| lock に記録の無いファイル（著者が足したもの） | 触らない。知らせない |
| lock に記録の無いテーマ | 触らない（今のまま） |

- 範囲は `themes/` の下だけとする。`stylesheets/` などの雛形のファイルは、入口の CSS が名前を挙げて読むので、残っても読まれない。1.x の本の `stylesheets/` の片づけは S11 の手順（`v2-migration-plan.md` §5.3）が扱う。
- 出力先の CSS だけに限らず、テーマのファイルの全部を対象にする。条件を「本の中身が lock と同じ」に絞ってあるので、消えるのは著者が手を入れていない雛形の写しだけである。種類で分けると、決まりが 2 つになる。
- `--dry-run` は「削除」の行を見せるだけ。`--yes` は確認なしで消す（競合ではなく、退避があるため）。
- **時期は S6-10。** 2.0 は未公開で、1.x の本は `themes/` を持たないので、今は誰の本にも効かない。それでも今作るのは、S8 で `standard` のファイルを動かす変更（§10 の論点 5）が入る前に仕組みが要ることと、S6-9 の振り分け（`managed_theme_digests`）の直後で変更が小さいことによる。ビルドの経路は変えないので、S6-10 の出力の比べには影響しない。
- 確かめ: `upgrade_commands_test.rb` に 3 件（消す・著者が変えたので残す・lock に無いファイルは触らない）。写しの本で、雛形の `themes/standard/` から 1 ファイルを抜いた材料の雛形に対して `vs upgrade --dry-run` と本番を走らせ、退避と lock の記録を見る（`ToolUpgrader.run!` と `run_gem_command` を差し替える）。

### 4.8 決定を移す先（Opus が S6-9b の最初に行う）

| 決定 | 移す先 |
| :--- | :--- |
| 4.3 の変数 | `theme-contract-spec.md` §5.2（一覧に 3 行）・§3.5 の表（「章と節の改ページ」の行: 変数で書く）・§7.2（`vs theme:check` の検査） |
| 4.4 の機能の判定と章扉の保護 | `theme-contract-spec.md` §3.4（決め 3 の後に箇条を足す） |
| 4.5 の小段階 | `theme-contract-spec.md` §9 の S6（小段階の表に S6-9b・完了の条件 2 の文面）・`v2-migration-plan.md` §3.6（S6-9b の比べ・B2 の EPUB の 1 回） |
| 4.6 | `css-layer-restructure-spec.md` §4.3 の「扱い（S6 以降）」・`theme-contract-spec.md` §10 の論点 7・§9 の S7 の入口の実験 |
| 4.7 | `theme-contract-spec.md` §7.3 の表・§9 の S6 の S6-10 の行・§10 の論点 8（閉じる） |
| 4.2 の確かめ | `vivliostyle-css-pitfalls-notes.md`（`break-before` の `var()` は働く） |
| 論点 6 | `theme-contract-spec.md` §10（閉じる）。`bunko` の節の改ページの既定は S8 の仕様の問いに足す |

移し終えたら、この文書を archives へ移す（前例 `v2-s6-consultation.md` と同じ）。
