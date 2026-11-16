# S9 絵本（固定レイアウト）と S10 動く絵本の仕様（Fable への相談）

> 作成日: 2026-11-17
> ステータス: **相談中**（答えは §4 に書く）
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
