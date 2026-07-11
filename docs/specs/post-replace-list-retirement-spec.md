# `config/post_replace_list.yml` 廃止 — 置換ルールの post_process コード化仕様書

> 作成日: 2026-07-11
> ステータス: **実装待ち**
> 対象: `config/post_replace_list.yml` の全置換ルールを Ruby コードへ移植し、YAML ファイル自体と著者拡張機能を廃止する
> 決定事項（2026-07-11 ユーザー確認済み）:
> - 著者向け「独自の拡張記法を追加する」機能（22 章コラム）は**完全廃止**（任意ファイルとしての存続はしない）
> - 実装方式は **正規表現のコード移植**（HtmlReplacer の適用エンジンを温存。Nokogiri 書き直しはしない）
> - Planned のガイド線マクロ（`@lu` 系）は**完全廃止**。後継は `explanatory-diagram-spec.md`（`.showcase` 記法・確定仕様）であり、退避ドキュメントは作らない
> 関連: `lib/vivlio_starter/cli/post_process/html_replacer.rb`, `lib/vivlio_starter/cli/post_process.rb`, `lib/vivlio_starter/cli/prism_lines.rb`, `lib/vivlio_starter/cli/common.rb`, `docs/specs/code-include-line-number-spec.md`, `docs/specs/explanatory-diagram-spec.md`, `docs/specs/PLANNED.md`

## 背景・動機

`config/post_replace_list.yml` は VFM→HTML 変換後の文字列置換ルール集で、`HtmlReplacer` が実行時に YAML を読み込んで適用している。廃止の動機:

1. **設定ではなく実装である**: ルールの大半（`:::` div 化、p/div ねじれ修正、空段落除去）はシステムの成立に不可欠で、著者が「設定」として変更してよいものではない。壊すと即ビルド成果物が崩れる。
2. **実行時 YAML パースの脆さ**: 正規表現を YAML 文字列で持つためエスケープ規約が二重（YAML＋Regexp）になり、編集事故を招く。コード化すれば Regexp リテラルとしてロード時に検証される。
3. **必須ファイル管理の簡素化**: `REQUIRED_YAML_FILES` から外れることで、`vs new` / `vs doctor` 復元 / guards 検証 / 多数のテストフィクスチャの前提が 1 ファイル分軽くなる。
4. **PLANNED「Post-processing 単体テスト整備」の実現**: ルールがコードになることで、グループ単位の単体テスト（スナップショット）が自然に書ける。

## 1. 現状の実装（調査結果・2026-07-11 時点）

### 1.1 適用フロー

- `post_process.rb` の `execute_post_process` が `load_replace_rules`（`post_process.rb:988`）で YAML をロードし、**1 ファイルにつき最大 3 回** `HtmlReplacer.process_html_file(html_file, replace_rules)` を呼ぶ:
  1. 初回適用（`post_process.rb:94`）
  2. `SectionWrapper` が変更を加えた場合のクリーンアップ（`post_process.rb:108`）
  3. 最終クリーンアップ（`post_process.rb:175`、Nokogiri 系ステップが残す空 `<p>` の除去）
- YAML 解決は `Common.post_replace_file_path`（`common.rb:871`）→ `CONFIG.files.post_replace`（既定 `post_replace_list.yml`、`common.rb:41` / `common.rb:266`）。
- `HtmlReplacer.apply_rule` はパターン文字列の内容からモードを**推定**する（`html_replacer.rb:126` `rule_mode`）:
  - `:code_aware` … `class="token` を含む → `<pre>` 内も対象（language-markdown の pre のみ退避）
  - `:text_only` … `<` を含まない → `<pre>`/`<code>`/全タグを退避しテキストノードのみ対象
  - `:tag_aware` … それ以外 → `<pre>` ブロックのみ退避

### 1.2 現役ルールの棚卸し（yml 行番号つき）

