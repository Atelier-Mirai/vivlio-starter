# ユーティリティ・コマンド集

:::{.chapter-lead}
執筆環境を整えたり、成果物作成を補助する為の便利なコマンド群です。普段は既定値で充分かと思いますが、必要に応じて利用してください。また、templates/ディレクトリの活用についても補足しています。
:::

| コマンド | カテゴリ | 目的 |
| :--- | :--- | :--- |
| `open` | プレビュー | PDFを即座に開く |
| `pdf:compress` | 圧縮 | PDFを軽量化する |
| `clean` | メンテナンス | 不要な生成ファイルを削除する |
| `resize` | 画像管理 | イメージ画像をWebPに一括変換する |

## vs open — PDFを開く

:::{.section-lead}
`vs open` はビルドで生成された PDF を macOS の Preview.app で即座に開きます。ファイル名を指定して任意の PDF を開くこともできます。
:::

```bash
# ビルド生成物を自動選択して開く
vs open

# ファイル名を指定して開く（拡張子は省略可）
vs open 01-quickstart
vs open 01-quickstart.pdf
```

引数を省略した場合は、圧縮版・通常版の更新日時を比較して新しいほうを自動選択します。

ファイル名を指定した場合は、プロジェクトルート直下 → `sources/` ディレクトリの順で探索します。

```bash
# sources/quickstart.pdf を開く
vs open quickstart
```

macOS 専用のコマンドです。

`config/book.yml` の `output.targets` に `pdf` が含まれている場合、`vs build` の実行後に自動で PDF が開きます。プレビューアプリを閉じてしまった後に再度確認したい場合や、任意の PDF ファイルを開きたい場合に `vs open` を使ってください。

## vs pdf:compress — PDFを圧縮・軽量化する

:::{.section-lead}
`vs pdf:compress` は、Ghostscript を利用してビルド済みの PDF ファイルを圧縮し、データサイズを軽量化するコマンドです。
:::

### 主な利用シーン

本コマンドは、主に**「ネットワーク経由での共有」**を目的として使用します。

- サンプル原稿の公開: 執筆中の章を `vs build 01-intro` などで個別にビルドし、レビュー担当者へ送付したり、SNSやブログで公開したりする際の転送量を抑えます。

:::{.memo}
**【重要】印刷所への入稿について**

印刷所に提出する「入稿用データ」には、このコマンドを使用しないでください。`vs pdf:compress` は、画像解像度の調整やフォントの最適化によってサイズを削るため、印刷品質に影響を与える可能性があります。入稿には `vs build` で生成された直後の（圧縮されていない）PDFを使用するのが正解です。
:::

### 基本的な使い方

```bash
# デフォルトファイルを圧縮
vs pdf:compress

# 入力ファイルを指定（拡張子 .pdf は省略可）
vs pdf:compress 01-intro
vs pdf:compress 01-intro.pdf

# 入出力を明示指定
vs pdf:compress input.pdf output.pdf
```

引数を省略した場合、`config/book.yml` の設定に従った出力ファイルが対象になります。

ファイル名を指定した場合、出力ファイルは自動的に `_compressed` が接尾語として付いたファイル名になります。

```bash
vs build 01-intro        # → 01-intro.pdf が生成される
vs pdf:compress 01-intro # → 01-intro_compressed.pdf が生成される
```

### 自動圧縮の設定

`config/book.yml` の `pdf.compress` を `true` にすると、`vs build` 実行後に自動で圧縮が行われます。

```yaml
pdf:
  compress: true   # ビルド後に自動圧縮（処理時間が増加）
```

処理時間が増えるため、普段は `false` に設定しておき、必要なときだけ `vs pdf:compress` コマンドを使うのがおすすめです。自動圧縮が有効な場合でも `vs build --no-compress` で一時的にスキップできます。

:::{.column}
**ヒント**: `vs build` で自動圧縮が有効（`pdf.compress: true`）な場合、ビルド後に `_compressed` 付きのファイルが自動生成されます。`vs pdf:compress` は既存の PDF を後から圧縮したい場合や、自動圧縮を無効にしている環境で使います。
:::

## vs clean — 生成ファイルを削除する

:::{.section-lead}
`vs clean` はビルドで生成された中間ファイルを削除します。`vs build` はデフォルトでビルド後に自動でクリーンアップを実行するため、通常は手動で実行する必要はありません。
:::

`vs build` 実行後に中間ファイルを残したい場合は `--no-clean` を使います。(開発者向け仕様)

```bash
vs build --no-clean   # 中間ファイルを残してビルド
vs clean              # 後から手動でクリーンアップ
```

### オプション

```bash
# 最終PDFも含めてすべて削除
vs clean --purge

# キャッシュのみ削除
vs clean --cache

# 生成されたカバー画像のみ削除（マスター画像は保持）
vs clean --cover

# すべてのオプションをまとめて実行
vs clean --all
```

