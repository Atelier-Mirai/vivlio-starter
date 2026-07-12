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

## データ用画像の配置

`cover:` などデータが参照する画像は、`data/` 配下に置いてデータ一式を自己完結にできます。YAML の値やテンプレートが**素のファイル名**（`relativity.webp` のようにスラッシュを含まないもの）で画像を指すとき、ビルド時に次の順で探索します。

1. `images/<章スラッグ>/<名前>` — 従来どおり。章ローカルが最優先（章ごとに差し替えたいとき）
2. `data/<データ名>/<名前>` — データファイルと同名のフォルダ（例: `data/physics_books.yml` → `data/physics_books/`）
3. `data/images/<名前>` — データ横断の共有プール

```
data/
  physics_books.yml
  physics_books/       ← ① そのデータ専用の画像
    relativity.webp
    quantum.webp
  images/              ← ② 複数のデータで共有する画像
    common_badge.webp
```

### ① と ② の使い分け

**その画像を参照するデータファイルが 1 つか複数か**で決めます。

- **① `data/<データ名>/`** — そのデータファイル**専用**の画像。「yml ＋ 同名フォルダ」のペアで自己完結し、コピーだけで別プロジェクトへ持ち運べます。迷ったらこちら
- **② `data/images/`** — **複数のデータファイル**から参照される共有画像。例えば `books.yml` と `technical_books.yml` の両方に載る本の表紙は、各 yml に `cover: ruby_book.webp` と書き、実体は `data/images/ruby_book.webp` に 1 枚だけ置きます

> QueryStream にはファイル間参照の仕組みがないため、共通レコードの**文字情報**は各 yml に重複して書きます。重複そのものを避けたい場合は、1 つの yml にまとめてタグで絞り込む（`= books | tags=technical`）方法が本来の設計です。その場合は画像も ① に置けて完全に自己完結します。

見つからない場合は、探索した 3 箇所を挙げた警告が表示されます。`.webp` / `.png` / `.jpg` は拡張子違いも自動で解決します（`.webp` を優先）。

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
