# S6 の小段階と、段階の中で決めること（Fable への相談）

> 作成日: 2026-11-16
> ステータス: **答え済み・仕様へ反映済み**（§4。2026-11-16・Fable。§4.11 の表のとおり各仕様書へ移した）
> 出自: S5 の完了（`v2-architecture-spec.md` §10.3〜§10.8・`bcaad6e3`）。S6（テーマの仕組みと `standard` の切り出し）に着手する前に、進め方を決める

Fable のセッションに、次の「---」より下をそのまま渡す。

---

2.0 の S5（本の種類・軸・`BuildPlan`）が終わりました。次は S6（テーマの仕組みと `standard` の切り出し）です。S5 の前に、小段階と「段階の中で決めること」を `v2-architecture-spec.md` §8 の S5 に書いてもらいました（`fa3d44ba`）。S6 についても同じ形で決めてください。

S6 の仕様は `theme-contract-spec.md` §3〜§5・§7〜§9 に書き込まれています。テーマのオプションの既定値の持ち主（`v2-architecture-spec.md` §5.2）や、1.x の本を上げる手順（`v2-migration-plan.md` §5.3）も決まっています。一方で S6 は S5 よりずっと大きく、完了の条件の 7〜9 は「この変更の前後で差 0」という形なので、変更の順番を先に決めないと条件を満たせません。設計のやり直しではなく、進め方と、仕様に書かれていない 7 点の判断をお願いします。

コードの書き換えはしないでください。読む資料は次のとおりです。

1. `theme-contract-spec.md` §3（テーマの形）・§4（標準のテーマ）・§5（公開する変数）・§7（置き場・配布・更新）・§8（契約の版）・§9 の S6（完了の条件 1〜10）
2. `css-layer-restructure-spec.md` §3（層とファイルの配置）・§4.4（リテラル化）・§7.2（変数の名前の別名）
3. `v2-architecture-spec.md` §2.2（`BookProfile`）・§5.2・§5.3（設定の持ち方）・§8 の S5（小段階の表の形。今回の答えの見本）・§10.3〜§10.8（S5 の実装記録）
4. `v2-migration-plan.md` §3.2（基準）・§3.6（設定の組み合わせ）・§4.1・§5.3・§8.12〜§8.14（確かめ方で分かったこと）

## 1. 今の状態（S5 の後）

| 項目 | 今 |
| :--- | :--- |
| 基準 | r2（`../vivlio-starter-v2-baseline/r2/`。v2 の `e01448df` で組んだ）。S4・S5 の完了は r2 と比べた。EPUB と Kindle 用 EPUB には、S4 で記録した属性の順の違いが 2 件ある（`v2-architecture-spec.md` §10.2） |
| 比べる道具 | `scripts/pdf_pixel_diff.rb`・`epub_diff.rb`・`kindle_record_diff.rb`・`css_computed_diff.rb`（EPUB の計算値）。基準の側の `tools/` に `prepare_pages_snapshot.rb`・`pages_diff.rb`（ビルドなしで EPUB の HTML を比べる）。契約 HTML は `--no-clean` の写しの `.cache/vs/build/html/` どうしをバイト単位で比べる |
| CSS の置き場 | S2-2 でファイルを分けた。色と寸法の変数は `stylesheets/tokens.css`（50 行の定義）、見出しの組み方は `stylesheets/parts/image-header.css`・`parts/simple-header.css`、扉絵・節絵の画像は `stylesheets/images/bundled/`（12 枚）。`stylesheets/theme.css` は今は無い |
| `theme.*` のキー | `ConfigKeys::KEYS` に 15 個（`theme.color`・`style`・`lead_size`・`frontispiece.*`・`ornament.*`・`markers.*` など）。`theme.name` はまだ無い |
| テーマ固有の名前を書いたコード | `BodyClassInjector`（`theme.style` から `vs-header-image`・`vs-header-simple`）・`BookSettingsCss`・`ThemeColor`・`ThemeValidator`・`HtmlContract`（`vs-header-*` を `theme_option` として分類） |
| 軸と段の表 | `Common.traits`・`Guards::TraitCombinationCheck`（テーマの `supports:` の行は S6 で足す・S5 の決め 6）・`BuildPlan`（`features` にテーマの機能はまだ無い） |

## 2. 問い

### 2.1 小段階の切り方と順番

S6 の「作るもの」（§9 の S6）を、S5 と同じく、各小段階の完了のコミットが本書の出力を基準と同じに保つ小段階に分けてください。

仕様から読み取れる順序の制約は次のとおりです。

- 「最初に入れるもの」は `LiteralResolver` が `clamp()`・`min()`・`max()` を含む宣言を理由つきで落とす変更（条件 7）。
- 変数の名前の変更（条件 9）と、`targets/` の規則のテーマへの移動（条件 8）は、それぞれの前後で Kindle の中間生成物が差 0 であることを求める。二つを同じコミットに混ぜると、どちらの差かが分からない。
- `standard` の切り出し（条件 1〜3）は、テーマを読む仕組み（`theme.yml` の読み込み・`styles:` を theme 層へ入れる・出力先の CSS の読み込み）が先に要る。
- オプションの書き出しと機能の宣言（条件 2）は、`ConfigKeys` から `theme.*` を外す変更（§2.3）と同時になる。

候補の順は、(1) 寸法の宣言を落とす → (2) 変数の名前を `--book-*` へ（別名を含む）→ (3) テーマを読む仕組みと `theme.name` → (4) `standard` の切り出し（CSS・画像）→ (5) `targets/` の規則をテーマの出力先の CSS へ → (6) オプション・機能の宣言・`ConfigKeys` からの移動 → (7) 版の検査・`supports:` の検査 → (8) コマンド（`vs theme`・`theme:add`・`theme:check`・`theme:new`）→ (9) `vs upgrade` の扱い → (10) 配色のテーマの見本と `kindle_tokens:`、です。

決めてほしいこと:

1. 小段階の表（作るもの・確かめ）。
2. 四つの出力先を組んで基準と比べるのを、どの小段階の後に行うか（S5 は S5-4 の後と最後の 2 回）。
3. `v2-migration-plan.md` §3.6 が S6 に求める B2〜B4 との比べ・単章のビルド・`rake test:layout`・`rake test:release` を、どの小段階で行うか。

### 2.2 EPUB の比べの基準

§9 の S6 の条件 3 は「PDF は全ページの画素が一致、Kindle は Kindle Previewer の画面が見比べて同じ」で、EPUB の扱いを書いていません。S4・S5 では、EPUB の HTML・CSS・OPF をバイト単位（S4 の第二段階は属性の順を除いて）で比べてきました。

S6 では、次のものが EPUB の字面を変えます。

