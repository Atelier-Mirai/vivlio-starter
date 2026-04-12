# frozen_string_literal: true

# ================================================================
# File: lib/vivlio/starter/cli/import/yaml_processor.rb
# ================================================================
# 責務:
#   Re:VIEW Starter から vivlio-starter への YAML 設定ファイル変換を担当。
#
# 処理内容:
#   - catalog.yml の変換（キー名変更、.re 拡張子除去）
#   - config.yml / config-starter.yml から book.yml への変換
#   - コメント保持しながらの YAML 書き込み
#
# 依存:
#   - YAML: YAML パース
#   - Build::CatalogUpdater: catalog.yml 書き込み
#   - Common: ログ出力
# ================================================================

require 'yaml'

module Vivlio
  module Starter
    module CLI
      module Import
        # YAML 設定ファイル変換モジュール
        module YamlProcessor
          module_function

          # catalog.yml を変換する
          #
          # @param starter_dir [String] Starter プロジェクトのディレクトリ
          # @return [void]
          def convert_catalog!(starter_dir)
            Common.log_action('[Step 5] catalog.yml を変換します')

            starter_catalog = File.join(starter_dir, 'catalog.yml')
            unless File.exist?(starter_catalog)
              Common.log_warn("  catalog.yml が見つかりません: #{starter_catalog}")
              return
            end

            catalog = YAML.safe_load_file(starter_catalog, permitted_classes: [Symbol])

            key_map = {
              'PREDEF' => 'PREFACE',
              'CHAPS' => 'CHAPTERS',
              'APPENDIX' => 'APPENDICES',
              'POSTDEF' => 'POSTFACE'
            }

            new_catalog = {}
            catalog.each do |key, value|
              new_key = key_map[key] || key
              new_catalog[new_key] = strip_re_extension(value)
            end

            Build::CatalogUpdater.save_catalog(new_catalog)
            Common.log_info('  config/catalog.yml を更新しました（コメント保持）')
          end

          # config.yml / config-starter.yml を book.yml に変換する
          #
          # @param starter_dir [String] Starter プロジェクトのディレクトリ
          # @return [void]
          def convert_config!(starter_dir)
            Common.log_action('[Step 6] config.yml を変換します')

            starter_config = File.join(starter_dir, 'config.yml')
            starter_config_starter = File.join(starter_dir, 'config-starter.yml')

            unless File.exist?(starter_config)
              Common.log_warn("  config.yml が見つかりません: #{starter_config}")
              return
            end

            config = YAML.safe_load_file(starter_config, permitted_classes: [Symbol])
            config_starter = if File.exist?(starter_config_starter)
                               YAML.safe_load_file(starter_config_starter, permitted_classes: [Symbol])
                             else
                               {}
                             end

            updates = build_config_updates(config, config_starter)

            if update_book_yaml_with_values(updates)
              Common.log_info('  config/book.yml を更新しました（コメント保持）')
            else
              Common.log_info('  config/book.yml に反映すべき値がありませんでした')
            end
          end

          # 表紙設定を book.yml に反映する
          #
          # @param cover_filename [String] 表紙ファイル名（例: hyoshi.pdf）
          # @return [Boolean] 更新成功時 true
          def update_cover_config!(cover_filename)
            return false unless cover_filename

            updates = [[%w[output pdf cover front], cover_filename]]
            update_book_yaml_with_values(updates)
          end

          # .re 拡張子を再帰的に除去する
          #
          # @param value [Object] YAML 値
          # @return [Object] .re を除去した値
          def strip_re_extension(value)
            case value
            when Array
              value.map { |v| strip_re_extension(v) }
            when Hash
              value.transform_keys { |k| k.to_s.sub(/\.re$/, '') }
                   .transform_values { |v| strip_re_extension(v) }
            when String
              value.sub(/\.re$/, '')
            else
              value
            end
          end

          # config.yml / config-starter.yml から更新リストを構築する
          #
          # @param config [Hash] config.yml の内容
          # @param config_starter [Hash] config-starter.yml の内容
          # @return [Array<Array>] 更新リスト（[path, value] の配列）
          def build_config_updates(config, config_starter)
            updates = []

            # 書籍タイトル
            main_title = extract_text(config['booktitle']) if config['booktitle']
            updates << [%w[book main_title], main_title] if main_title && !main_title.empty?

            # サブタイトル
            subtitle = extract_text(config['subtitle']) if config['subtitle']
            updates << [%w[book subtitle], subtitle] if subtitle && !subtitle.empty?

            # 言語
            updates << [%w[book language], config['language']] if config['language']

            # プロジェクト名・バージョン
            if config['bookname']
              updates << [%w[project name], config['bookname']]
              updates << [%w[project version], '0.1.0']
            end

            # 著者
            if config['aut']
              authors = Array(config['aut'])
              author_names = authors.map { |a| a.is_a?(Hash) ? a['name'] : a.to_s }
                                    .reject { |name| name.to_s.strip.empty? }
              updates << [%w[book author], author_names.first] if author_names.any?
            end

            # additional フィールドから発行者・連絡先を抽出
            updates.concat(extract_additional_fields(config['additional'])) if config['additional']

            # 発行履歴
            if config['history']
              history = Array(config['history']).flatten
              release = history.find { |entry| !extract_text(entry).to_s.empty? }
              release_text = extract_text(release) if release
              updates << [%w[book release], release_text] if release_text && !release_text.empty?
            end

            # イベント名
            updates << [%w[book series], config['pubevent_name']] if config['pubevent_name']

            # ページサイズ
            if config_starter.dig('starter', 'pagesize')
              pagesize = config_starter.dig('starter', 'pagesize')
              page_use = case pagesize.to_s.upcase
                         when 'B5' then 'b5_airy'
                         when 'A5' then 'a5_compact'
                         else 'a4_standard'
                         end
              updates << [%w[page use], page_use]
            end

            updates
          end

          # additional フィールドから発行者・連絡先を抽出
          def extract_additional_fields(additional)
            updates = []
            additional.each do |item|
              next unless item.is_a?(Hash)

              case item['key']
              when '発行者'
                value = extract_text(item['value'])
                updates << [%w[book publisher], value] if value && !value.empty?
              when '連絡先'
                contacts = Array(item['value'])
                email = contacts.find { |c| c.to_s.include?('@') }
                updates << [%w[book contact], email] if email
              end
            end
            updates
          end

          # 複数行テキストやハッシュから文字列を抽出
          def extract_text(value)
            case value
            when Hash
              value['name'] || value.values.first
            when String
              value.gsub("\n", ' ').strip
            else
              value.to_s
            end
          end

          # book.yml を更新する
          #
          # @param updates [Array<Array>] 更新リスト（[path, value] の配列）
          # @return [Boolean] 更新が行われた場合 true
          def update_book_yaml_with_values(updates)
            book_yml_path = 'config/book.yml'
            unless File.exist?(book_yml_path)
              Common.log_warn("  #{book_yml_path} が見つからなかったため、更新をスキップします")
              return false
            end

            lines = File.readlines(book_yml_path, encoding: 'utf-8')
            updated = false

            updates.each do |path, value|
              next if value.nil?

              replaced = replace_yaml_value_in_lines!(lines, path, value)
              Common.log_warn("  #{book_yml_path} 内で #{path.join('.')} を更新できませんでした") unless replaced
              updated ||= replaced
            end

            File.write(book_yml_path, lines.join, encoding: 'utf-8') if updated
            updated
          end

          # YAML 行内の値を置換する
          def replace_yaml_value_in_lines!(lines, path, value)
            stack = []

            lines.each_with_index do |line, idx|
              next if line.lstrip.start_with?('#')

              match = line.match(/^(\s*)([A-Za-z0-9_]+):(.*)$/)
              next unless match

              indent = match[1].length
              key = match[2]

              stack.pop while stack.any? && stack.last[:indent] >= indent
              stack << { key: key, indent: indent }

              next unless stack.map { |item| item[:key] } == path

              comment = match[3]&.match(/(\s+#.*)$/)&.[](1)
              scalar = format_yaml_scalar(value)
              new_line = "#{match[1]}#{key}: #{scalar}"
              new_line += comment.to_s
              new_line << "\n"
              lines[idx] = new_line
              return true
            end

            false
          end

          # YAML スカラー値をフォーマットする
          def format_yaml_scalar(value)
            case value
            when Numeric
              value.to_s
            when TrueClass, FalseClass
              value.to_s
            else
              str = value.to_s
              return "''" if str.empty?

              escaped = str.gsub(/["\\]/) { |m| "\\#{m}" }
              "\"#{escaped}\""
            end
          end
        end
      end
    end
  end
end