| # | yml 行 | 内容 | 現行モード | 移植先 |
|---|---|---|---|---|
| 1 | 33 | `:::{.class}` → `<div class="...">`（開始） | text_only | `CONTAINER_RULES` |
| 2 | 36,38,40 | 複数クラスの残余 `" ."` 整理 ×3 回 | tag_aware | `CONTAINER_RULES` |
| 3 | 43 | `:::` → `</div>`（終了） | text_only | `CONTAINER_RULES` |
| 4 | 46 | `<hr>` → `<hr class="pagebreak">` | tag_aware | `PAGEBREAK_RULES` |
| 5 | 52,54 | `@vspace:N[単位]` / `@vspace:N`（単位付きが先） | text_only | `SPACING_MACRO_RULES` |
| 6 | 57,60 | `@nega:N` / `@posi:N`（後方互換） | text_only | `SPACING_MACRO_RULES` |
| 7 | 63 | `@comment:...@commend` → `span.hen-comment` | text_only | `EDITOR_COMMENT_RULES` |
| 8 | 120 | `<li>▶` → `li.aokome` | tag_aware | `LIST_DECORATION_RULES` |
| 9 | 123 | `<li>❶…` → `li.akakome > span` | tag_aware | `LIST_DECORATION_RULES` |
| 10 | 126 | `<h6>` → `h6.codetitle > span`（span は Nokogiri の自動補完で閉じる） | tag_aware | `CODE_HEADING_RULES` |
| 11 | 130,133 | Prism コメント `[!]` 赤強調（`#`/`//`/`--`/`/*` と HTML コメント `&#x3C;!--`） | code_aware | **prism_lines.rb へ移設**（§3.3） |
| 12 | 136,138 | `〘` / `〙` → `<kbd>` / `</kbd>` | text_only | `KBD_RULES` |
| 13 | 141,144 | 会話 `【先生X】` / `【生徒X】` → `p.kaiwa.sensei/seito` | tag_aware | **廃止**（§3.4） |
| 14 | 147–184 | p/div/svg/image/hr のねじれ修正 ×12 ルール | tag_aware | `PARAGRAPH_CLEANUP_RULES` |
| 15 | 186,189,192 | 空段落除去 ×3（素/空白/nbsp・ゼロ幅） | tag_aware | `PARAGRAPH_CLEANUP_RULES` |
| 16 | 195,198 | 段落末 `{.aki}` / `{.aki2}` のクラス化 | tag_aware | `SPACING_CLASS_RULES` |
| — | 66–117 | 【Planned】絶対配置＋SVG ガイド線マクロ（全行コメントアウト） | — | **完全廃止**（§3.5。後継は `explanatory-diagram-spec.md` の `.showcase` 記法） |

移植後、`:code_aware` モードを使うルールは残らない（§3.3 で Nokogiri 化するため）。

### 1.3 依存箇所の全リスト

**lib（コード）**

| ファイル | 内容 |
|---|---|
| `common.rb:24` | `REQUIRED_YAML_FILES` に `config/post_replace_list.yml` を含む |
| `common.rb:41` | `POST_REPLACE_FILE = 'post_replace_list.yml'` |
| `common.rb:243,266` | `default_config_schema` の `files:` セクション（中身は `post_replace` のみ） |
| `common.rb:869-880` | `post_replace_file` / `post_replace_file_path` |
| `common.rb:952-962` | 上記の `module_function` 宣言 |
| `post_process.rb:60` | `POST_PROCESS_DESC` の説明文「book.yml の files.post_replace で指定された YAML に基づく置換処理」 |
| `post_process.rb:88,94,108,175` | `load_replace_rules` とその 3 呼び出し |
| `post_process.rb:982-1018` | `load_replace_rules` 本体 |
| `post_process/html_replacer.rb` | 適用エンジン（温存・縮小） |
| `guards/container_class_check.rb:13` | コメント「残りはすべて config/post_replace_list.yml の汎用正規表現が…」 |
| `guards/container_fence_check.rb:12` | コメント「置換される（config/post_replace_list.yml）」 |
| `guards/container_scanner.rb:21` | コメント「経路 B（post_replace_list.yml）は…」 |
| `pre_process/cross_reference_processor.rb:33-60` | `RESERVED_MACRO_IDS`（コメント更新のみ・定数存続）と `RESERVED_MACRO_POSITION_PREFIXES`＋`reserved_id?` の接頭辞判定分岐（**削除**、§3.5） |
| `doctor.rb:70,635` | `REQUIRED_YAML_FILES` 経由の復元（定数変更に自動追従、コード変更不要） |
| `guards/config_validity_check.rb:14` | 同上（自動追従） |

**config / scaffold**

- `config/post_replace_list.yml`（削除対象）
- `lib/project_scaffold/config/post_replace_list.yml`（`ruby copy_to_scaffold.rb` が config/ ディレクトリを `rm_rf`→`cp_r` するため、root 削除後の同期で自動消滅）

