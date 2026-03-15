# Specification: GetFileType Abolition & TokenResolver Integration

## 1. Purpose (目的)
`Common.get_file_type` によるファイル名ベースの推測ロジックを廃止し、`TokenResolver` が提供するカタログ（`catalog.yml`）由来の登録データ（`CatalogEntry#kind`）へ一本化する。

## 2. Background (背景)
- 現在はファイル名の数字（例: 90番台は付録）で種別を判定しているが、`TokenResolver` の導入により、すでに `CatalogEntry` オブジェクトが `kind` 情報を保持しているため、これを利用すべきである。

## 3. Core Strategy (戦略)
1. **Source of Truth**: 章の種別判定はすべて `TokenResolver::Entry#kind` を参照する。
2. **System Files Support**: カタログに載らない `_titlepage` などのシステムファイルも、Resolver 側で仮想的な Entry として解決する。

## 4. Modified Requirements (修正要件)

### 4.1 TokenResolver::Resolver の拡張
- `catalogentry` において、以下のシステム予約ファイルを解決対象に加える。
  - `_titlepage` -> `kind: :titlepage`
  - `_legalpage` -> `kind: :legalpage`
  - `_colophon`  -> `kind: :colophon`
  - `_indexpage` -> `kind: :indexpage`

## 5. Roadmap (移行手順)
1. **Phase 1**: `TokenResolver` のシステムファイル対応。
2. **Phase 2**: 各ビルドステップで、`CatalogEntry` を引き回すようにする。
3. **Phase 3**: 古い `get_file_type` メソッドおよび関連定数の削除。

## 6. Definitions (CatalogEntry 構造体の活用)
`TokenResolver::CatalogEntry` の以下の属性を最大限活用する：
- `kind`: 章情報をもとに、前処理時の markdown処理や、CSS クラス(chapter.cssなど)の挿入処理など
- `exists`: ファイルの実在チェック。

### 4.2 Common.get_file_typeメソッドの廃止
- 既存の `Common.get_file_type` は実装完了後、廃止する。

## 5. 現行ビルドプロセスの依存箇所

`get_file_type` は以下のモジュールで直接呼び出されている。いずれも `vs build` 実行時の内部ステップで利用されており、TokenResolver から受け取った章情報を引き回せれば置き換えが可能。

| フェーズ | ファイル/モジュール | 役割 | 依存理由 |
| --- | --- | --- | --- |
| PreProcess | `lib/vivlio/starter/cli/pre_process/markdown_preprocessor.rb` | `PreProcessContext` 初期化時に `file_type` と `chapter_number` を設定 | Frontmatter/画像変換が章種別に依存 |
| PostProcess | `lib/vivlio/starter/cli/post_process/body_class_injector.rb` | HTML `<body>` に `chapter`/`preface` 等のクラスを付与 | 最初の本文章判定・CSS クラス出し分け |
| PostProcess | `lib/vivlio/starter/cli/post_process/heading_processor.rb` | h1/h2 の番号生成や data 属性に `file_type` を使用 | 章番号の表示/付録ラベル判定 |
| TOC 生成 | `lib/vivlio/starter/cli/toc.rb` | TOC ノードが扱う `file_type` を `Common.get_file_type` から取得 | 種別ごとのアウトライン整形 |

※ `vs cover` / `vs clean` は `get_file_type` 非依存。`get_file_type` に引っかかるのは上記 4 箇所のみである。

## 6. ビルドパイプラインと CatalogEntry 受け渡し案

### 現状の実装

1. `UnifiedBuildPipeline` (lib/vivlio/starter/cli/build/pipeline.rb) は `entries` (Array<TokenResolver::Entry>) を保持している。
2. 各ステップは以下のように `entries` を受け取っている：
   - `Build::SectionBuilder.preprocess_sections!(entries)` (Step 4)
   - `Build::SectionBuilder.convert_sections_html!(entries)` (Step 6)
   - `Build::TocGenerator.generate_toc_and_pdf!('.', entries)` (Step 7)
   - `Build::PdfBuilder.build_overall_pdf_from_dir!('.', entries)` (Step 8)

3. **重要な発見**: `SectionBuilder` 内部では `entries` から `basename` を抽出し、それを `PreProcessCommands.execute_pre_process({}, [basename])` に渡している。この時点で `Entry` オブジェクトが失われている。

4. `PreProcessCommands` / `PostProcessCommands` は内部で `resolve_md_files` / `resolve_html_files_for_post_process` を使い、`Entry.respond_to?(:path)` や `Entry.respond_to?(:basename)` で判定して対応している。**しかし `MarkdownPreprocessor` の初期化時点では `Entry` を受け取っておらず、ファイル名から `Common.get_file_type` を呼んでいる。**

### 問題点

