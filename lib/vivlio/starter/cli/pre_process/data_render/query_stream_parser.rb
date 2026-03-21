# frozen_string_literal: true

# ================================================================
# File: lib/vivlio/starter/cli/pre_process/data_render/query_stream_parser.rb
# ================================================================
# 責務:
#   QueryStream 記法（= books | tags=ruby | -title | 5 | :full）を
#   パースし、構造化されたクエリハッシュを返す。
#
# パイプライン:
#   1. Source  - データ名（必須）
#   2. Filter  - 抽出条件（field=value, 比較演算子, 範囲指定）
#   3. Sort    - ソート条件（-field / +field）
#   4. Limit   - 件数制限（正の整数）
#   5. Style   - スタイル名（:stylename）
#
# トークンの自動判別:
#   各トークンは形式で一意に判別される（省略・順序入れ替えに対応）
# ================================================================

module Vivlio
  module Starter
    module CLI
      module PreProcessCommands
        module DataRender
          # QueryStream 記法のパーサー
          module QueryStreamParser
            # 主キー候補フィールド（優先順位順）
            PRIMARY_KEY_FIELDS = %i[id no code name title].freeze

            # AND 条件の区切りパターン
            AND_PATTERN = /\s+(?:AND|and|&&)\s+/

            module_function

            # QueryStream 記法をパースして構造化ハッシュを返す
            #
            # @param line [String] QueryStream 行（例: "= books | tags=ruby | :full"）
            # @return [Hash] パース結果
            #   - :source [String] データ名（複数形のまま）
            #   - :filters [Array<Hash>] フィルタ条件
            #   - :sort [Hash, nil] ソート条件 { field:, direction: }
            #   - :limit [Integer, nil] 件数制限
            #   - :style [String, nil] スタイル名
            #   - :single_lookup [Boolean] 主キーによる一件検索か
            def parse(line)
              # "= books | tags=ruby | :full" → ["books", "tags=ruby", ":full"]
              raw = line.sub(/\A=\s+/, '').strip
              segments = raw.split('|').map { it.strip }

              source = segments.shift
              return build_result(source:) if segments.empty?

              # 源泉名が単数形かどうかを判定
              # 単数形の場合、最初の非修飾セグメントは主キー検索として解釈する
              singular_source = (Singularize.call(source) == source)

              filters = []
              sort = nil
              limit = nil
              style = nil
              single_lookup = false

              segments.each_with_index do |segment, idx|
                next if segment.empty?

                classified = classify_tokens(segment, primary_context: singular_source && idx == 0)
                classified.each do |token|
                  case token
                  in { type: :style, value: }
                    style = value
                  in { type: :limit, value: }
                    limit = value
                  in { type: :sort, value: }
                    sort = value
                  in { type: :filter, value: }
                    filters.concat(value)
                  in { type: :primary_lookup, value: }
                    filters.concat(value)
                    single_lookup = true
                  end
                end
              end

              build_result(source:, filters:, sort:, limit:, style:, single_lookup:)
            end

            # セグメント内のトークンを分類する
            # AND で分割された複合条件、スタイル、ソート、件数を判別
            # @param segment [String] パイプで区切られた1セグメント
            # @param primary_context [Boolean] 主キー検索コンテキスト（単数形源泉の最初のセグメント）
            # @return [Array<Hash>] 分類済みトークン
            def classify_tokens(segment, primary_context: false)
              tokens = []

              # スタイル（:stylename）
              if segment.match?(/\A:[a-zA-Z0-9_-]+\z/)
                tokens << { type: :style, value: segment.delete_prefix(':') }
                return tokens
              end

              # ソート（-field / +field）
              if segment.match?(/\A[+-][a-zA-Z_]/)
                tokens << { type: :sort, value: parse_sort(segment) }
                return tokens
              end

              # フィルタ条件（field=value, 比較演算子, AND/OR 複合条件）
              if segment.match?(/[=!<>]/) || segment.match?(AND_PATTERN)
                tokens << { type: :filter, value: parse_filter_expression(segment) }
                return tokens
              end

              # 主キー検索コンテキスト（単数形源泉の最初のセグメント）では
              # 数値も主キー検索値として扱う（code=13 のような検索に対応）
              if primary_context
                tokens << { type: :primary_lookup, value: build_primary_lookup(segment) }
                return tokens
              end

              # 件数（正の整数のみ）
              if segment.match?(/\A\d+\z/)
                tokens << { type: :limit, value: segment.to_i }
                return tokens
              end

              # 上記いずれにも該当しない場合は主キー検索
              tokens << { type: :primary_lookup, value: build_primary_lookup(segment) }
              tokens
            end

            # ソート指定をパースする
            # @param token [String] "-title" / "+title" / "title"
            # @return [Hash] { field:, direction: }
            def parse_sort(token)
              case token
              in /\A-(.+)\z/
                { field: $1.to_sym, direction: :desc }
              in /\A\+?(.+)\z/
                { field: $1.to_sym, direction: :asc }
              end
            end

            # 直前フィールドを引き継いで値のみの条件をパースする
            # @param field [Symbol, String] 直前フィールド
            # @param value_str [String] "ruby" / "ruby, beginner"
            # @return [Array<Hash>] フィルタ条件
            def parse_value_only_condition(field, value_str)
              parse_eq_condition(field, value_str)
            end

            # AND で接続されたフィルタ式をパースする
            # @param expression [String] "tags=ruby && category=web"
            # @return [Array<Hash>] フィルタ条件のリスト
            def parse_filter_expression(expression)
              # AND で分割
              clauses = expression.split(AND_PATTERN)
              previous_field = nil
              previous_filter = nil

              clauses.flat_map do |clause|
                clause = clause.strip
                next [] if clause.empty?

                parsed = parse_single_condition(clause)

                if parsed.empty? && previous_field
                  if previous_filter && previous_filter[:field] == previous_field && previous_filter[:op] == :eq
                    additional = parse_values(clause)
                    previous_filter[:value] = Array(previous_filter[:value]) + additional
                    next []
                  else
                    parsed = parse_value_only_condition(previous_field, clause)
                  end
                end

                last_filter = parsed.last
                previous_field = last_filter&.[](:field)
                previous_filter = last_filter if last_filter&.[](:op) == :eq

                parsed
              end
            end

            # 単一条件をパースする（OR はカンマ区切りで表現）
            # @param condition [String] "tags=ruby, javascript" / "temp>=20"
            # @return [Array<Hash>] フィルタ条件（1つまたは複数）
            def parse_single_condition(condition)
              # 比較演算子の検出（!=, >=, <=, >, <, ==, = の順で試行）
              case condition.strip
              in /\A([a-zA-Z_]+)\s*!=\s*(.+)\z/
                [{ field: $1.to_sym, op: :neq, value: parse_values($2) }]
              in /\A([a-zA-Z_]+)\s*>=\s*(.+)\z/
                [{ field: $1.to_sym, op: :gte, value: parse_numeric($2.strip) }]
              in /\A([a-zA-Z_]+)\s*<=\s*(.+)\z/
                [{ field: $1.to_sym, op: :lte, value: parse_numeric($2.strip) }]
              in /\A([a-zA-Z_]+)\s*>\s*(.+)\z/
                [{ field: $1.to_sym, op: :gt, value: parse_numeric($2.strip) }]
              in /\A([a-zA-Z_]+)\s*<\s*(.+)\z/
                [{ field: $1.to_sym, op: :lt, value: parse_numeric($2.strip) }]
              in /\A([a-zA-Z_]+)\s*={1,2}\s*(.+)\z/
                parse_eq_condition($1.strip, $2.strip)
              else
                # パースできない場合は空で返す
                []
              end
            end

            # 等値/範囲条件をパースする
            # @param field [String] フィールド名
            # @param value_str [String] "ruby, javascript" / "20..25" / "20...25"
            # @return [Array<Hash>] フィルタ条件
            def parse_eq_condition(field, value_str)
              field_sym = field.to_sym

              # 範囲指定の検出
              # 開始なし（...N / ..N）を先にチェックし、次に両端あり（N...M / N..M）をチェック
              if (m = value_str.match(/\A\.\.\.(\S+)\z/))
                # 上限のみ・排他的（field=...25 → 25未満）
                [{ field: field_sym, op: :lt, value: parse_numeric(m[1]) }]
              elsif (m = value_str.match(/\A\.\.(\S+)\z/))
                # 上限のみ（field=..25）
                [{ field: field_sym, op: :lte, value: parse_numeric(m[1]) }]
              elsif (m = value_str.match(/\A([^.]\S*)\.\.\.(\S+)\z/))
                # 排他的範囲（終端除く）: 20...25
                [{ field: field_sym, op: :range, value: parse_numeric(m[1])...parse_numeric(m[2]) }]
              elsif (m = value_str.match(/\A([^.]\S*)\.\.(\S+)\z/))
                # 包括的範囲: 20..25
                [{ field: field_sym, op: :range, value: parse_numeric(m[1])..parse_numeric(m[2]) }]
              elsif (m = value_str.match(/\A([^.]\S*)\.\.\z/))
                # 下限のみ（field=20..）
                [{ field: field_sym, op: :gte, value: parse_numeric(m[1]) }]
              else
                # 通常の等値条件（カンマ区切りでOR）
                [{ field: field_sym, op: :eq, value: parse_values(value_str) }]
              end
            end

            # カンマ区切りの値をリストとしてパースする
            # @param str [String] "ruby, javascript"
            # @return [Array<String>] ["ruby", "javascript"]
            def parse_values(str)
              str.split(',').map { it.strip }
            end

            # 数値文字列を適切な型に変換する
            # @param str [String] "20" / "3.14" / "東京"
            # @return [Integer, Float, String] 変換後の値
            def parse_numeric(str)
              s = str.strip
              case s
              when /\A-?\d+\z/    then s.to_i
              when /\A-?\d+\.\d+\z/ then s.to_f
              else s
              end
            end

            # 主キー候補フィールドによる一件検索フィルタを構築する
            # すべての主キー候補に対して OR 的に検索する
            # @param value [String] 検索値
            # @return [Array<Hash>] フィルタ条件（特殊な primary_key_lookup）
            def build_primary_lookup(value)
              parsed = parse_numeric(value)
              [{ field: :_primary_key, op: :eq, value: parsed }]
            end

            # パース結果のハッシュを構築する
            def build_result(source:, filters: [], sort: nil, limit: nil, style: nil, single_lookup: false)
              { source:, filters:, sort:, limit:, style:, single_lookup: }
            end
          end
        end
      end
    end
  end
end
