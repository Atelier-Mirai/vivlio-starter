# `@` ディレクティブ Tier 1 実装仕様書

> 作成日: 2026-07-12
> ステータス: **確定仕様・未着手** — [at-directive-ideas.md](at-directive-ideas.md) の Tier 1（§2）を確定仕様へ昇格したもの
> 対象: `@pageref:id` / `@pagebreak:recto`・`:verso` / `@version`・`@today`・`@title` / `@qr:URL` / `@hspace:N` の 5 記法（7 ディレクティブ）
> 決定事項:
> - **2 トラック実装**（ideas §7 の方針どおり）: **参照系** `@pageref` は pre_process のクロスリファレンス基盤（`cross_reference_processor.rb`）へ、**定数・プラグマ系**（`@pagebreak`/`@version`/`@today`/`@title`/`@hspace`）は post_process の組み込み置換ルール（`replacement_rules.rb`・`@vspace` と同型）へ実装する。`@qr` のみ画像生成を伴うため pre_process の独立ステップ（数式 SVG と同じ「ビルド生成物」ファミリー）
> - **`@pageref` のページ番号は CSS `target-counter` で注入**（Vivliostyle ネイティブ・索引ページで実証済み → stylesheets/index.css:103）。ポスト処理での PDF 解析は行わない
> - **リフロー劣化は CSS カスケードで構造的に達成**する: EPUB リーダーは `target-counter` を解釈できず `content` 宣言ごと破棄・Kindle は `::after` 自体を無視 → **PDF だけに（p.N）が出て、EPUB/Kindle はタイトルリンクのみ**という理想の劣化が追加コードなしで成立する
> - **`@pagebreak:recto` の実装は `break-before: recto`**。ideas §2 の要検証メモ（「旧 `page-break-before` の方が確実」）の出所は contents/61-developer.md:392 で確認した——**Kindle KFX 限定の知見**であり Vivliostyle には該当しない。CSS は「`page-break-before: always`（フォールバック）→ `break-before: recto`（本命）」の 2 行重ねで PDF/EPUB 両対応する（§2.2）
> - **`@qr` の QR 生成は `rqrcode` gem**（pure Ruby・MIT・依存は rqrcode_core のみ）を runtime 依存に追加。本体の MIT-only ポリシー（CLAUDE.md）に適合
> 関連: `lib/vivlio_starter/cli/post_process/replacement_rules.rb:44`（`@vspace` の実装雛形・`ALL`:103・`apply_builtin!`:109）, `lib/vivlio_starter/cli/pre_process/cross_reference_processor.rb`（`RESERVED_MACRO_IDS`:37・`REFERENCE_PATTERN`:579・`render_link`:651・`build_href`:656）, `lib/vivlio_starter/cli/post_process/heading_processor.rb:95`（見出し id 保証）, `lib/vivlio_starter/cli/pre_process/math_transformer.rb`（ビルド生成画像の先行事例）, `stylesheets/index.css:94-108`（target-counter の実証コード）, `docs/specs/kindle-css-compatibility-notes.md`

## 0. 背景

`@nega`/`@posi`/`@comment`/`@commend` の廃止で `@` 記法は `@vspace` のみになった。ideas メモ（§1）の判断基準——「インラインの一点に効く」「Markdown/CSS では素直に書けない」——を満たす Tier 1 の 5 記法を追加する。

処理パイプライン上の位置（既存アーキテクチャの再確認）:

```
pre_process（Markdown・章ごと）      … @qr の画像生成をここに新設
pre_process（クロスリファレンス・全章一括）… @pageref・見出しラベルをここに追加
  ↓ VFM 変換（HTML 化）
post_process（HTML・章ごと）         … @pagebreak/@version/@today/@title/@hspace を
                                       ReplacementRules（@vspace の並び）に追加
  ↓ Vivliostyle → PDF ／ html/ ワークスペース → EPUB/Kindle
```

post_process 済みの HTML を PDF・EPUB・Kindle が共通に消費するため、**置換自体は全ターゲットに一度で効く**。ターゲット差は CSS 側（§2.2, §2.5）で吸収する。

## 1. 著者向け仕様

### 1.1 `@pageref:id` — ページ番号つき参照

```markdown
## インストール @install        ← 見出しに @id でラベルを付ける（新機能）

詳しくは @pageref:install を参照してください。
```

