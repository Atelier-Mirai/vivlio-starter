# Vivlio Starter 前提条件違反テスト 仕様書

| 項目 | 内容 |
|---|---|
| 文書名 | 前提条件違反テスト（Precondition Guard）仕様書 |
| 対象 | vivlio-starter Gem（v1.0.0-beta 以降） |
| 目的 | 各コマンド実行前に前提条件を検証し、致命的な不整合を早期に弾く |
| 関連 | `vs preflight` / `vs doctor` との役割分担を含む |
| 改訂 | 2026-06-11 実装に先立ち現行コードベースへ整合（catalog パス・TokenResolver 再利用・🔴/🟡 アイコン規約・OrphanFileCheck の preflight 限定） |

---

## 1. 背景と目的

### 1.1 解決したい問題

`catalog.yml` に宣言された章ファイル（例: `89-bugfix-check`）が `contents/` に実在しない場合、`vs build` がスレッド内で `Errno::ENOENT` を発生させ、利用者に大量のスタックトレースを提示してしまう。（解消済み）

これは **参照整合性エラー（前提条件違反）** であり、本来はコマンド本処理に入る前に検出・通知すべきものである。

### 1.2 目的

1. 各コマンドが「成立するための最低限の前提条件」を実行前に検証する
2. 違反時はスタックトレースではなく、簡潔で行動可能なメッセージを提示する
3. 検証ロジックを **Check オブジェクト**として共通化し、`vs preflight` からも再利用する

### 1.3 用語

| 用語 | 定義 |
|---|---|
| 前提条件違反 | コマンド成立に必要な前提（ファイル・設定・環境）が満たされない状態 |
| 参照整合性エラー | 宣言（catalog.yml 等）と実体（ファイルシステム）が乖離した状態 |
| Guard | コマンド冒頭で前提条件をまとめて検証する仕組み |
| Check | 単一の前提条件を検証する再利用可能なオブジェクト |
| 孤立ファイル | contents/ に存在するが catalog.yml に未登録のファイル |

---

## 2. 設計方針

### 2.1 二層構造

```
[ Guard 層 ]  各コマンド冒頭で「致命的な前提」だけを高速検証
                ↓ 違反があれば GuardError を raise（本処理に入らない）

[ Check 層 ]  単一責務の検証オブジェクト群（再利用可能）
                ↑ vs preflight / vs doctor からも同じ Check を利用
```

### 2.2 役割分担

| 仕組み | 役割 | 性質 |
|---|---|---|
| 各コマンドの Guard | コマンドが成立するか「だけ」を確認 | 軽量・高速・致命的なものに限定 |
| `vs preflight` | 原稿エラーの網羅的な事前チェック | 詳細・提案あり（明示実行） |
| `vs doctor` | 環境診断・不足ツールのセットアップ | 環境寄り（明示実行） |

> Guard は「弾く」、preflight/doctor は「丁寧に診断する」。同じ Check を共有しつつ、呼び出し側で粒度を変える。

---

## 3. Check 一覧

各 Check は単一責務とし、`validate` が違反メッセージの配列（空なら合格）を返す。

| Check 名 | 検証内容 | 違反時の分類 |
|---|---|---|
| `CatalogFileCheck` | `config/catalog.yml` が存在するか | 前提条件違反 |
| `CatalogEntriesCheck` | catalog 参照先の `.md` がすべて実在するか | 参照整合性エラー |
| `OrphanFileCheck` | contents/ の未登録ファイル（警告扱い・preflight 専用） | 参照整合性エラー（警告） |
| `ContentsDirCheck` | `contents/` ディレクトリが存在するか | 前提条件違反 |
| `VivliostyleConfigCheck` | `vivliostyle.config.js` が存在するか | 前提条件違反 |
| `NodeCheck` | Node.js が利用可能か | 環境前提違反 |
| `PdfArtifactCheck` | 対象 PDF（build 成果物）が存在するか | 前提条件違反 |
| `ImagesDirCheck` | `images/` ディレクトリが存在するか | 前提条件違反 |
| `ProjectRootCheck` | Vivlio Starter プロジェクト直下（`config/book.yml` あり）で実行されているか | 前提条件違反 |

> カタログの解析は YAML を独自にパースせず、既存の `TokenResolver::Resolver`（部タイトル・ショートハンド・セクション対応済み）を再利用する。`CatalogLoader` と検証ロジックが二重化するのを防ぐため。

---

## 4. コマンド × Check 対応表

凡例: ◎=必須（違反で停止） / ○=推奨 / △=警告のみ / —=不要

