# Vivliostyle / リフロー EPUB の CSS 落とし穴と実装知見メモ

> 作成日: 2026-07-12
> ステータス: **知見メモ（恒久参照）**
> 対象: PDF（Vivliostyle）とリフロー EPUB（クリーン/Kindle）のレイアウト実装で 2026-07-12 に実測特定した「CSS は正しいのに効かない」型の落とし穴、その原因・修正・切り分け手順。
> 関連: `kindle-css-compatibility-notes.md`（KFX 側の癖はあちらが正典。本メモは **Vivliostyle エンジンと両フレーバ共通基盤**の癖を扱う）, `epub-code-line-numbers-spec.md`, `stylesheets/image-header.css`, `stylesheets/components.css`, `lib/vivlio_starter/cli/build/epub_builder.rb`, `lib/vivlio_starter/cli/build/heading_image_composer.rb`, `lib/vivlio_starter/cli/masking.rb`

---

## 0. 背景と目的

EPUB/Kindle/PDF の実機確認フィードバック（スクリーンショット 16 枚・§5 の対応表参照）を 1 日で 10 件超修正した過程で、原因が **CSS の書き方ではなくエンジン側・基盤側の癖**にあるケースが繰り返し出た。いずれも「修正 CSS を書く → ビルドしても 1px も変わらない」という迷路になりやすく、切り分けに時間を要した。本メモは症状から原因を即座に引けるよう、判明分を一箇所へ集約する。

各修正のコミット: `442dbf10`（行番号 F 案）→ `9f6a59ae`（keyfont・行番号二重・節絵サイズ）→ `a1388901`（Masking・はみ出し・折返し）→ `7e5ba9e3`（扉背景・扉分割）→ `78659c45`（PDF 節見出し折返し）。

---

## 1. 症状 → 原因 早見表

| 症状 | 真因 | 修正先 | 詳細 |
|---|---|---|---|
| PDF の扉背景が左上へ偏る（サイズは正しい） | Vivliostyle が `background-position` の **calc() 内 var() を宣言ごと破棄** → 初期値 0 0 | image-header.css＋book-settings 生成 | §2.1 |
| 見出しがどう直しても折り返さない | `base.css` の見出し共通 **`word-break: keep-all`** が CJK 文字間の折返しを全面禁止 | image-header.css（節題限定で解除） | §2.2 |
| Kindle でコード行番号が 2 列表示 | **Kindle の body は `vs-epub` と `vs-kindle` を両方持つ** → クリーン用 CSS カウンタが Kindle にも当たる | code.css（`:not(.vs-kindle)`） | §2.3 |
| EPUB で扉絵が幅狭／節絵が後続を覆いページで割れる | **PDF 用 `body.vs-header-image …` の特異度が EPUB リセットに勝つ**（150px グリッド行・inline-size clamp が EPUB にも適用） | components.css（`body.vs-epub` 重ね） | §2.4 |
| EPUB で SVG 見出し画像がレイアウト箱からはみ出す | **svg ルートに width/height 属性（intrinsic size）が無い**とリーダーが縦横比を誤る | heading_image_composer.rb | §2.5 |
| 手書き book-card が全ターゲットで崩れる（`**` 生残り） | **Masking がフェンス終端の改行ごと退避** → 閉じ `:::` がプレースホルダと同一行に癒着 → コンテナ変換が閉じを見失う | masking.rb | §2.6 |
| flex 内のテキストが縮まず箱を突き抜ける | flex アイテムの **`min-width: auto`** ＋ inline-flex の**匿名 flex アイテム**は `min-inline-size: 0` を外から与えても縮まない | image-header.css（タイトルをブロック化） | §2.7 |

---

## 2. 各論

### 2.1 `background-position` の calc()+var() は Vivliostyle が宣言ごと破棄する

- **症状**: `@page :nth(1)` の扉背景が左上（0 0）へ偏る。`background-size` は `calc()`+`var()` でも正しく効くため「サイズだけ正しく位置だけ壊れる」紛らわしい見た目になる（`pdf_chapter5.png`）。
- **実測**: `calc(50% + var(--x))` ＝落ちる／`calc(50% + 2mm)`（リテラル）＝効く／`center center` ＝効く。
- **修正の型**: 静的 CSS（image-header.css）には **var 不使用の既定値**（`center center`）を書き、可変値（綴じオフセット）は **book-settings.css 生成時にリテラルの `@page` 上書きとして焼き込む**（`BookSettingsCss.frontispiece_position_rule`）。`@page { size }` が var 不可でリテラル生成している前例と同型。

### 2.2 `base.css` の見出し共通 `word-break: keep-all` が CJK 折返しを全面禁止する

