# テーブルの横結合（colspan）と複数行ヘッダー（PHP Markdown Extra / Backlog 風）に関する仕様書

## 目的
**テーブルの横結合（colspan）と複数行ヘッダー（PHP Markdown Extra / Backlog 風）**
`table.png` のように、横方向のセル結合と複数行ヘッダーを持つ表に対応する。需要は不透明だが、既存の `.long-table` / `.table-rotate` が `MarkdownUtils.pipe_table_to_html` で独自のパイプテーブル変換を持つため、その拡張で実現可能。

## 記法
記法は空セル `||`（直前セルへマージ）＝ colspan、区切り行（`---`）より上の複数行＝ `thead` の複数 `<tr>`。
  ```markdown
  |          |       結合       ||
  | ヘッダー1 | ヘッダー2 | ヘッダー3 |
  | :------- | :------: | -------: |
  | セル1     |      長いセル      ||
  | セル2     |  中央寄せ  |   右寄せ  |
  | セル3     | **太字**  |  *斜体*  |
  | セル4     |      さらに       ||
  ```
  - **パーサ拡張**: (1) 空セル（`||`）を直前セルの `colspan` として畳む、(2) 区切り行の位置を探して上を `thead`（複数 `<tr>`）に一般化、(3) 列整列（`:---`/`:---:`/`---:`）の付与、(4) セル内インライン装飾（太字・斜体・コード）のレンダリング。
  - **適用範囲の設計判断（最重要）**: 素のテーブルは VFM が処理するため、横結合・複数行ヘッダーを含む表は VFM では正しく組めない。(A) `:::{.long-table}` 等**コンテナ内に限定**して既存変換を拡張（検出不要・安全）するか、(B) 「`||` を含む／区切り行が 2 行目にない」表だけを**前処理で横取り**して変換（素のテーブルでも書けるが誤検出回避の設計が要る）かを決める。
  - 
  まずは (A) から入るのが堅実であるが、著者には `:::{.colspan-table}` などの記法を強いることとなる。
  (B) は実装がいささか大変ではあるが、特に新しい記法を学習する必要もなく、拡張テーブル記法としてそのまま著者は執筆することが出来る優位性が有る。
  (C) 将来的には、`:::{.long-table}`, `:::{.rotate-table}` などの記法を廃止して、テーブル構造に因る自動解析を目指す。

  ## マルチターゲット
  - `<table>` の `colspan` と複数 `<tr>` の `thead` は PDF/EPUB/Kindle すべてで有効なので、出力面の劣化対応は不要。結合セルの罫線 CSS は要追加。
  - 参照: `docs/specs/table.png`。

---

# 実装仕様（確定版）— 統合テーブル変換

以降は実装調査（2026-07-08）とレビュー合意に基づく確定仕様。上の構想メモ（A/B/C 案）に対する決定と、実装者（AI）が追加調査なしで着手できるレベルの詳細を記す。後方互換性は考慮しない（プロジェクト方針）。

## 0. 決定事項

1. **方針 (B) を採用**する。素のパイプテーブルに拡張記法（ゼロ幅セル `||`・複数行ヘッダー）が含まれる場合のみ、pre_process が VFM より先に横取りして HTML 化する。**`:::{.colspan-table}` コンテナは導入しない**（著者はフェンス記法なしで拡張テーブルを書ける）。
2. **`table-rotate` を `rotate-table` へ改名**する（`long-table` との語順統一）。CSS セレクタ・CSS カスタムプロパティ（`--table-rotate-*` → `--rotate-table-*`）・コード・マニュアル・scaffold・テストすべてを一括改名し、**旧名のエイリアスは残さない**（→ §2）。
3. 拡張記法は**素テーブルとコンテナ（`long-table` / `rotate-table`）内テーブルの両方で有効**。パーサは新モジュール `TableConverter` に一元化する（これが「統合テーブル変換」の意味）。
4. **コンテナ内のパイプテーブルは常に自前パーサで変換**する。現行の「Kramdown 優先・`<table>` が出なかった場合のみ `pipe_table_to_html` フォールバック」というルーティングは**廃止**する。
   - 廃止理由: Kramdown は `||` を「空セル」として解釈して `<table>` を生成してしまうため、フォールバックが永久に発火せず colspan と両立しない。
