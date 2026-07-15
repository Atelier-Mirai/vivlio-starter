# lint 記法ガード（Notation Guard）＋ `--fix` 修復 仕様書

> 作成日: 2026-07-16
> ステータス: **確定仕様・実装待ち**
> 元報告: [lint-notation-guard-report.md](lint-notation-guard-report.md)（実測値・設計案比較・調査過程の詳細はそちら。本書は**実装に必要な決定と手順**に絞る）
> 対象: `vs lint` が VFM 記法（機械データ）を日本語の文として誤検出する問題の根治（`textlint_allowlist.yml` への記法エントリ流用の解消）、および調査中に発見した **`vs lint --fix` が no-op である既存バグ**の修復
> 決定事項（報告書 §7 の未決事項はすべて本書 §5 で決定済み）:
> - 設計は報告書の**案 A**（前段でマスクした一時ファイルを textlint に渡す）を採用
> - 記法の知識は **`Lint::NotationGuard` を新設**して集約する（`Masking` の責務は広げない。理由: §3.1）
> - **`--fix` 修復を Phase 0 として先行**させる（独立コミット。ガードの設計が fix の直し方に依存するため）
> - 機械データ・ブロックは**宣言的な定数**（コンテナ名の配列）で持つ
> - allowlist の「VFM 記法」5 エントリは**全撤去**（root + scaffold 同期）
> 関連: `lib/vivlio_starter/cli/lint.rb`, `lib/vivlio_starter/cli/masking.rb`, `lib/vivlio_starter/cli/lint/tokenizer.rb`, `config/textlint_allowlist.yml`, `test/vivlio_starter/robustness/lint_fix_interrupt_test.rb`, `docs/specs/explanatory-diagram-spec.md`

## 0. 背景（要約）

`vs lint` は原稿を textlint へ渡す前に一時ファイルへ変換する前段
（`convert_vs_lint_comments` / `rewrite_vs_lint_to_textlint`、`lint.rb:419-440`）を既に持つ。
しかし VFM 記法（`:::{.showcase}` の座標行・ふりがな記法・クラス属性など）はそのまま
textlint に渡り、日本語の文として誤検出される（実測: showcase ブロックだけで 9 件、
allowlist が肩代わりしている分が 76 件）。現状は `config/textlint_allowlist.yml` の
「VFM 記法」エントリで抑え込んでいるが、これは語彙除外リストの誤用であり、
文脈を持てないため `sentence-length` 系の誤検出は消せていない（詳細は報告書 §2〜§3）。

また、調査中に **`vs lint --fix` が一時ファイルを修正して捨てるだけの no-op** である
ことが判明した（報告書 §4.1。再現手順・実測 md5 込みで確認済み）。

## 1. フェーズ構成

| フェーズ | 内容 | コミット |
|---|---|---|
| **Phase 0** | `vs lint --fix` の修復（書き戻し経路の新設） | 独立コミットで先行 |
| **Phase 1** | `Lint::NotationGuard` 新設・lint/スペルチェックへの接続・allowlist 撤去 | Phase 0 の後 |

Phase 0 を先行させる理由: ガード済み一時ファイルは記法が中和されており、そのまま原稿へ
書き戻せない。fix の書き戻し経路（§2.3）を先に確定させることで、Phase 1 は
「ガードは解析パスのみに適用」という単純な形で載る。

---

## 2. Phase 0 — `vs lint --fix` の修復

### 2.1 現状の不具合（コードで確認済み）

- `run_textlint`（`lint.rb:132-140`）は無条件に一時ファイルを作り、`ensure` で削除する。
- `build_command`（`lint.rb:312-317`）は `--fix` をその**一時ファイルに対して**付ける。
- 結果、`--fix` は原稿を 1 バイトも変更しない no-op。しかもサマリーは
  「自動修正可能です → `vs lint --fix`」と案内し続ける。

### 2.2 修正後の動作（正常系）

