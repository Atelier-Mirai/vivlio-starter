# Textlint

:::{.chapter-lead}
Vivlio Starter には、Markdown で書かれた文章の品質をチェックする textlint 機能が統合されています。表記揺れ、冗長表現、文体の混在などを自動検出し、執筆品質の向上をサポートします。
:::

## textlint とは

:::{.section-lead}
textlint は、自然言語の文章を検査するための Linter ツールです。プログラムコードの品質チェックツール（ESLint や RuboCop など）の文章版と考えるとわかりやすいでしょう。
:::

textlint は Node.js で動作するオープンソースツールで、特に日本語の技術文書に対して強力な校正機能を提供します。Vivlio Starter では、この textlint を CLI コマンドとして統合し、`contents/` ディレクトリ内の Markdown ファイルを簡単にチェックできるようにしています。

### textlint の主な機能

- **表記揺れの検出**: 「ユーザ」と「ユーザー」、「javascript」と「JavaScript」などの表記の不統一を検出
- **文体の統一**: 「です・ます調」と「だ・である調」の混在をチェック
- **冗長表現の検出**: 助詞の重複、接続詞の連続使用などを指摘
- **技術用語のスペルチェック**: IT 用語の誤記を検出
- **自動修正機能**: 一部のエラーは自動的に修正可能

## lint コマンドの基本

:::{.section-lead}
Vivlio Starter では、`vs lint` コマンドで textlint + スペルチェックを実行します。対象ファイルの指定、設定ファイルの切り替え、自動修正など、さまざまなオプションが用意されています。
:::

### 基本的な使い方

全ての Markdown ファイルをチェックする場合は、引数なしで実行します。

```bash
vs lint
```

### 特定のファイルをチェック

章のベース名（例: `11-install`）を指定すると、そのファイルのみをチェックします。拡張子（`.md`）や `contents/` ディレクトリの指定は省略できます。

```bash
# 11-install.md のみをチェック
vs lint 11-install

# 複数のファイルを指定
vs lint 11-install 21-customize
```

### 章番号による指定

章番号のみを指定することもできます。

```bash
# 91-*.md と 93-*.md をチェック
vs lint 91 93
```

### 範囲指定

章番号の範囲を指定して、複数のファイルをまとめてチェックできます。

```bash
# 11-*.md から 21-*.md までの範囲をチェック
vs lint 11-21
```

## コマンドオプション

:::{.section-lead}
textlint コマンドには、動作をカスタマイズするためのオプションが用意されています。設定ファイルの切り替え、出力フォーマットの変更、自動修正などが可能です。
:::

### --config オプション

使用する `.textlintrc.yml` ファイルのパスを指定します。省略時は `config/.textlintrc.yml` が使用されます。

```bash
# カスタム設定ファイルを使用
vs lint --config path/to/custom/.textlintrc.yml
```

### --format オプション

textlint の出力フォーマットを指定します。以下の形式が選択可能です。

- `stylish`（既定値）: 見やすい標準形式
- `compact`: コンパクトな形式
- `pretty-error`: エラー箇所を詳細に表示

```bash
# コンパクト形式で出力
vs lint --format compact

# 詳細なエラー表示
vs lint --format pretty-error
```

### --fix オプション

自動修正可能なエラーを自動的に修正します。

```bash
# エラーを自動修正
vs lint --fix

# 特定のファイルのみ自動修正
vs lint 11-install --fix
```

<!-- textlint-disable -->
**注意**: `--fix` オプションは元のファイルを直接書き換えます。重要なファイルを修正する前に、必ずバージョン管理システム（Git など）でコミットしておくことをお勧めします。
<!-- textlint-enable -->

## 実行結果の見方

:::{.section-lead}
textlint の実行結果には、エラーの種類、場所、修正方法などが表示されます。出力メッセージの読み方を理解することで、効率的に文章を改善できます。
:::

### エラーなしの場合

問題が見つからなかった場合は、以下のようなメッセージが表示されます。

```
✅ 文章チェックで問題は見つかりませんでした。
```

### エラーが見つかった場合

エラーが検出されると、ファイル名、行番号、列番号、エラーの種類、メッセージが表示されます。

```
contents/11-install.md
  10:15  error  "ユーザ" → "ユーザー" に統一してください  prh
  25:8   error  文末の句読点が統一されていません        ja-no-mixed-period
```

各行の意味は以下の通りです。

- `10:15`: 10行目の15文字目
- `error`: エラーレベル（`error` または `warning`）
- メッセージ: エラーの内容と修正方法
- `prh`: エラーを検出したルール名

