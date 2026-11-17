# 2.0 のアーキテクチャ（本の種類・パイプライン・出力先・設定）

> 作成日: 2026-11-14
> ステータス: **一部実装済み**（S4 は 2026-11-16 に完了・§10。S5・S8〜S10 は実装待ち）
> 対象: 2.0.0 で、技術書に加えて縦書きの小説・絵本・動く絵本を `pdf`・`print_pdf`・`epub`・`kindle` の四つで出せるようにするための、本体の構造の決定
> 出自: `v2-design-research-brief.md` §3 の A（A-1〜A-5）と B-4〜B-6。事実は `v2-inventory-report.md` と `v2-feasibility-notes.md` による
> 組になる仕様書: `theme-contract-spec.md`（テーマと HTML の契約）・`css-layer-restructure-spec.md`（CSS の層と Kindle 用の CSS）・`v2-migration-plan.md`（段階の順序。段階の番号 S0〜S11 はそちらが正典）

---

## 0. この文書の読み方

- §1 は決定の一覧である。実装者はまずここを読み、必要な節へ進む。
- §2〜§7 は決定の中身と理由である。「〜とする」と書いた文は決定で、実装で変えるときはユーザーの了承を得る。
- §8 は段階ごとの完了の条件と確かめ方である。段階の順序と依存は `v2-migration-plan.md` に書く。
- §9 は未決の論点である。実装の途中で答えが要る時点を添えた。
- 縦書きの小説・絵本・動く絵本の個別の仕様（記法の細部・紙面の寸法）は、本書の枠の中で別の仕様書に書く。本書は、それらが入る場所と境界だけを決める。

---

## 1. 決定の一覧

| 問い（brief） | 決定 | 節 |
| :--- | :--- | :--- |
| 中心の問い | 本の種類は `book.type` の 1 語で書く。実体は独立した軸の既定値の組で、コードは種類を読まず軸の値を読む（2026-11-13 ユーザー了承） | §2 |
| A-1 段の入れ替え | 段の表（`full_mode_step_table`）は残し、実行条件を `BuildPlan`（出力先・軸・機能）から決める。中間表現は新設せず、`html/` の HTML を「契約 HTML」として文書化する | §3 |
| A-2 出力先の抽象 | 出力先を `OutputTarget`（HTML の変換の並び・CSS の形・本全体の段の並び・素材の方針・梱包）として宣言する。`epub_builder.rb` はこの単位で分割する | §4 |
| A-3 Kindle 向けの劣化 | 四か所を、Kindle の出力先の宣言（変換の並び）と、CSS の生成（`css-layer-restructure-spec.md`）の二つにまとめる | §4.4 |
| A-4 設定の持ち方 | `Common::CONFIG` の形は変えない。既定値の解決に「種類の既定値」の段を一つ足す。`theme:` 節は「テーマ名＋そのテーマのオプション」にする。`book.yml` は分けない | §5 |
| A-5 技術書専用の機能 | 機能ごとに既存のキーか新しいキーで切り替え、種類の既定値で初期値を与える | §6 |
| B-4 記法の拡張点 | 既存の三つの型に、行内の属性の型と、出力先で形が変わる素材の型を足す | §7.1 |
| B-5 先例の評価 | 入っているかで挙動が変わる仕組みは作らない。拡張は `book.yml` に書いたときだけ効く | §7.2 |
| B-6 公開する範囲 | 外部へ公開する契約はテーマだけ。出力先・変換・記法・lint の規則の組は内部の登録表にとどめる | §7.3 |
| Web 出力 | 2.0 では作らない。`OutputTarget` に後から足せる形にする | §4.6 |

---

## 2. 本の種類と軸

### 2.1 軸

本の性質を、互いに独立した軸に分ける。著者が `book.yml` に書くのは次の表の「キー」の列である。

| 軸 | キー | 値 | 連動して決まるもの（キーにしない） |
| :--- | :--- | :--- | :--- |
| 本の種類 | `book.type` | `techbook`（既定）・`novel`・`picture_book` | ほかの軸の既定値（§2.2） |
| 組方向 | `page.writing_mode` | `horizontal`・`vertical` | 綴じの向き（横＝左綴じ・縦＝右綴じ）、ページの進む向き、奇数ページの左右 |
| レイアウト | `page.layout` | `reflowable`・`fixed` | 原稿の単位（リフロー＝章・固定＝ページ）、EPUB の梱包の方法、Kindle へ出すファイルの形式 |
| テーマ | `theme.name` | テーマの名前 | テーマのオプションの一覧（`theme-contract-spec.md` §3.3） |
| 機能 | §6 の各キー | | |
| 出力先 | `output.targets` | 今と同じ | |

- 動く絵本は種類にしない。`picture_book` に動画の記法（§4.5）を使った本である。
- 綴じの向きと原稿の単位をキーにしないのは、もう一方を選ぶ著者を描けないためである（`config-key-criteria-guidelines.md` §2.4。縦書きの左綴じ・固定レイアウトの章単位の原稿）。必要になったらキーを足せるよう、コードは §2.4 の `BookTraits` の導出値を読む。
- `output.epub.layout` と `output.kindle.layout`（どちらも `reflowable` だけが有効だった）は廃止し、`page.layout` に一本化する（§5.1）。レイアウトは出力先ごとではなく本の性質である。固定レイアウトの絵本をリフロー型の EPUB で出す場面は無い。

### 2.2 種類の既定値（`BookProfile`）

種類は「軸と機能の既定値の組」である。`lib/vivlio_starter/cli/book_profile.rb` に 1 枚の表として宣言する。

```ruby
module VivlioStarter::CLI::BookProfile
  # 種類ごとに、ConfigKeys の既定値と違うキーだけを書く
  PROFILES = {
    techbook: {},
    novel: {
      %i[page writing_mode]       => 'vertical',
      %i[page use]                => 'a6_standard',
      %i[page heading_numbering]  => 'none',
      %i[theme name]              => 'bunko',
      %i[index_glossary enabled]  => false,
      %i[lint ruleset]            => 'novel',
      %i[metrics use]             => 'none',
      %i[notation web_novel]      => true
    },
    picture_book: {
      %i[page layout]             => 'fixed',
      %i[page heading_numbering]  => 'none',
      %i[theme name]              => 'picture',
      %i[index_glossary enabled]  => false,
      %i[lint ruleset]            => 'minimal',
      %i[metrics use]             => 'none'
    }
  }.freeze
end
```

- 値の解決の順は「`ConfigKeys` の既定値 → 種類の既定値 → `book.yml` に書いた値」とする（§5.3）。
- `book.type` が無い `book.yml`（1.x の本）は `techbook` として読む。1.x の本は何も書き足さずに今と同じ値で組める。
- 表の中身（判型の名前・テーマの名前）は、小説と絵本の個別の仕様で確定する。上の表は形を示すためのものである。
- **`theme.name` の行は、そのテーマを同梱する段階で足す（`v2-s6-consultation.md` §4.6）。** `novel` の `bunko` は S8、`picture_book` の `picture` は S9 である。それまで `book.type: novel` の本は既定の `standard` で読まれ、`standard` が横書きだけに対応する（`supports.writing_mode: [horizontal]`）ので、S6 から S8 まで §2.5 の検査が 🔴 で止める。`book_profile_test.rb` に「`PROFILES` の `theme.name` の値が、どれも同梱のテーマにある」を足し、名前だけが先に入らないようにする。
- テスト（`book_profile_test.rb`）で次を検査する。(1) 表のキーがすべて `ConfigKeys::KEYS` にある。(2) 種類ごとの雛形の `book.yml` に書かれた値が、その種類の解決後の既定値と一致する（`config_keys_test.rb` が今の雛形に対して行っている検査を、種類ごとに行う）。

### 2.3 コードは種類を読まない

`book.type` を読んでよいのは次の三か所だけとする。

1. `Common.load_config`（種類の既定値を重ねる）
2. `vs new`（種類ごとの雛形を選ぶ）
3. 著者向けの表示（`vs doctor` などが種類の名前を出す場合）

それ以外のコードが「小説なら」と分岐したくなったら、分岐の理由になっている性質を軸か機能のキーにする。たとえば「小説なら縦中横を自動で付ける」ではなく「組方向が縦なら付ける」と書く。

- 理由: 種類での分岐を許すと、種類を一つ足すたびに全体を調べ直すことになる。また「横書きの小説」「縦書きの人文書」のような、種類の既定値から一つだけ軸を変えた本が組めなくなる。
- 検査: `book_type_usage_test.rb` が `lib/` を走査し、`book.type`・`book&.type`・`dig(:book, :type)` の参照が上の三か所のファイル以外に無いことを確かめる。

### 2.4 軸の値を読む窓口（`BookTraits`）

軸の値と、連動して決まる値を一つの `Data` にまとめる。`lib/vivlio_starter/cli/book_traits.rb` に置く。

```ruby
BookTraits = Data.define(:writing_mode, :layout) do
  def self.resolve(config = Common::CONFIG) = new(...)   # page.writing_mode / page.layout を正規化して作る

  def vertical?   = writing_mode == :vertical
  def fixed?      = layout == :fixed
  def binding     = vertical? ? :rtl : :ltr          # ページの進む向き
  def recto_side  = vertical? ? :left : :right       # 奇数ページの側
  def unit        = fixed? ? :page : :chapter        # 原稿の単位
end
```

`Common.traits` で引けるようにし、`reload_configuration!` で作り直す。今「横書き・左綴じ」を前提にしている次の箇所は、この値を読むように直す（`v2-inventory-report.md` §3.2・§3.3）。

| 箇所 | 今 | 直し方 |
| :--- | :--- | :--- |
| `build/vivliostyle_config_writer.rb` | `readingProgression: 'ltr'` の固定 | `traits.binding` |
| `build/nombre_stamper.rb` の `draw_page_number` | 奇数ページのノドを左端とする | `traits.recto_side` が `:left` なら左右を入れ替える |
| EPUB の `content.opf` | `page-progression-direction` を書かない | `traits.binding` が `:rtl` のとき `spine` に書く。Kindle は `primary-writing-mode` の `meta` も書く（`v2-feasibility-notes.md` §3.2） |
| `@page :left/:right` の柱とノンブル（5 ファイル・9 か所） | 左右を物理方向で書く | `css-layer-restructure-spec.md` §6 |
| 表紙の順（表 1・表 4） | 左綴じの順 | 背表紙とくるみ表紙の仕様で `traits.binding` を読む |

### 2.5 組み合わせの検査

軸は独立だが、通らない組み合わせがある。`Guards::TraitCombinationCheck` を足し、`vs build` と `vs preflight` の入口で同じ検査をする（`terminal-output-notes.md` の「build と preflight で同じものを出す」）。

| 組み合わせ | 扱い |
| :--- | :--- |
| テーマが対応しない組方向・レイアウト（テーマの `supports:`・`theme-contract-spec.md` §3） | 🔴 で止める。対応するテーマの名前を、本の `themes/` と同梱のテーマから探して示す。無ければ「縦書きに対応するテーマは、まだ同梱されていません」の形で示す（S8 まではこの文面になる。探す作りにしておけば、S8 で文面のコードを変えずに済む） |
| `page.layout: fixed` と `index_glossary.enabled: true` | 🟡。固定レイアウトでは索引と用語集のページを作らない、と示す |
| `page.layout: fixed` と `targets` の `kindle` | 警告はしない。KPF に変換せず EPUB を出力する、と出力の一覧に示す（§4.2） |
| 動画のある本で `targets` が `print_pdf` を含む | 警告はしない。閲覧用 PDF からの導出をやめ、組み直す（§4.5） |

### 2.6 雛形

`vs new mybook --type novel` で種類を選ぶ。省略時は `techbook`。

- 雛形は「共通の部分」と「種類ごとの差分」に分ける。共通の部分（`stylesheets/`・`themes/`・`templates/`・`package.json` など）の正典は今と同じくリポジトリの直下で、種類ごとの差分（`config/book.yml`・`config/catalog.yml`・`contents/` の見本・`covers/`）の正典は `scaffolds/<種類>/` に置く。`techbook` の差分は今と同じく直下の `config/`・`contents/` である。
- `ruby scripts/copy_to_scaffold.rb` は、直下を `lib/project_scaffold/` へ、`scaffolds/<種類>/` を `lib/project_scaffold_types/<種類>/` へ複製する。`vs new` は前者を写した後、後者を上から重ねる。
- 種類ごとの `book.yml` には、その種類で意味のあるキーだけを載せる。「載せると決めたキーは全部書く」（`config-key-criteria-guidelines.md` §1）は種類ごとに適用する。小説の `book.yml` に `index:` や `glossary:` の節は載せない。載せないキーは種類の既定値で動く。
- `scaffolds/<種類>/` は、それ自体が組める本であること（`cd scaffolds/novel && ../../bin/vs build` が通る）。直下の本書が技術書の確かめに使われているのと同じ役目を、小説と絵本で担う。

---

## 3. パイプラインの責務分割

### 3.1 五つの層と中間表現

