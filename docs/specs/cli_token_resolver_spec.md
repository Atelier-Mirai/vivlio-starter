# CLI Token Resolver Specification

## 1. 概要

- vivlio-starter（略称 vs）は Vivliostyle の厚いラッパーとして動作する電子書籍執筆システムであり、Ruby 4.0+ をターゲットに Gem 化を進めている。
- CLI の章指定トークンを一元的に解釈する Resolver を定義し、全コマンドで同じ正規化・照合ルールを共有することを目標とする。

## 2. 背景と目的

現在、各CLIコマンド（`vs build`、`vs create`、`vs delete`など）が独自にトークンの正規化処理を実装しており、コードの重複が発生している。本仕様は、章番号やスラッグを含む位置引数の正規化ロジックを共通化し、保守性を向上させることを目的とする。

## 3. 対象コマンド

  ビルド・出力:
    build            書籍全体または指定章をビルドします
    内部コマンド
      `vs pre_process`、`vs convert`、`vs post_process`、`vs entries`
      これらの章指定は、buildに渡されたものを引き継いで処理を行なう
      （独自にresolverを呼んで章番号を解決することは行なわない）

  執筆・編集支援:
    create           章ファイルと画像ディレクトリを生成します
    delete           指定した章の Markdown と画像を削除します
    rename           章のスラッグ/番号を変更します
    renumber         章番号を一括で付け直します

  文章校正・用語:
    lint             Markdownをtextlintで検査します
    metrics          Markdownの行数・文字数を集計します

- その他、章指定を受け取るすべてのコマンド

## 4. 基本方針

- `vs build`/`vs metrics` などのコマンドは、引数なしの場合 `catalog.yml` に定義された全章を処理対象とする。
- 章番号が欠落していても、存在する番号のみを対象にビルドする（例: `vs build 1-3` で `02` が未登録なら `01` と `03` のみ処理）。

## 5. コマンド別要件

### 5.1 create

- 形式: `vs create 1-foo 2-bar`
- slug 付き引数が必須。
- `catalog.yml` に既存の章番号があれば、slug が異なっていてもエラー扱いとして拒否する。

### 5.2 delete

- 形式: `vs delete 1`（番号必須、slug 任意）。
- `catalog.yml` に該当章があれば YAML と実ファイルを削除。未登録なら何もしない。

### 5.3 rename

- `rename 1-life 1-install`: 番号が同一で slug のみ変更するケースは許可。
- `rename 1-life 11-life`: 既存章（例: `11-env`）と番号が衝突する場合はエラーで拒否。

## 6. 用語の整理

- **Token**: CLIが受け取る文字列単位の章指定（例: `"1-3"`, `"05"`, `"07-web"`）
- **Normalized Token**: ゼロ埋め・レンジ展開済みのトークン（例: "01", "02", "03"）
- **Catalog Entry**: `catalog.yml`から読み込まれる章情報

## 7. 正規化ルール

### 7.1 ゼロ埋め

- `0-9`の入力は`00-09`に変換
- 例: `1` → `01`、`1-foo` → `01-foo`

### 7.2 レンジ展開

- `1-3` → `01, 02, 03`
- 降順も対応: `10-8` → `10, 09, 08`
- 混在指定: `1-3,5,8-10` → `01, 02, 03, 05, 08, 09, 10`

### 7.3 スラッグ付き指定

- `1-life`、`01-life.md`、`1-life.md`などを`01-life`に正規化
- 番号のみの指定は許可
- slugのみの指定は拒否(invalid)

### 7.4 重複排除

- 展開後の重複トークンは1度だけ出力
- 入力順は保持しなくて良い

## 8 catalog.ymlの形式

```yaml:catalog.yml
## まえがき
PREFACE:
  - 00-preface

## 本文
CHAPTERS:
  - 歴史篇:
      - 01-life
      - 02-history
      - 03-person
      - 04-computers-work
      - 05-binary
      - 06-algorithm
      - 07-programming
      - 08-web
  - 実践篇:
      - 11-env
      - 21-html
      - 22-css
      - 23-javascript
      # - 24-javascript
      - 31-netlify
      - 41-pwa

## 付録
APPENDICES:
  - 91-books
  - 92-links
  - 93-cheats

# ## あとがき
POSTFACE:
  - 99-postface
```

