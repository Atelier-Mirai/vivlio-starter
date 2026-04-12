# covers/ — 表紙画像ディレクトリ

書籍の表紙・裏表紙に使用する画像ファイルを配置するディレクトリです。

## ファイル構成

```
covers/
  bundled/
    frontcover.svg    ← gem 同梱のテンプレート（編集不要）
    backcover.svg     ← gem 同梱のテンプレート（編集不要）
  frontcover_light.svg  ← vs cover で生成（自動生成物）
  frontcover_dark.svg   ← vs cover で生成（自動生成物）
  frontcover_master.png ← 著者が用意するマスター画像（任意）
```

## カバー画像の生成

```bash
vs cover    # config/book.yml の設定に従ってカバー画像を生成
```

`config/book.yml` の `output.cover.theme` でテーマ名を指定します。`light` / `dark` は gem 同梱テンプレートを使用しますが、`master`、`special`、`awesome` など任意のスラッグ(ファイル名)を指定することもできます。その場合は `covers/frontcover_<theme>.png` または `covers/frontcover_<theme>.svg` を著者が用意します。

## ソースの優先順位

1. `covers/<side>cover_<theme>.png` — 著者が用意した PNG
2. `covers/<side>cover_<theme>.svg` — 著者が用意した SVG
3. `covers/bundled/<side>cover.svg` — gem 同梱テンプレート（自動でテキスト置換）

## クリーンアップ

```bash
vs clean --cover    # 生成されたカバー画像を削除（マスター画像は保持）
```
