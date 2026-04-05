# 変更履歴（Changelog）

このファイルには、本プロジェクトの主な変更内容を記録します。

記法は「Keep a Changelog」に基づき、Semantic Versioning（セマンティックバージョニング）に準拠します。



### Pre-release Checklist
- gem 公開時には `vivlio-starter.gemspec` の summary/description が現行仕様に即しているか再確認する。
- `pre_process.rb` で参照する theme.css テンプレート（`lib/project_scaffold/stylesheets/theme.css`）が gem に同梱されているか確認する。
- リリースノートの作成

#### 実装済み
- [Medium] lint 出力の再整形フォーマッター（列番号除去・ルール名括弧化・冗長部除去・英語メッセージ日本語化・ファイルパス相対化）
- [Medium] lint メッセージの最終整形（サマリ行ノイズ除去、末尾ルール名の付与、unmatched-pair 日本語化、ファイル見出しの余白整理）
- [Medium] lint コマンドの章指定解釈を TokenResolver に統一（独自 TargetResolver を廃止し、ゼロ埋め・降順レンジ・カンマ区切り等を他コマンドと同一ロジックで処理）
- [High] 任意の複数章を指定して、フルビルドする
- [High] 任意章フルビルド（既出の計画を拡張）章IDの指定順で束ね、目次・通し番号も整合。実装目安: rake build --chapters=11,12,21 形式。
- [High] PDF に章アウトライン（ブックマーク）を付与（本文PDF/最終PDF）。読者のナビゲーション向上のため、Step 7/10 後段で HexaPDF により後付け。
- [High] 縦に長い表のレイアウト崩れ
- [Medium] 図表キャプション規約の統一（Figure 1.1/表1.1 自動採番）。
- [High] Re:View Starter -> Vivlio Starter (vs import実装完了)
- [Medium] text_metrics に語の平均長・漢字比率など語彙難度指標を追加する
- [Medium] text_metrics に語彙多様度（TTR 等）の集計を追加する
- [Low] text_metrics で日本語向け読解難度スコア（Flesch/Kincaid 等を応用）を算出する
- [Low] text_metrics で見出し/セクション単位の分量バランスを可視化する
- [High] ビルド時にcover画像も含むように
- [Low] 用語集・索引自動生成
- [Medium] 用語集・索引自動生成 （それらしい専門用語を抽出して、`config/glossary.yml` に一括追加するタスク）
- [Medium] build / metrics / delete など CLI コマンド間で共通のショートハンド展開ロジックを切り出し、catalog.yml ベースの章解決を一元化する。
- [Medium] A4 以外の紙サイズを指定する（推奨文字サイズの確認）
- [Medium] book.yml の chapters を、contents/と連動するように。
- [Medium] 用語候補抽出と一括追加（glossary）: `contents/` を走査し `ABBR(Full Name)`/`Full Name(ABBR)` パターンを検出して候補一覧を作成。対話的に選択して `config/glossary.yml` に一括追加するタスク（例: `glossary:suggest` → `glossary:import_selected`）。※ 用語抽出のみ索引機能に包含して実装済み。
- [Medium] 用語集の付録化（`config/glossary.yml` → 付録章に整形出力、名称/略称/説明/スタイルを一覧化）
- [Medium] 初出ページ付き索引の生成（用語の文書走査→初出箇所のページ番号抽出→索引章に出力）
- 00, 01, (blank), 02, (blank), 03, (blank), 11-98(cssにより右頁始まり), (blank), 99 として結合
- [High] 奥付が偶数ページになるように
- [High] 塗り足しやepub対応
- [Medium] 出力バリアント PDF（裁ち落とし/ノンブル有無）、Web/EPUB（任意）。
- [Medium] ビルドのマニュアルを書く
- [Medium] 見出しID・相互参照ショートコード（ref:foo → 自動リンク）。
- [Medium] 章・節に対する相互参照の整備（章番号ベースの cross reference）。本文中から「第◯章」「第◯節」を参照する簡潔な記法を設計し、既存の `@id` ベースの図表・コードリスト参照パイプラインと統合する。
- [High] vs lint に スペルチェックを盛り込む
- [High] pdf_reader.rbを改修、pdf -> mdにするコマンドを実装する
- [High] data/ディレクトリから、yml形式で書籍(タイトル、著者、ISBNなど)などを展開できるようにする。

### Planned

#### ビルド/出力
- [High] 単章ビルドシステムのリファクタリング: 現在実装済みの単章ビルドtargets対応は機能的に完備しているが、コード構造の整理と保守性向上のためのリファクタリングを実施。ステップ登録ロジックの最適化、メソッド責務の明確化、テストカバレッジの拡充を含む。
- [High] 日本語表記・組版Lint（スタイルガイド）
- [High] リンク・画像の自動検証
- [Medium] リスト体裁改善の実装: 技術書で頻出するアルファベットリスト（a., b., c.）に対応。Markdownでは`a.`がリストとして解釈されないため、CSSユーティリティ（`ol.lower-alpha { list-style-type: lower-alpha; }`）を追加し、`<ol class="lower-alpha">`の生HTML記法で簡潔に実現可能にする。
- [Medium] 基本的に良く用いる用語をまとめた用語集テンプレートを標準添付し、プロジェクト作成時または後から選択適用できるようにする。
- [Medium] VFM設定のエントリーレベル適用: vivliostyle.config.js生成時に、ルートレベルではなく各エントリー個別にVFM設定を適用するよう改善。現在のフロントマターにvfm: hardLineBreaks: true設定でも動作するが、エントリーレベル設定によりきめ細やかな制御とVivliostyle CLI公式推奨方式への準拠が可能になる。
- [Low] Dataオブジェクト拡張の検討: Ruby 4.0のDataオブジェクトにempty?メソッドを拡張し、book.ymlの各種設定値をより直感的に扱えるようにする。現在はvfm_config&.hardLineBreaksのような安全呼び出しで対応しているが、Data.empty?メソッドがあればより自然なコード記述が可能になる。
- [Low] 画像の width 属性自動補完: Markdown が `![](foo.png)` のように幅指定なしの場合でも、実寸やクラス指定に応じて `width=100%` 等を自動補う仕組みを検討する（大判図をページ送りにせず収めるため）。

#### 参照・索引・書誌
- [Low] 脚注・参考文献サポート（簡易BibTeX/CSL）

#### テーマ/スタイル
- [High] テーマシステムの実装: vivliostyle 公式が提供する bunko.css などの既存テーマ CSS を活用できるようにする。config/book.yml からのテーマ選択、CSS ファイルの動的切り替え、小説用縦書き・技術書用横書きなどのプリセットテーマを提供。

#### コンテンツ/テンプレート
- [Low] テンプレ断片スニペット（注意/補足/Tipのコンポーネント化）。
- [High] 11-install.mdなどを、著者の使い方や、書き方の例として、書き直す。
- [High] tamplates/chapter.mdなどを、書き方の例として書き直す
- [High] プロジェクト生成時に、.cache/vs/ を生成する。
- [High] プロジェクト生成時に、project_scaffold/ を生成する。
- [High] vs new で、プロジェクト生成時に、scaffold以下の資産が新プロジェクトに展開され、著者が執筆の参考となるよう、書き方の例として、vivio-starterのマニュアルを展開する。

#### 品質・テスト
- [Medium] Post-processing単体テスト整備: `_postReplaceList.json`の主要ルール（段落クラス付与、見出し・bodyクラス、各種クレンジング）のスナップショットテストを追加。想定外パターン（複数ブレース、引用符・バックスラッシュ混入等）の回帰防止。
- [Low] 自動検証パイプライン（CI）: 最小サンプルでのビルド、Lint、HTMLポスト処理テストの自動実行。

#### 開発者体験・保守性
- [Medium] ビルドログ整備: ビルド各ステップに要約出力とエラーヒントを追加し、失敗時の原因特定とリカバリーを容易にする。
- [Low] スタイルガイド整備: 章タイプ別（preface/chapter/appendix/postface）スタイルの設計指針、ユーティリティクラス（`.aki`, `.aki2`, ほか）一覧、使用例をドキュメント化し、保守性を向上させる。






## Unreleased
（次回リリース候補の変更はここに追加してください）

### Added
- **カバー自動生成機能を実装**: `docs/specs/cover_auto_generation_spec.md` に基づき、表紙・裏表紙の自動生成機能を開発した。SVG→PDF変換、トンボ描画、RGB/CMYK出力、ビルドパイプライン統合までを含む完全自動化を達成。現在トンボ描画ロジックをVivliostyleコアと完全一致させ、crop offset領域のみに描画する仕様を確定済み。
- SVG カバー → PDF カバー変換完成: light/dark テーマの SVG カバーを rsvg-convert で PDF に変換する処理を完成。CSS カスタムプロパティ（`var(--xxx)`）を rsvg-convert に渡す前にインライン展開する処理（`expand_css_custom_properties`）を実装し、文字色・線色が正しく反映されるようになった。また表紙 PDF に TrimBox/BleedBox を設定し、印刷所入稿時に正しく B5（182mm × 257mm）で裁断されるよう対応。コーナートンボ・センタートンボの形状・寸法を本文（Vivliostyle 生成）と統一。

- **単章ビルドの完全なtargets対応**: `vs build 1`で`config/book.yml`の`output.targets`に応じてPDF・print_pdf・EPUBを柔軟に生成可能に。複合ターゲット（`pdf, print_pdf, epub`など）にも完全対応し、組み合わせ爆発を回避するシンプルな条件分岐ロジックを実現。これによりサンプル配布用の単章EPUB生成や入稿用単章PDF生成が本格的に実用可能に。
- **VFMのハード改行機能をデフォルトで有効化**: `hardLineBreaks: true` を既定値に設定し、日本語文章の直感的な執筆体験を向上。フロントマターで個別無効化（`hardLineBreaks: false`）も可能。コードブロックと空行は影響を受けない（VFM標準準拠）。

### Fixed
- **vs build --compress オプションの不具合修正**: Step 12の呼び出し順序を修正（圧縮→リネームの順に変更）。`output_compressed.pdf`が正しく生成されるようになり、動的ファイル名（例: `janken_v0.1.0_compressed.pdf`）に対応。
- **Enhanced Modeへの切り替え処理を修正**: Gemfileに`vivlio-starter-pdf`を追加しBundler環境下でのプラグインロードを改善。`vs build --compress`時にアウトライン付与がEnhanced Modeで実行されるようになった。Standard Mode時の警告メッセージを改善（Step番号を削除し表現を調整）。

### Changed
- **ビルドステップの表示名を改善**: Step 12の表示名を`(compress, rename and final clean)`に変更し、圧縮処理の時間が含まれることが明示的にわかるように修正。
- **チュートリアルドキュメントを更新**: ハード改行セクションを書き直し。
- **buildコマンドのオプションを整理**: 使用頻度の低いオプションを削除：`-n/--dry-run`、`--force`、`--no-cache`。関連するデッドコードを完全に削除し、ビルドシステムをクリーンアップ。よく使う実用的なオプションに焦点を当てたシンプルなインターフェースに。
- **ビルド完了メッセージを改善**: ビルド完了時に生成されたPDFファイル名を自動表示。圧縮PDFや複数章ビルドにも対応し、📚絵文字付きで分かりやすい表示に。`vs build --log=debug`時のBuild Step Timings表示順序を最適化（Outline Debug Info→Build Step Timings）。
- **`vs clean --all` のSVG削除ルールを改善**: `covers/frontcover_dark.svg` など `*_light.svg` / `*_dark.svg`（bundledテンプレートからの生成物）および `*_rendered.svg`（プレースホルダー適用済み中間ファイル）のみを削除対象とし、`covers/frontcover_floral.svg` など利用者が用意したカスタムSVGは保持するよう変更。