## 9. 実装コード例

```ruby:token_resolver.rb
# frozen_string_literal: true

require 'yaml'

module Vivlio::Starter::CLI
  module TokenResolver
    # 章情報を保持する不変データ構造
    # @param number [String] 2桁ゼロ埋め済みの章番号 (例: "01")
    # @param slug   [String, nil] 章のスラッグ
    # @param kind   [Symbol] :preface, :chapter, :appendix, :postface
    # @param label  [String] 「歴史篇」や「CHAPTERS」などの階層名
    # @param path   [String] 想定されるファイルパス
    # @param exists [Boolean] 実ファイルが存在するかどうか
    # @param in_catalog [Boolean] catalog.yml に定義されているか
    Entry = Data.define(:number, :slug, :kind, :label, :path, :exists, :in_catalog, :valid) do
      def basename = slug ? "#{number}-#{slug}" : number
    end

    # 入力の正規化、カタログの読み込み、両者の照合を一括管理する
    class Resolver
      KIND_RANGES = { preface: 0..0, chapter: 1..89, appendix: 90..98, postface: 99..99 }.freeze

      def initialize(catalog_path: 'config/catalog.yml', contents_dir: 'contents')
        @catalog_path = catalog_path
        @contents_dir = contents_dir
      end

      # メイン入口：引数があればそれを解決し、無ければカタログ全件を返す
      def resolve(tokens = [])
        catalog = load_catalog_entries
        
        if tokens.empty?
          # 引数なし：catalog.yml にある全章を対象とする (build 等)
          catalog
        else
          # 引数あり：入力を正規化してカタログと突き合わせる
          normalize(tokens).map { |t| match_entry(t, catalog) }
        end
      end

      private

      # --- Phase 1: Normalization (入力の正規化) ---
      def normalize(tokens)
        prefix = %r{\A#{Regexp.escape(@contents_dir)}/}
        Array(tokens).compact.flat_map { it.to_s.split(',') }.map(&:strip).flat_map do |raw|
          n = raw.sub(prefix, '').then { File.basename(it, '.*') }
          case n
          in /\A(\d+)\z/ then format('%02d', $1.to_i)
          in /\A(\d+)-(\d+)\z/
            s, e = $1.to_i, $2.to_i
            (s <= e ? s..e : e..s).map { format('%02d', it) }
          in /\A(\d+)([-_].+)\z/ then "#{format('%02d', $1.to_i)}#{$2}"
          else n
          end
        end.reject { it.empty? }.uniq
      end

      # --- Phase 2: Catalog Loading (カタログ読み込み) ---
      def load_catalog_entries
        return [] unless File.exist?(@catalog_path)
        raw_yaml = YAML.safe_load(File.read(@catalog_path)) || {}
        
        raw_yaml.flat_map do |section, items|
          extract_from_yaml(items, context: section).map do |base, label|
            build_entry(base, label, section.downcase.to_sym, in_catalog: true)
          end
        end.uniq(&:number)
      end

      # --- Phase 3: Catalog Loading (カタログ読み込み) ---
      def extract_from_yaml(items, context:)
        case items
        in String then [[items.sub(/\.md\z/i, ''), context]]
        in Array  then items.flat_map { extract_from_yaml(it, context:) }
        in Hash   then items.flat_map { |k, v| extract_from_yaml(v, context: k.to_s) }
        else []
        end
      end

      # --- Phase 4: Matching (照合) ---
      def match_entry(token, catalog)
        # 1. 形式チェック: 数字で始まらないものは即座に invalid
        unless token.match?(/\A\d+/)
            return instantiate_invalid_entry(token)
        end

        # 2. カタログから番号が一致するものを探す
        token_num = token[/\A\d+/] ? format('%02d', token.to_i) : nil
        found = catalog.find { |e| e.number == token_num}
        return found if found

        # 3. カタログにない場合、新規エントリ（create用）として生成
        instantiate_entry(token, "NEW", :chapter, in_catalog: false, valid: true)
      end

      # --- Phase 5: Entryオブジェクトの実体化（正常系）---
      def instantiate_entry(basename, label, fallback_kind, in_catalog:)
        # 内部で形式チェックに失敗した場合も対称性を保って invalid_entry を呼ぶ
        return instantiate_invalid_entry(basename) unless basename =~ /\A(\d+)(?:[-_](.+))?\z/
        
        num, slug = $1, $2
        number = format('%02d', num.to_i)
        path = File.join(@contents_dir, "#{basename}.md")
        kind = KIND_RANGES.find { |_, r| r.cover?(number.to_i) }&.first || fallback_kind

        Entry.new(number:, slug: slug&.strip, kind:, label:, path:, exists: File.exist?(path), in_catalog:, valid: true)
      end

      # --- Phase 6: Invalid Entry (不正形式エントリ生成) ---
      def instantiate_invalid_entry(token)
        Entry.new(number: "??", slug: token, kind: :unknown, label: "INVALID", path: "", exists: false, in_catalog: false, valid: false)
      end
    end
  end
end
```

