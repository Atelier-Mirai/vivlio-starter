# 文章校正（vs lint）

:::{.chapter-lead}
Vivlio Starter には、Markdown で書かれた原稿の品質をチェックする `vs lint` コマンドが統合されています。日本語の校正（textlint）と英単語のスペルチェックを一度に実行し、表記揺れ・冗長表現・文体の混在・綴り誤りなどを検出して、執筆品質の向上をサポートします。
:::

## vs lint とは

:::{.section-lead}
`vs lint` は、ひとつのコマンドで「日本語校正」と「英語スペルチェック」の 2 種類のチェックをまとめて実行します。プログラムコードの Linter（ESLint や RuboCop など）の文章版と考えるとわかりやすいでしょう。
:::

`vs lint` は次の 2 つを並行して実行します。

- **日本語校正（textlint）**: Node.js 製のオープンソース校正ツール textlint を利用し、日本語技術文書向けのルールで文章をチェックします。
- **英語スペルチェック**: Vivlio Starter 内蔵のスペルチェッカーが、原稿中の英単語の綴り誤りを検出します。約 50 以上の技術辞書を搭載しています。

### 主なチェック内容

<!-- vs-lint-disable-next-line -->
- **表記揺れの検出**: 「ユーザ」と「ユーザー」、「javascript」と「JavaScript」などの不統一を検出
- **文体の統一**: 「です・ます調」と「だ・である調」の混在をチェック
- **冗長表現の検出**: 助詞の重複、接続詞の連続使用などを指摘
- **一文の長さ**: 長すぎる文を指摘（最大文字数は設定可能）
- **英単語の綴り誤り**: プログラミング言語・フレームワーク・略語などを誤記から保護
- **自動修正**: 表記揺れなど一部の指摘は自動的に修正可能

## 基本的な使い方

:::{.section-lead}
`vs lint` は `contents/` ディレクトリ以下の Markdown を検査します。引数なしで全章、章のベース名・章番号・範囲指定で部分的に検査できます。
:::

### すべての章をチェック

引数なしで実行すると、`contents/` 配下のすべての Markdown が対象になります。

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

## 実行範囲を絞る

:::{.section-lead}
通常は日本語校正とスペルチェックの両方が実行されますが、片方だけを実行したい場合はオプションで切り替えられます。
:::

### --textlint-only / --spellcheck-only

```bash
# 日本語校正（textlint）のみを実行
vs lint --textlint-only

# スペルチェックのみを実行
vs lint --spellcheck-only
```

`--spellcheck-only` は textlint 関連の事前チェックをスキップするため、**textlint をまだ導入していない環境でも動作します**。「とりあえず英単語の綴りだけ確認したい」というときに便利です。

## 実行結果の見方

:::{.section-lead}
チェック結果は、同じ種類の指摘を 1 行にまとめた「集約表示」で出力されます。どのルールに何件・どの行で引っかかったかが一目でわかります。
:::

### 集約表示

指摘はファイルごと・ルールごとに集約され、出現件数の多い順に並びます。日本語校正は `(textlint)`、スペルチェックは `(spellcheck)` のラベルが付きます。

```
📄 contents/11-install.md  (textlint)
   12件  [ja-space-between-half-and-full-width] 原則として、全角文字と半角文字の間にスペースを入れません。
         行: 4, 10, 13, 20, 26, 31, 70, 84, 117, 157, …
    8件  [prh] 以下 => 次
         行: 84, 122, 138, 162, 256, 304, 447, 460

📄 contents/11-install.md  (spellcheck)
    3件  bandle => bundle             行: 23, 88, 152
    2件  yestoday => yesterday        行: 47, 90
```

各行の意味は次の通りです。

- 先頭の件数: そのルール（または語）の指摘が出た回数
- `[ja-space-between-half-and-full-width]`: 指摘したルール名（日本語校正）
- `bandle => bundle`: 誤りと修正候補（スペルチェック）。候補が見つからない場合は単語のみを表示
- `行: …`: 出現した行番号（最大 10 件まで。超過分は `…`）

### 完了サマリー

すべてのチェックが終わると、件数の内訳と次のアクションがまとめて表示されます。

