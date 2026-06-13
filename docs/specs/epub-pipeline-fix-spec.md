# EPUB 生成パイプライン修正仕様書

> **目的**: EP-02（epubcheck 検証）で検出された構造 ERROR をゼロにし、
> EPUB を RC 品質ゲートへ復帰させる。あわせて EPUB の異常な肥大（322MB）を解消する。
>
> **進捗（2026-06-13 更新）**: **Fix-1〜7 すべて実装・検証済み。DoD 達成。**
> 当初検出の 35 件に対する Fix-1〜4 を実装後、実ビルド再検証で findings 取りこぼしの
> 別カテゴリ 47 件（全章。単章 39 件）が残存していることが判明（§2.5）。これに対する
> Fix-5〜7 も実装し、最終検証で **epubcheck FATAL 0 / ERROR 0 / WARNING 0**
> （全章 EP-01/EP-02 green・単章 0 件）を確認した。EPUB サイズは 322MB → 59MB。
>
> - 起点: `docs/specs/epub-validation-findings.md`（調査記録。残存 47 件の実測内訳は
>   その §7 に記録済み）
> - 関連テスト: `test/vivlio_starter/release/epub_validation_test.rb`（EP-01 / EP-02）
> - 作成日: 2026-06-13（同日、Fix-1〜4 実装後の再検証を受けて §2.5 を追補）
> - 検証環境: EPUBCheck v5.3.0 / @vivliostyle/cli 10.5.0（canary で 11.0.1 互換確認済み）

---

## 0. findings からの重要な更新（実装前に必ず読むこと）

仕様書作成時の追加調査で、findings の推定 2 件が**覆った**。

### 0.1 雛形 CSS 混入の根本原因は「生成器のパス参照」ではない

findings §2.1 は「特殊ページ生成器が gem 雛形 CSS パスを参照している」と推定したが、
**誤り**。EPUB を展開して全 xhtml を grep した結果、`lib/project_scaffold/...` を参照する
xhtml は **0 件**。真の原因は:

- `Build::EpubBuilder.generate_epub_config!` が生成する `vivliostyle.config.epub.js` に
  **`copyAsset` の指定が無い**。
- Vivliostyle CLI は EPUB 生成時、`copyWebPublicationAssets`（webpub 構築）で
  `getAssetMatcher` を使い、**CWD 以下の `**/*.{css,png,jpg,...}`（DEFAULT_ASSET_EXTENSIONS）を
  node_modules を除いて全部** webpub へコピーし、`exportEpub` が webpub ディレクトリを
  **丸ごと** `EPUB/` へコピーする（`node_modules/@vivliostyle/cli/dist/chunk-P33ELNYE.js` の
  `copyWebPublicationAssets` / `exportEpub`、`chunk-Q4EIXB5V.js` の `getAssetMatcher` で確認）。
- その結果、生成 EPUB（15,601 ファイル・322MB）には以下が混入していた:

| 混入物 | サイズ | 備考 |
|---|---:|---|
| `vivlio_starter_v1.0.0_images/` | 269MB | 過去に `vs pdf:pages` で生成したページ画像 |
| `lib/` (gem 雛形丸ごと) | 98MB | `project_scaffold` の CSS・PNG マスター等 |
| `stylesheets/` | 90MB | fonts 51MB + twemoji 31MB を含むディレクトリ全体 |
| `docs/` / `test/` / `covers/` | 約9MB | 原稿外ファイル |

→ **`copyAsset.excludes` の明示**（§2 Fix-1）で混入を止める。これにより
`lib/project_scaffold/...` 側の CSS-008（13件）と RSC-007（2件）が消え、
サイズも激減する。`copyAsset` は vivliostyle.config の正式スキーマ
（`config/schema.js` の `includes`/`excludes`/`includeFileExtensions` 等）で確認済み。

### 0.2 `@media print` で包む案（findings §3.1 案 B）は不成立

最小 EPUB を作成して実験した結果（2026-06-13、EPUBCheck v5.3.0）:

```css
/* どちらも ERROR(CSS-008) になる */
@page { @bottom-center { content: counter(page); } }                  /* 素のまま */
@media print { @page { @bottom-center { content: counter(page); } } } /* print で包んでも同じ */
```

epubcheck の CSS パーサは**マージンボックス構文そのもの**を拒否する（包んでも無駄）。
なお `@page { size: 182mm 257mm; }` だけなら ERROR にならない（マージンボックスのみが問題）。

→ EPUB に同梱される CSS からマージンボックスを**物理的に除去**する必要がある（§2 Fix-2）。

---

## 1. 現状フローと修正ポイントの全体図

行番号は Fix-1〜4 実装後の現行コード（2026-06-13）。✅ = 実装済み、★ = これから実装。