### Removed
- **cross_reference_report.mdの生成機能**: ビルド実行時に生成されていたクロスリファレンスレポートを出力するコードを削除。デバッグ用レポートは不要と判断し、`pre_process.rb`と`cross_reference_processor.rb`から関連コードを完全に削除。ビルドプロセスがさらにクリーンになり、不要なファイル生成がなくなった。

### Fixed
- **vs clean --allで単章EPUBが削除されない問題**: `--purge`時の削除パターンに`[0-9][0-9]-*.epub`を追加し、単章ビルドで生成されたEPUBファイル（例: `01-life.epub`）も`vs clean --all`で完全に削除されるように修正。これによりPDF、print_pdf、EPUBのすべての単章生成物がクリーンアップ対象になる。

## [0.34.0] - 2026-03-21

### Added
- **データ展開機能（QueryStream 記法）**: 原稿内に `= books | tags=ruby | -title | 5 | :full` のような QueryStream 記法を書くと、`data/*.yml` のデータを `templates/_*.md` のテンプレートで自動展開する機能を実装。等値・比較・範囲フィルタ、AND/OR 条件、ソート、件数制限、スタイル選択、主キー一件検索、nil 安全行スキップに対応。`book-vivlio-starter/23-data.md` に著者向けマニュアルを追加。
- **VFM フェンス記法対応**: QueryStream 1.0.0 の VFM フェンス記法（`:::{.class-name}`）に完全対応。各レコードが個別のフェンスで囲まれて展開され、vivlio-starter の Markdown 変換パイプラインと統合。
- **align-left/center/right ブロックユーティリティ**: `:::{.align-left}` / `.align-center}` / `.align-right` で任意コンテナを左・中央・右寄せできるよう `layout-utils.css` を更新。図版や画像の回り込みと干渉しないようブロック専用の余白レイアウトとし、本文中で簡潔に配置調整できるようにした。
- **章操作コマンドのスラッグ単体指定**: `vs build / create / delete / rename` で `three-elements` のような slug 単独指定を正式サポート。TokenResolver ベースで章解決を統一し、章番号を覚えていなくてもコマンド実行できるようにした。
- **pdf:read 設定サポート**: `config/book.yml` に `pdf_read.text_area` / `pdf_read.line_reflow` を追加し、ページ抽出領域と改行整理しきい値を著者が調整できるようにした。設定値は `PdfReadCommand` の本文抽出・改行再整形に即反映され、ユニットテストで回帰を担保。
- **数値のみ章トークン対応**: `catalog.yml` の整数エントリや `contents/15.md` のような純数字ファイルを `TokenResolver` と各 CLI（build/delete/rename/renumber/lint/metrics）で統一的に解決。`vs rename 15-foo 15` のような数字指定リネームや `vs build 15` がエラーなく動作するようになり、章番号だけで一連の操作が完結する。

### Changed
- **依存関係更新**: query-stream を 0.1.0 から 1.0.0 にアップグレードし、ローカルパス参照を削除して公開済みバージョンを使用するよう変更。
- **vivlio-starter-pdf 連携**: Enhanced Mode のローカル開発用コードを削除し、クリーンなインストール済み版参照に統一。

### Fixed
- **ローカルパス参照問題**: 開発環境でのローカル gem 参照を排除し、本番環境と同一の依存関係を確保。

## 0.33.0 - 2026-03-09

### Added
- **vs pdf:read 強化（Enhanced Mode 完成）**: prh 辞書によるOCR誤読補正・括弧正規化・日本語スペース除去を実装し、`vivlio-starter-pdf` gem を README/Licence 付きで独立配布。`book-vivlio-starter/22-pdf-read.md` に利用者向けマニュアルを追加し、OCRモードや画像抽出設定を含めたドキュメントを整備。

## 0.32.0 - 2026-02-21

### Added
- **スペルチェック機能の正式実装**: `vs lint` に英語スペルチェックを統合。英単語トークナイザ（Vivliostyle拡張記法・コードブロック除外対応）、辞書マネージャ（52ファイル・約46,000語の技術辞書群＋索引用語＋追加単語）、DidYouMeanベースの候補提示、`spellcheck:ignore` コメントや `book.yml` 設定による制御、textlint サマリとの統合表示を提供。

### Changed

### Fixed

## 0.31.0 - 2026-02-12

### Added
- **印刷入稿用 PDF（print_pdf）生成**: `output.targets` に `print_pdf` を含めると、Step 13 でトンボ・塗り足し付き PDF を自動生成。`--crop-marks --bleed 3mm` で Vivliostyle build → PDF 結合 → HexaPDF による隠しノンブル書き込み → アウトライン付与 → リネームの一連を実行。PDF/X-4 準拠で主要同人印刷所（ねこのしっぽ、日光企画）に対応
- **lint 出力の再整形フォーマッター** 列番号除去・ルール名括弧化・冗長部除去・英語メッセージ日本語化・ファイルパス相対化、サマリ行ノイズ除去、末尾ルール名の付与、unmatched-pair 日本語化、ファイル見出しの余白整理
- **lint コマンドの章指定解釈を TokenResolver に統一** 独自 TargetResolver を廃止し、ゼロ埋め・降順レンジ・カンマ区切り等を他コマンドと同一ロジックで処理
- **各章・目次・付録・用語集・索引・後書きの右ページ（奇数ページ）始まり**: CSS `break-before: recto` により、見開きレイアウトで各セクションが常に右ページから開始
- **奥付の偶数ページ（左ページ）配置**: PDF 結合時に前方ページ数を計算し、必要に応じて空白ページを自動挿入
- **中扉（Part Title Page）**: `catalog.yml` の部タイトル（Hash キー）から中扉ページを自動生成。`Build::PartTitleGenerator` が `.cache/vs/_part{N}.md` → `_part{N}.html` を生成し、Step 5b としてビルドパイプラインに統合。`stylesheets/part-title.css` で右ページ開始＋裏面白紙、ノンブル非表示の専用レイアウトを適用。
- **EPUB 出力**: `output.targets` に `epub` を含めると、Step E で EPUB を自動生成。`Build::EpubBuilder` が EPUB 専用の `entries.epub.js`（目次・裏表紙を除外）と `vivliostyle.config.epub.js`（cover 埋め込み制御）を生成し、`vivliostyle build --config vivliostyle.config.epub.js` で EPUB を出力。`book.yml` の `output.epub.cover.embed` で表紙の埋め込み有無を制御（楽天/Apple 向け: true、Kindle 向け: false）。`layout: reflowable / fixed` でレイアウト方式を選択可能。フォントは埋め込まず汎用ファミリ指定。EPUB のみビルド（`targets: epub`）にも対応し、PDF 専用の Step 8（バックリンク重複排除）を自動スキップ。索引・用語集ページのリンクテキストには連番の章番号（0, 1, 2, …）を挿入し、EPUB リーダーでもクリック可能な索引を実現。カバー画像（`cover.jpg`）は `frontcover_master.png` から自動生成。`dc:identifier` は `project.name` をハッシュ化した決定的 UUID（URN）に置換し、バージョンを跨いでも同一作品であれば恒久的に同じ ID を維持。

### Changed
- **索引モジュールのデッドコード整理**: Samovar 経由では到達しない `vs index:match` 系の CLI エントリと `execute_index_*` ヘルパー、旧 `index_terms.yml` マイグレーション処理、および対応するテストケースを削除し、現行の `index_glossary_terms.yml` ベース実装にコードを集約しました。
- **システムページのキャッシュ分離**: `system_pages_cache_spec.md` に従い `_titlepage.md` / `_legalpage.md` / `_colophon.md` を `contents/` から `.cache/vs/` へ移動し、生成・参照パスとテスト群を整理しました。
- **Step 8 既存 preview サーバー再利用（方策D）**: `PageMappingExtractor` が起動時にポート応答を確認し、既に `vivliostyle preview` が動いていれば起動・停止をスキップするようにしました。計測の結果、preview 起動は Step 8 のボトルネックではなく有意な高速化は見られませんでしたが、プロセス重複回避の衛生的改善として維持。
- **Step 8 Playwright レンダリング待機の最適化（提案E）**: `extract_page_mapping.mjs` のポーリング間隔を `2000ms×3回 → 500ms×5回` に変更し、最小待機時間を `6s → 2.5s` に短縮。Step 8 を **16.8s → 13.2s（-21%）**、ビルド全体を **31.3s → 28.0s（-10.5%）** に改善しました。
- **help 出力から廃止済み glossary コマンドを削除**: `vs --help` の「文章校正・用語」セクションから `glossary` を除去し、実装済みの `lint`/`metrics` のみに整理しました。
- **章扉レイアウトの調整**: `image-header.css` の章番号・タイトル余白を再調整し、`.chapter-lead` をマイナスマージンで引き上げたうえ `chapter-common.css` の `margin-block` を `0.5rlh` に変更して章扉リードが同ページに収まるようにしました。
- **print_pdf 単独ビルドモード**: `output.targets: print_pdf` の場合は閲覧用 PDF ビルド（_toc.pdf、_sections.pdf、front/tail PDF、Step 10-12）をスキップし、entries.js 再利用から Step 13 直通で入稿用 PDF を生成。ビルド時間が約 45s まで短縮され、閲覧用 PDF を作らずに入稿用のみを出力可能にしました。
- **catalog.yml コメント保持対応**: `vs create` / `vs delete` が `config/catalog.yml` の該当行のみをテキスト編集するよう再実装。`# - 02-history` のようなコメントアウト済みエントリはそのまま残し、利用者が一時的にコメントアウトした章を自動削除しないように改善しました。

### Fixed
- **システムページ（titlepage/legalpage/colophon）が A4 で出力される問題**: `vivliostyle.config.js` に `size` プロパティを追加し、`book.yml` のページプリセット（A5/B5/A4）に従った正しいサイズで出力。プリセット変更時は `page-settings.css` 更新と同時に自動同期
- **画像がページ幅を超過する問題**: `base.css` に `img { max-inline-size: 100% }` を追加し、すべてのページで画像が版面内に収まるよう制限
- **[ig] 手動マークアップ時に HTML タグが壊れる問題**: `apply_auto_indexing` / `apply_glossary_only_linking` で `<a class="glossary-link">` を含む索引タグ全体と残りの HTML を保護し、属性内マッチによる二重タグ付けを防止しました。
- **原稿 (`contents/*.md`) への誤書き込み**: `scan_and_tag_file!` で contents ディレクトリ配下を常に読み取り専用として扱い、`read_only: false` で呼び出されても原稿ファイルが上書きされないようにしました。

## 0.30.0 - 2026-02-07

