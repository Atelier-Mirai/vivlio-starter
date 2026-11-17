# S9 絵本（固定レイアウト）と S10 動く絵本の仕様（Fable への相談）

> 作成日: 2026-11-17
> ステータス: **答え済み**（§4。2026-11-17・Fable。仕様書への反映は Opus が S9 の最初に行う）
> 出自: `v2-migration-plan.md` §2 の S9 は「絵本の仕様（S9 の最初に書く）」、S10 は「動く絵本の仕様」とし、どちらもまだ無い。S6 の後半を進めている間に、Fable に設計を頼む（2026-11-17 ユーザー決定。Fable が使えるのは 11/17 の 17 時まで。相談文 4 本のうちの 3 本目）

Fable のセッションに、次の「---」より下をそのまま渡す。

---

2.0 の S6（テーマの仕組みと `standard` の切り出し）が終わりに近づいています。その先の S8（縦書きの小説）は、さきほどの相談で骨格が決まりました（`v2-s8-novel-consultation.md` §4）。続く S9（絵本・固定レイアウト）と S10（動く絵本・動画）は、`v2-migration-plan.md` §2 で「絵本の仕様を S9 の最初に書く」「動く絵本の仕様」としていますが、まだ書いていません。

S9 は、vs に「固定レイアウト」という新しい出力の経路を足す段階です。原稿の単位が章からページに変わり、EPUB を Vivliostyle ではなく vs が梱包し、Kindle は KPF にせず EPUB のまま出します。4 本の仕様書には枠だけが決めてあり（下の §1.2）、中身は「絵本の仕様で決める」と送ってあります。Fable が使える期間のうちに、絵本の仕様の骨格（範囲・小段階・決めること）と、動く絵本の仕様の骨組みを決めてください。

これまでと同じく、設計のやり直しではありません。すでに決まっていること（§1.2）は前提にして、送られてきた点と、まだ誰も決めていない点（§1.3）を決めてください。S10 は S9 の後なので、骨組み（範囲・小段階・S9 のうちに決めておくべきこと）までで構いません。

コードの書き換えはしないでください。読む資料は次のとおりです。

1. `v2-architecture-spec.md` §2.1〜§2.5（軸・`BookProfile`・`BookTraits`・組み合わせの検査）・§3.1（五つの層と契約 HTML）・§3.3（軸と機能で変わる段。`build page spreads` と `build cover spread`）・§3.5（固定レイアウトの経路）・§4.1・§4.2（`OutputTarget` と、固定レイアウトの二行）・§4.5（動画）・§4.6（Web 出力は作らない）・§8 の S9・S10・§9（論点 1・2・4）・§10.5 の「仕様と違えたこと」の 4（`OutputTarget.for(id, traits)` を S9 で足す）
2. `theme-contract-spec.md` §2.7（固定レイアウトの契約 HTML・枠だけ）・§3（テーマの形。とくに §3.4 の機能と、テーマの `supports.layout`）・§6.4（小説と絵本の既定のテーマは vs が書く）・§10（論点 1）と、§11.6（S6-3 の実装記録）の「仕様と違えたこと」の 4（固定レイアウトの本ではレイアウトの `supports:` を見ない。S9 で働く）
3. `v2-migration-plan.md` §2（段階の順序）・§3（共通の確かめ方・基準の版）・§7（論点 3: KDP が固定レイアウトの EPUB を受け付けるか）
4. `v2-feasibility-notes.md` §0・§4（固定レイアウトの EPUB の実験と、KDP へ出すファイルの形式）・§5（動画の実験・動画の形式・EPUB の大きさの上限）
5. `v2-design-research-brief.md` §5（ユーザーの判断。三つの本の種類の順・動画の代わりの表現・Web アプリとしての配布）
6. `kindle-fixed-layout-ideas.md`（技術書を PDF の画像にして固定レイアウトにする案を見送った記録。端末の大きさの表と、固定レイアウトの EPUB の実装の素描）
7. `v2-s8-novel-consultation.md` §4（S8 の答え。とくに §4.3 の小段階・S8b と S8c の位置・§4.7 の挿絵の記法 `figure.vs-full-page`・§4.10 のくるみ表紙・§4.11 の雛形と基準 N1）
8. `PLANNED.md` の「Version 2.0 構想」（絵本・動く絵本の項）
9. 実物: `lib/vivlio_starter/cli/book_traits.rb`（`fixed?`・`unit`）・`lib/vivlio_starter/cli/book_profile.rb`（`picture_book` の行）・`lib/vivlio_starter/cli/guards/trait_combination_check.rb`（固定レイアウトを 🔴 で止める行）・`lib/vivlio_starter/cli/build/output_target.rb` と `build/targets/*.rb`（出力先の宣言）・`lib/vivlio_starter/cli/build/epub_flow.rb`・`lib/vivlio_starter/cli/build/plan.rb`（`BuildPlan`）・`lib/vivlio_starter/cli/build/pipeline.rb` の `full_mode_step_table`・`lib/vivlio_starter/cli/build/print_pdf_builder.rb`（導出と組み直しの二つの経路・`output.print_pdf.full_bleed`）・`lib/vivlio_starter/cli/build/cmyk_converter.rb`（表紙だけの CMYK 化）・`themes/standard/theme.yml`

## 1. 今の状態

### 1.1 S9 の前に済むもの

| 項目 | S9 に入る時点で |
| :--- | :--- |
| 軸 | `page.layout`（`reflowable`・`fixed`）、`BookTraits#fixed?`・`#unit`（`:page`）、`BookProfile::PROFILES` の `picture_book`（`page.layout: fixed`・`heading_numbering: none`・`index_glossary.enabled: false`・`lint.ruleset: minimal`・`metrics.use: none`。`theme.name` と `page.use` はまだ無い）（S5） |
| 止めているもの | `Guards::TraitCombinationCheck` が `page.layout: fixed` を 🔴 で止める（「この版ではまだ組めません」。`book.type: picture_book` もここで止まる）。S9 で外すと、`page.layout: fixed` と `index_glossary.enabled: true` の 🟡 と、テーマの `supports.layout` の検査が働きだす（S5-2・S6-3） |
| 段の表 | `BuildPlan`（`targets`・`traits`・`features`）を開始時に一度作り、`full_mode_step_table` の条件の列は `plan` だけを読む。§3.3 の表の `!traits.fixed?` の条件と、新しい段 `build page spreads`・`build cover spread` はまだ無い（S5-3） |
| 出力先の宣言 | `OutputTarget`（`transforms`・`css_form`・`finalizers`・`assets`・`packager`）と、四つの出力先の宣言。`OutputTarget.for(id)` はまだ `traits` を受けない（S5-3 で、読む箇所が無いので S9 に送った）。`packager` は `:vivliostyle_epub`・`:vivliostyle_epub_to_kpf` など（S4） |
| テーマ | テーマの形（`supports:`・`features:`・`options:`・`tokens:`・`kindle_tokens:`）と、テーマを読む仕組み・`vs theme:*` のコマンド（S6）。同梱は `standard`（`supports.layout: [reflowable]`）と、S8 で足す `novel` |
| S8 から来るもの | 全面の挿絵 `figure.vs-full-page`（S8-2 でクラス名を決める）・判型のプリセットの足し方（S8-3）・縦書きの経路（S8-4）・`scaffolds/<種類>/` と `vs new --type`（S8-7）・小説の基準 N1 と基準の版 r4（S8-7）。S8b（背表紙とくるみ表紙）と S8c（`vs furigana`）は S9 と入れ替えてよく、S11 の前に終える |
| 入稿用 PDF | 既定は閲覧用 PDF からの導出。`output.print_pdf.full_bleed: true` の本（塗り足しまで届く要素がある本）は組み直す。CMYK への変換（`CmykConverter`）は表紙だけで、本文の画像は RGB のまま |

### 1.2 S9・S10 についてすでに決まっていること（蒸し返さない）

