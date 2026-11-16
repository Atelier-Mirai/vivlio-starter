# S8 縦書きの小説の仕様（Fable への相談）

> 作成日: 2026-11-17
> ステータス: **相談中**（Fable の答え待ち）
> 出自: `v2-migration-plan.md` §2 の S8 は「小説の仕様（S8 の最初に書く）」とし、仕様はまだ無い。S6 の後半を進めている間に、Fable に設計を頼む（2026-11-17 ユーザー決定。Fable が使えるのは 11/17 の 17 時まで）

Fable のセッションに、次の「---」より下をそのまま渡す。

---

2.0 の S6（テーマの仕組みと `standard` の切り出し）が終わりに近づいています（S6-1〜S6-9 が完了。残りは S6-9b・S6-10）。その先の S8（縦書きの小説）は、`v2-migration-plan.md` §2 で「小説の仕様を S8 の最初に書く」としていますが、まだ書いていません。2.0 の 4 本の仕様書には、S8 に関わる決定と「小説の仕様で決める」と送った点が散らばっています。Fable が使える期間のうちに、小説の仕様の骨格（範囲・小段階・決めること）を決めてください。

これまでと同じく、設計のやり直しではありません。4 本の仕様書ですでに決まっていること（下の §1.2）は前提にして、送られてきた点と、まだ誰も決めていない点を決めてください。

コードの書き換えはしないでください。読む資料は次のとおりです。

1. `v2-architecture-spec.md` §2（本の種類と軸・`BookProfile`・`BookTraits`・組み合わせの検査・雛形）・§3.3（軸と機能で変わる段）・§6（技術書に寄った機能の切り替え）・§7.1（記法の型と 2.0 に含める 5 件の割り当て）・§8 の S5（決め 1〜6）と S8・§9（論点 2）
2. `theme-contract-spec.md` §2.5（2.0 で足す部品）・§3（テーマの形。とくに §3.4 の機能と §3.5 の Kindle の範囲）・§4（標準のテーマ・部品に残す飾り）・§6.4（小説の既定のテーマは vs が書く）・§10（論点 1・4・5）
3. `css-layer-restructure-spec.md` §6（縦書きに向けた物理方向の扱い）・§9（論点 2）
4. `v2-migration-plan.md` §2（段階の順序と S7・S8 の関係）・§3（共通の確かめ方）・§4.1（基準の版・r3）・§7（論点 1: 途中の版を配るか）
5. `v2-design-research-brief.md` §5（ユーザーの判断。目指す紙面と 2.0 に含める 5 件）
6. `v2-feasibility-notes.md` §3（縦書きの実験: Vivliostyle の PDF と Kindle）
7. `v2-inventory-report.md` §3（横書きの前提の棚卸し）
8. `furigana-level-spec.md`（`vs furigana` の対象の水準）・`PLANNED.md` の「Version 2.0 構想」と `vs furigana` の項・「くるみ表紙」「背表紙を作る」の項
9. `v2-s6-10-consultation.md` §4.3（改ページを公開する変数で読む決定。`bunko` の節の改ページの既定を S8 へ送った）
10. 実物: `config/page_presets.yml`（判型のプリセット）・`stylesheets/parts/prose.css`（段落の字下げ）・`lib/vivlio_starter/cli/lint/rulesets.rb`（規則の組）・`lib/vivlio_starter/cli/book_traits.rb`・`lib/vivlio_starter/cli/book_profile.rb`・`themes/standard/theme.yml`
11. 公式テーマ（`@vivliostyle/theme-bunko` 3.1.0・`@vivliostyle/theme-epub3j`）の実物は、リポジトリに置いていません。読む場合は、scratchpad で `npm pack` して展開してください（スクリプトは実行しない。`v2-inventory-report.md` §7 と同じ）。

## 1. 今の状態

### 1.1 S8 の前に済むもの

