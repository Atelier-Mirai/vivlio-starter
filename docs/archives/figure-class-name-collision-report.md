# `.figure` クラス名の衝突に関する調査報告

> 作成日: 2026-07-17
> ステータス: **解決済み（2026-07-18・案 A を採用）** — 新設枠を `.figure` → `.diagram` へ改名。同日、死んだ `.figure` クラスセレクタの掃除（`:is(.figure, figure)` → `figure`・`.figure.right` 削除・layout-utils の `:not()` リスト整理）も実施し、`.figure` クラスは CSS から完全に消滅。特異度低下で layout-utils の `.align-*`（0,1,0）が図版の `margin-block: 4mm` に勝つ問題は `figure:is(.align-left, .align-center, .align-right)` の明示ルールで保全。
> 目的: 新設した `:::{.figure}`（図・アスキーアートの枠）が、既存の `.figure`（図版）スタイルと**名前衝突**している件について、実態と選択肢を整理し、仕様検討の資料とする。
> 関連ファイル: `stylesheets/chapter-common.css`（既存 `.figure` 図版スタイル・新設 `.figure` 枠スタイル）, `lib/vivlio_starter/cli/prism_lines.rb`（`.figure` 配下の行番号免除）, `lib/vivlio_starter/cli/pre_process/cross_reference_processor.rb`（`<figure>` 要素の生成）, `contents/21-markdown-tutorial.md`・`contents/22-extentions.md`（`:::{.figure}` の使用）

## 1. 要約

- `.figure` という名前が、**2 つの異なる用途**で使われている：
  - **(A) 既存＝図版（画像）**：`stylesheets/chapter-common.css` に歴史的に存在する図版用スタイル。
  - **(B) 新設＝図・アスキーアートの枠**：2026-07-17 に追加した `:::{.figure}`（`.output` のエイリアス・行番号なしの囲み枠）。
- CSS のセレクタが `:is(.figure, figure)` と書かれているため、(B) の `div.figure` に (A) の図版スタイルが**意図せず適用**される。
- ただし調査の結果、**(A) の「`.figure` クラス」を実際に生成・使用している箇所は無い**（画像図版は `<figure>` 要素として生成され、クラス `.figure` は付かない）。つまり `.figure` クラスは (B) が新設するまで実質「空き地」だった。
- 現状の使い方（枠の中身が罫線図＝`<pre>` のみ）では**目立った表示破綻は起きていない**が、枠内に箇条書きや画像を入れると (A) のスタイルで崩れる**潜在バグ**がある。

## 2. 発端

`:::{.figure}` を「罫線図・アスキーアートを行番号なしで囲む枠」として新設した際、`.figure` を `.output` のエイリアスとして定義した。その後、`stylesheets/chapter-common.css` に**既存の `.figure`（図版）スタイル**があることに気づいた（`:is(.figure, figure) { … }`、コメントに「旧来の .figure と素の figure をまとめて扱う」とある）。

## 3. 既存 `.figure` / `<figure>` の実態

### 3.1 CSS 定義（本報告書作成時点・`stylesheets/chapter-common.css`）

「図版」セクション（297〜397 行付近）に、`:is(.figure, figure)` を主語とする一連のスタイルがある。主なもの：

| 行 | セレクタ | 内容 |
|---|---|---|
| 298 | `:is(.figure, figure)` | `display: block; position: relative; margin-block: 4mm` |
| 305 | `:is(.figure, figure):not(.align-center):not(.align-right)` | 左寄せ（`margin-inline-end: auto`） |
| 311 / 316 | `…​.align-center` / `.align-right` | 図版自体の中央／右寄せ配置 |
| 336 | `:is(.figure, figure)[style*="width"] > img` | 幅指定時に内側 img を 100% に |
| 353 | `:is(.figure, figure) :is(img, svg)` | 内側の画像に**枠線**を付ける |
| 357 | `:is(.figure, figure) p` | `text-indent: 0` |
| 376 | `.figure.right` | `float: inline-end`（回り込み） |
| 382 | `:is(.figure, figure) ul` | **`position: absolute`**（図中の注釈リストを絶対配置） |
| 392 | `:is(.figure, figure) li` | 赤枠・地色（図中注釈の見た目） |

