# 前付・奥付を本文と 1 回のレンダにまとめる仕様書

調査日: 2026-08-01 / 調査・設計: Claude (Opus 5) / 実装担当: 未定
対象: `PLANNED.md` 「ビルド / 出力」— ビルド時間の短縮

関連: `backlink-dedup-pdf-map-spec.md`（Step 8 の再レンダが不可避である根拠）、
`print-pdf-derivation-spec.md`（qpdf が構造保存型であることの実証）

---

## 0. 背景・問題

### 0.1 実測: PDF を吐く vivliostyle 起動は 1 回あたり約 22 秒の固定費

A5・515 ページ・`targets: pdf, epub, kindle` のフルビルド（`vs build --no-clean --log=debug`、
2026-08-01 実測・TOTAL 553.25s）で、前付・奥付の生成に **71.10 秒**かかっていた。

```
  - build front and back matter          71.10s
    (vivliostyle build)                 (37.50s)  ← _titlepage_legalpage.pdf（2 ページ）
    (vivliostyle build)                 (30.55s)  ← _colophon.pdf（1 ページ）
```

**たかだか 3 ページの組版に 68 秒**である。原因を切り分けるため、中身が空の 1 ページ HTML
（スタイルシート・フォント・画像を一切参照しない）を `vivliostyle build` に通した。

| 対象 | 所要 |
|---|---|
| 最小 HTML 1 ページ・CSS 無し | **21.7s** |
| `_colophon.html` 単体（フル CSS・フォント 8 種） | **22.3s** |

差は 0.6 秒。つまり **組版の実作業はほぼゼロで、ほぼ全部が vivliostyle CLI の起動費**
（Chromium の立ち上げと PDF 出力パイプラインの初期化）である。ページ数が少ないから
速い、という関係にはならない——**何を組んでも約 22 秒かかる**。

裏付けとして、同じビルド内で EPUB を吐く 2 回は 15.10s / 5.70s と安い。出力が EPUB で
Chromium の PDF レンダを通らないためで、**重いのは PDF を吐く起動だけ**である。

### 0.2 現状のレンダ回数

フルビルドで PDF を吐く vivliostyle 起動は **4 回**ある。

| # | ステップ | 対象 | 実測 |
|---|---|---|---|
| 1 | `build overall pdf` | 本文全体 → `_sections.pdf` | 147.55s |
| 2 | `backlink dedup` | 浄化後の本文全体を再レンダ | 152.50s |
| 3 | `build front and back matter` | 本扉＋権利ページ → `_titlepage_legalpage.pdf` | 37.50s |
| 4 | 〃 | 奥付 → `_colophon.pdf` | 30.55s |

1 と 2 は削れない。「どの †マークが重複か」はページ番号が分からないと判定できず、
ページ番号はレンダしないと存在しない——鶏と卵であり、`backlink-dedup-pdf-map-spec.md` §0 が
**「再レンダ 106.5s は本文が変わる以上不可避」**と明記している（同仕様が消したのは
Phase 1 の Playwright プレビューレンダ 73 秒のほうで、再レンダは意図して残された）。

削れるのは **3 と 4** である。

### 0.3 削減見込み

3 と 4 を 1 の起動に相乗りさせると、**実測 68.05 秒（今回のビルドの 12%）**が消える。
増える側は、本文 515 ページのレンダに 3 ページ足す分（1 秒未満）と、レンダ後の
qpdf 分割 3 回（各 0.5 秒未満）で、無視できる。

なお 2（dedup の再レンダ）にも 3 ページが相乗りするが、**同一起動なので追加費用はゼロ**。

---

## 1. 方針

### 1.1 本文スパインの末尾に 3 ページを足し、レンダ後に切り出す

```
レンダ:  00-preface … _indexpage │ _titlepage │ _legalpage │ _colophon
         └────────── 本文 N ページ ─────────┘   N+1        N+2        N+3

分割:    1..N     → _sections.pdf
         N+1..N+2 → _titlepage_legalpage.pdf
         N+3      → _colophon.pdf
```

**分割後のファイル名・ページ数を現行と完全に一致させる**のが要点である。こうすると
結合順（`PdfMerger.cover_enhanced_files`）・奥付前の白紙挿入（`insert_blank_page_before_colophon`）・
アウトラインの基点補正（`compute_front_matter_offset`）・入稿用 PDF の導出は
**一切変更せずに済む**。継ぎ目を今ある位置から動かさないこと。

