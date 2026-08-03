# Planned（将来計画）

本システムの将来対応・改善アイデアを目的別に整理する。

- 見出しは目的別の `##`／`###` に統一し、各項目は `-` の箇条書きで記す。
- 優先度は行頭に `[High]` / `[Medium]` / `[Low]` で付す（未判定のものは付けない）。
- 既存仕様書がある項目は末尾にファイル名を添える（`docs/specs/` / `docs/archives/` は付けない。実装後に移動しても壊れないようにするため）。

---

## Version 2.0 構想（メジャーアップデート）

後方互換を破る大きな方向転換を伴うため、v2.0 でまとめて取り組む。

- [High] **小説（挿絵入り）への対応**: 現在は技術書専用。小説向けレイアウト（縦書き・挿絵配置・章扉など）に対応できるようテーマ／組版を拡張する。
- [High] **テーマシステムの実装**: vivliostyle 公式の `bunko.css` などの既存テーマ CSS を活用。`book.yml` からのテーマ選択、CSS の動的切り替え、小説用縦書き・技術書用横書きのプリセット提供。
- [Low] **CLI 終了コードの体系化**: 現状「正常 0 / 問題あり 1」の 2 値を、UNIX 慣例（例: grep の 0=見つかった / 1=見つからない / 2=エラー）に倣いエラー種別ごとに分ける。影響範囲が広く後方互換を破るため v2.0 で対応。

---

## ビルド / 出力

- [Low] **画像の width 属性自動補完**: `![](foo.png)` のように幅指定なしでも、実寸やクラス指定に応じて `width=100%` 等を自動補う（大判図をページ送りにせず収めるため）。
- [Medium] **「表1＋背＋表4 を 1 枚にくるみ表紙」の形**: 入稿先の慣習でくるみ表紙を求められる場合も有るが、結合処理を伴う別機能になるため、現状は非対応。

- [Medium] $2^{1/3}$ $\sqrt{\pi r^2}$ $\pi$ などの TeX 記法を、2^(1/3)、√(πr²)、π の素の表記に改める機能（Kindle での表示を改善するため）は既に実装されています。逆に著者の書いた 、2^(1/3)、√(πr²)、π を $2^{1/3}$ $\sqrt{\pi r^2}$ $\pi$ などの TeX 記法に変換する機能の実装。

---

## 記法・置換ルール

- **`@` ディレクティブ拡張**: Tier 1（`@pageref`・`@pagebreak:recto`/`:verso`・`@version`/`@today`/`@title`・`@qr`・`@hspace`）は **2026-07-28 に実装完了** → `at-directive-tier1-spec.md`。Tier 2（`@nobr`・`@fill`・`@index`）と `@abbr` の代替案（用語集統合 or 標準 `*[…]:` `<abbr>`）は引き続きブレスト段階 → `at-directive-ideas.md`

- [Medium] **`vs furigana`（半自動ルビ付与）**: 小学生向けなど、対象読者の学年より上の漢字へ振り仮名 `{漢字|よみ}` を**半自動**で付けるコマンド。`vs metrics` の「漢字レベル（ルビ候補）」で**どの漢字が対象か**は把握できるので、その先の「本文へ実際にルビ記法を書き込む」変換を担う。
  - **対象の指定**: `book.yml` や引数で「基準レベル」を選ぶ（例: 小4向け＝小5以上／中学以上／常用外のみ、等。レベル定義は `furigana-level-spec.md` 参照＝`vs metrics` と共通の L0〜L4）。
  - **読みの生成と限界（最重要）**: 読みは MeCab から得るが、**まさにルビを振りたい稀な漢字（未知語）で最も外れる**（例「碍子」は `碍` が非常用で未知語となり誤分割・誤読になりやすい）。よって**全自動で正確なルビは不可能**という前提に立ち、(1) 読みが不確実・未知の語にはルビを付けずに**警告＋出現箇所を提示**して著者に委ねる、(2) 付けたルビも**要確認**として一覧化する、という半自動方式にする。将来的に漢字→音訓の補助辞書でカバー率を上げる。
  - **安全性・冪等性**: ファイルを改変するため、(1) 既に `{…|…}` でルビ済みの箇所を二重化しない、(2) コードブロック・URL・既存ルビ内は対象外、(3) `--dry-run` で差分プレビュー、(4) バックアップ or Git 前提。`vs metrics` は読み取り専用の統計に徹し、書き込み系はこの `vs furigana` に分離する。