- **症状**: 長い節見出しが飾り帯と版面を突き抜ける（`pdf_section3-2.png`）。`white-space`・flex の縮小・幅上限をすべて正しく直しても**折り返されない**。
- **原因**: `base.css` の `h1..h6 { word-break: keep-all }`。keep-all は「単語を分割しない」ではなく **CJK 文字間の行分割機会も全部消す**。日本語見出しは実質折返し不能になる。
- **教訓**: 最小再現（素の Chromium／Vivliostyle 単体）に base.css を含め忘れると、「単体では折れるのにビルドでは折れない」という偽のエンジン差に見える。**折返し系の不具合ではまず `word-break` / `line-break` / `white-space` の継承を疑う**。
- **修正**: 折り返したい要素に限定して `word-break: normal` を戻す（`.section-topic h2 .section-title`）。`text-wrap: balance`（base.css 由来）は継承で生き、2 行時の行長が自動で揃う副産物がある。

### 2.3 EPUB の body は `vs-epub` と `vs-kindle` が同居する

- **症状**: Kindle でコード行番号が二重表示（`kindle_code.png`）。クリーン EPUB 用の CSS カウンタ（`body.vs-epub … ::before`）と Kindle 用の実テキスト注入が両方描かれる。
- **原因**: `vs-epub` は**両フレーバ共通の基底マーカー**で、Kindle の body にも付く（`mark_body_for_epub!` → `mark_body_for_kindle!` の追い掛け）。「vs-epub ＝クリーン限定」ではない。
- **修正の型**: クリーン限定にしたい規則は `body.vs-epub:not(.vs-kindle)` で書く。`:not()` を解さない KFX では規則ごと落ちるだけなので安全（Kindle 側は実体注入が担う）。

### 2.4 PDF 用 `body.vs-header-image …` は特異度で EPUB リセットに勝つ

- **症状**: クリーン EPUB で h1 扉絵が異常に幅狭（`epub_h1.png`）、節絵が 150px 固定グリッド行からはみ出して後続を覆い、ページ跨ぎで上下に割れる（`epub_h2_a/b.png`）、`h2::before` の背景飾りが合成 SVG と二重描画。
- **原因**: components.css の EPUB リセット（`h1.vs-image-heading-epub` 等）は特異度 (0,1,1) 程度で、PDF 用の `body.vs-header-image h1`（0,1,2）や `body.vs-header-image .section-topic h2`（0,2,2）に**負ける**。import 順では解決しない（特異度が先に効く）。
- **修正の型**: EPUB 上書きには **`body.vs-epub` を重ねて特異度を確保**する（`body.vs-epub .section-topic h2.vs-image-heading-epub` 等）。PDF には `vs-epub` が付かないため不発で無害。

### 2.5 合成 SVG を `<img>` で使うなら svg ルートに intrinsic size 必須

- **症状**: viewBox しか持たない SVG を `<img width:100%>` で置くと、一部リーダーがレイアウト箱と描画サイズを取り違え、はみ出し・ページ割れを誘発。
- **修正**: `svg_wrapper` が常に `width`/`height` 属性（=viewBox と同値）を出す。viewBox の `min-y` 指定で原画座標のまま帯を切り出せる（扉絵の上下分割 `FRONTISPIECE_SPLIT`）。

### 2.6 Masking のコード退避はフェンス終端の改行をプレースホルダの外に残す（修正済み）

