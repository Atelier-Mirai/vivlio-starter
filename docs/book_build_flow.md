# 📚 ビルド仕様書
本ドキュメントでは、書籍のビルドプロセスである「フルビルド」と「単章ビルド」の概要と実行ステップを定義します。

## フルビルド (Full Build)

### 実行コマンド

```bash
vs build
```

### 概要

book.yml ファイルの chapters キーを参照し、書籍全体のPDFを生成します。目次 (TOC)、奥付、アウトライン（しおり）、およびPDFの圧縮を含む、全ての工程を実行します。

### 実行ステップ

| Step    | 名称                          | 処理内容 |
|---------|-------------------------------|----------|
| Step 0  | (clean)                       | クリーンアップ処理を実行します (run_step0_clean)。 |
| Step 1  | (optimize images)             | 画像の最適化処理を実行します (run_step1_optimize_images)。 |
| Step 2  | (prepare theme images)        | テーマに使用される画像の準備を行います (BuildHelpers.prepare_theme_images!)。 |
| Step 5  | (build sections html)         | 各セクションのHTMLをビルドします (BuildHelpers.build_sections_html!)。 |
| Step 6  | (generate toc and pdf)        | 目次 (TOC) を生成し、PDFとして出力します (BuildHelpers.generate_toc_and_pdf!)。 |
| Step 7  | (build overall pdf and split) | 全体PDFを生成し、TOC (目次) と sections (本文+付録+後書き) に分割します (BuildHelpers.build_overall_pdf_and_split_from_dir!)。 |
| Step 8  | (build 02-03-front.pdf)       | 前付 (titlepage, legalpage, colophonpage) のPDFをビルドします (BuildHelpers.build_frontmatter_pdf!)。 |
| Step 9  | (build front pages and tail)  | 前ページ（表紙など）および後書きページのビルドを行います (run_step9_front_pages_and_tail)。 |
| Step 10 | (merge all pdfs with outline) | 全ての中間PDFを結合します（アウトライン情報を含む） (BuildHelpers.merge_all_pdfs_only!)。 |
| Step 11 | (apply outline to output pdf) | 出力されたPDFにアウトライン（しおり）を適用します (BuildHelpers.add_outline_to_output_pdf!)。 |
| Step 12 | (compress pdf)                | PDFの圧縮処理を実行します (run_step12_compress_pdf)。 |
| Step 13 | (rename output pdfs)          | 出力PDFのファイル名をリネームします (BuildHelpers.rename_output_pdfs!)。 |
| Step 14 | (final clean)                 | 最終的なクリーンアップ処理を実行します (run_step14_final_clean)。 |

## 単章ビルド (Single Chapter Build)

### 実行コマンド

```bash
vs build [章番号]
```

例: vs build 54-56

### 概要

book.yml の chapters キーの代わりに、コマンド引数で指定された章のみを参照してPDFを生成します。これは、指定された章の確認や修正を目的とした、簡易的なビルドフローです。

### フルビルドとの主な相違点

- 前付ページの非生成: titlepage, legalpage, colophonpage の生成は行いません。
- 目次 (TOC) の非生成: 目次の生成は行いません。
- アウトラインの非適用: PDFへのアウトライン（しおり）の適用は行いません。
- 圧縮処理の非実行: PDFの圧縮処理は行いません。

### 実行ステップ

| Step    | 名称                          | 処理内容 |
|---------|-------------------------------|----------|
| Step 0  | (clean)                       | クリーンアップ処理を実行します (run_step0_clean)。 |
| Step 1  | (optimize images)             | 画像の最適化処理を実行します (run_step1_optimize_images)。 |
| Step 2  | (prepare theme images)        | テーマに使用される画像の準備を行います (BuildHelpers.prepare_theme_images!)。 |
| Step 5  | (build sections html)         | 指定された章のHTMLをビルドします (BuildHelpers.build_sections_html!)。 |
| Step 10 | (merge all pdfs) (Optional)   | merge オプションが指定された場合、全ての中間PDFを結合します（アウトラインなし）。 |
| Step 13 | (rename output pdfs) (Optional) | merge オプションが指定された場合、出力ファイル名は projectname.pdf となります。それ以外の場合、各章ごとにファイルが出力されます（例: 54.pdf, 55.pdf, 56.pdf）。 |
| Step 14 | (final clean)                 | 最終的なクリーンアップ処理を実行します (run_step14_final_clean)。 |

### 今後の検討課題

- **ステップ構成と実装の差異解消**: 現状の単章ビルドは `SingleChapterRunner` により `pre_process → convert → post_process → entries → pdf` のみを実行しており、仕様上の Step 0/1/2 などとは一致していません。将来的に、フルビルドのパイプライン（`FullBuildPipeline`）の論理的なサブセットとして再設計するかどうかを検討します。
- **オプション挙動の整理**: `--resize` や `--clean`、`--compress` などのオプションは、現在、フルビルドと単章ビルドで有効範囲が異なります。各オプションの意味を両者で揃えることとします。単章ビルド専用であった merge オプションは廃止します。
- **フルビルドとの成果物整合性**: `chapters:` で同じ章集合を指定したフルビルドと `vs build [章番号]` の単章ビルドで、章番号・図表番号・クロスリファレンス結果が一致することを原則としますが、単章ビルドで章の範囲外の図表等が指定されていた場合、図??-?? で出力するものとします。
- **ログ・計測出力の共通化**: 単章ビルドのタイミング計測・ログフォーマット（`SingleChapterRunner` + ビルドタイミング出力）と、フルビルドの `Build Step Timings` / `timings_summary.md` 出力を可能な範囲で共通化し、保守性を高めることを検討します。