- 絵本も動く絵本も `pdf`・`print_pdf`・`epub`・`kindle` の四つで出す（brief §5）。動く絵本は種類にしない。`picture_book` に動画の記法を使った本である（architecture §2.1）。
- 固定レイアウトの経路（architecture §3.5）: L1 は「ページの並び」を返す。L2・L3 は `build page spreads` の段で、ページごとに寸法の決まった 1 枚の HTML を作る。契約 HTML は、`body` に `vs-fixed` とページの種類のクラス、`head` にページの寸法の `viewport`（theme §2.7）。L4 は同じ仕組みで、変換の並びが固定レイアウト用。L5 の PDF は Vivliostyle（判型＝ページの寸法）、EPUB は vs が自分で梱包する。章の番号の範囲（`00`・`01–89`・`90–98`・`99`）は固定レイアウトに持ち込まない。
- 出力先（architecture §4.2）: `epub`（固定）は JPEG・PNG・WebP と `<video>`、vs が梱包。`kindle`（固定）は JPEG・PNG・動画はサムネイルに動画へのリンク、vs が梱包して **KPF にせず EPUB を出す**（`<名前>-kindle.epub`。KDP へはこの EPUB を出す）。固定レイアウトの `finalizers` は S9 で決める。`OutputTarget.for(id, traits)` が、リフローと固定レイアウトで別の宣言を返す（§4.1）。
- 固定レイアウトの EPUB は Kindle Previewer で KPF にできない（4 版とも Mobi になる。Enhanced Typesetting はリフロー型だけ）。KDP は固定レイアウトの本を EPUB で受け付ける。vs の作る EPUB を KDP が受け付けて正しく表示するかは未確認で、**S9 の最初に、最小の絵本の EPUB を作り、ユーザーが KDP のプレビューで確かめる**。通らない場合は、絵本の `kindle` を 2.0 の対象から外すか、Kindle Create で手で作る手順を案内するかを、ユーザーが決める（architecture §9 の論点 1・migration §7 の論点 3）。
- 動画（architecture §4.5）: 契約 HTML は `figure.vs-video > video[src][poster][controls][data-vs-url]` と `figcaption`。`epub` は `<video>` を残し、中に代わりの表示（ポスター画像と、`data-vs-url` があればリンク）。`pdf`・`kindle` はポスター画像に置き換えてリンクを張る。`print_pdf` はポスター画像に QR コード（既存の `QrTransformer`）。動画のある本は `print_pdf` を導出せず組み直す。`data-vs-url` の無い動画は 🟡。EPUB が 100 MB を超えたら 🟡。ポスター画像を切り出すか著者が用意するかは、動く絵本の仕様で決める。
- 動画の実験（feasibility §5）: Kindle Previewer は `<video>` をエラーにする。Apple Books は H.264 と HEVC を再生する（リフロー型・固定レイアウトとも）。Kobo は iOS と Android のアプリだけ。複数のリーダーに出すなら H.264。
- Web 出力（PWA）は 2.0 では作らない（architecture §4.6）。
- 絵本の既定のテーマは vs が `theme-contract-spec.md` §3.5 の範囲の CSS で書く（theme §6.4）。名前は仮に `picture`（theme §10 の論点 1）。
- `book.type`・`page.layout` は本全体で一つで、分冊の巻ごとには変えない（architecture §5.4）。

### 1.3 決まっていない点・気づいた食い違い

1. **原稿の形**（architecture §9 の論点 4）: 1 ファイルに複数ページか、1 ファイル 1 ページか。ページの中の文字の置き方の記法。`catalog.yml` の形をどう使うか（今は章の番号の範囲で前書き・本文・付録・後書きを分ける）。
2. **ページの寸法と画像の解像度**: 判型（PDF の mm）と `viewport`（EPUB の px）と画像の画素数の関係。feasibility §4 の実験は 1200 × 1600 px。印刷の解像度（350 dpi 前後）で A5 の全面の画像は約 2000 × 2900 px で、Kobo の 100 MB と KDP の配信のコストに響く。画像を出力先ごとに縮めるか（今のリフローの経路は、Kindle で長辺 1024 px・クリーン EPUB で 2048 px に縮める）。
3. **見開き**: 絵本は見開きで 1 枚の絵を置くことが多い。EPUB の `rendition:spread`・`page-spread-left/right`、PDF の見開きの扱い、入稿用 PDF（単ページで出す）で絵を左右に分けるか。綴じの向き（横書きの左綴じ・縦書きの右綴じ）との組み合わせ。日本の絵本は縦書き・右綴じも横書き・左綴じもある。
4. **画像に重ねる文字**: 文字を画像に焼き込むか（コミックの形）、実体の文字として重ねるか（`position: absolute`）。Kindle の固定レイアウトでの文字の拡大（Amazon の指針の `RegionMagnification`）。読み上げ・検索・振り仮名（S8c の `vs furigana` は子ども向けの絵本でも使う、brief §5）との関係。
5. **前処理と後処理**: §3.3 の表は `preprocess sections` と `convert sections html` を `!traits.fixed?` で止め、`build page spreads` に替えるとしている。ページの中の文字に、ルビ・傍点・縦中横・`vs furigana` の結果などの vs の記法を使えるようにするなら、前処理と VFM をページの文字にも通すことになる。どこまでの記法をページで使えるか。
6. **固定レイアウトの EPUB の梱包**: vs が自分で作る EPUB の中身（OPF のメタデータ・`nav`・表紙・ページごとの XHTML・画像）。Amazon の固定レイアウトの指針（`fixed-layout`・`original-resolution`・`book-type`・`orientation-lock`・`primary-writing-mode`）と、Apple Books・Kobo の求めるもの。EPUBCheck の扱い。`epub` と `kindle` で中身を分けるか（WebP と動画の有無だけか）。
7. **入稿用 PDF**: 絵本は全面の絵がほとんどで、`full_bleed` の経路（組み直し）になる。絵の塗り足し（3mm）を著者に用意させるか、vs が絵を拡大するか。本文の画像の CMYK への変換は今は無い。印刷所に RGB の PDF を出す前提でよいか、絵本では本文の画像も CMYK にするか。
8. **表紙**: 絵本では表紙も絵である。今の `covers/` の仕組み（表 1・表 4 の画像か、テンプレートから作る SVG）と、ページの並びの最初の 1 枚を表紙にする形のどちらにするか。S8b のくるみ表紙（ページ数が少ないので背幅が小さい。上製本の絵本は背幅を印刷所が決める）との関係。
9. **テーマ**: 絵本の既定のテーマの名前（`picture` は仮）と中身（ページの種類・文字の箱の形・`options:`・`features:`・`supports.layout: [fixed]`）。リフローのテーマ（`standard`・`novel`）を固定レイアウトの本で選んだときの扱い（`supports.layout` の検査で 🔴 になる）。
10. **段の表**: 固定レイアウトの本で走る段と止める段の一覧。目次（`generate toc html` を止め、EPUB の `nav` だけ）・前付と奥付（固定レイアウトの本の奥付をどう作るか。最後のページに置くか）・`techbook post-process`（PDF の書体の対策）・`check chapter leads`・`vs preflight`・`vs lint`（ページの文字に掛けるか）。
11. **S9 の入口の確かめ**: KDP のプレビューで確かめる「最小の絵本の EPUB」の中身（何ページ・見開き・重ねる文字・振り仮名・表紙）と、ユーザーが見る箇所。その EPUB を、S9 の実装の前に手で作るか、S9 の最初の小段階の出力にするか。
12. **S8b・S8c との順**: `vs furigana`（S8c）は子ども向けの絵本でいちばん要る。S9 の前に作るか、後でよいか。
13. **動く絵本（S10）**: 動画は絵本だけのものか、リフローの本（技術書の操作の動画・小説）でも使えるようにするか（architecture §4.5 は種類に依らない書き方をしている）。動画の記法の型（`notation-implementation-guide.md` の型のどれか）。ポスター画像の出どころ（切り出すなら ffmpeg が要る。feasibility §5 の試験の動画は macOS の AVFoundation で書いた）。動画の置き場（`videos/`）と形式の検査（H.264 以外を 🟡 にするか）。固定レイアウトのページいっぱいの動画・自動再生・繰り返し。`print_pdf` の QR コードのために `data-vs-url` を必須にするか。

## 2. 問い

### 2.1 S9 の範囲・小段階・入口の確かめ

1. S9 の小段階の表（`theme-contract-spec.md` §9 の S6 の表・`v2-s8-novel-consultation.md` §4.3 と同じ「小段階・作るもの・確かめ」の 3 列）。各小段階の完了のコミットが、本書（技術書）と小説（N1）の出力を、その時点の基準と同じに保つかどうかも、小段階ごとに書いてください。固定レイアウトは別の経路なので、リフローの本に触れない小段階が多いはずです。触れるもの（`OutputTarget.for(id, traits)`・段の表の条件・`TraitCombinationCheck`・EPUB の梱包の共通の部分）を明らかにしてください。
2. S9 の入口の確かめ（§1.3 の 11）。KDP のプレビューで見る EPUB の中身と、ユーザーが見る箇所。通らなかったときに、2.0 の範囲をどう変えるか（絵本の `kindle` を外す・Kindle Create の手順を案内する）を、ユーザーが決めやすい形で示してください。
3. S8b・S8c と S9 の順（§1.3 の 12）。

