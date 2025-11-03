# 📄 vivlio-starter Textlint 導入指針および検討背景資料

## 1. 導入機能とコマンド名

| 機能名 | 概要 | 採用コマンド名 |
| :--- | :--- | :--- |
| **文章チェック機能** | Markdown形式で書かれた日本語文章の品質、表記揺れ、冗長表現などを検査し、執筆品質を向上させる。 | `vivlio-starter text:lint`<br>（別名: `vivlio-starter text:check`） |

---

## 2. 検討背景と外部ツール採用の理由

### 2.1. 外部ツール採用の決定

日本語の文章校正ロジックは非常に複雑であり、以下の理由から、Rubyでの**独自実装を避け**、実績のある外部ツール**Textlint**を採用する。

* **コスト効率**: 形態素解析や高度な日本語チェックロジックをゼロから開発・保守するには莫大な工数がかかる。
* **品質と網羅性**: Textlintは多くの開発者によって利用・強化されており、特に日本語技術文書向けの**豊富な校正ルール（プラグイン）**が既に提供されているため、高い品質を担保できる。

### 2.2. Textlintの選定理由

形態素解析のMeCabなども候補であったが、**「文章校正・Linter」**機能の実現という観点から、Textlintを最有力とした。

* **日本語ルールセットの充実**: `textlint-rule-preset-ja-technical-writing` など、技術文書の執筆に特化したルールが豊富であり、電子書籍の執筆品質向上という目的に最も合致する。
* **Markdown対応**: 執筆環境がMarkdownベースであるため、そのまま解析できるTextlintは親和性が高い。
* **表記揺れの厳密なチェック**: `textlint-rule-prh` などのプラグインを利用することで、固有名詞などの**表記揺れを厳密にチェック・統一**できる。

---

## 3. Textlint 導入指針

### 3.1. 実装の基本方針

`vivlio-starter` は、Textlintを**コマンドラインインターフェース (CLI) 経由**で実行するラッパーとして機能する。

1.  **コア機能の分離**: Ruby Gem (`vivlio-starter`) 内部で、Node.jsの実行ファイル（`textlint`）をサブプロセスとして呼び出す (`system` または `Open3` を利用)。
2.  **結果の整形**: Textlintの出力（標準出力）を捕捉し、`vivlio-starter` のターミナル画面に分かりやすく整形して表示するために、スタイリッシュフォーマット (--format stylish )を用いる。
3.  **依存関係の明記**: Textlint自体はNode.js環境が必要であるため、GemのREADMEやドキュメントに、Node.jsおよびTextlintのインストールが**利用者の前提条件**であることを明確に記載する。
4. vivlio-starter doctor の自動インストール機能を用いて、Textlintやプラグインのインストールを自動化する。

### 3.2. 推奨プラグイン（初期導入検討リスト）

初期段階で導入を推奨する、日本語の品質向上に必須のプラグイン候補は以下の通り。これらの設定は、`.textlintrc` ファイルで管理する。

| プラグイン名 | 目的 |
| :--- | :--- |
| `textlint-rule-preset-ja-technical-writing` | 日本語技術文書の標準的なスタイルガイドチェック。 |
| `textlint-rule-prh` | **表記揺れ**（単語のブレ）の検出と統一。辞書ファイル（YAMLなど）によるカスタマイズ必須。 |
| `textlint-rule-preset-japanese` | 一般的な日本語の文章スタイルチェック（句読点、記号など）。 |
| `textlint-rule-no-dropping-the-ra` | 「ら抜き言葉」の検出。 |
| `textlint-rule-max-ten` | 一文に含まれる読点（テン）の最大数を制限し、文の冗長化を防ぐ。 |

### 3.2. 追加導入推奨リスト（品質向上）

| プラグイン名 | 目的 | チェックする主な内容 |
| :--- | :--- | :--- |
| **`textlint-rule-ja-no-mixed-period`** | **文末の句読点の統一** | 文書全体で句読点のスタイル（「です。」と「である。」の混在など）が統一されているかをチェックする。 |
| **`textlint-rule-no-doubled-conjunctive-word`** | **接続詞の重複** | 同じ意味を持つ接続詞や副詞（例: 「したがって、しかしながら」）が連続して使用されることを検出する。 |
| **`textlint-rule-no-doubled-joshi`** | **助詞の重複** | 同じ助詞（てにをは）が連続で使用されている、不自然な文を検出する。 |
| **`textlint-rule-no-exclamation-question-mark`** | **感嘆符・疑問符の制限** | 正式な文書における感嘆符（`!`）や疑問符（`?`）の過度な使用を制限し、文体を統一する。 |
| **`textlint-rule-ja-no-successive-word`** | **同単語の連続出現** | 同じ単語が短い間隔で連続して出現している箇所をチェックし、文章の単調さを改善する。 |

### 3.3. 設定管理

- Textlintの対象ファイルは、contents/以下のMarkdownファイルを対象とする。
- Textlintの設定ファイル（`.textlintrc` やルールファイル）は既定のものを用意するが、`vivlio-starter` の`book.yml` 通じて利用者が好みの設定が出来るようにする。

