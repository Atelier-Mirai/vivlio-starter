# 変更履歴（Changelog）

このファイルには、本プロジェクトの主な変更内容を記録します。

記法は「Keep a Changelog」に基づき、Semantic Versioning（セマンティックバージョニング）に準拠します。

## unreleased

### Added
- [Medium] **コードインクルード範囲指定時の行番号を元ファイルの実行番号で表示**: `` ```include:prime.rb:22-25``` `` で取り込んだコードの行番号が、従来の `1` 始まりではなく元ファイルでの実際の行番号（`22, 23, 24, 25`）で表示されるようになった（PDF・クリーン EPUB・Kindle の全ターゲット対応）。開始行の情報は pre_process で消失していたため、フェンス情報文字列に GitHub パーマリンク風マーカー `` ```ruby:prime.rb#L22-L25 ``（終了行はクランプ後の実効値）を載せて VFM の figcaption 経由で post_process へ伝搬し、`PrismLinesCommands` が `pre[data-start]`＋インライン `counter-reset: linenumber N-1` へ変換する（figcaption の表示テキストはパスのみへ復元）。著者が直接 `` ```ruby:foo.rb#L5 `` と書く手書きマーカーも公開仕様（R9）。全文取り込み・救済不能フォールバックは従来どおり `1` 始まり。原稿 `contents/22-extentions.md`（行番号節・コードインクルード節）に追記。仕様書: [code-include-line-number-spec.md](docs/specs/code-include-line-number-spec.md)。

### Changed
- [Medium] **EPUB/Kindle のコード行番号を「行ブロック＋ぶら下げインデント」方式（F 案）へ全面刷新**: Kindle の 2 列テーブル方式（KFX がセル `width`/`nowrap` を尊重せず、2 桁番号の縦折返し・行間不均一が是正不能）と、クリーン EPUB の「長行折返しで Prism ガターの番号がずれる」未解決問題を、同じ構造で同時に解消。`EpubBuilder` が `pre.line-numbers` を「1 論理行 = 1 `div.vs-code-line`」の容器 `div.vs-code-epub` へ変換し（両フレーバ共通フェーズへ移動）、折返しは `padding-left`＋負の `text-indent`（ぶら下げインデント）でコード開始位置へ揃える。行番号はクリーン EPUB では CSS カウンタ `::before`（選択・コピーに混入しない）、Kindle では nbsp 右詰めの実テキスト `span.vs-code-ln` を注入（`vs-adm-label` と同じ実体注入パターン・等幅で桁が揃い縦折返しが原理的に起きない）。範囲 include の `data-start` は容器へ引き継がれ両フレーバで開始値として消費される。`code.css` の Kindle テーブル CSS は F 案 CSS へ置換（要 `ruby copy_to_scaffold.rb` 同期）。PDF の Prism ガターは不変。仕様書: [epub-code-line-numbers-spec.md](docs/specs/epub-code-line-numbers-spec.md)。

### Fixed
- [Medium] **PDF の章扉背景（frontispiece）が左上へ偏って配置されていた不具合**: Vivliostyle は `background-position` の calc() 内 `var()` を解さず**宣言ごと落とす**ため、`@page :nth(1)` の背景が初期値（0 0 = 左上）へ偏り、左上の飾りがページ端ぎりぎり・右下の飾りが内側へ寄っていた（`background-size` 側の calc()+var() は解されるためサイズだけ正しく、位置だけ壊れる）。`image-header.css` は var 不使用の `center center` を既定とし、綴じオフセット（`--frontispiece-binding-offset` 由来）は生成物 book-settings.css が**リテラル値の `@page :nth(1)` 上書き**として焼き込む方式へ変更（`@page { size }` のリテラル必須と同型・`frontispiece_position_rule`）。単章ビルドのピクセル比較でリテラル直書きと同一出力を確認。
- [Medium] **EPUB/Kindle の章扉を PDF と同じ「見出し → リード文 → 裾飾り」の読み順へ（扉絵の上下分割）**: 従来は全面 1 枚の扉絵画像が h1 に入るため、リーダーがページ高さへフィットさせて幅が狭くなり、リード文は扉絵の下（実質ページ末尾）へ追いやられていた（epub_chapter5 実測）。扉絵を **上部（飾り＋章番号＋タイトル・原画の 0〜62%）と裾（文字なしの飾り・62%〜）の 2 画像へ分割合成**し（`FRONTISPIECE_SPLIT`・SVG viewBox の帯切り出し）、裾は `chapter-lead` の直後へ `<img class="vs-frontispiece-tail" alt="">` として注入する。裾 SVG/JPEG は番号・タイトルを含まないため全章で 1 枚を共用（キャッシュキー同一）。
- [High] **コード退避（Masking）がフェンス終端の改行まで飲み込み、行頭 `:::` 前提の変換を壊していた不具合**: `Masking.replace_fenced_blocks` がフェンスブロックを終端行の改行ごとプレースホルダへ退避していたため、退避中テキストで後続行がプレースホルダと同一行に癒着し（例: `__VS_CODE_SPAN__13__:::`）、行頭 `:::` を前提とするコンテナ変換が閉じを見失っていた。実害として 22 章の**手書き `:::{.book-card}` が直前の `:::{.output}`（フェンス入り）に飲み込まれて変換されず**、`**タイトル**` が生のまま・`book-info` 構造なしで全ターゲット（PDF/EPUB/Kindle）に出ていた。フェンス終端の改行をプレースホルダの外へ残すよう修正（復元の往復同一性は不変）。QueryStream 展開由来のカードは影響なし。
- [Medium] **クリーン EPUB で扉絵・節絵・リード文に PDF 用レイアウト CSS が誤適用されていた不具合**: `image-header.css` の PDF 用ルール（`body.vs-header-image` 配下）は components.css の EPUB リセットより特異度が高く、EPUB でも勝っていた。実害: (1) h1 扉絵が `inline-size: clamp(≈110mm)` でページ幅に対し極端に幅狭（epub_h1）、(2) 節絵が `.section-topic` の **150px 固定グリッド行**に収まらず後続コンテンツを覆い、ページ跨ぎで上下に割れる（epub_h2_b）、(3) `h2::before` の背景飾りが合成 SVG と二重描画、(4) `.chapter-lead` が PDF 扉用の幅・負マージンで異常に狭い。EPUB 限定マーカー `body.vs-epub` を重ねた上書きルールを components.css へ追加して解消（PDF には vs-epub が無く不発）。あわせて合成 SVG ルートへ intrinsic size（`width`/`height` 属性）を明示し、リーダーの縦横比誤判定を防ぐ。
- [Medium] **節絵（h2）見出しの「長いと極小・短いと過大」を解消 — 基準サイズ固定＋2 行折返しへ**: kindle_h2_c/d/e の実測フィードバックに基づき、節絵フォントを全節共通の基準（height×0.14 = e「ちょうどよい」相当）へ固定し、1 行に収まらない長い節題は**縮小せず 2 行へ折り返す**方式に変更（2 行でも収まらない例外のみ縮小）。半角文字は全角の約 0.55 として表示幅を概算し、Latin 語の途中では直近の空白で折り返す。扉絵（h1）タイトルも 1 行 9 字 → 11 字に調整し「拡張記法リファレン／ス」級の不格好な折返しを解消。
- [Medium] **EPUB/Kindle で `kbd` のキーキャップ表示（keyfont）が効いていなかった不具合**: EPUB はフォント非埋め込みが既定（`localize_assets!` が `fonts/` を除外・`sanitize_epub_css!` が `@font-face` を全除去）のため、〘Ctrl〙 のキーキャップ描画が素の等幅文字へ落ちていた。keyfont は本文フォントと違いリーダー側に代替が存在しないため、**この 1 書体だけ実体（TTF・約 90KB）を選択同梱**し（`keyfont_asset?`・OTF 原本は運ばない）、対の `@font-face` も選択保持する（`strip_font_faces_except_keyfont`）。Kindle は `kbd { font-family: keyfont, var(--font-code) }` の `var()` で宣言ごと落ちるため、`body.vs-kindle kbd { font-family: keyfont, monospace }` の具体値ルールを `chapter-common.css` へ追加（Kindle 劣化規約）。
- [Medium] **Kindle でコード行番号が二重表示される不具合（F 案実装の追い修正）**: Kindle の body は基底マーカー `vs-epub` と `vs-kindle` の両方を持つため、クリーン EPUB 用の CSS カウンタ行番号（`body.vs-epub .vs-code-line::before`）が Kindle にも当たり、実テキスト注入（`span.vs-code-ln`）と併せて番号が 2 列出ていた（Kindle Previewer は `::before` を描画する）。カウンタ 3 ルールを `body.vs-epub:not(.vs-kindle)` へ限定して解消。
- [Medium] **EPUB/Kindle の節絵（h2 合成画像）の見出し文字サイズが節ごとに不揃いだった不具合**: `HeadingImageComposer.ornament_svg` のフォントサイズが「幅 80% いっぱいへの拡大＋clamp」だったため、短い節題（例「8-1 概要」）は上限（height×0.34）に張り付いて巨大化し、長い節題（例「7-5 トラブルシューティング」）は下限（height×0.16）でも幅からあふれていた。**全節共通の固定基準（height×0.22）＋幅 88% に収まらない長文だけ縮小**へ変更し、通常長の節題は同一サイズで揃うようにした。
- [Low] **`code.css` が未定義のカスタムプロパティ `--code-font` を参照していた不具合**: 定義されているのは `--font-code`（`page-settings.css`）のみで、フォールバック無しの未定義 `var()` は宣言ごと無効化されるため、`language-*` クラスを持たない素のインライン `<code>`（本文中の `` `book.yml` `` 等）が本文の明朝で組まれていた。`techbook: true` のときだけ Techbook の別名注入 `--code-font: var(--font-code);` で救われるモード依存の潜在バグだったため、参照側を `var(--font-code), monospace` へ統一して恒久解消し、Techbook の別名注入は削除（Type 3 対策の `font-family … !important` ブロックは残置）。（要 `ruby copy_to_scaffold.rb` 同期。code-include-line-number-spec §1.6/§3.5）

### Changed
- [High] **表紙 CMYK を ICC ベース変換の PDF/X-1a:2001 化（カラーマネジメント実装）**: 従来の表紙 CMYK は `magick -colorspace CMYK` 一発で ICC も出力インテントも無く、色がくすみ・ビューア解釈も不一致だった（docs は「PDF/X-1a・Japan Color 2001 Coated 推奨」と謳うが実装は未対応で乖離）。新設 `Build::CmykConverter` で、レイアウトを RGB で作った表紙を Ghostscript により **Japan Color 2001 Coated の ICC ベース CMYK 変換＋出力インテント埋め込みの PDF/X-1a:2001** として書き出す。ICC は **@vivliostyle/cli が推移的に同梱する press-ready の `JapanColor2001Coated.icc`** を自動解決（gem への ICC 再配布・ライセンス調査は不要。`output.print_pdf.icc_profile` で任意プロファイルも指定可）。gs 10.x の SAFER で ICC 読み取りが拒否される問題は `--permit-file-read` で SAFER を維持したまま回避（press-ready 4.x が gs 10.x で失敗する落とし穴を踏まない）。gs が pdfwrite で TrimBox/BleedBox を落とすため、箱の確定は既存の `Build::PrintGeometry.finalize_boxes!`（qpdf・構造保存で OutputIntent を保持）で行う。PNG（master）経路・SVG（light/dark）経路の両方に適用（SVG 経路は従来 RGB のまま「CMYK カバー」を名乗っていたのも是正）。ICC が見つからない環境では従来の素朴 CMYK にフォールバック。docs（43-cover.md / 44-build.md）を実装に一致させた。仕様書: [cover-cmyk-color-management-spec.md](docs/archives/cover-cmyk-color-management-spec.md)。
- [High] **ビルド時生成資産（covers 生成物・テーマ画像バリアント）を `.cache/vs/` へ移設**: 著者ディレクトリへ書き込む最後の 2 系統の生成物を生成キャッシュへ移し、「著者ディレクトリ＝ソースのみ、生成物＝.cache」の一貫性を完成させた。(1) `vs cover`／ビルド内自動生成が出力する PDF・JPG・SVG 中間物は `covers/` ではなく `.cache/vs/covers/` へ、(2) `ImageGenerator` の `*_portrait.webp` / `*_landscape.webp` バリアントは `stylesheets/images/` の隣ではなく `.cache/vs/theme-images/`（images root からの相対サブパス維持）へ生成する。`covers/` はマスター画像・ユーザー SVG・テンプレートのみのソース置き場に純化され、scaffold の `.gitignore` から `/covers/` ＋ `!/covers/*.svg` のハック構成を撤去（**著者のマスター画像がデフォルトで git 管理されるようになった**）。ビルドで `stylesheets/images/bundled/` に生成 webp が湧いて git status を汚す問題も解消。book-settings.css のバリアント参照は `theme-images/…`（生成位置基準）へ短縮され、EPUB へは book-settings.css が参照する分だけを選択同梱する（Kindle は従来どおり WebP 非同梱）。**入稿用 CMYK カバー PDF は成果品としてルート直下へ複製**するようになった（`{project.name}_{front,back}cover.pdf`・`include_version` 準拠。print PDF と同じ場所で入稿一式が揃う）。既存プロジェクトの旧配置の残骸は `vs clean --cover` / `--generated-images`（`--all` 含む）が 1 リリースの間だけ移行掃除する。手動で削除する場合の対象: `covers/*.pdf`・`covers/*.jpg`・`covers/*_{light,dark}.svg`・`covers/*_rendered.svg`・`stylesheets/images/bundled/*_{portrait,landscape}.webp`。`stylesheets/theme.css` の `--section-bg-image` / `--frontispiece-image` の既定値 2 行は削除（book-settings.css が毎ビルド必ず設定するためデッドコードだった）。仕様書: [generated-assets-cache-relocation-spec.md](docs/specs/generated-assets-cache-relocation-spec.md)。
- [Medium] **`vs doctor` で inkscape を必須（🔴）から任意ツール（🟡）へ格下げ**: カバー SVG のラスタライズ主経路が rsvg-convert になり、inkscape は ImageMagick の SVG フォールバックでしか使われなくなったため（rsvg-convert さえ健全ならカバー生成は inkscape 無しで通る）。kindlepreviewer と同じ「任意ツールは fix 時のみ導入対象」方式にし、不在/破損時は 🟡 注記（復旧コマンド `brew reinstall --cask --force inkscape` を明示）に留め、他が揃っていれば `🎉 すべての必要ツールが見つかりました` で成功終了する。あわせて `vs doctor --fix` の inkscape 導入を `install_inkscape_macos!` に切り出し、通常の `brew install --cask inkscape` が半壊 cask（記録は在るのに `/Applications/Inkscape.app` が消え、アップグレード扱いの purge に失敗する状態）で失敗した場合は `brew reinstall --cask --force inkscape` で自動復旧するようにした。
- [High] **入稿用 PDF（print_pdf）を閲覧用 PDF から導出する方式へ移行（①「pdf ＋トンボ＝ print_pdf」）**: 従来は本文・前付・奥付を `--crop-marks --bleed` 付きで**個別に再レンダリング**していた（実測 192.5s・レンダ 3 回）。これを、閲覧用の中間 PDF（`_titlepage_legalpage.pdf` / `_sections.pdf` / `_colophon.pdf`・dedup 済み）を qpdf 結合し、**qpdf `--update-from-json` によるジオメトリ変換**（内容の等倍平行移動＋MediaBox 拡張＋アノテーション/`/Dests` 座標シフト・`Build::PrintGeometry` 新設）→ **qpdf `--overlay` によるトンボ重畳**（Prawn 生成の 1 ページを `--repeat` で全ページへ・`Build::CropMarksOverlay` 新設、描画幾何はカバーと共通化）→ 隠しノンブル → **TrimBox/BleedBox 確定**の順で導出する方式へ変更（本体 MIT のみ・プラグイン不要）。入稿用の本文が閲覧用と**同一レンダリング由来**になり、二系統レンダに起因するページずれ・内容差・入稿用レンダの flaky（body-guard リトライ）が構造的に消える。`output.print_pdf.full_bleed: true`（本文にフチなし＝塗り足しまで届く要素がある本）では従来の個別レンダリングへフォールバックする（閲覧用 PDF は仕上がりで裁たれており塗り足しを復元できないため。回転ページ等の導出不能 PDF 検出時も自動退避）。パイプラインは `derive_print` 判定をステップ表の条件列に吸収し、print_pdf 単独ビルドでも閲覧用中間物（`build overall pdf` / `build front pages and tail`）を生成する。**実装時の追加発見（仕様書 §3.8 に追記）**: qpdf `--overlay` は重ねる側を宛先ページの **TrimBox（無ければ CropBox）に収まるよう縮小配置**するため（B5 実測 0.85 倍・`--help` に記載なし）、初版仕様の手順順序（ボックス確定→overlay）ではトンボ・ノンブルが仕上がり線の内側へ入り込む。手順を「3a ジオメトリ拡張 → 4 トンボ → 5 ノンブル → 3b ボックス確定」へ変更し（`PrintGeometry` を `expand!` / `finalize_boxes!` の 2 段に分離）、順序契約は正順（等倍）・逆順（縮小再現）の両方向を qpdf 実機テストで固定。従来レンダのフォールバック経路（vivliostyle 出力＝ TrimBox 持ち）では順序変更で回避できないため、`Build::QpdfOverlay` が重畳中だけ MediaBox 以外のページボックスを退避・復帰するガードで対処（導出フローでは退避対象が無く素通り）。仕様書: [print-pdf-derivation-spec.md](docs/archives/print-pdf-derivation-spec.md)。
- [High] **Step 8（backlink dedup）のページマッピング取得を Playwright から PDF `/Dests` 解析へ置換（②）**: 従来は vivliostyle preview をヘッドレス起動し Playwright で全ページのブラウザレンダリング完了を待って DOM を走査していた（409 ページで約 73 秒）。vivliostyle build が生成する PDF は **id を持つ全要素の named destination を文書カタログの `/Dests` 辞書に書き出しており**（名前に `…#gls-src-…` の形でアンカー ID がそのまま埋まる）、Step 7 の `_sections.pdf` を pdf-reader で読むだけで「アンカー ID → ページ番号」マップが決定的に得られる（スパイク実測 0.52 秒・公式 dedup と判定一致。境界 15 件はむしろ実 PDF を測る新方式が正確）。`Build::PdfPageMapExtractor` を新設（vivliostyle の `:XXXX` UTF-16 hex エスケープ復号込み・`PageMapping` Data 定義を移設し `BacklinkDeduplicator` は無修正）、`BacklinkDedupOrchestrator` の Phase 1 を置換。Phase 3 の再レンダは `rebuild_pdf:` 引数で「閲覧用 PDF を出す場合または①の導出を行う場合」のみに限定（従来レンダの print_pdf 単独経路では print レンダ自体が浄化済み HTML を読むため不要——従来は無条件再レンダで無駄だった）。print_pdf 単独経路では `_sections.pdf` 不在時に一度だけ本文をレンダしてから抽出する（従来 preview が全ページをレンダしていたのと同等コストで、①導出のソースにもなる）。`/Dests` が無い・fragment 付きの名前が皆無の場合は例外→既存 rescue で警告スキップ（vivliostyle 更新の検知点）。**Playwright・preview サーバー・ポート 13100 への依存が丸ごと消滅**: `page_mapping_extractor.rb`・`extract_page_mapping.mjs` を削除し、`vs doctor` の playwright/chromium チェックと `--fix` インストール、package.json の `playwright` devDependency、README・原稿章（51-doctor / 61-developer / 91-install / 44-build）の記述を撤去・更新。仕様書: [backlink-dedup-pdf-map-spec.md](docs/archives/backlink-dedup-pdf-map-spec.md)。

- [Medium] **`config/post_replace_list.yml` の全置換ルールを post_process のコードへ移植（`ReplacementRules` 新設）**: VFM→HTML 変換後の文字列置換ルール集を実行時 YAML パースから Ruby コードへコード化した。旧 yml の 34 ルール（`:::{.class}` の div 化・p/div ねじれ修正・空段落除去・`@vspace` 等マクロ・`〘〙`→`<kbd>`・`{.aki}` クラス化ほか）を**同一の正規表現・同一の適用順・同一の保護モード**で `lib/vivlio_starter/cli/post_process/replacement_rules.rb` に定義（旧 yml とのバイト同一性を回帰テストで固定）。適用エンジン `HtmlReplacer` は Rule 配列前提へ縮小し、パターン文字列からのモード推定（`rule_mode`）と `:code_aware` 分岐を撤去、`mode` を各ルールに明示化した。`[!]` 赤強調（Prism コメント強調）は Nokogiri ベースで `prism_lines.rb` へ移設（旧・一般コメント／HTML コメントの 2 ルールを 1 パターンへ統合）。設定キー `book.yml` の `files.post_replace` と `REQUIRED_YAML_FILES` からの `post_replace_list.yml` を撤去し、`vs new` 生成物・`vs doctor` 復元対象からも外した（既存プロジェクトに残る同ファイルは無視）。仕様書: [post-replace-list-retirement-spec.md](docs/specs/post-replace-list-retirement-spec.md)。

### Removed
- [Medium] **著者による置換ルール拡張機能（`post_replace_list.yml` への自作正規表現追加）を廃止**: 同ファイルのルールは大半がシステム成立に不可欠で「設定」ではなく実装であり、実行時 YAML パースはエスケープ二重化（YAML＋Regexp）で編集事故を招くため、ファイルごと廃止しコード化した（上記 Changed 参照）。独自装飾は `:::{.myclass}` ＋ `stylesheets/custom.css`（`preflight.allowed_classes` で警告回避）で実現する方針へ 22 章コラムを書き換えた。
- [Medium] **会話文記法（`【先生X】`／`【生徒X】` → `p.kaiwa.sensei/seito`）を廃止**: `先生`/`生徒` をハードコード置換する経路と `stylesheets/replace-list.css` の `.kaiwa` 系 CSS を削除。会話文記法は PLANNED.md の刷新（`config/characters.yml` 化）へ一本化する。
- [Medium] **Planned のガイド線マクロ（`@lu`/`@ld`/`@ru`/… 系の絶対配置＋SVG ガイド線）を完全廃止**: 正式サポートに至らないまま撤去し、`RESERVED_MACRO_POSITION_PREFIXES` と `.figure-guides` の痕跡を削除。**後継は図解注釈記法 [explanatory-diagram-spec.md](docs/specs/explanatory-diagram-spec.md)（`.showcase` 記法）**。
- [Medium] **余白マクロの別名 `@nega` / `@posi` と編集者コメント `@comment` / `@commend` を廃止（残る `@` 記法は `@vspace` のみ）**: `@nega:N`／`@posi:N` は `@vspace:-N`／`@vspace:N` の完全な後方互換別名で実使用が無く、「後方互換性の完全排除」方針に沿って撤去。編集者コメント `@comment:…@commend`（`.hen-comment` 黄色ハイライト化）は、HTML コメント `<!-- TODO: … -->` / `<!-- FIXME: … -->` で上位互換に代替でき（本番 PDF に残らない・エディタの TODO ハイライトが効く）、かつ現状は除去機構が無く入稿物にハイライトが残る地雷であったため機能ごと廃止。これに伴い `.hen-comment` CSS・22 章「編集者コメント」節・`templates/chapter.md` の実演・PLANNED の「@comment 一括除去オプション」項目・予約 ID（`RESERVED_MACRO_IDS` は `@vspace` のみに縮小）を整理。既存原稿に残る各マクロは変換されず素のテキストとして出力される（`@nega` 等は未定義ラベル警告の対象）。

### Fixed
- [Low] **`rake test` が約 1/3 の頻度で Kramdown 系テスト 14 件を落とす flaky を解消（strscan の Gemfile 一本化）**: Ruby 4.0 環境では strscan が default gem（3.1.6 = stdlib 実体）と通常 gem（3.1.8 等）で同居し、Minitest のランダム実行順によっては実行途中に別バージョンが activate されて C 拡張が二重初期化され（`already initialized constant StringScanner::Version` 警告が常時 2 件）、StringScanner のクラス同一性が壊れて Kramdown が `wrong argument type StringScanner (expected StringScanner)` で落ちていた。`RUBYOPT=-rstrscan` 等の起動時プリロードでは 2 回目の遅延ロードを防げず不確定（5/8 通過）だったため、Gemfile に `gem 'strscan', '~> 3.1'` を明示して Bundler 起動時に 1 バージョンだけを確定 activate させ、全 `require 'strscan'` を単一ファイルへ解決する方式で根治（二重初期化警告 2→0 件・`rake test` 8/8 通過を実測）。gemspec（実行時依存）は変更なし — インストール済み gem の実行は require 順が決定的で本問題は発生しない。
- [Medium] **カバー SVG のラスタライズ（EPUB 表紙 JPG 等）が壊れた inkscape を踏んで失敗する不具合**: `convert_svg_to_raster` は `magick` を呼ぶだけだったが、ImageMagick は SVG デコードを inkscape delegate へ委譲するため、環境によっては壊れた inkscape（実体を失った Homebrew cask ラッパー等）を踏んで表紙 JPG 生成が失敗していた（light/dark テーマの EPUB 表紙が欠落）。ラスタライズを **rsvg-convert（librsvg）優先**へ変更し、SVG→PDF 経路（`convert_svg_to_pdf`）と同じエンジンに揃えた（表紙 PDF と JPG の絵柄も一致）。librsvg は JPEG 出力を持たないため JPEG は PNG を経由して ImageMagick で書き出す（PNG 入力なので inkscape delegate を踏まない）。rsvg-convert 不在時は従来どおり ImageMagick へフォールバック。
- [Medium] **`vs doctor` が壊れた inkscape を「✅ OK」と誤報告する不具合**: 存在チェック（`command_exists?`）が「ファイルが在り実行ビットが立つ」だけを見ていたため、削除済みアプリ本体を exec するラッパー（在るのに `exit 126` で起動失敗）を見抜けなかった。`command_runnable?` を新設し、`--version` の実起動で終了ステータスまで確認する機能チェックへ変更（inkscape に適用）。
- [Medium] **`vs doctor` の全ツール診断を「存在チェック」から「機能チェック（実起動）」へ全面移行**: inkscape 以外にも、`command_exists?`（存在＋実行ビットのみ）で判定していた全 CLI ツール（node / textlint / vivliostyle / qpdf / pdfinfo / pdftoppm / gs / imagemagick / vips / tesseract / mecab / rsvg-convert）を `cli_tool_ok?`（`--version` 実起動で終了ステータス確認）へ変更。「バイナリは在るが dylib 切れ・ダングリング symlink で起動失敗」も「見つかりません」として検出できる（`🎉 すべての必要ツールが見つかりました` の信頼性向上）。poppler 系（pdfinfo / pdftoppm）は `--version` を解さないため `-v` を使う（`VERSION_ARGS`）。kindlepreviewer も inkscape と同じ「シムだけ残って `.app` 本体が消えた」半壊を検出するため、シム存在＋`.app` 実体存在の機能チェック（`kindlepreviewer_functional?`）に変更（GUI アプリのため `--version` 実起動はしない）。waifu2x は自己完結バイナリ（シム経由でない）のため従来どおり実体存在チェック。診断時間は数秒増えるが、動かないツールを OK と誤報告しない正確さを優先。
- [High] **入稿用 PDF の目次・索引・用語集リンクが全滅していた不具合（①Phase 0）**: `PrintPdfBuilder#merge!` の qpdf 結合が `base_pdf` 未指定のため先頭ファイル（前付）がベースになり、本文が持つ named destinations（`/Dests` 辞書・数千件）が丸ごと捨てられていた。クリック領域（アノテーション）は残るが参照先が解決できず、**全リンクが無反応**になっていた。本文（`_sections_print.pdf` / 導出時は `_sections.pdf`）を `base_pdf:` に指定して解消（閲覧用 `merge_all_pdfs!` と同じ規約。qpdf 実機で `/Dests` 1 → 3,361 件への回復を確認済み）。
- [High] **Standard モードの隠しノンブル書き込みが入稿用 PDF のリンクを全損させていた潜在バグ**: `StandardProvider` のノンブル合成（CombinePDF）は保存時に文書カタログの `/Dests` 辞書を再構築せず全損させるため、ノンブル書き込み自体がリンクを壊していた。ノンブルを**プロバイダ非依存の本体共通実装**へ移設（`Build::NombreStamper`: Prawn 描画〔HackGen TTF サブセット埋め込み・FT-02 維持〕＋ qpdf `--overlay` 1:1 重畳・構造保存）し解消。`StandardProvider` から `stamp_nombre!` / `create_nombre_pdf` を撤去し、プロバイダの責務は「ページ数取得・空白ページ生成・アウトライン付与」に縮小（AGPL プラグインの役割は従来どおり outline のみ）。`/Dests` 保持・非縮小（TrimBox 退避）の回帰テストを追加。