| コマンド | ProjectRoot | CatalogFile | CatalogEntries | ContentsDir | VivliostyleConfig | Node | PdfArtifact | ImagesDir |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| **new** | — | — | — | — | — | — | — | — |
| **import** | — | — | — | — | — | — | — | — |
| **pdf:read** | ○ | — | — | — | — | — | ◎ | — |
| **doctor** | — | — | — | — | — | — | — | — |
| **clean** | ○ | — | — | — | — | — | — | — |
| **create** | ◎ | ○ | — | ◎ | — | — | — | — |
| **delete** | ◎ | ○ | — | ◎ | — | — | — | — |
| **rename** | ◎ | ◎ | — | ◎ | — | — | — | — |
| **renumber** | ◎ | ◎ | — | ◎ | — | — | — | — |
| **lint** | ◎ | ◎ | ○ | ◎ | — | — | — | — |
| **metrics** | ◎ | ○ | — | ◎ | — | — | — | — |
| **index:auto** | ◎ | ◎ | ○ | ◎ | — | — | — | — |
| **index:apply** | ◎ | ◎ | — | ◎ | — | — | — | — |
| **cover** | ◎ | — | — | — | — | — | — | ○ |
| **resize** | ◎ | — | — | — | — | — | — | ◎ |
| **preflight** | ◎ | — | — | — | — | — | — | — |
| **build** | ◎ | ◎ | ◎ | ◎ | ◎ | ◎ | — | — |
| **open** | ○ | — | — | — | — | — | ◎ | — |
| **pdf:compress** | ○ | — | — | — | — | — | ◎ | — |
| **pdf:pages** | ○ | — | — | — | — | — | ◎ | — |
| **pdf:rasterize** | ○ | — | — | — | — | — | ◎ | — |

### 4.1 設計上の補足

- **new / import / doctor** は前提条件が薄い（むしろ「無い状態」から始める）ため Guard 対象外。
- **build** が最重要。catalog 参照整合性（今回のエラー）を ◎ として必ず検証する。
- **○（推奨）** は `RelaxedCheck` デコレータで :error を :warn に格下げして実行する（警告は出すが停止しない）。
- **PdfArtifactCheck は明示パス指定時のみ検証**する。`vs open` / `vs pdf:read` および pdf 系の引数省略時は「ビルド生成物の自動選択」「sources/ 探索」「章トークン解決」がドメイン層に実装済みのため、解決ロジックを Check に複製せず、失敗時のメッセージもドメイン層（`MissingPdfError` 等）に委ねる。
- **resize** は `vs resize <dir>` で任意ディレクトリを対象にできるため、ImagesDir ◎ は既定の `images/` を対象とする場合のみ適用する。
- **OrphanFileCheck** は **preflight 専用の警告**とし、build では実行しない。catalog.yml で章をコメントアウトして除外するのはマニュアル記載の正規ワークフローであり、build のたびに未登録章の警告を出すと意図的な除外に対するノイズになるため。
- **preflight** は Phase 4 で全 Check（ProjectRoot / CatalogFile / CatalogEntries / ContentsDir / VivliostyleConfig / Node / OrphanFile）を網羅実行する。`Guard.run!` は全違反をログしてから停止判定するため、複数の問題を一度に報告できる。
- **既存の二重防御**: `root_command#ensure_project_context!` が new/doctor/help 以外の全コマンドで `Common.ensure_configured!`（config 4ファイルの存在・妥当性検証）を実行している。コマンド単位の Guard はこれと重複する部分があるが、`Command#call` を直接呼ぶ経路（テスト等）でも前提が保証される自己完結性を優先して併存させる。

---

## 5. インターフェース仕様

### 5.1 Check の契約

```ruby
# すべての Check が満たすべき契約（lib/vivlio_starter/cli/guards/base_check.rb）
module VivlioStarter::CLI::Guards
  # 単一の違反。detail は Common.log_error / log_warn の detail: に渡され、
  # 2行目以降としてインデント表示される（logging_spec.md 準拠）。
  Violation = Data.define(:severity, :message, :detail) # severity: :error / :warn

  # 単一の前提条件を検証する。
  # @return [Array<Violation>] 違反の配列（空配列なら合格）
  class BaseCheck
    def validate = raise NotImplementedError
  end
end
```

### 5.2 Guard の契約

```ruby
# lib/vivlio_starter/cli/guards.rb
module VivlioStarter::CLI::Guards
  class GuardError < StandardError; end

  module Guard
    module_function

    # @param checks [Array<BaseCheck>] 実行する Check 群
    # @raise [GuardError] :error 違反が 1 件以上あれば停止
    # ログ出力は Common.log_warn（🟡）/ Common.log_error（🔴）に委譲する。
    def run!(*checks)
      violations = checks.flat_map(&:validate)
      warns, errors = violations.partition { it.severity == :warn }

      warns.each  { Common.log_warn(it.message, detail: it.detail) }
      errors.each { Common.log_error(it.message, detail: it.detail) }

      return if errors.empty?

      raise GuardError,
            "前提条件を満たしていません（エラー #{errors.size} 件 / 警告 #{warns.size} 件）"
    end
  end
end
```