### 自動修正可能なエラー

自動修正可能なエラーがある場合、エラー数とともに案内メッセージが表示されます。

```
💡 5個のエラーは自動修正可能です。次のコマンドで修正できます:
   vs lint --fix
```

## 設定ファイルのカスタマイズ

:::{.section-lead}
textlint の動作は `.textlintrc.yml` ファイルで制御します。プロジェクトの執筆スタイルに合わせて、ルールの有効化・無効化、厳密度の調整などが可能です。
:::

### 設定ファイルの場所

Vivlio Starter では、以下の場所に設定ファイルが配置されています。

- `config/.textlintrc.yml`: プロジェクト全体の設定
- `config/textlint_prh.yml`: 表記揺れ辞書（プロジェクト固有）
- `config/textlint_allowlist.yml`: 除外リスト
- `config/textlint_dictionaries/`: 標準辞書ファイル

### 主要な設定項目

#### filters（フィルタ）

校正対象から除外する要素を指定します。

```yaml
filters:
  node-types:
    nodeTypes:
      - Code          # インラインコード
      - CodeBlock     # コードブロック
      - Link          # リンク
      - Image         # 画像
  comments: true      # HTMLコメントによる除外
  allowlist:
    allowlistConfigPaths:
      - ./textlint_allowlist.yml
```

#### rules（ルール）

適用する校正ルールを指定します。

```yaml
rules:
  # 技術文書のスタイルチェック
  preset-ja-technical-writing:
    tech-word: true
    max-kanji-continuous-len:
      max: 10  # 漢字の連続を10文字まで許可

  # 表記揺れチェック
  prh:
    rulePaths:
      - ./textlint_prh.yml

  # 文体の統一
  preset-japanese:
    no-mix-dearu-desumasu: true
```

### 表記揺れ辞書のカスタマイズ

`config/textlint_prh.yml` ファイルで、プロジェクト固有の表記ルールを定義できます。

```yaml
version: 1
rules:
  # 正式名称の統一
  - expected: Vivlio Starter
    patterns:
      - 'vivlio starter'
      - 'VivlioStarter'
      - 'vivliostarter'

  # 技術用語の統一
  - expected: JavaScript
    patterns:
      - 'javascript'
      - 'Javascript'
```

### 除外リストの設定

`config/textlint_allowlist.yml` ファイルで、チェック対象から除外する語句を指定できます。

```yaml
# VFM記法
- ":::"
- "/^:::\\{/"

# 書籍名（漢字連続チェック除外）
- "現代計算機科学"
- "プログラミング言語理論"

# 資格名称
- "基本情報技術者"
- "応用情報技術者"
```

## 部分的な除外

:::{.section-lead}
特定の箇所だけ textlint のチェックを無効化したい場合は、HTML コメントを使用します。
:::

### 一時的な無効化

```markdown
<!-- textlint-disable -->
ここはチェックされません。
表記揺れや文体の混在があっても無視されます。
<!-- textlint-enable -->
```

### 特定のルールのみ無効化

```markdown
<!-- textlint-disable prh -->
ここでは表記揺れチェックのみが無効化されます。
<!-- textlint-enable prh -->
```

### 次の行のみ無効化

```markdown
<!-- textlint-disable-next-line -->
この行だけチェックが無効化されます。
```

## トラブルシューティング

:::{.section-lead}
textlint の実行中に問題が発生した場合の対処方法を紹介します。
:::

### textlint コマンドが見つからない

以下のエラーが表示される場合は、textlint がインストールされていません。

```
textlint コマンドが見つかりません。
```

**対処方法**:

```bash
# 自動インストール（推奨）
vs doctor --fix

# または手動インストール
npm install -g textlint textlint-rule-preset-ja-technical-writing
```

### 設定ファイルが見つからない

```
textlint 設定ファイルが見つかりません: config/.textlintrc.yml
```

**対処方法**: プロジェクトのルートディレクトリで実行しているか確認してください。または、`--config` オプションで設定ファイルのパスを明示的に指定してください。

### プラグインが見つからない

```
Failed to load plugin: textlint-rule-preset-ja-technical-writing
```

**対処方法**: 必要なプラグインをインストールしてください。

```bash
npm install -g textlint-rule-preset-ja-technical-writing \
  textlint-rule-prh \
  textlint-rule-preset-japanese \
  textlint-rule-preset-ja-spacing \
  textlint-rule-spellcheck-tech-word \
  textlint-filter-rule-allowlist \
  textlint-filter-rule-comments
```

## 英語スペルチェック