| 項目 | S8 に入る時点で |
| :--- | :--- |
| 軸 | `book.type`・`page.writing_mode`・`page.layout` のキー、`BookTraits`（`vertical?`・`binding`・`recto_side`）、`BookProfile::PROFILES` の `novel` の行（S5）。`novel` の行には `theme.name` と `page.use` がまだ無い（S5 の決め 1） |
| 縦書きの経路 | `vivliostyle.config.js` の `readingProgression` と、隠しノンブルの左右だけが `traits` を読む（S5）。本文は横組みのまま。`standard` は `supports.writing_mode: [horizontal]` なので、縦書きの本は §2.5 の検査で 🔴 で止まる（S6-3 から） |
| テーマ | `themes/standard/`（`options:`・`features: [frontispiece, ornament]`・`styles:`・出力先の CSS）。テーマを読む仕組み・`extends:`・`kindle_tokens:`・`vs theme:*` のコマンド・`vs upgrade` の扱い（S6）。改ページは公開する変数 `--book-section-break-before` などで読む（S6-9b） |
| 公開する変数 | `--book-*`（`stylesheets/tokens.css` が正典。`standard` の `tokens:` は空） |
| 機能のキー | `lint.ruleset`（`novel` は今 `minimal` と同じ中身）・`metrics.use: none`・`notation.web_novel`（キーと `BuildPlan.features.web_novel` だけ。読む段は無い）（S5） |
| 基準 | r3（S6 の完了の後、S7 の前に作る）。本書（技術書）の出力の基準で、小説の出力の基準は無い |
| S7 | 公式テーマの取り込み。入口の実験が `theme-bunko` を vs の HTML に当てる。S7 と S8 は入れ替えてよい（`v2-migration-plan.md` §2） |

### 1.2 S8 についてすでに決まっていること（蒸し返さない）

- 小説も `pdf`・`print_pdf`・`epub`・`kindle` の四つで出す。目指す紙面は Vivliostyle の公式の縦書きの作例（「銀河鉄道の夜」）に、ときどき挿絵を入れた形（brief §5）。
- 小説の既定のテーマは vs が `theme-contract-spec.md` §3.5 の範囲の CSS で書く。手本は `theme-bunko` と `theme-epub3j`（どちらも CC0-1.0）。挿絵の `figure` と余白の箱は `writing-mode: horizontal-tb`（§6.4）。
- `BookProfile` の `novel` の既定値は、`writing_mode: vertical`・`heading_numbering: none`・`index_glossary.enabled: false`・`lint.ruleset: novel`・`metrics.use: none`・`notation.web_novel: true`。`theme.name` と `page.use` の値は小説の仕様で決める（architecture §2.2・§9 の論点 2）。
- コードは `book.type` を読まない。分岐は軸か機能のキーで書く（architecture §2.3）。縦中横の自動は「組方向が縦なら」で入れる。
- 2.0 に含める 5 件の型と入れる場所（architecture §7.1 の表）。傍点 `[文字]{.sesame}`・縦中横 `[12]{.tcy}`（D 型の行内の属性）、縦中横の自動（L3 の後処理・`traits.vertical?`）、投稿サイトの記法（前処理 `transform_web_novel_marks!`・`vs import` にしない）、小説の lint（`lint.ruleset: novel`）、`vs furigana`（原稿を書き換えるコマンド）、背表紙とくるみ表紙（`build cover spread` の段・紙の厚さを `book.yml` のキーに）。
- クラス名 `tcy`・`sesame` は `vs-` を付けない（theme §2.5）。
- 物理方向の 72 か所は、S8 で、縦書きの本が読む部品について論理方向へ直す。横書きでは結果が同じなので、本書の画素が変わらないことを S8 の確かめにする（css-layer §6）。
- 雛形は `scaffolds/novel/`（それ自体が組める本）。`vs new mybook --type novel`（architecture §2.6）。
- 行内の属性の記法（D 型）は、master の 1.1.0 で「文字の色を変えるインライン記法」として作られていればマージで受け、無ければ S8 で `v2` に作る（`v2-migration-plan.md` §6.3）。

