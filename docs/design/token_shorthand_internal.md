# TokenShorthand Resolver 内部設計書

## 1. アーキテクチャ概要

### 1.1 コンポーネント構成
- **TokenShorthand::CatalogLoader**  
  `config/catalog.yml` を読み込み、章番号・slug・種別など最小限のメタデータを `TokenShorthand::Data::CatalogEntry` として返す。`.cache` や `_*.pdf` など特殊ファイルは扱わない。
- **TokenShorthand::Resolver**  
  CLI から渡される生トークンを正規化し、catalog 照合・ポリシー判定・特殊ファイル列挙を一括で担う。戻り値は `TokenShorthand::Data::Entry` の配列。
- **TokenShorthand::Data**  
  Catalog/Entry 向けの不変データ構造を `Data.define` で提供し、CLI 間で共通化する。
- **TokenShorthand::Errors**  
  CLI が rescue 可能なドメイン固有エラー（UnknownChapterToken など）をまとめる。

### 1.2 呼び出しフロー
```
CLI command (e.g. vs metrics)
        │
        ▼
TokenShorthand::Resolver.resolve(
  tokens: ARGV positionals,
  catalog_entries: CatalogLoader.entries,
  allow_new:, allow_cache:, ...
)
        │
        ▼
Array<TokenShorthand::Data::Entry>
        │
        ▼
downstream command logic (metrics/build/etc.)
```

### 1.3 遅延列挙ポリシー
- CatalogLoader は O(n) で章情報のみを返す。
- Resolver は `allow_cache`, `allow_auxiliary`, `allow_metrics_cache` などのフラグを見て必要になった場合のみ `.cache/**` や `_*.pdf` を列挙する。
- 特殊ファイル列挙は `resolve_auxiliary_entries`, `resolve_cache_entries`, `resolve_metrics_cache_entries` に分離し、呼び出し毎にメモ化（Ruby memo ではなくローカル変数再利用）で負荷を抑える。

## 2. API リファレンス

### 2.1 `TokenShorthand::Resolver.resolve`
```ruby
TokenShorthand::Resolver.resolve(
  tokens:,
  catalog_entries: nil,
  allow_new: false,
  allow_slug_only: false,
  allow_missing_slug: false,
  allow_cache: false,
  allow_auxiliary: false,
  allow_metrics_cache: false,
  contents_dir: Common::CONTENTS_DIR,
  cache_dir: Common.cache_dir,
  metrics_cache_dir: '.cache/metrics'
) => Array<TokenShorthand::Data::Entry>
```

#### 主要フラグ
| フラグ | 役割 | 代表 CLI |
| --- | --- | --- |
| `allow_new` | catalog に無い番号/slug でも仮想 Entry を生成 | `vs create`, `vs rename` |
| `allow_slug_only` | slug 単独指定を許可 | 今後の補助 CLI（例: `vs rename slug-only`） |
| `allow_missing_slug` | 番号のみ指定を許可（slug は nil） | `vs build 01`, `vs metrics 01` |
| `allow_cache` | `.cache/vs/**` などの出力を列挙 | `vs clean`, `vs build` |
| `allow_auxiliary` | `_titlepage.md`, `_toc.md` など補助ファイルを列挙 | `vs build`, `vs clean` |
| `allow_metrics_cache` | `.cache/metrics/*.yml` を列挙 | `vs metrics` |

#### 返却 Struct (`TokenShorthand::Data::Entry`)
| フィールド | 説明 |
| --- | --- |
| `number` | 2 桁ゼロ埋めの章番号（無い場合は nil） |
| `slug` | 章 slug（補助ファイルではベース名に準拠） |
| `kind` | `:preface`, `:chapter`, `:appendix`, `:postface`, `:auxiliary`, `:cache`, `:metrics_cache` など |
| `basename` | `01-life` や `_toc` など拡張子無しの名称 |
| `path` | 実ファイルパス（補助ファイルは `_toc.md` 等の相対） |
| `ext` | `.md`, `.pdf`, `.yml`, `.html` など |
| `exists` | `File.exist?` 判定結果。新規作成時は false になり得る |
| `catalog_entry` | catalog 起源の `Data::CatalogEntry`（新規や特殊ファイルは nil） |
| `special?` | 補助/キャッシュ/metrics cache を true に設定 |

#### 正規化の動作例
- `"1-foo"` → `number: "01"`, `slug: "foo"`, `basename: "01-foo"`, `kind: :chapter`
- `"01"` → `number: "01"`, `slug: nil`（`allow_missing_slug: true` の場合に有効）
- `"1-3"` → レンジ展開後に `['01', '02', '03']` を順に解決
- `"foo"` → catalog から番号を逆引きし `number: "04"`（例）、`slug: "foo"`（`allow_slug_only: true` 時）

#### コード例（基本）
```ruby
result = TokenShorthand::Resolver.resolve(
  tokens: ['1-foo'],
  catalog_entries: TokenShorthand::CatalogLoader.new.entries,
  allow_missing_slug: true
)

entry = result.first
# => #<TokenShorthand::Data::Entry number="01", slug="foo", basename="01-foo", ...>
```

### 2.2 CatalogLoader API
```ruby
TokenShorthand::CatalogLoader.new(
  catalog_path = 'config/catalog.yml',
  contents_dir: Common::CONTENTS_DIR
)
  # => #<CatalogLoader>
loader.entries => Array<TokenShorthand::Data::CatalogEntry>
loader.catalog_exists? => Boolean
```
- `Data::CatalogEntry` は Entry と同じフィールド構成（special? なし）で、Resolver がそのままコピーして使う。

