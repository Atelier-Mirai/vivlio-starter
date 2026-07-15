# Kindle（KFX）CSS 対応状況と実装知見メモ

> 作成日: 2026-06-21
> ステータス: **知見メモ（恒久参照）**
> 対象: Kindle ターゲット（`target=kindle`）の EPUB→KPF 変換で得られた、Kindle 表示エンジンの CSS/画像対応状況と回避策。
> 関連: `epub-kindle-target-split-spec.md`（ターゲット分離）, `kindle-simple-header-svg-spec.md`（付録見出しの SVG 化・将来タスク）, `epub-code-line-numbers-spec.md`（コード行番号）, `stylesheets/`（各 `body.vs-kindle` フォールバック）, `lib/vivlio_starter/cli/build/epub_builder.rb`

---

## 0. 背景と目的

Kindle 対応（クリーン EPUB と Kindle 用 KPF のターゲット分離）の実装過程で、**Kindle の表示エンジンが非常に古い CSS サブセットにしか対応していない**ことが繰り返し問題になった。`var()` / `position:absolute` / `::before`・`::after` / CSS Grid / WebP など、EPUB 3.3 で広く使われる機能の多くが解されず、ルールごと破棄されたり画像が参照切れになったりして、レイアウトが素テキストに崩れる。

本メモは、今後 Kindle 向けの CSS・画像処理を編集・拡張する開発者が**同じ落とし穴を踏まないよう**、判明した対応状況・原因・回避策・実装上の知見を一箇所に集約するものである。個々の機能仕様ではなく「Kindle という環境の癖」を記録する位置づけ。

---

## 1. Kindle の表示エンジンと前提

- Kindle の現行レンダリングは **KFX / Enhanced Typesetting**。KDP に EPUB（や本プロジェクトの KPF）をアップロードすると、Amazon 側で KFX へ再変換される。
- 本プロジェクトは中間 EPUB を生成し、**Kindle Previewer 3 同梱の `kindlepreviewer` CLI** で `.kpf` に変換する（`convert_epub_to_kpf!`）。実機・Previewer での表示が「正」であり、epubcheck が通っても Kindle で崩れることは普通にある。
- **検証は必ず Kindle Previewer 3／実機で行う。** epubcheck の合格は KFX での正しい表示を保証しない（別レイヤーの検証）。
- KPF 変換ログのエラー/警告コード（`E####` / `W####`）は `summarize_kpf_logs` が内訳集計する。例: `W14016`＝`embed:false` 時の "Cover not specified" 通知（表紙は KDP 側で付けるため想定内）。

---

## 2. CSS 対応状況一覧（今回判明分）

「Kindle」列は KFX / Enhanced Typesetting での挙動。「クリーン EPUB（Kobo/Apple Books）」では下記はいずれも問題なく解される。

| CSS 機能 | Kindle(KFX) | 症状 | 本プロジェクトの回避策 |
|:---|:---:|:---|:---|
| `:is()` セレクタ | ❌ | **ルールごと丸ごと破棄**される | `body.vs-kindle` 用は明示セレクタへ展開（`a::before, b::before, …`） |
| `var()`（カスタムプロパティ） | ❌ | 値が解決されず無効化 | `body.vs-kindle` フォールバックは**具体値**で記述 |
| `calc()` / `clamp()` | ❌ | 無効化 | 具体値で記述 |
| `display: grid` | ❌ | グリッドにならず縦積み | `display: block` 等の素直なフローに縮退 |
| `::before` / `::after`（特に `position:absolute`） | ❌ | ラベル帯・装飾が出ない／重複ラベル化 | Kindle では擬似要素を抑止し、**実体要素を EpubBuilder が先頭注入** |
| `linear-gradient()` | ❌ | 背景が出ない | 単色 `background` / `border` で代替 |
| WebP 画像（`<img>` / CSS `url()`） | ❌ | 画像が表示されない・参照切れ | JPEG/PNG へトランスコード＋インライン WebP 宣言を除去 |
| modern 改ページ `break-before: page` | △ | 効かないことがある | legacy `page-break-before: always` を**併記** |
| テーブルセルの `width` / `white-space:nowrap` | △ | 尊重されず、2桁行番号が縦に折れる等 | テーブル方式のレイアウトに依存しない（行番号は別仕様で検討） |

> ❌＝非対応（解されない）、△＝不安定（端末/状況で挙動が変わる）。

### 補足: なぜ `:is()` が一番危険か

