# 2.0 の前提を確かめた実験の記録

`v2-design-research-brief.md` §3-D の実験の結果。2.0 の設計（CSS の層・縦書きの小説・絵本・動く絵本）が前提にする、エンジンと出力先の挙動を小さな文書で確かめた。

- 調べた日: 2026-11-13
- 環境: `@vivliostyle/cli` 11.3.3・`@vivliostyle/core` 2.45.1・Kindle Previewer 4.0.4・EPUBCheck（EPUB 3.3 の規則）・macOS の Books（Apple Books）
- 検証用の文書はリポジトリに入れていない。作り方は各節に書いた

## 0. 結果の早見表

| 問い | 結果 | 確かめ方 |
|---|---|---|
| Vivliostyle は `@layer` を仕様どおりに扱うか | **扱う**（6 項目すべて） | PDF の文字・寸法・色 |
| KFX は `@layer` の中の規則を使うか | **使わない**（層の中の規則は全部捨てられる） | Kindle Previewer の画面 |
| Vivliostyle の縦書きで、奇数ページは左右どちらか | **左**（recto = 左） | PDF の余白の箱 |
| 縦書きの EPUB を KPF にできるか | **できる**（Enhanced Typesetting 対応・エラー 0） | 変換の記録と画面 |
| 固定レイアウトの EPUB を KPF にできるか | **できない**（4 版とも Mobi になる）。Enhanced Typesetting はリフロー型だけの機能で、固定レイアウトの本は EPUB のまま KDP へ出す | 変換の記録・KDP のヘルプ |
| 動画を含む EPUB を KPF にできるか | **できない**（エラー。Mobi になる） | 変換の記録 |
| Apple Books は `@layer` を仕様どおりに扱うか | **扱う**（4 項目すべて） | Books の画面 |
| Apple Books は EPUB の動画を再生するか | **する**（H.264・HEVC とも。ポスター画像と再生ボタンが出て、再生できた） | Books の画面 |
| EPUB の大きさの上限 | Kobo 100 MB・KDP 650 MB・Apple Books と Google Play Books 2 GB（§5.2） | 各ストアのヘルプ |
| Kobo・Google Play Books の `@layer` の対応 | **未確認**（公開された資料が見つからない・手元に無い） | Web の調べ |
| `theme-bunko` を vs の契約 HTML に `theme` 層で当てて組めるか（S7a） | **(a)・(b)・(d) は成り立ち、(c) は成り立たない**。`theme-base` の reset.css の `* { border-width: 0 }` などが、PDF で vs の部品（囲み・表・図の枠）を打ち消す。層を外すと勝ち負けが変わる組は 301 組（§8） | PDF の紙面・寸法の実測・ビルドの要素ごとの判定 |

---

## 1. Vivliostyle の `@layer`

HTML 1 枚と CSS 1 枚で、層の振る舞いを 6 項目確かめた。判定は、`::after` の `content` に書いた文字を `pdftotext` で読み、ページの寸法を `pdfinfo` で、色を PDF の描画命令（`qpdf --qdf` で展開した `rg`）で見た。

| 項目 | 書いたこと | 結果 |
|---|---|---|
| 層の順と詳細度 | `@layer low, high;` のあと、high に詳細度の低い規則、low に高い規則 | high が勝つ |
| 層の外 | 層の外の規則と、詳細度の高い層の中の規則 | 層の外が勝つ |
| `!important` | low と high の両方に `!important` | low が勝つ（順が逆転する） |
| `@import url() layer(low)` | 読み込んだ規則（赤）と、high の規則（緑） | 緑（読み込んだ規則が low 層に入る） |
| 層の中の `@page` | low に `size: A5` と `@top-center`、high に `size: A6` と `@top-center` | A6（105 × 148 mm）・high の余白の箱 |
| 層の中の名前付きの文字列 | high の中で `h1 { string-set: chap content(); }` と `@bottom-center { content: string(chap); }` | 章題が出る |

Vivliostyle core はページの処理（`@page`・余白の箱・名前付きの文字列）を独自のカスケードで行うが、そこでも層は仕様どおりに効く。PDF の出力については、CSS を層で整理する案（`PLANNED.md` の「スタイルシートの構造を整理し直す」）を妨げる挙動は見つからなかった。

---

## 2. KFX の `@layer`

縦書きの EPUB（§3）の CSS に、層の中だけに色を置いた版を作った（`@layer base { p { color: rgb(220, 0, 0); } .tcy { color: rgb(0, 0, 230); } }`、層の外に色の規則は無し）。Kindle Previewer で開くと、本文も縦中横も黒だった。**KFX は `@layer` のブロックを中身ごと捨てる。** 順を無視して平らに読むのではない。

最初の版は、層の中の黒の規則が後ろにあったので、層が効いても効かなくても黒になり、判定に使えなかった。判定には「層の中にしか無い規則」を置く。

Kindle に届く CSS からは、層を外した（平らにした）規則を作る必要がある。層の順を詳細度や記述の順で再現する変換が要る。

---

## 3. 縦書き

### 3.1 Vivliostyle の PDF

