# 変更履歴（Changelog）

このファイルには、本プロジェクトの主な変更内容を記録します。

記法は「Keep a Changelog」に基づき、Semantic Versioning（セマンティックバージョニング）に準拠します。

### Pre-release Checklist
- gem 公開時には `vivlio-starter.gemspec` の summary/description が現行仕様に即しているか再確認する。
- `pre_process.rb` で参照する theme.css テンプレート（`lib/project_scaffold/stylesheets/theme.css`）が gem に同梱されているか確認する。
- リリースノートの作成

#### 既知の不具合（未修正）

（現在なし）

#### 実装済み
- [High] **sideimage 内の脚注URLの重複表示を修正**: 根本原因は Vivliostyle が、脚注参照リンク（`<a href="#fnN">`）の解決先が `aside.page-footnote`（`float: footnote`）自体になっている場合に、参照のあるページと `aside` のあるページの両方へ同じ脚注を描画することだった。通常の段落脚注は参照直後の不可視 `span#fnN`（`page-footnote-inline`）が解決先になるため無事だった。sideimage 経由の脚注にも同様の不可視 span を挿入し（`process_sideimage_footnotes!`）、`aside` を sideimage コンテナ直後に配置することで、重複が解消されると同時に、脚注が参照と同じページの下部に正しく表示されるようになった（`page-footnote-endnote` によるセクション末尾表示は廃止）。詳細は `docs/footnote.md` を参照。
- [High] **テーブル内リンクの脚注URLの重複表示を修正**: 原因は上記と同一。テーブルセル内の参照は `<p>` を持たないため不可視 span が挿入されず、参照リンクの解決先が `aside` 自体になり重複描画されていた。段落外参照（`insert_print_footnote_after_anchor!`）でも参照直後に不可視 span を挿入するように修正。あわせて、VFM 2.x がテーブルセル内から参照される脚注の**定義本文を入れ替えて出力する**不具合（参照IDの対応は正しいまま、別の脚注のURLが本文に入る）への対策として、参照直前の外部リンクURLと定義本文を照合して修復する `repair_table_footnote_definitions!` を追加（自動生成されたURL脚注のみ対象。手書きの脚注本文には触れない）。
- [High] **画像の配置（`align=left` / `align=center` / `align=right`）の乱れを修正**: `figure.align-left` / `figure.align-right` / `figure.align-center` に `clear: both` を追加し、配置指定付き図版が直前の float に巻き込まれないようにした。また `chapter-common.css` に残っていた旧 `.float-right` 互換ルール（`align-right` 図版へ `float` と `inline-size: 17em` を強制）を削除。左右配置のテキスト回り込みは従来どおり機能する。
- [Medium] CLI ロード構造のリファクタリング（`docs/specs/cli_loader_refactor_spec.md` 準拠）: `startup.rb` / `loader.rb` 分離、`help.rb` 削除、`commands/new.rb` 廃止、二バイナリの `exit` 統一。`Unreleased > Changed` に詳細記載。
- [High] リンク・画像の自動検証（`vs build` 統合、`--verify-links` / `--no-verify` オプション、`book.yml` 設定対応）
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
- [High] プロジェクト生成時に、project_scaffold/ を生成する。
- [High] vs new で、プロジェクト生成時に、scaffold以下の資産が新プロジェクトに展開され、著者が執筆の参考となるよう、書き方の例として、vivio-starterのマニュアルを展開する。
- [Medium] CSS カスタマイズ性の改善: 現状、`stylesheets/theme.css` はビルド時に `pre_process` によって自動生成・上書きされるため、著者が直接 CSS を編集してもビルドのたびに元に戻る。`book.yml` の `theme` セクションで色・扉絵などを設定する方式は維持しつつ、著者が追加 CSS を安全に記述できる仕組み（上書きされないオーバーライド用ファイルなど）を検討する。 => custom.css実装済み


### Planned

**記法・置換ルール（次期リリース候補）**
- [Medium] 編集者コメント `@comment:...@commend` の一括除去オプション: 現状は `post_replace_list.yml` により `<span class="hen-comment">...</span>` へ変換され、CSS（`stylesheets/replace-list.css` の `.hen-comment`）で色付け表示されるだけで、本文から除外する手段がない。本番ビルド向けに `vs build --strip-comments`（仮）や `book.yml` の `build.strip_editor_comments: true` 設定などで、PDF 出力時に `.hen-comment` 要素をまとめて除去（または `display: none` 注入）する仕組みを検討する。`contents/23-replace-list.md` §編集者コメントの記述（「ビルド時にまとめて消したりできます」）は現状では先取りの表現なので、実装時に本節の表現と整合を取ること。
- [Medium] リスト項目の絶対配置＋SVG ガイド線記法（`post_replace_list.yml`）: `@lu/@ld/@ru/@rd/@ur/@ls/@rs/@us/@ds` で `<li>` を絶対配置しつつ L 字・水平・垂直の SVG ガイド線を自動生成する機能。ルール自体は実装済みだが、(1) 親要素を自動で `position: relative` 化する標準クラスの提供、(2) 座標系・単位（mm/%）の整理、(3) 図解ページ向けプリセット（例: `.figure-guides` コンテナ）の正式化、(4) 印刷プレビューでの視覚検証、が未完了のため今回は対応外とする。サンプル（`81-replace-list-sample.md` §9）と `stylesheets/replace-list.css` のコンテナ定義は次期リリースで正式サポート予定。

**ビルド高速化**
- [High] Step 8（backlink dedup）の抜本的な高速化: 現状は「vivliostyle preview で全416ページをブラウザレンダリング（~150秒）→ Playwright でページ番号取得 → vivliostyle build で PDF 再生成（~196秒）」という2段階構成で、合計 ~350秒を要する。vivliostyle CLI がページ番号情報を JSON 等で出力する機能を持てば Playwright フェーズを丸ごと省略できる。

**将来のメジャーバージョンアップ時の検討事項**
- [Low] CLI 終了コードの体系的な整理: 現状は「問題なし → 0、問題あり → 1」の2値だが、UNIX ツールの慣例（例: `grep` は「見つかった → 0 / 見つからなかった → 1 / エラー → 2」）に倣い、エラー種別ごとに終了コードを分けることを検討する。影響範囲が広いため、後方互換性を破るメジャーバージョンアップのタイミングで対応する。
- [Medium] `vs preflight` の章別エラー・警告サマリー表示: 現状は各ファイルの処理中にリアルタイム出力されるため、章をまたいで混在する。章ごとに「21章: 警告 N 件、エラー N 件」とまとめて表示するには、`LinkImageValidator` にコードインクルード・クロスリファレンス・QueryStream のエラーも蓄積する汎用メカニズムが必要で、影響ファイルが4〜5件に及ぶ。

**あると良いが、リリース後でも可**
用語集テンプレートの標準添付 [Medium] — 便利ですがリリースブロッカーではありません
VFM 設定のエントリーレベル適用 [Medium] — 現状でも動作しているため、後方互換で後から対応可能
テーマシステムの実装 [High] — 小説用縦書きなどは大きな機能追加。v1.0 後のメジャーアップデートとして取り組むのが現実的
Post-processing 単体テスト整備 [Medium] — リリース品質の信頼性向上に有効ですが、現在のテスト（740件）で基本的なカバーはできています

**リリース後で十分**
単章ビルドのリファクタリング、リスト体裁改善、Data オブジェクト拡張、画像 width 自動補完、脚注サポート、Web アプリ連携、CI パイプラインなど

#### ビルド/出力
- [High] 単章ビルドシステムのリファクタリング: 現在実装済みの単章ビルドtargets対応は機能的に完備しているが、コード構造の整理と保守性向上のためのリファクタリングを実施。ステップ登録ロジックの最適化、メソッド責務の明確化、テストカバレッジの拡充を含む。
- [High] 日本語表記・組版Lint（スタイルガイド）
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
- [Low] Web アプリ連携機能: `codes/` ディレクトリに配置した HTML/JS/CSS のサンプルコードを、書籍内で QR コードや URL として紹介する仕組みの検討。PDF 生成がメインの用途から外れるため優先度は低いが、インタラクティブなサンプルを書籍と連携させる将来的な拡張として記録しておく。
- [High] 11-install.mdなどを、著者の使い方や、書き方の例として、書き直す。
- [High] tamplates/chapter.mdなどを、書き方の例として書き直す

#### 品質・テスト
- [Medium] Post-processing単体テスト整備: `_postReplaceList.json`の主要ルール（段落クラス付与、見出し・bodyクラス、各種クレンジング）のスナップショットテストを追加。想定外パターン（複数ブレース、引用符・バックスラッシュ混入等）の回帰防止。
- [Low] 自動検証パイプライン（CI）: 最小サンプルでのビルド、Lint、HTMLポスト処理テストの自動実行。

**堅牢性テスト（追加候補）**
- [Medium] 11-3: 巨大 YAML anchor の Billion Laughs 評価（`aliases: true` 下でも Psych 5.x の制限で実害なしだが、上限値・挙動の明示的な検証余地あり）
- [Medium] 11-4: PDF 結合時 hexapdf 例外で中間 PDF を事後調査用に残す（`pdf_merger.rb` の例外ハンドリング強化）
- [Medium] 12-2 / 12-3: 冪等性・キャッシュ回帰（同一入力で複数回ビルドしても成果物が変化しないことの検証）
- [Medium] vivlio-starter-pdf の堅牢性調査・テスト整備（vivlio-starter と同等の堅牢性テストを vivlio-starter-pdf にも適用）

**1.0.0 リリース準備**
- [High] CHANGELOG の整備
- [High] リリースノート作成
- [High] README の整備。文章をOpusで推敲。SVGロゴに変更。ロゴに込めた思いも。
- [High] ドキュメントの整備。Opusで推敲。
- [High] contents等をscaffoldにコピー

## unreleased

### Added
- **`vs pdf:pages` / `vs pdf:rasterize` コマンドを追加** (`lib/vivlio/starter/pdf/pdf_to_jpeg.rb`, `lib/vivlio/starter/pdf/jpeg_to_pdf.rb`, `lib/vivlio/starter/cli/pdf.rb`, `lib/vivlio/starter/cli/samovar/pdf_command.rb`): `pdftoppm` による PDF ページの JPEG 切り出しと、外部依存なしの独自実装 `JpegToPdf` による全ページラスタライズ PDF 再結合に対応。`pdf:pages` は `--dpi` / `--quality` / `--pages` / `--output` を、`pdf:rasterize` は `--dpi` / `--quality` / `--clean` を受け付ける。`vs --help` と `vs doctor` にも関連コマンド・外部依存 (`pdftoppm`) を追加し、単体テストとコマンドロジックテストを整備。

