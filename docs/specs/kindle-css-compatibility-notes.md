# Kindle（KFX）CSS 対応状況と実装知見メモ

> 作成日: 2026-06-21
> ステータス: **知見メモ（恒久参照）**
> 対象: Kindle ターゲット（`target=kindle`）の EPUB→KPF 変換で得られた、Kindle 表示エンジンの CSS/画像対応状況と回避策。
> 関連: `epub-kindle-target-split-spec.md`（ターゲット分離）, `kindle-simple-header-svg-spec.md`（付録見出しの SVG 化・実装したが却下）, `epub-code-line-numbers-spec.md`（コード行番号）, `stylesheets/`（各 `body.vs-kindle` フォールバック）, `lib/vivlio_starter/cli/build/epub_builder.rb`

---

## 0. 背景と目的

Kindle 対応（クリーン EPUB と Kindle 用 KPF のターゲット分離）の実装過程で、**Kindle の表示エンジンが非常に古い CSS サブセットにしか対応していない**ことが繰り返し問題になった。`var()` / `position:absolute` / `::before`・`::after` / CSS Grid / WebP など、EPUB 3.3 で広く使われる機能の多くが解されず、ルールごと破棄されたり画像が参照切れになったりして、レイアウトが素テキストに崩れる。

本メモは、今後 Kindle 向けの CSS・画像処理を編集・拡張する開発者が**同じ落とし穴を踏まないよう**、判明した対応状況・原因・回避策・実装上の知見を一箇所に集約するものである。個々の機能仕様ではなく「Kindle という環境の癖」を記録する位置づけ。

---

## 1. Kindle の表示エンジンと前提

- Kindle の現行レンダリングは **KFX / Enhanced Typesetting**。KDP に EPUB（や本プロジェクトの KPF）をアップロードすると、Amazon 側で KFX へ再変換される。
- 本プロジェクトは中間 EPUB を生成し、**Kindle Previewer 同梱の `kindlepreviewer` CLI** で `.kpf` に変換する（`convert_epub_to_kpf!`）。実機・Previewer での表示が「正」であり、epubcheck が通っても Kindle で崩れることは普通にある。
- **検証は必ず Kindle Previewer／実機で行う。** epubcheck の合格は KFX での正しい表示を保証しない（別レイヤーの検証）。
- **版を読者に揃える。** Previewer 3 と 4 では判定が変わる（§5.5）。3 で KPF になっていた本が 4 では Mobi になるので、古い版で確かめても確かめたことにならない。
- KPF 変換ログのエラー/警告コード（`E####` / `W####`）は `summarize_kpf_logs` が内訳集計する。例: `W14016`＝`embed:false` 時の "Cover not specified" 通知（表紙は KDP 側で付けるため想定内）。

---

## 2. CSS 対応状況一覧

「Kindle」列は KFX / Enhanced Typesetting での挙動。「クリーン EPUB（Kobo/Apple Books）」では下記はいずれも問題なく解される。**下表は Kindle Previewer 4.0.1 で測り直したもの**（2026-09-23・測り方は §2.1）。3 から変わった行には印を付けた。

