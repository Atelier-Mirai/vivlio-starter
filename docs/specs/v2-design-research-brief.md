# 2.0 の設計に向けた調査依頼（叩き台）

2.0.0 の構想を設計へ進めるにあたり、Fable に調べて決めてほしい点をまとめる。現状の数字と根拠のファイルを添え、Fable がコード全体（Ruby 75,000 行・テスト 72,000 行・CSS 6,000 行）を読まずに着手できるようにする。

- 作成: 2026-11-10（叩き台）。2026-11-13 にユーザーの判断を §5 へ反映
- 構想の出どころ: `PLANNED.md` の「Version 2.0 構想」

---

## 0. 分担と進め方

| 担当 | 役割 |
|---|---|
| Fable 5.2（11/16 まで） | パイプライン全体の責務分割の見直し、拡張点（プラグイン機構など）の設計、移行計画の立案 |
| Opus 5.5 | 設計が固まった後のモジュールの書き換え、テストの追従、ドキュメントの更新。加えて、Fable の着手前に §4 の棚卸しと §3-D の実験を済ませる |

Fable の期間は 7 日しかないため、Fable が使う時間は判断に充てる。コードを読んで表を作る作業と、エンジンの挙動を確かめる小さな実験は Opus が先に行い、結果を文書で渡す。

1. Opus: §4 の棚卸しを `v2-inventory-report.md` にまとめる。§3-D の実験を行い、結果を `*-notes.md` に残す。
2. Fable: §6 の資料と棚卸し・実験の結果を読み、§3 の A〜C を設計する。成果物は §7。セッションの最初に渡す指示文は `v2-design-kickoff.md`。
3. ユーザー: §5 の論点を決める。Fable の設計の途中で確認を求められる。
4. Opus: Fable の仕様書に従って段階ごとに実装する。

---

## 1. 2.0 で目指すもの

構想は六つある。それぞれが設計に何を求めるかを並べる。

| 構想 | 設計に求めること |
|---|---|
| Vivliostyle 公式のテーマを取り込む | 公式テーマ（npm の `@vivliostyle/theme-*`）が前提とする HTML 構造と、vs が生成する HTML 構造（ページの種類ごとの CSS・`post_process` が付けるクラス）の差を埋める |
| CSS を `@layer` で整理する | `PLANNED.md` の五案。層の順序が、そのままテーマと利用者のテーマを差し込む位置になる |
| 利用者が自分のテーマを作れる | テーマが提供するもの（公開する変数・ページの種類ごとの部品・画像・書体・Kindle 用の値）と、vs が保証する HTML 構造を、契約として文書にする |
| 挿絵入りの縦書き小説 | 縦書き・右綴じ・ルビ・縦中横・傍点・漢数字・挿絵の配置。横書きの前提がコードと CSS に入っているので洗い出す。技術書用の機能（索引・用語集・文章の lint・コード・章番号の範囲）を外せるようにする |
| 画像が主体の絵本 | 全面の画像、見開き、画像への文字の重ね、固定レイアウトの EPUB。原稿の単位が章ではなくページになる |
| 動画を入れた動く絵本 | EPUB3 の `<video>`。PDF と Kindle では再生できないので、出力ごとに代わりの表現（ポスター画像と URL・QR コードなど）を持つ素材として扱う |

六つに共通する中心の問いは、**本の種類（技術書・小説・絵本）を一つの設定として束ねるか、テーマ・記法・出力の組み合わせとして別々に選ばせるか**である。§3 の A と B はこの問いへの答えを前提に組み立てる。

---

## 2. 現状の要点

Fable が読まずに済むよう、数字と場所を書いておく。

**コードの大きさ**

- `lib/` は 267 ファイル・75,367 行。大きいものは `build/epub_builder.rb`（3,858 行・EPUB と Kindle の処理が同居）、`doctor.rb`（1,697 行）、`index/unified_index_manager.rb`（1,604 行）、`lint/prose_checker.rb`（1,535 行）、`post_process.rb`（1,435 行）、`common.rb`（1,288 行）
- 設定は `config/book.yml` をモジュールの読み込み時に `Common::CONFIG`（凍結した `Data`）へ読む。グローバルな状態として全体から参照される

**ビルドの流れ**