**stylesheets**

- `stylesheets/replace-list.css` … ヘッダコメントが yml を参照。`.kaiwa` 系ルール（30–52 行）は記法廃止に伴い削除。`.figure-guides` のコメントアウト済みブロック（78–88 行）とヘッダの言及（17 行）もガイド線マクロ廃止（§3.5）に伴い削除。ファイル名は 3 CSS（`chapter.css:20` / `preface.css:8` / `appendix.css:17`）から import されているため**変更しない**。
- `stylesheets/_README.md:16` … replace-list.css の説明行（yml 言及と `.kaiwa` / `.figure-guides` を除去）。

**contents（著者向けマニュアル）**

| ファイル | 箇所 | 対応 |
|---|---|---|
| `13-new.md:200` | 設定ファイル一覧表の `post_replace_list.yml` 行 | 行削除 |
| `22-extentions.md:693,698` | 赤コメの例文「❷ `post_replace_list.yml` を編集する」 | 例文を無害な内容に差し替え（例: 「❷ `stylesheets/custom.css` を編集する」） |
| `22-extentions.md:1089-1100` | コラム「独自の拡張記法を追加する」 | **書き換え**。「独自装飾は `:::{.myclass}` ＋ `custom.css`（`preflight.allowed_classes` で警告回避）で実現する」方向の内容へ（`post_replace_list.yml` に自作ルールを書く記述・`@mark` の例は削除） |
| `24-cross-reference.md:155-184` | 「`post_replace_list.yml` で定義されるビルド時マクロ」の節 | 「システム組み込みのビルド時マクロ」に文言変更（`@vspace` 等の完全一致予約 ID の一覧・意味は不変）。**`@lu` 系予約接頭辞の小節（173–179 行）は削除**し、184 行の衝突注意の例からも `@lu25` を除く（§3.5） |
| `61-developer.md:199` | config/ の説明 | `post_replace_list.yml` への言及を削除 |
| `61-developer.md:336` | 「2. `config/post_replace_list.yml` に基づく文字列置換（`html_replacer.rb`）」 | 「組み込み置換ルール（`replacement_rules.rb`）による文字列置換」へ |

**docs**

- `docs/specs/PLANNED.md:41-46`（会話文記法の刷新）… 「現状」注記を更新（`先生`/`生徒` ハードコード経路は**廃止済み**、`.kaiwa` CSS も削除済み、と書き換え）。
- `docs/specs/PLANNED.md:52`（`@comment` 一括除去オプション）… 「現状は post_replace_list.yml で…変換し」→「現状は組み込み置換ルールで…変換し」。`contents/23-replace-list.md` という古いファイル名参照も実在の章名に正す。
- `docs/specs/PLANNED.md:78`（品質/テスト「Post-processing 単体テスト整備」）… `_postReplaceList.json` という古い名称を実態に合わせ、本仕様の §5 テストで**完了扱い**にできる。

**test（フィクスチャとして yml を書いている箇所）**

| ファイル | 行 |
|---|---|
| `test/vivlio_starter/cli/vfm_hard_line_breaks_test.rb` | 257 |
| `test/vivlio_starter/release/idempotency_test.rb` | 64 |
| `test/vivlio_starter/cli/epub_builder_test.rb` | 311 |
| `test/vivlio_starter/cli/cover_crop_marks_bugfix_test.rb` | 425, 443, 459, 476, 493 |
| `test/vivlio_starter/cli/cover_test.rb` | 211, 451, 631 |
| `test/vivlio_starter/cli/create_commands_test.rb` | 243 |
| `test/vivlio_starter/cli/common_config_loading_test.rb` | 172 |
| `test/vivlio_starter/cli/build/epub_flavor_test.rb` | 166 |
| `test/vivlio_starter/cli/build/vivliostyle_config_writer_test.rb` | 35 |
| `test/vivlio_starter/cli/doctor/config_restore_test.rb` | 143 |
| `test/vivlio_starter/cli/markdown_transformer_test.rb` | 909-912（完全一致マクロの回帰テストは**存続**・コメントの yml 言及のみ更新）、926 付近（絶対配置マクロのテストは**削除**、§3.5）、`test_reserved_id_helper`（接頭辞グループのアサーション除去） |
| `test/vivlio_starter/cli/post_process/html_replacer_test.rb` | 全体（エンジンテストとして改修） |

