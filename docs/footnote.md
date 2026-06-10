# sideimage 内脚注の不具合と課題

> **【解決済み 2026-06】** 本ドキュメントが扱う重複表示問題は解決した。
>
> **真の根本原因**: Vivliostyle は、脚注参照リンク（`<a href="#fnN">`）の解決先要素が
> `float: footnote` の `aside` 自体である場合、参照のあるページと `aside` のあるページの
> **両方**に同じ脚注を描画する。通常の段落脚注が無事だったのは、参照直後に挿入される
> 不可視のインライン脚注 `span#fnN`（`page-footnote-inline`、`display: none`）が
> 文書順で `aside` より先にあり、リンクの解決先になっていたため。
>
> **修正内容**:
> 1. `process_sideimage_footnotes!`（`post_process.rb`）が生成する `<sup><a>` 参照の直後に、
>    通常脚注と同じ不可視 `span#fnN` を挿入し、リンクの解決先にする。
> 2. 段落外参照（テーブルセル内など）を処理する `insert_print_footnote_after_anchor!`
>    （`footnote_converter.rb`）でも同様に不可視 span を挿入する
>    （テーブル内リンクの脚注が3回重複表示される不具合も同根で、これで解消）。
> 3. これにより `float: footnote` が安全になったため、`page-footnote-endnote`
>    （セクション末尾へのブロック表示）を廃止し、sideimage 内の脚注も他の脚注と同様に
>    **ページ下部**に表示されるようになった。`aside` は sideimage コンテナの直後に
>    配置される（`move_body_asides_near_references!`）ため、参照と同じページに収まり、
>    脚注番号もドキュメント出現順に並ぶ。
>
> 以下は調査当時の記録として残す。

## 概要

sideimage コンテナ（`:::{.sideimage-right}` 等）内にリンクを含む場合、脚注URLが重複表示される・番号が順不同になる不具合がある。2026年4月時点で部分的な改善は達成したが、完全な解消には至っていない。

## 症状

`00-preface.md` の謝辞・著者紹介セクションで再現する。

**期待される出力（4つの脚注、各1回ずつ）:**
```
2. https://kauplan.org/reviewstarter/
3. https://vivliostyle.org/
4. https://hiromu-hayase.tumblr.com
5. https://atelier-mirai.net/
```

**実際の出力（重複・順不同）:**
```
2. https://kauplan.org/reviewstarter/
4. https://hiromu-hayase.tumblr.com
3. https://vivliostyle.org/
3. https://vivliostyle.org/   ← 重複
5. https://atelier-mirai.net/
```

## 処理パイプラインの全体像

脚注は以下の3段階で処理される。

### 1. 前処理（Markdown → 中間 Markdown）

**`transform_links_to_footnotes`** が `[text](url)` を `[text](url) [^urlN]` + 脚注定義に変換する。

```markdown
:::{.sideimage-right}
Vivlio Starter の開発は、[Re:VIEW Starter](https://kauplan.org/reviewstarter/) に触発された…
:::
```
↓
```markdown
:::{.sideimage-right}
Vivlio Starter の開発は、[Re:VIEW Starter](https://kauplan.org/reviewstarter/) [^url1] に触発された…
:::

[^url1]: https://kauplan.org/reviewstarter/
```

**`expose_container_footnotes!`** が VFM 用の非表示参照を追加する。VFM は `:::` コンテナ内の `[^urlN]` を認識しないため、コンテナ外に `<span class="footnote-anchor">` を挿入して VFM に脚注定義を認識させる。

```markdown
<span class="footnote-anchor" style="display:none">[^url1][^url2][^url3][^url4]</span>

[^url1]: https://kauplan.org/reviewstarter/
[^url2]: https://vivliostyle.org/
...
```

### 2. VFM（中間 Markdown → HTML）

VFM が `section.footnotes` に `fn1`〜`fn5` の脚注定義を生成する。

- `fn1`: 対象読者の注（通常の `[^1]`）
- `fn2`〜`fn5`: URL脚注（`footnote-anchor` span 経由で認識）

VFM は sideimage コンテナ内の `[^urlN]` と `footnote-anchor` span 内の `[^urlN]` の**両方**から `<a class="footnote-ref">` を生成する。

### 3. 後処理（HTML → 最終 HTML）

