# 変更履歴（Changelog）

このファイルには、本プロジェクトの主な変更内容を記録します。

記法は「Keep a Changelog」に基づき、Semantic Versioning（セマンティックバージョニング）に準拠します。




### Planned

- [Medium] 章・節に対する相互参照の整備（章番号ベースの cross reference）。本文中から「第◯章」「第◯節」を参照する簡潔な記法を設計し、既存の `@id` ベースの図表・コードリスト参照パイプラインと統合する。

### Pre-release Checklist
- gem 公開時には `vivlio-starter.gemspec` の summary/description が現行仕様に即しているか再確認する。
- `pre_process.rb` で参照する theme.css テンプレート（`lib/project_scaffold/stylesheets/theme.css`）が gem に同梱されているか確認する。
- リリースノートの作成


#### 実装済み
- [High] 任意の複数章を指定して、フルビルドする
- [High] 任意章フルビルド（既出の計画を拡張）章IDの指定順で束ね、目次・通し番号も整合。実装目安: rake build --chapters=11,12,21 形式。
- [High] PDF に章アウトライン（ブックマーク）を付与（本文PDF/最終PDF）。読者のナビゲーション向上のため、Step 7/10 後段で HexaPDF により後付け。
- [High] 縦に長い表のレイアウト崩れ
- [Medium] 見出しID・相互参照ショートコード（[ref:foo] → 自動リンク）。
- [Medium] 図表キャプション規約の統一（Figure 1.1/表1.1 自動採番）。

#### ビルド/出力
- 00, 01, (blank), 02, (blank), 03, (blank), 11-98(cssにより右頁始まり), (blank), 99 として結合
- [Medium] book.yml の chapters を、contents/と連動するように。
- [High] 奥付が偶数ページになるように
- [Medium] A4 以外の紙サイズを指定する（推奨文字サイズの確認）
- [Medium] 出力バリアント PDF（裁ち落とし/ノンブル有無）、Web/EPUB（任意）。

#### 校正/Lint・品質
リファクタリング前 519 件 -> 508件
- [High] RuboCop が全面的に通るよう CLI/ビルド系スクリプトを継続的にリファクタリング。
102 lib/vivlio/starter/cli/build_helpers.rb
 42 lib/vivlio/starter/cli/post_process.rb
 44 lib/vivlio/starter/cli/pre_process.rb
169 lib/vivlio/starter/cli/glossary.rb
 17 lib/vivlio/starter/cli/common.rb
 11 lib/vivlio/starter/cli/create.rb
 29 lib/vivlio/starter/cli/build.rb
 0 lib/vivlio/starter/cli/pdf.rb
 0 lib/vivlio/starter/cli/toc.rb
 0 lib/vivlio/starter/cli/text_metrics.rb
 0 lib/vivlio/starter/cli/delete.rb
 11 lib/vivlio/starter/cli/doctor.rb
 11 lib/vivlio/starter/cli/new.rb
 10 lib/vivlio/starter/cli/resize.rb
 10 lib/vivlio/starter/cli/rename.rb
  9 lib/vivlio/starter/cli/merge.rb
  9 lib/vivlio/starter/cli/vivliostyle.rb
  9 lib/vivlio/starter/cli/entries.rb
  9 lib/vivlio/starter/cli/clean.rb
  8 lib/vivlio/starter/cli/convert.rb
  8 lib/vivlio/starter/commands/new.rb
  0 lib/vivlio/starter/cli.rb
  0 lib/vivlio/starter/cli/prism_lines.rb
  0 lib/vivlio/starter/cli/help.rb
  0 lib/vivlio/starter/cli/renumber.rb
  0 lib/vivlio/starter/version.rb

