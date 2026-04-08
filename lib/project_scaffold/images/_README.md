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

## 対応フォーマット

原稿には `.webp` 形式を推奨します。PNG/JPG は `vs resize` で WebP に変換できます。

```bash
vs resize              # images/ 全体を標準品質で WebP 変換
vs resize --high       # 高品質で変換（quality=90）
vs resize 11-intro     # 特定章の画像のみ変換
```

`vs build` 実行時にも自動で WebP 変換が行われます。既存の WebP がある場合はスキップされます。

## 原稿での参照方法

```markdown
![説明テキスト](image.webp)
![説明テキスト](image.webp){width=80%}
![](image.webp){width=80% align=right}
```

画像パスは章ファイルからの相対パスで記述します。
