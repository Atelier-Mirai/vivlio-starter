# VivlioVerso 基盤整備 個別改修計画 P1〜P5（第 3 部）

対象: 各個票に記載 / 策定日: 2026-07-03 /
ステータス: **P1 実装完了（2026-07-03）・P2〜P4 実装待ち（実装担当: Opus 4.8）・P5 は V2.0 の依存マップ**

第 1 部 = [vivlioverso-build-investigation.md](vivlioverso-build-investigation.md)（現状調査）、
第 2 部 = [vivlioverso-foundation-plan.md](vivlioverso-foundation-plan.md)（基本構想）。

> **実装者への共通指示**
> - 各個票は独立に実装・コミットできる。1 個票 = 1 セッションを推奨。
> - 完了条件は共通で「`rake test` / `rake test:standard` 緑・rubocop クリーン・
>   実プロジェクトで `vs build`（全ターゲット）実走・出力の同一性確認」＋個票固有条件。
> - 出力同一性の確認は catalog-parser-unification で行った方式
>   （実プロジェクトでビルドし成果物を比較）に倣う。`rake test:targets` があれば併用。
> - 仕様と実装が食い違う場合は実装を止めて報告する（仕様側の誤りの可能性）。

---

## P1: マスキング一元化（`CLI::Masking` 新設）

**課題 B への処方 / 回帰リスク: 小 / 前提: なし**

### P1-1. 新設ファイル

`lib/vivlio_starter/cli/masking.rb` — `IndexCommands::CodeBlockStripper` の
状態機械（可変長・入れ子・`~~~`・`include:` 除外）を移植・一般化した唯一実装。

```ruby
module VivlioStarter
  module CLI
    # Markdown のコード領域（フェンス/インライン）解釈の唯一実装。
    # 仕様: docs/specs/vivlioverso-foundation-workplans.md P1
    module Masking
      module_function

      FENCE = /\A(?:`{3,}|~{3,})/   # 行頭 3 連以上（CodeBlockStripper と同一）

      # (a) コード外の行だけ yield する（行番号は 1 始まりで維持）
      def each_prose_line(text) # { |line, lineno| }

      # (b) コードを除去したテキストを返す（行数維持・インラインは空白化）
      def strip_code(text)

      # (c) コード退避 → 処理 → 復元（プレースホルダ方式）
      def protect_code(text)          # => [protected, spans]
      def restore_code(text, spans)
    end
  end