### 2.2 原稿の形とページの記法（architecture §9 の論点 4・§1.3 の 1・5）

1. 原稿の形。1 ファイルに複数ページ（ページの区切りの記法）か、1 ファイル 1 ページか。`contents/` と `catalog.yml` をどう使うか。前付（本扉・権利ページ）と奥付をページの並びのどこに置き、誰が作るか。
2. ページの中の要素と記法。全面の絵・見開きの絵・絵に重ねる文字の箱（位置と大きさの指定の仕方）・文字だけのページ・動画（S10）。記法の型（`notation-implementation-guide.md`）のどれに載せるか。契約 HTML の要素とクラス（theme §2.7 の「絵本の仕様で決め、契約の表に足す」）。
3. ページの文字に通す vs の記法の範囲（ルビ・傍点・縦中横・強調・改行）と、前処理と VFM の通し方（§1.3 の 5）。
4. 画像に重ねる文字を、実体の文字にするか、画像に焼き込むか（§1.3 の 4）。

### 2.3 ページの寸法・画像・見開き（§1.3 の 2・3）

1. 判型（mm）・`viewport`（px）・画像の画素数の決め方。判型のプリセット（S8-3 で足す形）に絵本の判型を足すか。絵本の既定の判型。
2. 出力先ごとの画像の大きさ（`assets` の方針）。Kobo の 100 MB と KDP の配信のコストに対する扱い（🟡 の閾値・自動で縮めるか）。
3. 見開きの扱い（EPUB・PDF・入稿用 PDF）と、綴じの向き（`traits.binding`）との組み合わせ。縦書きの絵本（`page.writing_mode: vertical` × `page.layout: fixed`）を 2.0 で扱うか。

### 2.4 出力先ごとの組み方（§1.3 の 6・7・8・10）

1. 固定レイアウトの `OutputTarget` の宣言（`transforms`・`css_form`・`finalizers`・`assets`・`packager`）を、四つの出力先それぞれについて。`OutputTarget.for(id, traits)` の形。
2. vs が作る固定レイアウトの EPUB の中身（OPF・`nav`・表紙・ページの XHTML）と、`epub` と `kindle` の違い。Amazon・Apple Books・Kobo の指針のうち、どれに合わせるか。
3. 入稿用 PDF（塗り足し・CMYK・見開き）と、閲覧用 PDF（見開きで見せるか）。
4. 表紙（§1.3 の 8）。
5. 固定レイアウトの本の段の表（走る段・止める段・新しい段）。`vs preflight`・`vs lint`・`vs metrics` の扱い。

### 2.5 絵本の既定のテーマ（theme §10 の論点 1・§1.3 の 9）

名前・中身（CSS の分け方・`options:`・`features:`・`supports:`・`tokens:`）・ページの種類のクラスと、テーマが書く範囲（vs の CSS が書く範囲）。リフローのテーマを選んだときの扱い。

### 2.6 確かめ方

1. S9 の完了の条件（architecture §8 の S9・S10 は「`scaffolds/picture_book/` の本が四つの出力先で組め、EPUB が EPUBCheck でエラー・警告とも 0」）を、S8 の答え（`v2-s8-novel-consultation.md` §4.11）と同じく「機械で見るもの」と「目で見るもの」に分けて。Kindle Previewer で固定レイアウトの EPUB を開いて見る箇所と、KDP のプレビューで見る箇所。
2. 絵本の基準（N1 と同じ形の `P1`）を作るか、いつ作るか。
3. `scaffolds/picture_book/` の本の中身。絵の出どころ（著作権の問題が無いもの。vs で作る図・パブリックドメインの絵・ユーザーが用意する絵）、ページ数、見開き・重ねる文字・振り仮名・文字だけのページ・前付と奥付を含める範囲。

### 2.7 動く絵本（S10）の骨組み（§1.3 の 13）

S10 の仕様の全部でなくて構いません。次を決めてください。

1. S10 の範囲（動画を絵本だけにするか、リフローの本にも開くか）と、小段階のおおまかな並び。
2. S9 のうちに決めておかないと S10 で作り直しになる点（契約 HTML の動画の要素の置き場・固定レイアウトの EPUB の梱包が `<video>` を運べる形か・`assets` の方針の形・段の表の `print pdf` の導出の条件）。
3. ポスター画像の出どころと、外部の道具（ffmpeg）を必須にするか。動画の形式の検査と大きさの 🟡。
4. 動画の記法の型と、`data-vs-url` の扱い。

### 2.8 その他（あれば）

ほかにも、絵本と動く絵本の仕様に要るのに上の問いに無いもの（音声・読み上げ（EPUB の Media Overlays）・ページめくりの向きの検査・絵本の分冊・画像の色の管理など）があれば、挙げて、2.0 に含めるか後へ回すかを決めてください。

## 3. 答えの形

- §2 の各問いの決定と理由を、`v2-s8-novel-consultation.md` §4 と同じく、この文書の末尾に「答え」の節として書く。
- 答えは、絵本の仕様書（新しい文書。名前は Fable が決める。案は `picture-book-spec.md`）の骨格として、Opus がそのまま節へ移せる形にする。仕様書に入れる節の並び（目次）を最初に示し、各決定がどの節に入るかを書く。動く絵本は、別の仕様書（案は `video-spec.md`）の骨組みとして、節の並びと決めたことだけを書く。
- §2.1 の小段階の表は、`v2-s8-novel-consultation.md` §4.3 の表と同じ形で書く。
- 決めるのに確かめが要る点（たとえば Kindle Previewer での重ねる文字の拡大・Apple Books での見開きの絵・Vivliostyle で `viewport` の寸法のページを組めるか）は、Fable が scratchpad で確かめてよい。確かめられなかった点は、確かめる内容と、結果ごとの手を書く（確かめは Opus が S9 の中で行う）。KDP のプレビューはユーザーだけが確かめられる。
- 今決めずに S9 の実装の中で決めてよい点は、そう書いて、決めるときの判断の軸を添える。
- ユーザーに確かめてほしい点（雛形の絵の出どころ・入口の確かめの段取りなど）は、別に一覧にする。
- 決定を移す先（新しい仕様書のほか、4 本の仕様書の節・`PLANNED.md`）を挙げる（移すのは Opus が行う）。

---

## 4. 答え（Fable・2026-11-17）

4 本の仕様書・`v2-feasibility-notes.md` §4・§5・`v2-s8-novel-consultation.md` §4 と、実物（`book_traits.rb`・`book_profile.rb`・`trait_combination_check.rb`・`build/plan.rb`・`print_pdf_builder.rb`・`cmyk_converter.rb`・`variant_glyph_font.rb`・`config/catalog.yml`・`config/book.yml` の `cover_bleed`）を読んだ。リポジトリのコードは書き換えていない。実験は行っていない。確かめが要る点は 4.12 に、確かめる内容と結果ごとの手を書いた。

### 4.1 仕様書の名前と節の並び

絵本の仕様書は `picture-book-spec.md`、動画の仕様書は `video-spec.md` とする。動画は絵本だけのものにしない（4.11）ので、名前に絵本を入れない。

| `picture-book-spec.md` の節 | 中身 | この答えの節 |
| :--- | :--- | :--- |
| §1 範囲と前提 | 相談文の §1.2 と、2.0 で扱わないもの | 4.2・4.12 |
| §2 原稿の形 | ページの区切り・文字の箱・ページの種類・奥付・ページで使える記法 | 4.4 |
| §3 契約 HTML（固定レイアウト） | `body` のクラス・ページの中の要素・`viewport` | 4.5 |
| §4 寸法・画像・見開き | 判型と `viewport`・画像の大きさ・見開き・綴じの向き | 4.6 |
| §5 出力先 | 四つの `OutputTarget`・EPUB の中身・Kindle の画像のページ・入稿用 PDF・表紙 | 4.7 |
| §6 段の表と、ほかのコマンド | 走る段・止める段・`vs preflight`・`vs lint`・`vs metrics` | 4.8 |
| §7 テーマ `picture-book` | 名前・vs の CSS とテーマの分担・`tokens:` | 4.9 |
| §8 雛形 `scaffolds/picture_book/` | 中身と絵の出どころ | 4.10 |
| §9 段階ごとの完了の条件と確かめ方 | 入口の確かめ・小段階の表・機械で見るもの・目で見るもの・基準 P1 | 4.3・4.10 |
| §10 論点（未決） | 4.12 の表 | 4.12 |