5. **`rotate-table` の `scale` / `shift-y` は自動算出を既定**とする。版面（ページサイズ・余白・文字サイズ）とテーブル内容から寸法を推定して自動フィットさせ、著者指定はそれを上書きする（→ §6）。あわせて CSS の配置基準を「完全センタリング」へ再設計し、`shift-y` の既定 `+25%` という補正ハックを撤去する。
6. `MarkdownUtils.pipe_table_to_html` は**撤去**し `TableConverter` へ移管する（中継メソッドは残さない）。
7. (C) 自動解析（long/rotate の自動判定によるコンテナ記法の廃止）と rowspan は**本実装のスコープ外**（→ §11）。

## 1. 現状調査サマリ（実装の前提知識）

実装に影響する現行コードの事実関係。

| 項目 | 現状 | 本実装での扱い |
|---|---|---|
| パイプライン順序 | `MarkdownPreprocessor#run`（L70-93）: `transform_math!` → … → `transform_book_cards!` → `transform_table_rotations!` → `transform_table_containers!` → … | rotate/containers の 2 ステップを `transform_tables!` 1 本に統合し、素テーブル横取りもここに含める |
| コンテナ→div 変換 | `MarkdownTransformer.convert_container_blocks(content, class_name:)` が `::: {.class params}` を `<div class="..." style="...">` へ変換。`scale=` / `shift-y=` は `--table-rotate-scale` 等をハードコードで出力 | 変数名を `--rotate-table-*` へ改名（それ以外は流用） |
| div 内テーブル変換 | `MarkdownTransformer.convert_table_container_inner_markdown(content, class_name)`: Kramdown で全体レンダリング → `<table` が無ければ `MarkdownUtils.pipe_table_to_html` | ルーティングを反転（§7.2）し `TableConverter` へ移管 |
| 既存パーサ | `MarkdownUtils.pipe_table_to_html`（markdown_utils.rb L144-187）: 1 行目=ヘッダー・2 行目=区切り固定。整列無視・colspan なし・複数行ヘッダーなし | `TableConverter` に置き換え |
| 既知バグ | `esc_code` が `<code>` 挿入**後**に HTML エスケープするため `&lt;code&gt;` になる（`markdown_transformer_test.rb` の `test_pipe_table_to_html_with_code` が「既存動作」として容認） | 新パーサで解消。テスト期待値を `<code>foo</code>` へ修正 |
| セル内の生 HTML | `transform_math!` がテーブル変換より**先**に走るため、セルに `<img>`（数式 SVG）等の生 HTML が入りうる（実例: `contents/94-sample.md` の SI 単位表 `$\text{s}$`） | セル描画は**生 HTML を保持必須**（§3.6）。現行パーサ式の `<`/`>` 全エスケープは不可 |
| 整列 | Kramdown が `:---` 等を `style="text-align: left"` 等のインラインスタイルで出力しており、著者は既に依存（`contents/22-extentions.md` の long-table 例は `:---:` を使用） | 新パーサも同形式で出力（**回帰防止のため整列対応は必須**） |
| コード退避 | `Masking.protect_code` / `restore_code`（`lib/vivlio_starter/cli/masking.rb`）が可変長フェンス・入れ子・`~~~`・```` ```include: ```` 除外に対応した状態機械として存在 | 素テーブル横取り（§4）の誤検出回避に流用 |
| 版面情報 | `Common.resolve_page_size(pcfg)`（`common.rb` L636）が幅/高さを mm 文字列で返す。page presets（`config/page_presets.yml`）に `margin_top/bottom/inner/outer`。`Common.normalize_page_units` 通過後は `base_font_size`（pt）・`base_line_height`（絶対 pt）。単位変換は `Units` モジュール | 自動フィット（§6）の入力として利用 |
| CSS | `stylesheets/table.css`: `border-collapse: collapse` ＋セル毎 border のため colspan の罫線は追加なしで成立。`tr:nth-child(even)` の縞は thead/tbody 各親内でカウントされ複数行ヘッダーでも破綻しない | 結合セルの中央寄せ追加＋rotate-table 再設計（§8） |
| VFM との関係 | pre_process が出力した生 HTML ブロックは VFM が素通しする（既存機構） | 横取りの出力は空行で挟んだ生 `<table>` HTML |

## 2. リネーム: `table-rotate` → `rotate-table`

互換エイリアスなしの一括改名。対象:

| 対象 | 変更 |
|---|---|
| コンテナクラス名 | `:::{.table-rotate}` → `:::{.rotate-table}`（旧記法は今後変換されない） |
| CSS セレクタ | `.table-rotate` / `.table-rotate > table` → `.rotate-table` / `.rotate-table > table`（`stylesheets/table.css` ＋ scaffold） |
| CSS カスタムプロパティ | `--table-rotate-scale` / `--table-rotate-shift-y` → `--rotate-table-scale` / `--rotate-table-shift-y`（`convert_container_blocks` のハードコード出力も同時改名） |
| コード | `markdown_preprocessor.rb`（メソッド名・ログ文言）・`markdown_transformer.rb`・`pre_process.rb` 委譲 |
| マニュアル | `contents/22-extentions.md`「`.table-rotate` — 表を90度回転」節・`contents/61-developer.md` 手順 9 |
| spellcheck 辞書 | `config/spellcheck_dictionaries/vivlio-starter-terms.txt` の `table-rotate` 行を `rotate-table` へ |
| scaffold | `lib/project_scaffold/` 配下の同名ファイル（`ruby copy_to_scaffold.rb` で同期） |
| テスト | `markdown_transformer_test.rb` の `table-rotate` 参照（`test_convert_container_blocks_*` 4 件） |

CHANGELOG に **Breaking** として明記する（旧 `:::{.table-rotate}` は変換されず素通しになる）。

## 3. 拡張パイプテーブル文法（正規仕様）

素テーブル・コンテナ内テーブル共通。

### 3.1 テーブルブロックの認識

- **行頭空白 3 文字以内で `|` から始まる連続行のかたまり**を 1 つのテーブルブロックとする（4 文字以上のインデントは Markdown のインデントコードブロックのため対象外）。
- コンテナ内では、テーブルブロック以外の行（キャプション段落など）は Kramdown でレンダリングし、出現順を保って結合する（§7.2）。

### 3.2 行のセル分割

1. セル内エスケープ `\|` を一時プレースホルダへ退避してから `split('|', -1)` する（`-1` 指定で末尾の空文字列を保持）。変換後に `|` として復元する。
2. 先頭要素が空文字列なら**行頭のパイプ**として 1 つだけ除去する。
3. 末尾要素が空文字列なら**行末のパイプ**として 1 つだけ除去する（`||` 終端の場合、残るもう 1 つの空文字列がマージマーカーになる）。

### 3.3 colspan（`||`）

- 分割結果の**ゼロ幅セル（空文字列。空白すら含まない）**は「直前セルへのマージマーカー」。直前セルの colspan を +1 して自身は消える。連続すれば +2, +3…。
- **空白のみのセル（`|   |`）は本物の空セル**として `<td></td>` / `<th></th>` を出力する（マージしない）。冒頭の記法サンプル 1 行目の先頭セルがこのケース。
- 行頭のゼロ幅セル（`|| x |` の先頭）はマージ先が無いため**空セルとして扱う**。

### 3.4 複数行ヘッダー

- **最初に出現した区切り行**（`/^\s*\|?[\s:\-|]+\|?\s*$/` にマッチし、かつ `-` を 1 つ以上含む行）を境界とする。
- 区切り行より**上のすべての行** → `<thead>` 内の複数 `<tr>`（セルは全て `<th>`）。
- 区切り行より**下のすべての行** → `<tbody>` の `<tr>`（セルは `<td>`）。
- 区切り行が行インデックス 0（ヘッダー行なし）の場合、または区切り行が存在しない場合は**テーブルとして不成立**（`nil` を返す。コンテナ内なら Kramdown フォールバック、素テーブルなら横取り対象外）。
- ヘッダー行内でも `||` による colspan は同一規則で有効。

### 3.5 列整列

- 区切り行のセルから列ごとの整列を決定する: `:---` = left / `:---:` = center / `---:` = right / `---` = 指定なし。
- **colspan が 1 のセル**: 整列指定のある列なら `style="text-align: left|center|right"` をインライン付与（Kramdown の出力形式と同一。既存 CSS `.long-table td { text-align: center }` とのカスケード関係も現行と同じになる）。
- **colspan が 2 以上のセル**: インラインスタイルを付与**しない**。中央寄せはグローバル CSS `th[colspan], td[colspan]`（§8）が担う（`table.png` の見た目に一致）。
- セルの列位置は「そのセルが開始する列インデックス」で数える（colspan ぶん列を消費して次セルへ進む）。区切り行の列数を超える分のセルは整列なしで出力する。

### 3.6 セル内インライン描画

- 各セルの文字列を `MarkdownUtils.render_markdown_to_html`（= Kramdown）でレンダリングし、結果が単一の `<p>…</p>` ならラッパを剥がして中身だけを採用する。
- これにより `**太字**` / `*斜体*` / `` `コード` `` / `<br>` / 数式 SVG の `<img>` 等の**生 HTML 保持**がすべて Kramdown の実績ある挙動に乗る（現行の `<code>` 二重エスケープバグも同時に解消）。
- 空セルは空文字列のまま出力する（Kramdown を通さない）。
- セル内に生の `|` を書きたい場合は `\|` でエスケープする（インラインコード内の `|` も同様）。この制約はマニュアルに明記する。

## 4. 素テーブルの横取り（(B) 方式）

### 4.1 トリガー条件

コンテナ外のテーブルブロック（§3.1）のうち、**次の両方**を満たすものだけを横取りする:

1. 区切り行（§3.4）が行インデックス 1 以上に存在する。
2. **いずれか**が成立: (a) ヘッダー行・データ行にゼロ幅セル（§3.3 のマージマーカー）が 1 つ以上ある、(b) 区切り行が行インデックス 2 以上にある（= 複数行ヘッダー）。

条件を満たさないテーブル（= 通常の GFM テーブル）は**一切触らず** VFM に委ねる。

- 安全性の根拠: (b) のケースは GFM 構文違反であり VFM でもテーブル化されず崩れるだけなので、横取りは純粋な改善。(a) は意味論の変更（§4.4）だが対象を `||` 使用時に限定できる。
- 判定は §3.2 の分割規則（`\|` 退避後）で行う。

### 4.2 実行位置とコード退避

- `transform_tables!`（§7.3）の**最終フェーズ**として実行する。この時点でコンテナ（`long-table` / `rotate-table`）内のテーブルは既に HTML 化済みのため、残っている Markdown パイプテーブル＝素テーブルである（`:::{.note}` 等の非テーブルコンテナ内はまだ Markdown だが、その中の拡張テーブルも横取り対象としてよい。出力される生 `<table>` はコンテナ変換後も生 HTML のまま保持される）。
- 走査前に `Masking.protect_code` でコードフェンス・インラインコードを退避し、走査後に `Masking.restore_code` で復元する（コードブロック内のパイプ表記を誤検出しない）。

### 4.3 出力

- ブロックを `TableConverter.pipe_table_to_html` の結果（生 `<table>` HTML）で置換し、**前後を空行で挟む**（VFM の生 HTML ブロック認識のため）。ラッパ div は付けない。
- 変換件数を `Common.log_success` で報告する（例: `拡張テーブル（colspan/複数行ヘッダー）を N 件変換しました`）。

### 4.4 意味論の変更（Breaking・要ドキュメント化）

GFM では `||` は「空セル」だが、本実装後は「直前セルへのマージ」になる。**空セルは `| |`（空白を挟む）と書く**。既存原稿で `||` を空セルとして使っている場合は表示が変わるため、CHANGELOG に Breaking として明記し、マニュアル（22 章）にも書き分けを記載する。

## 5. 生成 HTML（正規例）

冒頭「記法」節の入力例（素テーブルとして書かれた場合も、コンテナ内でも同一）に対する期待出力:

```html
<table>
  <thead>
    <tr><th style="text-align: left"></th><th colspan="2">結合</th></tr>
    <tr><th style="text-align: left">ヘッダー1</th><th style="text-align: center">ヘッダー2</th><th style="text-align: right">ヘッダー3</th></tr>
  </thead>
  <tbody>
    <tr><td style="text-align: left">セル1</td><td colspan="2">長いセル</td></tr>
    <tr><td style="text-align: left">セル2</td><td style="text-align: center">中央寄せ</td><td style="text-align: right">右寄せ</td></tr>
    <tr><td style="text-align: left">セル3</td><td style="text-align: center"><strong>太字</strong></td><td style="text-align: right"><em>斜体</em></td></tr>
    <tr><td style="text-align: left">セル4</td><td colspan="2">さらに</td></tr>
  </tbody>
