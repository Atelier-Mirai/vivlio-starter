# frozen_string_literal: true

module VivlioStarter
  module CLI
    module Guards
      # catalog.yml の区分と、原稿の番号の範囲が食い違っていないかを確かめる（catalog-section-kind-spec.md §3）。
      #
      # 原稿の種類は、catalog.yml に書いた区分で決まる（番号より優先）。区分を優先したことで、
      # かつては番号どおりに組まれていた書き間違い（`90-x` を CHAPTERS に書いた）が、
      # 黙って本文の章として組まれるようになった。それを知らせる。
      #
      # 知らせるのは CHAPTERS・APPENDICES に、ほかの区分の番号の原稿が書かれているときだけ。
      # PREFACE・POSTFACE に 00・99 以外の番号を書くのは、巻ごとの前書き（`20-vol2-intro`）のための
      # 正しい書き方なので知らせない。前書き・後書きの番号は一つずつしかないからである。
      #
      # 同じ原稿を二つの区分に書いたときは、種類が決まらないので止める。
      class CatalogSectionCheck < BaseCheck
        # 番号から決めた区分で知らせる区分。PREFACE・POSTFACE は範囲の外の番号を書いてよい
        CHECKED_SECTIONS = %w[CHAPTERS APPENDICES].freeze

        # 区分の呼び名（文面用）
        SECTION_NAMES = { 'PREFACE' => '前書き', 'CHAPTERS' => '本文の章',
                          'APPENDICES' => '付録', 'POSTFACE' => '後書き' }.freeze

        # @return [Array<Violation>]
        def validate
          return [] unless File.file?(Build::CatalogLoader::CATALOG_FILE)

          entries = Build::CatalogLoader.load_labeled_entries
          lines = File.readlines(Build::CatalogLoader::CATALOG_FILE, chomp: true)
          conflicted = entries.group_by(&:basename).select { |_, group| group.map(&:section).uniq.size > 1 }

          [
            *conflicted.map { |basename, group| conflict_error(basename, group, lines) },
            *entries.uniq(&:basename).reject { conflicted.key?(it.basename) }.filter_map { mismatch_warning(it, lines) }
          ]
        rescue StandardError
          # 読めない catalog.yml は CatalogFileCheck が知らせる
          []
        end

        private

        def conflict_error(basename, group, lines)
          written = group.map(&:section).uniq.map { "#{it}（#{SECTION_NAMES[it]}）" }.join('と')
          error(
            "#{location(basename, lines)} の #{basename} が、#{written}の二つの区分に書かれています",
            detail: ['原稿の種類は書いた区分で決まるので、どちらとして組むか決められないため、止めています。',
                     '→ どちらか一方の行を消してください']
          )
        end

        def mismatch_warning(entry, lines)
          return nil unless CHECKED_SECTIONS.include?(entry.section)

          number = Build::CatalogLoader.extract_chapter_number(entry.basename)
          return nil unless number

          by_number = Build::CatalogLoader.section_for_chapter_number(number)
          return nil if by_number == entry.section

          warning(
            "#{location(entry.basename, lines)} に、#{SECTION_NAMES[by_number]}の番号の原稿 #{entry.basename} が " \
            "#{entry.section} に書かれています。#{SECTION_NAMES[entry.section]}として組みます",
            detail: [
              "#{SECTION_NAMES[by_number]}にするなら: この行を #{by_number} の下へ移す",
              renumber_line(entry)
            ].compact
          )
        end

        # 書いた区分のままにするなら、その区分の空き番号へ振り直す。空きが無ければ案内しない
        def renumber_line(entry)
          taken = ChapterNames.existing_basenames
          # 区分の範囲の最初の番号から空きを探す
          kind = TokenResolver::Resolver::SECTION_KINDS.fetch(entry.section)
          free = ChapterNames.free_number(TokenResolver::Resolver::KIND_RANGES.fetch(kind).first, taken)
          return nil unless free

          slug = ChapterNames.slug_of(entry.basename)
          renamed = slug ? "#{free}-#{slug}" : free
          "#{SECTION_NAMES[entry.section]}にするなら: vs renumber #{entry.basename} #{renamed}"
        end

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
