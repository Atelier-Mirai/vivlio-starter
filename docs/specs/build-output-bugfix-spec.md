# ビルド成果物の不具合 修正仕様書

> 作成日: 2026-06-14
> ステータス: **原因調査完了・修正方針提案（未実装）**
> 対象: RC 公開前に修正したい 3 件の不具合（CHANGELOG「既知の不具合」記載分）

CHANGELOG.md の「既知の不具合（Known Issues）」に記録した次の 3 件について、
コードを調査して原因を特定し、修正方針を整理する。実装は本仕様書の合意後に行う。

| # | 症状 | 重大度 | 根本原因の性質 |
| --- | --- | --- | --- |
| ① | `bundled/` に画像の中間生成物が残存 | 低（見た目・リポジトリ衛生） | 旧実装の遺物 + クリーン対象漏れ |
| ② | `print_pdf` ビルドで本文が欠落（4ページのみ） | **高（成果物が壊れる）** | `entries.js` の状態依存バグ |
| ③ | `epub` ビルドで扉絵・奥付・索引併合などが欠落 | 中〜高（EPUB 品質） | 複数の独立した設計ギャップ |
| ④ | 数式が描画されず生の LaTeX が露出 | 中（EPUB）／中（テーブルは PDF も） | EPUB は MathJax 未焼込／VFM はテーブル内数式を未処理 |
| ⑤ | 付録ラベルが誤り（91-install が「付録B」、本来「付録A」） | 中（PDF・EPUB 共通の表示誤り） | override の付録ゼロ件 → 誤フォールバック |
| ⑥ | 付録内の図表番号が章番号（表 94-1）になる、本来は付録レター（表 D-1） | 低〜中（PDF・EPUB 共通） | 採番が生章番号固定・付録レター未対応（⑤に依存） |

---

## ① bundled/ に画像中間生成物が残存する

### 症状

`stylesheets/images/bundled/` に、最終成果物ではない中間ファイルが残る。

```
asagao_landscape_alpha.webp        asagao_landscape_alpha_x2.webp
asagao_landscape_color_x2.webp     asagao_landscape_merged_x2.webp
sakura_landscape_alpha.webp        sakura_portrait_alpha.webp
sakura_portrait_alpha_x2.webp      sakura_portrait_color_x2.webp
```

### 原因調査

**(1) これらは「現行コードの生成物ではない」。** 現行の
`pre_process/image_generator.rb#generate_variant_output` が生成する中間ファイルは
**PNG**（`*_alpha.png` / `*_alpha_x2.png` / `*_color_x2.png` / `*_merged_x2.png`）であり、
WebP 変換後の末尾で確実に削除している（`image_generator.rb:292-294`）:

```ruby
return if keep_intermediate
[alpha_path, alpha_scaled_path, color_path, merged_path].compact.each { |path| FileUtils.rm_f(path) }
```

ディスクに残っているのは拡張子が **`.webp`** の中間ファイルであり、これは
**WebP 中間ファイルを生成していた旧実装の遺物**である。実際、これらは
`git ls-files` に現れる＝**コミット済み**で、ビルドのたびに作られているわけではない。
（最終バリアント `sakura_portrait.webp` / `sakura_landscape.webp` は git 追跡外で、
生成物として正しく扱われている。）

**(2) scaffold にも同じ遺物が混入している。** `lib/project_scaffold/stylesheets/images/bundled/`
にも同じ中間 WebP がコミットされており、加えて最終バリアント
（`sakura_portrait.webp` / `sakura_landscape.webp`）まで追跡されている。
`copy_to_scaffold.rb` の prune は `*_portrait.webp` / `*_landscape.webp` の 2 種のみを
除去するため、`*_alpha*` / `*_color*` / `*_merged*` は scaffold へ運ばれ続ける。

**(3) クリーンパターンが中間生成物を網羅していない。**
`clean.rb#clean_bundled_variant_images` の削除パターンは
`['*_portrait.webp', '*_landscape.webp']` の 2 種のみ（`clean.rb:244`）。
仮に中間ファイルが残っても掃除できない。