`video-spec.md` の節の並びは 4.11 に書く。

### 4.2 決めたこと（一覧）

| # | 問い | 決定 |
| :--- | :--- | :--- |
| 2.1-1 | 小段階 | S9-0（入口の確かめ）と S9-1〜S9-7（4.3）。本書と小説の出力を組んで比べるのは S9-1 と S9-7 |
| 2.1-2 | 入口の確かめ | 手で作る 2 つの EPUB（A: 実体の文字を重ねる・B: ページを画像にする）を、ユーザーが KDP のプレビューで見る。製品のコードは書かない |
| 2.1-3 | S8b・S8c との順 | 入れ替えは自由のまま。`vs furigana`（S8c）を S9 の前提にしない。雛形の絵本の振り仮名は手で書く |
| 2.2-1 | 原稿の形 | 1 ファイルに複数ページ。ページは `@page`・`@spread` の行で区切る。`catalog.yml` は `CHAPTERS:` だけを使う |
| 2.2-2 | ページの記法 | 絵は `@page` の属性、文字は `:::{.text}` の箱。位置は名前（`.top`・`.bottom` など）か、ページに対する割合（`x=`・`y=`・`w=`） |
| 2.2-3 | ページで使える記法 | 段落と行内の記法だけ（ルビ・強調・傍点・縦中横・改行）。ほかは 🟡 |
| 2.2-4 | 重ねる文字 | PDF とクリーン EPUB は実体の文字。**Kindle は、閲覧用 PDF のページを画像にして並べる** |
| 2.3-1 | 寸法 | 判型は `page.use` のまま。`viewport` は判型を 96dpi の px に直した値。絵本の既定は今ある `b5_standard`（縦）。横長と正方形のプリセットを 3 つ足す |
| 2.3-2 | 画像の大きさ | クリーン EPUB は今の上限（長辺 2048px・WebP）。Kindle のページの画像は長辺 1920px の JPEG。大きさは出力の一覧に示し、100 MB を超えたクリーン EPUB は 🟡 |
| 2.3-3 | 見開き | 1 枚の絵を左右のページが半分ずつ見せる。どの出力先でも同じ作り。縦書きの絵本は S9-6 で扱う（切る場合の手も決めた） |
| 2.4-1 | 出力先の宣言 | 4.7 の表。`css_form` に `:none`、`packager` に `:fixed_epub`・`:fixed_epub_images` を足す |
| 2.4-3 | 入稿用 PDF | 組み直し。絵は塗り足しまで拡大して流用する（表紙の `cover_bleed: scale` と同じ）。本文の画像の CMYK 化は 2.0 では行わない |
| 2.4-4 | 表紙 | 今の `covers/` の仕組みのまま。ページの並びに表紙を入れない |
| 2.5 | テーマ | 名前は `picture-book`。位置と寸法は vs の CSS、見た目だけをテーマが書く。オプションは最初は置かない |
| 2.6 | 確かめ | 機械で見る条件 9 つと、目で見る 8 か所（4.10）。絵本の基準 P1 を S9 の完了で作る |
| 2.7 | 動画 | どの種類の本でも使える。記法は画像と同じ形。ポスター画像は著者の指定が先で、無ければ ffmpeg で切り出す（4.11） |
| 2.8 | 読み上げ・音声・色の管理・絵本の分冊 | 2.0 の後へ回す。固定レイアウトの分冊は 🔴 で止める |

### 4.3 入口の確かめと小段階（問い 2.1）

**S9-0 入口の確かめ。** KDP が受け付けるかは Kindle の出力だけの危険で、クリーン EPUB の梱包はどちらにしても要る。そこで、確かめのために製品のコードを先に書くことはしない。`v2-feasibility-notes.md` §7 の作り直しの手順で、スクラッチに次の 2 つの EPUB を作る（どちらも 8 ページ・B5 縦・表紙つき・見開き 1 組・EPUBCheck がエラーと警告 0）。

| 版 | 中身 | 見る理由 |
| :--- | :--- | :--- |
| A | 絵の上に実体の文字を `position: absolute` で重ねる。ルビつき。リンクを 1 つ | クリーン EPUB と同じ作りが Kindle で通るか |
| B | ページ全体を 1 枚の画像にする（文字は絵に焼いてある）。画像の上に、透明な `<a>` の箱を 1 つ重ねる | 4.4 の決定（Kindle は画像のページ）が通るか。動画のリンク（S10）が置けるか |

ユーザーが KDP に下書きとして上げ（出版はしない）、プレビューで次を見る。(1) 受け付けられる。(2) ページの順と、見開きの左右。(3) 絵がページいっぱいに出る。(4) A の文字の位置とルビ。(5) B のリンクを押せる。(6) 表紙。結果は `v2-feasibility-notes.md` §4 に追記する。

| 結果 | 手 |
| :--- | :--- |
| B が通る | 計画どおり。Kindle は画像のページで作る。A の結果は記録だけする（2.0 の後で、実体の文字に替えるかを考える材料） |
| B の表示は通るがリンクが効かない | Kindle は画像のページで作る。動画のリンクは、S10 で、ポスターの下に URL を字で焼く形にする |
| A だけが通る | Kindle もクリーン EPUB と同じ梱包にする（S9-5 が小さくなる） |
| どちらも通らない | **ユーザーが選ぶ**: (ア) 絵本の `kindle` を 2.0 の対象から外す（`TraitCombinationCheck` が 🔴 で止め、Kindle Create で作る手順をマニュアルに書く）。(イ) 原因を調べる期間を置く（Amazon の指針のメタデータを変えた版を 2 回まで）。Fable の勧めは (イ) を 1 回行ってから (ア) |

S9-0 は S8 の間に行ってよい（製品のコードに触れない）。答えが早いほど、S9-5 の作り方が早く決まる。

**小段階。**

| 小段階 | 作るもの | 確かめ |
| :--- | :--- | :--- |
| S9-1 軸を開く | `OutputTarget.for(id, traits)`（固定レイアウトの宣言は中身が空の枠でよい）。段の表の `!traits.fixed?` の条件（`v2-architecture-spec.md` §3.3）。`BuildPlan#derive_print?` に `!traits.fixed?`、`#viewing_pdf?` に「固定レイアウトで `kindle`」を足す。判型のプリセット 3 つ（4.6）。`BookProfile` の `picture_book` に `theme.name`・`page.use`。固定レイアウトの分冊と、`CHAPTERS:` のほかの区分の 🔴。固定レイアウトを止める 🔴 はまだ外さない | **本書と小説を、その時点の基準と比べる。** `Common::CONFIG` の書き出しと、段の並び（S5-3 と同じ 25 通りに N1 の設定を足す）が前後で同じ。B1 の `pdf`・`epub`・`kindle` を組み、PDF の画素・EPUB・Kindle 用 EPUB が同じ（`EpubFlow` が宣言の引き方を変えるため） |
| S9-2 ページの原稿と契約 HTML | 原稿をページに分ける読み込み（4.4）・`build page spreads` の段・`stylesheets/base/fixed.css`（4.9）・`HtmlContract` に 4.5 のクラス・原稿の検査（見開きの偶奇・絵の縦横比・`alt`・使えない記法） | 本書に触れない（新しい段は固定レイアウトの本でだけ載る）ことを段の並びで見る。材料のテーマ（`supports.layout: [fixed]`）と 6 ページの材料の本で、ページごとの HTML が出て、`HtmlContract` の検査が通る。検査ごとのテスト |
| S9-3 PDF と入稿用 PDF | ページの HTML から `vivliostyle.config.js` を作る・表紙との結合・入稿用の組み直しと塗り足し（4.7）・`techbook post-process` をページの HTML に当てる・固定レイアウトを止める 🔴 を `pdf`・`print_pdf` について外す | 材料の本で、`pdfinfo` の寸法とページ数、入稿用の TrimBox・BleedBox、文字の箱の位置（`pdftotext -bbox`）、Type 3 の書体が 0 |
| S9-4 クリーン EPUB | `build/epub/fixed_package.rb`（4.7）・書体の同梱・`nav`・`epub` について 🔴 を外す | EPUBCheck が致命・エラー・警告とも 0。OPF の `rendition:*`・`page-spread-*`・`viewport`。Apple Books で 4.10 の 8 か所 |
| S9-5 Kindle（画像のページ） | 閲覧用 PDF のページを画像にして梱包する（`:fixed_epub_images`）・`<名前>-kindle.epub`・`kindle` について 🔴 を外す | EPUBCheck。Kindle Previewer で開いて 8 か所（変換の記録は Success・エラー 0。Enhanced Typesetting は Not Supported が正しい） |
| S9-6 テーマ `picture-book` と、縦書きの絵本 | `themes/picture-book/`（4.9）・`vs theme:check`。`page.writing_mode: vertical` の固定レイアウト（文字の箱の `writing-mode`・右綴じでの見開きの左右） | `vs theme:check picture-book` が 🟡 0。縦書きの材料の本で、ページが右から左へ進み、見開きの左右が合う |
| S9-7 雛形と完了の確かめ | `scaffolds/picture_book/`（4.10）・`vs new --type picture_book`・`vs lint` と `vs preflight` の扱い（4.8）・`book_profile_test.rb` の (2) | 4.10 の機械の条件と目で見る 8 か所。**全部の比べ**（B1〜B5・N1）。`rake test`・`rake test:layout`・`rake test:standard`・`rake test:release`。ユーザーが、雛形の Kindle 用の EPUB を KDP のプレビューで見る。その後、基準の版を上げて P1 を足す |