```bash
$ vs lint --fix --textlint-only 97
# → prh 等の自動修正が contents/97-*.md へ実際に適用される
# → 適用後の残存指摘が通常の集約表示で出る
# → 再実行すると修正済みの指摘は出ない（冪等）
```

### 2.3 設計: 2 パス方式

`options[:fix]` のとき、解析の前に **fix パス**を挟む。

```
--fix あり:
  ① fix パス   : コメント変換のみの一時ファイル → textlint --fix → 差分があれば原稿へ書き戻し
  ② 解析パス   : 通常どおり（Phase 1 以降はガード付き）一時ファイル → --format json → 集約表示
--fix なし:
  ② 解析パスのみ（現行どおり）
```

#### ① fix パスの手順

1. 各原稿について `rewrite_vs_lint_to_textlint` を適用した一時ファイルを作る
   （**記法ガードは適用しない**。ガードは中和＝非可逆のため fix 経路に入れてはならない）。
   変換後の内容はメモリに保持しておく（手順 4 の変更検出に使う）。
2. `textlint --fix --config <effective_config> <一時ファイル...>` を実行する。
   `--format json` は付けない。stdout は `log_debug` へ流し、終了コードは判定に使わない
   （最終判定は②解析パスの結果で行う）。
3. 各一時ファイルを読み戻し、手順 1 で保持した変換後内容と**比較**する。
   不一致（= textlint が実際に修正した）ファイルだけを次へ進める。
   一致したファイルは書き戻さない（原稿の mtime・コメント書式を無駄に変えない）。
4. 修正されたファイルは**逆変換**してから原稿へ書き戻す:
   - `/<!--\s*textlint-disable-next-line\s*-->/` → `<!-- vs-lint-disable-next-line -->`
   - `/<!--\s*textlint-disable\s*-->/` → `<!-- vs-lint-disable -->`
   - `/<!--\s*textlint-enable\s*-->/` → `<!-- vs-lint-enable -->`
   - **next-line を先に**処理する（順序を守れば `textlint-disable` のパターンが
     next-line 形を誤マッチすることはない——`disable` の直後が `-n` であり `\s*-->` に合致しないため）。
   - 許容する副作用: 著者が素の `<!-- textlint-disable -->` を直書きしていた場合も
     vs-lint 形へ正規化される（機能は等価。vs-lint 形が本プロジェクトの正典記法）。
5. 書き戻しは**アトミック置換**で行う: 原稿と同一ディレクトリに一時ファイルを書き、
   元ファイルのパーミッションを引き継いだうえで `File.rename` で置換する。
   `File.write` 直書きは不可（書き込み途中の Interrupt で原稿が壊れる）。
6. `ensure` で一時ファイルを削除する（現行の `cleanup_temp_files` と同様）。

#### ② 解析パスとサマリー

- fix パス後、通常の解析パスを（修正済みの原稿から）実行して残存指摘を表示する。
  終了コードもこの結果で決める（残存 0 なら 0）。
- `print_combined_summary` の `--fix` 時表示を実態に合わせる:
  修正が適用された場合は「🔧 N ファイルへ自動修正を適用しました」を出し、
  そのうえで残存指摘のサマリーを続ける（N = 手順 3 で不一致だったファイル数）。

#### 安全性の不変条件（維持すべき性質）

- textlint プロセス実行中（手順 2）に Interrupt / StandardError が起きても、
  原稿は 1 バイトも変わらない（書き戻しは手順 4-5 まで発生しないため自明に成立）。
- 書き戻し中の中断でも、原稿は「旧内容のまま」か「新内容へ完全置換済み」の
  いずれかである（アトミック置換の効果）。
- どの経路でも一時ファイル（`/tmp/textlint_*.md`）が残らない。

### 2.4 テストの変更（報告書 §4.1.1 の確定版）

`test/vivlio_starter/robustness/lint_fix_interrupt_test.rb`:

| テスト | 扱い |
|---|---|
| `test_original_file_is_untouched_on_normal_completion` | **書き換え**。2 本に分割する: (a) `fix: false` の正常終了では元ファイル不変、(b) `fix: true` で textlint が一時ファイルを修正した場合（`Open3.stub` で一時ファイルへ修正済み内容を書き込むスタブを使う）、元ファイルが**修正済み＋vs-lint コメント形へ逆変換済み**になること |
| `test_original_file_is_untouched_when_interrupt_raised` | **維持**（中断時に原稿が壊れない性質は Phase 0 後も成立する） |
| `test_original_file_is_untouched_when_standard_error_raised` | **維持**（同上） |
| `test_textlint_receives_tempfile_not_original_path` | **維持**（fix 経路も一時ファイルを渡す設計のため前提は変わらない） |
| 新規: 変更なしファイルは書き戻されない | textlint が何も修正しなかった場合、原稿の内容・mtime が不変であること（コメント書式の正規化が漏れ出ないことの検証を兼ねる） |

ファイル冒頭コメントの「元ファイルを一切書き換えず…発生しない」という結論の記述も、
新しい設計（fix 時のみ・完了後のみ・アトミックに書き戻す）に合わせて書き直すこと。

### 2.5 受け入れ基準

報告書 §4.1 の再現手順がそのまま検証になる:

```bash
$ printf '# テスト章\n\nここに気を付けると良いです。\n詳しくは下さいと書きます。\n' > contents/97-fixtest.md
$ vs lint --fix --textlint-only 97   # → 修正が適用され、prh 指摘が出ない（または残存のみ）
$ md5 -q contents/97-fixtest.md      # → 実行前と異なる
$ vs lint --textlint-only 97         # → prh の 3 件が消えている
```

加えて `rake test` 全通過（`rake test:standard` も念のため確認）。

---

## 3. Phase 1 — `Lint::NotationGuard`

### 3.1 置き場所: 新設モジュール（`Masking` は広げない）

**`lib/vivlio_starter/cli/lint/notation_guard.rb`** に `VivlioStarter::CLI::Lint::NotationGuard` を
新設する。`Masking` は内部で利用するが、`Masking` 自体には手を入れない。

報告書 §6.1 は「`Masking` の責務を広げる」案も残していたが、これは**不採用**とする。
根拠（調査結果）: `Masking.each_prose_line` は lint 以外に
`image_path_normalizer` / `link_image_validator` / `cross_reference_processor` /
`frontmatter_generator` / `markdown_transformer` / `index_match_scanner` /
`metrics/sentence_collector` / `guards/container_scanner` など **10 箇所以上**から
「コード領域の唯一の解釈」として使われている。ここに記法の知識を混ぜると、
たとえば showcase ブロック内の画像行を `image_path_normalizer` が見なくなるなど、
**lint と無関係な前処理へ意味変更が波及**する。記法の中和は lint 系だけの要求なので、
知識は `NotationGuard` の 1 箇所に置き（不変条件 I5）、`Masking` は
「コード領域解釈の原器」のまま据え置く。

### 3.2 公開 API

```ruby
module VivlioStarter
  module CLI
    module Lint
      # VFM 記法（機械データ）を中和したテキストを返す。行数は必ず保存する（I1）。
      # コード領域（フェンス・インラインコード）には一切触れない——textlint は
      # ja-space-around-code 等でコードの存在自体を検査するため、コードを消してはならない。
      module NotationGuard
        module_function

        # 機械データを本文として持つコンテナ名の一覧（宣言的）。
        # 記法を追加するときはここに 1 語足すだけでガードが追従する。
        MACHINE_DATA_CONTAINERS = %w[showcase].freeze

        def strip_notation(text)
      end
    end
  end
end
```

### 3.3 変換規則