### Added
- **索引・用語集ビルドパイプラインの実装**: `index_glossary.enabled` に基づいて索引/用語集候補抽出、レビューフロー、`_indexpage.html`/`_glossarypage.html` 出力、PDF への統合まで自動化。
- **用語集バックリンク重複排除（Step 8）**: Playwright + Vivliostyle preview でページ配置を取得し、`BacklinkDeduplicator` が `_glossarypage.html` と本文の † リンクを Nokogiri で浄化。
- **Playwright 連携**: `extract_page_mapping.mjs` による Chromium 自動制御と `package.json` の依存追加、`vs doctor --fix` で npm パッケージと Chromium を自動セットアップ。
- **Glossary 管理モジュール**: `glossary_terms_manager.rb`、`glossary_page_builder.rb`、`_index_glossary_review.md` 生成などレビュー～適用フローを追加。
- **ドキュメント/テンプレート**: `book-vivlio-starter/20-index-glossary.md`、`docs/specs/glossary_backlink_dedup_spec.md`、`docs/specs/index_glossary_spec.md` を追加し、特集ページ（_titlepage/_legalpage/_colophon）テンプレートを整備。

### Changed
- **ビルドパイプライン Step を 0-based に再定義**し、Step 8 にバックリンク重複排除を組み込み。ログ・進捗表示を全体的に更新。
- **Index/Glossary コマンド刷新**: 既存 `glossary:*` Thor 互換コマンドを廃止し、Samovar ベースの `IndexCommands` に統合。`IndexCandidateExtractor` が `context_width` 設定を尊重するよう改善。
- **PDF/TOC/Outline 連携**: `_glossarypage.html` や `_indexpage.html` を PDF/アウトラインへ含める際の順序とスキップ条件を整理し、`postface.css` を本文ノンブル（算用数字）に合わせた。

### Fixed
- **`context_width` が反映されず抜粋が短くなる問題**: `index_candidate_extractor.rb` で前後不足分を相互補償し、設定値（既定 40）に応じた抜粋長を確保。
- **用語フラグ同期不備**: `[i]` のみに変更された語が用語集に残留しないよう `apply_markdown_review!` で `glossary_terms.yml` を同期。
- **`vs doctor --fix` Playwright 検知**: npm パッケージと Chromium 実行ファイルを別々に検証し、ログに `✅ playwright: OK` / `✅ chromium: OK` を表示。

## 0.29.0 - 2026-01-25

### Added
- **TokenResolver を実装し章番号の共通解決を一元化**: CLI 各所でばらついていた章番号/トークン展開ロジックを `TokenResolver` に統合し、`vs build` / `vs metrics` / `vs delete` など章指定を受け付ける全コマンドで共通の正規化・範囲解釈を行うようにした。

### Changed
- **Common::CONFIG を Ruby 4.0 の Data オブジェクトへ刷新**: `directories` や `vivliostyle` などの既定値をコード側でハードコーディングし、設定アクセスはシンボルキー＋ドット記法で統一。`book.yml` 依存の文字列キー参照や複雑なマージ処理を廃止して、Config の型安全性と可読性を向上させた。
- **Common.get_file_type を廃止し TokenResolver::Entry#kind へ一本化**: ファイル名ベースの章種別推測ロジックを廃止し、`TokenResolver` が提供する `Entry#kind` を唯一のソースとして使用するようにした。`_titlepage` 等のシステムファイルも `SYSTEM_FILE_KINDS` マッピングで解決可能に。
- **Common.get_chapter_number を廃止し TokenResolver::Entry#number へ一本化**: ファイル名から章番号を正規表現で抽出するロジックを廃止し、`TokenResolver::Entry#number` を唯一のソースとして使用するようにした。ビルドプロセス全体で Entry オブジェクトを伝播させ、章番号の再抽出を排除。
- **索引／テンプレート生成時の警告を整理**: `vs build` 終了後にのみ索引辞書欠如メッセージをまとめて表示し、`_titlepage.md` など既存テンプレート検出時の冗長な警告を削除。ノイズの少ないビルドログで次のアクションが分かりやすくなった。

### Fixed
- **front/back cover の PDF 生成処理のページサイズ不整合を修正**: 本文のページサイズ（B5/A5 など）に応じた RGB/CMYK カバー PDF を動的生成するようにし、`vs cover` → `vs build` の流れで常に適切なカバーが得られるようにした。

## 0.28.0 - 2026-01-16

### Added
- **metrics キャッシュとテストの拡充**:
  - 章ごとの解析結果を `ChapterAnalysis` 単位でキャッシュし、JSON/YAML 出力やサマリ集計がキャッシュのみで完結するようにした。
  - `tokens_map`/`kanji_char_count`/`total_word_length` など語彙統計の再計算に必要なデータをキャッシュへ保存し、TTR や平均語長を正確に再合成可能にした。
  - Runner/Liv eDisplay の Minitest スイートを追加し、集計ロジックとライブ UI の振る舞いを検証。
- **metrics コマンドを刷新**:
  - `docs/specs/metrics_spec.md` に基づき、文章品質メトリクスの分析機能を実装。
  - 基本統計（文字数・行数・文数・節数）、語彙難度（漢字比率・平均語長）、語彙多様度（TTR）、読解難度スコアを算出。
  - 章・節単位の分量をバーグラフで可視化し、基準から外れた章に警告を表示。
  - `--all` オプションで全章の節まで表示、`--warn` オプションで警告章のみ表示。
  - `config/book.yml` の `metrics` セクションでプリセット（compact/standard/commercial）を選択可能に。
  - 著者向けマニュアル `book-vivlio-starter/21-metrics.md` を整備。
- **metrics コマンドの高速化**:
  - `config/catalog.yml` に基づく解析対象の自動絞り込み（PREFACE/CHAPTERS/APPENDICES/POSTFACE セクション連動）。
  - サマリ即時出力＋ローディング表示＋章別結果の逐次出力で体感速度を向上。
  - `.cache/metrics/{basename}.yml` へのキャッシュ保存（`VIVLIO_METRICS_CACHE=0` で無効化可能）。
  - スレッドプールによる並列処理（`Etc.nprocessors` と 4 の小さい方、`VIVLIO_METRICS_CONCURRENCY` で上書き可能）。
- **CLI ヘルプUXを刷新**:
  - `help_spec.md` に基づき Public/Internal コマンドを明確に分類し、`vs --help` では Public コマンドのみカテゴリ別に表示。
  - `vs pdf --help` 実行時に `pdf:compress` を案内し、`vs pdf:compress --help` で詳細な使用方法と引数解説を表示。
  - Samovar の `print_usage` による統一ヘルプとミニテスト `help_spec_test.rb` を追加して、代表的なコマンドのヘルプ出力を自動検証。
- **lint 設定の book.yml 組み込み**:
  - `config/book.yml` に `lint.config` / `lint.format` セクションを追加し、`vs lint` の既定値をプロジェクト単位で管理できるようにした。
  - `LintCommands` は book.yml の値を既定として読み込み、CLI オプション (`--config`, `--format`) で一時的に上書き可能。
- **metrics 指標仕様ドキュメント**:
  - `docs/specs/metrics_spec.md` を新設し、語彙難度・語彙多様度・読解難度・章別バランスなど `vs metrics` が出力すべき指標と UI を定義。
  - 技術書向けの分量ガイドライン（目標/警告ライン）と、今後 book.yml の `metrics` セクションで上書き可能とする方針を明文化。
- **import コマンドの cover 資産取り込みを改善**:
  - Re:VIEW 側 `frontcover_pdffile` を検出した場合、`images/hyoshi.pdf` を `covers/` にコピーしたうえで ImageMagick で 2894x4092px の `frontcover_master.png` を自動生成。
  - `config/book.yml` の `output.pdf.cover.front` を Vivlio 既定の `frontcover_rgb.pdf` にリライトし、直後に `vs cover` を回すだけで各ターゲットへ再出力できる状態に揃えた。
- **vs build で PDF カバーを自動結合**:
  - `output.pdf.cover.enabled` が有効な場合、`frontcover_rgb.pdf` / `backcover_rgb.pdf` の存在を確認し、不足していれば `vs cover` を内部実行してカバー資産を生成。
  - 生成されたカバーを `_titlepage_legalpage.pdf` の前、`_colophon.pdf` の後ろへ結合し、出力 PDF に常に front/back cover が付与されるようにした。

### Fixed
- import: `[flushright]` ブロックの連続出現時に外側だけが変換される問題を修正し、各ブロックが個別に `:::{.text-right}` へ置換されるようにした。
- `vs cover` の Samovar コマンドを公開コマンドに登録し、`vs cover [a4|b5|a5|epub|auto]` が実行できるようにした。

### Changed
- **metrics コマンドのライブ UI を改良**:
  - サマリ即時出力 → プレースホルダー表示 → 最終出力の3フェーズに整理し、章解析の進捗を ANSI 制御でリアルタイム更新。
  - キャッシュ鮮度判定を章ファイルの mtime 比較に変更し、`00-preface.md` へ依存しない差分更新を実現。
  - 著者向けマニュアル `book-vivlio-starter/21-metrics.md` を更新し、新しいキャッシュ仕様・ライブ表示・構造化出力のワークフローを追記。
- 内部コマンドから `--help` オプションを撤廃し、利用者には `docs/DEVELOPER_GUIDE.md` を参照するフローへ統一。
- Thor 互換コードを全面的に整理し、Samovar ネイティブ実装へのリファクタリングを完了（`create.rb` / `pdf.rb` / `toc.rb` / 共通コメントなどの Thor 残滓を削除）。
- `test/vivlio/starter/cli/cover_test.rb` から疑似Thorスタブを廃し、`SamovarCommands::CoverCommand` を直接インスタンス化するスモーク/生成テストへ刷新した。
- **Lint/Metrics コマンドの名称整理**:
  - Samovar 公開コマンドを `text:lint` → `lint`、`text:metrics` → `metrics` に改称し、`vs --help` や `help` カテゴリ表記も合わせて更新。
  - 互換レイヤーの require 群を `lint.rb` / `metrics.rb` へ切り替え、テスト/ドキュメント全体のコマンド表記揺れを解消。
- **章番号入力のゼロ埋め正規化を追加**:
  - `build`/`create`/`delete`/`rename`/`renumber`/`metrics` など章番号を受け付ける CLI で、`1` と入力しても自動的に `01` と解釈するよう共通トークン正規化処理を拡張。
  - 章範囲（例: `1-3`）やスラッグ付き指定（例: `1-intro`）にもゼロ埋めを適用し、コマンド入力で桁数を気にせず利用できるようにした。

## 0.27.0 - 2026-01-10

### Added
- **Import コマンドを実装**:
  - 追従変換ロジックを `Import::MarkdownConverter` / `ImageProcessor` / `YamlProcessor` に分離し、コードブロック言語推定（Rouge）やルビ・表・辞書的変換をモジュール化。
  - `frontcover_pdffile` を検出して `covers/` にコピーし、`config/book.yml` の `output.cover.front` を自動更新。
  - `vs doctor --fix` に Rouge を追加し、索引用の MeCab などと同様に不足時の自動セットアップに対応。
  - `test/vivlio/starter/cli/import/` 配下に Markdown 変換・画像処理・YAML 操作の Minitest スイートを追加して回帰検証を確立。
  - 著者向けマニュアル `book-vivlio-starter/20-import.md` を整備し、実行手順と確認項目を明文化。

