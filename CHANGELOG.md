# 変更履歴（Changelog）

このファイルには、本プロジェクトの主な変更内容を記録します。

記法は「Keep a Changelog」に基づき、Semantic Versioning（セマンティックバージョニング）に準拠します。




### Planned


#### ビルド/出力
- [Medium] book.yml の chapters を、contents/と連動するように。
- [High] 奥付が偶数ページになるように
- [High] 縦に長い表のレイアウト崩れ
- [High] 任意の複数章を指定して、フルビルドする
- [High] 任意章フルビルド（既出の計画を拡張）章IDの指定順で束ね、目次・通し番号も整合。実装目安: rake build --chapters=11,12,21 形式。
- [Medium] A4 以外の紙サイズを指定する（推奨文字サイズの確認）
- [Medium] 出力バリアント PDF（裁ち落とし/ノンブル有無）、Web/EPUB（任意）。

#### 校正/Lint・品質

- [High] 日本語表記・組版Lint（スタイルガイド）
- [High] リンク・画像の自動検証
- [Medium] スペルチェック（辞書拡張対応）
- [Medium] 用語候補抽出と一括追加（glossary）: `contents/` を走査し `ABBR(Full Name)`/`Full Name(ABBR)` パターンを検出して候補一覧を作成。対話的に選択して `config/glossary.yml` に一括追加するタスク（例: `glossary:suggest` → `glossary:import_selected`）。
- [Medium] 用語集・索引自動生成 （それらしい専門用語を抽出して、`config/glossary.yml` に一括追加するタスク）
- [Medium] glossary `style: spacing` の実装（スペースの有無/種別の検出・自動修正）
- [Medium] glossary `style: punctuation` の実装（コロン/ハイフン等の記号種別・位置の検出・自動修正）

#### 参照・索引・書誌

- [Medium] 見出しID・相互参照ショートコード（[ref:foo] → 自動リンク）。
- [Medium] 図表キャプション規約の統一（Figure 1.1/表1.1 自動採番）。
- [Low] 用語集・索引自動生成
- [Low] 脚注・参考文献サポート（簡易BibTeX/CSL）
- [Medium] 用語集の付録化（`config/glossary.yml` → 付録章に整形出力、名称/略称/説明/スタイルを一覧化）
- [Medium] 初出ページ付き索引の生成（用語の文書走査→初出箇所のページ番号抽出→索引章に出力）

#### コンテンツ/テンプレート

- [Crucial] 11-install.mdなどを、書き直す
- [Low] テンプレ断片スニペット（注意/補足/Tipのコンポーネント化）。
- [High] プロジェクト生成時に、.cache/vs/ を生成する。


## [Unreleased]


次のステップ（ご相談）

段階2（章PDFの個別キャッシュ）
安定に導入するため、Step 7 のどの方式に載せるか整理が必要です。
現行の「entries → output.pdf → split」の分割結果から章ごと PDF を切り出してキャッシュに保存・再利用する方式
もしくは「章ごと PDF を生成 → merge」に寄せる方式（既存の実験関数 
build_chapter_pdfs_in_parallel_and_merge!
 をベースに拡充）
いずれの方式でも「付録の右ページ開始」「TOC/前付けのパリティ調整」との整合を確保します。
ご希望の方針（分割ベース vs 章別生成ベース）をお知らせいただければ、その方針で段階2をまとめて実装します。
ご要望があれば、段階2の詳細設計（ハッシュキーの定義、再生成判定、結合時の並び・パリティ調整）まで一気に実装します。

段階1（初期導入）
保存先だけ .cache/vs/ に変更（front/colophon/将来的に章PDF）。
結合時は .cache/vs/... からルートに所定名でコピーして使う。
設定：cache.enabled（既定: true）、
     false または --forceオプション指定時は、キャッシュを使わずに生成する。
     cache.dir（既定: .cache/vs/）。

段階2（最適化）
章PDFを個別キャッシュ（例: .cache/vs/11-install-<hash>.pdf）。
全体結合時は変更章のみ再生成、
他はキャッシュから展開。

段階3（メンテナンス）
vs clean:cache サブコマンド追加。

### Added
- `merge:html OUT FILES...` を追加（`lib/vivlio/starter/cli/merge.rb`）。任意の複数 HTML を結合して単一 HTML を生成します。
  - 先頭ファイルの `<html lang>` / `<title>` を採用し、全入力の `<link rel="stylesheet">` を重複排除して集約。
  - `lib/vivlio/starter/cli.rb` に `map 'merge:html' => 'merge_html'` を追加し、コロン表記で呼び出し可能に。
 - キャッシュ設定を追加（段階1）: `cache.enabled`（既定: true）, `cache.dir`（既定: `.cache/vs`）。
 - `clean:cache` コマンドを追加（段階3）: キャッシュディレクトリのみを安全に削除。
 - 真偽値の柔軟解釈ヘルパ `Common.truthy?`/`falsey?` と `Common.fetch_bool` を追加（`yes`/`no`, `on`/`off`, `1`/`0` を解釈）。
   - 本ヘルパは今後の全設定キーで共通利用可能。
   - 現時点での適用箇所: `pdf.quiet`, `pdf.single_doc`, `pdf.close_existing_windows`, `cache.enabled`。

### Changed
- Step 9（`build_helpers.build_front_pages_and_tail!`）の再生成条件を整理。
  - フロント（00/01）PDF のキャッシュ判定に `config/book.yml` の mtime を含め、book 情報更新で確実に再生成。
  - 再生成が必要な場合のみ `create:titlepage`/`create:legalpage`/`create:colophon` を呼び出し、常に `--force` で上書き（スキップ警告を抑止）。
- 00/01 の結合方式を一時的に「単一 HTML にマージして単一 entry 化」へ変更したのち、レイアウト影響（改ページ/センタリング等）を鑑み、元の「entries に 2 本の HTML を渡す」方式へ戻しました。
  - 現在は `entries 00-titlepage.html 01-legalpage.html` → `pdf` → `00-01-front.pdf` リネームのフローに確定。
- Step 9 のキャッシュロジックを簡素化。
  - フロントPDFが最新の場合は、その時点で Step 9 を終了（奥付も最新とみなす）。
  - フロントを再生成した場合は、奥付も必ず再生成。
- ログ文言の調整。
  - フロント/奥付が最新の場合のメッセージを併記表現に変更。
 - front/colophon PDF を `.cache/vs/` にキャッシュ保存し、再生成不要時は必要に応じてキャッシュから復元（段階1）。`--force` 指定時はキャッシュ不使用。

### Fixed
- `create:colophon` を `--force` なしで呼び出してしまい「既に存在するためスキップ」の警告が出る問題を解消。
- Step 9 で奥付 PDF 生成時のリネーム処理を整理（`output.pdf` → `99-colophon.pdf` の単一移動に統一）。


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

- 節見出し（`stylesheets/image_header.css` の `h2` / `h2::before`）の体裁調整を完了。
- 0.8.0 の「image_header.css の位置調整は一旦保留（TODO）」を解消。

## [0.8.0] - 2025-09-04

### Added
- `stylesheets/simple_header.css`: Simple 版の各色バリアントを用意（テーマ連動）。章扉なしデザインでの配色切替に対応。
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
- image_header.css の位置調整は一旦保留。後日見直しのため TODO/FIXME コメントを該当箇所に追記（上下位置の微調整、`--section-hero-height`/マージンの検討など）。

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

[Unreleased]: https://github.com/Atelier-Mirai/vivlio-starter/compare/v0.8.2...HEAD
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