### 3.4. プラグインのカスタマイズ 

標準で用意される`.textlintrc.yml`ファイルは、次の通りである。

```yaml
# 📄 推奨 Textlint 設定ファイル (`.textlintrc.yml`)

plugins: []

filters:
  # コードブロックやインラインコードを校正対象から除外するための設定。
  # textlint-filter-rule-node-types を利用する想定。
  node-types:
    nodeTypes:
      - Code
      - CodeBlock

rules:
  # ====================================================================
  # 3.1. 初期導入検討リスト（ベースライン）
  # ====================================================================

  # 技術文書のスタイルをチェックする標準プリセット
  preset-ja-technical-writing:
    # 厳格なチェックを行うため、デフォルト設定（全て有効）を採用
    prefer-ja-no-space-around-paren: true  # かっこの周りのスペースを禁止
    no-exclamation-question-mark:
      allowFullWidth: true  # 全角の！や？は許可（部分的にカスタム）

  # 固有名詞や特定の用語の表記揺れをチェック（辞書ファイルの指定が必要）
  # ※ 辞書ファイルは `config/textlint/` 配下に配置する想定
  prh:
    rulePaths:
      - ./config/textlint/icsmedia.yml
      - ./config/textlint/js_primer.yml
      - ./config/textlint/prh.yml

  # 一般的な日本語スタイルチェックのプリセット（ja-technical-writingと重複するルールもあるため、必要なものを有効化）
  preset-japanese:
    # 基本的には ja-technical-writing に任せるが、独自のチェック項目を追加する
    no-mix-dearu-desumasu: true  # 文体の混在（だ・である調とです・ます調）を禁止

  # 「ら抜き言葉」の検出
  no-dropping-the-ra: true

  # ====================================================================
  # 3.2. 追加導入推奨リスト（品質向上）
  # ====================================================================

  # 文末の句読点の統一
  # 句点（。）と読点（、）以外の句読点の混在をチェック
  ja-no-mixed-period:
    periodMarks: [".", "。", "！", "？"]  # 文末に許可する記号（必要に応じてカスタマイズ）
    allowPeriodMarks: ["。", "."]  # 基本的に「。」と「.」の混在を許可

  # 接続詞の重複チェック
  no-doubled-conjunctive-word: true

  # 助詞の重複チェック
  no-doubled-joshi:
    base: ["は", "が", "を", "に", "と", "より", "から", "で"]  # チェック対象とする助詞
    min: 3  # 連続する最小回数（デフォルトの3回を使用）

  # 感嘆符・疑問符の制限
  # ja-technical-writingで部分的に制御されているが、ここではより厳格に設定
  no-exclamation-question-mark:
    allowFullWidth: false  # 全角であっても原則禁止
    allowHalfWidth: false  # 半角も禁止
    # 文体によっては、この設定を削除し、ja-technical-writingのデフォルトに任せることも検討

  # 同単語の連続出現チェック
  ja-no-successive-word:
    dict: default  # デフォルト辞書を使用
    maxRepeated: 2  # 2回連続までを許容（3回以上でエラー）

  # ====================================================================
  # その他：推奨される汎用的な設定
  # ====================================================================

  # 一文に含まれる読点（テン）の最大数を制限
  max-ten:
    max: 4  # 一文あたりの読点の最大数（一般的に4が推奨される）

  # 全角と半角カタカナの混在をチェック
  # 必要に応じて他のルールに置き換えてください
  ja-no-mixed-kana: true
```

## 4. Textlint prh 標準辞書（ルールセット）の導入

### 4.1 推奨される標準辞書ファイル
以下の辞書ファイルは、技術文書の表記揺れチェックに特に有用で、いずれも MIT ライセンスで公開されていることから、推奨される辞書ファイルとして、Vivlio Starter に組み込むことにより、利用者に提供する。

