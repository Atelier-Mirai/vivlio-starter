# 改ページ制御の改善（空白ページ対策・節改ページの任意化）仕様書

> 作成日: 2026-07-12
> ステータス: **確定仕様・未着手**
> 対象: PLANNED.md [Medium]「改ページ制御の改善（空白ページ対策・任意化）」。3 案 (a) lint 警告 / (b) 連続改ページの正規化 / (c) h2 改ページの設定化 の取捨選択と実装仕様
> 決定事項:
> - **(b)＋(c) を採用し、(a) は不採用**。(b) が黙って無害化するものを (a) が警告するのは矛盾（自動で直る事象への警告はノイズ）。(b) の正規化発生時に `log_info` を出すことで透明性は担保する（`--log` で確認可能）
> - **(b) は post_process の HTML 正規化**として実装する。Markdown 段階では h2 の改ページが CSS 由来（マークアップに現れない）ため検出できず、HTML＋既知の CSS 規約（下記）に対して行うのが唯一確実
> - **(c) のキーは `page.section_page_break`（既定 true）**。`page:` セクションは「版面の物理構造」の置き場であり、節をページ頭から始めるか＝ページネーション挙動はここが適切（PLANNED 例示の `style.*` セクションは存在しない。theme は装飾・色の置き場で不適）
> - **意図的な空白ページ（`---` 連打）は正規化で潰さない**（§2.1-3）
> - [at-directive-tier1-spec.md](at-directive-tier1-spec.md) の `@pagebreak`/`@pagebreak:recto`/`:verso`（`div.vs-break-*`）も正規化の対象に含める（同種の二重改ページが起きるため）。**実装順は Tier 1 の後を推奨**（`hr.pagebreak` 分のみの先行実装も可）
> 関連: `stylesheets/chapter-common.css:255`・`stylesheets/preface.css:159`（`hr.pagebreak { break-after: page }`）, `stylesheets/image-header.css:124`（`body.vs-header-image .section-topic h2 { break-before: page }`）, `stylesheets/simple-header.css:133`（simple スタイルの h2 改ページ）, `stylesheets/components.css:239-245`（EPUB/Kindle 向け `.section-topic h2` の改ページ・legacy 併記）, `lib/vivlio_starter/cli/post_process.rb:76`（`execute_post_process` の処理順）, `lib/vivlio_starter/cli/post_process/section_wrapper.rb`（h2 の article ラップ）, `lib/vivlio_starter/cli/pre_process/book_settings_css.rb`（(c) の生成 CSS 出力先・P3 の条件付き書込みセマンティクス）

## 0. 背景・問題

改ページは現在 2 系統の CSS で発生する:

1. **`---` 記法** → ReplacementRules が `<hr class="pagebreak">` 化 → `hr.pagebreak { break-after: page }`
2. **h2（節見出し）** → `break-before: page`（image スタイル: image-header.css:124 / simple スタイル: simple-header.css:133 / EPUB・Kindle: components.css:244-245）

このため「`---` の直後が `## 見出し`」と書くと break-after ＋ break-before の**二重改ページで空白ページが 1 枚挟まる**。著者は「節の前は区切りを書く」という自然な習慣で書くため、頻発する事故である。

また、ページ数を抑えたい短い本では「節で改ページしない」選択肢そのものが欲しい（現状は CSS を書き換えるしかない）。

VFM は h2 ごとに `<section class="level2">` を生成し（sectionize）、`---` 由来の hr は**直前セクションの末尾要素**として、h2 は**次セクションの先頭**として離れた位置に置かれる。さらに image スタイルでは post_process の `SectionWrapper` が h2 を `<article class="section-topic">` で包む。「隣接」判定はこの構造を跨ぐ必要がある（§2.1-1）。

## 1. 著者向け仕様

### 1.1 二重改ページの自動正規化（(b)・既定で有効）

```markdown
…前節の本文。

---

## 次の節
```

- 従来: 空白ページが 1 枚挟まる → **本仕様後: 空白ページなし**（`---` が冗長と判定され自動で無効化される。h2 自身の改ページが効く）
- `@pagebreak`（単純改ページ）直後の h2 も同様に正規化
- `@pagebreak:recto`／`:verso` 直後の h2 は「**h2 を recto/verso から開始**」と解釈する（recto 指定が勝ち、二重改ページにならない）
- **意図的な空白ページは従来どおり作れる**: `---` を 2 つ重ねると、h2 直前の 1 つだけが正規化され、残りが空白ページを作る

```markdown
---
---

## 空白ページを 1 枚挟んでから始めたい節
```

