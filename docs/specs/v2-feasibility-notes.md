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
| Apple Books は EPUB の動画を再生するか | **する**（ポスター画像と再生ボタンが出て、再生できた） | Books の画面 |
| Kobo・Google Play Books の `@layer` の対応 | **未確認**（公開された資料が見つからない・手元に無い） | Web の調べ |

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
- macOS の Books で同じ `<video>` を開くと、ポスター画像の上に再生ボタンが出て、押すと再生された（2026-11-13。MP4・H.264）
- Kobo は、動画入りの本（ePub3AV）を iOS と Android のアプリでだけ扱う。電子ペーパーの端末とデスクトップのアプリは対象外（[Kobo のヘルプ](https://help.kobo.com/hc/en-us/articles/360017763713-File-formats-your-Kobo-eReader-and-Kobo-Books-app-support)）

クリーン EPUB にも、再生できない読者のための代わりの表示（`<video>` の中身）が要る。

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