```
vs build (targets: epub)
  Step 0〜5c: 前処理・HTML 変換（PDF と共通。共有 HTML が生成される）
  Step 6〜12: PDF 生成（pdf ターゲット時のみ）
  Step E (run_step_epub @ lib/vivlio_starter/cli/build/pipeline.rb:717):
    1. generate_epub_cover_if_needed
    2. EpubBuilder.generate_epub_entries!('.', entries)   @ epub_builder.rb:53
         - collect_epub_htmls（_toc・裏表紙を除外した HTML リスト）
         - post_process_index_glossary_for_epub!     ← 共有 HTML を EPUB 用に直接書き換える既存フック
         - strip_inline_footnote_ids_for_epub!       ← ✅Fix-3 実装済み（epub_builder.rb:414）
         - ★Fix-6（align→style）の後処理はここに並べて追加
         - write_epub_entries（entries.epub.js）
    3. EpubBuilder.generate_epub_config!               @ epub_builder.rb:78
         - ✅Fix-1（copyAsset.excludes）実装済み（build_copy_asset_excludes_config）
    4. EpubCommands.execute_epub（vivliostyle build → output.epub → リネーム）
    5. EpubBuilder.sanitize_epub_css!                  ← ✅Fix-2 実装済み（epub_builder.rb:443、
         呼び出しは pipeline.rb:738。MARGIN_BOX_PATTERN は epub_builder.rb:43）
         - ★Fix-5 は MARGIN_BOX_PATTERN に @footnote を加えるだけ（メソッド変更不要）
    6. ★Fix-7（sanitize_epub_opf_ids!）はここ（5 と 7 の間）に新設
    7. stabilize_epub_identifier!                      @ pipeline.rb:750
         （unzip→修正→zip 差し替えの既存パターン。Fix-7 はこれと同型で実装）
    8. EpubBuilder.cleanup!
```

**単章モードへの展開**: 単章プレビュー `generate_single_mode_epub`（pipeline.rb:302）にも
同じ後段処理があり、`sanitize_epub_css!` は展開済み（pipeline.rb:323）。
**Fix-7 の `sanitize_epub_opf_ids!` も同じ位置に展開すること**
（Fix-5/6 は共通コードを通るため単章側の追加作業は不要）。

**設計上の重要事実**（実装者が前提にしてよいこと）:

- Step E は PDF 完成後に走るため、**共有 HTML の破壊的書き換えは PDF に影響しない**
  （既存 `rewrite_index_for_epub!` と同じ前提。再ビルド時は Step 0/3/5 で再生成される）。
- `stabilize_epub_identifier!`（pipeline.rb:745 付近）が「`unzip` で対象ファイルだけ取り出し
  → 修正 → `zip -q <epub> <entry>` で**当該エントリのみ差し替え**」する前例を確立している。
  この方式なら mimetype（無圧縮制約）に触れず、rubyzip 等の依存追加も不要。
- 画面メディア（= EPUB リーダー）での脚注表示は `stylesheets/components.css` で
  `span.page-footnote-inline { display: none !important; }`、`aside.page-footnote` は表示。
  つまり **EPUB で読者に見えるのは aside 側**。

---

## 2. 修正項目（Fix-1〜4：当初検出 35 件への対応。**実装・検証済み**）

> **注**: 本節の Fix-1〜4 はすべて実装済み（§5 の状態表参照）。当初は「Fix-1〜4 で
> ERROR 35 → 0」と見込んでいたが、findings の取りこぼし（§2.5）により 0 件には
> 届かなかった。本節は実装の経緯・設計判断の記録として残す。
> **これから実装する場合の対象は §2.5（Fix-5〜7）のみ。**

### Fix-1: copyAsset.excludes の明示（CSS-008×13 + RSC-007×2 を解消、サイズ激減）

**対象**: `lib/vivlio_starter/cli/build/epub_builder.rb` の `generate_epub_config!`

生成する `vivliostyle.config.epub.js` のオブジェクトに `copyAsset` を追加する:

```js
  copyAsset: {
    excludes: [
      'lib/**',            // gem 開発リポジトリ自身を書籍化する場合の雛形混入防止
      'docs/**',           // 仕様書類
      'test/**',           // テストコード・fixture
      'sources/**',        // 執筆資料（元 PDF 等）
      'codes/**',          // インクルード元コード（HTML へ展開済みのため実体は不要）
      'templates/**',      // QueryStream / create 雛形
      'data/**',           // QueryStream データ
      '.cache/**',         // ビルドキャッシュ
      '*_images/**',       // vs pdf:pages の出力ディレクトリ（<project>_images/）
      'covers/bundled/**', // gem 同梱 SVG テンプレート（EPUB には不要）
    ],
  },
```

実装メモ:

- Ruby 側は `config_content` のヒアドキュメントに静的文字列として埋め込めばよい
  （動的要素なし）。`cover_line` の近くに `copy_asset_lines` 的なローカル変数を切り出すと読みやすい。
