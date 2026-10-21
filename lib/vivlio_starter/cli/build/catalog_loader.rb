# frozen_string_literal: true

require_relative 'volumes'

module VivlioStarter
  module CLI
    module Build
      # ------------------------------------------------
      # CatalogLoader: catalog.yml からの章構成読み込み
      # ------------------------------------------------
      # config/catalog.yml を読み込み、フラットな章リストを返す。
      # PREFACE / CHAPTERS / APPENDICES / POSTFACE のセクション、
      # 部タイトルによるグルーピング、番号だけの項目（22）に対応。範囲（21-25）と一行の形は止める。
      # ------------------------------------------------
      module CatalogLoader
        module_function

        CATALOG_FILE = 'config/catalog.yml'

        # 章番号レンジ定数（新仕様）
        PREFACE_RANGE  = (0..0)
        MAIN_RANGE     = (1..89)
        APPX_RANGE     = (90..98)
        POSTFACE_RANGE = (99..99)

        # セクションキー
        SECTION_KEYS = %w[PREFACE CHAPTERS APPENDICES POSTFACE].freeze

        # TokenResolver へ渡す 3 つ組。label は最内の部タイトル（なければセクション名）。
        # 仕様: catalog-parser-unification-spec.md §3.1
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
        # 仕様: catalog-parser-unification-spec.md §3.1
        #
        # @param catalog_path [String] catalog.yml のパス（テスト用に注入可能）
        # @param contents_dir [String] 番号だけの項目を原稿の名前にするときの glob 基点
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
        # 番号だけの項目（22）を原稿の名前にする。
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
        # 分冊（VOLUMES）の本では、選んだ巻・合本・全巻のどれかの目次を、巻の無い目次と同じ形で返す
        # （Volumes.view・multivolume-spec.md §3.4）。目次を読むほかの処理を直さずに済ませるため。
        #
        # @param catalog_path [String] catalog.yml のパス（テスト用に注入可能）
        # @return [Hash] catalog データ
        def load_catalog(catalog_path: CATALOG_FILE) = Volumes.view(load_raw_catalog(catalog_path:))

        # catalog.yml を書かれたとおりに読む（VOLUMES を展開しない）
        # @param catalog_path [String] catalog.yml のパス
        # @return [Hash]
        def load_raw_catalog(catalog_path: CATALOG_FILE)
          raise StandardError, "catalog.yml が見つかりません: #{catalog_path}" unless File.exist?(catalog_path)

          content = File.read(catalog_path, encoding: 'utf-8')
          catalog = YAML.safe_load(content, permitted_classes: [], aliases: true)

          raise StandardError, unsectioned_catalog_message(catalog) unless catalog.is_a?(Hash)

          message = untrackable_entries_message(catalog, content)
          raise StandardError, message if message

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

        # 一番上に区分（PREFACE・CHAPTERS など）の無い catalog.yml の案内。原稿の名前を区分の
        # 下へ並べ直した例を、著者が書いた項目から番号で区分を決めて示す（そのまま写せば直る）
        # @param catalog [Array, String, Integer, nil] YAML として読んだ一番上の値
        # @return [String]
        def unsectioned_catalog_message(catalog)
          # 範囲（00-02）は原稿の名前に開いてから区分を分ける。前書きと本文の章をまたぐ範囲を
          # 一つの区分に置くと、区分で種類が決まるため本文の章まで前書きになる
          items = Array(catalog).flatten.map { it.to_s.strip.sub(/\.md\z/, '') }.reject(&:empty?).flat_map do |item|
            next [item] unless range_item?(item)

            names = numbers_in_range(item).flat_map { find_basenames_by_number(it) }
            names.empty? ? [item] : names
          end
          return "#{CATALOG_FILE} に、区分（#{SECTION_KEYS.join('・')}）が書かれていません" if items.empty?

          grouped = items.group_by { section_for_chapter_number(it[/\A\d+/]&.to_i || 1) }
          example = SECTION_KEYS.filter_map do |key|
            ["    #{key}:", *grouped[key].map { "      - #{it}" }] if grouped.key?(key)
          end
          ["#{CATALOG_FILE} の一番上には、区分（#{SECTION_KEYS.join('・')}）を書きます。いまは区分の無い並びになっています",
           '→ 原稿の名前を区分の下へ字下げして書いてください:',
           *example.flatten].join("\n")
        end

        # vs create・delete・rename・renumber が追えない書き方（番号の範囲 `- 21-23`、一行の形
        # `CHAPTERS: 11, 21-23, 31`）の案内。どれも行で書き換えられないので、範囲で書いた章を消しても
        # 範囲に番号が残り、改番すると別の章を指すようになる。番号を一つずつ書いたリストを示す。
        # 書けるのは原稿の名前（22-extensions）と番号（22。contents/22.md も指せる）だけ
        # @param catalog [Hash] catalog.yml
        # @param content [String] catalog.yml の中身（行番号を添えるため）
        # @return [String, nil] 案内。書き換えられない書き方が無ければ nil
        def untrackable_entries_message(catalog, content)
          lines = content.lines(chomp: true)
          blocks = sections_of(catalog).flat_map { |key, value| untrackable_blocks(key, value, lines) }
          return nil if blocks.empty?

          ["#{CATALOG_FILE} に、番号の範囲か一行の形で書いた章があります。章の追加・削除・改番で書き換えられないので、書けなくなりました",
           *blocks.flat_map do |block|
             ["  #{block[:where]}", *block[:before].map { "    #{it}" }, '  → リストの形で、章を一つずつ書いてください:', *block[:after].map { "    #{it}" }]
           end,
           '一部の章だけを組むなら、catalog.yml は変えずに vs build 21-23 のように範囲を打てます'].join("\n")
        end

        # 区分のキーと値の組（分冊の目次では、巻ごとの区分も）
        def sections_of(catalog)
          top = SECTION_KEYS.filter_map { [it, catalog[it]] if catalog.key?(it) }
          volumes = Array(catalog[Volumes::KEY]).select { it.is_a?(Hash) }.flat_map do |volume|
            SECTION_KEYS.filter_map { [it, volume[it]] if volume.key?(it) }
          end
          top + volumes
        end

        # 区分の値から、書き換えられない書き方を探す（部の中も探す）
        # @return [Array<Hash>] { where:, before:, after: }
        def untrackable_blocks(key, value, lines)
          case value
          in String | Integer
            line = lines.index { it.match?(/\A\s*#{key}:\s*[^\s#]/) }
            indent = line ? lines[line][/\A\s*/] : ''
            items = value.to_s.delete('[]').split(',').map(&:strip).reject(&:empty?)
            [{ where: location(line), before: ["#{indent}#{key}: #{value}"],
               after: ["#{indent}#{key}:", *items.flat_map { spelled_out(it) }.map { "#{indent}  - #{it}" }] }]
          in Array
            value.flat_map do |item|
              case item
              in Hash then item.values.flat_map { untrackable_blocks(key, it, lines) }
              in String if range_item?(item)
                line = lines.index { it.strip == "- #{item}" }
                indent = line ? lines[line][/\A\s*/] : '  '
                [{ where: location(line), before: ["#{indent}- #{item}"],
                   after: spelled_out(item).map { "#{indent}- #{it}" } }]
              else []
              end
            end
          else []
          end
        end

        def location(line) = line ? "#{CATALOG_FILE}:#{line + 1}" : CATALOG_FILE

        # 範囲（21-23・21-23, 25）か
        def range_item?(item) = item.to_s.strip.match?(/\A\d+\s*-\s*\d+(\s*,\s*\d+(\s*-\s*\d+)?)*\z/)

        # 範囲を番号一つずつに開く。原稿のある番号だけにし、一つも無ければ範囲の番号すべてにする
        # @return [Array<String>] 2 桁の番号、または範囲でなければそのまま
        def spelled_out(item)
          return [item] unless range_item?(item)

          numbers = numbers_in_range(item)
          existing = numbers.reject { find_basenames_by_number(it).empty? }
          (existing.empty? ? numbers : existing).map { format('%02d', it) }
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
        # @param item [String] basename または番号（22）
        # @param contents_dir [String] 番号を原稿の名前にするときの glob 基点
        # @return [Array<String>] basename 配列
        def expand_item(item, contents_dir: Common::CONTENTS_DIR)
          normalized = item.to_s.strip

          # .md 拡張子を除去
          normalized = normalized.sub(/\.md\z/, '')

          # 番号だけの項目（22）は、その番号の原稿を指す。範囲（21-23）は load_raw_catalog が止める
          normalized.match?(/\A\d+\z/) ? find_basenames_by_number(normalized.to_i, contents_dir:) : [normalized]
        end

        # 範囲（"21-25" や "21-25, 38"）を章番号の配列にする。catalog.yml には書けないので、
        # 案内で番号を一つずつに開くためと、区分の無い目次の範囲を区分に分けるために使う
        # @param str [String]
        # @return [Array<Integer>]
        def numbers_in_range(str)
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

        # number と同じ区分（まえがき・本文・付録・あとがき）で、used に無い一番小さい番号（「98」）。
        # 番号の重なりを知らせるとき、振り直す先を添えるのに使う。空きが無ければ nil
        # @param number [Integer]
        # @param used [Array<Integer>] 使われている番号
        # @return [String, nil]
        def free_number_in_section(number, used)
          range = [PREFACE_RANGE, MAIN_RANGE, APPX_RANGE, POSTFACE_RANGE].find { it.cover?(number) } || MAIN_RANGE
          free = range.find { !used.include?(it) }
          free && format('%02d', free)
        end

      end
    end
  end
end