**`footnote_converter.rb`** が `section.footnotes` を解体し、各参照の近くに `aside.page-footnote-print` を配置する。

**`process_sideimage_footnotes!`** が sideimage-body 内の `[^urlN]` テキストを `<sup><a>` に変換する。

**`renumber_footnotes_by_document_order!`** が脚注番号を出現順に振り直す。

## 根本原因：Vivliostyle の `float: footnote` の挙動

### 問題の核心

CSS 組版エンジン Vivliostyle は `aside.page-footnote { float: footnote; }` を処理するとき、以下の挙動を示す。

1. `<a href="#fn2">` がページ A に表示される → Vivliostyle は「ページ A に fn2 の脚注を表示すべき」と判断
2. `aside#fn2` がページ B（セクション末尾）に配置されている → Vivliostyle は「ページ B にも fn2 の脚注を表示すべき」と判断
3. **結果として、参照のあるページと aside のあるページの両方に同じ脚注が表示される**

### なぜ sideimage 内の脚注だけが問題になるか

通常の段落内の脚注では、`aside` が段落の直後に配置されるため、参照と `aside` が同じページに収まる。しかし sideimage 内の脚注では：

- `aside` を sideimage 内に配置すると CSS Grid レイアウトが壊れる
- `aside` を sideimage の外に配置すると、参照と `aside` が別ページになる可能性がある
- `aside` をセクション末尾に配置すると、確実に別ページになる

**つまり、sideimage 内の脚注は `aside` の配置位置をどこにしても `float: footnote` による重複表示を完全には防げない。**

## 試みた修正と結果

### 修正1: `footnote-anchor` span 内の参照をスキップ

**変更箇所:** `footnote_converter.rb` の `insert_footnotes_for_references!` / `fill_missing_footnote_references!`

**効果:** `#fn5` などの不正な脚注（内部リンクが脚注本文になる問題）は解消された。

**残った問題:** URL脚注の重複表示は解消されなかった。

### 修正2: `inferred_body_from_previous_link` で外部URLのみ対象

**変更箇所:** `footnote_converter.rb` の `inferred_body_from_previous_link`

**効果:** `#fn5`, `#fn6`, `#fn7` のような内部リンクが脚注本文として生成される問題は解消された。

**残った問題:** URL脚注の重複表示は解消されなかった。

### 修正3: `aside` の配置位置を変更

sideimage の直後、セクション末尾、body 末尾など様々な配置を試みた。

**結果:** どの配置でも Vivliostyle の `float: footnote` による重複表示は解消されなかった。配置位置を変えると重複のパターンが変わるだけで、根本的な解決にはならなかった。

### 修正4: `page-footnote-endnote` クラスで `float: footnote` を無効化

**変更箇所:** `components.css` に `aside.page-footnote.page-footnote-endnote { float: none; }` を追加

**効果:** 重複表示は解消されたが、脚注がページ下部ではなくセクション末尾にブロック表示されるようになった。ユーザーの要件（ページ下部に表示）を満たさない。

### 修正5: `normalize_definition_ids!` で VFM の ID を正規化

**変更箇所:** `footnote_converter.rb` に `normalize_definition_ids!` を追加

**効果:** VFM が `section.footnotes` に割り当てる ID（`fn1`〜`fn5`）と `footnote-anchor` span 内の参照 ID の対応付けが正しくなった。

**残った問題:** ID の対応は正しくなったが、`float: footnote` による重複表示は解消されなかった。

### 修正6: `update_footnote_definitions` の2段階更新

**変更箇所:** `post_process.rb` の `update_footnote_definitions` を一時 ID 経由の2段階更新に変更

**効果:** 脚注番号の入れ替わり（fn4 と fn5 が逆になる問題）は解消された。

**残った問題:** `float: footnote` による重複表示は解消されなかった。

## 現在の実装状態

### 改善された点
- `#fn5`, `#fn6`, `#fn7` のような不正な脚注は表示されなくなった
- 脚注の内容（URL）は正しく対応している
- `footnote-anchor` span は最終 HTML から削除されている
- sideimage 内の脚注に `page-footnote-endnote` クラスが付与され、`float: none` で表示される

### 残っている問題
- sideimage 内の脚注がページ下部ではなくセクション末尾にブロック表示される
- `float: footnote` を使うと重複表示が発生する（Vivliostyle の仕様/制約）

## 変更ファイル一覧