上記以外にも残存がないか、実装完了時に `grep -rn "post_replace" lib test config contents docs stylesheets *.rb` で確認する（`config/index_glossary_terms.yml` の `context:` 文字列は索引辞書の抜粋であり、contents 修正後の `vs index:auto` 再実行で追従するため**手動編集しない**）。

## 2. 要求仕様

| # | 要件 |
|---|---|
| R1 | `config/post_replace_list.yml` と scaffold 同梱分を削除し、実行時に YAML 置換ルールを一切読み込まない |
| R2 | §1.2 の #1–#10, #12, #14–#16 の各ルールを、**同一の正規表現・同一の適用順・同一の保護モード**で Ruby コードとして適用する（出力 HTML のバイト同一性が原則） |
| R3 | `[!]` 赤強調（#11）は `prism_lines.rb` に移設し、従来と同じ表示結果（`codered` クラス付与＋`[!]` とその前後空白 1 つの除去、コメント記号保持）を得る |
| R4 | 会話記法（#13）は廃止し、`.kaiwa` 系 CSS も削除する（PLANNED.md:41 の将来刷新に一本化） |
| R5 | `execute_post_process` の 3 回適用（初回／SectionWrapper 後／最終クリーンアップ）の構造は変えない |
| R6 | 著者による置換ルール拡張機能は廃止し、22 章コラム等のドキュメントを整合させる |
| R7 | `REQUIRED_YAML_FILES` から除外し、`vs new` 生成物・`vs doctor` 復元対象・guards 検証対象から外す。既存プロジェクトに残る同ファイルは**無視**する（警告もエラーも出さない） |
| R8 | `book.yml` の `files.post_replace` 設定キーを撤去する（`files:` セクションは他キーが無いため丸ごと削除。`Common.reload_configuration!` 後も未知キーとして無害に無視されることを確認） |
| R9 | `@vspace`/`@nega`/`@posi`/`@comment`/`@commend` の予約 ID（`RESERVED_MACRO_IDS`）は現状のまま維持する。一方 `@lu` 系予約接頭辞（`RESERVED_MACRO_POSITION_PREFIXES`）はガイド線マクロの完全廃止（§3.5）に伴い**撤去**する |
| R10 | pdf / print_pdf / epub / kindle の 4 ターゲットがビルド完走し、生成 HTML が改修前と一致する（会話記法の消滅と `[!]` の処理タイミング差による無害な差分を除く。§6 参照） |

## 3. 実装設計

### 3.1 新規ファイル: `lib/vivlio_starter/cli/post_process/replacement_rules.rb`

組み込みルールの定義と適用ファサードを持つモジュール。

```ruby
# frozen_string_literal: true

require_relative 'html_replacer'

module VivlioStarter
  module CLI
    module PostProcessCommands
      # 旧 config/post_replace_list.yml の組み込み置換ルール。
      # 適用エンジンは HtmlReplacer（保護モード・退避機構）を共用する。
      module ReplacementRules
        module_function

        # 1 ルール。mode は旧 rule_mode の推定結果を明示化したもの:
        #   :text_only … <pre>/<code>/全タグを退避しテキストノードのみに適用
        #   :tag_aware … <pre> ブロックのみ退避して全体に適用
        Rule = Data.define(:pattern, :replacement, :mode)

        CONTAINER_RULES = [
          # :::{.class} 記法（Pandoc 拡張風）を <div class="..."> に変換（開始）
          Rule.new(/:{3,}\s*\{\.?([a-z0-9.\-_\s]+)\}/m, '<div class="$1">', :text_only),
          # 複数クラス指定で残った " ." を " " に（最大 4 クラス対応のため 3 回）
          Rule.new(/(<div class="[^"]*?) \./m, '$1 ', :tag_aware),
          Rule.new(/(<div class="[^"]*?) \./m, '$1 ', :tag_aware),
          Rule.new(/(<div class="[^"]*?) \./m, '$1 ', :tag_aware),
          # ::: ブロック終端を </div> に
          Rule.new(/:{3,}/m, '</div>', :text_only)
        ].freeze

        PAGEBREAK_RULES = [...].freeze          # yml 46 行
        SPACING_MACRO_RULES = [...].freeze      # yml 52,54,57,60 行（単位付き @vspace を先頭に置くこと）
        EDITOR_COMMENT_RULES = [...].freeze     # yml 63 行
        LIST_DECORATION_RULES = [...].freeze    # yml 120,123 行
        CODE_HEADING_RULES = [...].freeze       # yml 126 行
        KBD_RULES = [...].freeze                # yml 136,138 行
        PARAGRAPH_CLEANUP_RULES = [...].freeze  # yml 147〜192 行（順序厳守・15 ルール）
        SPACING_CLASS_RULES = [...].freeze      # yml 195,198 行

        # yml の記載順そのまま（順序変更禁止: 後段ルールは前段の結果に依存する）
        ALL = (CONTAINER_RULES + PAGEBREAK_RULES + SPACING_MACRO_RULES +
               EDITOR_COMMENT_RULES + LIST_DECORATION_RULES + CODE_HEADING_RULES +
               KBD_RULES + PARAGRAPH_CLEANUP_RULES + SPACING_CLASS_RULES).freeze

        # 組み込みルール一式を適用する（旧 process_html_file(file, yaml_rules) 相当）
        # @return [Hash] { changed: Boolean, replacements: Integer }
        def apply_builtin!(html_file) = HtmlReplacer.process_html_file(html_file, ALL)
      end
    end
  end
end
```