## テスト計画（案）

- **book.yml と生成物の対応確認**  
  - `chapters: all` / 数字レンジ（例: `11-13`）/ 複合レンジ / ファイル名配列など、代表的な `chapters` 設定ごとに `vs build` を実行し、期待する章 PDF / HTML が生成されているかを確認する。  
  - `pdf.output_file` や圧縮 suffix などの設定変更時に、最終的な PDF ファイル名・個数が仕様どおりかを確認する。
- **フルビルドと単章ビルドの整合性確認**  
  - 例: `chapters: 54-56` を指定した状態でフルビルドを実行した結果と、`vs build 54-56`（単章ビルド）を実行した結果について、54〜56章の HTML / PDF を比較し、章番号・図表番号・クロスリファレンス（相互参照リンク）が一致していることを確認する。
- **単章ビルド固有の挙動確認**  
  - `vs build 55-56` などを実行し、指定した章のみの PDF が生成されていること（不要な章 PDF が増えないこと）を確認する。  
  - `--merge` 有無で、章別の PDF のみ生成されるケースと、結合された output.pdf／リネーム済み PDF が生成されるケースの違いが仕様どおりであることを確認する。
- **テスト実行方法（CI なし前提）**  
  - 本テストは現時点では CI には組み込まず、必要に応じて開発者がローカル環境で手動実行する方針とする。  
  - 例: `bundle exec ruby test/build_flow_test.rb` のように、手動で一括実行できるスクリプトやテストエントリポイントを提供することを検討する。



## 仕様の疑問点などへの追加説明

1. 現状の構造の違いについて: 
FullBuildPipeline でも book.yml chapters で指定された章番号を元に 章番号の振り直しは行っています。

2.1 entries.js 生成のタイミングについて: 
vs build 54-56 の場合、54-56章を統合した entries.js を生成することとして、一つのpdfを生成してOKです。ファイル名は54-56.pdfとなり、ビルド完了後は、このファイルが自動で開かれます。またこれに伴い、mergeオプションは廃止となります。
export default [
  {
    "path": "./54-first-html.html",
    "title": "初めてのHTML"
  },
  {
    "path": "./55-first-html.html",
    "title": "初めてのHTML"
  },
  {
    "path": "./56-first-html.html",
    "title": "初めてのHTML"
  }
]

2-2. PDF 生成のスコープについて:
vs build 54 と指定された場合には、54章のみのPDFを生成します。
vs build 54-56 のように複数の章を指定された場合には、54-56章を統合したPDFを生成します。

2-3. 章番号の仮想連番（HeadingProcessor.chapter_tokens_override）について:
Full build: 使用しない（全章を正規番号でビルド）。
Single chapter: 指定章を「第 1 章, 第 2 章…」のように振り直す。

意図している動作としては、book.yml の chapters で指定された章番号を対象として、全章ビルドの場合は章番号が振られています。
vs build 54-56 のように、複数の章番号が指定された場合には、book.yml の chapters に 54-56 が指定されているものと見なすことで、全章ビルドで使用しているものと同様の章番号の振り直しを実現するということです。従って、単章ビルド専門のメソッドは不要になるはずです。

また、仕様書には「単章ビルドで章の範囲外の図表等が指定されていた場合、図??-?? で出力する」とあり、クロスリファレンス処理もモード依存の分岐が発生しますとのことですが、
これに関しては、フルビルドでも同様の処理が発生するはずです。
vs build で全章ビルド指定されている場合に、book.yml の chapters に 54-56 が指定されていたら、フルビルドでも同様の問題が発生するはずです。


| Step | 処理内容 | Single Mode での扱い |
|------|---------|---------------------|
| Step 0 | clean | 実行 |
| Step 1 | optimize images | 実行 |
| Step 2 | prepare theme images | 実行 |
| Step 5 | build sections html | 対象章のみ実行 |
| Step 6 | generate toc and pdf | スキップ |
| Step 7 | build overall pdf and split | スキップ |
| Step 8 | build frontmatter pdf | スキップ |
| Step 9 | build front pages and tail | スキップ |
| Step 10 | merge all pdfs with outline | スキップ |
| Step 11 | apply outline to output pdf | スキップ |
| Step 12 | compress pdf | スキップ |
| Step 13 | rename output pdfs | 実行（章単位リネーム） |
| Step 14 | final clean | スキップ |

課題: 「スキップ」の粒度を対象トークンの有無で自動判定します。
vs build -> 全章ビルド (full mode)
vs build 54 -> 54章のみのビルド (single mode)
vs build 54-56 -> 54-56章のみのビルド(entry.jsにより統合された一つのpdfが出力される) (single mode)

2-5. タイミング計測・ログ出力の統一について:
Full build: FullBuildPipeline#execute でステップ単位に計測し、最後に Build Step Timings としてサマリーを出力。
Single chapter: SingleChapterRunner#run で章×ステップ単位に計測し、別フォーマットで出力。
課題: 統合後は計測ラベルを <step> / <chapter> のような共通フォーマットに揃え、サマリー出力も一本化する必要があります。
full build のものをそのまま使用しようしてください。（スキップされた部分の出力は不要にして、また<chapter>の出力は不要でOKです）

2-6. 並列処理の扱い
vs build 54-56 のように、複数章が指定されるとしても、3章くらいを想定しています。
その為、並列処理は不要です。

3.1 single mode の判定基準
引数 tokens が 1 つ以上あれば single mode とします。（--single フラグなどは要求しません。）

3.2 full build 時の --merge の扱い
仕様書では「merge オプションは廃止」とありますが、single mode での結合機能自体は残すのか？