| CSS 機能 | Kindle(KFX) | 症状 | 本プロジェクトの回避策 |
|:---|:---:|:---|:---|
| `:is()` セレクタ | ❌ | **ルールごと丸ごと破棄**される | `body.vs-kindle` 用は明示セレクタへ展開（`a::before, b::before, …`） |
| `var()`（カスタムプロパティ） | ❌ | 値が解決されず無効化 | `body.vs-kindle` フォールバックは**具体値**で記述 |
| `calc()` / `clamp()` | ❌ | 無効化。**`calc()` は前処理が計算するが、描画側が捨てる**（§2.1） | 具体値で記述 |
| `color-mix()` | ❌ | 宣言ごと消える | `ThemeColor.mix_with_white` で事前計算 |
| `display: grid` / `display: flex` | ❌ | `block` に潰れる | `display: block` 等の素直なフローに縮退 |
| `::before` / `::after` の `content` | **✅ 4 で変わった** | **実体の `<span>` として本文へ注入される。`display:block`・`background-color`・`padding`・`color`・`font-weight` も効く** | 回避策は現状維持（§2.2） |
| `::before` の `position: absolute` | ❌ | 位置指定は効かない | 通常フローで組む |
| `linear-gradient()` | ❌ | 宣言は前処理を通るが、描画されない | 単色 `background` / `border` で代替 |
| WebP 画像（`<img>` / CSS `url()`） | ❌ | 画像が破棄される（`W14012` / `W14015`）。**4 では Enhanced Typesetting ごと落ち、本が `.mobi` になる** | JPEG/PNG へトランスコード＋インライン WebP 宣言を除去 |
| SVG 画像 | ❌ | **同梱されているだけで Enhanced Typesetting が落ちる**（§5.5） | 参照ぶんはラスタ化し、参照の切れたものは同梱しない |
| MathML | ✅ | Previewer 内の MathJax が SVG へ描き起こす。ET は落ちない | （本プロジェクトは素の表記→SVG／テキスト化の経路を使う） |
| modern 改ページ `break-before: page` | △ | 効かないことがある | legacy `page-break-before: always` を**併記** |
| テーブルセルの `width` / `white-space:nowrap` | △ | 尊重されず、2桁行番号が縦に折れる等 | テーブル方式のレイアウトに依存しない（行番号は別仕様で検討） |

> ❌＝非対応（解されない）、△＝不安定（端末/状況で挙動が変わる）。

### 2.1 測り方と、間違えやすい観測点

`kindlepreviewer` の CLI は描画結果を書き出せない。観測できるのは 3 つだけである。

1. **Enhanced Typesetting の判定**（`Summary_Log.csv`。Supported なら `.kpf`、でなければ `.mobi`）
2. **変換ログのコード**（`W14012` など）
3. **変換の中間生成物**。走行中の `cTemp/conv_temp/preprocessed/*.xhtml` に、KFXGen が解決した CSS が `style` と `computedstyle` として書き戻される

検査は `scripts/kfx_probe.rb` が行う。機能ごとに目印を入れた小さな EPUB を組み、変換し、中間生成物を採取して判定する。Previewer は終了時に作業ディレクトリを消すので、**走行中に写し取る**必要がある。

**中間生成物だけで判断してはいけない。** ここが今回いちばん間違えやすかった点である。前処理は Chromium（同梱の phantomjs）でページを組むため、`calc(2mm + 2mm)` は `padding-left:15.118px` と正しく計算され、`linear-gradient()` も宣言のまま残る。**それでも KFX の描画側は両方とも捨てる。** 中間生成物は「変換器が値を保った」ことしか示さない。**最終判定は Previewer の画面で行うこと。**

### 2.2 `::before` は効くようになったが、置き換えは急がない

Previewer 4 は `::before` の `content` を実体の `<span amzn-isaddedcontent="true" amzn-selector="before">` として本文へ注入する。囲みボックスに近い形で測ったところ、ラベルは独立した行に出て、帯（背景色＋余白）も描かれた。**Enhanced Typesetting が落ちた Mobi 経路でも同じ span が注入される**ので、出力形式には依存しない。

つまり `ADMONITION_LABELS` の実体ラベル注入と、`body.vs-kindle` 側の `content: none` は、**どちらも畳める**。ラベルの文言と装飾が CSS の一箇所に集まり、囲みボックスを増やすときの手順が 3 つから 1 つに減る。

**ただし現状維持でいる。** いまの方式は実体の要素なので、変換器の挙動に依存しない。擬似要素に頼ると、Previewer 5 で方針が戻ったときに気づきにくい。畳むなら、**畳んだ状態を Previewer の画面で確かめる手順**を併せて決めること。

### 補足: なぜ `:is()` が一番危険か