`html { writing-mode: vertical-rl; }` の 7 ページの文書を組んだ。`@page :left` / `:right` / `:recto` / `:verso` の余白の箱に目印を書き、各ページの目印を読んだ。

- **奇数ページは左（`:left` かつ `:recto`）**、偶数ページは右（`:right` かつ `:verso`）。横書きの逆になる
- `break-before: recto` の章は左ページから始まる
- `:recto` / `:verso` の擬似クラスは使える
- ノドと小口の割り当て（`@page :left` の `margin-right` がノド）は、見開きの内側がノドなので綴じの向きに依らず正しい
- **余白の箱の文字も縦に組まれる**（`pdftotext` では `LEFT p1` が逆順の `1p TFEL` になる）。柱やノンブルを横に組むには、余白の箱に `writing-mode: horizontal-tb` を指定する。公式の theme-base は `--vs-page--mbox-writing-mode: horizontal-tb` で指定している
- ルビ（`ruby`/`rt`）・縦中横（`text-combine-upright: all`）・傍点（`text-emphasis: filled sesame`）・「……」・「――」は、画面で見て正しく組まれた
- **全面の挿絵は縦横比が崩れた**: `figure.full img { block-size: 100%; inline-size: auto; max-inline-size: 100%; }` で、横長（600 × 400）の画像が縦長に引き伸ばされた。縦書きでは `inline-size` が高さ、`block-size` が幅になるので、横書きの感覚で書いた寸法の指定はそのまま使えない。全面の挿絵は別に設計する（`object-fit` か、挿絵だけ `writing-mode: horizontal-tb` にするか。公式の theme-bunko は `figure` を `horizontal-tb` にしている）

vs への影響: `build/nombre_stamper.rb` は「奇数ページは右」として隠しノンブルをノドに置く（`v2-inventory-report.md` §3.2）。右綴じでは左右が逆になる。

### 3.2 Kindle

最小の EPUB 3 を Ruby で組み立てた（`spine` に `page-progression-direction="rtl"`、`<meta name="primary-writing-mode" content="vertical-rl"/>`、CSS に `writing-mode: vertical-rl` と `-epub-writing-mode`）。EPUBCheck はエラー・警告とも 0。

- `kindlepreviewer <epub> --convert --output <dir> --locale ja`（vs の `convert_epub_to_kpf!` と同じ引数）で **KPF が生成された**。Enhanced Typesetting は Supported、記録の指摘は「カバーが指定されていません」（W14016）だけ
- Kindle Previewer の画面で、ページが右から左へ進み、本文と目次が縦に組まれ、ルビ・縦中横・傍点・「……」・「――」が正しく出た

縦書きの小説は、今の Kindle の経路（EPUB → KPF）に載る。

---

## 4. 固定レイアウト（絵本）

1200 × 1600 px のページ 3 枚の EPUB を作った（`rendition:layout pre-paginated`・`rendition:spread landscape`・各ページの `viewport`・`page-spread-left/right`・`original-resolution`・`book-type: children`、画像の上に `position: absolute` で文字を重ねる）。EPUBCheck はエラー・警告とも 0。