### Changed
- 名前空間およびディレクトリ構造を `Vivlio::Starter`（サブコンポーネントを含めて3階層、例: `Vivlio::Starter::CLI`）から `VivlioStarter`（2階層、例: `VivlioStarter::CLI`）へと一階層フラット化（浅く）した。
- **PDF 関連ソースを `cli/pdf/` 配下に集約** (`lib/vivlio_starter/cli/pdf/pdf_to_jpeg.rb`, `lib/vivlio_starter/cli/pdf/jpeg_to_pdf.rb`, `lib/vivlio_starter/cli/pdf.rb`, `test/vivlio_starter/cli/pdf/`): 従来 `lib/vivlio_starter/pdf/` と `lib/vivlio_starter/cli/pdf/` に分散していた PDF 関連ファイルを、名前空間（いずれも `VivlioStarter::Pdf`）と一致するよう `cli/pdf/` 配下へ統合した。`pdf_to_jpeg.rb` / `jpeg_to_pdf.rb` を移動し、`require_relative` とテスト配置を追従。プラグイン `vivlio-starter-pdf` 側も同様に `reader.rb` / `version.rb` を `cli/pdf/` へ移動し、不要だったシム `pdf/utilities.rb`（実装は `cli/pdf/utilities.rb` に集約済み）を削除。技術的必然性はなく、ディレクトリと名前空間の不一致を解消する整理。
- **プラグインのインデント整形** (`vivlio-starter-pdf`): 名前空間の 3 階層→2 階層化の名残で `module Pdf` 配下が 2 スペース過剰インデントになっていた `cli/pdf/` 配下の各ファイルを揃え、`ruby -w` の "mismatched indentations" 警告を解消。

### Fixed
- **sideimage 内リンクの脚注URLが重複表示される不具合を修正** (`lib/vivlio_starter/cli/post_process/footnote_converter.rb`, `lib/vivlio_starter/cli/post_process.rb`, `stylesheets/components.css`, `lib/project_scaffold/stylesheets/components.css`): 根本原因は、脚注参照リンク（`<a href="#fnN">`）の解決先が `float: footnote` の `aside` 自体である場合に、Vivliostyle が参照のあるページと `aside` のあるページの両方へ同じ脚注を描画することだった。通常の段落脚注は参照直後の不可視 `span#fnN`（`page-footnote-inline`）が解決先になるため無事だった。sideimage 経由の脚注にも同様の不可視 span を挿入し（`process_sideimage_footnotes!`）、`aside` を sideimage コンテナ直後に配置（`move_body_asides_near_references!`）。これにより重複が解消されると同時に、脚注が参照と同じページの**下部**に番号順で表示されるようになった（`page-footnote-endnote` によるセクション末尾へのブロック表示は廃止）。詳細は `docs/footnote.md` を参照。
- **テーブル内リンクの脚注URLが複数回（3回など）重複表示される不具合を修正** (`lib/vivlio_starter/cli/post_process/footnote_converter.rb`): 原因は上記と同一。テーブルセル内の参照は `<p>` を持たないため不可視 span が挿入されず、参照リンクの解決先が `aside` 自体になり重複描画されていた。段落外参照（`insert_print_footnote_after_anchor!`）でも参照直後に不可視 span を挿入するよう修正。あわせて、VFM 2.x がテーブルセル内から参照される脚注の**定義本文を入れ替えて出力する**不具合（参照IDの対応は正しいまま、別の脚注のURLが本文に入る）への対策として、参照直前の外部リンクURLと定義本文を照合して修復する `repair_table_footnote_definitions!` を追加（自動生成されたURL脚注のみ対象。手書きの脚注本文には触れない）。回帰テスト（`test/vivlio_starter/cli/post_process/footnote_converter_test.rb`）を新設。
- **画像の配置（`align=left` / `align=center` / `align=right`）が乱れる不具合を修正** (`stylesheets/layout-utils.css`, `stylesheets/chapter-common.css`, `lib/project_scaffold/stylesheets/` 同名ファイル): `align=left` の float に後続の `align=center` / `align=right` 画像が巻き込まれ、レイアウトが連鎖的に崩れていた。`figure.align-left` / `figure.align-right` / `figure.align-center` に `clear: both` を追加し、配置指定付き図版が直前の float を解除してから配置されるようにした。また `chapter-common.css` に残っていた旧 `.float-right` 互換ルール（`align-right` 図版へ `float` と `inline-size: 17em` を強制し `width` 指定と競合）を削除。左右配置のテキスト回り込みは従来どおり機能する。
- **PDF アウトラインの巻末・本文ブックマークが目次ページに飛ぶ不具合を修正** (`lib/vivlio_starter/cli/build/outline_extractor.rb`, `lib/vivlio_starter/cli/build/pdf_merger.rb`): 「終わりに」（後書き）等のしおりをクリックすると、本来のページではなく目次ページ（同名項目が一覧に並ぶ）へ飛ぶ問題を解決。原因は (1) 前付ページ位置のハードコード（タイトル=1 / 権利=2 / 前書き=3）が `output.pdf` 先頭に結合される表紙 PDF 分のオフセットを考慮していなかったこと、(2) 目次・巻末（用語集／終わりに／索引）の位置をタイトル文字列の全文検索で求めていたため、前書き本文中の語や目次の一覧へ誤マッチしていたこと。表紙ページ数を `front_matter_offset` として算出してアウトラインの基点（`start_page`）に反映し、目次・巻末は「ページ先頭行が見出しと一致するページ」として検出するよう変更。実 PDF で 目次=p.8 / 第1章=p.12 / 終わりに=p.20 と各見出しページへ正しく飛ぶことを検証。
- **`vivlio-starter-pdf` がインストール済みでも Enhanced モードへ自動切替されない不具合を修正** (`lib/vivlio_starter/cli/pdf/provider.rb`, `test/vivlio_starter/cli/pdf/provider_mode_test.rb`): 名前空間リファクタリング後、プラグインが常時検出されず Standard モードに固定される問題を解決。`vs build` は Bundler 配下（`bundle exec`）で実行されるため、書籍プロジェクトの Gemfile に未記載のシステムインストール済み gem が `$LOAD_PATH` から除外され、`require` が失敗していた。gemspec をディスクから直接読み取り（Bundler のバンドル制限を受けない）、プラグインと依存 gem の require パスを動的に注入して再試行することで、`gem install vivlio-starter-pdf` 済みなら Gemfile を編集せずとも自動的に Enhanced モード（HexaPDF によるしおり付与・高精度ノンブル）へ切り替わるようにした。動作モードは `:enhanced` / `:standard` / `:disabled` のパターンマッチで整理し、切替を検証する統合テストを追加。`lib/project_scaffold/Gemfile` のコメントも「gem install のみで自動有効化」へ更新。
- **プラグイン実行ファイルの旧名前空間を修正** (`vivlio-starter-pdf` `exe/vivlio-starter-pdf`): `require 'vivlio/starter/pdf'`・`module Vivlio::Starter::PDF` の旧名前空間のままで壊れていた CLI を、新名前空間 `VivlioStarter::Pdf` へ修正（`vivlio-starter-pdf --version` が正しく動作）。
- **`vs doctor --fix` でローカルの Playwright 用 Chromium がインストールされない不具合を修正** (`lib/vivlio_starter/cli/doctor.rb`, `test/vivlio_starter/cli/doctor_commands_test.rb`): ローカルの `node_modules/playwright/cli.js` に実行権限（`+x`）が付与されていない場合、`npx` がグローバルの Playwright を優先して実行してしまい、グローバルに Chromium がインストール済みだと何もダウンロードされず終了する問題を解決。`doctor --fix` 実行時に `node_modules/playwright/cli.js` が存在する場合は `node` コマンド経由で直接ローカルの CLI を呼び出してインストールを実行し、ローカルの Playwright バージョンに対応した正しいリビジョンの Chromium が確実にダウンロードされるよう修正。関連する単体テストを追加。
- **Techbook PDF の Type 3 フォント混入を解消** (`lib/vivlio/starter/cli/techbook/processor.rb`, `lib/vivlio/starter/cli/techbook/emoji_replacer.rb`, `lib/vivlio/starter/cli/build/pipeline.rb`, `lib/vivlio/starter/cli/build/pdf_builder.rb`, `stylesheets/image-header.css`, `lib/project_scaffold/stylesheets/image-header.css`): Chromium / Vivliostyle の PDF 生成で CSS generated content・SVG・特殊記号・`-webkit-text-stroke` 由来の Type 3 フォントが混入する問題を修正。Techbook 後処理を `post_process_html_files!` に集約し、SVG 参照の WebP 化、h3/h4 マーカーのテーマ色付き WebP 化、丸数字・副題波線の WebP 化、絵文字画像の `img.vs-emoji` 枠線打ち消し、Step 9 後の特殊ページ再処理を実装。`--code-font` 未定義による Osaka fallback を回避し、Type 3 を再発させる `.section-topic h2 .section-number` の `-webkit-text-stroke` は全出力形式で見た目差が出ないようコメントアウト。調査・検証手順を `docs/specs/svg_luster_bugfix_technical_notes.md` に記録。
- 新規に `vs new`  で作成したプロジェクトでも、すべての絵文字が画像へと正しく置換されるよう、`lib/project_scaffold/stylesheets/twemoji/` 配下に絵文字画像を配置するように修正。
- **見出し記号の`h3`、`h4`が `♣` / `♦` 以外の文字（例：🌸）であっても、画像化されるよう修正** 🌸 (cherry blossom) の場合、Twemojiのベクター素材から `stylesheets/twemoji/vs-techbook/marker-h3.svg` に書き出される（🌸なので強制 recolor はせずオリジナルカラーのまま）。その後、高画質なラスタライズ処理により `stylesheets/twemoji/vs-techbook/marker-h3.webp` という WebP 画像ファイルへと自動変換される。

## [1.0.0-beta] - 2026-04-26

### Added
- **`long-table` / `table-scroll` コンテナの pre_process 変換** (`lib/vivlio/starter/cli/pre_process/markdown_preprocessor.rb`, `lib/vivlio/starter/cli/pre_process/markdown_transformer.rb`): `:::{.long-table}` および `:::{.table-scroll}` コンテナ内のパイプテーブルを、`table-rotate` と同様に pre_process パイプラインで HTML テーブルに変換するよう実装。従来は VFM に変換を委ねていたが、VFM がコンテナ内のパイプテーブルを `<table>` に変換しないケースがあり、テーブルが崩れて表示されていた。`convert_table_container_inner_markdown` を汎用メソッドとして新設し、`convert_table_rotate_inner_markdown` はこれに委譲するよう変更。