- **`covers/**` 全体は除外しない**。EPUB 表紙は `cover: './covers/cover_<theme>.jpg'` として
  config に明示され webpub の resources 経由で同梱されるはずだが、アセット glob との
  二経路があるため、第一弾は `covers/bundled/**` のみ除外し、検証（§4）で
  cover.xhtml の表示と RSC-007 非増加を確認してから広げる。
- `stylesheets/fonts/**`・`stylesheets/twemoji/**` は **P1 では除外しない**（§3 P2 参照）。
  フォントを除外すると `@font-face` の src が未解決になり新たな RSC-007 を生む。
- 一般ユーザーのプロジェクト（`vs new` 生成）にも `sources/` `*_images/` 等の混入は
  起こるため、この修正は scaffold プロジェクト一般に有効。

**期待効果**: `EPUB/lib/...` 一掃 → 同パス由来の CSS-008 13 件 + RSC-007 2 件が解消。
ファイル数 15,601 → 数百、サイズ 322MB → 約 90MB（fonts/twemoji 残置のため）。

### Fix-2: 生成後 EPUB の CSS からマージンボックスを除去（CSS-008×13 を解消）

**対象（新設メソッド）**: `Build::EpubBuilder.sanitize_epub_css!(epub_path)` を新設し、
`pipeline.rb` の `run_step_epub` で `stabilize_epub_identifier!` の**直前**に呼ぶ。

**対象 CSS（プロジェクト本来側・Fix-1 適用後に EPUB に残るもの）**:
`EPUB/stylesheets/page-settings.css`（マージンボックス 7 箇所）/ `colophon.css`（2）/
`titlepage.css`（2）/ `part-title.css`（2）。

**処理内容**: `stabilize_epub_identifier!` と同型の unzip → 修正 → zip 差し替え。

```ruby
# 擬似コード（実装の骨子）
MARGIN_BOX_PATTERN = /@(?:top|bottom|left|right)-[a-z-]+\s*\{[^{}]*\}/

def sanitize_epub_css!(epub_path)
  abs_epub = File.expand_path(epub_path)
  Dir.mktmpdir('vs-epub-css') do |tmpdir|
    system('unzip', '-o', abs_epub, 'EPUB/stylesheets/*.css', '-d', tmpdir, ...)
    changed = Dir.glob(File.join(tmpdir, 'EPUB/stylesheets/*.css')).filter_map do |path|
      css = File.read(path, encoding: 'UTF-8')
      sanitized = css.gsub(MARGIN_BOX_PATTERN, '')
      next if sanitized == css
      File.write(path, sanitized)
      path
    end
    return if changed.empty?
    Dir.chdir(tmpdir) { system('zip', '-q', abs_epub, *changed.map { 相対パス化 }, ...) }
  end
end
```

実装メモ:

- マージンボックスは仕様上 1 段ネスト（`@bottom-center { content: ...; }`）なので
  `[^{}]*` の非貪欲マッチで安全に除去できる。**`@page` ブロック自体は残してよい**
  （`size:` 等のみの `@page` は epubcheck が許容することを実験で確認済み）。
- 除去後に `@page { }` が空になっても ERROR にはならないが、気になるなら
  `@page\s*\{\s*\}` も併せて除去してよい（任意）。
- `stylesheets/*.css` 固定ではなく `EPUB/**/*.css` を対象にすると、将来 CSS の配置が
  変わっても追従できる（推奨）。unzip のパターン指定は `'EPUB/*.css'` と
  `'EPUB/stylesheets/*.css'` 等複数指定か、いったん `-o abs_epub 'EPUB/**/*.css'` 相当の
  ワイルドカードで（unzip のグロブは `*` がパス区切りも跨ぐ点に注意して）取り出す。
- 失敗時は `stabilize_epub_identifier!` と同じく `rescue StandardError` で
  `Common.log_warn`（EPUB 自体は生成済みなのでビルドは落とさない）。

**なぜソース CSS を直さないのか**: `@page` マージンボックスは PDF のノンブル・柱の
実装そのものであり、ソースから消すと PDF が壊れる。CSS を PDF 用/EPUB 用に分離する案は
`@import` 連鎖の書き換えが必要になり影響が大きい（将来 P3 の検討事項）。
「PDF 用 CSS をそのまま同梱し、EPUB パッケージ内でのみ無害化する」のが最小・安全。

### Fix-3: 脚注 id 重複の解消（RSC-005×4 を解消）

**根本原因**: `lib/vivlio_starter/cli/post_process/footnote_converter.rb` は段落内脚注に対し

- `build_inline_footnote_node`（:331）→ `<span class="page-footnote page-footnote-inline" id="fnN">`
- `build_print_footnote_node`（:345）→ `<aside class="page-footnote page-footnote-print" id="fnN">`

と**同一 id を意図的に**付与している（PDF で Vivliostyle が脚注を二重描画しないための
解決先制御。コミット 61387fc の設計。**PDF 経路では変更禁止**）。
XHTML では同一文書内 id 重複は ERROR になる。

