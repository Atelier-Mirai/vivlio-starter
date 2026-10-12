# 電子書籍の表紙の JPEG を 1 つの作り方にそろえる

> 状態: 実装済み（2026-10-12）
> 発端: 改善案.md #91「Kindle の表紙の扱いを公式の資料で調べる」

## 1. 調べた結果（公式の資料）

- **KDP では、本の中に表紙を入れない。**
  - Kindle Publishing Guidelines 2026.3 の §4.2「Internal Content Cover Image Is Mandatory」には、
    "This cover image guidance doesn't apply to KDP eBooks." とある（2019.2 版で明記）。
  - KDP の eBook Manuscript Formatting Guide には、"Don't include your cover image in your manuscript file.
    When you publish your eBook, we'll automatically add the cover image you provide during title setup." とある。
  - 今の `kindle.embed: false`（KPF に表紙を入れない）は公式どおり。変えない。
- **表紙は KDP の登録画面で別に上げる。** 指定は次のとおり（KDP の表紙のヘルプとガイドライン §4.1）。
  - JPEG（推奨）か TIFF。
  - 理想は縦 2,560 × 横 1,600 px。高さ÷幅は 1.6 以上が理想。
  - RGB（CMYK は不可）。5MB 以下（KDP のヘルプは 50MB 未満）。
  - なるべく圧縮しない。

## 2. 直す前の食い違い

1. **作り方が 3 通りあった。**
   - PNG のテーマ（`master` など）: 縦 2,560 に縮め、中央の横 1,600 を切り出す。品質 90。
   - SVG のテーマ（`light`・`dark`・著者の SVG）: 判型の寸法を 150dpi で焼いていた。
     A4 なら 1,240 × 1,754 px で、KDP の理想の寸法に届かない。
   - SVG のテーマで裏表紙だけ PNG があるとき: 寸法を変えずに書き出していた。
2. **色の情報**: 著者の画像の色の情報（Display P3 など）が、そのまま JPEG に残っていた。
3. **置き場所**: JPEG は `.cache/vs/covers/` にしかなく、KDP へ上げるには著者がキャッシュを探す必要があった。
4. **Kindle だけのビルドで SVG のテーマの JPEG が作られなかった**（`targets` に `epub` があるかしか見ていなかった）。

## 3. 直し方

- **作り方を 1 つにする。** `CoverCommands.write_ebook_cover!(source, output)` が、どの経路の元画像からでも同じ JPEG を作る。
  - 縦 2,560 px に縮め、中央の横 1,600 px を切り出す（`EPUB_SIZE`）。左右を切ることは 43・44 章に書いてある。
    同梱の `light`・`dark` は左右の細い金の縦線（x=28・565）が切り落としにかかるが、上下の金の帯だけでも
    表紙の絵として成り立つので、テンプレートは変えない（2026-10-12 にユーザーが画像で確認）。
  - 色は sRGB に直す（§3.1）。
  - 品質は 95（`EBOOK_COVER_QUALITY`）。EPUB と Kindle で同じ 1 枚を使う。
  - SVG は、rsvg-convert で縦 2,560 px の PNG に焼いてから渡す（判型の比のまま）。
- **電子書籍のターゲット**（`epub` か `kindle`）があるときだけ作る。PDF だけのビルドでは作らない。
- **プロジェクトの直下へ写す。** 名前は入稿用の表紙の PDF と同じ形で、拡張子だけ変える（`<project>_frontcover_v<版>.jpg`）。
  - キャッシュ側は、EPUB へ入れる元として残す。
  - `vs clean --purge` で消す（KPF などほかの成果品と同じ）。`.gitignore` で追跡しない。

### 3.1 sRGB の色の情報

- OS にある sRGB の色の情報を、決まった場所から探す。
  - macOS: `/System/Library/ColorSync/Profiles/sRGB Profile.icc`
  - Linux: colord・Ghostscript の置き場所
- 見つかれば、ImageMagick の `-profile` で、元の色の情報から sRGB へ変換する。元に色の情報が無い画像は、sRGB とみなして sRGB の情報を付ける。
- 見つからなければ変換せず、元の色の情報のまま出す。KDP の指定（RGB）は満たすので、🟡 は出さず、`--log` のときだけ知らせる。
- gem に色の情報のファイルは同梱しない。

## 4. 変えないこと

- Kindle 用の KPF に表紙を入れない（`kindle.embed: false`）。
- クリーン EPUB の `epub.embed: true`（Vivliostyle の `cover.xhtml`）。
- 入稿用・閲覧用の表紙の PDF。