### Changed
- クロスリファレンスのエラー・警告出力を整形。ラベルID重複は `🔴 25-cross-reference.md:361 - ラベルID '画像(左寄せ) @img-left' は重複しています` の形式でIDごとにまとめ、重複箇所をファイル別に `detail:` で表示。孤立ラベルは `🟡 25-cross-reference.md:329 - 孤立ラベル '複雑な表 @complex-table' は未参照です` の1行形式で表示。ラベルの行番号を連番から実際の行番号に修正。孤立ラベル検出を `catalog.yml` 登録済み全章を対象に実施。
- `docs/specs/logging_spec.md` に基づきログ出力を全面改修。`log_warn` / `log_error` / `log_summary` に `detail:` キーワード引数を追加し、2行目以降を `DETAIL_INDENT`（8スペース）でインデントして出力する形式に統一。画像不在・コードインクルード不在・裸URL・危険スキーム・QueryStream エラーの各警告/エラーを新形式に移行。`format_detail` を内部ヘルパー（`private`）として追加。`link_image_validator.rb` の `print_summary` を `log_summary(msg, detail:)` 1回の呼び出しに集約。
- `Common` のログ出力メソッドを整理・統一。`echo_always` を `log_always` にリネームし、`log_summary`（集計サマリー常時表示）・`log_inspection`（詳細診断、info 以上）・`log_result`（最終結果、`status:` でアイコン選択）を新設。`lint.rb`・`spell_checker.rb`・`new.rb`・`rename.rb`・`create.rb`・`index/review_queue_manager.rb` 等で直接使われていた `puts` / `warn` を `Common.log_*` に統一。各メソッドに表示条件とアイコンを説明するコメントを追加。
- `vs preflight` / `vs build`: コードインクルードでソースファイルが見つからない場合のエラー表示を改善。`❌  13-new.md:157 - ソースコード 'sample.rb' が見つかりません` のように、画像警告と同じ形式（ファイル名・行番号・ファイル名）で表示するよう変更。また、このエラーを `vs preflight` の終了コード・「問題あり/なし」判定に反映するよう修正。
- `vs preflight`: 完了メッセージから所要時間を削除。`✅ Preflight 完了: 問題なし` のようにシンプルな表示に変更。
- `vs build`: 完了メッセージに所要時間を統合。`📚 12-quickstart.pdf を作成しました (4.6s)` の形式で表示。`--log=debug` 時は従来どおりステップ別の詳細タイミングテーブルを表示。 (`lib/vivlio/starter/cli/startup.rb`): Ctrl+C（SIGINT）や SIGTERM 受信時に Ruby デフォルトのスタックトレース表示を抑止し、`⚠️ 処理が中断されました` のシンプルなメッセージを表示してから UNIX 規約の終了コード（128 + signo: SIGINT なら 130、SIGTERM なら 143）で終了する。既存の `ensure` ブロック（`lint.rb` の一時ファイル削除、pipeline.rb の各種後片付け等）は Interrupt 伝播中に通常通り実行されるため、中断時のクリーンアップは保証される。rescue は `Interrupt` / `SignalException` / `Exception` の 3 段に分け、それぞれを `handle_interrupt` / `handle_signal` / `handle_unexpected_error` ヘルパーに抽出して `Metrics/AbcSize` 違反を発生させずに構造化した。
- **並列ビルドの排他ロック（`BuildCommands::BuildLock`）** (`lib/vivlio/starter/cli/build/build_lock.rb`, `lib/vivlio/starter/cli/samovar/build_command.rb`): 同一プロジェクトで `vs build` が多重実行された場合の中間生成物破壊を防ぐため、`.cache/vs/.build.lock` に対し `File::LOCK_EX | File::LOCK_NB` でフロックを取得する仕組みを新設。競合時は `AlreadyLockedError` を即座に送出し（待機せず即エラー終了）、`vs build` の終了コードを 1 とする。ロックファイルには取得プロセスの PID と開始時刻（ISO 8601）を書き込むため、残存ロックの原因追跡が可能。`ensure` で `LOCK_UN` と `rm_f` を実行するため正常終了時は残らず、`kill -9` 等の強制終了時も OS が flock を解放するため次回起動時の取得は可能。リグレッションテスト 5 件（`test_acquires_and_releases_lock` / `test_returns_block_value` / `test_releases_lock_on_exception` / `test_raises_when_already_locked` / `test_writes_pid_to_lock_file`）を追加。
- **`book.yml` 主要キーのバリデーション** (`lib/vivlio/starter/cli/common.rb`, `test/vivlio/starter/cli/common_validate_book_config_test.rb`): `Common.validate_book_config!` を新設し、`reload_configuration!` の冒頭で `book.main_title` / `book.author` / `project.name` の欠落を検査。欠落があれば `[book.yml] 警告: 以下の推奨キーが未設定です: …` と stderr に警告を出し、空欄になる値の影響（PDF タイトル・著者・出力ファイル名）を明示する。既存の最小構成プロジェクトとの互換性を保つため `abort` はせず、警告のみで処理を継続する。空文字列・空白のみ・`nil` のいずれも blank 扱い。リグレッションテスト 5 件を追加。
- **`<!-- vs-lint-disable -->` 未クローズ時の警告** (`lib/vivlio/starter/cli/lint/tokenizer.rb`, `lib/vivlio/starter/cli/lint/spell_checker.rb`): `build_excluded_lines` が未クローズ disable の開始行番号も返すように戻り値を変更し（`[Set<Integer>, Integer?]` タプル）、`tokenize` で `path:` 引数を受け取って `warn_unclosed_disable` を呼び出すよう拡張。`<!-- vs-lint-disable -->` が `<!-- vs-lint-enable -->` で閉じられないままファイル末尾に達した場合、`[vs-lint] 警告: path:2 の <!-- vs-lint-disable --> が <!-- vs-lint-enable --> で閉じられていません。ファイル末尾まで lint が無効化されます。` を stderr に出す。リグレッションテスト 3 件（未クローズ警告 / 閉じた場合は警告なし / path 省略時は `line N` 表記）を追加。
- **フロントマター未クローズ時の警告** (`lib/vivlio/starter/cli/pre_process/frontmatter_generator.rb`, `lib/vivlio/starter/cli/pre_process/markdown_preprocessor.rb`, `lib/vivlio/starter/cli/pre_process.rb`): `FrontmatterGenerator.apply_frontmatter` に `path:` 引数を追加し、開始 `---` に対応する閉じ `---` がコードフェンス外に見つからない場合に `warn_unclosed_frontmatter` で警告を出す。`[frontmatter] 警告: contents/99-draft.md のフロントマター開始 \`---\` に対応する閉じ \`---\` がコードフェンス外に見つかりません。フロントマターは適用されず、本文として扱われます。` と stderr に出し、PDF 生成物に YAML テキストがそのまま流れ込む事故を未然に防ぐ。`MarkdownPreprocessor#apply_frontmatter!` から `context.source_path` を伝播。リグレッションテスト 2 件を追加。
- **テーマカラーの選択肢を17色から12色に削減** (`lib/vivlio/starter/cli/pre_process/css_updater.rb`, `lib/vivlio/starter/cli/pre_process/frontmatter_generator.rb`, `config/book.yml`, `lib/project_scaffold/config/book.yml`, `contents/41-book-yml.md`, `contents/42-frontispiece.md`, `lib/project_scaffold/contents/34-book-yml.md`, `lib/project_scaffold/contents/19-frontispiece-ornament.md`): `ALLOWED_COLORS` 定数から `amber`, `peach`, `coral`, `plum`, `mint` の5色を削除。残りの12色は `yellow`, `orange`, `red`, `magenta`, `purple`, `indigo`, `navy`, `blue`, `cyan`, `teal`, `green`, `lime`。関連するドキュメントのカラーパレット表・トラブルシューティング記述も同期更新。