`:is()` は **マッチしない・無効化される**のではなく、**そのCSSルール全体がパース時に捨てられる**。つまり `body.vs-kindle :is(.tip,.memo,.column) { … }` と書くと、Kindle ではその枠線・余白指定が丸ごと消え、装飾なしの素の段落になる。共通CSS（クリーン EPUB/PDF 用）で `:is()` を使うのは構わないが、**Kindle 専用フォールバックでは絶対に使わない**。明示セレクタへ展開すること。

---

## 3. 画像形式（WebP 非対応）の扱い

Kindle は WebP を表示できない。`vs build` の画像最適化は WebP を生成するため、Kindle フレーバでは二段構えで対処する。

1. **実体のトランスコード**（`transcode_webp_images_for_epub!`）: `<img>` が参照する WebP を JPEG/PNG に変換し、参照を貼り替える。
2. **インライン CSS 宣言の除去**（`strip_webp_inline_styles_for_kindle!`）: techbook テーマが `<head>` に注入する `<style>` 内の `--h3-marker: url(...webp)` 系を削除。
   - パターンは `INLINE_WEBP_DECL_PATTERN = /[\w-]+\s*:\s*[^;{}]*url\([^)]*\.webp[^)]*\)[^;}]*;?/i`。
   - **教訓**: カスタムプロパティ名は `[\w-]+` で**丸ごと**拾うこと。`[a-zA-Z-]+` だと `--h3-marker` の `-marker` だけ消えて `--h3` 断片が残り、別の CSS エラー（CSS-008）を誘発した。
   - **教訓**: 正規表現リテラルは `%r{...}` ではなく `/.../` を使う。宣言値の `[^;{}]` に含まれる `{}` が `%r{}` の区切りと衝突する。
3. **同梱からの除外**（`build_copy_asset_excludes_config(flavor:)` / `sanitize_epub_css!(flavor:)`）: Kindle フレーバのときのみ `images/**/*.webp`・`stylesheets/**/*.webp` を除外し、CSS の WebP `url()` も除去する。
   - **教訓**: これは**フレーバ依存**にすること。当初 WebP を常時除外したらクリーン EPUB（WebP 同梱が正）で参照切れが起きた。クリーン EPUB は WebP を**残す**。

---

## 4. 個別に踏んだ不具合と対処（実例）

実装デバッグで実際に遭遇したものを、再発防止のため記録する（詳細経緯は CHANGELOG / 当時のデバッグメモ参照）。

| 症状（Kindle） | 原因 | 対処 |
|:---|:---|:---|
| TIP/MEMO/COLUMN の枠線が出ず「TIP」ラベルが重複 | `:is()` でルール破棄＋`::before` ラベルが効かない | `body.vs-kindle` で明示セレクタ展開・`::before` 抑止・実体ラベル注入・具体色枠線（`chapter-common.css`） |
| 節（節絵）がページ途中から始まる | modern `break-before` 非対応 | `article.vs-section-topic-epub` に `page-break-before: always` 併記（`components.css`） |
| 付録（simple スタイル）の見出しが素テキスト化 | `var()`/`grid`/`clamp()`/`::before` 多用 | `simple-header.css` に `body.vs-kindle` 具体値フォールバック（恒久策は SVG 画像化＝将来タスク） |
| 用語集・後書き・索引の h1 下線が消える | テーマ装飾が var()/擬似要素依存 | `glossary.css`/`index.css`/`preface.css` に具体色の下線フォールバック |
| book-card がグリッド崩れ | `display:grid` 非対応 | `body.vs-kindle .book-card { display:block }`（`components.css`） |
| コードブロックが特定幅でクリップ消失（Apple Books） | リフロー文脈での折り返し未指定 | **クリーン EPUB 側**の `body.vs-epub pre[class*="language-"]{ white-space:pre-wrap; overflow:visible }`（`code.css`）。Kindle ではなく EPUB 共通マーカー側の対処 |
| 数式が極大表示／表内数式が崩れる | 単位・レイアウトの解釈差 | `convert_math_units_for_epub!` で単位変換。表内数式は原稿側で回避（テキスト化）も検討 |

---

## 5. 実装アーキテクチャ上の知見

### 5.1 フレーバ分離と body マーカー

- `generate_epub_entries!(base_dir, entries, flavor:)` が `:epub` / `:kindle` を受け取り、共通フェーズ＋Kindle 限定フェーズを切り替える。
- **body マーカーで CSS を出し分ける**のが基本設計:
  - `mark_body_for_epub!` → `vs-epub`（**両フレーバ**に付く。EPUB リフロー文脈の印）
  - `mark_body_for_kindle!` → `vs-kindle`（**Kindle のみ**。劣化変換を施した印）