end
```

- `strip_code` は現 `CodeBlockStripper.strip` と、`protect_code`/`restore_code` は
  現 `MarkdownUtils.extract_code_spans`/`restore_code_spans` と**入出力互換**にする
  （既存テストがそのまま資産になる）。ただしフェンス判定は状態機械へ統一
  （MarkdownUtils の正規表現方式 `/^ {0,3}(`{3,}|~{3,}).*?^ {0,3}\1\s*$/m` は
  入れ子で誤るため置き換える）。

### P1-2. 移行対象と方針（順に 1 コミットずつ）

| # | 対象 | 使う API | 備考 |
|---|---|---|---|
| 1 | `index/code_block_stripper.rb` | 本体を Masking へ移し、旧名は delegate（または呼び出し 2 箇所を直接置換して削除） | 意味論の原器 |
| 2 | `pre_process/markdown_utils.rb` | protect/restore を Masking へ委譲 | プレースホルダ書式は既存互換 |
| 3 | `lint/tokenizer.rb` | each_prose_line | **挙動改善**: `~~~`・入れ子対応が加わる（改善方向の変化として CHANGELOG に記載） |
| 4 | `metrics/analyzer.rb` / `metrics/sentence_collector.rb` | strip_code / each_prose_line | 行番号維持が必須（sentence_collector） |
| 5 | `index/index_match_scanner.rb` | each_prose_line | `include:` 除外の挙動維持 |
| 6 | `pre_process/image_path_normalizer.rb` / `link_image_validator.rb`（4 箇所） | each_prose_line | **挙動改善**: 入れ子誤動作の解消 |
| 7 | `pre_process/frontmatter_generator.rb` / `markdown_transformer.rb` / `cross_reference_processor.rb` | 個別判断 | cross_reference は行種別判定と絡むため、フェンス判定部分のみ Masking の述語を使う形でも可 |

- `guards/code_fence_check.rb` は検証器として独立維持。`FENCE` 定数のみ
  Masking を参照。
- `post_process/html_replacer.rb`（HTML 段階の U+0000 退避）は**対象外**
  （テキスト段階のマスキングとは別問題。現状で凝集している）。

### P1-3. テスト

- 新設 `test/vivlio_starter/cli/masking_test.rb`: 入れ子（`````markdown` 内の
  ```` ``` ````）・`~~~`・`include:`・インラインコード・行番号維持・
  protect→restore の往復同一性。
- **意味論統一の回帰ゲート**: 代表原稿（入れ子フェンスを含む fixture）に対し、
  lint / metrics / index の各経路が「コードとみなす行の集合」を一致させること。

### P1-4. 完了条件（固有）

課題 B 表の #1〜#11 のうち移行済み実装の自前フェンス検出コードが消えていること。
入れ子フェンス fixture で lint が本文を誤ってコード扱いしない（現状はする）こと。

---

## P2: BuildPlan 宣言化（Targets 値オブジェクト＋ステップ表）

**課題 A への処方 / 回帰リスク: 中 / 前提: なし（P1 と独立）**

### P2-1. `Build::Targets` の新設

第 2 部 §1.1 のコードをそのまま実装（`lib/vivlio_starter/cli/build/targets.rb`）。
`UnifiedBuildPipeline#initialize` で 1 回 resolve し ivar に保持
（**ビルド中の reload には追従しない**のが正しい: ターゲット集合はビルド開始時に確定）。

- pipeline.rb の `pdf_target?` 等 4 メソッドを `@targets.pdf` 等へ置換して削除。
- レガシー `output.pdf.targets` フォールバックは Targets.resolve に一本化
  （現状の非対称＝epub/kindle 側にフォールバック無し、は**現挙動を維持**する。
  変更するなら別コミットで明示）。

### P2-2. ステップ表

`register_full_mode_steps` の 5 分岐＋3 補助メソッド
（`register_pdf_build_steps` / `register_print_pdf_only_steps_with_epub` /
`register_epub_only_steps`）を、条件付き 1 テーブルに畳む:

```ruby
Step = Data.define(:label, :handler, :condition)   # condition: Targets を受ける Proc または nil

def full_mode_steps
  t = @targets
  [
    ['clean',                    -> { run_step0_clean },                nil],
    ['optimize images',          -> { run_step1_optimize_images },     nil],
    ['prepare theme images',     -> { Build::ImageOptimizer.prepare_theme_images! }, nil],
    ['preprocess sections',      -> { Build::SectionBuilder.preprocess_sections!(entries) }, nil],
    ['index scan and build',     -> { run_step4_index_processing },    nil],
    ['convert sections html',    -> { Build::SectionBuilder.convert_sections_html!(entries) }, nil],
    ['generate part titles',     -> { Build::PartTitleGenerator.generate_all! }, nil],
    ['techbook post-process',    -> { run_techbook_post_process },     nil],
    ['generate toc html',        -> { Build::TocGenerator.generate_toc_html!('.', entries) }, nil],
    # --- ここからターゲット依存（分岐は condition に吸収） ---
    ['build overall pdf',        -> { Build::PdfBuilder.build_overall_pdf_from_dir!('.', entries) }, ->(t) { t.pdf }],
    ['generate entries.js',      -> { Build::PdfBuilder.generate_entries_for_sections!('.', entries) }, ->(t) { !t.pdf && t.print_pdf }],
    ['snapshot pre-dedup html',  -> { snapshot_pre_dedup_htmls },      ->(t) { t.epub_or_kindle? && t.any_pdf? }],
    ['backlink dedup',           -> { Build::BacklinkDedupOrchestrator.run!(entries) }, ->(t) { t.any_pdf? }],
    ['build front pages',        -> { run_step9_front_pages_and_tail }, ->(t) { t.pdf }],
    ['build front pages (html)', -> { run_step9_front_pages_html_only }, ->(t) { !t.pdf }],
    ['merge all pdfs',           -> { Build::PdfMerger.merge_all_pdfs!(entries) }, ->(t) { t.pdf }],
    ['apply outline',            -> { Build::PdfMerger.add_outline_to_output_pdf!(entries) }, ->(t) { t.pdf }],
    ['compress and rename',      -> { run_step12_rename_only },        ->(t) { t.pdf }],
    ['print pdf',                -> { run_step13_print_pdf },          ->(t) { t.print_pdf }],
    ['generate epub',            -> { run_step_epub },                 ->(t) { t.epub_or_kindle? }],
    ['final clean',              -> { run_final_clean },               nil]
  ]
end
```

> ⚠️ **忠実性が最重要**。上の表は方向性を示す草案であり、実装時は
> **現 5 分岐それぞれが生成するステップ列を全パターン書き出し**、表の評価結果と
> 完全一致することをユニットテストで固定してから置き換える（差があれば表を直す）。
> 特に注意: epub-only 経路は dedup と `merge` を含まない／print_pdf-only 経路は
> Step 9 が html_only 版／`register_epub_only_steps` は toc 生成後すぐ front pages。

### P2-3. 実装分離（同個票内・別コミット）

1. zip 手術 `stabilize_epub_identifier!` / `sanitize_epub_opf_ids!` /
   `stable_project_uuid` → `Build::EpubBuilder` へ移設（呼び出しはステップから）。
2. `run_step13_print_pdf` と print_pdf_* 6 メソッド →
   `Build::PrintPdfBuilder`（新設）へ移設。
3. ステップ番号入りログ文字列（`[Step 13]` 等）はラベル名へ置換。
   `Common.with_current_step_label` の仕組みはそのまま使える。

### P2-4. テスト・完了条件（固有）

- 新設 `pipeline_steps_test.rb`: targets 全 15 組（2^4 − 空 ＋既定）×
  mode(:full/:single/:preflight) について**ステップラベル列のスナップショット**を固定。
  現行実装で列を採取 → 置き換え後に一致を検証（これが回帰ゲート）。
- pipeline.rb が概ね 400 行以下に痩せていること。ターゲット判定の CONFIG 解析が
  resolve 1 回になっていること。

---

## P3: CSS 設定注入層（book-settings.css 生成）

**課題 C への処方 / 回帰リスク: 中 / 前提: なし（P1・P2 と独立）/ テーマシステムの前提**

### P3-1. 生成物の仕様

ビルド時に `.cache/vs/book-settings.css` を**全文生成**する（既存 CSS は不変）:

```css
/* 自動生成: config/book.yml のビルド設定（手編集しない）
   生成器: PreProcessCommands::BookSettingsCss（P3 参照） */
@page { size: 182mm 232mm; }
:root {
  /* page-settings 系（現 build_css_variable_mappings の 22 変数） */
  --page-width: 182mm;  --page-height: 232mm;  --paper-scale: 0.7810;
  --base-font-size: 10pt;  --base-line-height: 17pt;  --letter-spacing: 0em;
  --page-margin-top: 22mm;  /* …以下同様… */
  /* theme 系（現 update_theme_css/update_*_css が書いていた変数） */
  --theme-accent: var(--accent-blue);
  --color-strong: var(--theme-accent);  --color-em-underline: var(--theme-accent);
  --frontispiece-image: url("../../stylesheets/images/…");
  --section-bg-image: …;  --frontispiece-padding: …;
  --appendix-accent-color: …;  --color-preface-accent: …;
  --h3-marker: "♣";  --h4-marker: "♦";
}
```

- 値の**計算ロジックは現 CssUpdater をそのまま流用**（paper_scale・align_max_width・
  folio 配置・フォントスタック整形・Type3 フォールバック等は実証済みの資産）。
  変わるのは「正規表現で既存ファイルへ差し込む」→「テンプレートへ書き出す」だけ。
- 画像 URL は生成ファイルの位置（`.cache/vs/`）からの相対で解決すること
  （`../../stylesheets/images/…`）。**ここが最大の実装注意点**。
  absolute 化（`file://` は不可・プロジェクトルート相対）や、章 HTML から見た
  パス整合を vivliostyle の base URL 仕様で確認しながら決める。
- frontmatter の `link` 配列（`frontmatter_generator.rb:121`）を
  `[theme.css, {kind}.css, book-settings.css, custom.css]` の順に変更。

### P3-2. 撤去と互換

- `CssUpdater` の update_theme_css / update_appendix_css / update_preface_css /
  update_chapter_common_css / update_page_settings_css の**ファイル書き換え部**を撤去
  （値計算部は BookSettingsCss 生成器へ移動）。`awesomebook` 遺物（`css_updater.rb:294`）も削除。
- **既存プロジェクト互換**: 既存プロジェクトの theme.css には過去ビルドの
  書き換え結果（例: 具体色）が残っているが、book-settings.css が後段で同じ変数を
  再宣言するため**上書きされて正しく動く**。scaffold の CSS も無修正で良い
  （プレースホルダ値のままでも生成ファイルが実値を供給）。
- `vs clean` の削除対象に book-settings.css を追加（`.cache/vs/` 配下なら自動)。
- EPUB: `collect_epub_htmls` / copy_asset 系が `.cache/vs/book-settings.css` を
  EPUB へ同梱するよう配線確認（テーマ CSS と同列に扱う）。