### Fixed
- **`:::` コンテナ記法で `:::` と `{` の間にスペースがあると変換されない問題を修正** (`config/post_replace_list.yml`): `::: {.column}` のように `:::` と `{` の間にスペースを入れた場合、`post_replace_list.yml` の正規表現がマッチせず `<div>` に変換されなかった。正規表現に `\\s*` を追加してスペースを許容するよう変更。VFM の仕様に準拠した記法がすべて正しく変換されるようになった。
- **`:::` フェンス内の画像が画像パス正規化・欠落チェックから漏れる問題を修正** (`lib/vivlio/starter/cli/pre_process/markdown_utils.rb`): `extract_code_spans` のフェンスブロック退避正規表現が `` ```include:file.rb``` `` のようなインクルード記法をフェンスブロックの開始と誤認識し、次の `` ``` `` までの広範囲を退避してしまっていた。これにより `::: {.img-text}` 等のコンテナ内の画像記法が `fix_image_paths` の処理対象から外れ、欠落画像のエラー検出と代替画像への置換が行われなかった。`` ```include: `` で始まる行をフェンスブロックの開始から除外するよう変更。
- **`.img-text` / `.text-img` 系コンテナで画像とテキストが横並びにならない問題を修正** (`stylesheets/layout-utils.css`): VFM が `![](...)` を `<figure><img></figure>` に変換するため、CSS Grid の `> img` セレクタが `<figure>` 内の `<img>` にマッチせず、画像とテキストが上下にずれて表示されていた。セレクタに `> figure` を追加し、`figure` のマージン・パディングをリセット、内部の `img` を `width: 100%` に設定。`.img-text`、`.img-text2`、`.img-text3`、`.text-img`、`.text2-img`、`.text3-img` のすべてに適用。
- **付録の章番号レター（A/B/C...）が catalog.yml の順番と一致しない問題を修正** (`lib/vivlio/starter/cli/common.rb`, `lib/vivlio/starter/cli/post_process/heading_processor.rb`): `appendix_number_to_letter` が章番号から直接レターを計算していたため（90→A, 91→B, ...）、付録が 91 から始まるプロジェクトでは `vs build 91` が「付録 B」と表示されていた。ビルド対象の付録の順番に基づいてレターを割り当てるよう変更。`vs build 92` のような単章ビルドでは「付録 A」、`vs build 92 93` では 92→付録A, 93→付録B と正しく表示されるようになった。フルビルド時は catalog.yml の付録一覧の順番を使用する。
- **コードブロック内の `include:` 記法を誤検出しない修正** (`lib/vivlio/starter/cli/pre_process/markdown_transformer.rb`): `process_code_include` がマークダウンのコードブロック（` ``` ` で囲まれた領域）内に記述された `include:` 記法まで検出し、存在しないファイルとしてエラーを出していた問題を修正。コードブロックの開閉を追跡する `lines_inside_code_blocks` を新設し、コードブロック内のマッチをスキップするよう変更。記法の説明例として書かれた `include:sample.rb` 等が誤検出されなくなった。
- **コードブロック内の `:::` コンテナ記法が展開されてしまう問題を修正** (`lib/vivlio/starter/cli/pre_process/markdown_transformer.rb`): `convert_container_blocks` がマークダウンのコードブロック内に記述された `:::{.book-card}` や `:::{.table-rotate}` 等の記法まで `<div>` に展開していた問題を修正。処理前に `MarkdownUtils.extract_code_spans` でコードブロックをプレースホルダーに退避し、コンテナ変換後に `restore_code_spans` で復元するよう変更。記法の説明例がそのまま表示されるようになった。
- **`language-markdown` コードブロック内の `[!]` コメント強調が適用されてしまう問題を修正** (`lib/vivlio/starter/cli/post_process/html_replacer.rb`): `post_replace_list.yml` の `code_aware` ルール（`[!]` マーカーによるコメント赤色強調）が、`language-markdown` クラスを持つ `<pre>` ブロック内のネストされたコードにも適用され、記法説明用の `# [!] この行が強調される` から `[!]` が除去されて赤色表示になっていた問題を修正。`apply_rule` の `code_aware` モードで `language-markdown` の `<pre>` ブロックをプレースホルダーに退避してからルールを適用し、適用後に復元するよう変更。
- **画像未検出エラーの行番号が元ファイルとずれる問題を修正** (`lib/vivlio/starter/cli/pre_process/image_path_normalizer.rb`, `lib/vivlio/starter/cli/pre_process/markdown_preprocessor.rb`): `fix_image_paths` がフロントマター追加・HTMLコメント除去後のコンテンツに対して行番号を数えていたため、`🔴 31-lint.md:276` のように `contents/` 内の元ファイルとは異なる行番号が表示されていた。`fix_image_paths` に `source_path:` パラメータを追加し、元ファイルから画像名→行番号のマップを構築して正しい行番号を使用するよう変更。
- **インラインコード内の `include:` 記法が誤検出される問題を修正** (`lib/vivlio/starter/cli/pre_process/markdown_transformer.rb`): `` `` ```include:file.rb``` `` `` のようにバッククォートで囲まれたインラインコード内の `include:` 記法が、存在しないファイルとしてエラーを出していた問題を修正。`lines_with_inline_code_include` を新設し、インラインコード内のマッチをスキップするよう変更。
- **ソースコード未検出エラーの行番号が元ファイルとずれる問題を修正** (`lib/vivlio/starter/cli/pre_process/markdown_transformer.rb`, `lib/vivlio/starter/cli/pre_process/markdown_preprocessor.rb`): `process_code_include` がフロントマター追加・HTMLコメント除去後のコンテンツに対して行番号を数えていたため、元ファイルとは異なる行番号が表示されていた。`process_code_include` に `source_path:` パラメータを追加し、`build_source_include_line_map` で元ファイルから include 記法のパス→行番号マップを構築して正しい行番号を使用するよう変更。
- **裸 URL 検出の行番号が元ファイルとずれる問題を修正** (`lib/vivlio/starter/cli/pre_process/link_image_validator.rb`): `scan_bare_urls` が pre_process 後のコンテンツの行番号でログを出力していたため、元ファイルとは異なる行番号が表示されていた。ログ出力を行番号補正後に移動し、元ファイルの正しい行番号で表示するよう変更。
- **脚注URLの重複表示・不正な脚注参照の修正** (`lib/vivlio/starter/cli/post_process/footnote_converter.rb`, `lib/vivlio/starter/cli/post_process.rb`, `lib/vivlio/starter/cli/pre_process/markdown_preprocessor.rb`): sideimage コンテナ内のリンクURLが脚注として複数回表示される問題と、`#fn5` などの内部リンクが不正な脚注として表示される問題を修正。`footnote_converter.rb` の `insert_footnotes_for_references!` / `fill_missing_footnote_references!` で `footnote-anchor` span 内の参照をスキップするよう変更。`inferred_body_from_previous_link` で `http(s)://` 以外の内部リンクを除外。`normalize_definition_ids!` で VFM が割り当てた実際のIDに定義IDを正規化。`renumber_footnotes_by_document_order!` で `footnote-anchor` span を常に削除し、body 末尾の `aside` を参照元 section に移動する `move_body_asides_to_last_section!` を追加。`update_footnote_definitions` を2段階更新（一時ID経由）に変更してIDの衝突を防止。
- **クロスリファレンスの孤立ID・重複IDの出力を改善** (`lib/vivlio/starter/cli/pre_process/cross_reference_processor.rb`): 孤立ID（定義されているが参照されていないID）および重複ID（同一IDが複数箇所で定義されているケース）の警告メッセージを改善。孤立IDは `⚠️ path:line - 未参照のID: @foo` の形式で、重複IDは `❌ path:line - IDが重複しています: @foo（前回定義: path:line）` の形式で出力するよう統一し、問題箇所の特定を容易にした。
- **`vs new` の YAML プレースホルダエスケープ** (`lib/vivlio/starter/cli/new.rb`, `test/vivlio/starter/cli/new_commands_test.rb`): `vs new` で `book.yml` の `{{MAIN_TITLE}}` / `{{AUTHOR}}` / `{{PUBLISHER}}` / `{{PROJECT_NAME}}` を置換する際、入力値に `"` / `\\` / 改行が含まれると YAML リテラルが壊れて書籍ビルド全体が YAML パースエラーで失敗していた。`yaml_escape_double_quoted` ヘルパーを新設し、バックスラッシュ → `\\\\`、ダブルクォート → `\\"`、改行 → `\\n` / `\\r`、タブ → `\\t` の順でエスケープしてからプレースホルダに埋め込むよう修正。リグレッションテスト 1 件（`"` / `\\` / 改行を含む著者名で book.yml が valid YAML として `YAML.safe_load` できることを検証）を追加。
- クロスリファレンス処理で、` ````markdown ` のような4バッククォート以上のコードブロック内に `@id` 参照やキャプション行が含まれる場合、内側の `` ```javascript `` 等でコードブロック状態が誤って反転し、未定義ラベル警告が出ていたバグを修正。`LabelCollectorContext`・`ReferenceReplacer`・`CaptionedBlockTransformer` の3箇所でフェンスのバッククォート数を記憶し、同じ数で閉じたときのみコードブロックを終了するよう変更。
- `vs build 00` のような前書き章の単章ビルドで、生成した `00-preface.pdf` が Step F（final clean）で中間生成物として削除されてしまい、PDF が自動で開かれない不具合を修正。`run_final_clean` でクリーン前に `@generated_pdf_name` を一時退避し、クリーン完了後に復元するよう変更。
- `.sideimage-left` で `{width=20%}` 等の画像幅指定が画像ではなくテキスト列の幅として解釈されていた不具合を修正。`layout-utils.css` の `grid-template-columns` を `.sideimage-right`（列1=テキスト・列2=画像）と `.sideimage-left`（列1=画像・列2=テキスト）で個別定義するよう変更。あわせて `.sideimage-left` のエイリアスとして `.sideimage` を追加し、`post_process.rb` の `wrap_sideimage_blocks!` にも対象セレクタとして追加。
- 脚注番号が `2. 2.` のように二重表示される不具合を修正。Vivliostyle の `float: footnote` が脚注エリアの `<ol>` に自動付与する番号と、`aside.page-footnote::before` の `data-footnote-number` による独自番号が重複していた。`::footnote-marker { content: none }` で自動マーカーを非表示にし、`@page { @footnote { list-style: none } }` で脚注エリアの `list-style` を無効化することで解消。
- ```:::{.text-right}```、```{.text-right}```が無効となっていた不具合を修正。
- `post_process.rb` に `wrap_img_text_blocks!` を追加。`sideimage` の `wrap_sideimage_blocks!` と同じアプローチで、`img-text` / `text-img` 系コンテナ内の `figure` 以外の子ノードを `<div class="img-text-body">` でラップし、数式やインライン要素が独立したグリッドセルにならないよう正規化を行なった。
- `markdown_preprocessor.rb`: パイプラインに `strip_index_markup!` を追加。[用語|読み] → 用語、[用語] → 用語 に展開する。コードブロック・インラインコード内はスキップ。脚注参照 [^id] もスキップ。
これにより、単章ビルド（Step 4 の索引処理がスキップされる場合）でも、`:::` コンテナ内を含むすべての索引記法が正しくテキストに展開されるようにした。

### Security / Robustness
- **外部コマンド不在時のユーザー向け案内メッセージ（4-1-1 / 4-1-2 / 4-1-3）** (`lib/vivlio/starter/cli/common.rb`): `ensure_external_command!` ヘルパーを新設。`vivliostyle` / `inkscape` / `imagemagick`（`magick` / `convert`）が見つからない場合に、OS 別インストール手順と `vs doctor --fix` の案内を含む構造化メッセージ付きで例外を送出する。回帰テスト `test/vivlio/starter/robustness/missing_external_command_test.rb`。
- **SIGINT / SIGTERM の graceful handling 回帰テスト（4-3-2 / 8-1 / 8-2）** (`test/vivlio/starter/robustness/interrupt_handling_test.rb`): CLI.handle_interrupt / handle_signal の挙動、終了コード（SIGINT=130、SIGTERM=143）、および `CLI.start` の例外捕捉経路を検証する堅牢性テストを追加。
- **`vs new` 中断時の部分展開クリーンアップ（3-1-8）** (`lib/vivlio/starter/cli/new.rb`, `test/vivlio/starter/robustness/vs_new_interrupt_test.rb`): `expand_scaffold` に中断時クリーンアップを追加。プロンプト途中および展開途中で Ctrl+C や例外が発生した場合、部分展開されたディレクトリを削除して中途半端な状態の残存を防止する。
- **`lint --fix` 中断時の元ファイル保全（5-6-2）** (`test/vivlio/starter/robustness/lint_fix_interrupt_test.rb`): `vs lint --fix` 実行中に Ctrl+C で中断されても、`Open3.capture3` が例外を送出しても、元ファイルが壊れないことを回帰テストとして明文化。temp ファイルベースの書き換え方式により、中断時は元ファイルがそのまま残る設計を保証。
- **不正な SVG XML に対する堅牢化（7-1）** (`lib/vivlio/starter/cli/common.rb`, `lib/vivlio/starter/cli/create.rb`, `test/vivlio/starter/robustness/invalid_svg_test.rb`): `Common.run_svg_converter!` ヘルパーを新設し、`rsvg-convert` / ImageMagick による SVG 変換失敗時に stderr を整形（過大出力は中略）してログ出力する。変換失敗が PDF/JPG/PNG 生成すべてで同一のエラー経路を通るよう `create.rb` の `system` 呼び出しを全箇所ヘルパーに差し替えた。`Errno::ENOENT` 発生時のメッセージ整形も含む。
- **プロジェクトルート書き込み不可時の堅牢性確認（1-3-1）** (`test/vivlio/starter/robustness/readonly_project_root_test.rb`): 読み取り専用ディレクトリで `vs build` 等が `Errno::EACCES` を自然送出することを検証。stack trace が過度に複雑化せず、ユーザーが原因を特定可能であることを保証。
- **catalog.yml 欠落ファイルの警告検証（1-2-1）** (`test/vivlio/starter/robustness/catalog_missing_file_test.rb`): `TokenResolver` / `CatalogLoader` が `contents/` に存在しないファイルをスキップし、stderr に `⚠️ catalog.yml に記載された章ファイルが存在しません: …` を出力する挙動を回帰テスト化。
- **画像パスのディレクトリトラバーサル / HTML 特殊文字堅牢性（2-3-4）** (`test/vivlio/starter/robustness/malicious_image_path_test.rb`): `ImagePathNormalizer` のプレースホルダー置換が `../../../etc/passwd` や HTML 特殊文字を含む画像名に対しても安全に動作し、成果物に任意パス・スクリプトが埋め込まれないことを検証。
- **catalog.yml YAML anchors / aliases 悪用対策（9-7）** (`lib/vivlio/starter/cli/build/catalog_loader.rb`, `test/vivlio/starter/robustness/catalog_yaml_safety_test.rb`): `catalog.yml` の読み込みで `Psych::DisallowedClass` を rescue し、人間向けメッセージ（`❌ catalog.yml に許可されていない YAML タグが含まれています: …`）に変換して例外送出する。`YAML.safe_load` + `permitted_classes: []` + `aliases: true` により、通常の anchor / alias は展開できるが `!ruby/object` 等の危険なタグは拒否される。anchor / alias の正常展開と、Billion Laughs 攻撃耐性（Psych 5.x 標準の上限）も回帰テストで確認。
- **原稿内の危険スキーム（`file://` / `javascript:`）検出（11-1）** (`lib/vivlio/starter/cli/pre_process/link_image_validator.rb`, `test/vivlio/starter/robustness/dangerous_scheme_detection_test.rb`): `LinkImageValidator` に `scan_dangerous_schemes` を新設し、Markdown 原稿内の HTML タグ `<img src="file:///etc/passwd">` / `<a href="javascript:...">`、Markdown 画像 `![](file:///...)`、Markdown リンク `[text](javascript:...)` を静的解析で検出して警告する。**セキュリティ保護として常時有効**（`--no-verify` でも無効化不可）。コードブロック / インラインコード内の例示は誤検出しないよう除外。検出時は `⚠️ path:line - 危険なスキームを検出しました（file://）`、URL、「ローカルファイル漏洩 / スクリプト注入のリスクがあります。」を警告出力し、`print_summary` でも件数・URL・参照元行番号を集計表示。Vivliostyle/Chromium のポリシーに依存せず Ruby 側で明示的にブロックする第一の防衛線を構築。回帰テスト 10 件。
- **QueryStream データファイル（`data/*.yml`）の YAML safe_load 化（11-2）** (`Gemfile`, `test/vivlio/starter/robustness/data_render_yaml_safety_test.rb`): `query-stream` gem を 1.2.0 → 1.2.1 に更新し、`DataResolver.load_records` の `YAML.load_file` を `YAML.safe_load_file(permitted_classes: [Symbol, Time, Date, DateTime], aliases: true, symbolize_names: true)` に置き換えた（query-stream CHANGELOG 参照）。`!ruby/object:Kernel {}` 等の Ruby オブジェクトタグは `Psych::DisallowedClass` として検出され、`QueryStream::DataLoadError` に変換されて `DataRender.process` の `on_error` 経由で `Common.log_error` に通知される。vivlio-starter 側の統合回帰テストで、悪意のある data.yml が素通りしないこと、正常な Symbol / Time / Date データが従来どおり処理されること、YAML 構文エラーも同経路で通知されることを検証。
- **堅牢性テスト専用ディレクトリを新設** (`test/vivlio/starter/robustness/`): 🔴🆕 高優先度 18 項目すべての堅牢性テストを `test/vivlio/starter/robustness/` 配下に集約。README を新設し、各テストが対応する `docs/specs/vivlio_starter_robustness_test_spec.md` の項番を明記。詳細カバレッジ:
  - `catalog_missing_file_test.rb` — 1-2-1
  - `readonly_project_root_test.rb` — 1-3-1
  - `malicious_image_path_test.rb` — 2-3-4
  - `vs_new_interrupt_test.rb` — 3-1-8
  - `yaml_placeholder_escape_test.rb` — 3-2-1 / 3-2-2
  - `missing_external_command_test.rb` — 4-1-1 / 4-1-2 / 4-1-3
  - `build/build_lock_test.rb` — 4-3-1
  - `interrupt_handling_test.rb` — 4-3-2 / 8-1 / 8-2
  - `lint_fix_interrupt_test.rb` — 5-6-2
  - `invalid_svg_test.rb` — 7-1
  - `catalog_yaml_safety_test.rb` — 9-7
  - `dangerous_scheme_detection_test.rb` — 11-1
  - `data_render_yaml_safety_test.rb` — 11-2