### Fixed
- (なし)

### Changed
- (なし)

## 0.26.0 - 2026-01-09

### Added
- **索引機能 (indexing) を正式リリース**: Phase 1〜3 の実装が完了し、手動マークアップ／自動抽出／階層化索引・重複リンク除去までの一連のフローが安定運用可能になりました。`vs index:auto` → `_index_review.md` → `vs index:apply` → `vs build` によって本番 PDF の索引が自動更新されます。
- **ビルドシステムのリンク整合性を改善**: `_sections.pdf` を基点にしたページ検出とアウトライン付与ロジックを刷新し、目次・索引から 00-preface や各章（01-computer-journey など）へ正確にジャンプできるようになりました。`OutlineExtractor` のページ範囲推定を修正し、Preview.app などでも TOC/Index から目的のページへ確実に移動できます。
- **索引機能を実装（Phase 1〜3）**: 書籍の索引（インデックス）を自動生成する機能を追加。
  - **Phase 1 (MVP)**: 手動マークアップベース
    - `[読み|用語]` 記法で索引語を手動マークアップ（例: `[引数|ひきすう]`）
    - `[用語]` 記法（読み省略）で MeCab による読み自動推測
    - 初出は `<dfn>` タグ、2回目以降は `<span>` タグに自動切り替え
    - `vs index:build` コマンドで索引ページ（`_indexpage.html`）を生成 (内部コマンド。vs build時に自動実行される)
  - **Phase 2**: 自動抽出とスコアリング
    - `vs index:auto` コマンドで索引候補を自動抽出
    - 定義パターン検出（「〜とは」「〜について」など）
    - 専門用語パターン検出（カタカナ語、英字略語）
    - TF-IDF によるスコアリング
    - `config/index_terms.yml` に索引用語を出力
    - `_index_review.md` で索引用語を[x][r]による修正可能
  - **Phase 3**: 高度化
    - 同一ページ内の重複リンクを排除
    - 階層化索引（親子関係）のサポート
  - `vs build` パイプラインに Step 4a として統合（`book.yml` の `index.enabled: true` で有効化）
  - 五十音順ソート、行グループ化（あ行、か行、...、A-E、F-J、...）
  - `stylesheets/index.css` で索引ページのスタイル定義
  - `vs doctor --fix` で MeCab を自動インストール
- **`index.auto_discovery` 設定を追加**: `config/book.yml` で自動抽出（auto discovery）を有効/無効に切り替えられるようにし、手動マークアップのみで索引を運用したい場合にもフローを簡潔に保てるようにしました。

### Fixed
- (なし)

### Changed
- **RuboCop リファクタリングで違反を 1000→632 件へ削減**: `cover.rb` / `output_helpers.rb` / `glossary/*_commands.rb` / `markdown_preprocessor.rb` / `page_numberer.rb` / `footnote_converter.rb` を中心に軽微な Style・Layout 警告を是正し、Metrics 系以外の違反を一掃。`docs/rubocop_offense_summary.md` を最新化し、`vs build` で回帰を確認済み。
- **Samovar CLI の未知オプション処理を改善**: CLI エントリポイントを `RootCommand.call` から `parse + call` に変更し、`Samovar::InvalidInputError` を補足して該当サブコマンドの `print_usage` を自動表示する共通ハンドラを追加。`vs build --unknown-option` や `vs clean --unknown-option` などでも各コマンドのヘルプが即座に提示され、利用者が正しいオプションを確認しやすくなった。

## 0.25.0 - 2025-12-25

### Fixed
- **前書きのHTMLブロック境界の正規化**: `pre_process` で HTML ブロック閉じタグ直後の空行を正規化し、`</small>` 直後の `## 対象読者` などが Markdown 見出しとして正しく解釈されるように修正。
- **sideimage 内の外部リンク脚注サポート**: `:::{.sideimage-right}` / `:::{.sideimage-left}` コンテナ内の Markdown リンクを後処理で `<a>` タグに変換し、対応する URL 脚注をページ脚注として生成。sideimage 内の脚注参照も本文の出現順に合わせて番号付けし、脚注定義も番号順に並ぶように調整。
- **catalog.yml 更新時のコメント保持**: `CatalogUpdater` の保存処理を見直し、`vs create` / `vs delete` / `vs rename` / `vs renumber` などで `catalog.yml` を更新する際にも、冒頭の説明コメントと各セクション見出しコメント、および Tips セクションを含むフッターコメントが失われないようにした。
- **Prism.js 行番号付与のロード漏れ修正**: `post_process.rb` から `prism_lines.rb` を明示的に require し、`PrismLinesCommands.execute_prism_lines` を Samovar build パイプラインから直接呼び出しても `NameError` にならないようにした。これにより `vs build` 実行時の `uninitialized constant PrismLinesCommands` / `undefined method add_prism_line_numbers` エラーが解消され、行番号付与ステップまで正常に完走する。
- **テーブル直前段落のキャプション判定の改善**: `stylesheets/table.css` の `p:has(+ table)` セレクタを `p:has(> strong:only-child):has(+ table)` に変更し、テーブル直前の通常段落はキャプション扱いにせず、`**見出し**` 形式の段落のみを表キャプションとしてスタイリングするように修正。
- **目次（TOC）のページ番号整合性の修正**: `stylesheets/toc.css` を見直し、章・節・項のタイトル行に対して `leader(dotted)` と `target-counter(attr(data-href url), page)` を `.toc-title::after` で一貫して適用するように変更。Flex レイアウトと `leader()` の組み合わせで一部の節タイトルにページ番号が表示されない／ドットリーダーのみが頁外へ伸びる問題を解消し、目次全体でページ番号が揃って表示されるようにした。

### Changed
- **CLI を Samovar ベースへ全面移行**: 旧 Thor DSL を廃止し、`lib/vivlio/starter/cli/samovar/` 配下にコマンドごとの Samovar 実装（build/clean/create/delete/doctor/entries/help/new/pdf/pre_process/post_process/rename/resize/toc など）を追加。`vs --help` では Samovar が生成する usage 表示を採用し、共通オプション（`--verbose` 等）を RootCommand 経由で一元管理するようにした。これに伴い CLI テスト群を Samovar 仕様へ更新し、新コマンド（`entries` など）用のユニットテストも追加して回帰検証を強化。
- **依存ツールの最新動向を確認**: Vivliostyle CLI v10.x では Puppeteer への移行、ブラウザ切替オプション、Node 20+ 要件、`--executable-browser` など新フラグ体系、`vivliostyle create` のテンプレート拡充が行われた。アップデート時は `package.json` の `@vivliostyle/cli` / `@vivliostyle/core` を v10 系へ上げ、Samovar CLI 側で渡しているフラグの互換性（`--log-level verbose` など）を再確認する。また、VFM 2.5.0 では `figcaption` と画像の順序入れ替えオプション、フェンスコードブロックの属性シンタックス、`figcaption` への ID 付与、ARIA の挙動調整が追加されたため、Markdown から生成される HTML/CSS の仕様差分がないかをビルド後に目視確認する。
- **Vivliostyle/VFM 依存のバージョンアップ**: `@vivliostyle/cli` を **10.2.0**、`@vivliostyle/core` を **2.39.0**、`@vivliostyle/vfm` を **2.5.0** へ更新し、`npm install` でロックファイルも再生成。Node 20 以降が必須になったため、今後のビルド実行環境は Node 20+ を前提とする。
- **Ruby 4.0.0 での動作確認**: `rbenv install 4.0.0` → `rbenv global 4.0.0` で最新 Ruby へ切り替え、Bundler 2.7.2 で gem を再インストール。`vs build` を含む全 CLI が Ruby 4.0 系でもエラーなく動作することを確認し、`entries.js` 自動生成ロジックの改善により初回ビルド時の NameError も防止。
- **設定 YAML の事前検査を強化**: `vs` コマンド起動時に `config/book.yml` 不在/破損で即座にエラー終了するようにし、さらに `config/catalog.yml` / `config/page_presets.yml` / `config/post_replace_list.yml` についても存在確認と YAML パースのプリフライトチェックを追加。`vs glossary:*` 実行時には `config/glossary.yml` の YAML 構造を検証し、`vs text:lint` 実行時には `config/textlint_allowlist.yml` / `config/textlint_prh.yml` の存在・パースエラーを明示的に報告して処理を中止するようにした。
- **Samovar CLI 起動経路の自動検証を追加**: `test/vivlio/starter/cli/samovar_smoke_test.rb` を新設し、(1) 主要 Samovar コマンドのスモークテスト、(2) `require_relative` / 定数参照の欠落検知テスト、(3) `vs build` / `vs create` / `vs delete` などの最小統合テストを整備。`UnifiedBuildPipeline` や各コマンド実装をスタブ監視することで、Samovar 層の配線抜けが `vs build` などで NameError を起こす前に検出できるようにした。

### TODO
- **vs doctor での設定ファイル検査/復旧支援の拡充**: `config/book.yml` / `config/catalog.yml` などコア設定に加え、`config/` 配下の YAML 群の存在確認やテンプレートからの復旧（missing/破損時）の自動支援を追加する。
### Notes
- Vivliostyle の PDF レンダリングの仕様/不具合により、`linkurl_footnote: true` 使用時に `https://ja.wikipedia.org` や `https://www.apple.com/jp/` など `ja` / `jp` を含む URL 脚注が PDF 上で 2 つのリンクに分かれて見える場合がある（HTML 出力上は単一リンクであり、本プロジェクト側では既知の軽微な不具合として扱う）。

## 0.17.0 - 2025-11-26

### Added

- **クロスリファレンス機能の完成**: 図・表・コードリストに対するラベル収集・自動採番・本文中からの参照を一貫したパイプラインとして整備。`@id` を付けたコードリスト（`include:prime2.rb` などの埋め込みコードを含む）も章番号＋連番付きの「リスト N-M」として扱い、本文中の `@id` から該当箇所へジャンプできるようにした。画像は `<figure>` タグと統一的なキャプションスタイルで出力し、参照リンク（図/表/リスト番号）は太字で視認性を向上。

- **sideimage レイアウトコンテナ**: Markdown から `:::{.sideimage-right}` / `:::{.sideimage-left}` コンテナを解釈し、Vivliostyle/VFM が出力する `<div class="sideimage-right">` / `<div class="sideimage-left">` を後処理で正規化。`<figure>` 以外の子要素を `<div class="sideimage-body">` にまとめることで、CSS Grid により「図＋本文」を左右にきれいに並べてレイアウトできるようにした。
- **インラインコード内 HTML タグの安全な扱い**: `pre_process` でインラインコード（バッククォート囲み）内の `<`/`>` を `&lt;`/`&gt;` に自動エスケープし、`post_process` で sideimage 本文内のバッククォートを `<code>` 要素として解釈するように変更。著者は `` `<h1></h1>` `` のようにそのまま記述しても、最終出力では見出しとして解釈されず、コードとして正しく表示されるようになった。

### Changed