- 正規化が起きた箇所は `--log`（info）で「`21-images.html`: 冗長な改ページを 2 件正規化しました」と確認できる。既定レベルでは無音（無害な自動修正のため）
- PDF・EPUB・Kindle の全ターゲットに効く（共有 HTML 上の正規化のため）

### 1.2 節改ページの設定化（(c)・`book.yml`）

```yaml
page:
  use: a5_standard
  section_page_break: true   # false にすると h2（節）でページを改めない
```

- 既定 `true`（現行挙動・後方互換）。`false` で節見出しが本文の流れの中に連続して組まれる（ページ数を抑えたい短い本・ハンドアウト向け）
- `false` のとき、`---` や `@pagebreak` は**そのまま生きる**（h2 が改ページしなくなるため冗長ではなくなる——§1.1 の正規化は自動で無効になる）
- 🟡 注意（ドキュメントに明記）: `theme.style: image` の節絵・飾り帯はページ頭に置かれる前提の意匠のため、`false` ではページ中間に飾り帯が現れる。動作はするが、`false` を使う本には `theme.style: simple` を推奨する

## 2. 実装

### 2.1 (b) `PageBreakNormalizer`（post_process・新規）

`lib/vivlio_starter/cli/post_process/page_break_normalizer.rb`:

```ruby
module VivlioStarter
  module CLI
    module PostProcessCommands
      # 二重改ページ（改ページ要素の直後に改ページする h2）を正規化する。
      # 詳細は docs/specs/page-break-control-spec.md §2.1
      module PageBreakNormalizer
        # 改ページを引き起こす著者由来のマーカー要素
        BREAK_MARKERS = 'hr.pagebreak, div.vs-break-page, div.vs-break-recto, div.vs-break-verso'

        module_function

        def normalize!(html_file)
          # page.section_page_break が false なら h2 は改ページしない＝冗長性が消えるため何もしない
          return unless Common::CONFIG.page.section_page_break

          # Nokogiri でパースし、各マーカーについて「文書順で次の内容要素」を求める:
          #   マーカーの次の兄弟（空白テキスト・コメントはスキップ）が無ければ親を遡る
          #   （hr は前セクション末尾・h2 は次セクション先頭に居るため、
          #    section.level2 / article.section-topic のラッパーは透過して降りる）
          # 次の内容要素が h2 のとき:
          #   - hr.pagebreak / div.vs-break-page → マーカーを削除（h2 自身の改ページに一本化）
          #   - div.vs-break-recto / div.vs-break-verso → マーカーは残し、
          #     h2 に class="vs-break-merged" を付与（h2 側の改ページを無効化＝ recto が勝つ）
          # 変更があればファイルへ書き戻し、log_info で件数を報告
        end
      end
    end
  end
end
```

実装上の要点:

1. **隣接判定は「文書順で次の内容要素」**（§0 の構造のため兄弟判定では不足）。走査は「マーカー → 次兄弟が無ければ親へ → 見つけた要素が section/article ラッパーなら最初の内容子孫へ降りる」。h2 以外（p・図・h3 等）に当たったら**正規化しない**（正当な改ページ）
2. **h1 は対象外**。h1 は章ファイル先頭にのみ現れ（章自体が `break-before: recto`・chapter-common.css:9）、`---`＋h1 の並びは実運用で発生しない。過剰な一般化はしない
3. **連続マーカーは h2 直前の 1 個だけを処理**する（走査を「各マーカーごと」に行えば自然にそうなる: `hr hr h2` では 2 個目の hr の次要素だけが h2）。意図的な空白ページ（§1.1）が保存される
4. **recto/verso の合流 CSS**（chapter-common.css へ追加）:

   ```css
   /* PageBreakNormalizer が付与する合流クラス。@pagebreak:recto 直後の h2 は
      recto 側の改ページに一本化する（page-break-control-spec §2.1-4）。
      h2 の改ページ元セレクタ（image-header/simple-header）はスタイル別かつ高特異度のため
      !important で一括無効化する（唯一のユーティリティ用途に限定） */
   h2.vs-break-merged {
     break-before: auto !important;
     page-break-before: auto !important;
   }
   ```

5. **呼び出し位置**: `execute_post_process`（post_process.rb:76）の各ファイル処理で、`ReplacementRules.apply_builtin!`（hr.pagebreak / vs-break-* を生成）と `SectionWrapper`（article ラップ）の**両方が終わった後**に `PageBreakNormalizer.normalize!(html_file)` を追加する

### 2.2 (c) `page.section_page_break`（設定キー＋生成 CSS）

config-extension-guidelines.md の 3 ステップに従う:

1. **スキーマ登録**（common.rb `default_config_schema` の `page` セクション）: `section_page_break: true`
2. **消費**（`BookSettingsCss.generate!` を拡張）: `false` のとき**だけ**以下を book-settings.css へ出力する（P3 の「書かない条件では宣言しない」セマンティクスを踏襲。true では何も出さず既存 CSS が生きる）:

   ```css
   /* page.section_page_break: false — 節（h2）でページを改めない */
   body.vs-header-image .section-topic h2,
   /* ↓ simple スタイルの h2 改ページ元（simple-header.css:133）と
      EPUB/Kindle の .section-topic h2（components.css:244-245）。
      実装時に元セレクタをそのまま複製すること（book-settings.css は後段読込のため
      同特異度なら後勝ちで上書きできる。セレクタが一致しないと特異度負けする） */
   …,
   .section-topic h2 {
     break-before: auto;
     page-break-before: auto;   /* Kindle の legacy 併記（components.css:244）も打ち消す */
   }
   ```

3. **消費テスト**（§3-3）＋ scaffold の book.yml へキーとコメントを追記（`page.use` の下）→ `book_yml_consumption_test` が消費を自動検査

`(b)` との連動は `PageBreakNormalizer` 冒頭の early return（§2.1 コード）で完結する。

### 2.3 実装しないもの（(a) の不採用記録）

「`---` 直後の `##`」への 🟡 lint 警告は実装しない。理由: (b) により当該パターンは**無害**になり、無害な書き方への警告は著者を萎縮させるだけ（warning-messages の方針「警告は行動可能なものだけ」の裏面）。正規化の発生は info ログで追跡可能。将来 (b) を無効化するオプションを設ける場合に限り、警告化を再検討する。

## 3. テスト

Minitest・ruby-coding-rules skill 適用。

1. **`page_break_normalizer_test.rb`（新規・Nokogiri フィクスチャ）**:
   - `hr.pagebreak` → 直後セクションの h2: hr が消える（section.level2 / article.section-topic ラップの両構造で）
   - `hr.pagebreak` → 直後が p・h3・figure: 不変
   - `hr hr h2`: 2 個目だけ消え 1 個目は残る（意図的空白ページの保存）
   - `div.vs-break-page` ＋ h2: div が消える／`div.vs-break-recto` ＋ h2: div 残存＋ h2 に `vs-break-merged` 付与
   - `page.section_page_break: false`（`Common.wrap_config` スタブ）: 一切不変
   - 変更時に info ログ・件数
2. **`replacement_rules` 系（既存への追加なし）**: 正規化は別ステップのため既存スナップショットに影響しないことを `rake test` で確認
3. **`book_settings_css` テスト追加**: `section_page_break: false` で打ち消しセレクタ一式が出力される／`true`（既定）では**何も出力されない**
4. **結合（`rake test:layout`・任意）**: `---`＋`## 見出し` を含む章のビルドで、本仕様の前後で総ページ数が 1 減ること。`section_page_break: false` ビルドで h2 が改ページしないこと
5. **EPUB/Kindle（手動）**: 正規化済み HTML から生成した EPUB で二重改ページが消えること（Kindle Previewer 目視）

## 4. 手順（実装順序）

1. §2.2 (c) 設定キー＋生成 CSS ＋テスト（(b) と独立・単独コミット可）
2. §2.1 (b) `PageBreakNormalizer`（まず `hr.pagebreak` のみ）＋合流 CSS ＋テスト
3. at-directive-tier1-spec 実装後に `vs-break-*` 対応を追加（Tier 1 が先に入っていれば 2. と同時でよい）
4. ドキュメント: `contents/` の改ページ解説（`---` の章）へ「h2 直前の `---` は自動正規化」「空白ページは `---` 連打」「`page.section_page_break`」を追記。book.yml コメント → `ruby copy_to_scaffold.rb`
5. `rake test` → §3-4/5 の実機確認

## 5. スコープ外

- **(a) lint 警告**: 不採用（§2.3 に理由を記録）
- **h3 以下・h1 の改ページ制御**: h2 のみが対象（現状 CSS で改ページするのは h2 だけ。h1 は章単位の recto 開始でありビルド構造の一部）
- **`---` 記法自体の意味変更**（break-after → break-before 化など）: 既存原稿の見え方を変えるため行わない。正規化はあくまで冗長ケースの無効化に限定
- **部タイトルページ（part-title.css の recto/verso）との相互作用**: 部扉は独立生成ページ（PartTitleGenerator）で本文 HTML の隣接判定に現れないため対象外
