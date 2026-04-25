# TokenResolver 内部設計書

## 1. 設計思想

`TokenResolver` は、ユーザーからの曖昧な入力（Token）を、システムが安全に扱える厳格なデータ構造（Entry）に変換する「信頼できる唯一の情報源（Single Source of Truth）」である。

**設計上の特徴:**
- **例外を投げない**: 不正な入力も `valid: false` の Entry として返し、呼び出し側で判断させる
- **カタログ非依存の解決**: `in_catalog: false` でも Entry を生成し、create コマンド等で利用可能
- **不変オブジェクト**: `Data.define` による Entry は変更不可で、スレッドセーフ

## 2. ファイル配置

```
lib/vivlio/starter/cli/
└── token_resolver.rb      # Entry + Resolver を1ファイルに集約

test/vivlio/starter/cli/
└── token_resolver_test.rb # ユニットテスト
```

## 3. データ構造: `Entry`

Ruby 4.0 の `Data.define` による不変オブジェクト。

| 属性 | 型 | 内容 | 利用例 |
| :--- | :--- | :--- | :--- |
| `number` | String | 2桁ゼロ埋め済みの章番号 (`"01"`) | YAMLの検索キー、ファイル名 |
| `slug` | String? | 章の識別名 (`"life"`) | ファイル名の一部、URL識別子 |
| `kind` | Symbol | 章の種別 (`:chapter`, `:preface` 等) | テンプレート切り替え、統計 |
| `label` | String | YAML上の階層名 (`"歴史篇"`, `"実践篇"`) | エラーメッセージ、目次生成 |
| `path` | String | 推定されるファイルパス | `File.read`, `File.write` の引数 |
| `exists` | Boolean | 実ファイルがディスクにあるか | `delete`, `build` の実行可否判断 |
| `in_catalog`| Boolean | `catalog.yml` に定義済みか | 重複チェック、一括処理のフィルタ |
| `valid` | Boolean | 命名規則 (`\A\d+`) に則っているか | 不正な入力の即時拒否 |

### 派生データ（メソッド）

```ruby
Entry = Data.define(:number, :slug, :kind, :label, :path, :exists, :in_catalog, :valid) do
  def basename = slug ? "#{number}-#{slug}" : number
  def valid? = valid
  def in_catalog? = in_catalog
  def exists? = exists
end
```

- **`basename`**: `number` と `slug` を結合した文字列（例: `01-life`）
- **述語メソッド**: `valid?`, `in_catalog?`, `exists?` で可読性向上

## 4. 解決プロセス (Lifecycle)

`Resolver#resolve` は以下のフェーズを順に実行する。

```
┌─────────────────────────────────────────────────────────┐
│  Phase 1: Normalization                                 │
│  ・カンマ分割: "1,3" → ["1", "3"]                        │
│  ・パス除去: "contents/01-foo.md" → "01-foo"            │
│  ・ゼロ埋め: "1" → "01"                                  │
│  ・レンジ展開: "1-3" → ["01", "02", "03"]               │
│  ・重複排除: uniq                                        │
└─────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────┐
│  Phase 2: Catalog Loading                               │
│  ・catalog.yml を読み込み                                │
│  ・ネスト構造（歴史篇/実践篇等）を再帰的に走査           │
│  ・各章を Entry オブジェクトとして生成                   │
└─────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────┐
│  Phase 3: Matching                                      │
│  ・正規化トークンとカタログを突き合わせ                  │
│  ・数字で始まらない → invalid Entry                     │
│  ・カタログに存在 → そのまま返却                         │
│  ・カタログに不在 → in_catalog: false で新規生成        │
└─────────────────────────────────────────────────────────┘
```

## 5. kind の自動判定

章番号から kind を自動判定する。

| 番号範囲 | kind | 用途 |
| :---: | :--- | :--- |
| 00 | `:preface` | まえがき |
| 01-89 | `:chapter` | 本文 |
| 90-98 | `:appendix` | 付録 |
| 99 | `:postface` | あとがき |

```ruby
KIND_RANGES = { preface: 0..0, chapter: 1..89, appendix: 90..98, postface: 99..99 }.freeze
```

## 6. コマンド別フィルタリングパターン

| コマンド | フィルタ条件 | 説明 |
| :--- | :--- | :--- |
| **build** | `entries.select(&:in_catalog?)` | カタログにあるものだけビルド |
| **create** | `entries.reject(&:in_catalog?)` | カタログにないもの（新規）のみ作成可 |
| **delete** | `entries.select { it.in_catalog? \|\| it.exists? }` | 実体があれば削除 |
| **rename** | `to.in_catalog? && from.number != to.number` で拒否 | 番号衝突チェック |

## 7. 利用例

### 7.1 build コマンド

```ruby
resolver = TokenResolver::Resolver.new
entries = resolver.resolve(ARGV)

# カタログに存在する章のみビルド
targets = entries.select(&:in_catalog?)
skipped = entries.reject(&:in_catalog?)

puts "Skipped: #{skipped.map(&:number).join(', ')}" if skipped.any?
targets.each { build_chapter(it) }
```

### 7.2 create コマンド

```ruby
entries = resolver.resolve(ARGV)

# バリデーション
invalid = entries.reject(&:valid?)
abort "Invalid: #{invalid.map(&:slug)}" if invalid.any?

# 重複チェック
duplicates = entries.select(&:in_catalog?)
abort "Already exists: #{duplicates.map(&:basename)}" if duplicates.any?

# 作成
entries.each { create_chapter(it) }
```

### 7.3 rename コマンド

```ruby
from_entry, to_entry = resolver.resolve([from_token, to_token])

# 番号衝突チェック（同一番号内のスラグ変更は許可）
if to_entry.in_catalog? && from_entry.number != to_entry.number
  abort "Error: #{to_entry.number} は既に使用されています"
end

rename_chapter(from_entry, to_entry)
```

## 8. テストカバレッジ

| カテゴリ | テスト項目 |
| :--- | :--- |
| Normalization | ゼロ埋め、レンジ展開（昇順/降順）、カンマ混在、重複排除、パス除去 |
| Catalog Loading | ネスト構造、フラット構造、ファイル不存在時の空配列 |
| Matching | カタログ一致、新規エントリ、invalid エントリ、欠番処理 |
| Kind Detection | preface(00)、chapter(01-89)、appendix(90-98)、postface(99) |
| Entry Attributes | basename 生成、exists 反映、述語メソッド |

## 9. 移行時の削除対象

`common.rb` から以下のメソッドを削除可能:

- `normalize_tokens`
- `normalize_chapter_token`
- `expand_range_token`
- `digits_only?`

これらの処理は `TokenResolver::Resolver#normalize` に統合される。