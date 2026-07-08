# `:::{.terminal}` リテラル化 仕様書

## 現況（2026-07-08 時点）

**未実装。この仕様書に沿ってこれから実装する。**

前提としていた [container-class-validation-spec](container-class-validation-spec.md)（`vs preflight` の `:::` 構造検証）は **実装済み**（`Guards::ContainerFenceCheck` / `ContainerClassCheck` / `ContainerScanner`）。両ガードとの関係は次のとおりで、**本仕様の実装で壊れるものは無い**。

- `ContainerClassCheck` は `contents/*.md` を**生で**読み、許可リストを `stylesheets/**/*.css` から抽出する。`.terminal` は本仕様の実装後も CSS クラスとして残る（`<pre>` を装飾する）ため、許可され続ける。
- `ContainerFenceCheck` も生原稿を読むため、前処理の変更（`transform_terminal_blocks!` の追加）の影響を受けない。
- 前処理でフェンス化した後は `:::{.terminal}` が消えるため、`post_replace_list.yml` の経路 B には届かなくなる。これが本仕様の目的そのもの。

以下の記述はすべて `@vivliostyle/vfm` の実挙動と現行コードに対して実測で裏付けてある（参照行番号も検証済み）。

## 背景 — 「プロンプト記号を設定可能にする」は不要と結論した

当初 `prompt-setting-spec.md` として「`:::{.terminal}` の行頭プロンプト記号（`$` / `%` / なし）を `book.yml` で設定する」機能を検討したが、**実装不要**と結論し、当該仕様書は破棄した。理由:

- どの行がコマンドで、どの行が出力かは**著者だけが知っている**。素朴な「全行に記号を前置」実装は、`$ ls` の出力行 `foobar.png` にまで記号を付けてしまう。
- ならば著者が `$` を自分で書けばよい。そうすれば `cp`/`mv`/`rm` のような無応答コマンドも、`ls` のようなコマンド＋出力の混在も、機械の推測なしに正しく組める。
- 残る差分は「記号の色付け」という純粋な装飾のみで、設定機構に値しない。`prompt: "%"` による bash→zsh 一括変換も、一度きりの `sed` で済む。

しかし「著者が `$` を書く」を前提に据えた瞬間、**現状の `.terminal` がその書き方を正しく組版できない**ことが判明した。本仕様書はその不具合の修正を扱う。

## 問題 — `.terminal` の中身が素の Markdown として解釈されている

`:::{.terminal}` は前処理を通らず、`config/post_replace_list.yml:33` の正規表現が **HTML 生成後**に `<div class="terminal">` へ変換している。つまり中身は VFM に素の Markdown として渡る。シェルのコマンドと端末出力は、Markdown のメタ文字を最も多く含むテキストである。

`@vivliostyle/vfm` の `stringify(md, { math: true, hardLineBreaks: true })` で実測した結果:

| 入力 | 現在の出力 | 影響 |
|---|---|---|
| `$ cp *.png *.bak` | `$ cp <em>.png </em>.bak` | `*` が消え斜体化 |
| ``$ echo `date` `` | `$ echo <code>date</code>` | バッククォートが消える |
| `$ echo $A$B` | `$ echo \(A\)B` | `$A$` が数式化（`$1, $2` や `"from $5 to $9"` は空白があるため無傷） |
| `$ mv _old_ _new_` | `$ mv <em>old</em> <em>new</em>` | 両端が空白に接する `_` が強調化（`_old_file.txt` は語中 `_` のため無傷） |
| `| id | name  | email |` | `| id | name | email |` | **連続空白が HTML 生成時に消滅**し桁揃えが崩壊 |
| `contact@a.net` | `<a href="mailto:contact@a.net">` | 自動リンク化 |
| `---` の行 | `<hr>` → `post_replace_list.yml:46` が `<hr class="pagebreak">` に変換 | **本文が改ページされる** |

連続空白は**HTML の時点で失われている**ため、`white-space: pre` を後から足しても救えない。リテラル化が必須である。

