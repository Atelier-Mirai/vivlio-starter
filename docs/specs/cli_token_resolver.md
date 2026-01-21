# CLI Token Resolver Specification

## 1. 概要
- vivlio-starter（略称 vs）は Vivliostyle の厚いラッパーとして動作する電子書籍執筆システムであり、Ruby 4.0+ をターゲットに Gem 化を進めている。
- CLI の章指定トークンを一元的に解釈する Resolver を定義し、全コマンドで同じ正規化・照合ルールを共有することを目標とする。

## 2. 基本方針
- `vs build`/`vs metrics` などのコマンドは、引数なしの場合 `catalog.yml` に定義された全章を処理対象とする。
- 章番号が欠落していても、存在する番号のみを対象にビルドする（例: `vs build 1-3` で `02` が未登録なら `01` と `03` のみ処理）。

## 3. コマンド別要件

### 3.1 create
- 形式: `vs create 1-foo 2-bar`
- slug 付き引数が必須。
- `catalog.yml` に既存の章番号があれば、slug が異なっていてもエラー扱いとして拒否する。

### 3.2 delete
- 形式: `vs delete 1`（番号必須、slug 任意）。
- `catalog.yml` に該当章があれば YAML と実ファイルを削除。未登録なら何もしない。

### 3.3 rename
- `rename 1-life 1-install`: 番号が同一で slug のみ変更するケースは許可。
- `rename 1-life 11-life`: 既存章（例: `11-env`）と番号が衝突する場合はエラーで拒否。

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