- 変数の名前の変更。CSS の中の名前が変わる。平らな CSS の生成がリテラルに解く値は同じはずである。
- 規則の読む順の変更（`targets/` の規則がテーマの出力先の CSS へ移り、vs の `targets/` の後に読まれる）。
- 画像の置き場の変更（`stylesheets/images/bundled/` → `themes/standard/images/`）。EPUB の中の画像の名前は写しごとに変わるので、今の道具がすでに吸収している。

決めてほしいこと: S6 の各小段階と完了で、EPUB を何で比べるか。候補は、(a) EPUB の計算値（`css_computed_diff.rb`）が差 0、HTML はバイト単位で同じ、(b) (a) に Apple Books の画面の見比べを足す、(c) ほかの形。

### 2.3 `ConfigKeys` から `theme.*` を外した後の既存の仕組み

`v2-architecture-spec.md` §5.2 は、「`ConfigKeys::KEYS` から `theme.*`（`name` を除く）を外し、`Common.load_config` が、選ばれたテーマの宣言を既定値の表に足す」としています。今 `ConfigKeys` を読んでいる仕組みのうち、`theme.*` に関わるものは次のとおりです。

| 仕組み | 今していること |
| :--- | :--- |
| `config_keys_test.rb` | 雛形の `book.yml` に書かれたキーと `KEYS` が一致する・既定値が雛形の値と一致する（「載せると決めたキーは全部書く」の検査） |
| `book_yml_consumption_test.rb` | `book.yml` のキーが、どれも `lib/` のどこかで読まれている |
| `config_guide.rb` | `ConfigKeys.default_schema` から、キーの既定値と説明を引く |
| `upgrade.rb`・`scaffold_updates.rb` | 廃止キーの削除・移ったキーの案内 |
| `ThemeValidator` | `theme.color`・`frontispiece`・`ornament` の値を検査して 🟡 |
| `Common.load_config` | `ConfigKeys` の既定値 → 種類の既定値（`BookProfile`）→ 判型のプリセット → `book.yml` の値、の順に重ねる |

決めてほしいこと:

1. 「`KEYS` ＋ 選ばれたテーマの `options:` ＋ 機能の宣言」を一つの表に合わせて、上の仕組みが今の形のまま読むのか。それとも、テーマのオプションを読む側を分けるのか。
2. テーマが宣言していないキーが `book.yml` の `theme:` 節にあるときの扱い。`theme-contract-spec.md` §3.3 の「このテーマには無い設定」の 🟡 と、今の「知らないキー」の扱いの関係。
3. 雛形の `book.yml` の `theme:` 節の正典。今は直下の `book.yml` で、`config_keys_test.rb` が `KEYS` と照合している。S6 の後は `themes/standard/theme.yml` と照合するのか。

### 2.4 小説と絵本の既定のテーマが無い間の扱い

S5 の `BookProfile` は、`theme.name` がまだ無いので、§2.2 の表の `theme.name` を外して置いています（`v2-architecture-spec.md` §8 の S5 の決め 1）。S6 で `theme.name` を足すと、表の値は `novel` → `bunko`、`picture_book` → `picture` です。どちらのテーマも S8・S9 までは無いので、`theme-contract-spec.md` §7.1 の「テーマが無ければ 🔴 で止める」により、`book.type: novel` の本は S6 から S8 まで「テーマが無い」で止まります（`picture_book` は S5 の決め 2 で、すでに固定レイアウトの 🔴 で止まる）。

決めてほしいこと: S6 で `BookProfile` に `theme.name` を足すか。足す場合、S8 までの小説の本を止めてよいか。足さない場合、`book.type: novel` の本は `standard`（横組みの技術書の見た目）で組まれ、綴じの向きと隠しノンブルだけが縦書きの向きになります（S5 の決め 3 と同じ状態が続く）。

### 2.5 配色のテーマの見本（`standard-mono`）の置き場

条件 4・10 は、配色のテーマの見本 `themes/standard-mono/`（`extends: standard` と `tokens:`・`kindle_tokens:` だけ）で本書を組むことを求めています。

決めてほしいこと: 置き場は (a) リポジトリの直下の `themes/`（同梱のテーマとして雛形にも入り、`vs theme:add standard-mono` で足せる）、(b) テストの材料（`test/` の下）、(c) 基準のディレクトリの写しだけ、のどれか。(a) の場合、配色のテーマを作る人の見本として、§7.1 の同梱のテーマの一覧（`standard`・`bunko`・`picture`）に加えることになります。

### 2.6 S6 で作るコマンドの範囲

§9 の S6 は「§7.2 のコマンド」を作るものに挙げています。§9 の S7 は「`vs theme:add` の npm の経路」を S7 に回すと明記しています。`vs theme:add` の git の URL の経路と zip の経路をどちらの段階で作るかは書かれていません。

決めてほしいこと: S6 で作る `vs theme:add` の経路（同梱のテーマの名前・手元のディレクトリ・zip・git の URL のどれまでか）。git の経路は、取得したものの中のスクリプトを走らせない決まり（§7.2）の確かめ方も含めて決めてください。

### 2.7 基準の版を上げる時期と、仕様の書き換え

二つあります。

1. **基準の版。** §9 の S6 の条件 3 は「S0 の基準と比べて」と書いていますが、今の基準は r2 です（S5 も r2 と比べて完了とした）。また、CSS のコメントの中に `EpubBuilder` の名前が 14 か所・7 ファイル残っています（S4 で消したクラス）。今直すと EPUB の CSS が r2 とバイト単位で合わなくなるので、「基準の版を上げるとき（S6）に直す」としてあります。S6 の中で基準を r3 に上げるか、上げるならどの小段階の後か、決めてください。S6 で見た目を変える変更を入れないなら、上げる理由は字面の違い（変数の名前・コメント）だけです。
2. **仕様の書き換え。** §9 の S6 の条件 1 と §4 の表は、S2-2 で分ける前のファイルの名前（`stylesheets/theme.css`・`simple-header.css`・`image-header.css`・`stylesheets/images/`）で書かれています。今の名前（§1 の表）に書き直す必要があります。`css-layer-restructure-spec.md` §3 の「どの規則がテーマでどの規則が部品か」の線引きも、分けた後のファイル（`parts/heading.css`・`pages/chapter.css`・`pages/preface.css`・`pages/appendix.css` など）で引き直す必要があるかを見てください。

## 3. 答えの形

- §2 の各問いの決定と理由を、`v2-post-s3-consultation.md` §5 と同じく、この文書の末尾に「答え」の節として書く。
- §2.1 の小段階の表は、`v2-architecture-spec.md` §8 の S5 の表（「小段階・作るもの・確かめ」の 3 列と、「仕様に書かれていないので、S6 では次のように決める」の箇条）と同じ形で書く。
- 決定を移す先の仕様書と節を挙げる（移すのは Opus が S6 の最初に行う）。

