# S6-10 の前に決めること — 改ページの打ち消し・テーマの層の組の 🟡・雛形から消えたテーマのファイル（Fable への相談）

> 作成日: 2026-11-17
> ステータス: **相談中**（Fable の答え待ち）
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
