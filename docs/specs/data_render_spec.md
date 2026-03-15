# data_render 仕様書

## 1. 背景

- vivlio-starter で執筆する書籍の原稿（`contents/*.md`）内に、外部データを埋め込みたいニーズがある。
- 参考書籍の紹介、都道府県データ、天気・気温・降水量など、繰り返し登場するデータを一元管理したい。
- 原稿ファイルは QueryStream 記法のまま保持し、`vs build` 時に `pre_process` メソッド群によりテンプレートに従って展開され、後段の処理へ渡される。

## 2. ゴール

1. 著者が `data/` に YAML ファイルを置き、`templates/` にテンプレートを置くだけで、原稿内から簡潔な記法でデータを展開できるようにする。
2. 設定より規約（Convention over Configuration）を基本方針とし、ファイルを置くだけで自動的に記法が有効になる。
3. 原稿ファイルは記法のまま保持し、`vs build` 時に展開され後段の処理へ渡される（中間ファイルを生成しない）。
4. Bridgetown / Hanami などの Ruby エコシステムの規約に寄せ、著者にとって馴染みやすい設計にする。

## 3. 用語

- **データファイル**: `data/*.yml`。展開するデータの実体。
- **テンプレートファイル**: `templates/_[name].md.slim` または `templates/_[name].[style].md.slim`。データの表示レイアウト。
- **QueryStream**: 原稿内に記述する `= books | ruby | full` のような展開指示。パイプ（`|`）で源泉・抽出・表現の3ステージを区切る。
- **スタイル**: `standard` / `full` などの表示バリエーション名。著者が自由に追加可能。スタイル未指定時はデフォルトテンプレート（`_[name].md.slim`）を使用する。

## 4. ディレクトリ構成

```
data/
  books.yml             # 書籍データ
  prefectures.yml       # 都道府県データ（例）
  weather_reports.yml   # 気象観測データ（例）
  elements.yml          # 元素周期表データ（例）

templates/
  _books.md.slim        # 複数件・デフォルト
  _books.standard.md.slim
  _books.full.md.slim
  _book.md.slim         # 一件・デフォルト
  _book.standard.md.slim
  _book.full.md.slim
```

### 命名規約

```
_[データ名].md.slim              # デフォルトテンプレート
_[データ名].[スタイル名].md.slim  # バリエーション
 ↑パーシャル                      ↑フォーマット.エンジン
```

- 先頭の `_` はパーシャル（部分テンプレート）を示す（Hanami / Rails の規約に準拠）。
- `md` はVFM Markdown出力フォーマット、`slim` はテンプレートエンジンを示す。
- スタイル名は著者が自由に追加可能。`templates/_books.my-custom.md.slim` を置くだけで `= books | | my-custom` が有効になる。
- デフォルトテンプレート（`_[name].md.slim`）が存在しない場合はERRORを出力して処理を中断する。フォールバックは行わない。

## 5. データファイル仕様

### 5.1 データファイル全般の規約

以下の規約は `books.yml` に限らず、著者が `data/` に追加する**すべてのデータファイル**に適用される。

**複数値フィールドの記法**

複数の値を持つフィールドは、配列とカンマ区切り文字列のどちらでも記述可能。テンプレート側で透過的に扱う。

```yaml
# 配列形式
tags: [ruby, beginner]

# カンマ区切り文字列形式（どちらでも同じ結果）
tags: ruby, beginner
```

**キー名の単複について**

キー名の単複は著者に委ねる。ただし同一ファイル内では統一すること。

```yaml
# ✅ 正しい（ファイル内で統一されている）
author: まつもとゆきひろ, 高橋征義

# ❌ 使わない（同一ファイル内で単複が混在している）
author: まつもとゆきひろ
authors: [高橋征義, 松田明]
```

**`id` フィールドについて**

`id` は省略可能。`id` がない場合、後述の主キー自動解決により `title`, `name`, `code`, `no` などで検索できる。

### 5.2 データファイル例

