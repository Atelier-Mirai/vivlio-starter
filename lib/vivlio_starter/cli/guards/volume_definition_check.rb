# frozen_string_literal: true

module VivlioStarter
  module CLI
    module Guards
      # catalog.yml の巻（VOLUMES）の書き方を確かめる（multivolume-spec.md §3.3）。
      #
      # 止めるのは、組む範囲やファイル名を決められない書き方だけ:
      #   - VOLUMES と、一番上の CHAPTERS・APPENDICES が同じファイルにある（どちらが目次か決められない）。
      #     一番上の PREFACE・POSTFACE は本全体の前書き・後書きなので通す（multivolume-book-matter-spec.md）
      #   - 巻の name・id が無い、id の形が正しくない、id が all（ファイル名と巻の指定に使えない）
      #   - 二つの巻の id・name が同じ（vs build upper でどちらを指すか決められない）
      # 前書き・付録・後書き、本文の章も、二つ以上の巻に書いてよい（共通の付録・共通の章。§3.6）。
      # 知らない設定キー・読めない chapter_start / appendix_start は、打ち間違いとして 🟡 で知らせる。
      # book.yml の ISBN を二つ以上の巻が上書きせずに使っているときも 🟡（同じ urn:isbn になる。§4.7）。
      class VolumeDefinitionCheck < BaseCheck
        # @return [Array<Violation>]
        def validate
          catalog = Build::CatalogLoader.load_raw_catalog
          return [] unless Build::Volumes.defined_in?(catalog)

          entries = catalog[Build::Volumes::KEY]
          return [shape_error] unless entries.is_a?(Array) && entries.all?(Hash)

          volumes = Build::Volumes.list(catalog)
          [*mixed_sections_error(catalog), *volumes.flat_map { volume_errors(it) },
           *duplicate_errors(volumes),
           *entries.each_with_index.flat_map { |entry, index| setting_warnings(entry, index) },
           *shared_isbn_warning(volumes)]
        rescue StandardError
          # 読めない catalog.yml は CatalogFileCheck が知らせる
          []
        end

        private

        def shape_error
          error('config/catalog.yml の VOLUMES は、巻ごとに「- name: 上巻」で始まる並びで書きます',
                detail: ['VOLUMES:', '  - name: 上巻', '    id: upper', '    CHAPTERS:', '      - 01-intro'])
        end

        # 一番上の PREFACE・POSTFACE は本全体の前書き・後書きなので止めない（multivolume-book-matter-spec.md R1）
        def mixed_sections_error(catalog)
          top = (Build::CatalogLoader::SECTION_KEYS - Build::Volumes::BOOK_MATTER_KEYS).select { catalog.key?(it) }
          return [] if top.empty?

          [error("config/catalog.yml に VOLUMES と、一番上の #{top.join('・')} が並んでいます",
                 detail: ['どちらが目次か決められないため、止めています。',
                          "→ 一番上の #{top.join('・')} を、どれかの巻の中へ移してください",
                          '一番上に書けるのは、書籍全体の前書き・後書き（PREFACE・POSTFACE）だけです。'])]
        end

        def volume_errors(volume)
          label = "#{volume.index + 1} 番目の巻#{"（#{volume.name}）" unless volume.name.empty?}"
          problems = []
          problems << "#{label}に name がありません（例: name: 上巻）" if volume.name.empty?
          if volume.id.empty?
            problems << "#{label}に id がありません（例: id: upper）"
          elsif !volume.id.match?(Build::Volumes::ID_PATTERN)
            problems << "#{label}の id #{volume.id} は、半角英字で始め、数字は末尾にだけ使います（例: upper・vol1）"
          elsif volume.id == Build::Volumes::ALL
            problems << "#{label}の id に all は使えません（vs build all が全巻を組む指定のため）"
          end
          problems.map { error(it, detail: 'id は出力ファイル名と、vs build upper のように巻を選ぶのに使います。') }
        end

        def duplicate_errors(volumes)
          %i[id name].flat_map do |attr|
            volumes.reject { it.public_send(attr).empty? }.group_by(&attr).select { |_, group| group.size > 1 }
                   .map do |value, _|
              error("二つ以上の巻の #{attr} が #{value} で同じです",
                    detail: 'どの巻を指すか決められないため、止めています。巻ごとに違う値にしてください。')
            end
          end
        end

        def setting_warnings(entry, index)
          unknown = entry.keys.reject do
            Build::Volumes::SETTING_KEYS.include?(it) || Build::CatalogLoader::SECTION_KEYS.include?(it)
          end
          warnings = unknown.map do |key|
            warning("#{index + 1} 番目の巻の #{key} は、巻に書けるキーではありません（使われません）",
                    detail: ["巻の設定: #{Build::Volumes::VOLUME_KEYS.join('・')}",
                             "書誌情報（book.yml の book: と同じ名前）: #{Build::Volumes::BOOK_KEYS.join('・')}",
                             "章扉・節絵: #{Build::Volumes::THEME_KEY}（#{Build::Volumes::THEME_KEYS.join('・')}）",
                             "目次の区分: #{Build::CatalogLoader::SECTION_KEYS.join('・')}"])
          end
          warnings.concat(theme_warnings(entry[Build::Volumes::THEME_KEY], index)) if entry.key?(Build::Volumes::THEME_KEY)
          start = entry['chapter_start']
          if start && !start.is_a?(Integer)
            warnings << warning("#{index + 1} 番目の巻の chapter_start: #{start} は数ではないので、前の巻から続けます",
                                detail: '→ chapter_start: 1 のように数で書いてください')
          end
          letter = entry['appendix_start']
          if letter && !letter.to_s.match?(/\A[A-Za-z]\z/)
            warnings << warning("#{index + 1} 番目の巻の appendix_start: #{letter} は記号 1 字ではないので、A から振ります",
                                detail: '→ appendix_start: A のように英字 1 字で書いてください')
          end
          warnings
        end

        # 巻の theme:（改善案 #186）。書けるのは章扉と節絵だけで、ほかのキーは組むときに使わない。
        # 画像が見つからないと、その巻を組んだときに既定の画像で代用されるので、組む前に知らせる
        # （preflight は合本の設定で走り、巻の画像を確かめる段が無い）
        def theme_warnings(theme, index)
          label = "#{index + 1} 番目の巻の theme"
          allowed = Build::Volumes::THEME_KEYS
          unless theme.is_a?(Hash)
            return [warning("#{label} は、frontispiece・ornament を並べて書きます（使われません）",
                            detail: ['theme:', '  frontispiece:', '    image: koubou_upper',
                                     '  ornament:', '    image: koubou_upper'])]
          end

          unknown = (theme.keys - allowed).map do |key|
            warning("#{label} の #{key} は、巻ごとには変えられません（使われません）",
                    detail: ["巻の theme: に書けるのは #{allowed.join('・')} だけです。",
                             "→ #{key} は config/book.yml の theme: に書き、本全体で一つにします"])
          end
          unknown + missing_image_warnings(theme.slice(*allowed), label)
        end

        def missing_image_warnings(images, label)
          return [] if Common::CONFIG.theme&.style.to_s.strip.downcase == 'simple'

          images.filter_map do |key, value|
            name = value.is_a?(Hash) ? value['image'] : value
            variant = key == 'frontispiece' ? :portrait : :landscape
            next if name.nil? || name.to_s.strip.empty? ||
                    PreProcessCommands::ThemeImageResolver.theme_image_available?(name, variant:)

            warning("#{label}.#{key} の画像 '#{name}' が見つかりません。この巻は既定の画像で組まれます",
                    detail: "→ stylesheets/images/#{name}.webp を置くか、画像の名前を確かめてください")
          end
        end

        # book.yml の ISBN を、二つ以上の巻が上書きせずに使っているか（multivolume-spec.md §4.7）。
        # 同じ urn:isbn の EPUB になり、ストアや読書アプリが同じ本とみなす。上書きしない巻が一つなら、
        # book.yml の ISBN をその巻のものとして書いたとみなす。isbn: "" と書いた巻は数えない。
        def shared_isbn_warning(volumes)
          isbn = book_yml_isbn
          sharing = volumes.select { it.settings['isbn'].nil? }
          return [] if isbn.empty? || sharing.size < 2

          lines = File.readlines(Build::CatalogLoader::CATALOG_FILE, chomp: true)
          example = sharing.last
          [warning("#{sharing.map(&:name).join('・')}が、book.yml の ISBN（#{isbn}）を共有しています",
                   detail: [sharing.map { volume_location(it, lines) }.join(' / '),
                            '→ 巻ごとに ISBN を書いてください。ISBN の無い巻は isbn: "" と書きます',
                            "  - name: #{example.name}", "    id: #{example.id}", '    isbn: "978-4-…"'])]
        end

        # 巻で上書きする前の book.yml の ISBN（CONFIG は巻の値を重ねた後でありうるので、ファイルから読む）
        def book_yml_isbn
          YAML.safe_load_file(Common::CONFIG_FILE, aliases: true)&.dig('book', 'isbn').to_s.strip
        rescue StandardError
          ''
        end

        def volume_location(volume, lines)
          pattern = /\A\s*-\s*name:\s*["']?#{Regexp.escape(volume.name)}["']?\s*(#.*)?\z/
          index = lines.index { it.match?(pattern) }
          "#{Build::CatalogLoader::CATALOG_FILE}#{":#{index + 1}" if index} #{volume.name}"
        end
      end
    end
  end
end