### Added
- [Medium] **拡張パイプテーブル（横結合 colspan・複数行ヘッダー）＋ rotate-table の版面自動フィット（統合テーブル変換）**: 素のパイプテーブルのまま、空セル `||`（直前セルへマージ＝colspan）と、区切り行より上の複数行ヘッダー（`<thead>` の複数 `<tr>`）が書けるようになった。コンテナ（`:::{...}`）で囲む必要はなく、著者は拡張 GFM テーブルとしてそのまま執筆できる。パーサを新モジュール `TableConverter`（`lib/vivlio_starter/cli/pre_process/table_converter.rb`）へ一元化し、(1) コンテナ外の素テーブルは「`||` を含む／区切り行が 2 行目にない」表だけを VFM より先に横取り変換（通常の GFM テーブルは完全に不変で VFM に委ねる）、(2) `long-table` / `rotate-table` コンテナ内テーブルは常に自前パーサで変換（Kramdown 優先→フォールバックの旧ルーティングを廃止。Kramdown が `||` を空セルとして `<table>` 化しフォールバックが永久に発火しなかった問題を解消）。セル内は Kramdown で描画するため `**太字**`・`*斜体*`・`` `コード` ``・数式 SVG の `<img>` 等の生 HTML を保持し、旧 `pipe_table_to_html` の `<code>` 二重エスケープバグも解消。列整列（`:---`/`:---:`/`---:`）に対応。`rotate-table` は**版面（用紙・余白・文字サイズ）と表内容から scale と高さを自動算出**してページにフィットさせ（`TableConverter.estimate_rotate_style` 純粋関数）、著者の `scale=` 指定はそれを上書きする。CSS の配置基準を「ラッパー高さ＝版面高さ＋`translateY(-50%)` の完全センタリング」へ再設計し、旧 `shift-y: +25%` の補正ハックを撤去。`MarkdownUtils.pipe_table_to_html` / `MarkdownTransformer.convert_table_{rotate,container}_inner_markdown` は撤去し `TableConverter` へ移管。**⚠️ Breaking（3 点）**: (1) コンテナクラス `:::{.table-rotate}` → `:::{.rotate-table}` へ改名（`long-table` との語順統一・互換エイリアスなし。旧記法は変換されず素通しになる）、(2) テーブル内 `||` の意味変更（空セル→直前セルへの結合。**本物の空セルは `| |` と空白を挟んで書く**）、(3) `shift-y` の意味変更（センタリング補正値・既定 +25% → ページ中央からの追加オフセット・既定 0% で完全センタリング）。原稿 `contents/22-extentions.md`（拡張テーブル節の新設・`.rotate-table` 節）を更新。仕様書: [table-colspan-spec.md](docs/specs/table-colspan-spec.md)。
- [Medium] **`vs preflight` に `:::` コンテナの構造チェックを追加**: `:::{.class}` の div 化には二経路があり、`book-card` / `table-rotate` / `long-table` / `text-{right,center,left}` の 6 クラスだけが Ruby 前処理（`MarkdownTransformer.convert_container_blocks`）を通り、残りはすべて `config/post_replace_list.yml` の汎用正規表現が `<div class="$1">` へ置換する。後者は**クラス名も開閉の対応も一切知らない**ため、(1) `:::{.notice}` を `:::{.notion}` と打ち間違えても無言で `<div class="notion">` になり CSS が当たらないまま素の段落として組まれる、(2) `:::` の数が合わないと `<div>` が閉じず以降の本文が枠に飲み込まれる、という 2 つの破綻が黙殺されていた。これを検出する `Guards::ContainerFenceCheck`（開閉バランス・`:error` で停止）と `Guards::ContainerClassCheck`（未知クラス・`:warn`）を新設し、`vs preflight` の `Guard.run!` へ登録（`CodeFenceCheck` と同じく preflight 専用）。両者は共有スキャナ `Guards::ContainerScanner` を使い、走査の中核に既存の公開 API `Masking.each_prose_line` を用いる（`Masking.protect_code` はフェンスをプレースホルダ 1 個へ畳んで行番号を崩し、`INLINE_CODE_SPAN` が `/m` 付きのため孤立したバッククォート対が複数行を飲み込むので、行番号を要する検査には使えない——実測で `contents/41-book-yml.md` が「閉じ忘れ」と誤検出された）。許可リストは `stylesheets/**/*.css` のクラスセレクタから自動抽出するため「**クラスに CSS を書けば自動的に許可される**」で完結し（`custom.css` が著者の自由記述用に既存）、CSS を書かない独自クラスは `config/book.yml` の `preflight.allowed_classes` で追加許可する（要 `ruby copy_to_scaffold.rb` 同期）。修正候補は stdlib の `DidYouMean::SpellChecker#correct` の結果をそのまま（Jaro-Winkler 降順・レーベンシュタイン距離で足切り済み）最大 3 件まで提示し、`contents/x.md:17 - 未知のコンテナクラス '.colunm' を検出しました` ＋ `現状: :::{.notice .colunm}` / `候補: :::{.notice .column}` の形で警告する（行番号を持つ警告は `LinkImageValidator` と同形の `path:line - 内容`。候補は誤ったクラスだけを差し替えた貼り替え可能な開始行で示す）。フェンス内の記法解説（```` ```markdown ```` 内の `:::{.クラス名}`）・インラインコード・`<!-- -->` 内（会話文 TODO の `:::{.talk}`）は走査対象外。実測: 現行 `contents/` 26 ファイル・使用クラス 32 種に対し警告・エラーとも 0 件（許可リスト 111 種）、意図的に混入させた `.notion` / `.colunm` / 閉じ忘れは `vs preflight` で正しく検出。仕様書: [container-class-validation-spec.md](docs/specs/container-class-validation-spec.md)。
- [Medium] **入稿用表紙の塗り足し制御（著者持ち込み master 画像）**: `output.print_pdf.cover_bleed`（`scale`（既定）/ `keep`）を新設。`scale`=トリム画像を塗り足しまで拡大して流用（中央が数% 拡大・端が裁断される）、`keep`=拡大せず塗り足し帯を白のまま残す（フチが紙端まで無いデザイン向け）。加えて `covers/<front|back>cover_master_bleed.png`（塗り足し込みの専用画像）を置けば最優先で自動採用する（ゼロコンフィグ・拡大なしでトリム画像と絵柄差が出ない）。`CoverCommands.resolve_print_cover_input` を新設し、`config/book.yml` の print_pdf ブロックにコメントを追記（要 `ruby copy_to_scaffold.rb` 同期）。

### Removed
- [Medium] **著者向け手動フロー（`vs pdf` / `vs entries` / ルート `vivliostyle.config.js`）の撤去**: P4（ワークスペース分離）完了時点で手動フローは実体を失っていた（`vs entries` はルーティング不在で呼べず、`vs pdf` はルートに中間 HTML が無いため空 entries.js を生成して空振り。パイプラインは全経路で workspace の用途別生成 config を使用）ため、workspace 化ではなく撤去した。(1) Samovar `vs pdf`（内部コマンド）を削除（`pdf:compress` / `pdf:pages` / `pdf:rasterize` / `pdf:read` は従来どおり）。(2) `PdfCommandRunner` の config なし経路を廃止し `config_path:` / `output_path:` を必須化。ルート entries.js の自動再生成（`ensure_entries_file!`）・`SingleDocDecider`（`VIVLIO_SINGLE_DOC`）・`vs pdf [output]` 専用のリネーム機構を削除。(3) `EntriesCommands.execute_entries` 系を削除（`build_entry` / `extract_html_title` は workspace entries 生成の基盤として残置）。(4) `VivliostyleConfigWriter.write_root_config!` 系（P3-4 のルート config 全文生成・`.bak` 退避）を削除し、ルートと scaffold の `vivliostyle.config.js` 本体・package.json の `build:pdf` script・book.yml の `vivliostyle.entries_file` / `config_file` 既定値も撤去。既存プロジェクトに残る `vivliostyle.config.js`（と `.bak`）は無害な残骸のため手動削除してよい（ルート `entries.js` は `vs clean` が旧残骸として掃除）。単章再生成は `vs build <章>` を、開発者デバッグは `vs build --no-clean` 後の `npx vivliostyle build -c .cache/vs/build/pdf/vivliostyle.config.sections.js` を使う。原稿（12-quickstart / 13-new / 61-developer）のプロジェクトツリー・内部コマンド表も更新。仕様書: [vivlioverso-manual-flow-removal-spec.md](docs/specs/vivlioverso-manual-flow-removal-spec.md)。

### Fixed
- [Medium] **`:::{.terminal}` の中身が Markdown として解釈されていた不具合**: `.terminal` は前処理を通らず `config/post_replace_list.yml` の汎用正規表現が HTML 生成**後**に `<div class="terminal">` へ変換していたため、中身は素の Markdown として VFM に渡っていた。シェルのコマンドと端末出力は Markdown のメタ文字を最も多く含むテキストであり、実測で `$ cp *.png *.bak` → `*` が消え斜体化、`` $ echo `date` `` → バッククォートが消滅、`$ echo $A$B` → `$A$` が数式化、`$ mv _old_ _new_` → `_` が強調化、`contact@a.net` → 自動リンク化、桁揃えの**連続空白が HTML 生成の時点で消滅**、そして `---` の行が `<hr>` 経由で `<hr class="pagebreak">` になり**本文が改ページ**していた。`.terminal` を「端末の逐語転写」と定義し直し、前処理 `MarkdownTransformer.convert_terminal_blocks`（`strip_html_comments!` 直後・`transform_math!` より前）で `~~~vs-terminal` チルダフェンスへ書き換えてリテラル化する。これで以降の前処理ステップは既存の `Masking.protect_code` が中身を退避し（専用のプレースホルダ機構は作らない）、HTML エスケープと空白保持は VFM が引き受ける。後処理 `PostProcessCommands::TerminalBlockConverter`（`HtmlReplacer` より前に実行）が `pre.language-vs-terminal` を `<div class="terminal"><pre>…</pre></div>` へ戻す（`<code>` ラッパは畳み、`language-*` クラスは `code.css` の `pre[class*="language-"]` に巻き込まれて枠が二重化するため除去。`<div>` で包むのは `EpubBuilder::ADMONITION_LABELS` の Kindle 用ラベル注入が `doc.css("div.terminal")` に依存し、`<p class="vs-adm-label">` を `<pre>` の内側に置けないため）。`<pre>` は `HtmlReplacer` の `:tag_aware` / `:text_only` 双方で退避されるので、逐語出力中の `---` 等は後続の置換ルールからも守られる。プロンプト記号（`$` / `%` / `#`）は著者が書く方式に確定（どの行がコマンドでどの行が出力かは著者だけが知っているため、`book.yml` による記号設定機構は不要と結論）。`.output` は従来どおり中身が Markdown（箇条書き・表を入れる既存用途を維持）で、桁揃えの要る逐語出力は `.output` の中にコードフェンスを書く（二重枠にならないよう `.output pre[class*="language-"]` を追加）。CSS は `.terminal p` を廃し `.terminal pre`（`white-space: pre-wrap` で折り返しつつ連続空白を保持）＋ Kindle 用 `body.vs-kindle .terminal pre` を追加（要 `ruby copy_to_scaffold.rb` 同期）。原稿 `contents/22-extentions.md` の `.terminal` / `.output` 節も追記。実測: `vs build 22` で `$ cp *.png *.bak` が逐語で組まれ、`.output` 内の SQL テーブル出力が桁揃えを保つことを PDF で確認。仕様書: [terminal-literal-spec.md](docs/specs/terminal-literal-spec.md)。
- [Medium] **著者持ち込み表紙(master)の入稿版が約 +15% 拡大していた不具合**: `CoverCommands.generate_pdfx_single` のトンボ付き経路が、表紙画像を全紙サイズ(trim+(bleed+offset)×2)へ `-resize …!` で引き伸ばしていたため、閲覧版(trim)に対し中央が約 +15% 拡大＋端部裁断され、さらにトンボ代帯まで画像が回り込んでいた。画像を塗り足しボックス(trim+bleed×2、約 +2.86%)へ収めて白背景の全紙サイズへ**中央配置**する方式へ是正（トンボ代帯は白を維持）。`fill:` 引数（`:bleed` / `:trim`）を追加し、`keep` 指定時は仕上がりサイズのまま配置。実測（A4・単色）: scale/keep/`_bleed.png` の 3 モードで塗り足し帯の充填・白 offset を px 単位で確認。
- [Medium] **bundle 表紙（light/dark）print 版の絵柄ずれを解消**: 入稿用表紙を生成する `CreateCommands#convert_svg_to_pdf_with_crop_marks` が、トリム設計の SVG を trim+bleed サイズへスケールして描画していたため、閲覧用（pdf）表紙に対し絵柄が約 +2.86% 拡大＋端部裁断され、pdf 版と print 版でずれていた。SVG の `viewBox` を塗り足し分だけ外側へ拡張して**等倍レンダ**する方式（新ヘルパー `expand_svg_viewbox_for_bleed`）へ変更し、pdf/print で内容が 1:1 一致するようにした。塗り足し帯は同梱テンプレ側で縁に接する要素（背景・**上下の金フレームバー**）をトリム外までオーバーサイズに描き、print 版で**拡張後 viewBox ちょうどのクリップパス**を全ボディへ掛けて埋める（rsvg-convert は大ページ配置時に viewBox 外を自動クリップしないため。トンボ代の白帯は白のまま保持）。背景グラデは `userSpaceOnUse`＋`spreadMethod="pad"`。**上下の金バーを塗り足し帯まで伸ばした**ことで、断裁位置が多少ズレても紙の縁に金線が残る（左右の縦アクセントは内側のまま）。実測（A4・light/dark・front/back）: 閲覧版と入稿版トリムの構造 RMSE 0.098→0.0007、塗り足し帯の金充填・トンボ・白 offset を px 単位＋目視確認。あわせて `render_bundled_svg` の CSS `var()` 展開漏れ（初回生成時に中央グラフィックが黒く描画される既存バグ）も修正。対象テンプレ `covers/bundled/{front,back}cover.svg` は要 `ruby copy_to_scaffold.rb` 同期。
- [Low] **bundled 表紙の初回生成で中央グラフィックが黒く描画される不具合**: `render_bundled_svg`（bundled テンプレ経路）が CSS `var()` のインライン展開（`expand_css_custom_properties`）を呼んでおらず、生成 SVG キャッシュが無い初回生成時に RGB 経路 `convert_svg_to_pdf` で `var(--vs-node-fill)` 等が解決されずノード等が黒く描画されていた（2 回目以降は生成 SVG が user_svg 扱いで展開されるため顕在化せず）。user_svg 経路（`apply_text_placeholders_to_svg`）と揃えて展開を追加。
- [Low] **workspace 生成 config のタイトルエスケープ**: `VivliostyleConfigWriter.config_content` の `'` エスケープが gsub 置換文字列の `\'`（後方一致バックリファレンス）誤解釈で壊れる形だった（旧ルート config 生成側で修正済みだったブロック形へ一本化）。タイトルに `'` を含む書籍で生成 config が JS 構文エラーになる問題の予防。

### Changed
- [Medium] **prep 段生成物の workspace 化＝ルート個別掃除の撤去（VivlioVerso 基盤整備 P4b）**: P4 完了後にビルドがプロジェクトルート（著者領域）へ残していた中間物 2 点を workspace 内へ移設し、`run_final_clean` を `rm_rf BUILD_DIR` **のみ**へ縮退した（P4 完了条件 4「ルート無汚染」の完全達成）。(1) **数式 SVG**（`MathTransformer`）: 生成先を `BUILD_HTML_DIR/images/math/<章>/` へ、`<img>` 参照を**消費者 dir 相対 `images/math/…`（`asset_prefix` 無し）**へ変更。この参照形は EPUB/Kindle の prefix 剥がし（`stage_consumer_htmls!`）を素通りし、E2 の dot-dir 禁止にも抵触せず、PDF/EPUB/Kindle が同型になる（§2.1）。PDF 消費者は `PdfBuilder.stage_workspace_htmls!` が `html/images/` を `pdf/images/` へミラーして解決（§2.2）、EPUB/Kindle 消費者は `EpubBuilder.localize_assets!` が `copy_asset_tree!(dest_root:)` の一般化で workspace の `html/images/` からローカライズして解決する（EPUB 内部の最終パスは `images/math/…` で**現行と同一**・§2.3）。Techbook の `rewrite_svg_references!` は `.webp` 存在確認を **HTML ファイル位置基準**（`File.expand_path(webp_src, File.dirname(html_file))`）へ直し、`asset_prefix` 付き・dir 相対の両参照形を 1 規則で正しく扱う（§2.4）。(2) **`_index_matches.yml`**（索引スキャン結果）: 書き手 `IndexMatchScanner` と読み手 `UnifiedPageBuilder` を新定数 `Common::INDEX_MATCHES_FILE`（`BUILD_DIR` 直下）へ一本化（§2.5）。`vs clean` は `_index_matches.yml` と `images/math` を `LEGACY_*`（1 リリース残して V2.0 で撤去）へ格下げ（§2.6）。出力同一性: EPUB 内部の参照パスは現行と同一、PDF はレンダリング内容不変（パス表記のみ変化）。`workspace_structure_test` を格上げ（`ROOT_POLLUTION_GLOBS` に `images/math`・`_index_matches.yml` を追加し、WS-02b で workspace 生成＋pdf ミラー＋epub/kindle ローカライズを検証）。検証: `rake test` / `rake test:standard` 全緑・rubocop クリーン・実ビルド突き合わせ。仕様書: [vivlioverso-p4b-workspace-remnants-spec.md](docs/specs/vivlioverso-p4b-workspace-remnants-spec.md)。
- [Medium] **ルート `vivliostyle.config.js` の全文生成化＋VFM エントリーレベル適用（VivlioVerso 基盤整備 P3-4）**: P3 で `stylesheets/*.css` を「ソース不変＋生成ファイル 1 枚」へ移した思想に揃え、唯一残っていた **`vivliostyle.config.js` の size/title 正規表現 in-place 書換（`CssUpdater.sync_vivliostyle_config_size!` / `sync_vivliostyle_config_title!`）を全廃**し、`config/book.yml` からの**決定的な全文生成**へ移行した（生成器は P4 新設の `Build::VivliostyleConfigWriter` に `write_root_config!` を追加してメタデータ解決＝title/author/language/size を 1 箇所へ集約）。生成 config は entry を `entries.map((entry) => ({...entry, vfm: {...}}))` の形で展開し、**VFM 設定（hardLineBreaks）をエントリーレベルで適用**（Vivliostyle CLI 公式推奨方式）——トップレベル `vfm:` ブロックは廃止。存在検査のみだった `Guards::VivliostyleConfigCheck` は撤去した（config は毎ビルドの 'prepare theme images' ステップで全文生成され、欠落は自己修復されるため）。**Breaking（挙動差・§2.4）**: (1) title/size 以外の config への**手編集は今後保持されない**——生成マーカー（`// 自動生成:` 行）を持たない既存ファイル（旧 scaffold コピー・著者の手編集）は初回ビルド時に一度だけ `vivliostyle.config.js.bak` へ退避のうえ 🟡 警告して生成へ移行する（`.bak` は clean 対象外・既存時は上書きしない）。(2) title 未設定時はプレースホルダ `'書籍タイトル'`（vivliostyle 11 スキーマが 1 文字以上を要求）。設定変更は `config/book.yml` へ一本化。VFM の実効変換機構（フロントマター注入・章単位の `vfm: hardLineBreaks: false` 上書き）は現行のまま維持。出力は write-if-changed（内容同一なら無書込）で決定的。あわせて **EPUB config のメタデータ解決も writer へ一本化**（§2.6）——`EpubBuilder.generate_epub_config!` のインライン title/author/language 解決を `VivliostyleConfigWriter.resolve_*` 呼び出しへ置換し、ルート／パイプライン／EPUB の 3 経路で解決規則を一元化した（EPUB config 生成物が置換前後で **SHA256 バイト同一**であることと、実 EPUB ビルドの OPF メタデータ（dc:title / dc:creator / dc:language）不変を実測確認）。検証: `rake test` / `rake test:standard` 全緑・rubocop クリーン。PLANNED.md「VFM 設定のエントリーレベル適用」を消化。仕様書: [vivlioverso-p3-4-config-fullgen-spec.md](docs/specs/vivlioverso-p3-4-config-fullgen-spec.md)・[vfm-config-flow-notes.md](docs/specs/vfm-config-flow-notes.md)。
- [Medium] **ワークスペース構造保証テストの新設（VivlioVerso 基盤整備 P4 段階 6・P4 完了）**: P4（ビルドワークスペース分離）の構造そのものを回帰保護するテストを整備した（§5.5）。(1) `workspace_structure_test`（新設・`rake test:targets` 配下）: `--no-clean` フルビルド（targets: pdf, epub, kindle）1 回で、4 消費者 dir（`.cache/vs/build/{html,pdf,epub,kindle}/`）の生成と各用途の中間物配置（html=章 HTML 原本 / pdf=ステージ HTML＋用途別 entries/config / epub・kindle=ステージ HTML＋ローカライズ資産＋生成 config・kindle は WebP ゼロ / workspaceDir もワークスペース内）・ビルド後のルート無汚染（旧方式の中間物パターン網羅）・git 作業ツリー無汚染を検証（WS-01〜04）。(2) `target_consistency_test` へ「kindle を含む `--no-clean` combo のビルド後もルート `images/{_epub_assets,headings}` が存在しない」構造検証を追加——旧「kindle 画像汚染」の隔離（`vs clean` によるリセット）を、汚染が構造的に不可能であることの直接検証へ格上げ。(3) `manual_build_test` へ MB-05 を追加: 通常ビルドの final clean 後に `.cache/vs/build/` とルート `.vivliostyle/` が残らないことを検証。§5.5 の「ルート中間 HTML を覗くテストの参照先更新」は段階 3〜5 のテスト更新で解消済みと確認。検証: `rake test:release` 全緑（test/standard 各 1,453・layout 7・targets 18・manual 12・package 4）。過程で P4 と無関係の既存問題 2 件へ対処——① daa87921 で用語辞書が削除され索引/用語集ページが生成されないため、spine 検証を辞書存在時のみの条件付きへ変更 ② 61-developer.md の npm スコープ名（`@vivliostyle/cli` 等の平文部分）が相互参照 `@ID` に誤検出される false positive 5 件を検出——リンク/索引マークアップ/裸 URL の除外をリゾルバ側へ実装して恒久解消（Fixed 参照）。これにより P4 全段階（1〜6）が完了。仕様書: [vivlioverso-p4-investigation.md](docs/specs/vivlioverso-p4-investigation.md) §5.5・§7-6。
- [Medium] **final clean 刷新（VivlioVerso 基盤整備 P4 段階 5）**: ビルド終端のクリーン処理から**単章 PDF の `.keep` 退避ハックを撤去**（P4 完了条件 2）。中間物がワークスペース（`.cache/vs/build/`）に閉じたことで、final clean は「workspace の一括 `rm_rf`＋ルート側に残る現行中間物 2 点（`images/math/`・`_index_matches.yml`＝P4b 対象）の個別掃除」だけになり、ルートの最終成果物に触れる経路が消滅した（完了条件 4・ルート無汚染）。`vs clean` のルート掃除パターンは `ACTIVE_ROOT_PATTERNS`（手動フロー `entries.js`・索引のルート生成物）と `LEGACY_ROOT_PATTERNS` / `LEGACY_INTERMEDIATE_PDF_PATTERNS`（P4 以前のビルド残骸。1 リリース残して V2.0 で撤去予定）へ分離した（削除挙動は不変）。また EPUB/Kindle の生成 config に `workspaceDir: '.cache/vs/build/.vivliostyle'` を指定し（§5.6 の付随整理）、EPUB ビルド中にルートへ一時生成されていた `.vivliostyle/` も解消。検証: `rake test` 全緑（1,453 件）＋ 4 ターゲット実ビルドで、段階 4 成果物との突き合わせ＝閲覧用 400p / 入稿用 398p の全ページテキスト・MediaBox 一致・**EPUB パッケージ内 4,108 ファイル全バイト同一**（差分は dcterms:modified のみ）・epubcheck 0 エラー 0 警告・KPF 生成成功（Error 0）・ビルド後のルート完全無汚染（`git status` クリーン）・単章ビルド（`vs build 11`）で `.keep` 無しでも最終 PDF が残ることを実測確認。仕様書: [vivlioverso-p4-investigation.md](docs/specs/vivlioverso-p4-investigation.md) §3.4-8・§5.6・§7-5。
- [High] **EPUB/Kindle の消費者 dir 化（VivlioVerso 基盤整備 P4 段階 4）**: EPUB（クリーン）/ Kindle の生成を、段階 3 の暫定ブリッジ（`html/` からルートへ prefix を剥がして展開）から **`.cache/vs/build/epub/`・`kindle/` の専用消費者 dir で完結する方式**へ移行した（実験 E2 の確定案＝資産ローカライズ＋`entryContext`）。`EpubBuilder.stage_consumer_htmls!`（`html/` → dir へ `asset_prefix` 剥がしコピー）と `localize_assets!`（images/stylesheets/カバーの選択コピー。旧 `copyAsset.excludes` の除外知識をコピー側の選択規則へ全面移設し、config から copyAsset ブロックを撤去）を新設。entries は entryContext 基準の `./xx.html`、生成 config は `entryContext: '.cache/vs/build/{epub,kindle}'`＋dir 内 output で書き、`--config` で渡す（`EpubCommandRunner` の config/output をパラメータ化）。**`EpubFlow` の暫定ブリッジとフレーバ間スナップショット（`snapshot_chapter_htmls`/`restore_chapter_htmls`）を撤去**（P4 完了条件 1 の完結。フレーバごとに dir が分かれ相互汚染が構造的に不可能）。扉絵/節絵の合成画像（`images/headings/`）・Kindle の WebP→JPEG 変換物（`images/_epub_assets/`）・book-settings.css の EPUB 変種（ルート直下）はすべて消費者 dir 内へ生成されるようになり、**著者ディレクトリ汚染が解消**（P4b の EPUB/Kindle 分の前倒し・§5.2-b）。副産物として、未参照だった表 1/表 4 PNG（`covers/{front,back}cover_*.png`）が EPUB に同梱されなくなり約 5.7MB 軽量化。検証: `rake test` 全緑（1,453 件）＋実ビルド（4 ターゲット一括）で、epubcheck 0 エラー 0 警告・KPF 生成成功（Error 0）・段階 3 成果物との突き合わせで **EPUB パッケージ内 4,128 ファイルすべてバイト同一**（差分は dcterms:modified と意図的に外した PNG 2 点の manifest 行のみ）・閲覧用 400p / 入稿用 398p の全ページテキスト一致・ビルド後のルート無汚染（`git status` クリーン・`images/headings`・`images/_epub_assets` ともルートに生成されない）を実測確認。仕様書: [vivlioverso-p4-investigation.md](docs/specs/vivlioverso-p4-investigation.md) §5.2〜5.4・§6.1 E2。
- [High] **ビルドワークスペースの分離（VivlioVerso 基盤整備 P4 段階 3・課題 D）**: 中間生成物（前処理済み `.md`・章/特殊ページ HTML・`_sections.pdf` 等の中間 PDF・用途別 entries/config）を**プロジェクトルートから `.cache/vs/build/{html,pdf}/` へ移設**した。共通 prep の成果は `html/`（全消費者の複製元・常にクリーンな原本）へ、PDF 消費経路（閲覧用＋入稿用）は `html/` から `pdf/` へ無加工コピーして実行する（4 消費者 dir は同一深度＝資産への相対プレフィックス `../../../../` が共通、という P4 §3.1 の設計）。資産参照を生成する choke point（FrontmatterGenerator / ImagePathNormalizer / MathTransformer / Techbook::Processor / EmojiReplacer / TocDocumentBuilder / UnifiedPageBuilder）は `Common.asset_prefix` へ一元化した（段階 1 で prefix `''` のまま配線して全成果物の出力不変を実測確認→段階 3 で切替、という 2 段安全網）。**固定名 `entries.js` 単一資源を廃止**し、用途別の `entries.sections.js`／`vivliostyle.config.{sections,front,colophon,sections_print,front_print,colophon_print,single}.js` を `Build::VivliostyleConfigWriter`（新設）が `pdf/` へ生成して `--config` で渡す方式へ（EPUB 経路の既存方式の PDF 側への一般化。「前付ビルドが本文用 entries.js を上書き→再生成」という病理が概念ごと消滅）。パス表記は実験 E1〜E5（仕様書 §6.1）の確定事項どおり全て cwd（ルート）相対・実行 cwd はルート固定・`-d`（single-doc）は生成 config と併用しない。**dedup（backlink 重複排除）の破壊的書換は `pdf/` 配下のコピーに閉じ**、`html/` は常に dedup 非通過のクリーン原本になったため、EPUB 隔離のための「dedup 前スナップショット」ステップ（`snapshot pre-dedup html for epub`）と `EpubFlow#snapshot_pre_dedup!` を撤去（P4 完了条件 1 の前半・§3.4-3）。EPUB/Kindle は暫定ブリッジ（`html/` からルートへ prefix を剥がして展開）で現行経路のまま動かし、段階 4 で `epub/`・`kindle/` 消費者 dir へ移行する。単章ビルドも同経路（`html/` → `pdf/` ＋ `entries.single.js`）で、最終成果物（`11-workflow.pdf` 等・ルート直下）のみ `pdf/` からルートへ mv される。`vs clean` と final clean はワークスペースを `rm_rf .cache/vs/build` で一括掃除（`--no-clean` なら残す＝デバッグ資材が 1 箇所に揃う）。workspaceDir も `.cache/vs/build/.vivliostyle` へ移設（§5.6）。検証: `rake test` 全緑（1454 件）＋実ビルド突き合わせ（閲覧用/入稿用 PDF の全ページテキスト・ページ数一致、EPUB/KPF 生成、単章 5 ページ＝E5 基準一致、ビルド後のルート無汚染）。仕様書: [vivlioverso-p4-investigation.md](docs/specs/vivlioverso-p4-investigation.md)。
- [High] **CSS 設定注入層の導入（VivlioVerso 基盤整備 P3・課題 C）**: ビルド設定（book.yml の theme / page / typography）を毎ビルド正規表現で `stylesheets/*.css`（theme.css / page-settings.css / appendix.css / preface.css / chapter-common.css / chapter.css）へ **in-place 書換**していた `CssUpdater` を全廃し、設定値を **`.cache/vs/book-settings.css` へ全文生成**する `PreProcessCommands::BookSettingsCss` 生成器を新設。章 HTML の `link` 順を `[theme.css, {種別}.css, book-settings.css, custom.css]` とし、後段の再宣言が既存テーマ CSS にカスケードで勝つ設計へ移行した。これによりソース CSS が **読み取り専用のテーマ資産**へ戻り（book.yml を変えても `stylesheets/` に差分が出ない）、将来のテーマ CSS セット差し替えの前提が整った。値計算ロジック（用紙スケール・行長・ノンブル配置・綴じオフセット・フォントスタック整形・色正規化）は実証済みの `CssUpdater` の補助メソッドを流用し、`CssUpdater` は値計算＋`vivliostyle.config.js` 同期のみ担う。画像 URL は生成ファイル位置（`.cache/vs/`）基準へ組み替え（`../../stylesheets/…`、data:/http(s): は不変）。条件付き宣言のセマンティクス（simple スタイルの画像 none・appendix 未指定は非宣言・nil/空値は非宣言・preface は常に宣言）を in-place 版と一致させ、同梱プリセット（`a4_compact`）でのソース CSS バイト不変と、B5 プリセットでの実 PDF 版面（182×257mm）を実測確認した。
- [High] **章ヘッダの simple/image 切替を「方式A（body クラス）」へ移行（P3-3）**: `chapter.css` の `@import` を simple⇄image で in-place 差替していた `update_chapter_css` を廃止。`chapter.css` は両ヘッダを常時 `@import` し、`simple-header.css` / `image-header.css` の全レイアウト規則を `body.vs-header-simple` / `body.vs-header-image` で相互排他にゲートする。`BodyClassInjector` が種別ごとにクラスを注入（chapter=theme.style 依存 / appendix=常に simple）。Kindle フォールバック規則も `body.vs-header-simple.vs-kindle` へ限定し、画像モード Kindle の従来挙動を保った（バイト等価）。post_process は Vivliostyle の前に走るため PDF 組版にも効く。
- [Medium] **EPUB の設定追従を book-settings.css へ整合（P3・調査報告 §7.1/§7.2）**: (1) EPUB 扉絵/節絵合成の参照元（`read_theme_heading_assets`）を theme.css の正規表現読みから `parse_theme_settings` の計算値へ切替え、theme.css を既定のままでも book.yml の色/扉絵/飾りに追従するようにした（節番号色は静的な `--accent-*` パレットで具体色へ解決）。(2) `copyAsset` の `.cache/**` 除外と衝突する book-settings.css を、EPUB ルート直下へ url() をルート基準へ組み替えた変種としてコピーし、章 HTML の link href を書き換えて同梱（RSC-007 回避）。Kindle の webp url() 除去・マージンボックス除去は `sanitize_epub_css!` が同梱後の CSS へ自動適用される。`vs clean` の掃除対象にも追加。
- 新設 `book_settings_css_test.rb`（18 件：変数網羅＝テーマ互換の公開 IF・条件付き宣言・url 組替・@page リテラル・フォントスタック整形）。`css_updater_test.rb` は撤去メソッド分のテストを外し値計算＋config.js 同期に整理。全単体テスト（1454 件）緑。

