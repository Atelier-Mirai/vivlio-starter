# Status（仕様書の実装進捗）

> 💡 **運用のルール**
> - 実装が完了したら本ファイルから該当行を削除し、仕様書ファイルは `git mv docs/specs/xxx.md docs/archives/` で移動する（`docs/specs/archives/` ではなく `docs/archives/` が既存の置き場所）。
> - まだ仕様化していないアイデア段階のものは本ファイルではなく `PLANNED.md` に置く。仕様書を書いた時点で本ファイルへ移す。
> - 状態が変わったら都度その場で更新する。放置すると `PLANNED.md` に実装済み項目が残り続ける事故が起きる（2026-07-08 に実例あり: `terminal-literal-spec` 完了後も未完了項目として残っていた）。

---

## 一覧

`at-directive-tier1-spec.md`
: `@` ディレクティブ Tier 1（`@pageref:id`・`@pagebreak:recto`/`:verso`・`@version`/`@today`/`@title`・`@qr:URL`・`@hspace:N`）の実装仕様。参照系は cross_reference 基盤＋CSS target-counter、定数/プラグマ系は ReplacementRules（`@vspace` の並び）、QR は rqrcode gem によるビルド生成 SVG。リフロー劣化は CSS カスケードで構造的に成立。
  状態: 確定仕様・未着手（2026-07-12 策定。[at-directive-ideas.md](at-directive-ideas.md) §2 Tier 1 からの昇格）
  次のアクション: 実装（§2.1 予約 ID 拡張から。§2.4 の VFM 見出し内 span は実ビルド検証を最初に）

`page-break-control-spec.md`
: 改ページ制御の改善。PLANNED の 3 案から (b) 二重改ページの自動正規化（post_process の `PageBreakNormalizer` 新設・`---`/`@pagebreak` 直後の h2 でマーカーを無効化、`:recto` は h2 側を無効化して合流）＋ (c) `page.section_page_break` 設定キー（false で節改ページなし）を採用。(a) lint 警告は不採用（自動修正されるものへの警告はノイズ・§2.3 に記録）。
  状態: **(c) 実装済み（2026-07-28）／(b) 未着手**
  次のアクション: (b) `PageBreakNormalizer` の実装。`hr.pagebreak` のみ先行でも可だが、`vs-break-*`（`@pagebreak`）対応は at-directive-tier1-spec 実装後にまとめるのが効率的

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

- **metrics-quality-warnings-spec は 2026-07-28 に実装完了し `docs/archives/` へ移動した。**
  `WarningChecker#quality_warnings` 新設＋表示時合成（`format_chapter_line(extra_warnings:)`）・`--warn`（`has_warning?(analysis:)`）・`--json`/`--yaml` の `warnings` 配列。新設定キーはゼロ、キャッシュ不変（表示時に毎回導出）。
  **仕様からの変更・実装時の判明事項**:
  - **`mattr_evaluation` は `case/in` → `case/when` へ書き換えた。** 範囲パターンの端点に定数は置けず `in ..MATTR_MONOTONOUS_MAX` は**構文エラー**になる（`expected a pattern expression after the range operator`）。`when ..CONST` なら通常の式評価なので通る。バンドの挙動は完全に同一（境界値 0.5/0.6/0.7 で確認済み）。
  - **文数は `analysis.basic.sentences` ではなく `analysis.readability.features.sentence_count` を使う。** 仕様書 §2.1 は前者を候補に挙げていたが、10 文ガードが守りたいのは「RS の母数」であり、それは RS 算出に使われた特徴量そのもの。`basic.sentences` はコード込みの本文全体を数えており母数がずれる。
  - **`Metrics::LiveDisplay` は死にコードだったため撤去した**（`live_display.rb` と `live_display_test.rb`）。`Runner` は自前の pending/next_display_index で逐次表示しており `LiveDisplay` を一切呼んでいなかった（`require` すら無く、参照は自身のテストのみ）。あわせて `contents/32-metrics.md` の「ライブプレースホルダー」「ANSI 制御でグラフ部分だけを差し替える」という記述も撤回した——これは `LiveDisplay` の挙動を書いたもので、実際の出力（章番号順の逐次出力 → 全体集計）とは食い違っていた。「サマリを章の解析前に表示する」という記述も同様に誤りだったので実挙動へ直した。