- [Medium] `vs lint` に「交ぜ書き」検出機能を設ける。「だ円」->「楕円」、「けん引」->「牽引」、「ばん回」->「挽回」などの検出を行なう。

## 参照・索引・書誌

- [Low] **脚注・参考文献サポート**: 簡易 BibTeX / CSL 相当の仕組みを検討する。
- [Low] **索引語数の目安（`BASE_TERMS`）を実測で見直す**: 現在の値は刊行済み技術書 10 冊の実測だが、**`thorough`（丁寧に索引を拾う本）は 2 冊しかない**（226・228）。幅が狭いのは冊数のせいで、その帯が本当に狭いことを意味しない。索引付きの技術書 PDF が増えたら追加計測して更新する。計測方法・生データ・落とし穴は `index-size-calibration-data.md`（§2 に精度の限界、§8 に「語彙リストより機構」の一般則）。
- [Low] **索引の目安に使う文字数の基準を `vs metrics` と揃える**: 索引語数の目安は「地の文の文字数」（コード・記法を除く）から算出するが、`vs metrics` が著者に見せているのは生の文字数（コード込み・地の文の約 2 倍）で、**著者は目安の根拠になっている数字をどこにも見たことがない**状態にある。`metrics-char-count-basis-report.md` の論点 1〜3（表示と分量基準をどちらへ揃えるか）が決まったら、索引側の基準もそれに合わせる。

> **索引・用語集の仕上げ（RC 対象）**。仕様書 3 本のうち 2 本が実装完了。
>
> - `index-code-protection-unification-spec.md`（インラインコード保護の `Masking` 正典化）… **2026-08-02 完了**
> - `index-term-selection-spec.md`（どの語を載せるか）… **2026-08-03 完了・全 7 フェーズ**
> - `index-main-reference-spec.md`（参照をどう見せるか）… **Phase 1〜2 と R3 まで実装済み**。残りは候補の自動提示・未指定の警告・`reference_style`・ページ範囲圧縮
>
> 「索引辞書の stale な `context:` を自動で落とす」は **2026-07-16 に実装済み**だったため削除した（`index-glossary-consistency-spec.md`。`enrich_terms_with_context` は現在 `context_live?` で stale を捨てて補充する）。
>
> 主要参照の**節指定**（`main: 章#見出し`）と**原稿記法**によるマークは上記の対象外。必要になったら改めてここへ起こす。

---

## コンテンツ / テンプレート

- [Medium] **用語集テンプレートの標準添付**: よく用いる用語をまとめた用語集テンプレートを標準添付し、プロジェクト作成時または後から選択適用できるようにする。
- [Low] **テンプレ断片スニペット**: 注意 / 補足 / Tip などのコンポーネントを断片化して提供する。
- [Low] **Web アプリ連携**: `codes/` に置いた HTML/JS/CSS のサンプルを、書籍内で QR コードや URL として紹介する仕組み。PDF 生成という主用途からは外れるため優先度は低い。

---

## EPUB / Kindle

- [Low] **ポップアップ脚注（`epub:type="noteref"` / `"footnote"`）**: 参照番号をタップすると脚注が小窓で開く方式。Kindle(KFX)・Apple Books が対応しており、非対応リーダーは現状どおり本文に流し込まれるだけなので**加えるだけで壊れない**（追加であって置き換えではない）。2026-08-02 に脚注を「左罫つきの注記ブロック」として本文と切り分けたので**当面は不要**——参照の直後に読める形になっている。読者から「本文が脚注で分断される」という声が出たときに着手する。
  - **前提はすでに揃っている**（2026-08-02 に生成物で実測）。着手時に構造を作り直す必要はない。
    - `<html>` に `xmlns:epub="http://www.idpf.org/2007/ops"` が宣言済み（名前空間の追加作業は不要）
    - 参照リンク `<a id="fnref1" href="…#fn1">` の飛び先が `aside` の `id` と正確に対応している（`fn1`/`fn2`/`fn3`）
    - 段落内インライン span の `id` は `strip_inline_footnote_ids_for_epub!` が除去済みなので、`#fnN` の解決先が `aside` に一意（ポップアップの対象が曖昧にならない）
  - **作業は属性 2 つ**。`EpubBuilder#decorate_footnotes_for_epub!` が既に `aside.page-footnote-print[data-footnote-number]` を走査しているので、そこで `aside['epub:type'] = 'footnote'` を、対応する `a#fnrefN` に `epub:type="noteref"` を付ける。
  - **確認は実機で**。KFX のポップアップは epubcheck では検証できず、Kindle Previewer で開くしかない（`kindle-css-compatibility-notes.md` の実機確認の流儀に従う）。ポップアップ化すると `aside` は本文に出なくなるため、**CSS 側の注記ブロック体裁（`body.vs-epub aside.page-footnote`）を残すか外すか**も同時に判断する。

