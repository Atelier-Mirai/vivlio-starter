# frozen_string_literal: true

module VivlioStarter
  module CLI
    module Guards
      # catalog.yml の区分の中が、原稿の番号の順に書かれているかを確かめる。
      #
      # 組版は区分の中を原稿の番号の順に並べる（ChapterConfig.htmls_for_kind）。一方、部の見出しと全巻目次は
      # catalog.yml に書いた順に並ぶ。書いた順が番号の順と違うと、目次と紙面がずれる。それを 🟡 で知らせる。
      #
      # 見るのは、catalog.yml にひと続きに書いた並び（区分ごと。分冊の本は巻ごとの区分と、本全体の前書き・後書き）。
      # 本全体の前書きと巻の前書きのように、別々の所に書いた並びは、番号の順で混ぜると決めてあるので比べない
      # （multivolume-book-matter-spec.md R3）。分冊の本はさらに、巻を区別せず番号の順に組む合本で、本文の章と付録が
      # 巻の順に並ぶかを見る。
      #
      # 知らせる原稿は、書いた並びから動かす数が一番少なくなるように選ぶ（最長増加部分列の外の原稿）。
      # [15, 11, 12, 13] なら 11・12・13 の三つでなく、15 の一つを知らせる。
      class CatalogOrderCheck < BaseCheck
        # 区分の呼び名（文面用）
        SECTION_NAMES = CatalogSectionCheck::SECTION_NAMES

        # 合本で巻をまたいで比べる区分。前書き・後書きは合本でも一つの巻（または本全体）の分しか載らない
        COMBINED_SECTIONS = %w[CHAPTERS APPENDICES].freeze

        # @return [Array<Violation>]
        def validate
          return [] unless File.file?(Build::CatalogLoader::CATALOG_FILE)

          catalog = Build::CatalogLoader.load_raw_catalog
          lines = File.readlines(Build::CatalogLoader::CATALOG_FILE, chomp: true)
          taken = ChapterNames.existing_basenames

          # --- Phase: 書いた並びごと ---
          warned = Set.new
          violations = written_lists(catalog).flat_map do |place, section, names|
            misplaced(names).map do |index|
              warned << names[index]
              order_warning(names, index, place:, section:, lines:, taken:)
            end
          end

          # --- Phase: 合本（巻をまたぐ並び） ---
          violations + combined_warnings(catalog, lines, taken, warned)
        rescue StandardError
          # 読めない catalog.yml は CatalogFileCheck が知らせる
          []
        end

        private

        # catalog.yml にひと続きに書いた並び。[置き場所の呼び名（巻の名前・「本全体」・nil）, 区分, basename の並び]
        def written_lists(catalog)
          lists = if Build::Volumes.defined_in?(catalog)
                    Build::Volumes.book_matter(catalog).map { |key, items| ['本全体', key, items] } +
                      Build::Volumes.list(catalog).flat_map do |volume|
                        volume.sections.map { |key, items| [volume.name, key, items] }
                      end
                  else
                    catalog.slice(*Build::CatalogLoader::SECTION_KEYS).map { |key, items| [nil, key, items] }
                  end
          lists.map { |place, key, items| [place, key, Build::CatalogLoader.flatten_section(items)] }
        end

        def combined_warnings(catalog, lines, taken, warned)
          return [] unless Build::Volumes.defined_in?(catalog)

          volumes = Build::Volumes.list(catalog)
          sections = Build::Volumes.combined_sections(volumes, catalog)
          COMBINED_SECTIONS.flat_map do |section|
            names = Build::CatalogLoader.flatten_section(sections[section])
            misplaced(names).reject { warned.include?(names[it]) }.map do |index|
              combined_warning(names, index, catalog:, section:, lines:, taken:)
            end
          end
        end

        # 番号の順に並べ直すとき、動かす原稿の添字。最長増加部分列に入らない原稿を返す
        # （組版と同じく、原稿の名前の文字列で比べる）
        # @param names [Array<String>]
        # @return [Array<Integer>]
        def misplaced(names)
          return [] if names.each_cons(2).all? { |a, b| a < b }

          lengths = Array.new(names.size, 1)
          previous = Array.new(names.size)
          names.each_index do |i|
            (0...i).each do |j|
              next unless names[j] < names[i] && lengths[j] + 1 > lengths[i]

              lengths[i] = lengths[j] + 1
              previous[i] = j
            end
          end

          kept = Set.new
          index = lengths.index(lengths.max)
          while index
            kept << index
            index = previous[index]
          end
          names.each_index.reject { kept.include?(it) }
        end

        def order_warning(names, index, place:, section:, lines:, taken:)
          name = names[index]
          others = names.reject { it == name }
          after = others.select { it < name }.max
          before = others.select { it > name }.min
          where = before ? "#{before} の前" : "#{after} の後ろ"
          heading = place ? "#{place}の#{SECTION_NAMES[section]}で、" : ''

          warning(
            "#{heading}#{location(name, lines)} の #{name} が、番号の順と違う所に書かれています。" \
            "紙面では #{where}に載るので、目次の並びと合いません",
            detail: [
              renumber_line(names, index, section, taken, '書いた所に載せるなら'),
              "番号の順でよいなら: この行を #{where}へ移す"
            ].compact
          )
        end

        # 合本では、巻の区別なく番号の順に組む。巻の中の並びは正しいので、行を動かすと巻が変わってしまう。
        # 番号の振り直しだけを案内する
        def combined_warning(names, index, catalog:, section:, lines:, taken:)
          name = names[index]
          others = names.reject { it == name }
          after = others.select { it < name }.max
          before = others.select { it > name }.min
          where = before ? "#{label(before, catalog)}の #{before} の前" : "#{label(after, catalog)}の #{after} の後ろ"
          volume = label(name, catalog)

          warning(
            "#{location(name, lines)} の #{name}（#{volume}）は、合本では #{where}に載ります。" \
            "合本の#{SECTION_NAMES[section]}が、巻の順に並びません",
            detail: renumber_line(names, index, section, taken, "#{volume}の位置に載せるなら") ||
                    '巻の順に並ぶように、原稿の番号を振り直してください（vs renumber）'
          )
        end

        def label(basename, catalog) = Build::Volumes.containing(basename, catalog)&.name.to_s

        # 書いた所のまま番号の順になる空き番号へ振り直す案内。前後の原稿の番号の間に空きが無ければ nil
        def renumber_line(names, index, section, taken, lead)
          kept = names.each_index.to_a - misplaced(names)
          lower = kept.select { it < index }.map { number_of(names[it]) }.max
          upper = kept.select { it > index }.map { number_of(names[it]) }.min
          range = section_range(section, names[index])
          free = ((lower ? lower + 1 : range.first)..(upper ? upper - 1 : range.last)).find do |number|
            range.cover?(number) && taken.none? { number_of(it) == number }
          end
          return nil unless free

          slug = ChapterNames.slug_of(names[index])
          renamed = slug ? "#{format('%02d', free)}-#{slug}" : format('%02d', free)
          "#{lead}: vs renumber #{names[index]} #{renamed}"
        end

        # 振り直してよい番号の範囲。本文の章・付録は区分の番号の範囲、前書き・後書きは巻ごとの前書き
        # （`20-vol2-intro`）のように範囲の外の番号も書けるので、すべての番号
        def section_range(section, basename)
          return 0..99 if %w[PREFACE POSTFACE].include?(section) || number_of(basename).nil?

          TokenResolver::Resolver::KIND_RANGES.fetch(TokenResolver::Resolver::SECTION_KINDS.fetch(section))
        end

        def number_of(basename) = ChapterNames.number_of(basename)&.to_i

        # 「config/catalog.yml:38」。行が見つからなければ（番号だけの項目 `- 22` で書いたなど）ファイル名だけ
        def location(basename, lines)
          pattern = /\A\s*-\s*#{Regexp.escape(basename)}(?:\.md)?\s*(?:#.*)?\z/
          index = lines.index { it.match?(pattern) }
          index ? "#{Build::CatalogLoader::CATALOG_FILE}:#{index + 1}" : Build::CatalogLoader::CATALOG_FILE
        end
      end
    end
  end
end