ビルドを五つの層に分け、層の間の形を決める。段（ステップ）は今のまま残し、どの層に属するかを明らかにする。

| 層 | 入力 | 出力（置き場） | 責務 | 読んでよいもの |
| :--- | :--- | :--- | :--- | :--- |
| L1 原稿の読み込み | `contents/`・`catalog.yml` | 原稿の単位の並び（`Entry` の配列） | 章かページかを決め、番号と種類を振る | `traits.unit` |
| L2 前処理 | 原稿の Markdown | 前処理済みの Markdown | 記法を VFM が読める形にする。検査して原稿の行番号で指摘する | 機能のキー・`traits` |
| L3 HTML 化 | 前処理済みの Markdown | **契約 HTML**（`.cache/vs/build/html/`） | VFM で変換し、後処理で構造を整える | 機能のキー・`traits` |
| L4 出力先ごとの変換 | 契約 HTML | 出力先の HTML と CSS（`pdf/`・`epub/`・`kindle/`） | 出力先が扱えない表現を置き換える。CSS の束を作る | `OutputTarget`・テーマ |
| L5 組版と梱包 | 出力先の HTML と CSS | PDF・EPUB・KPF | Vivliostyle で組む。結合・しおり・変換・検査 | `OutputTarget`・`traits` |

決定:

- **中間表現は新しく作らない。** L3 の出力である `html/` の HTML を、唯一の文書化された中間表現とし、「契約 HTML」と呼ぶ。構造は `theme-contract-spec.md` §2 に書く。
  - 理由: 前処理の 38 段は Markdown の文字列の置換、後処理の約 30 段は HTML の書き換えで、合わせて 1 万行を超える。これらを構文木の上に書き直す利益は、2.0 の目的（本の種類・テーマ）に対して小さい。テーマと出力先が読むのは L3 の出力だけなので、形を決める必要があるのはそこだけである。
  - L2 の中の段と段の間（Markdown の文字列）と、L3 の中の段と段の間（HTML のファイル）は、今と同じく内部の形とし、文書にしない。
- **契約 HTML は出力先とテーマに依らない。** 同じ原稿と同じ機能のキーからは、どの出力先・どのテーマでも同じ契約 HTML ができる。出力先の違いは L4 が、見た目の違いは CSS が受け持つ。今この決まりに反している箇所と直し方は `theme-contract-spec.md` §2.6 に書く。
- **契約 HTML は、出力先が扱えるうちで最も豊かな表現を持つ。** 動画は `<video>`、図は SVG、色は CSS の変数のまま持ち、扱えない出力先の L4 が置き換える。今の `img[data-vs-raster]`（SVG を EPUB でラスターに差し替える）と同じ考え方を一般化したものである（§4.5）。

### 3.2 `BuildPlan` と段の表

今の段の表は `[ラベル, ハンドラ, 実行条件, 相, 単位]` で、実行条件は `targets` から決まる真偽値である。この形を保ち、条件の材料を一つにまとめる。

```ruby
# lib/vivlio_starter/cli/build/plan.rb
BuildPlan = Data.define(:targets, :traits, :features) do
  def self.resolve(config = Common::CONFIG) = new(...)
end
# features は機能の有効・無効をまとめた Data（index:, techbook_post_process:, web_novel: など。§6 の表の「窓口」の列）
```

- `UnifiedBuildPipeline` はビルドの開始時に `BuildPlan.resolve` を一度だけ呼び、`full_mode_step_table` の条件の列は `plan` だけを読む。ビルドの途中で `Common::CONFIG` から軸や機能を読み直さない。
- 段のハンドラの中で `Common.index_enabled?` のように設定を読んで戻っている箇所（`index scan and build`・`techbook post-process`）は、条件の列へ移す。段を走らせるかどうかが表だけで読めるようにする。
- `SINGLE_MODE_SKIP` と単位（`:chapter`・`:whole_book`）の意味は変えない。

### 3.3 軸と機能で変わる段

`v2-inventory-report.md` §1.1 の段のうち、条件が増えるものと、増える段を示す。書いていない段は条件を変えない。

| 段 | 相 | 条件に足すもの | 備考 |
| :--- | :--- | :--- | :--- |
| `prepare theme images` | shared | テーマが扉絵・節絵の機能を使う（`theme-contract-spec.md` §3.4） | `book-settings.css` の生成はこの段から切り離し、常に走る別の段にする |
| `preprocess sections` | shared | `!traits.fixed?` | 固定レイアウトは §3.5 の段に替わる |
| `index scan and build` | shared | `features.index` | |
| `convert sections html` | shared | `!traits.fixed?` | |
| `generate part title pages` | shared | `!traits.fixed?` | |
| `techbook post-process` | shared | `features.techbook_post_process` | |
| `generate toc html` | shared | `!traits.fixed?` | 固定レイアウトの目次は EPUB の `nav` だけ |
| `backlink dedup` | pdf | `features.index` | 索引が無ければ組み直しも要らない |
| `check chapter leads` | pdf | テーマが扉絵の機能を使う | |
| `print pdf` | pdf | 導出の条件に「動画が無い」を足す（§4.5） | |
| `generate epub` | epub | 変えない | 中身は `OutputTarget` ごとの流れになる（§4） |
| **`build page spreads`**（新） | shared | `traits.fixed?` | 絵本のページの HTML を作る（§3.5） |
| **`build cover spread`**（新） | pdf | 背表紙とくるみ表紙の仕様で決める | `traits.binding` とページ数から背幅を求める |

縦書きで増える処理（縦中横の自動判定など）は、段を足さずに L3 の後処理の中の一段として入れる（§7.1）。

### 3.4 前処理の並びを表にする

`MarkdownPreprocessor#run` は 38 個のメソッド呼び出しの並びである。これを段の表と同じ形にする。

```ruby
STEPS = [
  # [メソッド, 種別, 条件]
  [:validate_directives!,        :check,     nil],
  ...
  [:transform_web_novel_marks!,  :transform, ->(plan) { plan.features.web_novel }],
  ...
].freeze
```

- 並びの順は今と同じにする。順序の理由は、今と同じく各メソッドのコメントに書く（`notation-implementation-guide.md` §0 の 5）。
- 条件が `nil` の段は常に走る。記法を使っていなければ何もしない段（コード・数式・mermaid など）には条件を付けない。条件を付けるのは、有効にすると既存の本の出力が変わりうる段だけとする。
- 後処理（`PostProcessCommands.execute_post_process`）も同じ形にする。

### 3.5 固定レイアウトの経路（枠だけ決める）

`traits.fixed?` の本は、L1〜L3 が別の実装になる。L4 と L5 は共通の仕組みを使う。

| 層 | リフロー | 固定レイアウト |
| :--- | :--- | :--- |
| L1 | `TokenResolver`（章の番号の範囲で種類を決める） | ページの並びを読む（1 ファイルに複数ページか、1 ファイル 1 ページかは絵本の仕様で決める） |
| L2・L3 | 前処理 → VFM → 後処理 | `build page spreads`: ページごとに、寸法の決まった 1 枚の HTML を作る |
| 契約 HTML | 章ごとの HTML | ページごとの HTML（`body` に `vs-fixed` と、ページの種類のクラス。`theme-contract-spec.md` §2.7） |
| L4 | 出力先の変換 | 同じ仕組み。変換の並びは固定レイアウト用 |
| L5 | Vivliostyle の PDF・EPUB | PDF は Vivliostyle（判型＝ページの寸法）。EPUB は vs が自分で梱包する（Vivliostyle CLI の EPUB 出力はリフロー型を前提にするため。`v2-feasibility-notes.md` §4 で Ruby から最小の固定レイアウト EPUB を組めることは確認済み） |

章の番号の範囲（`00`・`01–89`・`90–98`・`99`）はリフローの本だけの決まりとし、固定レイアウトには持ち込まない。小説はリフローなので、今の番号の範囲をそのまま使う。

---

## 4. 出力先の抽象

### 4.1 `OutputTarget`

出力先を、次の項目を持つ宣言として表す。`lib/vivlio_starter/cli/build/output_target.rb` に型と登録表を、`build/targets/<名前>.rb` に各出力先の宣言を置く。

```ruby
OutputTarget = Data.define(
  :id,          # :pdf / :print_pdf / :epub / :kindle
  :branch,      # :pdf / :epub（どちらの枝で走るか）
  :workspace,   # 出力先の HTML と CSS を置くディレクトリ
  :body_classes,# body に足すクラス（['vs-epub'] など）
  :transforms,  # 1 ページの契約 HTML だけを見て書き換える段の並び（§4.3）
  :css_form,    # :layered / :flat / :flat_literal（css-layer-restructure-spec.md §4）
  :finalizers,  # 本の全部のページと CSS を見る段の並び（変換の後・梱包の前。§4.3）
  :assets,      # 素材の方針（使える画像の形式・SVG を同梱できるか・動画の扱い）
  :packager     # 梱包の方法
)
```

- 出力先は「HTML の変換規則と CSS の束」に、素材の方針と梱包の方法を加えた四つで表せる。brief の A-2 の問いへの答えは「表せる。ただし二つでは足りず、素材と梱包が要る」である。
- **`finalizers` は S3 の後に足した（2026-11-15・`v2-post-s3-consultation.md` §5.5）。** S3 で、ページごとの変換の後に、本の全部のページと CSS を見て書き直す段が三つ入った（`custom.css` を平らな CSS でも勝たせる・異体字の 1 字書体・層を外すと勝ち負けが変わる組の報告）。
  - `transforms` に入れない理由: 変換は「1 ページだけを見る」ことを決まりにする。この決まりがあるから、`runner.rb` は 1 ページを一度読んで一度書く形にでき、後でページごとに並べて走らせる余地も残る。本全体を見る段を混ぜると、決まりが崩れる。
  - `css_form` に付けない理由: 三つのうち一つ（異体字の 1 字書体）は CSS の形と関係が無く、一つ（`custom.css` を勝たせる）は HTML も書き直す。
- `transforms`・`finalizers`・`assets`・`packager` は `traits` によって変わる。宣言は `OutputTarget.for(id, traits)` で引き、リフローと固定レイアウトで別の値を返す。固定レイアウトの `finalizers` は S9 で決める。

### 4.2 四つの出力先

| 出力先 | 変換の並び | CSS の形 | 本全体の段 | 画像 | 動画 | 梱包 |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `pdf` | なし（Type 3 対策は L3 の段のまま） | 層あり | なし | そのまま | サムネイルに動画へのリンク | Vivliostyle → 結合 → しおり |
| `print_pdf` | `pdf` と同じ | 層あり | なし | そのまま（本文の画像の CMYK への変換は未実装。表紙だけ変換する） | サムネイルと QR コード | `pdf` から導出するか、組み直す |
| `epub`（リフロー） | 共通の 10 段 | 平ら | `AuthorPriority` → `InversionReport` | WebP | `<video>` と、再生できない読者向けの代わりの表示 | Vivliostyle の EPUB |
| `kindle`（リフロー） | 共通の 10 段 ＋ Kindle の 17 段 | 平ら・リテラル | `AuthorPriority` → `VariantGlyphFonts` → `InversionReport` | JPEG・PNG（SVG と WebP は同梱しない） | サムネイルに動画へのリンク | Vivliostyle の EPUB → KPF |
| `epub`（固定） | 固定レイアウト用 | 平ら | S9 で決める | JPEG・PNG・WebP | `<video>` | vs が梱包 |
| `kindle`（固定） | 固定レイアウト用 ＋ 動画の置き換え | 平ら・リテラル | S9 で決める | JPEG・PNG | サムネイルに動画へのリンク | vs が梱包。KPF にせず EPUB を出力する |

- 段の数は、S3 の完了の後（2026-11-16）に `EpubBuilder#prepare_entries` の呼び出しを数え直した値である。共通の 10 段は `mark_body`・`strip_inline_footnote_ids`・`rewrite_table_align`・`restore_plain_emoji`・`inject_heading_images`・`localize_showcase_images`・`shrink_side_by_side_figures`・`convert_code_blocks`・`decorate_footnotes`・`post_process_index_glossary`。Kindle の 17 段は `decorate_talk`・`transcode_webp_images`・`strip_webp_inline_styles`・`mark_body`（`vs-kindle`）・`restore_h3_markers`・`constrain_layout_images`・`compose_pictures`・`textify_simple_math`・`rasterize_display_math`・`convert_math_units`・`keep_cell_math_inline`・`align_code_cells`・`inject_code_line_numbers`・`decorate_admonitions`・`decorate_list_markers`・`layout_index_columns`・`replace_rotate_tables`。平らな CSS を書いて `link` を付け替える段（`bundle_flat_css_for_epub!`）は `css_form` の処理で、変換の数に入れない。
- 本全体の段の順は、今の順のままである。`AuthorPriority` は CSS を書き直すので、異体字の規則を CSS の末尾へ足す `VariantGlyphFonts` より前に置く。`InversionReport` は、書き直した後の CSS を見る。
- クリーン EPUB にも平らな CSS を渡す。Kobo と Google Play Books が `@layer` を解するかは確かめられていない（`v2-feasibility-notes.md` §6.2）が、層を外した CSS はどのリーダーでも同じに読まれるので、対応の有無を調べる必要も、著者に選ばせるキーも要らなくなる。層を外す仕組みは Kindle のために作るので、追加の実装は無い。
- 固定レイアウトの `kindle` の出力ファイルは `<名前>-kindle.epub` とする。KDP へはこの EPUB を出す（`v2-feasibility-notes.md` §4.1）。KDP が受け付けて正しく表示するかは未確認で、S9 の入口で確かめる（§9）。