`:is()` は **マッチしない・無効化される**のではなく、**そのCSSルール全体がパース時に捨てられる**。つまり `body.vs-kindle :is(.tip,.memo,.column) { … }` と書くと、Kindle ではその枠線・余白指定が丸ごと消え、装飾なしの素の段落になる。共通CSS（クリーン EPUB/PDF 用）で `:is()` を使うのは構わないが、**Kindle 専用フォールバックでは絶対に使わない**。明示セレクタへ展開すること。

---

## 3. 画像形式（WebP 非対応）の扱い

Kindle は WebP を表示できない。`vs build` の画像最適化は WebP を生成するため、Kindle フレーバでは二段構えで対処する。

**Previewer 4 では、失うものが「画像 1 枚」では済まなくなった。** WebP が 1 枚でも混じると、その画像が破棄される（`W14012` / `W14015`）だけでなく、**Enhanced Typesetting ごと落ちて本が `.mobi` になる**（実測 2026-09-23。同じ絵を JPEG に替えた対照では `Supported` になるので、画像の中身ではなく形式が効いている）。除外は「画質のため」ではなく「KPF を作るため」の必須処理である。

1. **実体のトランスコード**（`transcode_webp_images_for_epub!`）: `<img>` が参照する WebP を JPEG/PNG に変換し、参照を貼り替える。
2. **インライン CSS 宣言の除去**（`strip_webp_inline_styles_for_kindle!`）: techbook テーマが `<head>` に注入する `<style>` 内の `--h3-marker: url(...webp)` 系を削除。
   - パターンは `INLINE_WEBP_DECL_PATTERN = /[\w-]+\s*:\s*[^;{}]*url\([^)]*\.webp[^)]*\)[^;}]*;?/i`。
   - **教訓**: カスタムプロパティ名は `[\w-]+` で**丸ごと**拾うこと。`[a-zA-Z-]+` だと `--h3-marker` の `-marker` だけ消えて `--h3` 断片が残り、別の CSS エラー（CSS-008）を誘発した。
   - **教訓**: 正規表現リテラルは `%r{...}` ではなく `/.../` を使う。宣言値の `[^;{}]` に含まれる `{}` が `%r{}` の区切りと衝突する。
3. **同梱からの除外**（`build_copy_asset_excludes_config(flavor:)` / `sanitize_epub_css!(flavor:)`）: Kindle フレーバのときのみ `images/**/*.webp`・`stylesheets/**/*.webp` を除外し、CSS の WebP `url()` も除去する。
   - **教訓**: これは**フレーバ依存**にすること。当初 WebP を常時除外したらクリーン EPUB（WebP 同梱が正）で参照切れが起きた。クリーン EPUB は WebP を**残す**。

---

## 4. 個別に踏んだ不具合と対処（実例）

実装デバッグで実際に遭遇したものを、再発防止のため記録する（詳細経緯は CHANGELOG / 当時のデバッグメモ参照）。