v1 のスコープは「**現行 allowlist の VFM 5 エントリの機能置換＋機械データ・ブロック**」に
限定する（守備範囲を広げすぎて地の文へ穴を開けない。I3）。

| # | 分類 | 判定パターン | 変換 | 根拠 |
|---|---|---|---|---|
| G1 | 機械データ・ブロック | 開始行 `/\A:::\s*\{\s*\.(?:showcase)\s*\}/`（`MACHINE_DATA_CONTAINERS` から生成。`ShowcaseTransformer::BLOCK_PATTERN` の開始と整合させる）〜 終了行 `/\A:::[ \t]*\r?\n?\z/` | 開始・内容・終了の**全行を空行化** | 座標とオプションの機械データ。地の文なし。前処理で丸ごと消費されるブロック |
| G2 | コンテナのマーカー行 | 行頭 `/\A[ \t]*:{3,}/`（G1 のブロック外） | 行ごと空行化 | `:::{.column}` / `::::` / 閉じ `:::`。記法であって文ではない。**コンテナ内部の地の文は検査対象のまま**（マーカー行だけを消す） |
| G3 | ふりがな記法 | `/\{([^{}\|]*)\|[^{}]*\}/` | **親文字（`$1`）だけ残す** | 親文字は地の文であり検査対象（I3）。`{Albert Einstein\|アルバート…}` → `Albert Einstein` |
| G4 | クラス属性記法 | `/\{\.[-\w]+\}/`（G3 の後に適用） | 除去（空文字） | `{.aki}` `{.text-right}` 等。属性であって文ではない |
| — | コード | — | **不変**（フェンス・インラインとも） | textlint 側の検査対象（コード前後スペース等）。除外判定のみ `Masking` に委ねる |

適用順序: G1 → G2 →（残った地の文行に対して）G3 → G4。

### 3.4 実装アルゴリズム

```ruby
def strip_notation(text)
  prose   = Masking.each_prose_line(text).map { |_line, lineno| lineno }.to_set
  machine = machine_block_lines(text, prose)   # G1 に該当する行番号の集合

  text.each_line.with_index(1).map { |line, lineno|
    if !prose.include?(lineno)  then line                 # コード領域は不変
    elsif machine.include?(lineno) then blank(line)       # G1
    elsif container_marker?(line)  then blank(line)       # G2
    else neutralize_inline(line)                          # G3 → G4
    end
  }.join
end
```

- `blank(line)`: 行を空にして**改行だけ残す**（`line.end_with?("\n") ? "\n" : ''`）。
  最終行に改行が無いケースでも行数・末尾形状を変えない（I1）。
- `machine_block_lines`: 行を先頭から走査し、**prose 行**が G1 の開始パターンに一致したら
  ブロック開始。以降、終了行パターンに一致する行（この行も含む）までを集合に入れる。
  **終了行が見つからないままファイル末尾に達した場合、そのブロックは無かったものとする**
  （`ShowcaseTransformer::BLOCK_PATTERN` が閉じ必須で一致しないのと整合。未終了フェンスを
  退避しない `Masking` の方針とも揃う）。
- `neutralize_inline(line)`: 行内のインラインコードを `Masking.protect_code` で退避してから
  G3・G4 を適用し、`Masking.restore_code` で戻す。行単位で呼ぶため、フェンス誤爆の
  心配はない（開始だけのフェンス行は未終了扱いで素通しされる）。地の文で記法を
  **解説している** `` `{.aki}` `` のような箇所を壊さないための必須手順。
- 重要な前提: `contents/22-extentions.md` は ```` ```markdown ```` フェンス内に showcase の
  **書き方の例**を含む。これらはコード領域なので G1〜G4 の対象外（不変で残り、
  textlint はコードとして無視する）。テストで必ず担保すること（§3.8）。

### 3.5 接続点の変更

#### textlint 側（`lint.rb`）

```ruby
# 解析パス（--format json）で使う一時ファイルにのみガードを適用する。
# fix パス（Phase 0 の①）はコメント変換のみ＝ガードなし（中和は非可逆のため）。
def rewrite_vs_lint_to_textlint(source, guard: true)
  source = Lint::NotationGuard.strip_notation(source) if guard
  source
    .gsub(/<!--\s*vs-lint-disable-next-line\s*-->/, '<!-- textlint-disable-next-line -->')
    ...
