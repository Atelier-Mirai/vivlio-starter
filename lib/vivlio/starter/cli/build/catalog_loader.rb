# frozen_string_literal: true

module Vivlio
  module Starter
    module CLI
      module Build
        # ------------------------------------------------
        # CatalogLoader: catalog.yml からの章構成読み込み
        # ------------------------------------------------
        # config/catalog.yml を読み込み、フラットな章リストを返す。
        # PREFACE / CHAPTERS / APPENDICES / POSTFACE のセクション、
        # 部タイトルによるグルーピング、ショートハンド（21-25 等）に対応。
        # ------------------------------------------------
        module CatalogLoader
          module_function

          CATALOG_FILE = 'config/catalog.yml'

          # 章番号レンジ定数（新仕様）
          PREFACE_RANGE  = (0..0)
          MAIN_RANGE     = (1..89)
          APPX_RANGE     = (90..98)
          POSTFACE_RANGE = (99..99)

          # 特殊ページの内部 basename
          SPECIAL_PAGES = %w[_titlepage _legalpage _colophon _indexpage _glossarypage].freeze

          # セクションキー
          SECTION_KEYS = %w[PREFACE CHAPTERS APPENDICES POSTFACE].freeze

          # 章番号からセクションを決定
          # @param num [Integer] 章番号
          # @return [String] セクションキー
          def section_for_chapter_number(num)
            case num
            when PREFACE_RANGE  then 'PREFACE'
            when MAIN_RANGE     then 'CHAPTERS'
            when APPX_RANGE     then 'APPENDICES'
            when POSTFACE_RANGE then 'POSTFACE'
            else 'CHAPTERS' # デフォルト
            end
          end

          # catalog.yml を読み込み、フラットな basename 配列を返す
          # @return [Array<String>] basename 配列（拡張子なし）
          def load_all_basenames
            catalog = load_catalog
            validate_catalog!(catalog)

            basenames = []
            SECTION_KEYS.each do |section|
              items = catalog[section]
              next if items.nil? || items.empty?

              basenames.concat(flatten_section(items))
            end

            # 重複除去・ソート
            basenames = basenames.uniq
            validate_no_duplicates!(basenames)

            basenames
          end

          # catalog.yml を読み込み、存在するファイルのみをフィルタした basename 配列を返す
          # @return [Array<String>] 存在するファイルの basename 配列
          def load_existing_basenames
            basenames = load_all_basenames
            existing = []
            missing = []

            basenames.each do |bn|
              path = File.join(Common::CONTENTS_DIR, "#{bn}.md")
              if File.exist?(path)
                existing << bn
              else
                missing << bn
              end
            end

            # 存在しないファイルは警告
            missing.each do |bn|
              Common.log_warn("catalog.yml に記載された章ファイルが存在しません: contents/#{bn}.md")
            end

            existing
          end

          # catalog.yml を読み込み、YAML として返す
          # @return [Hash] catalog データ
          def load_catalog
            raise StandardError, "catalog.yml が見つかりません: #{CATALOG_FILE}" unless File.exist?(CATALOG_FILE)

            content = File.read(CATALOG_FILE, encoding: 'utf-8')
            catalog = YAML.safe_load(content, permitted_classes: [], aliases: true)

            raise StandardError, 'catalog.yml の形式が不正です（Hash ではありません）' unless catalog.is_a?(Hash)

            catalog
          rescue Psych::SyntaxError => e
            raise StandardError, "catalog.yml のパースに失敗しました: #{e.message}"
          end

          # catalog のバリデーション
          def validate_catalog!(catalog)
            # 全セクションが空の場合はエラー
            total = SECTION_KEYS.sum { |key| Array(catalog[key]).size }
            return unless total.zero?

            raise StandardError, 'catalog.yml にビルド対象の章がありません'
          end

          # 章番号の重複チェック
          def validate_no_duplicates!(basenames)
            number_to_basenames = Hash.new { |h, k| h[k] = [] }

            basenames.each do |bn|
              num = extract_chapter_number(bn)
              next unless num

              number_to_basenames[num] << bn
            end

            duplicates = number_to_basenames.select { |_num, list| list.size > 1 }
            return if duplicates.empty?

            error_msg = "同一章番号で複数のファイルが存在します:\n"
            duplicates.each do |num, list|
              error_msg += "  章番号 #{num}: #{list.join(', ')}\n"
            end
            raise StandardError, error_msg
          end

          # セクションの内容をフラットな basename 配列に展開
          # @param items [Array] セクション内のアイテム
          # @return [Array<String>] basename 配列
          def flatten_section(items)
            result = []

            Array(items).each do |item|
              case item
              when String, Integer
                result.concat(expand_item(item))
              when Hash
                item.each_value do |sub_items|
                  result.concat(flatten_section(sub_items))
                end
              end
            end

            result
          end

          # アイテム（文字列）を basename 配列に展開
          # @param item [String] basename またはショートハンド
          # @return [Array<String>] basename 配列
          def expand_item(item)
            normalized = item.to_s.strip

            # .md 拡張子を除去
            normalized = normalized.sub(/\.md\z/, '')

            # ショートハンド判定
            if shorthand?(normalized)
              expand_shorthand(normalized)
            else
              [normalized]
            end
          end

          # ショートハンド（番号・範囲指定）かどうか判定
          # @param str [String]
          # @return [Boolean]
          def shorthand?(str)
            # "21" や "21-25" や "21-25, 38" の形式
            str.match?(/\A[\d\s,-]+\z/) && !str.match?(/\A\d+-[a-zA-Z]/)
          end

          # ショートハンドを展開して basename 配列を返す
          # @param str [String] "21-25" や "21-25, 38" 形式
          # @return [Array<String>] basename 配列
          def expand_shorthand(str)
            numbers = parse_shorthand_to_numbers(str)
            numbers.flat_map { |num| find_basenames_by_number(num) }
          end

          # ショートハンド文字列を章番号配列に変換
          # @param str [String]
          # @return [Array<Integer>]
          def parse_shorthand_to_numbers(str)
            parts = str.split(/[,\s]+/).map(&:strip).reject(&:empty?)
            numbers = []

            parts.each do |part|
              if part.match?(/\A\d+-\d+\z/)
                # 範囲指定
                match = part.match(/\A(\d+)-(\d+)\z/)
                start_num = match[1].to_i
                end_num = match[2].to_i
                numbers.concat((start_num..end_num).to_a) if start_num <= end_num
              elsif part.match?(/\A\d+\z/)
                # 単一番号
                numbers << part.to_i
              end
            end

            numbers.uniq.sort
          end

          # 章番号に対応する basename を contents/ から検索
          # @param num [Integer] 章番号
          # @return [Array<String>] basename 配列（見つからない場合は空）
          def find_basenames_by_number(num)
            pattern = File.join(Common::CONTENTS_DIR, "#{num.to_s.rjust(2, '0')}-*.md")
            files = Dir.glob(pattern)

            files.map { |f| File.basename(f, '.md') }
          end

          # catalog.yml から部タイトル情報を抽出する
          # CHAPTERS 配列内の Hash キーを部タイトルとして認識し、出現順に番号を付与する
          # @return [Array<Hash>] 部情報の配列
          #   各要素: { number:, title:, first_chapter:, chapters: }
          def load_part_titles
            catalog = load_catalog
            items = catalog['CHAPTERS']
            return [] unless items.is_a?(Array)

            part_number = 0
            items.filter_map do |item|
              next unless item.is_a?(Hash)

              item.filter_map do |title, sub_items|
                chapter_basenames = flatten_section(sub_items)
                # 章が0件の部（全コメントアウト等）はスキップ
                next if chapter_basenames.empty?

                part_number += 1
                first_chapter_num = chapter_basenames.first&.then { extract_chapter_number(it) }

                { number: part_number, title: title.to_s,
                  first_chapter: first_chapter_num, chapters: chapter_basenames }
              end
            end.flatten
          end

          # 特殊ページ（システム生成）かどうかを判定する
          # _titlepage, _colophon 等の固定ページに加え、_part{N} も対象
          # @param basename [String]
          # @return [Boolean]
          def special_page?(basename)
            SPECIAL_PAGES.include?(basename) || basename.match?(/\A_part\d+\z/)
          end

          # basename から章番号を抽出
          # @param basename [String]
          # @return [Integer, nil]
          def extract_chapter_number(basename)
            match = basename.to_s.match(/\A(\d{2})/)
            match ? match[1].to_i : nil
          end

          # ショートハンドと basename の重複をチェック
          # @param basenames [Array<String>]
          # @return [Array<String>] 重複している basename
          def check_shorthand_overlap(basenames)
            seen = {}
            duplicates = []

            basenames.each do |bn|
              if seen[bn]
                duplicates << bn
              else
                seen[bn] = true
              end
            end

            duplicates
          end
        end
      end
    end
  end
end