このうち `figure.vs-showcase`（365 行）は図解注釈（showcase）専用で、`<figure>` 要素側のみに効くため本件とは無関係。

### 3.2 `<figure>` 要素の生成元

画像にキャプション（図番号）を付けると、`cross_reference_processor.rb`（510 行付近）が **`<figure>` 要素**を生成する：

```ruby
parts = ["<figure#{id_attr(label)}#{align_class(img[:align])}#{style_attr(img[:width])}>"]
```

- `id_attr` → `id="..."`
- `align_class` → `class="align-center"` 等（**`align-*` のみ**）
- `style_attr` → `style="width: .."`

つまり生成されるのは **`<figure class="align-center">`** のような**要素**であり、`class="figure"` は付かない。

### 3.3 `.figure` クラスの実使用状況

- `lib/` 全体で `class="figure"` を直接付与する箇所は**無い**（grep で 0 件）。
- 原稿で `:::{.figure}`（＝ `div.figure`）を使うのは、**2026-07-17 に新設した 3 箇所のみ**：
  - `contents/21-markdown-tutorial.md:70`（Markdown フレーバーの系統図）
  - `contents/22-extentions.md:194, 203`（`.figure` リファレンス節の作例）

➡ **結論**：CSS の `:is(.figure, figure)` のうち、実際に機能しているのは `figure`（要素）セレクタ側だけで、`.figure`（クラス）セレクタ側は新設まで誰も使っていなかった。`.figure` クラスは事実上の空き地だった。

## 4. 新設 `:::{.figure}`（図・アスキーアート枠）の実態

- 記法 `:::{.figure}` → 既存の汎用コンテナ機構が `<div class="figure">` へ変換（Ruby 追加なし）。
- CSS（`chapter-common.css` 536 行付近）：`.output` と同じ細い囲み枠のエイリアス。中の `<pre>` は枠・地色を落とし、`white-space: pre-wrap` で桁揃えを保つ。`body.vs-kindle .figure` で Kindle 用の具体色枠。
- 行番号免除（`prism_lines.rb`）：`.output` / `.terminal` / `.figure` 配下の `<pre>` には Prism 行番号を付けない。
- 用途：罫線ツリー・構成図・アスキーアートなど、桁揃えの要るテキストを行番号なしで囲む。

## 5. 衝突の詳細

新設の `div.figure`（アスキーアート枠）に、既存の図版スタイル `:is(.figure, figure)` が**クラス側でマッチ**して適用される。具体的な影響：

| 既存ルール | 新 `.figure` 枠への影響 | 実害 |
|---|---|---|
| `margin-block: 4mm`（298） | 新枠の `margin-block: 3mm` と二重指定になり、カスケード順で片方が勝つ | 小（余白が想定とわずかに違う可能性） |
| `margin-inline-end: auto`（305） | 左寄せ化 | 小（block 全幅なら実質無影響） |
| `:is(.figure, figure) :is(img, svg) { border }`（353） | 枠内に画像を置くと枠線が付く | 中（アスキーアート枠に画像は通常入れないが、入れると想定外） |
| `:is(.figure, figure) p { text-indent: 0 }`（357） | 段落字下げが消える | なし（むしろ好都合） |
| **`:is(.figure, figure) ul { position: absolute }`（382）** | **枠内に箇条書きを入れると絶対配置で吹き飛ぶ** | **大（レイアウト崩壊）** |
| **`:is(.figure, figure) li { 赤枠・地色 }`（392）** | **枠内の li に図中注釈の見た目が付く** | **大（意図しない装飾）** |
| `.figure.right { float }`（376） | `:::{.figure .right}` で回り込みになる | 小〜中（意図と一致する場合もある） |

### 現状で破綻が見えていない理由

新設の使い方では枠の中身が **`<pre>`（罫線図）のみ**で、`ul` / `li` / `img` を含まないため、危険な (382)(392)(353) が発火していない。ビルドした PDF でも枠・桁揃えは正常に見えた。**ただし枠内に箇条書きや画像を書いた瞬間に崩れる**。

## 6. 影響評価