### 4.3 `epub_builder.rb` の分割

`build/epub_builder.rb`（3,771 行・176 メソッド。S3 の完了の後・2026-11-16 に数え直した）を、`OutputTarget` の項目に沿って分ける。

```
lib/vivlio_starter/cli/build/
  output_target.rb                 型と登録表
  targets/pdf.rb print_pdf.rb epub.rb kindle.rb   各出力先の宣言
  transforms/
    context.rb                     段へ渡す文脈（出力先とワークスペース）と名前空間
    runner.rb                      変換の並びを HTML に当てる
    dom.rb                         段が共用する、要素の属性の小さな操作
    shared/*.rb                    両フレーバ共通の 10 段（1 段 1 ファイル）
    kindle/*.rb                    Kindle 専用の 17 段（1 段 1 ファイル）
    fixed/*.rb                     固定レイアウト用（S9 で足す）
  finalizers/
    book.rb                        本全体の段へ渡す「本」（ページの並びと平らな CSS の表）と名前空間
    author_priority.rb             custom.css の宣言を、平らな CSS でも PDF と同じに勝たせる（CSS と style 属性）
    variant_glyph_fonts.rb         異体字セレクタ付きの字を 1 字書体で出す（Kindle だけ）
    inversion_report.rb            層を外すと勝ち負けが変わる組の報告（--log=debug のときだけ）
  epub/
    workspace.rb                   消費者のディレクトリ・素材の複製（localize）・参照の切れた画像の回収
    stylesheets.rb                 平らな CSS を書き、HTML の link を付け替える（css_form）
    images.rb                      WebP への変換・著者の SVG の派生・ラスター化
    config.rb                      EPUB 用の entries.epub.js と vivliostyle.config.epub.js
    opf.rb                         content.opf と nav の書き換え（id・識別子・綴じの向き）
    kpf.rb                         KPF への変換と記録の要約
    fixed_package.rb               固定レイアウトの EPUB の梱包（S9 で足す）
```

**出力先の流れの順。** `EpubFlow` は、出力先の宣言から、次の順で流れを組む。

1. ワークスペースと素材（`epub/workspace.rb`・`epub/images.rb`）。
2. 平らな CSS を書いて `link` を付け替える（`css_form`。`epub/stylesheets.rb`）。
3. `transforms`（1 ページずつ）。
4. `finalizers`（本全体）。
5. `packager`。

2 が 3 の前にあるのは今と同じである。要素ごとの判定（`custom.css` を勝たせる・層を外すと変わる組の報告）は、Kindle の印（`vs-kindle`）と、EPUB 用に足す要素（合成画像の見出し・コードの行ブロックなど）が付いた後でなければ、Kindle の規則を見落とす（`css-layer-restructure-spec.md` §10.6 の「仕様と違えたこと」の 3）。判定が 3 の後であることは、4 に置くことで保証する。

変換の 1 段は、次の形の関数モジュールにする。

```ruby
module VivlioStarter::CLI::Build::Transforms::Kindle::TextifySimpleMath
  module_function

  # @param doc [Nokogiri::HTML5::Document] 1 ページ分の契約 HTML（破壊的に書き換えてよい）
  # @param ctx [Transforms::Context] 出力先・ワークスペース・書き換えているページ（traits は S5 で足す）
  def call(doc, ctx) = ...
end
```

文字列の置換でしか書けない段（HTML として不正な途中の形を通るもの）は、`call` の代わりに `rewrite(html, ctx)` を持ち、書き換えた HTML の文字列を返す。`runner.rb` は、文字列が変わったページだけ DOM を作り直す（§10.2）。

本全体の段（`finalizers`）の 1 段は、次の形にする。どれも `Css::Bundle` などを呼ぶ薄い段である。

```ruby
module VivlioStarter::CLI::Build::Finalizers::AuthorPriority
  module_function

  # @param book [Finalizers::Book] ページのパスの並びと、平らな CSS の表（href → Css::Bundle::Sheet）
  # @param ctx [Transforms::Context] 出力先・ワークスペース・traits
  # @return [Finalizers::Book] CSS を書き直したら、表を差し替えた book を返す
  def call(book, ctx) = ...
end
```

- `finalizers` は、ページを書き終えたファイルから読み、書き直したページだけを書く。第二段階でも、全部のページの `doc` を持ち回す形にはしない。「一度だけ読み、一度だけ書く」は `transforms` の決まりとし、`finalizers` の書き直しはその外に置く。書き直しが起きるのは `custom.css` が負ける本だけで、本書（`custom.css` が空）では 0 ページである。
- 名前は中身で付け、`_for_epub!`・`_for_kindle!` の接尾辞はやめる。どちらの出力先で走るかは、置いたディレクトリと出力先の宣言で分かる（今は名前から判別できない。`v2-inventory-report.md` §5）。
- 分割は二段階で行う。(1) メソッドをファイルへ移すだけで、呼び出しの順と中身は変えない。(2) `runner.rb` が 1 ページの HTML を一度だけ読み、変換を順に当て、一度だけ書く形にする。(1) の完了の条件は「EPUB と Kindle の出力が分割の前とバイト単位で同じ」、(2) は「HTML の差が属性の順と空白だけ」とする（§8 の S4）。
- 文字列の置換で書かれている段は、(1) ではそのまま移し、(2) で `doc` を受ける形に直す。直せない段（HTML として不正な途中の形を扱うもの）があれば、`runner.rb` に「ファイルを直接書き換える段」の種別を残す。

### 4.4 Kindle 向けの劣化を二つにまとめる

1.x の四か所（`v2-inventory-report.md` §6）は、次の二つに収める。CSS の側は S3 で済み、残りは S4 で行う（2026-11-16 に、S3 の結果に合わせて表を書き直した）。

| 1.x の場所 | 行き先 | 状態 |
| :--- | :--- | :--- |
| 静的な CSS の `body.vs-kindle`（10 ファイル・124 か所） | `stylesheets/targets/` に集め、出力先の束にだけ入れる。本文のページの規則は `kindle.css`（EPUB と共通の規則は `epub.css`）、そのページの種類だけの規則は `kindle-preface.css`・`kindle-index.css`・`kindle-glossary.css`・`kindle-colophon.css`（`css-layer-restructure-spec.md` §5） | S3-2 で済み（82 規則） |
| `BookSettingsCss` の `kindle_accent_rules`・`kindle_custom_color_rules`・`h4_marker_kindle_rule` | 消した。CSS の生成（`Css::LiteralResolver`）が、どの層の `var()`・`calc()`・`color-mix()`・`:is()` も値に解く。途中で置いた `book-settings-kindle.css` も無い（同 §4.4） | S3-3a・S3-4 で済み |
| PDF 向けの本文の字の大きさ・行送り・書体（1.x では、KFX が `var()` の宣言を捨てることで Kindle に届かなかった） | `stylesheets/targets/kindle-tokens.css` が、`body.vs-kindle` で端末任せの値（`1em`・`normal`・総称の書体の名前）に置き換える（同 §4.4） | S3-4 で済み |
| `sanitize_epub_css!`（組み上がった EPUB の CSS の書き換え） | 消した。CSS の生成（`Css::TargetFilter`）が、EPUB に入れる前の CSS から `@page` の余白の箱と WebP の `url()` を落とす | S3-1 で済み |
| `EpubBuilder` の Kindle 専用の 17 段 | `build/transforms/kindle/` と `build/targets/kindle.rb` の並び | S4 |
| `EpubBuilder` の本全体の段（`prioritize_author_css_for_epub!`・`apply_variant_glyph_fonts_for_kindle!`・`report_flat_css_inversions!`。S3 で入った） | `build/finalizers/` と、出力先の宣言の `finalizers` の並び（§4.1） | S4 |

結果として、「Kindle で何を変えているか」は `build/targets/kindle.rb`（DOM の変換の並び・本全体の段の並び・素材の方針）と、`targets/kindle-tokens.css` を含む `stylesheets/targets/kindle*.css`（端末任せにする値と、構造の劣化の規則）の二つを読めば分かる。色や寸法のリテラル化は、一般の仕組み（CSS の生成）になり、Kindle 専用の記述ではなくなった。

Kindle の囲みの 3 点の型（`.claude/CLAUDE.md` の「Kindle degradation convention」）は、(1) ラベルの登録（`ADMONITION_LABELS`）と (3) テストは残り、(2) の「リテラルの色で `body.vs-kindle` の規則を書く」は「`targets/kindle.css` に構造の違いだけを書く。色は変数のままでよい」に変わった（S3 の完了のときに、`.claude/CLAUDE.md` と `notation-implementation-guide.md` §3 を直した）。

### 4.5 出力先で形が変わる素材（動画）

契約 HTML は動画を次の形で持つ。

```html
<figure class="vs-video">
  <video src="videos/clip.mp4" poster="images/video/clip.jpg" controls data-vs-url="https://example.com/clip"></video>
  <figcaption>…</figcaption>
</figure>
```

| 出力先 | L4 の変換 |
| :--- | :--- |
| `epub` | `<video>` を残す。中に、再生できない読者向けの代わりの表示（ポスター画像と、`data-vs-url` があればリンク）を入れる |
| `pdf`・`kindle` | `<video>` をポスター画像に置き換え、`data-vs-url` へのリンクを張る |
| `print_pdf` | ポスター画像に置き換え、`data-vs-url` の QR コードを添える（QR の生成は既存の `QrTransformer` の仕組みを使う） |

- `pdf` と `print_pdf` で紙面が違うので、動画のある本では `print_pdf` を `pdf` から導出できない。`derive_print?` の条件に「契約 HTML に `figure.vs-video` が無い」を足し、ある場合は組み直す。
- `data-vs-url` が無い動画（配布先の URL を持たない）は、`pdf`・`kindle`・`print_pdf` ではポスター画像だけになる。`vs build` と `vs preflight` が 🟡 で知らせる（原稿の場所を指す）。
- EPUB の大きさが 100 MB（Kobo の上限。`v2-feasibility-notes.md` §5.2）を超えたら、`generate epub` の後で 🟡 を出す。上限は定数とする（著者が変える理由が無い）。
- ポスター画像を動画から切り出すか、著者が用意するかは、動く絵本の仕様で決める。切り出す場合は外部の道具が要るので、`notation-implementation-guide.md` §5 の型（生成資産・`GeneratedAssetCache`・doctor への登録）に載せる。

### 4.6 Web 出力

2.0 では作らない。理由は、四つの出力先を三つの本の種類で確かめるだけで確かめる面が 12 あり、ここに出力先を足すと公開が遅れるためである。

後から足すときは、`build/targets/web.rb` に宣言を一つ足し、`packager` に Web 出版物の梱包を足す。契約 HTML が出力先に依らない（§3.1）ので、L1〜L3 は触らずに済む。`output.targets` の値の検査（`PdfMerger.extract_targets`）は、登録表にある名前だけを通す形に直しておく。

---

## 5. 設定の持ち方

### 5.1 キーの増減

| キー | 状態 | 既定値 | 備考 |
| :--- | :--- | :--- | :--- |
| `book.type` | 新設 | `techbook` | §2.1 |
| `page.writing_mode` | 新設 | `horizontal` | 種類の既定値で `novel` は `vertical` |
| `page.layout` | 新設 | `reflowable` | 種類の既定値で `picture_book` は `fixed` |
| `theme.name` | 新設 | `standard` | 種類の既定値で変わる。`theme-contract-spec.md` §4 |
| `lint.ruleset` | 新設 | `technical` | §6 |
| `notation.web_novel` | 新設 | `false` | 小説投稿サイトの記法を読む（§7.1） |
| `metrics.use` | 値を追加 | `standard` | `none` を足す（分量の判定をしない）。§6 |
| `output.epub.layout`・`output.kindle.layout` | 廃止 | | 案内文: 「レイアウトは本全体で一つです。page.layout に書いてください」。値は `reflowable` しか有効でなかったので、`moved_to:` は付けない |

- 足すキーはどれも `config-key-criteria-guidelines.md` の 5 軸に当たらない（本の性質であり、著者ごとに答えが違う）。
- 縦書きの小説・絵本の個別の仕様でキーが増える（判型の行数と字数、挿絵の扱いなど）。そのときも同じ指針で問う。

### 5.2 `theme:` 節

`theme:` 節は「テーマの名前」と「そのテーマが宣言したオプション」を持つ。