:::{.section-lead}
`vs lint` は日本語校正（textlint）と同時に、原稿中の英単語のスペルミスも自動検出します。約46,000語の技術辞書を搭載しており、プログラミング言語・フレームワーク・略語など幅広い技術用語に対応しています。
:::

### 基本的な動作

`vs lint` を実行すると、textlint による日本語校正に続いて英語スペルチェックが自動的に実行されます。追加のコマンドや設定は不要です。

```bash
vs lint
```

スペルミスが検出されると、ファイル名・行番号・誤りの単語・修正候補が表示されます。

```
📄 contents/06-algorithm.md
   23  bandle => bundle
        綴りが誤っている可能性があります (spellcheck)
   47  yestoday => yesterday
        綴りが誤っている可能性があります (spellcheck)
```

候補語が見つからない場合は、単語のみが表示されます。

```
   12  xyzzy
        綴りが誤っている可能性があります (spellcheck)
```

### チェック対象

- `contents/` 配下の `*.md` ファイル内の英単語が対象です。
- コードブロック（` ``` `〜` ``` `）内はデフォルトでチェック対象外です。
- Vivliostyle 拡張記法（`:::{.class}` など）内の語も除外されます。

### 特定行の除外

その行だけスペルチェックを無効化したい場合は、行末に `<!-- spellcheck:ignore -->` を追記します。

```markdown
htmx はサーバーとの通信を HTML 属性で記述できるライブラリです。 <!-- spellcheck:ignore -->
```

### book.yml による設定

スペルチェックの動作は `config/book.yml` の `spellcheck` セクションで制御します。

```yaml
spellcheck:
  extra_dictionaries:      # オンデマンドダウンロード辞書（初回実行時に取得）
    - ada                  # Ada 言語の用語を追加したい場合
    - elixir               # Elixir 言語の用語を追加したい場合
  extra_words:             # プロジェクト固有語（辞書にない固有名詞など）
    - vivliostyle
    - vivlio-starter
    - MyProductName
  ignore_words:            # 誤検知を抑制したい単語
    - htmx                 # 辞書にないが正しい単語として扱いたい場合
  check_code_blocks: false # コードブロック内をチェックするか（デフォルト: false）
```

#### extra_words（プロジェクト固有語）

辞書に登録されていない固有名詞や造語を `extra_words` に追加すると、誤検知を防げます。

```yaml
spellcheck:
  extra_words:
    - vivliostyle
    - MyCompanyName
    - SomeFramework
```

#### ignore_words（誤検知の抑制）

`ignore_words` に指定した単語はチェック対象から除外されます。辞書に存在しないが意図的に使用している略語などに利用します。

```yaml
spellcheck:
  ignore_words:
    - htmx
    - MSSAP
```

#### extra_dictionaries（追加辞書）

標準搭載辞書に含まれない言語や分野の辞書を追加できます。初回実行時にインターネットから取得し、`.cache/spellcheck-dictionaries/` にキャッシュされます。

```yaml
spellcheck:
  extra_dictionaries:
    - ada
    - elixir
    - haskell
```

#### check_code_blocks（コードブロック内のチェック）

デフォルトでは `false`（コードブロック内はチェックしない）です。コードブロック内の英単語もチェックしたい場合は `true` に設定します。

```yaml
spellcheck:
  check_code_blocks: true
```

### 標準搭載辞書

以下の辞書が標準で搭載されています。

- **一般英単語**: SCOWL words.10 / words.20（約12,000語）
- **技術用語**: HTML / CSS / JavaScript / TypeScript / Ruby / Python / Go / Rust / Java / Swift / Kotlin など主要言語の用語
- **略語・製品名**: AWS / Azure / GCP などクラウド、各種フレームワーク・ツール名
- **索引用語**: プロジェクトの `index_glossary_terms.yml` に登録済みの語

## まとめ

:::{.section-lead}
textlint を活用することで、執筆中の文章品質を継続的に維持し、読者にとって読みやすい技術書を作成できます。
:::

Vivlio Starter の textlint 統合機能により、以下のメリットが得られます。

- **一貫性のある表記**: 表記揺れを自動検出し、統一された用語使用を実現
- **読みやすい文章**: 冗長表現や文体の混在を排除し、読者の理解を促進
- **効率的な校正**: 自動チェックにより、手動校正の負担を軽減
- **品質の維持**: 継続的なチェックにより、執筆品質を一定レベルに保持

textlint を日常的に使用することで、より洗練された技術書の執筆が可能になります。まずは `vs lint` コマンドを実行して、現在の文章品質を確認してみましょう。

![textlint](textlint.png)