### 1.2 なぜ先頭ではなく末尾か

目次のページ番号は CSS の `target-counter(attr(href url), page)` で解決される
（`toc.css:108, 194, 268`）。本扉・権利ページを**スパインの先頭**に足すと本文の
ページ番号が 2 つずれ、目次・索引・相互参照・dedup のページマップが軒並み動く。

**末尾に足せば本文のページ番号は 1 つも動かない。** 分割前の PDF の 1..N ページは、
現行の `_sections.pdf` と 1 ページも違わないものになる。

---

## 2. 実装

### 2.1 特殊ページ HTML の生成を前倒しする

現在 `PdfBuilder.build_front_pages_and_tail!`（`pdf_builder.rb:167`）が、
`_titlepage` / `_legalpage` / `_colophon` の Markdown 生成 → 前処理 → HTML 変換 →
techbook 後処理 → pdf/ へのステージングを **Step 9 でまとめて**行っている。

これを **`preprocess sections` 〜 `convert sections html` の並び**へ移す。移した結果、
`build_front_pages_and_tail!` にある次のコメントの前提が消え、`Techbook::Processor` の
個別再適用は不要になる（通常の `techbook post-process` ステップが拾う）。

```ruby
# Step 9 で生成されたタイトル・奥付 HTML は Step 5c より後に作られるため、
# 波ダッシュ置換 / 絵文字画像化 / SVG→WebP 参照整合 / CSS 注入をここで再適用する。
```

前倒しの安全性は確認済み: `_titlepage.md` / `_legalpage.md` / `_colophon.md` の内容は
すべて `book.yml` 由来で、**総ページ数など「本文を組んだ結果」に依存する値を含まない**
（`.cache/vs/` の生成物を実見して確認）。したがって本文レンダより前に確定できる。

### 2.2 本文 entries の末尾に 3 ページを足す

`PdfBuilder.sections_entry_htmls`（`pdf_builder.rb:100`）の戻り値の末尾に
`_titlepage.html` / `_legalpage.html` / `_colophon.html` を append する。
`VivliostyleConfigWriter.write!(name: 'sections', …)` はそのまま。

dedup の再レンダ（`backlink_dedup_orchestrator.rb:150 build_sections_pdf!`）は
`vivliostyle.config.sections.js` を再利用するので、**自動的に同じ 3 ページを含む**。

### 2.3 レンダ後に qpdf で 3 分割する

レンダの出力先を `_sections_all.pdf`（仮）とし、直後に分割する。

```
qpdf _sections_all.pdf --pages . 1-N       -- _sections.pdf
qpdf _sections_all.pdf --pages . N+1-N+2   -- _titlepage_legalpage.pdf
qpdf _sections_all.pdf --pages . N+3       -- _colophon.pdf
```

`N` は総ページ数 − 3 で求める。**「末尾 3 ページ」を機械的に切るのではなく、
特殊ページの位置を実測して切ること**（§3.3 の理由）。位置の特定には、dedup が使う
`/Dests` 抽出（`backlink-dedup-pdf-map-spec.md` §2）をそのまま流用できる——
`_colophon.html#…` のアンカー ID からページ番号が決定的に引ける。

分割は **1 と 2 の両方の後**に必要である（dedup は再レンダするため）。
分割処理を 1 箇所にまとめ、両方から呼ぶ。

**dedup のページマップ抽出は分割前の PDF から行う**こと。分割後の `_sections.pdf` は
qpdf を通っており、`/Dests` が保たれる保証を §3.1 で確かめるまでは依存しない。
分割前の PDF は vivliostyle が直接吐いたものなので、現行と同じ品質が保証される。

### 2.4 CSS: 柱の抑止とノド／小口の固定

3 ページは既に**名前付きページ**を使っている（`titlepage.css:41` / `legalpage.css:30` /
`colophon.css:47`）ので、スパイン中のどこに置かれてもノンブル抑止は効く。足りないのは
次の 2 点。

**(a) 柱（`@top-right`）の抑止**

今これらに柱が出ていないのは「自分のドキュメントの 1 ページ目」だからで、
`page-settings.css:235` の `@page :nth(1) { @top-right { content: none; } }` が効いている。
本文スパインの末尾に置くと `:nth(1)` が外れ、`string(chapter-number, first)` が
**最後の章の値を保持したまま**柱に出る。名前付きページ側で明示的に消す。

