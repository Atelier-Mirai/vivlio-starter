# EPUB Kindle 対応：WebP → JPEG/PNG トランスコード 仕様書

> 作成日: 2026-06-16
> ステータス: **策定（実装前）**
> 対象: `vs build`（epub ターゲット）が生成する EPUB の Kindle 変換不能（WebP 非対応）の恒久対応
> 原因調査: `docs/specs/epub-kindle-webp-incompatibility-report.md`
> 関連: `docs/specs/math-frontispiece-svg-spec.md`（③-a 扉絵/節絵の JPEG 化）, `epub-kindle-compatibility-report.md`
> 優先度: **高**（EPUB の最重要ターゲット Kindle / Amazon KDP で変換不能 → RC ブロッカー）
> スコープ: §5-1（WebP トランスコード）＋ §5-3（不要背景 WebP 除外）＋ §5-4（不正ファイル名の事前検出。W14010 アポストロフィを一般化）

---

## 0. 全体方針

| 項目 | 現状 | 本仕様の方針 | 効果 |
| --- | --- | --- | --- |
| 本文・絵文字等の画像 | ビルド時に WebP へ最適化し、その WebP が EPUB にも同梱される | **EPUB 経路でのみ `<img>` 参照 WebP を JPEG/PNG へトランスコード**し、staging へ書き出して `src` を差し替える | W14015/W14012 解消（Kindle で全画像が有効に） |
| 扉絵/節絵の背景 WebP | §B で合成 JPEG に置換済みだが、背景 WebP が EPUB に残存（非描画なのに同梱） | **`copyAsset.excludes` で全 WebP を EPUB から除外** ＋ EPUB 内 CSS から `url(...webp)` を除去 | W14015 と EPUB サイズの削減 |
| アポストロフィ入りファイル名 | `src="…&apos;…webp"` を Kindle が解決できず W14010 | **トランスコード先がハッシュ名のため自動解消** ＋ import 時のファイル名サニタイズで恒久対策 | W14010 解消 |
| PDF 経路 | WebP のまま | **一切変更しない**（WebP は PDF サイズ削減に有効） | 副作用ゼロ |

設計上の二本柱:

1. **PDF 経路は不変。** WebP 最適化（`ImageOptimizer.optimize_images!` / `ResizeCommands`）も、PDF が参照する WebP もそのまま。本仕様の変換は **EPUB ビルド（Step E）に閉じる**。これは §B（扉絵/節絵を EPUB 専用に画像化）と同じ「EPUB 専用に画像形式を変える」発想の一般化である。
2. **EPUB の `<img>` 参照画像だけを Kindle 対応形式へ。** CSS 背景（`url(...webp)`）はリフロー型 EPUB（特に Kindle）で描画されないため**変換せず除外**する。描画される `<img>` 参照だけを JPEG/PNG 化すればよい。

---

## 1. 劣化方針（変換元の選択）

ご懸念の「WebP → JPEG の二重劣化」は、変換元と出力形式を選ぶことで最小化する。

### 1-1. 変換元：元画像優先 ＋ WebP フォールバック

`ResizeCommands.execute_resize_with_preset` は既定で元 `png/jpg` を残す（`--delete-originals` 指定時のみ削除）。よって変換時に **同一 basename の元画像（`.png` / `.jpg` / `.jpeg`）が残っていれば、WebP を経由せず元画像から直接** EPUB 用画像を生成し、二重劣化を回避する。元が無い（最初から WebP、または削除済み）場合のみ WebP から変換する。

```
参照 src = images/10-intro/photo.webp
  ├─ images/10-intro/photo.png|jpg|jpeg が存在 → それを変換元に採用（劣化回避）
  └─ 無ければ photo.webp を変換元に採用（フォールバック）
```

### 1-2. 出力形式：写真は JPEG / 透過・可逆は PNG

| 条件 | 出力 | 理由 |
| --- | --- | --- |
| 変換元がアルファチャンネルを持つ | **PNG** | 透過を保持（JPEG は透過非対応）。可逆で追加劣化なし |
| 変換元が PNG（不透過） | **PNG** | 図版・スクリーンショット等。可逆 → 追加劣化ゼロ |
| 変換元が WebP かつ lossless | **PNG** | SVG 由来の図版・囲み数字・見出しマーカー（`convert_svg_to_webp` が `webp:lossless=true` で生成）。lossless WebP → PNG は無劣化 |
| 上記以外（不透過の写真 JPEG / lossy WebP） | **JPEG**（quality 90） | 写真。EPUB は画面表示のため quality 90 で実用上劣化は不可視 |

