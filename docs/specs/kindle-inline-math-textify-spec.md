# Kindle インライン数式のテキスト化仕様書

> 作成日: 2026-07-12
> ステータス: **実装待ち**
> 対象: KNOWN_ISSUES の 2 件——「Kindle の表内インライン数式のサイズが不安定」「Kindle のインライン数式のサイズが不安定」——の根治。Kindle フレーバ限定で、単純なインライン数式（SVG `<img>`）を本文テキスト（HTML）へ劣化変換し、フォントサイズ変更へ完全追従させる
> 決定事項（2026-07-12 調査に基づく）:
> - **方式はテキスト化**（LaTeX 単純サブセット → `<sup>`/`<sub>`＋Unicode 記号の HTML）。**Kindle フレーバのみ**。PDF・クリーン EPUB は現行の SVG のまま一切触らない
> - **MathML は不採用**（KDP 公式は Enhanced Typesetting での対応を謳うが、実機はデバイス間で表示が非一貫との報告あり。「Kindle で確実に表示」優先の本プロジェクト方針に反する。§8）
> - テキスト化できない複雑な式は現行の px 固定フォールバックを維持（既知の制限として存続・ただし対象は大幅に縮小）
> 関連: `lib/vivlio_starter/cli/build/epub_builder.rb`（`convert_math_units_for_epub!`・Kindle 限定フェーズ）, `lib/vivlio_starter/cli/pre_process/math_transformer.rb`（SVG 化・`alt` に元 LaTeX 保存）, `docs/archives/epub-kindle-target-split-spec.md` §3（px 固定の経緯）, `docs/specs/kindle-css-compatibility-notes.md`, `docs/specs/KNOWN_ISSUES.md`

## 0. 背景・問題

インライン数式は前処理で LaTeX→SVG 化され `<img class="vs-math vs-math-inline">` として埋め込まれる（PDF・EPUB 共通・Kindle でも表示自体は確実）。しかし Kindle(KFX) では画像サイズを本文フォント相対で指定する手段がない:

- `ex`/`em` の inline style → KFX が解さず無視 → SVG に固有寸法が無いため既定 300px で**極大表示**
- `width`/`height` px 属性（現行対策）→ 表示は安定するが、読者がフォントサイズを変更すると**本文だけ拡大され数式が相対的に極小/極大**になる（非追従）

これは「リフロー環境で画像をフォント相対サイズにできない」という KFX の本質的制約であり、**画像のままでは解決不能**。よって「数式を画像でなくす」＝本文テキスト化が根治策となる。テキストは定義上フォントサイズに 100% 追従する。

## 1. 調査結果（2026-07-12）

1. **現行実装**: `convert_math_units_for_epub!`（`epub_builder.rb:1438`）が **Kindle 限定フェーズ**（`epub_builder.rb:265`）で ex→em 変換（×0.5）＋ px 属性付与（em×16）を行う。クリーン EPUB は ex の style のまま（Kobo/Apple は ex を解する）。表セル内は `MIN_TABLE_MATH_EM`（1.0em）まで等比拡大する救済つき。
2. **原稿の実態**: `contents/*.md` のインライン数式は 32 件（コードスパン内の `$HOME` 等の疑似ヒットを除く）。**全件が単純な式**——単一変数（`$t$` `$\gamma$`）、上付き（`$E=mc^2$` `$10^{-34}$`）、分数（`$\frac{1}{299{,}792{,}458}$`）、記号（`\times` `\approx` `\langle\rangle` `\pm`）、単位（`\text{J}\cdot\text{s}`）——であり、§3 のサブセットで 100% テキスト化可能。
3. **MathML の実情**（Web 調査）: KDP 公式ドキュメントは Enhanced Typesetting の MathML 対応を明記する一方、KDP コミュニティには「Kindle Previewer 3 とスマホアプリでは表示されるが他では表示されない」「単純な分数が Kindle Desktop で描画されない」という報告があり、Amazon が内部で数式を画像化するという記述もある。**デバイス間の非一貫性はビルド時に検証不能**なため不採用（§8）。
4. **旧根治案「インライン SVG ＋ height:1em」**（アーカイブ spec §3 の別タスクメモ）: KFX のインライン SVG 対応自体が不確実（過去に「SVG 内 base64 画像非対応」で出版ブロックの実績あり）で、`em` の height を解さない可能性が高い（§0 と同根）。不採用。

## 2. 方式概要

Kindle フレーバの EPUB 後処理で、`img.vs-math-inline` の `alt`（`MathTransformer.build_img` が保存した**元 LaTeX**）を読み、単純サブセット（§3）に収まる式を HTML テキストへ変換して `<img>` を置換する:

```html
<!-- 変換前（現行の Kindle 出力） -->
<img class="vs-math vs-math-inline" src="images/math/94-sample/ab12….svg"
     alt="$E=mc^2$" style="…em…" width="52" height="17">

<!-- 変換後 -->
<span class="vs-math vs-math-text"><i>E</i>=<i>mc</i><sup>2</sup></span>
```