- **PDF**: 「詳しくは **「インストール」（p.200）** を参照してください。」（リンク付き・ページ番号は Vivliostyle が組版時に自動注入）
- **EPUB/Kindle**: 「詳しくは **「インストール」** を参照してください。」（ページ番号なしのリンク。リフローにページ概念がないため）
- 参照先は**見出しラベル**（上記の新記法）と**既存のキャプションラベル**（`** タイトル @id **` の図・表・リスト）の両方。キャプションラベルへの `@pageref:fig-3` は「図 3（p.45）」形式になる
- 見出しラベルの表示規則: 見出し（`#`〜`######`）行末の ` @id` はビルド時に除去され、紙面・目次・柱には**出ない**。同じ id を既存の `@id` 参照（`@install`）で参照した場合はページ番号なしの「「インストール」」リンクになる（`@pageref` との差はページ番号の有無のみ）
- 未定義 id は既存のクロスリファレンスと同じ 🔴「未定義のラベルID」（出現箇所つき）。`:id` を書き忘れた裸の `@pageref` は 🔴 で書式例を提示

### 1.2 `@pagebreak` / `@pagebreak:recto` / `@pagebreak:verso` — 改ページ・奇数/偶数ページ開始

```markdown
@pagebreak:recto

# 第II部 応用編
```

- `:recto`（右＝奇数ページ）／`:verso`（左＝偶数ページ）は次の内容をそのページ種別から開始する。必要なら空白ページが 1 枚自動で入る（印刷本の部扉・章の定番）
- **引数なしの裸 `@pagebreak` は単純改ページ**（`---` と等価）。`:recto` からの降格（「奇数開始でなくてよくなった」）が接尾辞の削除だけで済み、意図的な改ページであることが記法ファミリーとして残る。`---` も従来どおり有効（両記法は等価。使い分けは著者の好み）
  - 設計判断の記録: 「`:recto` の**書き忘れ**」と「裸の意図的使用」は判別不能だが、書き忘れの劣化は単純改ページ＝無害でゲラで即分かる。一方 `@pagebreak:rect` のような**コロン以降のタイポは引き続き 🔴 検出**する（§2.2）。ideas メモ §6 の「改ページ全般は `---` が受け皿」は、本項により「`---` または裸 `@pagebreak`」へ緩和
- **EPUB**: recto/verso は単純な改ページへ劣化（リフローに左右ページの概念がない）。**Kindle**: 同じく単純改ページ（`page-break-before: always`）

### 1.3 `@version` / `@today` / `@title` — ビルド時定数

```markdown
本書は v@version 時点の情報に基づきます（@today 更新）。
```

| 記法 | 展開値 | 出所 |
|---|---|---|
| `@version` | `1.0.0` | `book.yml` の `project.version` |
| `@title` | 書名 | `book.yml` の `book.main_title` |
| `@today` | `2026年7月12日` | ビルド実行日（形式固定・§5） |

- 単語境界で判定するため `@titlepage` のような続き文字には反応しない
- コードブロック・インラインコード内は展開しない（`@vspace` と同じ text_only 保護）

### 1.4 `@qr:URL` — QR コード画像

```markdown
サンプルコードはこちら: @qr:https://github.com/example/repo
```

- その場に QR コードの SVG 画像（既定 18mm 角・`class="vs-qr"`）を挿入する。インライン画像なので、行内に置けば文と並び、独立行に置けば単独表示になる
- URL は `https?://` 始まり・空白か `)` の手前まで。alt 属性に URL がそのまま入る（読み上げ・リンク切れ調査用）
- 同一 URL は全章で 1 ファイルに共有される（内容ハッシュ命名）
- 印刷で URL 文字列も併記したい場合は著者が隣に書く（自動併記はしない・§5）
- サイズ変更は `custom.css` で `.vs-qr { width: 25mm; }` のように上書き

### 1.5 `@hspace:N` — 水平アキ（`@vspace` の水平版）

```markdown
@hspace:2 ここから2文字分下がった行。
負値 @hspace:-0.5 も可。単位付き @hspace:10mm も可。
```

- 単位なしは **em（全角）**を既定とする（水平方向は文字数感覚が自然なため。`@vspace` の既定 mm とは意図的に非対称）
- 許容単位は `@vspace` と同一: `lh` `rem` `em` `mm` `cm` `pt` `px`

