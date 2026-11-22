# covers/ — 表紙画像ディレクトリ

書籍の表紙・裏表紙に使用する画像ファイルを配置するディレクトリです。

## ファイル構成

```
covers/
  bundled/
    frontcover.svg    ← gem 同梱のテンプレート（編集不要・vs upgrade で更新）
    backcover.svg     ← gem 同梱のテンプレート（編集不要・vs upgrade で更新）
  templates/
    frontcover_b5.png ← 画像を自作するときの雛形（A4・B5・A5 の表と裏・vs upgrade で更新）
  frontcover_master.png ← 著者が用意するマスター画像（任意）
  backcover_master.png  ← 裏表紙のマスター画像（任意）
```

## 表紙画像の生成

```bash
vs cover    # config/book.yml の設定に従って表紙画像を生成
```

`config/book.yml` の `book.cover` でテーマ名を指定します（未指定なら `light`）。`light` / `dark` は gem 同梱テンプレートを使用しますが、`master`、`special`、`awesome` など任意のスラッグ(ファイル名)を指定することもできます。著者独自の表紙画像を用いる場合には `covers/frontcover_<theme>.png`（`.jpg`・`.jpeg`・`.webp` も可）や `covers/frontcover_<theme>.svg` を用意してください。

`templates/` の雛形は、画像を自作するときの下敷きです。判型に合うものを開いて描き、文字と線を削除してから `covers/frontcover_<theme>.png`（例: `frontcover_master.png`）として保存し、`book.cover` をそのテーマ名にします。

## bundled/ と templates/ は直さない

`bundled/` と `templates/` のファイルは、Vivlio Starter が用意する見本です。`vs upgrade` で新しい版に置き換わるので、手を加えた内容は残りません。手を加えたいときは、`covers/` の直下へ写し、`frontcover_<theme>.svg` などの名前を付けてから直してください。

同梱の SVG を写した場合、背景の色の印（`{{bg-from}}`・`{{bg-to}}`）は、色の値に書き換えなければ `light` の色になります。書名などの `{{title}}` は、`config/book.yml` の値に置き換わります。

## ソースの優先順位

1. `covers/<side>cover_<theme>.png` — 著者が用意した画像（`.jpg`・`.jpeg`・`.webp` も可。この順に探す）
2. `covers/<side>cover_<theme>.svg` — 著者が用意した SVG
3. `covers/bundled/<side>cover.svg` — gem 同梱テンプレート（`light`・`dark` のみ。自動でテキスト置換）

## クリーンアップ

```bash
vs clean --cover    # 生成されたカバー画像を削除（マスター画像は保持）
```
