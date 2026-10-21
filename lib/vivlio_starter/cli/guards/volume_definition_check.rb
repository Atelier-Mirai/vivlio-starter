# frozen_string_literal: true

module VivlioStarter
  module CLI
    module Guards
      # catalog.yml の巻（VOLUMES）の書き方を確かめる（multivolume-spec.md §3.3）。
      #
      # 止めるのは、組む範囲やファイル名を決められない書き方だけ:
      #   - VOLUMES と、一番上の PREFACE・CHAPTERS などが同じファイルにある（どちらが目次か決められない）
      #   - 巻の name・id が無い、id の形が正しくない、id が all（ファイル名と --volume に使えない）
      #   - 二つの巻の id・name が同じ（--volume でどちらを指すか決められない）
      #   - 同じ本文の章を二つの巻に書いた（章番号が決まらない）
      # 前書き・付録・後書きは二つ以上の巻に書いてよい（共通の付録）。
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
           *duplicate_errors(volumes), *shared_chapter_errors(volumes),
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

        def mixed_sections_error(catalog)
          top = Build::CatalogLoader::SECTION_KEYS.select { catalog.key?(it) }
          return [] if top.empty?

          [error("config/catalog.yml に VOLUMES と、一番上の #{top.join('・')} が並んでいます",
                 detail: ['どちらが目次か決められないため、止めています。',
                          "→ 一番上の #{top.join('・')} を、どれかの巻の中へ移してください"])]
        end

        def volume_errors(volume)
          label = "#{volume.index + 1} 番目の巻#{"（#{volume.name}）" unless volume.name.empty?}"
          problems = []
          problems << "#{label}に name がありません（例: name: 上巻）" if volume.name.empty?
          if volume.id.empty?
            problems << "#{label}に id がありません（例: id: upper）"
          elsif !volume.id.match?(Build::Volumes::ID_PATTERN)
            problems << "#{label}の id #{volume.id} は、英小文字・数字・_ だけで書きます"
          elsif volume.id == Build::Volumes::ALL
            problems << "#{label}の id に all は使えません（vs build --volume all が全巻を組む指定のため）"
          end
          problems.map { error(it, detail: 'id は出力ファイル名と --volume に使います。') }
        end

        def duplicate_errors(volumes)
          %i[id name].flat_map do |attr|
            volumes.reject { it.public_send(attr).empty? }.group_by(&attr).select { |_, group| group.size > 1 }
                   .map do |value, _|
              error("二つ以上の巻の #{attr} が #{value} で同じです",
                    detail: '--volume でどの巻を指すか決められないため、止めています。巻ごとに違う値にしてください。')
            end
          end
        end

        def shared_chapter_errors(volumes)
          owners = Hash.new { |hash, key| hash[key] = [] }
          volumes.each do |volume|
            Build::CatalogLoader.flatten_section(volume.sections['CHAPTERS']).uniq.each { owners[it] << volume.name }
          end
          owners.select { |_, names| names.size > 1 }.map do |basename, names|
            error("本文の章 #{basename} が、#{names.join('と')}の二つの巻に書かれています",
                  detail: ['章番号が決まらないため、止めています。→ どちらか一方の巻から外してください',
                           '（前書き・付録・後書きは、二つ以上の巻に書けます）'])
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
                             "目次の区分: #{Build::CatalogLoader::SECTION_KEYS.join('・')}"])
          end
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