- `MarkdownPreprocessor.new(md_file)` は文字列パスのみを受け取り、内部で `Common.get_file_type(filename)` を呼び出している。
- `BodyClassInjector` / `HeadingProcessor` も HTML パスのみを受け取り、`Common.get_file_type` を呼び出している。
- つまり、**`Entry` は各ステップの入口までは届いているが、実際の処理クラス（Preprocessor / Injector / Processor）には渡されていない**。

## 7. フェーズ別移行計画（詳細）

### Phase 1: TokenResolver のシステムファイル対応

**目的**: `_titlepage` / `_legalpage` / `_colophon` / `_indexpage` を TokenResolver が解決できるようにする。

**実装方針**:
- `TokenResolver::Resolver#resolve` に特殊ファイル判定を追加し、`_titlepage` などが渡された場合は `kind: :titlepage` の仮想 Entry を返す。
- `KIND_RANGES` とは別に `SYSTEM_FILE_KINDS = { '_titlepage' => :titlepage, '_legalpage' => :legalpage, '_colophon' => :colophon, '_indexpage' => :indexpage }` のようなマッピングを用意。
- これにより、ビルドパイプラインが特殊ページを処理する際も `Entry#kind` を参照できる。

### Phase 2: 各ステップへの CatalogEntry 伝播

**目的**: `MarkdownPreprocessor` / `BodyClassInjector` / `HeadingProcessor` が `Entry#kind` を直接参照できるようにする。

**実装方針**:

1. **PreProcess**
   - `MarkdownPreprocessor.new(md_file, entry: nil)` のように `entry` をオプション引数として受け取れるようにする。
   - `entry` が渡された場合は `context.file_type = entry.kind` を使い、`nil` の場合は後方互換のため `Common.get_file_type(filename)` にフォールバック。
   - `SectionBuilder#preprocess_single_chapter!` を修正し、`Entry` オブジェクトを渡せるようにする（現状は basename 文字列のみ）。

2. **PostProcess (BodyClassInjector / HeadingProcessor)**
   - 現状の `PostProcessCommands.execute_post_process` は `entries` を受け取っているが、内部で `resolve_html_files_for_post_process` を呼んで HTML パスのリストに変換している。
   - この際、`Entry` と HTML パスの対応を `Hash` で保持し、`BodyClassInjector.inject_body_class(html_file, entry:)` / `HeadingProcessor.build_heading_context(html_path, entry:)` のように渡す。
   - 各モジュールは `entry` が渡された場合は `entry.kind` を使い、`nil` の場合は `Common.get_file_type` にフォールバック。

3. **TOC 生成**
   - `Toc::ChapterNode` は既に `file_type` を保持しているが、これを `Entry#kind` から取得するように変更。
   - `TocGenerator.generate_toc_and_pdf!` は既に `entries` を受け取っているため、内部で `Entry#kind` を参照するだけで済む。

### Phase 3: `Common.get_file_type` の段階的廃止

**目的**: 全ての `get_file_type` 呼び出しを `Entry#kind` に置き換え、メソッドを削除する。

**実装方針**:
1. Phase 1/2 完了後、各モジュールで `entry` が常に渡されることを確認。
2. フォールバック処理（`entry.nil?` 時の `get_file_type` 呼び出し）を削除。
3. `Common.get_file_type` メソッドを削除し、`module_function` のエクスポートリストからも除外。
4. `CHANGELOG` / `docs/DEVELOPER_GUIDE.md` に廃止の旨を記載。

## 9. 簡略化の理由

当初の仕様案では「html_manifest による逆引き」や「BuildPipelineContext の導入」など複雑な機構を提案していたが、実装を確認した結果、以下の点が判明した：

1. **既に `entries` は各ステップに渡されている**: `UnifiedBuildPipeline` → `SectionBuilder` → 各コマンドへの流れは確立済み。
2. **問題は最終処理クラスへの伝播のみ**: `MarkdownPreprocessor` / `BodyClassInjector` / `HeadingProcessor` が `Entry` を受け取っていないだけ。
3. **後方互換を保ちつつ段階的に移行可能**: オプション引数 `entry: nil` を追加し、フォールバックを残せば既存コードを壊さずに移行できる。

したがって、**大規模なリファクタリングは不要**で、各処理クラスに `entry:` オプションを追加し、呼び出し側で `Entry` を渡すだけで実現できる。

## 8. 成功条件 / 受け入れ基準

1. `grep -R get_file_type lib/` が 0 件になること。
2. `vs build` の全ステップが TokenResolver の `Entry#kind` のみで章種別を判定していること。
3. `_titlepage` / `_legalpage` などシステムファイルも Resolver から供給され、追加でファイル名を解析しなくても済むこと。
4. 既存テスト（特に `pre_process`, `post_process`, `toc` 周辺）が `Entry` 連携の新仕様で通過すること。
5. 後方互換性が保たれ、`entry: nil` 時のフォールバックが正しく動作すること（移行期間中）。

---

上記の簡略化された方針により、過度に複雑な中間層を導入せず、最小限の変更で `get_file_type` を廃止できる。
