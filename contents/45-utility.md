# ユーティリティ・コマンド集

:::{.chapter-lead}
原稿を書く作業の周りには、PDF を開き直す、配布用に軽くする、画像素材を整理するといった小さな仕事があります。本章では、そのときに使う補助コマンドと、紙面の CSS や章の雛形を自分の本に合わせる方法をまとめます。必要な場面から読んでください。
:::

| コマンド | カテゴリ | 目的 |
| :--- | :--- | :--- |
| `open` | プレビュー | PDFを即座に開く |
| `pdf:compress` | 圧縮 | PDFを軽量化する |
| `clean` | メンテナンス | 不要な生成ファイルを削除する |
| `resize` | 画像管理 | 手元の素材画像を WebP に一括変換する |

## vs open — PDFを開く

:::{.section-lead}
ビルド後に閉じた PDF をもう一度確かめるなら、macOS では `vs open` を使えます。ファイル名を指定すれば、章ごとに作った PDF も開けます。
:::

```bash
# ビルド生成物を自動選択して開く
vs open

# ファイル名を指定して開く（拡張子は省略可）
vs open 01-quickstart
vs open 01-quickstart.pdf
```

引数を省略した場合は、通常版・圧縮版の更新日時を比較して新しいほうを自動選択します。

ファイル名を指定した場合は、プロジェクトルート直下 → `sources/` ディレクトリの順で探索します。

```bash
# sources/quickstart.pdf を開く
vs open quickstart
```

macOS 専用のコマンドです。

`config/book.yml` の `output.targets` に `pdf` が含まれている場合、`vs build` の実行後に自動で PDF が開きます。プレビューアプリを閉じてしまった後に再度確認したい場合や、任意の PDF ファイルを開きたい場合に `vs open` を使ってください。

## vs pdf:compress — PDFを圧縮・軽量化する

:::{.section-lead}
レビュー用の PDF を送る前に容量を抑えたいときは、`vs pdf:compress` を使います。Ghostscript でビルド済みの PDF を圧縮し、別名のファイルを作ります。
:::

### 主な利用シーン

圧縮が役立つのは、主にネットワーク経由でファイルを共有するときです。

- サンプル原稿の公開: 執筆中の章を `vs build 01-intro` などで個別にビルドし、レビュー担当者へ送付したり、SNSやブログで公開したりする際の転送量を抑えます。

:::{.memo}
**印刷所へ入稿する PDF**

`vs pdf:compress` は画像解像度の調整などで容量を減らすため、印刷品質に影響する場合があります。印刷所へは、このコマンドで圧縮した共有用 PDF ではなく、`vs build` で生成した入稿用 PDF を渡してください。
:::

### 基本的な使い方

```bash
# 既定のファイルを圧縮
vs pdf:compress

# 入力ファイル名を指定（拡張子 .pdf は省略可）
vs pdf:compress 01-intro
vs pdf:compress 01-intro.pdf

# 入出力ファイル名を明示指定
vs pdf:compress input.pdf output.pdf
```

引数を省略した場合、`config/book.yml` の設定に従った出力ファイルが対象になります。

ファイル名を指定した場合、出力ファイルは自動的に `_compressed` が接尾語として付いたファイル名になります。

```bash
vs build 01-intro        # → 01-intro.pdf が生成される
vs pdf:compress 01-intro # → 01-intro_compressed.pdf が生成される
```

### 自動圧縮の設定

`config/book.yml` の `output.pdf.compress` を `true` にすると、`vs build` のあとで圧縮版が自動生成されます。

```yaml
output:
  pdf:
    compress: true   # ビルド後に自動圧縮（処理時間が増加）
```

処理時間が増えるため、普段は `false` に設定しておき、必要なときだけ `vs pdf:compress` コマンドを使うのがお勧めです。自動圧縮が有効な場合でも `vs build --no-compress` で一時的にスキップできます。

:::{.column}
`output.pdf.compress: true` なら、ビルド後に `_compressed` 付きのファイルが生成されます。既存の PDF をあとから圧縮したい場合は、`vs pdf:compress` を使います。
:::

## vs clean — 生成ファイルを削除する

:::{.section-lead}
`vs clean` はビルド中に作られたファイルを片付けるコマンドです。通常のビルド後は自動で片付けられますが、中間ファイルを調べたあとや、キャッシュを作り直したいときに使えます。
:::

`vs build` 実行後に中間ファイルを残したい場合は `--no-clean` を使います（開発者向け仕様）

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
ビルド結果が更新されないなど、キャッシュが原因と思われるときは `vs clean --cache` を試せます。次のビルドでは必要なデータが作り直されます。
:::

## vs resize — 画像をWebPに変換する

:::{.section-lead}
`vs resize` は、`images/` に置いた PNG・JPG を WebP へまとめて変換します。**書籍の出力だけでなく、手元に置く素材の容量を減らしたいとき**のコマンドです。
:::

### 基本的な使い方

```bash
# 標準品質で変換（quality=85, 最大1600px）
vs resize

# 高品質で変換（quality=90, 最大2048px）
vs resize --high

# 軽量品質で変換（quality=75, 最大1200px）
vs resize --low
```

既存の WebP があればスキップします。品質を変えたい場合は `vs resize --force` で上書き再生成してください。

