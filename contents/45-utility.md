# 補助コマンドとカスタマイズ

:::{.chapter-lead}
原稿を書く作業の周りには、PDF の閲覧・圧縮・画像化、生成物の片づけといった小さな作業があります。本章では、そのときに使う補助コマンドと、紙面の CSS や章の雛形を自分の本に合わせる方法をまとめます。必要な場面から読んでください。
:::

| コマンド | カテゴリ | 目的 |
| :--- | :--- | :--- |
| `open` | プレビュー | PDF を即座に開く |
| `pdf:compress` | 圧縮 | PDF を軽量化する |
| `pdf:pages` | 画像化 | PDF のページを画像にする |
| `pdf:rasterize` | 入稿対策 | PDF の全ページを画像にして結合し直す |
| `clean` | メンテナンス | 不要な生成ファイルを削除する |

## vs open — PDF を開く

:::{.section-lead}
ビルド後に閉じた PDF をもう一度確かめるなら、macOS では `vs open` を使えます。ファイル名を指定すれば、章ごとに作った PDF も開けます。
:::

```bash
# ビルド生成物を自動選択して開く
vs open

# ファイル名を指定して開く（拡張子は省略可）
vs open 11-intro
vs open 11-intro.pdf
```

引数を省略すると、通常版と圧縮版のうち新しいほうを開きます。ファイル名を指定したときは、プロジェクト直下、`sources/` の順に探します。macOS 専用のコマンドです。

## vs pdf:compress — PDF を圧縮・軽量化する

:::{.section-lead}
レビュー用の PDF を送る前に容量を抑えたいときは、`vs pdf:compress` を使います。Ghostscript でビルド済みの PDF を圧縮し、別名のファイルを作ります。
:::

画像の解像度を下げて容量を減らすので、印刷所へは圧縮していない入稿用 PDF を渡してください。

### 基本的な使い方

```bash
# 既定のファイルを圧縮
vs pdf:compress

# 入力ファイル名を指定（拡張子 .pdf は省略可）
vs pdf:compress 11-intro
vs pdf:compress 11-intro.pdf

# 入出力ファイル名を明示指定
vs pdf:compress input.pdf output.pdf
```

引数を省略すると、本全体の PDF を圧縮します。出力は、元のファイル名に `_compressed` を付けた名前になります。

```bash
vs build 11-intro        # → 11-intro.pdf が生成される
vs pdf:compress 11-intro # → 11-intro_compressed.pdf が生成される
```

ビルドのたびに圧縮版を作るには、`config/book.yml` の `output.pdf.compress` を `true` にします（@chapref:ch-build）。処理時間が増えるので、普段は `false` のままにして、必要なときにこのコマンドを使うのがお勧めです。

## vs pdf:pages / vs pdf:rasterize

:::{.section-lead}
完成した PDF から見本ページを画像にしたいときや、印刷所からフォントに関する指摘を受けたときは、PDF を加工するコマンドを使えます。用途と、加工後に変わる性質を確認してから選んでください。
:::

### 本のページを画像として保存する（vs pdf:pages）
`vs pdf:pages` は、表紙や本文の一部を JPEG に書き出します。SNS やイベント告知に載せる見本ページを作るときに使えます。

```bash
vs pdf:pages
```

引数を付けずに実行すると、書籍全体をビルドした閲覧用 PDF（`mybook_v0.1.0.pdf` など、`project.name` と `project.version` から付く名前）のすべてのページを画像にし、`mybook_v0.1.0_images/` のようなフォルダへ保存します。プロジェクト直下に単章ビルドの PDF が並んでいても、それらは選ばれません。

別の PDF を画像にしたいときは、引数でファイル名を指定します（`.pdf` は省けます）。

```bash
vs pdf:pages 95-sample       # 95 章だけをビルドした 95-sample.pdf を画像にする
```