仕様に無いので、次のように決める。

1. **固定レイアウトを止める 🔴 は、出力先ごとに外す。** S9-3 で PDF、S9-4 で EPUB、S9-5 で Kindle。途中の版で、作っていない出力先を選んだ本が壊れた出力を出さないためである。
2. **S9-2〜S9-6 は、本書と小説の出力を組み直さない。** 触るのは固定レイアウトの本でだけ走るコードである。段の並びが前後で同じことと `rake test` で足りる。共通の部分（`EpubFlow`・`OutputTarget`・段の表）に手を入れることになったら、その小段階で B1 と N1 を組んで比べる。
3. **縦書きの絵本（S9-6 の後半）は、S9-1〜S9-5 が計画どおりに進んだときに作る。** 遅れていれば、`page.writing_mode: vertical` と `page.layout: fixed` の組み合わせを 🔴 で止めて 2.0 の後へ回してよい。回すかどうかはユーザーが決める。作りは小さい（文字の箱の組方向と、見開きの左右の入れ替え）ので、勧めは「作る」である。

### 4.4 原稿の形（問い 2.2）

**1 ファイルに複数ページ。** 絵本は 16〜32 ページで、1 ページの文字は数行である。1 ファイル 1 ページにすると、文字を通して読み直すことも、ページを入れ替えることも手間になる。ファイルを分けるのは自由で、`catalog.yml` の `CHAPTERS:` に並べた順につなぐ（場面ごとに分ける使い方）。`PREFACE:` などのほかの区分は固定レイアウトでは使えず、書いてあれば 🔴。ファイル名の番号の範囲（`00`・`90`〜`99`）にも意味を持たせない。

**ページの区切り。** 行頭の `@page` と `@spread` で区切る。今の `@pagebreak` と同じ「行の指示」の形で、ページが原稿の単位であることが一目で分かる。

```markdown
@page image=images/p01.jpg alt="森の入り口に立つ、まるくん"

むかし むかし、{森|もり}の おくに……

@spread image=images/p02-03.jpg alt="夜の森"

:::{.text .left .bottom}
まるくんは あるきました。
:::

:::{.text .right x=55% y=10% w=35%}
「だれか いますか」
:::

@page

えの ない、もじだけの ページです。

@page colophon
```

| 書き方 | 意味 |
| :--- | :--- |
| `@page image=… alt=…` | 1 ページ。絵はページいっぱいに敷く。`fit=contain` で、切らずに収める（既定は、ページを覆うように切る） |
| `@spread image=… alt=…` | 見開きの 2 ページ。1 枚の絵を左右に半分ずつ見せる |
| `@page`（属性なし） | 絵の無い、文字だけのページ |
| `@page colophon` | 奥付。vs が、今の奥付と同じ中身を作る。**置いた場所にだけ作る**（置かなければ奥付は無い） |
| `@page blank` | 白いページ |
| `title="…"` | そのページを、EPUB の目次（`nav`）と PDF のしおりに載せる題。付けたページだけが載る |
| 区切りの後の、箱に入れない段落 | テーマの決めた既定の位置の箱に入る |
| `:::{.text 位置}` … `:::` | 文字の箱。位置は名前（`.top`・`.bottom`・`.center`・`.left`・`.right` と、その組み合わせ）か、`x=`・`y=`・`w=`（箱の左上と幅。ページに対する割合）。見開きでは `.left`・`.right` でページを選び、割合はそのページに対するもの |

- 位置を割合で書くのは、PDF（mm）と EPUB（px）で同じ値が使え、判型を変えても釣り合いが保たれるためである。名前の位置は、割合を考えなくても書けるようにするためのものである。細かい見た目（箱の地の色など）は、箱にクラスを足して `custom.css` で書ける（`:::{.text .bottom .mybox}`）。
- 本扉と権利ページは、vs が作らない。絵本の本扉は絵であり、著者が 1 ページとして書く。奥付だけを vs が作るのは、書誌（`book.yml`）から組める定型の中身だからである。
- 記法の型は、`notation-implementation-guide.md` に「ページの単位（固定レイアウト）」の節を足して載せる。型の記号は、S8 で足す D 型・E 型の次にする。
- **絵に `alt` が無ければ 🟡**（原稿の行を指す）。絵本は絵が中身なので、読み上げと Kindle の画像のページ（下の 4.7）の代わりの文になる。

**ページで使える記法。** 段落と、行内の記法（ルビ・強調・太字・傍点・縦中横・行内の属性・行末の改行）だけとする。見出し・箇条書き・表・コード・数式・脚注・相互参照・索引の印・囲みは、固定レイアウトの本では 🟡 で「絵本のページでは使えません」と示し、文字として組まない（落とす）。理由は、ページの中の文字は位置の決まった小さな箱で、あふれても次のページへ送れないからである。

- 通し方: ファイルごとに、`@page`・`@spread`・`:::{.text}` を入れ物の HTML に置き換えてから、今の前処理 → VFM → 後処理のうち行内の記法に関わる段だけを通し、最後にページごとの HTML に分ける。**段の選び方（S5-4 の `STEPS` に「固定レイアウトでも走る」の印を足すか、固定レイアウト用の短い並びを別に持つか）は S9-2 で決める。** 軸は「走る段が 10 以下なら別の並び」。どちらでも、記法の実装を二重に持たない。
- 文字が箱からあふれたかは、PDF を組んだ後で見る（S9-3。箱の高さと、中の文字の最後の行の位置を `pdftotext -bbox` で比べ、あふれたページを 🟡 で示す）。難しければ、あふれの検出は 2.0 の後へ回してよい（Opus が決めて記録する）。

**重ねる文字（問い 2.2 の 4）。** PDF とクリーン EPUB は実体の文字で組む。検索・読み上げ・文字の選択ができ、`vs furigana` の結果もそのまま使える。**Kindle は、閲覧用 PDF のページを 1 枚ずつ画像にして並べる。** 理由は三つある。

1. Kindle の固定レイアウトで、重ねた文字が PDF と同じ位置・同じ書体で出るかは、端末の種類（電子ペーパー・タブレット・スマートフォン）ごとに確かめる手段が無い。画像なら、紙面が PDF と同じになることが作りで決まる。
2. 道具がすでにある（`vs pdf:pages` の PDF → JPEG）。`kindle-fixed-layout-ideas.md` の実装の素描がそのまま使える。
3. 動画のポスター画像（S10）も、PDF で置き換えた後の紙面がそのまま Kindle に届く。

失うのは、Kindle での文字の検索と読み上げ、文字の拡大（Amazon の指針の `RegionMagnification`）である。絵本の文字は大きく組むものなので、2.0 では受け入れる。画像の `alt` には、そのページの絵の `alt` と文字をつないだものを入れる。S9-0 で A が通れば、2.0 の後で実体の文字に替える余地が残る。

### 4.5 契約 HTML（`theme-contract-spec.md` §2.7 に足す）

1 ページが 1 枚の HTML。

```html
<body class="vs-fixed vs-page-picture" data-vs-page="3">
  <div class="vs-page-art"><img class="vs-page-image" src="images/p01.jpg" alt="…"></div>
  <div class="vs-text bottom" style="--vs-x: 10%; --vs-y: 70%; --vs-w: 80%"><p>…</p></div>
</body>
```