GuardError は各 Samovar コマンドの `call` で捕捉し、`Common.log_error(e.message)` の後に終了コード 1 を返す（スタックトレースは表示しない）。

---

## 6. 実装例（参照実装）

### 6.1 CatalogEntriesCheck（今回のエラーの再発防止）

カタログ解析は `TokenResolver::Resolver` に委譲する（`config/catalog.yml` のセクション・部タイトル・ショートハンドを再実装しない）。catalog.yml 自体の不在は `CatalogFileCheck` の責務のため、ここでは合格扱いとする。

```ruby
# lib/vivlio_starter/cli/guards/catalog_entries_check.rb
module VivlioStarter::CLI::Guards
  class CatalogEntriesCheck < BaseCheck
    def validate
      return [] unless File.file?(Build::CatalogLoader::CATALOG_FILE)

      missing = TokenResolver::Resolver.new.resolve.reject(&:exists?)
      return [] if missing.empty?

      [Violation.new(
        severity: :error,
        message: 'config/catalog.yml に記載されている章ファイルが contents/ に見つかりません',
        detail: missing.map { "- contents/#{it.basename}.md" } +
                ['対処: catalog.yml の該当行を削除するか原稿を作成してください（vs delete <章番号> で一括削除可）']
      )]
    end
  end
end
```

### 6.2 OrphanFileCheck（警告のみ・preflight 専用）

未登録ファイルは1件ずつではなく **1つの警告にまとめて** detail に列挙する（章のコメントアウト除外は正規ワークフローのため、騒がしくしない）。

```ruby
# lib/vivlio_starter/cli/guards/orphan_file_check.rb
module VivlioStarter::CLI::Guards
  class OrphanFileCheck < BaseCheck
    def validate
      return [] unless File.file?(Build::CatalogLoader::CATALOG_FILE)

      catalog_basenames = TokenResolver::Resolver.new.resolve.map(&:basename)
      orphans = contents_basenames - catalog_basenames
      return [] if orphans.empty?

      [Violation.new(
        severity: :warn,
        message: "catalog.yml に未登録の原稿が #{orphans.size} 件あります（ビルド対象外）",
        detail: orphans.map { "- contents/#{it}.md" }
      )]
    end

    private

    # アンダースコア始まり（_titlepage 等のシステムページ）は対象外
    def contents_basenames
      Dir.glob(File.join(Common::CONTENTS_DIR, '*.md'))
         .map { File.basename(it, '.md') }
         .reject { it.start_with?('_') }
    end
  end
end
```

### 6.3 コマンドへの組み込み（build）

```ruby
# samovar/build_command.rb の call 冒頭
def call
  return print_usage if options[:help]

  Guards::Guard.run!(
    Guards::ProjectRootCheck.new,
    Guards::CatalogFileCheck.new,
    Guards::CatalogEntriesCheck.new,   # ← 今回のエラーをここで停止
    Guards::ContentsDirCheck.new,
    Guards::VivliostyleConfigCheck.new,
    Guards::NodeCheck.new
  )

  # ── 以降は本処理（前提が揃っていることが保証される）──
rescue Guards::GuardError => e
  common.log_error(e.message)
  1
end
```

---

## 7. テスト仕様（Minitest）

### 7.1 Check 単体テスト

| テスト ID | 対象 | 前提状態 | 期待結果 |
|---|---|---|---|
| GC-01 | CatalogEntriesCheck | 全参照先が実在 | 違反 0 件 |
| GC-02 | CatalogEntriesCheck | 1 件欠落（89-bugfix-check.md なし） | :error 1 件・detail に該当パスを含む |
| GC-03 | CatalogEntriesCheck | catalog.yml 自体がない | 違反 0 件（CatalogFileCheck の責務） |
| GC-04 | OrphanFileCheck | 未登録ファイル 1 件 | :warn 1 件・detail に該当パスを含む |
| GC-05 | CatalogFileCheck | catalog.yml なし | :error 1 件 |
| GC-06 | NodeCheck | node コマンドなし（runner DI で代替） | :error 1 件 |

### 7.2 Guard 統合テスト

