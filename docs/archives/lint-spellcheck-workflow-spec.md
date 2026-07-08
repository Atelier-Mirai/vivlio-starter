# vs lint（textlint / spellcheck）ワークフロー改善 仕様

> 既存のスペルチェック基盤の初版仕様は [`docs/archives/spellcheck_spec.md`](../archives/spellcheck_spec.md)（2024-11-30）を参照。
> 本書はその後の運用で見えた課題への改善を、第1段（実装済み・2026-06-29）／第2段（計画）に分けて記す。
> ※実装が先行し、本仕様書は後追いで起こした（フォーク後の読者向けに意図を残す目的）。

## 0. 背景・経緯

`vs lint` は textlint（日本語校正・prh 表記揺れ）と、自前の英語スペルチェックを並走させる。
半年以上の運用で次の課題が顕在化した。

1. **辞書が読めずに技術用語が大量誤検知**：インストール済み gem で `Kotlin` / `AWS` / `Azure` などが「綴り誤り」と報告された。
2. **辞書登録の手間**：プロジェクトごとに `book.yml` の `extra_words` を書くのは、専門用語が多い著者（例：マイコン技術書）には負担。
3. **出力が冗長**：同じ指摘が行ごとに大量に並び、読みにくい・「うるさい」。
4. **lint のテストが未実行**：`test_*.rb` 命名で rake の `*_test.rb` パターンに一致せず CI を素通り（上記 1 の回帰を取りこぼした）。
5. **prh の個別ルール制御が不便**：`ja-space-around-code` 等の textlint ルールは on/off 一発だが、prh は 1 ファイルに多数のルールが同居し、「このルールだけ無効化」がしづらい。

---

## 1. 用語・辞書の階層

スペルチェックの語彙（word_map）は、次の発生源をマージして構築する（`DictManager#build_word_map`）。

| 発生源 | 置き場所 | 主体 | 備考 |
| --- | --- | --- | --- |
| 標準辞書（cspell 由来） | `config/spellcheck_dictionaries/*.txt` | 同梱 | 言語・ツール・略語など 50+ ファイル |
| プロジェクト管理辞書 | `config/spellcheck_dictionaries/vivlio-starter-terms.txt` | 同梱 | 標準辞書に無い本ツール由来の語（textlint / yml / SCOWL 等） |
| 索引用語 | `config/index_glossary_terms.yml` | ビルド生成 | 英字を含む term を取り込む |
| `extra_dictionaries` | cspell からオンデマンド DL → `.cache/` | `book.yml` | プロジェクト固有の追加辞書 |
| `extra_words` | `book.yml` | プロジェクト | プロジェクト固有語 |
| **ユーザー辞書** | `config/user_words.txt` | 利用者 | `--register` の追記先。プロジェクト固有（別の本へはコピーして持っていく） |

`ignore_words`（`book.yml`）は word_map とは別に、検出後に除外する語（誤検知の握りつぶし）。

### 辞書ディレクトリの解決（同梱物のパッケージング）

`DictManager#bundled_dir` は **プロジェクト直下 `config/spellcheck_dictionaries`（CWD 相対）を優先し、無ければ gem 同梱の `lib/project_scaffold/config/spellcheck_dictionaries` へフォールバック**する。

- 理由：gemspec の `files` は `{bin,lib}/**/*` のみで、**リポジトリ直下の `config/` は gem に同梱されない**。旧実装は `<gem>/config/...` を指していたため、インストール済み gem で辞書 0 件になり技術用語が誤検知されていた（課題 0-1）。
- `vs new` が scaffold を各プロジェクトの `config/` へ複製するため、CWD 相対なら開発リポジトリでもユーザープロジェクトでも実在する。`.textlintrc.yml` を CWD 相対で参照するのと一貫。

---

## 2. 第1段（実装済み・2026-06-29）

### 2.1 辞書まわりの修正

