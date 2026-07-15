# 設定ファイルを経由しない直接ビルドコマンド 仕様書

> 作成日: 2026-07-12
> ステータス: **提案（未実装・レビュー待ち）**
> 対象: PLANNED.md:17 [High]「設定ファイルを経由しない直接ビルドコマンド」。`vs build myawesome.md --theme blue` のように `book.yml` / `catalog.yml` を介さず単一 Markdown を PDF 化する軽量経路
> 決定事項（本仕様の提案）:
> - **入口は `vs build` に相乗り**（新コマンドを増やさない）。ターゲットが「実在する `.md` ファイルパス 1 件」のときだけ直接モードへ分岐
> - **実装は「一時ワークスペース方式」（案A）**: 一時ディレクトリに最小プロジェクト相当（stylesheets ＋ 既定 CONFIG ＋ 原稿 1 章）を組み立て、既存の `:single` パイプラインを chdir して流用する。専用パイプライン新設（案B）は採らない——前処理・VFM 変換・Vivliostyle 呼び出し・リネームの実証済みコードを 100% 再利用でき、回帰リスクが最小
> - **出力は閲覧用 PDF のみ**。`--print_pdf` / `--epub` / `--kindle` 相当の分岐は設けない（PLANNED の要件どおり）
> - **章種は常に本章（chapter）扱い**。`contents/00-preface.md` を渡されても preface 扱いにしない（章名解決・catalog 参照を一切行わないという要件の帰結）
> 関連: `lib/vivlio_starter/cli/samovar/build_command.rb`（分岐の入口）, `lib/vivlio_starter/cli/samovar/root_command.rb:130`（`PROJECTLESS_COMMANDS` / `ensure_project_context!`）, `lib/vivlio_starter/cli/build/pipeline.rb`（`:single` モード）, `lib/vivlio_starter/cli/common.rb:169`（既定値マージ済み CONFIG 生成）, `lib/vivlio_starter/cli/new.rb:16`（`SCAFFOLD_SOURCE`）, `lib/vivlio_starter/cli/pre_process/book_settings_css.rb`（テーマ色の CSS 反映機構）

## 0. 背景・問題

現状の `vs build` は必ずプロジェクト前提で動く:

- `RootCommand#ensure_project_context!`（root_command.rb:132）が `Common.ensure_configured!` を呼び、`config/book.yml` がないと起動すらしない
- `BuildCommand#call` は `ProjectRootCheck` / `CatalogFileCheck` / `CatalogEntriesCheck` / `ContentsDirCheck` の Guard を通し、ターゲットは `TokenResolver` で catalog 解決される（build_command.rb:86–93, 181–186）

そのため「書き捨ての Markdown 1 枚をとりあえず組版したい」「執筆前の企画メモを Vivlio Starter の見た目で PDF にしたい」という用途には `vs new` からのプロジェクト作成が必須で、敷居が高い。

## 1. 著者向け仕様

### 1.1 使い方

```bash
vs build myawesome.md                       # どこでも実行可（プロジェクト外 OK）
vs build ~/notes/idea.md --theme blue       # テーマカラー指定
vs build contents/00-preface.md --theme '#e91e63'   # プロジェクト内のファイルも直接指定可
```

- カレントディレクトリに `<元ファイルの basename>.pdf`（例 `myawesome.pdf`）を出力し、macOS ではビルド後に開く（既存 `PdfOpener` 流用）
- 入力 Markdown は**自己完結**を前提とする: `codes/` からのコードインクルード、QueryStream 記法、クロスリファレンス、索引・用語集は**非サポート**（記述されていたら 🟡 警告して素通し。§3.4）
- 画像参照は**入力 .md と同じディレクトリからの相対パス**のみ解決する（§2.4）。WebP 化などの画像最適化は行わない
- 章の扱いは常に「本章（01–89 chapter）」。見出し・柱・ページスタイルは chapter 用が適用される。ファイル名が `00-…` / `99-…` でも preface / postface 扱いにはならない
- タイトルは Markdown 先頭の `# 見出し`、なければファイル名（拡張子なし）

### 1.2 `--theme` オプション

- 形式は `--theme <color>` / `--theme=<color>`（Samovar 標準記法。PLANNED 記載の `--theme:blue` はコロン区切りだが、他オプションと揃えて空白/`=` 区切りとする）
- 値は `book.yml` の `theme.color` と同じ語彙: `yellow / orange / red / magenta / purple / indigo / navy / blue / cyan / teal / green / lime` ＋ HEX 記法（`'#ff0000'`）。検証は既存 `ThemeValidator` を流用し、未知の値は候補提示付きで 🔴 エラー（warning-messages の方針どおり before→after を添える）
- 省略時は既定の `yellow`
- 装飾スタイルは **`simple`（画像なし）固定**とする。`image` スタイルは扉絵・節絵アセットの生成/配置を伴い「軽量経路」の趣旨に反するため v1 では対象外（§6）