**修正（EPUB 経路のみ）**: `EpubBuilder` に HTML 後処理を新設し、
`generate_epub_entries!` 内の `post_process_index_glossary_for_epub!` と並べて呼ぶ。

```ruby
# 擬似コード: 各 EPUB 対象 HTML に対して
doc = Nokogiri::HTML(File.read(path))
doc.css('span.page-footnote-inline[id]').each { it.remove_attribute('id') }
File.write(path, doc.to_html)
```

設計判断の根拠:

- 画面メディアでは span は `display: none !important`（components.css:121）で**不可視**。
  id を外しても表示に影響しない。
- id を外すことで `<a href="#fnN">` の解決先が**表示されている aside 側に一意化**され、
  リーダーの脚注ジャンプも正しく機能する。
- span の削除ではなく id 除去に留める（「行を維持するために DOM は残す」という
  既存設計コメントを尊重し、差分を最小にする）。
- 共有 HTML の直接書き換えになるが、§1 の前提（Step E は PDF 完成後・再ビルドで再生成）
  により安全。既存の `rewrite_index_for_epub!` と同じ制約・同じ書き換えパターン。
- Nokogiri は footnote_converter が既に使用しており新規依存なし。ただし既存の
  `rewrite_*_for_epub!` は文字列 gsub 方式なので、合わせて gsub
  （`/(<span[^>]*page-footnote-inline[^>]*)\sid="[^"]*"/` → `\1`）で実装してもよい。
  **どちらでも可。確実に動く方を選び、単体テストで担保すること**（§4）。

### Fix-4: 絵文字 `<img>` の width/height 属性を style へ統合（RSC-005×3 を解消）

**根本原因**: HTML の `width`/`height` **属性**は整数（px）しか許容しないが、
techbook の絵文字画像化が `width="1em" height="1em"` を出力している。
**しかも CSS（`img.vs-emoji { width: 1em; height: 1em; ... }`、processor.rb:316）が
既に同じ指定を持つため、属性は完全に冗長**（表示は CSS が決めており、属性削除で見た目は不変）。

**対象（3 箇所、全ターゲット共通の修正でよい — HTML 仕様違反は PDF 経路でも同じ）**:

1. `lib/vivlio_starter/cli/techbook/emoji_replacer.rb:89-94` `build_img_tag`
2. `lib/vivlio_starter/cli/techbook/processor.rb:99`（丸数字）
3. `lib/vivlio_starter/cli/techbook/processor.rb:238`（丸数字・同型コード）

修正例（emoji_replacer.rb）:

```ruby
def build_img_tag(char, svg_path)
  %(<img src="#{svg_path}" alt="#{char}" ) +
    %(class="emoji vs-emoji" ) +
    %(style="width: 1em; height: 1em; vertical-align: -0.15em;">)
end
```

processor.rb の 2 箇所も同様に `width="1em" height="1em"` を属性から外し、
`style` に `width: 1em; height: 1em;` を統合する（インライン style に入れておけば
CSS 注入が無い文脈でも寸法が保証され、最も安全）。

注意: processor.rb の 99 行と 238 行は同一文字列の重複コード。**今回は属性修正のみ**を
行い、重複の共通化はスコープ外（ruby-coding-rules: バグ修正とリファクタを混ぜない）。

---

## 2.5 追加修正（Fix-5〜7：2026-06-13 実装後の再検証で判明）

Fix-1〜4 を実装し実ビルド（単章・全章）+ `epubcheck v5.3.0` で再検証したところ、
Fix-1〜4 は設計どおり機能した（lib 混入・RSC-007・脚注 id・絵文字 width・
`@bottom-*`/`@top-*` を解消）が、**§0 起点の findings が取りこぼしていた別カテゴリ**が
残り ERROR は 0 にならなかった（全章 47 件）。詳細は
`epub-validation-findings.md` §7。これらは Fix-1〜4 が生んだものではなく既存構造に由来する。
Fix-5〜7 はすべて **EPUB 専用の生成後パッケージ後処理**で、PDF 経路には一切影響しない。

### Fix-5: EPUB 内 CSS の `@footnote` at-rule 除去（CSS-008×2 を解消）

**対象**: `Build::EpubBuilder::MARGIN_BOX_PATTERN`（Fix-2 で新設した定数）。

`@footnote { … }` は Vivliostyle が `float: footnote` 要素を収めるマージン at-rule で、
`@bottom-center` 等と同様に epubcheck の CSS パーサが拒否する。Fix-2 の正規表現
（`@(top|bottom|left|right)-…`）が `@footnote` を含まないため残存した。

**処理内容**: `MARGIN_BOX_PATTERN` に `@footnote` を加える。`@footnote` の本体も
1 段ネスト（`{ list-style: none; … }`）なので `[^{}]*` で安全に除去できる。
Fix-2 の `sanitize_epub_css!` がそのまま処理するため、メソッド側の変更は不要。