**`data/books.yml`**

```yaml
- title: 楽しいRuby
  author: 高橋征義
  desc: Rubyを楽しく学べる入門書。
  tags: [ruby, beginner]
  cover: ruby-enjoyer.webp  # 省略可

- title: はじめてのC
  author: 柴田望洋
  desc: C言語の定番入門書。
  tags: [c, beginner]
```

**`data/prefectures.yml`**

```yaml
- name: 北海道
  capital: 札幌市
  region: 北海道
  code: 1
  population: 5224614
  area_sq_km: 83424.31
  density_per_sq_km: 62.6

- name: 東京都
  capital: 新宿区
  region: 関東
  code: 13
  population: 14047594
  area_sq_km: 2194.07
  density_per_sq_km: 6402.5
```

**`data/weather_reports.yml`**

```yaml
- location: 東京
  date: 2024-01-01
  condition: 晴
  temp_max_c: 12.2
  temp_min_c: 1.5
  precipitation_mm: 0.0
  humidity_avg_pct: 45

- location: 東京
  date: 2024-06-15
  condition: 雨
  temp_max_c: 25.8
  temp_min_c: 18.2
  precipitation_mm: 15.5
  humidity_avg_pct: 82
```

**`data/elements.yml`**

```yaml
- symbol: H
  name: 水素
  atomic_number: 1
  atomic_mass: 1.008
  category: nonmetal
  phase_at_stp: gas

- symbol: He
  name: ヘリウム
  atomic_number: 2
  atomic_mass: 4.0026
  category: noble_gas
  phase_at_stp: gas
```

## 6. QueryStream 記法

原稿内の展開指示をパイプ（`|`）で3ステージに区切る。著者の思考順（何を → どれを → どう見せるか）と一致する。

```
= [源泉] | [抽出] | [表現]
```

各ステージは省略可能。

```markdown
= books                          # 源泉のみ（全件・デフォルトテンプレート）
= books | ruby                   # 源泉・抽出（tagsショートハンド）
= books | ruby | full            # 源泉・抽出・表現
= books | | full                 # 源泉・表現（抽出なし・スタイル指定）
```

### 6.1 源泉ステージ

`data/` 配下のYAMLファイル名（拡張子なし）を指定する。単数形・複数形どちらでも記述可能。

```markdown
= books      # → data/books.yml（複数件展開）
= book       # → data/books.yml（一件展開）
= elements   # → data/elements.yml（複数件展開）
= element    # → data/elements.yml（一件展開）
```

### 6.2 抽出ステージ

#### 主キーによる一件検索

値のみを指定すると、以下の優先順位で主キー候補フィールドを検索する。

| 優先順位 | フィールド名 | 適用例 |
|---|---|---|
| 1 | `id` | `= book \| ruby-enjoyer` |
| 2 | `title` | `= book \| 楽しいRuby` |
| 3 | `name` | `= prefecture \| 東京都` |
| 4 | `code` | `= prefecture \| 13` |
| 5 | `no` | `= item \| 42` |

`name_ja` / `name_en` などの派生キーは主キー候補に含まない。検索する場合は `field=value` 形式で明示指定する。

#### 複数件絞り込み

**任意フィールド指定**

```markdown
= books | tags=ruby                          # tags が ruby
= prefectures | region=関東                  # region が 関東
= elements | category=nonmetal
= weather_reports | condition=晴
```

**同一フィールドのOR（カンマ区切り）**

```markdown
= books | tags=ruby, javascript              # ruby または javascript
= prefectures | region=関東, 関西            # 関東 または 関西
= elements | category=nonmetal, noble_gas
= weather_reports | condition=晴, 曇
```

**条件演算子**

| 演算子 | 意味 |
|---|---|
| `AND` / `and` / `&&` | AND条件 |
| `OR` / `or` / `\|\|` | OR条件 |