- `bundled_dir` をプロジェクト優先・同梱フォールバックへ（上記 §1）。
- `CACHE_DIR` を CWD 相対 `.cache/spellcheck-dictionaries` に（インストール済み gem 配下へ書き込まない）。
- 標準辞書に無い本ツール用語を `vivlio-starter-terms.txt` に集約（標準辞書を直接編集しないので将来の再同期で消えない）。

### 2.2 ユーザー辞書

- パス：**プロジェクト直下 `config/user_words.txt`**（CWD 相対）。隠しフォルダ（`~/.config`）でなく見つけやすく、別の本でも使いたければこのファイルをコピーすればよい。
- `DictManager#user_dict_path` は**メソッド**（定数にすると require 時に固定され、テストで `chdir` しても追従しないため）。
- `build_word_map` の最後にこの辞書も読み込む。
- 形式：1 行 1 語、`#` 始まりはコメント。大文字小文字は無視（word_map は downcase キー）。
- 当初は `~/.config/vivlio-starter/spellcheck/user-words.txt`（XDG・全プロジェクト共通）だったが、深い／隠しフォルダで見つけづらく、`config/` 配下の他設定（snake_case の yml）との一貫性も欠くため、`config/user_words.txt` へ変更した。

### 2.3 `--register`（未知語の一括登録）

- `DictManager#register_user_words(words)`：既存語＋新規語を**大文字小文字無視で一意化し、辞書順に並べ替えてファイルを書き直す**（編集過程の重複・未整列も毎回整える）。追加した語を返す。
- `vs lint --register`：スペルチェックで未知だった語をまとめて `config/user_words.txt` へ登録する（`LintRunner#register_unknown_words`）。
- `--register` は**スペルチェック専用の操作**なので、暗黙に spellcheck 単独で動く（textlint は実行しない。`--spellcheck-only` の併記は不要。"only なのに register" の違和感を避ける）。
- 登録が目的のため、未知語があっても**終了コード 0**（次回 `vs lint` で消える）。
- 想定ワークフロー：`vs lint --register` で「ぐだぐだ言われた語」を一括登録 → 内容を確認して不要な語を削れば、以後そのプロジェクトで認識される。

### 2.4 実行範囲オプション

- `--spellcheck-only`：スペルチェックのみ。textlint 関連の事前チェック（`ensure_textlint_available!` 等）をスキップするため、**textlint 未導入でも動く**。
- `--textlint-only`：日本語校正のみ。
- `--register`：上記のとおり spellcheck 単独（`spellcheck_only?` が true を返す）。
- `LintRunner#call` を `run_textlint` / `run_spellcheck` に分割し、`spellcheck_only?` / `textlint_only?` で分岐。
- **`--config` / `--format` オプションは廃止**（パス切替は `.textlintrc.yml` のリネームで足り、出力は集約で十分なため）。textlint 設定ファイルのパスは `book.yml` の `lint.config` で指定する。

### 2.5 スペルチェック出力の集約

- `SpellChecker.print_errors` / `aggregate`：同じ語の指摘を 1 行へ集約し、出現行と件数を**出現数の多い順**で表示（出現行は最大 10 件、超過は `…`）。

```
📄 contents/31-lint.md  (spellcheck)
    3件  textlint => textline   行: 4, 302, 304
    2件  yml                    行: 383, 401
```

### 2.6 テストの実行漏れ修正

- `test/vivlio_starter/cli/lint/test_*.rb` 3 ファイルを `*_test.rb` へ改名し、rake の対象に組み込み（課題 0-4）。
- 追加した回帰テスト：辞書フォールバック、プロジェクト管理辞書、ユーザー辞書の登録・ロード、出力集約、`extra_words` の end-to-end 抑制、`ignore_words` の抑制（既存）。

---

## 3. 第2段

### 3.1 textlint 出力の集約（実装済み・2026-06-29）

- `textlint --format json` で取得し、**[メッセージ先頭行, ルール] 単位で集約**して表示する（`TextlintFormatter.aggregate_json`）。スペルチェック側（§2.5）と体裁を揃えた。
- 出力（`📄 ファイル (textlint)` ＋ `N件 [ルール] 指摘` ＋ `行: …`、件数降順）：

  ```
  📄 contents/31-lint.md  (textlint)
     43件  [ja-space-between-half-and-full-width] 原則として、全角文字と半角文字の間にスペースを入れません。
           行: 4, 10, 13, 20, 26, 31, 70, 84, 117, 157, …
      8件  [prh] 以下の => 次の
           行: 84, 122, 138, 162, 256, 304, 447, 460
  ```