- アルファ判定: `magick identify -format '%A'`（`True` / `Undefined` / `False`）。
- WebP lossless 判定: `magick identify -verbose <file>` の `Compression` 行（`Lossless` を含むか）。判定失敗時は安全側で JPEG とする（致命的でないため）。
- **結論**: 図版・絵文字・囲み数字（report で件数の多い種別）はすべて PNG 経路に乗り無劣化。二重劣化が起こり得るのは「元画像が無い lossy 写真」だけで、quality 90・画面表示では実害なし。

### 1-3. 寸法

WebP は既にビルドプリセットで縮小済み（medium=1600px）。EPUB 用画像も**有効化中のプリセット `max_px` を長辺上限**として `-resize "<max>x<max>>"` を適用し、PDF と過不足ない解像度にそろえる（元画像から変換する場合の肥大化も防ぐ）。

---

## 2. 変換と差し替え（§5-1 中核）

### 2-1. 処理位置

`EpubBuilder.generate_epub_entries!`（Step E）の HTML 書き換え群の**最後**に新パスを追加する。既存の並びに合わせる:

```
post_process_index_glossary_for_epub!
strip_inline_footnote_ids_for_epub!
rewrite_table_align_for_epub!
restore_plain_emoji_for_epub!
inject_heading_images_for_epub!
transcode_webp_images_for_epub!   ← 新規（最後に置く）
```

最後に置く理由: 直前の `inject_heading_images_for_epub!` までで `<img>` の出入りが確定する（絵文字復元・扉絵注入後）。残った `<img src="*.webp">` だけを対象にできる。Step E は PDF 完成後に共有 HTML を書き換えるため PDF 経路へ副作用はない（既存の table align 書き換え等と同じ前提）。

> 注: 扉絵/節絵の合成画像（`HeadingImageComposer`）は既に JPEG 出力のため本パスの対象外。

### 2-2. アルゴリズム（`transcode_webp_images_for_epub!`）

入力: EPUB 対象 HTML パス配列。

1. 各 HTML を走査し `<img ... src="(...)\.webp">` を収集（`&apos;` / `'` を含む src も対象。後述 §4）。
2. 参照 src（HTML 実体参照をデコードした実パス）ごとに、未変換なら **staging へ変換出力**しキャッシュ:
   - 変換元を §1-1 で決定（元画像優先）。
   - 出力形式を §1-2 で決定（JPEG / PNG）。
   - 出力先 `images/_epub_assets/<sha16>.<jpg|png>`。`<sha16>` = `SHA256(変換元の実パス + mtime + 出力形式)[0,16]`（同一画像は使い回し・冪等）。
   - `magick <変換元> [-background white -flatten（JPEG時）] -resize "<max>x<max>>" -strip [-quality 90（JPEG時）] <出力>`。
3. その src を `images/_epub_assets/<sha16>.<ext>` へ書き換える（`<img>` の他属性は保持）。
4. `magick`／変換に失敗した画像は **src を書き換えない**（元の WebP のまま残す）。致命にせず警告ログのみ（縮退）。失敗が残った場合 §6 の検証で検出される。

> **staging 方式の副次効果**: 出力名がハッシュのため、
> - 元の `png/jpg` ソースを上書きしない（衝突回避）。
> - アポストロフィ等の問題のあるファイル名が EPUB から消える（§4 の W14010 を自動解消）。
> - 既存の `images/headings/`（扉絵合成 JPEG）と同じ「EPUB 用生成物を `images/` 配下の専用サブディレクトリへ」という前例に沿う。

`images/_epub_assets/*.{jpg,png}` は Vivliostyle CLI の `DEFAULT_ASSET_EXTENSIONS` で EPUB へコピーされる（`images/` 配下は copyAsset の除外対象外のため）。

### 2-3. クリーン対象

`images/_epub_assets/` を `CleanCommands`（`clean.rb`）のクリーン対象へ追加する（`images/headings/` と同様）。`--no-clean` 時は残置・キャッシュ再利用。

---

## 3. WebP の EPUB 除外と CSS サニタイズ（§5-3）

### 3-1. copyAsset.excludes に全 WebP を追加

`EpubBuilder.build_copy_asset_excludes_config` の除外パターンに以下を追加する:

```
images/**/*.webp
stylesheets/**/*.webp
```

§2 で `<img>` 参照画像は staging（`images/_epub_assets/*.jpg|png`）へ移るため、EPUB に WebP を 1 つも同梱しなくてよい。これにより:
- 本文画像由来の W14015/W14012 が解消。
- 扉絵/節絵の背景 WebP（`images/42-frontispiece/*`・`stylesheets/images/bundled/*`）など**非描画の死蔵 WebP**（report §5-3）も同時に除外され、W14015 と EPUB サイズが削減。
- 既存の個別パターン（`stylesheets/twemoji/*.webp` 等）は包含されるが、明示性のため残してよい。