#### 特定のページだけを画像にする
「表紙と、3ページ目、そして5〜8ページ目だけを画像にしたい」という場合は、`--pages` オプションを使ってページを指定します。

```bash
# 1ページ、3ページ、5〜8ページのみを画像にする
vs pdf:pages --pages="1,3,5-8"
```

#### 画像の画質や保存先を調整する
画像の解像度や保存フォルダを変更することもできます。

| オプション | 既定値 | 説明 | 使用例 |
|:---|:---:|:---|:---|
| `--dpi` | `350` | 画像の解像度を指定します。数値を大きくするとより鮮明になります。 | `--dpi=600` |
| `--quality` | `95` | 画像の保存品質（1〜100）を指定します。 | `--quality=90` |
| `--output` | `(自動)` | 画像を保存するフォルダの名前を指定します。 | `--output=./samples` |

```bash
# 解像度を600dpiにして、./samples フォルダに保存する
vs pdf:pages --dpi=600 --output=./samples
```

### 印刷エラーを確実に回避する「ラスタライズ」（vs pdf:rasterize）
印刷所のシステムが PDF 内のフォントを受け付けない場合は、原因を確認したうえで、ページ全体を画像化する方法もあります。`vs pdf:rasterize` は、**すべてのページを画像にして結合し直した PDF** を作ります。文字を検索できなくなる、ファイルサイズが大きくなるなどのデメリットが発生します。必要に応じて用いてください。

```bash
vs pdf:rasterize
```

元の PDF の各ページを画像にして結合し直し、`<元のファイル名>_rasterized.pdf` を作成します。

#### ラスタライズした PDF の性質

- **フォントに由来する問題を避けられます**: 文字が画像になるので、入稿先がフォントを処理する必要がなくなります。画像の PDF を受け付けるかは、入稿先の条件で確かめてください
- **文字を選択・検索できなくなります**: 印刷の仕上がりには影響しません
- **ファイルサイズが大きくなります**: 元の数倍〜数十倍になることがあります

途中で書き出した各ページの JPEG を、終わったあとに削除するときは `vs pdf:rasterize --clean` とします。

`vs pdf:pages` と `vs pdf:rasterize` には `pdftoppm` が必要です。インストールされていないときは、`vs doctor --fix` で導入できます。

## vs clean — 生成ファイルを削除する

:::{.section-lead}
`vs clean` は、ビルドで作られたファイルを削除するコマンドです。中間ファイルはビルドの後に自動で削除されます。キャッシュを作り直したいときや、生成した PDF をまとめて削除したいときに使います。
:::

### オプション一覧

| オプション | 説明 |
|------------|------|
| `--purge` / `-P` | 最終 PDF も含めてすべて削除 |
| `--cache` / `-C` | `.cache/vs/`・`.cache/metrics/` キャッシュのみ削除 |
| `--cover` | 生成されたカバー画像のみ削除（マスターは保持） |
| `--generated-images` | 生成された扉絵・装飾画像を削除 |
| `--all` | `--index-dictionaries` を除く上記すべてをまとめて実行 |
| `--index-dictionaries` | 索引・用語集辞書データを削除（確認あり） |

:::{.tip}
ビルド結果が更新されないなど、キャッシュが原因と思われるときは `vs clean --cache` を試せます。次のビルドでは必要なデータが作り直されます。
:::

## カスタム CSS — スタイルを調整する @custom-css

:::{.section-lead}
書籍全体の色や書体は `config/book.yml` で選べます。リンクの色やコードブロックの枠など、一部分の見た目を調整したいときは `stylesheets/custom.css` を編集します。

この機能は実験的なもので、次のメジャーバージョンで仕様が変わる可能性があります。
:::

### 仕組み

ビルド時、各章の Markdown には次の順番でスタイルシートが適用されます。