### 2.3 エラークラス
| クラス | 発生条件 |
| --- | --- |
| `UnknownChapterToken` | catalog に存在しない番号/slug が指定された（かつ allow_new=false） |
| `MissingChapterSlug` | 新規作成を許可しているが slug が省略された |
| `MissingChapterNumber` | slug のみ指定を許可しておらず番号が不足、または slug 重複 |
| `UnsupportedSpecialFile` | 許可していない特殊ファイルを指定した |

## 3. 実装ガイド

### 3.1 CLI から Resolver を利用する基本手順

**例: `vs awesome 1-foo` の実装断片**

```ruby
# lib/vivlio/starter/cli/awesome.rb
module Vivlio
  module Starter
    module CLI
      module Awesome
        module_function

        def execute(token)
          entries = TokenShorthand::Resolver.resolve(
            tokens: [token],
            catalog_entries: TokenShorthand::CatalogLoader.new.entries,
            allow_missing_slug: true,
            allow_new: false
          )
          entry = entries.first
          Common.log_info("Processing #{entry.basename}")
          # … awesome 固有の処理 …
        rescue TokenShorthand::Errors::Error => e
          Common.log_error(e.message)
          exit(1)
        end
      end
    end
  end
end
```

1. **トークン収集**: CLI で受け取った文字列を `Array(tokens).compact` で整形。
2. **Resolver 呼び出し**: CLI の要件に合わせて `allow_*` フラグを設定し、catalog entries を共有する場合は呼び出し前にロード。
3. **結果の利用**: `TokenShorthand::Data::Entry` から `number`, `slug`, `basename`, `kind`, `special?` などを参照して処理。
4. **エラー処理**: `TokenShorthand::Errors::Error` を rescue し、`Common.log_error` と `exit(1)` で CLI の一貫性を保つ。

### 3.2 代表 CLI 移行パターン
| CLI | 旧挙動 | Resolver での設定 |
| --- | --- | --- |
| `vs create 01-foo` | ファイル存在チェックと slug 抽出を手作業 | `allow_new: true`, `allow_missing_slug: false` |
| `vs rename 01-foo 02-bar` | slug/番号の相互チェック | 入力側: `allow_new: true`, `allow_missing_slug: false`; 出力側: catalog entries で照合 |
| `vs build 01-03` | 章と補助ファイル、キャッシュを混在扱い | `allow_auxiliary: true`, `allow_cache: true` |
| `vs metrics 01` | metrics cache ファイル（`.cache/metrics/*.yml`）を参照 | `allow_metrics_cache: true`, `allow_missing_slug: true` |
| `vs clean cache` | `.cache` 配下を列挙して削除 | `allow_cache: true`, `allow_auxiliary: false`, `allow_new: false` |

### 3.3 新規 CLI 追加時のチェックリスト
1. 章トークン以外（補助ファイル、キャッシュ）が必要かを判断し、該当フラグを有効化。
2. 番号のみ／slug のみ入力を許可するかを明確化し、`allow_missing_slug`・`allow_slug_only` を設定。
3. 新規章を作成する可能性があるか（`allow_new`）。slug 必須なら `allow_missing_slug: false`。
4. Resolver から返る `Entry` をどのようにフィルタリングするか（`special?` チェックなど）。
5. CLI 実装で追加の検証が必要な場合（例: metrics cache の存在確認）、`entry.exists` を利用。

### 3.4 テスト観点
- **ユニットテスト** (`test/vivlio/starter/cli/token_shorthand/resolver_test.rb`):
  - 正規化（ゼロ埋め、範囲展開、slug 抽出）
  - 特殊ファイル解決（aux/cache/metrics）
  - `allow_*` フラグの組み合わせによる挙動差分
  - エラー発生パス
- **CLI テスト**: metrics/delete/entries など Resolver を利用するコマンドで、未知トークンに対する SystemExit やエラーメッセージを検証。
- **統合テスト**（任意）: catalog.yml を含む実プロジェクトを用いて end-to-end に Resolver 変更が波及しないかを確認。

## 4. 拡張パターン

### 4.1 新カテゴリの追加（索引・用語集など）
1. `allow_<new_flag>` の追加を検討。例: 用語集キャッシュなら `allow_glossary_cache` を Resolver オプションに導入。
2. 特殊ファイル列挙メソッドを新設（`resolve_glossary_cache_entries` 等）し、`special_allowed?` に判定を追加。
3. `TokenShorthand::Data::Entry#kind` に新しい種類を追加し、CLI 側で条件分岐可能にする。
4. 仕様書の「Open Questions」にある通り、付録や別カテゴリも Resolver フラグ駆動で遅延列挙する。

### 4.2 フラグの組み合わせ最適化
- CLI 間で共通するオプションセットは `Common::TokenResolverOptions`（例）を作り、`DEFAULT_OPTIONS` に merge する形で共有可能。
- 将来的に DSL 化（`TokenResolverPolicy.for(:metrics)`）すると、CLI 実装がより単純になる。

### 4.3 メタデータ拡張
- `TokenShorthand::Data::Entry` にフィールドを追加する際は、Resolver で一元的に設定し、既存 CLI が参照するか否かに関わらず値を埋めておく。
- 例: `source`（catalog/new/cache など）や `input_token`（元の生入力）を追加すれば、デバッグログの改善に役立つ。

## 5. 今後のタスク
- Resolver ポリシーを CLI 単位で共通化する `Policy` 層の導入検討。
- `allow_slug_only` を活用する CLI の追加（例: slug だけで章を特定する管理系コマンド）。
- `_index_matches.yml` や `_index_review.md` など索引機能が生成するファイルを Resolver の特殊ファイルリストに組み込むかの判断。
- 本設計書の内容を開発者向け Wiki に転載し、Pull Request テンプレートに「Resolver フラグ確認チェック」を追加する。