end
```

`convert_vs_lint_comments(files, guard:)` として貫通させ、fix パスは `guard: false`、
解析パスは `guard: true` で呼ぶ。

#### スペルチェック側（`lint/tokenizer.rb`）

`Tokenizer` が原稿を読み込んだ直後に `NotationGuard.strip_notation` を通してから
既存の `Masking.each_prose_line` ベースの走査に入る。行数保存（I1）により行番号表示は
そのまま正しい。これで `rect` / `pos` / `Einstein.webp` のような記法内トークンが
未知語として湧く経路が閉じ、textlint とスペルチェックの記法判定が一本化される。

#### 著者向けの逃げ道（変更不要）

ガードが効きすぎた場合の個別回避として `<!-- vs-lint-disable -->` 系は従来どおり機能する。

### 3.6 allowlist の撤去と scaffold 同期

1. `config/textlint_allowlist.yml` から「VFM（Vivliostyle Flavored Markdown）の記法」の
   **5 エントリとその節見出しコメントを削除**する。書籍名・資格名称・専門用語の節は残す。
2. ファイル冒頭の説明コメントは現状のまま（「書籍名、資格名称、専門用語など」）で、
   実態と一致する状態に戻る。
3. **scaffold 同期**: root を編集したら `ruby copy_to_scaffold.rb` を実行する
   （`lib/project_scaffold/config/textlint_allowlist.yml` を直接編集しない）。

撤去は**ガード実装・検証（§3.9 手順 1）の後**に行うこと。順序を守れば、撤去による
指摘の増減がガードの効果測定と分離できる。

### 3.7 不変条件（報告書 §5.1 の確定版）

| # | 不変条件 | 充足方法 |
|---|---|---|
| I1 | 行番号の保存 | 空行化＋行内置換のみ。行の追加・削除・結合をしない |
| I2 | 列番号は保存不要 | 集約表示はルール名と行番号のみ。行内置換は自由 |
| I3 | 地の文を 1 文字も落とさない | 変換規則を G1〜G4 に限定。ふりがなは親文字を残す。§3.9 の総数比較で回帰検知 |
| I4 | `--fix` を壊さない | ガードは解析パス専用。fix パスは Phase 0 の設計どおりガードなし |
| I5 | 記法の知識は 1 箇所 | `NotationGuard` に集約。textlint・スペルチェック両方がここを参照 |

### 3.8 テスト

新規 `test/vivlio_starter/cli/lint/notation_guard_test.rb`（単体・textlint 不要）:

- G1: showcase ブロック（開始・rect/pointer 行・画像行・終了）が全行空行化される
- G1: 未終了の showcase ブロックは変換されない
- G2: `:::{.column}` / `::::` / 閉じ `:::` が空行化され、**コンテナ内部の地の文は残る**
- G3: `{Albert Einstein|アルバート・アインシュタイン}` → `Albert Einstein`（親文字保存）
- G4: `{.aki}` が消え、周囲の地の文は不変
- コード保全: ```` ```markdown ```` フェンス内の showcase 例・`` `{.aki}` `` インラインコードが
  **1 文字も変わらない**
- I1: あらゆる入力で `lines.count` が変換前後で一致する（最終行に改行が無いケースを含む）
- `MACHINE_DATA_CONTAINERS` に仮の名を足すとそのコンテナもブロック扱いになる（宣言性の担保）

既存テストへの影響: lint 系・robustness 系が全通過すること（`rake test`）。

### 3.9 検証手順と受け入れ基準