## 2. 問い

### 2.1 S8 の範囲・小段階・S7 との順

S8 は、縦組みの本文（テーマと部品）と、2.0 に含める 5 件の全部を抱えています。5 件のうち `vs furigana` と背表紙・くるみ表紙は、縦書きと独立に作れます（`vs furigana` は絵本でも使う。背表紙は技術書の分冊でも要望がある）。

決めてほしいこと:

1. S8 の小段階の表（`theme-contract-spec.md` §9 の S6 の表と同じ「小段階・作るもの・確かめ」の 3 列）。S6 と同じく、各小段階の完了のコミットが本書（技術書）の出力を r3 と同じに保つかどうかも、小段階ごとに書いてください（物理方向の書き直しは画素が変わらないはず、`bunko` の追加は本書に触れないはず、など）。
2. 5 件のうち、S8 から外して別の段階（S8 の後・S9 の中・S11 の前など）に回すものがあるか。
3. S7 と S8 の順。S7 の入口の実験（`theme-bunko` を vs の HTML に当てる）の結果は、`bunko` を書くときの手本の読み方に役立つ一方、S8 を止めないと決めてあります。どちらを先にするか。

### 2.2 小説の既定のテーマ（`theme-contract-spec.md` §10 の論点 1・4・5）

1. **名前。** 仮の名前は `bunko`。公式の `theme-bunko` を取り込んだテーマ（S7 で `vs theme:add @vivliostyle/theme-bunko` が作るもの）と、本の `themes/` の中で名前がぶつかります（取り込んだ側のディレクトリの名前は `theme.yml` の `name:` から決まる。S6-8 の `theme:add` の決め）。
2. **中身。** `styles:` の CSS の分け方、`options:`（著者が `book.yml` の `theme:` で変えられる項目。たとえば章扉の形・柱の有無・段落の字下げ）、`features:`（`frontispiece`・`ornament` は使わない見込み。小説に要る組み込みの機能があるか。挿絵の配置などを機能として足すか）、`supports:`（`writing_mode: [vertical]` だけか、横書きの小説にも対応するか）、`tokens:`（`standard` との値の違い。§4 の「中立の既定値と `standard` の値を分けるのは、2 つ目の組版のテーマが値を決めるとき」の決め）。
3. **部品の扱い（論点 5）。** vs の部品（`parts` 層。見出し・段落・囲み・コード・表・脚注・相互参照など）のうち、小説の本が読むもの。縦書きで崩れる部品を「直す」「`bunko` で打ち消す」「`standard` へ移す」「縦書きでは使えないとして lint か検査で知らせる」のどれにするか。`parts/preface.css` が `standard` へ移すいちばんの候補とされています。
4. **ページの種類。** 縦書きで、目次・奥付・本扉・権利ページ・部扉・前書き・後書きを、どう組むか（縦か横か）。索引と用語集は `novel` では無効だが、著者が有効にした場合の扱い（縦書きの索引を作るか、🔴/🟡 で止めるか）。
5. **節の改ページの既定**（`v2-s6-10-consultation.md` §4.3 から送られた点）。小説は節で改ページしないのが普通です。`bunko` の `tokens:` に `section-break-before: auto` を書くと、雛形の `book.yml` の `page.section_pagebreak: true`（今の決まりでは何も書き出さない）が効かなくなります。`BookProfile` の `novel` で `section_pagebreak: false` を既定にするか、`true` のときも値を書き出すように決まりを変えるか、など。
6. **`theme-epub3j` を土台にしたテーマを同梱するか（論点 4）。** 電書協の様式を求める著者向け。

### 2.3 判型のプリセット（`v2-architecture-spec.md` §9 の論点 2）