#### 開発者体験・保守性
- [Medium] ビルドログ整備: ビルド各ステップに要約出力とエラーヒントを追加し、失敗時の原因特定とリカバリーを容易にする。
- [Low] スタイルガイド整備: 章タイプ別（preface/chapter/appendix/postface）スタイルの設計指針、ユーティリティクラス（`.aki`, `.aki2`, ほか）一覧、使用例をドキュメント化し、保守性を向上させる。






## [1.0.0-alpha] - 2026-04-20

### Added
- **`post_replace_list.yml` 専用スタイルシート `stylesheets/replace-list.css` を新設** (`stylesheets/replace-list.css`, `stylesheets/chapter.css`, `stylesheets/appendix.css`, `stylesheets/preface.css`, `lib/project_scaffold/stylesheets/`): `post_replace_list.yml` の置換ルールが付与する「隠れクラス」専用のスタイルシートを標準 CSS として新設。`.hen-comment`（編集者コメント）、`.kaiwa` / `.kaiwa.sense` / `.kaiwa.deshi`（会話文）、`li.aokome`（青コメ ▶）、`li.akakome`（赤コメ ❶❷❸）のスタイルを定義。`chapter.css` / `appendix.css` / `preface.css` から `@import` されるため、著者の `custom.css` に依存せず標準でスタイルが適用される。プロジェクトスキャフォールド（`vs new`）にも同期し、新規プロジェクトにも自動配置される。`stylesheets/_README.md` も更新。
- **`post_replace_list.yml` 検証用サンプル章を追加** (`contents/81-replace-list-sample.md`, `config/catalog.yml`): `post_replace_list.yml` の全置換ルール（`:::` コンテナ、`@nega` / `@posi` / `@clear` / `@comment`、改ページ `---`、会話文、`〘 〙` キーキャップ、青コメ `▶` / 赤コメ `❶`、コード内 `←` コメント強調、`{.aki}` / `{.aki2}`、空段落除去、`<p><div>` ねじれ補正）を網羅的に動作確認できる検証用章を追加。章末にチェックリスト付き。

- **`vs preflight` コマンドを実装**: `vs build`（約600秒）の前に原稿のエラーチェックだけを約6秒で行う高速チェックコマンド。`vs build` の Step 1〜4（画像最適化・テーマ画像準備・Markdown前処理・索引スキャン）のみを実行し、PDF生成を伴わない。画像不在・コードインクルードファイル不在・QueryStream展開エラー・クロスリファレンス未定義ラベルを検出して報告する。エラーあり→終了コード1、警告のみ→終了コード0。`vs preflight 1-10` / `vs preflight install` など `vs build` と同じ章トークン指定に対応。実装は `UnifiedBuildPipeline` に `mode: :preflight` を追加する方式で、build 側の変更が自動追従する。