### 3-2. EPUB 内 CSS の `url(...webp)` 除去

WebP を除外すると、CSS の `background-image: url(...webp)` 等が**参照切れ**になり、epubcheck の RSC-007 や Kindle の W14010 を誘発し得る。これらの背景はリフロー EPUB で描画されないため、生成後 EPUB 内 CSS から除去する。

`EpubBuilder.sanitize_epub_css!`（既に @page マージンボックス・@font-face を除去している unzip→修正→zip 方式）を拡張し、以下を追加で除去する:

- `url( ... .webp ... )` を含む宣言を無害化する。安全な実装は **「`url(...webp)` を `none` に置換」** または **その宣言（`background-image:` / `background:` 等）行の削除**。CSS カスタムプロパティ（`--frontispiece-image: url(...webp)`）にも一致させる。
- 影響範囲は背景・装飾のみ（EPUB では元々非描画）。本文レイアウトには影響しない。

> 実装メモ: 既存 `MARGIN_BOX_PATTERN` / `FONT_FACE_PATTERN` と同じ「パターン配列を `gsub('')` で畳み込む」流儀に、`WEBP_URL_PATTERN`（例: `/[a-z-]+\s*:\s*[^;{}]*url\([^)]*\.webp[^)]*\)[^;}]*;?/i`）を加える。過剰一致を避けるため宣言単位で捕捉する。

---

## 4. 不正ファイル名の事前検出（§5-4 を一般化）

報告書の W14010 は `images/94-sample/Einstein&apos;s_later_years.webp` で、`src` の `&apos;` を Kindle が解決できない事象だった。今回は `'` で発覚したが、同種で**実際に壊れる文字は他にもある**。`'` 限定の事後対応ではなく、**`vs preflight` / `vs build` でビルド前に不正ファイル名を検出して警告する**仕組みに一般化する。

> 設計判断: 環境チェックの `vs doctor` ではなく**プロジェクト内容を走査する `preflight`** に置く。`build`（full/single）の早い段でも同じガードを共有呼び出しし、本番ビルド前に必ず気づけるようにする。

### 4-1. WebP に限った自動解消（§2 の副次効果）

`<img>` 参照 WebP は §2 で staging のハッシュ名へ変換されるため、アポストロフィを含む src 自体が EPUB から消え、W14010 は**自動的に解消**する。`transcode_webp_images_for_epub!` の src 収集は `&apos;` / `'` をデコードして実ファイルを解決する（デコード前後の両表記でディスク上の実体を探す）。これは §2 で担保され、§4-2 以降の事前検出はそれと独立した「著者への早期警告」である。

### 4-2. 検出文字ポリシー（実害ベース・マルチバイト許可）

| 区分 | 文字 | 理由 |
| --- | --- | --- |
| **危険（要対応）** | `(` `)` `'` `"` `&` `<` `>` `#` `?` `%` `\` `:` `*` `|`、制御文字、先頭/末尾の空白・末尾ドット | `()` は Markdown `![alt](path)` を壊す。`' " & < >` は XHTML 属性・実体参照（W14010 もこれ）。`# ? %` は URL 特殊文字。`\ : * |` は Windows 不可・zip 移植性 |
| **やや危険（注意）** | 半角スペース、`+`、`[ ] { } @ ! $ , ; =` | 多くは通るが `src`/URL で非推奨 |
| **許可** | `A-Za-z0-9 . _ -`、および**マルチバイト（日本語等）** | 技術書では和文ファイル名が常用。EPUB3/Vivliostyle で概ね通るため既定では警告しない |

- 重大度は **警告のみ（非ブロッキング）**。ビルドは止めず、著者が気づいて直せるようにする（自動リネームは行わない。§4-4）。
- マルチバイトを厳格に弾く「strict ASCII」モードは将来の任意拡張点として `EpubBuilder`/ガードにコメントを残す（既定は無効）。

### 4-3. 検出対象ディレクトリと警告内容

利用者が画像を配置できる **3 ディレクトリ**すべてを走査する（glob 対象を増やすだけで検出は同一実装）:

| ディレクトリ | 用途 | 検出 | 改名案 | 出現箇所の案内 |
| --- | --- | --- | --- | --- |
| `images/` | 本文画像（`contents/*.md` から参照） | ✅ | ✅ | **.md ファイル名と行番号**（既存 `ImagePathNormalizer.build_source_image_line_map` 相当で取得） |
| `covers/` | 表紙・裏表紙 | ✅ | ✅ | 「表紙・裏表紙として配置されています」 |
| `stylesheets/images/` | 扉絵・節絵 | ✅ | ✅ | 「扉絵・節絵として配置されています」 |

設計上のポイント: **検出（走査）は 3 ディレクトリとも行う**（`covers/` の表紙にアポストロフィがあれば EPUB は同じく壊れるため、外すと既知の穴が残る）。一方、**.md の行番号まで出すリッチな出現報告は `images/`（本文）だけ**とし、`covers/` / `stylesheets/images/` は固定文言の軽い案内に留める（参照が `book.yml` / `theme.css` 経由で行番号トレースが別実装になり実装規模が増えるため、深い参照トレースは今回見送り）。

**警告メッセージ例**（「不親切でない警告」＝具体的な改名案と出現箇所を必ず添える）:

```
🟡 画像ファイル名に問題のある文字 ' が含まれています:
   images/94-sample/Einstein's_later_years.webp
   → images/94-sample/Einsteins_later_years.webp に変更してください
   出現箇所: contents/94-sample.md の 12 行目, 48 行目
```
```
🟡 画像ファイル名に問題のある文字 ' が含まれています:
   covers/Einstein's_portrait.webp
   → covers/Einsteins_portrait.webp に変更してください
   表紙・裏表紙として配置されています
```

改名案は「危険文字を `_` へ、連続する `_` は 1 つに畳む」等の素朴な正規化で生成する（提示のみ。実ファイルは変更しない）。

### 4-4. 自動リネームは行わない（今回の非目標）

ファイルと `contents/*.md` 内の参照を一括書き換えする自動リネームヘルパーは、参照書き換えの実装・検証コストが大きいため**今回は実装しない**。警告に改名案と出現箇所を添えることで、著者が手動で安全に直せるようにする（将来 `vs` サブコマンドとして別途検討可）。

### 4-5. 実装位置

`guards/`（既存 `images_dir_check.rb` の隣）に新ガード（例: `ImageFilenameCheck`）を置き、`pipeline.rb` の `register_preflight_steps` と full/single ビルドの早い段（Step 1 付近）から共有呼び出しする。`import/image_processor.rb` の取り込み時にも同じ正規化基準でファイル名をサニタイズしておけば「今後の取り込み」に対する恒久防御になる（任意・低優先）。

---

## 5. 設定とドキュメント

- 既定で本変換は **epub ターゲットで常時有効**（追加設定なしで Kindle 対応）。
- 将来拡張点（任意・本仕様では実装しない）: `book.yml` の `output.epub.image` 下に `format`（`auto`/`jpeg`/`png`）・`jpeg_quality`・`max_px` を置けるようにするコメントを `EpubBuilder` に残す（`embed_fonts?` と同様の拡張点コメント様式）。
- `vs doctor`: `magick`（ImageMagick）は既に扉絵合成で必須級。EPUB トランスコードでも必須となる旨を doctor の案内に追記（未導入時は変換スキップ＝WebP 残存で Kindle 変換不可になるため、警告を強める）。

---

## 6. テスト（2 層）

### 6-1. 軽量・回帰ガード（OS 非依存）

**(a) ユニットテスト（`rake test`、`test/vivlio_starter/cli/build/`）**
`magick` 未導入時は `skip`。フィクスチャ（WebP / 透過 PNG / JPEG と、参照する最小 HTML）を用意し:
- `transcode_webp_images_for_epub!`: `<img src="*.webp">` が `images/_epub_assets/<hash>.{jpg,png}` に書き換わり、出力ファイルが生成される。
- 出力形式判定: アルファあり→PNG、不透過写真→JPEG、lossless WebP→PNG。
- 変換元選択: 同名の元 `png/jpg` があればそれを使う（§1-1）。
- `&apos;` / `'` を含む src でも実ファイルを解決し、ハッシュ名に差し替わる（§4-1）。
- 冪等性: 2 回実行で同一ハッシュ・再変換なし（mtime 据え置き時）。
- CSS サニタイズ: `url(...webp)` を含む CSS が除去/`none` 化される（§3-2）。

**(a-2) 不正ファイル名検出ガードのユニットテスト（`rake test`、`test/vivlio_starter/guards/`）**
実ビルド不要・OS 非依存。フィクスチャのディレクトリ構成で:
- 危険文字（`(` `)` `'` `"` `&` `<` `>` 等）を含むファイル名を検出し、警告を出す（§4-2）。
- マルチバイト（日本語）・許可文字（`A-Za-z0-9._-`）は検出しない。
- 改名案が期待どおり（危険文字→`_`、連続 `_` 畳み）生成される。
- `images/` は `contents/*.md` の出現行番号を、`covers/` / `stylesheets/images/` は固定文言を案内する（§4-3）。
- 重大度が警告のみで、ビルドを止めない（戻り値・例外を投げない）。