### オプション一覧

| オプション | 説明 |
|------------|------|
| `--purge` / `-P` | 最終 PDF も含めてすべて削除 |
| `--cache` / `-C` | `.cache/vs/`・`.cache/metrics/` キャッシュのみ削除 |
| `--cover` | 生成されたカバー画像のみ削除（マスターは保持） |
| `--generated-images` | 生成された扉絵・装飾画像を削除 |
| `--all` | `--index-dictionaries` を除く上記すべてをまとめて実行 |
| `--index-dictionaries` | 索引・用語集辞書データを削除（確認あり） |

:::{.column}
**ヒント**: `vs clean --cache` はビルドの挙動がおかしいと感じたときに試してみてください。キャッシュが古くなっている場合に解消することがあります。
:::

## vs resize — 画像をWebPに変換する

:::{.section-lead}
`vs resize` は `images/` ディレクトリ内の PNG・JPG 画像を WebP 形式に一括変換します。ビルド時にも自動実行されますが、手動で変換したい場合に使います。
:::

### 基本的な使い方

```bash
# 標準品質で変換（quality=85, 最大1600px）
vs resize

# 高品質で変換（quality=90, 最大2000px）
vs resize --high

# 軽量品質で変換（quality=75, 最大1200px）
vs resize --low
```

`vs build` はビルド時に WebP が存在する場合はそのままスキップします。つまり `vs resize --high` で事前に高品質の WebP を生成しておけば、`vs build` 実行時にその高品質 WebP がそのまま使われます。品質を変えたい場合は `vs resize --force` で上書き再生成してください。

### vs build と vs resize の関係

`vs build` は内部的に `vs resize`（標準品質）を呼んで WebP 変換を行います。既存の WebP がある場合は上書きしないのが基本仕様です。

WebP が生成済みの状態で `vs build --high` を実行しても、既存の WebP の 作成日時 が元画像より新しければスキップされ、既存の WebP がそのまま使われます。

画質を変更したい場合は、以下のどちらかを行ってください。

```bash
# 方法1: 先に高品質で上書き変換してからビルド
vs resize --high --force
vs build

# 方法2: ビルド時に --force を付けて上書き
vs build --high --force
```

### 対象ディレクトリを指定

```bash
vs resize 01-intro
# または
vs resize images/01-intro
```

省略時は `images/` 全体が対象です。章名のみ（`01-intro`）で指定した場合は `images/01-intro/` として解決されます。

### 強制再生成

```bash
# 既存のWebPファイルも再生成する
vs resize --force
vs resize --high --force
```

通常は既存の WebP ファイルをスキップしますが、`--force` を付けると上書き再生成します。

### 元ファイルの削除

```bash
vs resize --delete-originals
```

WebP への変換が成功した元の PNG/JPG ファイルを削除します。削除前に対象ファイルの一覧を表示して確認プロンプトが表示されます。元ファイルは復元できないため、バックアップを取ってから実行することを推奨します。

### 品質プリセットの比較

| プリセット | オプション | 品質 | 最大サイズ | 用途 |
|-----------|-----------|------|-----------|------|
| 高精細 | `--high` | 90 | 2000px | 印刷・高解像度表示 |
| 標準 | （なし） | 85 | 1600px | 通常の技術書 |
| 軽量 | `--low` | 75 | 1200px | Web配布・ファイルサイズ優先 |

## カスタム CSS — スタイルを自由に調整する

:::{.section-lead}
Vivlio Starter は `config/book.yml` のテーマ設定で色やフォントを簡単に切り替えられますが、「リンクの色だけ変えたい」「コードブロックの角を丸くしたい」といった細かな調整をしたい場合もあるでしょう。そのようなときに使えるのが `stylesheets/custom.css` です。

(※ 実験的機能です。次期メジャーバージョンアップにより変更の可能性が有ります)
:::

### 仕組み

ビルド時、各章の Markdown には次の順番でスタイルシートが適用されます。

1. **`theme.css`** — テーマカラーや扉絵などの基本設定（`book.yml` から自動生成）
2. **`chapter.css`** 等 — 章タイプごとのレイアウト（自動生成）
3. **`custom.css`** — 著者が自由に編集できるファイル（**上書きされない**）

CSS のカスケード（後から読み込まれたスタイルが優先される仕組み）により、`custom.css` に書いた内容が最優先で反映されます。

::: {.note}
`theme.css` や `page-settings.css` はビルドのたびに `book.yml` の設定で上書きされます。これらのファイルを直接編集しても、次の `vs build` で元に戻ってしまいます。恒久的なカスタマイズには必ず `custom.css` を使ってください。
:::

### 使い方

`stylesheets/custom.css` を開き、変更したい CSS 変数やルールを記述します。