---

## 4. 答え（Fable・2026-11-16）

仕様書のほかに、実物（`stylesheets/`・`Css::EntryWriter`・`ConfigKeys`・`BodyClassInjector`・`config/book.yml`）を読んで決めた。コードは書き換えていない。

### 4.1 決めたこと

| # | 問い | 決定 |
| :--- | :--- | :--- |
| 2.1 | 小段階 | 10 の小段階に分ける（4.2）。候補の順を基本にし、二つ変える。(a) `standard` の切り出しを「層を移す」（S6-4）と「置き場を移す」（S6-5）に分ける。(b) 版の検査と `supports:` の検査は、テーマを読む仕組み（S6-3）に含める |
| 2.1 | 全部の比べの回数 | 四つの出力先と B2〜B4 を組んで r2 と比べるのは、S6-2 の後・S6-7 の後・最後の 3 回（4.3） |
| 2.2 | EPUB の比べ | 案 (c)。HTML は毎回バイト単位。CSS は、字面を変えない小段階ではバイト単位、変える小段階（S6-2・S6-4・S6-6）では計算値が差 0。Apple Books の画面は S6-7 の後に 1 回（4.4） |
| 2.3 | `ConfigKeys` | テーマの宣言を `Spec` の形に直して `KEYS` に重ねる入口を 1 つ作る。既定値と案内を読む側はそれを読み、廃止キーを読む側は今のまま。`theme:` 節の知らないキーは 🟡。雛形の `theme:` 節は `themes/standard/theme.yml` と機能の宣言に照合する（4.5） |
| 2.4 | 小説の既定のテーマ | S6 では `BookProfile` に `theme.name` を足さない（S8 で `bunko` と一緒に足す）。ただし `supports:` の検査が入るので、縦書きの本は S6 から S8 まで 🔴 で止まる。止めてよい（4.6） |
| 2.5 | `standard-mono` の置き場 | 案 (b)。テストの材料（`test/vivlio_starter/fixtures/themes/standard-mono/`）。同梱しない（4.7） |
| 2.6 | `vs theme:add` の経路 | S6 は同梱のテーマの名前・手元のディレクトリ・zip まで。git の URL は S7 で npm と一緒に作る（4.8） |
| 2.7 | 基準の版 | S6 の間は r2 のまま。r3 は S6 の完了のコミットの後、S7 の前に 1 回だけ作る（4.9） |
| 2.7 | 仕様の書き換え | 要る。theme 層へ移すファイルは見出しの 2 枚だけに絞り、ファイルごとの表で引き直す（4.10） |

実物を読んで見つかった、仕様のままでは本書の出力が変わるか、完了の条件を満たせない箇所が 4 つある。4.2 の「S6 で決めること」の 2〜5 に書いた。

### 4.2 小段階（問い 2.1 の 1）

S6 は 10 の小段階に分ける。どの小段階も、完了のコミットは「本書の出力が、その時点の基準（r2）と同じ」ものだけにする。EPUB と Kindle 用の CSS の字面は S6-2・S6-4・S6-6 で変わるので、「同じ」の中身は 4.4 による。前後の比べの相手は、前の小段階の確かめの出力（`r2/check/s6-<番号>/`）を使う。

| 小段階 | 作るもの | 確かめ |
| :--- | :--- | :--- |
| S6-1 紙の寸法の宣言を落とす | `LiteralResolver` が `clamp()`・`min()`・`max()` を含む宣言を、理由 `:paper_dimension` を付けて落とす。`css_layer_test.rb` の許可の表から紙の寸法を分ける | 完了の条件の 7（B1 の Kindle の中間生成物が差 0・Kindle 用の CSS に `clamp(`・`min(`・`max(` が無い）。クリーン EPUB の CSS は前後でバイト単位で同じ（リテラル化を通らないため） |
| S6-2 変数の名前を `--book-*` へ | `stylesheets/tokens.css` を `--book-*` の 1 行ずつの一覧にする。`stylesheets/`・`templates/`・`lib/`（`BookSettingsCss`・`CssUpdater`・`techbook/processor.rb`・`inject_heading_images.rb` など）の名前の置き換え。`targets/kindle-tokens.css` を `--book-*` で書く。`Css::LegacyTokens`（対応の表）・`tokens-legacy.css`（読む向き）・`settings` 層の書き出し（値を入れる向き）・今の名前を使う `custom.css` への 💡。`--color-shadow` を消す | 完了の条件の 9。前の平らな CSS に対応の表の置き換えを当てたものが、後の平らな CSS と一致する（`tokens-legacy.css` の分と `--color-shadow` を除く）。EPUB の計算値が差 0。完了の条件の 5（今の名前を使った `custom.css` の写し）。その後、全部の比べ（4.3） |
| S6-3 テーマを読む仕組み | `theme.name`（`ConfigKeys`・雛形の `book.yml`）。`Theme::Manifest`（読み込み・検査・`extends:` の 1 段）・`Theme::Contract`（`contract:`・`requires_vs:`）。`EntryWriter` が `styles:` を theme 層に、`tokens:` を tokens 層に、テーマの出力先の CSS を target 層に入れる（順は `css-layer-restructure-spec.md` §5 の 1〜5）。`TraitCombinationCheck` の `supports:` の行。中身の無い `themes/standard/theme.yml`（`name`・`title`・`version`・`contract`・`supports` だけ）。`build_copy.rb`・`copy_to_scaffold.rb`・`scaffold.lock` に `themes/` を足す | 本書の入口の CSS（`.cache/vs/entry-*.css`）と契約 HTML が、前後でバイト単位で同じ。完了の条件の 6（材料のテーマで 🔴 の 3 通り）。`extends:` の読む順のテスト。単章のビルドと `vs preflight` |
| S6-4 見出しの 2 枚を theme 層へ | `parts/simple-header.css`・`parts/image-header.css` を、置き場を変えずに parts 層から theme 層へ移す（`EntryWriter` の表だけを変える）。本文以外の種類（目次・索引など）の入口にも入る | B1 の `pdf`・`epub`・`kindle` と B2 の `pdf` を組む。PDF は全ページの画素が一致。EPUB の計算値と Kindle の中間生成物が差 0。`InversionCheck` の要素ごとの判定が B1・B4 の EPUB と Kindle 用 EPUB で 0 組 |
| S6-5 `standard` へファイルと画像を移す | 2 枚を `themes/standard/` へ移し、`theme.yml` の `styles:` に今の順（`simple-header.css` → `image-header.css`）で並べる。`stylesheets/images/bundled/` を `themes/standard/images/` へ移す。画像の指定を探す順（`v2-migration-plan.md` §5.3 の 4）。`images/bundled` を書いた `lib/` の 10 ファイル | 入口の CSS の差が、2 枚の `@import` の行のパスだけ。B1 の EPUB と Kindle 用 EPUB が `epub_diff.rb` で違い 0 件（Kindle 用 EPUB が同じなので、変換はしない）。B1・B2 の PDF は全ページの画素が一致。`rake test:layout` |
| S6-6 出力先の規則を `standard` へ | `targets/epub.css`・`targets/kindle.css` の規則のうち、選択子が `vs-header-image`・`vs-header-simple` を含むもの（今は 3 か所と 8 か所）を、選択子と宣言を変えずに `themes/standard/epub.css`・`kindle.css` へ移す | 完了の条件の 8（B1 の EPUB の計算値と Kindle の中間生成物が差 0）。EPUB の HTML はバイト単位で同じ。PDF は、入口の CSS が前後でバイト単位で同じであることだけを見る（target 層を読まないため） |
| S6-7 オプションと機能の宣言 | `theme.yml` の `options:`、`Theme::Features::Frontispiece`・`Ornament` の宣言、`ConfigKeys::KEYS` から `theme.*`（`name` を除く）を外す、`Common.load_config` の 3（`v2-architecture-spec.md` §5.3）、`BookSettingsCss` が `token:` から書き出す、`BodyClassInjector` が `body_class:` から付ける、値の検査を宣言から行う（`ThemeValidator` の置き換え）、`HtmlContract` の `theme_option` を宣言から引く、`BuildPlan.features` に `frontispiece`・`ornament`、`theme:` 節の知らないキーの 🟡（4.5） | 完了の条件の 2。B1・B2・B3 の設定で、`Common::CONFIG` の書き出しと `.cache/vs/book-settings.css` が前後でバイト単位で同じ。契約 HTML がバイト単位で同じ。段の一覧が同じ。`theme.color` などに読めない値を書いた材料で、🟡 の文面が前後で同じ。その後、全部の比べと画面（4.3）。`rake test:standard` |
| S6-8 コマンド | `vs theme`・`vs theme:add`（4.8 の範囲）・`vs theme:check`・`vs theme:new` | `themes/standard/` に `vs theme:check` を掛けて 🟡 が 0 件。`vs theme:new x --extends standard` の出力が `vs theme:check` を通る。zip の検査（4.8）のテスト |
| S6-9 `vs upgrade` | `theme-contract-spec.md` §7.3 の表（`scaffold.lock` に記録のあるテーマの更新・`vs theme:add` で入れた同梱のテーマの記録・著者のテーマの契約の版の 🟡）と、`custom.css` の今の名前の置き換え（`css-layer-restructure-spec.md` §7.2） | 写しの本での実行。`ToolUpgrader.run!` を差し替えて走らせる（道具の更新がマシンに効かないようにする）。置き換える行を全部見せ、「いいえ」で何も変わらないこと |
| S6-10 配色のテーマと `kindle_tokens:` | `kindle_tokens:` の書き出し（target 層の 2 番目）。材料の `standard-mono`（4.7）。S6 の完了の確かめ | 完了の条件の 4・10（写しの `book.yml` の `theme.color`・`preface_color`・`appendix_color` を空欄にして組む。下の決め 4）。全部の比べ（4.3）。`rake test:layout`・`rake test:standard`・`rake test:release` |

