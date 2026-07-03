# frozen_string_literal: true

module VivlioStarter
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

        # TokenResolver へ渡す 3 つ組。label は最内の部タイトル（なければセクション名）。
        # 仕様: docs/specs/catalog-parser-unification-spec.md §3.1
        CatalogEntry = Data.define(:basename, :label, :section)

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

        # catalog.yml を解析し、ラベル付きの章一覧を返す（TokenResolver の下層 API）。
        #
        # ファイル不在は [] を返す（TokenResolver の「カタログなしでも動く」契約を維持するため、
        # ビルド専用の load_all_basenames と違い raise しない）。空カタログ・重複番号の検証も
        # 行わない（それはビルド時の関心事 = load_all_basenames 側）。
        # 仕様: docs/specs/catalog-parser-unification-spec.md §3.1
        #
        # @param catalog_path [String] catalog.yml のパス（テスト用に注入可能）
        # @param contents_dir [String] ショートハンド展開時の glob 基点
        # @return [Array<CatalogEntry>]
        def load_labeled_entries(catalog_path: CATALOG_FILE, contents_dir: Common::CONTENTS_DIR)
          return [] unless File.exist?(catalog_path)

          catalog = load_catalog(catalog_path:)
          warn_unknown_sections(catalog)

          SECTION_KEYS.flat_map do |section|
            collect_labeled(catalog[section], label: section, section:, contents_dir:)
          end
        end

        # セクション内を再帰走査し、Hash キー（部タイトル）を label として伝播させつつ
        # ショートハンド（21-25 等）を展開する。
        # @return [Array<CatalogEntry>]
        def collect_labeled(items, label:, section:, contents_dir:)
          case items
          in nil then []
          in String | Integer
            expand_item(items, contents_dir:).map { CatalogEntry.new(basename: it, label:, section:) }
          in Array then items.flat_map { collect_labeled(it, label:, section:, contents_dir:) }
          in Hash  then items.flat_map { |k, v| collect_labeled(v, label: k.to_s, section:, contents_dir:) }
          else []
          end
        end

        # catalog.yml の未知トップレベルセクションを警告する（タイプミス検出）。
        # 有効セクションは catalog_spec が定める 4 種のみ。黙って落とすと調査困難なため知らせる。
        def warn_unknown_sections(catalog)
          (catalog.keys - SECTION_KEYS).each do |key|
            Common.log_warn("catalog.yml に未知のセクション '#{key}' があります（有効: #{SECTION_KEYS.join(' / ')}）")
          end
        end

        # catalog.yml を読み込み、YAML として返す
        #
        # セキュリティ設計（堅牢性仕様 9-7 対応）:
        #   - `safe_load` + `permitted_classes: []` により、
        #     Hash / Array / String / 数値 / Boolean / nil のみを許可する。
        #     Symbol / Time / Date も含まない最も厳しい制限。
        #   - `aliases: true` は DRY な catalog 記述のため許可するが、
        #     Psych 5.x の Billion Laughs 対策により DoS 耐性がある。
        #   - `!ruby/object` など許可されないクラスタグは `Psych::DisallowedClass` を
        #     発生させ、ユーザー向けの明示的なメッセージに変換する。
        #
        # @param catalog_path [String] catalog.yml のパス（テスト用に注入可能）
        # @return [Hash] catalog データ
        def load_catalog(catalog_path: CATALOG_FILE)
          raise StandardError, "catalog.yml が見つかりません: #{catalog_path}" unless File.exist?(catalog_path)

          content = File.read(catalog_path, encoding: 'utf-8')
          catalog = YAML.safe_load(content, permitted_classes: [], aliases: true)

          raise StandardError, 'catalog.yml の形式が不正です（Hash ではありません）' unless catalog.is_a?(Hash)

          catalog
        rescue Psych::SyntaxError => e
          raise StandardError, "catalog.yml のパースに失敗しました: #{e.message}"
        rescue Psych::DisallowedClass => e
          raise StandardError, <<~MSG.strip
            catalog.yml に許可されていないクラス/タグが含まれています: #{e.message}
            安全性のため、!ruby/object などの Ruby オブジェクト記法や !ruby/symbol は catalog.yml では使用できません。
            標準的な YAML（文字列・数値・配列・ハッシュ・真偽値）のみを記述してください。
          MSG
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
        # @param contents_dir [String] ショートハンド展開時の glob 基点
        # @return [Array<String>] basename 配列
        def expand_item(item, contents_dir: Common::CONTENTS_DIR)
          normalized = item.to_s.strip

          # .md 拡張子を除去
          normalized = normalized.sub(/\.md\z/, '')

          # ショートハンド判定
          if shorthand?(normalized)
            expand_shorthand(normalized, contents_dir:)
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
        # @param contents_dir [String] glob 基点
        # @return [Array<String>] basename 配列
        def expand_shorthand(str, contents_dir: Common::CONTENTS_DIR)
          numbers = parse_shorthand_to_numbers(str)
          numbers.flat_map { |num| find_basenames_by_number(num, contents_dir:) }
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
        # slug 付き（NN-*.md）に加え、番号のみファイル（NN.md）も拾う。番号のみファイルは
        # TokenResolver が従来サポートする章形態であり、これを glob 対象に含めないと
        # bare number の catalog エントリ（`- 15`）が脱落する（パーサ乖離の原因になっていた）。
        # @param num [Integer] 章番号
        # @param contents_dir [String] glob 基点
        # @return [Array<String>] basename 配列（見つからない場合は空。slug 付きを先に並べる）
        def find_basenames_by_number(num, contents_dir: Common::CONTENTS_DIR)
          padded = num.to_s.rjust(2, '0')
          slug_files = Dir.glob(File.join(contents_dir, "#{padded}-*.md"))
          numeric_file = File.join(contents_dir, "#{padded}.md")
          slug_files << numeric_file if File.exist?(numeric_file)

          slug_files.map { |f| File.basename(f, '.md') }
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

        # basename から章番号を抽出
        # @param basename [String]
        # @return [Integer, nil]
        def extract_chapter_number(basename)
          match = basename.to_s.match(/\A(\d{2})/)
          match ? match[1].to_i : nil
        end

      end
    end
  end
end