- **症状**: `:::{.output}`（中身が ```フェンス）の**直後にある** `:::{.book-card}` が変換されず、`**タイトル**` が生のまま全ターゲットに出る（`epub_bookcard.png` / `kindle_bookcard.png`）。QueryStream 展開由来のカードは正常、という非対称も特徴。
- **原因**: 旧 `Masking.replace_fenced_blocks` がフェンス終端行の改行ごと退避し、退避中テキストで後続行が `__VS_CODE_SPAN__13__:::` のように**同一行へ癒着**。行頭 `:::` を前提とするコンテナ変換が `.output` の閉じを見失い、次の `:::` 行（= book-card の閉じ）までを中身として飲み込んで素通しした。
- **現在の保証**: 改行はプレースホルダの外に残る（往復同一性は不変）。**行頭アンカーの処理を退避中テキストに書くときはこの前提に依存してよい**（`masking_test.rb` の回帰テストで固定）。

### 2.7 flex のテキストは既定では縮まない（`min-width: auto`）

- **症状**: flex コンテナ内の長いテキストが折り返されず箱を突き抜ける。
- **原因**: flex アイテムの既定 `min-width: auto` は内容の最小幅より縮ませない。さらに **inline-flex の中のテキストは匿名 flex アイテム**になり、外から `min-inline-size: 0` を与える対象が存在しない。
- **修正の型**: テキストを折り返したい flex 子は `display: block` に戻して通常の行組へ＋`min-inline-size: 0`。箱側にも幅上限（`inline-size/max-inline-size: 100%` + `border-box`）を明示する（無上限だと箱自体が max-content 幅で版面を超える）。

---

## 3. 今回確立した実装パターン

| パターン | 実装箇所 | 用途 |
|---|---|---|
| **リテラル焼き込み @page 上書き** | `BookSettingsCss.frontispiece_position_rule` | var/calc を解さない @page 系プロパティへ設定値を渡す（size の前例と同型） |
| **扉絵の上下分割**（`FRONTISPIECE_SPLIT = 0.62`） | `HeadingImageComposer` + `inject_frontispiece_tail!` | EPUB で「見出し → リード文 → 裾飾り」の PDF と同じ読み順を再現。裾は文字なしで全章 1 枚を共用 |
| **節絵の均一サイズ＋2 行折返し**（`ORNAMENT_FONT_RATIO = 0.14` / `ORNAMENT_MAX_LINES = 2`） | `HeadingImageComposer.ornament_layout` | 節題の長短でフォントが暴れない。表示幅は半角 0.55 換算、Latin 語は空白で折る（`split_by_display_width`） |
| **keyfont の選択同梱** | `EpubBuilder.keyfont_asset?` + `strip_font_faces_except_keyfont` | フォント非埋め込み既定の中で、リーダーに代替が無い 1 書体だけ実体（TTF）＋対の @font-face を運ぶ |
| **Kindle 実体注入 ＋ クリーン CSS カウンタ** | `inject_code_line_numbers_for_kindle!` + `body.vs-epub:not(.vs-kindle)` | 同一 DOM 構造で両フレーバの行番号を排他に出す（§2.3 とセット） |

---

## 4. レイアウト不具合の切り分け手順（推奨ワークフロー）

1. **3 段比較**で層を特定する:
   (a) 素の Chromium（最小 HTML+CSS）→ (b) Vivliostyle 単体（`node_modules/.bin/vivliostyle build 最小.html`・約 10 秒）→ (c) 実ビルド（`vs build <章>`・約 25 秒）。
   - (a)=(b)≠(c) なら**他 CSS の干渉**（特に base.css の継承・特異度）。最小再現に base.css 相当を含めたか確認。
   - (a)≠(b) なら **Vivliostyle エンジンの癖**（§2.1 型）。プロパティを 1 個ずつリテラル化して犯人を特定。
2. **箱の可視化**: 対象要素に `outline: 1px solid red`（レイアウト不変）を一時注入してビルドすると、箱とはみ出しの実態が一目で分かる（`.section-topic h2` の全幅超え max-content 箱はこれで発見）。
3. **紙面の計測**: `pdftoppm -png -r 40 -f N -l N` でページをラスタ化し、修正前後を `magick compare -metric AE` でピクセル比較。「変わったはず」を思い込みで済ませない（リテラル焼き込みの等価性検証は AE=0 で確認した）。
4. **EPUB の中身確認**: `unzip` して XHTML/CSS を直接 grep する。リーダーの見た目より先にマークアップと同梱物を事実確認する。

---

## 5. 報告スクリーンショット対応表（確認用の作業ファイル・リポジトリ非同梱）

実機確認時のスクリーンショット名と症状・修正コミットの対応。画像自体は確認後に削除済みで、
症状の再現・詳細は各コミットメッセージと本メモ §2 を参照する。

| ファイル | 症状 | 修正コミット |
|---|---|---|
| `keyfont.png` | kbd キーキャップが素の等幅に落ちる | 9f6a59ae |
| `kindle_code.png` | Kindle コード行番号の二重表示 | 9f6a59ae |
| `kindle_h2_a/b.png` | 節絵見出しの大きさ不揃い（第 1 報） | 9f6a59ae |
| `kindle_h2_c/d/e.png` | c=極小 / d=過大 / e=ちょうどよい（基準 0.14h の根拠） | a1388901 |
| `epub_h2_a/b.png` | 節絵の後続覆い・ページ跨ぎ割れ・サイズ不揃い | a1388901 |
| `epub_bookcard.png` / `kindle_bookcard.png` | 手書き book-card 崩れ（`kindle_bookcard_physics.png` は正常な QueryStream 側） | a1388901 |
| `epub_h1.png` | h1 扉絵・リード文の幅狭 | a1388901 |
| `epub_chapter5.png` / `pdf_chapter5.png` | EPUB の読み順（リードがページ末尾へ）／PDF 扉背景の左上偏り | 7e5ba9e3 |
| `pdf_section3-2.png` | PDF 長節題の帯突き抜け | 78659c45 |