### Added
- [Medium] **版面単位変換を `Units` モジュールへ一元化（`lib/vivlio_starter/cli/units.rb` 新設）**: 版面設定（`page_presets.yml`）の単位変換ロジックが 3 系統（`common.rb` の `q_to_pt` 系／`css_updater.rb` の `parse_to_mm`／`theme_image_resolver.rb` の `css_length_to_mm`）に分散し、`72.0 / 25.4`（mm↔pt）などの変換係数が 8 ファイルに散在、かつ Q→pt 係数が近似値 `0.709` の直書きだった。基準関係「1in = 25.4mm = 72pt」「1Q = 0.25mm」の 2 つだけから全係数を導出する `Units` モジュール（`length_to_mm` / `font_size_to_pt` / `pt_value` / `format_pt` と `MM_PER_INCH`/`PT_PER_MM`/`PT_PER_Q` 等の定数）を新設し、`common.rb`・`css_updater.rb`・`theme_image_resolver.rb` の変換をこれへ統一。散在していた `72.0 / 25.4` も `Units::PT_PER_MM` 参照へ集約（create/utilities/nombre_stamper/standard_provider/pdf_read/cover。数値同一で挙動不変）。単位の使い分け（文字=pt・字間=em・余白/判型=mm・行送り=倍率→絶対 pt 化、Q は受理継続）は仕様書 [page-unit-conversion-spec.md](docs/specs/page-unit-conversion-spec.md) に明文化。純粋関数の `units_test.rb`（6 件）と `common_config_loading_test.rb` への統合テスト（`normalize_page_units`/`apply_page_preset`/`resolve_page_size`、B1 回帰含む 9 件）を追加。同梱プリセット（`a4_compact`）でのビルド出力（`page-settings.css` の CSS 変数値）はバイト単位で不変を実測確認。
- [Medium] **book.yml 設定キーの「消費漏れ」を検出する保証テストを新設（`book_yml_consumption_test.rb`）**: 「新機能追加時に book.yml へ設定キーを書いたが、実装はハードコーディングのままで設定値が消費されていない」という漏れが時折発生していた（直近でも metrics ラベル等で顕在化）。scaffold の book.yml の**全キーパス（177 件）を列挙し、各キー名が lib コードにシンボル・文字列・ドット記法のいずれかで出現すること**を検証する。動的参照されるキー（`metrics.author_custom` ＝ `use:` の値として参照）は理由つきの許可リストで管理し、許可リスト自体の陳腐化（参照されるようになったのに残っている）も検査する。今回この監査で **4 件の実際の消費漏れ**（`vfm.hard_line_breaks` / `book.isbn` / `output.epub|kindle.layout` / `index_glossary.use_mecab`）を発見し、それぞれ配線した（下記）。
- [Medium] **`vfm.hard_line_breaks`（book.yml）を各章フロントマターへ配線**: これまで book.yml の `vfm:` セクションは**どのコードからも消費されていなかった**（改行変換はテンプレート由来のフロントマターと `vivliostyle.config.js` の直書きに依存）。`FrontmatterGenerator#build_base_frontmatter` が book.yml の値を読み、各章のフロントマターへ **VFM が解する camelCase キー `vfm: hardLineBreaks:`** として自動注入するようにした（book.yml 側は snake_case、外部 API 境界は camelCase という棲み分け）。著者が章のフロントマターに直接 `vfm:` を書いた場合は**章側が優先**され（`merge_frontmatter` で既存キー温存のディープマージ）、`math: false` など vfm の別キーとも共存する。回帰テスト 4 件（注入・false 設定・章別優先・別キー共存）を追加し、マニュアル（21 章・41 章）に本全体／章単位の設定方法を明記。
- [Low] **`book.isbn` を EPUB の識別子（`dc:identifier`）へ配線**: 41 章で「メタデータは book セクションから流用される」と記述しながら isbn は未消費だった。著者が独自 ISBN を設定している場合、EPUB identifier の安定化（`stabilize_epub_identifier!`）で `urn:uuid`（プロジェクト名由来）の代わりに **`urn:isbn:<番号>`** を書き込む（EPUB の標準作法。ハイフン・空白は除去）。未設定なら従来どおり安定 UUID。
- [Low] **`index_glossary.use_mecab: false` を配線（MeCab の明示的無効化）**: 設定キーは存在したが未消費で、MeCab は「導入されていれば必ず使う」動作だった。`YomiInferrer#available?` が false 設定を尊重して MeCab を使わなくなる（読み推測・名詞連続抽出の両方がここを通る）。著者の明示的な選択のため、未導入時と違い導入案内の警告は出さない。
- [Low] **`output.epub.layout` / `output.kindle.layout` の検証を追加**: 設定キーは存在したが未消費だった。現在サポートするのは `reflowable`（リフロー型）のみのため、`fixed` 等が指定されていたら**ビルド時に警告して reflowable として続行**する（黙って無視すると「設定したのに効かない」事故になるため。fixed は将来対応の予約値として book.yml・41 章の説明も更新）。
- [Medium] **索引ライブラリの持ち運び（`vs index:export` / `vs index:import`）を追加**: 作者が書いた用語集の定義（`[g]`）・reject 一覧・**読みの個人辞書**を、書籍をまたいで引き継げるようにした（`IndexCommands::IndexLibrary` を新設）。`index_glossary_terms.yml` 等はこの本固有の情報（出現章・行、バックリンク、`source`）と作者の資産（定義・棄却判断・読み補正）が混在するため、**持ち運べる分だけ**を `index_library.yml`（`version: 1`）へ抜き出す。`export` は用語集[g]の `term`/`yomi`/`definition`・reject 一覧・読み（`term => yomi`）を term 昇順・冪等で書き出し（固有情報は除外）、`import` は追記マージで既存語を既定で温存（`--prefer-import` でライブラリ優先）・採用済み語は reject に追加しない。**読みの個人辞書**は `IndexCommands::YomiOverrides`（`config/index_yomi_overrides.yml`）に蓄積し、`YomiInferrer#infer` が MeCab 推定より優先して返す（読み解決順: 記法 > `index_glossary_terms.yml` > 個人辞書 > MeCab）。「碍子→がいし」等の補正を本ごとに登録し直す手間が不要になる（この個人辞書は `vs clean --index-dictionaries` の削除対象にも含める）。既定パスは `book.yml` の `index_glossary.library.path`（`export_to`/`import_from` で個別上書き可、`~` 展開）で設定でき、引数省略で使える。パス解決は「引数 > 設定 > 組み込み既定」。ルート routing に `index:export`/`index:import` を登録、`vs index` 概要ヘルプも更新。仕様は [index-library-portability-spec.md](docs/specs/index-library-portability-spec.md)。回帰テスト（export の[g]限定/固有情報除外/yomi 抽出/冪等・import の追記/既存優先/`--prefer-import`/reject 衝突スキップ/yomi 蓄積/パス解決・`YomiOverrides` の追記/上書き・`YomiInferrer` の override 優先）を追加。マニュアル（`33-index-glossary.md`）に説明を追記。
- [Low] **`vs index:auto [章]` の章指定をドキュメント化**: `vs index:auto 21` / `21-23,25` のように章を指定して一部だけ候補抽出できること（`TokenResolver` により実装済み・追記マージで非破壊・catalog 未登録章も可）を、`vs index` ヘルプとマニュアル（`33-index-glossary.md`）に明記した（新規実装なし）。
- [Medium] **`vs lint` にスペルチェック・ワークフローを追加（`--spellcheck-only` / `--textlint-only` / `--register` ＋ ユーザー辞書 ＋ 出力集約）**: (1) `--spellcheck-only` / `--textlint-only` で片方だけ実行可能に（`call` を分岐、spellcheck-only は textlint 未導入でも動く）。(2) **ユーザーグローバル辞書** `~/.config/vivlio-starter/spellcheck/user-words.txt`（`$XDG_CONFIG_HOME` 追従）を導入し、全プロジェクト共通でユーザーが育てられるように（`DictManager#user_dict_path` / `register_user_words`。テスト汚染を避けるためパスは定数でなくメソッド）。(3) `--register` で検出した未知語をユーザー辞書へ**一括登録**（重複は大文字小文字無視で除外）。マイコン用語など専門語を毎回 `book.yml` に書く手間を解消。(4) スペルチェック出力を**語ごとに集約**（`SpellChecker.print_errors` / `aggregate`：同じ語を 1 行へまとめ、出現行と件数を出現数の多い順に。最大 10 行＋…）。回帰テスト追加（register・ユーザー辞書ロード・集約・`extra_words` の end-to-end 抑制）。
- [Low] **スペルチェック用のプロジェクト管理辞書 `vivlio-starter-terms.txt` を追加**: cspell 由来の標準辞書に未収録の技術用語（`textlint` / `yml` / `SCOWL`）を補う辞書を `config/spellcheck_dictionaries/` に新設。`DictManager` は `*.txt` を全ロードするため自動認識される（標準辞書を直接編集しないので将来の再同期で消えない）。これで `vs lint` がこれらを誤検知しなくなる（大文字小文字は無視されるため `Textlint` も `textlint` で吸収）。回帰テスト（`dict_manager_test`）を追加。
- [Medium] **`vs doctor` に `kindlepreviewer`（Kindle Previewer 3）の診断と `--fix` 導入を追加**: Kindle 対応（`targets: kindle` の KPF 変換）に必須の `kindlepreviewer` を、これまで `vs doctor` が診断対象に含んでいなかった。`kindlepreviewer` を **`targets: kindle` 専用の任意ツール**として診断対象に追加（導入済みは `✅ kindlepreviewer`、未導入は OCR ツールと同様に 🟡 案内でハードエラーにはしない＝Kindle を使わない利用者の妨げにしない）。macOS の `vs doctor --fix` では Homebrew cask `kindle-previewer`（Pkg）を導入後、単体では PATH に乗らない CLI を呼ぶラッパー（`#!/bin/sh` で `/Applications/Kindle Previewer 3.app/Contents/MacOS/Kindle Previewer 3` を引数透過実行）を Homebrew の bin へ作成して `which kindlepreviewer` を通す（手動セットアップの定石を自動化）。`describe_missing` のラベル・`DOCTOR_DESC` も追補。ユニットテスト（ラッパー生成の実行権限・内容、案内文の macOS/非 macOS 分岐）を `doctor_commands_test` に追加。ドキュメント（`contents/44-build.md` のインストール節、`kindle-css-compatibility-notes.md` §5.4）も更新。
- [Medium] **`rake test:standard`（Standard モード強制テスト）を追加**: 開発機には拡張プラグイン `vivlio-starter-pdf` が入っているため通常の `rake test` は常に `EnhancedProvider` 経路を通り、MIT 本体の `StandardProvider` 経路が exercise されず、改修で standard 版が壊れても気付けない懸念があった。プラグインを uninstall せずとも、本体が備える `VIVLIO_PDF_PLUGIN=disable` を独立プロセスで与えて同じスイートを standard 経路で実行する `test:standard` を追加。`test:release` の前段に組み込み、リリース前に両プロバイダ経路（enhanced / standard）を必ず検証する。
- [Low] **`.text-center` / `.text-left` ユーティリティを追加（テキスト配置の対称性）**: 従来インライン文字寄せは `.text-right` のみだったが、`.text-center` / `.text-left` を追加して `.align-left/center/right`（ブロック配置）と対をなす形に対称化（`layout-utils.css` root/scaffold）。あわせてマニュアル（`22-extentions.md`）に「`.align-*`＝ブロック用（枠が内容幅に縮んで寄る）／`.text-*`＝インライン用（本文全幅のまま文字だけ寄る）」という棲み分けと、違いが分かる `.column .align-right` / `.column .text-right` の対比実行例を明記。
- [Low] **`.notice` / `.note` の Kindle 劣化対応（囲み枠＋実体ラベル注入）**: Kindle（KFX）は `::before` 絶対配置ラベルや `var()` を解さないため、これまで column/memo/tip にのみ行っていた実体ラベル注入（`EpubBuilder#decorate_admonitions_for_epub!`）を `.notice`→`【NOTICE】` / `.note`→`【NOTE】` にも拡張し、`body.vs-kindle` で囲み枠（`1px solid #888`）へ劣化させる規則を追加（`chapter-common.css` root/scaffold）。クリーン EPUB はテーマ色のデザインを維持。回帰テスト `epub_kindle_layout_test` に notice/note のラベル注入アサーションを追加。
- [Low] **実行例・ターミナル入力のブロック記法（`:::{.output}` / `:::{.terminal}`）を追加**: コマンドの実行結果や記法の表示例を示す `:::{.output}`（細い全幅の囲み枠）と、端末へのコマンド入力を示す `:::{.terminal}`（黒地・白文字・等幅の全幅枠）を追加。いずれも VFM ネイティブの `:::` コンテナで `<div class="...">` 化されるため前処理は不要で、`chapter-common.css` に CSS を追加（root/scaffold）。`.terminal` は具体色（`#1a1a1a` / `#f5f5f5`）でテーマ非依存に描き Kindle(KFX) でもそのまま反映、`.output` の枠線は `var()` のため Kindle で消える分を `body.vs-kindle .output` の具体色（`#888`）で描き直す。Kindle 劣化対応として、他の注記枠と同様に実体ラベルを先頭注入（`EpubBuilder::ADMONITION_LABELS` に `output`→`【OUTPUT】` / `terminal`→`【TERMINAL】` を追加）し、`body.vs-kindle` で囲み枠＋ラベルへ劣化させる（端末ラベルは黒地に沈まないよう白で表示、`.terminal` の等幅も `font-family: monospace` で担保）。回帰テスト（`epub_kindle_layout_test` のラベル注入）に output/terminal を追加。マニュアル（`22-extentions.md`）に両記法を追記し、`24-cross-reference.md` の章間参照の実行例を `:::{.output}` で囲んだ。プロンプト記号（bash の `$` / zsh の `%` / なし）を選べる設定は将来構想として `PLANNED.md` に起票。
- [Medium] **定義リスト記法（`用語` / `: 説明` → `<dl><dt><dd>`）を追加**: 標準 Markdown（pandoc / Markdown Extra 風）の定義リストを前処理で `<dl class="def-list">` へ変換する `MarkdownTransformer.convert_definition_lists` を新設（VFM が定義リスト未対応のため）。用語行の次行から `: ` で説明を書き、複数の `: ` 行で複数 `<dd>`、半角スペース字下げの継続行で複数行の説明に対応。著者は空行なしのコンパクトな形でも書け、内部でエントリ間に空行を補ってから Kramdown でレンダリング（インラインコード等のインライン装飾も処理）。本書全体の `hardLineBreaks: true`（改行＝`<br>`）に揃えるため、説明（`<dd>`）内の各行末へハード改行を補い、複数行の説明が `<br>` で改行される。コードフェンス内・他のブロック構文（見出し/リスト/引用/表/コンテナ）は誤変換しないよう除外。従来 `- **用語**` の箇条書き（`<ul><li>`）で見た目だけ定義リスト風だったのを本物の `<dl>` に。CSS は索引・奥付の既存 `<dl>` と衝突しないよう `.def-list` でスコープ（用語＝太字の独立行／説明＝字下げ／エントリ間 1/4 行アキ、`chapter-common.css`）。マニュアル（`22-extentions.md`）を新記法へ更新。回帰テスト 5 件を `markdown_transformer_test` に追加。
- [Low] **縦余白マクロ `@vspace:N`（符号付き）を追加**: 上方向に詰める `@nega:N` と下方向に空ける `@posi:N` を、符号付き 1 記法へ統一した `@vspace:N` を追加（`@vspace:10` ＝ `@posi:10` ＝ `margin-top:10mm` / `@vspace:-10` ＝ `@nega:10` ＝ `margin-top:-10mm`）。`config/post_replace_list.yml` に置換ルール、`cross_reference_processor.rb` の `RESERVED_MACRO_IDS` に `vspace` を追加（相互参照の未定義警告を出さない）。マニュアルを `@vspace` 主体へ更新（`22-extentions.md`）し、`24-cross-reference.md` の予約ID表にも追記。`@nega` / `@posi` は後方互換のため存続。値には**単位**（`lh`＝行の高さ／`rem`／`em`／`mm`/`cm`/`pt`/`px`。省略時は `mm`）を付けられ、`@vspace:1.5lh` / `@vspace:-2lh` のように行送りに合わせた指定が可能（単位付き／単位なし→mm の 2 ルールで処理）。回帰テスト（予約ID・マクロ保持）に `vspace` を追加。
- [Low] **`vs lint` に和欧間スペースを許容する設定を追加（技術書の一般的記法）**: `` `vs import` コマンド `` のようにインラインコードと和文の間にスペースを入れる技術書スタイルを残せるよう、`book.yml` に `lint.allow_space_around_code` / `lint.allow_space_between_ja_en` を追加。指定時は `preset-ja-spacing.ja-space-around-code` / `ja-space-between-half-and-full-width` を**実行時 textlintrc で設定レベル無効化**する（出力フィルタの `disabled_rules` と違い、警告を隠すだけでなくルール自体を切るので `vs lint --fix` でもスペースが削除されない）。`generate_runtime_config` をキーワード引数化して sentence_length_max と共通化。回帰テストを追加。仕様は [lint-spellcheck-workflow-spec.md](docs/specs/lint-spellcheck-workflow-spec.md) §3.2。
- [Low] **`vs lint` に文体の好みを設定する 2 項目を追加（一文の最大文字数・末尾長音）**: (1) `book.yml` の `lint.sentence_length_max`（例 80 / 120。未指定は既定 100）で一文の上限を変更できる（指定時は `rules.preset-ja-technical-writing.sentence-length.max` を上書きした一時 textlintrc を `config/` 直下に生成して使用。prh の相対 rulePaths が壊れないよう同一ディレクトリへ書き、`run_textlint` の ensure で後始末）。(2) `book.yml` の `lint.trim_long_vowel: true` で「サーバ／パラメータ／フィルタ」等の**末尾長音を省く技術文体**を選べる（`"X => Xー"` 系の指摘を集約段で抑止。`TextlintFormatter.long_vowel_addition?`。出力フィルタ方式で prh 辞書の所在に非依存）。回帰テスト（長音抑止・上限上書き設定の生成）を追加。仕様は [lint-spellcheck-workflow-spec.md](docs/specs/lint-spellcheck-workflow-spec.md) §3.2。
- [Medium] **`vs preflight` にコードフェンス整合チェックを追加（閉じ忘れ／余分を 🔴 で停止）**: 行頭の ```` ``` ````／`~~~`（3 連以上）を「フェンス区切り」と数え、総数が奇数なら「閉じ忘れ／余分」としてビルド前に**エラー停止**する `Guards::CodeFenceCheck` を新設し、preflight の `Guard.run!` 群に追加（画像名チェック等と同じ Check 層・全章 `contents/*.md` 走査）。フェンスが閉じていないと以降の本文がコード扱い（またはその逆）になりビルドが意図通りにならないため、警告でなくエラーとした。整形式は入れ子を含め常に偶数になる（コード例で ```` ``` ```` を見せる入れ子は外側を ```` ```` ```` 4 連にすれば内側 2 行と合わせて整合）。メッセージは修正案＋出現箇所（フェンス行番号）を添付。回帰テスト 5 件（`code_fence_check_test`）を追加。
- [Low] **`vs lint` のスペルチェックが相互参照ラベル（`@id`）を誤検出しないように**: `@photoelectric-table` のようなクロスリファレンスのラベルがスペル誤りとして大量に報告されていたのを、トークナイザでリンク・画像と同様に `@id`（`@` ＋英字始まり）を除外して解消（メール `user@example.com` は `@` 直前が単語文字なら対象外）。`@id` を使う章すべてで誤検出が一掃され、これまで誤検出の陰に隠れていた本物の指摘が見えるようになった。回帰テスト（ラベル除外・メール非破壊）を `tokenizer_test` に追加。
- [Low] **技術用語辞書の拡充とユーザー辞書の整備（誤検出語の仕分け）**: 全章スイープで挙がった誤検出語を「**広く知られた技術用語＋vivlio-starter 自身の語**＝同梱辞書 `vivlio-starter-terms.txt`」と「**本固有の作例**＝`config/user_words.txt`（新規）」に仕分けて登録。前者へ電子書籍（Kobo/KPF/KDP/KFX/OPF/NCName）・Markdown（VFM/CommonMark/GFM/MathJax）・PDF/画像/OCR ツール（HexaPDF/poppler/qpdf/Ghostscript/Tesseract/MeCab/natto/ruby-vips）・メトリクス（TTR/Flesch/TF-IDF）・vivlio-starter の機能/記法（querystream/book-card/table-rotate/renumber 等）を追加、後者へ作例のローマ字名（sakura/ume 等）を登録。`book.yml` の肥大化を避けるため、固有語は今後 `config/` 配下の辞書ファイルへ登録する方針（`copy_to_scaffold.rb` で scaffold へ複製される）。CLI ツール名・バージョン出力はコード表記（バッククォート）へ統一。
- [Low] **`vs metrics` の出力を「解析結果」と「参考資料」に分離し、集計行を追加**: 通常の `vs metrics` は従来の解析結果（章別分量・基本情報・文構造・詳細分析）までを表示し、A–G の推敲用参考資料（章間のばらつき・見直したい長い文・文末リズム・よく使う言葉・漢字レベル）は `--all` を付けたときだけ続けて出力するようにした（`Runner#output_advice`。全部を常時出すと長すぎるため使い分けられる）。あわせて章別リスト直後に「合計◯章／平均◯文字」の集計行を追加（`Formatter#format_chapter_count_summary`）。**オプションの改名**: 旧 `--all`（全章を節まで展開）は `--sections` へ改称し（`--warn`＝警告章のみ節展開 とペア）、`--all` は「解析結果＋参考資料」の意味に付け替えた（後方互換エイリアスは設けない）。`--json`/`--yaml` は参考資料を `advice`、語彙集計を `totals.vocabulary` として**追加出力**（内部で算出済みのものを構造化するだけ。`structured_advice`/`vocabulary_to_structured_hash` ほか）。回帰テスト（集計行の書式・JSON の `advice`/`vocabulary` 追加）を追加・更新。マニュアル（`32-metrics.md`）のオプション説明・出力例・JSON 例を新体系へ更新。
- [Low] **`vs metrics` に「漢字レベル（ルビ候補）」セクションを追加**: 本文の漢字を難易度レベル（教育=学年別配当／中学=常用／一般=JIS第一水準の常用外／専門=JIS第二水準／JIS外）に分け、レベル内訳（％）と、中学・一般・専門の漢字を頻度順に、さらに一般・専門漢字は**出現箇所（章・行）**つきで提示する（`Metrics::KanjiLevels` を新設、`Formatter#format_kanji_levels`）。小学生向けなど対象読者より上位の漢字＝ルビを振るべき候補を、場所まで含めて把握できる。教育漢字（学年別）・常用漢字の判定データ（`lib/…/metrics/data/kyoiku_joyo_kanji.tsv`、文科省「学年別漢字配当表」／文化庁「常用漢字表」の事実データ）を同梱し、一般（L2）・専門（L3）・JIS外（L4）は文字の符号位置（JIS X 0208 の区）から算出（実行時ネットワーク不要）。読みの自動付与は誤読が多く危険なため metrics は統計に徹し、自動ルビ（`vs furigana`）は `PLANNED.md` に将来構想として起票。回帰テスト（レベル判定・内訳/一覧/出現箇所の集計・漢字なし時 nil・表示）を追加。マニュアル（`32-metrics.md`）に説明を追記。
- [Low] **`vs metrics` に「よく使う言葉（頻出内容語）」セクションを追加**: 本文に頻出する内容語を品詞ラベル（名詞／固有名詞／形容動詞／動詞／形容詞）つきで上位 15 語まで提示する（`Metrics::ContentWords` を新設、`Analyzer#content_words`、`Formatter#format_content_words`）。同じ語の使いすぎ＝言い換え候補を見つけられる。MeCab/IPADIC の品詞・細分類で内容語を選別（`固有名詞`・`形容動詞語幹`・`サ変接続`等を区別）、助詞・助動詞・記号・非自立語・単語文字を含まないトークン（表区切り `|` 等）・汎用動詞（する/なる/ある/いる/できる）・単漢字の固有名詞（MeCab の誤判定。「章」等。正当な固有名詞は 2 字以上なので温存）は除外。**MeCab 前提でフォールバックは設けず**、未導入環境ではセクション自体を表示しない（vocab 統計側の簡易分割フォールバックは従来どおり）。表示は語・品詞を表示幅（全角=2）でそろえる。回帰テスト（品詞分類・基本形/表層形・機能語/記号除外・頻度順集計＋MeCab 連携は導入時のみ実行）を追加。マニュアル（`32-metrics.md`）に説明を追記。
- [Low] **`vs metrics` に「文末表現のリズム」セクションを追加（単調な文末の検出）**: 文末表現の内訳（です・ます／体言止め／だ・である／その他）と、同じ文末が 5 つ以上連続する箇所を「多い順」に先頭行番号つきで提示する（`Metrics::SentenceEndings` を新設、`Formatter#format_sentence_rhythm`）。「です・ます」ばかりが続く単調さを内訳で俯瞰し、特に直したい連続箇所（例「ます。が32連続」）を上位から把握できる。文末分類は形態素解析に頼らないパターン判定（です・ます／だ・である は確実、体言止めはひらがな以外で終わる名詞止めの近似）。連続の最小本数は 5（和文では 3〜4 連続は普通のため）。`SentenceCollector` の文収集は最長文セクションと共有。回帰テスト（分類・内訳・連続検出・体言止めラベル・桁そろえ表示）を追加。マニュアル（`32-metrics.md`）に説明を追記。
- [Low] **`vs metrics` に「見直したい長い文」セクションを追加（位置つきの最長文）**: 本文中で特に長い文（80 文字以上）の上位 5 件を、出現位置（章・行番号）と冒頭抜粋つきで提示する（`Metrics::SentenceCollector` を新設し行番号を保ったまま文を収集、`Formatter#format_long_sentences`。章番号・行番号・字数は右詰めで桁そろえ）。平均文長だけでは分からない「一文に詰め込みすぎた箇所」をエディタで直接開けて推敲できる。フェンスドコードブロックや見出し・表などの構造行は対象外、インラインコードを除いた本文基準で字数を数える。回帰テスト（行番号記録・複数行文・コード除外・構造行除外・桁そろえ）を追加。マニュアル（`32-metrics.md`）に説明を追記。
- [Low] **`vs metrics` に「章間のばらつき」セクションを追加（外れ章の検出）**: 漢字比率・平均文長について、全章の平均と標準偏差（ばらつき幅）を算出し、平均±標準偏差を超える章を「高め／低め（長め／短め）」に分けて各最大 3 章まで提示する（`Metrics::Consistency` を新設、`Formatter#format_consistency`。高め／低めは別行で表示）。全体平均だけでは分からない「浮いている章（難しすぎ・易しすぎ・文が長すぎ）」が分かり推敲の手掛かりになる。前書き・付録・後書き（`exclude_chapters`）と本文のない章は比較対象から除外し、対象が 2 章以上のときだけ出力（ばらつき 0 のときは外れ章なし）。回帰テスト（平均・母標準偏差・高低振り分け・件数上限・均一時）を追加。マニュアル（`32-metrics.md`）に説明を追記。
- [Low] **`vs metrics` の語彙難度に文字種構成（漢字／ひらがな／カタカナ／英字／その他）を表示**: 本文（コード除去後）を構成する文字種の割合を併記（`Formatter#character_composition`）。和文の読みやすさの目安（漢字3:ひらがな7 など）や、カタカナ語・英字の多さ＝専門用語の密度が一目で分かり、入門書での言い換え検討などに使える。`VocabularyStats` に `hira_char_count` / `kata_char_count` / `alpha_char_count` を追加して集計・キャッシュ（schema を 4 へ）。分母は漢字比率と同じ `total_char_count` にそろえ、表示される漢字%が漢字比率と一致する（その他＝数字・記号・句読点）。回帰テスト（文字種カウント・構成表示）を追加。マニュアル（`32-metrics.md`）に評価基準を追記。
- [Low] **`vs metrics` の詳細分析に使用語彙数（異なり語数・総語数）を表示**: 語彙多様度（MATTR）の評価ラベルに加え、実際に使われた**異なり語数**と**総語数**を併記（`Formatter#format_detailed_analysis`）。「豊富/標準的」の判定根拠となる語彙の規模が一目で分かり、評価への納得感が増す。値は既存の `unique_tokens` / `total_tokens` をそのまま表示（追加計算なし）。回帰テストを更新。
- [Low] **`vs metrics` の `--json`/`--yaml` の `totals` に読解難度（RS）を追加し、キャッシュに読解特徴量を保存（schema v2）**: 構造化出力の `totals` に `readability`（`score` / `label`）を追加し、外部ツールが全体の読みやすさを再計算せず取得できるように（`Metrics::Readability` モジュールを新設）。全体 RS は章ごとの RS を平均するのではなく、各章の特徴量（文・連・句読点の数）を合算してから一度だけ算出する（平均値を非線形に使う式のため）。章キャッシュ `.cache/metrics/{章}.yml` に読解特徴量を保存し、再解析せず正確に再合成できる。キャッシュ構造を破壊的に変更したため `schema_version` を導入（旧キャッシュは自動的に無効化して再解析）。回帰テスト（建石式の手計算一致・特徴量抽出・合算・ラベル境界・キャッシュ往復・schema 無効化・JSON totals）を追加。

### Changed
- [Medium] **ビルドパイプラインの出力ターゲット判定と full mode 分岐を宣言化（BuildPlan 宣言化・VivlioVerso 基盤整備 P2）**: `UnifiedBuildPipeline`（`pipeline.rb`）は、出力ターゲット判定を 4 メソッド（`pdf_target?`/`print_pdf_target?`/`epub_target?`/`kindle_target?`）が**ビルドのたびに CONFIG を都度解析**して重複判定し、full mode のステップ列は **5 分岐＋3 補助メソッドの手組み**で、同一処理に `Step 10 (print pdf)` と `Step 13 (print pdf)` のような**番号矛盾**を抱えていた（課題 A: 分岐爆発）。(1) **`Build::Targets` 値オブジェクトを新設**（`build/targets.rb`）し、`output.targets` の解決を**ビルド開始時に 1 回だけ**行う不変値（`pdf`/`print_pdf`/`epub`/`kindle`＋`epub_or_kindle?`/`any_pdf?`）へ集約。4 判定メソッドを撤去し、`initialize` に `targets:` を DI 追加（省略時 `Targets.resolve`）。`pdf`/`print_pdf` のみ `output.pdf.targets` フォールバックを見る**現行の非対称は忠実に維持**。(2) **5 分岐を 1 枚の宣言的ステップ表（`full_mode_step_table`）へ畳んだ**。各行＝`[ラベル, ハンドラ, 実行条件]`で、分岐は条件列（`targets` 依存の真偽値）へ吸収。**ステップ番号を撤去**し番号なしの安定ラベル（`build overall pdf` / `print pdf` / `generate epub` 等）へ統一、ログの `[Step N]` プレフィックスもラベル名へ置換。(3) **実装分離**: 入稿用 PDF 生成（6 メソッド）を `Build::PrintPdfBuilder`、EPUB/Kindle オーケストレーション（フレーバ別ビルド・dedup 隔離スナップショット・KPF 変換）を `Build::EpubFlow`、content.opf の zip 手術（identifier 安定化・NCName id 修正・安定 UUID）を `Build::EpubBuilder` へ移設。`pipeline.rb` は **796→429 行（約 46% 減）**。回帰ゲートとして `pipeline_steps_test.rb`（全 16 ターゲット組×mode の「操作キー列」スナップショット。番号付き分岐でも番号なしテーブルでも同一で比較できる正規化を採用）を新設し、pre-P2 と全 16 組が操作同一であることを固定。**出力同一性**は実マニュアル（26 章）を pdf ターゲットで移行前後ビルドし、生成 HTML 35 本・前処理済み Markdown 25 本・PDF 総ページ数（400）がバイト単位／数値で完全一致することを実測確認。EPUB ターゲットの実ビルド成功も確認。仕様は [vivlioverso-foundation-workplans.md](docs/specs/vivlioverso-foundation-workplans.md) P2。
- [Medium] **Markdown のコード領域（フェンス/インライン）解釈を `CLI::Masking` へ一元化（マスキング 12+ 重複実装の集約・VivlioVerso 基盤整備 P1）**: 「コードブロックを処理対象から外す」というニーズが横断的に存在し、索引・校正・メトリクス・画像/リンク検証など **11 の独立実装**にコード判定の状態機械が散在していた。方式がバラバラ（`~~~`・可変長フェンス・入れ子・`` ```include: `` 除外の対応が実装ごとに欠落）で、`` ````markdown `` の入れ子（本マニュアル自身が使用）に対し単純トグル実装が内外反転する時限バグを抱えていた。行頭フェンスのみを数える唯一の状態機械 `CLI::Masking`（`lib/vivlio_starter/cli/masking.rb` 新設）に `each_prose_line` / `strip_code` / `protect_code` / `restore_code` を集約し、以下を移行: `index/code_block_stripper`（`strip_code` へ委譲）・`pre_process/markdown_utils`（`protect_code`/`restore_code` へ委譲。プレースホルダ書式互換）・`lint/tokenizer`・`metrics/analyzer`・`metrics/sentence_collector`・`index/index_match_scanner`・`pre_process/image_path_normalizer`・`pre_process/link_image_validator`（4 箇所）・`pre_process/frontmatter_generator`・`pre_process/markdown_transformer`（4 ループ）・`pre_process/cross_reference_processor`（3 ループ）。`guards/code_fence_check`（検証器）は `FENCE` 定数のみ `Masking` を参照。**挙動改善**: 従来 `` ``` `` 単純トグルだった `tokenizer`・`image/link validator`・`index_match_scanner` 等に、`~~~`・可変長フェンス・入れ子・`include:` 除外への追従が加わり、入れ子フェンス直後の本文を誤ってコード扱いする潜在バグが解消（`lint` に回帰テスト 2 件追加）。`masking_test.rb`（意味論統一の回帰ゲート：`lint`/`metrics`/`index` がコード行集合を一致させる検証を含む 14 件）を新設。**出力同一性**: 同梱マニュアル（26 章）を pdf/print_pdf/epub/kindle 全ターゲットで移行前後ビルドし、生成 HTML 35 本・前処理済み Markdown 25 本がバイト単位で完全一致することを実測確認。仕様は [vivlioverso-foundation-workplans.md](docs/specs/vivlioverso-foundation-workplans.md) P1。
- [Medium] **catalog.yml のパーサを `Build::CatalogLoader` へ一本化（パーサ乖離の構造的解消）**: 「各コマンドの独自な章展開解釈を `TokenResolver` へ集約する」過去のリファクタで、章指定トークンの解釈は統一されたが **catalog.yml の YAML パース層は 3 実装に分散したまま**残っていた。これを 2 層構造（各コマンド → `TokenResolver`〔Entry モデル・トークン照合〕→ `Build::CatalogLoader`〔唯一のパーサ：YAML パース・セクション/ショートハンド展開〕）へ整理した。(1) `CatalogLoader` に下層 API `load_labeled_entries`（`CatalogEntry`＝basename/label/section の 3 つ組を返す）を追加し、`load_catalog`・`expand_item` 系をキーワード引数でパラメタ化（テストからのパス注入に対応。既存の `load_all_basenames` 等はデフォルト値で無変更）。(2) `TokenResolver#load_catalog_entries` を `CatalogLoader` への委譲に置換し、自前 YAML パース（`extract_from_yaml` / `normalize_catalog_basename`）を削除。(3) `Metrics::CatalogLoader`（`CatalogLoader` の劣化コピー。ショートハンド・エイリアス非対応）を**ファイルごと削除**し、`Metrics::Runner#resolve_from_catalog` を `TokenResolver` 経由へ乗せ替え。metrics 固有のエラー耐性（catalog 破損でもハード停止せず warn＋全 Markdown へフォールバック）は runner 側の `rescue` として明示化した（＝パーサの実装差ではなく呼び出し側のポリシー差として表現）。(4) 未知トップレベルセクション（`CHAPTER:` 等のタイプミス）は無視に統一しつつ警告を出す。これにより上記 Fixed のバグ 2 件が構造的に解消される。リグレッションゲートとして `load_all_basenames == load_labeled_entries.map(&:basename)` の同値性テストを新設。仕様は [catalog-parser-unification-spec.md](docs/specs/catalog-parser-unification-spec.md)。
- [Low] **`page_presets.yml` の読み込みを `YAML.safe_load_file` に統一**: `Common.load_page_presets` だけが `YAML.load_file` を使っており、起動時検証（`ensure_required_yaml_files!`）の `safe_load` 経路とパースポリシーが不揃いだった。`safe_load_file(aliases: true, symbolize_names: true)` へ揃えて YAML 読み込みポリシーを一系統に（プリセットの差分定義 `<<: *a5_std` に必要な aliases は維持。Psych 5 では `load_file` も安全読み込みのため挙動不変のスタイル統一）。
- [Medium] **`Common::CONFIG` の互換層を完全撤去し正規記法のみに（アクセス記法統一 Phase 3・次期メジャーを待たず即時適用）**: (1) **String キーの全面禁止** — `CONFIG[]`/`dig` へ String キーを渡すと警告ではなく **ArgumentError**（「Symbol でエラーになったので String を渡す」というその場凌ぎの再発を構造的に不可能に）。この厳格化により残存していた文字列キー 6 箇所を検出・修正した。うち 2 件は実バグ: **pipeline の圧縮判定がレガシー `pdf.compress` を読んでおり、正規の `output.pdf.compress` がずっと効いていなかった**（`Common.pdf_compress?` に一本化して解消）、cover.rb の二重 dig（`dig(:output,:cover) || dig('output','cover')`）はシンボル側が nil のとき文字列側で例外になる時限バグだった。(2) **`fetch` / `fetch_bool` を削除**（Hash#fetch と意味論が異なる混乱の元。呼び出しゼロを確認のうえ撤去）。(3) **Hash/Data ブリッジ 3 系統を削除** — `resolve_page_size` は「シンボルキー Hash 前提（Data は境界で `.to_h`）」に統一、`variable_font_injector#config_value`（Hash/Data 両対応アクセサ）は `[:key]` 直接参照へ、`resolve_vivliostyle_size`/epub_builder の `respond_to?` 型分岐も撤去。(4) common.rb 冒頭のハイブリッド仕様コメントを仕様書参照へ刷新し、テストの設定偽装も One Way（`wrap_config` 経由・`symbolize_names: true`）に統一。これで **book.yml へのアクセスは「静的キーはドット・動的キーはシンボル」の一系統のみ**となり、次期バージョンアップの土台が整った。
- [Medium] **`Common::CONFIG` のアクセス記法を全呼び出し側で統一（アクセス記法統一 Phase 2）**: 仕様書 [config-access-unification-spec.md](docs/specs/config-access-unification-spec.md) の正規記法「静的キーはドット・動的キーはシンボル」へ、lib 全域（約 30 ファイル・約 90 箇所）を一斉移行した。(1) 文字列キーのブラケット/dig（`CONFIG['pdf']` / `dig('output','cover')`）をドット記法へ置換。(2) `respond_to?` ガード・`&.[]` ハイブリッド・`|| {}` フォールバックを既定値スキーマ前提で削除（lint.rb / index 系 / create.rb / pdf_read 等）。(3) **cover.rb / clean.rb の `Common.load_config` 直接呼び出し（毎回のディスク再読込）を `Common::CONFIG` 参照へ一本化**。(4) **metrics/ConfigLoader の独自 YAML 直読みを廃止**し `Common::CONFIG.metrics` を入力に（内部も文字列キー→シンボルキーへ全面書き換え。テスト用の Hash 差し替え口は境界で正規化して維持）。(5) heading_processor の二重 dig（シンボル‖文字列）を単一化。(6) pdf.rb のセクション ivar メモ化を都度参照に変更（`reload_configuration!` 後の stale 参照防止）。(7) `CONFIG#fetch` に deprecation 警告を追加（Phase 3 で削除予定）。あわせて**未文書のレガシー設定パスを撤去**: `pdf:` トップレベルセクション（`output_file`/`output_file_compressed`/`single_doc`/`close_existing_windows`/`window_bounds` の旧フォールバック）と `output.pdf.targets`。`single_doc` は環境変数 `VIVLIO_SINGLE_DOC=1` のみで有効化する開発者向け機能に整理。PdfOpener の `close_existing_windows` 判定は `output.pdf_preview` のみを参照する正実装に修正（従来は Data 化により常に rescue 既定値へ落ちる潜在バグだった）。
- [Medium] **`Common::CONFIG` の設定アクセス基盤を安全化（アクセス記法統一 Phase 1）**: (1) **`[]` のメソッド漏れを修正** — 旧実装（`respond_to?` ベース）では `CONFIG[:to_h]` が設定全体を、`CONFIG['inspect']` が inspect 文字列を返していた。member 限定の参照に改め、非メンバーキーは常に nil を返す（String キーは移行互換として Symbol へ正規化）。(2) **既定値スキーマを全 16 セクションへ拡大** — 従来は 6 セクション（directories/cache/commands/files/vivliostyle/vfm）のみ既定値があり、`lint:` 等を book.yml から削った最小構成では `CONFIG.lint.config`（lint.rb）や `CONFIG.project`（pipeline.rb）が **NoMethodError でクラッシュ**していた。book.yml が持ち得る全セクション・コードが参照する既知キーに既定値（未設定は nil）を与え、ドット記法を常に安全にした。マージは **deep merge** 化し、`output.pdf.compress` だけ書いても兄弟キー（`combined` 等）がスキーマから残る。「キーだけ書いて値が空欄」（nil）は既定値を採用し、false は明示設定として尊重。(3) `deconstruct_keys(nil)` が空 Hash を返す Ruby 規約逸脱を修正（`in { **rest }` で全キーを束縛可能に）。(4) Data の予約メソッド名（`hash`/`with`/`to_h` 等）と衝突するキーをロード時に警告。回帰テスト 16 件（`common_config_loading_test.rb`：記法・メソッド漏れ・最小 book.yml・deep merge・reload）を新設。仕様は [config-access-unification-spec.md](docs/specs/config-access-unification-spec.md)（Phase 2 で呼び出し側の記法統一、Phase 3 で互換層削除を予定）。
- [Low] **book.yml の `vfm.hardLineBreaks` を `vfm.hard_line_breaks` へ改名（snake_case 統一）**: book.yml のキー命名を snake_case に統一（`Common.default_vfm`・プロジェクト/scaffold の book.yml・マニュアル 41 章）。**章フロントマターの `vfm: hardLineBreaks:` と `vivliostyle.config.js` の `vfm.hardLineBreaks` は VFM / Vivliostyle CLI 自身の API キーのため camelCase のまま**（そちらを書き換えると改行変換が壊れる）。book.yml 側のこのキーは現状コードから未消費のため挙動変更なし。
- [Medium] **`vs metrics` の語彙多様度を生 TTR から MATTR（移動平均 TTR）へ変更（文書長依存の解消）**: 生の TTR（異なり語 ÷ 総語）は文書が長いほど機械的に低下し（異なり語は語数の平方根程度でしか増えない）、章の長短で値が変わって比較できず、本書全体では 0.07 まで潰れて「単調」と誤判定していた。一定語数の窓を 1 語ずつずらして各窓の TTR を平均する **MATTR**（Covington & McFall 2010）へ置き換え、**文書長に頑健**な多様性指標にした（実原稿で長章 61＝8771 語の値が生 TTR 0.147→MATTR 0.579 と中央値並みに是正）。窓幅は既定 100 語（quanteda 既定に準拠。`book.yml` の `metrics.mattr_window` で 50〜100 を目安に変更可、`Analyzer#moving_average_ttr` は O(n) のスライディング集計）。全体値は MATTR が長さに頑健なことを利用し各章 MATTR の**語数加重平均**で代表（頻度マップから語順は復元できないため）。評価バンドは MATTR の値域に合わせ `0.5/0.6/0.7`（単調/標準的/豊富/非常に豊富）へ較正。表示・キャッシュ（`schema_version` を 3 へ）・マニュアル（`32-metrics.md`）を更新。生 TTR も参考値として `VocabularyStats#ttr` に保持。回帰テスト（長さ頑健性・短文フォールバック・窓平均の手計算一致・語数加重集計・窓幅設定）を追加。
- [Medium] **`vs metrics` の読解難度を建石式リーダビリティー（RS）に刷新し、コードを文章分析から除外**: 従来の読解難度は「平均文長 × 0.5 ＋ 漢字比率 × 0.5」という独自の単純加重平均で、`日本語版 Flesch` と称しながら実態は定評ある式ではなく、スコア値に意味がなかった。これを **建石由佳・小野芳彦・山田尚勇 (1988)「日本文の読みやすさの評価式」** の RS（文長・漢字/ひらがな/カタカナ/アルファベットの連の平均長・句読点比から算出する文字種ベースの決定的指標）へ置き換え（`Metrics::Readability`）。**RS は値が大きいほど読みやすい**ため評価の向きが反転し、`book.yml` の `lint.readability` 既定を新方向のバンド下限（`easy: 60` / `standard: 40`。実原稿の実測分布で校正）に修正、`日本語版 Flesch/Kincaid` という誤った説明も訂正。あわせて、漢字比率・語彙多様度（TTR）・読解難度の各分析から**コードブロック／インラインコードを除外**（英数字・記号の塊が指標を実態より平易側に歪めるため。文字数＝章別分量にはページを占める実体としてコードを含めたまま）。`Analyzer` は分量用の生本文と、文構造・語彙・読解で共通利用する prose（コード除去後）を分離。マニュアル（`32-metrics.md`）の読解難度の説明・評価表・出力例・設定例を新方式へ全面更新。
- [Low] **`vs lint` の textlint 出力フォーマット切替を廃止し、集約表示一択に簡素化**: 実用上 `aggregate`（ルール単位の集約）一択で十分なため、`book.yml` の `lint.format` を削除し、内部の切替機構（`format_option` / textlint ネイティブ経路 / stylish 再整形の `TextlintFormatter::Reformatter` / `reformat_output` / `translate_output` / 関連定数・サマリー抽出ヘルパー）を一括撤去（JSON 解釈失敗時のみ生出力へフォールバック）。コード・テスト（reformat/translate のユニットテスト約 30 件）が減り保守が軽くなった。`lint.config`（.textlintrc.yml のパス）は使い分け用に存続。
- [Low] **`vs lint` のユーザー辞書を `config/user_words.txt`（プロジェクト直下）へ変更し、`--register` をスペルチェック専用化＋ `--config`/`--format` オプションを廃止**: ユーザー辞書を `~/.config/vivlio-starter/spellcheck/user-words.txt`（深い・隠しフォルダ）から **プロジェクト直下 `config/user_words.txt`**（snake_case・見つけやすい・別の本へコピー可能）へ移動。`register_user_words` は登録時に**辞書順ソート＋大文字小文字無視の一意化**でファイルを書き直す（編集過程の重複・未整列も毎回整える）。`--register` は**スペルチェック専用の操作**として暗黙に textlint をスキップ（`--spellcheck-only` 併記不要。"only なのに register" の違和感を解消）。集約表示で十分なため `--format` を、パス切替はリネームで足りるため `--config` を CLI オプションから廃止（textlint 設定パスは `book.yml` の `lint.config`）。回帰テスト（辞書順ソート・CWD 相対パス）を更新。仕様は [lint-spellcheck-workflow-spec.md](docs/specs/lint-spellcheck-workflow-spec.md) §2.2〜2.4。
- [Low] **`vs preflight` の完了サマリーに文章校正コマンドへの誘導を追加**: preflight は構造チェック（Guards ＋外部 URL 検証）のみで textlint/spellcheck は実行しない方針のため、サマリー末尾に「文章校正（表記揺れ・スペル）は vs lint で行えます。」の一文を添えた（`print_preflight_summary`）。仕様は [lint-spellcheck-workflow-spec.md](docs/specs/lint-spellcheck-workflow-spec.md) §3.3。
- [Low] **`vs lint` に textlint ルールの個別無効化と表記揺れ誤検出への対処を追加**: 集約表示でルール衝突・誤検出が一目で分かるようになったのを受け、`book.yml` に `lint.disabled_rules`（ルール ID で丸ごと無効化。例：`arabic-kanji-numbers` の「一つ→1つ」と prh の「一つ→ひとつ」の衝突解消）と `lint.disabled_terms`（`"X => Y"` 表記揺れ系の指摘を語で個別無効化）を新設（`TextlintFormatter.aggregate_json` の集約前フィルタ。除外分は問題数・終了コードに数えない。root/scaffold book.yml）。`sentence-length` のように出現ごとに数値が変わる指摘は `RULE_SUMMARIES` で要約ラベル「一文が長すぎます（最大文長を超過）」に畳んで集約（意味のある数値は保持）。`spellcheck-tech-word` の「対処方→対処法」が「対処方法」に誤発火する件は `config/textlint_allowlist.yml` に「対処方法」を登録して抑止。回帰テスト（disabled_rules / disabled_terms / sentence-length 要約）を追加。仕様は [lint-spellcheck-workflow-spec.md](docs/specs/lint-spellcheck-workflow-spec.md) §3.2。
- [Medium] **`vs lint` の textlint 出力を既定で「ルール単位の集約表示」に変更（冗長な重複の解消）**: 同じ指摘が行ごとに大量に並んでいたのを、`textlint --format json` を取得して **[メッセージ先頭行, ルール] 単位に集約**し、`N件 [ルール] 指摘` ＋ 出現行（件数降順・最大 10 行＋…）で表示する（`TextlintFormatter.aggregate_json`、スペルチェック側の集約と体裁統一）。既定フォーマットを `aggregate` に変更（`book.yml` の `lint.format` root/scaffold ＋ `DEFAULT_FORMAT_FALLBACK`）。`--format stylish`（/`compact`/`pretty-error`/`json`）で従来の textlint ネイティブ出力に切り替え可能、`--fix` 時はネイティブ。検査対象の一時ファイルパスは元ファイル名へ戻す。回帰テスト（集約・不正 JSON フォールバック・指摘ゼロ除外）を `textlint_formatter_test` に追加。仕様は [lint-spellcheck-workflow-spec.md](docs/specs/lint-spellcheck-workflow-spec.md) §3.1。
- [Low] **PDF 検査テストを AGPL HexaPDF 非依存化し、`rake test` の skip をゼロに**: `cover_test` / `cover_crop_marks_bugfix_test` の PDF 寸法・トンボ検査を HexaPDF から MIT の pdf-reader（`attributes[:MediaBox]` / `raw_content`）へ移行し、プラグイン未バンドル時に skip していたテストを常時実行へ。`nombre_stamper_test` も同様（生成は Prawn）。`provider_mode_test` のプロバイダ選択テストは「プラグイン有無で期待値を切り替える常時実行型」に統合し、環境依存 skip を解消。結果、`rake test` / `rake test:standard` とも skip ゼロ・全件実行（`module VivlioStarter::CLI` 配下では `VivlioStarter::PDF`（`mecab_newline_cleaner`）と衝突するため `::PDF::Reader` と完全修飾する点に注意）。
- [Medium] **拡張プラグイン `vivlio-starter-pdf` を rubygems 公開版へ切り替え（ローカルパス依存の撤去）**: 本体 `Gemfile` の `gem 'vivlio-starter-pdf', path: '../vivlio-starter-pdf'`（ローカル開発用）をコメントアウトし、`bundle install` で `Gemfile.lock` から plugin 依存を除去。AGPL の plugin を MIT 本体の bundle へ取り込まず、`gem install vivlio-starter-pdf`（rubygems 公開版 **1.1.1**）済みなら `provider.rb` が自動検出して Enhanced モードへ切り替える設計どおりに統一した（`bundle exec` 下でも公開版 1.1.1 の `EnhancedProvider` を解決することを確認）。FT-02 を含む不具合版 1.1.0 は rubygems から yank 済み。
- [Low] **`@vivliostyle/cli` を 11.0.2 に厳密固定**: `package.json` のバージョン指定を `^11.0.2` → `11.0.2` に変更し、ビルド再現性のためマイナー自動更新を抑止（`lib/project_scaffold/package.json` も追従）。
- [Low] **`vs new` の `--force` を `--add-missing` に改称**: 既存ディレクトリへ「不足ファイルだけを非破壊で追加する（既存ファイルは保持）」という実態に対し `--force` は誤解（上書き）を招くため、`--add-missing` へリネーム（`new_command.rb` / `new.rb`・エラーメッセージ・関連テスト）。`--force` という名前のオプションは廃止。
- [Low] **単章ビルド（`vs build <章名>`）を PDF 専用化**: 単章プレビューは EPUB/Kindle・入稿用 print_pdf を生成せず PDF のみを出力するよう `UnifiedBuildPipeline#register_single_mode_steps` を簡素化（不要になった単章用の print_pdf/epub 生成系メソッド 7 件を削除）。プレビュー所要が約 80s→25s に短縮。`44-build.md` に「単章ビルドは PDF 専用」と明記。
- [Low] **`.note` のデザインを上下アクセントカラーの二重線に変更**: 目立たなかった `.note`（上下の細い灰色線のみ）を、`.notice` の左アクセント線を上下へ移したデザイン（`border-block-start` / `border-block-end: double 1mm var(--color-mark)`）へ変更（`chapter-common.css` root/scaffold）。
- [Low] **`vs new` の著者/発行者プロンプトに説明を補足**: 「著者＝原稿を書いた人」「発行者・サークル名＝本を世に出す主体（お一人なら著者と同じでも可）」のヒントを対話プロンプトと確認サマリーに追記（`new.rb`）。プロンプト文言の回帰テストを追加。マニュアル（`13-new.md`）に著者/発行者の違いと `catalog.yml` の概要（機能・役割・記述方法）の説明を追記。
- [Low] **`vs doctor` の診断対象ドキュメントを実装へ追従**: `51-doctor.md` / `91-install.md` の診断対象・自動インストール一覧と `doctor.rb` のコメントを実装に合わせて整合（`pdftoppm` / `mathjax` / `rsvg-convert` / `kindlepreviewer` を追補）。Linux/Windows の動作は未検証である旨を明記し、`PLANNED.md` に将来の Linux/Windows 対応を追記。
- [Low] **EPUB 表紙画像の拡張子を `.jpg` / `.jpeg` 両対応に**: `EpubBuilder#resolve_cover_image_path` が `cover_{theme}.jpg` 決め打ちで `.jpeg` を認識せず表紙なしになっていたのを、`.jpg` 優先で実在する方を採用するよう改修（`epub_builder.rb`）。EPUB 設定行生成（`build_cover_config_line`）とカバー生成スキップ判定（`generate_epub_cover_if_needed`）の双方に波及。あわせて `copy_to_scaffold.rb` の `covers/` 不要ファイル除去で `.png` / `.jpg` / `.svg` / `.md` を温存する処理を追加。
- [Low] **会話文の隠れクラス名をローマ字へ修正し、当該節を一旦オフライン化**: 会話文（`【先生X】`/`【生徒X】`）が生成する隠れクラスの綴りを `.kaiwa.sense`→`.kaiwa.sensei` / `.kaiwa.deshi`→`.kaiwa.seito`（生徒＝seito）へ修正（`replace-list.css` / `post_replace_list.yml` root/scaffold）。あわせて記法・設定方式（`config/characters.yml` 化・アイコン・吹き出しの左右レイアウト等）が未確定のため `22-extentions.md` の「会話文」節を HTML コメントで本文から外し、刷新案を `PLANNED.md` に起票。`先生`/`生徒` のハードコード経路自体は当面残置。

### Removed
- [Low] **`book.yml` の死蔵設定キー `metrics.sentence_length` / `metrics.clause_length` を削除**: 読解難度を建石式リーダビリティー（`readability`）へ刷新した際に、平均文長・平均節長を閾値判定する経路が失われ、これら 2 ブロックは `Metrics::ConfigLoader` からも一切読まれない死蔵設定になっていた（コメントは「これ未満: 短すぎて幼稚な印象」等と判定閾値のように書かれたままで誤解を招く／長文ワースト抽出は `runner.rb` の `LONG_SENTENCE_MIN = 80` ハードコード）。`config/book.yml` の「文構造の基準」節ごと撤去（scaffold へは `copy_to_scaffold.rb` で反映）。マニュアル `41-book-yml.md` の metrics 節も、プリセットが切り替えるのは `chapter`/`section` の分量のみで、語彙難度・語彙多様度・読解難度・`labels` はプリセット外の共通設定である旨に修正。
- [Low] **`vs metrics` の死蔵コードを削除（旧実装 metrics.rb ＋ 未使用フォーマッタ）**: `lib/vivlio_starter/cli/metrics.rb` の旧実装クラス群（`MetricsRunner` / `MarkdownResolver` / `StatBuilder` / `TotalsCalculator`（＋ `TotalsAggregator`）/ `TablePrinter`）は、実行経路が `Metrics::Runner` へ移行した後どこからも参照されておらず（テストも無し）、約 380 行の完全なデッドコードだったため撤去。`metrics.rb` は現役の入口 `MetricsCommands`（`Metrics::Runner` へ委譲）＋後方互換エイリアス `TextMetricsCommands` のみの 30 行に縮小（旧クラス専用だった `require 'json'` / `'yaml'` / `token_resolver` も削除。Runner が自前で読み込む）。あわせて `Formatter#format_chapters`（章別分量の一括描画）も、実出力が逐次描画（`format_chapter_line`）へ移行済みでテストからのみ到達する死蔵だったため削除し、バー描画のカバレッジは現役の `format_chapter_line` を直接検証するテストへ置き換えた。
- [Low] **`.two-col` を廃止し `.text-2dan`（段組）に一本化**: CSS が完全に同一だった `.two-col` と `.text-2dan` を `.text-2dan` に統合し `.two-col` を削除（`layout-utils.css` / `templates/chapter.md` root/scaffold）。マニュアル（`22-extentions.md`）の段組例も、縦並びになって誤解を招く短項目の二列例を割愛し、長文を二段組に流し込む例のみへ整理。
- [Low] **`.table-scroll`（横スクロール表）を廃止**: `overflow-x: auto` による横スクロールは HTML プレビュー時のみ有効で、vivlio-starter が対象とする PDF / print_pdf / EPUB / Kindle では出番がないため、CSS（`table.css`）・前処理変換（`markdown_preprocessor.rb` の table コンテナ変換対象から除外。`long-table` のみ残す）・テンプレート（`templates/chapter.md`）・マニュアル（`22-extentions.md` / `61-developer.md`）から一括削除。広い表は `.long-table`（折返し）・`.table-rotate`（横向き）で対応。
- [Low] **`@div:CLASS` … `@divend` 短縮記法を廃止**: `:::{.class}` コンテナと完全に等価（しかも `@div:note`/`@divend` より `:::{.note}`/`:::` の方が記述量が短い）で、生の正規表現置換ゆえ入れ子・テスト面で不具合の温床になりうる冗長な別経路だったため削除。`config/post_replace_list.yml` の 2 ルール、予約マクロID リスト（`cross_reference_processor.rb` の `RESERVED_MACRO_IDS` から `div` / `divend`）、マニュアル（`22-extentions.md` の解説節・`24-cross-reference.md` の予約ID表）、関連テスト（`<pre>` 保護の例を `:::` 記法へ差し替え、予約ID/マクロ保持テストから `div`/`divend` を除外）を一括撤去。`:::{.class}` … `:::` を正規の記法とする。`@nega`/`@posi`/`@comment` 等の他マクロは存続。
- [Low] **`@clear` / `---{.pagebreak}` / `---{.blankline}` を廃止**: 正式公開前の整理。(1) `@clear`（回り込み解除）は sideimage が `display: grid` 化済みでそもそも回り込みが発生せず、生成先 `.floatclear` の CSS も存在しない**実質 no-op** だったため撤去。(2) `---{.pagebreak}` は素の `---`（`<hr>`→`<hr class="pagebreak">` 変換）で既に改ページになり冗長なため明示記法を撤去（`---`＝改ページの挙動と `hr.pagebreak` CSS は存続）。(3) `---{.blankline}` は `{.aki}` / `<br>` で代替できるため `hr.blankline` CSS ごと撤去。`config/post_replace_list.yml`（`@clear` ルール）・`RESERVED_MACRO_IDS`（`clear`）・`chapter-common.css`（`hr.blankline`）・マニュアル（`22-extentions.md` の該当節を簡潔な「改ページ」案内へ／`24-cross-reference.md` の `@clear` 行）・`templates/chapter.md`・関連テスト（`html_replacer_test` の `:text_only` 例を `@vspace` へ差し替え、予約ID/マクロ保持テストから `clear` を除外）を一括撤去。

### Fixed
- [Medium] **相互参照 `@ID` の誤検出を修正（リンク・索引マークアップ・裸 URL 内の `@` を除外）**: 本文中の `@語` 参照走査が、Markdown リンク/画像のテキスト・URL 内（例: `[npmjs.com/@vivliostyle/cli](https://…/@vivliostyle/cli)`）、索引・用語集の手動登録マークアップ（`[用語|読み]`・`[@用語]`）内、および角括弧の外に現れる裸 URL（リンク脚注化が追記する脚注定義行 `[^url1]: https://…/@scope/pkg` 等）内の `@` まで「未定義のラベルID」として誤検出していた。`ReferenceReplacer` に除外スパン（`MASKED_SPAN_PATTERN`）を導入し、これらを参照走査から素通しするよう修正（除外スパンの間に書かれた正当な `@参照` は従来どおりリンク化される）。バッククォート外の平文に裸で書かれた `@語`（表セルへ生書きした npm パッケージ名等）は従来どおり検出する——インライン code で括るのが正であり、61-developer.md の第二表のパッケージ名 3 行もバッククォート化した。回帰テスト 4 件を `markdown_transformer_test` へ追加。
- [Medium] **catalog.yml のパーサ乖離による潜在バグ 2 件を解消（YAML エイリアス非対称・ショートハンド誤解釈）**: catalog.yml の読み込みが 3 実装（`Build::CatalogLoader` / `TokenResolver` 自前パース / `Metrics::CatalogLoader`）に分散し、同じファイルを同じビルド内で異なる解釈で読んでいた。最小プロジェクトで再現確認した 2 件を修正: **バグ1（エイリアス非対称）**＝ catalog.yml に YAML アンカー/エイリアス（`&x` / `*x`）を書くと `Build::CatalogLoader`（DRY な記述のため許可）は通るのに `TokenResolver` が `Psych::AliasesNotEnabled` でクラッシュし、guards は合格するのにビルド本体が落ちた。**バグ2（ショートハンド誤解釈）**＝ catalog.yml 内のショートハンド `21-25`（章 21〜25 の範囲指定）を `TokenResolver` が「number=21, slug=25」の幽霊エントリ（`contents/21-25.md` 不在）と誤解釈し、**21〜25 章が丸ごとビルド対象から脱落**していた（`chapter_config.rb` は正しく展開するため 1 ビルド内で解釈が二重化）。あわせて番号のみファイル（`15.md`）を bare number（`- 15`）で catalog 参照した際、`TokenResolver` は拾うが `CatalogLoader` は `NN-*.md` のみ glob して落とす乖離も是正（両者とも `NN.md` を拾う）。実プロジェクトの catalog.yml は該当記法を未使用のため未顕在の「時限バグ」だったが、実 catalog にエイリアス＋ショートハンドを一時投入して両修正を実地確認した。仕様は [catalog-parser-unification-spec.md](docs/specs/catalog-parser-unification-spec.md)。
- [Medium] **`book.yml` に `title` キーが無い通常構成で PDF タイトルが `vivliostyle.config.js` へ同期されない不具合を解消**: `CssUpdater#sync_vivliostyle_config_title!` が `book['title']`（String キーのブラケットアクセス）で値を読んでいたが、CONFIG 互換層の撤去（frozen `Data` 化）後は String キーのブラケットアクセスが `ArgumentError`（「CONFIG のキーは Symbol で指定してください」）を送出するようになり、`title` キーを持たない通常の book.yml（`main_title` + `subtitle` 運用）でこの例外がメソッドの `rescue` に捕まって「title 同期に失敗」の警告だけ出し、**タイトルが一切同期されず PLACEHOLDER のまま**になっていた。値の参照を正規のドット記法 `Common::CONFIG.book.title` / `.main_title` / `.subtitle`（`title` は `default_config_schema` のメンバーで未指定時は nil）へ統一し、`title` 未指定時は `main_title` + `subtitle` を結合して同期する本来の挙動を復元した。回帰テスト（`title` キー不在での結合同期・`title` 明示時の優先）を `css_updater_test` に追加。
- [Low] **版面単位変換の潜在バグ 7 件（B1〜B7）を解消**: 単位変換の一元化（上記 `Units` 導入）に伴い、調査で特定した既知バグを修正した。**B1**（変換順序）＝ `base_font_size: 30Q` と倍率行送り `base_line_height: 1.7` を併用すると、行送り解決が変換前の値を参照して倍率が生のまま素通しされ行グリッドが絶対値にならなかったのを、文字サイズを先に pt 化してからその結果を基準に解決する順序へ修正（回帰テスト固定）。**B2**（不正 CSS）＝ `base_font_size: 10.5`（素の数値）が `pt` 付与されず `--base-font-size: 10.5` という不正 CSS として黙って無視されていたのを、`pt` 付与して有効化。**B3**＝ `typography.column.font_size` が読み込み後注入のため Q 変換を通らなかったのを、注入時に `Units.font_size_to_pt` を通すよう配線。**B4**（未消費キー）＝ `folio_font_size` は Q 変換対象なのに消費者が無かった（`--folio-font-size` は `calc()` 派生値）のを、CSS 変数 `--folio-font-size` へ配線（指定時のみ固定値で上書き、未指定は従来の `calc()` 既定を維持）。**B5**＝ mm パーサが未知単位を黙って `to_f`（`"0em"`→0.0mm）していたのを、解釈不能なら nil を返し呼び出し側の既定値フォールバックが働くよう変更（margin で `Q`/`cm`/`in` も解釈可能に）。**B6**（近似係数）＝ Q→pt 係数 `0.709` を厳密値（`0.25 × 72 ÷ 25.4 = 0.70866…`）へ精密化。**B7**＝ `PAGE_SIZES` に `JIS-B5` キーが無く `size: JIS-B5` がフォールバック先の `B5`（偶然 JIS 寸法）に一致して動いていたのを明示登録（解決結果は同一）。同梱プリセットに Q・素の数値は無いため、既定利用者のビルド出力に差分は生じない（B1/B2/B3 は Q やカスタム値を使う著者向けの改善）。
- [Low] **21 章のコードフェンス不整合を修正（hardLineBreaks 解説の例示が壊れていた）**: `21-markdown-tutorial.md` の「個別無効化」節で、Markdown 記法例のフェンスが閉じられておらず、解説文「あるいは、book.yml で〜」と `### 技術的な説明` の実演例がコード例に飲み込まれる／逆に例示の一部が本文化する崩れが（別の箇所の不整合と相殺して）潜在していた。記法例（フロントマター＋実演本文）と book.yml 設定例を正しいフェンス構造に再構成した。`vs preflight` の CodeFenceCheck が今回の顕在化を検出しており、修正後は全フェンスが整合（偶数）に戻った。
- [Medium] **`metrics.kanji_ratio` / `metrics.word_length` の設定値が無視され評価帯がハードコードされていた不具合を解消（設定を再配線）**: `vs metrics` の語彙難度は、漢字比率の評価帯が `formatter.rb#kanji_evaluation` に `..20/20..25/25..35/35..45` とハードコードされ、平均語長は数値を表示するのみで、`book.yml` の `metrics.kanji_ratio`/`metrics.word_length` をカスタムしても黙って無視されていた（`ConfigLoader#vocabulary_thresholds` が定義のみで呼び出し 0 件・「理想的な範囲 25〜35%」もリテラル埋め込み。読解難度を建石式へ刷新した際に配線が外れた副作用）。`Formatter` が `vocabulary_thresholds` を受け取り、汎用の `difficulty_evaluation(value, threshold)`（min/ideal/max で 5 段階＝平易／やや平易／適切／やや難解／難解）で漢字比率・平均語長の双方を評価するようにし、理想範囲の表示も設定値へ追従させた（既定値は従来と同一のため既定利用者の出力は不変。著者が対象読者に合わせて基準を調整できるようになった）。回帰テスト（既定帯の据え置き・カスタム閾値への追従）を `formatter_test` に追加。あわせて、同様に死蔵していた **`metrics.labels.monotonous` / `metrics.labels.too_complex`** も配線：語彙多様度が単調バンド（MATTR<0.5）のとき `mattr_evaluation` が `labels.monotonous` を、読解難度が難解側（Professional）のとき `readability_description` が `labels.too_complex` を用いるようにし、著者が文言を変えられるようにした（この 2 バンドの既定表示文言は `単調`→`表現が単調`／`専門家・技術者向け`→`やや難解` に変わる。従来文言に戻したい場合は `book.yml` の当該ラベルに設定すればよい）。`labels.too_short`/`too_long` は従来どおり分量警告で使用。「章ごとに『表現が単調』『やや難解』の警告を出す」構想は [PLANNED.md](docs/specs/PLANNED.md) に将来計画として記載。
- [Medium] **存在しない frontispiece/ornament 画像名・無効な `theme.color` が警告なしに（または一方は突然の異常終了で）扱われる不具合を解消（`ThemeValidator` を新設し `vs build`/`vs preflight` で警告）**: (1) `theme.frontispiece`/`theme.ornament` に実在しない画像名（例: `fuji`）を指定しても、`ThemeImageResolver` は警告を一切出さず SVG プレースホルダーで静かにビルドを続行していた（スペルミスに気付けない）。(2) 逆に `theme.color` に一覧外の色名（例: `pink`）を指定すると `parse_theme_color` が `log_error` + `exit 1` で**突然ビルドを中断**していた（同じ theme 設定なのに挙動が不一致・不親切）。両者を、Step 2（`prepare_theme_images!`）で一度だけ走る新モジュール `PreProcessCommands::ThemeValidator` に集約。無効な色は 🟡 警告のうえ**既定色（yellow）でビルド続行**へ変更（`parse_theme_color` の `exit 1` を廃止しフォールバック化。章ごとに呼ばれるため警告は Validator 側のみで一度だけ）。存在しない画像も同じ考え方で 🟡 警告のうえ**既定画像（`sakura`）へフォールバック**して続行するようにし（`resolve_theme_image_path` に `fallback_slug:` を追加。フォールバック先すら無い場合のみ従来どおり画像名入り SVG プレースホルダー）、色・画像とも配置先・有効値・バンドル名を添えた著者向けの親切な文面にした。あわせて **frontispiece/ornament の未指定時の既定画像も `sakura` に統一**（従来は扉絵=`door2.webp`／飾り画像=`frame-yellow.webp` だったが、`frame-yellow.webp` は既に削除済みで飾り画像の既定が実在しないファイルを指す不具合になっていた。`FRONTISPIECE_DEFAULT_PATH`/`ORNAMENT_DEFAULT_PATH` を刷新し、未指定・無効いずれも `sakura` のバリアント生成に寄せる。`css_updater` の保険分岐が参照していた `frame-yellow.webp` も解消）。画像の存在判定は `ThemeImageResolver.theme_image_available?`（base 画像があればバリアント生成元として OK、`url()`/`http(s)`・未指定は対象外）を新設。`theme.style: simple` では色のみ検証（画像は不使用のためスキップ）。preflight は Step 1〜4 を実行するためこの警告も自動的に拾う。回帰テスト（`theme_validator_test` 9 件・`theme_image_resolver_ratio_test` 5 件・missing→sakura フォールバック・`parse_theme_color` フォールバック・`prepare_theme_images!` 統合ほか）を追加、マニュアル（`42-frontispiece.md`）の「画像が見つからない場合」「色」節も実挙動に更新。
- [Low] **テーマ画像プレースホルダー生成時に `CGI` 未定義で画像名が欠落しうる不具合を解消（`require` 順序）**: `theme_image_resolver.rb` の `svg_placeholder_uri` が `CGI.escapeHTML` を使う一方、`require 'cgi'` は後段の `svg_to_data_uri` 内にあったため、`cgi` が他経由で未ロードのコンテキストでは `uninitialized constant CGI` で rescue に落ち、画像名の入らない空 SVG プレースホルダーへフォールバックしていた（本体では他ファイルが先に `cgi` を読むため顕在化しにくいが、暗黙のロード順に依存した脆い状態）。`require 'cgi'`/`require 'uri'` をファイル先頭へ移動し、メソッド内の遅延 require を除去。回帰テスト（`frontmatter_generator_test`：プレースホルダーに画像名がエンコードされること）を追加。
- [Medium] **`vs index:auto` がコードブロック内の `[...]` を索引語として誤検出する不具合を解消（フェンス除去を状態機械方式に統一）**: 手動マークアップ抽出（`UnifiedIndexManager#extract_manual_markup_terms`）と候補抽出（`IndexCandidateExtractor#sanitize_content_for_extraction`）がコードフェンス除去に素朴な `/```[\s\S]*?```/` を使っていたため、地の文中のインライン ```` ``` ````（例:「` ``` ` で囲んだ部分」）が余分なフェンスと誤認され、フェンス対が 1 つずつズレて以降のコードブロックが地の文化。結果、`32-metrics.md` のバーグラフ `[###]`／`[##########]`、YAML/JSON 例の `[00, 90-98, 99]`／`[1000, 2000]`／`[...]` などが `_index_glossary_review.md` に「[手動登録]」として大量に誤登録されていた。実タグ付けを行う `IndexMatchScanner` と同じ**行頭フェンスだけを数える状態機械方式**（可変長 ```` ``` ````/```` ```` ````/`~~~`・入れ子・`` ```include: `` 除外に対応）を共有ユーティリティ `IndexCommands::CodeBlockStripper` に切り出し、両抽出経路をこれに統一（インラインコード `...` も除去）。`32-metrics.md` で誤検出 13→0、正規の `[語|読み]` タグは保持されることを実測。回帰テスト（`code_block_stripper_test` 5 件＋インライン ``` を含む統合テスト 1 件）を追加。
- [Low] **`61-developer.md` のコードフェンス閉じ忘れを修正（同一バッククォート数の入れ子）**: Markdown のコード例の中に CSS フェンスを 3 連バッククォートのまま入れ子にしており（外 ```` ```markdown ````／内 ```` ```css ````）、フェンスが閉じきらず以降の校正・体裁がずれていた（フェンス区切り行が 73 個＝奇数）。外側を 4 連バッククォートにして整合（74 個）。あわせて環境ダンプ表のハッシュ断片やツール名（`waifu2x-ncnn-vulkan` 等）もコード表記化。本不具合は新設の `vs preflight` CodeFenceCheck で今後は検出される。
- [High] **インストール済み gem の `vs lint` で技術用語（Kotlin/AWS/Azure 等）が軒並みスペル誤検知される不具合を解消（辞書がパッケージされず未ロード）**: `DictManager::BUNDLED_DIR` がリポジトリ直下 `config/spellcheck_dictionaries` を指していたが、gemspec の `files` は `{bin,lib}/**/*` のみで**直下 `config/` を gem に同梱しない**ため、インストール済み gem では辞書ディレクトリが存在せず bundled 辞書が 0 件になり、`Kotlin`/`AWS`/`Azure`/`JavaScript`/`Markdown` 等が辞書未登録として誤検知されていた（ローカル `-Ilib` 実行ではリポジトリ直下 config/ が在るため再現せず食い違っていた）。辞書の探索先を「**プロジェクト直下 `config/spellcheck_dictionaries`（CWD 相対・`vs new` が配置しユーザーが編集可）を優先 → 無ければ gem 同梱の `lib/project_scaffold/config/spellcheck_dictionaries` へフォールバック**」へ変更（`.textlintrc.yml` の参照方法と一貫。`CACHE_DIR` も CWD 相対化）。あわせて、この回帰を取りこぼしていた lint テスト 3 件（`test_*.rb` 接頭辞のため rake の `*_test.rb` パターンに一致せず未実行だった）を `*_test.rb` へ改名して実行対象に組み込み、辞書フォールバックの回帰テストを追加（`dict_manager_test`）。
- [Low] **`.book-card` 内のタイトル・著者・説明の行頭が不揃いになる不具合を解消**: グローバルの `p { text-indent: 1em }` が book-card 内の段落にも効き、タイトル・著者・説明の各 1 行目だけ 1em 字下げされ（`<br>` 後の行は字下げ 0）行頭が揃わず不格好だった。`.book-info p { text-indent: 0 }` を追加して book-card 内の段落字下げを打ち消し、左端へ揃えた（`components.css` root/scaffold）。
- [Low] **`.book-card`（書籍カード）内で複数行の説明が 1 行に連結される不具合を解消（hardLineBreaks 不整合）**: book-card の本文（著者・説明など）を改行して書いても、`![](cover)` とタイトル `**…**` 以外の連続行が Kramdown のソフト改行のまま `<p>著者 著\n説明</p>` となり、HTML 上で空白に潰れて 1 行（`著者 著 説明`）で表示されていた。本書全体の `hardLineBreaks: true`（改行＝`<br>`）が book-card 内だけ効いていなかった。`normalize_book_card_md` で説明部の連続行に Markdown のハード改行（末尾 2 スペース）を補い、`<br>` として描画されるよう修正（`render_markdown_to_html` は deflist 等と共有のため変更せず、book-card 側で対処）。これにより `_book.md` / `_physics_book.md` 等で `= author.name 著` と `= desc` を別行に書けば別行で表示される。QueryStream（query-stream gem）は展開後マークダウンを正しく別行で出力しており、原因は vivlio-starter の book-card 変換側だった。回帰テストを `markdown_transformer_test` に追加。
- [Medium] **`:::{.output}` 等のコンテナ内でクロスリファレンスのキャプション（`**見出し @id**`）が素の強調表示になる不具合を解消（コンテナ開始/終了に空行を補完）**: `:::{.output}` の直後に `**…@id**` を空行なしで書くと、VFM が `hardLineBreaks` で開始行 `:::{.output}` を直後のキャプション行と 1 つの `<p>` に結合し、その後 post_replace が `:::{.class}` を `<div>` へ置換する際に `<p>` が分割されて、キャプションの `<strong>` がコンテナ直下に取り残された。結果 `wrap_cross_ref_code_blocks!` がキャプションを `div.cross-ref-list` へ包めず、見出しが「リスト n-m: …」の体裁にならず**素の太字**で表示されていた（同じ見出しが箇所により変換されたりされなかったりする症状）。前処理に `MarkdownTransformer.normalize_container_fence_spacing` を追加し、`:::{.class}` 開始直後・`:::` 終了直前に空行を補って各内側ブロックを独立段落にすることで解消（コードフェンス内の `:::` は対象外、既存の空行は二重化しない）。これにより全コンテナ記法で開始/終了マーカーが本文と混ざらず、stray `<br>` も解消。実パイプライン（vfm CLI → HtmlReplacer → wrap）で `.output` 内の全キャプションが `p.code-caption > strong` に正しく収まり、素の `<strong>` が 0 件になることを実測。sideimage/img-text/pictures/note の構造は不変（むしろ整理）であることも確認。回帰テスト 3 件を `markdown_transformer_test` に追加。
- [Medium] **コード保護プレースホルダ `__VS_CODE_SPAN__n__` が本文へ漏れ出す不具合を解消（`restore_code_spans` の復元順を LIFO 化）**: フェンス／インラインコードを一時退避する `MarkdownUtils.extract_code_spans` は「フェンス→インライン」の順に**同一ハッシュ・共有カウンタ**で退避するため、行を跨ぐバッククォート対が**フェンス置換後のプレースホルダを巻き込む**と、後から退避したインラインの original が先のフェンスのプレースホルダ（`__VS_CODE_SPAN__n__`）を内包する**真の入れ子**になる。一方 `restore_code_spans` が**挿入順（FIFO）**で復元していたため、内側プレースホルダを先に復元しようとして空振りし、後で外側を開いた瞬間に未復元のプレースホルダ文字列が本文へ表面化して残留していた（`24-cross-reference.md` の「章間参照」直後で `__VS_CODE_SPAN__15__` / `16` が露出。コード扱いの範囲も崩れて見えた）。復元を**挿入の逆順（LIFO / `reverse_each`）**へ変更し、外側→内側の順に巻き戻すよう修正（`markdown_utils.rb`）。これは本体が共有する全 pre_process 経路（`image_path_normalizer` / `markdown_transformer` ×2 / `markdown_preprocessor` ×4）に一括で効く。CHANGELOG 既出の `IndexMatchScanner`（保護トークンの LIFO 復元）と同種の事象。あわせて pre_process / post_process の退避・復元を横断点検し、`html_replacer`（pre→code→tag を逆順復元）・`index_match_scanner`（`reverse_each` 済み）・`strip_html_comments!`（別 NUL トークンで入れ子なし）はいずれも安全と確認。回帰テスト 2 件（入れ子プレースホルダの LIFO 復元・章規模の往復一致）を `markdown_transformer_test` に追加。実章 `24-cross-reference.md` の前処理で漏れ 0・往復 identity 一致を実測。
- [Medium] **コードインクルードで存在しない行範囲を指定するとビルドが落ちる不具合を解消（末尾クランプ／全文フォールバック）**: `` ```include:prime.rb:22-25` `` のようにファイル行数を超える範囲を指定すると、`lines[(start-1)..(end-1)]` が `nil` を返し `nil.join` で `undefined method 'join' for nil` となりビルドが異常終了していた。範囲を検証する `extract_line_range`（1 始まり）を新設し、`process_code_include` を次のように修正（ビルドは継続）: (1) **開始行は有効で終了行だけがファイル末尾を超える**場合は、ファイル末尾までに**クランプ**して取り込む（🟡「終了行がファイル末尾を超えています…N-末尾行を取り込みます」）。(2) **開始行自体がファイル末尾を超える／逆順**など救済不能な指定は、🟡「範囲指定が不正です…全文を取り込みます」を出して**ファイル全文の取り込みへフォールバック**。回帰テスト 4 件（終了超過→末尾クランプ／開始超過→全文／逆順→全文／正常→該当行）を `markdown_transformer_test` に追加。あわせて、警告メッセージの行番号が**同一パスを複数回 include した際に常に最初の出現行を指す不具合**も解消（`build_source_include_line_map` がパスキーで `||=` 衝突していた。`build_line_number_map` と同じ**フルマッチ文字列キーの配列**にして `occurrence` インデックスで一致させ、その出現の原稿ファイル行を報告）。行番号報告の回帰テストを追加。
- [Medium] **同一の `include:` 記法が複数箇所にあると 2 つ目以降が展開されない不具合を解消（行番号の取り違え）**: 記法説明用フェンス（````markdown 等）内の例文と、`:::{.output}` などに置いた**本物の `include:` が同一文字列**のとき、本物が展開されず ```` ```include:foo.rb``` ```` のまま残っていた（結果、シンタックスハイライト・行番号が付かず、直後のキャプション `**… @id**` もコードブロックと認識されずクロスリファレンスが「リスト n-m」へ解決しなかった）。原因は `build_line_number_map` が `map[match] ||= 行番号` で**同一 include 文字列の最初の行番号しか保持せず**、本物の include まで「フェンス内の例文（スキップ対象）」の行番号で誤判定していたこと。行番号を**出現順の配列**で保持し、`gsub` で出現ごとに対応する行番号を消費するよう修正（`process_code_include` / `build_line_number_map`）。これにより `:::{.output}` 内の `include:` も正しく展開・ハイライトされ、`@id` 参照も解決する。回帰テスト（フェンス内の例文はスキップ／同一文字列の本物は展開）を `markdown_transformer_test` に追加。あわせて `24-cross-reference.md` の例側ラベルを本物・参照と揃え（`@prime2-range`→`@prime-range`）。
- [Low] **単独行の `{.aki}` / `{.aki2}` が変換されず `{.aki}` と直接出力される不具合を解消**: `{.aki}` は本来「段落末に付けて段落へ class を与える」インライン記法のため、空行を作る用途（`<br>` のように 1 行空ける）で `{.aki}` だけを 1 行に書くと、付与先の本文が無く VFM が `{.aki}` をそのまま文字として出力していた（さらに `hardLineBreaks` で直後の本文行と連結され、段落末クラス化ルール `<p>…{.aki}</p>` にもマッチしなかった）。前処理に `MarkdownTransformer.convert_standalone_spacing` を追加し、**行内容が `{.aki}` / `{.aki2}` だけの単独行**（直前が空行＝独立段落のもの）を縦余白マクロ `@vspace:1lh` / `@vspace:2lh` へ置換、独立段落になるよう直後に空行を補う（`.aki`＝1lh / `.aki2`＝2lh に対応）。段落末に付いた `{.aki}`・直前が本文（trailing 添付）・コードフェンス内は対象外で従来挙動を維持。回帰テスト 6 件を `markdown_transformer_test` に追加。
- [Medium] **著者名未入力（`book.author` が空）で EPUB / Kindle 生成が失敗する不具合を解消**: `vs new` で著者名を空のまま作成すると、`vs build` の EPUB / Kindle ビルドが `npx vivliostyle build` の即時失敗（`Validation of vivliostyle config failed. / At least one character is required` … `author: ''`）で 🔴 になっていた（PDF は scaffold 同梱の静的 `vivliostyle.config.js` がプレースホルダ author を持つため成功し、EPUB だけが `book.yml` の空 author を動的 config へ埋め込んでいた）。vivliostyle 11 の config スキーマが `author` / `language` に 1 文字以上を要求するのが原因。`EpubBuilder#generate_epub_config!` のフォールバック `book_config&.author || '著者名'` が **nil しか拾わず空文字を素通り**させていたため、空文字も `'著者名'`／`'ja'` へ寄せるよう修正（`epub_builder.rb`）。回帰テスト（空 author → プレースホルダ／設定済み author は保持）を `epub_flavor_test` に追加。なお `vs new` で著者名を入力していれば従来どおり問題なく生成される。
- [Medium] **キャプション付きコードブロックでコード本体が消える不具合を解消（`** タイトル @id **` ＋ ```code```）**: `** サンプルコード @sample-code **` のキャプションを付けたコードブロックが、ビルド結果でキャプション（「リスト 1-1: …」）だけ残りコード本体が出力されない不具合があった。原因は `CrossReferenceProcessor` の `list_markdown` がキャプションと `<!--xref:ID-->` マーカーのみを出力し、`transform_block` がコードブロック行を読み飛ばしていたこと。`post_process` の `wrap_cross_ref_code_blocks!` は `<!--xref-->` 直後の `<pre>` を探してキャプションと一緒に `div.cross-ref-list` へ包む設計だが、その `<pre>` の素になるコードフェンスがそもそも出力されていなかった（図・表のキャプションは別経路で正常）。`list_markdown` がキャプション → マーカー → **コードフェンス本体**の順に出力するよう修正。回帰テスト（キャプション付きコードがコード本体ごと変換される）を `markdown_transformer_test` に追加。
- [Medium] **コメント強調マーカー `[!]` が索引語化されビルドが崩れる不具合を解消（索引スキャナのコード保護漏れ）**: `[!]` コメント強調記法を解説する章（`22-extentions.md`）で、インラインコード `` `[!]` `` や 4 連バッククォート ````` ```` ` のコード例内の `[!]` が、明示索引マーカー `[用語]` と誤認されて `<dfn>` / `<span class="index-term">` へ置換され、見出し・本文・表・コード例が崩れて生 HTML タグが露出していた（`!` ＝ `idx-0ab8318acaf6`、コード例フェンスも巻き込まれて地の文化）。原因は `IndexMatchScanner` の 2 点: (1) フェンス検出が ``` のトグルのみで、`````（4連）の中の ```（3連）の入れ子で `in_code_block` が反転し、コード例の中身を地の文として索引スキャンしていた。(2) 明示マーカー処理（`process_line` の第1段）がインラインコード `` `...` `` を保護しておらず（自動索引の第2/3段は保護済み）、`` `[!]` `` を索引語化していた。フェンス検出を**可変長**（開始フェンス長以上の行でのみ閉じる）に修正し、第1段でもインラインコードを保護トークン化してから `[用語]` を処理するよう変更。裸の `[!]` / `[&&]` / `[<h1>]` 等を意図的に索引する既存挙動は維持。回帰テスト 2 件（インラインコード内・4連フェンス内の `[!]` 非索引化）を `index_match_scanner_test` に追加し、実章 `22-extentions.md` のスキャンで `!` マッチが 0 件になることを確認。
- [High] **入稿用本文 PDF の本文欠落（約4ページ degenerate）を握り潰さない本文ガードを導入**: `targets` に `print_pdf` を含むビルドで、入稿用 PDF が稀に本文欠落（titlepage+legalpage+colophon の約4ページ）になる flaky があった。原因は**本文レンダリング失敗の握り潰し**。入稿用本文はトンボ・塗り足し付き（`--crop-marks --bleed`）の**最重量レンダリング**で、Chrome の一過性失敗（複合ビルドでは pdf 本文・前付・dedup・結合・アウトラインの後に走るためリソース圧のピークで踏みやすい）で空振りしても、`PdfCommandRunner#handle_build_result` は `log_error` するだけで raise せず、`print_pdf_merge!` は存在するファイル（front+colophon）だけで結合して「成功」していた。`pdf` 本文はトンボ無しで頑健なため同じ握り潰し構造でも顕在化せず、`print_pdf` 側でだけ表面化していた（非対称の正体）。**解消**: `PdfCommandRunner#call` が「出力ファイル生成までの真の成否」を返すようにし、`Build::Utilities.build_pdf_with_body_guard!`（本文相応のページ数を検証→失敗/degenerate ならリトライ→規定回数で回復しなければ `exit 1` で明示中断）を新設して、入稿用本文（`print_pdf_build_sections!`）・閲覧用本文（`compile_overall_pdf!`）の双方を guard 経由に変更。本文欠落判定の下限は、閲覧用 `_sections.pdf`（Step 7 で生成済みの既知良）があればその半分、無ければ本文エントリ数の半分とし、degenerate（約4ページ）は確実に下回り正常ビルドは余裕で上回る自己校正型にした（固定閾値の脆さを回避）。これにより一過性フレークはリトライが吸収し、恒常失敗時は**黙って本文欠落 PDF を出荷せず**ビルドが明示的に失敗する。ユニットテスト `utilities_body_guard_test`（1発成功でリトライ無し／初回 degenerate からの回復／ビルド失敗報告でのリトライ／回復不能時の `exit 1`）を新設。`pdf` を2回ビルドして本文テキストが完全一致することを実測し、レンダリングが run-to-run で決定的であることも確認済み。
- [Medium] **`rake test:targets` のビルド間サイズ乖離フレーク（②系）を combo 隔離で解消**: `test_pdf_consistent_across_single_and_combined` が単体 `pdf` と複合ビルドの閲覧用 PDF で稀に失敗していた件を実測で切り分け。本文テキスト・ページ送りは**常に完全一致**（vivliostyle は決定的）で、失敗していたのは `assert_pdf_equal` の**サイズ乖離 ≤ 2%** 判定だった。真因は**テストの状態汚染**: `target_consistency_test` は kindle を含む combo を中間 `…-kindle.epub` 保全のため `--no-clean` で走らせるが、これは**ビルド側の初期 clean（Step 0）までスキップ**するため、直前 combo が残した画像派生物（特に `images/headings/` の kindle 版）を引き継ぎ、後続 full ビルドの閲覧用 PDF が +44 画像・約 +2.2% に膨らんで 2% 閾値を超えていた（製品の単体ビルドは無影響＝決定的で正しい。テスト専用の汚染）。**解消**: `build_one!` に `reset_intermediate_state!`（combo ごとに `vs clean` 相当を必ず通す）を追加し、`--no-clean` でも**開始時は常にクリーンな中間状態**から走らせて combo を隔離（`--no-clean` は最終 `…-kindle.epub` 保全のためだけに効かせる）。実測で「kindle 汚染→`vs clean`→full」のサイズ乖離が 2.23% → 0.0%（テキストも完全一致）に戻ることを確認。製品コードは不変・テストのみの是正で、テストの厳格性は緩めない。
- [High] **`print_pdf` 単独ビルドのしおりが目次へ集中する不具合を解消（アウトラインの `_toc.pdf`/`00-preface.pdf` 依存を撤去）**: `targets: print_pdf` 単独でビルドすると、PDF アウトライン（しおり）の各見出しをクリックしても該当章ではなく**目次ページ**へ飛んでいた（`targets: pdf` を含む結合ビルドは正常）。原因は `OutlineExtractor.calculate_chapter_ranges` が章のページ範囲計算に補助 PDF `_toc.pdf` / `00-preface.pdf` の**ページ数**を使っていたこと。これらは閲覧用パイプラインの副産物で、print_pdf 単独では Step 6 が `generate_toc_html!`（HTML のみ）になり生成されない。結果 `toc_pages=0` でフォールバック（`if … && toc_pages.positive?`）も不発となり、本文章の検索範囲が目次へ食い込み、目次の章タイトル一覧へ各しおりが吸い寄せられていた。本来 `pdf` と `print_pdf` の差は**カバー・トンボの有無だけ**で、補助 PDF への暗黙依存自体が設計上の綻びだった。**解消**: 前付・目次のページ数を、注釈対象の結合 PDF（`output.pdf`/`output_print.pdf`）から「ページ先頭が目次見出し／章見出し」のテキスト検出（`detect_front_matter_spans`）で直接算出する方式へ変更し、`_toc.pdf`/`00-preface.pdf` 依存を撤去。章扉ではページ先頭に「第N章」だけが出てフルタイトルは柱として後続ページに現れるため、マーカー一致ページの**最小値**を採って実際の章開始ページを選ぶ。あわせて閲覧用 Step 6 を `generate_toc_html!` に統一して `_toc.pdf` 生成を廃止（`generate_toc_and_pdf!` 削除）、`toc_heading_title` を `_toc.html` 基準化、`00-preface.pdf` の残骸参照を整理。前書きを書かない書籍（`00-preface` 不在）でも破綻しない。これにより `pdf`/`print_pdf` のアウトライン処理が同一ロジックに統一された。検証: 実ビルドで print_pdf 単独・結合・閲覧用の 3 系統とも各しおりが実章ページを指すこと（目次集中の解消／閲覧用は無回帰）を確認。ユニットテスト `outline_extractor_test`（前書き有/無・目次未検出・章マーカー最小選択）を新設。なお `pdf`/`print_pdf` の**パイプライン全体**の共通化は第2段（別タスク）として仕様化予定。
- [High] **保護トークン `[[…_TOKEN_n]]` の本文露出を解消（html_token 問題）**: インラインコード内に HTML タグ様の文字列がある行（例: `` `vs build <章名>` ``）で、`[[HTML_TOKEN_0]]` 等の中間トークンが PDF/print_pdf/EPUB/Kindle の全出力にそのまま露出していた。原因は `IndexMatchScanner`（`apply_auto_indexing` / `apply_glossary_only_linking`）の保護トークン**復元順序**。保護は IDX→HTML→RUBY→CODE の順に走り、コード内の `<章名>` が先に HTML トークン化され、その文字列ごと CODE トークンに内包される（入れ子）。復元を**挿入順（FIFO）**で行うと、まだ CODE トークンに隠れている HTML トークンを先に展開しようとして空振りし、後で CODE トークンを開いた瞬間に未展開の HTML トークンが表面化して残留していた。スキャナはこの残留を章 `.md`（＝ビルド入力）へ書き戻すため全出力へ波及（KNOWN_ISSUES の「中間ファイル誤参照」という推測は症状で、真因は復元順序）。復元を**挿入の逆順（LIFO・`reverse_each`）**へ変更し、外側（CODE）→内側（HTML）と入れ子を正しく巻き戻すよう修正（2 メソッド）。回帰テストを `index_match_scanner_test`（auto-index・glossary-only の両経路）に追加。実マニュアルの全 4 ターゲット（pdf/print_pdf/epub/kindle）＋中間生成物で `[[…_TOKEN_n]]` ＝ 0 を確認。
> 2026-06-23: 本 `### Fixed` 一式を反映後、`rake test:release`（test → standard → layout → targets → manual → package）を実行し **全 6 段グリーン**を確認（各段 0 failures / 0 errors / 0 skips、exit 0）。RC 品質保証として、FT-01 Type 3 ＝ 0・FT-02 全フォント埋め込み・索引/用語集 RSC-012 ＝ epubcheck ERROR 0・冪等性 6 ビルド全一致を**実ビルドで確定**（修正完了）。
- [High] **隠しノンブルを埋め込み可能フォントで描画（FT-02・非埋め込み Helvetica を解消）**: 入稿用 PDF の隠しノンブル（通しページ番号）が PDF 標準 14 フォントの `Helvetica`（非埋め込み）で描画されており、印刷所入稿で「非埋め込みフォント」事故になっていた。`StandardProvider#create_nombre_pdf`（Prawn・MIT 経路）を、同梱の `stylesheets/fonts/hackgen35/HackGen35ConsoleNF-Regular.ttf` を使うよう変更（Prawn が数字グリフのみをサブセット埋め込み＝極小）。フォント未配置時は従来どおり `Helvetica` にフォールバック。拡張プラグイン（`vivlio-starter-pdf` / `EnhancedProvider`・HexaPDF 経路）も同様に修正（1.1.1。`document.config['font.map']` へ登録してサブセット埋め込み）。`nombre_stamper_test` に FT-02 回帰テストを追加（StandardProvider を直接検証）。
- [High] **EPUB を Step 8 backlink dedup から隔離（⑦・単体／結合の不整合を解消）**: `targets` に PDF と EPUB/Kindle を同時指定すると、Step 8（backlink dedup）が共有の章 HTML を「PDF ページ依存」で破壊的に書き換える（同一 PDF ページ内の 2 回目以降の † / `index-term` を削除）ため、その後にビルドする EPUB が dedup 済み HTML を再利用し、† と索引リンクが間引かれていた（実測: 索引リンク 単体 99 → 結合 73）。リフロー型 EPUB にページ概念は無く本来「全 † / 全出現リンク」を持つべき不整合（`TargetConsistencyTest#test_epub_consistent_across_single_and_combined` が † を除いてしか一致しなかった原因）。`UnifiedBuildPipeline` に **Step 7b（pre-dedup snapshot）** を追加し、`epub_or_kindle_target?` のとき Step 8 直前の章 HTML（`_glossarypage.html` / 本文 / `_indexpage.html` を含む `collect_epub_htmls`）を `@pre_dedup_snapshot` に退避。`run_step_epub` 冒頭で復元してから EPUB を生成することで、PDF（閲覧用・入稿用は dedup 済みで生成済み）と EPUB（dedup 前＝全出現）を両立させた。既存の epub→kindle 相互非汚染スナップショットは、この復元後に取り直すため Kindle も dedup 前から始まる。`single` モードは Step 8 非実行のため対象外。テストは † を除かず本文完全一致＋† 数一致を検査するよう強化（`strip_daggers` 撤去）。仕様 `docs/specs/epub-backlink-dedup-isolation-spec.md`。
- [Medium] **索引・用語集の epubcheck RSC-012 を恒常的に解消（未定義フラグメントのリンク解除）**: 索引 `_indexpage.xhtml` のページ番号リンク（`#idx-…`）や用語集バックリンク（`#gls-src-…`）が当該 EPUB に実在しないフラグメント id を指すと、epubcheck が RSC-012「フラグメント識別子が定義されていません」ERROR を多数出していた。`docs/specs/epub-kindle-target-split-spec.md` 付録 A-2 が恒常対策（実在 id 集合との照合とリンク解除）を規定していたが、用語集 RSC-005 のみ実装され**索引側が未実装**だった。`Build::EpubBuilder.post_process_index_glossary_for_epub!` に、EPUB 同梱の全 HTML から実在 id 集合を集める `collect_existing_fragment_ids` と、参照先 id が集合に無いリンクを内側テキスト（索引・用語集リンクは中身が空＝消滅）へフォールバックする `unlink_missing_fragment_links` を追加し、`rewrite_index_for_epub!`／`rewrite_glossary_for_epub!` の双方で連番挿入・併合の**前**に死リンクを解除する。これによりサブセット／全章いずれのビルドでも RSC-012 を出さない。索引・用語集後処理はクリーン EPUB・Kindle 中間 EPUB の**共通フェーズ**で実行されるため両フレーバに等しく適用され、PDF は共有 HTML を直接使うため無影響（EPUB 専用後処理）。**重要（実ビルドで判明した真因）**: 実在 id 集合は当初 `/\bid="…"/` の正規表現で収集していたが、これだとマニュアルがコード例として本文に載せたエスケープ済みテキスト `&lt;span id="idx-…"&gt;` の `id="…"` まで「実在」と誤カウントし、実 DOM に要素が無い id を温存して RSC-012 が 1 件だけ残った（`vivlio_starter_v1.0.0.epub/EPUB/_indexpage.xhtml` の `#idx-0ab8318acaf6-9`）。epubcheck と同じく**実 DOM の要素 id だけ**を数えるよう `collect_existing_fragment_ids` を Nokogiri パース（`doc.xpath('//*[@id]')`）へ変更して恒常解消。`targets: epub` 実ビルド＋epubcheck（`epub_validation_test` EP-02）で ERROR 0 を確認。回帰テスト `test/vivlio_starter/cli/build/epub_index_rsc012_test.rb`（エスケープ済みコード内 id の偽陽性ケースを含む）を新設。`docs/specs/KNOWN_ISSUES.md` の該当項目をクローズ。
- [Low] **冪等性（`IdempotencyTest`）と dedup の関連を実測検証し仮説を撤回**: 「Step 8 dedup の PDF ページ依存が冪等性フレーキーの真因では」という仮説を dedup ON/OFF の対照実験で検証した結果、**否定**。`vs build`（毎回 clean 込み）連続実行で `targets: pdf`（dedup ON=376p / OFF=378p）・`targets: pdf, print_pdf`（viewing 376p + print 374p）のいずれも 6 ビルド全一致＝非決定性ゼロ。dedup は決定的で、以前の単一ページ差は索引アンカー ID の `String#hash`→SHA1 決定化で既に解消済みだった（詳細 `docs/specs/epub-backlink-dedup-isolation-spec.md` §2.5）。
- [High] **Type 3 フォント再発の主因を是正（波ダッシュ正規化の向き反転・† を明朝で描画）**: vivliostyle 11.0.2（Chrome 149）で 25 ページに Type 3 が再発した件の調査と修正（詳細 `docs/specs/type3-regression-investigation.md`）。(1) **波ダッシュ**: `Techbook::Processor#process` の正規化が `U+301C(波ダッシュ)→U+FF5E(全角チルダ)` と**逆方向**だった。同梱 Zen フォントは U+301C を収録し U+FF5E を**非収録**のため、この変換が OS フォント（ヒラギノ）へのフォールバック＝Type 3 を自ら誘発していた。向きを `U+FF5E→U+301C` に反転（入力されやすい全角チルダを Zen 収録の波ダッシュへ正規化）。Type 3 実測 28 グリフ中 22 を占める主因。(2) **ダガー †**: ZenKakuGothicNew（ゴシック）に † が無く、見出し等のゴシック文脈の用語集記号 † がフォールバックして Type 3 化していた。`.glossary-link sup` に `font-family: var(--font-main-text)`（Zen Old Mincho・† 収録）を明示し常に明朝で描画（`chapter.css` / `glossary.css`）。なお 10.5 系で出なかったのは旧 Chromium がフォールバック書体を CID TrueType で埋め込んでいたため（Chrome 149 で Type 3 埋め込みへ挙動変化）。(3) **Zen 非収録記号（▶ U+25B6・⁵ U+2075 等）**: 記号被覆の広い同梱 `HackGen35ConsoleNF`（Nerd Fonts 版）を本文・見出し等のフォントスタック末尾フォールバックに採用（`page-settings.css` の `hackgen35` @font-face を ConsoleNF へ差し替え、`CssUpdater#format_font_value` が `--font-main-text`/`--font-header`/`--font-column`/`--font-folio` の generic 前に `"hackgen35"` を挿入）。これにより Zen 非収録字も OS でなく同梱フォント（CID TrueType）で受ける。**重要**: フォールバック書体は Regular/Bold 両字面を宣言する（bold 文脈で字面が無いと Chrome が faux-bold 合成→Type 3 化するため。`-webkit-text-stroke` 由来の Type 3 と同類）。(4) **キーキャップ（keyfont）**: 同梱 `Keyboard-JP-Regular.otf`（CFF）を Chrome 149 が Type 3 化するため、**OTF→TTF(glyf) 変換**した `Keyboard-JP-Regular.ttf` を同梱し @font-face を差し替え（CID TrueType 化）。再現スクリプトは `test/vivlio_starter/fixtures/type3/otf2ttf.rb`（Ruby・fontforge 委譲）。あわせて未使用になった `HackGen35-Regular/Bold.ttf` を削除し、`--font-body` にも `hackgen35` フォールバックを付与。Apache-2.0 のため改変告知を `stylesheets/fonts/Keyboard_font/MODIFICATION-NOTICE.md` に追加。検証は `test/vivlio_starter/fixtures/type3/`（`verify.sh` で約 10 秒の高速ループ・実バンドルフォントで Type 3 = 0 を確認）。
- [Low] **`target_consistency_test` のクリーン EPUB 非汚染ガードを実マーカー検出へ厳密化（偽陽性の解消）**: `EpubSnap` の `vs_kindle` / `vs_code_epub` を `raw.include?("vs-kindle")` / `raw.scan("vs-code-epub")` から、`<body … vs-kindle>` / `<table … vs-code-epub>` という**実マーカー**の検出へ変更。開発者ガイド（`61-developer.md`）が `mark_body_for_kindle!`・`body.vs-kindle` 等の仕組みを解説する地の文・コード例（クリーン EPUB 内に 5 箇所）に素朴な文字列一致が誤反応し、`test_clean_epub_has_no_kindle_degradation` が落ちていた。実測でクリーン EPUB の実マーカーは 0（body class・table class とも）、Kindle 中間 EPUB は body.vs-kindle 34 件・table.vs-code-epub 440 件で、製品出力は正しく非汚染であることを確認（テスト側のみの是正）。
- [Medium] **索引アンカー ID をビルド間で決定化（非決定性の解消）**: `IndexMatchScanner#process_term` の索引語アンカー ID 生成を `term_text.hash`（`String#hash` はプロセス毎にシードがランダム化される）から `Digest::SHA1.hexdigest(term_text)[0, 12]` へ変更。同一語が常に同一 `idx-…` ID になり、単体ビルドと結合ビルドで本文（†除く）が一致しない `TargetConsistencyTest#test_epub_consistent_across_single_and_combined` の失敗を解消（`heading_processor.rb` の安定アンカー生成と同イディオム）。`@vivliostyle/cli` 11.0.2 への更新（Node 26 の Chrome 展開デッドロック回避）に伴う `rake test:targets` 失敗 4 件のうち本件を是正。