| 辞書名 | 入手先 | 主な用途 |
| :--- | :--- | :--- |
| **ICS MEDIA** | [github.com/ics-creative/textlint-rule-preset-icsmedia/tree/master/dict](https://github.com/ics-creative/textlint-rule-preset-icsmedia/tree/master/dict) | Web 技術全般の用語統一に利用可能な辞書が複数含まれる。 |
| **js-primer** | [github.com/asciidwango/js-primer/blob/master/prh.yml](https://github.com/asciidwango/js-primer/blob/master/prh.yml) | JavaScript 関連用語の表記揺れ統一。 |

### 4.2. 📁 辞書ファイルの配備先

プロジェクトルート直下に `config/textlint/` を用意し、必要な辞書ファイルを配置する。

```bash
config/textlint/
├── icsmedia.yml
├── prh_cho_on.yml
├── prh_corporation.yml
├── prh_duplicate.yml
├── prh_idiom.yml
├── prh_open_close.yml
├── prh_redundancy.yml
├── prh_web_technology.yml
└── js_primer.yml
└── prh.yml（独自辞書）
```

ICS MEDIA リポジトリ（[dict/ ディレクトリ](https://github.com/ics-creative/textlint-rule-preset-icsmedia/tree/master/dict)）には、用途別に分割された辞書ファイルが複数用意されている。

- [prh_cho_on.yml](https://github.com/ics-creative/textlint-rule-preset-icsmedia/blob/master/dict/prh_cho_on.yml)
- [prh_corporation.yml](https://github.com/ics-creative/textlint-rule-preset-icsmedia/blob/master/dict/prh_corporation.yml)
- [prh_duplicate.yml](https://github.com/ics-creative/textlint-rule-preset-icsmedia/blob/master/dict/prh_duplicate.yml)
- [prh_idiom.yml](https://github.com/ics-creative/textlint-rule-preset-icsmedia/blob/master/dict/prh_idiom.yml)
- [prh_open_close.yml](https://github.com/ics-creative/textlint-rule-preset-icsmedia/blob/master/dict/prh_open_close.yml)
- [prh_redundancy.yml](https://github.com/ics-creative/textlint-rule-preset-icsmedia/blob/master/dict/prh_redundancy.yml)
- [prh_web_technology.yml](https://github.com/ics-creative/textlint-rule-preset-icsmedia/blob/master/dict/prh_web_technology.yml)
- [prh.yml](https://github.com/ics-creative/textlint-rule-preset-icsmedia/blob/master/dict/prh.yml)（Vivlio Starter では `icsmedia.yml` にリネームして利用）

js-primer 辞書も同様に公開されており、[prh.yml](https://github.com/asciidwango/js-primer/blob/master/prh.yml) を取得して `js_primer.yml` として保存する。（後述する独自辞書との競合を避けるため）

### 4.3. ⚙️ .textlintrc.yml の設定
プロジェクトルート直下に `.textlintrc.yml` を配備する。そして、`.textlintrc.yml` の `prh.rulePaths` を更新して参照する。

この設定により、`vivlio-starter text:lint` コマンド実行時に、ICS MEDIA 辞書と JS Primer 辞書、独自辞書をまとめて適用する。

### 4.4. 📁 プロジェクト独自の辞書ファイル

プロジェクト独自の辞書ファイル（prh.yml）は、YAML形式で作成する。
辞書ファイルには、修正すべき**パターン（表記ゆれ）と、それに置き換えるべき正しい表記（期待値）**を定義する。
以下に、vivlio-starter の表記を統一するための辞書ファイルの例を示す。

#### 📁 プロジェクト独自の辞書ファイル（prh.yml）作成例

```yaml
version: 1
rules:
  # ----------------------------------------------
  # ルール1: 正式名称（Vivlio Starter）の統一
  # ----------------------------------------------
  - expected: Vivlio Starter
    # 大文字・小文字やスペースが意図せず崩れた表記を修正対象とする
    patterns:
      - 'vivlio starter'  # 小文字とスペース
      - 'VivlioStarter'   # スペースなし（キャメルケースのような形式）
      - 'vivliostarter'   # 完全な小文字・スペースなし
      - 'VIVLIO STARTER'  # 全て大文字

  # ----------------------------------------------
  # ルール2: コマンド名（vivlio-starter）の統一
  # ----------------------------------------------
  - expected: vivlio-starter
    # コマンド表記が意図せず崩れた表記を修正対象とする
    patterns:
      - 'Vivlio-Starter' # コマンドなのに大文字が混ざっている
      - 'vivlio_starter' # コマンドなのにアンダースコアが使われている
      - 'vivliostarter'  # ハイフンなし

  # ----------------------------------------------
  # ルール3: コマンド表記（vivlio-starter）の回避設定（オプション）
  # ----------------------------------------------
  # 文中での「vivlio-starter」の使用を禁止し、正式名称（Vivlio Starter）に誘導したい場合に使用
  - expected: Vivlio Starter
    # このルールのパターンの前に、より具体的なルールを定義することが推奨されます。
    # このルールは、原則として「Vivlio Starter」を使用するように矯正する役割を持ちます。
    patterns:
      - 'vivlio-starter'

  # ルール3を導入する場合の注意点
  # textlint は、Markdownのコードブロック内やインラインコード内の文字列を
  # 通常のテキストとして扱わないように設定することで、
  # コマンド表記を意図的にチェック対象外にすることができます。

  # ----------------------------------------------
  # ルール4: よくある一般的な表記ゆれ（例: ユーザ vs ユーザー）
  # ----------------------------------------------
  - expected: ユーザー
    patterns:
      - 'ユーザ'
      - 'ユーザーさん' # ユーザーの後に続く不要な敬称を修正したい場合
  
  # ----------------------------------------------
  # ルール5: 技術用語の表記ゆれ（例: javascript vs JavaScript）
  # ----------------------------------------------
  - expected: JavaScript
    patterns:
      - 'javascript'
      - 'Javascript'
  
  # ----------------------------------------------
  # ルール6: 誤字・脱字の修正（「〜したいと想います」の修正など）
  # ----------------------------------------------
  - expected: 思います
    patterns:
      - '想います'
  
  # ----------------------------------------------
  # ルール7: 全角/半角スペースの統一（特定の単語の直後の統一）
  # ----------------------------------------------
  - expected: 'GitHub Actions'
    # 'GitHubActions' のようにスペースがない場合に修正
    patterns:
      - 'GitHubActions'
```
