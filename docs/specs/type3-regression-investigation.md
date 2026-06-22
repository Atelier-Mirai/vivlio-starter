# Type 3 フォント再発 調査報告書（vivliostyle 11.0.2 / Chrome 149）

> 作成日: 2026-06-22
> ステータス: **原因確定。修正一部適用・一部方針提案**
> 対象: `vs build`（techbook: true）の入稿用／閲覧用 PDF に混入する Type 3 フォント。
> 関連: `lib/vivlio_starter/cli/techbook/processor.rb`、`stylesheets/page-settings.css`（@font-face）、`stylesheets/chapter.css`・`stylesheets/glossary.css`（†）、`test/vivlio_starter/release/manual_build_test.rb`（FT-01）、`docs/archives/svg_luster_bugfix_technical_notes.md`（10.x 時代の Type3 対策）、`docs/specs/KNOWN_ISSUES.md`

---

## 0. 背景

`@vivliostyle/cli` を 10.6 → **11.0.2** に更新（Node 26 の Chrome 展開デッドロック回避）したところ、FT-01（`manual_build_test`）が **25 ページに Type 3 フォント**を検出。vivliostyle 10.5 系では Type 3 は存在しなかった。技術書典は Type 3 が NG のため、原因を特定する。

## 1. 調査方法

1. `targets: pdf`（techbook: true）で実ビルドし、最終結合 PDF を `pdffonts` と `PDF::Reader` で検査。
2. Type 3 フォントの**名称**と**出現ページ**を集計。
3. Type 3 フォントの **ToUnicode**（実際に描画している文字コード）を抽出し、引き金文字を特定。
4. バンドルフォント（Zen）の **cmap 収録状況**を `fc-query` で判定。
5. 生成済み章 HTML の中身を直接検査し、正規化の効き目を確認。

## 2. 結論（要約）

- Type 3 になっているのは**同梱フォントではなく**、Chromium がフォールバックした **OS / 装飾フォント**（HiraMinProN・HiraKakuProN・Keyboard-JP-Regular）。同梱 Zen / HackGen はすべて CID TrueType で正常。
- 真因は「**Zen フォントに無い文字 → Chromium が他フォントへフォールバック → Chrome 149 がそれを Type 3 で埋め込む**」。10.5 系の旧 Chromium は同じフォールバックを CID TrueType で埋め込んでいたため顕在化しなかった（Chrome のレンダリング挙動変化）。
- 引き金文字の最多は **波ダッシュ U+301C**。しかも **既存の正規化処理が逆方向**で、これ自体が主因だった（§4.1）。

## 3. 計測結果

### 3.1 Type 3 フォントと出現ページ（25 ページ）

p.18, 55, 81, 82, 97, 143, 155, 156, 157, 165, 173, 189, 241, 242, 248, 284, 291, 298, 299, 303, 320, 328, 330, 334, 349

### 3.2 Type 3 が実際に描画していた文字（ToUnicode 抽出）

| 文字 | 符号位置 | 回数 | フォールバック先 | 文脈 |
|---|---|---:|---|---|
| `〜` | U+301C 波ダッシュ | 22 | HiraMinProN / HiraKakuProN | 本文・地の文 |
| `†` | U+2020 ダガー | 4 | HiraKakuProN（W3/W6） | **ゴシック文脈**の用語集記号 |
| `Ctrl` `S` | U+0043,74,72,6C,53 | 5 | Keyboard-JP-Regular | `〘Ctrl〙` キーキャップ |
| `▶` | U+25B6 | 1 | HiraMinProN-W6 | |
| `⁵` | U+2075 上付き5 | 1 | HiraMinProN-W3 | |

### 3.3 バンドル Zen フォントの cmap 収録状況（`fc-query`）

| 文字 | ZenOldMincho（明朝/本文） | ZenKakuGothicNew（ゴシック/見出し） |
|---|---|---|
| U+301C 波ダッシュ | **収録 ✓** | **収録 ✓** |
| U+FF5E 全角チルダ | **✗ 非収録** | **✗ 非収録** |
| U+2014 emダッシュ | 収録 ✓ | 収録 ✓ |
| U+2020 † | 収録 ✓ | **✗ 非収録** |
| U+25B6 ▶ | ✗ 非収録 | ✗ 非収録 |

## 4. 原因の内訳と対処

### 4.1 波ダッシュ U+301C（22 件・主因）— 正規化が逆方向だった

`processor.rb` に正規化は**実装済み**だが向きが逆だった:

```ruby
# Before（誤）: 収録字 U+301C を 非収録字 U+FF5E に変換していた
html = html.gsub("〜", "～")
```

- Zen は **U+301C を収録**し **U+FF5E を非収録**（§3.3）。よってこの変換は「描画できる字を、描画できない字に変える」ことになり、ヒラギノへのフォールバック＝Type 3 を**自ら誘発**していた。
- 実証: 生成章 HTML は変換後 U+301C=0 / U+FF5E=55。PDF 側の Type 3 ToUnicode が U+301C と出るのは、フォールバック先ヒラギノが波形グリフを U+301C に正規化するため。
- 入力実態: 全角チルダ `～`(U+FF5E) はキーボードから入力しやすく多用される。波ダッシュ `〜`(U+301C) は「なみ」変換が必要で稀。**Zen が収録するのは U+301C 側**なので、正規化先は U+301C にすべき。