```ruby
# 例: top/bottom/left/right-* に加えて @footnote も対象にする
MARGIN_BOX_PATTERN = /@(?:(?:top|bottom|left|right)-[a-z-]+|footnote)\s*\{[^{}]*\}/
```

### Fix-6: EPUB xhtml の `align` 属性を style へ変換（RSC-005×35 を解消）

**対象（新設メソッド）**: `Build::EpubBuilder.rewrite_table_align_for_epub!(html_files)` を
新設し、`generate_epub_entries!` 内で Fix-3 の `strip_inline_footnote_ids_for_epub!` と
並べて呼ぶ。

**根本原因**: VFM（Markdown → HTML）がテーブル列の整列（`|:--|`）を `<th align="left">` /
`<td align="right">` という**廃止済みプレゼンテーション属性**として出力する。XHTML5 では
`align` 属性は不許可で epubcheck が ERROR とする。PDF（Vivliostyle）は許容するため
顕在化していなかった。

**処理内容**: EPUB 対象 xhtml に対し、`th`/`td` の `align="x"` を `style="text-align:x"` へ
変換する（既存 style があれば `text-align` を前置）。Fix-3 と同じく EPUB 経路でのみ
共有 HTML を書き換える（Step E は PDF 完成後・再ビルドで再生成されるため安全）。

```ruby
# 擬似コード（gsub での骨子。align の値は left|center|right|justify のみ）
html.gsub(/(<t[hd]\b[^>]*?)\salign="(left|center|right|justify)"/) do
  tag, val = ::Regexp.last_match(1), ::Regexp.last_match(2)
  if tag =~ /\sstyle="/
    tag.sub(/\sstyle="/, %( style="text-align:#{val};))
  else
    %(#{tag} style="text-align:#{val}")
  end
end
```

実装メモ:
- `align` は table セル（`th`/`td`）のみを対象とする（`<img align>` 等の別文脈は現状の
  検出対象外。出たら別途）。値は VFM が出す `left`/`center`/`right` を想定（保険で
  `justify` も許容）。
- 表示は CSS の `text-align` で同値に保たれるため、EPUB リーダーでの見た目は不変。
- gsub 方式で十分（Fix-3 と同じ確実性・差分最小の方針）。単体テストで担保する（§4）。
- **属性順序の罠（必読）**: 上記擬似コードの捕捉 `(<t[hd]\b[^>]*?)` は align より**前**の
  属性しか含まない。`<td align="right" style="…">` のように style が align の**後ろ**に
  ある場合、捕捉した tag に style が無いと判定して `style="text-align:…"` を新設し、
  元の style が後ろに残って **style 属性が二重**になる（これ自体が新たな RSC-005）。
  VFM の現行出力は align 単独属性だが、堅牢にするなら「①align を除去 → ②同タグへ
  text-align を style に統合」の 2 段階で処理するか、タグ全体（`<t[hd]\b[^>]*>`）を
  マッチ単位にして内部で align/style を組み立て直すこと。EPF-07 で**属性順が前後両方**の
  ケースをテストして担保する。

### Fix-7: content.opf の数字始まり id/idref に接頭辞付与（RSC-005×10 を解消）

**対象（新設メソッド）**: `pipeline.rb` に `sanitize_epub_opf_ids!(epub_path)` を新設し、
`run_step_epub`（および単章 `generate_single_mode_epub`）で
`sanitize_epub_css!` と `stabilize_epub_identifier!` の間に呼ぶ。
※ `content.opf` を扱う既存後処理は `stabilize_epub_identifier!`（pipeline.rb）側にあるため、
EpubBuilder ではなく pipeline 側に置き、unzip/zip 差し替えパターンを踏襲する。

**根本原因**: vivliostyle CLI が manifest item の id を href から機械生成する際、
ファイル名が `00-preface` のように**数字始まり**だと生成 id `00-prefacexhtml` が NCName
（先頭は英字または `_`）に違反する。spine の `idref` も同値を参照するため idref 側も ERROR。

**処理内容**: 生成後 `content.opf` を unzip → 取得し、`<item id="...">` のうち**数字で
始まる id** に固定接頭辞（例 `id-`）を付け、対応する `<itemref idref="...">` も同じ規則で
書き換える（id↔idref の整合を必ず保つ）。`stabilize_epub_identifier!` と同型で zip 差し替え。

```ruby
# 擬似コード（id と idref を同一規則で前置。数字始まりのみ対象）
content = content.gsub(/\b(id|idref)="(\d[^"]*)"/) do
  %(#{::Regexp.last_match(1)}="id-#{::Regexp.last_match(2)}")
end
```

実装メモ:
- `id`/`idref` 属性のみを対象にし、`href`/`media-type` 等は触れない（値が数字始まりでも
  NCName 制約は id 系のみ）。`dc:identifier` 等メタの id（`bookid`）は数字始まりでないので
  影響しない。
