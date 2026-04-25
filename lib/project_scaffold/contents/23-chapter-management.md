# 章の管理（create / delete / rename / renumber）

:::{.chapter-lead}
Vivlio Starter では、章ファイルの作成・削除・名前変更・連番整理をコマンドで行えます。手作業でファイルを操作する必要はなく、`catalog.yml` や画像ディレクトリも自動で更新されます。
:::

## vs create — 章ファイルを作成する

:::{.section-lead}
`vs create` は章の Markdown ファイルと画像ディレクトリを一括で生成し、`config/catalog.yml` に自動追記します。
:::

### 基本的な使い方

```bash
vs create 11-intro
```

`contents/11-intro.md` と `images/11-intro/` が生成され、`config/catalog.yml` に `11-intro` が追記されます。

### 番号のみで作成

番号だけを指定することもできます。スラッグなしのファイル名（`11.md`）が生成されます。

```bash
vs create 11
```

### 複数の章を一度に作成

```bash
vs create 11-intro 12-setup 13-advanced
```

### 番号を省略して作成

章番号を省略すると、既存の章番号と重複しない番号が自動で割り当てられます。

```bash
vs create intro setup advanced
```

### テンプレートの自動選択

章ファイルの内容は `templates/` ディレクトリのテンプレートから自動生成されます。章番号によって使用されるテンプレートが変わります。

| 章番号の範囲 | 使用テンプレート | 用途 |
|-------------|----------------|------|
| 00 | `templates/preface.md` | 前書き・はじめに |
| 01-89 | `templates/chapter.md` | 通常の章 |
| 90-98 | `templates/appendix.md` | 付録 |
| 99 | `templates/postface.md` | 後書き・おわりに |

テンプレートファイルはプロジェクトの `templates/` ディレクトリに配置されており、自由に編集できます。`{{TITLE}}` プレースホルダーはファイル名のスラッグに自動置換されます。

テンプレートが見つからない場合は、最小限の骨子が生成されます。

## vs delete — 章を削除する

:::{.section-lead}
`vs delete` は章の Markdown ファイル・画像ディレクトリ・`catalog.yml` のエントリをまとめて削除します。各削除前に確認プロンプトが表示されます。
:::

### 基本的な使い方

```bash
vs delete 11-intro
```

`contents/11-intro.md`、`images/11-intro/`、`catalog.yml` のエントリが削除されます。

### 章番号で指定

```bash
vs delete 11
```

`11-` で始まるファイルを自動で特定して削除します。

### 範囲指定

```bash
vs delete 11-13
```

11〜13 番の章をまとめて削除します。

### 確認をスキップする（--force）

```bash
vs delete 11-intro --force
```

確認プロンプトをスキップして即座に削除します。

### オプション一覧

| オプション | 説明 |
|------------|------|
| `--force` / `-f` | 確認なしで削除 |
| `--yes` / `-y` | `--force` と同じ意味 |

## vs rename — 章のスラッグ/番号を変更する

:::{.section-lead}
`vs rename` は章の Markdown ファイル名・画像ディレクトリ名・`catalog.yml` のエントリを一括で変更します。
:::

### 基本的な使い方

```bash
vs rename 11-intro 12-introduction
```

`11-intro.md` → `12-introduction.md`、`images/11-intro/` → `images/12-introduction/` に変更し、`catalog.yml` も更新されます。

### 番号だけを変更する

```bash
vs rename 11 12
```

スラッグはそのままで、番号だけを変更します。`11-intro.md` → `12-intro.md` のように変換されます。

### スラッグだけを変更する

```bash
vs rename 11-intro new-slug
```

番号はそのままで、スラッグだけを変更します。

### 確認をスキップする（--force）

```bash
vs rename 11-intro 12-introduction --force
```

### オプション一覧

| オプション | 説明 |
|------------|------|
| `--force` / `-f` / `-y` | 確認なしで変更を実行 |

## vs renumber — 章番号を一括で付け直す

:::{.section-lead}
`vs renumber` は全章の番号を 1 から順に振り直します。章を追加・削除した後に番号が飛んでしまった場合に使います。`vs rename` の別名コマンドです。
:::

### 基本的な使い方

```bash
vs renumber
```

`contents/` 内の通常章（01-89）を 01 から順に、付録（90-98）を 90 から順に振り直します。変更前に確認プロンプトが表示されます。

実行例：

```
章の刻み幅: 1
対象ファイル:
通常の章:
  11-intro → 01-intro
  13-setup → 02-setup
  15-advanced → 03-advanced
付録:
  91-appendix-a → 90-appendix-a

連番付け直しを実行しますか？ (y/N):
```

### 刻み幅を指定する（--step）

```bash
vs renumber --step 2
# または短縮形
vs renumber -s 2
```

章番号を 1, 3, 5, ... のように 2 刻みで振り直します。後から章を挿入しやすくなります。

### 確認をスキップする（--force）

```bash
vs renumber --force
```

### オプション一覧

| オプション | 説明 |
|------------|------|
| `--force` / `-f` / `-y` | 確認なしで実行 |
| `--step <n>` / `-s <n>` | 章番号の刻み幅（デフォルト: 1） |

## 注意事項

:::{.section-lead}
章の操作は `catalog.yml` と連動しています。手動でファイルを移動・削除した場合は `catalog.yml` も手動で更新してください。
:::

- `vs renumber` 実行後は、古い章番号で生成されたビルド中間ファイル（`.html` など）が `vs clean` と同じ処理で自動削除されます
- 画像ディレクトリが移動先に既に存在する場合は、手動での統合が必要です
- 付録（90-98）の章番号を変更すると、`appendix-a` などのスラッグも自動で調整されます

### 章番号の種別と `vs renumber` の範囲

Vivlio Starter の章番号には次の種別があり、`vs renumber` はそれぞれの種別の範囲内で連番を振り直します。種別をまたいだ番号の移動は行いません。

| 番号帯 | 種別 | `vs renumber` の動作 |
|---|---|---|
| 00 | 前書き（preface） | 対象外（固定） |
| 01–89 | 本文（chapter） | 先頭章の番号を起点に連番を付与 |
| 90–98 | 付録（appendix） | 90 から連番を付与（スラッグも自動調整） |
| 99 | 後書き（postface） | 対象外（固定） |

前書き（00）と後書き（99）は種別が固定されているため、`vs renumber` では番号が変わりません。本文の章を削除・追加しても、前書きが本文に繰り上がったり、付録が本文に混ざったりすることはありません。

種別をまたいで章を移動したい場合は、`vs rename` で明示的に指定してください。

```bash
# 前書きを本文に移す
vs rename 00-preface 11-preface

# 本文を付録に移す
vs rename 45-utility 91-utility
```

