# 補助コマンドとカスタマイズ

:::{.chapter-lead}
原稿を書く作業の周りには、ビルド前の点検、PDF の閲覧・圧縮・画像化、生成物の片づけといった小さな仕事があります。本章では、そのときに使う補助コマンドと、紙面の CSS や章の雛形を自分の本に合わせる方法をまとめます。必要な場面から読んでください。
:::

| コマンド | カテゴリ | 目的 |
| :--- | :--- | :--- |
| `preflight` | 点検 | ビルドの前に原稿の参照先を確かめる |
| `open` | プレビュー | PDF を即座に開く |
| `pdf:compress` | 圧縮 | PDF を軽量化する |
| `pdf:pages` | 画像化 | PDF のページを画像にする |
| `pdf:rasterize` | 入稿対策 | PDF の全ページを画像にして束ね直す |
| `clean` | メンテナンス | 不要な生成ファイルを削除する |

## vs preflight — 原稿を点検する

:::{.section-lead}
組版を待たずに原稿の問題を確かめたいときは、`vs preflight` を使います。PDF を生成せず、画像やコードの参照先などを短時間で確認できます。
:::

preflight は「飛行前点検」という意味です。章を書き終えたときやフルビルドの前に実行すると、参照先の置き忘れを早く見つけられます。

### vs build との比較

| | `vs preflight` | `vs build` |
|:---|:---|:---|
| 実行時間 | 数秒 | 数分（本書の全章で約 6 分） |
| PDF 生成 | しない | する |
| エラー検出 | その場で報告 | ビルド後に判明 |
| 用途 | 執筆中の頻繁なチェック | 入稿・配布前の最終ビルド |

`vs build` でも同じ検証は行われますが、エラーに気づくのがビルド完了後になります。`vs preflight` を先に実行しておけば、ビルドを待たずに問題を直せます。

### 基本的な使い方

```bash
vs preflight         # 全章をチェック
vs preflight 11      # 11章だけチェック
vs preflight 21-24   # 21〜24章をチェック
vs preflight intro   # スラッグが intro の章をチェック
```

章の書き方は `vs build` と同じです（@ch-chapter-management の章の @pageref:chapter-targets）。

### 実行結果の見方

`🔴` は品質エラー（著者の意図が成果物に反映されない）、`🟡` は警告（確認を促したい）を表します。検出できる問題の種別は以下のとおりです。

| 種別 | 記号 |
|:---|:---:|
| 画像ファイル不在 | 🔴 |
| コードインクルードファイル不在 | 🔴 |
| QueryStream 雛形ファイル不在 | 🔴 |
| ラベル ID重複 | 🔴 |
| 裸URL | 🟡 |
| 孤立ラベル | 🟡 |

たとえば `vs preflight 11 95` で二つの章を点検すると、次のように出力されます。

:::{.output}
```text
🟡 95-sample.md:201 - 裸 URL を検出しました
        URL: https://www.nobelprize.org/prizes/physics/1926/perrin/lecture/
🔴 95-sample.md:571 - 雛形ファイル '_physics_book.full.md' が見つかりません（記法: = physics_books | :full）
        雛形の場所: templates/_physics_book.full.md
        ヒント: templates/_physics_book.md は存在します。スタイル名を確認してください。
🔴 11-workflow.md:56 - 画像 'workflow.svg' が見つかりません（代替画像を使用します）
        画像の場所: images/11-workflow/workflow.svg
🔴 95-sample.md:246 - ソースコード 'mass_energy.rb' が見つかりません
        コードの場所: codes/mass_energy.rb
🔴 95-sample.md:160 - ラベルID '仕事関数の目安 @photoelectric-table' は重複しています
        重複箇所: 95-sample.md: 160, 166
🟡 95-sample.md:203 - 孤立ラベル '拡散係数の測定値 @diffusion-table' は未参照です
🔍 リンク・画像検証の結果:
        画像: 1 件の課題（存在しない画像: 1）
        ソースコード: 1 件の課題（存在しないファイル: 1）
        リンク: 1 件の問題（裸 URL: 1）
        外部URL到達性チェック: スキップ（--verify-links で有効化）

📋 章別サマリー
   11 執筆ワークフローとクイック… 🔴 エラー 1 件
   95 挑戦することの贈り物        🔴 エラー 3 件・🟡 警告 2 件
❌ Preflight 完了: エラー 4 件・警告 2 件 — 詳細は上記を確認してください
   文章校正（表記揺れ・スペル）は vs lint で行えます。
```
:::