**移植上の厳守事項**:

- 全パターンに `/m`（`Regexp::MULTILINE`）を付ける。旧実装は `Regexp.new(str, Regexp::MULTILINE)` で全ルールを /m コンパイルしており、`{.aki}` ルールの `(?:(?!</p>).)*?` などは /m 前提で複数行段落を貪欲に扱う。
- 置換文字列の `$1`〜`$9` 記法は**そのまま維持**する（エンジン側 `replace_with_captures` が手動置換する。Ruby の `'\1'` へ書き換えない）。
- YAML → Regexp リテラルへの変換ではエスケープの剥がし忘れに注意（YAML の `\\{` は正規表現 `\{`、`"<span class=\"token…"` の `\"` は素の `"`）。移植後に**各パターンの `source` が旧 yml 文字列と一致するか**を検証するテストを書く（§5.1）。
- `mode` は §1.2 の表どおりに明示する（旧 `rule_mode` の推定結果の固定化。推定と食い違うとテキスト保護の挙動が変わり HTML が壊れる）。

### 3.2 `html_replacer.rb`（エンジンの縮小改修)

- `process_html_file(html_file, rules)` のシグネチャを `Rule` 配列前提に変更。YAML ハッシュ（`rule['f']` / `rule['r']`）対応・`Regexp.new` コンパイル・`RegexpError` rescue を撤去（パターンはリテラルなのでロード時に検証済み）。
- `rule_mode` / `CODE_AWARE_PATTERN_MARKER` / `apply_rule` の `:code_aware` 分岐（language-markdown 退避を含む）を**削除**する。`[!]` ルールの移設（§3.3）後、code_aware を使うルールは存在しない。
- `apply_rule(content, rule)` は `rule.mode` で分岐する 2 モード構成へ。`with_text_scope_protected` / `replace_with_captures` / プレースホルダ定数は不変。
- ヘッダコメント（`html_replacer.rb:3-17`）を「ReplacementRules の組み込みルールを適用するエンジン」に書き換える。

### 3.3 `[!]` 赤強調の `prism_lines.rb` 移設

`code-include-line-number-spec.md` で改修予定のファイルに、Nokogiri ベースで実装する。

- `add_prism_line_numbers`（`prism_lines.rb:63`）の `document.css('pre').each` の**前**に `highlight_alert_comments!(document)` を追加:

  ```ruby
  # Prism コメントトークンの [!] マーカーを赤強調クラスに変換する。
  # コメント記号（# / // / -- / /* / <!--）は保持し、[!] とその前後の空白 1 つを除去する。
  ALERT_COMMENT_PATTERN = %r{\A(\#|//|--|/\*|<!--)\s*\[!\]\s?}

  def highlight_alert_comments!(document)
    document.css('pre span.token.comment').each do |span|
      # 記法解説用のネストコード（language-markdown の pre 内）は対象外
      next if span.ancestors('pre').any? { |pre| pre['class'].to_s.include?('language-markdown') }

      text_node = span.children.find(&:text?)
      next unless text_node
      next unless (m = text_node.text.match(ALERT_COMMENT_PATTERN))

      text_node.content = text_node.text.sub(ALERT_COMMENT_PATTERN) { "#{m[1]} " }
      span['class'] = "#{span['class']} codered"
    end
  end
  ```