- 接頭辞は決定的（`id-`）なので id↔idref の対応は機械的に保たれる。
- 失敗時は `rescue StandardError` で `log_warn`（EPUB は生成済みのためビルドは落とさない）。
- 単章モード（`generate_single_mode_epub`）にも同じ呼び出しを追加する（Fix-2 の
  `sanitize_epub_css!` を単章へ展開済みなのと同じ方針）。

### Fix-8: EPUB 絵文字のプレーン復元（P2-2 と一体。twemoji 非同梱で軽量化）

**対象（新設メソッド）**: `Build::EpubBuilder.restore_plain_emoji_for_epub!(html_files)` を
新設し、`generate_epub_entries!` 内で Fix-3/6 と並べて呼ぶ。

**背景**: techbook の絵文字画像化（`EmojiReplacer`）は Chromium が PDF で絵文字を
**Type 3 フォント化**する障害への対策で **PDF 専用**。EPUB はリフロー型で Type 3 が
存在せず、絵文字はリーダーのカラー絵文字フォントで描画されるため画像化は不要。むしろ
twemoji マスター（svg/webp 各 3,713・計約 11MB）を同梱して肥大化する（実使用は十数個）。

**処理内容**: EPUB 経路でのみ `<img class="… vs-emoji …">` を `alt` の元絵文字へ戻す。
`alt` に元の絵文字そのものが保持されているため可逆。`build_copy_asset_excludes_config`
で `stylesheets/twemoji/*.{svg,webp}` を除外（`*` はパス区切りを跨がないため
`vs-techbook/` は残る）。PDF は img のままで Type 3 回避を維持（共有 HTML 書き換えは
Step E = PDF 完成後のため安全）。

```ruby
EMOJI_IMG_PATTERN = /<img\b[^>]*\bclass="[^"]*\bvs-emoji\b[^"]*"[^>]*>/

html.gsub(EMOJI_IMG_PATTERN) do |tag|
  next tag if tag.include?('vs-circled-number') # 囲み数字は画像維持
  tag[/\salt="([^"]*)"/, 1] || tag
end
```

実装メモ:
- **囲み数字（vs-circled-number）は画像のまま残す**。`alt` が数字（"1"）で元の「①」字へ
  戻せず、アクセント色も失うため。vs-techbook（囲み数字・見出しマーカー）は同梱維持。
- 見出しマーカー・波ダッシュ置換（processor.rb の他の Type 3 対策）は EPUB でも実害が
  小さいため当面そのまま（必要なら別途）。

---

## 3. P2（サイズ最適化。2026-06-13 ユーザー判断のうえ実装済み）

ERROR 0 達成時点で EPUB は 59MB（fonts 51MB + twemoji + images）あった。ユーザー判断
（技術書は一般的な 明朝/ゴシック/等幅 で十分・フォント非埋め込みを既定とする）を受け、
P2-1（フォント）と P2-2（twemoji）を実装。**59MB → 25MB** に削減し ERROR 0 を維持した。

| 項目 | 内容 | 状態 |
|---|---|---|
| P2-1 | **フォント非埋め込み（既定）**: `embed_fonts?`（既定 false）が false のとき `stylesheets/fonts/**` を excludes に追加し、`sanitize_epub_css!` が EPUB 内 CSS から `@font-face` と `@import url("fonts/…")` を除去。リーダーのフォントに委ねる。css_updater が `--font-*` に generic フォールバック（明朝=serif/ゴシック=sans-serif/コード=monospace）を付与し category を保つ。**v2.0 で book.yml オプション化**し `embed_fonts?` を切替予定（埋め込み経路はコード上維持・テスト EPF-10 で担保）。 | ✅ 済（−51MB） |
| P2-2 | **twemoji 非同梱（Fix-8）**: 絵文字画像化は PDF の Type 3 障害対策で **EPUB には不要**（EPUB に Type 3 は無くリーダーのカラー絵文字で描画）。EPUB 経路で `restore_plain_emoji_for_epub!` が `<img class="…vs-emoji…">` を alt の元絵文字へ戻し、`stylesheets/twemoji/*.{svg,webp}`（マスター 7,000+）を excludes。囲み数字（vs-circled-number）は alt が数字・アクセント色付きのため画像維持（vs-techbook は同梱）。 | ✅ 済 |
| P2-3 | EPUB 専用ミニマル CSS への全面切替（組版 CSS を持ち込まない） | 未（表示品質の全面再設計。工数大。当面不要） |

---

## 4. テスト計画

### 4.1 単体テスト（rake test に追加。実ビルドなし）

テストファイルは **`test/vivlio_starter/cli/epub_builder_sanitize_test.rb`**（作成済み。
EPF-01〜05 は実装済みで green）。**EPF-06〜08 はこのファイルに追記**する。
EPF-01/02/06 用の「EPUB を模した zip を作って sanitize → 再展開して検証」ヘルパー
（`build_epub_with_css` / `read_css_from_epub`）が同ファイルにあるので再利用すること:

| ID | 検証内容 |
|---|---|
| EPF-01 | マージンボックス除去: `@page { size: A5; @bottom-center { content: counter(page); } }` → `@bottom-center` ブロックだけ消え `size:` が残る |
| EPF-02 | マージンボックス除去がネスト外の通常ルール（`.foo { margin-bottom: 1em; }` 等）を**壊さない**（`bottom-` を含むプロパティ名に誤マッチしないこと） |
| EPF-03 | 脚注 id 除去: `span.page-footnote-inline` の id だけが消え、`aside.page-footnote-print` の id と `data-footnote-number` は残る |
| EPF-04 | `build_img_tag` の出力に `width=` / `height=` 属性が無く、`style` に `width: 1em; height: 1em` が含まれる |
| EPF-05 | `generate_epub_config!` の生成物に `copyAsset` と `excludes` の各パターンが含まれる（文字列アサーション） |
| EPF-06 | （Fix-5）`@footnote { list-style: none; }` がサニタイズで除去され、通常ルールは残る |
| EPF-07 | （Fix-6）`<th align="left">` → `<th style="text-align:left">`。既存 style との統合は**属性順の両方**を検証: `<td style="…" align="right">`（style が前）と `<td align="right" style="…">`（style が後）のどちらでも style 属性が**1 つ**になり `text-align:right` を含むこと（§2.5 Fix-6「属性順序の罠」参照） |
| EPF-08 | （Fix-7）`content.opf` の数字始まり `id="00-prefacexhtml"` と対応 `idref` に `id-` 接頭辞が付き、`bookid` 等の英字始まり id は不変 |
| EPF-09 | （P2-1）非埋め込み時 `sanitize_epub_css!` が `@font-face` と `fonts/` への `@import` を除去し、通常の `font-family` 宣言は残す。`generate_epub_config!` の excludes に `stylesheets/fonts/**` が入る |
| EPF-10 | （P2-1）`embed_fonts?` を true にスタブすると `@font-face` を保持し `stylesheets/fonts/**` を除外しない（埋め込み経路が機能する） |
| EPF-11 | （Fix-8）`<img class="emoji vs-emoji" alt="✅">` が `✅` に復元され、`vs-circled-number` の img は画像のまま維持。config に `stylesheets/twemoji/*.{svg,webp}` 除外が入り `twemoji/**` 全除外はしない |
| CU-01〜05 | （css_updater）`format_font_value` が `--font-main-text`→serif / `--font-code`→monospace / ゴシック系→sans-serif を付与し、カンマ済み値は尊重・非 :font は不変（`test/.../pre_process/css_updater_test.rb`） |

### 4.2 結合検証（実ビルド。rake test:manual の EP）

```bash
ruby -Ilib -Itest test/vivlio_starter/release/epub_validation_test.rb
```

- **EP-01**: epub ビルド成功（従来どおり）
- **EP-02**: `FATAL` / `ERROR` が **0 件**（これが本仕様の DoD）

追加の手動確認（実装中のデバッグに有用）:

```bash
# 中身の確認（lib/ が消えたか・ファイル数・サイズ）
unzip -l vivlio_starter_v*.epub | tail -3
unzip -l vivlio_starter_v*.epub | grep -c "lib/project_scaffold"   # → 0 であること

# epubcheck 単体実行（件数の推移を見る）
epubcheck vivlio_starter_v*.epub 2>&1 | grep -cE "^(FATAL|ERROR)"
```

- 表紙確認: EPUB をリーダー（macOS ブック等）で開き、カバー画像・本文画像・
  絵文字画像が表示されること（Fix-1 の excludes が必要物を巻き込んでいないか）。

### 4.3 PDF 非回帰（必須）

Fix-3 は共有 HTML を書き換え、Fix-4 は PDF にも入る HTML 出力を変えるため:

```bash
rake test          # 高速ユニット（footnote_converter 既存テスト含む）
rake test:manual   # MB（警告ゼロ）+ FT（Type 3 なし）+ ID（冪等性）+ EP
```

- 特に **ID（冪等性）テスト**は build×2 の意味的同一性を比較するため、
  Fix-3 の「Step E で共有 HTML を書き換える」変更が PDF 側に影響しないことの
  良い検知器になる。
- 絵文字の見た目確認: techbook: true でビルドした PDF の絵文字寸法が従来どおりであること
  （CSS が同じ指定を持つため理論上不変だが、目視で 1 ページ確認しておく）。

---

## 5. 実装順序（推奨）

**Fix-1〜7 すべて実装・検証済み**（2026-06-13）。