| 症状（Kindle） | 原因 | 対処 |
|:---|:---|:---|
| TIP/MEMO/COLUMN の枠線が出ず「TIP」ラベルが重複 | `:is()` でルール破棄＋`::before` ラベルが効かない | `body.vs-kindle` で明示セレクタ展開・`::before` 抑止・実体ラベル注入・具体色枠線（`chapter-common.css`） |
| 節（節絵）がページ途中から始まる | modern `break-before` 非対応 | `article.vs-section-topic-epub` に `page-break-before: always` 併記（`components.css`） |
| 付録（simple スタイル）の見出しが素テキスト化 | `var()`/`grid`/`clamp()`/`::before` 多用 | `simple-header.css` に `body.vs-kindle` 具体値フォールバック（SVG 画像化を試したが却下・2026-07-20 revert）。枠色は下記のテーマ色リテラル焼き込みでテーマ追従化 |
| 本文アクセント（strong 太字・強調下線・見出しマーカー・コラム/注記枠）がテーマ色にならない | すべて `var(--theme-accent)`/`color-mix()` 依存。KFX で解決されず、strong 等は**黒**、枠は静的フォールバックの**グレー #888**、付録見出しは**くすんだ金 #b8860b** に劣化 | **テーマ色をリテラル hex へ解決し、最後に読まれる `book-settings.css` に `body.vs-kindle` 規則として焼き込む**（`ThemeColor`＋`BookSettingsCss#kindle_accent_rules`）。静的フォールバックを後勝ちで上書き。`theme.color` に追従（`kindle-theme-color-literalize-spec.md`） |
| 用語集・後書き・索引の h1 下線が消える | テーマ装飾が var()/擬似要素依存 | `glossary.css`/`index.css`/`preface.css` に具体色の下線フォールバック |
| book-card がグリッド崩れ | `display:grid` 非対応 | `body.vs-kindle .book-card { display:block }`（`components.css`） |
| コードブロックが特定幅でクリップ消失（Apple Books） | リフロー文脈での折り返し未指定 | **クリーン EPUB 側**の `body.vs-epub pre[class*="language-"]{ white-space:pre-wrap; overflow:visible }`（`code.css`）。Kindle ではなく EPUB 共通マーカー側の対処 |
| 数式が極大表示／表内数式が崩れる／フォント変更に非追従 | 画像を本文フォント相対にできない KFX の本質的制約 | **単純式は `textify_simple_math_for_kindle!`（`MathTextRenderer`）で HTML テキスト化**し 100% 追従させる（Kindle 限定・`convert_math_units_for_epub!` の直前）。テキスト化不可の複雑式のみ従来の px フォールバックで巨大化を防ぐ（`kindle-inline-math-textify-spec.md`） |

---

## 5. 実装アーキテクチャ上の知見

### 5.1 フレーバ分離と body マーカー

- `generate_epub_entries!(base_dir, entries, flavor:)` が `:epub` / `:kindle` を受け取り、共通フェーズ＋Kindle 限定フェーズを切り替える。
- **body マーカーで CSS を出し分ける**のが基本設計:
  - `mark_body_for_epub!` → `vs-epub`（**両フレーバ**に付く。EPUB リフロー文脈の印）
  - `mark_body_for_kindle!` → `vs-kindle`（**Kindle のみ**。劣化変換を施した印）
- **PDF には付かない**ため、`body.vs-epub` / `body.vs-kindle` の CSS は PDF 出力に一切影響しない。安全に追記できる。
- CSS 編集時の原則:
  - クリーン EPUB/PDF 向けの装飾は従来どおり（`:is()`/`var()` 等を使ってよい）。
  - Kindle 向け調整は **`body.vs-kindle` セレクタ配下に、§2 の禁止機能を避けた具体値で**追記する。
- **テーマ色は「静的 CSS」でなく「生成 CSS」でリテラル化する**: テーマ色は book.yml 依存でビルドごとに変わるため、`body.vs-kindle` フォールバックに固定色を直書きすると**テーマに追従しない**（実際 `#b8860b`/`#888` がこの罠だった）。`BookSettingsCss#kindle_accent_rules` が、最後に読まれる生成 CSS `book-settings.css` へ**テーマ色を `ThemeColor` でリテラル hex 解決**して `body.vs-kindle` 規則を焼き、静的フォールバックを後勝ちで上書きする。KFX 非対応の `color-mix()` は `ThemeColor.mix_with_white` で事前計算する（`kindle-theme-color-literalize-spec.md`）。

### 5.2 「CSS で無理なら画像」戦略

Kindle で CSS による装飾が信頼できない箇所は、**合成画像に焼き込んで `<img>` 注入**するのが最も確実。

- 扉絵（h1）・節絵（h2）は `HeadingImageComposer` で「飾り画像＋見出し文字」を1枚に合成する。
  - クリーン EPUB: `HeadingImageComposer.compose`（**SVG**。Kobo/Apple は SVG を解すので高品質・検索可）
  - Kindle: `HeadingImageComposer.render`（**JPEG ラスタライズ**。CSS 非依存で確実）
  - 出し分けは `heading_image_src(..., flavor:)`。ハッシュ鍵に `flavor` を含めキャッシュを分離。