- サブセット外の式（`\sqrt` `\sum` `\int` 等）は**無変換**＝現行の px 固定のまま（既知の制限として存続）。
- ディスプレイ数式（`figure.vs-math-display`）は**対象外**（KNOWN_ISSUES にも「`$$` は正常」と記録済み。行全体を占めるため px 固定でも破綻しない）。
- 表セル内のインライン数式も同じ変換が適用され、テキスト化できれば**表内数式問題も同時に解決**する。

## 3. LaTeX → HTML テキスト変換サブセット

### 3.1 変換規則

| LaTeX 構文 | 出力 | 備考 |
|---|---|---|
| 数字・空白 | そのまま | 空白は LaTeX 流に無視（明示スペースは `\,` 等のみ） |
| ラテン文字 | `<i>x</i>` | 数学変数はイタリック（MathJax の見た目に揃える）。連続文字は 1 つの `<i>` にまとめてよい |
| `\text{…}` / `\mathrm{…}` | 中身を**立体**（イタリックなし）で | 単位・語 |
| `x^{…}` / `x^2` | `<sup>…</sup>` | 中身もサブセット再帰（1 段のみ。sup/sub の入れ子は拒否） |
| `x_{…}` / `x_0` | `<sub>…</sub>` | 同上 |
| `\frac{A}{B}` | `A/B` | A・B とも単純ラン（frac の入れ子は拒否）。括弧は付けない（`1/299,792,458` の見た目を優先） |
| `{…}`（グルーピング） | 透過 | `299{,}792` → `299,792`、`10^{-34}` |
| 演算子 `+ - = / < > ( ) [ ] | , . : ; !` | そのまま | `-` は U+2212（−）へ置換してよい（実装時に PDF の見た目と比較して判断） |
| `\times` `\cdot` `\pm` `\mp` `\approx` `\neq` `\leq` `\geq` `\sim` `\propto` `\infty` `\ll` `\gg` | `× ⋅ ± ∓ ≈ ≠ ≤ ≥ ∼ ∝ ∞ ≪ ≫` | Unicode 直書き |
| `\langle` `\rangle` | `⟨` `⟩`（U+27E8/27E9） | |
| ギリシャ文字 `\alpha`〜`\Omega` | `α`〜`Ω` | 小文字・大文字とも全対応表を実装（イタリックにしない） |
| `\,` `\;` `\:` `\quad` `\qquad` | 空白（`\,` は U+2009 thin space、他は通常スペースで可） | |
| `\%` `\&` `\#` `\_` `\{` `\}` `\$` | `% & # _ { } $` | エスケープ解除 |
| `\ldots` `\cdots` `\dots` | `…` | |

### 3.2 拒否規則（＝無変換で SVG 維持）

- 上記以外の `\コマンド`（`\sqrt` `\sum` `\int` `\lim` `\vec` `\hat` `\begin` …）
- `\\`（改行）・`&`（アライメント）
- sup/sub の 2 段以上の入れ子、`\frac` の入れ子
- 変換器はホワイトリスト方式で実装する: **1 トークンでも解釈できなければ全体を拒否**（部分変換は絶対にしない）。拒否は正常系（`log_debug` 程度）であってエラーではない。

## 4. 実装設計

### 4.1 変換器 `MathTextRenderer`（新規・純粋関数）

`lib/vivlio_starter/cli/build/math_text_renderer.rb`。公開 API は 1 つ:

```ruby
# @param latex [String] $…$ / \(…\) を剥いだ LaTeX 本文
# @return [String, nil] HTML 文字列（変換可能時）/ nil（サブセット外）
MathTextRenderer.render(latex)
```

- 実装は小さな再帰下降トークナイザ（正規表現の逐次消費で可）。§3.1 のホワイトリストを 1 トークンずつ消費し、未知トークンで即 `nil` を返す。
- 出力の HTML 予約文字（`< > &`）はエスケープする（`<i>`/`<sup>`/`<sub>` は変換器自身が生成するもののみ）。
- Nokogiri 非依存・CONFIG 非依存の純粋モジュールにする（単体テスト容易性・`module_function`）。

### 4.2 EpubBuilder への組み込み

`textify_simple_math_for_kindle!(html_files)` を新設し、Kindle 限定フェーズの **`convert_math_units_for_epub!` の直前**（`epub_builder.rb:265` 付近）に置く（テキスト化されなかった残存 `<img>` に px フォールバックが従来どおり効く順序）:

1. `doc.css('img.vs-math-inline')` を走査。
2. `alt` から元 LaTeX を復元: デリミタ `$…$` / `\(…\)` を剥ぐ（`MathTransformer` の `escape` は空白圧縮のみで LaTeX 構文は保存されるため、Nokogiri の属性読み出しでそのまま使える）。
3. `MathTextRenderer.render` が HTML を返したら、`<span class="vs-math vs-math-text">…</span>` ノードで `<img>` を置換。`nil` なら何もしない。
4. 変換件数・残存（SVG 維持）件数を `log_info` で報告する。残存があっても警告にはしない（既知の制限）。
5. 冪等: 置換後は `img.vs-math-inline` が消えるため再実行しても安全。