| 要素・クラス | 保証 |
| :--- | :--- |
| `body.vs-fixed` と、ページの種類のクラス | `vs-page-picture`（絵のあるページ）・`vs-page-text`（文字だけ）・`vs-page-spread-left`・`vs-page-spread-right`・`vs-page-colophon`・`vs-page-blank` |
| `div.vs-page-art > img.vs-page-image` | ページいっぱいの絵。見開きでは、同じ画像を左右のページが半分ずつ見せる（`vs-page-art` が幅 200% の絵を切る） |
| `div.vs-text` | 文字の箱。名前の位置はクラス（`top`・`bottom`・`center`・`left`・`right`）、割合は `style` の `--vs-x`・`--vs-y`・`--vs-w` |
| `head` の `viewport` | `width=<px>, height=<px>`（4.6） |
| `figure.vs-video` | 動画（S10。4.11）。位置の決め方は文字の箱と同じ |

- 位置を `style` の変数で渡すのは、vs の CSS（`base/fixed.css`）が 1 つの規則で読め、Kindle 用の CSS の制約（`var()` を解く）に触れないためである（Kindle は画像なので CSS を持たない。クリーン EPUB と PDF は `var()` を解する）。
- 足すだけなので、契約の版は上げない（`theme-contract-spec.md` §2.7）。

### 4.6 寸法・画像・見開き（問い 2.3）

- **判型は `page.use` のプリセットで決める（今と同じ）。** 固定レイアウトで読むのは紙の大きさと、基準の字の大きさだけで、余白と行送りは読まない。
- **`viewport` は、判型を 96dpi の px に直した値にする**（B5 は 688 × 971）。CSS の 1mm は 96/25.4 px なので、同じ HTML と CSS が、Vivliostyle の PDF（`@page` の大きさ＝判型）と EPUB（`viewport`）の両方でそのまま同じ釣り合いに組まれる。寸法を二つ持たない。
- **絵本の既定の判型は、今ある `b5_standard`（B5 の縦）にする。** 同人誌の印刷所は A5 と B5 の縦が標準で、横長と正方形は特別な扱いになることが多い。電子では、縦のページを 2 枚並べた見開きが、横向きのタブレットの画面にそのまま合う。
- **足すプリセットは 3 つ**: `b5l_standard`（B5 の横・257 × 182）・`a4l_standard`（A4 の横）・`sq210_standard`（210mm の正方形）。`Common::PAGE_SIZES` と `config/page_presets.yml` に、S8-3 と同じ足し方で入れる。値（基準の字の大きさ）は S9-6 でテーマと一緒に決める。
- **画像の大きさ。** 著者は印刷の解像度の絵を 1 枚だけ用意する。出力先ごとに vs が縮める。

  | 出力先 | 絵の大きさ |
  | :--- | :--- |
  | `pdf` | 今の画像の最適化のまま |
  | `print_pdf` | 元の絵のまま（縮めない） |
  | `epub` | 今の上限（長辺 2048px）で WebP。見開きの絵は、2 ページぶんなので長辺 4096px まで |
  | `kindle` | ページの画像は長辺 1920px の JPEG（品質 85）。定数とする |

- **大きさの知らせ。** 出力の一覧に、EPUB と Kindle 用の EPUB の大きさを示す。クリーン EPUB が 100 MB（Kobo の上限）を超えたら 🟡（`v2-architecture-spec.md` §4.5 の決めを、動画の無い絵本にも当てる）。Kindle の 1920px と品質 85 は、雛形の本の大きさを S9-5 で測って、1 ページ 400 KB を大きく超えるようなら下げる（Opus が決めて記録する）。
- **見開きは、1 枚の絵を左右のページが半分ずつ見せる。** 2 ページぶんの 1 枚の HTML にはしない。PDF（単ページ）・入稿用 PDF（単ページ）・EPUB（`page-spread-left`・`page-spread-right`）・Kindle の画像のページが、どれも同じ作りになるためである。リーダーによっては左右のページの間に細い線が見えるが、受け入れる。
  - `@spread` が偶数ページ（左綴じなら左のページ）から始まらないときは 🔴 で、「前に 1 ページ足すか、`@page blank` を入れてください」と示す。表紙はページに数えないので、本文の 1 ページ目は奇数ページ（1 枚だけで見える側）である。
  - 文字の箱は、左右どちらかのページに置く。ノドをまたぐ箱は書けない。
- **綴じの向きは `traits.binding` を読む。** 右綴じ（縦書き）では、見開きの絵の右半分を先のページが見せる。
- **閲覧用 PDF** は単ページのまま出し、見開きで開くよう `PageLayout`（左綴じは `TwoPageRight`、右綴じは `Direction` と合わせる）を書く。qpdf で 1 か所書けば済むなら入れ、手間が大きければ入れない（Opus が決めて記録する）。

### 4.7 出力先（問い 2.4）

**宣言。** `OutputTarget.for(id, traits)` が、`traits.fixed?` のときに次を返す。

| 出力先 | `transforms` | `css_form` | `finalizers` | `assets` | `packager` |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `pdf` | なし | `:layered` | なし | 画像はそのまま | `:vivliostyle_pdf` |
| `print_pdf` | なし | `:layered` | なし | 画像はそのまま（縮めない） | `:print_pdf`（組み直しだけ。導出しない） |
| `epub` | 固定レイアウト用（S9 では `MarkBody` に当たる 1 段だけ。動画の段は S10） | `:flat` | `AuthorPriority` → `InversionReport` | WebP・`<video>` | `:fixed_epub` |
| `kindle` | なし（HTML を使わない） | `:none`（新しい値。CSS を持たない） | なし | JPEG | `:fixed_epub_images` |

- `body_classes` は `vs-fixed`（どの出力先でも契約 HTML に付いている）に、`epub` では `vs-epub` を足す。
- クリーン EPUB に平らな CSS を渡すのは、リフローと同じ理由（層を外した CSS はどのリーダーでも同じに読まれる）。`custom.css` を勝たせる段もそのまま使える。
- `kindle` は閲覧用 PDF を材料にするので、`output.targets` に `pdf` が無くても、閲覧用 PDF を組む（`BuildPlan#viewing_pdf?`。入稿用だけを選んだ本が閲覧用を組むのと同じ扱い）。

**vs が作る固定レイアウトの EPUB（`build/epub/fixed_package.rb`）。** `epub` と `kindle` で同じ梱包を使い、ページの中身（XHTML と CSS か、画像 1 枚か）だけが違う。

| 項目 | 中身 |
| :--- | :--- |
| OPF | `rendition:layout` は `pre-paginated`、`rendition:spread` は `landscape`、`rendition:orientation` は `auto`。`spine` の `page-progression-direction`（`traits.binding`）と、各 `itemref` の `page-spread-left`・`page-spread-right`。書誌と識別子は今の EPUB と同じ出どころ（`Epub::Opf` の識別子の安定化を使う） |
| Kindle だけ | Amazon の固定レイアウトの指針のメタデータ（`fixed-layout`・`original-resolution`・`orientation-lock`・`primary-writing-mode`・`book-type`）。**どれを書くかは S9-0 で通った版に合わせる** |
| `nav` | `title=` の付いたページだけを目次に載せる。1 つも無ければ、最初のページだけを載せる（`nav` は必須のため）。`landmarks` に表紙と本文の始まり |
| 表紙 | 今の表紙の画像（`covers/`。`output.epub.embed`・`output.kindle.embed` の決めも今のまま） |
| ページ（`epub`） | 1 ページ 1 枚の XHTML・平らな CSS 1 枚・WebP の絵・書体 |
| ページ（`kindle`） | 1 ページ 1 枚の XHTML で、中は画像 1 枚（と、S10 のリンクの箱） |
| 書体（`epub`） | **文字の箱で使う書体を同梱する。** 固定レイアウトでは、読者の端末の書体で組むと箱から字があふれる。`VariantGlyphFont` と同じ ttfunk の部分集合で、使った字だけにする。部分集合を作れない書体（TTF でないもの）は丸ごと同梱し、大きさを出力の一覧に示す。書体の利用の条件は著者が確かめるもので、マニュアルに書く |
| 梱包 | `mimetype` を無圧縮で先頭に置く zip。素材は、種類（MIME）つきの一覧で受ける形にしておく（S10 で動画がそのまま入る） |

- 合わせる指針は、クリーン EPUB は EPUB 3 の規格と Apple Books の Asset Guide、Kindle は Amazon の指針とする。Kobo は規格どおりの固定レイアウトを読むので、別の作りを持たない。

