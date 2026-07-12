# QueryStream データ用画像の data/ 同居対応 仕様書

> 作成日: 2026-07-12
> ステータス: **実装待ち**
> 対象: PLANNED.md [Medium]「QueryStream のデータ用画像を `data/` 配下にも置けるようにする」の実現。`data/*.yml` の `cover:` 等が参照する画像を、記法を書く各章の画像ディレクトリではなく `data/` 配下に同居させ、データ一式を自己完結にする
> 決定事項（2026-07-12 調査に基づく）:
> - **解決タイミングは QueryStream 展開直後**（前処理 Step「process_data_streams!」内）。展開結果のテキストだけを対象に画像参照を書き換える
> - **query-stream gem には汎用の `post_render` コールバックを追加**（v1.3.0）。gem は画像を一切知らない——「展開結果＋コンテキスト（データ名・データファイル）を呼び出し元のフィルタに通す」だけの拡張に留める
> - **画像の実体はビルド時にワークスペース `html/images/data/` へコピー**し、参照は `images/data/…`（asset_prefix なし）へ書き換える。数式 SVG（P4b §2.1）と同型の「ビルド生成物」経路に乗せるため、**PDF ミラー・EPUB/Kindle 同梱は既存機構で自動対応**（epub_builder/pdf_builder の同梱コードは原則無変更）
> - 探索順は **章画像ディレクトリ → `data/<データ名>/` → `data/images/`**（章ローカルが最優先＝完全後方互換＋章別差し替えを許す）
> - 衝突回避は「宛先が `data/` 配下の相対パスをミラーする」ことで構造的に担保。複数章で同一データを使う場合も宛先が同一パスになるため重複コピー・重複同梱は起きない
> 関連: `lib/vivlio_starter/cli/pre_process/data_render.rb`（gem ラッパー）, `lib/vivlio_starter/cli/pre_process/image_path_normalizer.rb`, `lib/vivlio_starter/cli/pre_process/math_transformer.rb`（`images/…` 無 prefix 参照の先行事例・P4b §2.1）, `lib/vivlio_starter/cli/build/epub_builder.rb`（`localize_assets!`・`stage_webp_replacement`）, `lib/vivlio_starter/cli/build/pdf_builder.rb:45`（html→pdf 画像ミラー）, `/Users/mirai/projects/query-stream`（gem 本体・改修可）

## 0. 背景・問題

QueryStream 記法（`= physics_books` 等）はテンプレート（`templates/_physics_book.md`）へデータ（`data/physics_books.yml`）を流し込み、`![](cover)` → `![](relativity.webp)` のような**素のファイル名**の画像参照を生成する。その後 `ImagePathNormalizer.fix_image_paths` が素のファイル名を `images/<章スラッグ>/<ファイル名>` へ正規化するため、**データが参照する画像は「記法を書いた章」の画像ディレクトリに置くしかない**。

- データ（文字情報）は `data/` に一元化されているのに、画像だけ章ごとに複製が必要で一体感に欠ける
- 同じデータを複数章で使うと画像も複数章分コピーする羽目になる

## 1. 現状調査結果（2026-07-12）

### 1.1 展開と正規化の流れ（`MarkdownPreprocessor#run`）

```
process_data_streams!   ← QueryStream 展開。ここで ![](relativity.webp) が生まれる
normalize_image_paths!  ← 素のファイル名 → images/<章>/… ＋ asset_prefix 前置 ＋ .webp 寄せ
validate_links_and_images!
…
transform_math!         ← 数式 SVG。BUILD_HTML_DIR/images/math/ へ書き出し images/math/… 参照
```