S6 の範囲に入れないもの: `vs theme:add` の git と npm の経路（S7）、`BookProfile` の `theme.name`（S8）、1.x の本の `stylesheets/` を 2.0 の配置へ移す手順（`v2-migration-plan.md` §5.3 の 2〜4・6・7。S11）、原稿の中の変数の名前（S11。下の決め 9）、vs の内部の変数の改名（下の決め 8）、見出しの 2 枚のほかの規則を theme 層へ移すこと（4.10）。

仕様に書かれていないので、S6 では次のように決める。

1. **`standard` の切り出しは、層を移す小段階と、置き場を移す小段階に分ける。** 見出しの 2 枚は今、parts 層の最初に読まれている。theme 層へ移すと、PDF では parts・pages のどの規則にも詳細度に関係なく勝つようになり、平らな CSS では並びが pages の後になる。`parts/heading.css` は今 2 枚より後に読まれるので、詳細度が同じ組では今 `heading.css` が勝っている。この入れ替わりが S6 でいちばん差の出やすい箇所である。置き場の移動と同じコミットにすると、差の原因が層かパスかを分けられない（`css-layer-restructure-spec.md` §3.2 の「段階を分ける」と同じ理由）。差が出たら、S3-2 と同じく、選択子の形をそろえて直す。
2. **`tokens:` の書き出し先は tokens 層とする（theme 層ではない）。** `.cache/vs/theme-tokens.css` に `:root { … }` で書き出し、vs の `tokens.css` の後に tokens 層で読む。`extends:` があれば、土台の `tokens:` → 自分の `tokens:` の順に並べる。theme 層に入れると、pages 層の `:root` の付け替え（`pages/appendix.css` の `--color-mark`・`--color-strong` など 6 個、`pages/preface.css` の `--color-link`）にテーマの値が勝ち、付録の色と前書きのリンクの色が本文の色になる。theme 層に入るのは `styles:` の CSS だけである。
3. **扉絵の `@page :nth(1)` の規則は、vs の `pages/chapter.css` に残す。** テーマの `styles:` は全部の種類の入口に入り、`@page` は `body` のクラスで絞れない。テーマへ移すと、付録・前書き・目次の最初のページにも扉絵が出る。この規則は機能 `frontispiece` の骨格として vs が持ち、テーマは変数（`--book-frontispiece-*`）で値を入れる。機能を使わないテーマのために、`tokens.css` に `--book-frontispiece-image: none;` の既定値を置く。
4. **配色のテーマの `tokens:` と、土台のオプションの関係。** `standard` の `color` は `token: color-accent` で、値は settings 層に書き出される。settings 層は tokens 層より上なので、`standard-mono` が `tokens:` に `color-accent` を書いても、仕様のままでは負ける（完了の条件の 4 を満たせない）。次のように決める。
   - 選ばれたテーマの `tokens:` に、土台のオプションの `token:` と同じ名前があれば、その値をオプションの既定値として扱う（`Common.load_config` の 3 で重ねる）。settings 層への書き出しは今と同じく、解決した後の値を必ず書く。
   - `book.yml` に著者が書いた値は、テーマの値に勝つ（`css-layer-restructure-spec.md` §2.1 の「`book.yml` の設定が、テーマの既定値より優先される」のとおり）。雛形の `book.yml` は `color: green` を書いているので、配色のテーマの色にするには、その行を空欄にする。
   - `vs theme:add` は、`book.yml` に書く行を示すときに、テーマの値を覆っている `theme:` 節の行と、空欄にする書き方を一緒に示す。`vs build` では知らせない（著者が意図して書いた値と区別できないため）。