**(4) 現行コードにも残存し得る経路がある（軽微）。** `generate_variant_output` は
PNG 中間ファイルを **`base_dir`（= bundled/）に直接書き出してから削除**する方式のため、
waifu2x / ImageMagick が途中で失敗し例外が送出されると（`generate_frontispiece_and_ornament_from`
の `rescue` で捕捉）、削除前に処理が中断し PNG が残り得る。
（`generate_diagonal_variant` の上下分割 PNG は `Dir.mktmpdir` 内で完結しており安全。）

### 修正方針

1. **遺物の物理削除（最優先・確実）**
   - root と scaffold の両方から、中間 WebP を `git rm` する。
     ```
     stylesheets/images/bundled/{asagao_landscape,sakura_portrait,sakura_landscape}_*{alpha,color,merged}*.webp
     lib/project_scaffold/stylesheets/images/bundled/ 内の同名群
     ```
   - scaffold 側の最終バリアント `sakura_portrait.webp` / `sakura_landscape.webp` も
     生成物のため `git rm`（`copy_to_scaffold.rb` が今後 prune するので再混入しない）。

2. **再発防止：中間ファイルを tmpdir に隔離（コード修正）**
   - `generate_variant_output` の `alpha_path` / `alpha_scaled_path` / `color_path` /
     `merged_path` を `base_dir` ではなく **専用 tmpdir 配下**に作るよう変更する。
     こうすれば例外中断時も `Dir.mktmpdir` のブロック離脱で自動削除され、`bundled/` を汚さない。
   - スコープ: `image_generator.rb` の `generate_variant_output`（および
     呼び出し元 `generate_frontispiece_and_ornament_from` の tmpdir 受け渡し）のみ。

3. **クリーンの保険（任意）**
   - `clean_bundled_variant_images` のパターンに中間命名を追加し、万一の残存も掃除できるようにする:
     `*_alpha.webp` / `*_alpha_x2.webp` / `*_color_x2.webp` / `*_merged_x2.webp`
     および対応する `.png`。
   - ただし最終バリアント（`*_portrait.webp` / `*_landscape.webp`）と
     **元画像（`sakura.webp` 等）を誤削除しない**パターン設計に注意する。

### 影響範囲・リスク

- (1)(2) は純粋なファイル削除で挙動変更なし。リポジトリが軽くなる。
- (2) の tmpdir 化は出力結果に影響しない内部リファクタ。既存テストで回帰確認。
- 元画像（`sakura.webp` 等）を削除しないことを必ず確認する（パターンの取り違え防止）。

---

## ② print_pdf ビルドで本文が欠落する（最優先）

### 症状

`output.targets` に `print_pdf` を含めてビルドすると、生成 PDF が約 140kB・
**4 ページ（titlepage / legalpage / colophon / colophon）のみ**で、本文が一切出力されない。
アウトラインは付与されている。

### 原因調査（特定済み・症状と完全一致）

入稿用 PDF の本文ビルド `pipeline.rb#print_pdf_build_sections!`（Step 13）は、
**その時点の `entries.js` をそのまま使って** `vivliostyle build` する:

```ruby
def print_pdf_build_sections!
  PdfCommands.execute_print_pdf({}, '_sections_print.pdf')   # ← 現在の entries.js に依存
end
```

ところが、フルの `pdf + print_pdf`（+ `epub`）フロー
（`register_full_mode_steps` 冒頭の `if pdf_target? && print_pdf_target?` 分岐）では、
Step 13 に到達するまでに `entries.js` が **奥付だけに書き換えられている**。

経路を追うと:

1. Step 7 `PdfBuilder.build_overall_pdf_from_dir!` → `compile_overall_pdf!` が
   本文込みの `entries.js` を生成（`pdf_builder.rb:144`）。