```yaml
theme:
  name: standard        # 省略すると種類の既定のテーマ
  color: green          # 以下は standard テーマのオプション（今のキーと同じ名前）
  style: image
  frontispiece:
    image: sakura
```

- 今の `theme:` 節のキー（`color`・`preface_color`・`appendix_color`・`style`・`lead_size`・`frontispiece.*`・`ornament.*`・`markers.*`）は、そのまま `standard` テーマのオプションになる。1.x の `book.yml` の `theme:` 節は書き換えずに通る。
- オプションの宣言と既定値はテーマの `theme.yml` が持つ（`theme-contract-spec.md` §3.3）。`ConfigKeys::KEYS` から `theme.*`（`name` を除く）を外し、`Common.load_config` が、選ばれたテーマの宣言を既定値の表に足す。
- **読む入口は 1 つにし、読む側の形は変えない（`v2-s6-consultation.md` §4.5 の 1）。** テーマの側（`Theme::Manifest` と機能の宣言）が、自分のオプションを `ConfigKeys::Spec` の形（`{ %i[theme color] => Spec[default: 'green'] }`）で返す。`ConfigKeys` に、`KEYS` とその表を重ねて返す入口を 1 つ置き（名前は実装で決める）、`default_schema` はこの入口を通る。読む側を分ける案は採らない。分けると、既定値の重ね合わせと `vs config` の案内が `theme:` 節だけ別の経路になり、`config-defaults-design-spec.md` が無くした「宣言が複数箇所にある」状態に戻る。

  | 仕組み | S6 の後 |
  | :--- | :--- |
  | `Common.load_config` | 重ねた表を読む（§5.3 の 3）。`theme.name` を生の YAML から先に取り出し、テーマを読んでから全体を重ねる |
  | `config_guide.rb` | 重ねた表を読む。今の形のまま |
  | `upgrade.rb`・`scaffold_updates.rb`・`retired_key_remover.rb` | `ConfigKeys::RETIRED` を今のまま読む。`theme.yml` に廃止キーの宣言は作らない。同梱のテーマのオプションを廃止するときは、今と同じく `RETIRED` に書く |
  | `ThemeValidator` | 宣言（`type`・`values`・`min`・`max`）からの検査に置き換える。扉絵・節絵の画像があるかの検査は、機能のコードに残す。`standard` での 🟡 の文面は、前後で同じにする |
  | `config_keys_test.rb` | 重ねた表と照合する。`theme:` 節は、(a) 雛形の `book.yml` のキーの組が、`name` ＋ `standard` の `options:` ＋ `standard` が使う機能のオプションと一致する、(b) 書かれた値が既定値と一致する、の二つを検査する。種類ごとの雛形（S8）では、その種類の既定のテーマの宣言と照合する |
  | `book_yml_consumption_test.rb` | `theme.*` のキーは、「`theme.yml` の `options:` に `token:` か `body_class:` つきで宣言されている」か「機能のコード（`theme/features/`）で読まれている」ことを検査する。`token:` で渡るキーは、`lib/` に名前が出なくなるためである |

- 雛形の `book.yml` の `theme:` 節について、宣言と既定値の正典は `themes/standard/theme.yml` と機能の宣言である。著者が読む説明（コメント）と、キーを載せる場所は、今と同じく直下の `config/book.yml` である。
- 選ばれたテーマが宣言していないキーが `theme:` 節にあれば、🟡 で知らせる（テーマを替えた後に前のテーマのオプションが残った場合。「このテーマには無い設定です」と、そのテーマのオプションの一覧を示す）。文面と、廃止キー・ほかの節との関係は `theme-contract-spec.md` §3.3。

### 5.3 値の解決の順

`Common.load_config` の解決を次の順にする。後のものが前のものを上書きする。

1. `ConfigKeys` の既定値
2. 種類の既定値（`BookProfile::PROFILES[book.type]`）
3. テーマのオプションの既定値（`theme.*` だけ）。選ばれたテーマの `tokens:` に、土台のオプションの `token:` と同じ名前があれば、その値を既定値にする（配色のテーマ。`theme-contract-spec.md` §3.2）
4. 判型のプリセット（今の `apply_page_preset`）
5. `book.yml` に書いた値
6. 巻ごとの上書き（今の分冊の仕組み）

`book.type` と `theme.name` は 2 と 3 を決めるために先に読む必要がある。`load_config` は、生の YAML からこの二つだけを先に取り出し（無ければ既定値）、その後で全体を重ねる。

`Common::CONFIG` は今と同じく凍結した `Data` で、モジュールの読み込み時に作る。形と引き方（`CONFIG.book.main_title`・`dig`）は変えない。

### 5.4 分冊との関係

`book.type`・`page.writing_mode`・`page.layout`・`theme.name` は本全体で一つとし、巻ごとには変えない。巻ごとの上書きの対象（今は `book:` 節の書誌と表紙）にこれらを足さない。巻ごとに組方向やテーマが違う本は、別の本として作る。`catalog.yml` の形は変えない。

### 5.5 `book.yml` を機能別のファイルに分けるか

分けない。

- 種類ごとの雛形（§2.6）で、その種類に要らない節が `book.yml` から消える。小説の `book.yml` は、今の 471 行のうち `index_glossary`・`index`・`glossary`・`metrics`・`lint` の大半・`pdf_read`・`theme` の扉絵と節絵を持たないので、およそ半分になる。分ける動機（長い）の大部分がこれで解ける。
- 分けると、1.x の本の移行に「ファイルを分ける」作業が加わる。`vs upgrade` の書き換え・廃止キーの案内・`authored_keys` の記録を、複数のファイルに対応させる必要もある。
- `PLANNED.md` の「`book.yml` を機能別のファイルへ切り出すか」の項目は、2.0 の後に見直す項目として残す。

---

## 6. 技術書に寄った機能の切り替え

| 機能 | 切り替えるキー | `BuildPlan.features` の窓口 | `techbook` | `novel` | `picture_book` | 無効のときに止まるもの |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| 索引・用語集 | `index_glossary.enabled`（既存） | `index` | 有効 | 無効 | 無効 | `index scan and build`・`backlink dedup`・EPUB の索引の後処理・索引と用語集のページ |
| 見出しの番号 | `page.heading_numbering`（既存） | （CSS とテーマが読む） | 章と節 | 振らない | 振らない | |
| 文章の lint の規則の組 | `lint.ruleset`（新） | （`vs lint` が読む） | `technical` | `novel` | `minimal` | |
| 分量の判定 | `metrics.use`（既存・`none` を足す） | （`vs metrics` が読む） | `standard` | `none` | `none` | 分量の判定の行。字数と漢字の水準の表示は残る |
| 小説投稿サイトの記法 | `notation.web_novel`（新） | `web_novel` | 無効 | 有効 | 無効 | 前処理の一段 |
| Type 3 対策 | `output.pdf.techbook`（既存） | `techbook_post_process` | 有効 | 有効 | 有効 | `techbook post-process` |
| 扉絵・節絵 | テーマの宣言（`theme-contract-spec.md` §3.4） | （テーマから決まる） | `standard` テーマが使う | 使わない | 使わない | `prepare theme images`・h2 の飾り・EPUB の見出しの画像・`check chapter leads` |
| コード・数式・相互参照・図 | キーなし | | 記法を使えば働く | 同じ | 固定レイアウトでは使えない | |
| 免責・商標 | `legal`（既存） | | 変えない | 変えない | 変えない | |

- コードや数式にキーを設けないのは、記法を使わなければ何も起きず、切る理由が無いためである（小説にコードブロックを入れる著者を妨げる理由も無い）。
- `lint.ruleset` は、規則の id の組に名前を付けたものである。`technical` は今の一組、`novel` は表記の共通の規則に小説の 4 規則（「……」「――」の二つ重ね・「！」「？」の後の全角空白・閉じ括弧の前の句点・段落の頭の字下げ）を足した組、`minimal` は誤字と表記の揺れだけの組とする。組の中身は `lint/` の中の 1 枚の表（`Lint::RULESETS`）に置く。`lint.disabled_rules`（既存）は、選んだ組からさらに外す指定として今と同じに働く。規則の組を切り替える以外の `lint/` の構造は変えない。
- `metrics.use: none` は、章と節の分量の基準（技術書で較正した値。`chapter-volume-calibration-data.md`）を小説と絵本に当てないためのものである。小説の分量の基準を作るかは 2.0 の後で決める。
- `output.pdf.techbook` は名前に「技術書」を含むが、中身は PDF の書体の対策で、どの種類の本にも要る。名前は変えない（§9 の論点 3）。

---

## 7. 拡張点

### 7.1 記法の型

`notation-implementation-guide.md` §1 の三つの型（A: CSS 型・B: 前処理変換型・C: 生成資産型）に、二つを足す。S8 の着手時に同ガイドへ節を足す。

- **D: 行内の属性の型** — `[文字]{.class}` を `<span class="class">文字</span>` にする（Pandoc の bracketed span と同じ書き方）。`PLANNED.md` の「文字の色を変えるインライン記法」と同じ仕組みで、前処理の一段（`transform_inline_spans!`）が受ける。使えるクラスは、CSS にあるクラスだけとし、それ以外は 🟡（`ContainerClassCheck` と同じ判定を行内にも当てる）。コードの中は置き換えない（`Masking`）。索引の `[用語]` との区別は `]` の直後の `{` で行い、`IndexMarkup` に除外を足す。
- **E: 出力先で形が変わる素材の型** — 契約 HTML に最も豊かな形を出し、出力先の変換（L4）が置き換える（§4.5）。`img[data-vs-raster]` はこの型の最初の例である。新しい素材を足すときは、(1) 契約 HTML の形、(2) 出力先ごとの置き換えの表、(3) 置き換えの変換（`build/transforms/common/` か各出力先）を決める。

2.0 に含める 5 件と、絵本・動画の記法の割り当て:

| 機能 | 型 | 入れる場所 | 決定 |
| :--- | :--- | :--- | :--- |
| 傍点 | D | `[文字]{.sesame}` → `span.sesame` | クラス名は公式テーマと同じ `sesame` にする（`theme-contract-spec.md` §2.5） |
| 縦中横（手で指定） | D | `[12]{.tcy}` → `span.tcy` | 同じく公式テーマと同じ `tcy` |
| 縦中横（自動） | L3 の後処理の一段 | 条件は `traits.vertical?`。本文の中の半角の数字 1〜2 桁と `!?`・`!!` を `span.tcy` で包む。コード・数式・ルビの読み・`span.tcy` の中は対象にしない | 桁数の上限と対象の字は小説の仕様で確定する |
| 小説投稿サイトの記法（`\|漢字《かんじ》`・`《《…》》`） | B | 前処理の一段 `transform_web_novel_marks!`。条件は `features.web_novel`。ルビは vs の `{漢字\|かんじ}` へ、傍点は `[…]{.sesame}` へ置き換える | **前処理で受ける。`vs import` にはしない。** 投稿サイトと本の両方へ同じ原稿を出す著者が対象で、原稿を書き換えると二つの原稿を持つことになるため |
| 小説の表記の lint | （記法ではない） | `lint.ruleset: novel`（§6） | |
| `vs furigana` | （コマンド） | 原稿を書き換えるコマンド。ビルドの段ではない | 対象の水準は `furigana-level-spec.md`。本書の枠では、ルビの記法が今の `{漢字\|よみ}` のままであることだけを前提にする |
| 背表紙とくるみ表紙 | （出力） | `build cover spread` の段（§3.3） | 背幅はページ数と紙の厚さから求める。紙の厚さは著者が答えを持つ値なので `book.yml` のキーにする。個別の仕様で決める |
| 絵本のページの区切り | （原稿の構造） | L1 の固定レイアウトの読み込み（§3.5） | 記法の型には入れない |
| 動画 | E ＋ C | `figure.vs-video`（§4.5） | |

### 7.2 PDF プロバイダの切り替えから得た決まり

`cli/pdf/provider.rb` は今ある唯一の差し替えの仕組みである。うまく行った点と困った点から、テーマと今後の拡張に次の決まりを置く。

| 先例で起きたこと | 決まり |
| :--- | :--- |
| 境界が 3 つの呼び出しに絞られていて、差し替えの影響が読めた（良かった点） | 拡張の境界は、文書にした狭い契約にする。テーマの契約は、契約 HTML・公開する変数・`theme.yml` の三つだけとする |
| gem が入っているかどうかで挙動が変わる。著者は選んだ覚えが無い | **入っているだけでは効かない。** テーマも今後の拡張も、`book.yml` に名前を書いたときだけ効く |
| 開発機では拡張の側しか走らず、標準の側の不具合に気づきにくい（`rake test:standard` を別に用意した） | **標準のものも同じ経路で読む。** 標準のテーマ（`standard`）も、配られたテーマと同じ置き場・同じ読み込み・同じ検査を通す。特別扱いの経路を作らない |
| 修正を両方の実装に入れる必要があり、片方は別の gem の公開を待つ | **本の中に実体を置く。** テーマは本の `themes/` に複製して使う。ビルドは、そのマシンに何が入っているかに依らない |
| 拡張の側は別ライセンス（AGPL の HexaPDF）のコードを実行する | **テーマはコードを持たない。** テーマは CSS・画像・書体・YAML だけで、Ruby や JavaScript を実行しない。配られたテーマを入れてもコードは実行されない |

