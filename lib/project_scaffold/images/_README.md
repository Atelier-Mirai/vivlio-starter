# images/ — 画像ディレクトリ

書籍内で使用する画像ファイルを配置するディレクトリです。

## ディレクトリ構成

章ごとにサブディレクトリを作成して管理します。

```
images/
  11-intro/
    logo.png
    diagram.png
  12-setup/
    screenshot.png
```

`vs create` で章を作成すると、対応する画像ディレクトリが自動生成されます。

章のほかに、次の 2 つのディレクトリがあります。

- `characters/` — 会話文の話者アバター（置き方は `characters/_README.md` を参照）
- `gaiji/` — 書体にない字の形を `vs build` が保存する場所（手で置くものではありません）

## 対応フォーマット

画像の形式は PNG・JPG・WebP・SVG のどれでも構いません。`vs build` が PDF・EPUB・Kindle それぞれに適した形式へ変換して使います。変換した画像は作業用のフォルダ（`.cache/`）に作られるので、`images/` に置いた画像は書き換えられません。

## 原稿での参照方法

```markdown
![説明テキスト](image.webp)
![説明テキスト](image.webp){width=80%}
![](image.webp){width=80% align=right}
```

原稿にはファイル名だけを書きます。ビルド時に、その章のディレクトリ（`images/<章のファイル名>/`）から探します。ほかの章の画像を使うときは、`images/11-intro/logo.webp` のように `images/` から書きます。