| 順 | 作業 | 状態 / 効果測定 |
|---|---|---|
| 1 | Fix-1（copyAsset） | ✅ 済。lib 混入・RSC-007 解消・サイズ激減（322MB→約90MB） |
| 2 | Fix-4（絵文字属性。最小・独立） | ✅ 済。RSC-005（絵文字 width）−3 |
| 3 | Fix-3（脚注 id） | ✅ 済。RSC-005（脚注 id）−4 |
| 4 | Fix-2（CSS サニタイズ） | ✅ 済。CSS-008（`@bottom-*`/`@top-*`）解消 |
| — | （再検証）実ビルド単章/全章 + epubcheck | ✅ 済。残 ERROR 47 件＝findings 取りこぼし 3 カテゴリ（§2.5） |
| 5 | Fix-5（`@footnote` 除去） | ✅ 済。CSS-008 −2 |
| 6 | Fix-6（`align` → style） | ✅ 済。RSC-005（align）−35 |
| 7 | Fix-7（content.opf id NCName） | ✅ 済。RSC-005（NCName）−10 → **0 件達成** |
| 8 | §4.1 単体テスト（EPF-01〜08）+ §4.3 非回帰 | ✅ 済。rake test 1088 件 green・EP-01/EP-02 green |
| 9 | CHANGELOG・findings に解消日を追記 | ✅ 済 |

**最終検証結果（2026-06-13）**: 全章 `epubcheck` = **FATAL 0 / ERROR 0 / WARNING 0**、
単章（`vs build 11`）= 0 件。EPUB は 59MB・7,625 ファイル（混入解消後の残量は
fonts/twemoji。その削減は §3 P2 = 別途判断）。

経緯メモ: 当初「Fix-2 で 0 件」と見込んでいたが、findings が align（35）/
content.opf NCName（10）/ `@footnote`（2）を取りこぼしていたため、実際の 0 件達成には
Fix-5〜7 が必要だった（§2.5・findings §7）。

---

## 6. スコープ外（明示）

- P2（フォント・twemoji のサイズ最適化、EPUB 専用 CSS）— §3 のとおり別途判断
- epubcheck **WARNING** の棚卸し（現状 0 件。ERROR ゼロ化後に再確認し、出たら
  `release/allowed_warnings.yml` と同様の許容リスト方式を導入）
- ~~`rake test:release` への EP-02 復帰判断~~ → **2026-06-13 復帰済み**（ERROR 0 達成。
  EP-02 は `test:manual`→`test:release` に内包。findings §5/§7.4）
- footnote_converter / processor の重複コード共通化などのリファクタリング
- マニュアル（44-build / 61-developer）の EPUB 記述更新（本修正の完了後に別途実施予定）

---

## 7. 参照（実装時に読むべき箇所）

行番号は Fix-1〜4 実装後の現行コード（2026-06-13 時点）。

| ファイル | 何があるか |
|---|---|
| `lib/vivlio_starter/cli/build/epub_builder.rb` | Fix-1〜3/5/6 の実装場所。`MARGIN_BOX_PATTERN`（:43。**Fix-5 はここを変更**）・`generate_epub_entries!`（:53。**Fix-6 の呼び出しはここに追加**）・`generate_epub_config!`（:78）・`rewrite_index_for_epub!`（:361。gsub 書き換えの既存例）・`strip_inline_footnote_ids_for_epub!`（:414。**Fix-6 はこれと同型**）・`sanitize_epub_css!`（:443） |
| `lib/vivlio_starter/cli/build/pipeline.rb` | `generate_single_mode_epub`（:302。**Fix-7 はここにも展開**）・`run_step_epub`（:717）・`sanitize_epub_css!` 呼び出し（:323/:738。**Fix-7 の呼び出しはこの直後**）・`stabilize_epub_identifier!`（:750。**Fix-7 はこれと同型**の unzip→修正→zip 差し替え） |
| `test/vivlio_starter/cli/epub_builder_sanitize_test.rb` | EPF-01〜05 実装済み。**EPF-06〜08 はここに追記**。zip 往復ヘルパー `build_epub_with_css` / `read_css_from_epub` あり |
| `lib/vivlio_starter/cli/post_process/footnote_converter.rb:296-355` | 脚注の span/aside 同一 id 付与（**変更禁止**。EPUB 側で対処済み＝Fix-3） |
| `lib/vivlio_starter/cli/techbook/emoji_replacer.rb` / `processor.rb` | Fix-4 修正済みの 3 箇所と、既存 CSS 指定（`img.vs-emoji`） |
| `stylesheets/components.css:105-160` | 脚注の画面/印刷出し分け CSS（Fix-3 の判断根拠） |
| `stylesheets/page-settings.css:169-173` | `@footnote { … }` の実体（Fix-5 の対象。**ソースは変更しない**。EPUB パッケージ内でのみ除去） |
| `node_modules/@vivliostyle/cli/dist/chunk-P33ELNYE.js` | `DEFAULT_ASSET_EXTENSIONS`（:218）・`copyWebPublicationAssets`（:2848）・`exportEpub`（:2095） |
| `docs/specs/epub-validation-findings.md` | エラー全件の分類。**§7 に残存 47 件（Fix-5〜7 の対象）の実測内訳**（§0・§7 の更新内容に注意） |