- **等価性の要点**: 旧ルールは Prism のエンティティ出力 `&#x3C;!--` を文字列マッチしていたが、Nokogiri のテキストノードではデコード済みの `<!--` になるため、パターンは素の `<!--` で書く。旧ルール 2 本（一般コメント＋HTML コメント）が 1 パターンに統合される。
- 旧実装で `[!]` は post_process の初回置換（Step 内の早段）で処理されていたが、prism_lines も同じ `execute_post_process` ループ内（`post_process.rb:155`）で実行されるため、最終 HTML は同一になる。`span` の属性付き `<span class="token comment" ...>` も `css('span.token.comment')` で同様に拾える。
- CSS `.codered.token.comment`（`code.css:179`）は不変。
- `code-include-line-number-spec.md` §3.2 の `decorate_pre_tag` 改修とは独立（同ファイルを触るが別メソッド）。実装順はどちらが先でもよい。

### 3.4 会話記法の廃止

- yml #13 の 2 ルールは移植**しない**。
- `stylesheets/replace-list.css` の `.kaiwa` / `.kaiwa::before` / `.kaiwa.sensei::before` / `.kaiwa.seito::before`（30–52 行）を削除し、ヘッダコメント（1–18 行）を「post_process の組み込み置換ルールが付与する隠れクラス」の説明に書き換え、定義クラス一覧から `.kaiwa` 系を除く。→ `ruby copy_to_scaffold.rb` で同期。
- `contents/22-extentions.md` の会話文節は既に HTML コメントアウト済み（`container_scanner.rb:50-52` が前提にしている）ため本文変更は不要。**コメントアウトブロックは残す**（guards の `comment_state` テスト前提を崩さない）。
- `docs/specs/PLANNED.md:46` の「現状」を更新（§1.3 参照）。

### 3.5 Planned ガイド線マクロ（yml 66–117 行）の完全廃止

「画像への注釈・ガイド線」という用途は `docs/specs/explanatory-diagram-spec.md`（図解注釈記法 `.showcase`＋`rect:`/`pointer:` コマンド。確定仕様・未着手、STATUS.md 参照）が後継となることが決定済み（2026-07-11 ユーザー確認）。`@lu` 系マクロは正式サポートに至らないまま廃止する。**退避ドキュメントは作らない**（yml のコメントアウト部は git 履歴で参照できる）。

- yml のコメントアウトブロック（66–117 行）はファイルごと削除（移植しない）。
- `cross_reference_processor.rb` の `RESERVED_MACRO_POSITION_PREFIXES`（46–49 行）と `reserved_id?` の接頭辞判定分岐（59 行）、および関連コメント（41–45, 54 行）を削除する。`RESERVED_MACRO_IDS`（`@vspace` 等）は存続（R9）。
- `contents/24-cross-reference.md` の予約接頭辞の小節（173–179 行）を削除し、衝突注意（184 行）から `@lu25` の例を除く。
- `stylesheets/replace-list.css` の `.figure-guides` 関連（ヘッダ 17 行・コメントアウトブロック 78–88 行）と `stylesheets/_README.md:16` の言及を削除する。
- テスト: `markdown_transformer_test.rb` の `test_replace_references_preserves_absolute_position_macros`（926 行付近）を**削除**し、`test_reserved_id_helper` から接頭辞グループ（`lu25` 等）のアサーションを除く。
- CHANGELOG の過去エントリ（309–310 行付近の予約語追加・コメントアウト化の記録）は歴史として**編集しない**。今回の Removed エントリに「後継: explanatory-diagram-spec.md」と明記する。

### 3.6 `post_process.rb` の改修

- `require_relative 'post_process/replacement_rules'` を追加。
- `load_replace_rules`（982–1018 行）を**削除**。
- `replace_rules = load_replace_rules` と 3 箇所の `HtmlReplacer.process_html_file(html_file, replace_rules)` を `ReplacementRules.apply_builtin!(html_file)` に置換（戻り値の `{changed:, replacements:}` 契約は同一なのでログ処理は不変）。
- `POST_PROCESS_DESC` の long 説明から「book.yml の files.post_replace で指定された YAML に基づく」を「組み込み置換ルールによる」に変更。
- ヘッダコメント 24 行目の「HtmlReplacer: YAML置換ルール適用」を更新。

### 3.7 `common.rb` の改修