```markdown
= books | tags=ruby && tags=beginner                      # AND
= books | tags=ruby \|\| tags=javascript                  # OR
= weather_reports | location=東京 AND condition=晴, 曇    # 東京 AND（晴 OR 曇）
= elements | category=nonmetal AND phase_at_stp=gas
```

パース規則:
1. `AND` / `and` / `&&` で分割して複数の条件節に分ける
2. 各条件節内のカンマ区切りは同一フィールドへの OR として扱う
3. AND の優先順位は OR（カンマ）より高い

**主キー候補にないフィールドでの明示指定**

```markdown
= element | symbol=H              # 明示指定
= element | atomic_number=1       # 明示指定
```

**比較演算子**

| 演算子 | 意味 | 備考 |
|---|---|---|
| `=` / `==` | 等しい | どちらでも同じ意味 |
| `!=` | 等しくない | |
| `>` | より大きい | |
| `>=` | 以上 | |
| `<` | より小さい | |
| `<=` | 以下 | |
| `=20..25` | 20以上25以下（両端含む） | Ruby範囲オブジェクト記法 |
| `=20...25` | 20以上25未満（終端除く） | Ruby範囲オブジェクト記法 |
| `=20..` | 20以上（上限なし） | Ruby無限範囲記法 |
| `=..25` | 25以下（下限なし） | Ruby無限範囲記法 |

比較演算子記法と範囲オブジェクト記法はどちらも使用可能。著者の背景に合わせて選べる。

| 比較演算子記法 | 範囲オブジェクト記法 | 意味 |
|---|---|---|
| `field >= 20` | `field=20..` | 20以上 |
| `field <= 25` | `field=..25` | 25以下 |
| `field > 20` | — | 20より大きい |
| `field < 25` | `field=...25` | 25未満 |
| `field >= 20 AND field <= 25` | `field=20..25` | 20以上25以下 |
| `field >= 20 AND field < 25` | `field=20...25` | 20以上25未満 |

```markdown
= weather_reports | condition=晴                       # 等しい
= weather_reports | condition==晴                      # 同上
= weather_reports | condition!=雨                      # 等しくない
= weather_reports | temp_min_c >= 20                   # 20以上（比較演算子）
= weather_reports | temp_min_c=20..                    # 20以上（範囲記法）
= weather_reports | temp_min_c=20.5..25.5              # 20.5以上25.5以下（浮動小数点）
= weather_reports | temp_min_c=20..25                  # 20以上25以下
= weather_reports | temp_min_c=20...25                 # 20以上25未満
# 複合条件
= weather_reports | condition=晴, 曇, 薄曇 and temp_min_c >= 20 | -date | 5
```

### 6.3 表現ステージ

スタイル名・ソート・件数制限を指定する。複数の指定はスペース区切り。省略時はデフォルトテンプレート（`_[name].md.slim`）を使用する。

**スタイル指定**

```markdown
= books | tags=ruby | full       # → _books.full.md.slim
= book | 楽しいRuby | standard   # → _book.standard.md.slim
= books | | full                 # → _books.full.md.slim（抽出なし・明示）
= books                          # → _books.md.slim（デフォルト）
```

**ソート指定**

フィールド名の前に `-`（降順）または `+`（昇順）を付ける。`+` は省略可能。抽出条件なしの場合でも `| |` は不要。

```markdown
= weather_reports | -date        # date の降順
= books | +title                 # title の昇順（+ は省略可能）
= books | title                  # title の昇順
= books | tags=ruby | -title     # 絞り込み＋ソート
```

**件数制限**

正の整数で件数を指定する。抽出条件なしの場合でも `| |` は不要。

```markdown
= weather_reports | 5            # 先頭5件
= books | tags=ruby | 5          # 絞り込み＋件数制限
```

**`|` の後の値の解釈順序**

1. `-field` または `+field` で始まる → ソート指定
2. 正の整数のみ → 件数制限
3. データ検索を試みる → ヒットあり → 抽出条件
4. データ検索 → ヒットなし → スタイル名として解釈
5. テンプレートも存在しない → ERROR