### Changed
- **RuboCop 違反の追加クリーンアップ（888 → 860、28件減）** (`lib/vivlio/starter/cli/build/backlink_deduplicator.rb`, `build/page_mapping_extractor.rb`, `build/pipeline.rb`, `build/utilities.rb`, `index/index_match_scanner.rb`, `index/unified_page_builder.rb`, `metrics/analyzer.rb`, `metrics/cache.rb`, `metrics/parallel_runner.rb`, `pdf/pdf_read_command.rb`, `pdf/standard_provider.rb`, `post_process.rb`, `post_process/html_replacer.rb`, `pre_process/css_updater.rb`, `pre_process/data_render.rb`, `pre_process/image_generator.rb`, `pre_process/theme_image_resolver.rb`): v1.0 に向けて **振る舞い不変** のまま自動修正および手動修正を適用。(1) `rubocop --autocorrect` で 7 件（余分な空白・trailing comma・frozen_string_literal 下の `.freeze` 除去・string literal 統一）。(2) `rubocop --autocorrect-all` で 7 件（`each_with_object` → `to_h { ... }` / `tally` 、`.select` with range → `.grep` 等、Modern Ruby 慣用表現への置換）。(3) 手動で 5 件の `Style/ComparableClamp` を `[[x, min].max, max].min` → `x.clamp(min, max)` に書き換え。(4) 手動で 4 件の `Style/ItBlockParameter` (multi-line blocks) を `it` → 明示パラメータ `|entry|` / `|line|` に置換。(5) 手動で 2 件の `Style/FormatString` (`"..." % it` → `format("...", it)`)。(6) 3 件の `Lint/UnusedMethodArgument`（公開 API の kwarg で interface 互換のため改名不可なもの）に `# rubocop:disable` コメントを付与。全変更後も `bundle exec rake test` は 828 runs / 4598 assertions / 0 failures で通過。残 860 件は大半が `Metrics/*` 系（83%）で、メソッド分割を伴うリファクタリング案件のため v1.0 後のタスクとする。
- **コード内コメント強調の記法を `←` から `[!]` マーカー方式に変更** (`config/post_replace_list.yml`, `lib/project_scaffold/config/post_replace_list.yml`, `stylesheets/replace-list.css`, `lib/project_scaffold/stylesheets/replace-list.css`, `contents/23-replace-list.md`, `contents/81-replace-list-sample.md`): (1) 旧記法 `#←` / `//←` / `/*← ... */` / `<!--← ... -->` を廃止し、新記法 `# [!]` / `// [!]` / `-- [!]` / `/* [!] ... */` / `<!-- [!] ... -->` に統一。(2) 旧仕様は `#← コメント` を `<span class="token comment codered">コメント</span>` に変換しコメント記号まで削除していたが、新仕様は `# [!] コメント` を `<span class="token comment codered"># コメント</span>` としてコメント記号（`#` / `//` / `--` / `/*` / `<!--`）を保持し `[!]` マーカーとその前後の空白のみ除去する。(3) SQL や Lua 等で用いられる `--` コメントへの対応を追加。(4) 二重矢印 `/*←← ... */` による右寄せ仕様を廃止し、関連する CSS クラス `.codered-right` と置換ルール 1 本を削除。5 本あった置換ルールを 2 本（標準コメント用 + HTML コメント用）に整理。`contents/23-replace-list.md` と `contents/81-replace-list-sample.md` のサンプル・期待結果も全面的に新記法へ差し替え。
- **`.column` / `.memo` / `.tip` のデザインを刷新** (`stylesheets/chapter-common.css`, `contents/23-replace-list.md`): コンテナ記法の視認性を向上させるためデザインを統一・刷新。(1) タグを枠の外に配置（`top: -6mm`, `margin-top: 3mm`）、タグ文字を大文字（COLUMN/MEMO/TIP）・ゴシック体に変更。(2) 全幅レイアウトに統一（`.column` の固定幅 114mm を廃止）。(3) margin/padding を統一（`margin-block: 4mm 6mm`, `padding: 4mm`, `padding-inline: 6mm`）。(4) 色使いを整理: `.column` と `.memo` はアクセントカラーの枠線・背景（`.column` は淡い色、`.memo` は白色）、`.tip` はアクセントカラーの枠線・タグ（タグ背景は白色）。`.memo` の CSS 定義を `stylesheets/replace-list.css` から `stylesheets/chapter-common.css` に移動し、`.column` / `.tip` と同じ場所で管理するように整理。`contents/23-replace-list.md` に説明文を更新し、使い分けが分かるように記載（column: 補足情報やコラム記事、memo: 覚書きや注釈、tip: ヒントやコツ）。
- **クロスリファレンスの予約IDに `post_replace_list.yml` のマクロ名を追加** (`lib/vivlio/starter/cli/pre_process/cross_reference_processor.rb`, `contents/25-cross-reference.md`, `test/vivlio/starter/cli/markdown_transformer_test.rb`): 本文中の `@div` / `@divend` / `@nega` / `@posi` / `@clear` / `@comment` / `@commend`（完全一致）および `@lu25` / `@ld30` / `@ls40` / `@us30` など絶対配置マクロ（接頭辞 `lu` / `ld` / `ru` / `rd` / `ur` / `ls` / `rs` / `us` / `ds` ＋数字）を **システム予約語** として扱い、「未定義のラベルID」警告を出さないようにした。`RESERVED_IDS` に加えて `RESERVED_MACRO_IDS` / `RESERVED_MACRO_POSITION_PREFIXES` の 2 定数と一元判定ヘルパー `CrossReferenceProcessor.reserved_id?` を新設。`replace_single_ref` はこのヘルパー経由で判定する。`25-cross-reference.md` に **§4.3 システム予約ID（予約語）** を新設し、予約語一覧と著者向けの衝突注意を明記。リグレッションテスト 3 件（完全一致マクロ / 絶対配置マクロ / ヘルパー単体）を追加。
- **`post_replace_list.yml` のリスト項目絶対配置＋SVG ガイド線記法（`@lu` / `@ld` / `@ru` / `@rd` / `@ur` / `@ls` / `@rs` / `@us` / `@ds`）を今回のリリースでは対応外とし、全ルールをコメントアウト** (`config/post_replace_list.yml`, `contents/23-replace-list.md`, `contents/81-replace-list-sample.md`, `stylesheets/replace-list.css`, `CHANGELOG.md`): (1) 親要素の自動 `position: relative` 化する標準クラスの提供、(2) 座標系・単位（mm/%）の整理、(3) 図解ページ向けプリセット（`.figure-guides` コンテナ）の正式化、(4) 印刷プレビューでの視覚検証、が未完了のため今回の対象外とした。`post_replace_list.yml` は 9 本の rule 行を `#` でコメントアウト（例・説明コメントは保持）。`contents/23-replace-list.md` は該当節と一覧表の行を `<!-- ... -->` で囲い、復旧時に `# ` や `<!-- -->` を外すだけで戻せるよう原稿を保全。`contents/81-replace-list-sample.md` の §9 は `[要fix]` → `[**Planned**]` へ変更し、サンプルを ` ```markdown ` フェンスブロックで囲ってビルド時に展開されないようにした。`CHANGELOG.md` の **Planned > 記法・置換ルール（次期リリース候補）** に正式サポート条件を記載。

### Fixed
- **Vivliostyle ビューア警告を解消** (`stylesheets/prism.css`, `stylesheets/layout-utils.css`, `stylesheets/page-settings.css`, `lib/project_scaffold/stylesheets/*.css`, `lib/vivlio/starter/cli/pre_process/css_updater.rb`, `test/vivlio/starter/cli/build/page_layout_test.rb`): `vs build` 時に大量出力されていた以下の警告を解消した。(1) `Unknown pseudo-element ::-moz-selection` / `::selection` — Prism.js 由来の印刷には無意味な擬似要素ルールを `prism.css` から削除。(2) `E_INVALID_PROPERTY -moz-user-select: none` — `user-select` は現在主要ブラウザすべてでベンダープレフィックスなしが標準化されているため、`-webkit-` / `-moz-` / `-ms-` の 3 種を削除し標準 `user-select: none` のみ残した。(3) `E_INVALID_PROPERTY_VALUE inline-size: min(26em, max-content)` — Vivliostyle が `min()` 関数内の `max-content` キーワードを未対応のため、`layout-utils.css` の `.align-left` / `.align-center` / `.align-right` を `max-inline-size: var(--align-max-width); inline-size: fit-content;` に変更。元の「最大幅に収める／短ければ内容幅に縮む」挙動を維持しつつ `min()` を排除。(4) `F_UNEXPECTED_STATE ,` — (3) の修正により連鎖発生が解消。新設した CSS カスタムプロパティ `--align-max-width` は既存の `css_updater.rb` 前処理インフラに乗せ、`page.use` に応じて判型別に上書きする（A5=26em, B5=36em, A4=40em）。新ヘルパー `calculate_align_max_width` を追加し、ユニットテスト 8 件を `page_layout_test.rb` に追加。設計経緯は `docs/specs/vivliostyle_warnings_spec.md` 参照。
- **`book.yml` 更新時に特殊ページ・カバーが再生成されない不具合を修正** (`lib/vivlio/starter/cli/build/pipeline.rb`, `lib/vivlio/starter/cli/build/pdf_builder.rb`, `lib/vivlio/starter/cli/create.rb`, `test/vivlio/starter/cli/create_commands_test.rb`): `page.use` を `a4 ↔ a5` 等に変更しても `_titlepage_legalpage.pdf` / `_colophon.pdf` / `covers/*_rgb.pdf` / 中間 SVG が再生成されず旧成果物が流用される不具合を修正。原因は mtime 比較＋キャッシュ復元ロジックで、`FileUtils.cp` が mtime を「現在時刻」に書き換えるため `book.yml` の変更が検知されない／`execute_titlepage` 等が `File.exist?` で早期 return する等、複数の脆弱性があった。特殊ページ・カバーの再生成はビルド全体（~60秒）への影響が軽微（計測上ほぼ誤差範囲）なため、mtime 比較・キャッシュ判定を全廃し「常に再生成する」仕様に変更した。`run_step9_front_pages_and_tail` / `build_front_pages_and_tail!` / `execute_titlepage` / `execute_legalpage` / `execute_colophon` / `render_bundled_svg` / `apply_text_placeholders_to_svg` / `convert_svg` / `convert_png` から mtime 比較・キャッシュロジック・未使用の `needs_regeneration?` / `safe_mtime` を削除。設計経緯と計測結果は `docs/specs/book_yml_regeneration_spec.md` 参照。
- **デッドコードを削除** (`lib/vivlio/starter/cli/build/utilities.rb`): `cache_store_file` / `cache_restore_file` は今回の修正で呼び出し元がなくなりデッドコード化していたため削除。
- **QueryStream 展開エラー／警告メッセージの表示を改善** (`lib/vivlio/starter/cli/pre_process/data_render.rb`, `test/vivlio/starter/cli/build/preflight_pipeline_test.rb`, `query-stream` gem): (1) 展開エラー時のメッセージが `❌ ❌ QueryStream 展開エラー: …` と `❌` が 2 つ重複していた問題を修正。`Common.log_error` が `❌` を自動付与するのに、`DataRender#process` の `on_error` コールバック側でも `❌` を付けていたため。コールバック側の `❌` を削除。(2) 一件検索の警告が Ruby デフォルトの `W, [timestamp #pid] WARN -- : 一件検索で該当なし(…): …` 形式で出力され、他の警告（`⚠️ …`）と見た目が揃わず分かりづらかった問題を修正。原因は `query-stream` gem の `render_query` 内に残存していた `logger.warn(…)` 呼び出し。gem 側で `NoResultWarning` / `AmbiguousQueryWarning` に `query` / `location` / `count` 属性を追加し、`logger.warn` を `on_warning` コールバック呼び出しに置き換えた（query-stream CHANGELOG 参照）。vivlio-starter 側では `DataRender#process` に `on_warning` コールバックを追加し、`Common.log_warn` 経由で `⚠️ QueryStream 一件検索: 該当レコードが見つかりません` / `⚠️    記法: = book \| 相対性理論 (…)` の形式で出力するようにした。(3) `PreflightPipelineProperty4Test` の `FORMAT_PATTERN` が `❌ ❌ QueryStream 展開エラー: .+` と二重 `❌` を検証していた問題も併せて修正。
- **目次のレイアウト崩れを修正** (`stylesheets/toc.css`): (1) 節数が多い章（例：開発者向けガイド）で目次が次ページに押し出される問題を修正。`.toc-chapter` を `display: flex` から `display: block` に変更し、章ブロックがページ境界で適切に分割されるようにした。これにより長い章の節が見切れることなく、ページを跨って表示される。(2) 「第 N 章」見出しバーと本文タイトルの間で改ページされないよう `.toc-chapter::before` に `break-after: avoid` を追加し、見出しが単独で残るのを防止。(3) 付録は見出しバーが無いため `.toc-chapter-appendix::before` は `break-after: auto` に設定。(4) flex 前提の不要なプロパティ（`order`, `flex-basis`, `align-items` 等）を削除し、CSS を整理。既知の不具合の2件を解決済みに変更。
- **`HtmlReplacer` が `<pre>` / `<code>` / HTML 属性値の内側にも置換を適用してしまう不具合を修正** (`lib/vivlio/starter/cli/post_process/html_replacer.rb`, `test/vivlio/starter/cli/post_process/html_replacer_test.rb`): `post_replace_list.yml` の全ルールが HTML 全体に対して無差別に `gsub` で適用されていたため、以下 2 系統の事故が発生していた。**(A) コードブロック汚染**: ```` ```markdown ```` フェンス付きコードブロックやインライン `` `@posi:10` `` 等に書かれたマクロ例まで展開され（例: `@posi:10` → `<div style="margin-top:10mm"></div>`、`〘Ctrl〙` → `<kbd>Ctrl</kbd>`）、記法解説の原稿が成立しなくなる。**(B) 属性値破損**: `### 回り込みの解除 `@clear`` のように見出しにマクロ名が登場すると、`HeadingProcessor` が `data-heading="回り込みの解除 @clear"` 属性へテキストをコピーした後、最終 `HtmlReplacer` パスが属性値内の `@clear` を `<div class="floatclear"></div>` に置換し、結果 `data-heading="回り込みの解除 <div class="floatclear"></div>"` となって属性値内の `"` で HTML 解析が破綻、PDF に `" data-h3="回り込みの解除` のような生の属性定義が露出していた。修正は `HtmlReplacer.process_html_file` にルール分類器（`rule_mode`）を導入する方式:(1) **`:code_aware`** — パターンに `class="token` を含むルール（Prism ハイライト強調）。HTML 全体に適用。(2) **`:text_only`** — パターンに `<` を含まないルール（`@clear` / `@posi:N` / `@nega:N` / `@div:X` / `@divend` / `@comment:...@commend` / `:::{.class}` / `〘〙` 等）。`<pre>...</pre>` 全体、`<code>...</code>` 全体、および `<...>` タグ定義（属性値を含む）を `\u0000__VS_PRE__` / `\u0000__VS_CODE__` / `\u0000__VS_TAG__` のプレースホルダへ退避し、テキストノードだけに適用して復元する。(3) **`:tag_aware`** — 上記以外（`<p>`、`<hr>`、`<li ...>▶`、`<p>【先生...】`、空段落除去、`<p><div>` ねじれ補正など HTML 構造を対象）。保護なしで全体に適用（`<pre>`/`<code>` 内にはリテラルタグが実体参照化されて存在しないため安全）。リグレッションテスト 11 件（コードブロック保護 3 件、インライン `<code>` 保護、Prism token ルール適用、属性値保護 3 件、分類器の単体、ノーオペ系 2 件）を新設。
- **`post_replace_list.yml` の置換ルールに潜む複数のバグを修正** (`config/post_replace_list.yml`): 新設の検証章 `81-replace-list-sample.md` 上で発見された不具合を修正。(1) `:::{.note .align-center}` のような複数クラス記法の第2クラスのドットが残っていた問題を、`[.-]` への拡張と後段の `" ."` → `" "` 整理ルール 3 段追加で解消（最大 4 クラス対応）。(2) `@div:CLASS` 短縮記法の文字クラスに `-` を追加し、`@div:align-right` のようなハイフンを含むクラス名を受理。(3) C 言語系の引き出し線コメント `/*← ... */` `/*←← ... */` の貪欲マッチ `(.*)` を非貪欲 `(.*?)` に変更。貪欲マッチが複数コードブロックを巻き込み、説明文中のサンプル記法や後続の HTML コメントブロックごと吸い込んで削除してしまう重大バグがあった。(4) HTML コメント `<!--← ... -->` の強調ルールを VFM/Prism の実出力（`&#x3C;` / `-->`）に合わせて修正。(5) `<p><div>` ねじれ補正ルールの間に `\s*` を許容し、空白・改行が入っていても整形されるよう改善。(6) 空段落 `<p>&nbsp;</p>` の除去ルールの文字クラスに `U+00A0` を追加。VFM が `&nbsp;` を実体文字に変換するため `\s` 単体ではマッチしなかった。
- **`strip_html_comments!` がフェンス付きコードブロック内の HTML コメントまで削除する不具合を修正** (`lib/vivlio/starter/cli/pre_process/markdown_preprocessor.rb`): Markdown 原稿内の `<!-- ... -->` を一律に削除していたため、` ```html ... ``` ` コードブロック内の `<!-- HTML コメントのサンプル -->` まで消去されていた（Prism ハイライト用のサンプルコードが空行になる症状）。フェンス付きコードブロック（` ``` ` / `~~~`）とインラインコード（`` ` ... ` ``）を一旦プレースホルダーに退避してから `<!-- -->` を除去し、最後に復元する三段構成に変更。解説文としての HTML コメントは除去し、コード例としての HTML コメントは保持できるようになった。
- **Nokogiri 系後処理が残す空 `<p></p>` を最終クリーンアップで除去** (`lib/vivlio/starter/cli/post_process.rb`): `<p><div>...</div></p>` のねじれを Nokogiri ベースの後処理（`HeadingProcessor` など）が正す際、副産物として空の `<p></p>` が複数残る問題があった（検証章で 10 件発生）。ポストプロセス末尾に `HtmlReplacer` をもう一度走らせる最終クリーンアップパスを追加。`post_replace_list.yml` の `<p></p>` 除去ルールが Nokogiri 経由の整形後にも適用され、残留ゼロを達成。
- **`rake test` で検出された 7 件のテスト失敗を修正** (`cli/samovar/preflight_command.rb`, `test/vivlio/starter/cli/link_image_validator_test.rb`, `test/vivlio/starter/cli/link_image_validator_integration_test.rb`): (1) `PreflightCommand#test_should_print_help_with_help_option` は `print_usage` が未定義で Samovar の既定ヘルプが `$0`（rake 実行時は `rake_test_loader.rb`）を使っていたため、他の Samovar コマンドと同形式の `print_usage` を追加し、ヘルプに `preflight` が含まれるよう修正。(2) `LinkImageValidator` 関連 6 件は、`print_summary` の「問題なし」系メッセージが `Common.log_info` 経由で出力され、既定のログレベルが warn のため `assert_output(/問題なし/)` が空文字列にマッチしなかった。さらに `page_mapping_extractor_test.rb` などが `Common.log_info` を no-op に上書きする影響で `current_log_level` のスタブでは不十分だったため、テスト側で `Common.stub(:log_info, ->(msg) { puts "ℹ️ #{msg}" })` を挟む形に統一。プロダクションコードは無変更で、「問題なし時は通常ビルドで表示しない」という既存挙動を保ったままテストが通るようにした。
- **`vs renumber 25 26` でスラッグが脱落する不具合を修正** (`cli/rename.rb`): 旧側にスラッグ有り・新側が数値のみ（通常章 01-89）の分岐で `new_slug` が暗黙 `nil` に落ち込み、`25-querystream.md` が `26.md` に改名されていた。`else old_slug end` を追加してスラッグを維持するよう修正。これにより `vs renumber 25 26` / `vs rename 25 26` は `25-querystream.md → 26-querystream.md` となり、対応する `images/25-querystream/` および `catalog.yml` のエントリも同時に更新される（`RenumberCommand < RenameCommand` の継承により両コマンドに同時適用）。リグレッションテスト `test_rename_preserves_slug_when_new_arg_is_number_only` を追加。
- **pre_process パイプラインのコードブロック除外処理を統一し、コードブロック内の画像記法が誤展開される不具合を予防** (`cli/pre_process/markdown_utils.rb`, `cli/pre_process/markdown_preprocessor.rb`): `MarkdownUtils.extract_code_spans` の正規表現を強化し、先頭 0-3 スペースのインデント付きフェンス（CommonMark 準拠）と、`` ``foo`bar`` `` のようにバッククォートをネストしたマルチバッククォートのインラインコードを正しく退避できるようにした。また、これまで個別に `in_code_block` フラグを手動管理していた `escape_inline_code_html!` / `transform_text_right_inlines!` を `extract_code_spans` / `restore_code_spans` のサンドイッチパターンに統一し、`normalize_html_block_boundaries!` と合わせて全ての pre_process メソッドでコードブロック除外方式を共通化した。これにより、コードブロック内の `![](key)` 画像記法がプレースホルダー SVG に展開される等の回帰を構造的に予防できるようになった。`docs/specs/pre_process_codeblock_spec.md` のチェックリスト 7/8/9 を完了扱いに更新。
- **Step 8（backlink dedup）の Playwright 完了検知を改善** (`cli/build/extract_page_mapping.mjs`): ページコンテナ数のポーリング方式から `window.coreViewer.readyState` の `COMPLETE` イベント待機方式に変更。ポーリング間隔（300ms）と安定判定待機（2秒）が不要になり、数秒程度の短縮を図った。なお Step 8 全体の大半（~150秒）は vivliostyle preview による416ページのブラウザレンダリング時間であり、根本的な高速化は vivliostyle CLI 側の改善を待つ必要がある。
- **QueryStream 展開エラー時に `Thread terminated with exception` ログが出力される問題を修正** (`cli/pre_process/markdown_preprocessor.rb`): テンプレートファイルが見つからない等の `DataRenderError` 発生時、`process_data_streams!` が `raise` で例外を再送出していたため、並列ビルドのスレッド内で未キャッチとなり `Thread terminated with exception` ログが出力されていた。エラーメッセージは `Common.log_error` で出力済みのため、`raise` を削除してコンテンツを変更せずに処理を継続するよう修正。
- **QueryStream エラーを構造化例外に変更** (`query-stream` gem): `TemplateNotFoundError` / `DataNotFoundError` に `template_path`, `query`, `location`, `hint` 等の属性を追加。gem 内の `logger.error` 呼び出しを全廃し、エラーメッセージの構成を呼び出し元（`DataRender.process`）に委譲。i18n 対応やフォーマット変更が gem 側の変更なしに可能になった。
- **QueryStream 展開エラー時に残りの記法を継続展開するよう修正** (`query-stream` gem): `QueryStream.render` 内で `render_query` の例外を `rescue` し、失敗した行は元の記法のまま残して後続の記法の展開を継続するよう変更。`on_error` コールバックでエラー情報を呼び出し元に通知する。
- **`extract_preview_url!` を固定 URL 方式に変更** (`cli/build/page_mapping_extractor.rb`): vivliostyle CLI 10.5.0 へのバージョンアップ後、Step 8（backlink dedup）で `⚠️ Preview URL をログから取得できませんでした` という警告が出るようになった。原因を調査した結果、vivliostyle CLI 10.5.0 で `terminalLink()` が導入されたことで `Preview URL:` の出力形式が変わり、`spawn` + ファイルリダイレクト環境では Node.js の stdout バッファリングによりログへの書き込みが間に合わなくなっていた。一方、`--port` と `-c vivliostyle.config.js` を指定した場合、vivliostyle preview は常に固定パターンの URL で起動することが確認されたため、ログ抽出処理を廃止し固定 URL を直接使用する方式に変更。旧実装はコメントアウトして残存。
- **リンク・画像検証サマリーの出力を改善** (`cli/pre_process/link_image_validator.rb`, `cli/samovar/build_command.rb`): 問題なし時の `✅ リンク・画像の検証が完了しました（問題なし）` を `echo_always` から `log_info` に変更し、通常ビルド（`vs build`）では出力しないようにした。`--log=debug` 時のみ表示される。問題あり時は従来通り常に表示。また検証サマリーの出力順序を変更し、`📚 xxx.pdf を作成しました。` より前に表示されるよう調整。
- **`vs new --help` が動作しない問題を修正** (`cli/samovar/new_command.rb`, `cli/new.rb`): `one :name` で引数を定義していたため Samovar が `--help` をオプションではなくプロジェクト名として解釈し、対話プロンプトが起動していた。`many :names` に変更することで `--help` がオプションとして正しく解析されるようになり、`vs create --help` と同じ形式でヘルプが表示されるよう統一した。
- **コラムの背景色・枠色をテーマカラーに連動するよう変更** (`stylesheets/theme.css`): `--color-column-bg` が固定値 `#eef` だったため、テーマカラーに関わらず常に青みがかった背景になっていた。CSS の `color-mix()` 関数を使い `color-mix(in srgb, var(--theme-accent) 15%, white)` に変更することで、選択したテーマカラーを薄めた色が自動的に適用されるようになった。`--color-column-border` も `var(--theme-accent)` に変更した。