- `REQUIRED_YAML_FILES` から `config/post_replace_list.yml` を除去（`common.rb:24`）。
- `POST_REPLACE_FILE`（41 行）、`default_files`（266 行）、`default_config_schema` の `files: default_files`（243 行）、`post_replace_file` / `post_replace_file_path`（869–880 行）、および 952–962 行の該当 `module_function` 宣言を削除。
- 削除前に `grep -rn "CONFIG&\?\.files\|\.files\b" lib test` で `files` セクションの他参照が無いことを確認する（調査時点では `post_replace_file` のみ）。
- `doctor.rb` / `guards/config_validity_check.rb` は `REQUIRED_YAML_FILES` 参照のため自動追従（コード変更不要。コメントのみ実態確認）。

### 3.8 ドキュメント・コメント整備

§1.3 の contents / docs / stylesheets / guards コメントを一括更新する。contents を触った後は `ruby copy_to_scaffold.rb` で scaffold 同期（config/ の削除も同時に同期される）。索引辞書（`index_glossary_terms.yml`）は `vs index:auto` → 差分確認 → apply の通常フローに任せる。

### 3.9 変更しないもの（スコープ外）

- `TerminalBlockConverter` 以降の post_process 実行順・各 Nokogiri ステップ。
- `pre_process` の経路 A（`MarkdownTransformer.convert_container_blocks` の 6 クラス）と guards の検出ロジック本体。
- `.aki`/`.aki2`・`kbd`・`hr.pagebreak`・`.hen-comment`・`li.aokome`/`li.akakome`・`.codetitle` の各 CSS。
- `@comment` 一括除去オプション（PLANNED 記載の将来機能）。
- 旧プロジェクトに残る `config/post_replace_list.yml` の掃除支援（無視するのみ）。

## 4. エッジケースと期待動作

| ケース | 期待動作 |
|---|---|
| コードブロック内の `:::` / `@vspace` / `〘〙`（記法解説の例文） | 従来どおり置換されない（`<pre>` 退避・text_only 保護が Rule.mode で同一に働く） |
| 属性値内のマクロ文字列（`data-heading="@vspace:2"` 等） | text_only 保護により置換されない（旧挙動と同一） |
| `:::{.a .b .c .d}`（4 クラス） | `" ."` 整理 3 回で全て空白化（旧挙動と同一） |
| `【先生A】こんにちは` を含む原稿 | **変換されず素のテキストとして出力される**（記法廃止。現行同梱原稿には非コメントの使用箇所なし） |
| `language-markdown` の pre 内にネストされた `# [!] 注意` の例 | 赤強調されない（§3.3 の ancestors 判定） |
| C 言語 `/*← [!] */` / SQL `-- [!]` / HTML `<!-- [!] -->` | 従来どおり `codered` 付与＋`[!]` 除去 |
| 旧プロジェクト（yml が残存）で `vs build` | yml は読まれず無視。エラー・警告なし |
| 原稿中に `@lu25,15@20,30` などのガイド線マクロ記述が残っている | 予約が外れるため「未定義のラベルID」警告の対象になる（現行同梱原稿・サンプルに使用箇所なし。警告文言が具体的修正案を伴う既存方針のまま） |
| `vs doctor` を旧プロジェクトで実行 | yml は必須ファイルではないため欠落チェック・復元の対象外 |
| `vs new mybook` | 生成物に `config/post_replace_list.yml` が含まれない |

## 5. テスト計画

### 5.1 新設: `test/vivlio_starter/cli/post_process/replacement_rules_test.rb`

グループごとのスナップショット単体テスト（PLANNED「Post-processing 単体テスト整備」を兼ねる）:

- コンテナ: `:::{.column}` 開閉 → `<div class="column">`…`</div>`、複数クラス `{.a .b .c}`、`<pre>` 内非置換。
- マクロ: `@vspace:1.5lh`（単位付き優先）／`@vspace:10`（mm 補完）／`@vspace:-2lh`／`@nega:5`／`@posi:5`／`@comment:…@commend`。
- リスト装飾: `<li>▶…` → `li.aokome`、`<li>❶…` → `li.akakome > span`、`⓴` 境界。
- h6: `<h6 id="x">` → `<h6 id="x" class="codetitle"><span>`。
- kbd: `〘Ctrl〙` → `<kbd>Ctrl</kbd>`、`<pre>` 内の全角マーカー非置換（既存 `html_replacer_test.rb:80` の意図を継承）。
- クリーンアップ: `<p><div class="x">…</div></p>` ねじれ、`<p></p>`／`<p>&nbsp;</p>`／ゼロ幅文字段落の除去、`{.aki}`/`{.aki2}`。
- **会話記法が変換されないこと**: `<p>【先生A】…` が原文のまま。
- **ALL の順序検証**: `ALL` の並びが本仕様 §1.2 の順（yml 順）と一致すること（グループ連結順の回帰防止）。