**組み合わせ**

スタイル・ソート・件数はスペース区切りで並べる。順序は自由。

```markdown
= weather_reports | condition=晴 | full -date 5
```

**スタイル省略記法と抽出なし明示記法**

`|` の後の値がデータに存在しない場合、スタイル名として解釈する。万一データ値と衝突する場合は `| |` で抽出なしを明示できる。

```markdown
= books | full       # full をデータ検索 → ヒットなし → fullスタイルで全件表示
= books | | full     # 抽出なしを明示 → fullスタイルで全件表示
                     # （full というデータが存在する場合でも安全）
= books | full | standard  # full というデータを検索 → standardスタイルで表示
```

### 6.4 記法例まとめ

```markdown
# 書籍
= books                                        # 全件・デフォルト
= books | tags=ruby                            # rubyタグで絞り込み
= books | tags=ruby && tags=beginner           # AND絞り込み
= books | tags=ruby, javascript                # OR絞り込み
= books | tags=ruby | full                     # 絞り込み＋スタイル指定
= books | full                                 # 全件・fullスタイル（省略記法）
= book | 楽しいRuby                            # タイトルで一件
= book | 楽しいRuby | standard                 # スタイル指定

# 都道府県
= prefectures | region=関東, 関西 | full       # OR絞り込み
= prefecture | 東京都                          # name で一件
= prefecture | 13                              # code で一件

# 気象観測
= weather_reports | location=東京 AND condition=晴, 曇
= weather_report | location=東京 AND date=2024-01-01
# 関東の晴・曇・薄曇かつ最低気温20度以上25度未満を日付降順で5件・fullスタイル
= weather_reports | region=関東 and condition=晴, 曇, 薄曇 and temp_min_c=20...25 | -date 5 full

# 元素
= elements | category=nonmetal AND phase_at_stp=gas | full
= element | 水素
= element | symbol=H
```

## 7. テンプレートファイル仕様

テンプレートは **Markdown** ファイル（`.md`）として記述する。TemplateCompiler が独自記法を解釈してMarkdownを直接生成する（Slim等の外部テンプレートエンジンは使用しない）。

### 命名規約

```
templates/
  _book.md           # デフォルト
  _book.full.md      # fullスタイル
  _book.standard.md  # standardスタイル
```

- 先頭の `_` はパーシャルを示す。
- `_books.md`（複数形）は不要。`= books` と書かれた場合、vivlio-starter が `_book.md` を使って自動反復する。
- スタイルを追加したい場合は `_book.myStyle.md` を1つ作るだけで `= books | | myStyle` が有効になる。

### テンプレート例

**`templates/_book.md`**（デフォルト）

```markdown
### = title
**著者**: = author
= desc
![](cover){width=40% align=right}
```

**`templates/_book.table.md`**（表形式）

```markdown
| = title | = desc | = author |
```

ヘッダー行を含む場合：

```markdown
| タイトル | 説明 | 著者 |
|---|---|---|
| = title | = desc | = author |
```

`= key` を含む行のみ反復され、`= key` を含まない行（ヘッダー行・区切り行）は一度だけ出力される。出力結果：

```markdown
| タイトル | 説明 | 著者 |
|---|---|---|
| 楽しいRuby | Rubyを楽しく学べる入門書。 | 高橋征義 |
| はじめてのC | C言語の定番入門書。 | 柴田望洋 |
```

### 変数名の記法

YAMLのキー名がそのままテンプレートの変数名になる。`= title` と書けば `title` キーの値が展開される。

```yaml
# data/books.yml
- title: 楽しいRuby
  author: 高橋征義
  desc: Rubyを楽しく学べる入門書。
  cover: ruby-enjoyer.webp
```

```markdown
# templates/_book.md
### = title
**著者**: = author
= desc
![](cover){width=40% align=right}
```

YAMLのキーとテンプレートの変数名が1:1対応する。著者が覚えることは「YAMLに書いたキー名をそのまま `=` の後に書く」だけ。