## [1.0.0-rc.1] - 2026-06-21

### Added
- [High] **EPUB / Kindle ターゲット分離（Step ④ テスト反転＋クリーン EPUB の WebP 維持是正）**: `docs/specs/epub-kindle-target-split-spec.md` §5 に基づくテスト整備。(§5-1) `test/vivlio_starter/cli/build/epub_flavor_test.rb` を新設し、`generate_epub_entries!(flavor: :epub)` が Kindle 専用 rewrite を**行わない**（`vs-kindle` 非付与・コード非テーブル化・数式 ex 維持・ラベル非注入）こと、`(flavor: :kindle)` が**全 rewrite を行う**こと、`generate_epub_config!(flavor: :kindle)` が表紙非埋め込みになること、`convert_epub_to_kpf!` が `kindlepreviewer` 未導入時に false を返して継続すること（DI）、出力名が `.kpf` / `-kindle.epub` になることを検証（`rake test` に常時組込み）。(§5-3) `target_consistency_test` の `EpubSnap` に `vs_kindle` / `vs_code_epub` / `math_px` を追加し、クリーン EPUB には現れず・Kindle 中間 EPUB には現れることを検査。Kindle を含む combo は `--no-clean` で中間 `…-kindle.epub` を残して検査する（`VsBuilder.build!` に `extra_args:` を追加、`cleanup_artifacts!` に `*.kpf` を追加）。クリーン EPUB の回帰ガードは「`<img>` 解決・劣化痕跡ゼロ」、Kindle は「WebP ゼロ・ガター/ex ゼロ・劣化痕跡あり」に分離。(§5-2) `kindle_conversion_test` を `targets: kindle`（`--no-clean`）ビルドへ更新し、`.kpf` 自動生成と画像系警告ゼロを検査。**是正**: Step ② の見落としで `build_copy_asset_excludes_config` が WebP を常時除外し、`sanitize_epub_css!` が webp url() を常時除去していたため、クリーン EPUB で `<img src="…webp">` が未解決になっていた。両者を `flavor:` 引数化し、**WebP 除外・webp url() 除去を Kindle フレーバ限定**に修正（クリーン EPUB は WebP を高画質維持＝§4 の方針どおり。EPUB 3.3 で image/webp はコアメディアタイプのため妥当）。既存 `test_should_exclude_all_webp_and_twemoji_svg` は「kindle のみ WebP 除外・clean は維持」へ反転。**未対応（別タスク）**: §1-8 用語集 RSC-005／索引 RSC-012 の epubcheck ERROR 0 回復は本 4 ステップ計画に含まれない別機能のため未実装（§5-1 の当該 2 テストは対象外）。
- [High] **EPUB / Kindle ターゲット分離（Step ③ kindle ターゲット＋KPF 自動変換）**: `docs/specs/epub-kindle-target-split-spec.md` §1-3/§1-4/§1-7/§2 に基づき、`output.targets` の `kindle` をパイプラインに配線。`UnifiedBuildPipeline#kindle_target?` / `epub_or_kindle_target?` を新設し、EPUB ビルド経路を `kindle` でも起動するよう登録ロジックを更新（full / print_pdf-only / single 各モード）。`run_step_epub` を `build_epub_flavor(flavor)` に分解し、`epub`（クリーン）→ `kindle`（劣化）の順に生成。**相互非汚染**（§1-3 方式B）として、両ターゲット同時指定時はクリーン処理が章 HTML を書き換える前に `snapshot_chapter_htmls` で退避し、Kindle ビルド前に `restore_chapter_htmls` で復元。Kindle は KPF 変換の入力にすぎないため中間 EPUB（`…-kindle.epub`）として作り、`EpubBuilder.convert_epub_to_kpf!`（`kindlepreviewer <epub> -convert -output <dir> -locale en`）で `.kpf`（ルート直下・最終成果物）へ変換、成功時は中間 EPUB を削除（`--no-clean` 時は検証用に残す）。`kindlepreviewer` 未導入時は警告して中間 EPUB を残し KPF のみスキップ（ビルドは継続・存在チェックは `kindlepreviewer_available?` で DI 可能）。変換ログ（`Summary_Log.csv` / `Logs/*_log.csv`）の Error/Quality 件数を `summarize_kpf_logs` が `log_summary` で要約。出力名は `Common.generate_output_filename('kindle')`→`.kpf`、中間は `generate_kindle_epub_filename`→`-kindle.epub`。`build_pipeline_test` の各サブクラスに `kindle_target?` の上書きを追加し「pdf 専用モード強制」の分離を維持（期待値不変）。`vs clean --purge` の動的パターンに `<project>*.kpf` / `<project>_v*.kpf` を追加し、最終 Kindle 成果物も purge 対象にした（中間 `…-kindle.epub` は既存の `<project>*.epub` で拾う。通常クリーンでは `.kpf` を保持）。`vs open` は pdf/print_pdf のみ対象のまま（EPUB/KPF は本棚登録型リーダーが必要で気軽なプレビュー不可のため据え置き）。実ビルド（`targets: kindle`・実ツール導入環境）で中間 `-kindle.epub`→`kindlepreviewer`→最終 `vivlio_starter_v1.0.0.kpf`（ルート直下・通常クリーンで残存）の生成を確認。網羅テスト（非汚染・epubcheck・KPF 変換成功）は次の Step ④。
- [High] **EPUB / Kindle ターゲット分離（Step ② フレーバ化）**: `docs/specs/epub-kindle-target-split-spec.md` §1-2/§1-5/§1-6 に基づき、`EpubBuilder.generate_epub_entries!(base_dir, entries, flavor:)` に `flavor`（`:epub`＝Kobo/Apple Books 向けクリーン / `:kindle`＝Amazon 向け劣化）を追加し、HTML 後処理を振り分け。**両フレーバ共通**は XHTML 妥当性に必要な最小処理（索引・用語集是正 / 段落内脚注 id 除去 / table align 変換 / 絵文字復元 / 扉絵・節絵注入）のみ。**Kindle 専用**（`flavor: :kindle` のときだけ）に WebP→JPEG・`mark_body_for_kindle!`（`vs-kindle` 付与）・画像 inline 制約・数式 px 化・コードのテーブル化・admonition ラベル注入を実行。これによりクリーン EPUB は `::before` 角タブ・`var()` テーマ色・WebP・高画質 SVG を維持する。扉絵/節絵は `heading_image_src(flavor:)` で出し分け、クリーンは `HeadingImageComposer.compose` の**合成 SVG**（base64 画像内包・高画質）、Kindle は `render` の**平坦 JPEG**（Kindle は SVG 内 base64 非対応）を配る（キャッシュ鍵に flavor を含めて衝突回避）。`generate_epub_config!(flavor:)` / `build_cover_config_line(..., flavor:)` を引数化し、Kindle は表紙二重化回避のため `embed:false` 固定（§1-6）。**§1-5 CSS**: `.tip/.memo/.column` の base 規則から Kindle 用の枠線フォールバック（`1px #888` + `var(--adm-border-width)`）を撤去して元の `border: solid 0.2mm var(--…)` へ復元（クリーン EPUB / PDF を完全復元）。Kindle 用の `::before` 抑止（`content: none`）・実体ラベル `.vs-adm-label` の通常表示・具体色枠線（`1px solid #888`）・上余白詰め（`padding-block-start: 4mm`）は `body.vs-kindle` ガード配下へ集約（root・scaffold 両方）。既存の単体テスト（`epub_builder_test.rb` の扉絵注入）は JPEG 経路＝Kindle フレーバ前提に入力 context を `flavor: :kindle` へ整合（期待値不変）。パイプライン配線（`kindle` ターゲット・KPF 変換）と網羅テストは次の Step ③/④。デフォルト `flavor: :epub` のため `targets: pdf, epub` の出力は劣化のないクリーン EPUB になる。
- [High] **EPUB / Kindle ターゲット分離（Step ① マーカー改名）**: `docs/specs/epub-kindle-target-split-spec.md` §1-1 に基づき、Kindle 専用ガード CSS のマーカークラスを `body.vs-epub` → `body.vs-kindle` へ、付与メソッドを `mark_body_for_epub!` → `mark_body_for_kindle!` へ一括改名（意味を正確化し、後続のフレーバ化で Kindle ビルド時のみ付与する布石）。対象は `chapter-common.css` / `code.css` / `components.css` / `layout-utils.css`（root・scaffold 両方）の `body.vs-epub …` ルールおよび関連コメント、`EpubBuilder#mark_body_for_kindle!`、`epub_kindle_layout_test.rb`。`vs-code-epub` 等の別クラスや `mktmpdir` の `vs-epub-*` プレフィックスは非対象。挙動は不変（次の Step ②〜④ でフレーバ化・KPF・テストを実装）。
- [Low] **EP-02（epubcheck）有効化と CN（カナリア）実機確認**: `epubcheck` を導入して EP-02 を初回実行し、EPUB 生成側の構造 ERROR 35 件を検出（上記「既知の不具合」に記録、テストは緩めない）。あわせて `rake test:canary` を実機実行し、`@vivliostyle/cli` **11.0.1**（ピン留め 10.5.0 からのメジャー更新）でマニュアルが正常ビルド・Type 3 再発なし・新規警告なしを確認。`rake test:layout` がプリセット切替後に `stylesheets/page-settings.css` / `vivliostyle.config.js` を最終プリセット値で残していた既存挙動を、`BookYmlPatcher.apply` のブロック復元に含めて解消（テスト後の `git status` が汚れない）。
- [High] **RC 品質保証テスト群を導入（テストスイート拡充）**: `docs/specs/test-suite-expansion-spec.md` に基づき 11 グループ（マニュアルフルビルド警告ゼロ / PDF フォント検査 / パッケージング E2E / ファズ / 機能縮退 / NFD / CLI 契約 / ドキュメント整合 / 冪等性 / EPUB / 依存カナリア）を新設。`rake test:manual` / `test:package` / `test:release` / `test:canary` タスクを追加。導入過程でファズ・契約テストが実不具合 5 件を検出（4 件修正・1 件課題化）。詳細は `Unreleased > Added` / `Fixed` に記載。
- [Medium] **doctor の設定ファイル復元・サルベージ・プラグイン連動診断（Phase 5）**: `vs doctor --fix` で config/ 配下の欠落・破損ファイルを scaffold から復元（破損時は必ず .bak へ退避する非破壊設計）。破損 catalog.yml は contents/ から再構築、破損 book.yml は書名・著者などを行スキャンで best-effort 救出。OCR ツールはプラグイン未導入時に🟡任意ツール扱いへ。破損 YAML で CLI 起動自体が abort して修復不能だった問題も修正。詳細は `Unreleased > Added` に記載。
- [Medium] **前提条件ガードを全コマンドへ展開（Phase 3+4）**: 対応表に従い執筆支援系・pdf 系・open / clean へ Guard を組み込み、`vs preflight` は全 Check の網羅的診断に再構成。`ImagesDirCheck` / `PdfArtifactCheck` / `RelaxedCheck` / `Guards.precheck` を追加。詳細は `Unreleased > Added` に記載。
- [High] **前提条件ガード基盤（Phase 1+2）を実装**: `docs/specs/precondition-guard-spec.md` に基づき、Guard/Check 二層構造を `lib/vivlio_starter/cli/guards/` に新設。`vs build` は ProjectRoot / CatalogFile / CatalogEntries / ContentsDir / VivliostyleConfig / Node の6種を実行前に検証し、違反時は🔴メッセージ + exit 1 で即終了。`vs preflight` は catalog 未登録原稿を1つの🟡警告に集約して通知。詳細は `Unreleased > Added` に記載。
- **EPUB の扉絵（h1）・節絵（h2）を合成画像として画像化（③-a）** (`lib/vivlio_starter/cli/build/heading_image_composer.rb`, `lib/vivlio_starter/cli/build/epub_builder.rb`, `lib/vivlio_starter/cli/doctor.rb`, `lib/project_scaffold/stylesheets/components.css`（＋ repo 直下 `stylesheets/components.css`）, `clean.rb`, `docs/specs/math-frontispiece-svg-spec.md` §B): 扉絵は PDF では `@page` 背景＋固定寸法で全面描画されるが、リフロー型 EPUB では背景・固定寸法・`position` 重ね合わせが（特に Kindle で）描画されず、画像実体は同梱されるのに見えなかった（③-a）。飾り絵の上に見出しを重ねた状態を全リーダーで確実に出すため、新設 `HeadingImageComposer` が「飾り画像＋見出し `<text>` を重ねた合成 SVG」を組み、**ビルド時にフラット JPEG へラスタライズ**（`rsvg-convert` で PNG 化 → ImageMagick で白フラット JPEG 化）して `<img>` で見出しに差し込む。`EpubBuilder#generate_epub_entries!` の Step E に `inject_heading_images_for_epub!` を追加（PDF 完成後に共有 HTML を書き換えるため PDF 経路へ副作用なし）。`theme.style == 'image'` かつ**本文章（番号 1..89）**のときのみ、`theme.css` の `--frontispiece-image`（portrait・章扉）/ `--section-bg-image`（landscape・節扉）を**単一の参照元**として実画像を読み、白フラット化した縮小 JPEG を合成 SVG に data URI 埋め込み（rsvg がロード）。生成 JPEG は `images/headings/<kind>-<hash>.jpg` に入力ハッシュ名でキャッシュ。見出しテキストは `<img alt>` に格納（読み上げ・検索・画像非表示時のフォールバック）。**Kindle 実機検証（Kindle Previewer）で判明した重要点**: (1) **Kindle は SVG 内 base64 埋め込み画像を非対応**（変換時ブロッキングエラー＝出版不可）のため、当初の `<img src=".svg">` 直配りをやめ JPEG ラスタライズ方式へ変更。(2) **EPUB 目次（nav）は各章の `<title>` から生成され h1 テキストに依存しない**と判明したため、当初入れていた `clip: rect()` の隠しテキスト span（Kindle が `clip` 非対応）を撤廃し、見出しテキストは alt に集約。扉絵は番号を持つ h1（`data-chapter-number-display`）のみ、節絵は `article.section-topic > h2` のみを対象とし、**付録（90-98）・前付（00）・後付（99）・特殊ページは simple 版**（画像注入せず・PDF と整合）。節絵では親 article の PDF 用固定寸法グリッド（150px 行）を EPUB 用クラスで解除。EPUB 用 CSS（`vs-image-heading-epub` / `vs-section-topic-epub`）は `components.css` に追加（PDF 経路は当該マークアップが無いため無害）。見出しフォントは焼き込み（EPUB 非埋め込み方針どおりビルド機フォントでラスタライズ・字形完全一致は v2.0 で対応）。`rsvg-convert`（librsvg）/ magick 未導入・画像未解決・合成失敗時は注入をスキップし simple 相当へ自然縮退（§B-5）。`rsvg-convert` は `vs doctor` のチェック対象に追加（`--fix` で `brew install librsvg`）。`images/headings/` は `clean.rb` のクリーン対象。単体テスト（合成 SVG 生成・render 縮退 7 件・EpubBuilder 注入/付録除外 3 件）を追加。
- **`vs doctor` が Vivliostyle の壊れた headless Chrome を検出・修復** (`lib/vivlio_starter/cli/doctor.rb`, `test/vivlio_starter/cli/doctor_commands_test.rb`): ビルドを `Ctrl+C` で中断すると Vivliostyle が PDF レンダリングに使う Chrome（`~/Library/Caches/vivliostyle/browsers`）のダウンロード/展開が途中で壊れ（展開途中の `.zip` が残り Framework 本体が欠落）、以降「🔴 PDFの生成に失敗しました」で**本文が欠落（表紙・裏表紙のみ）**になる。著者がキャッシュを手で消さずに済むよう、`vs doctor` が不完全な Chrome を検出して 🟡 警告し、`vs doctor --fix` が該当の残骸 `.zip`・不完全バージョンディレクトリのみを削除する（健全な版は保持・次回ビルドで自動再取得）。検出は「残骸 `.zip` の有無」と「バージョンディレクトリ配下の Framework 本体の有無」で判定。単体テスト2件を追加。Chrome は初回のみ DL してキャッシュ再利用するため通常は再 DL されない（CLI 更新で必要版が変わった時・キャッシュ破損時のみ）。
- **数式の SVG 化（前処理で LaTeX→SVG・PDF/EPUB/表セルを一括解決・MathJax 採用）** (`lib/vivlio_starter/cli/pre_process/math_transformer.rb`, `lib/vivlio_starter/cli/pre_process/mathjax_to_svg.mjs`, `markdown_preprocessor.rb`, `clean.rb`, `post_process/heading_processor.rb`, `lib/project_scaffold/stylesheets/components.css`（＋ repo 直下 `stylesheets/components.css`）, `doctor.rb`, `docs/specs/math-frontispiece-svg-spec.md` §A): VFM 内蔵 MathJax は PDF にしか数式を組版せず EPUB に生 LaTeX が露出し（④-A）、GFM 表セル内 `$…$` は PDF でも組版されなかった（④-B）。前処理（VFM より前・PDF/EPUB が共有する Markdown）で `$…$` / `$$…$$` / `\(…\)` / `\[…\]` を検出し、**Node 上の MathJax（mathjax-full）を「ビルド時 SVG 生成器」として** `mathjax_to_svg.mjs`（章内の全式を 1 回の subprocess に束ねる・`fontCache:'none'` で自己完結 SVG）で SVG 化、外部 SVG ファイル（`images/math/<章>/<hash>.svg`）＋ `<img>`（インライン）/ `<figure>`（ディスプレイ）として埋め込む。リーダー実行時の MathJax（EPUB 非対応）ではなく**静的 SVG を焼き込む**ため、PDF・EPUB・表セルを同一 SVG で描画し Kindle 含む全リーダーで崩れない。MathJax が SVG に付す ex 値（vertical-align/width/height）を `<img>` へ写し本文相対で正しく整列。コードスパン内の `$` は退避して誤変換しない。`alt` に元 LaTeX を保持。同一式は LaTeX＋表示種別ハッシュでキャッシュ（`vs clean` で `images/math/` を削除）。node/mathjax-full 未導入・描画失敗時は本文を変えず縮退（PDF は Vivliostyle の MathJax 組版）。導入は `vs doctor`（`vs new` 初回の `--fix`）が `mathjax` チェックを行い `npm install -g mathjax-full` で対応（playwright と同方式・ネイティブビルド不要）。EPUB の数式画像には twemoji 同様にクラスで枠線・余白・背景を付けない（一部リーダーが `img[src$=".svg"]` 属性セレクタを解さないため）。`### $E=mc^2$` のように見出しが数式のみで VFM の slug が空になり epubcheck RSC-005（空 id）を招く件は `heading_processor` が内容ハッシュで非空 id を補って解消。単体テスト MT 10 件を追加。フルマニュアル/94-sample 実ビルドで PDF・EPUB に数式 SVG が焼き込まれ生 LaTeX 漏れが無いこと、`\langle\rangle`・`\sqrt` 等の記号も正しく描画されること、表セル内数式（94-1）も画像化されることを確認済み（当初採用した `mathematical`/lasem は記号グリフを化けさせたため撤回）。**残課題**: 扉絵・節絵の EPUB 画像化（③-a・仕様 §B）は別タスクで未着手。
- **ターゲット整合性テスト `rake test:targets`（実ビルド回帰テスト）** (`test/vivlio_starter/targets/target_consistency_test.rb`, `test/vivlio_starter/support/build_helper.rb`, `Rakefile`): `output.targets` を 7 通り（単体 pdf / print_pdf / epub ＋ 複合 4 種）に切り替えて実マニュアルをビルドし、成果物を突き合わせる回帰テストを新設。**同一フォーマットが単体ターゲットと複合ターゲットで一致すること**（pdf・print_pdf はページ数/各ページ本文/アウトライン/サイズ、epub は spine 構成/本文）を検証し、「`targets: pdf, print_pdf, epub` で print_pdf 本文が欠落し 4 ページになる」種の不具合（②）を直接検知する。加えてフォーマット横断の本文量比較・print_pdf と pdf のページ数近似・epub spine の構成ページ（前書き/後書き/奥付/用語集/索引）包含・pdf と print_pdf のアウトライン一致・本文マーカー存在を確認。EPUB の spine/本文抽出に `EpubInspector` を `build_helper.rb` へ追加。実ビルドを 7 回回すため最も遅く（20〜30 分）、通常 `rake test` からは除外し `rake test:release` に組み込む。
- **RC 品質保証テスト群（テストスイート拡充）** (`test/vivlio_starter/{release,fuzz,contract,robustness,support}/`, `Rakefile`, `docs/specs/test-suite-expansion-spec.md`): RC 移行前の品質保証として、過去に実際に踏んだ不具合から逆算した 11 グループのテストを新設。(1) **MB**: マニュアル実体のフルビルドが exit 0・🔴🟡 ゼロ（許容リスト `release/allowed_warnings.yml` は理由必須）・git 作業ツリー非汚染で通ることを固定。(2) **FT**: 生成 PDF に Type 3 フォントが無く全フォント埋め込み済み・標準添付書体が実使用されていることを pdf-reader で検査。(3) **PK**: gem build → 内容一覧検査（scaffold 全ファイル同梱・開発ファイル非混入）→ 隔離 GEM_HOME インストール → scaffold 直接コピーの一時プロジェクトで実ビルド（`vs new` は内部で doctor --fix が走るため不使用）。(4) **FZ**: ConfigSalvager / TokenResolver / ConfigValidityCheck に「任意入力で例外を出さない」プロパティテスト（シード固定・自前ジェネレータ、500 ケース超）。(5) **DG**: mecab / playwright 不在時の縮退完走（gs / waifu2x は理由付き skip で課題化）。(6) **NF**: macOS NFD ファイル名の正規化差テスト。(7) **CL**: 全 Public コマンドの `--help` 契約（RootCommand から動的取得）。(8) **DC**: マニュアル記載コマンドの実在・Public コマンドのドキュメント網羅（許容リスト `contract/docs_allowlist.yml`）。(9) **ID**: ビルド 2 回連続・clean 後再ビルドの意味的同一性（ページ数・本文テキスト・アウトライン・サイズ ±1%。PDF はタイムスタンプ入りのためバイト比較不可）と設定復元の冪等性。(10) **EP**: epub ターゲットのビルドと epubcheck 検証（未導入環境は skip）。(11) **CN**: `@vivliostyle/cli@latest` での破壊検知（`rake test:canary` 専用・リリース判定に含めない）。あわせて page_layout の `BookYmlPatcher` / `VsBuilder` を `test/vivlio_starter/support/build_helper.rb` へ抽出し、フォント・テキスト・アウトライン検査の `PdfInspector` を追加。Rakefile に `test:manual` / `test:package` / `test:release`（RC 前総点検）/ `test:canary` を新設。
- **`vs doctor` に設定ファイルの診断・復元とサルベージを追加（Phase 5）** (`lib/vivlio_starter/cli/doctor.rb`, `lib/vivlio_starter/cli/doctor/config_salvager.rb`, `lib/vivlio_starter/cli/guards/config_validity_check.rb`, `lib/vivlio_starter/cli/common.rb`, `docs/specs/doctor-restore-and-plugin-tools-spec.md`): 利用者が config/ 配下の設定ファイルを誤って削除・破損させた場合に、`vs doctor` が欠落・破損（YAML 解析不能）を診断し、`vs doctor --fix` で `project_scaffold` から復元できるようにした。必須 YAML 4 種は破損まで判定し（新設の `Guards::ConfigValidityCheck` を Guard 層と共有）、破損ファイルは必ず `<path>.bak.<timestamp>` へ退避してから復元する非破壊設計。textlint 系設定・`_README.md`・辞書ディレクトリ（spellcheck/textlint）は欠落時のみ復元し、既存の `copy_textlint_*` 群を統合（scaffold ルート直下を参照していて実際には何もコピーされない不具合も同時に解消）。さらに機能 D として、破損 catalog.yml は `contents/*.md` から章構成を再構築（`TokenResolver::KIND_RANGES` を再利用）、破損 book.yml は行スキャンで書名・著者などの単一行スカラーを best-effort 救出し「要確認」を明示して書き戻す（失敗時は素の scaffold 復元へフォールバック）。あわせて、必須 YAML が「存在するが破損」だと CLI 起動時のモジュールロードで abort してしまい修復手段の `vs doctor --fix` 自体が実行できなかった問題を修正（破損時も欠落時と同様 `CONFIG = nil` で起動し、検出・案内は各コマンドの `ensure_configured!` と doctor に委ねる）。OCR 系ツール（tesseract / tesseract-lang / vips）は `vivlio-starter-pdf` プラグイン未導入時にエラー扱いせず🟡任意ツールとして案内するよう出し分け（`--fix` での先回りインストールは維持）。プラグイン側 `post_install_message` も手動 brew 列挙から `vs doctor --fix` 誘導へ修正（別リポジトリ）。テスト 22 件（CV-01〜04 / DR-01〜06 / SV-01〜05 / PT-01〜02 ほか）を追加。
- **前提条件ガードを全コマンドへ展開（Phase 3+4）** (`lib/vivlio_starter/cli/guards/`, `lib/vivlio_starter/cli/samovar/`): コマンド × Check 対応表（`docs/specs/precondition-guard-spec.md` §4）に従い、create / delete / rename / renumber / lint / metrics / index:auto / index:apply / cover / resize / clean / open / pdf:compress / pdf:pages / pdf:rasterize / pdf:read へ Guard を組み込み。新規 Check として `ImagesDirCheck`・`PdfArtifactCheck`（明示パス指定時のみ検証。引数省略時の自動解決はドメイン層に委譲）・`RelaxedCheck`（対応表の「○=推奨」を :error→:warn 格下げで表現するデコレータ）と、コマンド `call` 冒頭用ヘルパー `Guards.precheck`（違反時に🔴要約 + 終了コード1を返す）を追加。Phase 4 として `vs preflight` は全7 Check を網羅実行する診断に再構成（`Guard.run!` は全違反をログしてから停止判定するため複数の問題を一度に報告できる）。Check 単体テスト5件を追加。
- **前提条件ガード（Precondition Guard）基盤を追加** (`lib/vivlio_starter/cli/guards.rb`, `lib/vivlio_starter/cli/guards/`, `docs/specs/precondition-guard-spec.md`): コマンド実行前に「成立するための最低限の前提条件」を検証し、違反時はスタックトレースではなく行動可能な🔴メッセージで早期終了する二層構造（Guard 層 + 単一責務の Check 層）を新設。Check は `ProjectRootCheck` / `CatalogFileCheck` / `CatalogEntriesCheck` / `ContentsDirCheck` / `VivliostyleConfigCheck` / `NodeCheck`（runner DI 対応）/ `OrphanFileCheck` の7種。`vs build` には必須6種を、`vs preflight` には ProjectRoot ◎ + 未登録原稿の一括🟡警告（OrphanFileCheck）を組み込み。カタログ解析は `TokenResolver::Resolver` を再利用しロジックの二重化を回避。`UnifiedBuildPipeline#run` 冒頭の検証は二段目の保険として併存。仕様書を現行コードベース（config/catalog.yml パス・🔴/🟡 ログ規約・`Common.log_*` の detail 形式）へ整合させた上で Phase 1+2 を実装し、Check 単体・Guard 統合のテスト 13 件を追加。あわせて preflight の `ensure` 節クリーン処理を「本処理開始後のみ」に限定（`--help` や Guard 違反時にプロジェクト外ディレクトリでクリーンが走る潜在問題を解消）。
- **`vs pdf:pages` / `vs pdf:rasterize` コマンドを追加** (`lib/vivlio/starter/pdf/pdf_to_jpeg.rb`, `lib/vivlio/starter/pdf/jpeg_to_pdf.rb`, `lib/vivlio/starter/cli/pdf.rb`, `lib/vivlio/starter/cli/samovar/pdf_command.rb`): `pdftoppm` による PDF ページの JPEG 切り出しと、外部依存なしの独自実装 `JpegToPdf` による全ページラスタライズ PDF 再結合に対応。`pdf:pages` は `--dpi` / `--quality` / `--pages` / `--output` を、`pdf:rasterize` は `--dpi` / `--quality` / `--clean` を受け付ける。`vs --help` と `vs doctor` にも関連コマンド・外部依存 (`pdftoppm`) を追加し、単体テストとコマンドロジックテストを整備。
- **`long-table` / `table-scroll` コンテナの pre_process 変換** (`lib/vivlio/starter/cli/pre_process/markdown_preprocessor.rb`, `lib/vivlio/starter/cli/pre_process/markdown_transformer.rb`): `:::{.long-table}` および `:::{.table-scroll}` コンテナ内のパイプテーブルを、`table-rotate` と同様に pre_process パイプラインで HTML テーブルに変換するよう実装。従来は VFM に変換を委ねていたが、VFM がコンテナ内のパイプテーブルを `<table>` に変換しないケースがあり、テーブルが崩れて表示されていた。`convert_table_container_inner_markdown` を汎用メソッドとして新設し、`convert_table_rotate_inner_markdown` はこれに委譲するよう変更。