### 5.2 改修: `test/vivlio_starter/cli/post_process/html_replacer_test.rb`

- 各テストのルール指定を YAML ハッシュから `ReplacementRules::Rule` に変更（モードは旧推定結果と同値を明示）。
- `test_prism_token_targeting_rule_still_reaches_inside_pre`（120 行）と `rule_mode` 分類テスト（206 行）は code_aware 削除に伴い**撤去**し、意図（pre 内のトークンに届くこと）は §5.3 の prism_lines テストへ移す。

### 5.3 prism_lines の `[!]` テスト

`test/vivlio_starter/cli/prism_lines_test.rb`（無ければ新設。`code-include-line-number-spec.md` §5.2 と同居可）:

- `# [!] 注意` → `span.token.comment.codered`＋テキスト `# 注意`。
- `// [!]` / `-- [!]` / `/* [!]` / `<!-- [!]` の各記号で記号保持・`[!]` 除去。
- `[!]` を含まないコメントは不変・`codered` 非付与。
- `pre.language-markdown` 内のコメントは非対象。
- 行番号付与（`line-numbers-rows`）と同時実行しても互いに干渉しないこと。

### 5.4 既存テストのフィクスチャ掃除

§1.3 の表のとおり、`post_replace_list.yml` を書き込む setup 行を削除。`doctor/config_restore_test.rb` と `create_commands_test.rb` は「復元対象・生成物に含まれない」ことの検証へ期待値を反転。`ensure_required_yaml_files!` のエラーメッセージを検証するテストがあればファイル列挙を 3 件に更新。

### 5.5 統合確認（手動）

1. 改修前に `vs build --no-clean` を実行し `.cache/vs/build/html/*.html` を退避。改修後に再ビルドして diff。**期待差分ゼロ**（同梱原稿に会話記法の非コメント使用が無いため。`[!]` 例は 22 章にあり、等価出力を確認）。
2. `rake test` / `rake test:standard` / `bundle exec rubocop` 通過。
3. pdf / print_pdf / epub / kindle の 4 ターゲット完走（`rake test:layout` を含む）。
4. 別ディレクトリで `vs new tmpbook` → 生成物に yml が無いこと、`vs doctor` が正常なこと。

## 6. 受け入れ条件

- [ ] R1〜R10 をすべて満たす。
- [ ] `grep -rn "post_replace" lib test config contents stylesheets *.rb` のヒットが 0 件（`docs/`（本仕様書・archives）と `index_glossary_terms.yml` の自動生成コンテキストを除く）。
- [ ] §5 の自動テストが全件パスし、既存テストにリグレッションがない。
- [ ] §5.5-1 の HTML diff が空（または差分の全件が本仕様で説明可能）。
- [ ] `ruby copy_to_scaffold.rb` 実行済みで、scaffold から yml が消え、CSS/contents 変更が同期されている。
- [ ] `docs/specs/PLANNED.md` の 3 箇所（会話記法・@comment・Post-processing テスト整備）が更新されている。
- [ ] `CHANGELOG.md` の unreleased に Removed（yml・著者拡張機能・会話記法）と Changed（ルールのコード化・`[!]` の prism_lines 移設）を記載。

### 将来拡張（本タスクではやらない）

- パス 2・3（SectionWrapper 後／最終）の適用を `PARAGRAPH_CLEANUP_RULES` のみに絞る最適化（現在は全ルール再適用。冪等性は h6 ルールの再マッチを Nokogiri の重複属性破棄が偶然吸収している構図のため、絞り込みはむしろ健全化になるが、挙動同一性を優先し本タスクでは見送る）。
- 会話文記法の刷新（`config/characters.yml` 化、PLANNED.md:41）。
- 図解注釈記法（`explanatory-diagram-spec.md`、ガイド線マクロの後継）。Phase 0（showcase_svg_builder コア）から着手予定の別タスク。