- [High] 日本語表記・組版Lint（スタイルガイド）
- [High] リンク・画像の自動検証
- [Medium] スペルチェック（辞書拡張対応）
- [Medium] 用語候補抽出と一括追加（glossary）: `contents/` を走査し `ABBR(Full Name)`/`Full Name(ABBR)` パターンを検出して候補一覧を作成。対話的に選択して `config/glossary.yml` に一括追加するタスク（例: `glossary:suggest` → `glossary:import_selected`）。
- [Medium] 用語集・索引自動生成 （それらしい専門用語を抽出して、`config/glossary.yml` に一括追加するタスク）
- [Medium] 基本的に良く用いる用語をまとめた用語集テンプレートを標準添付し、プロジェクト作成時または後から選択適用できるようにする。
- [Medium] glossary `style: spacing` の実装（スペースの有無/種別の検出・自動修正）
- [Medium] glossary `style: punctuation` の実装（コロン/ハイフン等の記号種別・位置の検出・自動修正）
- [Medium] text_metrics に語の平均長・漢字比率など語彙難度指標を追加する
- [Medium] text_metrics に語彙多様度（TTR 等）の集計を追加する
- [Low] text_metrics で日本語向け読解難度スコア（Flesch/Kincaid 等を応用）を算出する
- [Low] text_metrics で見出し/セクション単位の分量バランスを可視化する

#### 参照・索引・書誌
- [Low] 用語集・索引自動生成
- [Low] 脚注・参考文献サポート（簡易BibTeX/CSL）
- [Medium] 用語集の付録化（`config/glossary.yml` → 付録章に整形出力、名称/略称/説明/スタイルを一覧化）
- [Medium] 初出ページ付き索引の生成（用語の文書走査→初出箇所のページ番号抽出→索引章に出力）

#### コンテンツ/テンプレート
- [High] 11-install.mdなどを、書き直す
- [Low] テンプレ断片スニペット（注意/補足/Tipのコンポーネント化）。
- [High] プロジェクト生成時に、.cache/vs/ を生成する。
- [High] プロジェクト生成時に、project_scaffold/ を生成する。


ビルドのマニュアルを書く
- [High] ビルド時にcover画像も含むように
- [High] 塗り足しやepub対応
- [High] pdf_reader -> mdに
- [High] Re:View Starter -> Vivlio Starter

## [Unreleased]
（次回リリース候補の変更はここに追加してください）

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

## [0.16.0] - 2025-11-15

### Added
- **章番号ベースのビルド指定**: `book.yml` の `chapters` 設定で番号ベースの指定をサポート。配列 `[02, 11, 12, 91]`、カンマ区切り "02, 11, 12, 91"、範囲指定 "02-12, 91" の形式で章を指定可能に。従来のファイル名指定と併用はできず、混在時はエラーで中止。
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

### Changed
- `vs build` の完了時に、`output.pdf` および `output_compressed.pdf` を `book.yml` の設定に基づく動的ファイル名へリネームし、生成物がプロジェクト名・バージョンを反映した名称で出力されるように調整（例: `vivlio_starter_v1.0.0.pdf` / `vivlio_starter_v1.0.0_compressed.pdf`）。
- `lib/project_scaffold/stylesheets/titlepage.css` と `stylesheets/titlepage.css` を更新し、タイトル・副題・著者名が紙サイズに応じて重ならず整列するよう CSS Grid ベースのレイアウトに再設計。


## [0.15.0] - 2025-11-07

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

## [0.14.0] - 2025-11-04

### Added
- Textlint を日本語対応ワークフローとして再構築し、カスタムフォーマッターの導入・VFM 記法向け allowlist/filter 対応・scaffold/`vs doctor --fix` による設定一式の自動配備を実装。

### Changed

## [0.13.0] - 2025-11-03

### Added
- テーマカラー候補に coral / navy / mint / plum / peach を追加し、yellow 系の色味を調整。
- `theme.frontispiece` をネスト構造で受け取り、padding / heading_width / lead_width を CSS カスタムプロパティとして展開。
- macOS 環境の `vs doctor --fix` で waifu2x を自動ダウンロード・展開し、`$HOME/.local/bin/waifu2x/` 以下へ配置できるよう対応。
- frontispiece / ornament の解決時に `_portrait` / `_landscape` バリアントを自動生成し、次回以降は既存ファイルを優先利用するよう改良。
- 扉絵・節装飾に利用できるバンドル画像セットを 36 種類（ajisai など）に拡充し、即座に `_portrait` / `_landscape` バリアントへ展開可能に。

