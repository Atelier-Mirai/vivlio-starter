# CLI Token Shorthand Specification (Simplified)

## 1. 目的

CLI 引数（`1-3`, `05-slug` など）の解釈ロジックが各コマンドに散在している現状を解消し、**正規化 (Normalization)** と **カタログ照合 (Resolution)** の共通レイヤを提供する。

## 2. 核心データ構造

Ruby 4.0+ の `Data.define` を用い、後続処理に必要な情報を不変オブジェクトとして保持する。

```ruby
# token_shorthand/data.rb
module TokenShorthand
  # 解決済みエントリ。
  # @param number [String] ゼロ埋め済みの章番号 (例: "01")
  # @param slug   [String, nil] スラッグ (例: "intro")
  # @param kind   [Symbol, nil] 章種別 (:chapter, :preface 等)
  # @param path   [String, nil] ファイルパス
  # @param exists [Boolean] catalog.yml に存在するかどうか
  Entry = Data.define(:number, :slug, :kind, :path, :exists)
end
```

## 3. トークン解釈ルール

複雑なバリエーションは廃止し、次の 3 ルールに従う。

1. **ゼロ埋め (Zero-padding)**: 数字単体、または数字から始まるトークンは 2 桁に正規化する。
   - `1` → `01`
   - `1-intro` → `01-intro`
2. **レンジ展開 (Range Expansion)**: `n-m` 形式を連続番号へ展開する。降順も許容する。
   - `1-3` → `['01','02','03']`
   - `10-8` → `['10','09','08']`
3. **分解 (Decomposition)**: `NN-slug` 形式を `number: 'NN'`, `slug: 'slug'` に分離する。拡張子付きも同様。
   - `01-intro.md` → `01-intro`

## 4. 共通 API: TokenShorthand::Resolver

Resolver は「入力の正規化」と「catalog.yml の照合」に専念する。

```ruby
module TokenShorthand
  class Resolver
    # @param tokens [Array<String>] ARGV 等の生入力
    # @param catalog_entries [Array<Struct/Data>] 既存章のリスト
    # @return [Array<Entry>] 解決済み Entry の配列
    def self.resolve(tokens:, catalog_entries:)
      # 1. tokens を正規化・レンジ展開してフラット化
      # 2. catalog_entries と照合し Entry を生成
      # 3. catalog 未登録は exists: false で返す
    end
  end
end
```

## 5. 実装・エラー運用の指針

### 5.1 ポリシーの分離

Resolver 自体は「未知の章を許可するか」などのポリシーを持たない。

- `vs build`: `exists: false` が含まれていたらエラー表示して中断する。
- `vs create`: `exists: false` であることを確認してから作成処理へ進む。

### 5.2 特殊ファイルの除外

`.cache/**` や `_toc.md` などの特殊ファイルは本レイヤの対象外。必要なコマンド（例: clean）が個別にスキャンし、共通レイヤの複雑化を防ぐ。

### 5.3 依存関係

- **CatalogLoader**: `catalog.yml` を読み込み、単純な構造体の配列を Resolver に渡す。
- **TokenShorthand::Resolver**: 渡されたデータと入力を照合する。