- `build/pipeline.rb` の `UnifiedBuildPipeline`。`:full` は 14 段以上、`:single` は章ごとのプレビュー用の短縮版
- PDF の枝と EPUB の枝は fork で並列に走る（`VIVLIO_BUILD_PARALLEL`）。プロセス全体に効く API の落とし穴は `build-pipeline-pitfalls-notes.md`
- `vivliostyle.config.js` はビルドのたびに `build/vivliostyle_config_writer.rb` が生成する
- `@vivliostyle/cli` 11.3.3、`@vivliostyle/core` ^2.45.1、`@vivliostyle/vfm` ^2.7.2

**CSS**

- 27 ファイル・6,180 行。`chapter-common.css` が 1,066 行。`!important` が 18 か所。`body.vs-kindle` の上書きが 10 ファイルに散る
- 各ページの読み込み順は `pre_process/frontmatter_generator.rb` が決める: `theme.css` → `{種類}.css` → `book-settings.css`（生成物）→ `custom.css`
- `{種類}.css`（`chapter.css`・`appendix.css` など）が `base.css`・`theme.css`・`page-settings.css`・各部品を `@import` する。`preface.css` は `chapter-common.css` を読まず、段落・引用・字間の規則を別に持つ
- Kindle 向けの劣化は三か所に分かれる: 静的な CSS のリテラル、`pre_process/book_settings_css.rb` が書き出す規則、`EpubBuilder` の DOM の組み替え

**技術書に寄った前提**

- `book.yml` の `theme:` 節は技術書の章扉の設定（テーマ色 12 色・`style: image/simple`・扉絵と節絵の花の画像・見出し記号）
- 章番号の範囲で種類を決める（`00` 前書き・`01–89` 章・`90–98` 付録・`99` 後書き）
- 縦書きの記述は無い。`stylesheets/` に `writing-mode` は 0 件、`lib/` に `page-progression-direction` は 0 件
- CSS の方向の指定は、論理方向（`inline-start` など）が 169 か所、物理方向（`margin-left`・`left:`・`text-align: right` など）が 78 か所。`@page :left/:right` は 5 ファイル・9 か所

**既存の拡張点**

- PDF の低水準の操作は `cli/pdf/provider.rb` が標準（このリポジトリ）と拡張（別 gem `vivlio-starter-pdf`）を切り替える。現在ある唯一のプラグイン機構
- 記法の追加には `notation-implementation-guide.md` の型（Masking・GeneratedAssetCache・doctor・EpubBuilder の localize）がある

---

## 3. Fable に調べて決めてほしいこと

### A. パイプラインの責務分割

- **A-1 段の入れ替え**: 本の種類によって、外れる段・入れ替わる段・増える段はどれか。§4 の段の一覧表をもとに判断する。中間表現をどこに置くかも決める。今は Markdown の文字列の置換と、Nokogiri による HTML の後処理が中心で、段と段の間の形が文書になっていない。
- **A-2 出力先の抽象**: 今の出力先は PDF・印刷用 PDF・クリーン EPUB・Kindle の四つ。固定レイアウトの EPUB や Web 版を足すときの単位を決める。出力先を「HTML の変換規則と CSS の束」として表せるかを検討する。`epub_builder.rb` の分割はこの答えに従う。
- **A-3 Kindle 向けの劣化を一か所にまとめる**: §2 の三か所を一つの仕組みにする設計。`PLANNED.md` の「Kindle 用の CSS を別に生成する」案と組みになる。
- **A-4 設定の持ち方**: 本の種類やテーマで設定の形が変わるとき、`Common::CONFIG` をどう拡張するか。分冊（`catalog.yml` の `VOLUMES`）との関係、`book.yml` を機能別のファイルへ分けるか（`PLANNED.md` の項目）も合わせて決める。
- **A-5 技術書専用の機能を外せるようにする**: 索引・用語集・文章の lint・コードブロック・章番号の範囲・`vs metrics`。小説や絵本で無効にする単位と、既定値の持ち方を決める。

### B. 拡張点の設計