2. Step 9 `run_step9_front_pages_and_tail` → `PdfBuilder.build_front_pages_and_tail!` が、
   前付・奥付 PDF を作るために `entries.js` を上書きする（`pdf_builder.rb:182, 192`）:
   ```ruby
   EntriesCommands.execute_entries({}, ['_titlepage.html', '_legalpage.html'])  # 上書き
   ...
   EntriesCommands.execute_entries({}, ['_colophon.html'])                       # さらに上書き
   ```
   → この時点で **`entries.js` = `['_colophon.html']` だけ**になる。
3. Step 13 `print_pdf_build_sections!` がこの `entries.js`（奥付のみ）で
   `_sections_print.pdf` をビルド → **本文ではなく奥付 1 ページ**が入る。
4. `print_pdf_merge!`（`pipeline.rb:631`）が結合する:
   `_titlepage_legalpage_print.pdf`（titlepage+legalpage = 2 ページ）
   ＋ `_sections_print.pdf`（**奥付**）
   ＋ `_colophon_print.pdf`（奥付）
   = **titlepage / legalpage / colophon / colophon の 4 ページ**。症状と一致する。

**なぜ `print_pdf` のみ指定では起きにくいか:** `register_print_pdf_only_steps_with_epub`
経路は Step 7 で `generate_entries_for_sections!`（本文 entries.js を生成）を呼び、
Step 9 は HTML 生成のみ（`run_step9_front_pages_html_only` は `execute_entries` を
呼ばない）で `entries.js` を壊さないため、本文 entries.js が Step 13 まで保たれる。
今回の症状は **`pdf` と `print_pdf` を併用する構成**で顕在化する。

### 修正方針

`print_pdf_build_sections!` を **周囲の `entries.js` 状態に依存しない自己完結処理**にする。
本文ビルドの直前に本文用 `entries.js` を生成してから `execute_print_pdf` する:

```ruby
def print_pdf_build_sections!
  Common.log_action('[Step 13] 本文 PDF をトンボ・塗り足し付きでビルドします…')
  # 直前の Step 9 等で entries.js が前付/奥付に書き換わっているため、本文 entries.js を再生成する
  Build::PdfBuilder.generate_entries_for_sections!('.', entries)
  PdfCommands.execute_print_pdf({}, '_sections_print.pdf')
end
```

- `generate_entries_for_sections!` は既存メソッド（前書き→目次→本文→付録→用語集→後書き→索引の
  順で本文 entries.js を生成）。`print_pdf` のみ経路の Step 7 と同一処理のため、両経路で一貫する。
- スコープ: `pipeline.rb#print_pdf_build_sections!` の 1 メソッドのみ。
- 単章入稿用（`print_pdf_build_sections_for_single!`）は別経路で entries.js を直前生成
  しているため対象外（要確認）。

### 影響範囲・テスト方針

- `pdf + print_pdf` 構成で `output_print.pdf` に本文が含まれることを実ビルドで確認。
- `print_pdf` 単独構成が引き続き正常であることを確認（退行防止）。
- `rake test:layout` / `rake test:manual` の入稿用 PDF 検査にページ数・本文有無の
  アサーションを追加することを検討（4 ページ問題を回帰検知できるように）。

---

## ③ epub ビルドの欠落（扉絵・奥付・索引併合・カバー）

EPUB は複数の独立した問題が重なっている。優先度順に整理する。

### ③-a 扉絵（frontispiece）・飾り（ornament）が表示されない

**原因:** 扉絵・飾りは `<img>` ではなく **CSS の背景画像**として描画されている。
`stylesheets/image-header.css:13-17`:

```css
background-image: var(--frontispiece-image);   /* url("images/sakura_portrait.webp") */
background-position: calc(50% + var(--frontispiece-binding-offset));
background-attachment: fixed;                  /* ← リフロー EPUB で未対応 */
background-size: var(--frontispiece-background-size);
```