## 9. 各コマンドでの利用例

### 9.1 コマンド側での処理（build コマンド例）

build コマンド側で、「カタログにあるものだけをフィルタリング」するように書けば、エラーで止まることなく 01 と 03 だけをビルドできます。

```Ruby
# vs build 1-3
entries = resolver.resolve(ARGV)

# カタログに存在する章のみに絞り込む
targets = entries.select(&:in_catalog)

# 実行（01 と 03 だけが処理される）
targets.each { |e| build(e) }

# オプション：スキップしたことを通知する場合
skipped = entries.reject(&:in_catalog).map(&:number)
puts "Skipped (not in catalog): #{skipped.join(', ')}" if skipped.any?
```

# 引数: ["1-foo", "2-foo"]
entries = TokenResolver::Resolver.new.resolve(ARGV)

### 9.2 create コマンドでの利用イメージ

```ruby
# 1. まず一括でエラーチェック（1つでもダメなら止める、という設計の場合）
invalid_entries = entries.reject(&:valid)
if invalid_entries.any?
  abort "Error: 不正な形式が含まれています: #{invalid_entries.map(&:slug).join(', ')}"
end

# 2. 次に「カタログとの重複」をチェック
duplicate_entries = entries.select(&:in_catalog)
if duplicate_entries.any?
  abort "Error: 以下の章は既にカタログに存在します:\n" + 
        duplicate_entries.map { "  - #{it.basename} (#{it.label})" }.join("\n")
end

# 3. すべてクリアしたら、一括で作成
entries.each do |entry|
  # 実際の実装では、ここで YAML への追記とファイル作成 を行う
  puts "Creating: #{entry.path} ..."
  # FileUtils.touch(entry.path) 
  # CatalogUpdater.add(entry)
end

puts "Success: #{entries.size} 個の章を作成しました。"
```

### 9.3 delete コマンドでの利用イメージ

- カタログに 01-life が登録されており、contents/01-life.md も存在する場合。

```ruby
# Resolver の返却値:
# <Entry number="01", slug="life", in_catalog=true, exists=true, valid=true ...>

# コマンド側の挙動: 「カタログにある」かつ「ファイルもある」ため、YAMLからの削除とファイルの削除の両方を実行します。
if entry.in_catalog
  # catalog.yml から 01-life を取り除く処理
end
if entry.exists
  # FileUtils.rm(entry.path) を実行
end
```


- vs delete 1 で章が存在しない場合

カタログにも登録されておらず、ファイルも存在しない場合。

```ruby
# Resolver の返却値:
# <Entry number="01", slug=nil, in_catalog=false, exists=false, valid=true ...>

# コマンド側の挙動: in_catalog も exists も false なので、何もしません。 「指定された章は存在しません」とメッセージを出して終了するのが親切です。
```