- `ImagePathNormalizer.fix_image_paths`（image_path_normalizer.rb:80）: `images/` 始まりはそのまま、他は `images/<章>/` へ。実在すれば `Common.asset_prefix`（`../../../../`）を前置、無ければ 🔴 エラー＋プレースホルダー data URI。存在確認は `.webp/.png/.jpg/.jpeg` の変種込み（`image_exists_for?`）
- `MathTransformer`（math_transformer.rb:94–99）が「ビルド生成画像」の先行事例: 実体は `Common::BUILD_HTML_DIR/images/math/<章>/` へ書き、参照は **asset_prefix なしの `images/math/…`**。EPUB/Kindle の prefix 剥がし（`stage_consumer_htmls!`）を素通りし、PDF は html/→pdf/ ミラー内で解決する

### 1.2 消費者側（変更不要であることの確認）

- **PDF**: `pdf_builder.rb:45` が `BUILD_HTML_DIR/images` を丸ごと `pdf/` へミラー → `images/data/…` も自動で載る
- **EPUB/Kindle**: `epub_builder.rb` `localize_assets!` が `copy_asset_tree!(BUILD_HTML_DIR/images, dir, dest_root: 'images')` で同梱。フィルタ `localized_image?` は `_epub_assets/`・`headings/` のみ除外 → `data/…` は通る
- **Kindle WebP transcode に既存の穴あり（要修正）**: `stage_webp_replacement`（epub_builder.rb 付近、§1.2 末尾参照）は WebP ソースを **cwd（ルート）相対でしか探さない**（`File.exist?(webp_path)`）。ルートに実体がないワークスペース生成画像（`images/data/…`）は変換不能になり src 据え置き→Kindle で表示されない。数式 SVG は .webp でないため今まで露見しなかった。**BUILD_HTML_DIR フォールバックの追加が必要**（§3.5）

### 1.3 query-stream gem（v1.2.2・改修可）

- `QueryStream.render` は行単位で記法を検出し `render_query` へ委譲。`render_query` は parse → `DataResolver.resolve`（単複自動解決で `data/<名>.yml|.yaml|.json` を特定）→ filter/sort/limit → テンプレート解決 → `TemplateCompiler.render`
- **`render_query` はデータ名（`parsed[:source]`）と実データファイルパス（`data_file`）を知っている唯一の場所**。展開結果に対する後段フィルタを差し込むならここ
- `TemplateCompiler.expand_images`: `![](key)` は拡張子なし→変数展開、拡張子あり→リテラル素通し。つまり展開後の画像 src は「YAML の値そのまま」または「テンプレートのリテラルそのまま」

### 1.4 その他

- `Common` に `DATA_DIR` 定数・`directories.data` 設定・`data_dir` ヘルパは**存在しない**（data_render.rb は `data_dir: 'data'` を直書き）
- Step 1 画像最適化（`ImageOptimizer.optimize_images!`）の対象は `images/` と `stylesheets/images/` のみ。`data/` 配下の png/jpg は WebP 化されない
- `lib/vivlio_starter/cli/pre_process/data_render/` 配下の 3 ファイル（query_stream_parser.rb・singularize.rb・template_compiler.rb）は **gem 移行前の残骸で未参照**（require されていない）
- `LinkImageValidator` はプレースホルダー data URI の痕跡だけを見るため本件と干渉しない

## 2. 配置規約（著者向け仕様）

```
data/
  physics_books.yml
  physics_books/            # ① データ単位フォルダ（データファイルの basename と同名）
    relativity.webp
    quantum.webp
  images/                   # ② データ横断の共有プール
    common_badge.webp
```

画像参照（YAML の `cover:` 値やテンプレート内リテラル）が**素のファイル名**（`/` を含まない・URL/data:/絶対パスでない）のとき、次の順で探索する:

1. `images/<章スラッグ>/<名前>` —— 従来どおり。**章ローカルが最優先**（後方互換・章別差し替え用）
2. `data/<データファイル basename>/<名前>` —— 例: `data/physics_books.yml` → `data/physics_books/`。単複解決後の**実ファイル名**基準（`= physics_book` と書いても実体が `physics_books.yml` なら `data/physics_books/`）
3. `data/images/<名前>` —— 共有プール

