# frozen_string_literal: true

# ================================================================
# File: lib/vivlio/starter/cli/pre_process/data_render.rb
# ================================================================
# 責務:
#   QueryStream 記法を検出し、データファイルとテンプレートを用いて
#   Markdown を生成する。pre_process パイプラインの一部として動作する。
#
# QueryStream 記法:
#   = [源泉] | [抽出条件] | [ソート] | [件数] | [スタイル]
#   例: = books | tags=ruby | -title | 5 | :full
#
# 依存ファイル:
#   data/*.yml       - データソース
#   templates/_*.md  - テンプレートファイル
# ================================================================

require 'yaml'
require_relative '../common'
require_relative 'data_render/singularize'
require_relative 'data_render/query_stream_parser'
require_relative 'data_render/template_compiler'

module Vivlio
  module Starter
    module CLI
      module PreProcessCommands
        # QueryStream 記法を展開してMarkdownを生成するモジュール
        module DataRender
          # QueryStream 記法を検出する正規表現
          # 行頭 = の直後にスペース + 英数字/ハイフン/アンダースコアのデータ名
          QUERY_STREAM_PATTERN = /^=\s+([a-zA-Z0-9_-]+)(?:\s*\|.*)?$/

          # 画像の拡張子（リテラル判定用）
          IMAGE_EXTENSIONS = %w[png jpg jpeg webp gif svg].freeze

          module_function

          # Markdown コンテンツ内の QueryStream 記法をすべて展開する
          # @param content [String] Markdown コンテンツ
          # @param source_filename [String] エラー報告用のソースファイル名
          # @param data_dir [String] データディレクトリのパス
          # @param templates_dir [String] テンプレートディレクトリのパス
          # @return [String] 展開後の Markdown コンテンツ
          def process(content, source_filename: nil, data_dir: 'data', templates_dir: Common::TEMPLATES_DIR)
            lines = content.lines
            result = []
            in_code_block = false

            lines.each_with_index do |line, idx|
              line_number = idx + 1

              # コードブロック内はスキップ
              if line.lstrip.start_with?('```')
                in_code_block = !in_code_block
                result << line
                next
              end

              if in_code_block
                result << line
                next
              end

              # QueryStream 記法の検出
              if line.match?(QUERY_STREAM_PATTERN)
                expanded = expand_query_stream(
                  line.chomp, line_number:, source_filename:, data_dir:, templates_dir:
                )
                result << expanded << "\n"
              else
                result << line
              end
            end

            result.join
          end

          # 単一の QueryStream 行を展開する
          # @param line [String] QueryStream 記法の行（例: "= books | tags=ruby | :full"）
          # @param line_number [Integer] 行番号（エラー報告用）
          # @param source_filename [String] ソースファイル名
          # @param data_dir [String] データディレクトリ
          # @param templates_dir [String] テンプレートディレクトリ
          # @return [String] 展開後の Markdown
          def expand_query_stream(line, line_number: nil, source_filename: nil, data_dir: 'data', templates_dir: Common::TEMPLATES_DIR)
            location = source_filename ? "#{source_filename}:#{line_number}" : "行#{line_number}"

            # --- Phase: Parse ---
            query = QueryStreamParser.parse(line)

            # --- Phase: Load Data ---
            # 複数形・単数形の両方でデータファイルを探す
            # 例: "book" → data/book.yml, data/books.yml の順で探索
            data_file = resolve_data_file(query[:source], data_dir)
            unless data_file
              expected = File.join(data_dir, "#{query[:source]}.yml")
              Common.log_error("データファイルが見つかりません(#{location})")
              Common.log_error("  記法: #{line}")
              Common.log_error("  期待: #{expected}")
              raise DataRenderError, "データファイルが見つかりません: #{expected}"
            end

            records = YAML.load_file(data_file, symbolize_names: true)
            records = [records] if records.is_a?(Hash)

            # --- Phase: Filter ---
            records = apply_filters(records, query[:filters])

            # --- Phase: Sort ---
            records = apply_sort(records, query[:sort]) if query[:sort]

            # --- Phase: Limit ---
            records = records.first(query[:limit]) if query[:limit]

            # --- Phase: Single record warning ---
            if query[:single_lookup]
              case records.size
              when 0
                Common.log_warn("一件検索で該当なし(#{location}): #{line}")
                return ''
              when 1
                # 正常
              else
                Common.log_warn("一件検索で複数件ヒット(#{location}): #{line}")
                Common.log_warn("  #{records.size}件見つかりました。条件を明示してください。")
              end
            end

            # --- Phase: Resolve Template ---
            singular = Singularize.call(query[:source])
            style = query[:style]
            template_path = resolve_template_path(singular, style, templates_dir)

            unless File.exist?(template_path)
              hint = build_template_hint(singular, style, templates_dir)
              Common.log_error("テンプレートファイルが見つかりません(#{location})")
              Common.log_error("  記法: #{line}")
              Common.log_error("  期待: #{template_path}")
              Common.log_error("  ヒント: #{hint}") if hint
              raise DataRenderError, "テンプレートファイルが見つかりません: #{template_path}"
            end

            template_content = File.read(template_path, encoding: 'utf-8')

            # --- Phase: Render ---
            TemplateCompiler.render(template_content, records, source_filename:, line_number:)
          end

          # フィルタ条件をレコード群に適用する
          # @param records [Array<Hash>] レコード群
          # @param filters [Array<Hash>] フィルタ条件の配列
          # @return [Array<Hash>] フィルタ後のレコード群
          def apply_filters(records, filters)
            return records if filters.nil? || filters.empty?

            records.select do |record|
              filters.all? { evaluate_filter(record, it) }
            end
          end

          # 単一フィルタ条件をレコードに対して評価する
          # @param record [Hash] 単一レコード
          # @param filter [Hash] フィルタ条件 { field:, op:, value: }
          # @return [Boolean] 条件に合致するか
          def evaluate_filter(record, filter)
            # 主キー検索（_primary_key）の特別処理
            if filter[:field] == :_primary_key
              return evaluate_primary_key_lookup(record, filter[:value])
            end

            field_value = record[filter[:field]]

            case filter[:op]
            when :eq
              match_eq(field_value, filter[:value])
            when :neq
              !match_eq(field_value, filter[:value])
            when :gt
              to_comparable(field_value) > to_comparable(filter[:value])
            when :gte
              to_comparable(field_value) >= to_comparable(filter[:value])
            when :lt
              to_comparable(field_value) < to_comparable(filter[:value])
            when :lte
              to_comparable(field_value) <= to_comparable(filter[:value])
            when :range
              range = filter[:value]
              range.cover?(to_comparable(field_value))
            else
              false
            end
          end

          # 主キー候補フィールドを順番に走査して一致するものを探す
          # @param record [Hash] 単一レコード
          # @param query_value [Object] 検索値
          # @return [Boolean] いずれかの主キー候補と一致するか
          def evaluate_primary_key_lookup(record, query_value)
            QueryStreamParser::PRIMARY_KEY_FIELDS.any? do |key|
              record[key]&.to_s == query_value.to_s
            end
          end

          # 等値比較（配列・カンマ区切り文字列を透過的に扱う）
          # データ側が配列/カンマ区切りの場合、ORの値リストと交差判定する
          def match_eq(field_value, filter_values)
            field_list = normalize_to_list(field_value)
            value_list = Array(filter_values).map { it.to_s.strip }

            # フィールド側の値リストと条件値リストに交差があれば一致
            (field_list & value_list).any?
          end

          # フィールド値をリスト化する（配列/カンマ区切り/単値を統一）
          def normalize_to_list(value)
            case value
            when Array
              value.map { it.to_s.strip }
            when String
              value.split(',').map { it.strip }
            when nil
              []
            else
              [value.to_s.strip]
            end
          end

          # 比較用に数値変換を試みる
          def to_comparable(value)
            case value.to_s
            when /\A-?\d+\z/
              value.to_i
            when /\A-?\d+\.\d+\z/
              value.to_f
            else
              value.to_s
            end
          end

          # ソート条件を適用する
          # @param records [Array<Hash>] レコード群
          # @param sort [Hash] ソート条件 { field:, direction: }
          # @return [Array<Hash>] ソート後のレコード群
          def apply_sort(records, sort)
            sorted = records.sort_by { to_comparable(it[sort[:field]]) }
            sort[:direction] == :desc ? sorted.reverse : sorted
          end

          # データファイルのパスを解決する
          # 指定名そのまま → 複数形（末尾に s を付与）の順で探索する
          # @param source_name [String] データ名（単数形または複数形）
          # @param data_dir [String] データディレクトリ
          # @return [String, nil] 見つかったファイルパス、または nil
          def resolve_data_file(source_name, data_dir)
            # そのまま試行
            exact = File.join(data_dir, "#{source_name}.yml")
            return exact if File.exist?(exact)

            # 複数形を試行（単数形→複数形: book → books）
            plural = File.join(data_dir, "#{source_name}s.yml")
            return plural if File.exist?(plural)

            # 単数形を試行（複数形→単数形: books → book）
            singular = Singularize.call(source_name)
            if singular != source_name
              singular_file = File.join(data_dir, "#{singular}.yml")
              return singular_file if File.exist?(singular_file)
            end

            nil
          end

          # テンプレートファイルパスを解決する
          # @param singular_name [String] 単数形のデータ名
          # @param style [String, nil] スタイル名
          # @param templates_dir [String] テンプレートディレクトリ
          # @return [String] テンプレートファイルパス
          def resolve_template_path(singular_name, style, templates_dir)
            if style
              File.join(templates_dir, "_#{singular_name}.#{style}.md")
            else
              File.join(templates_dir, "_#{singular_name}.md")
            end
          end

          # テンプレート不在時のヒントメッセージを生成する
          def build_template_hint(singular_name, style, templates_dir)
            default_path = File.join(templates_dir, "_#{singular_name}.md")
            if style && File.exist?(default_path)
              "#{default_path} は存在します。スタイル名を確認してください。"
            else
              nil
            end
          end

          # DataRender 固有のエラークラス
          class DataRenderError < StandardError; end
        end
      end
    end
  end
end