`--frontispiece-image` は `css_updater.rb#update_theme_css` が
`url("images/…webp")` を埋め込む（`css_updater.rb:104-108`）。これは固定ページ寸法
（PDF）を前提にしたフルブリード背景であり、**リフロー型 EPUB では
`background-attachment: fixed` と固定寸法前提の背景がまず描画されない**
（EPUB リーダーに固定ビューポートがない）。結果、扉絵・飾りが消える。

**修正方針（設計判断を要する）:** リフロー EPUB で扉絵を出すには、背景画像ではなく
**インラインの `<img>`（または figure）として章冒頭に挿入**する EPUB 専用変換が要る。
EpubBuilder の HTML 後処理（`generate_epub_entries!` 内の各 `*_for_epub!` と同列）に
「frontispiece 背景を持つ章見出しブロックを検出し、対応する `<img src="images/…webp">`
を挿入する」処理を追加する案が有力。`copyAsset.excludes`（`epub_builder.rb:275`）は
`stylesheets/images` を除外していないため、画像実体は EPUB に同梱され得る（要確認）。
規模が大きいため、RC では「EPUB は扉絵なし（簡素表示）」と割り切る選択肢もある。

### ③-b 奥付（colophon）が EPUB に含まれない

**原因:** `epub_builder.rb#collect_epub_htmls`（`epub_builder.rb:168-216`）が組み立てる
収録順は **前書き → 本文(+中扉) → 付録 → 用語集 → 後書き → 索引** で、
**`_colophon.html` を含めていない**（タイトル/扉裏も同様に除外）。
表紙は `cover:` 設定で埋め込むが、奥付は本文 HTML として組み込む必要があるのに
収録対象から漏れている。

**修正方針:** `collect_epub_htmls` の末尾（索引の後ろ、書籍として自然な位置）に
`_colophon.html` を追加する。`_colophon.html` は pdf+epub 経路では Step 9
（`build_front_pages_and_tail!`）、epub 単独経路では `run_step9_front_pages_html_only`
で生成済みのため、存在前提でよい（存在チェック付きで `select { File.exist?(it) }`）。
スコープ: `collect_epub_htmls` の配列組み立てのみ。

### ③-c 索引・用語集の「同一ページ番号併合」が EPUB で未適用

**原因:** PDF では Step 8 `BacklinkDedupOrchestrator` がヘッドレスブラウザで実ページ番号を
取得し、**同一ページに落ちる重複リンクを併合**する（`_indexpage.html` / `_glossarypage.html`
を直接浄化）。一方 EPUB 経路の `rewrite_index_for_epub!` / `rewrite_glossary_for_epub!`
（`epub_builder.rb:411, 435`）は、空リンクに **章の連番**を差し込み ", " 区切りを足すだけで、
**連番が重複しても併合しない**。さらに:

- `epub` 単独経路（`register_epub_only_steps`）は Step 8 を**実行しない**
  （`pipeline.rb:709` のコメント: preview が必要なため除外）。
- `pdf + epub` 経路では Step 8 は走るが、それは **PDF のページ番号基準**の併合であり、
  EPUB の「章連番」基準では別の重複（同一章の複数語が同じ連番になる）が生じる。

結果、EPUB の索引は「3, 3, 3」のような重複番号が併合されずに並ぶ。

**修正方針:** `rewrite_index_for_epub!` / `rewrite_glossary_for_epub!` に、
連番差し込み後の**連続重複番号の併合**を追加する（同一 term の参照先が同じ連番なら 1 つに集約）。
EPUB の連番は章単位で確定するため、Step 8 のヘッドレス計測には依存せず、文字列処理で完結できる。
スコープ: EpubBuilder の該当 2 メソッドのみ（PDF 経路には影響しない）。

### ③-d 表紙画像が「一回り小さい」

**原因（仮説・要実機確認）:** EPUB カバーは `cover.rb` の `EPUB_SIZE = {width:1600, height:2560}`
（`cover.rb:52`、比 1:1.6）で生成される。本文 A4 は `2894x4091`（比 ≒1:1.414）。
アスペクト比が異なるため、リーダー表示で天地に合わせると左右に余白が出て「小さく」見える可能性。
これは欠陥というより**カバー比率とリーダー表示仕様**の問題で、③-a/b/c とは別レイヤー。

