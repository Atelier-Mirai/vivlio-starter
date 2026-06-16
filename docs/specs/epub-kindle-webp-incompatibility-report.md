# EPUB Kindle 変換不能（WebP 非対応）不具合報告書

> 作成日: 2026-06-15
> ステータス: **調査報告（仕様・実装は別途）**
> 対象: `vs build`（epub ターゲット）が生成する EPUB を Kindle Previewer で変換する経路
> 検出: Kindle Previewer の変換ログ `*-conversionLog.csv`
> 関連: `docs/specs/epub-kindle-compatibility-report.md`, `math-frontispiece-svg-spec.md` §B
> 優先度: **高**（EPUB の最重要ターゲットである Kindle / Amazon KDP で変換不能になる）

## 1. 概要

扉絵/節絵の合成画像化（§B）で「SVG 内 base64 埋め込み画像」のブロッキングエラーを解消した後も、
**Kindle Previewer での変換が完了しない**。変換ログを精査した結果、原因は **EPUB 内の画像が WebP
形式であること**だった。**Kindle（KindleGen / KFX 変換系）は WebP を画像フォーマットとして
サポートしていない。**

本プロジェクトはビルド時に画像を WebP へ最適化する（PDF のファイルサイズ削減に有効）。しかし
その WebP がそのまま EPUB にも同梱されるため、Kindle 変換時に**全画像が無効（未組み込み）**となる。

## 2. 変換ログの内訳

`vivlio_starter_v1.0.0-conversionLog.csv`（4 章サブセットビルド）には **109 件**の警告（すべて
「注意」レベル）があり、その実体はすべて WebP に関するもの。

| コード | 意味 | 件数（概数） |
| --- | --- | --- |
| W14015 | 画像が無効で、本に組み込まれていません | 大多数 |
| W14012 | メディアファイルフォーマットがサポートされていません | 数件 |
| W14010 | メディアファイルが見つかりません | 1 件（§4 の別件） |

EPUB 内の WebP は **108 ファイル**。所在別内訳:

| 所在 | 件数 | 種別 |
| --- | --- | --- |
| `stylesheets/twemoji/vs-techbook/*` | 24 | 囲み数字・見出しマーカー（techbook 絵文字画像） |
| `images/42-frontispiece/*` | 24 | 章扉の**背景**画像（§B 後は EPUB で不要・§5-3） |
| `images/71-emoji/*` | 16 | ロゴ・絵文字関連 |
| `stylesheets/images/bundled/*` | 14 | 同梱テーマ画像（sakura 等の扉絵/節絵背景） |
| `images/<章>/*` | 約 25 | 本文中のコンテンツ画像（写真・図） |
| `stylesheets/images/*` | 5 | テーマ画像 |

> 注: 「注意」レベルだが**件数が多く（＝事実上すべての画像が無効）**、結果として Kindle Previewer が
> 変換を完了できない。数式の SVG（82 ファイル）は base64 を含まない素の SVG のため Kindle で問題ない。
> §B の扉絵/節絵は JPEG 化済みのため問題ない（本件の対象外）。

## 3. 原因

- **Kindle は WebP 非対応**（公式に未サポート）。EPUB 3 規格自体は WebP を許容し epubcheck も通るが、
  Kindle の変換系は WebP を読めず「無効な画像」として破棄する。
- 本 gem の画像最適化は WebP を既定の最適化先にしている（PDF 向けには妥当）。EPUB（特に Kindle）向けには
  **JPEG / PNG**（Kindle 対応フォーマット）へ変換する必要がある。

## 4. 付随する別件（W14010・アポストロフィを含むファイル名）

```
W14010: メディアファイルが見つかりません … images/94-sample/Einstein&apos;s_later_years.webp
```

ファイル名にアポストロフィ（`'`）を含む画像で、HTML の `src` 側が `&apos;`（HTML 実体参照）に
なっており、**Kindle がパスを解決できず「見つからない」**になっている疑い。WebP 対応とは独立した
小さな不具合として、ファイル名のサニタイズまたは `src` のエンコード整合を別途確認する。

## 5. 想定される修正方針（実装は別途）

本件は**画像最適化パイプライン全体に関わる**ため、§B（扉絵/節絵）より広いスコープ。方針案:

1. **EPUB 経路で WebP → JPEG/PNG へトランスコード（推奨）**: EPUB ビルド時（`EpubBuilder` の Step E、
   または専用後処理）に、同梱対象の WebP を **写真＝JPEG / 透過ありの図版＝PNG** へ変換し、各 XHTML の
   `<img src="….webp">` を変換後の拡張子へ書き換える。PDF 経路は WebP のまま（無影響）。§B の扉絵
   ラスタライズ（rsvg/magick で JPEG 生成）と同じ「EPUB 専用に画像形式を変える」発想の一般化。
   - キャッシュ・クリーン対象の追加、`copyAsset.excludes` での元 WebP 除外を伴う。
2. **囲み数字・見出しマーカー（twemoji/vs-techbook の 24 枚）**: 絵文字本体は既に EPUB で
   プレーン文字へ復元済み（`restore_plain_emoji_for_epub!`）。囲み数字（`vs-circled-number`）と
   見出しマーカーは画像のまま残るため、これらも PNG 化するか、可能なら文字/別表現へ置換する。
3. **不要な背景画像の除外**: `images/42-frontispiece/*` と `stylesheets/images/bundled/*` の扉絵/節絵
   **背景** WebP は、§B で合成 JPEG に置き換わった後は **EPUB では描画されない**（CSS 背景は無効）。
   `copyAsset.excludes` で EPUB から除外すれば、無効画像（W14015）と EPUB サイズの双方を削減できる
   （§B の比較的小さな後続改善として単独でも着手可能）。
4. **W14010（アポストロフィ）**: 画像ファイル名のサニタイズ（`'` を含めない）か、`src` 生成時の
   エンコード整合を修正。

## 6. 影響と優先度

- **最優先ターゲットでの致命的問題**: プロジェクトの方針上 EPUB は Kindle / Amazon を最重視
  （`epub-kindle-compatibility-report.md`）。その Kindle で**変換不能＝出版不可**になるため、RC までに
  解消が必要。
- §B（扉絵/節絵 JPEG 化）と §A（数式 SVG）は本件の影響を受けない（既に Kindle 対応形式）。
- epubcheck は WebP を許容するため**本件は epubcheck では検出されない**（Kindle 固有）。
  リリース検証に **Kindle Previewer（または KFX 変換）での画像有効性チェック**を加えることを推奨。

## 7. 次のアクション

1. 本報告を基に仕様書を起こし、§5-1（EPUB 画像トランスコード）を中心に実装する。
2. 着手しやすい §5-3（不要背景 WebP の除外）と §5-4（アポストロフィ）は先行して個別に対応してもよい。
3. 全章ビルドの EPUB を Kindle Previewer で再検証し、W14015/W14012/W14010 が消えることを確認する。