### 4.3 CSS

追加不要（span は本文のフォント・サイズをそのまま継承するのが正しい動作）。見た目の調整が必要になった場合のみ `body.vs-kindle .vs-math-text { … }` を `chapter-common.css` へ追記する（`:is()`/`var()` 禁止・root 編集→ `copy_to_scaffold.rb` 同期）。

### 4.4 触らないもの

- `MathTransformer`（前処理）: 変更なし。PDF・クリーン EPUB・Kindle の初期状態は今までどおり SVG。
- `convert_math_units_for_epub!` / `apply_math_px_fallback!` / `MIN_TABLE_MATH_EM`: 変更なし（サブセット外の式のフォールバックとして存続）。
- ディスプレイ数式・クリーン EPUB・PDF の経路: 変更なし。

## 5. テスト計画

Minitest。実装時は ruby-coding-rules skill を適用。

1. **`test/vivlio_starter/cli/build/math_text_renderer_test.rb`（新規）**:
   - 原稿実在の式を必ず含める: `E=mc^2` / `\frac{1}{299{,}792{,}458}` / `h = 6.626 \times 10^{-34}\,\text{J}\cdot\text{s}` / `\gamma \approx 2.29` / `\langle x^2 \rangle` / `e^{i\pi} + 1 = 0` / `\nu_0` / 単独ギリシャ `\phi`
   - イタリック規則（ラテン文字 `<i>`・`\text{}` 内は立体・ギリシャは立体）
   - 拒否系: `\sqrt{2}` / `\sum_{i=1}^n` / `x^{y^z}`（入れ子 sup）/ `\frac{\frac{1}{2}}{3}` / 未知コマンド → すべて `nil`
   - HTML エスケープ（`a < b` を含む式）
2. **`test/vivlio_starter/cli/epub_builder_test.rb`（追記）**: `textify_simple_math_for_kindle!` のユニット——単純式 img が span 化・複雑式 img が無傷で px 属性を保持・alt デリミタ 2 形式（`$…$` / `\(…\)`）の剥がし。
3. **`test/vivlio_starter/cli/build/epub_kindle_layout_test.rb`（追記）**: Kindle フレーバ生成 HTML に `span.vs-math-text` が存在し `img.vs-math-inline`（単純式分）が消えていること。クリーン EPUB では span が**存在しない**こと。
4. `rake test` / `bundle exec rubocop`。

## 6. 検証（実装後）

1. `vs build --target=kindle` → Kindle Previewer 3 で 94-sample 章を開き、**フォントサイズを最小⇔最大に振って**数式が本文に追従することを確認（本仕様の受け入れ条件そのもの）。
2. 表内数式（94-sample の SI 単位表等）が崩れないこと。
3. クリーン EPUB（epubcheck ＋ Apple Books/Kobo いずれか）が無変化であること。
4. KPF 変換ログにエラー増が無いこと（`summarize_kpf_logs`）。

## 7. 完了時の後片付け

- `KNOWN_ISSUES.md` の 2 件を更新: 「インライン数式が不安定」→ 解消（テキスト化）。「表内インライン数式」→ 対象を「テキスト化サブセット外の複雑な式のみ」に縮小して存続（運用回避の推奨も「複雑な式を表内に置かない」へ緩和）。
- `kindle-css-compatibility-notes.md` §4 の数式行に本方式を追記（同メモは恒久参照のため）。
- `contents/`（94-sample または Kindle 解説章）に「Kindle では単純なインライン数式はテキスト表示になる」旨を一言（著者向け）。

## 8. 考慮した代替案（不採用）

| 案 | 不採用理由 |
|---|---|
| MathML（Kindle ネイティブ描画） | KDP 公式は ET 対応を謳うが、実機報告はデバイス間で非一貫（Previewer/スマホ○・Desktop ×等）。内部で画像化されるという情報もあり、追従性の保証がない。ビルド時に全デバイスを検証できず「確実に表示」方針に反する。**将来 KFX の対応が安定したら再評価する価値はある** |
| インライン SVG ＋ `height:1em`（旧・別タスク案） | KFX のインライン SVG・font 相対単位の対応が不確実（`em`/`ex` 無視は §0 で実証済み）。SVG 関連は過去に出版ブロックの実績もありリスク高 |
| px 属性の複数解像度出し分け・メディアクエリ | KFX はフォントサイズをメディアクエリに露出しない。原理的に不可能 |
| 全数式テキスト化（ディスプレイ含む） | ディスプレイ数式は現状正常（行占有で px でも破綻しない）。`\sqrt`・積分等はテキストで表現不能。壊れていないものは触らない |
| 原稿側運用（表・本文に数式を書かない） | 現行 KNOWN_ISSUES の回避策そのもの。著者体験が悪く、94-sample のような科学系原稿で非現実的 |
