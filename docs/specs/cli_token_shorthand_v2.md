# CLI Token Shorthand v2（最小仕様）

本ドキュメントは、CLI トークンの **正規化 (Common.normalize_tokens)** と **CatalogLoader の最小インターフェイス** のみを定義する。特殊ファイルや allow フラグは扱わず、「全コマンドが同じ正規化・同じ catalog 参照を共有する」ための土台を整えることが目的。

---

## 1. 目的

1. `vs build` / `metrics` / `pre_process` / `post_process` / `entries` / `delete` / `rename` / `create` など、すべての CLI が **Common.normalize_tokens** を経由するよう統一する。
2. `CatalogLoader` を「catalog.yml → Data 構造」へ変換する薄い層として明文化し、Resolver/CLI から同じ API を参照できるようにする。
3. この 2 点を満たすことで、将来の Resolver 拡張（allow_new 等）を安全に段階実装できる状態を整える。

---

## 2. Common.normalize_tokens

| フェーズ | 内容 | 代表例 |
| --- | --- | --- |
| 入力整形 | `Array(tokens)` → `String` 配列化。`,`・空白で split、空要素除去 | `['1, 2']` → `['1','2']` |
| パス剥離 | `contents/` プレフィクスやサブディレクトリ、拡張子 `.md/.html/.pdf/.yml` を除去 | `contents/01/foo.md` → `01` |
| ゼロ埋め | 数値のみ（または先頭数値）を 2 桁に統一 | `1` → `01`、`1-intro` → `01-intro` |
| slug 分解 | `01-foo`, `01_foo`, `01-foo-bar` を `01-foo` に正規化 | `1-Foo.md` → `01-foo` |
| レンジ展開 | `01-03` → `['01','02','03']`。降順は反転処理 | `10-8` → `['08','09','10']` |
| 重複排除 | 展開後の配列を左から順に `uniq` | `['01','02','01']` → `['01','02']` |

### 2.1 出力形式

`normalize_tokens` は **文字列配列** を返す（各要素は `NN` もしくは `NN-slug`）。CLI はこの配列をそのまま Resolver に渡す。

```ruby
normalized = Common.normalize_tokens(ARGV)
entries    = TokenShorthand::Resolver.resolve(tokens: normalized)
```

### 2.2 実装上の注意

1. 各 CLI に散在しているゼロ埋め・レンジ展開・slug 区切りのコードは削除し、`Common.normalize_tokens` 呼び出しに置き換える。
2. 正規化中に例外が発生した場合は元トークンを返し、既存挙動との互換性を保つ。
3. レンジ展開結果は `String` だけで構成し、後段の比較や Resolver への受け渡しを単純にする。

---

## 3. CatalogLoader の最小仕様

CatalogLoader は `config/catalog.yml` を読み、Resolver が利用する `Data` 構造を返す。

```ruby
module TokenShorthand
  CatalogEntry = Data.define(:number, :slug, :basename, :path, :kind, :exists)

  class CatalogLoader
    def initialize(path = 'config/catalog.yml', contents_dir: 'contents')
      @path = path
      @contents_dir = contents_dir
    end

    def entries
      # YAML.load_file(@path)
      # => Hash を CatalogEntry 配列へ変換
    end
  end
end
```

### 3.1 フィールド定義

| フィールド | 説明 | 例 |
| --- | --- | --- |
| `number` | ゼロ埋め済み章番号 (`String`) | `'01'` |
| `slug` | `nil` 可 | `'intro'` |
| `basename` | `"01-intro"` | `'01-intro'` |
| `path` | `contents/01-intro.md` | `'contents/01-intro.md'` |
| `kind` | `:preface`, `:chapter`, `:appendix`, `:postface` | `:chapter` |
| `exists` | `File.exist?(path)` の真偽 | `true` |

### 3.2 処理手順

1. catalog.yml の PREFACE / CHAPTERS / APPENDICES / POSTFACE を順に読み、`basename` 配列を作る。
2. `basename` から `number` と `slug` を抽出し、フィールドを埋める。
3. `number` の範囲 (00 / 01-89 / 90-98 / 99) に応じて `kind` を割り振る。
4. YAML 読み込み失敗時は警告を出しつつ空配列を返す（既存 CLI と同挙動）。

---

## 4. Resolver との接続（参考）

v2 では Resolver の細部は扱わないが、CLI からの呼び出し順序を統一する。

1. `tokens = Common.normalize_tokens(raw_tokens)`
2. `catalog = TokenShorthand::CatalogLoader.new.entries`
3. `TokenShorthand::Resolver.resolve(tokens:, catalog_entries: catalog)`

allow_new / allow_slug_only などのポリシーは旧仕様（または今後の v3）で定義する。

---

## 5. 移行ステップ（最小）

1. **正規化の横断置換**: 既存 CLI の自前正規化ロジックを `Common.normalize_tokens` に差し替える。
2. **CatalogLoader 導入**: catalog.yml を参照する処理を `CatalogLoader.entries` に統一する。
3. **Regression**: `rake test` と主要 CLI の手動試験で動作確認。

上記が完了すれば「正規化 + catalog 読み込み」の共通化が達成され、以後の Resolver 拡張は別仕様（v3 以降）に切り出せる。