- **sideimage レイアウトの可変幅対応**: `:::{.sideimage-right}` / `:::{.sideimage-left}` コンテナ内の画像に `{width=50%}` などのパーセンテージ指定を与えると、その値をページ幅に対する画像の希望比率として解釈し、CSS カスタムプロパティ（`--sideimage-text-fr` / `--sideimage-img-fr`）を通じて本文と画像の列幅比を動的に切り替えるようにした（既定値は従来どおり 3:2 のまま）。
- **ビルドパイプラインのモジュール分割**: `build.rb` と巨大な `build_helpers.rb` をリファクタリングし、`lib/vivlio/starter/cli/build/` 配下に `ChapterConfig` / `SectionBuilder` / `ImageOptimizer` / `TocGenerator` / `Utilities` / `PdfBuilder` / `PdfMerger` / `PdfFinalizer` / `PageNumberer` / `OutlineExtractor` など機能別モジュールとして分割。`build.rb` は Thor CLI とビルドオーケストレーションのみを担う薄いエントリーポイントに整理し、`UnifiedBuildPipeline` および関連テスト（`build_pipeline_test.rb`, `build_helpers_test.rb` など）を新構造に追従させた。さらに、従来は別実装だったフルビルド/単章ビルドの 2 系統パイプラインを `UnifiedBuildPipeline` に統合し、モード切り替えのみで共通フローを実行する構成に整理した（CLI オプションやビルド結果など外部仕様は従来どおり互換）。

### Fixed
- Markdown の画像記法で `{align="center"}` や `{width="30%"}` のように引用符付きで指定した属性も正しくパースし、`<figure class="align-center">` および `style="width: .."` として出力されるように修正。
- 章ページの右上柱で章番号と章タイトルを表示できるように、`chapter-common.css` で `h1 .chapter-number` / `.chapter-title` から named string (`chapter-number` / `chapter-title`) を `string-set` し、`page-settings.css` の `@top-right` で `string(...)` を参照するよう整備。
- 扉絵背景の横位置を `margin_inner`/`margin_outer` の差分から自動算出した `--frontispiece-binding-offset` を使って補正し、`image-header.css` / `simple-header.css` いずれでもノド側に画像が飲み込まれないようにした。
- 扉絵ポートレート variant の生成時に、ページ設定の `margin_inner` と `margin_outer` からバインディングセーフなアスペクト比を算出して利用するようにし、ノド側の欠けを防止。
- **リンク脚注と PDF 脚注番号の整合性**: Markdown 内の外部リンクを自動的に URL 脚注へ変換する処理を見直し、章末脚注からページ脚注への展開時にも本文中の参照順と脚注番号が一致するように修正。Vivliostyle の print 脚注と CSS カウンターのずれにより `color 5` などの参照番号と脚注行が食い違っていた問題を解消。
 - **`.aki` 段落クラスの適用不具合**: `config/post_replace_list.yml` の `{.aki}` / `{.aki2}` 用正規表現を修正し、Vivliostyle/VFM が出力する `<p>...</p>` を段落単位で安全にマッチするように変更。これにより、`contents/46-first-css.md` などで `{.aki}` / `{.aki2}` が別段落まで巻き込まれて消えてしまい、本来 `class="aki"` による 1 行（または 2 行）分の下マージンが付かない問題を解消。

## 0.16.0 - 2025-11-15

### Added
- **章番号ベースのビルド指定**: `book.yml` の `chapters` 設定で番号ベースの指定をサポート。配列 `<dfn id="idx-15a03j2u2uez-1" class="index-term" data-yomi="02,11,12,91">02, 11, 12, 91</dfn>`、カンマ区切り "02, 11, 12, 91"、範囲指定 "02-12, 91" の形式で章を指定可能に。従来のファイル名指定と併用はできず、混在時はエラーで中止。
- **章番号重複検出**: 同一章番号で複数ファイルが存在する場合、ビルド開始時にエラーメッセージを表示して中止し、利用者にファイル名の修正を促す。
- **横長表のページ内回転機能（table-rotate）**: `docs/table_rotate_spec.md` に基づき、`:::{.table-rotate ...}` コンテナブロックと内部テーブルを事前変換する `pre_process` パイプラインを実装。`scale`/`shift-y` オプションから CSS カスタムプロパティ（`--table-rotate-scale`, `--table-rotate-shift-y`）を生成し、Vivliostyle 上で横長表を 90 度回転させて専用ページにレイアウトできるようにした。

### Changed
- **コードリファクタリング**: `build_helpers.rb` の `configured_chapters` メソッドを複数の小さなメソッドに分割し、可読性と保守性を向上。全章取得ロジックを `all_chapter_files` メソッドに共通化し、文字列/配列処理を個別のメソッド（`process_string_config`, `process_array_config`, `process_filename_list` など）に分離。各メソッドに詳細なコメントを追加。
- **コメント追加**: 目次生成（`toc.rb`）とPDFアウトライン生成（`build_helpers.rb`）の重要なロジックに詳細なコメントを追加し、処理の意図を明確化。
- **前付けノンブル描画を改良**: HexaPDF オーバーレイで margin 情報を用いてローマ数字を正確に配置し、既存のページ番号を白帯でマスクしてから描画するように変更。
- **PDFアウトラインを拡張**: `book.yml` の `book.main_title`（未設定時は `book.title`）を参照し、表紙（1ページ目）へ戻れるアウトライン項目を自動で先頭に追加。

### Fixed
- **CSS自動再展開機能**: `preface.css`, `postface.css`, `appendix.css` が空または破損している場合、テンプレートから自動的に再展開するロジックを `pre_process.rb` の `generate_frontmatter` メソッドに追加。`theme.css` と同様の仕組みで、ファイルが存在しない・空・必須トークンが欠けている場合にテンプレート（project_scaffold）から復元されるようになった。
- 目次生成で、ビルド対象に含まれていない前書き（02-preface）や後書き（98-postface）が表示されないように修正。また、前書き・後書きが重複して表示される問題を修正。`toc.rb` の `append_headings` メソッドで前書き・後書きを除外し、`SupplementEntryProvider` で専用処理するように変更。
- PDFアウトラインで目次（03-toc）のジャンプ先を修正。前書きがビルドされていない場合、目次は3ページ目から始まるように `build_helpers.rb` の `heading_page_entries` メソッドを調整。また、目次の見出しについてはテキスト検索をスキップし、計算済みの開始ページを直接使用することで、確実に目次の先頭ページにジャンプするように改善。さらに、`chapter_numbers_for_outline` で目次（章番号3）を常に含めるよう修正し、`chapters` 設定に関わらず目次のアウトラインが生成されるようにした。
- `chapters` 設定で `all` と番号指定（例: `02-21, 98`）の処理を統一。`chapters: all` の場合も全章のファイル名リストとして扱うことで、各ビルドステップで同一の処理フローを使用するように改善。前書きが重複して出力される問題を解決。
- Step 7（全体PDF生成）で前書き（02）を除外。前書きは Step 8 で `02-03-front.pdf` として別途処理されるため、`11-98-sections.pdf` に含めないよう修正。
- `chapters` 設定で章範囲を指定した際に、前書き（02）や後書き（98）が目次生成・HTML生成・PDF生成の対象から漏れていた問題を修正。Step 5（HTML生成）、Step 6（目次生成）で全範囲（前書き、本文、付録、後書き）を正しく処理するように改善。
- Step 8 の目次判定ロジックを修正。目次（`03-toc`）は Step 6 で常に自動生成されるため、`keep` 設定ではなくファイルの実在で判定するように変更。
- `vs open` コマンドが `output.pdf_preview` セクションの `close_existing_windows` と `window_bounds` を参照するよう更新し、`book.yml` の設定に従って Preview ウィンドウを制御。
- `vs build` コマンドが `vivliostyle.quiet` を参照して Vivliostyle CLI の出力抑制を切り替えるよう対応。

### Breaking Changes
- `book.yml` の PDF プレビュー関連設定を `output.build` から `output.pdf_preview` に移行し、Vivliostyle のコンソール抑制設定を `vivliostyle.quiet` へ統合。旧構成はサポートされません。
- **章構成設定の移行**: 章構成は `book.yml` の `chapters` セクションではなく、新しい `config/catalog.yml` から読み込むように変更。旧来の `chapters` 設定は無視されます。

### Changed
- `vs build` の完了時に、`output.pdf` および `output_compressed.pdf` を `book.yml` の設定に基づく動的ファイル名へリネームし、生成物がプロジェクト名・バージョンを反映した名称で出力されるように調整（例: `vivlio_starter_v1.0.0.pdf` / `vivlio_starter_v1.0.0_compressed.pdf`）。
- `lib/project_scaffold/stylesheets/titlepage.css` と `stylesheets/titlepage.css` を更新し、タイトル・副題・著者名が紙サイズに応じて重ならず整列するよう CSS Grid ベースのレイアウトに再設計。

## 0.15.0 - 2025-11-07

### Added
- 付録専用カラー設定（`theme.appendix_color`）を追加。指定がない場合は本文と同じ `theme.color` を使用し、付録のみ異なる色を設定可能に。
- 付録のh3/h4マーカー（♣/♦）が `theme.appendix_color` を使用するように対応。
- 前書き専用カラー設定（`theme.preface_color`）を追加。指定がない場合は本文と同じ `theme.color` を使用し、前書きのみ異なる色を設定可能に。
- PDF圧縮設定（`pdf.compress`）を `config/book.yml` に追加。デフォルトは `false`（圧縮なし）で、`true` に設定するとビルド時に自動的に圧縮を実行。
- `vs build` コマンドに `--compress` オプションを追加。`--compress` で圧縮を強制実行、`--no-compress` で圧縮をスキップ。オプション未指定時は `book.yml` の `pdf.compress` 設定に従う。
- **見開きページ対応の余白設計**: `margin_inner`（ノド）と `margin_outer`（小口）を導入し、左右ページで自動的に余白が入れ替わる見開きレイアウトをサポート。
- **タイポグラフィセクション**: `book.yml` に `typography` セクションを新設し、書体・色・装飾を一元管理。`typography.body`, `typography.heading`, `typography.column`, `typography.code`, `typography.folio` で各要素の設定を階層的に管理可能に。
- **出力設定セクション**: `book.yml` に `output` セクションを新設し、出力フォーマット（PDF/印刷用PDF/EPUB）、ファイル名規則、ビルド設定を統一管理。`targets`, `filename`, `build`, `pdf`, `print_pdf`, `epub` の各サブセクションで設定を整理。
- **プロジェクト情報セクション**: `book.yml` に `project` セクションを追加し、プロジェクト名とバージョン情報を管理。出力ファイル名のベースとなる `name` とバージョン管理用の `version` を設定可能に。
- **統一的な見出し構造**: `book.yml` のすべてのセクションとサブセクションに統一的な見出しを追加。一階層目は `# ========================================`、二階層目は `# ----------------------------` で囲む形式で視認性を大幅に向上。
- **カバー画像生成コマンド**: `vs cover` コマンドを追加。マスター画像（`frontcover_master.png`, `backcover_master.png`）から、PDF用（A4、RGB）、印刷用（B5/A5、CMYK、PDF/X-1a）、EPUB用（1600×2560、JPEG）のカバー画像を自動生成。サブコマンド `vs cover:a4`, `vs cover:b5`, `vs cover:a5`, `vs cover:epub` で個別生成も可能。ImageMagickとGhostscriptを使用してPDF/X-1a準拠の印刷用カバーを生成。
- `vs clean --cover` オプションを追加。生成されたカバー画像（RGB/CMYK版PDF、EPUB用JPEG）のみを削除し、マスター画像は保持。
- `vs cover` と `vs clean --cover` の自動テストを追加。カバー生成・削除のユニットテストで動作を検証。