今の `config/page_presets.yml` は、A5・B5・A4 のそれぞれに `standard`・`airy`・`compact`・`custom` を持ち、値は基準の字の大きさ・行送り・字間・天地ノド小口の余白です。文庫・新書・四六・B6 は無く、`BookProfile` の `novel` の `page.use: a6_standard` は形を示すための仮の値です。`theme-bunko` は、判型を行数と字数から `calc()` で求めます（`theme-contract-spec.md` §6.1）。

決めてほしいこと:

1. 小説のために足すプリセット（判型と名前）と、`novel` の既定。
2. 縦書きの版面を、今の形（字の大きさ・行送り・余白）で決めるか、行数と字数で決める形を足すか。足す場合のキーの形と、`page_presets.yml` との関係（横書きの技術書にも開くか）。
3. 余白の名前。今の `margin_top`・`margin_bottom`・`margin_inner`・`margin_outer`（天・地・ノド・小口）は、縦書きでもそのまま意味が通るか。

### 2.4 縦書きの記法の細目

1. **縦中横の自動。** architecture §7.1 は「本文の中の半角の数字 1〜2 桁と `!?`・`!!` を `span.tcy` で包む。桁数の上限と対象の字は小説の仕様で確定する」としています。桁数の上限（3 桁・4 桁の西暦をどうするか）・対象の字（`!?`・`!!`・`??`・全角の数字・英字の略語）・除外（コード・数式・ルビの読み・`span.tcy` の中・URL・見出しの番号）。全角の数字を本文で使うか半角に寄せるかの表記の方針（lint で扱うか）も含めて。
2. **投稿サイトの記法の範囲。** 受けるのは `|漢字《かんじ》`（縦棒あり）と傍点 `《《…》》` と決まっています。縦棒の無い `漢字《かんじ》`（直前の漢字の並びに掛かる）、`（かんじ）` を使うルビ、なろうの傍点の書き方（ルビに `・` を並べる）、全角の縦棒 `｜` を受けるか。vs の今の記法（`{漢字|かんじ}`・`[用語]` の索引・`《` を地の文に書く場合）とぶつかる場合の扱い。
3. **小説の lint の 4 規則の向き。** とくに「段落の頭を字下げする」。vs は CSS で段落の頭を 1 字下げる（`parts/prose.css` の `p { text-indent: 1em; }`）ので、原稿に全角空白を書くと 2 字下がります。一方、投稿サイトの原稿は全角空白で字下げしてあり、会話文（`「` で始まる段落）は字下げしないのが慣習です。lint が「全角空白が無いこと」を見るのか「あること」を見るのか、会話文の段落の字下げを CSS とテーマでどう扱うか（`theme-bunko` は `「` で始まる段落の字下げをどうしているか）、投稿サイトの記法を読む前処理が先頭の全角空白を落とすか、を一緒に決めてください。残りの 3 規則（「……」「――」の二つ重ね・「！」「？」の後の全角空白・閉じ括弧の前の句点）の誤検出を避ける条件（文末の `！」` や、`？` の直後が閉じ括弧のとき）も。

### 2.5 `vs furigana`

`furigana-level-spec.md` は対象の水準（L0〜L4・学年）だけを決め、読みの生成は「`vs furigana` の仕様書で決める」としています。`PLANNED.md` の項に、半自動にする理由（MeCab が稀な漢字ほど誤読する）・補助辞書の種（交ぜ書き辞書から表外漢字の読み 125 字）・安全性（二重化しない・`--dry-run`・退避）が書かれています。

決めてほしいこと:

1. S8 で作るか、別の段階か（§2.1 の 2）。
2. 作る時期に関わらず、仕様書を別に立てるか、小説の仕様の 1 節にするか。
3. 骨格: 基準の水準の指定（`book.yml` のキーか引数か）・読みの出どころの順（MeCab・補助辞書・著者の辞書）・語単位か字単位か・初出だけに振るか全部に振るか（章ごとの初出など）・確かめの一覧の形（`vs index:auto` のようなレビューのファイルにするか）。

### 2.6 背表紙とくるみ表紙