</table>
```

インデント・改行の体裁は現行 `pipe_table_to_html` 実装を踏襲する。

## 6. rotate-table の自動フィット（scale / shift-y / 高さの自動算出）

### 6.1 幾何再設計（前提）

現行 CSS の既定 `shift-y: +25%` は「ラッパー高さが固定 clamp（320〜560px）でページより小さいため、回転後のテーブル中心がページ中心からずれる」ことへの補正ハックである（幾何解析済み: `translate(-50%, Y)` の Y% はテーブル自身の高さ基準・`rotate`/`scale` は transform-origin center のため中心を動かさない。**ラッパー高さ＝版面高さ・`translateY(-50%)` なら数学的に完全センタリング**になる）。

そこで次のように再設計する:

- **ラッパー高さは pre_process が版面高さ（mm）を `--rotate-table-height` として注入**する。CSS は `height: var(--rotate-table-height, clamp(320px, calc(500px * var(--paper-scale)), 560px))`（フォールバックは旧値。通常は常に注入される）。
- **transform の基準を完全センタリングへ**: `translate(-50%, calc(-50% + var(--rotate-table-shift-y, 0%)))`。
- **`shift-y` の意味を「センタリング位置からの追加オフセット」へ変更**する（既定 0%。正で下方向・テーブル高さ基準）。Breaking として CHANGELOG・マニュアルに明記。

### 6.2 自動算出アルゴリズム

`TableConverter.estimate_rotate_style(table_model, page_cfg)` を**純粋関数**として実装する（`Common::CONFIG` を直接参照しない。DI でテスト可能にする）。

**入力**（`page_cfg`: プリセット適用・単位正規化済みの page 設定 Hash。呼び出し境界で `MarkdownPreprocessor` が `Common::CONFIG.page.to_h` から解決して渡す）:

- ページ寸法: `Common.resolve_page_size(page_cfg)` → mm 値（`Units.length_to_mm` でパース）
- 余白: `margin_top` / `margin_bottom` / `margin_inner` / `margin_outer`（mm）
- 文字: `base_font_size`（pt → `Units` で mm 化）・`base_line_height`（正規化済み絶対 pt → mm 化）

**手順**:

```
content_w = page_w - margin_inner - margin_outer     # 版面幅 mm
content_h = page_h - margin_top  - margin_bottom     # 版面高さ mm