**修正方針:** RC 段階では「実機（複数リーダー）で表示確認し、必要なら `EPUB_SIZE` の比率
または余白を調整」程度に留め、本格対応は別タスク化を推奨。

### ③-e 分量が少ない（EPUB 137p vs PDF 374p）— 実測により「内容欠落なし」と確認

**調査（2026-06-14、生成済み成果物 `vivlio_starter_v1.0.0.epub` を展開して実測）:**

- **本文テキスト量はほぼ同等。** タグ除去後の文字数で
  **EPUB 207,748 字 / PDF 219,566 字（差 5.4%）**。
- **全章が EPUB に収録済み。** content.opf の spine に
  `cover → 00-preface → _part1 → 11〜13 → _part2 → 21〜25 → _part3 → 31〜33 →
  _part4 → 41〜45 → _part5 → 51 → _part6 → 61 → 91〜95 → _glossarypage →
  99-postface → _indexpage` が並び、本文 26 章＋部扉 6＋用語集＋索引が揃う。
  各章 XHTML も実サイズが大きく（例: 61-developer 136KB、44-build 94KB）、中身が伴う。
- **章内画像も同梱済み**（`images/11-workflow/workflow.webp`、
  `images/24-cross-reference/Einstein.webp` 等）。

→ **「分量が少ない」は内容欠落ではなく、リフロー型 EPUB のページ算出が
リーダー依存であることに起因する見かけ上の差**（固定 A4 の 374p とは直接比較できない）。
5.4% の差分は、EPUB に無い **目次（_toc）・タイトル/扉裏・奥付（③-b の欠落分）**の
テキスト、および PDF が 374 ページ分繰り返す**柱（ランニングヘッド）・ノンブル**で
ほぼ説明できる。

**結論:** ③-e は独立した不具合ではない。`collect_epub_htmls` の収録漏れも無い。
③-b（奥付）を直せば差分はさらに縮まる。**追加対応は不要**（③-a/③-b の対応に包含される）。

### ③ 全体の影響範囲・テスト方針

- 修正は EpubBuilder 内に閉じ、**PDF 経路へ副作用を出さない**ことを原則とする
  （EPUB 専用 HTML 後処理は Step E = PDF 完成後に走るため安全）。
- `rake test:manual` の EPUB 検査（epubcheck・収録ファイル一覧）に、
  `_colophon.html` の同梱と索引重複番号の不在をアサートする項目を追加検討。

---

## ④ 数式が描画されず生の LaTeX が露出する

### 症状

EPUB の「光電効果」節（`94-sample`）で、数式が組版されず
`$5.32 \times 10^{14}$` のような生の LaTeX 文字列がそのまま表示される。

### 原因調査（実測）

数式の扱いには **2 系統**あり、別々の原因を持つ。

**(A) 段落・ブロック数式（`$...$` / `$$...$$`、テーブル外）— EPUB のみ未描画**

VFM は MathML を生成せず、生の LaTeX を **Vivliostyle の MathJax がレンダリング時に
組版するためのマーカー付き span** に変換する。生成 EPUB の `94-sample.xhtml` 実測:

```html
<span class="math inline" data-math-typeset="true">\(E=mc^2\)</span>
<span class="math display" data-math-typeset="true">$$
\nu_0 = \frac{\phi}{h}
$$</span>
```

- **PDF**: Vivliostyle CLI が内蔵 MathJax で `data-math-typeset` を組版する。
  `pdftotext` で `ν`・`ϕ`・`h = 6.626 × 10⁻³⁴` と描画されていることを確認。
