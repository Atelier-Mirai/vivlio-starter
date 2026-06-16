# EPUB 用語集・索引 XHTML 妥当性 不具合報告書

> 作成日: 2026-06-15
> ステータス: **調査報告（仕様・実装は別途）**
> 対象: `vs build`（epub ターゲット）が生成する `_glossarypage.xhtml` / `_indexpage.xhtml`
> 検出: epubcheck 3.3（EPUB 3.3 ルール）で ERROR
> 関連: `docs/specs/epub-pipeline-fix-spec.md`（epubcheck ERROR 0 達成済みの前提を回復するための課題）

## 1. 概要

EPUB を epubcheck で検証すると、**用語集（`_glossarypage.xhtml`）と索引（`_indexpage.xhtml`）に
合計 4〜6 件の ERROR** が出る。本文章・扉絵/節絵（§B）・数式 SVG（§A）の XHTML は ERROR 0 であり、
本件は用語集・索引ページに限定された構造の問題である。Kindle 変換（W14015 等）とは別系統。

検出される ERROR は次の 2 種。

| コード | ファイル | 概要 |
| --- | --- | --- |
| RSC-005 | `_glossarypage.xhtml` | `<dl>` 直下に**テキストを持つ `<div>`**（グループ見出し）があり、XHTML5 の `<dl>` 内容モデル違反 |
| RSC-012 | `_indexpage.xhtml` | バックリンクの**フラグメント識別子が未定義**（参照先 id が当該ビルドに存在しない） |

## 2. RSC-005（用語集）— `<dl>` 直下の見出し `<div>`

### 2-1. 実際のエラー

```
ERROR(RSC-005): _glossarypage.xhtml(89,75): テキストはここには書けません.
                ここに書かれるべきものは 要素 "dt", "script" または "template" です.
ERROR(RSC-005): _glossarypage.xhtml(89,81): 要素 "div" の内容が不完全です. 必要な要素 "dt" がありません.
ERROR(RSC-005): _glossarypage.xhtml(90,40): 要素 "dt" をここに書いてはいけません.
ERROR(RSC-005): _glossarypage.xhtml(93,33): 要素 "dd" をここに書いてはいけません.
```

### 2-2. 該当マークアップ

```html
<dl class="glossary-list">
  <div class="glossary-group-header" role="heading" aria-level="2">A-Z</div>  <!-- ← 問題 -->
  <dt id="gls-pdf" class="glossary-term">…</dt>
  <dd class="glossary-definition">…</dd>
  …
</dl>
```

### 2-3. 原因

HTML5/XHTML5 の `<dl>` の内容モデルは「`<dt>`/`<dd>` の並び」または「それらを**グループ化する
`<div>`**」のみを許す。`<dl>` 直下に `<div>` を置くこと自体は許されるが、その `<div>` は
**`<dt>`/`<dd>` を内包するグループ**でなければならない。本件の `<div class="glossary-group-header">`
は **テキスト「A-Z」だけを持つ見出し**であり、`<dt>` を含まないため不正。これにより
「div の内容が不完全（dt が無い）」「div の後の dt/dd がここに書けない」という連鎖エラーになる。

生成元: `lib/vivlio_starter/cli/index/unified_page_builder.rb:309`

```ruby
entries << %(<div class="glossary-group-header" role="heading" aria-level="2">#{initial}</div>)
```

頭文字（A-Z / あ行…）ごとのグループ見出しを `<dl>` の中に直接差し込んでいる。

### 2-4. 想定される修正方針（実装は別途）

いずれも見出しを `<dl>` の**内容モデルに適合**させる案。

1. **グループ見出しを `<dl>` の外に出す**（推奨）: 頭文字ごとに「見出し（`<h2>` か `<p role="heading">`）
   ＋ その文字の用語だけを含む `<dl>`」を 1 セットにして繰り返す。最も素直で妥当。
2. **グループ化 `<div>` を正しく使う**: `<dl>` 直下の `<div>` に、見出しと当該グループの `<dt>`/`<dd>` を
   **すべて内包**させる（`<div><p ...>A-Z</p><dt>…</dt><dd>…</dd>…</div>`）。見出しを `<dt>`/`<dd>` 以外の
   要素にすれば妥当。ただし入れ子が深くなる。
3. **PDF 経路への影響に注意**: 用語集は PDF・EPUB で共有 HTML を使うため、PDF のレイアウト（CSS）への
   影響を確認したうえで変更する。EPUB 専用後処理（`EpubBuilder` の `*_for_epub!` 群）で EPUB 側だけ
   構造を組み替える方法もある（PDF 無影響・既存の align 変換等と同じ安全設計）。

## 3. RSC-012（索引）— 未定義フラグメント

### 3-1. 実際のエラー（例）

```
ERROR(RSC-012): _indexpage.xhtml(92,179): フラグメント識別子が定義されていません.
```

### 3-2. 原因

索引の各項目は本文中の出現箇所へ `…#idx-<hash>-<n>` でリンクするが、**そのフラグメント（id）が
当該 EPUB に含まれない**場合に RSC-012 になる。今回の検出は **章のサブセットビルド**（4 章のみ）で
発生しており、リンク先の id が「ビルド対象外の章」や「未生成のアンカー」を指していたためと考えられる。
全章をそろえる通常のリリースビルドでは発生しない可能性が高いが、確証のため次を確認する必要がある。

- 全章ビルドの EPUB で RSC-012 が出ないか（サブセット固有か恒常か）。
- 索引アンカー（`#idx-…`）が本文 HTML 側に確実に出力されているか（出現箇所の id 付与漏れの有無）。

### 3-3. 想定される修正方針（実装は別途）

- 恒常的に出る場合: 索引リンクの生成時に、**参照先 id が実在するエントリだけをリンク化**する
  （存在しない参照は素のテキストにフォールバック）。
- サブセット固有の場合: ドキュメントに「索引付き EPUB は全章ビルドで検証する」旨を明記し、
  リリーステスト（`rake test:targets` / epub 検証）で全章ビルドを対象にする。

## 4. 影響と優先度

- **出版可否**: epubcheck ERROR は厳密には規格違反だが、多くのリーダーは寛容に表示する。ただし
  Amazon/Apple へ出稿する際の検証で弾かれ得るため、RC までに ERROR 0 へ戻すのが望ましい
  （`epub-pipeline-fix-spec.md` で一度達成済みの品質基準の回復）。
- **本件は用語集・索引に限定**。本文・扉絵/節絵・数式の XHTML は妥当（ERROR 0）。
- Kindle 変換失敗（WebP 非対応）とは**別系統**（そちらは別報告書を参照）。

## 5. 次のアクション

1. 全章ビルドの EPUB で epubcheck を取り、RSC-005（恒常）と RSC-012（サブセット固有か）の切り分けを行う。
2. 本報告を基に仕様書を起こし、用語集グループ見出しの構造修正（§2-4 案 1 推奨）と索引リンクの
   存在チェック（§3-3）を実装する。