- **B-1 テーマの契約**: テーマが提供するもの（CSS の層・公開する変数・ページの種類ごとの部品・扉絵などの画像・書体・Kindle 用の値）と、vs が保証する HTML 構造（クラス名・`section` の入れ子・`body` のクラス）を決める。HTML 構造を仕様として書き出すことが契約の半分になる。素材は §4 の「HTML の構造の一覧」。
- **B-2 公式テーマとの接続**: 公式テーマの実物（§4 で取得）をもとに、次のどれが成り立つかを判断する。(1) 公式テーマを下の層に敷き、vs の部品を上に重ねる。(2) 公式テーマを採用し、vs 固有の部品（索引・用語集・奥付など）だけを足す。(3) 取り込むときに変換する。
- **B-3 テーマの置き場と解決**: プロジェクト内の `themes/`・gem・npm のどれで配るか。版の互換をどう示すか。`vs upgrade` と雛形の同期で、利用者のテーマと `custom.css` をどう守るか。
- **B-4 記法の拡張点**: 本の種類ごとの記法（小説のルビ・傍点・縦中横、絵本のページ区切り、動画）を、`notation-implementation-guide.md` の既存の型で受けられるか。受けられない場合に足す型を決める。
- **B-5 先例の評価**: PDF プロバイダの切り替えでうまく行った点と困った点（gem が入っているかで挙動が変わる、開発機では拡張側しか走らない）を、テーマや記法のプラグインの設計に生かす。
- **B-6 公開する範囲**: 公開した API には後方互換の負担が生じる。最初は内部の拡張点として作り、外部へ公開するのはテーマだけにする、といった段階を決める。

### C. 移行計画

- **C-1 既存の本の移行**: 1.x の `book.yml`（特に `theme:` 節）・`custom.css`・原稿が 2.0 で組めるようにする方法。`vs upgrade` で書き換えるか、旧キーを読む期間を置くか（`config-retirement-guidelines.md` の型）。
- **C-2 見た目が変わらないことの確かめ方**: CSS の再編は、写しの本で全章を組み、変更前と全ページの画素を比べる（`vivliostyle-css-pitfalls-notes.md` §2.18 の方法）。Kindle は Kindle Previewer で確かめる。段階ごとに何を比べれば完了とするかを決める。
- **C-3 進める順序**: 依存のある段階を並べ、各段階が単独でリリースできるかを決める。1.x の小さな版で出せるもの（見た目を変えない CSS の層化など）と、2.0 でしか出せないもの（後方互換を破るもの）を分ける。叩き台の順序は次のとおり。
  1. HTML 構造を仕様として書き出す
  2. CSS を層に分ける（見た目は変えない）
  3. Kindle 用の CSS を生成する
  4. テーマの契約を定め、今の見た目を一つのテーマとして切り出す
  5. 公式テーマを取り込む
  6. 縦書きの小説
  7. 絵本と動画
- **C-4 1.x の保守との並行**: 技術書典の 6 冊（登録の締切 12/6）は 1.x で組む。2.0 の作業は大物なので、当面 master へ直接コミットしている方針の例外としてブランチを切るかを決める。

### D. 設計の前提になる未知（Opus が先に実験する）

Fable の判断を左右するので、小さな実験で先に答えを出しておく。結果は `v2-feasibility-notes.md`（2026-11-13）。棚卸しの結果は `v2-inventory-report.md`。Kindle 向けの劣化は、§2 の三か所に加えて、組み上がった EPUB の CSS の書き換え（`sanitize_epub_css!`）があり、四か所だった。

- **D-1 Vivliostyle の `@layer`**: Vivliostyle core はページの処理（`@page`・ページの余白の箱・名前付きの文字列）を独自のカスケードで行う。`@layer` がそこでも効くか、`@import url(...) layer(...)` と `@font-face` が層の中で動くかを確かめる。
- **D-2 EPUB リーダーの `@layer`**: Apple Books・Kobo・Google Play Books で効くか。KFX は解さないことが分かっている。層を平坦にした CSS を生成するなら、何で生成するか（Ruby で書く、lightningcss などの Node の道具を使う）。
- **D-3 縦書き**: Vivliostyle での右綴じの `@page :left/:right`、柱とノンブル、縦中横、ルビ、傍点、挿絵の配置。Kindle の縦書き（KPF の変換での `primary-writing-mode` と `page-progression-direction="rtl"`）。クリーン EPUB での表示。
- **D-4 固定レイアウト**: EPUB3 の `rendition:layout pre-paginated` と見開き（`rendition:spread`・`page-spread-left/right`）。Kindle で固定レイアウトの絵本を出す方法（Kindle Kids' Book Creator・KPF）。`kindle-fixed-layout-ideas.md` は技術書向けに見送ったが、絵本では判断が変わる点を洗う。絵本を `kindle` で出すと決めたので（§5）、この実験は省けない。
- **D-5 動画**: EPUB3 の `<video>` の対応（Apple Books・Kobo・Kindle）、ストアの容量の上限、PDF での代わりの表現。Web 版を新しい出力先にするか（Vivliostyle CLI の Web 出版物の出力）。

---

## 4. Fable の着手前に Opus が作る棚卸し

コードを読んで表にする作業。Fable が大きなファイルを読まずに済むよう、`v2-inventory-report.md` に一つにまとめる。