実原稿での測定（報告書 §2 の実測と対になる）:

1. **ガード実装後・allowlist 撤去前**: `vs lint --textlint-only 22 94` を実行。
   → showcase ブロック内の 9 件（`sentence-length` / `max-comma`）が **0 件**になる。
   → それ以外の指摘（地の文への指摘）が 1 件も減っていない（I3 の回帰チェック）。
2. **allowlist の VFM 5 エントリ撤去後**: 同コマンドを再実行。
   → 記法由来の誤検出（撤去前に +76 件あった分）が**再発しない**。
   → 新たに現れた指摘があれば個別に目視確認する。記法由来なら G1〜G4 の漏れとして
   ガード側を修正。**地の文への正当な指摘なら受け入れる**（allowlist のグローバル正規表現が
   本来の検出まで飲み込んでいた分の復活であり、回帰ではない。報告書 §3 問題 3）。
   `":::"` 素文字列エントリの残渣（報告書 §7 論点 4）もここで判明する。
3. 全章 `vs lint` がエラーなく完走し、`rake test` が全通過する。

---

## 4. 成果物一覧

| ファイル | 変更 | フェーズ |
|---|---|---|
| `lib/vivlio_starter/cli/lint.rb` | fix パス新設（2 パス化・逆変換・アトミック書き戻し）、`convert_vs_lint_comments(files, guard:)`、サマリー表示 | 0, 1 |
| `test/vivlio_starter/robustness/lint_fix_interrupt_test.rb` | §2.4 のとおり書き換え・追加 | 0 |
| `lib/vivlio_starter/cli/lint/notation_guard.rb` | 新設 | 1 |
| `lib/vivlio_starter/cli/lint/tokenizer.rb` | `strip_notation` を読み込み直後に適用 | 1 |
| `test/vivlio_starter/cli/lint/notation_guard_test.rb` | 新設（§3.8） | 1 |
| `config/textlint_allowlist.yml` | VFM 5 エントリ撤去（root 編集 → `ruby copy_to_scaffold.rb`） | 1 |
| `docs/specs/explanatory-diagram-spec.md` | 冒頭の「未解決（要判断）: textlint が showcase を…」注記を本仕様への参照に差し替え | 1 |

## 5. 報告書 §7（未決事項）の決定一覧

| # | 論点 | 決定 |
|---|---|---|
| 1 | `--fix` の扱い | 2 パス方式（§2.3）。fix パスはガードなし・コメント変換のみ → 逆変換して書き戻し。ガードは解析パス専用 |
| 2 | 置き場所 | `Lint::NotationGuard` 新設。`Masking` は据え置き（§3.1 の波及調査が根拠） |
| 3 | ガードの粒度 | 宣言的一覧 `MACHINE_DATA_CONTAINERS`。記法追加時の変更は 1 語 |
| 4 | allowlist の撤去範囲 | 5 エントリ全撤去。残渣は §3.9 手順 2 で実測して判定（記法由来ならガード修正・正当なら受け入れ） |
| 5 | scaffold 同期 | root 編集 → `ruby copy_to_scaffold.rb`（直接編集禁止） |
| 6 | 著者向けの逃げ道 | `<!-- vs-lint-disable -->` 系を維持（変更不要） |

## 6. スコープ外（将来）

- `{width=50%}` `{#id}` 等の属性記法の中和: 現行 allowlist に対応エントリが無く実害未測定。
  誤検出が観測されたら G4 の隣へパターンを 1 つ足す（構造は本仕様のまま受け入れられる）。
- `vs metrics`（`sentence_collector` / `analyzer`）への `strip_notation` 適用:
  文長統計からも記法を除けるはずだが、lint とは検証条件が別なので本仕様には含めない。
- 案 B（後段の行範囲フィルタ）: 案 A の実測（§3.9）で取りこぼしが出た場合の保険として
  報告書 §5.3 に設計が残っている。先回りでは実装しない。