**入稿用 PDF。** 固定レイアウトの本は、閲覧用 PDF から導出せず、組み直す（今の `full_bleed` の経路。`output.print_pdf.full_bleed` の値に関わらず）。

- **塗り足しは、vs が絵を塗り足しの端まで拡大して作る。** 表紙の `cover_bleed: scale` と同じ考え方で、著者は判型どおりの絵を用意すれば済む。B5 で 3mm の塗り足しなら、絵は 3% ほど大きく刷られる。文字の箱の位置は変わらない。
- 塗り足しを含めた絵を著者が用意する形（表紙の `_bleed` の画像に当たるもの）は、2.0 では作らない。要望が出たら足す（`PLANNED.md`）。
- 本文の画像の CMYK 化は 2.0 では行わない（今の技術書と同じく RGB のまま）。`PLANNED.md` の CMYK の項に「絵本ではとくに要る」と書き足す。
- 印刷に出す本でページ数が 4 の倍数でないときは、💡 で知らせる（中綴じでは 4 の倍数が要る。止めはしない）。

**表紙。** 今の `covers/` の仕組みのまま使う。絵本の表紙は絵なので、著者が画像を置く形（`book.cover` に自分の画像の名前）が中心になる。ページの並びの 1 枚目を表紙にする形は取らない。理由は、表紙が本文と別のファイルで入稿される今の流れ・EPUB の表紙の扱い・S8b のくるみ表紙が、どれも `covers/` を前提にしているためである。

### 4.8 段の表と、ほかのコマンド（問い 2.4 の 5）

| 段 | 固定レイアウトの本で |
| :--- | :--- |
| `optimize images`・`book-settings.css` の生成・`prepare cover assets` | 走る |
| **`build page spreads`**（新） | 走る。`preprocess sections`・`convert sections html`・後処理に替わる |
| `techbook post-process` | 走る（ページの HTML に当てる。PDF の書体の対策は種類に依らない） |
| `build overall pdf`・表紙との結合・圧縮・改名 | 走る |
| しおり（`outline`） | `title=` の付いたページがあれば作る |
| `print pdf` | 走る（組み直し） |
| `generate epub` | 走る（中身は固定レイアウトの梱包） |
| `preprocess sections`・`convert sections html`・`index scan and build`・`generate part title pages`・`generate toc html`・前付（本扉・権利ページ）の生成・`backlink dedup`・`check chapter leads`・`prepare theme images`・回転した表の画像 | 載らない |

- `vs build` の単章のビルド（`vs build 21`）は、固定レイアウトでは「そのファイルのページだけを PDF に組む」とする。
- `vs preflight` は、`build page spreads` の検査（4.4）を走らせる。
- `vs lint` は、`contents/` のファイルの文字に掛ける。`@page`・`@spread` の行と `:::{.text …}` の行は、校正の対象から外す（`NotationGuard` に足す）。規則の組は種類の既定の `minimal`。
- `vs metrics` は `metrics.use: none` なので、字数と漢字の水準だけを示す。ページごとの字数を示すかは、2.0 の後で考える。
- `vs create`・`vs rename` などの章の番号を扱うコマンドは、固定レイアウトの本でもファイルの単位で働く。番号の範囲の意味（前書き・付録）だけが無い。食い違いが出たら、そのコマンドを固定レイアウトで 🔴 にして 2.0 の後へ回してよい（Opus が決めて記録する）。

### 4.9 テーマ `picture-book`（問い 2.5）

- **名前は `picture-book`。** `novel` と同じく、本の種類の名前にする（`theme-contract-spec.md` §10 の論点 1 を閉じる）。
- **分担。** 位置と寸法は vs の CSS、見た目はテーマが書く。

  | 置き場 | 書くもの |
  | :--- | :--- |
  | `stylesheets/base/fixed.css`（vs。base 層。固定レイアウトの本の入口にだけ入れる） | `@page` の余白を 0 に・`body.vs-fixed` の大きさ・`vs-page-art` と絵の敷き方（覆う・収める・見開きの半分）・`vs-text` の位置（名前のクラスと `--vs-x` など）・入稿用の塗り足しへの拡大 |
  | `themes/picture-book/`（テーマ） | 文字の箱の書体・字の大きさ・行送り・字の色・箱の地（白い板・影・なし）・既定の位置（箱に入れない段落の置き場）・文字だけのページと奥付の組み方 |

- **`theme.yml`**: `supports.layout: [fixed]`・`supports.writing_mode: [horizontal, vertical]`（縦書きを S9-6 で作らなかった場合は `[horizontal]`）・`supports.targets` は四つ・`features:` は空・`options:` は最初は置かない（`novel` と同じく、迷う項目は足さない）。`tokens:` に、文字の箱の値（字の大きさ・色・地の色）を公開する変数として置く。名前は `--book-*` の決まりに従い、S9-6 で決める。
- 字の大きさは、ページの幅に対する割合ではなく pt で書く（判型のプリセットの基準の字の大きさから求める）。`viewport` が判型と同じ釣り合いなので、EPUB でも同じ見た目になる。
- **リフローのテーマ（`standard`・`novel`）を固定レイアウトの本で選ぶと、`supports.layout` の検査が 🔴 で止め、固定レイアウトに対応するテーマの名前を示す**（S6-3 で作った検査が、S9 で 🔴 を外すと働く）。逆に、`picture-book` をリフローの本で選んでも同じ検査で止まる。

### 4.10 雛形と確かめ方（問い 2.6）

**雛形 `scaffolds/picture_book/`。** 12 ページの短い絵本。

- 絵は、**リポジトリの中のスクリプトで作る、単純な図形の絵**にする（丸・三角・四角の登場人物）。著作権の問題が無く、作り直せて、判型を変えても作り直せる。**絵の出どころはユーザーが確かめる**（用意できる絵があれば替える。雛形は `vs new` で著者の手元に写る）。
- 中身: 絵と文字のページ・見開き 2 組・文字だけのページ・ルビ（手で書く）・`title=` の付いたページ 2 つ・`@page colophon`・表紙（`covers/` に絵）。
- `book.yml` は絵本で意味のあるキーだけを載せる。

**S9 の完了の条件。** `scaffolds/picture_book/` の本で見る。

機械で見るもの:

1. 四つの出力先が終了コード 0 で組め、🔴 と 🟡 が 0。
2. PDF の紙の寸法がプリセットの値で、ページ数が原稿のページ数（＋表紙）と合う（`pdfinfo`）。
3. 入稿用 PDF の TrimBox と BleedBox が合い、絵が BleedBox の端まである（ページの端の画素が白でない）。
4. 文字の箱の位置が、原稿の割合と合う（`pdftotext -bbox`。許す差は 1mm）。
5. Type 3 の書体が 0。
6. 契約 HTML に 4.5 のクラスがあり、`HtmlContract` の検査が通る。
7. クリーン EPUB と Kindle 用の EPUB の EPUBCheck が、致命・エラー・警告とも 0。OPF の `rendition:layout`・`page-progression-direction`・`page-spread-*` が合う。
8. Kindle Previewer が Kindle 用の EPUB を開ける（変換の記録が Success・エラー 0）。
9. クリーン EPUB が 100 MB 未満。Kindle 用の EPUB の大きさを記録する。

目で見るもの（PDF・Apple Books・Kindle Previewer のそれぞれで。撮った画面を基準に残す）: 表紙・最初のページ・見開き（左右がつながる）・絵に重ねた文字とルビ・文字だけのページ・`title=` からの目次・奥付・ページをめくる向きの 8 か所。Apple Books では、文字の箱が PDF と同じ位置にあり、書体が同梱したものであることを見る。**KDP のプレビューは、S9-7 でユーザーが雛形の Kindle 用の EPUB を上げて見る**（S9-0 と同じ 6 点）。

**絵本の基準。** S9-7 の完了のコミットで、基準の版を上げ、`P1`（`scaffolds/picture_book/` の本の四つの出力先・画面）を足す。決まりのとおり B1〜B5 と N1 も組み直す。S10 以降は、P1 を PDF の画素と `epub_diff.rb` で守る（Kindle の中間生成物の比べは、固定レイアウトでは使わない。Kindle 用の EPUB を `epub_diff.rb` で比べる）。

### 4.11 動画（S10）の骨組み（問い 2.7）

**範囲。** 動画は、どの種類の本でも使える記法にする。`v2-architecture-spec.md` §4.5 の置き換えは種類に依らない書き方で決めてあり、技術書の操作の動画にも同じ要望がある。絵本だけにすると、契約 HTML の `figure.vs-video` の変換を固定レイアウト用に閉じ込めることになり、後で開くときに作り直しになる。