```
✏️ 文章の品質チェックが完了しました
🟡 1080箇所に改善提案があります
   - 日本語校正: 679箇所
   - スペルチェック: 401箇所
💡 そのうち364箇所は自動修正可能です。
   vs lint --fix
```

問題が見つからなかった場合は、次のように表示されます。

```
✅ 文章チェックで問題は見つかりませんでした。
```

## 自動修正

:::{.section-lead}
表記揺れなど、機械的に直せる指摘は `--fix` オプションで自動修正できます。
:::

```bash
# 自動修正可能な指摘を修正
vs lint --fix

# 特定のファイルのみ自動修正
vs lint 11-install --fix
```

<!-- vs-lint-disable -->
**注意**: `--fix` は元のファイルを直接書き換えます。重要なファイルを修正する前に、必ずバージョン管理システム（Git など）でコミットしておくことをお勧めします。
<!-- vs-lint-enable -->

## チェックの部分的な除外

:::{.section-lead}
特定の箇所だけチェックを無効化したい場合は、`vs-lint` コメント記法を使用します。日本語校正・スペルチェックの両方に共通して機能します。
:::

原稿中には、固有名詞・コード断片・意図的な表記など、チェックから外したい箇所があります。Vivlio Starter では以下の統一記法でこれを制御します。

### 複数行の除外

`<!-- vs-lint-disable -->` と `<!-- vs-lint-enable -->` で囲まれた範囲は、すべてのチェックから除外されます。

```markdown
<!-- vs-lint-disable -->
ここは textlint もスペルチェックも両方スキップされます。
表記揺れや綴りの誤りがあっても検出されません。
<!-- vs-lint-enable -->
```

### 次の行のみ除外

`<!-- vs-lint-disable-next-line -->` を行の直前に置くと、その次の行だけがチェックから除外されます。

```markdown
<!-- vs-lint-disable-next-line -->
この行だけチェックが無効化されます。
```

### 使用例

固有名詞や製品名など、辞書に登録されていない語句が多数登場するセクションをまとめて除外する場合：

```markdown
<!-- vs-lint-disable -->
htmx はサーバーとの通信を HTML 属性で記述できるライブラリです。
意図的に複数の表記を混在させたい場合にも使用できます。
<!-- vs-lint-enable -->
```

一行だけ除外したい場合：

```markdown
<!-- vs-lint-disable-next-line -->
htmx はサーバーとの通信を HTML 属性で記述できるライブラリです。
```

## 英語スペルチェック

:::{.section-lead}
`vs lint` は日本語校正と同時に、原稿中の英単語の綴り誤りも検出します。プログラミング言語・フレームワーク・略語など幅広い技術用語に対応した辞書を内蔵しています。
:::

### チェック対象

- `contents/` 配下の `*.md` ファイル内の英単語が対象です。
- コードブロック（` ``` `〜` ``` `）内は既定でチェック対象外です。
- Vivliostyle 拡張記法（`:::{.class}` など）内の語も除外されます。

### ユーザー辞書と --register

辞書に載っていない固有名詞や造語は「綴り誤り」として指摘されます。プロジェクト固有の語をまとめて許可語に加えたいときは、`--register` が便利です。

```bash
# 未知語をユーザー辞書へ一括登録
vs lint --register
```

`--register` は、スペルチェックで未知だった語をすべて `config/user_words.txt`（ユーザー辞書）へ追記します。登録後、不要な語を手で削れば、以後そのプロジェクトでは指摘されなくなります。

- `--register` は**スペルチェック専用の操作**です。`--spellcheck-only` を併記しなくても、日本語校正は実行されません。
- ユーザー辞書は 1 行 1 語・`#` 始まりはコメント。大文字小文字は区別しません。辞書順・重複なしで自動的に整えられます。
- このプロジェクト固有の辞書です。別の本でも使いたい場合は `config/user_words.txt` をコピーしてください。