### P3-3. chapter.css の header import 切替の解消

現在の `simple-header.css ⇄ image-header.css` 書き換え（`update_chapter_css`）は
以下の**方式 A で解消**する（P3 実装時に B と比較して最終決定して良い）:

- **方式 A（推奨）**: 両 CSS の中身を「`--header-mode` 変数ぶら下がり」に改修し、
  chapter.css は両方を常時 @import。book-settings.css が
  `--header-mode: image`（または simple）を宣言し、各規則は
  `body` 属性 or `:root` 変数分岐で適用。※ Vivliostyle は `@container`/`@supports var`
  が使えないため、実装は「image-header の規則群に `body.vs-header-image` を前置し、
  post_process の BodyClassInjector（既存機構）でクラス注入」が確実。
- 方式 B: frontmatter link に header CSS を動的選択で入れる
  （{kind}.css の @import から header を外す）。CSS 編集は少ないが link 生成が複雑化。

### P3-4. vivliostyle.config.js（本個票では現状維持）

`sync_vivliostyle_config_size!` / `sync_vivliostyle_config_title!` は
**書き換えのまま残す**（JS ファイルで caste ケードの外・被害が小さい）。
V2.0 での config.js 全文生成化を KNOWN 事項として本個票の完了報告に記す。

### P3-5. テスト・完了条件（固有）

