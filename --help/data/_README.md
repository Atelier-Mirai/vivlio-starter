# data/ — QueryStream データディレクトリ

原稿内で展開する外部データ（YAML形式）を配置するディレクトリです。

## QueryStream とは

原稿の中に `= データ名` と記述するだけで、YAML データをテンプレートに従って自動展開できる機能です。参考書籍の一覧、都道府県データ、製品リストなど、繰り返し登場する情報の管理に便利です。

## ファイル構成例

```
data/
  books.yml           ← 参考書籍リスト
  technical_books.yml ← 技術書リスト
```

## 原稿での使い方

```markdown
= books                    # 全件展開
= books | tags=ruby        # タグで絞り込み
= books | -year | 3        # 年度降順・3件
= book  | タイトル名       # 1件検索
```

## テンプレートとの対応

データの展開テンプレートは `templates/` ディレクトリに配置します。

- `data/books.yml` → `templates/_book.md`
- `data/technical_books.yml` → `templates/_technical_book.table.md`

詳細は「データ展開機能の使い方」の章を参照してください。
