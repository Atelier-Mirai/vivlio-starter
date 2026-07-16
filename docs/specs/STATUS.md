# Status（仕様書の実装進捗）

> 💡 **運用のルール**
> - 実装が完了したら本ファイルから該当行を削除し、仕様書ファイルは `git mv docs/specs/xxx.md docs/archives/` で移動する（`docs/specs/archives/` ではなく `docs/archives/` が既存の置き場所）。
> - まだ仕様化していないアイデア段階のものは本ファイルではなく `PLANNED.md` に置く。仕様書を書いた時点で本ファイルへ移す。
> - 状態が変わったら都度その場で更新する。放置すると `PLANNED.md` に実装済み項目が残り続ける事故が起きる（2026-07-08 に実例あり: `terminal-literal-spec` 完了後も未完了項目として残っていた）。

---

## 一覧

`explanatory-diagram-spec.md`
: 図解注釈記法（Explanatory Diagram Syntax）の仕様。スクリーンショット等の画像に矩形囲み・矢印（pointer）などの注釈を SVG で重ねる記法を追加する。
  状態: 確定仕様・未着手
  次のアクション: Phase 0（showcase_svg_builder コア）から実装

`post-replace-list-retirement-spec.md`
: `config/post_replace_list.yml` を廃止し、全置換ルールを post_process のコード（`ReplacementRules`）へ移植する仕様。`[!]` 赤強調は prism_lines へ移設、会話記法（`.kaiwa`）とガイド線マクロ（`@lu` 系）は完全廃止、著者向けの置換ルール拡張機能も廃止する。
  状態: 確定仕様・未着手
  次のアクション: 実装（`ReplacementRules` の新設から）

`kindle-simple-header-svg-spec.md`
: Kindle 向け simple ヘッダーを SVG 画像化する仕様。
  状態: 将来タスク・未着手
  次のアクション: 優先度低

`nested-list-notation-spec.md`
: 箇条書き拡張（fancy list / 複合番号）の仕様。Pandoc `fancy_lists` 互換マーカー（`a.` `(A)` `i.` 等）＋複合番号 `:::{.outline-list}`＋ul レベル別マーカー「● ○ ・」。
  状態: 確定仕様・未着手（2026-07-12 策定。`nested-list-notation-ideas.md` からの昇格）
  次のアクション: 実装

`kindle-inline-math-textify-spec.md`
: Kindle 限定でインライン数式を SVG 画像でなくテキスト（`<sup>`/`<sub>`＋Unicode 記号）へ劣化変換し、フォントサイズ変更への追従不全を根治する仕様。KNOWN_ISSUES.md の数式サイズ不安定 2 件に対応。
  状態: 確定仕様・未着手（2026-07-12 策定）
  次のアクション: 実装

`direct-build-spec.md`
: PLANNED.md「設定ファイルを経由しない直接ビルドコマンド」の仕様。`vs build myawesome.md --theme blue` のように `book.yml` / `catalog.yml` を介さず単一 Markdown を PDF 化する。一時ワークスペースに最小プロジェクトを組み立て既存 `:single` パイプラインを chdir 流用する案（案A）を採る。
  状態: 提案仕様・未着手（2026-07-12 策定）
  次のアクション: 実装（`Common.build_direct_configuration` から着手）

`doctor-tool-upgrade-spec.md`
: PLANNED.md「`vs doctor` にツールのバージョンアップ機能」の仕様。`vs doctor --upgrade` として `--fix` の上位互換に。計画提示→確認→実行→再診断の 4 段構成。Ruby 本体・vivlio-starter 本体は自動更新せず新版検出＋手順案内のみ（導入経路が多様・gem 再インストールを伴うため）。
  状態: 提案仕様・未着手（2026-07-12 策定、2026-07-13 に Ruby/本体の新版お知らせ機能を追記）
  次のアクション: 実装（`tool_upgrader.rb` の骨格＋ TOOLS 定義から着手）

`characters-dialogue-spec.md`
: PLANNED.md「会話文（対話）記法の刷新と `config/characters.yml` 化」の仕様。記法は `:::{.talk}` 内 `キー: 発話`（ローマ字キー）に一本化。PDF/クリーン EPUB はチャットアプリ風吹き出し、Kindle は実体ラベル＋リテラル色の劣化表示。
  状態: 提案仕様・未着手（2026-07-12 策定）
  次のアクション: 仕様レビュー・確定後、`character_registry.rb` から実装（`contents/22-extentions.md` の会話文節が書き直し待ち）