```css
@page titlepage { @top-right { content: none; } }
@page legalpage { @top-right { content: none; } }
@page colophon  { @top-right { content: none; } }
```

**(b) ノド／小口の固定**

`page-settings.css:190, 207` の `@page :left` / `@page :right` が、綴じ側（ノド 26mm）と
外側（小口 22mm）を**ページの表裏で入れ替えている**。3 ページは今それぞれ独立した
ドキュメントの 1 ページ目（＝右ページ）または 2 ページ目（＝左ページ）なので表裏が
確定しているが、本文末尾に置くと **本文のページ数次第で表裏が変わり、余白が左右反転する**。

最終的な綴じ位置（本扉＝右ページ、権利ページ＝左ページ、奥付＝左ページ）に合わせて、
名前付きページで余白を固定する。

```css
@page titlepage { margin-left: var(--page-margin-inner); margin-right: var(--page-margin-outer); }
@page legalpage { margin-left: var(--page-margin-outer); margin-right: var(--page-margin-inner); }
@page colophon  { margin-left: var(--page-margin-outer); margin-right: var(--page-margin-inner); }
```

`break-before: recto` / `verso` で表裏を強制する手も有るが、**採らない**。レンダ中に白紙が
挟まって分割位置が動くうえ、`page.chapter_pagebreak: any` の本では改丁の思想と衝突する。
余白を直に固定するほうが副作用が無い。

奥付が左ページに来るための白紙挿入は、従来どおり結合時（`insert_blank_page_before_colophon`）が
担当する。レンダ側で表裏を作らないので、**この分業は変わらない**。

### 2.5 下流への影響

| 箇所 | 影響 |
|---|---|
| `PdfMerger.cover_enhanced_files`（`pdf_merger.rb:16`） | 変更なし（同じ 3 ファイルを同じ順で読む） |
| `insert_blank_page_before_colophon`（`:171`） | 変更なし（ページ数が同じ） |
| `compute_front_matter_offset`（`:233`） | 変更なし |
| `BacklinkDedupOrchestrator`（`:139`） | 出力先の名前だけ変更。抽出元は分割前 PDF |
| `PrintPdfBuilder` | 変更なし（同じ中間ファイルを読む） |
| `OutlineExtractor` | 変更なし |
| EPUB / Kindle | 変更なし（`html/` の原本から展開するため） |

EPUB 側は影響を受けない。特殊ページ HTML は現行でも Step 9（EPUB 生成より前）に
`html/` へ置かれており、前倒ししても `html/` に置かれる時点が早まるだけである。

---

## 3. 実装前に潰す検証項目

### 3.1 qpdf の分割で `/Dests` とリンク注釈が生き残るか【要検証】

**これが唯一の本質的なリスク。** 本文には索引・用語集のバックリンク、相互参照、脚注の
往復リンクが大量にある（実測 `/Dests` 3,361 件・注釈 8,577 件・`print-pdf-derivation-spec.md` §0）。

追い風の材料は 2 つある。

- 結合側は既に `qpdf base --pages "file" 1-z … -- output` を使っており（`pdf_merger.rb:160`）、
  現行 PDF のリンクは機能している。
- `print-pdf-derivation-spec.md` が「qpdf は構造保存型なのでリンク・named destinations が
  壊れない」ことをフルスケールで実証している。

ただし **ページ範囲を切り出す `--pages` は別の操作**であり、文書カタログ直下の `/Dests` 辞書が
どう扱われるかは未確認である。実装の最初の作業として、次を確かめること。

1. 分割前 PDF の `/Dests` 件数を pdf-reader で数える
2. 分割後 `_sections.pdf` の `/Dests` 件数を数える
3. 件数が減っていたら、`--pages` を諦めて別の分割手段（`qpdf --update-from-json` 等）を検討する

**もし `/Dests` が失われるなら、方針 1.1 は「分割せず、結合時に `--pages` のページ範囲指定で
並べ替える」（案 B）へ切り替える。** 結合は現状でも `--pages` 一発なので、
`frontcover 1-z / all N+1-N+2 / all 1-N / blank / all N+3 / backcover 1-z` と書けば
中間ファイルを作らずに済む。ただし §2.5 の「変更なし」がすべて崩れるため、
第一候補は分割方式（案 A）とする。

### 3.2 名前付きページが `:left` / `:right` に勝つこと【実証済み】

CSS Paged Media Level 3 の詳細度は (A: ページ名の有無, B: `:first`/`:blank` の数,
C: `:left`/`:right` の数) の順で比較され、名前付きページ（A=1）が `@page :right`（C=1）に勝つ。