### `()` 内の解釈規則

`![]()` の `()` 内は常に変数として展開する。拡張子あり（png/jpg/jpeg/webp/gif/svg）の場合のみリテラルとして出力する。

| 記法 | 解釈 |
|---|---|
| `![](cover)` | `cover` を変数展開、nil なら行スキップ |
| `![](photo.png)` | リテラル（拡張子ありはそのまま出力） |

`{}` 内はVFMの属性指定としてそのままリテラル出力される。`{}` 内のキー名（`align`, `width` 等）が `data/*.yml` のキーと衝突しないよう注意すること（運用で回避）。

### テンプレート記法のルール

- `=` はデータの展開を示す。nil/空文字の場合はその行ごとスキップされる。
- `###` はVFMのh3見出し。後段のVFM処理でh3として解釈される。
- `![](book.cover)` のように `()` 内に拡張子なしの識別子を書くと変数として展開される。
- `![](cover.png)` のように拡張子あり（png/jpg/jpeg/webp/gif/svg）はリテラルとしてそのまま出力される。
- テンプレート内の空行は項目間の区切りとして出力される。インデントはコンパイラが自動補完する。
- `png` など画像拡張子に相当するキー名は `data/*.yml` で使用しないこと。

### 記法との対応

| 記法 | 使われるテンプレート | 処理 |
|---|---|---|
| `= book \| 楽しいRuby` | `_book.md` | 1件表示 |
| `= book \| 楽しいRuby \| full` | `_book.full.md` | 1件表示 |
| `= books` | `_book.md` | 自動反復 |
| `= books \| \| full` | `_book.full.md` | 自動反復 |

## 8. テンプレートコンパイラ仕様（TemplateCompiler）

著者が書きやすいシンプルな独自記法を解釈し、Markdownを直接生成するコンパイラ。

### 8.1 変換ルール一覧

| 入力パターン | 変換後 | 備考 |
|---|---|---|
| `= key` のみの行 | `key` の値を展開 | nil/空文字なら行ごとスキップ |
| `prefix = key` | `key` の値を展開 | prefix はMarkdown記法等 |
| `![](key)` | `key` の値を展開 | nil/空文字なら行ごとスキップ |
| `![](file.png)` | リテラル出力 | 拡張子ありはそのまま通す |
| `= key` を含まない行 | リテラル出力 | ヘッダー行等は一度だけ出力 |
| 空行 | 改行出力 | |

ドット記法（`= book.title`, `= it.title`）は不要。YAMLのキー名をそのまま使う。

### 8.2 nil安全展開の詳細

`= key` を含む行は、`key` が nil または空文字の場合に行ごとスキップされる。著者が `nil` を意識する必要はなく、`=` 記法で統一して書けばよい。

```markdown
# 著者が書くテンプレート
**著者**: = author   ← author が nil/空文字なら行ごとスキップ
```

### 8.4 入出力例

**`data/books.yml`**

```yaml
- title: 楽しいRuby
  author: 高橋征義
  desc: Rubyを楽しく学べる入門書。
  cover: ruby-enjoyer.webp

- title: はじめてのC
  author: 柴田望洋
  desc: C言語の定番入門書。
  cover:
```

**`templates/_book.md`**

```markdown
### = title
**著者**: = author
= desc
![](cover){width=40% align=right}
```

**レンダリング結果**

```markdown
### 楽しいRuby
**著者**: 高橋征義
Rubyを楽しく学べる入門書。
![](ruby-enjoyer.webp){width=40% align=right}

### はじめてのC
**著者**: 柴田望洋
C言語の定番入門書。
```

- `cover` が nil の「はじめてのC」では `![](cover)` の行がスキップされる。
- テンプレートの空行が書籍間の区切りとして出力される。

`![](key)` の `()` 内が拡張子なし識別子の場合、変数として展開しnil安全処理を適用する。