## [0.39.2] - 2026-04-14

### Fixed
- **目次のページ番号フォントが等幅にならない問題を修正** (`stylesheets/toc.css`): `var(--folio-font)` は未定義の変数名で、正しくは `var(--font-folio)`（`page-settings.css` で定義）。変数名の不一致によりフォールバックのプロポーショナルフォントが使われ、付録などの3桁ページ番号が揃わなかった。
- **章数が多い場合に目次が次ページに押し出される問題を修正** (`stylesheets/toc.css`): `li.toc-chapter` に `break-before: auto` を追加し、章ブロックが大きすぎる場合でも前でのページ分割を許容するようにした。

### Added
- **拡張記法リファレンス章を追加** (`contents/25-extensions.md`): `.column`, `.tip`, `.note`, `.notice`, `.book-card`, `.pictures`, `.img-text` 系, `.table-rotate`, `.table-scroll`, `.aki`, `.aki2` など Vivlio Starter 独自の拡張コンテナ記法を一覧解説する章を第二部に追加。

## [0.39.1] - 2026-04-13

### Changed
- **CLI ロード構造のリファクタリング**（`docs/specs/cli_loader_refactor_spec.md` 準拠）: `CLI.start` と無効入力時ヘルプを `lib/vivlio/starter/cli/startup.rb` に単一定義。ドメイン〜 Samovar の一括 require を `cli/loader.rb` に集約し、`cli.rb` は startup 経由の薄いエントリに変更。`bin/vs` と `bin/vivlio-starter` はともに `require 'vivlio/starter/cli/startup'` と `exit CLI.start(ARGV)` で終了コードを統一。デッドコードだった `cli/help.rb`（`HelpCommands`）を削除し、ヘルプ文言は `samovar/help_command.rb` のみとした。`lib/vivlio/starter/commands/new.rb` を廃止し、`Vivlio::Starter::CLI::NewCommands`（`cli/new.rb`）へ統合。`NewCommand` は `NewCommands` のみを参照。
- **RuboCop による自動修正を実施**: `--autocorrect` および `--autocorrect-all` で合計1140件を自動修正（1595件 → 887件）。`TargetRubyVersion` を 3.4 → 4.0 に更新（RuboCop 1.86.1 が Ruby 4.0 を正式サポート）。`Style/NumericPredicate` は `nil` になりうる変数への誤適用を防ぐため無効化。
- **各種バージョンアップ**:
  - Ruby: 4.0.0 → 4.0.2
  - RuboCop: 1.81.7 → 1.86.1
  - @vivliostyle/cli: 10.3.1 → 10.5.0
  - @vivliostyle/vfm: 2.5.0 → 2.6.0
  - @vivliostyle/core: 2.40.0 → 2.41.0
  - Node.js: v25.2.1 → v25.9.0
  - ImageMagick: 7.1.2-17 → 7.1.2-18
  - qpdf: 12.2.0 → 12.3.2
  - npm audit fix による依存パッケージの脆弱性7件を解消