`video-spec.md` の節: §1 範囲・§2 記法・§3 契約 HTML・§4 出力先ごとの置き換え（リフロー・固定レイアウト）・§5 ポスター画像と道具・§6 検査と大きさの知らせ・§7 段階ごとの完了の条件。

| 項目 | 決定 |
| :--- | :--- |
| 記法 | 画像と同じ形で、拡張子で見分ける: `![題](videos/clip.mp4){poster=images/clip.jpg url=https://…}`。前処理変換型（B 型）で `figure.vs-video` にする。固定レイアウトのページでは、文字の箱と同じ位置の書き方を使う（`:::{.video x=… y=… w=…}` の中に同じ 1 行）。`@page video=…`（ページいっぱいの動画）は S10 の仕様で決める |
| 置き場 | 本の直下の `videos/`（`images/` と並べる）。`build_copy.rb` と雛形の素材の一覧に足す |
| ポスター画像 | `poster=` の指定が先。無ければ、ffmpeg で最初のこまを切り出す（生成資産型。`GeneratedAssetCache`）。**ffmpeg は必須にしない**: `vs doctor` には「`poster=` の無い動画があるときだけ要る道具」として載せる。指定も ffmpeg も無ければ 🔴 で、二つの直し方（`poster=` を書く・ffmpeg を入れる）を示す |
| `url=`（`data-vs-url`） | 必須にしない。無ければ 🟡（決定済み）。入稿用 PDF の QR コードは `url=` があるときだけ添える |
| 形式の検査 | 拡張子が `.mp4` でなければ 🔴。ffprobe があれば符号化を見て、H.264 でなければ 🟡（HEVC は 💡 で「Apple Books だけで再生できます」）。ffprobe が無ければ見ない |
| 大きさ | EPUB が 100 MB を超えたら 🟡（決定済み）。動画 1 本ごとの大きさを出力の一覧に示す |
| 自動再生・繰り返し | 2.0 では作らない（`controls` つきの再生だけ） |
| Kindle の固定レイアウト | 画像のページに、ポスター画像が焼かれて届く。リンクは、S9-0 の B でリンクが効けば透明な `<a>` の箱、効かなければポスターの下に URL を字で焼く |

**小段階のおおまかな並び。** S10-1 記法と契約 HTML と、リフローの `epub`・`pdf`・`kindle` の置き換え（本書は動画を使わないので、基準と同じ）→ S10-2 入稿用 PDF の QR コードと、導出をやめる条件 → S10-3 固定レイアウトのページの動画の箱と、固定レイアウトの EPUB への同梱 → S10-4 ポスター画像の切り出し・形式の検査・大きさの知らせ → S10-5 雛形（`scaffolds/picture_book/` に動画のページを 1 つ足すか、見本の本を別に置くかは S10 の仕様で決める）と完了の確かめ。

**S9 のうちに決めておくこと**（作り直しを避けるため。どれも上で決めた）。

1. 固定レイアウトの EPUB の梱包は、素材を種類（MIME）つきの一覧で受ける（4.7）。動画がそのまま入る。
2. ページの中の箱の位置の決め方（クラスと `--vs-x` など）は、文字の箱に限らない書き方にする（`base/fixed.css` は `vs-text` と `figure.vs-video` に同じ規則を当てる。4.5）。
3. `BuildPlan#derive_print?` は、固定レイアウトでは常に偽にする（S9-1）。リフローの本の「動画があれば導出しない」は S10-2 で足す。
4. Kindle の固定レイアウトを画像のページで作る（4.4）ので、動画の置き換えを Kindle の固定レイアウト用に別に書かなくて済む。`v2-architecture-spec.md` §4.2 の表の「`kindle`（固定）: 固定レイアウト用 ＋ 動画の置き換え」は「なし（PDF のページの画像）」に直す。

### 4.12 残した点と、S9 の中で決める点

| # | 点 | 決める時点 | 判断の軸・結果ごとの手 |
| :--- | :--- | :--- | :--- |
| 1 | KDP が受け付けるか | S9-0（ユーザー） | 4.3 の表 |
| 2 | Vivliostyle が、ページごとの HTML（`@page` の余白 0・絵をページいっぱいに・`object-fit`・見開きの半分）を寸法どおりに組めるか | S9-2 の最初（材料の本を 1 回組む） | 見開きの半分が `object-fit` と `object-position` で組めなければ、絵を前もって左右に切った 2 枚にする（`build page spreads` が切る）。位置の変数が効かなければ、`style` に直接 `left`・`top`・`width` を書く |
| 3 | Apple Books が、同梱した書体と重ねた文字を PDF と同じ位置に出すか | S9-4 | 位置がずれるなら、原因が書体（同梱が効いていない）か単位かを分ける。直せないときは、クリーン EPUB も画像のページにして `alt` に文字を入れる（実体の文字を失う。ユーザーに見せて了承を得る） |
| 4 | Kindle のメタデータの組 | S9-0 で通った版に合わせる | |
| 5 | Kindle のページの画像の大きさ（1920px・品質 85） | S9-5 | 雛形の本で 1 ページ 400 KB を大きく超えたら下げる |
| 6 | 固定レイアウトでも走る前処理の段の選び方 | S9-2 | 走る段が 10 以下なら別の並び（4.4） |
| 7 | 縦書きの絵本を 2.0 に含めるか | S9-5 の後（遅れていればユーザー） | 4.3 の決め 3 |
| 8 | 文字のあふれの検出 | S9-3 | 難しければ 2.0 の後 |
| 9 | 足すプリセットの値・テーマの `tokens:` の名前と値 | S9-6。値はユーザーが紙面を見て了承 | |
| 10 | 雛形の絵の出どころ | S9-7 の前にユーザーが確かめる | 4.10 |
| 11 | 読み上げ（EPUB の Media Overlays）・音声・絵の色の管理（CMYK）・塗り足しつきの絵・自動再生・ページごとの字数の表示 | 2.0 の後 | `PLANNED.md` に載せる |
| 12 | 固定レイアウトの分冊 | 2.0 の後 | S9-1 で 🔴 にする。確かめる面を増やさないため |

**ユーザーに確かめていただきたい点**: (1) S9-0 の KDP のプレビュー（下書きを上げて 6 点を見る）と、通らなかったときの選択。(2) 絵本の既定の判型を B5 の縦にすること。(3) Kindle の絵本を「ページの画像」で作り、Kindle では文字の検索と読み上げができないこと。(4) 雛形の絵を、スクリプトで作る単純な図形の絵にすること。(5) 縦書きの絵本を、遅れた場合に 2.0 の後へ回してよいか。

### 4.13 決定を移す先（Opus が S9 の最初に行う）

| 決定 | 移す先 |
| :--- | :--- |
| 4.1・4.4〜4.10 | 新しい仕様書 `picture-book-spec.md`（`STATUS.md` に 1 行） |
| 4.11 | 新しい仕様書 `video-spec.md`（骨組み。S10 の最初に中身を書く） |
| 4.3 の小段階・S9-0 | `picture-book-spec.md` §9。`v2-migration-plan.md` §2.1 の S9 の行・§7 の論点 3（S9-0 の形に書き直す） |
| 4.4 の「Kindle は画像のページ」・4.7 の宣言 | `v2-architecture-spec.md` §3.5（L1 の原稿の形）・§4.1（`css_form` の `:none`）・§4.2 の固定レイアウトの二行・§4.5（Kindle の固定レイアウトの動画）・§9 の論点 1・4（閉じる）・§8 の S9・S10 |
| 4.5 | `theme-contract-spec.md` §2.7（契約の表）・`HtmlContract` |
| 4.6 のプリセット・`BookProfile` | `v2-architecture-spec.md` §2.2 の表（`picture_book` の `theme.name: picture-book`・`page.use: b5_standard`）・§9 の論点 2（閉じる） |
| 4.8 | `v2-architecture-spec.md` §3.3 の表（固定レイアウトで載らない段を足す） |
| 4.9 | `theme-contract-spec.md` §4 の表（`picture` → `picture-book`）・§7.1・§10 の論点 1（閉じる） |
| 4.10 の P1 | `v2-migration-plan.md` §3.2 の基準の表・§3.6 |
| 4.12 の 11・12、4.7 の CMYK と塗り足しつきの絵 | `PLANNED.md` |
| S9-0 の結果 | `v2-feasibility-notes.md` §4 |

移し終えたら、この文書を archives へ移す。
