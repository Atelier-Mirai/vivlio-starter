# S6 の小段階と、段階の中で決めること（Fable への相談）

> 作成日: 2026-11-16
> ステータス: **答え待ち**
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