- 付録など simple スタイル見出しは CSS フォールバック（`simple-header.css` の `body.vs-kindle` 具体値）で表示する。同方式の SVG→JPEG 化を 2026-07-19 に一度実装したが「PDF ほど美しくならない」と判断され 2026-07-20 に revert（`kindle-simple-header-svg-spec.md`・再実装しない）。

### 5.3 クリーン EPUB を汚染しない（方式B）

- パイプライン（`pipeline.rb`）は、章 HTML を**スナップショット**してから `:epub` フレーバでビルドし、**スナップショットを復元**してから `:kindle` フレーバでビルドする。
- これにより Kindle 用の破壊的変換（WebP トランスコード・マーカー付与・装飾置換）がクリーン EPUB に混入しない。
- クリーン EPUB は WebP・SVG をそのまま活かした高品質版、Kindle は確実表示優先の劣化版、という役割分担を崩さない。

### 5.4 KPF 変換まわり

- `kindlepreviewer_available?`（`which` で存在確認）が false なら、中間 EPUB を残して変換をスキップし警告（ビルド自体は止めない）。
- `vs doctor` は `kindlepreviewer` を**任意ツールとして診断**する（導入済みは `✅`、未導入は 🟡 案内でハードエラーにはしない）。macOS では `vs doctor --fix` が Homebrew cask `kindle-previewer` を導入し、アプリ内 CLI を呼ぶラッパーを Homebrew の bin へ作成して PATH を通す。
- 表紙は `kindle.embed: false`（既定）。Kindle は本文に表紙を埋めると KDP 側表紙と二重化するため、表紙は KDP 管理画面でアップロードする運用。
- `vs doctor` は導入の有無に加えて、**版と実行環境**も見る。
  - **Previewer 3 のままなら 4 への更新を促す。** §5.5 のとおり版で判定が変わるので、読者と違う版で確かめても意味がない。更新すると 3 の実行ファイルが消えてラッパーが宙に浮くため、`vs doctor --fix` の再実行も併せて案内する。
  - **Apple Silicon で Rosetta 2 が無ければ導入を促す。** Previewer は外側だけが arm64 で、変換の実体は Intel のまま（4.0.1 実測: 実行ファイル 122 本中 114 本が x86_64 専用。`Server_KRF4`・同梱 JRE・`kindlegen`・`phantomjs`）。無いと `bad CPU type in executable` で KPF 変換だけが落ちる。導入は管理者権限を要するので `--fix` でも自動実行せず、コマンドだけ示す。

### 5.5 Kindle Previewer 4 は SVG を 1 枚でも許さない

**Previewer 4.0.1 は、同梱された SVG があると Enhanced Typesetting（ET）を無効にし、`.kpf` ではなく `.mobi` を出す。** 本文が参照しているかは問わない——`content.opf` の manifest に載っているだけで落ちる。

同一ファイルで版をまたいで測った結果（2026-09-22）。入力は 6 月に作った KPF から取り出した `book.epub` で、1 バイトも違わない。

| | Previewer 3（2026-06-18） | Previewer 4.0.1（2026-09-22） |
|---|---|---|
| Enhanced Typesetting | Supported | **Not Supported** |
| 出力 | `.kpf` | `.mobi` |

変換器に `com/amazon/language/resources/yjsvgtokvg/`（SVG → KVG＝Kindle Vector Graphics）が入っており、`SVG_PATH_PARSE_ERROR` などのエラー定義を持つ。ベクタのまま KFX へ持ち込む新機能で躓いたものが ET から外れる、という筋に見える（**変換ログには何も出ないので、ここは推測**）。

切り分けの実測値。spine を 1 章に固定し、要素を外しながら測った。

| 変えたこと | 結果 |
|---|---|
| CSS を全部外す / 埋め込みフォントを外す | Mobi |
| ラスタ画像だけ外す（SVG は残す） | Mobi |
| **SVG だけ外す（ラスタは残す）** | **KPF** |
| SVG を QR コード 1 枚だけにする | Mobi |