# --- テーブル寸法の推定 ---
# セル表示幅（em）: インライン記法・HTML タグを除去した素テキストで
#   ASCII 文字 = 0.5em / それ以外 = 1.0em を加算。<br> で分割し最長行を採用
col_w_em[c]  = 全行における列 c 開始セルの表示幅の最大値（colspan≥2 のセルは列幅決定から除外）
col_w_mm[c]  = col_w_em[c] * font_mm + 2 * CELL_PAD_MM
table_w      = Σ col_w_mm
row_h_mm     = line_height_mm * (セル内 <br> 行数の行内最大) + 2 * CELL_PAD_MM
table_h      = Σ row_h_mm（全行 = thead + tbody）

# --- 回転後のフィット（-90°回転で幅↔高さが入れ替わる） ---
scale = min(content_h / table_w, content_w / table_h, 1.0) * SAFETY
scale = clamp(scale, SCALE_MIN, 1.0) を 5% 刻みへ切り捨て
```

**定数**（`TableConverter` 内に凍結定数として定義。根拠コメント必須）:

| 定数 | 値 | 根拠 |
|---|---|---|
| `CELL_PAD_MM` | 1.2 | table.css の padding clamp（0.6〜1.4mm）＋罫線幅の中庸値 |
| `SAFETY` | 0.95 | 文字幅推定の誤差（プロポーショナル欧文等）の安全率 |
| `SCALE_MIN` | 0.30 | これ未満は可読性がないため下限で止める（著者へ縮小限界の判断を委ねる） |

**出力**: `{ 'rotate-table-height' => "#{content_h.round(1)}mm", 'rotate-table-scale' => "#{(scale * 100).round}%" }`

### 6.3 適用と著者上書き

- `TableConverter.convert_container_inner(content, 'rotate-table', page_cfg:)` が、div 内のテーブル HTML 化と同時に自動算出を実行し、div の `style` 属性へ CSS 変数をマージする。
- **著者がコンテナパラメータで指定した値が常に優先**: `convert_container_blocks` が先に出力した `--rotate-table-scale` / `--rotate-table-shift-y` が style 属性に既にあれば、自動値で上書きしない（`--rotate-table-height` は常に注入）。
- 精度の限界（セル内画像・長い欧文・折返し発生時は推定が甘くなる）はマニュアルに明記し、従来どおり `scale=` / `shift-y=` で微調整できることを案内する。

## 7. モジュール設計

### 7.1 `TableConverter`（新設）

```
lib/vivlio_starter/cli/pre_process/table_converter.rb
module VivlioStarter::CLI::PreProcessCommands::TableConverter
```

公開 API（`module_function`）:

- **`pipe_table_to_html(md_text)`** — 拡張パイプテーブル 1 個を HTML 化。不成立なら `nil`。
  - 内部フェーズ: 区切り行探索 → 行→セル分割（§3.2-3.3）→ thead/tbody 構築（§3.4-3.5）→ セル描画（§3.6）→ HTML 組み立て。
  - セルは `Data.define(:content, :colspan)` 程度の軽量な値オブジェクトで持つ（Struct 禁止）。過剰なクラス分割はしない（コール深度 3 段以内）。
- **`convert_container_inner(content, class_name, page_cfg: nil)`** — `<div class="… CLASS …">…</div>` の内側を変換（現行 `convert_table_container_inner_markdown` の後継）。
  - div マッチ正規表現は現行を流用: `%r{<div\s+([^>]*\bclass="[^"]*\b#{Regexp.escape(class_name)}\b[^"]*"[^>]*)>\s*(.*?)\s*</div>}m`
  - 内側処理: テーブルブロック抽出 → 各ブロックを `pipe_table_to_html`（`nil` ならそのブロックを Kramdown へ）→ 非テーブル区間は Kramdown → 出現順に結合。
  - `class_name == 'rotate-table'` かつ `page_cfg` があれば §6 の自動算出を行い style 属性へマージ。
- **`intercept_extended_tables(content)`** — 素テーブル横取り（§4）。`Masking.protect_code` → ブロック走査・トリガー判定 → 変換 → `restore_code`。戻り値は `[変換後テキスト, 変換件数]`。
- **`estimate_rotate_style(table_model, page_cfg)`** — §6.2 の純粋関数。

### 7.2 コンテナ内変換のルーティング（現行からの反転）

```
現行: Kramdown で全体変換 → <table が無ければ pipe_table_to_html
新規: テーブルブロックは常に TableConverter → 非テーブル区間と不成立ブロックのみ Kramdown
```

### 7.3 `MarkdownPreprocessor`

`transform_table_rotations!` と `transform_table_containers!` を削除し、以下 1 本へ統合する（`run` 内の呼び出し位置は現行 `transform_table_rotations!` の位置＝`transform_book_cards!` の直後）:

```ruby
TABLE_CONTAINER_CLASSES = %w[long-table rotate-table].freeze

# テーブルコンテナ（long-table / rotate-table）の div 化＋内側テーブルの拡張変換と、
# コンテナ外の拡張テーブル（colspan / 複数行ヘッダー）の横取り変換を行う
def transform_tables!
  # --- Phase: コンテナ変換 ---
  TABLE_CONTAINER_CLASSES.each do |klass|
    context.content, opened, closed = MarkdownTransformer.convert_container_blocks(
      context.content,
      class_name: klass
    )
    next unless opened.positive?

    Common.log_success("#{klass}ブロックの事前変換が完了しました（開始:#{opened}件 終了:#{closed}件）")
    context.content = TableConverter.convert_container_inner(context.content, klass, page_cfg: resolved_page_cfg)
  end

  # --- Phase: 素テーブル横取り ---
  context.content, converted = TableConverter.intercept_extended_tables(context.content)
  Common.log_success("拡張テーブル（colspan/複数行ヘッダー）を#{converted}件変換しました") if converted.positive?
end
```

`resolved_page_cfg` は `Common::CONFIG.page` からプリセット適用済み Hash を解決する private ヘルパー（`Common.apply_page_preset` / `normalize_page_units` の適用状態は CONFIG 読み込み経路に従う。境界で `.to_h` する規約は `resolve_page_size` のコメント準拠）。

### 7.4 撤去

- `MarkdownUtils.pipe_table_to_html`（実装本体）
- `MarkdownTransformer.convert_table_rotate_inner_markdown` / `convert_table_container_inner_markdown`
- `pre_process.rb` の対応する委譲（`TableConverter` への委譲へ置き換え。`pre_process.rb` が既存の一律委譲パターンを取っているため合わせる）

## 8. CSS（`stylesheets/table.css` ＋ scaffold 同期）

```css
/* 結合セル（colspan）は中央寄せ。列整列より結合の視覚的まとまりを優先する */
th[colspan],
td[colspan] {
  text-align: center;
  vertical-align: middle;
}

.rotate-table {
  display: block;
  position: relative;

  /* 専用ページ化 */
  break-before: page;
  break-after: page;
  break-inside: avoid;

  /* ラッパー高さ＝版面高さ。pre_process が --rotate-table-height を mm で注入する。
     フォールバックは旧実装の暫定値（通常は使われない） */
  width: 100%;
  height: var(--rotate-table-height, clamp(320px, calc(500px * var(--paper-scale)), 560px));
  overflow: visible;
}

.rotate-table > table {
  position: absolute;
  top: 50%;
  left: 50%;
  transform-origin: center center;
  /* 完全センタリング基準。--rotate-table-shift-y は中央からの追加オフセット（既定 0%）。
     scale は pre_process の自動算出値または著者指定（scale= パラメータ）が注入される */
  transform: translate(-50%, calc(-50% + var(--rotate-table-shift-y, 0%))) rotate(-90deg) scale(var(--rotate-table-scale, 70%));
  margin: 0;
  inline-size: max-content;
  max-inline-size: none;
  z-index: 0;
}
```

- 現行 `.table-rotate` の `block-size: 100%; min-block-size: 100%;`（後続 `height` に上書きされている死にコード）は撤去する。
- 結合セルの罫線は `border-collapse: collapse` ＋セル毎 border により追加対応不要（調査済み）。
- 縞模様 `tr:nth-child(even)` は thead/tbody 各親内でカウントされるため複数行ヘッダーでも破綻しない（調査済み・変更不要）。

## 9. エッジケース一覧

| 入力 | 挙動 |
|---|---|
| `\|` エスケープ | セル内の生 `|` として復元（インラインコード内も同様） |
| 空白のみのセル | 空セル（マージしない） |
| ゼロ幅セル（行中・行末） | 直前セルの colspan +1（連続で +2, +3…） |
| 行頭のゼロ幅セル | 空セル（マージ先なし） |
| 区切り行が先頭行 / 区切り行なし | 不成立 → コンテナ内は Kramdown フォールバック・素テーブルは横取り対象外 |
| 行のセル数が区切り行の列数超過 | 超過分は整列なしで出力（切り捨てない） |
| 行のセル数が不足 | 不足分は補わない（短い行のまま。現行同様） |
| 4 文字以上インデントされたパイプ行 | テーブルブロックと見なさない（インデントコードブロック保護） |
| コードフェンス内のパイプ表記 | `Masking.protect_code` により横取り対象外 |
| 通常の GFM テーブル（区切り行 2 行目・`\|\|` なし） | 横取りせず VFM へ（完全不変） |
| コンテナ内にキャプション段落＋テーブル | 段落は Kramdown（`<p><strong>…</strong></p>` → 既存キャプション CSS が効く）、テーブルは拡張パーサ |
| コンテナ内に複数テーブル | 各ブロックを個別に変換 |
| セル内の数式 SVG `<img>` / `<br>` / `<span>` | Kramdown 描画により生 HTML 保持 |
| 区切り行自体のゼロ幅（例 `\| --- \|\|`） | 区切り行はセル定義ではないため colspan 解釈しない。ゼロ幅は列として数えない |
| rotate-table で著者が `scale=` 指定 | 自動算出値より著者指定を優先 |
| page 設定が解決できない（テスト単体実行等） | `page_cfg: nil` → 自動算出をスキップし CSS フォールバック値で動作 |

## 10. テスト計画

`test/vivlio_starter/cli/table_converter_test.rb` を新設（Minitest・DAMP・統合スタイル）:

**パーサ単体（`pipe_table_to_html`）**
1. `test_should_convert_basic_table` — 現行相当の基本形
2. `test_should_apply_column_alignment` — `:---` / `:---:` / `---:` → インラインスタイル
3. `test_should_merge_cells_with_colspan` — 行末 `||` → `colspan="2"`・インライン整列なし
4. `test_should_build_multi_row_thead` — §5 の正規例をそのまま入力し期待 HTML と突き合わせ
5. `test_should_keep_whitespace_only_cell_empty` — `|   |` は空セル
6. `test_should_treat_leading_zero_width_cell_as_empty` — `|| x |`
7. `test_should_unescape_pipes` — `\|`
8. `test_should_render_inline_markdown_in_cells` — `**bold**` / `` `code` ``（`<code>foo</code>` が非エスケープで出ること）
9. `test_should_preserve_raw_html_in_cells` — `<img src="x.svg">` 保持
10. `test_should_return_nil_for_non_table` — 不成立入力

**素テーブル横取り（`intercept_extended_tables`）**
11. `test_should_intercept_bare_table_with_colspan`
12. `test_should_intercept_bare_table_with_multi_row_header`
13. `test_should_not_touch_plain_gfm_table` — 通常テーブルは完全不変（バイト一致）
14. `test_should_not_touch_tables_inside_code_fences`
15. `test_should_not_touch_indented_pipe_lines` — 4 文字インデント

**コンテナ統合（`convert_container_inner`）**
16. `test_should_convert_tables_inside_each_container_class` — `long-table` / `rotate-table` 両方＋キャプション段落共存

**自動フィット（`estimate_rotate_style`・純粋関数を固定 page_cfg で検証）**
17. `test_should_estimate_scale_and_height_from_page_and_table` — 既知入力に対する scale/height の期待値
18. `test_should_respect_author_scale_over_auto` — style マージで著者指定優先
19. `test_should_skip_estimation_without_page_cfg`

**既存テストの修正（期待値変更を伴うため実装 PR で明示する）**
- `markdown_transformer_test.rb`: `pipe_table_to_html` 系 3 件を `TableConverter` へ向け替え。`test_pipe_table_to_html_with_code` の期待値を `&lt;code&gt;foo&lt;/code&gt;` → `<code>foo</code>` へ修正（既知バグ解消による意図的変更）。`table-rotate` 参照 4 件を `rotate-table` へ改名。
- 全体は `rake test` で回帰確認。可能なら実ビルド（`vs build`）で `contents/22-extentions.md`・`94-sample.md` の表の見た目を目視確認。

## 11. ドキュメント更新

- `contents/22-extentions.md`「表のレイアウト」:
  - 拡張テーブル記法の節を新設: コンテナ不要で `||`（結合）・複数行ヘッダーが書けること、空セルは `| |` と書くこと、`\|` エスケープ、記法サンプル＋実行結果。
  - `.table-rotate` 節を `.rotate-table` へ改名し、**scale/shift-y が自動算出されること**・手動指定は微調整用であること・`shift-y` の新しい意味（中央からのオフセット・既定 0%）を記載。
- `contents/61-developer.md` 手順 9 を「book-card / テーブル変換（コンテナ＋拡張テーブル横取り）」へ更新。
- `config/spellcheck_dictionaries/vivlio-starter-terms.txt`: `table-rotate` → `rotate-table`。
- scaffold 側（`lib/project_scaffold/`）は `ruby copy_to_scaffold.rb` で同期。
- `CHANGELOG.md`（unreleased）: Added（拡張テーブル・自動フィット）＋ **Breaking 3 点**を明記 — (1) `:::{.table-rotate}` → `:::{.rotate-table}`（旧記法は変換されない）、(2) テーブル内 `||` の意味変更（空セル→結合。空セルは `| |`）、(3) `shift-y` の意味変更（センタリング補正値→中央からの追加オフセット。既定 +25% → 自動センタリング）。本仕様書への参照リンクを付ける。
- `docs/specs/PLANNED.md` の該当項目（[Low] テーブルの横結合）を消化としてマーク（または削除）。

## 12. 将来拡張（本実装のスコープ外）

- **(C) 自動解析**: `long-table`（行数）・`rotate-table`（推定幅が版面超過）の自動判定によるコンテナ記法の廃止。§6.2 の寸法推定がそのまま判定材料に流用できる。レイアウト判断（回転するか縮小するか）は著者意図を含むため、完全自動化より「preflight での警告＋提案」型が現実的。
- **rowspan**: Backlog 風 `^` 等の縦結合。需要が出た時点で `TableConverter` の行モデルに載せる。

## 13. 解決済みの旧未決事項

- ~~クラス名 `table-rotate` ↔ `rotate-table`~~ → **`rotate-table` へ改名で確定**（レビュー合意 2026-07-08。`long-table` との語順統一・後方互換なし）。
- ~~`:::{.colspan-table}` コンテナの要否~~ → **導入しない**（(B) 横取り採用によりフェンス記法自体が不要）。