- **出力は常に集約**（`textlint --format json` を内部取得）。当初は `book.yml lint.format` で aggregate/stylish 等を切り替え、stylish は `TextlintFormatter::Reformatter` で再整形していたが、実用上 aggregate 一択で十分なため、**`lint.format` と切替機構（`format_option` / native 経路 / `Reformatter` / `reformat_output` / `translate_output`）を撤去**して簡素化した（JSON 解釈に失敗した場合のみ生出力へフォールバック）。`--config` / `--format` の CLI オプションも廃止済み（§2.4）。
- textlint は vs-lint コメント変換後の一時ファイルを検査するため、出力の一時パスは元ファイル名へ戻す（temp→original マップ）。
- 受け入れ（達成）：`ja-space-around-code` などが「ルール名＋出現行＋件数」の 1 行に畳まれる。

### 3.2 ルールの個別無効化（実装済み・2026-06-29）

prh は複数の辞書ファイル（`textlint_dictionaries/*.yml` ＋ `textlint_prh.yml`）に多様な形式で同居し、設定ファイル側でのフィルタは脆い。そこで **集約段（json）で該当メッセージを落とす出力フィルタ方式**を採った（どの辞書由来でも・形式非依存）。`book.yml` で次の 2 つを指定する。

- `lint.disabled_rules: [arabic-kanji-numbers, …]` — ルール ID（集約表示で `[ ]` に出る名前）で**丸ごと無効化**。
- `lint.disabled_terms: [次の, とおり, …]` — `"X => Y"` 形式（prh / arabic-kanji-numbers / spellcheck-tech-word 等）の**指摘先頭行に含まれる語**で無効化（「お節介」ルールの個別無効化）。

実装：`TextlintFormatter.aggregate_json(..., disabled_rules:, disabled_terms:)` が集約前に `disabled_message?` で除外。無効化で除外した分は問題数・終了コードに数えない（残り 0 なら成功）。

#### ルール衝突・誤検出の扱い（集約で可視化された例）

- **衝突**：`arabic-kanji-numbers`（一つ→1つ）と `prh`（一つ→ひとつ）が矛盾。→ どちらかを `disabled_rules` で切る（著者の方針）。
- **誤検出**：`spellcheck-tech-word`（対処方→対処法）が「対処方法」の部分一致で誤発火。→ `disabled_terms` でも消せるが、textlint の **allowlist（`config/textlint_allowlist.yml`）に「対処方法」を登録**するのが正攻法（textlint が報告自体しなくなる）。

#### 文体の好みを設定可能に（実装済み・2026-06-29）

- **一文の最大文字数**：`book.yml` の `lint.sentence_length_max`（例 80 / 120。未指定なら既定 100）。指定時は、既定 textlintrc に `rules.preset-ja-technical-writing.sentence-length.max` を上書きした**一時設定を `config/` 直下へ生成**して textlint へ渡す（prh.rulePaths 等の相対パスが壊れないよう元設定と同じディレクトリに書く。後始末は `run_textlint` の ensure）。
- **末尾長音の文体**：`book.yml` の `lint.trim_long_vowel: true`。「サーバ／パラメータ／フィルタ」など**末尾の長音を省く技術文体**を選ぶ場合に、`"X => Xー"`（末尾に長音記号を足すだけ）の指摘を集約段で抑止する（`TextlintFormatter.long_vowel_addition?`）。出力フィルタ方式なので prh 辞書の所在に依存しない。
- **和欧間スペースの許容**：`book.yml` の `lint.allow_space_around_code: true`（例: `` `vs import` コマンド `` のようにインラインコードと和文の間にスペースを入れる）/ `lint.allow_space_between_ja_en: true`（全角と半角の間のスペース）。技術書で一般的なこのスタイルを残したいとき、それぞれ `preset-ja-spacing.ja-space-around-code` / `ja-space-between-half-and-full-width` を**実行時 textlintrc で false に**する（§3.2 の sentence_length_max と同じ生成機構）。
  - これらは**出力フィルタ（disabled_rules）ではなく設定レベルで無効化**する点が重要：disabled_rules は警告を隠すだけで `vs lint --fix` がスペースを削除してしまう（隠したのに直る不整合）。スペースは残したい意図的スタイルなので、ルール自体を切る。

