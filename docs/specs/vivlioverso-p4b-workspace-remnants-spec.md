# P4b: prep 段生成物の workspace 化（images/math/・_index_matches.yml）詳細仕様

調査日: 2026-07-05 / 調査者: Claude (Fable 5) / 実装担当: Opus 4.8 /
位置づけ: [vivlioverso-p4-investigation.md](vivlioverso-p4-investigation.md) §1.2・§8 で
「任意・P4b」として切り出された残件の実装個票。P4 本体（段階 1〜6）は完了済み
（master マージ e9927b88）。

> **実装者への共通指示**（workplans と同一）
> - 完了条件は「`rake test` / `rake test:standard` 緑・rubocop クリーン・
>   実プロジェクトで `vs build`（全ターゲット）実走・出力の同一性確認」＋本書固有条件。
> - 仕様と実装が食い違う場合は実装を止めて報告する。

---

## 0. 結論（先出し）

- P4 完了後、ビルドがプロジェクトルート（著者領域）へ書く中間物は **2 点だけ**残っている:
  `images/math/`（数式 SVG）と `_index_matches.yml`（索引スキャン結果）。
  final clean（`pipeline.rb:396-408`）がこの 2 点を個別掃除しているのが現状の姿。
- 数式 SVG は **`BUILD_HTML_DIR/images/math/` へ生成し、HTML からの参照は
  消費者 dir 相対（`images/math/…`・asset_prefix 無し）**とする。
  この参照形が要（§2.1）: EPUB/Kindle の prefix 剥がし（`stage_consumer_htmls!` の gsub）を
  **素通り**し、E2 で確定した dot-dir 禁止にも抵触せず、PDF/EPUB/Kindle が同型になる。
- `_index_matches.yml` は `Common::BUILD_DIR` 直下へ移す（書き手・読み手とも定数 1 本化）。
- final clean は `rm_rf BUILD_DIR` **のみ**になり、ルート個別掃除が消滅する
  （P4 完了条件 4「ルート無汚染」の完全達成）。clean.rb のルート側掃除は
  headings/_epub_assets と同じ「旧バージョン残骸掃除（1 リリース残して V2.0 撤去）」へ縮退。
- 出力同一性は**厳密に検証可能**: 参照パスの最終形は EPUB 内部では現行と同一
  （後述）、PDF はレンダリング内容不変（パス表記のみ変化）。

---

## 1. 現状（対象 2 生成物の書き手・読み手マップ）

### 1.1 `images/math/`（数式 SVG）