1. **段の一覧表**: `pipeline.rb` の `full_mode_step_table` と `register_single_mode_steps` から、段ごとの入力・出力・読む設定キー・書き出すファイル・PDF と EPUB のどちらの枝か。
2. **HTML の構造の一覧**: VFM の出力に対して、前処理と `post_process` が付けるクラス・要素・`body` のクラス・`section` の入れ子。テーマの契約（B-1）の素材になる。
3. **横書きの前提の一覧**: 物理方向の CSS 78 か所の内訳、`@page :left/:right` 9 か所、Ruby で左右や綴じを扱う箇所（ノンブルの位置・表紙の順・表の回転など）。
4. **技術書専用の機能の対応表**: 索引・用語集・lint・metrics・コード・章番号の範囲が、`book.yml` のどのキーに対応し、どの段で使われるか。
5. **`EpubBuilder` のメソッドの分類**: EPUB 共通・クリーン EPUB だけ・Kindle だけ、に分けた表。
6. **Kindle 向けの劣化の全項目**: §2 の三か所それぞれで何を変えているか。
7. **公式テーマの実物**: `@vivliostyle/theme-*` を npm で取得し、ファイルの構成、`package.json` の `vivliostyle` 欄、前提とする HTML、ライセンス、変数の名前を一覧にする。2026-11-13 に npm で確かめた範囲では、公式は `theme-base`（部品の集まり）・`theme-bunko`（文庫・縦書き）・`theme-epub3j`（電書協 EPUB 3 制作ガイド準拠）・`theme-techbook`・`theme-academic`・`theme-gutenberg`（欧文）・`theme-slide` の 7 つで、いずれも 2026-10-28 公開の 3.x。ライセンスは `theme-base` が Apache-2.0・CC0-1.0・MIT の併用、他は CC0-1.0。

---

## 5. ユーザーの判断

### 決まったこと（2026-11-13）

- **出力先**: 小説と絵本も、技術書と同じく `pdf`・`print_pdf`・`epub`・`kindle` の四つで出す。目指す紙面は Vivliostyle 公式の縦書きの作例（「銀河鉄道の夜」）に、ときどき挿絵を入れた形。絵本を `kindle` で出す場合、リフロー型では紙面を保てないため、固定レイアウトの KPF が前提になる（§3-D-4 は省けない実験になる）。
- **動画の代わりの表現**: `pdf` と `kindle` では動画のサムネイルを見せる。電子の PDF と Kindle ではサムネイルに動画へのリンクを張り、紙に刷る `print_pdf` では QR コードを添える。
- **Web アプリとしての配布**: PWA などの簡単な Web アプリとして配る形も候補にする。2.0 で作るかは Fable が決めるが、出力先の抽象（§3-A-2）は、後から Web 出力を足せる形にしておく。Slidev は Markdown の方言とツールチェーンが vs と別なので、取り込む対象とはしない。スライドが要るなら、公式の `@vivliostyle/theme-slide` で同じツールチェーンの中に収まるかを先に見る。
- **テーマの配布**: エディタのカラーテーマ（Monokai など）のように、他の人へ配れる形を目指す。今は `custom.css` を差し替えると 12 色だけを変えられる。CSS を再編すれば、色だけでなく組版の全体を配れるようになる。
- **HTML 構造の変更**: 見た目が変わる変更は 2.0 で入れる。1.x の小さな版には入れない。
- **1.x の保守期間**: 2.0 の公開から 3 か月。

### Fable に検討してほしい点（上の決定から生じたもの）

- **テーマを二段に分けるか**: エディタのカラーテーマは「配色を宣言したデータ」で、エディタ本体のレイアウトには触れない。同じ形で、(1) 配色や書体などの値だけを宣言する**カラーテーマ**（YAML か JSON。組版を壊さず、Kindle 用のリテラル化もそのまま効く）と、(2) CSS の層と画像を含む**組版テーマ**に分けると、配る側と使う側の負担を段階にできる。二段にするか、一段で足りるかを決める。
- **変数名の接頭辞の衝突**: 公式テーマは `--vs--*`・`--vs-page--*`・`--vs-theme-bunko--*` のように `vs` を Vivliostyle の略として使う。vs（Vivlio Starter）の `body.vs-epub`・`body.vs-kindle` などのクラスと、これから決める公開変数の名前が、公式テーマと衝突しないようにする。
- **1.x の保守の中身**: 3 か月の間に何を出すか（不具合と依存の更新だけにするか）。2026-12-25 の Ruby 4.1.0 対応と、2027 年 1 月の Kindle Previewer 3 の扱いの削除（`PLANNED.md`）は、2.0 の公開時期によっては 1.x の作業になる。保守を終える前に、技術書典の 6 冊を含むユーザー自身の本を 2.0 へ移行し終えることを条件にする。

