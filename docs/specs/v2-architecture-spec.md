# 2.0 のアーキテクチャ（本の種類・パイプライン・出力先・設定）

> 作成日: 2026-11-14
> ステータス: **設計済み・実装待ち**
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
| A-2 出力先の抽象 | 出力先を `OutputTarget`（HTML の変換の並び・CSS の形・素材の方針・梱包）として宣言する。`epub_builder.rb` はこの単位で分割する | §4 |
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
| テーマが対応しない組方向・レイアウト（テーマの `supports:`・`theme-contract-spec.md` §3） | 🔴 で止める。対応するテーマの名前を示す |
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
  :transforms,  # 契約 HTML に当てる変換の並び（§4.3）
  :css_form,    # :layered / :flat / :flat_literal（css-layer-restructure-spec.md §4）
  :assets,      # 素材の方針（使える画像の形式・SVG を同梱できるか・動画の扱い）
  :packager     # 梱包の方法
)
```

- 出力先は「HTML の変換規則と CSS の束」に、素材の方針と梱包の方法を加えた四つで表せる。brief の A-2 の問いへの答えは「表せる。ただし二つでは足りず、素材と梱包が要る」である。
- `transforms`・`assets`・`packager` は `traits` によって変わる。宣言は `OutputTarget.for(id, traits)` で引き、リフローと固定レイアウトで別の値を返す。

### 4.2 四つの出力先

| 出力先 | 変換の並び | CSS の形 | 画像 | 動画 | 梱包 |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `pdf` | なし（Type 3 対策は L3 の段のまま） | 層あり | そのまま | サムネイルに動画へのリンク | Vivliostyle → 結合 → しおり |
| `print_pdf` | `pdf` と同じ | 層あり | CMYK へ変換 | サムネイルと QR コード | `pdf` から導出するか、組み直す |
| `epub`（リフロー） | 共通の 11 段 | 平ら | WebP | `<video>` と、再生できない読者向けの代わりの表示 | Vivliostyle の EPUB |
| `kindle`（リフロー） | 共通の 11 段 ＋ Kindle の 18 段 | 平ら・リテラル | JPEG・PNG（SVG と WebP は同梱しない） | サムネイルに動画へのリンク | Vivliostyle の EPUB → KPF |
| `epub`（固定） | 固定レイアウト用 | 平ら | JPEG・PNG・WebP | `<video>` | vs が梱包 |
| `kindle`（固定） | 固定レイアウト用 ＋ 動画の置き換え | 平ら・リテラル | JPEG・PNG | サムネイルに動画へのリンク | vs が梱包。KPF にせず EPUB を出力する |

- クリーン EPUB にも平らな CSS を渡す。Kobo と Google Play Books が `@layer` を解するかは確かめられていない（`v2-feasibility-notes.md` §6.2）が、層を外した CSS はどのリーダーでも同じに読まれるので、対応の有無を調べる必要も、著者に選ばせるキーも要らなくなる。層を外す仕組みは Kindle のために作るので、追加の実装は無い。
- 固定レイアウトの `kindle` の出力ファイルは `<名前>-kindle.epub` とする。KDP へはこの EPUB を出す（`v2-feasibility-notes.md` §4.1）。KDP が受け付けて正しく表示するかは未確認で、S9 の入口で確かめる（§9）。

### 4.3 `epub_builder.rb` の分割

`build/epub_builder.rb`（3,858 行・177 メソッド）を、`OutputTarget` の項目に沿って分ける。

```
lib/vivlio_starter/cli/build/
  output_target.rb                 型と登録表
  targets/pdf.rb print_pdf.rb epub.rb kindle.rb   各出力先の宣言
  transforms/
    runner.rb                      変換の並びを HTML に当てる
    common/*.rb                    両フレーバ共通の 11 段（1 段 1 ファイル）
    kindle/*.rb                    Kindle 専用の 18 段（1 段 1 ファイル）
    fixed/*.rb                     固定レイアウト用（S9 で足す）
  epub/
    workspace.rb                   消費者のディレクトリ・素材の複製（localize）・参照の切れた画像の回収
    images.rb                      WebP への変換・著者の SVG の派生・ラスター化
    config.rb                      EPUB 用の vivliostyle.config.js
    opf.rb                         content.opf の書き換え（id・識別子・綴じの向き）
    kpf.rb                         KPF への変換と記録の要約
    fixed_package.rb               固定レイアウトの EPUB の梱包（S9 で足す）
```

変換の 1 段は、次の形の関数モジュールにする。

```ruby
module VivlioStarter::CLI::Build::Transforms::Kindle::TextifySimpleMath
  module_function

  # @param doc [Nokogiri::HTML5::Document] 1 ページ分の契約 HTML（破壊的に書き換えてよい）
  # @param ctx [Transforms::Context] 出力先・ワークスペース・entry・traits
  def call(doc, ctx) = ...
end
```

- 名前は中身で付け、`_for_epub!`・`_for_kindle!` の接尾辞はやめる。どちらの出力先で走るかは、置いたディレクトリと出力先の宣言で分かる（今は名前から判別できない。`v2-inventory-report.md` §5）。
- 分割は二段階で行う。(1) メソッドをファイルへ移すだけで、呼び出しの順と中身は変えない。(2) `runner.rb` が 1 ページの HTML を一度だけ読み、変換を順に当て、一度だけ書く形にする。(1) の完了の条件は「EPUB と Kindle の出力が分割の前とバイト単位で同じ」、(2) は「HTML の差が属性の順と空白だけ」とする（§8 の S4）。
- 文字列の置換で書かれている段は、(1) ではそのまま移し、(2) で `doc` を受ける形に直す。直せない段（HTML として不正な途中の形を扱うもの）があれば、`runner.rb` に「ファイルを直接書き換える段」の種別を残す。

### 4.4 Kindle 向けの劣化を二つにまとめる

今の四か所（`v2-inventory-report.md` §6）は、次の二つに収める。

| 今の場所 | 行き先 |
| :--- | :--- |
| 静的な CSS の `body.vs-kindle`（10 ファイル・124 か所） | `stylesheets/targets/kindle.css` に集め、Kindle の CSS の束にだけ入れる（`css-layer-restructure-spec.md` §5） |
| `BookSettingsCss` の `kindle_accent_rules`・`kindle_custom_color_rules`・`h4_marker_kindle_rule` | CSS の生成が `var()` と `color-mix()` をリテラルに解くので、個別に書き出す規則は要らなくなる。同じ結果になることを確かめてから消す（同 §4.4） |
| `EpubBuilder` の Kindle 専用の 18 段 | `build/transforms/kindle/` と `build/targets/kindle.rb` の並び |
| `sanitize_epub_css!`（組み上がった EPUB の CSS の書き換え） | CSS の生成が、EPUB に入れる前の CSS から `@page` の余白の箱と WebP の `url()` を落とす。組み上がった EPUB を開いて書き換える処理は消す |

結果として、「Kindle で何を変えているか」は `build/targets/kindle.rb`（DOM の変換の並びと素材の方針）と `stylesheets/targets/kindle.css`（構造の劣化の規則）の二つを読めば分かる。色や寸法のリテラル化は、一般の仕組み（CSS の生成）になり、Kindle 専用の記述ではなくなる。

Kindle の囲みの 3 点の型（`.claude/CLAUDE.md` の「Kindle degradation convention」）は、2 点になる。(1) ラベルの登録（`ADMONITION_LABELS`）と (3) テストは残り、(2) の「リテラルの色で `body.vs-kindle` の規則を書く」は「`targets/kindle.css` に構造の違いだけを書く。色は変数のままでよい」に変わる。S3 の完了時に `.claude/CLAUDE.md` と `notation-implementation-guide.md` §3 を直す。

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
- 選ばれたテーマが宣言していないキーが `theme:` 節にあれば、🟡 で知らせる（テーマを替えた後に前のテーマのオプションが残った場合。「このテーマには無い設定です」と、そのテーマのオプションの一覧を示す）。

### 5.3 値の解決の順

`Common.load_config` の解決を次の順にする。後のものが前のものを上書きする。

1. `ConfigKeys` の既定値
2. 種類の既定値（`BookProfile::PROFILES[book.type]`）
3. テーマのオプションの既定値（`theme.*` だけ）
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

- 作るもの: §4.1 の `OutputTarget`、§4.3 のファイル構成、`EpubFlow` を出力先の宣言から流れを組む形にする。
- 完了の条件:
  1. `build/epub_builder.rb` が無くなり、どのファイルも 600 行を超えない。
  2. 変換の段の名前に `_for_epub!`・`_for_kindle!` が残っていない。
  3. 本書の写しを四つの出力先で組み、S0 の基準と比べて、PDF は全ページの画素が一致、EPUB と Kindle 用の EPUB は中の HTML・CSS・OPF が §4.3 の (1) ではバイト単位で一致、(2) では属性の順と空白を除いて一致する。
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
| 1 | KDP が、vs の作る固定レイアウトの EPUB を受け付けて正しく表示するか | S9 の入口 | KDP が固定レイアウトの本を EPUB で受け付けることは確認済み（`v2-feasibility-notes.md` §4.1）。vs の作る EPUB での表示は S9 で確かめる。S9 の最初に、最小の絵本の EPUB を作り、ユーザーが KDP のプレビューで確かめる。通らない場合は、絵本の `kindle` を 2.0 の対象から外すか、Kindle Create で手で作る手順を案内するかを、ユーザーが決める。§4.2 の表は「通る」を前提に書いた |
| 2 | 小説と絵本の判型のプリセット・既定のテーマの名前 | S8・S9 の仕様 | §2.2 の表の値は仮 |
| 3 | `output.pdf.techbook` の名前を変えるか | 決定済み（2026-11-14） | 変えない。働きは種類に依らず同じで、ほかの設定との衝突も無い |
| 4 | 絵本の原稿の形（1 ファイルに複数ページか・1 ファイル 1 ページか）と、ページの中の文字の置き方の記法 | S9 の仕様 | §3.5 は L1 が「ページの並び」を返すことだけを決めた |
| 5 | 小説の分量の基準を `vs metrics` に持つか | 2.0 の後 | `metrics.use: none` で判定を外す |
