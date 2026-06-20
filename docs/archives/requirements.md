# 要件定義書

## はじめに

Techbook モードは、技術書典向け印刷用 PDF 生成において Chromium の PDF エンジンに起因する2つの問題を回避するための専用処理モードである。

1. カラー絵文字の Type 3 フォント化 → Twemoji SVG img タグへの差し替え
2. 可変フォント（Variable Font）の PDF 出力不正 → 静的 @font-face インスタンスの自動注入

本モードは `book.yml` の `output.pdf.techbook: true` で有効化され、`vs build` コマンドの追加オプションは不要である。

## 用語集

- **Techbook_Mode**: 技術書典向け印刷用 PDF 生成のための専用処理モード。Chromium PDF エンジンの制約を回避する前処理を行う
- **Processor**: Techbook モードのエントリポイントクラス。EmojiReplacer と VariableFontInjector を統括する
- **EmojiReplacer**: HTML 中のカラー絵文字を Twemoji SVG img タグに差し替えるクラス
- **VariableFontInjector**: 可変フォントの静的インスタンス @font-face 宣言を生成するクラス
- **Twemoji**: Twitter が提供するオープンソースの絵文字画像セット（CC BY 4.0 ライセンス）
- **Codepoint**: Unicode コードポイント。絵文字を16進数で表現した識別子（例: ✅ → 2705）
- **Variable_Font**: 1つのフォントファイルで複数のウェイトやスタイルを表現できるフォント形式
- **Static_Instance**: 可変フォントの特定のウェイト・スタイルを固定した @font-face 宣言
- **Build_Pipeline**: Vivlio Starter のビルドパイプライン。Markdown → HTML 変換 → Vivliostyle ビルド → PDF 出力の一連の処理
- **Legalpage**: `vs create:legalpage` コマンドで生成される法的情報ページ。免責事項・商標・Twemoji クレジット等を含む

## 要件

### 要件 1: Techbook モードの有効化制御

**ユーザーストーリー:** 技術書典出展者として、book.yml の設定で Techbook モードを有効化したい。それにより、ビルド時に Chromium PDF エンジンの問題が自動的に解決される。

#### 受け入れ基準

1. book.yml で `output.pdf.techbook` が `true` に設定されている場合、Processor は Techbook モード処理を有効化すること
2. book.yml で `output.pdf.techbook` が `false` に設定されている場合、Processor はすべての Techbook モード処理をスキップし、HTML をそのまま返すこと
3. book.yml で `output.pdf.techbook` が省略されている場合、Processor は値を `false` として扱い、すべての Techbook モード処理をスキップすること
4. Processor は `config.dig("output", "pdf", "techbook")` を使用して設定値を読み取ること

### 要件 2: カラー絵文字の SVG 差し替え

**ユーザーストーリー:** 技術書典出展者として、原稿中のカラー絵文字を Twemoji SVG 画像に差し替えたい。それにより、印刷用 PDF に絵文字の Type 3 フォントグリフが含まれなくなる。

#### 受け入れ基準

1. Techbook モードが有効で HTML に Unicode 絵文字が含まれる場合、EmojiReplacer は `stylesheets/twemoji/` ディレクトリに対応する SVG ファイルが存在するか確認すること
2. 絵文字に対応する SVG ファイルが存在する場合、EmojiReplacer はその絵文字を `<img>` タグに置換すること。タグには `src`（SVG への絶対パス）、`alt`（元の絵文字文字）、`class="emoji vs-emoji"`、`width="1em"`、`height="1em"`、`style="vertical-align: -0.15em;"` を含めること
3. 絵文字に対応する SVG ファイルが存在しない場合、EmojiReplacer は HTML 出力中のその文字をそのまま残すこと
4. EmojiReplacer は絵文字の Unicode コードポイントを小文字16進数でハイフン結合した文字列から SVG ファイル名を導出すること（例: "✅" → "2705.svg"、複合絵文字 → "xxxx-yyyy.svg"）
5. EmojiReplacer は gem に同梱された `stylesheets/twemoji/` ディレクトリを SVG ソースとして使用し、ネットワークアクセスを必要としないこと
6. HTML に同一の絵文字が複数箇所に含まれる場合、EmojiReplacer はすべての出現箇所を置換すること
7. HTML に絵文字が含まれない場合、EmojiReplacer は HTML をそのまま返すこと

### 要件 3: 絵文字スタイル CSS の自動注入

**ユーザーストーリー:** 技術書典出展者として、絵文字スタイル CSS が自動注入されるようにしたい。それにより、差し替え後の絵文字画像が PDF 出力で正しく表示される。

#### 受け入れ基準

1. Techbook モードが有効な場合、Processor は `img.vs-emoji` ルールを含む CSS を注入すること。ルールには `display: inline`、`width: 1em`、`height: 1em`、`vertical-align: -0.15em` を含めること
2. Techbook モードが無効な場合、Processor は絵文字スタイル CSS を注入しないこと

### 要件 4: Twemoji クレジット表記の legalpage 統合

**ユーザーストーリー:** 技術書典出展者として、Twemoji のクレジット表記を既存の legalpage（免責・商標ページ）に統合したい。それにより、CC BY 4.0 ライセンスに準拠しつつ、専用クラスを追加せずに既存の `vs create:legalpage` の仕組みで管理できる。

#### 受け入れ基準