### vs build との関係

**`vs build` は `vs resize` を呼びません。** 素材はそのまま使い、PDF・EPUB・Kindle それぞれに適した画像をビルドが `.cache/` に用意します（次節）。したがって `vs resize` を実行してもしなくても、出来上がる本の大きさは変わりません。

`vs resize` を使うのは **`images/` 自体を軽くしたいとき**です。4K の写真を大量に置いていると Git リポジトリが膨らむので、そうした場合に手元の素材を縮めます。

### PDF 向けの画像は別に用意されます

`vs build` は `images/` の画像をそのまま PDF へ入れるのではなく、**PDF に適した形式へ変換した派生を `.cache/vs/derived/` に作って**組版に渡します。PDF の仕様には WebP 用のフィルタがなく、そのまま渡すと可逆圧縮で展開されて 7 倍近くに膨らんでしまうためです。

| ターゲット | 使われる形式 | 理由 |
|:---|:---|:---|
| PDF | JPEG（写真）／ PNG（図） | そのまま格納できる。WebP は展開されて膨らむ |
| EPUB | WebP をそのまま | ZIP に素材のまま入る。三つの形式でもっとも小さい |
| Kindle | JPEG / PNG | KFX が WebP に対応していない |

**著者が形式を選ぶ必要はありません。** 透過の有無と色数から自動で決まります。紙面に対して解像度が過剰な画像も、組版してから実際の表示サイズを測り、必要なぶんまで縮めた派生に差し替えられます。

**`images/` の画像は書き換えられません。** 派生は `.cache/` の中だけに作られるので、用意した画像はそのまま残ります。手元の画像そのものを軽くしたいときは、この節の `vs resize` を使ってください。

この仕組みにより、本書（26 章・346 ページ）の PDF は 97 MB から 27 MB になりました。

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

WebP への変換に成功した元の PNG/JPG を削除します。実行前に対象の一覧と確認プロンプトが出ます。元画像が必要になる可能性があれば、先に別の場所へ保管してください。

### 品質プリセットの比較

| プリセット | オプション | 品質 | 最大サイズ | 用途 |
|-----------|-----------|------|-----------|------|
| 高精細 | `--high` | 90 | 2048px | 印刷・高解像度表示 |
| 標準 | `--medium`（既定） | 85 | 1600px | 通常の技術書 |
| 軽量 | `--low` | 75 | 1200px | Web配布・ファイルサイズ優先 |

## カスタム CSS — スタイルを自由に調整する

:::{.section-lead}
書籍全体の色や書体は `config/book.yml` で選べます。リンクの色やコードブロックの枠など、一部分の見た目を調整したいときは `stylesheets/custom.css` を編集します。

この機能は実験的なもので、次のメジャーバージョンで仕様が変わる可能性があります。
:::

### 仕組み

ビルド時、各章の Markdown には次の順番でスタイルシートが適用されます。

1. **`theme.css`** — テーマカラーや扉絵などの基本設定（`book.yml` から自動生成）
2. **`chapter.css`** 等 — 章タイプごとのレイアウト（自動生成）
3. **`custom.css`** — 著者が自由に編集できるファイル（**上書きされない**）

`custom.css` は最後に読み込まれます。同じ条件の CSS ルールなら後から書かれた指定が優先されるため、生成されるスタイルを上書きできます。

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
**ヒント**: `book.yml` の `theme.color` や `page.use` で設定できる項目は、まず `book.yml` で設定するのがお勧めです。`custom.css` は `book.yml` では設定できない細かな調整に使ってください。
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

#### 章扉の引っ込み量を微調整する

```css
:root {
  --frontispiece-edge-inset: 15mm;
}
```

## 章テンプレートのカスタマイズ

:::{.section-lead}
`vs create` で章を作るときは、`templates/` の雛形が使われます。毎回必要な見出しやリード文の枠を入れておけば、新しい章を作ったところから本文を書き始められます。
:::

### 章番号と雛形の対応

| ファイル | 対象章番号 | 用途 |
|----------|-----------|------|
| `preface.md` | `00` | 前書き・はじめに |
| `chapter.md` | `01-89` | 通常の章 |
| `appendix.md` | `90-98` | 付録 |
| `postface.md` | `99` | 後書き・おわりに |

`vs create 11-intro` を実行すると、`templates/chapter.md` を元に `contents/11-intro.md` が生成されます。

この四つとは別に `markdown_snippet.md` が置かれています。こちらは雛形ではなく、使える記法を実例つきで並べた見本帳です（`vs create` では使われません）。

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

章ごとに決まった構成を使うなら、よく使う見出しを雛形に入れておけます。ただし、章に合わない見出しまで残さず、内容に合わせて調整してください。

### QueryStream テンプレート

`templates/` には章テンプレートのほかに、QueryStream のデータ展開テンプレートも置かれます。ファイル名の先頭に `_` が付くのが特徴です。

| ファイル | 対応データ | 用途 |
|----------|-----------|------|
| `_book.md` | `data/books.yml` | 書籍カード形式 |
| `_book.table.md` | `data/books.yml` | 書籍テーブル形式 |

新しいデータファイルを追加する場合は、対応するテンプレートをこのディレクトリに作成してください。詳細は「データ展開機能の使い方」の章を参照してください。