- 新設 `book_settings_css_test.rb`: 変数一覧の網羅（**この変数名一覧が
  テーマ互換の公開インターフェース**。第 2 部 §3.4）・値の整形
  （フォントスタック・url クォート・@page size）・相対パス解決。
- 既存 `css_updater_test` の値計算テストは生成器へ引き継ぐ。
- **出力同一性**: 同梱プリセットでの `vs build`（pdf/print_pdf/epub/kindle）出力が
  移行前後で一致（レイアウト回帰なし）。`rake test:layout` 全プリセット緑。
- **編集自由の実証**: theme.css の `--theme-accent` 行を削除したプロジェクトで
  book.yml の theme.color が正しく効くこと（現在は黙って無効になるケース）。
- ビルド後に `git status` で stylesheets/ に差分が出ないこと。

---

## P4: ワークスペース分離（V2.0 開幕タスク）

**課題 D への処方 / 回帰リスク: 大 / 前提: P2（ステップ表）完了を強く推奨**

第 2 部 §4 の方針を実装する。本個票は P1〜P3 完了後に**詳細仕様を別途起こす**
（`.cache/vs/build/{html,pdf,epub,kindle}/` 構成、vivliostyle.config.js の
entry パス、テーマ相対パス、テスト前提の更新）。ここでは完了条件のみ先に固定する:

- `snapshot_pre_dedup_htmls` / `snapshot_chapter_htmls` / `restore_chapter_htmls`
  （pipeline.rb）が**削除**されている。
- final clean の `.keep` 退避ハック（pipeline.rb:429-435）が削除されている。
- entries.js の「Step 9 が上書きするため Step 13 で再生成」（pipeline.rb:493-503）が
  消費者別ディレクトリで不要になっている。
- プロジェクトルートに中間 HTML / `_sections*.pdf` が生成されない。

---

## P5: V2.0 機能群の依存マップ（実装個票ではなく計画）

PLANNED.md のビルド系項目が、P1〜P4 のどれを土台にするかの対応:

| V2.0 機能（PLANNED.md） | 依存 | 土台が効く理由 |
|---|---|---|
| テーマシステム（bunko.css 等の活用） | **P3** | 変数語彙＝公開 IF が確立し、CSS セット差し替えが可能に |
| 小説（挿絵入り・縦書き）対応 | P3・P4 | novel テーマ＋novel 用ステップ表/フレーバの追加で成立 |
| 直接ビルド（`vs build my.md --pdf`） | P2（＋P4） | 「単発 Markdown 用ステップ表」を 1 枚足すだけになる |
| print_pdf の pdf からの導出高速化 | P2 | ステップ表上で「派生ステップ」への差し替えが局所化 |
| ビルドパイプライン全般の見直し | P2・P4 | 本 3 部作そのものが見直しの実体 |
| 会話文記法（characters.yml） | P1 | 「コード内では無効」が Masking で自動保証 |
| VFM 設定のエントリーレベル適用 | （独立） | config.js 全文生成化（P3-4 の残課題）と同時が効率的 |
| 改ページ制御の改善（空白ページ対策） | P1（lint 案の場合） | each_prose_line で「--- 直後の見出し」検出が容易 |

### 推奨着手順（再掲）

```
1.x 系:  P1（マスキング）→ P2（BuildPlan）→ P3（CSS 注入層）   ※相互独立・順序入替可
V2.0:    P4（ワークスペース分離）→ P5 機能群
```