なお `+----+---+` / `| id | name |` 形式の SQL 出力が Markdown テーブルとして誤認される懸念は**杞憂**（区切り行が成立しない）。実害は上表の桁崩壊・自動リンク・改ページである。

## 設計

### 方針

`.terminal` は「端末の逐語転写」である。中身は Markdown ではなくリテラルとして扱い、実体は `<pre>` とする。

- **`.terminal`** — 逐語。コマンドと出力を 1 ブロックに混在させてよい。プロンプト記号は著者が書く。
- **`.output`** — 整形された結果表示。中身は Markdown のまま（箇条書き・表を入れる既存用途と原稿互換を保つ）。逐語の出力を入れたい場合は `.output` の中にコードフェンスを書く（実測で空白完全保持を確認済み）。

### 変換経路

既存の「フェンス付きコードブロックはあらゆる前処理ステップから保護される」機構（`Masking.protect_code` / `MarkdownUtils.extract_code_spans`）に相乗りする。専用のプレースホルダ機構は作らない。

1. **前処理（Markdown）** — `:::{.terminal}` … `:::` を、独自言語名のチルダフェンスへ書き換える:

   ```
   ~~~vs-terminal
   $ cp *.png *.bak
   ~~~
   ```

   以降の前処理ステップ（`transform_math!` を含む）は `protect_code` によりフェンス内を退避するため、中身に一切触れない。

2. **VFM** — フェンスは `<pre class="language-vs-terminal"><code class="language-vs-terminal">…</code></pre>` になる。HTML エスケープと空白保持は VFM が行う。空行を含んでも壊れないことを実測で確認済み。

3. **後処理（HTML）** — 上記ノードを `<div class="terminal"><pre>…</pre></div>` へ置換する（`language-*` クラスは除去。`stylesheets/code.css:9` の `pre[class*="language-"]` に巻き込まれるため）。

`<pre>` を `<div class="terminal">` で包む理由: `EpubBuilder::ADMONITION_LABELS` の Kindle 用ラベル注入が `doc.css("div.terminal")` に依存しており、かつ `<p class="vs-adm-label">` を `<pre>` の内側に置くことはできない。div で包めば、ラベルは `<pre>` の兄弟として `<pre>` の前に入り、既存の Kindle 経路がそのまま生きる。

## 実装

### 1. 前処理ステップの追加

- `lib/vivlio_starter/cli/pre_process/markdown_transformer.rb`
  - `convert_terminal_blocks(content)` を追加。
  - 先頭で `MarkdownUtils.extract_code_spans` により退避する（`contents/22-extentions.md` の記法解説フェンス内にある `:::{.terminal}` を変換対象外にするため）。
  - 対象パターン: `/^:{3,}[ \t]*\{\.terminal\}[ \t]*\n(.*?)^:{3,}[ \t]*$\n?/m`
  - フェンス長は「本文中の最長の `~` 連続 + 1」と `3` の大きい方（本文に `~~~` が現れても壊れないように）。
  - 出力は前後に空行を伴う `~~~vs-terminal` フェンス。
- `lib/vivlio_starter/cli/pre_process/markdown_preprocessor.rb`
  - `run` の `strip_html_comments!` の直後に `transform_terminal_blocks!` を挿入する。`transform_math!`（`$…$` の SVG 化）より前でなければならない。
  - `normalize_container_fences!` が `:::` の前後に空行を補う処理より前に走るため、terminal ブロックはその時点で既に消えている。

### 2. 後処理コンバータの追加

- `lib/vivlio_starter/cli/post_process/terminal_block_converter.rb`（新規）
  - `pre.language-vs-terminal` を `<div class="terminal"><pre>…</pre></div>` へ置換。`<code>` ラッパは畳む。
  - `HtmlParser.parse_html_document` / `save_html_document` を用いる（既存の後処理と同様）。