| ファイル | 変更内容 |
|---------|---------|
| `lib/vivlio/starter/cli/post_process/footnote_converter.rb` | `footnote-anchor` span スキップ、`inferred_body_from_previous_link` の外部URL限定、`normalize_definition_ids!` 追加、`build_print_footnote_node` に `endnote:` パラメータ追加、`find_sideimage_container` 追加、sideimage 内脚注のセクション末尾配置 |
| `lib/vivlio/starter/cli/post_process.rb` | `renumber_footnotes_by_document_order!` で常に `remove_footnote_anchors` 実行、`update_footnote_definitions` の2段階更新、`move_body_asides_to_last_section!` 追加、`remove_footnote_anchors` で `p.footnote-anchor` も削除 |
| `lib/vivlio/starter/cli/pre_process/markdown_preprocessor.rb` | `expose_container_footnotes!` のコメント更新（ロジック変更なし） |
| `stylesheets/components.css` | `aside.page-footnote.page-footnote-endnote` ルール追加（`float: none`） |
| `lib/project_scaffold/stylesheets/components.css` | 同上（scaffold 同期） |

## 将来の解決に向けた考察

### アプローチ A: Vivliostyle 側の対応を待つ

Vivliostyle の `float: footnote` が「参照と同じページにのみ脚注を表示する」挙動に修正されれば、現在の HTML 構造のままで問題が解消される。Vivliostyle の GitHub Issues で報告・議論する価値がある。

### アプローチ B: sideimage 内のリンクを脚注化しない

`transform_links_to_footnotes` で sideimage コンテナ内のリンクを脚注化の対象外にする。リンクテキストとURLが同じ場合（`[早瀬ひろむ](https://...)` のように表示テキストとURLが異なる場合）は脚注化が有用だが、印刷時にURLが見えなくなるトレードオフがある。

### アプローチ C: JavaScript による脚注の後処理

Vivliostyle のビルド後に、生成された PDF の脚注を JavaScript（Playwright 等）で後処理し、重複を除去する。技術的には可能だが、ビルド時間が増加する。

### アプローチ D: `footnote-call` / `footnote-marker` CSS カウンターの活用

CSS の `counter-increment: footnote` と `::footnote-call` / `::footnote-marker` 疑似要素を使って、`float: footnote` に頼らない脚注表示を実装する。Vivliostyle がこれらの CSS 仕様をどこまでサポートしているか要調査。

### アプローチ E: `aside` を参照と同じ `<p>` 内に配置

`aside` を `<p>` タグ内にインラインで配置し、CSS で `float: footnote` を適用する。`<p>` 内の `aside` は段落と同じページに配置されるため、重複が発生しない可能性がある。ただし HTML の仕様上 `<p>` 内に `<aside>` を配置するのは不正であり、Vivliostyle がどう処理するか不明。

### アプローチ F: `expose_container_footnotes!` の廃止

`expose_container_footnotes!` を廃止し、VFM に脚注定義を認識させる仕組みを根本から変える。例えば、前処理の段階で sideimage コンテナ内の `[^urlN]` をコンテナの外に移動し、VFM が直接認識できるようにする。ただし VFM は `[^urlN]` が段落内のインラインテキストとして存在する必要があるため、単純にコンテナ外に移動するだけでは認識されない。

## 再現手順

```bash
cd vivlio-starter
rake reinstall
vs clean --all
vs build 00 --log=debug --no-clean > build.log
# 00-preface.pdf を開いて謝辞・著者紹介セクションの脚注を確認
# 00-preface.html を確認して aside の配置を確認
```

## 関連ファイル

- `contents/00-preface.md` — 再現用の原稿（謝辞・著者紹介に sideimage + リンク）
- `lib/vivlio/starter/cli/pre_process/markdown_transformer.rb` — `transform_links_to_footnotes`
- `lib/vivlio/starter/cli/pre_process/markdown_preprocessor.rb` — `expose_container_footnotes!`
- `lib/vivlio/starter/cli/post_process/footnote_converter.rb` — 章末脚注→ページ脚注変換
- `lib/vivlio/starter/cli/post_process.rb` — `process_sideimage_footnotes!`, `renumber_footnotes_by_document_order!`
- `stylesheets/components.css` — `.page-footnote` / `.page-footnote-endnote` スタイル
- `config/post_replace_list.yml` — HTML 置換ルール
