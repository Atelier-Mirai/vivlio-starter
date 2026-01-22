# TokenResolver 内部設計書

## 1. 設計思想
`TokenResolver` は、ユーザーからの曖昧な入力（Token）を、システムが安全に扱える厳格なデータ構造（Entry）に変換する「信頼できる唯一の情報源（Single Source of Truth）」である。

CLIコマンド側で複雑な正規表現やカタログ解析を繰り返す必要をなくし、「解決されたあとのデータに対して、何をしたいか」という業務ロジックに集中できる環境を提供する。

## 2. データ構造: `Entry`
Ruby 4.0 の `Data.define` による不変オブジェクト。

| 属性 | 型 | 内容 | 利用例 |
| :--- | :--- | :--- | :--- |
| `number` | String | 2桁ゼロ埋め済みの章番号 (`"01"`) | YAMLの検索キー、ディレクトリ名 |
| `slug` | String? | 章の識別名 (`"life"`) | ファイル名の一部、URL識別子 |
| `kind` | Symbol | 章の種別 (`:chapter`, `:preface` 等) | テンプレート切り替え、統計 |
| `label` | String | YAML上の階層名 (`"実践篇"`) | エラーメッセージ、目次生成 |
| `path` | String | 推定されるファイルパス | `File.read`, `File.write` の引数 |
| `exists` | Boolean | 実ファイルがディスクにあるか | `delete`, `build` の実行可否判断 |
| `in_catalog`| Boolean | `catalog.yml` に定義済みか | 重複チェック、一括処理のフィルタ |
| `valid` | Boolean | 命名規則 (`\A\d+`) に則っているか | 不正な入力の即時拒否 |

### 派生データ（メソッド）
- **`basename`**: `number` と `slug` を結合した文字列（例: `01-life`）。内部で動的に生成されるため、属性間の不整合が発生しない。

## 3. 解決プロセス (Lifecycle)
`Resolver#resolve` は以下のステップを順に実行する。

1.  **Normalization**: カンマ区切りの分割、パス/拡張子の除去、範囲指定 (`1-3`) の展開を行う。
2.  **Catalog Loading**: `catalog.yml` を解析し、定義済みの全章を `Entry` オブジェクトとして展開する。
3.  **Matching**:
    - 入力が「数字」で始まらなければ `valid: false` として即座に解決。
    - 数字で始まる場合、カタログ内の `number` と照合し、情報を付与する。
    - カタログにない場合は `in_catalog: false`（新規予約状態）として解決。

## 4. 拡張ガイド: 新コマンド実装レシピ
将来、`vs awesome` のような新コマンドを追加する際は、以下のフローで実装する。

### ステップ1: トークンの解決
```ruby
# 入力が 1, 2-4, foobar など混ざっていても一括解決
entries = TokenResolver::Resolver.new.resolve(ARGV)
```

### ステップ2: バリデーション

valid フラグを使って、不正な形式の入力を最初に弾く。

```ruby
invalid = entries.reject(&:valid)
abort "Invalid format: #{invalid.map(&:slug)}" if invalid.any?
```

### ステップ3: 目的別フィルタリング

Entry の状態フラグを組み合わせて、処理対象を絞り込む。

- build系: entries.select(&:in_catalog) （カタログにあるものだけ）
- create系: entries.reject(&:in_catalog) （まだないものだけ）
- メンテナンス系: entries.select { |e| e.in_catalog && !e.exists } （定義はあるがファイルがない不整合）

| コマンド | 期待する `valid` | 期待する `in_catalog` | 判定のポイント |
| :--- | :---: | :---: | :--- |
| **build** | `true` | **`true`** | カタログにないものはビルド対象から外す（または警告）。 |
| **create** | `true` | **`false`** | `in_catalog` が `true` なら「重複」として拒否。 |
| **delete** | `true` | **`true`** | カタログまたは `exists` が `true` なら削除実行。 |
| **rename** | `true` | (To) **`false`** | 移動先が既存なら拒否。ただしFromとToの番号が同じならスラグ変更として許可。 |

## vs awesomeコマンドの実装例

```ruby
# frozen_string_literal: true

module Vivlio::Starter::CLI
  class AwesomeCommand
    def initialize(resolver: TokenResolver::Resolver.new)
      @resolver = resolver
    end

    def run(argv)
      # 1. Resolver で入力を一括解決
      entries = @resolver.resolve(argv)

      # 2. バリデーション（不正な形式が含まれていれば即終了）
      invalid_entries = entries.reject(&:valid)
      if invalid_entries.any?
        abort "Error: 不正な章番号が含まれています: #{invalid_entries.map(&:slug).join(', ')}"
      end

      # 3. フィルタリング（カタログにある実体が存在する章のみを抽出）
      targets = entries.select { |e| e.in_catalog && e.exists }
      
      if targets.empty?
        puts "Awesomeにできる章が見つかりませんでした。"
        return
      end

      # 4. 実行フェーズ
      puts "--- Making chapters awesome! ---"
      targets.each do |entry|
        case entry
        in { kind: :preface }
          # Entry の中身をパターンマッチで見ることで、「まえがき」と「本編」で処理を分けるといった高度なロジックが簡潔に書けます。
          process_special_awesome(entry, "✨")
        in { kind: :chapter, label: "実践篇" }
          # entry.label を使うことで、ユーザーに「今、実践篇の章を処理していますよ」というリッチなフィードバックを返せます。
          process_special_awesome(entry, "🚀")
        else
          process_normal_awesome(entry)
        end
      end

      puts "--- Success: #{targets.size} chapters are now awesome. ---"
    end

    private

    def process_special_awesome(entry, icon)
      puts "#{icon}  Processing [#{entry.label}] #{entry.basename}..."
      # ここに特別な処理を記述
    end

    def process_normal_awesome(entry)
      puts "👍 Processing #{entry.basename}..."
      # ここに通常処理を記述
    end
  end
end
```