### Changed
- **版面設計を余白ベースに変更**: 文字数・行数を指定する方式から、余白を指定して文字数・行数を自動計算する方式に変更。`page_presets.yml` で `margin_top/bottom/inner/outer` を指定すると版面サイズが自動的に決定される。

### Breaking Changes
- **旧形式の設定を廃止**: `book.yml` の `page` セクション直下でのフォント設定（`page.main_text_font` など）を廃止。`typography` セクション（`typography.body.font` など）での指定に移行が必要。
- **page_presets.yml の構造を変更**: `letters_per_line`, `lines_per_page`, `margin_xshift` を削除し、`margin_top/bottom/inner/outer`, `letter_spacing` に変更。既存のカスタムプリセットは新形式への書き換えが必要。
- **設定の役割を明確化**: `page_presets.yml` は物理的な版面レイアウト（紙サイズ、余白、文字サイズ、行送り）を、`book.yml` の `typography` セクションは視覚デザイン（書体、色）を管理するよう整理。
- `page_presets.yml` のすべてのプリセットを新形式に更新。`letters_per_line`, `lines_per_page`, `margin_xshift` を削除し、`margin_top/bottom/inner/outer`, `letter_spacing` を追加。
- `page-settings.css` の `@page :left/:right` を更新し、見開きページで `margin_inner`（ノド）と `margin_outer`（小口）が自動的に入れ替わるように対応。
- **新仕様に全面移行**: `book.yml` を `typography` セクションを使った新構造に更新し、`page-settings.css` のデフォルト値も新しい余白ベースの設計に統一。旧形式のサポートを廃止し、コードを簡潔化。
- プレースホルダー画像（no_frontispiece.svg / no_ornament.svg / no_image.svg）を pre_process.rb 内にハードコーディングし、ファイルシステムへの依存を削除。利用者が誤って削除しても動作するように改善。
- 付録（appendix.css）のデザインを本文の simple-header.css と統一。h1/h2 のスタイルを共通化し、色変数のマッピングのみで差異化。
- 章と付録の共通スタイルを `chapter-common.css` に集約し、`chapter.css` と `appendix.css` の重複コードを大幅に削減（約90%削減）。メンテナンス性が向上。
- `chapter.css` から未使用の CSS 変数（`--h2-offset-*`, `--section-number-padding-*`, `--section-bg-inset-*`, `--section-lead-margin-*` など計10個）を削除し、コードをシンプル化。
- `chapter-common.css` の不要なコメントを削除し、セクション構造を明確化。可読性とメンテナンス性を向上。

### Fixed
- テーマカラーの定義不足を修正。amber / orange / peach / coral / magenta / plum / indigo / navy / cyan / teal / mint / lime の色定義を追加し、book.yml で指定した色が正しく反映されるように修正。
- theme.css のコメントを現在の仕様に合わせて修正。利用者が直接編集すべきでない旨を明記し、古いコメントや不適切な説明を削除。

## 0.14.0 - 2025-11-04

### Added
- Textlint を日本語対応ワークフローとして再構築し、カスタムフォーマッターの導入・VFM 記法向け allowlist/filter 対応・scaffold/`vs doctor --fix` による設定一式の自動配備を実装。

### Changed

## 0.13.0 - 2025-11-03

### Added
- テーマカラー候補に coral / navy / mint / plum / peach を追加し、yellow 系の色味を調整。
- `theme.frontispiece` をネスト構造で受け取り、padding / heading_width / lead_width を CSS カスタムプロパティとして展開。
- macOS 環境の `vs doctor --fix` で waifu2x を自動ダウンロード・展開し、`$HOME/.local/bin/waifu2x/` 以下へ配置できるよう対応。
- frontispiece / ornament の解決時に `_portrait` / `_landscape` バリアントを自動生成し、次回以降は既存ファイルを優先利用するよう改良。
- 扉絵・節装飾に利用できるバンドル画像セットを 36 種類（ajisai など）に拡充し、即座に `_portrait` / `_landscape` バリアントへ展開可能に。

### Changed
- simple テーマ向け header スタイルを刷新し、章タイトル・節見出しをバナー調に再設計。
- image テーマの章扉レイアウトと節見出し装飾を再設計し、frontispiece 余白・見出し幅・装飾画像のアスペクト比・折り返し制御を改善。

## 0.12.0 - 2025-10-28

### Added
- minitest を導入し、バージョン定数およびフルビルドパイプラインの基本動作を検証する最初のテストスイートを整備。
- CLI コマンド（build/open/create/delete/rename/renumber/new/doctor/glossary/text_metrics/help/version）の挙動を確認する追加テストを整備し、主要サブコマンドのユースケースをカバー。
- 画像が見当たらない場合、代替画像でビルドする機能を`pre_process.rb`に追加。
- `vs doctor` が macOS 環境で Google Fonts 用 SSL 証明書の診断を行い、`--fix` 指定時に Homebrew で openssl@3 / ca-certificates を整備し `SSL_CERT_FILE` / `SSL_CERT_DIR` を自動設定する機能。
- book.yml に指定したフォントを Google Fonts からローカルへ自動取得し、可読性の高いファイル名で保存したうえで `google-fonts.css` に集約する FontManager を整備。

### Changed
- `pdf_compress` の Ghostscript オプションに線形化（Fast Web View）と重複画像検出を追加し、閲覧時の初期表示とページ遷移を高速化。
- `vs clean --cache` 実行時に `.vivliostyle` ディレクトリも削除するようクリーン処理を拡張。


## 0.11.0 - 2025-10-27


### Added
- README 冒頭に Vivlio Starter ロゴとブランド要約を追記。
- text_metrics コマンドに平均文長・文数・読点数・句数・平均句長を追加し、JSON/YAML/表すべてで出力できるよう拡張。

### Changed
- CLI コマンド群をリファクタリングし、`module_function` 化とコマンド説明文の定数化を実施（thor DSL の記述揺れを解消）。
- `build.rb` の単章ビルド処理をパイプライン化し、実行フローと付随処理（マージ・オープン）を専用クラスへ分割。
- `pre_process.rb` / `post_process.rb` の大型メソッドを段階的ヘルパーへ分解し、前後処理の責務を明確化。

## 0.10.0 - 2025-10-26

### Added
- 目次の構成を見直し、ブックマークが所定の階層で揃うよう調整（「始めに」配下の見出し整理、および奥付・付録の固定ラベル化）。HTML 出力に章番号用の `<span class="chapter-number">…</span>` を導入し、抽出アルゴリズムを改良したことで、フルビルド時にも目次が欠落なく生成されるよう改善。
- 文章量や見出し統計を取得できる `text_metrics` コマンドを追加し、原稿の分量チェックを容易に。

### Removed
- 従来の章別 CSS（例: `stylesheets/11.css` など）を廃止し、共通スタイルに一本化。

### Changed
- 開発環境の Vivliostyle CLI/Core を 9.7.2 / 2.35.0 へ更新。
- ビルドシステムを整理し、キャッシュ活用などで処理を簡素化・高速化。

## 0.9.1 - 2025-09-09

### Added
- `pdf <dfn id="idx-e6zlxwr15vti-1" class="index-term" data-yomi="OUTPUT">OUTPUT</dfn>`: 出力ファイル名を引数で指定可能に（指定時は生成後にリネームを自動実行）。
- ビルド対象/存在チェックの汎用ヘルパ `BuildHelpers.buildable?(basename, keep)` を追加。

### Changed
- `vs build --no-clean` が Step 0（事前クリーン）でも有効になるよう変更（従来は Step 13 のみ）。
- `build_helpers.preface_prebuild!` は `Vivlio::Starter::ThorCLI.start(<dfn id="idx-mb76ie3zq8pa-1" class="index-term" data-yomi="'pdf','02-preface.pdf'">'pdf', '02-preface.pdf'</dfn>)` を使用し、リネーム処理を `pdf` コマンド側へ集約。
- 付録の対象抽出で `buildable?` を使用して `keep` と存在を同時に判定。
- `chapter_numbers_for_book(keep)` が例外時に `nil` を返す仕様に変更。これに伴い呼び出し側の `begin/rescue` を削除し、代入1行へ簡素化。
- ルーター（`lib/vivlio/starter.rb`）から Rake 時代の残滓（`new` の特別扱い、コメント）を整理し、Thor 委譲に一本化。

### Fixed
- `vs build` 実行時に Thor の `options` を直接書き換えてしまい `FrozenError` で無音終了する問題を修正。
  - 対応: `options<dfn id="idx-l40h90cqidow-1" class="index-term" data-yomi=":force">:force</dfn> ||= options<dfn id="idx-jntn57qlr420-1" class="index-term" data-yomi=":'no-cache'">:'no-cache'</dfn>` を廃止し、ローカル変数 `force` に展開して使用。

### Removed
- `--single_html` オプションを削除しました。Step 7 の通常経路は以下に整理されています。
  - 指定あり（または `VIVLIO_EXPERIMENTAL_PARALLEL_PDF=1`）: `build_chapter_pdfs_in_parallel_and_merge!`
  - 指定なし（既定）: `build_overall_pdf_and_split_from_dir!('.', keep)`

### Refactored
- レンジ定数を導入: `MAIN_RANGE=(11..89)`, `APPX_RANGE=(91..97)`（重複するリテラルを排除）。
- HTML収集の共通化: `BuildHelpers.htmls_for_range(base_dir, range, keep_numbers)` を追加し、Step 6/7 で使用。
- 並列処理ユーティリティ: `BuildHelpers.parallel_each(items, concurrency:)` を追加し、Step 5 の並列ビルド実装を簡素化。
- `pdf <span id="idx-e6zlxwr15vti-2" class="index-term" data-yomi="OUTPUT">OUTPUT</span>` に寄せるリファクタリング: TOC/フロント/奥付/後書きの PDF 生成で手動リネームを廃止。
- 付録ガードHTML: `ensure_appendices_guard_html` ヘルパを追加し、Step 7 から呼び出すよう変更。`clean` に `90-appendices-guard.html` を明示追加。
- 互換コードの整理: `run_pdf_without_single_doc!` を削除（`--single-doc` 廃止済み）。
- アウトライン抽出を簡素化: 旧 `VS-H:` 接頭辞の除去処理を削除し、`data-heading`/見出しテキストのみに統一。

### Notes
- 将来的に、特定 basename を扱う他ステップ（例: `98-postface` や `99-colophon` 相当）にも `buildable?` の導入を検討し、対象判定と存在チェックの一元化を進めます。



## 0.9.0 - 2025-09-09