### 1.3 直接モードの発動条件と排他

| 入力 | 挙動 |
|---|---|
| `vs build 10-intro` / `vs build 10 12` | 従来どおり catalog 解決（変更なし） |
| `vs build myawesome.md`（実在ファイル） | **直接モード** |
| `vs build a.md b.md` | 🔴 エラー「直接ビルドは 1 ファイルのみ指定できます」 |
| `vs build a.md 10-intro` | 🔴 エラー（.md パスと章トークンの混在禁止） |
| `vs build nothere.md`（実在しない） | 🔴 エラー「ファイルが見つかりません」＋ 従来解釈（basename 解決）にはフォールバックしない |

判定規則: ターゲット文字列が `.md` で終わる場合は常に直接モードの候補とする（catalog 章の basename は拡張子を含まないため衝突しない）。

### 1.4 直接モードで有効なオプション

`--theme`（新設）, `--log`, `-h/--help` のみ。`--[no]-resize` / 品質プリセット / `--[no]-compress` / `--[no]-verify` / `--verify-links` / `--[no]-clean` は直接モードでは無効（指定されたら 🟡「直接ビルドでは無視されます」を 1 回通知）。

## 2. 実装

### 2.1 入口の分岐（build_command.rb）

- `options` に `option '--theme <color>', 'テーマカラー（直接ビルド専用）', key: :theme` を追加
- `#call` の Guard 実行**前**に `direct_mode?`（`targets.size == 1 && targets.first.end_with?('.md')` ほか §1.3 の排他判定）を評価し、真なら `run_direct_build` へ委譲。プロジェクト前提の Guard（ProjectRoot/CatalogFile/CatalogEntries/ContentsDir）は通さず、**`NodeCheck` のみ**実行する
- 通常モードで `--theme` が指定されたら 🟡「--theme は直接ビルド（.md 指定）専用です。book.yml の theme.color を編集してください」

### 2.2 プロジェクト文脈チェックの解除（root_command.rb）

`ensure_project_context!` は現状クラス単位（`PROJECTLESS_COMMANDS`）の判定のため、`BuildCommand` インスタンスが自分の引数から判断できるようにする:

```ruby
# root_command.rb
def ensure_project_context!(target)
  return if PROJECTLESS_COMMANDS.any? { |klass| target.is_a?(klass) }
  return if target.respond_to?(:projectless?) && target.projectless?   # 追加

  Common.ensure_configured!
end
```

`BuildCommand#projectless?` は `direct_mode?` を返す。プロジェクト内で実行された場合も CONFIG は**読み込まない**（book.yml の値に依存しない、が本機能の定義）。

### 2.3 一時ワークスペースの組み立てと CONFIG 差し替え

`run_direct_build` の手順:

1. `Dir.mktmpdir('vs-direct-')` にワークスペースを作成
2. **stylesheets**: gem 同梱スキャフォールド（`NewCommands::SCAFFOLD_SOURCE/stylesheets`）を丸ごとコピー。ただし**カレントがプロジェクトルート（`stylesheets/` と `config/book.yml` が実在）ならルートの `stylesheets/` を優先コピー**——推敲中の章をプロジェクトの見た目で軽量プレビューする用途を殺さないため（book.yml の値は使わない点は不変）
3. **config**: `config/` ディレクトリだけ作る（ファイルは置かない）。CONFIG は YAML を読まずに組み立てる:
   - `Common` に `build_direct_configuration(overrides)` を追加。既定値スキーマ（common.rb:169 の「book.yml に記述がなくても全セクション・既知キーが常に存在する」マージ機構）へ空 Hash を通し、`theme.style = 'simple'`・`theme.color = <--theme 値>`・`project.name = <basename>`・`book.main_title = <H1 or basename>`・`output.targets = ['pdf']` を上書きして frozen Data 化
   - 既存 `reload_configuration!` と同様に `CONFIG` 定数を差し替える内部 API（`Common.install_configuration!(data)`・テスト用に既存流儀へ合わせる）