今の表紙は `covers/` の表 1（表紙）・表 4（裏表紙）の画像か、テンプレートから作る SVG で、巻ごとに作れます（`cover_spec.md`・`cover_auto_generation_spec.md`・分冊は `multivolume-spec.md`）。背表紙を作る機能は無く、くるみ表紙（表 4＋背＋表 1 を 1 枚に）も非対応です（`PLANNED.md`）。architecture §7.1 は「`build cover spread` の段・背幅はページ数と紙の厚さから求める・紙の厚さは `book.yml` のキー・個別の仕様で決める」としています。

決めてほしいこと:

1. S8 で作るか、別の段階か（§2.1 の 2）。仕様書を別に立てるか。
2. 骨格: 出力の形（くるみ表紙を `print_pdf` と一緒に出すか、別の出力先・別のコマンドにするか）・背幅の求め方（ページ数 × 紙の厚さ＋表紙の厚さ。入稿先ごとの値を著者が書く形）・塗り足しと背の文字（縦書きの書名と著者名）・右綴じの並び（表 1 が右）・分冊。
3. 技術書（横書き・左綴じ）でも使えるようにするか。

### 2.7 確かめ方

技術書の段階は、本書の出力を基準と比べることで完了を確かめてきました。小説には基準がありません。

決めてほしいこと:

1. S8 の完了の条件（architecture §8 の S8 は「`scaffolds/novel/` の本が四つの出力先で組め、Kindle が KPF になる（Enhanced Typesetting が Supported）。紙面の条件は小説の仕様に書く」）の「紙面の条件」の中身。何を見て「組めた」とするか（目で見る箇所の一覧・Vivliostyle の作例との見比べ・`pdftotext` や画素での検査など）。
2. 小説の基準を作るか。作るなら、何を（`scaffolds/novel/` の本の四つの出力先）・いつ（S8 のどの小段階の後）。S9 以降に小説の出力を守る手段になる。
3. `scaffolds/novel/` の本の原稿。著作権の切れた作品（青空文庫）を使うか、架空の短い原稿を書くか。挿絵・ルビ・傍点・縦中横・会話文・投稿サイトの記法・前書きと後書きを含める範囲。
4. 本書（技術書）の出力を守る確かめ（物理方向の書き直しなど）を、どの小段階で r3 と比べるか。

### 2.8 その他（あれば）

`PLANNED.md` の「小説（挿絵入り）への対応」は、「小説など特定の書体を厳密に保ちたい用途に向けたフォント埋め込みオプションを `config/book.yml` に追加する」も挙げています。S8 に含めるか、2.0 の後へ回すか。ほかにも、小説の仕様に要るのに上の問いに無いもの（脚注を縦書きでどう組むか・ノンブルや柱を漢数字にするか・章題の書き方・挿絵の記法など）があれば、挙げて決めてください。

## 3. 答えの形

- §2 の各問いの決定と理由を、`v2-s6-consultation.md` §4 と同じく、この文書の末尾に「答え」の節として書く。
- 答えは、小説の仕様書（新しい文書。名前は Fable が決める。案は `novel-vertical-spec.md`）の骨格として、Opus がそのまま節へ移せる形にする。仕様書に入れる節の並び（目次）を最初に示し、各決定がどの節に入るかを書く。
- §2.1 の小段階の表は、`theme-contract-spec.md` §9 の S6 の小段階の表と同じ形で書く。
- 決めるのに確かめが要る点（たとえば Kindle での縦中横の自動の結果・`theme-bunko` の会話文の字下げ）は、Fable が scratchpad で確かめてよい。確かめられなかった点は、確かめる内容と、結果ごとの手を書く（確かめは Opus が S8 の中で行う）。
- 今決めずに S8 の実装の中で決めてよい点は、そう書いて、決めるときの判断の軸を添える。
- 決定を移す先（新しい仕様書のほか、4 本の仕様書の節・`PLANNED.md`）を挙げる（移すのは Opus が行う）。