5. **`body_class:` は、ページの種類ごとに書ける。** 今の `BodyClassInjector` は、章には `theme.style` の値のクラスを、付録には値に依らず `vs-header-simple` を付け、ほかの種類には付けない。`theme-contract-spec.md` §3.1 の例の形（値 → クラス）では付録を表せない。次の形を足す。種類を書かない形は、全部の種類に付ける。

   ```yaml
   style:
     type: enum
     values: [image, simple]
     default: image
     body_class:
       chapter:  { image: vs-header-image, simple: vs-header-simple }
       appendix: vs-header-simple          # 文字列は、値に依らず付けるクラス
   ```

6. **「書かなければ別のオプションに従う」を宣言で書けるようにする。** `preface_color`・`appendix_color`（`color` に従う）と `frontispiece.lead_size`（`lead_size` に従う）の 3 つは、既定値が `nil` である。`options:` に `default_from: <オプションの名前>` を足す。
7. **Ruby が値を読むオプションは、機能の宣言に置く。** `theme.yml` の `options:` に置くのは、`token:` と `body_class:` だけで渡せるものに限る。S6-7 の最初に、今の 15 個のキーを「`options:`」「`frontispiece`」「`ornament`」に分けた表を作り、`theme-contract-spec.md` §3.4 に書く。どれにも入らないキー（Ruby が読むが、扉絵にも節絵にも属さないもの。`markers.*` と `lead_size` が候補）が出たら、実装を止めて相談する。3 つ目の機能を足すかは、その表を見て決める。
8. **名前を変えるのは、公開する変数（`theme-contract-spec.md` §5.2 の一覧と、機能の変数）と、テーマへ移る 2 枚の中だけの変数（`--standard-*`）とする。** vs の内部の変数（`base/page.css` の 24 個・`pages/titlepage.css`・`pages/colophon.css` の各 8 個など）は、2.0 では名前を変えない。`--_*` に変えて別名を置けば内部の変数でなくなり、置かなければ、その変数に値を入れていた 1.x の `custom.css` が警告なしに効かなくなる。`--_*` の決まりは、これから足す内部の変数に当てる。名前を変えた変数は例外なく対応の表に載せ、テストで「r1 の雛形の CSS で定義されていた変数の名前が、どれも (a) 今も定義されている、(b) 対応の表にある、(c) 消した変数の表にある、のどれかである」ことを検査する。
9. **原稿の中の変数の名前は、S6 では書き換えない。** `contents/46-utility.md`（`custom.css` の書き方の表）と `contents/23-figures.md` は今の名前を載せている。書き換えると本書の PDF が変わる。今の名前は別名で効くので、説明は誤りにならない。マニュアルの書き直しは S11 で行う。
10. **`theme.name` は、雛形の `book.yml` に `name: standard` として書く。** 「載せると決めたキーは全部書く」（`config-key-criteria-guidelines.md` §1）による。本書の `book.yml` に 1 行増えるが、出力は変わらない。
11. **テーマの出力先の CSS へ移すのは、選択子が `vs-header-*` を含む規則だけとする。** テーマの `epub.css`・`kindle.css` は 11 種類の全部に入るが、vs の `targets/epub.css`・`kindle.css` は本文のページの 4 種類にしか入らない。素の `h1`・`h2` を選ぶ規則を移すと、目次・索引・用語集の見出しにも当たるようになる。そのような規則は、相手の部品がテーマへ移っていても vs の `targets/` に残す。
12. **`styles:` には 2 枚を直接並べ、`theme.css` という入口は作らない。** 入口から `@import` で読む形は、層を付けた `@import` の中の `@import` を `Flattener` が解く必要があり、確かめる対象が増える。`theme-contract-spec.md` §3.1 のディレクトリの例の `theme.css` は「分け方は自由」の一例として残す。
13. **S5 の完了の条件の 4（`page.writing_mode: vertical` の最小の本）のテストは、`supports.writing_mode: [horizontal, vertical]` を書いた材料のテーマで組む。** `standard` は横書きだけなので、S6-3 から 🔴 で止まる（4.6）。
14. **`theme.yml` の `standard` の `tokens:` は、S6 の完了の時点で空でよい。** 公開する変数の既定値は `stylesheets/tokens.css` が正典である（`theme-contract-spec.md` §5.2）。今の値はそのまま既定値になり、`standard` が別に書く値は無い。「テーマに依らない中立の既定値」を `standard` の値と分けるのは、2 つ目の組版のテーマ（`bunko`・S8）が値を決めるときに行う。

### 4.3 全部の比べと、設定の組み合わせ（問い 2.1 の 2・3）

| 確かめ | 行う時点 |
| :--- | :--- |
| 全部の比べ（B1 の四つの出力先・B2・B3・B4 を組んで r2 と比べる。単章のビルド `bin/vs build 21` と `bin/vs preflight` を含む） | S6-2 の後・S6-7 の後・最後（S6-10）の 3 回 |
| Kindle Previewer と Apple Books の 10 か所の画面の見比べ | S6-7 の後の 1 回。最後の比べで Kindle の中間生成物と EPUB が S6-7 の後と同じなら、画面は見比べ直さない（r3 を作るときに撮り直す） |
| B2（`theme.style: simple`）の PDF | 上の 3 回のほかに、S6-4・S6-5（見出しの 2 枚を動かす小段階） |
| B4 の EPUB の `InversionCheck` | 上の 3 回のほかに、S6-4・S6-6（規則の読む順が変わる小段階） |
| `rake test:layout` | S6-5 の後と最後。走らせている間は雛形を同期しない |
| `rake test:standard` | S6-7 の後と最後 |
| `rake test:release` | 最後の 1 回（1 段ずつ・記録はファイルへ）。r3 を作る前に通す |

- 3 回にする理由: S6-2 は CSS の全部のファイルと `lib/` の書き出しを触り、変数が解けないと宣言が無効になるだけでエラーにならない。S6-7 は設定の解決と settings 層の書き出しを作り替える。この二つは B2〜B4 の経路（`simple`・判型・分冊）を通るので、その場で全部を比べる。S6-3〜S6-6 は、触る範囲に合わせた比べ（4.2 の表）で足りる。S6-8・S6-9 はビルドの経路を変えない。
- B4 の写しには、`stylesheets/` と同じく、作業ツリーの `themes/` を置く（S6-3 から `themes/standard/` が無いと 🔴 で止まる）。
- PDF の画素の比べとビルドを同時に走らせない。長いビルドと、待つだけのコマンドは `caffeinate -i` の下で走らせる（`v2-migration-plan.md` §8.12・§8.13）。

### 4.4 EPUB の比べ（問い 2.2）

案 (c) とする。変更の種類ごとに、いちばん強い比べを当てる。