- **PDF には付かない**ため、`body.vs-epub` / `body.vs-kindle` の CSS は PDF 出力に一切影響しない。安全に追記できる。
- CSS 編集時の原則:
  - クリーン EPUB/PDF 向けの装飾は従来どおり（`:is()`/`var()` 等を使ってよい）。
  - Kindle 向け調整は **`body.vs-kindle` セレクタ配下に、§2 の禁止機能を避けた具体値で**追記する。

### 5.2 「CSS で無理なら画像」戦略

Kindle で CSS による装飾が信頼できない箇所は、**合成画像に焼き込んで `<img>` 注入**するのが最も確実。

- 扉絵（h1）・節絵（h2）は `HeadingImageComposer` で「飾り画像＋見出し文字」を1枚に合成する。
  - クリーン EPUB: `HeadingImageComposer.compose`（**SVG**。Kobo/Apple は SVG を解すので高品質・検索可）
  - Kindle: `HeadingImageComposer.render`（**JPEG ラスタライズ**。CSS 非依存で確実）
  - 出し分けは `heading_image_src(..., flavor:)`。ハッシュ鍵に `flavor` を含めキャッシュを分離。
- 付録など simple スタイル見出しの恒久対策（同方式の SVG→JPEG 化）は `kindle-simple-header-svg-spec.md` に将来タスクとして記載。

### 5.3 クリーン EPUB を汚染しない（方式B）

- パイプライン（`pipeline.rb`）は、章 HTML を**スナップショット**してから `:epub` フレーバでビルドし、**スナップショットを復元**してから `:kindle` フレーバでビルドする。
- これにより Kindle 用の破壊的変換（WebP トランスコード・マーカー付与・装飾置換）がクリーン EPUB に混入しない。
- クリーン EPUB は WebP・SVG をそのまま活かした高品質版、Kindle は確実表示優先の劣化版、という役割分担を崩さない。

### 5.4 KPF 変換まわり

- `kindlepreviewer_available?`（`which` で存在確認）が false なら、中間 EPUB を残して変換をスキップし警告（ビルド自体は止めない）。
- `vs doctor` は `kindlepreviewer` を**任意ツールとして診断**する（導入済みは `✅`、未導入は 🟡 案内でハードエラーにはしない）。macOS では `vs doctor --fix` が Homebrew cask `kindle-previewer` を導入し、アプリ内 CLI を呼ぶラッパーを Homebrew の bin へ作成して PATH を通す。
- 表紙は `kindle.embed: false`（既定）。Kindle は本文に表紙を埋めると KDP 側表紙と二重化するため、表紙は KDP 管理画面でアップロードする運用。

---

## 6. 今後の開発ガイドライン（チェックリスト）

Kindle 向けに CSS / 画像処理を追加・変更するときは:

- [ ] その装飾は **`body.vs-kindle` 配下**に書いたか（クリーン EPUB/PDF を巻き込んでいないか）。
- [ ] `:is()` / `var()` / `calc()` / `clamp()` / `grid` / `linear-gradient` / `::before(position:absolute)` を**使っていない**か。
- [ ] 改ページは `page-break-before: always` を**併記**したか。
- [ ] 新規画像が WebP のまま Kindle に渡っていないか（トランスコード／除外の対象になっているか）。
- [ ] CSS で確実性が出ないなら、**画像化（合成 SVG→JPEG）**を検討したか。
- [ ] WebP を扱う正規表現は `/.../` リテラル・`[\w-]+`（プロパティ名を丸ごと）になっているか。
- [ ] フレーバ依存の除外/サニタイズは `flavor:` 引数で分岐し、クリーン EPUB を壊していないか。
- [ ] **Kindle Previewer 3／実機**で表示確認したか（epubcheck 合格だけで判断しない）。

---

## 7. 参考

- `lib/vivlio_starter/cli/build/epub_builder.rb` — フレーバ分離・WebP 処理・マーカー・KPF 変換の実装本体。
- `lib/vivlio_starter/cli/build/heading_image_composer.rb` — 見出し合成画像（`compose`=SVG / `render`=JPEG）。
- `lib/vivlio_starter/cli/build/pipeline.rb` — スナップショット方式（方式B）とステップ登録。
- `stylesheets/chapter-common.css` / `components.css` / `simple-header.css` / `glossary.css` / `index.css` / `preface.css` / `code.css` — `body.vs-kindle` / `body.vs-epub` フォールバック。
- `docs/specs/epub-kindle-target-split-spec.md` — ターゲット分離の全体設計。
- `docs/specs/kindle-simple-header-svg-spec.md` — 付録見出しの SVG 画像化（将来タスク）。
- `docs/archives/epub-code-line-numbers-spec.md` — コード行番号と Kindle テーブルの不具合（実装済み）。