**対処（適用済み）**: 向きを反転 → `html.gsub("～", "〜")`。

### 4.2 ダガー † U+2020（4 件）— ゴシックに † が無い

- ZenOldMincho（明朝）は † を収録、**ZenKakuGothicNew（ゴシック）は非収録**。用語集記号 † (`<a class="glossary-link"><sup>†</sup></a>`) が見出し等のゴシック文脈に入るとフォールバック。

**対処（適用済み）**: `.glossary-link sup` に `font-family: var(--font-main-text)`（= "Zen Old Mincho"）を明示し、周囲がゴシックでも † を明朝で描画。

### 4.3 ▶ U+25B6 / ⁵ U+2075（各 1 件）— Zen 非収録の記号

- どちらも Zen 非収録。OS（ヒラギノ）にフォールバック → Type 3。
- 単発だが、同種（Zen に無く OS にある記号）は将来も発生しうる。→ §5 で方針提案。

### 4.4 キーキャップ Ctrl / S（5 件）— 同梱装飾フォントが Type 3 化

- `keyfont` は**意図的に同梱**した `fonts/Keyboard_font/Keyboard-JP-Regular.otf`（`〘Ctrl〙` 等のキー表現用、`chapter-common.css:191` で `font-family: keyfont, var(--font-code)`）。
- これは OS フォールバックではなく**同梱フォント**だが、OTF（CFF アウトライン）を Chrome 149 が Type 3 で埋め込んでいる。→ §5 で方針提案。

## 5. 未解決分（▶・⁵・キーキャップ）の方針提案

「Zen に無く、別フォントにある字体」は今後も出る前提で、汎用方針が望ましい。

### 提案A（推奨）: 同梱の広域フォールバックフォントをスタック末尾に追加
- `--font-main-text` / `--font-header` の末尾に、**静的（可変フォント不可）・ライセンス明確・記号被覆の広い同梱フォント**を 1 つ加える。Zen に無い字も**必ず同梱フォント（= CID TrueType）**で解決し、OS フォールバック（Type 3）を根絶できる。▶・⁵ 等を個別対応せず汎用的に塞げる。
- 候補: 既に同梱の `hackgen35`（記号・矢印に強い）をフォールバック末尾に使う／または静的な Noto・BIZ UD 系を追加。可変フォントは Type 3 化するため**必ず静的インスタンス**を使う。

### 提案B: 個別ラスタ画像化（既存パターンの踏襲）
- 囲み数字・絵文字と同様に、▶ 等の装飾記号を事前生成 WebP に置換（`replace_circled_numbers` の拡張）。確実だが記号ごとに対応が必要。

### キーキャップ（keyfont）について
- OTF/CFF が Type 3 化の原因の可能性が高い。対処候補: (a) keyfont を TrueType 化／別キーキャップ書体へ差し替え、(b) キーキャップをラスタ画像化、(c) `〘Ctrl〙` を通常書体（Zen 収録字）+ 枠線 CSS で表現。まず (a) の TTF 化で Chrome が CID 埋め込みするか検証するのが低コスト。

### 共通の保険
- 既存の「PDF ページのラスタライズ」機能を、Type 3 残存ページに限定適用する保険も併用可。

## 6. なぜ 10.5 では出なかったか

文字・設定は同じで、**Chromium がフォールバック書体を埋め込む方式が変わった**。10.5 の旧 Chromium は CID TrueType でサブセット埋め込み（Type 3 なし）。11.0.2 同梱の Chrome 149 はフォールバック書体を Type 3 で埋め込む。§4.1 の逆向き正規化も、10.5 では Type 3 化しなかったため害が露見しなかった。

## 7. 検証結果（修正後・2026-06-22）

全 4 要因に対処し、**FT-01（`test:manual` の Type 3 検査）は Type 3 ゼロで合格**（25 ページ → 0）。

採択した対処（§5 提案 A + keyfont TTF 化）:
- §4.1 波ダッシュ: `processor.rb` の正規化を `U+FF5E→U+301C` に反転。
- §4.2 †: `.glossary-link sup` に `font-family: var(--font-main-text)`（明朝）＋既存の `font-weight: normal`（faux-bold 回避）。
- §4.3 ▶・⁵: 同梱 `HackGen35ConsoleNF`（Regular/Bold）をフォントスタック末尾フォールバックに（`page-settings.css` @font-face 差し替え＋`CssUpdater#format_font_value` で `--font-main-text`/`--font-header`/`--font-column`/`--font-folio` に挿入）。
- §4.4 キーキャップ: keyfont を OTF→TTF 変換（`test/vivlio_starter/fixtures/type3/otf2ttf.py`）。

**追加で判明した要点**: フォールバック書体は **Regular/Bold の両字面**を宣言しないと、bold 見出し内で **faux-bold 合成**が起き Chromium が Type 3 化する（`-webkit-text-stroke` 由来 Type 3 と同類の「合成」要因）。

検証手段:
- 高速ループ `test/vivlio_starter/fixtures/type3/verify.sh`（実バンドルフォント・約 10 秒）で Type 3 = 0 を確認。
- フル `rake test:manual` の FT-01 合格で最終確認。

残課題（本件と無関係の既知 issue）: FT-02（隠しノンブルの Helvetica 非埋め込み）、epubcheck 索引 RSC-012。いずれも `KNOWN_ISSUES.md` 記載済みで本修正による退行ではない。