### Added
- PDF アウトライン（ブックマーク）実装
  - 11-89(章)HTML 見出しから PDF アウトラインを付与できるようにしました。
  - 実装: `post_process` による見出しメタ（`class="vs-h-marker"` と `data-heading`/`data-hN`）の付与を徹底。
 - キャッシュ設定を追加（段階1）: `cache.enabled`（既定: true）, `cache.dir`（既定: `.cache/vs`）。
 - `clean:cache` コマンドを追加（段階3）: キャッシュディレクトリのみを安全に削除。
 - 真偽値の柔軟解釈ヘルパ `Common.truthy?`/`falsey?` と `Common.fetch_bool` を追加（`yes`/`no`, `on`/`off`, `1`/`0`）。
   - 現時点の適用箇所: `pdf.quiet`, `pdf.single_doc`, `pdf.close_existing_windows`, `cache.enabled`。

### Removed
- Plan A（章別PDFの分割/キャッシュ）を廃止し、関連コードを削除。
  - 削除: `split_and_cache_chapters_from_body_pdf!` / `detect_chapter_starts_by_markers`
  - Step 7 内の Plan A 呼び出しも削除
- Step 7 (Alternative) の実験実装（chapters.html に結合してから PDF 生成）を削除。

### Changed
- Step 9（`build_helpers.build_front_pages_and_tail!`）の再生成条件を整理。
  - フロント（00/01）PDF のキャッシュ判定に `config/book.yml` の mtime を含め、book 情報更新で確実に再生成。
  - 再生成が必要な場合のみ `create:titlepage`/`create:legalpage`/`create:colophon` を呼び出し、常に `--force` で上書き（スキップ警告を抑止）。
- 00/01 の結合方式は最終的に「entries に 2 本の HTML を渡す」方式に確定（`entries 00-titlepage.html 01-legalpage.html` → `pdf` → `00-01-front.pdf`）。
- Step 9 のキャッシュロジックを簡素化。
  - フロントPDFが最新の場合は、その時点で Step 9 を終了（奥付も最新とみなす）。
  - フロントを再生成した場合は、奥付も必ず再生成。
- front/colophon PDF を `.cache/vs/` にキャッシュ保存し、再生成不要時は必要に応じてキャッシュから復元（段階1）。`--force` 指定時はキャッシュ不使用。

### Fixed
- `create:colophon` を `--force` なしで呼び出してしまい「既に存在するためスキップ」の警告が出る問題を解消。
- Step 9 で奥付 PDF 生成時のリネーム処理を整理（`output.pdf` → `99-colophon.pdf` の単一移動に統一）。

### Notes
本リリースでは、章別PDFの分割/キャッシュ（旧 Plan A）を正式に廃止しました。将来的な最適化は「論理フィルタ（book.yml chapters）を前提とした通常フロー」の改善に集約し、必要であれば Experimental な「章別並列生成→結合（`build_chapter_pdfs_in_parallel_and_merge!`）」の強化で対応します。キャッシュ方針は次のとおりです: Plan A（分割ベースの章別キャッシュ）は撤回済み。一方で、Plan B（章別並列生成→結合ベース）の章単位キャッシュ計画は継続検討中です。front/colophon 等の再生成短縮キャッシュは引き続き有効です。

## 0.8.2 - 2025-09-07

### Added
- `build`: `--force` を追加（Step 9 で 00/01/99 を強制再生成）。
  - `vs build --force` 実行時、`create:titlepage --force` / `create:legalpage --force` / `create:colophon --force` を自動呼び出し。
- `config/book.yml` のテーマ系オプションを拡充（実装）。
  - `style: image|simple`, `color: '#ff0000'`（HEX 記法は引用符推奨）、
    `frontispiece: door2`（扉絵）、`ornament: frame-blue`（節見出し装飾）、`markers:`（見出し用マーカー）

### Changed
- ログ出力制御を `--log<dfn id="idx-k86z2cx8mop5-1" class="index-term" data-yomi="=level">=level</dfn>` に統一しました（`lib/vivlio/starter/cli/common.rb`）。
  - `--log=error`(0) / `--log=warn`(1) / `--log=info|success|action`(2, 既定) / `--log=debug`(3)
  - `--log`（レベル省略）は `--log=info` と同義です。
  - 既定（未指定）は `warn` レベルです。
  - 互換性: 旧オプション `-q` / `-v` / `-vv` や `--verbose`、環境変数 `VERBOSE`/`DEBUG`/`LOG_LEVEL` は廃止しました。
- `vs clean` の削除対象/挙動を見直し。
  - pre_process 展開などで生成される章系 Markdown（`00-*.md`〜`99-*.md` のみ）を削除対象に追加。
  - それ以外の Markdown（README.md などユーザー資産）は、`--purge` 指定でも削除しない安全仕様に固定。
  - これに伴いヘルプ文言（`--purge` の説明）を更新。

### Notes

## 0.8.1 - 2025-09-05

### Changed

- 節見出し（`stylesheets/image-header.css` の `h2` / `h2::before`）の体裁調整を完了。

## 0.8.0 - 2025-09-04

### Added
- `stylesheets/simple-header.css`: Simple 版の各色バリアントを用意（テーマ連動）。章扉なしデザインでの配色切替に対応。
- `open:pdf <dfn id="idx-ehx75nxh714m-1" class="index-term" data-yomi="PATH">PATH</dfn>` 対応（`lib/vivlio/starter/cli/pdf.rb`）: 任意のPDFパスを指定しても Preview のウィンドウ位置設定（`pdf.window_bounds`）を適用可能に。
- page_preset.yml 導入
  - 使い方: `config/book.yml` の `page.use`（または `page.preset`/`page.preset_name`）に `b5_standard`/`a5_paperback`/`a4_standard` 等を指定。
  - 仕組み: `config/page_presets.yml` を読み込み、プリセット値に `book.yml` の `page` 値を上書きマージ（ユーザー設定優先）。実装: `lib/vivlio/starter/cli/common.rb` の `load_config`。
  - 単位正規化: `base_font_size` の Q→pt、`base_line_height` の 倍率/Em/Q→pt を正規化（`normalize_page_units!`）。
  - ページ寸法: `size`（A4/B5/A5）に応じて既定寸法を解決。`width`/`height` 明示時はそれを優先（`resolve_page_size`/`normalize_page_size!`）。未指定時は B5 既定。
- A4 / B5 / A5 にスケーリング対応
  - `pre_process` でページ寸法から `paper_scale` を算出し CSS 変数 `--paper-scale` として注入。実装: `lib/vivlio/starter/cli/pre_process.rb`。
  - 算出方法: A4 対比での縮尺を幅/高さの最小値で決定し、0.5〜1.0 の安全域へ丸め込んで付与（`page.paper_scale`）。
  - 影響範囲: 見出し/章扉/前付け等の CSS で `var(--paper-scale)` を参照し、余白・配置のスケール追従が有効に。

- 見出しマーカーのテーマ連動（`theme.markers.h3` / `theme.markers.h4`）
  - `config/book.yml` の `theme.markers` から h3/h4 のマーカー文字を指定可能に。
  - `pre_process` が `stylesheets/chapter.css` の `:root` に `--h3-marker` / `--h4-marker` を注入・更新。
  - CSS 側は `h3::before { content: var(--h3-marker, "◆"); }`、`h4::before { content: var(--h4-marker, "●"); }` を参照。

### Changed
- 見出しレイアウトの軽微な体裁調整（位置/余白などの微修正）。
- `lib/vivlio/starter/cli/build.rb`: 単章/選択ビルド時の最終オープンを `open_pdf(<chapter>.pdf)` に統一し、Preview のウィンドウ位置設定をフルビルドと同一化。

- `vs clean --purge`: 単章PDF（例: `11-install.pdf`, `81-install.pdf`）も削除対象に含めるように変更。

### Notes
- image-header.css の位置調整は一旦保留。後日見直しのため TODO/FIXME コメントを該当箇所に追記（上下位置の微調整、`--section-hero-height`/マージンの検討など）。

## 0.7.1 - 2025-09-03

### Changed
- `vs build` 内部実装をリファクタリングし、`config/book.yml` の `chapters` サブセット（keep）が Step 6/7/11 に貫通する実装を安定化（退避・復元なしの論理フィルタを前提に整理）。

### Fixed
- `vs build` のトークン展開で、`.md` を含む入力（例: `11-install.md`）や `contents/` 接頭の入力を正しく解決するよう修正。
- `build.rb` のクォート不備（シェル式の `\'\''`）により構文エラーとなる箇所を修正。
- `base.class_eval` ブロックを早期に閉じていた余分な `end` を削除し、構文エラーを解消。

## 0.7.0 - 2025-09-03

### Added
- `vs build` の章指定方法を拡充（`11-install`, `11-install.md 12-tutorial`, `11-21`, `11 21-31` に対応）。
- `vs build` に `--dry-run, -n` を追加（実行せずにビルド予定のみを表示）。
- `vs build` に `--merge, -m` を追加（単章で生成された各PDFを結合して `output.pdf` / `output_compressed.pdf` を出力）。
- `vs clean` に `--purge, -P` を追加（生成物（PDF含む）をすべて削除）。
- `vs renumber` に `--chapter-step, -S` を追加（連番付け直し時の章番号の刻み幅を指定。`rename` と同等の挙動。互換: `--step` も使用可）。
- `config/book.yml` の `chapters` で指定した対象のみを論理的にフィルタしてビルドするようにしました。

### Changed
- フルビルド時の PDF 結合（`build_helpers.rb` の `merge_all_pdfs!`）で、奥付（`99-colophon.pdf`）が必ず偶数ページ（左ページ）で開始されるよう自動調整（必要に応じて直前に空白1ページを挿入）。

### Fixed
- CI セクションの圧縮エンジン表記の不整合を修正し、Ghostscript 固定に統一（例も `-dCompatibilityLevel=1.7` に合わせて更新）。固定理由: qpdf は再圧縮で効果が乏しいケースが多く、Ghostscript(pdfwrite) の方が安定して圧縮率を得やすいため。
- 見出しの節番号がにじんで見える問題を改善（`stylesheets/chapter.css` の `h2` 装飾の縁取り/ストロークを調整）。
- `vs build <chapter>`（単章ビルド）時に既存の `output.pdf`/`output_compressed.pdf` を誤って開いて終了してしまう問題を修正。各章を個別に PDF 化して `11-install.pdf` のようにリネームし、最後にその単章PDFを開くように変更。

### Notes
- `configured_chapters` は `contents/` 接頭辞と拡張子の有無を正規化し、`<dfn id="idx-ei5plpxkvbfc-1" class="index-term" data-yomi="'11-foo.md',...">'11-foo.md', ...</dfn>` の形式で扱います。
- CSS の仮想連番（Step 2）は引き続き `.orig` バックアップを用いた復元（Step 11）を行いますが、章の選定は `keep` に基づきます。

## 0.6.0 - 2025-08-31

### Added
- `vs doctor` が不足ツールの自動導入に対応（macOS）
  - Homebrew 未導入時の自動インストール（確認あり、`-y/--yes` で省略）
  - Node.js（`brew install node@20` 優先）/ Vivliostyle CLI（`npm install -g @vivliostyle/cli`）
  - qpdf / poppler(pdfinfo) / Ghostscript / ImageMagick の自動導入