**ベクタで届いたことは一度もない。** Previewer 3 が作った KPF の中身は、SVG 82 枚を含む本でもリソース 57 件すべて JPEG だった。だからラスタ化しても読者が受け取るものは変わらない。変わるのは、焼く解像度を Previewer に委ねるか、こちらで決めるかだけである。

対処は 2 つに分かれる（`sweep_unreferenced_svg!` と `stage_author_svg_for_epub!`）。

- **参照されていない SVG を同梱しない。** 数式はディスプレイが PNG・インラインがテキストへ移った後も、SVG がパッケージに残っていた。実測で 102 枚中 **98 枚が孤児**（数式 58・twemoji 25・絵文字 13・その他 2）。落としても見た目は一切変わらない。
- **参照されている SVG は焼く。** 文字を持たない図（ロゴ・QR）は `DerivedSvg` が派生を作らないため素通りしていた。Kindle では原本をラスタ化する。

**空ディレクトリを残すと、変換そのものが失敗する。** SVG を外した跡に空のディレクトリが残ると、Previewer 4 は 1 秒で `Book Conversion failed` を返し、ログも出さない。epubcheck は `PKG-014` の**警告**で通してしまうので、検証を足しても気づけない（`prune_empty_dirs!`）。

**素の EPUB（表紙あり）は Previewer 4 で変換が止まる。** ET 経路に入ったあと 24 分間まったく進まず CPU も 0% だった。Kindle 経路には関わらないため未解明のまま。

---

## 6. 今後の開発ガイドライン（チェックリスト）

Kindle 向けに CSS / 画像処理を追加・変更するときは:

- [ ] その装飾は **`body.vs-kindle` 配下**に書いたか（クリーン EPUB/PDF を巻き込んでいないか）。
- [ ] `:is()` / `var()` / `calc()` / `clamp()` / `grid` / `linear-gradient` / `::before(position:absolute)` を**使っていない**か。
- [ ] 改ページは `page-break-before: always` を**併記**したか。
- [ ] 新規画像が WebP のまま Kindle に渡っていないか（トランスコード／除外の対象になっているか）。
- [ ] CSS で確実性が出ないなら、**画像化（合成 SVG→JPEG）**を検討したか。
- [ ] WebP を扱う正規表現は `/.../` リテラル・`[\w-]+`（プロパティ名を丸ごと）になっているか。
- [ ] フレーバ依存の除外/サニタイズは `flavor:` 引数で分岐し、クリーン EPUB を壊していないか。
- [ ] **Kindle パッケージに SVG を 1 枚も残していない**か（§5.5。参照の有無を問わず ET を失う）。
- [ ] **Kindle Previewer／実機**で表示確認したか（epubcheck 合格だけで判断しない。空ディレクトリのように、epubcheck が警告で通すのに Previewer が落ちる例がある）。

---

## 7. 参考

- `scripts/kfx_probe.rb` — §2 の対応表を測り直す検査スクリプト。Previewer の版が上がったら回す。
- `lib/vivlio_starter/cli/build/epub_builder.rb` — フレーバ分離・WebP 処理・マーカー・KPF 変換の実装本体。
- `lib/vivlio_starter/cli/build/heading_image_composer.rb` — 見出し合成画像（`compose`=SVG / `render`=JPEG）。
- `lib/vivlio_starter/cli/build/pipeline.rb` — スナップショット方式（方式B）とステップ登録。
- `stylesheets/chapter-common.css` / `components.css` / `simple-header.css` / `glossary.css` / `index.css` / `preface.css` / `code.css` — `body.vs-kindle` / `body.vs-epub` フォールバック。
- `epub-kindle-target-split-spec.md` — ターゲット分離の全体設計。
- `kindle-simple-header-svg-spec.md` — 付録見出しの SVG 画像化（実装したが却下）。
- `epub-code-line-numbers-spec.md` — コード行番号と Kindle テーブルの不具合（実装済み）。