| 比べるもの | 基準 |
| :--- | :--- |
| HTML（契約 HTML と EPUB の中の XHTML）・OPF | どの小段階でも、r2 とバイト単位で同じ（S4 で記録した属性の順の 2 件と、画像の名前を除く） |
| CSS — 字面を変えない小段階（S6-1 のクリーン EPUB・S6-3・S6-5・S6-7） | 前の小段階とバイト単位で同じ（S6-5 は `url()` の中の画像の名前を除く） |
| CSS — 名前を変える小段階（S6-2） | 前の CSS に対応の表の置き換えを当てたものと一致する。あわせて計算値（`css_computed_diff.rb`）が差 0 |
| CSS — 読む順を変える小段階（S6-4・S6-6） | 計算値が差 0。`InversionCheck` の要素ごとの判定が 0 組 |
| EPUBCheck | 毎回、致命・エラー・警告とも 0 |
| Apple Books の画面 | S6-7 の後に 1 回、r2 の 10 か所と見比べる |

- 計算値の比べでは、変数そのもの（`--` で始まるプロパティ）の行を除く。S6-2 で名前が変わるためである。変数の値が正しく届いているかは、変数を読む側のプロパティ（`color`・`font-family` など）の計算値で分かる。
- Apple Books の画面を小段階ごとに見ない理由: 計算値が差 0 で HTML がバイト単位で同じなら、表示が変わる経路は「同じ計算値を Apple Books が別に描く」だけで、S6 の変更はその経路に触れない。S6-7 の後の 1 回は、道具（`css_computed_diff.rb` は Chromium で計算する）が見ていない差が無いことの確かめである。
- `theme-contract-spec.md` §9 の S6 の条件 3 に、EPUB の基準（上の表）を書き足す。

### 4.5 `ConfigKeys` から `theme.*` を外した後（問い 2.3）

**1. 読む入口を 1 つにし、読む側の形は変えない。**

- テーマの側（`Theme::Manifest` と機能の宣言）が、自分のオプションを `ConfigKeys::Spec` の形（`{ %i[theme color] => Spec[default: 'green'] }`）で返す。
- `ConfigKeys` に、`KEYS` とその表を重ねて返す入口を 1 つ置く（名前は実装で決める）。`default_schema` はこの入口を通る。
- 仕組みごとの読み方:

| 仕組み | S6 の後 |
| :--- | :--- |
| `Common.load_config` | 重ねた表を読む（`v2-architecture-spec.md` §5.3 の 3）。`theme.name` を生の YAML から先に取り出し、テーマを読んでから全体を重ねる |
| `config_guide.rb` | 重ねた表を読む。今の形のまま |
| `upgrade.rb`・`scaffold_updates.rb`・`retired_key_remover.rb` | `ConfigKeys::RETIRED` を今のまま読む。`theme.yml` に廃止キーの宣言は作らない。同梱のテーマのオプションを廃止するときは、今と同じく `RETIRED` に書く |
| `ThemeValidator` | 宣言（`type`・`values`・`min`・`max`）からの検査に置き換える。扉絵・節絵の画像があるかの検査は、機能のコードに残す。`standard` での 🟡 の文面は、前後で同じにする |
| `config_keys_test.rb` | 下の 3 |
| `book_yml_consumption_test.rb` | `theme.*` のキーは、「`theme.yml` の `options:` に `token:` か `body_class:` つきで宣言されている」か「機能のコード（`theme/features/`）で読まれている」ことを検査する。`token:` で渡るキーは、`lib/` に名前が出なくなるためである |

- 読む側を分ける案を採らない理由: 分けると、既定値の重ね合わせと `vs config` の案内が、`theme:` 節だけ別の経路になる。`config-defaults-design-spec.md` が無くした「宣言が複数箇所にある」状態に戻る。

**2. `theme:` 節の、宣言に無いキー。**

今の vs は、`book.yml` の知らないキーを知らせずに読み飛ばす。S6 では、`theme:` 節に限って 🟡 で知らせる（`vs build` と `vs preflight` で同じものを出す）。ほかの節の扱いは変えない。

| キー | 扱い |
| :--- | :--- |
| `ConfigKeys::RETIRED` にある | 今の廃止の案内だけを出す（二重に知らせない） |
| 選ばれたテーマと、その機能の宣言に無い | 🟡「このテーマには無い設定です」。キーの名前・選ばれたテーマの名前・そのテーマで書けるキーの一覧を示す。綴りの近いキーがあれば「`colour` → `color`」の形で直し方を添える |

- 「前のテーマのオプションが残った」と「打ち間違い」は区別できないので、文面は一つにする。値は読まない。
- `theme:` 節だけを知らせる理由: テーマを替えると、同じ `book.yml` のまま有効なキーの組が変わる。ほかの節では起きない。

**3. 雛形の `book.yml` の `theme:` 節の正典。**

- 宣言と既定値の正典は、`themes/standard/theme.yml` と機能の宣言である。著者が読む説明（コメント）と、キーを載せる場所は、今と同じく直下の `config/book.yml` である。
- `config_keys_test.rb` は、重ねた表と照合する。`theme:` 節については、(a) `book.yml` のキーの組が、`name` ＋ `standard` の `options:` ＋ `standard` が使う機能のオプションと一致する、(b) 書かれた値が既定値と一致する、の二つを検査する。
- 種類ごとの雛形（S8）では、その種類の既定のテーマの宣言と照合する（`v2-architecture-spec.md` §2.2 のテストの (2) と同じ形）。

### 4.6 小説と絵本の既定のテーマ（問い 2.4）

- **S6 では `BookProfile::PROFILES` に `theme.name` を足さない。** S5 の決め 1（その時点で有効な値だけを書く）と同じである。`novel` の行の `theme.name` は、`bunko` を同梱する S8 で足す。`book_profile_test.rb` に「`PROFILES` の `theme.name` の値が、どれも同梱のテーマにある」を足し、名前だけが先に入らないようにする。
- **縦書きの本は、S6-3 から S8 まで 🔴 で止まる。止めてよい。** `book.type: novel` の本は、`theme.name` が既定の `standard` になる。`standard` は `supports.writing_mode: [horizontal]` なので、S6-3 で入る `supports:` の検査（`v2-architecture-spec.md` §2.5）が止める。`page.writing_mode: vertical` を直接書いた本も同じである。
- 理由:
  - S5 の決め 3（縦書きを止めない）は、綴じの向きと隠しノンブルを確かめるための、テーマの宣言が無い間の扱いだった。`standard` の本文は横組みで、縦書きの本として組める出力ではない。S6 でテーマが対応する組方向を宣言するので、宣言のとおりに止めるのが `supports:` の働きである。
  - 止まる理由の文面は「テーマ `standard` は縦書きに対応していません」になる。「テーマ `bunko` が無い」で止めるより、起きていることに合う。
  - `v2` は公開していない。ユーザーが普段使う `vs` は 1.x なので、止まって困る本は無い。
