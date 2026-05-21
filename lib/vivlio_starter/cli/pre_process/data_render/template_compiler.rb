# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/pre_process/data_render/template_compiler.rb
# ================================================================
# 責務:
#   テンプレートファイル（_book.md 等）にデータを流し込み、
#   Markdown を生成するコンパイラ。
#
# 変換ルール:
#   - `= key` のみの行 → key の値を展開（nil/空文字なら行スキップ）
#   - `prefix = key` → prefix を残してkey の値を展開
#   - `![](key)` → 変数展開（拡張子なし → 変数、拡張子あり → リテラル）
#   - `= key` を含まない行 → リテラル出力（ヘッダー等は一度だけ出力）
#   - 空行 → 改行出力
#
# テーブル記法対応:
#   `= key` を含む行のみ反復し、含まない行（ヘッダー・区切り行）は
#   一度だけ出力する。
# ================================================================

module VivlioStarter
  module CLI
    module PreProcessCommands
      module DataRender
        # テンプレートコンパイラモジュール
        module TemplateCompiler
          # 変数展開パターン: = key（行内に出現）
          VARIABLE_PATTERN = /(?<!=)=\s+([a-zA-Z_][a-zA-Z0-9_]*)/

          # 画像記法内の変数展開パターン: ![](key) / ![](= key)
          # 名前付きキャプチャで gsub ブロック内の $N 上書き問題を回避
          IMAGE_VAR_PATTERN = /!\[(?<alt>[^\]]*)\]\((?:=\s*)?(?<src>[^)]+)\)(?<attr>\{[^}]*\})?/

          # 画像の拡張子（リテラル判定用）
          IMAGE_EXTENSIONS = %w[png jpg jpeg webp gif svg].freeze

          module_function

          # テンプレートにレコード群を流し込んで Markdown を生成する
          # @param template [String] テンプレートの内容
          # @param records [Array<Hash>] データレコード群
          # @param source_filename [String, nil] エラー報告用ファイル名
          # @param line_number [Integer, nil] エラー報告用行番号
          # @return [String] 展開後の Markdown
          def render(template, records, source_filename: nil, line_number: nil)
            lines = template.lines
            validate_template_keys!(lines, records.first, source_filename:, line_number:) if records.any?

            # テンプレート行を「反復行」と「静的行」に分類する
            # = key を含む行は反復行、含まない行は静的行
            parts = classify_lines(lines)

            output = []
            records.each_with_index do |record, idx|
              # レコード間に空行を挿入（最初のレコード以外）
              output << "\n" if idx.positive?

              parts.each do |part|
                case part
                in { type: :static, content: }
                  # 静的行は最初のレコードでのみ出力
                  output << content if idx.zero?
                in { type: :dynamic, content: }
                  # 動的行はレコードごとに展開
                  expanded = expand_line(content, record)
                  output << expanded if expanded
                in { type: :blank }
                  # テンプレート内の空行は出力
                  output << "\n"
                end
              end
            end

            output.join
          end

          # テンプレート行を分類する
          # @param lines [Array<String>] テンプレートの行リスト
          # @return [Array<Hash>] 分類済み行リスト
          def classify_lines(lines)
            lines.map do |line|
              if line.strip.empty?
                { type: :blank }
              elsif contains_variable?(line)
                { type: :dynamic, content: line }
              else
                { type: :static, content: line }
              end
            end
          end

          # 行に変数参照（= key）が含まれるかを判定する
          # @param line [String] テンプレート行
          # @return [Boolean]
          def contains_variable?(line)
            return true if line.match?(VARIABLE_PATTERN)
            return true if line.match?(IMAGE_VAR_PATTERN) && image_has_variable?(line)

            false
          end

          # 画像記法内に変数参照があるかを判定する
          # @param line [String] テンプレート行
          # @return [Boolean]
          def image_has_variable?(line)
            line.scan(IMAGE_VAR_PATTERN).any? do |(_, src, _)|
              src = src.sub(/\A=\s*/, '').strip
              !literal_image?(src)
            end
          end

          # 画像パスがリテラル（拡張子あり）かを判定する
          # @param src [String] 画像パス文字列
          # @return [Boolean]
          def literal_image?(src)
            ext = File.extname(src).delete_prefix('.').downcase
            IMAGE_EXTENSIONS.include?(ext)
          end

          # テンプレート行をレコードデータで展開する
          # nil/空文字のキーがあれば行ごとスキップ（nil を返す）
          # @param line [String] テンプレート行
          # @param record [Hash] データレコード
          # @return [String, nil] 展開後の行、またはスキップ時 nil
          def expand_line(line, record)
            result = line.dup

            # 画像記法の展開（先に処理）
            result = expand_images(result, record)
            return nil unless result

            # = key パターンの展開
            result = expand_variables(result, record)
            return nil unless result

            result
          end

          # 画像記法内の変数を展開する
          # @param line [String] テンプレート行
          # @param record [Hash] データレコード
          # @return [String, nil] 展開後の行、またはスキップ時 nil
          def expand_images(line, record)
            result = line.dup
            skip = false

            result.gsub!(IMAGE_VAR_PATTERN) do |match|
              md   = Regexp.last_match
              alt  = md[:alt]
              src  = md[:src].sub(/\A=\s*/, '').strip
              attr = md[:attr] || ''

              if literal_image?(src)
                # 拡張子ありはリテラルとしてそのまま出力
                match
              else
                # 変数として展開
                value = record[src.to_sym]
                if value.nil? || value.to_s.strip.empty?
                  skip = true
                  match # gsub のブロックからは文字列を返す必要がある
                else
                  "![#{alt}](#{value})#{attr}"
                end
              end
            end

            skip ? nil : result
          end

          # = key パターンの変数を展開する
          # @param line [String] テンプレート行
          # @param record [Hash] データレコード
          # @return [String, nil] 展開後の行、またはスキップ時 nil
          def expand_variables(line, record)
            result = line.dup

            result.gsub!(VARIABLE_PATTERN) do |_match|
              key = ::Regexp.last_match(1).to_sym
              value = record[key]
              if value.nil? || value.to_s.strip.empty?
                return nil # 行ごとスキップ
              end

              value.to_s
            end

            result
          end

          # テンプレート内のキーがデータに存在するかを検証する
          # @param lines [Array<String>] テンプレートの行リスト
          # @param sample_record [Hash] サンプルレコード（最初の1件）
          # @param source_filename [String, nil] エラー報告用ファイル名
          # @param line_number [Integer, nil] エラー報告用行番号
          def validate_template_keys!(lines, sample_record, source_filename: nil, line_number: nil)
            return unless sample_record

            location = source_filename ? "#{source_filename}:#{line_number}" : ''
            available_keys = sample_record.keys

            lines.each do |line|
              # = key パターン
              line.scan(VARIABLE_PATTERN).each do |(key)|
                key_sym = key.to_sym
                next if available_keys.include?(key_sym)

                Common.log_error("テンプレートに存在しないキーが記述されています(#{location})")
                Common.log_error("  キー: #{key}")
                Common.log_error("  利用可能なキー: #{available_keys.join(', ')}")
                raise DataRenderError, "テンプレートに存在しないキーが記述されています: #{key}"
              end

              # 画像記法内の変数
              line.scan(IMAGE_VAR_PATTERN).each do |(_, src, _)|
                src = src.sub(/\A=\s*/, '').strip
                next if literal_image?(src)

                key_sym = src.to_sym
                next if available_keys.include?(key_sym)

                Common.log_error("テンプレートに存在しないキーが記述されています(#{location})")
                Common.log_error("  キー: #{src}")
                Common.log_error("  利用可能なキー: #{available_keys.join(', ')}")
                raise DataRenderError, "テンプレートに存在しないキーが記述されています: #{src}"
              end
            end
          end
        end
      end
    end
  end
end