いずれも `ImagePathNormalizer.image_exists_for?` と同じ変種解決を行う: `.svg` は完全一致のみ、その他は `.webp → .png → .jpg → .jpeg` の優先順で実在を採る。

- 1 でヒット → **書き換えない**（従来経路。normalizer が `images/<章>/…`＋asset_prefix へ正規化）
- 2/3 でヒット → 実体を `BUILD_HTML_DIR/images/data/<data/ 配下の相対パス>` へコピーし、参照を `images/data/<相対パス>` へ書き換え（例: `![](relativity.webp)` → `![](images/data/physics_books/relativity.webp)`）
- どこにも無い → 書き換えず 🟡 警告で**探索 3 箇所を列挙**（→ その後 normalizer が従来どおり 🔴＋プレースホルダー。著者は 🟡 の探索リストで置き場所を判断できる）

`data/` 配下の相対パスを宛先にミラーするため、`data/physics_books/note.webp` と `data/images/note.webp` は別宛先になり**同名衝突は構造的に起きない**。複数章が同じデータ画像を使っても宛先が同一なのでコピーは 1 回・EPUB 同梱も 1 部。

### 2.1 ①と②の使い分け基準（著者向けドキュメントにも記載する）

**その画像を参照するデータファイルが 1 つか複数か**で決める:

- **① `data/<データ名>/`** —— そのデータファイル**専用**の画像。「yml＋同名フォルダ」のペアで自己完結し、コピーだけで別プロジェクトへ持ち運べる。迷ったらこちら
- **② `data/images/`** —— **複数のデータファイル**から参照される共有画像。例: `books.yml` と `technical_books.yml` の両方に載る本の表紙は、各 yml に `cover: ruby_book.webp` と書き、実体は `data/images/ruby_book.webp` に 1 枚だけ置く（探索順 ①→② により両方から解決され、ビルド宛先も `images/data/images/ruby_book.webp` で同一＝同梱 1 部）

なお QueryStream にはファイル間参照が無いため、共通レコードの**文字情報**は各 yml に重複して書く。重複を避けたい場合は「1 ファイル＋タグ絞り込み」（`= books | tags=technical`）へ一本化するのが本来の設計で、その場合は画像も ① に置けて完全に自己完結する。ファイルを分ける目安は「テンプレートを変えたい」「データ構造が違う」とき。

## 3. 実装

### 3.1 query-stream gem v1.3.0: `post_render` コールバック（汎用拡張）

**方針**: gem に画像の知識を持ち込まない。「1 記法の展開結果を、コンテキスト付きで呼び出し元のフィルタへ通す」だけの汎用フックにする。これによりテンプレート内リテラル画像（`![](note.webp)`）も変数展開画像も一括で拾える。

`lib/query_stream/configuration.rb`:

```ruby
# @return [Proc, nil] 展開結果の後段フィルタ。(text, context) -> String
attr_accessor :post_render
```

`lib/query_stream.rb`:

```ruby
def render(content, source_filename: nil, data_dir: nil, templates_dir: nil,
           on_error: nil, on_warning: nil, post_render: nil)
  post_render ||= configuration.post_render
  # …既存処理。render_query 呼び出しに post_render: を伝搬…
end

def render_query(query, line_number: nil, source_filename: nil, data_dir: nil,
                 templates_dir: nil, on_warning: nil, post_render: nil)
  # …既存処理…
  rendered = TemplateCompiler.render(template_content, records, source_filename:, line_number:)

  return rendered unless post_render

  context = {
    source:        parsed[:source],   # 記法に書かれた論理名（例: "physics_book"）
    data_file:     data_file,          # 単複解決後の実パス（例: "data/physics_books.yml"）
    data_dir:      data_dir,
    template_path: template_path,
    query:         query,
    location:      location            # "filename:line" 形式
  }
  result = post_render.call(rendered, context)
  result.is_a?(String) ? result : rendered   # String 以外（nil 含む）は元の展開結果を採用
end
```