- [Low] **Kindle 固定レイアウト（`kindle.layout: fixed`・PDF ラスタライズ流用）**: A5 PDF をページ画像化して固定レイアウト KPF にする案。劣化対応不要で組版忠実だが、主力端末 6〜7″ は文庫（A6）サイズで判型が合わず、フォント可変・検索・配信料（約 ¥50〜90/冊 増）を失うため**見送り**。数式・図版主体の本や文庫判型向けの第 3 ターゲットとして RC 後に再検討。調査結果・実装スケッチ → `kindle-fixed-layout-ideas.md`

---

## 品質 / テスト

- [Low] **自動検証パイプライン（CI）**: 最小サンプルでのビルド、Lint、HTML ポスト処理テストの自動実行。
- [Medium] **Kindle Previewer 実機確認の積み残し**: 実装は完了しているが実機目視だけ未実施のものが 3 件ある。まとめて 1 回の確認で消化できる（索引の主要参照が入れば 4 件目になるので、それを待って一度に見るのが効率的）。
  - 入れ子リスト記法（`nested-list-notation-spec` §10-12）: ul のレベル別マーカー「● ○ ・」の実体注入
  - コード行番号（`epub-code-line-numbers-spec` §4）: 1 論理行＝1 行の対応とぶら下げインデント
  - `@` ディレクティブ Tier 1（`at-directive-tier1-spec` §3-4）: `@pageref` がページ番号なしのタイトルリンクへ劣化するか・`@pagebreak:recto` が単純改ページになるか・QR コードの表示
  - （実装後に追加）索引の主要参照（`index-main-reference-spec` §5.3）: `.main-ref` の太字が KFX で効くか

## コード整理

- [Medium] **クロスリファレンスの死にコードを撤去する**: `CrossReferenceProcessor.process_cross_references` は**未定義メソッド `generate_report` を呼ぶ到達不能コード**で、実ビルドが通る経路は `PreProcessCommands.process_cross_references_for_files`（`pre_process.rb`）のほう。委譲先の `MarkdownTransformer.process_cross_references` も存在せず二重に壊れている（2026-07-25 の preflight-chapter-summary 実装時に判明）。読む人を確実に誤らせるので撤去する。

### 堅牢性テスト（追加候補）

- [Medium] **11-3 巨大 YAML anchor の Billion Laughs 評価**: `aliases: true` 下でも Psych 5.x の制限で実害なしだが、上限値・挙動の明示的な検証余地あり。
- [Medium] **11-4 PDF 結合時の例外で中間 PDF を残す**: 結合例外時に中間 PDF を事後調査用に保持（`pdf_merger.rb` の例外ハンドリング強化）。
- [Medium] **12-2 / 12-3 冪等性・キャッシュ回帰**: 同一入力で複数回ビルドしても成果物が変化しないことの検証。
- [Medium] **`vivlio-starter-pdf` の堅牢性テスト整備**: 本体と同等の堅牢性テストをプラグインにも適用する。

---

## 開発者体験 / CLI UX

- [Low] **Linux / Windows の自動セットアップ対応（やるかもしれない枠）**: 現状 `vs doctor --fix` の自動インストールは macOS + Homebrew のみで、Linux / Windows は動作検証もできていない。将来的に Linux（apt / dnf など）や Windows（winget / Scoop / Chocolatey など）でも `vs doctor --fix` でひと通り揃うようにできると望ましい。需要と検証コスト次第で、対応するかどうかも含めて将来検討する。
- [Medium] **ビルドログ整備**: 各ステップに要約出力とエラーヒントを追加し、失敗時の原因特定とリカバリーを容易にする。
- [Low] **スタイルガイド整備**: 章タイプ別（preface / chapter / appendix / postface）の設計指針、ユーティリティクラス（`.aki`, `.aki2` ほか）一覧と使用例をドキュメント化する。