最後の章別サマリーで、どの章に何件の課題があるかを確かめられます。課題がない場合には、次のように出力されます。

:::{.output}
```text
✅ 全 28 章: 問題なし
✅ Preflight 完了: 良好な状態です
   文章校正（表記揺れ・スペル）は vs lint で行えます。
```
:::

警告だけのときは「❗ Preflight 完了: 警告 2 件（ビルドは可能です）」のように出力され、そのままビルドへ進めます。

### オプション

| オプション | 説明 |
|:---|:---|
| `--log <level>` | ログレベルを指定（error / warn / info / debug） |
| `-h` / `--help` | ヘルプを表示 |

### 終了コード

`vs preflight` はシェルスクリプトや Makefile からの呼び出しを考慮して、終了コードを返します。

| 終了コード | 意味 |
|:---|:---|
| `0` | 問題なし（警告のみの場合も含む） |
| `1` | ❌ エラーが1件以上検出された |

:::{.tip}
**執筆中の活用例**

章を書き終えたところで `vs preflight <章番号>` を実行すると、画像の置き忘れやコードファイルのパス違いに気づけます。問題を直してから単章ビルドへ進めば、紙面の確認に集中できます。
:::

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

引数を付けずに実行すると、書籍全体をビルドした閲覧用 PDF（`janken_v0.1.0.pdf` など、`project.name` と `project.version` から付く名前）のすべてのページを画像にし、`janken_v0.1.0_images/` のようなフォルダへ保存します。プロジェクト直下に単章ビルドの PDF が並んでいても、それらは選ばれません。

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
画像の解像度（きれいさ）や保存フォルダを自由に変更することもできます。

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

元の PDF の各ページを画像にして束ね直し、`<元のファイル名>_rasterized.pdf` を作成します。

#### ラスタライズした PDF の性質

- **フォントに由来する問題を避けられます**: 文字が画像になるので、入稿先がフォントを処理する必要がなくなります。画像の PDF を受け付けるかは、入稿先の条件で確かめてください
- **文字を選択・検索できなくなります**: 印刷の仕上がりには影響しません
- **ファイルサイズが大きくなります**: 元の数倍〜数十倍になることがあります

途中で書き出した各ページの JPEG を、終わったあとに消すときは `vs pdf:rasterize --clean` とします。

`vs pdf:pages` と `vs pdf:rasterize` には `pdftoppm` が必要です。入っていないときは、`vs doctor --fix` で導入できます。

## vs clean — 生成ファイルを削除する

:::{.section-lead}
`vs clean` はビルド中に作られたファイルを片付けるコマンドです。通常のビルド後は自動で片付けられますが、中間ファイルを調べたあとや、キャッシュを作り直したいときに使えます。
:::

`vs build` 実行後に中間ファイルを残したい場合は `--no-clean` を使います（開発者向け仕様）

```bash
vs build --no-clean   # 中間ファイルを残してビルド
vs clean              # 後から手動でクリーンアップ
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

:::{.tip}
ビルド結果が更新されないなど、キャッシュが原因と思われるときは `vs clean --cache` を試せます。次のビルドでは必要なデータが作り直されます。
:::

## カスタム CSS — スタイルを調整する

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
| `--font-main-text` | `"Noto Serif JP"` | 本文フォント |
| `--font-header` | `"Noto Sans JP"` | 見出しフォント |
| `--font-code` | `"hackgen35"` | コードフォント |
| `--column-font-size` | `8pt` | コラムの文字サイズ |

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

`templates/chapter.md` を開いて自由に編集できます。テンプレート内の `{{TITLE}}` は、章のスラッグ（`11-intro` なら `intro`）に置き換わります。

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

新しいデータファイルを追加する場合は、対応するテンプレートをこのディレクトリに作成してください。詳細は @chapref:ch-querystream を参照してください。