- **顕在的な実害**：現状は小（罫線図＝`<pre>` のみの用途に限れば見た目は正常）。
- **潜在リスク**：大。`.figure` 枠に `ul`/`li`/`img` を入れると図版スタイルで崩壊する。著者は「囲み枠だから何でも入る」と考えるのが自然なので、踏みやすい罠。
- **意味の混乱**：同じ `.figure` が「図版（画像）」と「アスキーアート枠」の 2 義になり、コード・原稿の可読性を損なう。

## 7. 対応の選択肢

### 案 A：新設の枠を改名する（`.figure` → 別名）

新設した「アスキーアート枠」のクラス名を、`.figure` 以外へ変える。既存の図版スタイルはそのまま。

- 改名候補：`.diagram`（図・ダイアグラム）／`.textart`・`.art`（アスキーアート）／`.listing`
- **変更範囲**：`chapter-common.css`（新設の `.figure` / `.figure p` / `.figure pre` / `body.vs-kindle .figure`）、`prism_lines.rb`（免除リスト）、`contents/21`・`contents/22` の `:::{.figure}` 3 箇所、`CHANGELOG` の該当記述。**いずれも未コミットまたは容易に追える範囲**。
- メリット：既存図版スタイルに一切触れず、回帰リスクが最小。実装コストも小（新設分は原稿 3 箇所のみ）。
- デメリット：`.figure` という直感的な名前を「枠」が使えない。ただし「図版」と紛れないので、むしろ明確とも言える。

### 案 B：既存の `.figure` クラスセレクタを廃止し、`.figure` を新設の枠へ明け渡す

`:is(.figure, figure)` を **`figure`（要素セレクタ）のみ**へ書き換え、`.figure` クラスを図版用途から解放。空いた `.figure` を新設の枠が使う。

- 根拠：3.3 のとおり `.figure` クラスは現状どこからも生成されておらず、廃止しても実害が無い。
- **変更範囲**：`chapter-common.css` の図版セクション（297〜397 の `:is(.figure, figure)` を全て `figure` に）＋ `.figure.right`（376）の扱い。**CSS の広範な書き換え**を伴う。
- メリット：`.figure` という自然な名前を「枠」が持てる。歴史的な死んだクラスの掃除にもなる。
- デメリット：図版 CSS の広範な書き換えで回帰リスクがある（実ビルドでの図版レイアウト確認が必須）。将来「図版に `.figure` クラスを付ける」余地を捨てる。

### 案 C：図版と枠を統合する（1 つの `.figure` に意味を集約）

- 「図版（画像配置）」と「アスキーアート枠（リテラル囲み）」は用途が根本的に異なる（前者は画像の寄せ・幅、後者は等幅テキストの囲み）。1 クラスに両方の意味を持たせるのは不自然で、条件分岐の多い CSS になる。
- **非推奨**（整理にならず、複雑さが増す）。

## 8. 参考：推奨と留意

- 最小リスクは **案 A（新設の枠を改名）**。新設分は未コミットで原稿 3 箇所のみのため、改名コストが低く、既存図版に一切触れないため回帰も無い。
- 「`.figure` という名前を枠に使いたい」を重視するなら **案 B**。ただし図版 CSS の書き換えと実ビルド検証が必要。
- いずれにせよ、新設の枠には **`ul`/`li`/`img` を入れたときの挙動**を仕様として明記しておくとよい（枠は「等幅テキストを囲むもの」で、リッチな要素は対象外、等）。

## 9. 関連ファイル・行（本報告書作成時点）

- `stylesheets/chapter-common.css`
  - 既存図版：297〜397（`:is(.figure, figure)` 一連・`.figure.right`）
  - 新設枠：536〜（`.output, .figure` / `.figure p` / `.figure pre`）、645〜（`body.vs-kindle .figure`）
- `lib/vivlio_starter/cli/prism_lines.rb`：`LINE_NUMBER_EXEMPT_ANCESTORS = '.output, .terminal, .figure'` と `line_number_exempt?`
- `lib/vivlio_starter/cli/pre_process/cross_reference_processor.rb`：510 付近（`<figure>` 要素の生成・`align_class` は `align-*` のみ付与）
- 原稿での `:::{.figure}` 使用：`contents/21-markdown-tutorial.md:70`、`contents/22-extentions.md:194, 203`