- **EPUB**: `vivliostyle build --format epub` は MathJax の組版結果を XHTML に
  焼き込まない。`data-math-typeset` span が生の `\(...\)` / `$$...$$` のまま残り、
  EPUB リーダーは MathJax を実行しないため LaTeX がそのまま見える
  （生成 EPUB に `<math>` タグは 0 件）。

**(B) テーブルセル内の数式（`| … | $…$ |`）— PDF・EPUB ともに未描画**

GFM テーブルのセル内 `$...$` は、VFM が **数式 span で包まない**（マーカーが付かない）。
このため `data-math-typeset` も付かず、PDF の MathJax も対象にできず、
**PDF でも生の `$5.32 \times 10^{14}$` のまま**であることを `pdftotext` で確認
（表 94-1 のセル）。これは EPUB 固有ではなく VFM のテーブル内数式未対応に起因する。

### 修正方針

- **(A) EPUB 向け数式の事前組版**: EpubBuilder の HTML 後処理
  （`generate_epub_entries!` 内の `*_for_epub!` と同列）に、
  `data-math-typeset` span の `\(...\)` / `$$...$$` を **MathML へ変換して埋め込む**
  ステップを追加する。MathML は EPUB3 リーダーが描画できる。
  変換器は KaTeX（`renderToString` の MathML 出力）や MathJax の Node API、
  または `temml` 等の LaTeX→MathML ライブラリを Node 側で利用する案。
  既存の EPUB 専用後処理が「PDF 完成後に共有 HTML を直接書き換える」方式のため、
  同方式で PDF へ副作用を出さずに実装できる。
- **(B) テーブル内数式**: VFM の制約。**当面は許容する（2026-06-14 決定）。**
  サンプル原稿（表 94-1）はテーブルをやめて**箇条書き等に置き換え**れば数式露出を
  回避でき、本体コードに手を入れずに済む。RC ではこの方針を採る。
  恒久対応するなら、前処理（`pre_process`）で**テーブルセル内 `$...$` を検出して
  数式 span 相当へ展開**する変換を追加する（PDF・EPUB 双方に効く。規模は中）が、
  別タスクとする。あわせて「テーブルセル内では数式を避ける」をドキュメント明記する。

### 影響範囲・優先度

- (A) は EPUB 品質に直結。RC で対応する価値が高いが、Node 側の数式変換導入を伴うため
  規模は中。最小実装として「インライン `\(...\)` と ディスプレイ `$$...$$` の MathML 化」に絞る。
- (B) は PDF にも影響する既存仕様の穴だが、サンプル原稿（表 94-1）固有色が強い。
  RC ではドキュメント明記＋サンプル原稿の表現見直しで回避し、恒久対応は別タスク化を推奨。

---

## ⑤ 付録ラベルの誤り（91-install が「付録B」になる）

### 症状

付録の最若番号 `91-install` の見出しが **「付録 B」**と表示される
（PDF・EPUB 共通）。本来、付録 90–98 のうち最も若い番号が「付録 A」であるべき。

### 原因調査（特定済み・実機の生成物で確認）

採番は `post_process/heading_processor.rb#resolve_appendix_letter` →
`Common#appendix_number_to_letter`（`common.rb:495`）で行う。
`appendix_number_to_letter(91)` を **単体評価すると "a"（正しい）** を返すのに、
生成 EPUB の `91-install.xhtml` は「付録 B」。**ビルド時のみフォールバック経路**が走っている。

連鎖は次のとおり:

1. `build/section_builder.rb:164-165`（`convert_sections_html!`）が、
   本文表示順キャッシュ（`@main_chapter_order`）を確定させる目的で
   **本文章のみ（1–89）**を override に設定する:
   ```ruby
   main_tokens = targets.select { |t| t.match?(/\A\d{2}-/) && t[/\A(\d{2})/, 1].to_i.between?(1, 89) }
   PostProcessCommands::HeadingProcessor.chapter_tokens_override = main_tokens unless main_tokens.empty?
   ```
   → override に **付録（90–98）が一切含まれない**。