1. **`theme.css`** — テーマ色や見出しの寸法などの CSS 変数の既定値
2. **`chapter.css`** 等 — 章タイプごとのレイアウト
3. **`book-settings.css`** — `book.yml` の設定をビルド時に書き出したもの（`.cache/vs/` に作られます）
4. **`custom.css`** — 著者が自由に編集できるファイル（**ビルドで上書きされない**）

`custom.css` は最後に読み込まれます。同じ条件の CSS ルールなら後から書かれた指定が優先されるため、ここまでのスタイルを上書きできます。

::: {.note}
`theme.css` や `page-settings.css` は `vs upgrade` で新しい雛形へ更新されます。直接編集すると、雛形が変わるたびに手元の変更との突き合わせが必要になります。恒久的なカスタマイズには `custom.css` を使ってください。
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

`theme.css` と `page-settings.css` で定義されている主な CSS カスタムプロパティの一覧です。`custom.css` でこれらの値を上書きできます。コラムの文字の大きさのように変数のないものは、`.column { font-size: 9pt; }` のように規則を書きます。

#### 配色（theme.css）

| 変数名 | 既定値 | 説明 |
| :--- | :--- | :--- |
| `--theme-accent` | `var(--accent-green)` | テーマのアクセントカラー |
| `--color-text` | `#000` | 本文テキスト色 |
| `--color-link` | `#000` | リンク色 |
| `--color-strong` | `var(--theme-accent)` | 太字（`**強調**`）の色 |
| `--color-em-underline` | `var(--theme-accent)` | 強意（`*イタリック*`）の下線色 |
| `--color-border` | `#ccc` | 画像など汎用枠線色 |
| `--color-column-bg` | テーマ色を淡くした色 | コラム背景色 |
| `--color-column-border` | `var(--theme-accent)` | コラム枠線色 |
| `--color-figure-border` | `#ccc` | 図の枠線色 |
| `--color-danger` | `#f00` | 警告色 |

#### 版面・フォント（page-settings.css）

既定値は `b5_standard` の例です。実際の値は `page.use` と `typography` で決まります。

| 変数名 | 既定値（例） | 説明 |
| :--- | :--- | :--- |
| `--base-font-size` | `10.5pt` | 基準文字サイズ |
| `--base-line-height` | `17.85pt` | 行送り |
| `--letter-spacing` | `0em` | 字間 |
| `--page-margin-top` | `25mm` | 天（上余白） |
| `--page-margin-bottom` | `25mm` | 地（下余白） |
| `--page-margin-inner` | `25mm` | ノド（綴じ側余白） |
| `--page-margin-outer` | `20mm` | 小口（外側余白） |
| `--font-main-text` | `"Noto Serif JP"` | 本文フォント |
| `--font-header` | `"Noto Sans JP"` | 見出しフォント |
| `--font-code` | `"HackGen35 Console NF"` | コードフォント |

:::{.tip}
`book.yml` の `theme.color` や `page.use` で設定できる項目は、まず `book.yml` で設定するのがお勧めです。`custom.css` は `book.yml` では設定できない細かな調整に使ってください。
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

## 章テンプレートのカスタマイズ

:::{.section-lead}
`vs create` で章を作るときは、`templates/` の雛形が使われます。毎回必要な見出しやリード文の枠を入れておけば、新しい章を作ったところから本文を書き始められます。
:::

### テンプレートの編集

章番号と雛形の対応は @chapref:ch-chapter-management で説明しています。`templates/chapter.md` を開いて自由に編集できます。テンプレート内の `{{TITLE}}` は、章のスラッグ（`11-intro` なら `intro`）に置き換わります。

```markdown
<!-- templates/chapter.md の例 -->
# {{TITLE}}

:::{.chapter-lead}
:::

## はじめに

## まとめ
```

### QueryStream テンプレート

`templates/` には章テンプレートのほかに、ファイル名の先頭に `_` が付く QueryStream のデータ展開テンプレート（`_book.md` など）も置かれます。新しいデータファイルを追加するときは、対応するテンプレートをここに作成します（@chapref:ch-querystream）。