- `lib/vivlio_starter/cli/post_process.rb`
  - `execute_post_process` 内、`BodyClassInjector.inject_body_class` と同じループ位置（`HtmlReplacer` より前）で呼ぶ。
  - `HtmlReplacer` は `:tag_aware` / `:text_only` の双方で `<pre>…</pre>` を退避するため、変換後の中身は後続の置換ルール（`<hr>` → `pagebreak` 等）から保護される。

### 3. CSS（**root で編集し `ruby copy_to_scaffold.rb` で同期**）

- `stylesheets/chapter-common.css`
  - `.terminal p { … }` を廃し、`.terminal pre` を追加:
    ```css
    .terminal pre {
      margin: 0;
      white-space: pre-wrap;      /* 長いコマンドは折り返しつつ、連続空白は保つ */
      overflow-wrap: anywhere;
      font-family: var(--font-code), monospace;
      background: none;
      border: none;
      color: inherit;
    }
    ```
  - Kindle: `body.vs-kindle .terminal pre { font-family: monospace; color: #f5f5f5; }`（`var()` 不可のため）。
    `body.vs-kindle .terminal .vs-adm-label` の既存ルールは div 直下の兄弟に当たるためそのまま有効。
  - `.output` 内のコードフェンスが二重枠にならないよう:
    ```css
    .output pre[class*="language-"] { border: none; margin: 0; background: none; }
    ```
    セレクタ特異度は `code.css:9` の `pre[class*="language-"]`（0,1,1）を上回る（0,2,1）ため、読み込み順に依らず勝つ。

### 4. ドキュメント

- `contents/22-extentions.md`
  - `.terminal` の節に「中身はリテラル。コマンドと出力を混在させてよい。プロンプト記号（`$` / `%` / `#`）は著者が書く」を明記。
  - `.output` の節に「中身は Markdown。桁揃えが要る逐語出力はコードフェンスで囲む」を明記し、SQL テーブル出力の例を載せる。

## テスト

- `test/vivlio_starter/cli/markdown_transformer_test.rb`
  - `convert_terminal_blocks`: `*.png` / `` `date` `` / `$A$B` / `_old_ _new_` / `---` / 連続空白 / 空行を含む本文 が、いずれもフェンス内に逐語で入ること。
  - ```` ```markdown ```` フェンス内の `:::{.terminal}` は変換されないこと。
  - 本文に `~~~` を含む場合にフェンス長が伸びること。
- `test/vivlio_starter/cli/post_process/terminal_block_converter_test.rb`（新規。既存の `footnote_converter_test.rb` / `html_replacer_test.rb` と同じ置き場）
  - `pre.language-vs-terminal` → `div.terminal > pre`、`language-*` クラスが残らないこと。
- `test/vivlio_starter/cli/build/epub_kindle_layout_test.rb`
  - `div.terminal` の先頭に `【TERMINAL】` ラベルが `<pre>` の前に注入されること（既存アサーションが `<pre>` 化後も通ること）。
- `test/vivlio_starter/page_layout/`（`rake test:layout`）
  - `---` を含む `.terminal` ブロックが改ページを起こさないこと。

## 非目標

- **プロンプト記号の設定機構**（`book.yml` / ブロック属性）。上記「背景」のとおり却下。
- **`admonitions.*.style` による CSS の YAML 化**。枠線・地色は `chapter-common.css` にあり、著者は `stylesheets/` で上書きできる。YAML から CSS を生成すると見た目の真実が二重化し、値のサニタイズ・特異度・Kindle の `var()` 不可制約を新たに背負う。
- **`.output` のリテラル化**。箇条書き・表を入れる既存用途と原稿互換を壊す。逐語が要る場合は内側にコードフェンスを書く。

## 後方互換について

`.terminal` の中身に Markdown（リンク・強調・インラインコード）を書いていた原稿は、それらがリテラル表示になる。これは本仕様の意図そのもの。現行の `contents/` 配下で `:::{.terminal}` を使っているのは `contents/22-extentions.md` の 2 箇所のみで、いずれも `vs build` の単一行であり影響はない。