2. 付録見出しの処理時、`resolve_appendix_letter`（`heading_processor.rb:353`）は
   override が非空のため override 分岐に入り、override から付録 Entry を抽出する:
   ```ruby
   entries = override.filter_map { |t| e = resolver.resolve_file(t); e if e&.kind == :appendix }
   # → 本文のみの override なので entries == []（空）
   Common.appendix_number_to_letter(chapter_number_i, entries: entries)  # entries: []
   ```
3. `appendix_number_to_letter` は **空配列 `[]` を「真」**として受け取り、
   渡された（空の）entries を使う。index 探索は失敗（nil）し、フォールバックへ:
   ```ruby
   appendix_entries = if entries            # [] は truthy → 空のまま採用
                        entries.select { it.kind == :appendix }.sort_by { it.number.to_i }
                      else
                        resolver.resolve.select { it.kind == :appendix }...
                      end
   index = appendix_entries.index { it.number.to_i == n }   # nil
   return ('a'..'i').to_a[index] if index                    # skip
   ('a'..'i').to_a[n - 90]                                    # 91-90=1 → 'b' → 「付録 B」
   ```
4. フォールバック `('a'..'i').to_a[n - 90]` は **付録が 90 始まり**と仮定しており、
   90 から始まらない（最若が 91 の）構成では番号がずれる（91→B）。

`appendix_number_to_letter(91)` 単体が "a" を返したのは、`entries: nil` 経由で
catalog 全体を resolve（[91..95]）→ index 0 → "a" となるため。
ビルド経路は `entries: []` を渡すため fallback に落ちる、という差。

### 修正方針

**主因の単点修正（推奨）**: `appendix_number_to_letter` で
**空 entries を「指定なし」とみなし全体 resolve にフォールバック**させる:

```ruby
appendix_entries = if entries && !entries.empty?
                     entries.select { it.kind == :appendix }.sort_by { it.number.to_i }
                   else
                     resolver = TokenResolver::Resolver.new
                     resolver.resolve.select { it.kind == :appendix }.sort_by { it.number.to_i }
                   end
```

これで full build（override=本文のみ → entries=[]）でも catalog 全体から
付録順を取り直し、91→index 0→A になる。単章付録ビルドの override（付録を含む）経路は不変。

**保険（任意・別修正）**: 末尾フォールバック `('a'..'i').to_a[n - 90]` は
「付録 90 始まり」前提で潜在的に不正確。`resolve` 由来の付録集合の中での
**相対位置**で算出するか、フォールバック自体を見直すと堅牢になる。
（ただし主因修正で full build は解決するため、優先度は低い。）

### 影響範囲・テスト方針

- 修正は `common.rb#appendix_number_to_letter` の判定 1 箇所。PDF・EPUB 双方に効く。
- 単体テスト: 付録 [91,92,93,94,95] で `91→A, 92→B, …`。
  `entries: []`（空）でも全体 resolve にフォールバックして 91→A となること。
- `section_builder` の override（本文のみ）設定は `@main_chapter_order` 用途として残す
  （スコープ外の挙動を変えない）。

---

## ⑥ 付録内の図表番号が章番号になる（表 94-1 → 表 D-1 にすべき）

### 症状

付録 `94-sample` の表キャプションが **「表 94-1」**（生の章番号 94）。
付録の見出しは「付録 X」、節番号は「X-1」と**付録レター**で振られるのに、
図表番号だけが章番号のまま。見出しと整合させ **「表 D-1」**（⑤ 修正後の 94-sample = 付録D）
とすべき。

### 原因調査

図表番号は `pre_process/cross_reference_processor.rb` が採番する。
`create_label`（`cross_reference_processor.rb:192-196`）が番号を組み立てる:

```ruby
label_id = info[:auto] ? "#{type}-#{@chapter_number}-#{count}" : info[:id]
Label.new(label_id, type, @chapter_number, "#{@chapter_number}-#{count}", ...)
#                                           ^^^^^^^^^^^^^^^^^^^^^^^^^^ 表示番号 = 生章番号-連番
```