### 7.3 公開する範囲

| 拡張点 | 2.0 での扱い | 理由 |
| :--- | :--- | :--- |
| テーマ（契約 HTML・公開する変数・`theme.yml`） | **公開する。** 契約に版を付け、後方互換を保つ | ユーザーの方針（他の人へ配れる形） |
| `book.yml` のキー | 公開（今と同じ。廃止は `config-retirement-guidelines.md` の型） | |
| 出力先（`OutputTarget`） | 内部の登録表。外から足せない | 梱包と検査を伴い、契約にするには早い |
| 変換（`Transforms`）・前処理の段 | 内部 | 順序の制約が多く、外から挿す位置を保証できない |
| 記法 | 内部。足すときは `notation-implementation-guide.md` に沿って本体に入れる | 同上 |
| lint の規則の組 | 内部の表。著者は名前で選ぶだけ | |
| 種類（`BookProfile`） | 内部の表。著者は名前で選ぶだけ | 種類を外から足す要望が出たら、表を YAML に出す形で応じられる |

内部の拡張点も、登録表（1 枚の表に 1 行足す）の形にそろえる。後で公開するときに、表の形がそのまま契約の下書きになる。

---

## 8. 段階ごとの完了の条件と確かめ方

段階の番号と順序は `v2-migration-plan.md` §2 による。ここには、本書の決定に関わる段階の条件だけを書く。どの段階も `rake test` と `bundle exec rubocop` が通ることを含む。

### S4 出力先の宣言と `epub_builder.rb` の分割

- 作るもの: §4.1 の `OutputTarget`（`finalizers` を含む）、§4.3 のファイル構成、`EpubFlow` を出力先の宣言から §4.3 の順で流れを組む形にする。
- 完了の条件:
  1. `build/epub_builder.rb` が無くなり、どのファイルも 600 行を超えない。
  2. 変換の段の名前に `_for_epub!`・`_for_kindle!` が残っていない。
  3. 本書の写しを四つの出力先で組み、その時点の基準（r2。`v2-migration-plan.md` §3.2）と比べて、PDF は全ページの画素が一致、EPUB と Kindle 用の EPUB は中の HTML・CSS・OPF が §4.3 の (1) ではバイト単位で一致、(2) では属性の順と空白を除いて一致する。「属性の順」は属性どうしの順のことで、`style` 属性の値は中の宣言の順まで一致を求める。
     - 本書（B1）は `custom.css` が空で、`finalizers` が何も書き直さない。そこで、`custom.css` に 2 行（`h2 { margin-block-start: 2em; }` と `table { inline-size: 80%; }`）を足した写し（`css-layer-restructure-spec.md` §8 の S3-3 の (f) の写し）も、分割の前後で組み、EPUB と Kindle 用の EPUB を同じ基準で比べる。分割の前後を同じ入力で比べるので、`style` 属性の `!important` は両側に同じに出る。
  4. `rake test:standard` が通る。
- 確かめ方: `v2-migration-plan.md` §3 の比較（PDF の画素・EPUB の中身の差分）。Kindle は KPF の変換の記録（Enhanced Typesetting が Supported・エラー 0）も見る。

### S5 種類・軸・`BuildPlan`

- 作るもの: §2.2〜§2.5、§3.2〜§3.4、§5.1（`theme.name` を除く）、§5.3 の 1・2・4〜6、§6 の `lint.ruleset` と `metrics.use: none`。
- 完了の条件:
  1. `book.type` の無い本書が、S0 の基準と同じ出力になる（四つの出力先）。
  2. `book_profile_test.rb`・`book_type_usage_test.rb` が通る。
  3. `full_mode_step_table` の条件の列が `plan` だけを読み、ハンドラの中で設定を見て戻る段が無い。
  4. `page.writing_mode: vertical` を書いた最小の本（章 1 つ）で、`vivliostyle.config` の `readingProgression` が `rtl` になり、入稿用 PDF の隠しノンブルが奇数ページの右端（ノド）に出る。本文の縦組みはこの段階では求めない。
  5. `index_glossary.enabled: false` の本で、`index scan and build` と `backlink dedup` が段の一覧に出ない。
- 確かめ方: 1 は S0 との比較。4 は `pdftotext -bbox` でノンブルの座標を読む。5 は `--log=debug` の段の一覧。

#### S5 の小段階と、段階の中で決めること（2026-11-16）

S5 は五つの小段階に分ける。どの小段階も、完了のコミットは「`book.type` の無い本書が、その時点の基準（r2）と同じ出力になる」ものだけにする（`v2-migration-plan.md` §4.1）。小段階ごとの確かめは `rake test` と下の表の「確かめ」で行い、四つの出力先を組んで r2 と比べるのは、S5-4 の後と S5 の最後の 2 回とする。

| 小段階 | 作るもの | 確かめ |
| :--- | :--- | :--- |
| S5-1 設定のキーと解決の順 | §5.1 のキー（`theme.name` を除く）を `ConfigKeys::KEYS` に足す。`BookProfile`（§2.2）。`Common.load_config` の解決の順（§5.3 の 1・2・4〜6）。`output.epub.layout`・`output.kindle.layout` の廃止の案内。`book_profile_test.rb`・`book_type_usage_test.rb` | 本書の `Common::CONFIG` を前後で書き出して比べ、足したキーのほかに差が無い |
| S5-2 `BookTraits` と、横書き・左綴じの前提 | `BookTraits`・`Common.traits`（§2.4）。`vivliostyle_config_writer.rb` の `readingProgression` と `nombre_stamper.rb` の左右。`Guards::TraitCombinationCheck`（§2.5） | 完了の条件の 4（`page.writing_mode: vertical` の最小の本） |
| S5-3 `BuildPlan` と段の表 | `build/plan.rb`（§3.2）。`full_mode_step_table` の条件の列を `plan` だけから決める。ハンドラの中で設定を見て戻る段を、条件の列へ移す（§3.3 の表のうち、今ある段の行） | 完了の条件の 3・5。本書の `--log=debug` の段の一覧が前後で同じ |
| S5-4 前処理・後処理の並びを表にする | `MarkdownPreprocessor` の `STEPS`（§3.4）と、後処理の同じ形の表 | 本書の契約 HTML（`.cache/vs/build/html/` の全部の HTML）が、前後でバイト単位で同じ。その後、四つの出力先を組んで r2 と比べる |
| S5-5 `lint.ruleset` と `metrics.use: none` | `Lint::RULESETS`（§6）と、`vs metrics` の `none` | 本書の `vs lint` の全部の指摘を前後で突き合わせ、差が無い（`technical` は今の一組）。`metrics.use: none` の本で、分量の判定の行だけが出ない |

S5 の範囲に入れないもの: `theme.name` とテーマの宣言（S6）、`vs new --type` と種類ごとの雛形（§2.6。S8）、OPF の `page-progression-direction` と `@page` の左右（S8）、固定レイアウトの経路（§3.5。S9）、小説投稿サイトの記法の段と小説の lint の 4 規則（S8）。

仕様に書かれていないので、S5 では次のように決める。

1. **`BookProfile::PROFILES` には、S5 の時点で `ConfigKeys::KEYS` にあるキーだけを書く。** §2.2 の表の `theme.name`（S6）と、まだ無い判型のプリセット（`page.use: a6_standard`。S8）は、その段階で足す。`book_profile_test.rb` の (1)「表のキーがすべて `ConfigKeys::KEYS` にある」を、最初から通る検査にするためである。(2) の雛形との照合は、種類ごとの雛形ができる S8 で足す。
2. **`page.layout: fixed` は、S9 までは 🔴 で止める。** 固定レイアウトの経路が無いまま組むと、リフローの段がそのまま走って壊れた本ができる。`TraitCombinationCheck` に「固定レイアウトはまだ組めません」の行を置き、S9 で外す。`book.type: picture_book` も、この行で止まる。
3. **`page.writing_mode: vertical` は止めない。** S5 で変わるのは綴じの向き（`readingProgression`）と隠しノンブルの左右だけで、本文は横組みのまま組まれる（完了の条件の 4）。本文の縦組みは S8 である。S6-3 からは、`standard` の `supports.writing_mode: [horizontal]` により §2.5 の `supports:` の検査が 🔴 で止めるので、S8 まで縦書きの本は組めない（`v2-s6-consultation.md` §4.6）。完了の条件の 4 のテストは、`supports.writing_mode: [horizontal, vertical]` を書いた材料のテーマで組む。
4. **`lint.ruleset` の `novel` は、S5 では `minimal` と同じ中身で置く。** 小説の 4 規則は S8 で足す。名前だけ先に置くのは、`BookProfile` の `novel` の行が指す値を、S5 の時点で有効な値にするためである。
5. **`notation.web_novel` は、キーと `BuildPlan.features.web_novel` だけを作る。** 読む段は S8 で足す。S5 の間は、`true` にしても何も変わらない。
6. **`Guards::TraitCombinationCheck` のうち、テーマの `supports:` の行は S6 で足す。** S5 で置くのは、`page.layout: fixed` と `index_glossary.enabled: true` の 🟡 と、上の 2 の 🔴 である（2 が先に当たるので、🟡 が出るのは S9 からになる）。

### S8 縦書きの小説（本書に関わる部分）

- 作るもの: §2.4 の表の残り（OPF・`@page`）、§7.1 の D 型・縦中横・投稿サイトの記法、`scaffolds/novel/`、`lint.ruleset: novel` の 4 規則。
- 完了の条件: `scaffolds/novel/` の本が四つの出力先で組め、Kindle が KPF になる（Enhanced Typesetting が Supported）。紙面の条件は小説の仕様に書く。

### S9・S10 絵本と動画（本書に関わる部分）

- 作るもの: §3.5 の経路、§4.2 の固定レイアウトの二行、§4.5。
- 完了の条件: `scaffolds/picture_book/` の本が四つの出力先で組め、EPUB が EPUBCheck でエラー・警告とも 0。動画のある本で、`pdf`・`print_pdf`・`epub`・`kindle` の動画の表示が §4.5 の表のとおりになる。

---

## 9. 論点（未決）

| # | 論点 | 答えが要る時点 | 設計での扱い |
| :--- | :--- | :--- | :--- |
| 1 | KDP が、vs の作る固定レイアウトの EPUB を受け付けて正しく表示するか | S9-0（S8 の間に行える） | KDP が固定レイアウトの本を EPUB で受け付けることは確認済み（`v2-feasibility-notes.md` §4.1）。vs の作る EPUB での表示は S9 で確かめる。S9 の最初に、最小の絵本の EPUB を作り、ユーザーが KDP のプレビューで確かめる。通らない場合は、絵本の `kindle` を 2.0 の対象から外すか、Kindle Create で手で作る手順を案内するかを、ユーザーが決める。§4.2 の表は「通る」を前提に書いた。**2026-11-17:** S9-0 で、実体の文字の EPUB（A）とページの画像の EPUB（B）の二つを手で作り、ユーザーが確かめる（`v2-s9-picture-book-consultation.md` §4.3）。どちらも通らない場合は `v2-migration-plan.md` §4.4 の「い」。開いたまま |
| 2 | 小説と絵本の判型のプリセット・既定のテーマの名前 | 決定済み（2026-11-17） | 小説は `v2-s8-novel-consultation.md` §4.5・§4.6、絵本は `v2-s9-picture-book-consultation.md` §4.6・§4.9。プリセットの値は、ユーザーが紙面を見て了承する（S8-5・S9-6）。§2.2 の表は、それぞれの仕様書を書いたときに直す |
| 3 | `output.pdf.techbook` の名前を変えるか | 決定済み（2026-11-14） | 変えない。働きは種類に依らず同じで、ほかの設定との衝突も無い |
| 4 | 絵本の原稿の形（1 ファイルに複数ページか・1 ファイル 1 ページか）と、ページの中の文字の置き方の記法 | 決定済み（2026-11-17） | 1 ファイルに複数ページ。ページは `@page`・`@spread`、ページの中の文字は `:::{.text}` の箱（`v2-s9-picture-book-consultation.md` §4.4）。§3.5 は L1 が「ページの並び」を返すことだけを決めた |
| 5 | 小説の分量の基準を `vs metrics` に持つか | 2.0 の後 | `metrics.use: none` で判定を外す |

## 10. 実装記録

### 10.1 S4 の第一段階: メソッドをファイルへ移す（2026-11-16）

§4.3 の (1)。`build/epub_builder.rb`（3,771 行・176 メソッド・定数 55 個）を無くし、§4.3 のファイルへ移した。メソッドの中身と呼び出しの順は変えていない。

#### 作ったもの