#### 出現ごとに値が変わるルールの集約（§3.1 の補足・実装済み）

`sentence-length` のようにメッセージへ行番号・文字数が埋まるルールは、そのままだと 1 件ずつになる。`TextlintFormatter::RULE_SUMMARIES` で要約ラベル（例「一文が長すぎます（最大文長を超過）」）に置換して 1 つに畳む。意味のある数値（`一つ => 1つ` の 1 など）は保つため、数字の一律マスクはしない。

- 受け入れ（達成）：著者が「このお節介ルール／表記揺れだけ切る」を yml 直接編集なしに `book.yml` で設定できる。

### 3.3 preflight との関係（実装済み・2026-06-29）

- `vs preflight` は構造チェック（Guards）＋外部 URL 検証のみで、textlint/spellcheck は**含めない**（誤検知・件数が多く、preflight は「ビルド可能な構造か」を高速に見るため）。
- 代わりに preflight サマリー末尾へ誘導文を 1 行追加した（`print_preflight_summary`）：

  ```
  ✅ Preflight 完了: 良好な状態です
     文章校正（表記揺れ・スペル）は vs lint で行えます。
  ```

---

## 4. 関連ファイル

| 役割 | パス |
| --- | --- |
| lint ランナー（textlint 実行・spellcheck 統合・summary） | `lib/vivlio_starter/cli/lint.rb` |
| Samovar コマンド（オプション定義） | `lib/vivlio_starter/cli/samovar/lint_command.rb` |
| 辞書ロード・ユーザー辞書・登録 | `lib/vivlio_starter/cli/lint/dict_manager.rb` |
| スペルチェック本体・集約出力 | `lib/vivlio_starter/cli/lint/spell_checker.rb` |
| トークナイザ（行内ディレクティブ・コード除外） | `lib/vivlio_starter/cli/lint/tokenizer.rb` |
| textlint 出力整形 | `lib/vivlio_starter/cli/textlint_formatter.rb` |
| textlint 設定 | `config/.textlintrc.yml` / `config/textlint_allowlist.yml` / `config/textlint_prh.yml` |
| スペル辞書 | `config/spellcheck_dictionaries/*.txt`（`vivlio-starter-terms.txt` 含む） |
| テスト | `test/vivlio_starter/cli/lint/*_test.rb` |

---

## 5. 受け入れ条件（全体）

- インストール済み gem の `vs lint` で標準的な技術用語が誤検知されない。
- `vs lint --spellcheck-only --register` で未知語をユーザー辞書へ一括登録でき、再実行で消える。
- ユーザー辞書は全プロジェクト共通で効く。
- スペルチェック・textlint とも、同種の指摘が集約されて表示される（§2.5・§3.1）。
- prh の個別ルールを設定で無効化できる（§3.2）。
- lint のテストが rake で実行され、上記が回帰テストで守られる。

---

## 6. 決定事項 / 残論点

- 決定：辞書は「プロジェクト config/ 優先・gem 同梱フォールバック」。ユーザー辞書は **`config/user_words.txt`**（プロジェクト直下・snake_case・辞書順／一意化）。`--register` はスペルチェック専用で、ユーザー辞書へ登録する。`--config` / `--format` オプションは廃止し、出力は集約のみ。
- 残論点：prh 無効化を語マッチでなくルール＋語の組で指定したいケース（同一語が複数ルールに跨る場合の最終調整）。`book.yml` の `lint.config` を残すか（パス切替は基本リネームで足りる）。