- 🔴 の文面は、仕様では「対応するテーマの名前を示す」である。S8 までは、本の `themes/` にも同梱のテーマにも縦書きに対応するものが無い。そのときは「縦書きに対応するテーマは、まだ同梱されていません」と示す。S8 で `bunko` の名前と `vs theme:add bunko` を示す形になる（対応するテーマを同梱の一覧から探す作りにしておけば、S8 で文面のコードを変えずに済む）。
- S5 の完了の条件の 4 のテストは、4.2 の決め 13 のとおり、材料のテーマで組む。

### 4.7 配色のテーマの見本（問い 2.5）

案 (b) とする。置き場は `test/vivlio_starter/fixtures/themes/standard-mono/`。完了の条件の 4・10 の確かめでは、写しの本の `themes/` へ複製して組む。

- 同梱（案 a）にしない理由: 同梱のテーマは、雛形に入り、`vs theme` の一覧に出て、`vs upgrade` の対象になり、2.x の間の保守を約束するものである。完了の条件を確かめるための見本に、その約束は要らない。
- テーマを作る人の見本は、`vs theme:new <名前> --extends standard` が作る雛形が担う（S6-8 で、その出力が `vs theme:check` を通ることをテストする）。書き方の説明は S11 のマニュアルで行う。
- 案 (c)（基準の写しだけ）にしない理由: 完了の条件の 10 の後半（`kindle_tokens:` に `font-size` を書くと 🟡）は `rake test` で確かめるので、材料がリポジトリに要る。
- モノクロ印刷に向けた配色のテーマを製品として同梱するかは、S6 とは別の企画である。採るかどうかはユーザーが決める。採るなら、`PLANNED.md` に 1 行足す。
- `theme-contract-spec.md` §9 の S6 の条件 4 の「`themes/standard-mono/`」は、「写しの本の `themes/standard-mono/`（材料は `test/vivlio_starter/fixtures/themes/`）」に直す。§7.1 の同梱のテーマの一覧は変えない。

### 4.8 `vs theme:add` の範囲（問い 2.6）

| 経路 | 段階 |
| :--- | :--- |
| 同梱のテーマの名前 | S6-8 |
| 手元のディレクトリ | S6-8 |
| 手元の zip | S6-8 |
| git の URL | S7（入口の実験の結果に依らず作る） |
| npm のパッケージ名 | S7（実験の結果による。`theme-contract-spec.md` §9 の S7 のとおり） |

- git を S7 に回す理由: ネットワークから取得する経路は、git と npm で同じ土台（一時ディレクトリへ取得する・取得したものを信用しない）を使う。2 回に分けて作る利益が無い。2.0 の公開の前に、git で配られているテーマは無い。配られたテーマは、zip を手元へ落とせば S6 の経路で入る。
- **複製の決まり（S6 で作り、三つの経路と S7 の二つの経路が同じものを通る）。**
  1. テーマのディレクトリは、`theme.yml` のあるディレクトリとする（指定した場所の直下か、その下の 1 階層）。見つからなければ 🔴。
  2. 複製するのは、拡張子の許可の表にあるファイルだけとする（`.yml`・`.css`・画像の `.webp`・`.png`・`.jpg`・`.jpeg`・`.svg`・`.avif`・書体の `.ttf`・`.otf`・`.woff`・`.woff2`・`README.md`・`LICENSE*`）。それ以外は複製せず、複製しなかったファイルの一覧を示す。本の中に実行できるファイルが入らないので、「スクリプトを走らせない」（`theme-contract-spec.md` §7.2）が、決まりではなく作りで成り立つ。
  3. シンボリックリンクは複製しない。zip は、中のパスが絶対パスか `..` を含む項目・シンボリックリンクの項目があれば、展開せずに 🔴 で止める。展開は一時ディレクトリで行う。
  4. 本の `themes/<名前>/` が既にあれば、置き換わるファイルの一覧を見せて確認を取る。「いいえ」なら何も変えない。
  5. `extends:` の先が本の `themes/` に無ければ、同梱のテーマなら一緒に入れ、そうでなければ無いと知らせる（`theme-contract-spec.md` §3.2）。
- `vs theme:check` に、テーマの CSS の中の外部の URL（`url(http…)`・`@import url(http…)`）を 🟡 で示す検査を足す。組むたびにネットワークへ取りにいくテーマを、入れた時点で知らせるためである。
- **git の経路の確かめ方（S7 の「作るもの」に書く）。**
  - 取得は、一時ディレクトリへ `git -c core.hooksPath=/dev/null clone --depth 1 --no-recurse-submodules <URL>` で行う。その後は上の複製の決まりだけを通し、取得したディレクトリの中でコマンドを走らせない（`bundle`・`npm`・`rake`・`make` を呼ばない）。
  - テストは、手元に作った材料のリポジトリ（`file://` の URL）で行う。材料には、`package.json`（`scripts.postinstall` が、決めた場所に印のファイルを作る）・`Rakefile`・`Makefile`・実行できる `.sh`・`.git/hooks/post-checkout` を入れる。`vs theme:add` の後で、(a) 本の `themes/<名前>/` に許可の表の拡張子のファイルしか無い、(b) 印のファイルができていない、(c) 一時ディレクトリが消えている、の三つを検査する。ネットワークは使わない。

### 4.9 基準の版（問い 2.7 の 1）

- **S6 の間は r2 のままとし、S6 の完了も r2 と比べる。** `theme-contract-spec.md` §9 の S6 の条件 3 の「S0 の基準」は、`v2-migration-plan.md` §4.1 のとおり「その時点の基準」と読む。
- S6 の間に上げない理由: S6 の変更は見た目を変えない。r2 との比べは、PDF は画素、HTML はバイト単位、CSS は計算値、Kindle は中間生成物で、どれも最後まで成り立つ。途中で上げると、B1〜B5 の組み直しと画面の撮り直しが増えるだけで、比べられるものは増えない。
- **r3 は、S6 の完了のコミットの後、S7 の前に、1 回だけ作る。** 次の順で行う。
  1. S6 の完了のコミット（r2 と比べ、差が 4.4 の「説明のつく字面の差」だけ）。
  2. CSS のコメントの `EpubBuilder`（14 か所・7 ファイル）を直すコミット。
  3. 節リードの決定（`v2-migration-plan.md` §4.1 の決まりで、この時点に置いてある）。見た目を変えるなら、ユーザーの了承を得てコミットする。
  4. r3 を作る（B1〜B5 を全部組み直す・B1 を二度組む・画面を撮り直す）。