| ファイル | 中身 |
| :--- | :--- |
| `build/output_target.rb` | `OutputTarget`（§4.1 の 9 項目）・`OutputTarget::Assets`（画像の形式・SVG を同梱できるか）・登録表（`register`・`for`） |
| `build/targets/pdf.rb`・`print_pdf.rb`・`epub.rb`・`kindle.rb` | 四つの出力先の宣言。1.x の `generate_epub_entries!` にあった「なぜこの順か」の注は、宣言の並びの各行へ移した |
| `build/transforms/context.rb`・`runner.rb`・`dom.rb` | `Transforms::Context`（出力先とワークスペース）・`Transforms::Runner.apply!`・`Transforms::Dom`（`add_class`・`add_inline_style`・`mark_body!`） |
| `build/transforms/shared/*.rb`（10 本）・`kindle/*.rb`（17 本） | 変換の段。1 段 1 モジュールで、入口は `call(html_files, ctx)`。その段だけが使う補助と定数も同じファイルに置いた |
| `build/finalizers/book.rb`・`author_priority.rb`・`variant_glyph_fonts.rb`・`inversion_report.rb` | 本全体の段。入口は `call(book, ctx)` で、`Finalizers::Book`（ページの並びと平らな CSS の表）を受けて返す |
| `build/epub/workspace.rb`・`stylesheets.rb`・`images.rb`・`config.rb`・`opf.rb`・`kpf.rb` | ワークスペースと素材・平らな CSS・画像の変換・entries と config・OPF・KPF |

- `EpubFlow` は、出力先の宣言（`OutputTarget.for(:epub)`・`for(:kindle)`）を受けて流れを組む。HTML の書き換え（平らな CSS → `transforms` → `finalizers` → entries）は `EpubFlow.prepare_pages!(target, entries)` にまとめた（1.x の `generate_epub_entries!`）。
- いちばん大きいファイルは `epub/workspace.rb` の 389 行で、どのファイルも 600 行を超えない。`_for_epub!`・`_for_kindle!` の付いた名前は `lib/` に残っていない（S4 の完了の条件の 1・2）。
- 移すのは使い捨てのスクリプトで機械的に行った。メソッドと定数を 231 個のかたまりに分け、参照の表を作り、割り当て表のとおりにファイルへ書き出す。別のモジュールへ移ったメソッド・定数への参照には、モジュールの名前を前に付けた（`add_class(…)` → `Transforms::Dom.add_class(…)`）。字下げは変えていないので、差分はこの書き換えと入口の `def` の行だけである。

#### 仕様と違えたこと

1. **両方で走る段の名前空間は `Transforms::Shared`（`transforms/shared/`）にした。** §4.3 は `common/` としていた。`Transforms::Common` を作ると、`Build::Transforms` の下で書いた `Common.log_info` が `CLI::Common` でなく `Transforms::Common` を指す。ログと設定の窓口（`Common`）は、ほぼ全部の段が使う。
2. **流れの順は今のままで、§4.3 の「出力先の流れの順」の 1 のうち素材の段は、変換の後に走る。** ワークスペースへ HTML を置く段（`stage_consumer_htmls!`）だけが最初で、素材の複製（`localize_assets!`）・著者の SVG の派生・WebP への変換・参照の切れた画像の回収は、変換と本全体の段の後である。回収は差し替えを全部終えた後でなければならず、派生と WebP への変換は複製の後でなければならない（`EpubFlow#build_target` の注）。第一段階は順を変えない決まりなので、動かしていない。
3. **`MarkBody`（`vs-epub`）と平らな CSS の段の順だけ、入れ替えた。** 1.x は `mark_body_for_epub!` → `bundle_flat_css_for_epub!` の順だった。§4.3 の順（平らな CSS が 2、変換が 3）に合わせて、平らな CSS を先にした。平らな CSS の段は `link` の `href` を文字列の置換で付け替えるだけで、body のクラスを見ない。出力はバイト単位で同じだった（下の「確かめた結果」）。
4. **`body_classes` は、変換の段（`Shared::MarkBody`・`Kindle::MarkBody`）が付けるクラスを宣言に写したものにした。** `vs-kindle` を付ける位置（`StripWebpInlineStyles` の後）を変えないためである。宣言と段の食い違いは `output_target_test.rb` が確かめる。
5. **入稿用 PDF の `assets` は「そのまま」にした。** §4.2 は「CMYK へ変換」としていたが、本文の画像の CMYK への変換は実装されていない（`CmykConverter` を呼ぶのは表紙だけ）。宣言は今の振る舞いを書き、§4.2 の表を直した。
6. **`OutputTarget.for` は `traits` を受けない。** §4.1 は `OutputTarget.for(id, traits)` としている。`BookTraits` は S5 で作るので、S5 で引数を足す。
7. **`entries.epub.js` を書くメソッドは `epub/config.rb` に置いた。** §4.3 の一覧に entries の置き場は無い。`vivliostyle.config.epub.js` が読むファイルなので、config と同じモジュール（`Epub::Config`）にした。`excluded_basename?` だけは、回収（`Epub::Workspace`）も使うので `Epub::Workspace` にある（`Epub::Config` → `Epub::Workspace` の一方向にするため）。
8. **`PostProcessIndexGlossary` は、ほかのページも読む。** 索引と用語集のページを書き換えるときに、全部のページの id と章の題を読む。「変換は 1 ページだけを見る」（§4.1）の例外で、扱いは第二段階で決める。

#### 確かめた結果

比べた結果は、基準のディレクトリの `r2/check/s4-1/`。

| 確かめ | 結果 |
| :--- | :--- |
| 本書（B1）を四つの出力先で組み、基準 r2 と比べる | 閲覧用 PDF 284 ページ・入稿用 PDF 282 ページとも、違うページ 0。EPUB（339 ファイル）・Kindle 用 EPUB（261 ファイル）とも違い 0 件。展開した HTML・CSS・OPF（EPUB 46 件・Kindle 45 件）はバイト単位で同じ（OPF の更新の日時と、写しごとに変わる画像の名前を除く） |
| Kindle の変換 | Enhanced Typesetting: Supported・Success・エラー 0・品質の問題 0。中間生成物は 36 件 |
| `custom.css` に 2 行を足した写し（`r2/src/custom-f/`）を、分割の前（`56570316`）と後のコードで組む | EPUB・Kindle 用 EPUB とも違い 0 件で、HTML・CSS・OPF はバイト単位で同じ。平らな CSS に `!important` が付いており、`AuthorPriority` が書き直す本での比べになっている |
| `rake test` | 4,353 件・失敗 0（分割の前は 4,346 件。増えた 7 件は `output_target_test.rb`） |

- テストの呼び出しは、移った先の名前へ付け替えた（期待値は変えていない）。変換の段を 1 つだけ当てるテストは、`test_helper.rb` の `apply_transform(段, html_files)` を通す。`Transforms::Runner.apply!` を呼ぶ補助で、第二段階で段の引数が `doc` に変わっても、テストの書き方は変わらない。
- テストのファイルの名前（`epub_builder_test.rb`・`epub_builder_sanitize_test.rb`）は変えていない。
- `stylesheets/` の CSS のコメントに `EpubBuilder` の名前が 8 ファイルに残っている。平らな CSS に写る字を変えないために、第一段階では触っていない。

### 10.2 S4 の第二段階: 1 ページを一度読み、一度書く（2026-11-16）

§4.3 の (2)。`Transforms::Runner.apply!` が、全部のページを一度だけ読み、出力先の宣言の順に段を当て、一度だけ書く。段の入口は `call(doc, ctx)` になった。これで S4 は完了である。

#### 作ったもの

- **`Transforms::Runner.apply!`**: 全部のページを DOM にして持ち、段の順（外側）・ページの順（内側）で当て、最後に全部のページを書く。第一段階までは、27 段のそれぞれがページごとに読んで書いていた（Kindle では 1 ページにつき最大 27 回）。
- **`Transforms::Context`** に、書き換えているページ（`path`・`page_name`・`page_dir`）、本の全部のページの今の DOM（`pages`）、本で一度だけ求める値の置き場（`remember`）を足した。段は状態を持たないので、テーマの画像・外部コマンドの有無・変換した画像の表は `ctx.remember` に置く。
- **25 段を `call(doc, ctx)` にした。** 22 段は、ファイルを読む行と書く行を外しただけである。文字列の置換で書かれていた 3 段（`RestorePlainEmoji`・`RewriteTableAlign`・`StripWebpInlineStyles`）は、DOM の操作に書き直した。
- **2 段は `rewrite(html, ctx)` のまま残した。** `PostProcessIndexGlossary` は、`</dl>` を足してリストを分けるなど、HTML として不正な途中の形を通る。`TranscodeWebpImages` は、`src` の実体参照の字のまま変換の表を引く。`runner.rb` は、この種別の段に DOM を書き出した文字列を渡し、返った文字列が変わっていたページだけ DOM を作り直す。ファイルの読み書きは増えない。

#### 仕様と違えたこと

1. **段の順が外側で、ページの順が内側である。** §4.1 は「1 ページを一度読んで一度書く形にでき、後でページごとに並べて走らせる余地も残る」としていた。`PostProcessIndexGlossary` が、索引と用語集のリンク先の id を全部のページから照合するので、この段に来たときには、前の段が全部のページに当たり終えていなければならない。ページを並べて走らせるには、この段の前後で区切ることになる（今は並べていない）。
2. **`PostProcessIndexGlossary` は `ctx.pages` でほかのページを読む。** 「変換は 1 ページだけを見る」の例外で、書き換えるのは自分のページ（索引・用語集）だけである。`finalizers` へ移さなかったのは、Kindle の段（`LayoutIndexColumns` など）がこの段の書き換えた後の索引を組み替えるためで、順を変えると出力が変わる。
3. **`ConstrainLayoutImages` が組む表に `tbody` を足した。** 1.x は `<table><tr>` を DOM で作り、後の段がファイルを読み直すたびに、構文解析が `tbody` を補っていた。読み直しが無くなったので、段が `tbody` も作る。これを足さないと、書き出した HTML から `tbody` が消える（属性の順と空白のほかの差になる）。
4. **扉絵・節絵の注入は、DOM の写しに行い、全部できたときだけ差し替える。** 1.x は、途中で失敗したページのファイルを書かないことで、見出しを文字のまま残していた（simple 縮退）。DOM を持ち回す形では途中までの書き換えが残るので、写し（`doc.dup`）に注入して、成功したら根の要素を差し替える。
5. **`OutputTarget` の `transforms` の段の数は変わらない。** 文字列の段を別の並びに分けることはせず、段が `rewrite` を持つかで `runner.rb` が見分ける。

#### 確かめた結果

比べた結果は、基準のディレクトリの `r2/check/s4-2/`。

| 確かめ（S4 の完了の条件） | 結果 |
| :--- | :--- |
| 1. `build/epub_builder.rb` が無く、どのファイルも 600 行を超えない | いちばん大きいのは `epub/workspace.rb` の 389 行 |
| 2. 段の名前に `_for_epub!`・`_for_kindle!` が残っていない | Ruby のコードに 0 件（CSS のコメントの中に 3 か所。下の「残したもの」） |
| 3. 本書（B1）を四つの出力先で組み、基準 r2 と比べる | 閲覧用 PDF 284 ページ・入稿用 PDF 282 ページとも、違うページ 0。EPUB は HTML・CSS・OPF の 46 件のうち 44 件がバイト単位で同じ、2 件（`42-frontispiece`・`92-latex-cheatsheet`）が属性の順だけの違い。Kindle 用 EPUB は 45 件のうち 43 件が同じ、同じ 2 件が属性の順だけの違い。CSS と OPF は全部バイト単位で同じ。EPUBCheck は致命・エラー・警告 0 |
| 3. `custom.css` に 2 行を足した写しを、分割の前（`56570316`）のコードで組んだものと比べる | EPUB・Kindle 用 EPUB とも、B1 と同じ 2 件が属性の順だけの違いで、ほかはバイト単位で同じ |
| Kindle の変換 | Enhanced Typesetting: Supported・Success・エラー 0・品質の問題 0。中間生成物は 36 件・26,405 要素で、`computedstyle` の差 0・`style` の差 0 |
| 4. `rake test:standard` | 4,358 件・失敗 0 |
| `rake test` | 4,358 件・失敗 0（第一段階から 5 件増えた。`transforms_runner_test.rb`） |

- **属性の順が変わったのは、表のセルの `class` と `style` である。** `RewriteTableAlign` は、1.x では開始タグの文字列の先頭に `style` を足していた（`<td style="text-align:center" class="vs-inline-image">`）。DOM の操作では、後から足した属性が後ろに付く（`<td class="vs-inline-image" style="text-align:center">`）。`style` の値は同じである。本書では 2 ページ・21 個のセル。
- **実際の本の HTML を、ビルドをせずに比べる道具を使った。** `--no-clean` で組んだ写しの `.cache/vs/build/html/` から、`EpubFlow.prepare_pages!` だけを前後のコードで走らせて、EPUB と Kindle のワークスペースの HTML（36 ページずつ）を比べる（1 回 1 分）。`tbody` の差は、これで全部のビルドの前に見つけた。使い捨ての道具で、スクラッチに置いた。
- **書き出しの回数は減ったが、ビルドの時間はほぼ変わらない。** `prepare_pages!` の 2 出力先の合計は、第一段階のコードで 62.9 秒、第二段階で 61.3 秒だった。時間のほとんどは画像の変換と合成である。