```markdown
# 変数展開（拡張子なし）→ nil なら行スキップ
![](cover){width=40% align=right}

# リテラル出力（拡張子あり）→ そのまま出力
![](Einstein.png){width=40% align=right}
```

## 9. 展開処理の仕様

### 9.1 展開タイミング

`vs build` 実行時、以下の順序で処理される。

```
① contents/05-references.md をスキャン
  → = books という QueryStream 記法を発見

② data/books.yml を読み込み
  → 抽出条件を解決し、レンダリングすべきデータを確定

③ templates/_book.md に実際のデータを流し込む
  → TemplateCompiler がレンダリング結果の Markdown を生成

④ contents/05-references.md 内の QueryStream 記法を
  レンダリング結果で置き換え、プロジェクトルート直下に
  05-references.md として書き出す
  （contents/05-references.md 自体は書き換えない）

⑤ プロジェクトルート直下の 05-references.md を
  pre_process メソッド群がさらに処理する

⑥ 後段の VFM 等のビルドシステムが処理を続行する

⑦ pdf / print_pdf / epub がプロジェクトルート直下に出力される
```

### 9.2 解決の流れ

1. 原稿内の QueryStream 記法（`= [源泉] | [抽出] | [表現]`）を検出する。
2. 源泉からデータファイル（`data/[name].yml`）を特定する。
3. 抽出ステージを解析してデータを絞り込む。
4. 表現ステージからテンプレートファイルを選択する。スタイル未指定時は `_[name].md` を使用。
5. TemplateCompiler がテンプレートにデータを流し込み、Markdown を生成する。
6. 展開結果の文字列で記法行を置換する。

### 9.3 QueryStream 実装案

QueryStream は4ステップのパイプラインとして実装する。

```
= weather_reports | condition=晴, 曇, 薄曇 and temp_min_c >= 20 | -date | 5
```

上記の例に対応する実装イメージ：

```ruby
# 1. Source（YAMLロード）
data = YAML.load_file('data/weather_reports.yml', symbolize_names: true)

# 2. Filter（条件によるフィルタリング）
# カンマ（OR）は配列の include?、AND は && で表現
data = data.select {
  ['晴', '曇', '薄曇'].include?(it[:condition]) && it[:temp_min_c] >= 20
}

# 3. Sort（並び替え）
# `-field` は sort_by { it[:field] }.reverse で表現
data = data.sort_by { it[:date] }.reverse

# 4. Limit（件数制限）
data = data.first(5)
```

各ステップの対応：

| QueryStream | 実装 |
|---|---|
| 源泉（`weather_reports`） | `YAML.load_file('data/weather_reports.yml')` |
| OR条件（カンマ区切り） | `array.include?(it[:field])` |
| AND条件（`and` / `&&`） | `&&` で接続 |
| 比較演算子（`>=`, `<=` 等） | そのまま Ruby の比較演算子に変換 |
| 範囲指定（`20..25`） | Ruby の Range オブジェクト（`(20..25).include?(it[:field])`） |
| ソート（`-date`） | `sort_by { it[:date] }.reverse` |
| 昇順ソート（`+date` / `date`） | `sort_by { it[:date] }` |
| 件数制限（`5`） | `first(5)` |

### 9.4 エラーハンドリング

| 状況 | 挙動 |
|---|---|
| テンプレートファイルが存在しない | ERROR を出力して処理を中断 |
| データファイルが存在しない | ERROR を出力して処理を中断 |
| テンプレート内に存在しないキーが記述されている | ERROR を出力して処理を中断 |
| 一件検索で複数件ヒット | WARNING を出力し明示指定を促す |
| 一件検索で0件ヒット | WARNING を出力 |

フォールバックは行わない。

## 10. 拡張性

- `data/` に YAML を追加するだけで新しいデータ種別が使用可能になる。
- `templates/` にファイルを追加するだけで新しいスタイルが使用可能になる。
- 将来的に `vs lint` で原稿内の QueryStream 記法の整合性チェック（データファイル・テンプレートの存在確認）を行うことを検討する。