### Added
- **リンク・画像の自動検証機能を実装** (`vs build` に統合): ビルド時に Markdown 原稿内の画像パスと URL を自動検証し、問題を警告として報告する。ビルド自体は止めない設計。
  - **画像パスの存在チェック**: `ImagePathNormalizer` がプレースホルダー（`data:` URI）に置換した箇所を検出し、欠落画像として報告する（方式 A）。
  - **裸 URL の検出**: Markdown リンク記法を使わずに本文中に直書きされた URL を検出し、`[テキスト](URL)` 記法の使用を推奨する警告を表示する。コードブロック・インラインコード・脚注定義行は除外。
  - **外部 URL の HTTP 到達性チェック**（`--verify-links` で有効化）: `net/http` による HEAD リクエストで外部 URL の到達性を確認。4xx/5xx/タイムアウト/DNS 失敗を警告として報告。URL の重複排除・最大同時接続数（既定 5）・タイムアウト（既定 10 秒）に対応。
  - **`--[no]-verify` オプション**: 画像・裸 URL の基本検証を有効/無効にする（既定: 有効）。`--no-verify` で全チェックをスキップしてビルドを高速化できる。
  - **`--verify-links` オプション**: 外部 URL の HTTP 到達性チェックを有効にする（既定: 無効）。
  - **`book.yml` での細かい制御**: `build.verify.images` / `bare_urls` / `external_links` / `timeout` / `max_concurrency` で個別に設定可能。CLI オプションが `book.yml` より優先される。
  - **検証サマリー表示**: 全ファイル処理後に問題件数・詳細をまとめて表示。問題なし時は `✅ リンク・画像の検証が完了しました（問題なし）` を表示。
- **`contents/20-build.md` にリンク・画像検証の使い方を追記**: 検証内容・サマリー出力例・`--verify-links` / `--no-verify` の使い方・`book.yml` 設定を解説するセクションを追加。

## [0.38.0] - 2026-04-09

### Added
- **`vs new` コマンドを実装**: 新規書籍プロジェクトを対話的に作成するコマンド。プロジェクト名を指定すると `project_scaffold/` からファイルを展開し、`config/book.yml` の書籍名・著者名等を置換する。`--yes` で対話スキップ、`--force` で既存ディレクトリへの追加展開、`--log debug` でデバッグ出力に対応。展開後に `vs doctor --fix` を自動実行して環境をセットアップする。
- **著者マニュアル `contents/40-new.md` を追加**: `vs new` コマンドの使い方・オプション・プロジェクト構成を解説するマニュアル。

### Changed
- **章番号の範囲定義を全コマンドで統一**: 00（前書き）、01-89（本文）、90-98（付録）、99（後書き）の仕様に統一。旧仕様（11-89 / 91-97）が残っていた `Common.appendix_number_to_letter`、`OutlineExtractor::APPX_RANGE`、`HeadingProcessor` のロジックとコメントを修正。付録のレター対応を A-G（7章分）から A-I（9章分）に拡張。
- **`vs renumber` の連番開始番号を先頭章に合わせるよう改善**: 引数なし実行時、先頭章の番号を起点として順に詰める（例: 11, 15, 31 → 11, 12, 13）。
- **`vs --version` / `vs --help` をプロジェクト外でも実行可能に**: `config/book.yml` が存在しないディレクトリでも `--version`、`--help`、`new`、`doctor` コマンドが動作するよう、設定ロードを遅延化。
- **`vs doctor --fix` の npm 警告を抑制**: `npm install` に `--loglevel=error` を付与し、初回セットアップ時の非推奨パッケージ警告を非表示に。
- **`scaffold Gemfile` のバンドラーエラーを修正: `gemspec` 参照から `gem 'vivlio-starter'` への変更。ローカル gem インストール後、任意の場所でプロジェクト作成が可能に。
- **`vs doctor` のグローバル npm インストール時の Playwright 検出を修正**: `vs doctor --fix` で Playwright をグローバルインストール（`npm install -g playwright`）し、ローカル・グローバル両方の環境を検出するよう変更。複数プロジェクト間での再インストールプロンプトを防止。
- **`extract_page_mapping.mjs` の Playwright インポートを修正**: ESM インポートが gem ディレクトリ内から失敗する場合に `createRequire` を使ったフォールバックを追加。`vs build` 実行時の `ERR_MODULE_NOT_FOUND` を解消。

## [0.36.0] - 2026-04-07

### Changed
- **`vs doctor` ヘルプ表示を改善**: `--fix` の説明を `不足ツールを自動インストール (一部確認あり)` に、`--yes/-y` の説明を `確認プロンプトをスキップ (--fix 指定時のみ有効)` に変更。usage行も `doctor [--fix [--yes/-y]] [-h/--help]` 形式に更新し、`--yes` が `--fix` の従属オプションであることを明示。
- **`vs delete` の `--dry-run` オプションを削除**: 使用頻度が低いため廃止。
- **`vs rename` / `vs renumber` のオプションを整理**: `--dry-run` を廃止。`--chapter-step` / `-S` を `--step` / `-s` に統一。
- **`vs renumber` の章番号範囲を `create` コマンドの仕様に統一**: 通常章の連番開始を `11` → `01` に、付録の連番開始を `91` → `90` に変更。対象外は `00`（前書き）と `99`（後書き）のみとし、`01-89` が通常章、`90-98` が付録の範囲に統一。
- **`vs --help` の表示を全面改訂**: カテゴリ構成を「プロジェクト管理 / 執筆・編集支援 / 文章校正・統計 / 索引・用語集 / 画像・カバー / ビルド・出力・プレビュー」に整理。`pdf:read`、`index:auto`、`index:apply` など漏れていたコマンドを追加。`open` を「ビルド・出力・プレビュー」に移動。実際の出力元が `help_command.rb` であることも確認済み。
- **`vs open` にファイル名引数を追加**: `vs open 01-quickstart` や `vs open quickstart.pdf` のようにファイル名を指定して任意の PDF を開けるように改良。拡張子 `.pdf` は省略可能。プロジェクトルート直下 → `sources/` ディレクトリの順で探索する。
- **`vs pdf:compress` の引数で拡張子 `.pdf` を省略可能に**: `vs pdf:compress 01-intro` のように拡張子なしで指定できるように改良。
- **`vs clean` に `--index-dictionaries` オプションを追加**: `config/index_glossary_terms.yml` と `config/index_glossary_rejected.yml` を削除するオプション。著者が登録した用語データを含むため、削除前に確認プロンプトを表示する。`--all` には含めない仕様。
- **`vs clean --cache` の削除対象に `.cache/metrics/` を追加**: metrics キャッシュも `--cache` および `--all` で削除されるように対応。
- **`vs resize` のディレクトリ指定を簡略化**: `vs resize 01-intro` のように `images/` プレフィックスを省略して指定できるように改良。`images/` で始まらない場合は自動的に `images/` を前置して解決する。
- **`vs resize` に `--delete-originals` オプションを追加**: WebP 変換後に元の PNG/JPG ファイルを削除するオプション。変換成功したファイルのみを対象とし、削除前に確認プロンプトを表示する。
- **`vs lint:check` を廃止**: `vs lint` のエイリアスとして残っていた `vs lint:check` コマンドを削除。
- **`vs resize:high` / `vs resize:medium` / `vs resize:low` サブコマンドを廃止**: `vs resize --high` / `vs resize --low` オプション形式に統一。

### Added
- **各ディレクトリに `_README.md` を追加**: `contents/`、`images/`、`covers/`、`data/`、`templates/`、`sources/`、`codes/`、`stylesheets/`、`config/` の各ディレクトリに、役割・配置するファイル・関連コマンドを説明する `_README.md` を配置。`vs build` / `vs lint` / `vs metrics` の対象外。
- **マニュアルを拡充**: `32-doctor.md`（環境診断）、`13-chapter-management.md`（章の管理）、`33-utility.md`（ユーティリティコマンド集）、`34-book-yml.md`（book.yml リファレンス）、`80-developer.md`（開発者向けガイド）を新規作成。

## [0.35.0] - 2026-04-06

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
### Changed
- **`vs lint`コメント記法を統一**: textlint・spellcheck の両方で `vs-lint-disable`/`vs-lint-enable`/`vs-lint-disable-next-line` が機能するように変更。旧記法（`textlint-disable`/`spellcheck:ignore`）は非対応とした。

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

[Unreleased]: https://github.com/Atelier-Mirai/vivlio-starter/compare/v1.0.0-alpha...HEAD
[1.0.0-alpha]: https://github.com/Atelier-Mirai/vivlio-starter/compare/v0.39.2...v1.0.0-alpha
[0.39.2]: https://github.com/Atelier-Mirai/vivlio-starter/compare/v0.39.1...v0.39.2
[0.39.1]: https://github.com/Atelier-Mirai/vivlio-starter/compare/v0.39.0...v0.39.1
[0.39.0]: https://github.com/Atelier-Mirai/vivlio-starter/compare/v0.38.0...v0.39.0
[0.38.0]: https://github.com/Atelier-Mirai/vivlio-starter/compare/v0.37.0...v0.38.0
[0.37.0]: https://github.com/Atelier-Mirai/vivlio-starter/compare/v0.36.0...v0.37.0
[0.35.0]: https://github.com/Atelier-Mirai/vivlio-starter/compare/v0.35.0...v0.36.0
[0.35.0]: https://github.com/Atelier-Mirai/vivlio-starter/compare/v0.34.0...v0.35.0
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