## 2. 実装

### 2.1 予約マクロ ID の拡張（最初に行う・全記法共通の前提）

`cross_reference_processor.rb:37`:

```ruby
RESERVED_MACRO_IDS = %w[vspace hspace pagebreak pageref version today title qr].freeze
```

- `ReferenceReplacer`（:579 の `REFERENCE_PATTERN` は `:` の手前まで、つまり `@pageref:install` からは `pageref` だけをマッチする）が、これらを「未定義ラベル」と誤警告せずに素通しし、後段（post_process）へ届ける
- **ラベル定義側のガード追加**: 著者がキャプション/見出しラベルとして予約語を使った場合（`** 図の題 @version **` 等）、`reserved_id?` を使って 🔴「'version' は予約語のため ラベルID に使えません（予約語: vspace, hspace, …）」を出す（`LabelCollector#add_label` に判定を追加）。従来この検査は無かったが、予約語が 8 個に増えるため必須

### 2.2 `@pagebreak` / `@hspace`（post_process・`@vspace` の並び）

`replacement_rules.rb` の `SPACING_MACRO_RULES`（:43）を拡張:

```ruby
SPACING_MACRO_RULES = [
  # 単位付きを先に（既存 @vspace と同じ理由）
  Rule.new(%r{@vspace:(-?[\d.]+(?:lh|rem|em|mm|cm|pt|px))}m, '<div style="margin-top:$1"></div>', :text_only),
  Rule.new(%r{@vspace:(-?[\d.]+)}m, '<div style="margin-top:$1mm"></div>', :text_only),
  Rule.new(%r{@hspace:(-?[\d.]+(?:lh|rem|em|mm|cm|pt|px))}m, '<span class="vs-hspace" style="margin-left:$1"></span>', :text_only),
  Rule.new(%r{@hspace:(-?[\d.]+)}m, '<span class="vs-hspace" style="margin-left:$1em"></span>', :text_only),
  # 引数付きを先に。裸形は「直後がコロンでない」の否定先読みが必須——
  # これが無いと不正引数（@pagebreak:left 等）の @pagebreak 部分だけが置換され
  # ":left" が紙面に残る（不正形は丸ごと素通しし、前処理の検知に委ねる）。
  Rule.new(%r{@pagebreak:(recto|verso)\b}m, '<div class="vs-break-$1"></div>', :text_only),
  Rule.new(%r{@pagebreak\b(?!:)}m, '<div class="vs-break-page"></div>', :text_only)
].freeze
```

CSS（`stylesheets/chapter-common.css` に追加。root のみ編集 → `copy_to_scaffold.rb` 同期）:

```css
/* @pagebreak / :recto / :verso（at-directive-tier1-spec §2.2）
   1 行目は EPUB リーダー・Kindle 向けフォールバック（recto/verso 非対応環境は単純改ページへ劣化）。
   2〜3 行目が本命で、両プロパティは同一プロパティの別名のため後勝ち＝ Vivliostyle は recto/verso を採る。
   recto/verso を解釈できないリーダーは 2〜3 行目の宣言だけを破棄し 1 行目が生きる。 */
.vs-break-page,
.vs-break-recto,
.vs-break-verso { page-break-before: always; }
.vs-break-recto { break-before: recto; }
.vs-break-verso { break-before: verso; }
```

- Kindle: `page-break-before: always` は KFX で確実に効く形（61-developer.md:392 の知見そのもの）。`body.vs-kindle` の個別ルールは不要（フォールバック行が既にリテラル値）
- **未知引数**（`@pagebreak:left` 等）は両ルールにマッチせず post_process まで残って紙面に生テキストが出てしまうため、**preflight/build の前処理で検知**する: `LinkImageValidator` の走査（または `MarkdownPreprocessor` 内の軽量チェック）に `/@pagebreak:(?!(?:recto|verso)\b)/`（プローズ行のみ・`Masking.each_prose_line`）の 🔴 を追加し、「引数は `:recto` / `:verso` です（引数なし `@pagebreak` は単純改ページ）」と案内する。裸 `@pagebreak` は正当な記法なので検知対象外

### 2.3 `@version` / `@today` / `@title`（post_process・実行時生成ルール）

値が CONFIG・ビルド時刻に依存するため、**frozen 定数 `ALL`（:103）には入れず**、適用時に組み立てる:

```ruby
# replacement_rules.rb（require に '../common' を追加）
# ビルド時定数マクロ。CONFIG 依存のため呼び出し時に組み立てる
# （frozen 定数にすると reload_configuration! 後に stale 値を差し込むため）。
def value_macro_rules
  [
    Rule.new(%r{@version\b}m, sanitize_value(Common::CONFIG.project.version), :text_only),
    Rule.new(%r{@title\b}m,   sanitize_value(Common::CONFIG.book.main_title), :text_only),
    Rule.new(%r{@today\b}m,   Time.now.strftime('%Y年%-m月%-d日'), :text_only)
  ]
end

# 置換エンジンは $1〜$9 を手動展開するため、値中の $ を無害化しつつ HTML エスケープする
def sanitize_value(v) = CGI.escapeHTML(v.to_s).gsub('$', '&#36;')

def apply_builtin!(html_file) = HtmlReplacer.process_html_file(html_file, ALL + value_macro_rules)
```

- `\b` により `@titlepage` 等の続き文字を除外（§1.3）
- `project.version`・`book.main_title` は既定値スキーマ登録済みキーのため `&.` ガード不要（config-extension-guidelines.md の正規パターン）
- `@today` はチャプター間で日付粒度なら実質同一。時分を含む形式は提供しないため厳密な同時刻性は不要（§5）

### 2.4 `@pageref:id` と見出しラベル（pre_process・クロスリファレンス基盤）

#### 2.4.1 見出しラベルの収集と変換

`cross_reference_processor.rb` に見出しラベルを追加する:

```ruby
HEADING_LABEL_PATTERN = /^(\#{1,6})\s+(.+?)\s+@([-\w]+)\s*$/
```

- **収集**（`LabelCollector#process_line`）: プローズ行（コード外・既存の `code_lines` 判定を流用）が上記にマッチしたら `Label.new(id:, type: :sec, chapter:, number: <表示章番号>, title: <見出しテキスト>, source_file:, line:)` を登録。id が `reserved_id?` なら 🔴（§2.1）。重複検査は既存機構（`build_labels_map_with_duplicates_check`）にそのまま乗る
- **変換**（`transform_all_chapters` に見出し変換を追加）: マッチ行を
  `## インストール <span id="install" class="vs-sec-anchor"></span>` へ書き換える（` @id` を除去し、**アンカー span を見出し内部**に置く）。見出し内部に置く理由: h2 は `break-before: page` のため、見出しの**前**の行にアンカーを置くと前ページ末尾に落ちてページ番号が 1 ずれる。見出し**内**なら構造的に同一ページ
  - **実装時の検証必須**: VFM が見出し内インライン HTML を保持すること・見出しスラッグ（自動 id）と TOC 抽出（`data-heading`・`extract_heading_core_text`）が空 span で汚れないことを、実ビルドで確認する。問題が出た場合の代替は「見出しの**直後**の行に `<span id="…"></span>` を置く」（h3 以下が改ページ直前に来た場合のみ 1 ページずれうる劣化を許容）
- `LABEL_TYPE_NAMES` に `sec: '節'` を追加（エラーメッセージ用。リンク文言には使わない——次項）

#### 2.4.2 参照の置換

`ReferenceReplacer#replace_refs`（:631）の**generic パターン適用前**に `@pageref:` を処理:

```ruby
PAGEREF_PATTERN = /@pageref:([\w-]+)/

def replace_refs(text, line_num)
  text = text.gsub(PAGEREF_PATTERN) { replace_pageref(Regexp.last_match(1), line_num) }
  # 裸の @pageref（:id なし）は 🔴 actionable（修正例: @pageref:install）を @errors に積み、素通し
  text.gsub(REFERENCE_PATTERN) { … 既存 … }
end
```

- `replace_pageref(id, line_num)`: labels_map を引き、
  - **hit**: `<a href="#{build_href(label)}" class="cross-ref-link pageref">#{link_text(label)}</a>`
  - **miss**: 既存と同文言の 🔴「未定義のラベルID: @pageref:xxx」＋素通し