### Changed
- [Medium] **`book.yml` に `kindle:` 設定セクションを追加・配線**（`docs/specs/kindle_epub_debug.md` 由来）: Kindle 向け設定を明示するため `output.kindle.{embed, layout}` を追加（既定 `embed: false`＝二重表紙回避）。`Common.kindle_embed?` を新設し、`build_cover_config_line(flavor:)` がフレーバごとに `epub.embed` / `kindle.embed` を参照するよう変更（従来の Kindle 固定 false をやめ設定駆動に）。あわせて `vs build` 完了メッセージに Kindle の最終成果物 `.kpf` を追記（`get_created_files_list` の kindle 対応）、KPF 変換ログ要約に**エラー/警告コードの内訳**（例 `W14016×1`＝embed:false 時の Cover not specified 通知）を表示。
- [High] **EPUB のサイズ最適化（59MB → 25MB・フォント非埋め込みを既定化）**: `epub-pipeline-fix-spec.md` §3（P2）に基づき、ERROR 0 を維持したままサイズを削減。(P2-1) フォント非埋め込みを既定化（`EpubBuilder.embed_fonts?` 既定 false）。`stylesheets/fonts/**` を `copyAsset.excludes` に加え、`sanitize_epub_css!` が EPUB 内 CSS から `@font-face` と `@import url("fonts/…")` を除去（RSC-007 回避）。`css_updater` が `--font-*` 変数へ generic フォールバック（明朝=serif / ゴシック=sans-serif / コード=monospace）を付与し、リーダー側でも書体カテゴリが保たれるようにした（root/scaffold の `page-settings.css` 既定値も同様に統一）。v2.0 の小説対応に向け book.yml でのフォント埋め込みオプション化を予定し、埋め込み経路はコード上維持（EPF-10）。−51MB。(P2-2 / Fix-8) 絵文字画像化（twemoji）は PDF の Type 3 障害対策で EPUB には不要なため、EPUB 経路で `restore_plain_emoji_for_epub!` が `<img class="…vs-emoji…">` を alt の元絵文字へ復元し、`stylesheets/twemoji/*.{svg,webp}`（マスター 7,000+）を除外（囲み数字 `vs-circled-number` と `vs-techbook/` は画像維持）。単体テスト EPF-09〜11・CU-01〜05 を追加。
- [Medium] **標準フォントのファミリ名を実体に統一**: Type 3 対策後も `@font-face` のファミリ名が "Noto Serif JP" / "Noto Sans JP" のまま実体だけ Zen 系 TTF という紛らわしい状態だったため、`page-settings.css` のファミリ名・CSS 変数、book.yml の typography 設定、`FontManager::STANDARD_FONT_FAMILIES`、マニュアル原稿（41-book-yml.md / 45-utility.md）を "Zen Old Mincho" / "Zen Kaku Gothic New" に統一（root と scaffold の両方）。
- [High] **gem パッケージングのホワイトリスト化**: gemspec の `spec.files` を「git ls-files 全部 − test/」方式から `bin/` `lib/` + README/LICENSE/THIRD-PARTY-LICENSES のホワイトリスト方式へ変更。原稿（contents/・docs/・covers/）や開発用ファイル（.claude/・.github/ など）、`lib/project_scaffold` と重複していたリポジトリ直下の stylesheets/ が配布物に混入していた問題を解消（gem サイズ 430MB → 55MB）。
- [High] **未参照フォントの削除**: `page-settings.css` は Type 3 フォント対策（コミット 9c86ff4 前後）以降、ファミリ名 "Noto Serif JP" / "Noto Sans JP" の実体として Zen Old Mincho / Zen Kaku Gothic New の静的 TTF を使用しており、Noto CJK の OTF 実体（193MB）と BIZ UD 系（20MB）はどの CSS からも参照されていなかったため、`stylesheets/fonts/` と `lib/project_scaffold/stylesheets/fonts/` の両方から削除（fonts/ 257MB → 43MB）。book.yml の標準添付書体コメントにエイリアス対応を明記。
- [Medium] **未使用コードの一掃**: 呼び出し元ゼロのレガシー API を削除。`scaffolder.rb`（476行・旧 `vs new` 実装の残骸）をファイルごと削除し、`new.rb` の旧 Scaffolder 経路（`execute_new` / `run` ほかヘルパー5件）、`vs delete` の未配線 dry-run 機能一式、`execute_vivliostyle_config`、`build_sections_html!`、ほか各所の未使用メソッド約20件を削除。
- [Low] **ビルド系リファクタリング**: 3箇所に重複していた qpdf 結合処理を `Build::PdfMerger.merge_pdfs_with_qpdf!` に集約。pipeline の `Step` を Struct から `Data.define` へ。TOC 項目生成・entries タイトル抽出の沈黙 rescue にデバッグログを追加。metrics テストを ⚠️→🟡 出力統一（3b346bb）に追従。`live_display.rb` / `jpeg_to_pdf.rb` / `mecab_newline_cleaner.rb` / `pdf_to_jpeg.rb` に Why-First コメントを追加。
- [Medium] CLI ロード構造のリファクタリング（`docs/specs/cli_loader_refactor_spec.md` 準拠）: `startup.rb` / `loader.rb` 分離、`help.rb` 削除、`commands/new.rb` 廃止、二バイナリの `exit` 統一。`Unreleased > Changed` に詳細記載。
- **無効入力（未知のコマンド・オプション）の終了コードを 0 → 1 に変更**（契約テスト CL-02 で検出）(`lib/vivlio_starter/cli/startup.rb`): `vs nosuchcommand` や `vs build --unknown-option` が help を表示しつつ exit 0 を返していたため、シェルスクリプトや CI からタイプミスを検知できなかった。POSIX 慣習に従い、help 表示はそのままに exit 1 を返すよう変更。CL-02 補遺テストを有効化し、help_behavior_test の期待値を追従。
- 名前空間およびディレクトリ構造を `Vivlio::Starter`（サブコンポーネントを含めて3階層、例: `Vivlio::Starter::CLI`）から `VivlioStarter`（2階層、例: `VivlioStarter::CLI`）へと一階層フラット化（浅く）した。
- **PDF 関連ソースを `cli/pdf/` 配下に集約** (`lib/vivlio_starter/cli/pdf/pdf_to_jpeg.rb`, `lib/vivlio_starter/cli/pdf/jpeg_to_pdf.rb`, `lib/vivlio_starter/cli/pdf.rb`, `test/vivlio_starter/cli/pdf/`): 従来 `lib/vivlio_starter/pdf/` と `lib/vivlio_starter/cli/pdf/` に分散していた PDF 関連ファイルを、名前空間（いずれも `VivlioStarter::Pdf`）と一致するよう `cli/pdf/` 配下へ統合した。`pdf_to_jpeg.rb` / `jpeg_to_pdf.rb` を移動し、`require_relative` とテスト配置を追従。プラグイン `vivlio-starter-pdf` 側も同様に `reader.rb` / `version.rb` を `cli/pdf/` へ移動し、不要だったシム `pdf/utilities.rb`（実装は `cli/pdf/utilities.rb` に集約済み）を削除。技術的必然性はなく、ディレクトリと名前空間の不一致を解消する整理。
- **プラグインのインデント整形** (`vivlio-starter-pdf`): 名前空間の 3 階層→2 階層化の名残で `module Pdf` 配下が 2 スペース過剰インデントになっていた `cli/pdf/` 配下の各ファイルを揃え、`ruby -w` の "mismatched indentations" 警告を解消。
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
- [High] **奥付前の空白ページが判型を無視して常に B5 で挿入される不具合を修正** (`lib/vivlio_starter/cli/common.rb`): `page.use:` プリセット方式（例 `a4_standard`）を使う書籍で、`vs build` が奥付の前に挿入する空白調整ページ（`_blank_before_colophon.pdf`）が、本文・表紙の判型に関係なく **B5（182×257mm）固定**で生成されていた。原因は `Common.resolve_page_size` が `page_cfg.is_a?(Hash)` でしか引数を受け付けず、`Common::CONFIG['page']`（`wrap_config` でラップされた **Data オブジェクト**）を渡すと Hash でないため空ハッシュ扱いになり、`size` を読めず B5 デフォルトへフォールバックしていたこと。`resolve_page_size` を Data など `to_h` 可能なオブジェクトも受理するよう正規化し、CONFIG 経由でも正しい判型（A4/A5/B5）を解決するよう修正。`vivliostyle.rb` / `epub_builder.rb` など `Common::CONFIG` を直接渡していた他経路の同種フォールバックも同時に解消。判型統合テスト（`rake test:layout`）の検証対象を閲覧用 PDF に確定させるため、`build_helper` の `BookYmlPatcher.apply` がプリセット切替時に `targets: pdf` を一時固定するよう調整（トンボ＋ドブ付きの入稿用 PDF を誤って拾わないようにする）。全 7 プリセットの判型テストが green。
- [High] **EPUB/Kindle 双方で epubcheck ERROR 0 / WARNING 0 を回復（用語集 RSC-005・Kindle techbook WebP RSC-007）**（`docs/specs/kindle_epub_debug.md` 由来）: (RSC-005) 用語集 `_glossarypage.xhtml` の `<dl>` 直下グループ見出し `<div>`（XHTML5 の dl 内容モデル違反）を、EPUB 後処理 `split_glossary_groups_for_epub` が `<p role="heading">` として `<dl>` の外へ出し、頭文字ごとに `<dl>` を分割して解消（PDF は生成元 HTML を使うため無影響・両フレーバ共通）。(RSC-007) Kindle で techbook が head に注入するインライン `<style>` の `:root{ --h3-marker: url(...webp) }` 系が、WebP 非同梱により参照切れになる件を、Kindle 限定の `strip_webp_inline_styles_for_kindle!` で除去（カスタムプロパティ名を丸ごと拾う `INLINE_WEBP_DECL_PATTERN` を新設し、`--h3` 断片残りによる CSS-008 も回避）。クリーン EPUB は WebP を同梱維持するため当該参照は解決し ERROR は出ない。epubcheck 5.3.0 でクリーン EPUB・Kindle 中間 EPUB の双方が **0 FATAL / 0 ERROR / 0 WARNING** を確認。テスト EPF-12（dl 分割）/ EPF-13（インライン webp 除去）を追加。
- [High] **Kindle / Apple Books の表示不具合をまとめて是正**（`docs/specs/kindle_epub_debug.md` 由来）: (1) Kindle の TIP/MEMO/COLUMN で枠線が出ず「TIP」ラベルが重複する件は、**Kindle KFX が `:is()` を解さずルールごと破棄する**ことが原因と判明。`body.vs-kindle :is(.tip,.memo,.column)` を明示セレクタへ展開し、`::before` 抑止・具体色枠線（`1px solid #888`）・枠間余白（`margin: 1.5em`）を確実に適用。(2) 節（節絵）がページ途中から始まる件を `article.vs-section-topic-epub` の `page-break-before: always`（＋ modern `break-before: page`）で改ページ。(3) 付録（simple スタイル）の章/節見出しが Kindle で素テキスト化する件を、`simple-header.css` の `body.vs-kindle` フォールバック（`var()`/`grid`/`clamp()`/`::before` を使わない具体値）で装飾再現。(4) 用語集・後書き・索引の h1 下線が Kindle で消える件を、`glossary.css`/`index.css`/`preface.css` に具体色の `body.vs-kindle` 下線フォールバックを追加。(5) Apple Books でクリーン EPUB のコードが特定幅でクリップ消失する件を、EPUB 基底マーカー `vs-epub`（`mark_body_for_epub!` で両フレーバ付与）配下の `body.vs-epub pre[class*="language-"]{ white-space: pre-wrap; overflow: visible }` で全文表示化（§6 A案。PDF は当該マーカー無しのため無影響）。(6) `vs build`（epub/kindle のみ）で「生成対象がありません」と誤警告する件を、`ensure_cover_files_for_build!` が pdf/print_pdf ターゲットがある場合のみ PDF カバーを生成するよう修正。**残課題（将来タスク）**: コード行番号↔行の対応（`docs/specs/epub-code-line-numbers-spec.md`）・付録見出しの SVG 画像化（`docs/specs/kindle-simple-header-svg-spec.md`）。
- [Medium] **EPUB(Kindle) のレイアウト崩れを是正（画像の巨大化・数式単位の巨大化・コード行番号）**: `docs/specs/epub-kindle-layout-spec.md` に基づく。原因は Kindle のリフローが CSS Grid / `position:absolute` / `ex` 単位を非対応なこと。PDF は不変のまま EPUB 経路でのみ是正する。EpubBuilder が EPUB 章 HTML の `<body>` に `vs-epub` マーカーを付与（`mark_body_for_epub!`）し、以下を適用。**重要な知見: Kindle は外部 CSS の画像サイズ指定を無視し inline style を尊重する**ため、画像の制約は inline で行う。(§2) `constrain_layout_images_for_epub!` が `book-card`・`sideimage(-left/-right)`・`img-text/text-img` 系のコンテナ画像に幅(%)・`float` を inline style で付与し、grid 崩壊時の全幅化を防止（`LAYOUT_IMAGE_RULES`、book-card=40%/その他=45%）。CSS（`components.css`/`layout-utils.css`、root・scaffold 両方）は grid 解除のフォールバックとして保持。(§3) `convert_math_units_for_epub!` が inline/display 数式画像の inline style の `ex` を `em`（×0.5）へ変換し巨大化を解消。さらに**表セル内の単位記号**（`$\text{A}$` 等）が Kindle の表縮小で読めなくなるため、`td/th` 内の数式は最低 1.0em の高さを確保し等比拡大する。(§4) `convert_code_blocks_for_epub!` が Prism の行番号付きコード（絶対配置ガター）を Kindle が解す 2 列テーブル（番号｜コード）へ変換。複数行トークンは行ごとに span を開き直す。行は上下中央で揃え、空行は nbsp で高さを保ち、余白を圧縮（`code.css` の `vs-code-epub`、root・scaffold 両方）。テスト: 各変換のユニット（OS 非依存・10 ケース）と `target_consistency_test` に「絶対配置ガター不在・数式 ex 不在」検査を追加。実機検証で Kindle 変換成功（Error 0 / 画像系警告 0）・book-card 画像 inline 制約・sideimage figure 制約・表内数式 height≥1.0em・コードのテーブル化と空行 nbsp を確認。**v3 改訂（2026-06-18）**: (a) **数式 SVG は固有寸法を持たず、Kindle が em を無視すると 300px 既定で巨大表示される**ことが判明。`apply_math_px_fallback!` が em→px（×16）を `width`/`height` の HTML 属性として付与し、Kindle でも本文相当（単位記号 16px）に固定。(b) sideimage 系を 25%（text 3 : image 1）へ縮小（book-card 40% は据え置き）。(c) Tip/MEMO は `::before` ラベル（position:absolute）が Kindle で消えるため、`decorate_admonitions_for_epub!` が実体ラベル `<p class="vs-adm-label">【TIP】/【MEMO】</p>` を先頭注入し、`body.vs-epub .tip/.memo` に px 枠線を付与。(d) EPUB のコード表に出ていた行罫線・ゼブラ（`table.css` の全表ルール由来）を `body.vs-epub table.vs-code-epub` で打ち消し、外枠と番号｜コードの縦仕切りのみ残す。なおコード下の「黒い四角」は Kindle 標準のテーブル/図ズーム虫眼鏡バッジで機能上は無害（完全除去は任意対応）。再ビルドで Kindle 変換成功（Enhanced Typesetting: Supported / Error 0 / Quality 0）・数式 px 属性・sideimage 25%・ラベル注入を確認。**v4 改訂（2026-06-18）**: (a) **Kindle KFX は `var()` も解さず宣言ごと破棄する**ことが判明（`border: 0.2mm var(--x)` が消えて Tip/MEMO/COLUMN の枠が消失）。`.tip/.memo/.column` の border を「具体値(1px #888)を先に置き `border-width`/`border-color` を `var()` で上書き」する形へ変更し、**PDF/Apple Books は従来どおり 0.2mm・themed のまま Kindle だけ可視枠**にした。(b) 注入ラベル `.vs-adm-label` を `position:absolute; left:-9999px` とし、absolute 対応の Apple Books では画面外退避＝不可視（従来の `::before` バッジのみ表示）／absolute 非対応の Kindle では通常フロー表示、とすることで **EPUB(Apple Books) を完全に元のまま**に戻した（`::before` は消さない）。(c) COLUMN もラベル対象に追加（`ADMONITION_LABELS` に `column`）。(d) tip/memo 間のアキを本体既定（`margin-block: 8mm 6mm`）へ復帰。(e) 数式の本文連動サイズは外部 SVG を `<img>` 参照する方式の本質的限界（em→巨大/不安定、px→読者フォント拡大に非追従）のため、**px 固定で安定化しつつ既知の制限**とし、表内数式は運用回避を推奨（`$$` ディスプレイ数式は正常）。再ビルドで Kindle 変換成功（Error 0 / Quality 0）・tip/memo/column ラベル注入・border フォールバックを確認。
- [High] **EPUB の Kindle 変換不能（WebP 非対応）を解消＋不正ファイル名の事前検出**: `docs/specs/epub-kindle-webp-transcode-spec.md` に基づく。(§5-1) EPUB 経路でのみ `<img>` 参照の WebP を `images/_epub_assets/<hash>.{jpg,png}` へトランスコードして `src` を差し替える `EpubBuilder.transcode_webp_images_for_epub!` を新設（PDF 経路は WebP のまま不変）。劣化方針として、同名の元 png/jpg が残っていれば WebP を経由せず元から変換（二重劣化回避）、出力は透過/可逆=PNG・不透過写真=JPEG(q90)。staging 集約によりアポストロフィ等の問題ファイル名（W14010）も自動解消。(§5-3) `copyAsset.excludes` に `images/**/*.webp`・`stylesheets/**/*.webp` を追加して WebP を EPUB から全除外し、`sanitize_epub_css!` に `WEBP_URL_PATTERN`（`url(...webp)` 宣言）の除去を追加（参照切れ＝RSC-007/W14010 回避）。(§5-4) 著者が配置した画像のファイル名に壊れる文字（`( ) ' " & < > # ? % \ : * |` 等）が無いかを `vs build` / `vs preflight` 前に検出する `Guards::ImageFilenameCheck` を新設（images/・covers/・stylesheets/images/ を走査、改名案＋出現箇所を添えた警告のみ＝非ブロッキング、日本語名は許可）。あわせて `vs import`（Re:VIEW Starter 取り込み）でもファイル名を正規化し恒久防御化（`image_processor` の実体コピーと `markdown_converter` の参照 `convert_img_tags`/`normalize_image_paths` の双方に同一サニタイズを適用）。判定・除去基準は `ImageFilenameSanitizer` に一元化し、検出と取り込みで共有。`images/_epub_assets/` をクリーン対象に追加。テスト: ガード/トランスコードのユニット（OS 非依存）、`target_consistency_test` に「EPUB 内 WebP ゼロ・`<img>` 全解決」を追加、`rake test:kindle`（opt-in・Kindle Previewer 3 CLI で実変換し W14015/W14012/W14010 ゼロを検証）を新設。
- [High] **EPUB 生成パイプライン修正（epubcheck 構造 ERROR → 0 件達成）**: `docs/specs/epub-pipeline-fix-spec.md` に基づき Fix-1〜7 を実装し、最終検証で **FATAL 0 / ERROR 0 / WARNING 0**（全章 EP-01/EP-02 green・単章 0 件）・サイズ 322MB → 59MB を確認。(Fix-1) `vivliostyle.config.epub.js` に `copyAsset.excludes` を追加し、gem 雛形・仕様書・ページ画像など原稿外ファイルの EPUB 混入を停止（CSS-008×13 + RSC-007×2 解消）。(Fix-2) 生成後 EPUB 内 CSS から `@page` マージンボックスを物理除去する `EpubBuilder.sanitize_epub_css!` を新設（CSS-008×13 解消。PDF 用 CSS は不変）。(Fix-3) 段落内脚注 span の重複 id を EPUB 経路でのみ除去する `strip_inline_footnote_ids_for_epub!` を追加（RSC-005×4 解消。PDF 経路の footnote_converter は変更せず）。(Fix-4) 絵文字・囲み数字 `<img>` の非整数 `width="1em"`/`height="1em"` 属性を `style` へ統合（RSC-005×3 解消。表示は CSS と同値で不変）。実装後の再検証で findings 取りこぼしの 47 件を発見し（findings §7）、追補で解消 — (Fix-5) `MARGIN_BOX_PATTERN` に `@footnote` at-rule を追加（CSS-008×2 解消）。(Fix-6) VFM 由来のテーブル `align` 属性を EPUB 経路でのみ `style="text-align:…"` へ変換する `rewrite_table_align_for_epub!` を新設（RSC-005×35 解消。属性順序非依存で既存 style と統合）。(Fix-7) vivliostyle CLI が数字始まりファイル名から生成する content.opf の NCName 違反 id/idref に `id-` 接頭辞を付与する `sanitize_epub_opf_ids!` を新設（RSC-005×10 解消。全章・単章の両モードに適用）。単体テスト EPF-01〜08 を追加。調査記録は `docs/specs/epub-validation-findings.md`。
- [Medium] **テスト群が検出した残課題 3 件を解消**: (1) gs 不在時のビルド破壊を実行文脈の分離（pipeline はスキップ続行 / 単体 `vs pdf:compress` は 🔴 exit 1）で修正、(2) 無効入力（未知コマンド・オプション）の終了コードを POSIX 慣習の exit 1 へ変更、(3) マニュアルの旧コマンド表記（`vs cover:a4` 系・`vs index:build`）を現行 CLI へ追従（scaffold 同期）。あわせて DG-04（waifu2x → ImageMagick フォールバック）を実画像テストで有効化し、今回導入したテスト群の skip をゼロにした。
- [High] **catalog.yml の欠落原稿をフェイルファストで検出**: catalog.yml に記載があるのに contents/ に原稿がない状態で `vs build` すると、並列前処理スレッド内の `Errno::ENOENT` により長いスタックトレースが表示されていた。`UnifiedBuildPipeline#run` の冒頭で全エントリの実体ファイルを検証し、欠落ファイル一覧と対処方法（catalog.yml の該当行削除 / `vs delete` の利用）を表示して exit 1 で即終了するように改良（full / single / preflight の全ビルド経路に適用）。あわせて root と scaffold の catalog.yml に残っていた検証用エントリ（89-bugfix-check）を削除。
- [Low] **jpeg_to_pdf の PDF ヘッダ修正**: `'%PDF-1.4\n'`（シングルクォート）により `\n` が改行ではなく文字どおり出力され、ヘッダコメント行が最初のオブジェクト宣言を巻き込んでいた不具合を修正。
- [High] **sideimage 内の脚注URLの重複表示を修正**: 根本原因は Vivliostyle が、脚注参照リンク（`<a href="#fnN">`）の解決先が `aside.page-footnote`（`float: footnote`）自体になっている場合に、参照のあるページと `aside` のあるページの両方へ同じ脚注を描画することだった。通常の段落脚注は参照直後の不可視 `span#fnN`（`page-footnote-inline`）が解決先になるため無事だった。sideimage 経由の脚注にも同様の不可視 span を挿入し（`process_sideimage_footnotes!`）、`aside` を sideimage コンテナ直後に配置することで、重複が解消されると同時に、脚注が参照と同じページの下部に正しく表示されるようになった（`page-footnote-endnote` によるセクション末尾表示は廃止）。詳細は `docs/footnote.md` を参照。
- [High] **テーブル内リンクの脚注URLの重複表示を修正**: 原因は上記と同一。テーブルセル内の参照は `<p>` を持たないため不可視 span が挿入されず、参照リンクの解決先が `aside` 自体になり重複描画されていた。段落外参照（`insert_print_footnote_after_anchor!`）でも参照直後に不可視 span を挿入するように修正。あわせて、VFM 2.x がテーブルセル内から参照される脚注の**定義本文を入れ替えて出力する**不具合（参照IDの対応は正しいまま、別の脚注のURLが本文に入る）への対策として、参照直前の外部リンクURLと定義本文を照合して修復する `repair_table_footnote_definitions!` を追加（自動生成されたURL脚注のみ対象。手書きの脚注本文には触れない）。
- [High] **画像の配置（`align=left` / `align=center` / `align=right`）の乱れを修正**: `figure.align-left` / `figure.align-right` / `figure.align-center` に `clear: both` を追加し、配置指定付き図版が直前の float に巻き込まれないようにした。また `chapter-common.css` に残っていた旧 `.float-right` 互換ルール（`align-right` 図版へ `float` と `inline-size: 17em` を強制）を削除。左右配置のテキスト回り込みは従来どおり機能する。
- **RC 前のビルド成果物不具合 6 件を修正** (`docs/specs/build-output-bugfix-spec.md`):
  - **(②) `print_pdf` ターゲットで本文が欠落する**（titlepage/legalpage/colophon/colophon の 4 ページのみ）(`lib/vivlio_starter/cli/build/pipeline.rb`): `pdf + print_pdf` 併用フローでは Step 9（前付・奥付ビルド）が `entries.js` を奥付のみに上書きするため、Step 13 の入稿用本文ビルドが奥付を本文として出力していた。`print_pdf_build_sections!` が周囲の `entries.js` 状態に依存せず、本文用 `entries.js` を `generate_entries_for_sections!` で再生成してからビルドするよう修正。
  - **(⑤) 付録ラベルが誤る（91-install が「付録B」表示、本来「付録A」）** (`lib/vivlio_starter/cli/common.rb`): フルビルドでは `chapter_tokens_override` に本文章のみが渡り、付録抽出後に空配列となって `appendix_number_to_letter` が誤フォールバック（`('a'..'i')[n-90]`）に落ち 91→B になっていた。空 `entries` を「指定なし」として扱い catalog 全体から付録順を取り直すよう修正（91→A, 94→D）。
  - **(⑥) 付録内の図表番号が章番号になる（「表 94-1」、本来「表 D-1」）** (`lib/vivlio_starter/cli/pre_process/cross_reference_processor.rb`): 付録ファイル（90–98）の図表番号プレフィックスに付録レター（`appendix_letter_for`）を用いるよう `create_label`（採番）と `resolve_label`（auto-id 照合キー）を修正。見出し（付録 D）・節番号（D-1）と整合。本文章の挙動は不変。
  - **(③-b) EPUB に奥付（colophon）が含まれない** (`lib/vivlio_starter/cli/build/epub_builder.rb`): `collect_epub_htmls` の収録順末尾に `_colophon.html` を追加（PDF はカバー埋め込みのみで奥付を本文収録しないと EPUB に入らないため）。
  - **(③-c) EPUB の索引・用語集でページ番号（章連番）が併合されない** (`lib/vivlio_starter/cli/build/epub_builder.rb`): 同一章を指す連続リンク（`0, 0, 0, 1, 1, …`）を初出のみに併合する `dedup_sequential_number_links` を新設し、`rewrite_index_for_epub!` / `rewrite_glossary_for_epub!` に適用（`0, 1, …` に併合）。PDF のページ番号併合（Step 8）に相当する処理を EPUB の章連番へ文字列処理で実施。
  - **(①) frontispiece/ornament 画像の中間生成物が `bundled/` に残存** (`lib/vivlio_starter/cli/pre_process/image_generator.rb`, `clean.rb`, `copy_to_scaffold.rb`, `stylesheets/images/bundled/`, `lib/project_scaffold/stylesheets/images/bundled/`): 残存していた `*_alpha*.webp` / `*_color*.webp` / `*_merged*.webp`（旧実装が webp 中間を生成していた時代の git 追跡済み遺物）を root/scaffold から削除（scaffold の最終バリアント `sakura_portrait/landscape.webp` も生成物のため追跡解除）。再発防止として `generate_variant_output` の中間 PNG を `Dir.mktmpdir` に隔離し（例外中断時も自動削除され `bundled/` を汚さない）、WebP 変換を `convert_to_webp` に抽出。`clean_bundled_variant_images` と `copy_to_scaffold.rb` の除去パターンに中間生成物（webp/png）を保険として追加。
- **(④-B) サンプル原稿のテーブル内数式が生 LaTeX で露出する** (`contents/94-sample.md`, `lib/project_scaffold/contents/94-sample.md`): VFM は GFM テーブルセル内の `$...$` を数式 span 化しないため PDF・EPUB とも生 LaTeX（`$5.32 \times 10^{14}$`）が露出していた。表 94-1（光電効果のしきい周波数）のセルを Unicode 表記（`5.32 × 10¹⁴`）へ置換し、表構造とクロスリファレンス（「表 D-1」）を維持したまま回避。テーブルセル内数式の VFM 制約自体は当面許容（`build-output-bugfix-spec.md` ④-B）。
- **マニュアルの旧コマンド表記を現行 CLI へ追従**（ドキュメント整合テスト DC-01 で検出）(`contents/43-cover.md`, `contents/33-index-glossary.md`, `lib/project_scaffold/contents/` の同名ファイル): 43-cover.md が案内していたサブコマンド形式（`vs cover:a4` 等 5 箇所）を現行の位置引数形式（`vs cover a4` 等）へ修正。33-index-glossary.md の `vs index:build`（現行 CLI に存在しない）3 箇所を `vs build` へ修正（索引タグ付与・索引ページ生成はビルド時に自動実行されるため）。`contract/docs_allowlist.yml` の暫定許容エントリを削除し、DC-01 が今後の残骸を検出できる状態に復帰。
- **waifu2x 不在時の ImageMagick フォールバックをテストで保証**（DG-04 を有効化）(`test/vivlio_starter/robustness/tool_degradation_test.rb`): magick で生成した実画像を用い、waifu2x 不在でも 🟡 案内の上 frontispiece / ornament の portrait・landscape WebP が ImageMagick のみで生成完了することを検証。robustness / 契約テストの skip がゼロになった。
- **gs 不在時にビルド全体が落ちる問題を修正**（機能縮退テスト DG-03 で検出）(`lib/vivlio_starter/cli/pdf.rb`, `lib/vivlio_starter/cli/build/pdf_finalizer.rb`): `PdfCompressor` は gs 不在時に「圧縮をスキップします」と🟡警告しつつ `exit(1)` しており、`vs build`（compress 有効時）の Step 12 経由では **PDF 生成後にビルド全体が落ちる**矛盾があった。実行文脈で挙動を分離: ビルドパイプライン（`pipeline: true`）では gs 不在・圧縮失敗とも🟡案内 + スキップで続行（未圧縮 PDF のまま完走）、単体コマンド `vs pdf:compress` では利用者の明示要求のため🔴 + `vs doctor --fix` 案内 + exit 1 に統一。DG-03a/03b のテストを有効化。
- **テストスイート拡充で検出した実不具合 4 件を修正**:
  - **`vs open --help` / `vs pdf:read --help` が機能しない**（契約テスト CL-01 で検出）: 位置引数（`one :target`）を `options` より先に宣言していたため、Samovar が `--help` を PDF ファイル名 / 章トークンとして消費し、「PDFが見つかりません: --help.pdf」エラー（exit 1）になっていた。宣言順を入れ替えて修正（`open_command.rb`, `pdf_command.rb`）。
  - **`vs resize --help` が機能しない**（同上）: そもそも `-h/--help` オプションと `print_usage` が未実装で、`--help` が対象ディレクトリ名として解釈され「🔴 ディレクトリが存在しません: --help」になっていた。ヘルプ一式を追加（`resize_command.rb`）。
  - **不正バイト列の引数で CLI がクラッシュ**（ファズテスト FZ-03 で検出）: 非 UTF-8 端末からの引数（不正 UTF-8 バイト列・NUL 入り）で `TokenResolver` の正規表現・File 系 API が `ArgumentError` を送出していた。`resolve` 入口でサニタイズし、該当トークンは不一致として扱うよう修正（`token_resolver.rb`）。`ConfigSalvager` も同様に破損ファイル中の不正バイトで落ちないよう scrub を追加（FZ-01 で検出、`config_salvager.rb`）。
  - **NFD ファイル名の原稿が誤って「未登録」警告される**（NFD テスト NF-02 で検出）: macOS が濁点付きファイル名を NFD で保持する場合、catalog の NFC 表記と文字列比較で不一致になり `OrphanFileCheck` が誤警告していた。両辺を NFC 正規化して比較するよう修正（`orphan_file_check.rb`）。
- **パイプラインテストのスタブ漏れで本物のクリーン処理が実行されていた問題を修正** (`test/vivlio_starter/cli/build_pipeline_test.rb`): single mode のパイプラインテスト 3 件が末尾の `Step F (final clean)` → `run_final_clean` をスタブしておらず、フルスイート実行時には本物の `CleanCommands.execute_clean` がテスト実行ディレクトリで走り、単独ファイル実行時には `CleanCommands` 未ロードで `NameError` になっていた。`run_final_clean` のスタブを 3 箇所に追加し、実行順アサーションにも `stepF` を明示。テストの単独実行・フルスイートの両方で安全に通るようになった。
- **catalog.yml の欠落原稿をフェイルファストで検出** (`lib/vivlio_starter/cli/build/pipeline.rb`, `config/catalog.yml`, `lib/project_scaffold/config/catalog.yml`, `test/vivlio_starter/cli/build_pipeline_test.rb`): catalog.yml に記載があるのに contents/ に原稿ファイルが存在しない状態で `vs build` すると、並列前処理スレッド内の `Errno::ENOENT` により長いスタックトレースが表示され、著者を驚かせていた。`UnifiedBuildPipeline#run` の冒頭に `ensure_entry_files_exist!` を新設して全エントリの実体ファイルを検証し、欠落ファイル一覧と対処方法（catalog.yml の該当行削除 / `vs delete <章番号>` の利用）を🔴で表示して exit 1 で即終了するように改良（full / single / preflight の全ビルド経路に適用）。あわせて root と scaffold の catalog.yml に残っていた検証用エントリ（89-bugfix-check）を削除し、リグレッションテスト 2 件を追加。
- **標準フォントのファミリ名を実体フォント名に統一** (`stylesheets/page-settings.css`, `config/book.yml`, `lib/vivlio_starter/cli/font_manager.rb`, `contents/41-book-yml.md`, `contents/45-utility.md`, `lib/project_scaffold/` 配下の同名ファイル): Type 3 フォント対策で実体を Zen 系静的 TTF へ差し替えた後も、`@font-face` のファミリ名が "Noto Serif JP" / "Noto Sans JP" のままで book.yml の typography 設定と実体フォントが一致しない紛らわしい状態だった。`@font-face` のファミリ名・`:root` の CSS 変数デフォルト・book.yml の typography 設定・`FontManager::STANDARD_FONT_FAMILIES`・マニュアル原稿を "Zen Old Mincho" / "Zen Kaku Gothic New" へ一括統一（root と scaffold の両方）。CSS 変数とファミリ名を同時に変更しているため組版結果は従来と同一。
- **ログ出力の絵文字を🔴/🟡に統一** (`lib/vivlio_starter/cli/index/index_match_scanner.rb`, `doctor.rb`, `resize.rb`, `clean.rb`, `startup.rb`, `delete.rb`, `metrics/formatter.rb`, `build/chapter_config.rb`, `pre_process/data_render.rb`): ターミナルによって半角扱いされる⚠️と❌が残存していた。エラー出力は🔴・警告出力は🟡に統一し、`log_error` / `log_warn` を経由していない直接出力箇所もすべて修正。
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
