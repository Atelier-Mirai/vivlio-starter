# Status（仕様書の実装進捗）

> 💡 **運用のルール**
> - 実装が完了したら本ファイルから該当行を削除し、仕様書ファイルは `git mv docs/specs/xxx.md docs/archives/` で移動する（`docs/specs/archives/` ではなく `docs/archives/` が既存の置き場所）。
> - まだ仕様化していないアイデア段階のものは本ファイルではなく `PLANNED.md` に置く。仕様書を書いた時点で本ファイルへ移す。
> - 状態が変わったら都度その場で更新する。放置すると `PLANNED.md` に実装済み項目が残り続ける事故が起きる（2026-07-08 に実例あり: `terminal-literal-spec` 完了後も未完了項目として残っていた）。

---

## 一覧

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

- **explanatory-diagram-spec は 2026-07-15 に実装完了し、2026-07-16 に `docs/archives/` へ移動した（挿絵 explanatory_diagram.png・table-colspan-spec の挿絵 table.png も同時にアーカイブ）。**
  図解注釈記法 `:::{.showcase}`（rect/pointer/crop・合成 SVG 焼き込み・PDF はベクタ / EPUB・Kindle はラスター差し替え）。コミット `1f1799c9`。showcase 起因の textlint 誤検出は lint-notation-guard-spec で根治済み。

- **lint-notation-guard-spec は 2026-07-16 に実装完了し `docs/archives/` へ移動した（調査報告 lint-notation-guard-report.md も同時にアーカイブ）。**
  Phase 0（`vs lint --fix` no-op 修復・2 パス方式）とPhase 1（`Lint::NotationGuard` 新設・allowlist VFM 5 エントリ撤去）を実装。実装中に G2 マーカー判定の厳格化（`:::-->` 巻き込みで textlint 暴走）と `Tempfile.new` の GC 削除による検査漏れ（既存潜在バグ）を追加で修正した——経緯は仕様書 §7 の追記を参照。

- **post-replace-list-retirement-spec は 2026-07-12 に実装完了し、2026-07-16 に `docs/archives/` へ移動した（コミット `adaf6f2d`）。**
  旧 yml の全ルールを `ReplacementRules`（31 本）へコード化・`[!]` 赤強調は prism_lines へ移設・会話記法（`.kaiwa`）とガイド線マクロ（`@lu` 系）と著者拡張機能を廃止。フォローアップで `@nega`/`@posi`/`@comment`/`@commend` も廃止済み（**残る `@` 記法は `@vspace` のみ**＝`RESERVED_MACRO_IDS` も vspace 単独）。
  残作業だった `config/index_glossary_terms.yml` の stale な `context:` 抜粋も 2026-07-16 に解消済み（root/scaffold 同期・下記）。

- **索引辞書の stale context 15 件を除去した（2026-07-16）。** post-replace-list-retirement の残作業として起票した「旧 22 章の `post_replace_list.yml` 引用が context に残る」問題を調べた際、辞書全体で 15 件（724 中 2.1%）の context が現原稿と一致しない stale であることが判明（CMYK・doctor・編集者コメント節など複数の変更に由来）。原稿から消えた 15 件を機械的に除去（削除のみ・追加 0 行、語数 155 不変）、root と `ruby copy_to_scaffold.rb` で scaffold の両方を更新。
  **判明した設計上の注意**: `UnifiedIndexManager#enrich_terms_with_context` は **context が空の語だけ**本文から再抽出する（`unless enriched['contexts']&.any?`）。既存 context は stale でも温存されるため、仕様 §1.3 が想定した「`vs index:auto` で自動追従」は**成立しない**。context を空にすれば次回 auto が埋め直す。原稿を大きく推敲したら stale が溜まるので、将来的には enrich 側で「参照章に現存しない context を落とす」を検討（本タスクでは辞書側の除去のみ）。