- r3 の `VERSIONS.md` の「前の版から変わったもの」には、変数の名前・CSS の読む順（theme 層とテーマの出力先の CSS）・画像の置き場・コメント・（決めた場合は）節リードを書く。`v2-migration-plan.md` §3.2 の版の表に r3 の行を足す。
- 2 を S6 の中に入れない理由: コメントの修正は EPUB の CSS の字面を変える。S6-1・S6-3 の「前後でバイト単位で同じ」の比べに、関係の無い差が混ざる。

### 4.10 仕様の書き換え（問い 2.7 の 2）

要る。`css-layer-restructure-spec.md` §3.2 の線引き（消すと働かなくなるものは部品、飾りはテーマ）は、決まりとして残す。そのうえで、**S6 で theme 層へ移すファイルを、次の表に限る。**

| 今の置き場 | S6 の後 | 理由 |
| :--- | :--- | :--- |
| `parts/simple-header.css`・`parts/image-header.css` | `themes/standard/`（theme 層） | 見出しの組み方。選択子は `:root` の 1 規則を除いて全部 `vs-header-*` で絞ってあり、ほかの種類のページに当たらない |
| `stylesheets/images/bundled/`（12 枚） | `themes/standard/images/` | 扉絵・節絵の画像 |
| `targets/epub.css`・`targets/kindle.css` の、選択子が `vs-header-*` を含む規則 | `themes/standard/epub.css`・`kindle.css` | 4.2 の決め 11 |
| `stylesheets/tokens.css` | 残す（`--book-*` の一覧の正典） | 4.2 の決め 14。`standard` の `tokens:` は空 |
| `pages/chapter.css` の `@page :nth(1)`（扉絵） | 残す | 4.2 の決め 3 |
| `pages/appendix.css`・`pages/preface.css` の `:root` の付け替え | 残す | 付録の色・前書きの色は公開する変数（`--book-color-accent-appendix`・`-preface`）で、どのテーマでも働く仕組みである |
| `parts/heading.css`・`parts/prose.css`・`parts/box.css`・`parts/preface.css` などの、色・書体・余白・飾りの規則 | 残す | 下の箇条 |

- 見出しの 2 枚のほかを移さない理由:
  - 部品の色と書体は、すでに公開する変数を読んでいる。テーマは変数で変えられる。規則で変えたいテーマは theme 層に書けば、PDF では詳細度に関係なく勝つ（`css-layer-restructure-spec.md` §2.1）。規則を移さなくても、テーマにできることは減らない。
  - 規則を parts 層から theme 層へ移すたびに、4.2 の決め 1 と同じ入れ替わりが起きうる。組版のテーマが `standard` の 1 つしか無い時点では、どの規則が「どのテーマにも要る骨格」で、どれが「`standard` だけの飾り」かを確かめる相手が無い。
  - `css-layer-restructure-spec.md` §3.2 の「迷う規則は部品の側に置く」に合う。
- 残した規則のうち、`bunko`（S8）を書くときに打ち消しが要ったものを、S8 の中で `standard` へ移す。移す規則の一覧は、小説の仕様で決める。`theme-contract-spec.md` §10 の論点に 1 行足す（「部品に残した飾りの規則を `standard` へ移す範囲。答えが要る時点は S8」）。前書きの見た目（`parts/preface.css` の 207 行）が、いちばんの候補である。

### 4.11 決定を移す先（Opus が S6 の最初に行う）

| 移す先 | 書くこと |
| :--- | :--- |
| `theme-contract-spec.md` §3.1 | `tokens:` の書き出し先は tokens 層（決め 2）。`styles:` に直接並べる書き方（決め 12） |
| `theme-contract-spec.md` §3.2 | 配色のテーマの `tokens:` と土台のオプションの関係（決め 4） |
| `theme-contract-spec.md` §3.3 | `body_class:` の種類ごとの形（決め 5）・`default_from:`（決め 6）・`options:` に置けるものの範囲（決め 7）・宣言に無いキーの 🟡 の文面（4.5 の 2） |
| `theme-contract-spec.md` §3.4 | 扉絵の `@page` の規則は vs が持つ（決め 3）。15 個のキーの分け方の表（S6-7 の最初に作る） |
| `theme-contract-spec.md` §4 | 表を今のファイルの名前で書き直す（4.10 の表）。`tokens.css` の行と「章・前書き・付録の本文の見た目」の行を 4.10 のとおりに直す |
| `theme-contract-spec.md` §5.1・§5.2 | 名前を変える範囲と、内部の変数を変えないこと（決め 8） |
| `theme-contract-spec.md` §7.2 | `vs theme:add` の複製の決まり・外部の URL の 🟡（4.8）。`book.yml` の行を示すときに、テーマの値を覆う行も示す（決め 4） |
| `theme-contract-spec.md` §9 の S6 | 小段階の表と「S6 で決めること」（4.2 を `v2-architecture-spec.md` §8 の S5 と同じ形で）。条件 1 を今のファイルの名前に（`parts/simple-header.css`・`parts/image-header.css`・`stylesheets/images/bundled/` が無くなり、`themes/standard/` にある）。条件 3 に EPUB の基準（4.4）。条件 4 の材料の置き場（4.7）と、`theme.color` などを空欄にして組むこと |
| `theme-contract-spec.md` §9 の S7 | 「作るもの」に git の経路と、その確かめ方（4.8） |
| `theme-contract-spec.md` §10 | 論点を 1 行足す（4.10 の最後の箇条） |
| `css-layer-restructure-spec.md` §3.1・§3.2 | 配置の図の `themes/standard/` の中身。「S6 で当てる範囲」として 4.10 の表 |
| `css-layer-restructure-spec.md` §7.2 | 名前を変える範囲と、対応の表のテスト（決め 8） |
| `v2-architecture-spec.md` §2.2・§8 の S5 | `BookProfile` の `theme.name` は S8（4.6）。S5 の決め 3 に「S6-3 からは `supports:` の検査が止める」を足す。条件 4 のテストの材料（決め 13） |
| `v2-architecture-spec.md` §5.2・§5.3 | `ConfigKeys` の重ねる入口と、仕組みごとの読み方（4.5 の 1）。3 に、配色のテーマの `tokens:` を既定値として重ねること（決め 4） |
| `v2-migration-plan.md` §3.2 | r3 を作る時点と順（4.9）。B4 の写しに `themes/` を置く（4.3） |
| `v2-migration-plan.md` §3.6 | S6 の全部の比べの時点の表（4.3） |
| `v2-migration-plan.md` §4.3（S11） | 原稿の中の変数の名前を書き直す（決め 9） |
| `v2-migration-plan.md` §5.3 | 1.x の本の移行の手順は S11 のまま。S6-9 で作るのは `custom.css` の名前の置き換えとテーマの更新だけ |

移し終えたら、この文書は `docs/archives/` へ移す（`v2-post-s3-consultation.md` と同じ扱い）。