- コールバック内の例外は握り潰さず**そのまま伝播**させる（`render` の既存 rescue が `QueryStream::Error` 以外を拾わないことに注意——呼び出し元＝vivlio-starter 側の resolver で StandardError を rescue して警告ログ＋素通しにする。gem 側では何もしない）
- テスト（`test/query_stream_test.rb` に追加）: (a) post_render が展開結果と context 全キーを受け取る、(b) 戻り値 String が採用される、(c) nil/非 String 戻りは元テキスト採用、(d) render キーワードと configuration 両経路、(e) 記法が無い行では呼ばれない
- `version.rb` → `1.3.0`、CHANGELOG 追記、`gem build` → `gem install`（ローカル検証用）。RubyGems 公開後に vivlio-starter の `Gemfile`/`gemspec` を `~> 1.3` へ更新（§5）

### 3.2 vivlio-starter: `Common` に data ディレクトリを定数化

`lib/vivlio_starter/cli/common.rb`:

- `DATA_DIR = 'data'` 定数を追加（CONTENTS_DIR 等の並び・common.rb:33 付近）
- `default_directories` に `data: DATA_DIR` を追加（common.rb:248 付近）
- ヘルパ `def data_dir = CONFIG&.directories&.data || DATA_DIR` を追加（`images_dir` の並び・common.rb:826 付近、公開メソッドリスト common.rb:924 付近にも追記）
- `data_render.rb:32` の既定値 `data_dir: 'data'` を `data_dir: Common.data_dir` へ

### 3.3 新規モジュール `DataImageResolver`

`lib/vivlio_starter/cli/pre_process/data_image_resolver.rb`（新規）:

```ruby
module VivlioStarter
  module CLI
    module PreProcessCommands
      # QueryStream 展開結果内の素ファイル名画像を data/ 配下から解決する。
      # ヒットした実体はワークスペース html/images/data/ へコピーし、
      # 参照を images/data/…（asset_prefix なし・P4b §2.1 のビルド生成物形）へ書き換える。
      module DataImageResolver
        module_function

        # 変種解決の優先順（image_exists_for? と同ポリシー）
        VARIANT_EXTS = %w[.webp .png .jpg .jpeg].freeze

        # @param text [String] QueryStream 1 記法の展開結果
        # @param context [Hash] QueryStream post_render コンテキスト
        # @param chapter_slug [String] 章スラッグ（例: "22-extentions"）
        # @return [String] 画像参照を書き換えた展開結果
        def rewrite(text, context, chapter_slug:)
          # Markdown 画像と HTML <img> の両方を走査
          #  - ![alt](src) / ![alt](src){attrs}
          #  - <img src="src" …>（:html テンプレート対応）
          # src が対象外（URL・data:・絶対パス・"/" を含む・images/ 始まり）なら素通し
        end
      end
    end
  end
end
```

処理手順（src 1 件ごと）:

1. **対象判定**: `%r{\A(?:[a-zA-Z][a-zA-Z0-9+.-]*:|/)}` にマッチ（スキーム付き・絶対パス）または `/` を含む、または `images/` 始まり → 素通し
2. **章ローカル優先**: `File.join(Common.images_dir, chapter_slug, src)` を変種込みで確認。実在 → 素通し（従来経路）
3. **data 探索**: `data_base = File.basename(context[:data_file], '.*')` として
   `File.join(Common.data_dir, data_base, src)` → `File.join(Common.data_dir, 'images', src)` の順に変種込みで確認
4. **ヒット時**: 実在した変種ファイル（例 `data/physics_books/relativity.webp`）を
   `File.join(Common::BUILD_HTML_DIR, 'images', 'data', <data/ からの相対パス>)` へコピー
   （`FileUtils.mkdir_p` ＋ 既存宛先が同一 mtime/size なら skip・古ければ上書き）。
   参照を `images/data/<相対パス>` へ書き換え（拡張子は**実在した変種のもの**にする——後段の .webp 寄せに依存しない）