#### 利用イメージ
```ruby
# vs delete 1
entries = resolver.resolve(ARGV)

entries.each do |e|
  unless e.valid?
    puts "Skip: '#{e.slug}' は不正な指定です。"
    next
  end

  # カタログ・ファイルどちらか一報でもあれば削除対象とする
  if e.in_catalog || e.exists
    delete_from_yaml(e) if e.in_catalog
    File.delete(e.path) if e.exists
    puts "Deleted: #{e.basename}"
  else
    puts "Notice: #{e.number}番の章は見つかりませんでした。"
  end
end
```

### 9.4 rename コマンドでの利用イメージ

rename コマンドでは、TokenResolver が返す 2 つの Entry（変更元 / 変更先）を突き合わせて可否を判定します。

判定ルール:

- From（変更元）：`in_catalog: true` であること。
- To（変更先）：次のいずれかを満たす場合に許可。
  - `in_catalog: false`（誰もその番号を使っていない）。
  - `in_catalog: true` かつ `From.number == To.number`（同じ章番号内のスラグ変更）。

#### 例1: `rename 1-install 1-tutorial`（許可）

番号は同じで、スラグだけを変更するケース。

- From (1-install): `number: "01"`, `slug: "install"`, `in_catalog: true`
- To (1-tutorial): `number: "01"`, `slug: "tutorial"`, `in_catalog: true`

`From.number` と `To.number` がどちらも `01` のため、同一章内のスラグ変更と判定して許可されます。

#### 例2: `rename 1-install 11-install`（拒否）

番号を 1 から 11 に変更しようとしたが、11 番が既に埋まっているケース。

- From (1-install): `number: "01"`, `slug: "install"`, `in_catalog: true`
- To (11-install): `number: "11"`, `slug: "install"`, `in_catalog: true`

`From.number (01)` と `To.number (11)` が異なり、かつ 11 番が既存章に割り当てられているため、上書きしようとしていると判断して拒否します。

実装での判定ロジック例:

```Ruby
# from_entry, to_entry = resolver.resolve(["1-install", "11-install"])

if to_entry.in_catalog && from_entry.number != to_entry.number
  abort "Error: 変更先の番号 #{to_entry.number} は既に '#{to_entry.label}' で使用されています。"
end

# ここまで来れば OK
# 1. ファイルのリネーム: from_entry.path -> to_entry.path
# 2. YAMLの更新: number: 01 の slug を "tutorial" に書き換える、等
```

まとめ：rename の成功条件

| ケース           | From番号 | To番号 | Toがカタログにあるか | 判定 | 理由                     |
| ---------------- | -------- | ------ | -------------------- | ---- | ------------------------ |
| スラグ変更       | 01       | 01     | Yes                  | OK   | 同じ章内のリネーム       |
| 空き番号へ移動   | 01       | 05     | No                   | OK   | 5番は空いている          |
| 重複番号へ移動   | 01       | 11     | Yes                  | NG   | 11番は既に使用中         |

## 11. 移行手順

1. `TokenResolver`を実装
2. 既存コマンドを順次移行
3. 旧実装の削除

## 12. テスト戦略

### 12.1 TokenResolverのテスト
- ゼロ埋め: `1` → `01`
- レンジ展開: `1-3` → `['01', '02', '03']`
- 降順レンジ: `5-3` → `['05', '04', '03']`
- 混在指定: `1-3,5` → `['01', '02', '03', '05']`
- 重複排除: `1,2,1` → `['01', '02']`
- スラッグ付き: `1-life` → `01-life`

### 12.2 CatalogLoader のテスト
- `catalog.yml`の正常読み込み
- 章情報の構造検証

### 12.3 統合テスト
- 実際のコマンドでの動作確認

## 13. コーディング上の注意点

- Rubocopの`Metrics/MethodLength`制限は無視してよい
- 長くなる場合にはフェーズコメントを用いて構造化する
- 一つのメソッド内で文脈を保持することを優先