#### 残したもの

- `stylesheets/` の CSS のコメントに `EpubBuilder` の名前が 15 か所（8 ファイル）残っている。コメントは平らな CSS にそのまま写るので、書き換えると EPUB の中の CSS が基準 r2 とバイト単位で一致しなくなる。CSS に手を入れる次の段階（S6）で、基準の版を上げるときに直す。
- テストのファイルの名前（`epub_builder_test.rb`・`epub_builder_sanitize_test.rb`）は変えていない。

### 10.3 S5-1 設定のキーと解決の順（2026-11-16）

#### 作ったもの

- **キー**（`ConfigKeys::KEYS`）: `book.type`（`techbook`）・`page.writing_mode`（`horizontal`）・`page.layout`（`reflowable`）・`notation.web_novel`（`false`）・`lint.ruleset`（`technical`）。直下の `book.yml` と雛形にも書いた（`notation:` は新しい節で、「機能ごとの詳細設定」の先頭に置いた）。
- **廃止キー**: `output.epub.layout`・`output.kindle.layout`。案内は §5.1 のとおり「レイアウトは本全体で一つです。page.layout に書いてください」。値を読んでいた `Epub::Config.validate_epub_layout_setting!` は消した。
- **`BookProfile`**（`lib/vivlio_starter/cli/book_profile.rb`）: §2.2 の表から `theme.name` と `page.use` を除いたもの（§8 の S5 の決め 1）。`type_of(raw)`・`written_type(raw)`・`defaults_for(type)`。
- **`Common.load_config`** の解決の順を §5.3 の 1・2・4・5 にした。種類の既定値は、`ConfigKeys` の既定値の上、判型のプリセットと `book.yml` の値の下に重ねる。`apply_page_preset` は `fallback_use:` を受け、`book.yml` に `page.use` が無いときは種類の既定値の判型を選ぶ（S8 の小説の判型のため。今の表には `page.use` が無い）。
- **`ConfigKeys::WHOLE_BOOK_KEYS`**（`%i[type]`）: `book.type` を分冊の巻で上書きできるキー（`ConfigKeys.book_keys`）から外す（§5.4）。
- **テスト**: `book_profile_test.rb`（表のキーが `KEYS` にあり既定値と違う・`book.type` の読み方・解決の順・巻で上書きできない）・`book_type_usage_test.rb`（§2.3 の三か所のほかに `book.type` を読む箇所が無い）。

#### 仕様と違えたこと

1. **知らない `book.type` は、読み込みでは `techbook` として扱い、止めない。** 設定の読み込みはモジュールの読み込みのときに走るので、ここで止めると `vs doctor` も `vs upgrade` も起動できなくなる。名前の誤りは、S5-2 の組み合わせの検査（`vs build`・`vs preflight` の入口）が 🔴 で示す。書いた字は `CONFIG.book.type` に残るので、検査で示せる。
2. **`book_type_usage_test.rb` の許す箇所は、`common.rb` に `config_keys.rb`（宣言）と `book_profile.rb`（表と読み方）を足した 3 ファイルである。** `vs new`（S8）と著者向けの表示は、作った段階で足す。
3. **`book_yml_consumption_test.rb` の許可リストに、`lint.ruleset`（S5-5 で読む）と `notation.web_novel`（S5-3 の `BuildPlan` が読む）を理由つきで載せた。** 読まれるようになると、同じテストの陳腐化の検査が削除を促す。

#### 確かめた結果

- 本書の `Common::CONFIG` を葉のキーごとに書き出して前後で比べ、差は足した 5 キーと消した 2 キーだけだった。B4（1.x の `book.yml` のまま）は足した 5 キーだけ（`output.epub.layout` は `book.yml` に書いてあるので、知らないキーとしてそのまま残る。読む箇所は無い）。
- 雛形の同期（`copy_to_scaffold.rb`）の差は `config/book.yml` だけ。同期の前に、同期しても差が 0 であることを確かめた。
- `rake test`: 4,374 件・失敗 0。`config_guide_test.rb` の雛形の節の数を 15 から 16 に直した（`notation` を足したため）。
- 四つの出力先を組んで r2 と比べるのは、計画どおり S5-4 の後に行う（S5-1 は設定の値だけを変え、本書の値の差は上の 7 キーで、どれも出力を作る段が読まない）。

#### 残したもの

- 原稿の 41 章と 44 章は、`output.epub.layout`・`output.kindle.layout` を書く例を載せている。原稿を直すと PDF と EPUB が変わり、基準の版を上げることになるので、S5 では直さない。2.0 の原稿の更新（S11）でまとめて直す。

### 10.4 S5-2 `BookTraits` と、横書き・左綴じの前提（2026-11-16）

#### 作ったもの

- **`BookTraits`**（`lib/vivlio_starter/cli/book_traits.rb`）: §2.4 のとおり。`resolve` は `page.writing_mode`・`page.layout` を、前後の空白と大文字・小文字を無視して読む。設定が無いとき（プロジェクトの外）と知らない値は、既定（横書き・リフロー）にする。書ける値は `BookTraits::WRITING_MODES`・`BookTraits::LAYOUTS` に置いた。
- **`Common.traits`**: `CONFIG` を差し替える唯一の入口（`install_configuration!`）が捨てて、次に引いたときに作り直す。`reload_configuration!` のほか、直接ビルド（`build_direct_configuration`）と巻の切り替えでも作り直される。
- **`vivliostyle_config_writer.rb`**: `readingProgression` を `Common.traits.binding` から書く。
- **`nombre_stamper.rb`**: `stamp!` が `recto_side:`（既定は `Common.traits.recto_side`）を受け、`draw_page_number` まで渡す。右ページ（ノド＝左端）かどうかを「奇数ページか」と「奇数ページの側」から決める。
- **`Guards::TraitCombinationCheck`**（`guards/trait_combination_check.rb`）: `vs build` と `vs preflight` の入口の検査の並びに、`ProjectRootCheck` の次に置いた。🔴 は、知らない `book.type`・知らない `page.writing_mode`・知らない `page.layout`・`page.layout: fixed`（S9 まで）。どれも `config/book.yml` のキーと、書ける値か直し方を示す。
- **`BookProfile.unknown_type(config)`**: 読み込んだ設定の `book.type` が知らない名前ならその字を返す。検査は種類を自分で読まず、ここから受け取る。
- **テスト**: `book_traits_test.rb`（5 件）・`guards/trait_combination_check_test.rb`（8 件）・`vivliostyle_config_writer_test.rb` に組方向と `readingProgression`（1 件）・`nombre_stamper_test.rb` に綴じの向きとノドの左右（1 件）。

#### 仕様と違えたこと

1. **知らない `page.writing_mode`・`page.layout` も 🔴 で止める。** §2.5 の表には無い。`BookTraits.resolve` は知らない値を既定として読むので、`writing_mode: tategaki` と書いた本が、何も示されずに横書き・左綴じで組まれることになる。`book.type` の名前の誤り（§10.3 の 1）と同じ扱いにした。
2. **固定レイアウトを 🔴 で止めている間は、索引と用語集の 🟡 を出さない。** §8 の S5 の決め 6 の「2 が先に当たるので、🟡 が出るのは S9 から」は、`Guard.run!` が全部の違反を出してから止まるので、何もしなければ 🟡 と 🔴 が並んで出る。組めない本に次の直しを示しても役に立たないので、`fixed_layout || fixed_layout_with_index` とした。S9 で 🔴 を外すと 🟡 が出る（テストに書き換えの注記を置いた）。
3. **`book_type_usage_test.rb` の許す箇所に `guards/trait_combination_check.rb` を足した。** 著者向けの文面に `book.type` の字が出るため（§2.3 の 3）。値は `BookProfile.unknown_type` から受け取り、種類では分岐しない。
4. **EPUB の設定（`build/epub/config.rb`）の `readingProgression: 'ltr'` は直していない。** ここを `rtl` にすると Vivliostyle が OPF の `page-progression-direction` を書き、S8 に回した範囲（§8 の「S5 の範囲に入れないもの」）に入る。S8 で `traits.binding` から引く。

#### 確かめた結果

- **完了の条件の 4**: 本書の写しから章を 1 つ（3 ページ）にし、`page.writing_mode: vertical`・`targets: pdf, print_pdf` にした本を組んだ（64 秒）。`VivliostyleConfigWriter.config_content` の `readingProgression` は `rtl`。入稿用 PDF（12 ページ）を `pdftotext -bbox` で読み、隠しノンブルは奇数ページが右端（x=677.7〜683.7。ページの幅 686.0）、偶数ページが左端（x=2.3〜8.3）だった。本文は横組みのままである（S5 の決め 3）。
- 本書（`book.type` なし・横書き）の `readingProgression` は `ltr` のままで、`Common.traits` は横書き・リフロー。隠しノンブルの左右を決める式は、`recto_side: :right` のとき前と同じ値になる（既存のテスト 7 件がそのまま通る）。
- `page.layout: fixed` にした写しで `vs preflight` が 🔴 を出して止まる。
- `rake test`: 4,389 件・失敗 0（S5-1 から 15 件の増。足した 15 件と一致）。`bundle exec rubocop`: 指摘 0。
- 四つの出力先を組んで r2 と比べるのは、計画どおり S5-4 の後に行う。

### 10.5 S5-3 `BuildPlan` と段の表（2026-11-16）

#### 作ったもの

- **`BuildPlan`・`BuildFeatures`**（`lib/vivlio_starter/cli/build/plan.rb`）: `BuildPlan = Data.define(:targets, :traits, :features)`。`BuildPlan.resolve(targets:)` が、出力先（`Build::Targets`）・軸（`Common.traits`）・機能（`BuildFeatures`）をまとめる。導く値は `derive_print?`・`viewing_pdf?`・`rotate_table_images?`・`cover_assets?` で、パイプラインにあった同じ名前の述語（`derive_print?`・`rotate_table_images?`・`cover_assets_needed?`）を移した。
- **`UnifiedBuildPipeline`**: `initialize` で `BuildPlan.resolve` を一度だけ呼ぶ（`attr_reader :plan`。`targets` は `plan.targets` を返す）。`full_mode_step_table` の条件の列は `plan`（`t = plan.targets`・`f = plan.features` と導く値）だけを読む。
- **条件の列へ移した段**（§3.3 の表のうち、今ある段の行）:

  | 段 | 前 | 後 |
  | :--- | :--- | :--- |
  | `index scan and build` | 常に載り、ハンドラが `IndexCommands.index_enabled?` を見て戻る | `f.index` |
  | `techbook post-process` | 常に載り、`Techbook::Processor` が `enabled?` を見て戻る | `f.techbook_post_process` |
  | `backlink dedup` | `t.any_pdf?`（索引が無効なら `BacklinkDedupOrchestrator.run!` がすぐ戻る） | `t.any_pdf? && f.index` |
  | `generate whole toc` | `Build::WholeTocGenerator.needed?` | `f.whole_toc` |
  | `prepare cover assets` | `cover_assets_needed?`（`Common.pdf_combined?`・`Common.epub_embed?`） | `plan.cover_assets?` |
  | `extract rotate table images` | `rotate_table_images?` | `plan.rotate_table_images?` |

  `vs preflight` の段の一覧（`register_preflight_steps`）の `index scan and build` も、`plan.features.index` のときだけ載せる。
- **テスト**: `build/plan_test.rb`（9 件）。導く値・設定から作る・索引が無効の本の段の一覧（全章・単章・preflight）・段の表の条件の列に `Common`・`CONFIG`・`IndexCommands` が現れないこと。

#### 仕様と違えたこと

1. **`BuildFeatures` に、§6 の表に無い値を 4 つ置いた。** `print_full_bleed`（`output.print_pdf.full_bleed`）・`pdf_cover`（`output.pdf.combined`）・`epub_cover`（`output.epub.embed`）・`whole_toc`（分冊の、全巻目次を載せる巻）。段の表が今まで設定や巻から直接読んでいたもので、ここへ置かないと「条件の列が `plan` だけを読む」（完了の条件の 3）にならない。
2. **`BuildPlan.resolve` は設定を引数に取らず、`targets:` だけを取る。** §3.2 は `resolve(config = Common::CONFIG)` としている。機能の値は `Common.index_enabled?` などの述語を通して読む。同じ述語を、段の中の処理（索引のページを並べる `PdfBuilder`・しおりを作る `OutlineExtractor`）も読むので、読み方を二つにしないためである。出力先を引数にしたのは、直接ビルドとテストが設定と違う組を渡すため。
3. **`BacklinkDedupOrchestrator.run!` と `Techbook::Processor#post_process_html_files!` の中の有効・無効の判定は残した。** どちらも段の表のほかからも呼ばれる（先回りの `speculate!`、前付・奥付の組み直しの後の再適用）。段の表から見ると、無効の本ではその段が載らないので、判定で戻ることは無い。
4. **`OutputTarget.for(id, traits)`（§10.1 の 6 で「S5 で引数を足す」としたもの）は足していない。** `traits` で宣言が変わるのは固定レイアウトだけで、S9 までは読む箇所が無い。S9 で足す。