5. **ミス時**: 素通し＋ 🟡 `Common.log_warn`。メッセージは actionable に:
   `"#{context[:location]} - データ画像 '#{src}' が見つかりません（記法: #{context[:query]}）"`、
   detail に探索 3 パスを列挙し、`data/<data_base>/#{src}` へ置くのが推奨である旨のヒントを添える
   （最終的な 🔴＋プレースホルダーは従来どおり ImagePathNormalizer が出す。🟡 は置き場所の手掛かり提供が目的）

`data_render.rb` の `process` に `chapter_slug:` キーワードを追加し（呼び出し元 `markdown_preprocessor.rb:125` は `File.basename(context.output_path, '.md')` 相当を渡す——`transform_math!` の chapter_slug と同式）、`QueryStream.render` へ `post_render:` を注入する:

```ruby
post_render = lambda do |text, ctx|
  DataImageResolver.rewrite(text, ctx, chapter_slug:)
rescue StandardError => e
  Common.log_warn("データ画像の解決に失敗しました: #{e.class}: #{e.message}")
  text
end
```

### 3.4 `ImagePathNormalizer` の carve-out

`fix_image_paths`（image_path_normalizer.rb:95 の gsub 内）で、**`images/data/` 始まりの参照は確定済みとして素通し**する。分岐位置は asset_prefix 判定（:100–102）の直後:

```ruby
# DataImageResolver が確定させたビルド生成物参照（P4b §2.1 の無 prefix 形）。
# 実体はワークスペース html/images/data/ にあり、ルート images/ には無い。
elsif image_path.start_with?('images/data/')
  "![#{alt_text}](#{image_path})"
```

- asset_prefix を**前置しない**（数式 SVG と同じ消費者 dir 相対）
- `.webp` 寄せ（:112）も適用しない（resolver が実在変種で確定済み）
- 存在チェックもしない（コピーは resolver が実施済み。万一の欠落は PDF/EPUB 側で顕在化するが、resolver がコピー失敗時に警告を出している）

### 3.5 Kindle WebP transcode のワークスペースフォールバック

`epub_builder.rb` `stage_webp_replacement`: ソース探索を「cwd → BUILD_HTML_DIR」の 2 段にする:

```ruby
webp_path = decode_html_entities(src_attr)
unless File.exist?(webp_path)
  candidate = File.join(Common::BUILD_HTML_DIR, decode_html_entities(src_attr))
  webp_path = candidate if File.exist?(candidate)
end
return nil unless File.exist?(webp_path)
```

- `transcode_source_for`（png/jpg 原本優先の二重劣化回避）はワークスペース内に原本が無いため WebP 自身から変換するフォールバックに乗る。**原本の追加コピーはしない**（クリーン EPUB への原本混入・パッケージ肥大を避ける。EPUB_IMAGE_MAX_EDGE の上限で品質は既存ポリシー内）

### 3.6 Step 1 画像最適化に `data/` を追加

`image_optimizer.rb:20` の対象に `Common.data_dir` を追加:

```ruby
dirs = [Common::IMAGES_DIR, File.join(Common::STYLESHEETS_DIR, 'images'), Common.data_dir]
```

- `resize:*` は `**/*.{png,jpg,jpeg}` のみ処理し **sibling に .webp を生成**する（yml には触れない）。`images/` と同じ「著者ディレクトリ内に最適化 .webp を並置する」既存ポリシーの適用であり、resolver の `.webp` 優先探索がそのまま効く
- Techbook モードの SVG→WebP（image_optimizer.rb:41 `svg_dirs`）にも `Common.data_dir` を加える（データ画像に SVG を使った場合の Type 3 フォント問題を同様に回避）

## 4. テスト