### Changed
- simple テーマ向け header スタイルを刷新し、章タイトル・節見出しをバナー調に再設計。
- image テーマの章扉レイアウトと節見出し装飾を再設計し、frontispiece 余白・見出し幅・装飾画像のアスペクト比・折り返し制御を改善。

## [0.12.0] - 2025-10-28

### Added
- minitest を導入し、バージョン定数およびフルビルドパイプラインの基本動作を検証する最初のテストスイートを整備。
- CLI コマンド（build/open/create/delete/rename/renumber/new/doctor/glossary/text_metrics/help/version）の挙動を確認する追加テストを整備し、主要サブコマンドのユースケースをカバー。
- 画像が見当たらない場合、代替画像でビルドする機能を`pre_process.rb`に追加。
- `vs doctor` が macOS 環境で Google Fonts 用 SSL 証明書の診断を行い、`--fix` 指定時に Homebrew で openssl@3 / ca-certificates を整備し `SSL_CERT_FILE` / `SSL_CERT_DIR` を自動設定する機能。
- book.yml に指定したフォントを Google Fonts からローカルへ自動取得し、可読性の高いファイル名で保存したうえで `google-fonts.css` に集約する FontManager を整備。

### Changed
- `pdf_compress` の Ghostscript オプションに線形化（Fast Web View）と重複画像検出を追加し、閲覧時の初期表示とページ遷移を高速化。
- `vs clean --cache` 実行時に `.vivliostyle` ディレクトリも削除するようクリーン処理を拡張。


## [0.11.0] - 2025-10-27


### Added
- README 冒頭に Vivlio Starter ロゴとブランド要約を追記。
- text_metrics コマンドに平均文長・文数・読点数・句数・平均句長を追加し、JSON/YAML/表すべてで出力できるよう拡張。

### Changed
- CLI コマンド群をリファクタリングし、`module_function` 化とコマンド説明文の定数化を実施（thor DSL の記述揺れを解消）。
- `build.rb` の単章ビルド処理をパイプライン化し、実行フローと付随処理（マージ・オープン）を専用クラスへ分割。
- `pre_process.rb` / `post_process.rb` の大型メソッドを段階的ヘルパーへ分解し、前後処理の責務を明確化。

## [0.10.0] - 2025-10-26

### Added
- 目次の構成を見直し、ブックマークが所定の階層で揃うよう調整（「始めに」配下の見出し整理、および奥付・付録の固定ラベル化）。HTML 出力に章番号用の `<span class="chapter-number">…</span>` を導入し、抽出アルゴリズムを改良したことで、フルビルド時にも目次が欠落なく生成されるよう改善。
- 文章量や見出し統計を取得できる `text_metrics` コマンドを追加し、原稿の分量チェックを容易に。

### Removed
- 従来の章別 CSS（例: `stylesheets/11.css` など）を廃止し、共通スタイルに一本化。

### Changed
- 開発環境の Vivliostyle CLI/Core を 9.7.2 / 2.35.0 へ更新。
- ビルドシステムを整理し、キャッシュ活用などで処理を簡素化・高速化。

## [0.9.1] - 2025-09-09

### Added
- `pdf [OUTPUT]`: 出力ファイル名を引数で指定可能に（指定時は生成後にリネームを自動実行）。
- ビルド対象/存在チェックの汎用ヘルパ `BuildHelpers.buildable?(basename, keep)` を追加。