#### 確かめた結果

- **完了の条件の 3**: `plan_test.rb` が、段の表の条件の列に設定の読み出しが無いこと、パイプラインに `index_enabled?` が残っていないことを検査する。
- **完了の条件の 5**: 章 1 つの写しを `index_glossary.enabled: false` にして `vs build --log=debug` で組み、段の一覧（Build Step Timings）に `index scan and build` と `backlink dedup` が出ないことを確かめた（21 段・24.95 秒）。
- **本書の段の一覧が前後で同じ**: 出力先の 8 つの組（`pdf`・`print_pdf`・`pdf+print_pdf`・`pdf+epub`・四つ全部・`epub`・`kindle`・`print_pdf+kindle`）× 3 つのモード（全章・単章・preflight）と、本書の設定のままの全章の、計 25 通りの段の並び（ラベル・相・単位）を、S5-2 の版（`96f16920`）と書き出して比べ、バイト単位で一致した。
- `rake test`: 4,398 件・失敗 0（S5-2 から 9 件の増。足した 9 件と一致）。`bundle exec rubocop`: 指摘 0。
- `book_yml_consumption_test.rb` の許可リストから `notation.web_novel` を外した（`BuildPlan` が読むようになり、陳腐化の検査が促した。§10.3 の 3）。
- `pipeline_unit_test.rb` は `@targets` の代わりに `@plan` を置く形に、`epub_builder_test.rb` の `EpubTargetTest` は `output` だけの設定の代わりに本書の設定の `output.targets` を差し替える形にした（パイプラインが開始時に設定の全体から `plan` を作るため）。期待値は変えていない。

### 10.6 S5-4 前処理・後処理の並びを表にする（2026-11-16）

#### 作ったもの

- **`MarkdownPreprocessor::STEPS`**: §3.4 の形 `[メソッド, 種別, 条件]` の 37 行。種別は `:check`（content を変えない点検）・`:transform`（content を書き換える）・`:output`（書き出し）。`run` は表を上から回し、条件が `nil` か `condition.call(plan)` が真の段を走らせる。並びの順は前と同じ。
- **条件の付いた段**: `strip_index_markup!` の `->(plan) { !plan.features.index }` だけ。メソッドの中の `return if Common.index_enabled?` を条件の列へ移した（S5-3 の段の表と同じ扱い）。ほかの段は記法を使わなければ何もしないので、条件を付けない。
- **後処理の表**（`post_process.rb`）: `first_pass_steps`（全ページに先にかける 2 段）と `page_steps`（1 ページずつ順にかける 25 段）。1 行は `[名前, 処理, 失敗したときの扱い, 条件]`。失敗したときの扱いは、表にする前の `begin`/`rescue` をそのまま写した（`[:error, 文]` は 🔴・`[:warn, 文]` は 🟡 で記録して次の段へ、`nil` は例外を上げる）。表を回すのは `run_post_process_steps`。置換ルールの件数の合計は、表を作るときに渡す `count_replacements` で数える。
- **`BuildPlan.current`・`BuildPlan.install`**: パイプラインが段を走らせている間だけ、開始時に作った `plan` を置く。前処理（`MarkdownPreprocessor.new(md, entry, plan: BuildPlan.current)`）と後処理はそれを読み、ビルドの途中で設定を読み直さない（§3.2）。パイプラインの外（テスト・単独の前処理）では、その場の設定から作る。
- **テスト**: `markdown_preprocessor_test.rb` に表の形（名前が実在の private メソッドで重複が無い・書き出しが最後・種別と条件の形）の 2 件。`post_process/step_table_test.rb`（5 件。🔴・🟡・例外・条件・表の形）。索引の記法のテストは、`Common` の差し替えをやめ、`plan` を引数で渡して表の条件を通す形にした（期待値は変えていない）。

#### 仕様と違えたこと

1. **後処理の表は `[名前, 処理, 失敗したときの扱い, 条件]` の 4 列にした。** §3.4 は「後処理も同じ形にする」としている。後処理の段は、段ごとに失敗の扱い（🔴 で続ける・🟡 で続ける・止める）と記録の文が違い、引数も `html` だけの段と `html` と `entry` を取る段がある。前処理の形（メソッドの名前だけ）に合わせると、段ごとに中継のメソッドが 25 個要る。そこで、S5-3 の段の表（`full_mode_step_table`）と同じく処理を lambda で持たせ、失敗の扱いを列にした。種別の列は置いていない（後処理の段はどれも HTML を書き換える）。
2. **`plan` を引数で引き回さず、`BuildPlan.current` に置いた。** 前処理と後処理は、章の段のほかに部扉・全巻目次・目次の生成からも呼ばれ、テストの差し替えも引数の数に依っている。引数で渡すと、呼び出しの連なり（`SectionBuilder` → `PreProcessCommands` → `MarkdownPreprocessor`）の 4 か所の形が変わる。`Build::Volumes.current` と同じ置き方にした。

#### 確かめた結果

比べた結果は、基準のディレクトリの `r2/check/s5-4/`。

| 確かめ | 結果 |
| :--- | :--- |
| 本書の契約 HTML（`.cache/vs/build/html/` の全部の HTML）が前後で同じ | 39 件とも、S4 の第二段階の写し（`r2/check/s4-2/runs/b1`）とバイト単位で同じ。基準 r2 の写し（`r2/runs/b1`）とも同じ |
| 本書（B1）を四つの出力先で組み、基準 r2 と比べる | 閲覧用 PDF 284 ページ・入稿用 PDF 282 ページとも、違うページ 0。EPUB・Kindle 用 EPUB とも、r2 との違いは S4 で記録した 2 件（`42-frontispiece`・`92-latex-cheatsheet` の属性の順。§10.2）だけで、S4 の第二段階の出力とは違い 0 件 |
| Kindle の変換 | Enhanced Typesetting: Supported・Success・エラー 0・品質の問題 0。中間生成物は 36 件・26,405 要素で、r2 との `computedstyle` の差 0・`style` の差 0 |
| `rake test` | 4,405 件・失敗 0（S5-3 から 7 件の増。足した 7 件と一致）。`bundle exec rubocop`: 指摘 0 |

- §8 の S5 の完了の条件の 1（四つの出力先が基準と同じ）は、S5 の最後にもう一度確かめる（S5-5 は `vs lint` と `vs metrics` だけを変え、ビルドの出力を作る段を変えない）。

### 10.7 S5-5 `lint.ruleset` と `metrics.use: none`（2026-11-16）

#### 作ったもの

- **`Lint::Rulesets`**（`lib/vivlio_starter/cli/lint/rulesets.rb`）: 組の名前 → `technical` から切る規則の名前の表（`TABLE`）。`technical` は何も切らない（今の一組）。`minimal` は文体・文の長さ・空きの規則（`preset-ja-technical-writing`・`preset-ja-spacing` のプリセットごとと、独自の `ambiguous-comparison`・`slash-between-japanese`・`space-around-brackets`・`long-parenthetical`・`missing-period`・`sentence-length`・`max-ten`・`ja-no-weak-phrase`）を切る。`novel` は `minimal` と同じ（§8 の S5 の決め 4）。
- **`LintRunner#disabled_rules`**: 組が切る規則と `lint.disabled_rules` を合わせたものを返す。textlint の実行時の設定・独自の規則・`--fix` はどれもここを読むので、組は全部に同じに効く。知らない組の名前は `LintError` で止め、書ける名前を示す。
- **`metrics.use: none`**: `Metrics::ConfigLoader#judge_volume?` が偽になり、章と節の分量の判定（💡 加筆検討・やや長い・✅ ちょうどよい）を出さない。字数・棒・漢字の水準・文章の質の指摘（🤔）は残る。直下の `book.yml` の `metrics.use` の選択肢の一覧に `none` を書き足した。
- **テスト**: `lint/rulesets_test.rb`（6 件）・`lint_commands_test.rb` に組が実行時の設定で効くことと知らない組の名前（2 件）・`metrics/volume_none_test.rb`（4 件）。`book_yml_consumption_test.rb` の許可リストから `lint.ruleset` を外した（読まれるようになり、陳腐化の検査が促した）。

#### 仕様と違えたこと

1. **`Lint::RULESETS` は「入れる規則の id の組」ではなく「`technical` から切る規則の名前」で書いた。名前は `Lint::Rulesets::TABLE`。** textlint のプリセットの中身は著者の `.textlintrc.yml` で増減するので、vs の側で入れる規則を数え上げられない。切る規則の名前は `lint.disabled_rules` と同じ読み方で、プリセットの名前を書けばプリセットごと切れる。`rulesets_test.rb` が、表の名前がどれも実在の独自の規則か、本書の `.textlintrc.yml` のプリセットの名前であることを確かめる（綴りを誤った名前は何も切らないため）。
2. **`minimal` の中身（「誤字と表記の揺れだけ」）は、この版で次のように決めた。** 残すのは、表記の揺れ（`prh`）・誤字（`spellcheck-tech-word`・`kanji-lookalike`）・表記（`mazegaki`・`kansuji-counter-suffix`）・語の間の空きの取り違え（`index-term-spacing`・`affix-spacing`・`hiragana-spacing`）・記法の取り違え（`indented-code-block`・`setext-heading`・`multiple-chapter-headings`・`unclosed-suppression`・`accidental-emphasis`・`accidental-index-term`。紙面が壊れるため）。`minimal` を既定にする絵本は S9 まで組めないので、中身は絵本の仕様で確かめ直す。
3. **`metrics.use: none` は、`vs metrics` の分量の判定のほかを変えない。** `--warn`（指摘のある章だけを出す）では、分量の指摘が出ないので、文章の質の指摘がある章だけが残る。

#### 確かめた結果

| 確かめ | 結果 |
| :--- | :--- |
| 本書の `vs lint` の全部の指摘を前後（`33816137` と作業ツリー）で突き合わせる | 本書は前後とも指摘 0 件で、出力は同じ。0 件どうしでは差を見落とせるので、基準の B4（`ai_web_starter`）の写しでも突き合わせた。455 行（日本語校正 194 箇所・スペルチェック 125 箇所）がバイト単位で同じ |
| 同じ写しを `lint.ruleset: minimal` にする | 日本語校正 194 → 123 箇所。0 件になったのは文体の規則（`max-ten` 22・`ja-no-weak-phrase` 13・`ja-space-around-link` 8・`ja-no-space-between-full-width` 4・`no-doubled-conjunction` 2・`ambiguous-comparison` 1）。`prh` 64・`spellcheck-tech-word` 7・`kansuji-counter-suffix` 6・`mazegaki` 1・`index-term-spacing` 1 は同じ件数で残る |
| `metrics.use: none` の本で、分量の判定の行だけが出ない | B4 の写しで `standard` と `none` の `vs metrics` を比べた。70 行のうち違うのは 18 行で、どれも行末の 💡・✅ が消えただけ（字数と棒は同じ）。`standard` の出力は前後で同じ |
| `rake test` | 4,417 件・失敗 0（S5-4 から 12 件の増。足した 12 件と一致）。`bundle exec rubocop`: 指摘 0 |

### 10.8 S5 の完了（2026-11-16）

S5 の小段階 S5-1〜S5-5 を終えた。§8 の S5 の完了の条件は次のとおり満たした。比べた結果は、基準のディレクトリの `r2/check/s5-final/`。

| 完了の条件 | 結果 |
| :--- | :--- |
| 1. `book.type` の無い本書が、基準と同じ出力になる（四つの出力先） | S5-5 の後の作業ツリーで組み、基準 r2 と比べた。契約 HTML 39 件はバイト単位で同じ。閲覧用 PDF 284 ページ・入稿用 PDF 282 ページとも違うページ 0。EPUB・Kindle 用 EPUB とも、r2 との違いは S4 で記録した 2 件（属性の順。§10.2）だけ。Kindle の変換は Supported・Success・エラー 0・品質の問題 0 で、中間生成物 26,405 要素の `computedstyle`・`style` の差 0 |
| 2. `book_profile_test.rb`・`book_type_usage_test.rb` が通る | 通る（§10.3・§10.4） |
| 3. `full_mode_step_table` の条件の列が `plan` だけを読み、ハンドラの中で設定を見て戻る段が無い | `plan_test.rb` が検査する（§10.5） |
| 4. `page.writing_mode: vertical` の最小の本で、`readingProgression` が `rtl`、隠しノンブルが奇数ページの右端 | §10.4 |
| 5. `index_glossary.enabled: false` の本で、`index scan and build` と `backlink dedup` が段の一覧に出ない | §10.5 |

- 基準 r2 は「S0 の基準」の版を上げたもの（`v2-migration-plan.md` §3.2）なので、条件の 1 は r2 と比べた。