- **CLI 引数解析・コマンド応答の 3 本は 2026-07-27〜28 に実装完了し `docs/archives/` へ移動した。**
  `cli-option-parsing-report`（`--opt=value` の共通化）→ `cli-argument-parsing-spec`（オプション位置の自由化・ログレベルの一本化）→ `command-feedback-spinner-spec`（スピナー・応答メッセージ・確認プロンプト統一）の順で実施。
  **実装時の判明事項（次に CLI を触るときの前提）**:
  - 正規化・並べ替えの対象フラグは **`table.merged` から自動導出**する（`option_token_normalizer.rb`）。オプションを増やしても宣言の追加は不要。継承コマンド（`RenumberCommand`）を拾うには `table` ではなく `table.merged` が要る。
  - 公開コマンドの基底クラス `VsCommand` は **`options` をあえて置いていない**。置くと `Table#merged` が親の行を先に並べるため、子の宣言順に関わらず行順が `Options` 先に固定され、usage 表示も一律に変わる。共通オプションを足したくなったときはこの副作用を踏まえて判断すること。
  - **ドメイン層に「最終結果の報告」を置かない**。`execute_clean` は `vs build` の Step 0、`execute_resize_with_preset` は Step 1 が対象ディレクトリごとに呼ぶため、ビルド中に無関係な報告が何行も混ざる（実装中に実際に踏んだ）。表示はコマンドクラスの責務。`pdf:compress` のようにビルドと共用するものは `pipeline_mode?` で分岐する。
  - **`--log` を持たないコマンドの `log_info` が未使用とは限らない**。`clean` / `resize` / `create` / `index` / `pdf` の 118 箇所は `vs build --log` で実際に表示される。削除前にビルド経路から呼ばれないか必ず確認すること。
  - 撤去したデッドコード: `IndexBuildCommand`（`command_map` 未登録）・`rename` の dry-run 分岐（`--dry-run` がオプション定義に無く到達不能）。同種の「クラスやコードだけが残る」パターンは他にもありうる。

- **preflight-glossary-warning-scope-report は 2026-07-26 に対応完了し `docs/archives/` へ移動した。**
  §6.5（`vs preflight <章>` と `vs build <章>` の索引処理有無を統一・R4 ガード・文言修正・preflight の flush 漏れ修正）と §6.6（索引スキャン 8.3 倍高速化・黄金マスタで結果不変を確認・`\` を含む行の破損 3 箇所を是正）を実施済み。残る「索引系警告の `IssueRegistry` ブリッジ」（全章実行で出る正しい R4/R7 警告を章別サマリーへ載せるか）は `KNOWN_ISSUES.md`「索引・用語集スキャンの警告が章別サマリーに載らない」で継続管理する。

- **preflight-chapter-summary-spec は 2026-07-25 に実装完了し `docs/archives/` へ移動した。**
  横断収集器 `IssueRegistry`（`Issue`/`Counts` の Data・Monitor 同期）＋ 5 発生源のブリッジ＋章別サマリー表＋3 段階の最終行（`Common.log_result` に `:warning` 追加）。
  **仕様からの改良点・実装時の判明事項**:
  - クロスリファレンスのブリッジ先は仕様書が指した `CrossReferenceProcessor#log_duplicates` / `#log_reference_errors` **ではない**。実ビルドが通るのは `PreProcessCommands.process_cross_references_for_files`（`pre_process.rb`）で、`CrossReferenceProcessor.process_cross_references` は**未定義メソッド `generate_report` を呼ぶ到達不能コード**（`MarkdownTransformer.process_cross_references` も不存在＝委譲が二重に壊れている）。ライブ経路側へ record を置き、孤立ラベル警告も併せて拾うようにした。**この死にコードの撤去は未実施**（別タスク）。
  - 章ラベルは原稿の H1 を読む（`<br>`・振り仮名・強調記号を除去し全角 2 幅換算で 30 幅に切り詰め）。仕様書は表の体裁だけを示していたため、記号の縦位置が揃う実装を補った。
  - 索引・用語集スキャン（Step 4）の 🟡 は**未ブリッジ**（仕様書 §2.2 の表に無い）。章を絞った実行では辞書と catalog の突き合わせで構造的にノイズが出るため、分類の整理が必要 → KNOWN_ISSUES に記録。
  - 終了コードは仕様どおり `any_issues?` のまま（裸 URL 警告でも 1 になる歪みは KNOWN_ISSUES 送り・§2.3 の決定）。

- **characters-dialogue-spec / talk-display-options-spec / talk-auto-avatar-spec は 2026-07-25 に実装完了し `docs/archives/` へ移動した（コミット `5bc952ab`）。**
  旧 【先生】/【生徒】 ハードコード方式を廃し、`:::{.talk}` 内「キー: 発話」＋ `config/talk.yml`（display 設定＋話者定義）に一本化。表示は style（chat 吹き出し / inline）・name・avatar（`auto` で簡易アバター自動生成）の 3 軸。Kindle は KFX が flex・擬似要素・var() を解さないため EpubBuilder が DOM ごと inline 形式へ組み替え、話者色は hex リテラルで焼き込み。

- **nested-list-notation-spec は 2026-07-17 に実装完了し `docs/archives/` へ移動した（検討経緯 nested-list-notation-ideas.md も同時にアーカイブ）。**
  fancy list 13 様式（前処理 `convert_fancy_lists`・Kramdown 経由・fancy なしブロックはバイト一致素通し）＋ `:::{.outline-list}` 複合番号（CSS `counters()`・Ruby 実装ゼロ）＋ ul レベル別マーカー「● ○ ・」（文字列 `list-style-type: "・"` は Vivliostyle で有効と PDF 実測）＋ Kindle 実体マーカー注入（`decorate_list_markers_for_epub!`）。
  仕様からの改良点: 空行を挟んだ様式変更は警告でなく**別リストとして分裂**させる（Kramdown EOB マーカー `^` 注入。警告の修正案「空行を挟んで分ける」が通らない矛盾の解消）。§10-12 の Kindle Previewer 実機確認のみ未実施（受け入れ時に確認）。

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