**(b) EPUB 成果物検査（実ビルドを伴う既存スイートへ追加）**
`test/vivlio_starter/targets/target_consistency_test.rb`（`rake test:targets`）は既に epub を unzip 検査している（`EpubSnap`）。ここに以下のアサートを追加:
- **EPUB 内に `.webp` が 1 つも存在しない。**
- 全 `<img src>` が EPUB パッケージ内の実体に解決する（リンク切れゼロ）。
- これが本不具合の直接的な回帰ガード（epubcheck では検出できないため必須）。

### 6-2. Kindle Previewer 実変換（opt-in・Mac/Win ローカル）

`rake test:kindle`（新設）として `rake test` から分離。`test/vivlio_starter/kindle/` 配下。

- 冒頭で `kindlepreviewer`（Kindle Previewer 3 CLI。本環境は `/usr/local/bin/kindlepreviewer`、確認済み）と `magick` の存在を確認し、無ければ `skip`（Linux CI・未導入環境でコケない）。
- 手順:
  1. epub ターゲットでマニュアルをビルド（既存 `support/build_helper` を利用）。
  2. `kindlepreviewer <built>.epub -convert -output <tmp> -locale ja` を実行（`-log` でも可。CSV さえ出ればよい）。
  3. 出力フォルダの `*-conversionLog.csv` をパースし、**画像系コード（W14015 / W14012 / W14010）が 0 件**であることをアサート。レベル「注意」でも件数を厳格に 0 とする。
  4. 失敗時は CSV の該当行をメッセージに添えて回帰の所在を示す。
- 補足: Amazon の公開「変換 API」は存在せず、KindleGen も提供終了（本環境にも無し）。自動検証の現実解は Kindle Previewer CLI のみ。`rake test:release`（RC 前総点検）の前段で手元実行する運用とする。

### 6-3. Rakefile

- `namespace :test` に `Rake::TestTask.new(:kindle)`（`pattern = "test/vivlio_starter/kindle/**/*_test.rb"`）を追加。`rake -T` の `custom_order` にも `test:kindle` を加える。
- `rake test`（既定・CI）には含めない。

---

## 7. 実装順序

1. **§2 中核**: `EpubBuilder.transcode_webp_images_for_epub!`（変換元選択 §1-1・形式判定 §1-2・staging 出力・src 差し替え）＋ `generate_epub_entries!` への組み込み。
2. **クリーン**: `images/_epub_assets/` を `clean.rb` のクリーン対象へ追加（§2-3）。
3. **§3 除外**: `build_copy_asset_excludes_config` に `**/*.webp` 追加（§3-1）＋ `sanitize_epub_css!` に `url(...webp)` 除去追加（§3-2）。
4. **§4 不正ファイル名検出**: src 収集の実体参照デコード（§4-1）＋ `guards/` 新ガード（3 ディレクトリ走査・改名案・出現箇所案内、警告のみ）を preflight / build へ組み込み（§4-3・§4-5）＋ import サニタイズ（任意・§4-5）。
5. **§6-1 軽量テスト**: トランスコード/ガードのユニット ＋ `target_consistency_test` への WebP ゼロ検査。
6. **§6-2 Kindle テスト**: `rake test:kindle` 新設（opt-in）。
7. 全章ビルド → `rake test:kindle`（手元）で W14015/W14012/W14010 消滅を実機確認 → クローズ判定。

---

## 8. 影響と非目標

- **影響**: epub 成果物のみ。PDF / print_pdf は不変（§0 二本柱-1）。EPUB サイズは（WebP 全除外＋必要画像のみ JPEG/PNG 化で）概ね減少見込み。
- **非目標**:
  - PDF 経路の画像形式変更（しない）。
  - 縦書き EPUB・フォント埋め込み（別件）。
  - `book.yml` での画像形式の設定 UI 化（§5 で拡張点コメントのみ。実装は将来）。
  - Kindle 以外のリーダー個別最適化（JPEG/PNG は全リーダー対応のため不要）。
  - 不正ファイル名の**自動リネーム**（ファイル＋参照の一括書き換え。§4-4。警告のみとし、将来別途検討）。
  - `covers/` / `stylesheets/images/` の**深い参照トレース**（行番号報告。§4-3。固定文言案内に留める）。