- `link_text(label)`: `type == :sec` なら `「#{title}」`（かぎ括弧つき・ideas §5 の例示どおり）、それ以外（fig/table/list）は既存 `full_number`（「図 3」）
- **既存 `render_link`（:651）にも :sec 分岐を追加**: generic `@install` 参照が「要素 nil」ではなく `「インストール」` リンクになるように（`full_number` は :sec では使わない）
- href は既存 `build_href`（:656・`章basename.html#id` 形式）をそのまま使う——**索引ページの target-counter が同形式の cross-file href で動作している実績**（index.css:103）により、PDF のページ番号解決・EPUB のリンクとも既存機構で成立する

#### 2.4.3 CSS（ページ番号注入と劣化）

`stylesheets/chapter-common.css`:

```css
/* @pageref のページ番号（PDF のみ）。EPUB リーダーは target-counter を解釈できず
   content 宣言ごと破棄・Kindle は ::after 自体を無視するため、リフローでは
   自動的に「タイトルのみのリンク」へ劣化する（at-directive-tier1-spec §1.1） */
a.pageref::after {
  content: "（p." target-counter(attr(href url), page) "）";
}
```

### 2.5 `@qr:URL`（pre_process・独立ステップ）

`lib/vivlio_starter/cli/pre_process/qr_transformer.rb`（新規）:

```ruby
module VivlioStarter
  module CLI
    module PreProcessCommands
      # @qr:URL を QR コード SVG 画像（ビルド生成物）へ変換する。
      # 実体は BUILD_HTML_DIR/images/qr/ へ書き出し、参照は images/qr/…
      # （asset_prefix なし・数式 SVG＝math_transformer と同じ消費者 dir 相対形）。
      module QrTransformer
        QR_PATTERN = %r{@qr:(https?://[^\s)]+)}

        module_function

        def transform(content, chapter_basename)
          # Masking.each_prose_line 相当でコード外の行のみ処理し、
          # マッチごとに:
          #   1. hash = Digest::SHA1.hexdigest(url)[0, 12]
          #   2. dest = File.join(Common::BUILD_HTML_DIR, 'images', 'qr', "#{hash}.svg")
          #      未生成なら RQRCode::QRCode.new(url).as_svg(use_path: true, module_size: 4,
          #      viewbox: false) を書き出す（既存なら skip＝全章共有・冪等）
          #   3. 置換: %(<img class="vs-qr" src="images/qr/#{hash}.svg" alt="#{CGI.escapeHTML(url)}">)
          # rqrcode の例外（不正 URL 等）は 🔴（章:行・URL 併記）＋素通し
        end
      end
    end
  end
end
```

- **呼び出し位置**: `MarkdownPreprocessor#run` の `normalize_image_paths!` の**直後・`validate_links_and_images!` の前**。理由: (1) 変換後は HTML `<img>` になるため normalizer（Markdown 画像記法のみ書き換え）にも裸 URL 警告（LinkImageValidator）にも掛からない、(2) validate より前に変換しないと `@qr:` 内の URL が裸 URL として 🟡 誤警告される
- **SVG は width/height 属性つきで出力する**こと（`as_svg` 既定で付く。intrinsic size 無しの SVG は Vivliostyle/EPUB で寸法崩れする——vivliostyle-css-pitfalls-notes.md の既知の罠）
- **消費側は無改修**: `BUILD_HTML_DIR/images/` 配下は PDF ミラー（pdf_builder.rb:45）・EPUB/Kindle 同梱（epub_builder `localize_assets!`）が既に丸ごと拾う（querystream-data-images-spec §1.2 で確認済みの経路）。SVG のため Kindle WebP transcode も無関係。**Kindle での SVG 表示は数式 SVG で実績あり**
- CSS（chapter-common.css）: `.vs-qr { width: 18mm; vertical-align: middle; }`
- **gemspec**: `spec.add_dependency 'rqrcode', '~> 2.2'`（pure Ruby・MIT）。`Gemfile.lock` 更新・`rake reinstall`

### 2.6 直接ビルド（direct-build-spec）との整合

`@version`/`@title` は直接ビルドでは既定 CONFIG の値（basename・H1 由来）で展開される——仕様どおりの動作であり特別対応不要。`@pageref` は単章内ラベルのみ解決（他章参照は未定義エラー）で、これも既存単章ビルドと同じ制約。

## 3. テスト

Minitest・ruby-coding-rules skill 適用。