1. book.yml の `legal` セクションは `twemoji` キーを受け付けること。値はクレジット表記テキスト（文字列）とすること
2. `legal.twemoji` が設定されている場合、`vs create:legalpage` コマンドは免責事項・商標セクションに加えて Twemoji クレジットセクションを生成すること
3. `vs create:legalpage` が生成する Twemoji セクションは、`<div class="twemoji-credit">` で囲み、`<h2>■絵文字クレジット</h2>` の見出しを付け、`legal.twemoji` のテキストを `<p>` タグで行ごとに出力すること
4. `legal.twemoji` が省略されている場合、`vs create:legalpage` コマンドは Twemoji クレジットセクションを生成しないこと（免責・商標のみ出力）
5. `legal.twemoji` の設定例は以下の形式とすること:
   ```yaml
   legal:
     twemoji: |
       絵文字画像: Twemoji (https://twemoji.twitter.com) © Twitter, Inc. (CC BY 4.0)
   ```

### 要件 5: 可変フォント静的インスタンス注入

**ユーザーストーリー:** 技術書典出展者として、可変フォント設定から静的 font-face 宣言を生成したい。それにより、Chromium が PDF 出力でフォントを正しくレンダリングする。

#### 受け入れ基準

1. book.yml の `output.pdf.variable_fonts` にフォント設定エントリが含まれる場合、VariableFontInjector は各インスタンスに対して静的 `@font-face` 宣言を生成すること
2. 可変フォント設定の各インスタンスについて、VariableFontInjector は `font-family`（ファミリー名とウェイトから導出）、`src`（woff2 形式のフォントファイルへの url）、`font-weight`（指定されたウェイト値）、`font-style: normal`、`font-variation-settings`（指定された設定文字列）を含む `@font-face` ブロックを生成すること
3. `output.pdf.variable_fonts` が省略または空の場合、VariableFontInjector は CSS を出力しないこと
4. Techbook モードが無効な場合、`variable_fonts` の設定に関わらず VariableFontInjector は CSS を出力しないこと

### 要件 6: Processor によるオーケストレーション

**ユーザーストーリー:** 技術書典出展者として、Techbook の全処理ステップが自動的にオーケストレーションされるようにしたい。それにより、`techbook: true` を設定するだけで正しい PDF 出力が得られる。

#### 受け入れ基準

1. Techbook モードが有効な場合、Processor は HTML コンテンツに対して EmojiReplacer を実行すること
2. Techbook モードが有効な場合、Processor は VariableFontInjector の CSS 出力を取得するメソッドを提供すること
3. Processor は設定ハッシュを受け取り、`output.pdf.techbook` の設定を抽出すること
4. Techbook モードが無効な状態で `process` メソッドが呼ばれた場合、Processor は入力 HTML をそのまま返すこと
5. Processor は Build_Pipeline において Markdown → HTML 変換の後、Vivliostyle レンダリングの前に呼び出されること

### 要件 7: SVG ファイルの Gem 同梱

**ユーザーストーリー:** 技術書典出展者として、Twemoji SVG ファイルが gem に同梱されるようにしたい。それにより、ネットワーク接続なしでビルドが動作する。

#### 受け入れ基準

1. Vivlio_Starter gem は `stylesheets/twemoji/` ディレクトリ配下に Twemoji SVG ファイルを含めること
2. EmojiReplacer は `stylesheets/twemoji/` ディレクトリのパスを、ユーザーのプロジェクトディレクトリではなく gem のインストール先を基準に解決すること
3. Twemoji の新バージョンで絵文字が追加された場合、Vivlio_Starter gem は新しい gem バージョンリリースで更新された SVG ファイルを含めること

### 要件 8: book.yml 可変フォント設定スキーマ

**ユーザーストーリー:** 技術書典出展者として、book.yml で可変フォントインスタンスを明示的に設定したい。それにより、静的インスタンスとして生成するフォントウェイトを制御できる。

#### 受け入れ基準

1. book.yml のスキーマは `output.pdf` 配下に `variable_fonts` 配列を受け付けること。各エントリは `family`（文字列、フォントファミリー名）、`src`（文字列、フォントファイルへのパス）、`instances`（インスタンスオブジェクトの配列）を含むこと
2. 各インスタンスオブジェクトは `weight`（整数、CSS font-weight 値）と `settings`（文字列、CSS font-variation-settings 値）を受け付けること
3. `variable_fonts` エントリに必須フィールド（`family`、`src`、`instances`）が欠けている場合、VariableFontInjector はそのエントリをスキップし、警告をログ出力すること

### 要件 9: 絵文字差し替えの HTML 構造保全

**ユーザーストーリー:** 技術書典出展者として、絵文字差し替えが周囲の HTML 構造を保全するようにしたい。それにより、原稿のレイアウトが崩れない。

#### 受け入れ基準

1. 絵文字を置換する際、EmojiReplacer は周囲のすべての HTML タグ、属性、テキストコンテンツを保全すること
2. EmojiReplacer は `<img>` タグの `src` 属性に絶対ファイルパスを生成し、HTML ファイルの配置場所に依存しないようにすること
3. 絵文字が HTML 要素（例: `<p>`、`<li>`、`<td>`）の内部に出現する場合、EmojiReplacer は絵文字文字のみを置換し、囲んでいる要素はそのまま残すこと