| テスト ID | シナリオ | 期待結果 |
|---|---|---|
| GG-01 | error 違反あり | GuardError を raise・件数メッセージ |
| GG-02 | warn のみ | raise しない・warn ログ出力 |
| GG-03 | 違反なし | raise しない・本処理へ進む |

### 7.3 参照実装テスト（GC-02）

catalog.yml は実際の構造（PREFACE / CHAPTERS / APPENDICES / POSTFACE）で書き、
一時ディレクトリへ chdir して検証する。

```ruby
# test/vivlio_starter/cli/guards/catalog_entries_check_test.rb
def test_should_report_error_with_missing_entry_path_in_detail
  with_temp_project do
    write_catalog(chapters: %w[11-intro 89-bugfix-check])
    write_content('11-intro')          # 89-bugfix-check.md は作らない

    violations = Guards::CatalogEntriesCheck.new.validate

    assert_equal 1, violations.size
    assert_equal :error, violations.first.severity
    assert violations.first.detail.any? { it.include?('89-bugfix-check.md') }
  end
end

def test_should_pass_when_all_entries_present
  with_temp_project do
    write_catalog(chapters: %w[11-intro])
    write_content('11-intro')

    assert_empty Guards::CatalogEntriesCheck.new.validate
  end
end
```

---

## 8. エラー出力フォーマット規約

プロジェクトのログ規約（🔴/🟡 統一・`Common.log_*` 経由・`detail:` インデント）に従う。⚠️/❌ は使用しない。

| 種別 | アイコン | 出力 | 形式 |
|---|---|---|---|
| エラー | 🔴 | `Common.log_error(msg, detail:)` | `🔴 <何が>` + detail 行に `<どこが>` `<どうすべきか>` |
| 警告 | 🟡 | `Common.log_warn(msg, detail:)` | `🟡 <何が>` + detail 行に `<推奨対応>` |
| 要約 | 🔴 | GuardError 捕捉側で `Common.log_error` | `🔴 前提条件を満たしていません（エラー N 件 / 警告 M 件）` |

### 8.1 出力例

```
🔴 config/catalog.yml に記載されている章ファイルが contents/ に見つかりません
        - contents/89-bugfix-check.md
        対処: catalog.yml の該当行を削除するか原稿を作成してください（vs delete <章番号> で一括削除可）
🔴 前提条件を満たしていません（エラー 1 件 / 警告 0 件）
```

> スタックトレースは `-v / --verbose` 指定時のみ追加出力する。通常時は上記の簡潔な表示に留める。

---

## 9. 段階的導入計画

| フェーズ | 内容 | 優先度 | 状況 |
|---|---|---|---|
| Phase 1 | `CatalogFileCheck` / `CatalogEntriesCheck` を build に導入（今回の再発防止） | 最高 | ✅ 実装済み（2026-06-11） |
| Phase 2 | Guard / Check 基盤の整備、build へ全 Check 適用 | 高 | ✅ 実装済み（2026-06-11） |
| Phase 3 | lint / metrics / index 系・create / delete / rename / renumber / cover / resize / clean / pdf 系 / open へ展開（`RelaxedCheck` / `ImagesDirCheck` / `PdfArtifactCheck` / `Guards.precheck` を追加） | 中 | ✅ 実装済み（2026-06-11） |
| Phase 4 | `vs preflight` を Check 層の上に再構成（全 Check の網羅的診断） | 中 | ✅ 実装済み（2026-06-11） |
| Phase 5 | `vs doctor` で設定ファイル復元・プラグイン外部ツール診断統合（`ConfigValidityCheck` を共有）。詳細は別仕様書 `doctor-restore-and-plugin-tools-spec.md` | 低 | ✅ 実装済み（2026-06-11） |

---

## 10. 補足: スレッド内例外との関係

今回のエラーは `section_builder.rb` の並列処理（Thread）内で発生し `report_on_exception` によりスタックトレースが表示された。Guard を build 冒頭に置けば**並列処理に入る前に停止**するため、本質的な再発防止になる。

なお `UnifiedBuildPipeline#run` 冒頭の `ensure_entry_files_exist!`（実装済み）は、Guard をすり抜けた異常（コマンド開始後のファイル削除・pipeline を直接呼ぶ経路）に対する**二段目の保険**としてそのまま残す。Guard（コマンド層・カタログ全体）と pipeline 検証（ビルド対象 entries のみ）は検証範囲が異なる補完関係にある。

さらにスレッド内にもフォールバックの `rescue` を残しておくと、実行中のファイル削除などに対しても簡潔なメッセージを返せる。

```ruby
rescue Errno::ENOENT => e
  file = e.message[/@ rb_sysopen - (.+)$/, 1] || e.message
  logger.error "📄 ファイルが見つかりません: #{file}"
  raise
```