### 本の種類の順序と、2.0 に含める機能（2026-11-13）

三つの本の種類はすべて 2.0 で扱う。順序は次のとおり。

1. **縦書きの小説**: 文字が中心で、出力の形は今と同じ。公式テーマ（`theme-bunko`・`theme-epub3j`）が手本になる。
2. **絵本**: 固定レイアウトという新しい出力の形が加わる。
3. **動く絵本**: 絵本に、動画の代わりの表現と、場合によっては Web 出力が加わる。

本の種類に結びつく次の 5 件も 2.0 に含める。設計（§3-A-5・§3-B-4）では、これらが拡張点の最初の利用例になる。

| 機能 | 結びつく本の種類 | 設計で見る点 |
|---|---|---|
| `vs furigana`（半自動の振り仮名） | 絵本（子ども向け）・小説 | `PLANNED.md` の既存項目。学年別の水準は `furigana-level-spec.md` |
| 小説投稿サイトの記法を読む（ルビ `\|漢字《かんじ》`・傍点 `《《…》》`） | 小説 | 前処理で vs の記法へ置き換えるか、`vs import` の小説版にするか |
| 小説の表記の lint（「……」「――」の二つ重ね・「！」「？」の後の全角空白・閉じ括弧の前の句点・段落頭の字下げ） | 小説 | 本の種類で lint の規則を切り替える仕組み（§3-A-5） |
| 背表紙とくるみ表紙 | 小説（同人誌として刷る場合） | `PLANNED.md` の既存項目（「ビルド / 出力」と「分冊」）。判型と頁数から背幅を求める |
| 縦書きの記法（縦中横・傍点） | 小説 | `notation-implementation-guide.md` の型に載せる。縦中横は数字の自動判定を含む |

---

## 6. Fable が読む資料

**読む**

- 規則と構想: `.claude/CLAUDE.md`、`PLANNED.md` の「Version 2.0 構想」、`NOTES.md`
- エンジンと出力先の知見: `vivliostyle-css-pitfalls-notes.md`、`kindle-css-compatibility-notes.md`、`kindle-fixed-layout-ideas.md`、`vfm-config-flow-notes.md`、`build-pipeline-pitfalls-notes.md`
- 設計の型: `notation-implementation-guide.md`、`config-key-criteria-guidelines.md`、`config-retirement-guidelines.md`
- 棚卸しと実験の結果: `v2-inventory-report.md`、§3-D の `*-notes.md`
- コード（必要な範囲だけ）: `lib/vivlio_starter/cli/build/pipeline.rb`、`build/vivliostyle_config_writer.rb`、`pre_process/frontmatter_generator.rb`、`pre_process/book_settings_css.rb`、`post_process/body_class_injector.rb`、`pdf/provider.rb`、`common.rb` の設定の部分、`stylesheets/_README.md`、`stylesheets/theme.css`

**読まない**

`index/`・`lint/`・`metrics/`・`import/`・`doctor/`、`pdf/` の `pdf:read` 系（`layout_structure.rb`・`structure_markdown.rb` など）、`test/` の大半。これらは本の種類によって有効・無効を切り替える側として扱い、パイプラインとの境界（どの段から呼ばれ、どの設定キーを読むか）だけを §4 の表で見る。

---

## 7. Fable の成果物

Opus が読み直しをせずに実装へ移れるよう、各仕様書に段階・完了の条件・確かめ方を書く。

| ファイル | 内容 |
|---|---|
| `v2-architecture-spec.md` | 本の種類の扱い、パイプラインの責務分割、出力先の抽象、設定の持ち方（A・B-4〜B-6） |
| `theme-contract-spec.md` | テーマの契約、vs が保証する HTML 構造、公式テーマとの接続、テーマの置き場（B-1〜B-3） |
| `css-layer-restructure-spec.md` | 層の順序、Kindle 用 CSS の生成、ファイルの分け方（`PLANNED.md` の五案の具体化） |
| `v2-migration-plan.md` | 段階の順序、各段階の確かめ方、既存の本の移行、1.x との並行（C） |

縦書き小説・絵本・動画の個別の仕様は、上の四本が固まった後に書く。Fable の期間内に間に合わなければ、要件と論点だけを残して Opus が引き継ぐ。