- **KPF にならず Mobi になった**。記録は Enhanced Typesetting が Not Supported、変換は Success、エラー 0
- Kindle Previewer の画面では、画像がページ全体に出て文字が重なり、書体と文字の大きさの選択が無効になった（固定レイアウトとして扱われている）
- **KDP は Mobi を受け付けない**。固定レイアウトの本の Mobi は 2025-03-18 に受け付けを終えた。固定レイアウトの本は EPUB か KPF（Kindle Create で作るもの）で出す（[KDP ヘルプ](https://kdp.amazon.com/en_US/help/topic/G200634390)）

KPF にならない理由がメタデータの不足かどうかを、さらに 3 版で確かめた（2026-11-13）。どれも EPUBCheck はエラー・警告とも 0 で、変換の結果は 3 版とも Enhanced Typesetting が Not Supported・出力は Mobi だった。

| 版 | 前の版からの違い |
|---|---|
| V1 | Amazon の固定レイアウトの指針のメタデータ（`fixed-layout`・`orientation-lock`・`RegionMagnification`・`primary-writing-mode`）と表紙（`cover-image`）を足す |
| V2 | V1 から文字を外し、画像だけのページにする（コミックと同じ形） |
| V3 | V1 の `position: absolute` をやめ、文字を画像の下に流す |

Kindle Previewer 4 のコマンドラインには、固定レイアウトを指定するオプションも無い（`--convert`・`--showpreview`・`--log`・`--qualitychecks`・`--update` だけ）。KDP のヘルプは、Enhanced Typesetting は「リフロー型の Kindle 本（.epub・.doc(x)・.html でアップロードしたもの）にだけ適用される」としている（[KDP ヘルプ](https://kdp.amazon.com/en_US/help/topic/G202131170)）。**固定レイアウトの KPF は、Kindle Previewer では作れない**（作れるのは Kindle Create）。Previewer の Mobi はプレビュー用で、出版には使えない。

絵本の `kindle` は、今の経路（Kindle Previewer で KPF にする）を通らず、Amazon の指針に沿った固定レイアウトの EPUB をそのまま KDP へ出す形になる。Kindle Previewer は、その EPUB を開いて画面を確かめるためだけに使う。KDP がその EPUB を受け付けて正しく表示するかは、KDP のプレビューで確かめる必要がある（未確認）。

`kindle-fixed-layout-ideas.md` は、技術書を PDF の画像にして固定レイアウトにする案を見送った記録である。絵本は初めから固定レイアウトが前提なので、見送りの理由（端末の大きさが判型に合わない・文字の大きさを変えられない）は当てはまらない。

### 4.1 KDP へ出すファイルの形式

KDP は、リフロー型と固定レイアウトのどちらの本も受け付ける。違うのは、KDP へアップロードするファイルの形式だけである。

| 本の形 | 向いている本 | KDP へ出すファイル | vs での作り方 |
|---|---|---|---|
| リフロー型 | 技術書・小説（縦書きを含む） | KPF | 今と同じ。EPUB を作り、Kindle Previewer で KPF に変換する |
| 固定レイアウト | 絵本 | EPUB | EPUB を作り、そのまま出す。Kindle Previewer は表示の確認だけに使う |

- 固定レイアウトの EPUB は、KDP がアップロードを受けてサーバー側で Kindle の形式に変換する。Kindle Create（著者が手元で KPF を作る別のアプリ）は、この経路では使わない
- Kindle Previewer は、固定レイアウトの EPUB も開いて表示を確かめられる。できないのは、出版に使える KPF を書き出すことだけである

---

## 5. 動画

640 × 360 の `<video src="clip.mp4" poster="poster.jpg" controls>`（中に代わりの段落）を含む EPUB を作った。EPUBCheck はエラー・警告とも 0。

- Kindle Previewer の変換は **エラー**を記録した:「audio/video タグは、現在タイプセッティングの改善でサポートされていません。」（推奨の修正は「音声/動画タグを削除」）。出力は Mobi で、Enhanced Typesetting は Not Supported
- Kindle 向けには `<video>` を取り除き、決まった代わりの表示（ポスター画像と、動画へのリンク）に差し替える必要がある。§5 の「pdf と kindle は動画のサムネイル」の方針と合う
- Apple Books は、リフロー型・固定レイアウトとも HTML5 の `<video>` で動画を入れられる。ポスター画像を付けるよう求めている（[Apple Books Asset Guide](https://help.apple.com/itc/booksassetguide/en.lproj/itcd08fcb646.html)）
- macOS の Books で `<video>` を開くと、ポスター画像の上に再生ボタンが出て、押すと再生された（2026-11-13。MP4・H.264）。再生の確認には、1 秒ごとに背景の色と数字（1〜6）が変わり白い丸が動く 6 秒の動画を使い、再生を始めて約 1 秒後に「2」、約 4 秒後に「5」が出ることを画面で確かめた。最初に使った macOS の資産の動画は冒頭が白く、再生しているかを画面で判定できなかった。試験の動画は AVFoundation の `AVAssetWriter` で書き出した（ffmpeg が無くても作れる）
- Kobo は、動画入りの本（ePub3AV）を iOS と Android のアプリでだけ扱う。電子ペーパーの端末とデスクトップのアプリは対象外（[Kobo のヘルプ](https://help.kobo.com/hc/en-us/articles/360017763713-File-formats-your-Kobo-eReader-and-Kobo-Books-app-support)）

クリーン EPUB にも、再生できない読者のための代わりの表示（`<video>` の中身）が要る。

### 5.1 動画の形式

- **EPUB の規格は動画の形式を定めていない**。EPUB 3.3 の中核メディア型（core media types）は画像・音声・書体などで、動画は入っていない。EPUB Reading Systems 3.3 は、H.264 と VP8 の少なくとも一方に対応することを勧めるだけで、対応は義務ではない（[EPUB Reading Systems 3.3](https://www.w3.org/TR/epub-rs-33/)）。どの形式が再生できるかは、リーダーごとに決まる
- **Apple Books は H.264 と HEVC（H.265）を受け付ける**。どちらも MPEG-4 のコンテナに入れる。HEVC は 2019-10-28 の Asset Guide 5.2.11 で加わった。再生できない環境に向けた代わりの動画（fallback）は扱わない（[Apple Books Asset Guide](https://help.apple.com/itc/booksassetguide/en.lproj/itcd08fcb646.html)）
- **macOS の Books で HEVC の再生を確かめた**（2026-11-13）。§5 と同じ数を数える動画を `AVVideoCodecType.hevc` で書き出し（中身の識別子は `hvc1`）、再生を始めて約 1 秒後に「2」、約 4 秒後に「5」が出た。同じ動画で、H.264 は 62,350 バイト、HEVC は 43,021 バイト（約 31% 小さい）。単色の 6 秒の動画なので、実際の映像での圧縮率の目安にはならない
- Kobo の対応する形式は公開の資料で確かめられなかった。Kindle は動画を扱わない（§5）。複数のリーダーに出すなら H.264 が無難で、HEVC は Apple Books だけに出す本で選べる

### 5.2 EPUB のファイルの大きさの上限

| 出し先 | 上限 | 出典 |
|---|---|---|
| Apple Books | パッケージ全体で 2 GB。推奨は 500 MB 以下 | [Apple Books Asset Guide](https://help.apple.com/itc/booksassetguide/en.lproj/itcd08fcb646.html) |
| Google Play Books | 1 ファイル 2 GB 未満（表紙の画像を含む） | [Google Play ブックス パートナー センター](https://support.google.com/books/partner/answer/3424254) |
| KDP | 650 MB。大きいほど変換に時間がかかり、失敗することもある | [KDP ヘルプ](https://kdp.amazon.com/help?topicId=200735140) |
| Kobo Writing Life | 100 MB（画像を含む）。画像は 1 枚 3 MB 以下を推奨 | [Kobo Writing Life ヘルプ](https://kobowritinglife.zendesk.com/hc/en-us/articles/360058975512) |
| 技術書典の電子版 | 公開の資料が見つからなかった | |

- いちばん厳しいのは Kobo の 100 MB。動く絵本を複数のストアに出すなら、動画の量はこれに合わせて決める
- KDP は、70% のロイヤリティを選ぶと、ファイルの大きさに応じた配信のコストが差し引かれる（米国は 1 MB あたり 0.15 ドルとする二次資料がある。公式の値は未確認）。Kindle には動画を入れないので、絵本の画像の大きさが効く

---

## 6. EPUB リーダーの `@layer`

### 6.1 Apple Books（macOS）

4 項目を、仕様どおりなら緑、そうでなければ黒か赤になるように書いた EPUB を開いた。

| 項目 | 書いたこと | 結果 |
|---|---|---|
| 層の中だけの規則 | `@layer a { .t1 { color: 緑 } }` だけ | 緑（使われる） |
| 層の順と詳細度 | b（後の層）に詳細度の低い緑、a に詳細度の高い赤 | 緑（層の順で決まる） |
| 層の外 | 層の外に緑、b の中に詳細度の高い赤 | 緑 |
| `!important` | a に緑の `!important`、b に赤の `!important` | 緑（順が逆転する） |

**Apple Books は `@layer` を仕様どおりに扱う。** Kindle とちがい、クリーン EPUB は層を使った CSS のままで Apple Books に出せる。

最初の版は、CSS の先頭に層の外の規則 `p { color: black; }` を置いていたため、1 と 2 が黒になった。層の外の規則は層の中の規則に必ず勝つので、これは仕様どおりの結果で、判定には使えない。層の試験では、判定する性質の要素に、層の外の規則を当てない。

### 6.2 Kobo・Google Play Books（未確認）

`@layer` を解するかを示す公開の資料は見つからなかった。W3C の EPUB 3.3 の試験結果（[epub-tests](https://w3c.github.io/epub-tests/epub33/results)）にも、層の試験は見当たらない。Kobo の端末は古い描画エンジンを使い、CSS の変数や flex・grid で崩れる例が報告されている。

確かめるには、§6.1 と同じ EPUB を各リーダーの実機で開く。それまでは、クリーン EPUB に層を使った CSS を渡すか、層を外した CSS を渡すかを、出力の設定で選べる形にしておくと、対応の有無に左右されない（層を外す仕組みは Kindle 用に作るので、それを使える）。

---

## 7. 作り直すときの手順

- Vivliostyle: `node_modules/.bin/vivliostyle build index.html -o out.pdf`。結果は `pdftotext -f N -l N`・`pdfinfo`・`qpdf --qdf --object-streams=disable` の描画命令で読む
- EPUB: `mimetype` を無圧縮で先頭に置き（`zip -X0`）、残りを `zip -Xr9D` で足す。EPUBCheck を通してから変換する
- Apple Books は `open -a Books <epub>` で開く（ライブラリに取り込まれ、iCloud の同期が有効ならほかの端末にも出るので、書名を `vs-test` で始め、確かめた後に消す）。窓の位置の取り方は Kindle Previewer と同じ。ページ送りは System Events の `key code 124`、再生ボタンは CGEvent のクリック
- Kindle Previewer の画面は、アプリを開いて `CGWindowListCopyWindowInfo`（JXA。`ObjC.castRefToObject` で包んでから `deepUnwrap`）で窓の位置を取り、`screencapture -x -R` で撮る。別の本を見るときはアプリを終了してから開き直す

---

## 8. 公式テーマの入口の実験（S7a）

`theme-contract-spec.md` §9 の S7 の入口の実験。`theme-bunko` と `theme-base` を、§6.2 の形（`theme` 層・`bridge.css`）で vs の契約 HTML に当て、`vs build` で PDF と EPUB を組んだ。製品のコードは変えていない。

- 調べた日: 2026-11-18（`v2` の 9a54a56d）
- 環境: `@vivliostyle/cli` 11.3.3・`@vivliostyle/core` 2.45.1・Chromium 156（EPUB の XHTML の描画）
- 公式テーマ: `@vivliostyle/theme-bunko` 3.1.1・`@vivliostyle/theme-base` 3.1.0（どちらも 2026-11-14 の公開で、この時点の最新。§6.1 で調べた 3.1.0・3.0.1 からは、`theme-bunko` は依存の版だけ、`theme-base` は 12 ファイルが変わっている）
- 実験の本: 本書の写し。`catalog.yml` を 21 章（ルビ・脚注・囲み・コード・表）と付録 95（ルビ・脚注・囲み・図・会話文・サイドイメージ）の 2 つにした。`book.yml` は `theme.name: vivliostyle-bunko`・`page.writing_mode: vertical`・`page.use: a5_standard`・`output.targets: [pdf, epub]`。本扉・権利ページ・目次・用語集・索引・奥付も組まれる
- 検証用の本はリポジトリに入れていない。作り方は §8.5 に書いた

### 8.1 テーマの置き方

S7b の取り込みが作る形を、手で作った。

| ファイル | 中身 |
| :--- | :--- |
| `themes/vivliostyle-bunko/theme.yml` | `name: vivliostyle-bunko`・`contract: 1`・`license: CC0-1.0`・`supports: { writing_mode: [vertical], layout: [reflowable], targets: [pdf, print_pdf, epub] }`・`features: []`・`styles: [theme.css, bridge.css]` |
| `themes/vivliostyle-bunko/theme.css` | `theme-bunko` の `theme.css`。先頭の 15 行の `@import '@vivliostyle/theme-base…'` を、`theme-base` の `package.json` の `exports` で解いて `@import url('base/css/…/index.css')` に書き換えた |
| `themes/vivliostyle-bunko/base/` | `theme-base` の `theme.css`・`css/`・`LICENSE` |
| `themes/vivliostyle-bunko/bridge.css` | §8.3 の対応表 |

`vs` の入口は、テーマの `styles:` を `theme` 層に読む。入れ子の `@import` は、PDF（Vivliostyle）も EPUB（`Css::Flattener`）も解いた。

### 8.2 四つの点の結果

| 点 | 結果 | 見たもの |
| :--- | :--- | :--- |
| (a) 縦書き・右綴じで組める | **成り立つ**（PDF）。奇数ページが左で、見開きは右から左へ進む。EPUB の CSS も `html` が `vertical-rl` になる（Chromium の計算値）。ただし EPUB の `spine` は `page-progression-direction="ltr"` のまま（OPF を書くのは S8-1 の縦書きの経路で、テーマではない） | PDF の柱とノンブルの位置・Chromium の計算値・OPF |
| (b) 見出し・段落・ルビが `theme-bunko` の見た目になる | **PDF では成り立つ**。章題は明朝の太字で字間が空き、段落は 1 字下げ・両端揃え、ルビは本文の右に付く。柱は横組みで、左ページの上に「ノンブル＋章題」が出る（`theme-bunko` の `@page :left`）。**EPUB では見出しの規則が外れる**: `theme-base` の `basic.css` は `h1`〜`h6`・`ul`・`ol`・`dd`・`pre`・`th`・`td` など 14 の規則を入れ子（`h1 { & { … } }`）で書いており、vs の平らな CSS の生成はこれを読めずに外す（ビルドの 🟡 が 14 件）。**2026-11-18 に vs が入れ子を開くよう直した**（`css-layer-restructure-spec.md` §10.11） | PDF の紙面・ビルドの記録 |
| (c) vs の部品（脚注・囲み・図）が崩れない | **§6.2 の置き方では成り立たない**（PDF。`bridge.css` で部品を読み直すと、本文のページでは戻る。§8.6）。理由は二つある。(1) **層の位置**: `theme-base` の `reset.css`（`* { border-width: 0 }`・`pre { margin-block: 0 }` など）と `basic.css` の要素の規則が `theme` 層にあり、PDF では詳細度に関係なく `parts`・`pages` 層の vs の規則に勝つ。囲み（`.memo`・`.column`・`.tip`・`.output`）・表・図の枠が全部消え、`p { font-size }` が book-card や奥付の字の大きさを、`a { color }` が索引のリンクの色を上書きする。EPUB は平らな CSS で詳細度が勝ち負けを決めるので、vs の部品の規則が勝ち、枠が出る。**PDF と EPUB で見た目が割れる。** (2) **vs の部品の物理方向**: 公式テーマに依らず、vs の部品が縦書きを想定していない箇所がある（§8.4） | PDF の紙面・要素ごとの判定（§8.3） |
| (d) 判型が vs の `page.use` の値になる | **成り立つ**（対応表を直した後）。A5（419.53 × 595.28 pt）で、本文の版面の余白は実測でノド 22 mm・小口 18 mm・天地 21〜22 mm（`a5_standard` の値）。`@page { size }` は vs の settings 層が書くので、テーマの `@page { width; height }` があっても紙の寸法は vs の値になる | `pdfinfo`・`pdftotext -bbox` |

### 8.3 層を外すと勝ち負けが変わる組（要素ごとの判定）

`vs build --log=debug` の EPUB の要素ごとの判定（`Css::InversionCheck.inversions`）の数。種類ごとの数（章 140・付録 169・用語集 44・索引 23・奥付 26）は重なりを含み、重なりを除くと **301 組**である。どれも「PDF では公式テーマの規則が勝ち、EPUB では vs の規則が勝つ」組で、PDF と EPUB の見た目の違いの数になる。

| 層ありで勝つ規則（公式テーマ） | 平らな CSS で勝つ規則（vs） | 組 |
| :--- | :--- | ---: |
| `theme-base` の `basic.css`（要素の規則） | `parts` 層 | 110 |
| `theme-base` の `reset.css` | `parts` 層 | 67 |
| `theme-base` の `basic.css` | `pages` 層（用語集・索引・奥付） | 51 |
| `theme-bunko` の `theme.css`（`figure` の余白など） | `parts` 層 | 32 |
| `theme-base` の `reset.css` | `pages` 層 | 28 |
| `theme-base` の `basic.css` | `base` 層（`:root` の書体と字の大きさ） | 7 |
| `theme-base` の `footnote/index.css` | `parts` 層（脚注） | 6 |

プロパティでは、`margin-top`（36）・枠の 3 つ（`border-right-*` が各 23）・`font-size`（15）が多い。vs の側は `parts/box.css`（46）・`pages/glossary.css`（37）・`parts/talk.css`（31）・`parts/figure.css`・`parts/code.css`（各 24）の順である。

`theme-base` の土台の 2 ファイルを vs の部品より下の層に置いた場合も試した（vs の製品のコードを変えずに試すため、写しの `stylesheets/base/page.css` の先頭で `@import` した。`base` 層の最後に入る）。

| 置き方 | 組 | PDF の紙面 |
| :--- | ---: | :--- |
| A: §6.2 のとおり、全部 `theme` 層 | 301 | 囲み・表・図の枠が消える。見出しは `theme-bunko` の見た目 |
| C: `reset.css` だけを `base` 層へ | 206 | 枠は出る。`basic.css` の要素の規則（字の大きさ・リンクの色・余白）は vs の部品に勝ったまま |
| B: `reset.css` と `basic.css` を `base` 層へ | 47 | vs の部品は 1.x と同じ見た目に戻る。章題は vs の見出しの見た目（ゴシック）になり、`theme-bunko` の見出しの見た目は失われる。残る 47 組は `theme-bunko` の `theme.css`（32）・脚注（6）と、`base` 層の `basic.css` と vs の部品の組（9） |

`vs theme:check vivliostyle-bunko`（A の置き方）は、🟡 が 49 件（契約 HTML に無いクラス 33・入れ子の書き方 14・vs の内部のクラス `.footnote-ref` 2）、静的な組の 💡 が 2,269 組だった。

### 8.4 vs の部品が縦書きで崩れた箇所（公式テーマに依らない）

S8 の材料（`novel-vertical-spec.md` §3.4 の「部品の 3 段」）。どの置き方（A・B・C）でも、EPUB（Chromium）でも同じに出た。

| 箇所 | 崩れ方 | 原因の見当 |
| :--- | :--- | :--- |
| 権利ページ | 内容が出ず、白紙が 12 ページ続く | `pages/legalpage.css` の `body { min-block-size: 100vh; display: grid; align-content: end; }`。縦書きでは `block-size` が横の長さになる。`theme-bunko` が `:root` の `--vs-writing-mode` を `vertical-rl` にするので、vs が横に組むつもりのページ（権利ページ・奥付。`novel-vertical-spec.md` §2.2）も縦になる |
| 前付けのノンブル | 本扉・権利ページの上に、130 番台のノンブルが出る（本文と別に組む前付けの PDF の通し番号） | `theme-base` の `@page` の余白の箱（上の小口）が、vs が前付けで消している箱（下）と別の位置にあり、打ち消されない |
| 節の見出しと節リード | 重なる（PDF・EPUB とも） | **縦書きに依らない**（§8.7 で横書きの公式テーマでも重なった）。`parts/heading.css` の `.section-lead { margin-block: -15mm 1.5rlh }` が、`standard` の見出しの形を前提に節リードを上へずらしている。`standard` は見出しの CSS（`image-header.css`・`simple-header.css`）で打ち消しているが、ほかのテーマは打ち消さない。部品からテーマへ移す候補（`theme-contract-spec.md` §10 の論点 5・S8-5） |
| 囲みのラベル（MEMO・COLUMN） | 本文の上に重なる | ラベルの位置が物理方向（`top`・`left`） |
| サイドイメージ | 絵と説明が離れ、絵が次のページへ送られる | 横に並べる部品（`novel-vertical-spec.md` §3.4 の「縦書きでは使えない」の候補） |
| 相互参照のリンクの下線 | 縦の行を横切る線になる | `border-bottom` |
| 章題（EPUB） | 2 行に分けた章題の 2 行目が 1 行目に重なる | 見出しの `line-height` か `<br>` の扱い。PDF では重ならない |

脚注（PDF は版面の左に区切りの線と注の行が出る）・ルビ・表・図（`figure` は `theme-bunko` が `horizontal-tb` にする）・会話文・コラムの本文は、縦に読める形で出た。

### 8.5 作り直すときの手順

1. `npm pack @vivliostyle/theme-bunko@3.1.1 @vivliostyle/theme-base@3.1.0` を一時ディレクトリで行い、展開する。
2. 本書の素材（`scripts/build_copy.rb` の `MATERIALS`）を写し、§8.1 のとおりテーマを置き、`catalog.yml` を 2 章にする。
3. `ruby scripts/build_copy.rb --book <写し> --out <組む先> --no-clean --targets pdf,epub --set theme.name=vivliostyle-bunko --set page.writing_mode=vertical --set page.use=a5_standard -- --log=debug`。要素ごとの判定は記録の `層を外すと勝ち負けが変わる組` の行。
4. 版面は `pdftotext -bbox -f N -l N` の文字の箱の最小と最大から余白を求める。EPUB は展開した XHTML を Chromium で開き、`getComputedStyle(document.documentElement).writingMode` と画面を見る。

**対応表の落とし穴。** 最初の版は `--vs-page--width` に紙の幅（vs の内部の変数 `--page-width`）を渡し、本文が紙の外へはみ出した。`theme-base` の `@page { width; height }` は、紙ではなく版面（ページの内容の箱）の寸法である。`theme-bunko` は行数と字数から版面を求め、余白は `auto`（中央に寄せる）にしている。vs の値を渡すときは、版面 = 紙 − 余白（`calc(var(--page-width) - var(--book-page-margin-inner) - var(--book-page-margin-outer))`）を渡し、余白は `@page :left`・`:right` ごとに `--vs-page--margin-left`・`--vs-page--margin-right` へノドと小口を渡す（`@page` の中の変数の定義は Vivliostyle が読んだ）。紙の寸法は公開する変数（`--book-*`）に無いので、S7b で対応表を作るなら、公開する変数を足すか、内部の変数を読むかを決める必要がある。

**本の設定の 🟡。** `standard` のオプション（`theme.color`・`theme.style` など 8 つ）を書いた本で `theme.name` を替えると、`TraitCombinationCheck` が「テーマ vivliostyle-bunko には無い設定です」の 🟡 を 8 件出す。仕様どおりの動きだが、S7b の完了の条件「`theme.name` を替えるだけで組める」は、🟡 が出る状態で組めることになる。

### 8.6 `bridge.css` で vs の部品を読み直す（2026-11-18・S7a の追加）

§8.3 の (c) の原因（`theme-base` の土台の規則が、PDF で層の順によって vs の部品に勝つ）を、製品のコードと層の順を変えずに直せるかを試した。CSS の入れ子を vs が開くようにした後（`css-layer-restructure-spec.md` §10.11。d5d28a74）で、置き方 A も組み直した。

**やり方。** `bridge.css` の先頭で、vs の部品の CSS（`stylesheets/parts/*.css`）をもう一度 `@import` する。`bridge.css` は `theme` 層の最後に読まれるので、読み直した部品の規則は公式テーマと同じ層に入る。同じ層の中では詳細度で勝ち負けが決まるので、クラスで書いた vs の部品の規則が、要素で書いた `theme-base` の規則（`* { border-width: 0 }`・`p { font-size }` など）に勝つ。平らな CSS（EPUB）と同じ決まり方になるので、PDF と EPUB の差も縮む。

| 置き方 | 読み直す部品 | 組 | PDF の紙面 |
| :--- | :--- | ---: | :--- |
| A（§6.2 のとおり。入れ子を開いた後） | なし | 337 | 囲み・出力例・横並びの枠が消える。見出しと段落は `theme-bunko` の見た目 |
| D | vs だけの部品 13（`prism`・`code`・`layout`・`sideimage`・`side-by-side`・`book-card`・`footnote`・`math`・`epub-reflow`・`talk`・`reference`・`figure`・`box`） | 138 | 枠が戻る。表・リストの vs のクラス（`.def-list`・`.table-caption`・`.long-table`・タスクリスト）は公式テーマの値のまま |
| **D2** | D に `table`・`list` を足した 15（見出し `heading` と段落 `prose` だけを公式テーマに任せる） | **104** | 枠・表の見出しの網掛け・リストの印が vs の見た目に戻り、見出し・段落・ルビ・柱は `theme-bunko` の見た目のまま |

A の組が §8.3（301）より増えたのは、入れ子で書かれていた見出しなどの規則 14 件が EPUB にも届くようになり、判定の対象に入ったためである。

**D2 で残る 104 組の内訳。**

| 組 | 数 | 扱い |
| :--- | ---: | :--- |
| `theme-base` と、用語集・索引・奥付のページの CSS（`pages` 層） | 89 | `bridge.css` では直せない。テーマの CSS はページの種類によらず同じものが読まれ、`pages/*.css` は `body` などを種類で絞らずに書いているので、全部のページで読み直すと別のページを崩す。紙面は縦に読める形で出た（字の大きさ・リンクの色・定義リストの余白に公式テーマの値が当たる）。直すなら、ページの種類ごとに読む口が要る（S7b で決める） |
| `theme-base` と、段落（`prose`）・見出し（`heading`）の部品 | 8 | 公式テーマに任せた部分（`.chapter-lead p` の字下げなど） |
| `theme-base` の `html` と、vs の `:root` の書体と字の大きさ | 7 | `bridge.css` で同じ値を渡しているので、見た目は変わらない |

章と付録のページだけで数えると、D2 の組は 15 と 13 だった（A は 162 と 171）。

**読み直しで起きうること。** 読み直した部品の規則は `pages` 層より上に入るので、`pages/chapter.css` などが部品の規則を上書きしている箇所があれば、その上書きが PDF で負ける。D と D2 の判定では、読み直した部品とページの CSS の組は 0 だった（本書の 2 章の範囲）。

### 8.7 ほかの公式テーマ（2026-11-19・S7a の追加）

ユーザーの提案で、bunko のほかの公式テーマでも同じ実験をした。公開されている公式テーマは 7 つ（`theme-base`・`theme-bunko`・`theme-techbook`・`theme-academic`・`theme-gutenberg`・`theme-epub3j`・`theme-slide`）。本の形でない `theme-slide` と、土台の `theme-base` を除いた 4 つを、§8.6 の置き方 A と D2 で組んだ。どれも横書き（epub3j の縦書きは HTML の `.vrtl` クラスで切り替える作りで、vs の HTML には無い）。比べる相手は、同じ 2 章を `standard` で組んだもの（92 ページ・組 0）。

| テーマ | 版 | 土台 | A の組 | D2 の組 | D2 の PDF |
| :--- | :--- | :--- | ---: | ---: | :--- |
| `theme-techbook` | 3.1.1 | `theme-base` 3.1.0 | 332 | 105 | 106 ページ |
| `theme-academic` | 3.1.1 | `theme-base` 3.1.0 | 324 | 105 | 87 ページ |
| `theme-gutenberg` | 3.1.1 | `theme-base` 3.1.0 | 323 | 105 | 120 ページ |
| `theme-epub3j` | 2.1.0 | なし（電書協の制作ガイドの CSS） | 149 | 51 | 90 ページ |

D2 では 4 つとも、囲み・出力例・表の枠が戻り、見出しと段落はそのテーマの見た目になった（gutenberg の飾りの頭文字など）。`theme-base` を使う 3 つの D2 の 105 組の内訳は bunko と同じ形（用語集・索引・奥付の `pages` 層が大半）。

**対応表で直したこと（どれも S7b の `bridge.css` の生成に入れる）。**

1. **`--vs-line-height` には倍率を渡す。** 最初は `--book-line-height`（17pt の長さ）を渡し、academic と gutenberg の組版が止まった（Vivliostyle の待ち時間切れ 300 秒 × 3 回）。`theme-base` の `--vs-spacing-rlh: calc(var(--vs-line-height) * 1rem)` が長さ × 長さの無効な計算になり、脚注の部品（`css/footnote/index.css`）を読み込んだときに組版が終わらなくなる（読み込みを一つずつ外して特定した）。bunko は `--vs-spacing-rlh: 0` を自分で書いているので止まらず、techbook は止まらなかったが 413 ページに膨らんでいた。倍率（実験では `a5_standard` の 1.7 を直に書いた）を渡すと、どれも 1 分前後で組めた。**vs の公開する変数には行送りの倍率が無い**（`--book-line-height` は長さ）ので、S7b で足すか決める。
2. **`theme-base` の番号を出さない。** 付録・節・図・表などの番号の表示（`--vs-appendix--marker-display`・`--vs-section--marker-display` など 8 つ）を `none` にする。番号は vs が契約 HTML に書くので、出すと「付録A　付録A」と二重になる（techbook・academic・gutenberg）。bunko は日本語のときに自分で消している。
3. **見出しとコードの書体も渡す**（`--vs--heading-font-family`・`--vs--monospace-font-family`）。academic は見出しを Hiragino Kaku Gothic ProN にしていて、54 ページで字が Type 3 になった。
4. **変数を持たないテーマには、書体を規則で渡す。** epub3j は本文を `serif-ja, serif`（電書協のガイドの総称の名前）で組むので、PC では本の書体が使われず、87 ページで Type 3 になった。`bridge.css` に `html, body`・見出し・コードの `font-family` の規則を書くと 0 になった。

直した後の D2 で、Type 3 の 🟡 は 4 つとも 0。

**残ったもの。**

| 箇所 | テーマ | 扱い |
| :--- | :--- | :--- |
| 節リードが見出しに重なる | techbook・academic・gutenberg（bunko も） | vs の部品の側の問題（§8.4 の表を直した）。S8-5 で `novel` を書くときに部品からテーマへ移す |
| 柱とノンブルが二重に出る | epub3j | epub3j の `@media print` の `@page`（上に題名・下にノンブル）と、vs の余白の箱が別の位置にある。取り込みのときに打ち消すか、S7b で決める |
| 用語集・索引・奥付の 89 組 | `theme-base` の 3 つ | §8.6 のとおり。ページの種類ごとに読み直す口が要る |