**現行ビルドで実証済み**: `_titlepage_legalpage.pdf` の 2 ページ目（＝左ページ）は
`@page :left { @bottom-left { content: var(--folio-left-content); } }` の対象だが、
`@page legalpage { @bottom-left { content: none; } }` が勝ってノンブルが出ていない
（pdf-reader でテキスト抽出して確認）。したがって §2.4 の (a)(b) はどちらも効く。

### 3.3 `chapter_pagebreak: verso` のとき本扉の前に白紙が入る

`BookSettingsCss::CHAPTER_PAGEBREAK_SELECTORS` は**裸の `body`** を含み、生成 CSS は
`body, body.toc, body.vs-header-simple h1, .part-title { … }` という形で出る。
特殊ページ 3 枚はいずれも `book-settings.css` を読んでいる（`_colophon.html` の
`<link>` を実見して確認）ので、**この裸の `body` は特殊ページにも当たる**。

今は各々が独立ドキュメントの先頭なので `break-before` が無効化され実害が無いが、
本文スパインに載せると設定値によって挙動が分かれる。

| `chapter_pagebreak` | 生成される値 | 本扉の直前 |
|---|---|---|
| `recto`（既定） | 生成 CSS は空（元 CSS の `recto` に任せる。特殊ページ側の CSS に `break-before` は無い） | 改ページのみ・白紙なし |
| `any` | `break-before: page` | 改ページのみ・白紙なし |
| `verso` | `break-before: verso` | **白紙が 1 枚入り得る** |

`verso` のときだけ分割位置がずれる。対策は次のいずれか。

- `CHAPTER_PAGEBREAK_SELECTORS` の射程から特殊ページを外す（裸の `body` をやめる）
- `titlepage.css` / `legalpage.css` / `colophon.css` で `break-before: auto;` を明示する

後者が局所的で安全。いずれにせよ §2.3 で分割位置を「末尾 3 ページ」ではなく
`/Dests` 由来の実位置で決めるのは、**この種の取りこぼしが起きても静かに壊れない**
ようにするためである。ページ番号を数えて切る実装は、白紙が 1 枚入った瞬間に
奥付の代わりに白紙を切り出し、しかもエラーにならない。

---

## 4. テスト

- `test/vivlio_starter/cli/build/` にユニットテストを追加
  - `sections_entry_htmls` の末尾に 3 件が付くこと
  - 分割が「総ページ数 − 3」ではなく `/Dests` 由来の実位置で行われること
  - 特殊ページ HTML の生成が本文レンダより前であること（ステップ表の順序）
- `test/vivlio_starter/page_layout/` に統合テストを追加（`rake test:layout`）
  - `_sections.pdf` のページ数が、この変更の前後で一致すること
  - `_titlepage_legalpage.pdf` が 2 ページ・`_colophon.pdf` が 1 ページであること
  - 分割後の `_sections.pdf` の `/Dests` 件数が分割前と一致すること（§3.1 の回帰固定）
  - 本扉・権利ページ・奥付にノンブルと柱が出ていないこと（pdf-reader でテキスト抽出）
- 判型を変えても壊れないこと。A5 と A4 の両方で確認する（`chapter-pagebreak-spec.md` §7 で
  A4 以外の検証漏れが実際に見つかっている）

---

## 5. スコープ外

- **dedup の再レンダを消すこと**。§0.2 のとおり構造的に不可避。
- **vivliostyle の起動費 22 秒そのものを縮めること**。CLI の外側の問題であり、
  常駐プロセス化などは vivliostyle CLI 側の機能を待つ。
- **カバー PDF**。vivliostyle を通らない（rsvg-convert / magick 生成）ため無関係。
- **EPUB / Kindle の生成回数**。PDF レンダを通らないため 1 回あたり 5〜15 秒で、
  削る旨味が小さい。

---

## 6. 期待効果

| | 現状 | 実装後 |
|---|---|---|
| PDF を吐く vivliostyle 起動 | 4 回 | **2 回** |
| `build front and back matter` | 71.10s | **約 3s**（HTML 生成のみ・レンダ無し） |
| フルビルド合計（A5・515 ページ） | 553.25s | **約 486s** |

削減 **約 67 秒（12%）**。ページ数・判型に依存しない固定費の削減なので、
薄い本ほど相対的な効果は大きくなる。