`@chapter_number` は `extract_chapter_number(filename)`（`:120`）で得た**生の章番号**
（"94"）。よって実際の自動キャプションは章番号ベース（"94-1"）になる。
（`display_chapter_number_for_filename`（`:125`）という変換関数はあるが、
本文章は順序 index＋1 に変換する一方、**付録レンジでは生番号 `num.to_s` を返す**ため、
付録レターには未対応。しかもこの関数は現状 auto-id の**照合キー生成**（`:443`）でのみ使われ、
表示番号 `Label.number` 自体の生成には使われていない。）

> 補足: 本仕様書 ④/⑤ 調査時に見えた「表 3-2」等は、cross-reference の使い方を解説する
> `24-cross-reference` 章内の**コード例（説明用テキスト）**であり、実採番キャプションではない。
> 実採番キャプションの実例は付録の「表 94-1」のみ確認できた。

### 修正方針

付録ファイル（90–98）では、図表番号の章プレフィックスに**付録レター**
（`Common.appendix_number_to_letter`）を使う。`display_chapter_number_for_filename` の
**付録レンジ分岐でレターを返す**よう拡張し、それを **`Label.number` の生成**と
**auto-id の照合キー**の双方で一貫して用いる:

- `create_label`（`:195`）の `number`（表示番号）を、付録なら `"#{letter}-#{count}"` に。
- auto-id（`label_id`, `:194`）と `resolve_label`（`:443-444`）のキーも同一規則に揃える
  （両者が一致しないと自動採番ブロックの参照が解決できなくなる）。
- `@photoelectric-table` のような明示 id ラベルは id 一致で引けるため、`Label.number` の
  修正だけで参照リンク（`full_number` 経由）も「表 D-1」に追従する。

### ⑤ への依存・確認事項（重要）

- 本修正は **⑤（付録レター採番）の修正が前提**。⑤ 未修正だとレターが誤る
  （フォールバックで 94→E）。⑤ 修正後は 91→A … **94→D**, 95→E となるため、
  94-sample の表は **「表 D-1」が正**（現在見えている「表 E-1」相当は ⑤ のバグ由来）。
- 念のため: 付録の連番（count）は付録ファイルごとに 1 から振られるため、
  94-sample 最初の表は `D-1` となる（見出しの節番号体系 `D-1`, `D-2` と一致）。

### 影響範囲・テスト方針

- 変更は `cross_reference_processor.rb` の採番／照合の付録分岐に限定。本文章の番号は不変。
- テスト: 付録ファイルの自動キャプションが `表 D-1`／参照リンクも同値になること。
  明示 id・auto id の双方で番号とキーが整合すること。

---

## 実装順序の提案

1. **② print_pdf 本文欠落**（成果物が壊れる・修正は 1 メソッド・効果大）
2. **⑤ 付録ラベル誤り**（PDF・EPUB 共通の表示誤り・修正は 1 箇所・低リスク・効果大）
3. **⑥ 付録の図表番号**（⑤ の直後に。採番の付録分岐のみ・⑤ に依存）
4. **③-b 奥付収録** / **③-c 索引併合**（EpubBuilder 内・低リスク・効果が見えやすい）
5. **① 遺物削除＋ tmpdir 隔離**（衛生面・低リスク）
6. **④-A EPUB 数式の MathML 化**（EPUB 品質・Node 側の数式変換導入を伴い規模中）
7. **③-a 扉絵 EPUB 対応**（設計判断要・規模大。RC では割り切りも選択肢）
8. **④-B テーブル内数式 / ③-d カバー比率**（PDF にも関わる・ドキュメント明記で回避し別タスク化）

③-e（EPUB 分量）は実測の結果、独立した不具合ではないため対応不要。

各項目は独立しているため、合意の取れたものから順次着手できる。
②・⑤ は修正が小さく効果が大きいため最優先を推奨。
本仕様書は調査結果のスナップショットであり、実装時に再検証する。