### Changed
- `vs build --no-clean` が Step 0（事前クリーン）でも有効になるよう変更（従来は Step 13 のみ）。
- `build_helpers.preface_prebuild!` は `Vivlio::Starter::ThorCLI.start(['pdf', '02-preface.pdf'])` を使用し、リネーム処理を `pdf` コマンド側へ集約。
- 付録の対象抽出で `buildable?` を使用して `keep` と存在を同時に判定。
- `chapter_numbers_for_book(keep)` が例外時に `nil` を返す仕様に変更。これに伴い呼び出し側の `begin/rescue` を削除し、代入1行へ簡素化。
- ルーター（`lib/vivlio/starter.rb`）から Rake 時代の残滓（`new` の特別扱い、コメント）を整理し、Thor 委譲に一本化。

### Fixed
- `vs build` 実行時に Thor の `options` を直接書き換えてしまい `FrozenError` で無音終了する問題を修正。
  - 対応: `options[:force] ||= options[:'no-cache']` を廃止し、ローカル変数 `force` に展開して使用。

### Removed
- `--single_html` オプションを削除しました。Step 7 の通常経路は以下に整理されています。
  - 指定あり（または `VIVLIO_EXPERIMENTAL_PARALLEL_PDF=1`）: `build_chapter_pdfs_in_parallel_and_merge!`
  - 指定なし（既定）: `build_overall_pdf_and_split_from_dir!('.', keep)`

### Refactored
- レンジ定数を導入: `MAIN_RANGE=(11..89)`, `APPX_RANGE=(91..97)`（重複するリテラルを排除）。
- HTML収集の共通化: `BuildHelpers.htmls_for_range(base_dir, range, keep_numbers)` を追加し、Step 6/7 で使用。
- 並列処理ユーティリティ: `BuildHelpers.parallel_each(items, concurrency:)` を追加し、Step 5 の並列ビルド実装を簡素化。
- `pdf [OUTPUT]` に寄せるリファクタリング: TOC/フロント/奥付/後書きの PDF 生成で手動リネームを廃止。
- 付録ガードHTML: `ensure_appendices_guard_html` ヘルパを追加し、Step 7 から呼び出すよう変更。`clean` に `90-appendices-guard.html` を明示追加。
- 互換コードの整理: `run_pdf_without_single_doc!` を削除（`--single-doc` 廃止済み）。
- アウトライン抽出を簡素化: 旧 `VS-H:` 接頭辞の除去処理を削除し、`data-heading`/見出しテキストのみに統一。

### Notes
- 将来的に、特定 basename を扱う他ステップ（例: `98-postface` や `99-colophon` 相当）にも `buildable?` の導入を検討し、対象判定と存在チェックの一元化を進めます。



## [0.9.0] - 2025-09-09

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

## [0.8.2] - 2025-09-07

### Added
- `build`: `--force` を追加（Step 9 で 00/01/99 を強制再生成）。
  - `vs build --force` 実行時、`create:titlepage --force` / `create:legalpage --force` / `create:colophon --force` を自動呼び出し。
- `config/book.yml` のテーマ系オプションを拡充（実装）。
  - `style: image|simple`, `color: '#ff0000'`（HEX 記法は引用符推奨）、
    `frontispiece: door2`（扉絵）、`ornament: frame-blue`（節見出し装飾）、`markers:`（見出し用マーカー）

### Changed
- ログ出力制御を `--log[=level]` に統一しました（`lib/vivlio/starter/cli/common.rb`）。
  - `--log=error`(0) / `--log=warn`(1) / `--log=info|success|action`(2, 既定) / `--log=debug`(3)
  - `--log`（レベル省略）は `--log=info` と同義です。
  - 既定（未指定）は `warn` レベルです。
  - 互換性: 旧オプション `-q` / `-v` / `-vv` や `--verbose`、環境変数 `VERBOSE`/`DEBUG`/`LOG_LEVEL` は廃止しました。
- `vs clean` の削除対象/挙動を見直し。
  - pre_process 展開などで生成される章系 Markdown（`00-*.md`〜`99-*.md` のみ）を削除対象に追加。
  - それ以外の Markdown（README.md などユーザー資産）は、`--purge` 指定でも削除しない安全仕様に固定。
  - これに伴いヘルプ文言（`--purge` の説明）を更新。

