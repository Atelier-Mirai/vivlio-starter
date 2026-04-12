# frozen_string_literal: true

# ================================================================
# File: lib/vivlio/starter/cli/metrics/catalog_loader.rb
# ================================================================
# 責務:
#   config/catalog.yml から有効な章リストを取得する。
#
# 機能:
#   - PREFACE/CHAPTERS/APPENDICES/POSTFACE セクションをパース
#   - ネストされた部（パート）構造を平坦化
#   - ベース名のリストを返却
#
# Ruby 4.0+ 構文:
#   - it パラメータ
#   - エンドレスメソッド
# ================================================================

require 'yaml'

module Vivlio
  module Starter
    module CLI
      module Metrics
        # catalog.yml から有効章を取得する
        class CatalogLoader
          CATALOG_PATH = 'config/catalog.yml'
          SECTIONS = %w[PREFACE CHAPTERS APPENDICES POSTFACE].freeze

          def initialize(catalog_path = CATALOG_PATH)
            @catalog_path = catalog_path
          end

          # 有効な章のベース名リストを取得する
          def enabled_chapters
            return [] unless File.exist?(catalog_path)

            catalog = load_catalog
            SECTIONS.flat_map { extract_chapters(catalog[it]) }.compact.uniq
          end

          # catalog.yml が存在するか確認する
          def catalog_exists? = File.exist?(catalog_path)

          private

          attr_reader :catalog_path

          # YAML ファイルを読み込む
          def load_catalog
            YAML.safe_load_file(catalog_path, permitted_classes: [Symbol]) || {}
          rescue Psych::SyntaxError => e
            Common.log_warn("catalog.yml の構文エラー: #{e.message}")
            {}
          end

          # セクションから章リストを抽出する（ネスト対応）
          def extract_chapters(section)
            return [] if section.nil?

            Array(section).flat_map { flatten_entry(it) }
          end

          # エントリを平坦化する（部タイトル付きネストを展開）
          def flatten_entry(entry)
            case entry
            when String
              normalize_basename(entry)
            when Hash
              entry.values.flat_map { flatten_entry(it) }
            when Array
              entry.flat_map { flatten_entry(it) }
            else
              []
            end
          end

          # ベース名を正規化（拡張子除去）
          def normalize_basename(name)
            name.to_s.sub(/\.md\z/, '').strip
          end
        end
      end
    end
  end
end
