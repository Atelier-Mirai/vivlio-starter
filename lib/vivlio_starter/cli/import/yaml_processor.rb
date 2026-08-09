# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/import/yaml_processor.rb
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
#   - Build::CatalogLoader: catalog.yml の場所
#   - Common: ログ出力
# ================================================================

require 'fileutils'
require 'yaml'

require_relative '../build/catalog_loader'

module VivlioStarter
  module CLI
    module Import
      # YAML 設定ファイル変換モジュール
      module YamlProcessor
        module_function

        # Re:VIEW のセクション名と vivlio-starter のセクション名の対応
        CATALOG_KEY_MAP = {
          'PREDEF' => 'PREFACE',
          'CHAPS' => 'CHAPTERS',
          'APPENDIX' => 'APPENDICES',
          'POSTDEF' => 'POSTFACE'
        }.freeze

        # 行頭のセクション名。コメントアウトされた例（`##     PREDEF:`）も同時に直す
        CATALOG_KEY_PATTERN = /\A(\s*(?:#+\s*)?)(#{Regexp.union(CATALOG_KEY_MAP.keys)}):/

        # Re:VIEW の原稿拡張子。後ろに英数字が続かないときだけ落とす
        # （`.review` のような語を巻き込まないため）
        RE_EXTENSION_PATTERN = /\.re(?![A-Za-z0-9_])/

        # Re:VIEW Starter の判型と vivlio-starter の判型プリセットの対応
        PAGE_PRESETS = { 'A5' => 'a5_standard', 'B5' => 'b5_standard' }.freeze

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

          catalog_file = Build::CatalogLoader::CATALOG_FILE
          converted = File.readlines(starter_catalog, encoding: 'utf-8').map { convert_catalog_line(it) }

          FileUtils.mkdir_p(File.dirname(catalog_file))
          File.write(catalog_file, converted.join, encoding: 'utf-8')
          Common.log_info("  #{catalog_file} を更新しました（部・コメントは原文のまま）")
        end

        # catalog.yml の 1 行を変換する。
        #
        # YAML として読み書きすると「まだ有効にしていない章」を書き残したコメント行
        # （`# - lectures.re`）が消える。著者にとっては原稿の予定表そのものなので、
        # 行単位で置き換えて並び・部（部タイトル）・コメントを原文のまま残す。
        #
        # @param line [String] Re:VIEW の catalog.yml の 1 行
        # @return [String] 変換後の 1 行
        def convert_catalog_line(line)
          renamed = line.sub(CATALOG_KEY_PATTERN) do
            "#{Regexp.last_match(1)}#{CATALOG_KEY_MAP.fetch(Regexp.last_match(2))}:"
          end
          renamed.gsub(RE_EXTENSION_PATTERN, '')
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

        # 取り込んだ表紙を book.yml に反映する。
        #
        # 表紙は covers/frontcover_master.png・backcover_master.png として取り込むので、
        # book.yml 側も master テーマを指している必要がある。master は既定値でもあるが、
        # 著者が light/dark を選んだプロジェクトへ取り込むと持ち込んだ表紙が
        # 黙って無視されるため、ここで明示的に書く。
        #
        # @return [Boolean] 更新成功時 true
        def use_master_cover!
          update_book_yaml_with_values([[%w[output cover], 'master']])
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

          # 言語・ISBN
          updates << [%w[book language], config['language']] if config['language']
          updates << [%w[book isbn], config['isbn']] if config['isbn']

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

          # 判型
          preset = page_preset_for(config_starter.dig('starter', 'pagesize'))
          updates << [%w[page use], preset] if preset

          updates
        end

        # Re:VIEW Starter の判型に対応する判型プリセットを返す。
        #
        # 同じ判型の standard へ寄せる。行間や余白の好み（airy / compact）は
        # 取り込んだあとに著者が選び直すもので、Re:VIEW 側の値からは決められない。
        #
        # @param pagesize [String, nil] config-starter.yml の starter.pagesize
        # @return [String, nil] 判型プリセット名。対応が無ければ nil
        def page_preset_for(pagesize)
          key = pagesize.to_s.strip
          return nil if key.empty?

          preset = PAGE_PRESETS[key.upcase]
          return preset if preset

          Common.log_warn("  判型 #{key} に対応する判型プリセットがありません。",
                          detail: '対処: config/book.yml の page.use に ' \
                                  "#{PAGE_PRESETS.values.join(' / ')} などから選んで書いてください" \
                                  '（今回は雛形の判型のままにしました）。')
          nil
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