### Notes

## [0.8.1] - 2025-09-05

### Changed

- 節見出し（`stylesheets/image-header.css` の `h2` / `h2::before`）の体裁調整を完了。

## [0.8.0] - 2025-09-04

### Added
- `stylesheets/simple-header.css`: Simple 版の各色バリアントを用意（テーマ連動）。章扉なしデザインでの配色切替に対応。
- `open:pdf [PATH]` 対応（`lib/vivlio/starter/cli/pdf.rb`）: 任意のPDFパスを指定しても Preview のウィンドウ位置設定（`pdf.window_bounds`）を適用可能に。
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

## [0.7.1] - 2025-09-03

### Changed
- `vs build` 内部実装をリファクタリングし、`config/book.yml` の `chapters` サブセット（keep）が Step 6/7/11 に貫通する実装を安定化（退避・復元なしの論理フィルタを前提に整理）。

### Fixed
- `vs build` のトークン展開で、`.md` を含む入力（例: `11-install.md`）や `contents/` 接頭の入力を正しく解決するよう修正。
- `build.rb` のクォート不備（シェル式の `\'\''`）により構文エラーとなる箇所を修正。
- `base.class_eval` ブロックを早期に閉じていた余分な `end` を削除し、構文エラーを解消。

## [0.7.0] - 2025-09-03

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
- `configured_chapters` は `contents/` 接頭辞と拡張子の有無を正規化し、`['11-foo.md', ...]` の形式で扱います。
- CSS の仮想連番（Step 2）は引き続き `.orig` バックアップを用いた復元（Step 11）を行いますが、章の選定は `keep` に基づきます。

## [0.6.0] - 2025-08-31

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


## [0.5.0] - 2025-08-30

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

## [0.4.0] - 2025-08-26

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

## [0.3.0] - 2025-08-26

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

## [0.2.0] - 2025-08-25

### 追加（Added）
- CLI: `vs new <name>` で書籍プロジェクトの雛形を生成するコマンドを追加

## [0.1.0] - 2025-08-24

### 追加（Added）
- Gem の初期スケルトンおよび CLI の追加:
  - 実行ファイル: `vivlio-starter`, `vs`
  - プロジェクト直下に `Rakefile` がある場合はそれを優先してロード、無い場合は Gem 同梱のタスクをロード
  - グローバルフラグ `-v/--verbose` に対応（`ENV['VERBOSE']=1`）
- Gemspec（実行時依存）: `kramdown ~> 2.4`, `nokogiri ~> 1.16`, `hexapdf ~> 1.0`
- 開発時依存: `rake ~> 13.2`, `bundler ~> 2.5`
- バージョンファイル追加: `lib/vivlio/starter/version.rb`（0.1.0）
- README にインストール方法・CLI の使い方・リリース手順を追記

[Unreleased]: https://github.com/Atelier-Mirai/vivlio-starter/compare/v0.9.0...HEAD
[0.9.0]: https://github.com/Atelier-Mirai/vivlio-starter/compare/v0.8.2...v0.9.0
[0.8.2]: https://github.com/Atelier-Mirai/vivlio-starter/compare/v0.8.1...v0.8.2
[0.8.0]: https://github.com/Atelier-Mirai/vivlio-starter/compare/v0.7.1...v0.8.0
[0.7.1]: https://github.com/Atelier-Mirai/vivlio-starter/compare/v0.7.0...v0.7.1
[0.7.0]: https://github.com/Atelier-Mirai/vivlio-starter/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/Atelier-Mirai/vivlio-starter/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/Atelier-Mirai/vivlio-starter/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/Atelier-Mirai/vivlio-starter/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/Atelier-Mirai/vivlio-starter/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/Atelier-Mirai/vivlio-starter/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/Atelier-Mirai/vivlio-starter/releases/tag/v0.1.0

