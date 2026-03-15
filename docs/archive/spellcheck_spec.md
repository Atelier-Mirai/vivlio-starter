# vivlio-starter スペルチェック機能仕様書

## 1. 概要

`vs lint` コマンドに英語スペルチェック機能を追加する。
既存の日本語校正機能（textlint / prh）と並行して動作し、原稿中の英単語のスペルミスを検出・候補提示する。

---

## 2. コマンドインターフェース

```bash
vs lint                        # 日本語校正 + 英語スペルチェック（両方実行）
```

既存の `vs lint` オプション（`--config`、`--format`、`--fix`、章番号指定など）はすべてそのまま利用できる。
スペルチェックに固有のオプションは `book.yml` の `spellcheck` セクションで制御する（→ [4.7節](#47-bookyml-設定例)）。

---

## 3. 検出対象

Markdown原稿（`contents/` 配下の `*.md`）に含まれる英単語を対象とする。
コードブロック（` ``` `〜` ``` `）内は原則チェック対象外とする（`book.yml` の `check_code_blocks: true` で有効化可能）。

### 出力例

```
📄 contents/chapter01.md
   23  bandle => bundle
        綴りが誤っている可能性があります (spellcheck)
   47  got => git
        綴りが誤っている可能性があります (spellcheck)

📄 contents/chapter03.md
   12  yestoday => yesterday
        綴りが誤っている可能性があります (spellcheck)
```

---

## 4. 辞書構成

### 4.1 辞書の優先順位（マージ順）

| 優先度 | 辞書ソース | 説明 |
|--------|-----------|------|
| 1（最低） | SCOWL words.10 + words.20 | 一般英単語（約12,000語） |
| 2 | cspell技術用語辞書（gem同梱） | 主要言語の技術用語 |
| 3 | `.cache/spellcheck-dictionaries/` | オンデマンド取得辞書 |
| 4 | `index_glossary_terms.yml` | 登録済み索引語 |
| 5（最高） | `book.yml` の `extra_words` | プロジェクト固有語 |

後から読み込んだ辞書の表記（大文字小文字）が優先される。
例：`javascript`（一般語）→ `JavaScript`（技術用語辞書）で上書き。

### 4.2 gem同梱辞書

ライセンス条件：**MITライセンスのもののみ同梱**する。

**一般英単語（SCOWL）**
- `english-words-10`（約4,400語）
- `english-words-20`（約7,900語）
- ライセンス：BSD互換

**技術用語（cspell-dicts より MITのみ選定）**

```
aws                   bash-words            basic
cobol                 coding-compound-terms computing-acronyms
cpp                   csharp                css
django                docker                dotnet
fonts                 fortran               git
go                    html                  java-additional-terms
java-terms            javascript            kotlin
latex                 networkingTerms       node
npm                   objective-c           php
placeholder-words     python-common         ruby
rust                  scala                 smalltalk
software-tools        softwareTerms         sql-common-terms
sql                   swift                 tsql
webServices
```

これらは `config/spellcheck_dictionaries/` に配備済みである。

### 4.3 オンデマンド辞書

`book.yml` の `extra_dictionaries` に記載された辞書を初回実行時に取得し、
プロジェクトルート直下の `.cache/spellcheck-dictionaries/` にキャッシュする。
2回目以降はキャッシュを利用する。

取得元（`dict/` を優先し、存在しなければ `src/` も探索する）：
```
https://raw.githubusercontent.com/streetsidesoftware/cspell-dicts/main/dictionaries/<name>/dict/<name>.txt
https://raw.githubusercontent.com/streetsidesoftware/cspell-dicts/main/dictionaries/<name>/src/<name>.txt
```

### 4.4 辞書ファイルの書式

辞書ファイルはテキスト形式（1行1エントリ）で、以下の規則に従う。

```text
# cspell-tools: keep-case no-split

*Auth*
*Auto*
word/SM
!word
```

- 空行は読み飛ばす
- `#` で始まる行はコメントとして読み飛ばす
- 行の途中で `#` が現れた場合、以降はコメントとして読み飛ばす
- `word/SM` のような Hunspell フラグ（`/` 以降）は除去する
- `*Auth*`、`!word`、`$word` のような記号プレフィックス／サフィックスは除去する
- アポストロフィ付き表記（`abbreviation's` など）はアポストロフィを除去して登録する

### 4.5 normalize の仕様

```ruby
def normalize(line)
  line = line.strip

  # 空行・コメント行をスキップ
  return nil if line.empty? || line.start_with?('#')

  # 行中コメントを除去
  line = line.split('#').first.strip

  # Hunspellフラグを除去（word/SM → word）
  line = line.split('/').first.strip

  # 記号を除去（*Auth* → Auth、!word → word、abbreviation's → abbreviations）
  line = line.gsub(/[^a-zA-Z0-9\-]/, '').strip

  return nil if line.empty?
  line
end
```

normalize の変換例：

| 辞書の記載           | normalize 後    |
|----------------------|-----------------|
| `*Auth*`             | `Auth`          |
| `*Auto*`             | `Auto`          |
| `word/SM`            | `word`          |
| `!word/SM`           | `word`          |
| `!word-SM`           | `word-SM`       |
| `$word`              | `word`          |
| `abbreviation's`     | `abbreviations` |
| `# comment`          | スキップ        |
| `word # comment`     | `word`          |
| （空行）             | スキップ        |

### 4.6 ハイフンを含む複合語の登録

`keep-case`、`no-split` のような複合語にはハイフンが含まれる。
typoパターンは2種類あるため、辞書登録時にハイフンあり・なしの両方を登録する。

- **ハイフンなしで書いてしまう**：`nosplit` → `no-split`
- **ハイフンありだが綴りが違う**：`no-sprit` → `no-split`

```ruby
def load_into_word_map(path, word_map)
  File.foreach(path) do |line|
    word = normalize(line)
    next unless word

    # ハイフンありで登録
    word_map[word.downcase] = word

    # ハイフンなしでも登録（nosplit → no-split と提示できる）
    if word.include?('-')
      no_hyphen = word.gsub('-', '').downcase
      word_map[no_hyphen] ||= word  # 既登録語を上書きしない
    end
  end
end
```

これにより：

| 入力       | `word_map` の状態          | 表示                   |
|------------|----------------------------|------------------------|
| `nosplit`  | `nosplit => no-split`      | `nosplit => no-split`  |
| `no-sprit` | Levenshtein距離1で候補提示 | `no-sprit => no-split` |
| `nosprit`  | Levenshtein距離2で候補提示 | `nosprit => no-split`  |

### 4.7 book.yml 設定例

```yaml
spellcheck:
  extra_dictionaries:      # オンデマンドダウンロード辞書
    - ada
    - elixir
  extra_words:             # プロジェクト固有語（ダウンロード不要）
    - vivliostyle
    - vivlio-starter
    - MyProductName
  ignore_words:            # 誤検知を抑制したい単語
    - htmx                 # JavaScriptを書かずにAJAX的なことをHTMLだけで実現するライブラリ
    - MSSAP                # My Special Super Awesome Project の略
  check_code_blocks: false # コードブロック内をチェックするか（デフォルト: false）
```

---

## 5. スペルチェックエンジン

### 5.1 基本方針

`did_you_mean` のLevenshtein距離ロジックを採用し、スペルミスに対して候補語を提示する。

```ruby
require 'did_you_mean'

def suggest(word, dictionary)
  dictionary
    .min_by { |w| DidYouMean::Levenshtein.distance(word.downcase, w.downcase) }
end
```

### 5.2 処理フロー

```
原稿ファイル（.md）
  ↓
英単語トークンの抽出（コードブロック除外）
  ↓
各単語を word_map（downcase）で検索
  ↓
  ├─ ヒット → 正常（スルー）
  └─ ミス  → Levenshtein距離で候補語を検索
               ↓
             距離が閾値以内 → "Did you mean: xxx?" を表示
             距離が閾値超  → "unknown word" として報告
```

### 5.3 word_map の構造

```ruby
# 検索用（小文字統一）と表示用（元表記）を分けて保持
word_map = {}  # { "javascript" => "JavaScript", "yesterday" => "yesterday", ... }
```

### 5.4 候補提示の閾値

| 単語長 | 許容Levenshtein距離 |
|--------|-------------------|
| 1〜4文字 | 1 |
| 5〜8文字 | 2 |
| 9文字以上 | 3 |

---

## 6. スペルチェックの抑制（ignore）

著者が意図的に誤表記を記述する場合（「`bandle install` ではなく `bundle install` と書きます」など初心者向けの説明）に、
スペルチェックの警告を抑制する手段を2つ提供する。

### 6.1 インラインコメントによる1行単位の抑制

原稿の行末に `<!-- spellcheck:ignore -->` を付与することで、その行のスペルチェックをスキップする。

```markdown
`bandle install` ではなく、`bundle install` と入力してください。 <!-- spellcheck:ignore -->
```

Markdownのコメント記法を利用するため、生成されるHTMLには出力されない。

### 6.2 book.yml による単語単位の全体抑制

プロジェクト全体を通じて特定の単語を常に無視したい場合は `book.yml` の `ignore_words` に追加する。
造語・製品固有の略語・意図的な誤表記サンプルなどに適している。

```yaml
spellcheck:
  ignore_words:
    - bandle          # 誤表記サンプルとして原稿中で繰り返し使用
    - vivliostyle
    - vivlio-starter
```

### 6.3 使い分けの指針

| ケース | 推奨手段 |
|--------|---------|
| 1箇所だけ誤表記サンプルを書く | インラインコメント `<!-- spellcheck:ignore -->` |
| 同じ誤表記サンプルが複数章にわたる | `book.yml` の `ignore_words` |
| プロジェクト固有の造語・製品名 | `book.yml` の `extra_words`（辞書に登録） |
| コードブロック内の記述 | 対象外（デフォルトでチェックしない） |

### 6.4 実装上の処理

```ruby
# インラインコメントの検出
INLINE_IGNORE_MD  = /<!--\s*spellcheck:ignore\s*-->/
INLINE_IGNORE_RE  = /#@#\s*spellcheck:ignore/

def check_line(line, line_no, ignore_words)
  return if line.match?(INLINE_IGNORE_MD) || line.match?(INLINE_IGNORE_RE)

  tokens = tokenize(line)
  tokens.each do |word|
    next if ignore_words.include?(word.downcase)
    check_word(word, line_no)
  end
end
```

### 6.5 利用者作成辞書の追加

利用者は `config/spellcheck_dictionaries/` に自身の作成した辞書ファイルを置くことで、珍しい言語や専門用語等の綴り誤りを検出可能にできる。

---

## 7. prhとの連携

prhによる表記ゆれ校正は既存機能として維持する。
スペルチェックはprhの**後段**で実行し、prh修正済みテキストに対してチェックをかける。
prhルールで定義済みの正規表現パターンにマッチする語はスペルチェックの対象外とする。

---

## 8. ディレクトリ構成

```
vivlio-starter/
  config/
    spellcheck_dictionaries/                        # gem同梱辞書（MITのみ）
      aws.txt
      bash-words.txt
      basic.txt
      cobol.txt
      coding-compound-terms.txt
      computing-acronyms.txt
      cpp.txt
      csharp.txt
      css.txt
      django.txt
      docker.txt
      dotnet.txt
      english-words-10.txt
      english-words-20.txt
      fonts.txt
      fortran.txt
      git.txt
      go.txt
      html.txt
      java-additional-terms.txt
      java-terms.txt
      javascript.txt
      kotlin.txt
      latex.txt
      networkingTerms.txt
      node.txt
      npm.txt
      objective-c.txt
      php.txt
      placeholder-words.txt
      python-common.txt
      ruby.txt
      rust.txt
      scala.txt
      smalltalk.txt
      software-tools.txt
      softwareTerms.txt
      sql-common-terms.txt
      sql.txt
      swift.txt
      tsql.txt
      webServices.txt
  lib/
    vivlio/starter/cli/
      lint.rb                   # lint コマンド本体（既存）
      lint/
        dict_manager.rb         # 辞書ロード・キャッシュ管理
        spell_checker.rb        # スペルチェック本体
        tokenizer.rb            # 原稿からの英単語抽出
```

---

### 8.1 辞書の取得フロー

`extra_dictionaries` に `"ada"` と指定された場合の解決順：

1. プロジェクトローカル: `config/spellcheck_dictionaries/ada.txt` を探す
2. キャッシュ:          `.cache/spellcheck-dictionaries/ada.txt` を探す
3. オンデマンド取得:    cspell-dicts からダウンロード → キャッシュに保存
   - `dict/ada.txt` が存在すれば採用して終了
   - 存在しなければ `src/ada.txt` も探索する
4. 見つからない場合:    警告を出して続行

---

## 9. 出力例

```
$ vs lint
📄 contents/chapter01.md
   23  bandle => bundle
        綴りが誤っている可能性があります (spellcheck)
   47  got => git
        綴りが誤っている可能性があります (spellcheck)

📄 contents/chapter03.md
   12  yestoday => yesterday
        綴りが誤っている可能性があります (spellcheck)
```

---

## 10. DictManager 仕様

```ruby
module Vivlio
  module Starter
    module CLI
      module Lint
        class DictManager
          BUNDLED_DIR   = File.expand_path("../../../config/spellcheck_dictionaries", __dir__)
          CACHE_DIR     = File.expand_path("../../../.cache/spellcheck-dictionaries", __dir__)
          DICT_BASE_URL = "https://raw.githubusercontent.com/streetsidesoftware/" \
                          "cspell-dicts/main/dictionaries"

          BUNDLED_DICTS = %w[
            aws               bash-words        basic
            cobol             coding-compound-terms computing-acronyms
            cpp               csharp            css
            django            docker            dotnet
            english-words-10  english-words-20  fonts
            fortran           git               go
            html              java-additional-terms java-terms
            javascript        kotlin            latex
            networkingTerms   node              npm
            objective-c       php               placeholder-words
            python-common     ruby              rust
            scala             smalltalk         software-tools
            softwareTerms     sql-common-terms  sql
            swift             tsql              webServices
          ].freeze

          # 辞書をマージして word_map を返す
          # @return [Hash] { downcase_word => display_word }
          def build_word_map(config)
            words = {}
            (BUNDLED_DICTS + extra_dicts(config)).each do |name|
              path = resolve_path(name)
              load_into_word_map(path, words) if path
            end
            extra_words(config).each { |w| words[w.downcase] = w }
            words
          end

          private

          def resolve_path(name)
            bundled = File.join(BUNDLED_DIR, "#{name}.txt")
            return bundled if File.exist?(bundled)

            cached = File.join(CACHE_DIR, "#{name}.txt")
            return cached if File.exist?(cached)

            fetch_and_cache(name)
          end

          def load_into_word_map(path, words)
            File.foreach(path) do |line|
              word = normalize(line)
              next unless word
              words[word.downcase] = word
              if word.include?('-')
                no_hyphen = word.gsub('-', '').downcase
                words[no_hyphen] ||= word
              end
            end
          end

          def normalize(line)
            line = line.strip
            return nil if line.empty? || line.start_with?('#')
            line = line.split('#').first.strip
            line = line.split('/').first.strip
            line = line.gsub(/[^a-zA-Z0-9\-]/, '').strip
            return nil if line.empty?
            line
          end

          def fetch_and_cache(name)
            FileUtils.mkdir_p(CACHE_DIR)
            path = File.join(CACHE_DIR, "#{name}.txt")
            %w[dict src].each do |subdir|
              url = "#{DICT_BASE_URL}/#{name}/#{subdir}/#{name}.txt"
              URI.open(url) { |f| File.write(path, f.read) }
              Common.log_action("[spellcheck] Downloaded dict: #{name} (#{subdir})")
              return path
            rescue OpenURI::HTTPError
              next
            end
            Common.log_warn("[spellcheck] Failed to download dict: #{name}")
            nil
          end
        end
      end
    end
  end
end
```

---

## 11. 将来の拡張

- `book.yml` の `ignore_patterns` による正規表現単位の除外
- パフォーマンス改善が必要な場合: 単語長フィルタの導入、またはBK-treeの採用を検討する
- パフォーマンス改善が必要な場合: 辞書ファイルの gzip 圧縮を検討する

---

## 12. ライセンス上の注意事項

gem同梱辞書はすべてMITライセンスに限定する。
オンデマンドダウンロード辞書（cspell-dicts の GPL辞書等）はgem内に含めず、
ユーザーの `~/.cache` に保存することで再配布を回避する。
各辞書の著作権表示は `THIRD-PARTY-LICENSES.md` にまとめて記載する。