`preflight-chapter-summary-spec.md`
: PLANNED.md「`vs preflight` の章別エラー・警告サマリー」＋付随の非対称（Guard 系 `:warn` が最終サマリーに反映されない）の仕様。横断的な `IssueRegistry` を新設し各発生源（LinkImageValidator・code-include・クロスリファレンス・QueryStream・Guard 警告）がブリッジする構成。
  状態: 提案仕様・未着手（2026-07-12 策定）
  次のアクション: 実装（`IssueRegistry` ＋ LinkImageValidator ブリッジから着手）

`command-feedback-spinner-spec.md`
: PLANNED.md「コマンド実行時の応答メッセージ」＋「CLI スピナー」を統合した仕様。Public コマンドは成功時に実績値入り 1 行報告を規約化。スピナーは外部ライブラリなしの自作（TTY かつ既定ログレベル時のみ、pipeline の `execute` 1 箇所に装着）。
  状態: 提案仕様・未着手（2026-07-12 策定）
  次のアクション: 実装（`Spinner` クラス＋テストから着手。応答メッセージ監査は `vs clean` から）

`at-directive-tier1-spec.md`
: `@` ディレクティブ Tier 1（`@pageref:id`・`@pagebreak:recto`/`:verso`・`@version`/`@today`/`@title`・`@qr:URL`・`@hspace:N`）の実装仕様。参照系は cross_reference 基盤＋CSS target-counter、定数/プラグマ系は ReplacementRules（`@vspace` の並び）、QR は rqrcode gem によるビルド生成 SVG。リフロー劣化は CSS カスケードで構造的に成立。
  状態: 確定仕様・未着手（2026-07-12 策定。[at-directive-ideas.md](at-directive-ideas.md) §2 Tier 1 からの昇格）
  次のアクション: 実装（§2.1 予約 ID 拡張から。§2.4 の VFM 見出し内 span は実ビルド検証を最初に）

`metrics-quality-warnings-spec.md`
: `vs metrics` の章別リストに「表現が単調」（MATTR ≤ 0.5）／「やや難解」（建石式 RS が Professional）の 🟡 警告を出す仕様。専用しきい値は設けず詳細分析の評価バンドと同一条件で発火（単一の真実・新設定キーゼロ）。`WarningChecker#quality_warnings` 新設、表示時合成でキャッシュ不変、`--warn`/`--json` にも統合。誤検知対策は exclude_chapters ＋統計的安定性ガード（トークン数 < mattr_window・10 文未満は判定しない）。
  状態: 確定仕様・未着手（2026-07-12 策定）
  次のアクション: 実装（`MATTR_MONOTONOUS_MAX` 定数抽出から。挙動不変の単独コミット可）

`page-break-control-spec.md`
: 改ページ制御の改善。PLANNED の 3 案から (b) 二重改ページの自動正規化（post_process の `PageBreakNormalizer` 新設・`---`/`@pagebreak` 直後の h2 でマーカーを無効化、`:recto` は h2 側を無効化して合流）＋ (c) `page.section_page_break` 設定キー（false で節改ページなし）を採用。(a) lint 警告は不採用（自動修正されるものへの警告はノイズ・§2.3 に記録）。
  状態: 確定仕様・未着手（2026-07-12 策定）
  次のアクション: 実装（(c) が独立で先行可。(b) の `vs-break-*` 対応は at-directive-tier1-spec 実装後）

`project-upgrade-command-spec.md`
: PLANNED.md「既存プロジェクトのアップグレード専用コマンド（`vs sync` / `vs upgrade`）」の仕様。コマンド名は `vs upgrade`。雛形マニフェスト `config/scaffold.lock` による三者比較（雛形旧版/新版/現物）で「雛形の変化」と「著者のカスタム」を区別する。
  状態: 提案仕様・未着手（2026-07-12 策定）
  次のアクション: 優先度 [Low] だが RC 前導入を推奨（lock なし旧プロジェクトを最小化できるため）。実装は lock 生成＋分類ロジックから着手

---

## 参考メモ

`release-1.0-considerations.md`
: RC版 → 正式版（1.0.0）へ移行するにあたっての検討事項メモ。
  状態: 検討メモ
  次のアクション: RC版完成後に再検討

`print-pdf-full-bleed-notes.md`
: print_pdf のフチなし（full_bleed）要素対応についての設計メモ。写真集・爪見出しなど紙の端まで達するデザイン要素を持つ本を将来作る際の判断材料として、導出方式と個別レンダー方式の違いを整理したもの。
  状態: 設計メモ・実装保留
  次のアクション: フチなし要素のある本が実際に企画されるまで着手しない

---

## メモ（依存関係・実装順序）