Minitest・`test/vivlio_starter/` 配下（fixtures は `test/vivlio_starter/fixtures/`）。ruby-coding-rules skill 適用。

1. **query-stream 側**（`/Users/mirai/projects/query-stream/test/query_stream_test.rb`）: §3.1 の (a)〜(e)
2. **`data_image_resolver_test.rb`**（新規）: Dir.mktmpdir 内で data/・images/・ワークスペースを組み立て
   - 探索順: 章ローカルにあれば書き換えない／`data/<名>/` が `data/images/` に優先
   - 書き換え形: `images/data/physics_books/relativity.webp`（無 prefix・実在変種の拡張子）
   - コピー先: `BUILD_HTML_DIR/images/data/…` に実体が生まれる。2 回目呼び出しで再コピーされない（mtime 保持）
   - 変種解決: `cover: foo.png` でも `data/…/foo.webp` があれば .webp を採る。`.svg` は完全一致のみ
   - 対象外素通し: URL・`data:`・`/` 含み・`images/` 始まり
   - ミス時: 🟡 警告に探索 3 パスが含まれ、テキストは不変
   - HTML `<img src>` の書き換え
3. **`image_path_normalizer_test.rb` 追加ケース**: `images/data/…` 参照が asset_prefix 前置・.webp 寄せ・プレースホルダー化のいずれも受けないこと
4. **`epub_builder` 系**: `stage_webp_replacement` が cwd に無く BUILD_HTML_DIR にある WebP を変換できること（既存の EPUB テストの流儀に合わせる）
5. **結合（任意・rake test 対象外）**: 本リポジトリ実プロジェクトで `data/physics_books/` に表紙を置き `vs build`。PDF に表紙が出る・EPUB (`vs epub`) のパッケージ内に `images/data/physics_books/*.webp` が 1 部だけ入る・Kindle (`vs kindle`) で jpg/png へ transcode されることを確認

## 5. 手順（実装順序）

1. query-stream gem: `post_render` 実装＋テスト＋ v1.3.0 に bump ＋ `gem build && gem install`（ローカル）
2. vivlio-starter: `Gemfile`/`gemspec` を `'query-stream', '~> 1.3'` へ。`bundle install`（ローカル gem 参照は `bundle config local.query-stream` か、公開まで Gemfile の path 指定を一時使用——**コミット前に path 指定は外す**）
3. §3.2〜§3.6 を実装（root のみ編集。`lib/project_scaffold/` は触らない）
4. `rake test` ＋ §4 の結合確認（`rake reinstall` 後に実プロジェクトで `vs build` / `vs epub` / `vs kindle`）
5. ドキュメント: `data/_README.md` に配置規約（§2）を追記、`contents/25-querystream.md`（データ画像の節を新設）・`contents/61-developer.md:189` 付近（data/ の説明）を更新
6. `ruby copy_to_scaffold.rb` でスキャフォールド同期
7. query-stream を RubyGems へ公開し、Gemfile.lock を公開版で確定

## 6. スコープ外・補足

- **`data/` 画像のテーマ別（light/dark）バリアント**は対象外（theme-images 機構はテーマ資産専用）
- **章ローカルと data の同名共存**は仕様（章ローカル優先＝章別差し替え）。警告は出さない
- 既存サンプル（`images/22-extentions/` の物理学書表紙）は**当面そのまま**でも動く（章ローカル優先）。ガイドブック原稿で本機能を解説する際に `data/physics_books/` へ移す判断は著者に委ねる
- `lib/vivlio_starter/cli/pre_process/data_render/` 配下の未参照 3 ファイル（gem 移行前の残骸）は本件と独立に削除してよい（任意クリーンアップ。削除時は `rake test` で無参照を確認）
- 単章ビルド（`:single`）も Step 1（最適化）と前処理を通るため追加対応不要。`--no-resize` 時は data/ の png/jpg が WebP 化されないが、変種解決が実在拡張子を採るため表示は成立する
