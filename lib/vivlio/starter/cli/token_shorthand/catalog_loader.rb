# frozen_string_literal: true

require 'yaml'
require_relative '../common'
require_relative 'data'

module Vivlio
  module Starter
    module CLI
      module TokenShorthand
        # catalog.yml から章エントリを読み込む
        class CatalogLoader
          CATALOG_PATH = 'config/catalog.yml'
          SECTIONS = {
            'PREFACE' => :preface,
            'CHAPTERS' => :chapter,
            'APPENDICES' => :appendix,
            'POSTFACE' => :postface
          }.freeze

          PREFACE_RANGE  = (0..0)
          MAIN_RANGE     = (1..89)
          APPX_RANGE     = (90..98)
          POSTFACE_RANGE = (99..99)

          # catalog.yml の探索パスと contents_dir を束ね、後続ロードでの参照を一定化する。
          def initialize(catalog_path = CATALOG_PATH, contents_dir: Common::CONTENTS_DIR)
            @catalog_path = catalog_path
            @contents_dir = contents_dir
          end

          # catalog.yml から章エントリを取得する
          # @return [Array<TokenShorthand::Data::CatalogEntry>]
          # Yaml を解釈し、章情報を CLI が扱える Struct に変換する入口。
          def entries
            return [] unless File.exist?(catalog_path)

            catalog = load_catalog
            loaded = SECTIONS.flat_map do |section, kind|
              extract_entries(catalog[section], kind)
            end

            unique_entries(loaded)
          end

          # catalog.yml が存在するかどうかを事前チェックする。
          def catalog_exists? = File.exist?(catalog_path)

          private

          # 初期化時に受け取ったパス情報は attr_reader 経由で参照し、メソッド内でのローカル変数化を避ける。
          attr_reader :catalog_path, :contents_dir

          # catalog.yml を YAML.safe_load し、構文エラー時はワーニングを出して空ハッシュを返す。
          def load_catalog
            YAML.safe_load(File.read(catalog_path, encoding: 'utf-8'), permitted_classes: [Symbol]) || {}
          rescue Psych::SyntaxError => e
            Common.log_warn("catalog.yml の構文エラー: #{e.message}")
            {}
          end

          # PREFACE/CHAPTERS 等のセクション配列を受け取り、章ベース名の列へと平坦化する。
          def extract_entries(section, kind)
            return [] if section.nil?

            Array(section).flat_map { flatten_entry(it, kind) }
          end

          # catalog.yml のネスト（Hash/Array）を再帰的に辿り、最終的な章指定へ変換する。
          def flatten_entry(entry, kind)
            case entry
            in String
              build_entry(entry, kind)
            in Hash
              entry.values.flat_map { flatten_entry(it, kind) }
            in Array
              entry.flat_map { flatten_entry(it, kind) }
            else
              []
            end
          end

          # ベース名文字列から CatalogEntry Struct を 1 件生成する。
          def build_entry(raw_name, fallback_kind)
            basename = normalize_basename(raw_name)
            return [] if basename.empty?

            number, slug = parse_basename(basename)
            kind = derive_kind(number, fallback_kind)
            path = File.join(contents_dir, "#{basename}.md")

            [Data::CatalogEntry.new(
              number:,
              slug:,
              kind:,
              basename:,
              path:,
              ext: '.md',
              exists: File.exist?(path)
            )]
          end

          # .md を取り除きつつ前後空白を削り、basename 判定を安定させる。
          def normalize_basename(name)
            name.to_s.sub(/\.md\z/i, '').strip
          end

          # `01-slug` 形式を number/slug のペアへ分解し、後段の kind 判定を容易にする。
          def parse_basename(basename)
            match = basename.match(/\A(?<number>\d+)(?:[-_](?<slug>.+))?\z/)
            return [nil, nil] unless match

            number = normalize_number(match[:number])
            slug = match[:slug]&.strip
            [number, slug]
          end

          # 数値を 2 桁ゼロ埋めして章番号フォーマットを統一する。
          def normalize_number(number)
            return nil if number.nil?

            format('%02d', number.to_i)
          end

          # 章番号の範囲から preface/chapter/appendix/postface を判定し、fallback を上書きする。
          def derive_kind(number, fallback_kind)
            return fallback_kind unless number

            case number.to_i
            when PREFACE_RANGE
              :preface
            when MAIN_RANGE
              :chapter
            when APPX_RANGE
              :appendix
            when POSTFACE_RANGE
              :postface
            else
              fallback_kind
            end
          end

          # catalog.yml 内で重複指定された章を 1 度にまとめ、Resolver へユニーク配列を渡す。
          def unique_entries(entries)
            seen = {}
            entries.each_with_object([]) do |entry, result|
              next if entry.nil? || entry.basename.nil?
              next if seen[entry.basename]

              seen[entry.basename] = true
              result << entry
            end
          end
        end
      end
    end
  end
end