4. **原稿**: 入力 .md を `contents/10-<元basename の slug 化>.md` へコピー。元ファイル名が `NN-slug.md` 形で NN が 01–89 ならその番号を保持、それ以外（番号なし・00・90–99）は `10` に付け替える（=常に chapter 扱い。§1.1）
5. `Dir.chdir(workspace)` して `TokenResolver::Entry` を 1 件手組みし、`UnifiedBuildPipeline.new(self, entries: [entry], mode: :single)` を実行（`BuildLock` はワークスペースが毎回異なるため実質無効だが、経路はそのまま通す）
6. 生成された `10-<slug>.pdf` を**呼び出し元 cwd の `<元basename>.pdf`** へ move（既存ファイルは上書き。`log_result` で報告）
7. `ensure` で chdir を戻し、一時ディレクトリを削除（`--log=debug` 時は削除せずパスを表示——トラブルシュート用）

> `Common` のパス定数（`CACHE_DIR` 等）は相対パスなので、chdir 方式によりビルド機構・`BookSettingsCss.generate!`（テーマ色→ `--theme-accent` の反映）・`VivliostyleConfigWriter` が**無改修**でワークスペース内に閉じる。これが案A の最大の利点。

### 2.4 画像参照の解決

入力 .md 内のローカル画像参照（URL・`data:` 以外）は、コピー時に**入力 .md の元ディレクトリ基準で実在確認**し:

- 実在 → ワークスペースの `images/10-<slug>/<ファイル名>` へコピー（既存の `ImagePathNormalizer` が章画像ディレクトリとして解決する従来経路に乗る）
- 不在 → そのまま（既存 normalizer が 🔴＋プレースホルダー data URI を出す従来動作）

### 2.5 単章ビルドとの差分（`:single` からの間引き）

`:single` のステップのうち直接モードでは:

- `optimize images` → スキップ（`--no-resize` 相当を固定）
- `prepare theme images` → 実行（`BookSettingsCss.generate!` がここで呼ばれ、`--theme` の色が効く）
- 前処理のうちコードインクルード・QueryStream・クロスリファレンスは**機構ごとスキップせず素通し**とする（原稿に記法がなければ no-op であり、分岐追加のほうが高コスト）。記法が検出された場合のみ 🟡「直接ビルドでは code-include / QueryStream / クロスリファレンスはサポートされません」（検出は前処理各ステップの既存エラー経路に任せ、メッセージだけ直接モード文言に差し替え）

## 3. テスト

Minitest・ruby-coding-rules skill 適用。

1. **分岐判定**（`build_command` 単体）: §1.3 の表の 5 ケース（catalog トークンとの排他・複数 .md 拒否・不在ファイル拒否）
2. **`projectless?` / `ensure_project_context!`**: .md 指定時に `ensure_configured!` が呼ばれない／通常時は呼ばれる
3. **CONFIG 組み立て**: `build_direct_configuration` が既定値全キーを持つ・`--theme` の色と HEX が `theme.color` に載る・未知色で `ThemeValidator` エラー
4. **ワークスペース組み立て**: 番号なし .md → `10-*.md`、`05-x.md` → 番号保持、`00-x.md` → `10-x.md`。画像の同伴コピー（実在/不在）
5. **結合（`rake test:layout` 側・任意）**: 一時ディレクトリで `vs build sample.md --theme blue` を実行し、cwd に `sample.pdf` が生まれる・`--theme-accent` が blue 系で CSS に反映されている（ワークスペースの book-settings.css を検査）

## 4. 手順（実装順序）

1. `Common.build_direct_configuration` ＋ CONFIG 差し替え API（§2.3-3）
2. `BuildCommand` の分岐・`projectless?`・`RootCommand` の 1 行（§2.1–2.2）
3. ワークスペース組み立て（§2.3–2.4）と PDF 回収
4. テスト（§3）→ `rake test`
5. ドキュメント: `README.md` のビルド節・`contents/` の該当章（build コマンド解説）に直接モードを追記。ヘルプ文言（`many :targets` の説明）更新
6. `ruby copy_to_scaffold.rb`（README 更新分の同期）

## 5. スコープ外・将来拡張

- **`image` スタイル（扉絵・節絵）**: 生成アセットの準備が重く軽量経路に反するため v1 は `simple` 固定。要望があれば `--style image` を後日検討
- **EPUB / print_pdf / Kindle 出力**: 要件により恒久的に対象外（オプション自体を設けない）
- **複数 .md の結合ビルド**: v1 対象外。`vs new` への誘導メッセージで代替
- **book.yml の部分的な尊重**（プロジェクト内実行時にフォント設定だけ拾う等）: 「設定ファイルを介さない」という定義が崩れるため行わない。プロジェクトの完全な見た目が要る場合は従来の `vs build <章番号>` を使う（エラーメッセージでも案内する）