```css
/* stylesheets/custom.css */
:root {
  --color-link: #1a73e8;        /* リンク色を青に変更 */
  --color-column-bg: #f5f5dc;   /* コラム背景をベージュに */
}
```

`vs build` を実行すると、変更が即座に PDF に反映されます。

### カスタマイズ可能な CSS 変数

`theme.css` と `page-settings.css` で定義されている主な CSS カスタムプロパティの一覧です。`custom.css` でこれらの値を上書きできます。

#### 配色（theme.css）

| 変数名 | 既定値 | 説明 |
| :--- | :--- | :--- |
| `--theme-accent` | `var(--accent-blue)` | テーマのアクセントカラー |
| `--color-text` | `#000` | 本文テキスト色 |
| `--color-link` | `#000` | リンク色 |
| `--color-strong` | `var(--theme-accent)` | 太字（`**強調**`）の色 |
| `--color-em-underline` | `var(--theme-accent)` | 強意（`*イタリック*`）の下線色 |
| `--color-border` | `#ccc` | 画像など汎用枠線色 |
| `--color-column-bg` | `#eef` | コラム背景色 |
| `--color-column-border` | `#8df` | コラム枠線色 |
| `--color-figure-border` | `#ccc` | 図の枠線色 |
| `--color-danger` | `#f00` | 警告色 |

#### 版面・フォント（page-settings.css）

| 変数名 | 既定値（例） | 説明 |
| :--- | :--- | :--- |
| `--base-font-size` | `10.5pt` | 基準文字サイズ |
| `--base-line-height` | `19.425pt` | 行送り |
| `--letter-spacing` | `0em` | 字間 |
| `--page-margin-top` | `25mm` | 天（上余白） |
| `--page-margin-bottom` | `25mm` | 地（下余白） |
| `--page-margin-inner` | `25mm` | ノド（綴じ側余白） |
| `--page-margin-outer` | `23mm` | 小口（外側余白） |
| `--font-main-text` | `"Zen Old Mincho"` | 本文フォント |
| `--font-header` | `"Zen Kaku Gothic New"` | 見出しフォント |
| `--font-code` | `"hackgen35"` | コードフォント |
| `--column-font-size` | `8pt` | コラムの文字サイズ |

:::{.column}
**ヒント**: `book.yml` の `theme.color` や `page.use` で設定できる項目は、まず `book.yml` で設定するのがおすすめです。`custom.css` は `book.yml` では設定できない細かな調整に使ってください。
:::

### 実践例

#### コードブロックの見た目を変える

```css
/* コードブロックに背景色と角丸を追加 */
pre {
  background: #f8f8f8;
  border-radius: 6px;
  border: 1px solid #e0e0e0;
}
```

#### 引用ブロックの装飾を変える

```css
blockquote {
  border-left: 4px solid var(--theme-accent);
  padding-left: 1em;
  font-style: italic;
}
```

#### 章扉の余白を微調整する

```css
:root {
  --frontispiece-padding: 15mm;
}
```

## 章テンプレートのカスタマイズ

:::{.section-lead}
`vs create` で章ファイルを生成する際、`templates/` ディレクトリの雛形が使われます。この雛形を編集することで、新しい章を作るたびに決まった構成が自動で入力された状態から執筆を始められます。
:::

### 章番号と雛形の対応

| ファイル | 対象章番号 | 用途 |
|----------|-----------|------|
| `preface.md` | `00` | 前書き・はじめに |
| `chapter.md` | `01-89` | 通常の章 |
| `appendix.md` | `90-98` | 付録 |
| `postface.md` | `99` | 後書き・おわりに |

`vs create 11-intro` を実行すると、`templates/chapter.md` を元に `contents/11-intro.md` が生成されます。

### テンプレートの編集

`templates/chapter.md` を開いて自由に編集できます。テンプレート内の `{{TITLE}}` は章のスラッグ（`11-intro` など）に自動置換されます。

```markdown
<!-- templates/chapter.md の例 -->
# {{TITLE}}

:::{.chapter-lead}
:::

## はじめに

## まとめ
```

毎回同じ構成で書き始める場合は、よく使うセクション見出しをあらかじめ入れておくと便利です。

### QueryStream テンプレート

`templates/` には章テンプレートのほかに、QueryStream のデータ展開テンプレートも置かれます。ファイル名の先頭に `_` が付くのが特徴です。

| ファイル | 対応データ | 用途 |
|----------|-----------|------|
| `_book.md` | `data/books.yml` | 書籍カード形式 |
| `_book.table.md` | `data/books.yml` | 書籍テーブル形式 |

新しいデータファイルを追加する場合は、対応するテンプレートをこのディレクトリに作成してください。QueryStream の詳細は「QueryStream」の章を参照してください。