| 役割 | 所在 | 実態 |
|---|---|---|
| 書き手 | `MathTransformer.transform`（`math_transformer.rb:94-97`） | `out_dir = File.join(Common.images_dir, 'math', chapter_slug)`＝**ルートの images/math/**。`render_uncached!` は既存ファイルをスキップ（ビルド内キャッシュ） |
| 参照の書き手 | 同上 `rel_dir` | `"#{Common.asset_prefix}#{images_dir}/math/#{slug}"` → HTML には `../../../../images/math/…` が書かれる |
| 呼び出し元 | `MarkdownPreprocessor#transform_math!`（`markdown_preprocessor.rb:148-163`） | `normalize_image_paths!`（`:75`）より**後**に実行 → ImagePathNormalizer は math `<img>` に触れない（順序保証あり・変更不要） |
| PDF 消費者 | `pdf/` にステージされた HTML | 上方参照 `../../../../` でルートの実体を読む（E3 実証済みの現行形） |
| EPUB/Kindle 消費者 | `stage_consumer_htmls!`（`epub_builder.rb:104-110`）が prefix を剥がし `images/math/…` に、`localize_assets!`（`:123-128`）が**ルート images/ から** dir 内へ選択コピー | EPUB 内部パスは `images/math/…` |
| Techbook | `rewrite_svg_references!`（`techbook/processor.rb`） | `<img src="*.svg">` を「対応 .webp が**ディスクに在れば**」書換。存在確認は asset_prefix を剥がした cwd 相対（math は .webp が無いので常に素通り） |
| 掃除 | final clean（`pipeline.rb:405`）・`vs clean`（`clean.rb:237-243`） | 個別 `rm_rf` |

### 1.2 `_index_matches.yml`（索引スキャン結果）

| 役割 | 所在 |
|---|---|
| 書き手 | `IndexMatchScanner#save_matches!`（`index_match_scanner.rb:533-540`・固定名ルート直下） |
| 読み手 | `UnifiedPageBuilder::INDEX_MATCH_FILE`（`unified_page_builder.rb:52, 70-71, 126`） |
| 経路 | どちらも `UnifiedIndexManager`（build Step「index scan and build」および `vs index` 系）内で完結。**scan の入力 .md は既に `BUILD_HTML_DIR` を読み**（`index_match_scanner.rb:173`）、生成する `_indexpage.html` / `_glossarypage.html` も `BUILD_HTML_DIR` へ書く（`unified_page_builder.rb:54-55`）——**この yml だけがルートに取り残されている** |
| 掃除 | final clean（`pipeline.rb:406`）・clean.rb `ACTIVE_ROOT_PATTERNS`（`:63-66`）・`--cache` 分岐（`:167-171`） |

### 1.3 対象外（本書スコープに含めない・§6 参照）

- `stylesheets/fonts/google-fonts.css`（FontManager 生成・git 管理下）
- `_index_review.md` / `_index_glossary_review.md`（著者レビュー用・ルート据え置きが仕様）
- `entries.js` / `vivliostyle.config.js`（著者向け手動フロー・P3-4 個票の領分）

---

## 2. 設計仕様

### 2.1 数式 SVG の生成先と参照形（★本書の要）

**生成先**: `File.join(Common::BUILD_HTML_DIR, 'images', 'math', chapter_slug)`
**HTML 参照**: `images/math/<slug>/<hash>.svg`（**asset_prefix を付けない**・消費者 dir 相対）

`math_transformer.rb:94-97` の変更（イメージ）:

```ruby
out_dir = File.join(Common::BUILD_HTML_DIR, 'images', REL_BASE, chapter_slug)
# 参照は消費者 dir 相対。EPUB/Kindle の prefix 剥がし（stage_consumer_htmls!）を
# 素通りし、PDF は §2.2 のステージで同 dir 内に実体を持つ（P4b §2.1）。
rel_dir = "images/#{REL_BASE}/#{chapter_slug}"
```

**なぜ dir 相対か**（他案の棄却理由）:

| 案 | 判定 | 理由 |
|---|---|---|
| dir 相対 `images/math/…`（採用） | ✅ | 4 消費者 dir が同一深度（P4 §3.1）なので html/→pdf/ の無加工コピーでも有効。EPUB の prefix 剥がし gsub は no-op で素通り。EPUB 内部パスは現行と**同一**（`images/math/…`） |
| 現行どおり `../../../../images/…` で実体だけ workspace へ | ❌ | プレフィックスを剥がした先（ルート）に実体が無くなり、EPUB ローカライズ・Techbook 存在確認が全て特例化する |
| `.cache/vs/math/`（キャッシュ永続化） | 見送り | 剥がし後に `.cache/…` の dot-dir 参照が残り E2（EPUB は dot-dir でビルド不能）に抵触。EPUB 側に専用の書換規則を足せば回避できるが、可動部が増える。レンダリング永続キャッシュとしての価値は将来課題へ（§6） |

補足: 同一 HTML 内で「著者画像は `../../../../images/…`・数式は `images/…`」と参照形が
混在するが、これは「著者資産（ルート）とビルド生成物（workspace 内）」の区別が
参照形に現れたものであり、意味的に正しい。

### 2.2 PDF 消費者: ステージに images/ ミラーを追加

`PdfBuilder.stage_workspace_htmls!`（`pdf_builder.rb:38-45`）に、HTML コピーへ続けて
`BUILD_HTML_DIR/images/` → `BUILD_PDF_DIR/images/` の再帰ミラーを追加する
（存在すれば `cp_r`・上書き可）。これで `pdf/` の HTML から `images/math/…` が解決される。

- 呼び出しは `build_overall_pdf_from_dir!` / `generate_entries_for_sections!` の 2 経路
  （full の pdf あり/print_pdf のみ・single とも通過）→ **追加の配線は不要**。
- dedup 後の再ビルド（`BacklinkDedupOrchestrator#rebuild_pdf!`）はステージ済み資産を
  そのまま使う → 変更不要。
- `PageMappingExtractor` は `pdf/` の config で preview する（P4 E4）→ ステージ済みで解決。

### 2.3 EPUB/Kindle 消費者: ローカライズ元に workspace を追加

`EpubBuilder.localize_assets!`（`epub_builder.rb:123-128`）に、ルート `images/` に加えて
`BUILD_HTML_DIR/images/` をソースとするコピーを追加する。
`copy_asset_tree!`（`:132-143`）は「src がルート相対のまま dest に接がる」前提のため、
**`dest_root:` 引数を足して一般化**する（`dest = File.join(dir, dest_root, rel)`）:

```ruby
copy_asset_tree!(Common.images_dir, dir) { localized_image?(it, flavor) }
# ビルド生成画像（数式 SVG）は workspace の html/ 配下から（P4b）
copy_asset_tree!(File.join(Common::BUILD_HTML_DIR, 'images'), dir, dest_root: 'images') { … }
```

- フィルタは `localized_image?` をそのまま通す（math は SVG なので両フレーバで同梱対象。
  Kindle の WebP 除外にも数式は該当しない）。
- EPUB 内部の最終パスは `images/math/…` で**現行と完全一致** → epubcheck・
  `epub_kindle_layout_test` に構造差は出ない。

### 2.4 Techbook `rewrite_svg_references!` の存在確認を HTML 基準へ

`techbook/processor.rb` の `rewrite_svg_references!` は `.webp` の存在確認を
「src から asset_prefix を剥がした cwd 相対」で行っている。dir 相対参照（math）に対しては
剥がしが no-op となり**ルートの `images/math/*.webp` を見に行く**（実体は workspace）。
math に .webp は存在しないため現状でも誤書換は起きないが、判定が「たまたま正しい」状態に
なるため、**src を HTML ファイル自身の位置基準で解決する**正しい形へ直す:

```ruby
webp_on_disk = File.expand_path(webp_src, File.dirname(html_file))
```

（asset_prefix 付き・dir 相対の両参照形を 1 つの規則で正しく扱える。既存挙動は不変。）

### 2.5 `_index_matches.yml` の移設

- `Common` に定数を新設: `INDEX_MATCHES_FILE = "#{BUILD_DIR}/_index_matches.yml"`
  （委譲メソッド `index_matches_file` も既存規約に合わせて追加可）。
- 書き手 `index_match_scanner.rb:535`: `cache_file = Common::INDEX_MATCHES_FILE` ＋
  `FileUtils.mkdir_p(File.dirname(cache_file))`（`vs index` 系の単独実行では
  workspace が未作成の可能性があるため）。
- 読み手 `unified_page_builder.rb:52`: `INDEX_MATCH_FILE` を撤去し `Common::INDEX_MATCHES_FILE`
  参照へ（`:70-71` の警告文言も新パスに）。
- ログ・ヘッダコメント（`index_match_scanner.rb:11` ほか）のパス記述を更新。

### 2.6 掃除系の縮退

1. **final clean**（`pipeline.rb:396-408`）: 個別掃除 2 行（`rm_rf images/math`・
   `rm_f _index_matches.yml`）と該当コメントを削除。`rm_rf BUILD_DIR` のみが残る。
2. **clean.rb**:
   - `ACTIVE_ROOT_PATTERNS`（`:63-66`）から `_index_matches.yml` を外し、
     `LEGACY_ROOT_PATTERNS` へ移す（旧バージョン残骸掃除・1 リリース残置）。
     `entries.js` `_index_review.md` `_index_glossary_review.md` は現役のまま残す。
   - `math_dir` 個別削除ブロック（`:237-243`）を、直後の headings/_epub_assets ループ
     （`:245-254`）へ `'math'` を加える形で統合（＝legacy 残骸掃除へ格下げ。コメントも
     「P4b で workspace 化済み」へ更新）。
   - `--cache` 分岐のルート `_index_matches.yml` 削除（`:167-171`）は legacy 掃除を兼ねて
     現状維持（`.cache/vs` の rm_rf が新配置を掃除する）。V2.0 撤去対象としてコメント付記。

---

## 3. 段階実装（各段で独立コミット・出力同一性を検証）

1. **数式 SVG の workspace 化**（§2.1〜2.4）: MathTransformer・PdfBuilder ステージ・
   EpubBuilder ローカライズ・Techbook 解決基準・関連ユニットテスト更新。
   検証: `rake test` 全緑＋実ビルド突き合わせ（PDF 全ページテキスト＋MediaBox 一致・
   EPUB 内ファイルのバイト同一（差分は dcterms:modified のみ）・KPF 生成成功）・
   ビルド後ルートに `images/math/` が無いこと（--no-clean 時は workspace 内に在ること）。
2. **`_index_matches.yml` の移設**（§2.5）: 定数化＋書き手/読み手更新。
   検証: 索引ありビルドで `_indexpage.html` / `_glossarypage.html` の内容不変・
   `vs index` 系コマンドの単独実行が従来どおり動くこと。
3. **掃除系の縮退＋テスト前提更新**（§2.6・§4）: final clean 簡素化・clean.rb 再編・
   `workspace_structure_test` の格上げ。検証: `rake test:release` 全緑。

（1 と 2 は独立。まとめて 1 セッションで実装してよいが、コミットは分けること。）

---

## 4. テスト影響

| テスト | 変更 |
|---|---|
| `math_transformer_test.rb`（`:55, :68, :114, :138, :151, :163` ほか） | 生成先 glob を `BUILD_HTML_DIR` 配下へ・src アサーションを `images/math/…`（prefix 無し）へ |
| `workspace_structure_test.rb` | `ROOT_POLLUTION_GLOBS`（`:42-49`）へ `images/math` と `_index_matches.yml` を**追加**（「現行仕様のため対象外」コメント `:40-41` を削除）。WS-02 系に「html/ 配下に `images/math/` が生成される（数式が存在する場合）・pdf/ にミラーされる」検査を追加 |
| `target_consistency_test.rb`（`:331` 付近） | `reset_intermediate_state!` の images/math 掃除は衛生措置として残置可・コメント更新 |
| `epub_flavor_test` / `epub_kindle_layout_test` | fixture の src は既に `images/math/…`（dir 相対）→ **無修正で通る見込み**。確認のみ |
| `index_match_scanner_test` / `unified_page_builder_test` | 生成/読込パスを `Common::INDEX_MATCHES_FILE` 前提へ |
| 新設（任意） | `stage_workspace_htmls!` の images ミラー・`copy_asset_tree!(dest_root:)` のユニットテスト |

---

## 5. 完了条件（固有）

1. 通常ビルド（clean あり）の後、ルートに `images/math/` と `_index_matches.yml` が
   存在しない。`--no-clean` 時は両者が `.cache/vs/build/` 配下に揃う。
2. `run_final_clean` が `rm_rf BUILD_DIR`（＋ログ）だけになっている。
3. 実ビルド突き合わせ: PDF（閲覧用・入稿用）全ページテキスト＋MediaBox 一致・
   クリーン EPUB 内ファイルのバイト同一（dcterms:modified 除く）・epubcheck 0/0・
   KPF 生成成功（Error 0）。数式を含む章（例: 94-sample 系 fixture）で
   PDF・EPUB 双方に数式画像が描画されていることを目視または抽出で確認。
4. `rake test:release` 全緑（workspace_structure_test の格上げ分を含む）。
5. `vivlioverso-p4-investigation.md` §8 と `pipeline.rb` / `clean.rb` の
   「P4b」言及コメントを完了状態へ更新。CHANGELOG に記載。

---

## 6. スコープ外（明示）

- **`stylesheets/fonts/google-fonts.css`**: FontManager が生成するが **git 管理下の
  著者資産ディレクトリに置かれ、page-settings.css の `@import` から固定相対で参照される**
  （`epub_builder.rb:62` 参照）。「生成 HTML からの参照」ではなく「ソース CSS からの参照」で
  あり、移設はテーマ CSS 側の書換（P3 の領分）を伴う別問題。V2.0 テーマシステムで扱う。
- **`_index_review.md` / `_index_glossary_review.md`**: 著者レビュー用の意図的なルート生成物
  （P4 §1.3）。移設しない。
- **数式レンダリングの永続キャッシュ**（`.cache/vs/math/` に SHA 名で保持しビルド間で
  再利用・毎ビルドの Node+MathJax 再実行を省く）: 本書の workspace 化とは独立の
  性能改善。content-addressed なので安全に足せる。必要になったら別個票で
  「キャッシュに描画 → workspace へ選択コピー」の 2 層にする。
- ルート `vivliostyle.config.js` / `entries.js`（P3-4 個票
  [vivlioverso-p3-4-config-fullgen-spec.md](vivlioverso-p3-4-config-fullgen-spec.md) の領分）。
