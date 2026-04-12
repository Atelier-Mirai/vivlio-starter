## ボトルネック別の所要時間

- **Step 7 `build_overall_pdf_and_split!()`** (約 11.66s)
  - `BuildHelpers.compile_overall_pdf_and_split!()` で Vivliostyle による大規模 HTML→PDF 生成と分割を実施。
  - **target 数削減**: ドラフトや不要章は `keep` 設定で除外する。
  - **キャッシュ活用**: Vivliostyle 側を常駐化・サーバーモード化して再生成を減らす。

- **Step 12 `compress pdf`** (約 13.28s)
  - `Vivlio::Starter::ThorCLI.start(['pdf_compress'])` → HexaPDF 圧縮がボトルネック。
  - **圧縮スキップ**: サイズ許容時は `--no-compress` を検討。
  - **品質調整**: `config/book.yml` の `pdf.compress` 設定を見直し、画質とのバランスを最適化。

- **Step 6 `generate_toc_and_pdf`** (約 5.28s)
  - `BuildHelpers.generate_toc_and_pdf!()` が章 HTML を読み込み `03-toc.html` を毎回再生成。
  - **キャッシュ条件分岐**: `03-toc.html` に差分が無ければ再生成をスキップする仕組みを検討。

- **Step 5 `build_sections_html!`** (約 1.33s)
  - 並列度 4 で実行済み。
  - **並列度調整**: `VIVLIO_BUILD_CONCURRENCY` を環境コア数に合わせて 6 などへ調整。
  - **対象絞り込み**: `parallel_each()` の対象から更新不要章を事前に除外。

## 推奨アクション

- **PDF フローの見直し**
  ```bash
  vs build --no-compress --log
  ```
  で圧縮スキップ時の性能・ファイルサイズを比較。

- **Vivliostyle サーバーモードの検証**
  - `vivliostyle-cli` を常駐化して複数ジョブを単一プロセスで処理し、Step 7 の高速化を狙う。

- **`keep` 設定の活用**
  - `config/book.yml` の `chapters` で対象章を限定し、日次作業では更新分だけビルド。

- **TOC 再生成の条件分岐**
  - `03-toc.html` の更新要否を判定し、変更が無ければ Step 6 をスキップする仕組みを追加検討。