:::{.tip}
想定ワークフロー: まず `vs lint --register` で大量に指摘された語を一括登録し、`config/user_words.txt` を開いて「本当に正しい語」だけを残します。残った誤記は次回の `vs lint` で改めて指摘されます。
:::

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
  ignore_words:            # 誤検知を抑制したい単語
    - htmx                 # 辞書にないが正しい語として扱いたい場合
  check_code_blocks: false # コードブロック内をチェックするか（既定: false）
```

- **extra_words**: 辞書に登録されていない固有名詞や造語を許可語に加えます。`--register` がプロジェクトの作業中辞書（`user_words.txt`）であるのに対し、`extra_words` は明示的に管理したい語を `book.yml` に書く位置づけです。
- **ignore_words**: 指定した語を検出後に除外します。
- **extra_dictionaries**: 標準搭載辞書に含まれない言語・分野の辞書を追加します。初回実行時にインターネットから取得し、`.cache/spellcheck-dictionaries/` にキャッシュされます。
- **check_code_blocks**: `true` にするとコードブロック内の英単語もチェックします。

### 標準搭載辞書

以下のような辞書が標準で搭載されています（50 以上のファイル）。

- **一般英単語**: SCOWL ベースの英単語辞書
- **技術用語**: HTML / CSS / JavaScript / TypeScript / Ruby / Python / Go / Rust / Java / Swift / Kotlin など主要言語の用語
- **略語・製品名**: AWS / Azure / GCP などクラウド、各種フレームワーク・ツール名
- **本ツール固有語**: `vivlio-starter-terms.txt`（textlint / yml / SCOWL など、標準辞書にない語）
- **索引用語**: プロジェクトの `index_glossary_terms.yml` に登録済みの英字語

## book.yml による調整（lint セクション）

:::{.section-lead}
日本語校正の細かな挙動は、`config/book.yml` の `lint` セクションで調整できます。「お節介な指摘」を黙らせたり、文体の好みを反映したりできます。
:::

```yaml
lint:
  # 使用する textlint 設定ファイル
  config: config/.textlintrc.yml

  # ルールごと丸ごと無効化したい textlint ルール ID（集約表示の [ ] 内の名前）
  disabled_rules:
    # - arabic-kanji-numbers
    # - sentence-length

  # "X => Y" 形式の指摘を語で無効化（指摘先頭行にその語を含むものを黙らせる）
  disabled_terms:
    # - 次
    # - とおり

  # 一文の最大文字数（未指定なら既定 100）
  sentence_length_max: 100

  # 「サーバ／パラメータ／フィルタ」等の末尾長音を省く文体なら true
  trim_long_vowel: true

  # インラインコードと和文の間のスペースを許容するなら true
  allow_space_around_code: true

  # 全角と半角（英数・記号）の間のスペースを許容するなら true
  allow_space_between_ja_en: true