- `vs doctor` に Xcode Command Line Tools の診断と `--fix` 時のインストーラ起動・待機を追加（macOS）
- `vs doctor` にオプションを追加
  - `--fix`: 不足ツールを自動インストール
  - `-y, --yes`: 確認プロンプトを省略
- `bin/install-ruby.zsh`
  - 既定の Ruby バージョン指定を「最新安定版（latest）」に変更し、自動解決を実装
  - Xcode Command Line Tools の検出とインストーラ起動（案内）を追加
- `vs new` 実行時に GitHub Actions ワークフローを自動配置
  - 同梱テンプレート: `lib/project_scaffold/.github/workflows/build.yml`
  - 生成先: `mybook/.github/workflows/build.yml`

### Changed
- ドキュメント（`contents/11-install.md`）を更新
  - CI セクション: `vs build` の圧縮挙動・既定名（`output_compressed.pdf`）・エンジン選択（`qpdf/gs`、ENV/設定）を明記
  - YAML スニペットの成果物パスを `output_compressed.pdf` に統一
  - 順序調整: 「vs build の圧縮オプション」を先、Ghostscript 例を後に
  - 付録: Windsurf エディタの紹介・インストール手順・ショートカット（macOS 優先）を追加
- ヘルプ（`lib/vivlio/starter/cli/help.rb`）を更新
  - `vs doctor` の説明に Xcode Command Line Tools の診断/誘導を追記

### Notes
- 既定で PDF 圧縮を実行（`--no-compress` でスキップ可能）。圧縮後の既定ファイル名は `output_compressed.pdf`。


## 0.5.0 - 2025-08-30

### Added
- Thor への移行を完了し、CLI として独立実行可能に
  - 例: `vs build --verbose --no-compress`
- `create:legalpage` を追加（リーガルページ生成を [create.rb](cci:7://file:///Users/mirai/projects/vivlio-starter/lib/vivlio/starter/cli/create.rb:0:0-0:0) に統合）

### Changed
- ヘルプとログを日本語化し、ユーザビリティを向上
- コマンド/オプション定義を整理（`desc` / `long_desc` / `method_option` の整備）
- 共通ヘルパー（`Common` ほか）を統合し保守性を改善
- `require_relative` 群をアルファベット順に整理し重複を解消（[lib/vivlio/starter/cli.rb](cci:7://file:///Users/mirai/projects/vivlio-starter/lib/vivlio/starter/cli.rb:0:0-0:0)）

### Removed
- [legalpage.rb](cci:7://file:///Users/mirai/projects/vivlio-starter/lib/vivlio/starter/cli/legalpage.rb:0:0-0:0) を削除（機能は `create:legalpage` に移管）

### Notes
- 実質コード行数は Rake 相当から約 1.5 倍に増加（機能拡張・ログ/ヘルプ充実のため）
- 既存の Rake タスクは引き続き利用可能だが、推奨は Thor CLI（`vs ...`）
- 生成系コマンドは [safe_write](cci:1://file:///Users/mirai/projects/vivlio-starter/lib/vivlio/starter/cli/create.rb:246:14-251:17) 採用でディレクトリ自動作成・エンコーディング統一を保証
- 共通オプション `-v/--verbose` を全コマンドでサポート（ENV `VERBOSE=1` をセット）
- コマンド公開名を [ThorCLI.commands_supported](cci:1://file:///Users/mirai/projects/vivlio-starter/lib/vivlio/starter/cli.rb:47:6-67:9) に集約し、ルーティングとヘルプ整合性を確保
- `BuildHelpers` を増強し、ステップごとのログ粒度と失敗時の継続性を改善
- 互換性: 既存プロジェクトはそのまま動作する想定。Rake 拡張に依存する場合は `vs` 相当のコマンドへ移行を推奨

## 0.4.0 - 2025-08-26

### Added

- **rename 機能の実装**  
  - 章ファイルのリネーム支援コマンドを追加。

- **project_scaffold の整備**  
  - `lib/project_scaffold/` を準備し、プロジェクト雛形を提供。

- **圧縮PDFの自動オープン**  
  - `rakelib/pdf.rake`: `open:pdf` を更新し、`output_compressed.pdf` があれば優先して開くように変更。

- **PDF圧縮エンジンの選択機能**  
  - `rakelib/pdf.rake`: `pdf.compress_engine`（`book.yml`）および `ENV VIVLIO_COMPRESS_ENGINE` に対応。
  - 既定は qpdf 優先、無ければ gs。gs は `-dCompatibilityLevel=1.7` を指定。

- **book.yml の設定追加**  
  - `config/book.yml`: `pdf.compress_engine: qpdf` を追加（qpdf 固定）。

- **フルビルドの制御フラグ拡張**  
  - `rakelib/build.rake`:
    - 画像最適化: `--no-resize` / `--high` / `--medium` / `--low`（既定: medium）
    - PDF圧縮: `--no-compress` でスキップ（既定: 圧縮する）
    - クリーン: `--no-clean` でスキップ（既定: 実行）

### Changed

- **フルビルド後処理の自動化**  
  - ビルド完了後に 画像最適化・PDF圧縮・`clean` を自動実行（`rakelib/build.rake`）。

- **後書きページ番号の通し番号化**  
  - 後書きページも本編と同一カウンタで出力。

- **章扉のページ番号非表示（第2章以降）**  
  - 章扉ページにページ番号が付与されないように修正。

### Fixed

- **扉・奥付のレイアウト修正**  
  - `contents/00-titlepage.md`, `contents/99-colophon.md` の崩れを修正。

- **見出し「1-1」灰色化の修正**  
  - `stylesheets/chapter.css`: `h2::before` を背景専用、`h2::after` を番号＋`text-shadow` 用に分離し、圧縮時の灰色ボックスを解消。

- **CONFIG_PREFIX の定義修正**  
  - `rakelib/common.rb` の `CONFIG_PREFIX` を見直し・修正。

## 0.3.0 - 2025-08-26

### 追加（Added）
- Scaffold 資産を `lib/project_scaffold/` に集約し、`vs new` / `rake new` でコピーされるように対応
  - `contents/`, `stylesheets/`, `images/`, `chapter_templates/`, `vivliostyle.config.js`, `README.md`
- `codes/` を scaffold に追加し、新規プロジェクトへコピー
- `Gemfile`（最小構成）を scaffold に追加し、新規プロジェクトに任意でコピー

### 変更（Changed）
- `lib/vivlio/starter/commands/new.rb` と `rakelib/new.rake` を scaffold 新構成に合わせて全面更新
- `author_templates` を `chapter_templates` にリネームし、参照箇所を更新
- Gemspec: `rake` を runtime 依存に移行（CLI 実行時の LoadError を解消）

### 検証（Verified）
- `_sandbox/sbx-cli2` にて新規作成 → `bundle install` → `bundle exec vivlio-starter build` / `build 11-install` を実行し成功
- `codes/` の include（`sample1.js` / `sample2.js`）が解決されることを確認

## 0.2.0 - 2025-08-25

### 追加（Added）
- CLI: `vs new <name>` で書籍プロジェクトの雛形を生成するコマンドを追加

## 0.1.0 - 2025-08-24

### 追加（Added）
- Gem の初期スケルトンおよび CLI の追加:
  - 実行ファイル: `vivlio-starter`, `vs`
  - プロジェクト直下に `Rakefile` がある場合はそれを優先してロード、無い場合は Gem 同梱のタスクをロード
  - グローバルフラグ `-v/--verbose` に対応（`ENV<dfn id="idx-pzkxfaob7qqk-1" class="index-term" data-yomi="'VERBOSE'">'VERBOSE'</dfn>=1`）
- Gemspec（実行時依存）: `kramdown ~> 2.4`, `nokogiri ~> 1.16`, `hexapdf ~> 1.0`
- 開発時依存: `rake ~> 13.2`, `bundler ~> 2.5`
- バージョンファイル追加: `lib/vivlio/starter/version.rb`（0.1.0）
- README にインストール方法・CLI の使い方・リリース手順を追記

[Unreleased]: https://github.com/Atelier-Mirai/vivlio-starter/compare/v0.34.0...HEAD
[0.34.0]: https://github.com/Atelier-Mirai/vivlio-starter/compare/v0.33.0...v0.34.0
[0.33.0]: https://github.com/Atelier-Mirai/vivlio-starter/compare/v0.32.0...v0.33.0
[0.32.0]: https://github.com/Atelier-Mirai/vivlio-starter/compare/v0.31.0...v0.32.0
[0.31.0]: https://github.com/Atelier-Mirai/vivlio-starter/compare/v0.30.0...v0.31.0
[0.30.0]: https://github.com/Atelier-Mirai/vivlio-starter/compare/v0.29.0...v0.30.0
[0.29.0]: https://github.com/Atelier-Mirai/vivlio-starter/compare/v0.28.0...v0.29.0
[0.28.0]: https://github.com/Atelier-Mirai/vivlio-starter/compare/v0.27.0...v0.28.0
[0.27.0]: https://github.com/Atelier-Mirai/vivlio-starter/compare/v0.26.0...v0.27.0
[0.26.0]: https://github.com/Atelier-Mirai/vivlio-starter/compare/v0.25.0...v0.26.0
[0.25.0]: https://github.com/Atelier-Mirai/vivlio-starter/compare/v0.17.0...v0.25.0
[0.17.0]: https://github.com/Atelier-Mirai/vivlio-starter/compare/v0.16.0...v0.17.0
[0.16.0]: https://github.com/Atelier-Mirai/vivlio-starter/compare/v0.15.0...v0.16.0
[0.15.0]: https://github.com/Atelier-Mirai/vivlio-starter/compare/v0.14.0...v0.15.0
[0.14.0]: https://github.com/Atelier-Mirai/vivlio-starter/compare/v0.13.0...v0.14.0
[0.13.0]: https://github.com/Atelier-Mirai/vivlio-starter/compare/v0.12.0...v0.13.0
[0.12.0]: https://github.com/Atelier-Mirai/vivlio-starter/compare/v0.11.0...v0.12.0
[0.11.0]: https://github.com/Atelier-Mirai/vivlio-starter/compare/v0.10.0...v0.11.0
[0.10.0]: https://github.com/Atelier-Mirai/vivlio-starter/compare/v0.9.1...v0.10.0
[0.9.1]: https://github.com/Atelier-Mirai/vivlio-starter/compare/v0.9.0...v0.9.1
[0.9.0]: https://github.com/Atelier-Mirai/vivlio-starter/compare/v0.8.2...v0.9.0
[0.8.2]: https://github.com/Atelier-Mirai/vivlio-starter/compare/v0.8.0...v0.8.2
[0.8.0]: https://github.com/Atelier-Mirai/vivlio-starter/compare/v0.7.1...v0.8.0
[0.7.1]: https://github.com/Atelier-Mirai/vivlio-starter/compare/v0.7.0...v0.7.1
[0.7.0]: https://github.com/Atelier-Mirai/vivlio-starter/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/Atelier-Mirai/vivlio-starter/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/Atelier-Mirai/vivlio-starter/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/Atelier-Mirai/vivlio-starter/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/Atelier-Mirai/vivlio-starter/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/Atelier-Mirai/vivlio-starter/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/Atelier-Mirai/vivlio-starter/releases/tag/v0.1.0