- **① print-pdf-derivation-spec と ② backlink-dedup-pdf-map-spec は 2026-07-10 に実装完了し `docs/archives/` へ移動した。**
  実装時の追加知見（qpdf `--overlay` が宛先 TrimBox に合わせて縮小配置する仕様と、手順順序 3a→4→5→3b への変更）は①仕様書 §3.8 に追記済み。

- **print-pdf-full-bleed-notes は実装対象ではない。**
  「フチなし要素のある本」が実際に企画されるまで保留（本文§0・§5に明記）。①（print-pdf-derivation-spec）の `full_bleed` 設定（§2.6）自体は①側の実装で完結するので、full-bleed-notes を待つ必要はない。

- **cover-cmyk-color-management-spec は 2026-07-11 に実装完了し `docs/archives/` へ移動した。**
  表紙 CMYK を Japan Color 2001 Coated の ICC ベース変換で PDF/X-1a:2001 化（出力インテント埋込）。
  ICC は @vivliostyle/cli 同梱の press-ready から自動解決（`output.print_pdf.icc_profile` で上書き可）。
  gs は SAFER 維持のため `--permit-file-read`、箱確定は `PrintGeometry.finalize_boxes!`（qpdf）。

- **code-include-line-number-spec と epub-code-line-numbers-spec は 2026-07-12 に実装完了し `docs/archives/` へ移動した。**
  コードインクルードの開始行を「F 案」（`epub-code-line-numbers-spec` 側で方式確定）と同時実装：範囲取り込みは実ファイルの行番号（`22, 23, 24…`）で表示され、EPUB/Kindle のコードブロックは「1 論理行＝1 `div.vs-code-line`」＋ぶら下げインデントへ全面刷新（クリーン EPUB は `::before` CSS カウンタ、Kindle は実テキスト `span.vs-code-ln` 注入）。`epub-code-line-numbers-spec` §4 の Kindle Previewer 実機チェックのみ未実施（受け入れ時に確認）。KNOWN_ISSUES.md の「EPUB(Kindle) のコード行番号と行の対応がずれる」は解消済みのため削除済み。

- **querystream-data-images-spec は 2026-07-12 に実装完了し `docs/archives/` へ移動した。**
  `data/*.yml` が参照する画像を各章の画像ディレクトリでなく `data/` 配下（`data/<データ名>/` または `data/images/`）に同居できるようになった。`DataImageResolver` が QueryStream 展開直後に解決し `html/images/data/` へミラー、PDF/EPUB/Kindle 同梱は既存機構が自動対応。残作業は query-stream gem v1.3.0 の RubyGems 公開のみ（vivlio-starter 側は当面ローカル path 参照で完結・仕様書 §5-7）。

- **generated-assets-cache-relocation-spec は 2026-07-11 に実装完了し `docs/archives/` へ移動した。**
  covers 生成物は `.cache/vs/covers/`・テーマ画像バリアントは `.cache/vs/theme-images/` へ移設。
  入稿用 CMYK カバー PDF はルート直下へ成果品複製（`{name}_{front,back}cover_v{ver}.pdf`）。
  旧配置の移行掃除（clean.rb）は 1 リリース後に撤去予定。

- **table-colspan-spec と explanatory-diagram-spec は互いに独立。** どちらから着手してもよい。どちらも `markdown_preprocessor.rb` の変換ステップに新規フックを挿入する点は共通するため、同時期に着手する場合はフック挿入順序（既存ステップとの前後関係）の衝突に注意。

- **lint-notation-guard-spec は 2026-07-16 に実装完了し `docs/archives/` へ移動した（調査報告 lint-notation-guard-report.md も同時にアーカイブ）。**
  Phase 0（`vs lint --fix` no-op 修復・2 パス方式）とPhase 1（`Lint::NotationGuard` 新設・allowlist VFM 5 エントリ撤去）を実装。実装中に G2 マーカー判定の厳格化（`:::-->` 巻き込みで textlint 暴走）と `Tempfile.new` の GC 削除による検査漏れ（既存潜在バグ）を追加で修正した——経緯は仕様書 §7 の追記を参照。

- **post-replace-list-retirement-spec は post_process 側の改修で、explanatory-diagram-spec（pre_process 側）と衝突しない。** 実装順はどちらが先でもよい。ただし前者はガイド線マクロ（`@lu` 系）を完全廃止し、後者（`.showcase` 記法）をその後継と位置づけている。code-include-line-number-spec とは `prism_lines.rb` を共に触るが、別メソッド（`[!]` 強調 vs `decorate_pre_tag`）のため独立。