1. **`replacement_rules_test.rb`（既存スナップショット群に追加）**:
   - `@hspace:2` → `margin-left:2em` / `@hspace:10mm` → `10mm` / 負値 / `<code>` 内は非置換
   - `@pagebreak:recto`・`:verso` → 対応 div。裸 `@pagebreak` → `vs-break-page` div。`@pagebreak:left` は **`@pagebreak` 部分含め丸ごと**置換されない（否定先読みの回帰ゲート・前処理検知の対象・§2.2）
   - `value_macro_rules`: CONFIG スタブ（`Common.wrap_config` 経由・guidelines §3 の流儀）で `@version`/`@title` 展開、`@titlepage` 非反応、値に `$`/`<` を含む場合のエスケープ、`@today` が `\d{4}年\d{1,2}月\d{1,2}日` 形式
2. **`cross_reference_processor_test.rb`（既存に追加）**:
   - 見出しラベル: 収集（type :sec・title・章番号）／変換（` @id` 除去＋span 注入）／コードブロック内の `## … @id` 風の行は不処理
   - `@pageref:install` → `class="cross-ref-link pageref"`・href 形式・リンク文言 `「インストール」`／fig ラベル参照 → `図 N` 文言
   - generic `@install`（:sec）→ ページ番号なし `「インストール」` リンク
   - 未定義 `@pageref:zzz` 🔴／裸 `@pageref` 🔴（修正例を含む）／予約語をラベル定義に使うと 🔴
3. **`qr_transformer_test.rb`（新規）**: SVG が `BUILD_HTML_DIR/images/qr/<hash>.svg` に生まれ width/height 属性を持つ／同一 URL 2 回で 1 ファイル／`<img class="vs-qr">` 置換・alt=URL／コードブロック内 `@qr:` 不変換／不正入力で 🔴＋素通し
4. **結合（手動・`rake test` 対象外）**: 実プロジェクトに 5 記法を含むテスト章を置き `vs build`（PDF で p.N・recto 開始・QR 読取り実機確認）→ `vs epub`/`vs kindle`（pageref がタイトルのみ・pagebreak が単純改ページ・QR 表示。Kindle Previewer で確認）
5. **`epub_kindle_layout_test`**: pageref リンクにページ番号テキストが**含まれない**こと（::after は DOM 外なので HTML 検査では自明だが、劣化 CSS の回帰ゲートとして `a.pageref` の存在と本文リンク文言を固定）

## 4. 手順（実装順序）

1. §2.1 予約 ID 拡張＋ラベル定義ガード（全記法の前提・単独コミット可）
2. §2.2 `@hspace`/`@pagebreak`（ルール＋CSS＋裸 `@pagebreak` 検知）→ テスト 1
3. §2.3 `@version`/`@today`/`@title`（`value_macro_rules`）→ テスト 1
4. §2.4 見出しラベル＋`@pageref`（VFM 見出し内 span の実ビルド検証を最初に行い、NG なら直後行方式へ切替）＋ CSS → テスト 2
5. §2.5 `@qr`（gemspec 追加 → transformer → 配線）→ テスト 3
6. ドキュメント: `contents/22-extentions.md`（`@vspace` の節の並びに 5 記法を追記）・`contents/61-developer.md` の記法一覧 → `ruby copy_to_scaffold.rb`
7. `rake test` → §3-4 の実機確認 → at-directive-ideas.md の Tier 1 表へ「実装済み → 本仕様書」の注記、PLANNED/STATUS 更新

## 5. スコープ外・将来拡張

- **`@today` の書式指定**（`@today:%Y-%m-%d` 等）: 固定書式で開始。要望が出たら book.yml キー（`directives.today_format`）として追加（guidelines の 3 ステップ遵守）
- **`@qr` の URL 自動併記・サイズ引数**（`@qr:URL{width=25mm}`）: 併記は著者の文章に委ねる。サイズは custom.css で足りる
- **`@titleref`（タイトルのみ参照の明示形）**: 見出しラベルへの generic `@id` 参照がその役を兼ねるため新設しない（ideas §5 の「1 記法で両方出すか」への回答）
- **Tier 1.5/2**（`@nobr`・`@fill`・`@index`）: 本仕様の対象外。ideas メモに残置
- **`@pagebreak` の EPUB での見開き制御**（EPUB 3 の `page-spread` プロパティ等）: リフローでの recto/verso 再現は追わない（単純改ページ劣化で確定）
