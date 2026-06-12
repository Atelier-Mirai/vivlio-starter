# EPUB 生成パイプライン修正仕様書

> **目的**: EP-02（epubcheck 検証）で検出された 35 件の構造 ERROR をゼロにし、
> EPUB を RC 品質ゲートへ復帰させる。あわせて EPUB の異常な肥大（322MB）を解消する。
>
> - 起点: `docs/specs/epub-validation-findings.md`（調査記録。本仕様書はその findings を
>   実コード調査で検証・更新した最終版に基づく）
> - 関連テスト: `test/vivlio_starter/release/epub_validation_test.rb`（EP-01 / EP-02）
> - 作成日: 2026-06-13
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

```
vs build (targets: epub)
  Step 0〜5c: 前処理・HTML 変換（PDF と共通。共有 HTML が生成される）
  Step 6〜12: PDF 生成（pdf ターゲット時のみ）
  Step E (run_step_epub @ lib/vivlio_starter/cli/build/pipeline.rb:714):
    1. generate_epub_cover_if_needed
    2. EpubBuilder.generate_epub_entries!('.', entries)
         - collect_epub_htmls（_toc・裏表紙を除外した HTML リスト）
         - post_process_index_glossary_for_epub!  ← 共有 HTML を EPUB 用に直接書き換える既存フック
         - write_epub_entries（entries.epub.js）
         - ★Fix-3（脚注 id）・★Fix-4 の HTML 後処理はここに追加
    3. EpubBuilder.generate_epub_config!（vivliostyle.config.epub.js を生成）
         - ★Fix-1（copyAsset.excludes）はここに追加
    4. EpubCommands.execute_epub（vivliostyle build → output.epub → リネーム）
    5. stabilize_epub_identifier!  ← 生成後 .epub を unzip→修正→zip 差し替えする既存パターン
         - ★Fix-2（CSS サニタイズ）は同じパターンで直前に追加
    6. EpubBuilder.cleanup!
```

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

## 2. 修正項目（Fix-1〜4 が P1 = ERROR 35 → 0）

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
解決先制御。コミット 06760b8 の設計。**PDF 経路では変更禁止**）。
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

## 3. P2（ERROR ゼロ化とは独立。本仕様では実装しない。別途判断）

P1 完了後も EPUB は約 90MB（fonts 51MB + twemoji 31MB + images 8.4MB）残る見込み。

| 項目 | 内容 | リスク |
|---|---|---|
| P2-1 | `stylesheets/fonts/**` を excludes に追加し、theme/page-settings 内の `@font-face` を EPUB CSS サニタイズ（Fix-2 拡張）で除去 → リーダーフォントに委ねる | `@font-face` 除去漏れで RSC-007 再発。表示はリーダー依存になる（リフロー型では一般的） |
| P2-2 | twemoji の同梱を**使用分のみ**に絞る（HTML から参照される webp を抽出して includes/excludes を動的生成） | 実装が動的になり複雑。glob 動的生成より「不要側の除外」が安全 |
| P2-3 | EPUB 専用ミニマル CSS への全面切替（組版 CSS を持ち込まない） | 表示品質の全面再設計。工数大 |

P2-1/P2-2 は EP-02 とは独立にサイズ最適化として価値があるが、リフロー EPUB の
表示ポリシー（フォント埋め込みの是非）という製品判断を含むため、**著者（ユーザー）の
判断を仰いでから着手**すること。

---

## 4. テスト計画

### 4.1 単体テスト（rake test に追加。実ビルドなし）

新規 `test/vivlio_starter/build/epub_builder_sanitize_test.rb`（または既存の
epub 系テストファイルに追加）:

| ID | 検証内容 |
|---|---|
| EPF-01 | マージンボックス除去: `@page { size: A5; @bottom-center { content: counter(page); } }` → `@bottom-center` ブロックだけ消え `size:` が残る |
| EPF-02 | マージンボックス除去がネスト外の通常ルール（`.foo { margin-bottom: 1em; }` 等）を**壊さない**（`bottom-` を含むプロパティ名に誤マッチしないこと） |
| EPF-03 | 脚注 id 除去: `span.page-footnote-inline` の id だけが消え、`aside.page-footnote-print` の id と `data-footnote-number` は残る |
| EPF-04 | `build_img_tag` の出力に `width=` / `height=` 属性が無く、`style` に `width: 1em; height: 1em` が含まれる |
| EPF-05 | `generate_epub_config!` の生成物に `copyAsset` と `excludes` の各パターンが含まれる（文字列アサーション） |

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

| 順 | 作業 | 効果測定 |
|---|---|---|
| 1 | Fix-1（copyAsset） | EP-02 再実行 → ERROR 35 → 約 20 件（lib 由来 15 件解消）・サイズ激減 |
| 2 | Fix-4（絵文字属性。最小・独立） | ERROR −3 |
| 3 | Fix-3（脚注 id） | ERROR −4 |
| 4 | Fix-2（CSS サニタイズ） | ERROR −13 → **0 件** |
| 5 | §4.1 単体テスト + §4.3 非回帰 | rake test / test:manual green |
| 6 | CHANGELOG「既知の不具合」から削除し「実装済み」へ移記。findings に解消日を追記 | — |

各 Fix は独立しており、1 つずつコミットして EP-02 の ERROR 件数が単調減少することを
確認しながら進めること（途中で件数が**増えた**ら、その Fix が新たな参照切れ等を
生んでいるサイン）。

---

## 6. スコープ外（明示）

- P2（フォント・twemoji のサイズ最適化、EPUB 専用 CSS）— §3 のとおり別途判断
- epubcheck **WARNING** の棚卸し（現状 0 件。ERROR ゼロ化後に再確認し、出たら
  `release/allowed_warnings.yml` と同様の許容リスト方式を導入）
- `rake test:release` への EP-02 復帰判断（ERROR 0 達成後にユーザーが判断）
- footnote_converter / processor の重複コード共通化などのリファクタリング
- マニュアル（44-build / 61-developer）の EPUB 記述更新（本修正の完了後に別途実施予定）

---

## 7. 参照（実装時に読むべき箇所）

| ファイル | 何があるか |
|---|---|
| `lib/vivlio_starter/cli/build/epub_builder.rb` | Fix-1/3 の実装場所。`generate_epub_config!`（:68）・`generate_epub_entries!`（:46）・既存の EPUB 用 HTML 書き換え `rewrite_index_for_epub!`（:318） |
| `lib/vivlio_starter/cli/build/pipeline.rb:714-779` | `run_step_epub` と `stabilize_epub_identifier!`（unzip→修正→zip 差し替えの前例。Fix-2 はこの直前に呼ぶ） |
| `lib/vivlio_starter/cli/post_process/footnote_converter.rb:296-355` | 脚注の span/aside 同一 id 付与（**変更禁止**。EPUB 側で対処） |
| `lib/vivlio_starter/cli/techbook/emoji_replacer.rb:89-94` / `processor.rb:99,238,316` | Fix-4 の 3 箇所と、既存 CSS 指定 |
| `stylesheets/components.css:105-160` | 脚注の画面/印刷出し分け CSS（Fix-3 の判断根拠） |
| `node_modules/@vivliostyle/cli/dist/chunk-P33ELNYE.js` | `DEFAULT_ASSET_EXTENSIONS`（:218）・`copyWebPublicationAssets`（:2848）・`exportEpub`（:2095） |
| `docs/specs/epub-validation-findings.md` | エラー全件の分類と当時の推定（§0 の更新内容に注意） |