```

### config（設定ファイルの切り替え）

`vs lint` が使う textlint 設定ファイルのパスです。設定を使い分けたい場合は、`config/.textlintrc-strict.yml` などを用意してここで切り替えます。

### disabled_rules / disabled_terms（指摘の個別無効化）

集約表示に出るルール名や語を指定して、特定の指摘だけを黙らせます。

- **disabled_rules**: ルール ID（`[ ]` 内の名前）で丸ごと無効化します。たとえば `arabic-kanji-numbers`（「一つ → 1つ」）と `prh`（「一つ → ひとつ」）のように**矛盾するルール**は、どちらかを切ると衝突が解消します。
- **disabled_terms**: `"X => Y"` 形式の指摘について、先頭行にその語を含むものを無効化します。表記揺れ系の「お節介」な指摘を 1 つずつ抑制したいときに使います。

これらは**出力段で該当の指摘を取り除く**方式なので、`prh` 辞書の所在に依存せず確実に効きます。無効化した分は問題件数にも数えません。

### sentence_length_max（一文の最大文字数）

一文の長さを指摘する `sentence-length` ルールの上限文字数です。未指定なら既定の 100 文字。文章の好みに応じて 80 や 120 などに変更できます。指定すると、既定の設定にこの値を反映した一時設定を生成して textlint へ渡します。

### trim_long_vowel（末尾長音の文体）

`true` にすると、「サーバ／パラメータ／フィルタ」のように**末尾の長音を省く技術文体**を選べます。「サーバ → サーバー」のように末尾に長音を足すだけの指摘を抑止します。

### `allow_space_around_code` / `allow_space_between_ja_en`（和欧間スペースの許容）

技術書では、`` `vs import` コマンド `` のようにインラインコードや英数字の前後にスペースを入れる書き方がよく使われます。これらを許容したい場合に `true` にします。

- `allow_space_around_code`: インラインコードと和文の間のスペースを許容
- `allow_space_between_ja_en`: 全角と半角（英数・記号）の間のスペースを許容

:::{.notice}
この 2 つは「指摘を隠す」のではなく、textlint の設定レベルでルールを無効化します。そのため `vs lint --fix` を実行しても、意図的に入れたスペースが削除されることはありません。
:::

## 設定ファイルの場所

:::{.section-lead}
日本語校正の詳細なルールは textlint の設定ファイルで管理します。プロジェクトの執筆スタイルに合わせて調整できます。
:::

Vivlio Starter では、以下の場所に設定ファイルが配置されています。

- `config/.textlintrc.yml`: textlint 本体の設定（フィルタ・ルール）
- `config/textlint_prh.yml`: 表記揺れ辞書（プロジェクト固有）
- `config/textlint_allowlist.yml`: 除外リスト（VFM 記法・書籍名・資格名称など）
- `config/textlint_dictionaries/`: 標準の `prh` 辞書ファイル
- `config/spellcheck_dictionaries/`: 英語スペルチェック辞書
- `config/user_words.txt`: スペルチェックのユーザー辞書（`--register` の追記先）

### 除外リストの設定

特定の語句を textlint のチェック対象から完全に外したい場合は、`config/textlint_allowlist.yml` に登録します。`disabled_terms` が「出力から消す」のに対し、allowlist は **textlint が報告そのものをしなくなる**正攻法です。

```yaml
# VFM記法
- ":::"
- "/^:::\\{/"

# 書籍名（漢字連続チェック除外）
- "現代計算機科学"

# 部分一致の誤検出を避ける（例: 「対処方法」が「対処方」と誤検出される）
- "対処方法"
```

## トラブルシューティング

:::{.section-lead}
`vs lint` の実行中に問題が発生した場合の対処方法を紹介します。
:::

### textlint コマンドが見つからない

以下のエラーが表示される場合は、textlint がインストールされていません。

```
textlint コマンドが見つかりません。npm などで textlint をインストールしてください。
```

**対処方法**:

```bash
# 自動インストール（推奨）
vs doctor --fix

# または手動インストール
npm install -g textlint textlint-rule-preset-ja-technical-writing
```

なお、スペルチェックだけなら textlint なしでも実行できます。

```bash
vs lint --spellcheck-only
```

### 設定ファイルが見つからない

```
textlint 設定ファイルが見つかりません: config/.textlintrc.yml
```

**対処方法**: プロジェクトのルートディレクトリで実行しているか確認してください。設定ファイルのパスは `config/book.yml` の `lint.config` で指定できます。

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

### 技術用語が綴り誤りとして指摘される

正しい技術用語が繰り返し指摘される場合は、その語をユーザー辞書へ登録します。

```bash
vs lint --register
```

恒久的に管理したい語は、`config/book.yml` の `spellcheck.extra_words` に書いておくとよいでしょう。

## まとめ

:::{.section-lead}
`vs lint` を活用することで、執筆中の文章品質を継続的に維持し、読者にとって読みやすい技術書を作成できます。
:::

`vs lint` による校正機能で、以下のメリットが得られます。

- **一貫性のある表記**: 表記揺れを自動検出し、統一された用語使用を実現
- **読みやすい文章**: 冗長表現・文体の混在・長すぎる文を排除し、読者の理解を促進
- **綴りの安心**: 内蔵辞書とユーザー辞書で、英単語の誤記を防止
- **効率的な校正**: 集約表示と自動修正により、手動校正の負担を軽減
- **好みに合わせた調整**: `book.yml` の `lint` セクションで、お節介な指摘や文体の好みを反映

まずは `vs lint` を実行して、現在の原稿の品質を確認してみましょう。