---

## 後日調査

- **A4 以外の判型での目次・索引・用語集**: この 3 ページは長らく `book-settings.css` を読んでおらず、`page-settings.css` の `@page { size: 210mm 297mm }` で **A4 固定**に組まれていた（`chapter-pagebreak-spec.md` §7.2 で link を追加して解消）。A5 / B5 でのビルド確認は未実施。
- **既定値の二重管理**: `page.section_pagebreak` などの既定が `common.rb` のスキーマと同梱 `book.yml` の両方にあり、黙ってずれる（実例: `section_page_break` 改名時にスキャフォールドが取り残された）。案 A = 既定値専用 YAML（`lib/vivlio_starter/config/defaults.yml`）を新設してスキーマをそこから読む／案 B = 同梱 `book.yml` とコード側既定の**キー名の対応**、および `theme.css` のフォールバック値とコード側定数の一致を、回帰テストで固定する。**スキャフォールドの `book.yml` を既定値の情報源にするのは不可**——あれは `copy_to_scaffold.rb` が root から作る「サンプル本の設定」で、`theme.color: red` のような本書固有の値と `{{MAIN_TITLE}}` のテンプレート記法が混ざっている。

  **資料: 既定値が実際にどこに置かれているか**（2026-08-01 実測）

  | キー | 既定値 | 既定の在り処 | 同梱 `book.yml` の値 |
  |---|---|---|---|
  | `theme.frontispiece.edge_inset` | 10mm | `theme.css:79` `--frontispiece-edge-inset` | 5mm |
  | `theme.frontispiece.heading_chars` | 8 | `book_settings_css.rb:184` `DEFAULT_HEADING_CHARS` ＋ `theme.css:87` の `103.7mm`（8 字ぶん） | 10 |
  | `theme.frontispiece.lead_chars` | 20 | `book_settings_css.rb:185` `DEFAULT_LEAD_CHARS` ＋ `theme.css:88` の `88.9mm`（20 字ぶん） | 24 |
  | `page.section_pagebreak` | true | `common.rb:219` スキーマ | false |
  | `page.chapter_pagebreak` | recto | `common.rb:219` スキーマ ＋ `book_settings_css.rb:397` `DEFAULT_CHAPTER_PAGEBREAK` | recto |
  | `output.targets` | pdf | `targets.rb:29`（空なら `pdf: true`） | pdf, epub, kindle |

  「既定値」列がキー未記載時に効く値、「同梱 `book.yml` の値」列は同梱本が実際に書いている値。
  **右 2 列が食い違うのは異常ではない**——同梱 `book.yml` は `copy_to_scaffold.rb` が root から
  作るサンプル本の設定であり、既定を上書きして見せるのが役目だからである。したがって
  **健全性の指標は値の一致ではなく「キー名が対応していること」**——実際に起きた事故は
  `section_page_break` → `section_pagebreak` の改名でスキャフォールドが取り残されたことで、
  値のずれではなかった。案 B の回帰テストもキー名の対応を見る形にする。

  最もずれやすいのは `heading_chars` / `lead_chars` の 2 行で、**既定が Ruby 定数と
  `theme.css` のフォールバック mm の 2 箇所にあり、字数 → mm の換算結果を手で焼き込んでいる**。
  実際 `theme.css:87` は `103.7mm`、生成器が 8 字から算出する値は `103.68mm` で、既に 0.02mm
  ずれている（実害は無いが、機械が見ていない証拠）。片方だけ直すと、キーを書いた本と
  書かない本で扉のレイアウトが変わる。

  なお**案 B の前例は既にある**——`book_settings_css_test.rb:557` が、字数 → mm 換算の
  依拠する `image-header.css` の `font-size` / `letter-spacing` を「変えたら落ちる」形で
  固定している。同じ形を `theme.css` のフォールバック値と `DEFAULT_HEADING_CHARS` /
  `DEFAULT_LEAD_CHARS` の対応にも足せばよい。

- **Kindle 表紙（KDP 渡し）** の扱い。
- **`kindlepreviewer` の `-locale`** が現在 `en` 固定（必要に応じて切り替え可能にするか検討）。
