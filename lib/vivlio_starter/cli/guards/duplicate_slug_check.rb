# frozen_string_literal: true

module VivlioStarter
  module CLI
    module Guards
      # 名前（slug）が同じで番号の違う章を検出する（pdf-read-file-naming-spec.md §7）。
      #
      # `01-sample` と `97-sample` は番号で指せば組めるが、`vs build sample` はエラーを出さずに片方だけを組み、
      # 章のラベル ID（名前から作る `@ch-sample`）は重なって、`@chapref:ch-sample` がどちらを指すか決まらない。
      # 著者もどちらの sample を書けばよいか迷う。止めて、2 つめ以降の名前を変えるコマンドを添える。
      #
      # 数えるのは contents/ の原稿と catalog.yml の章。大文字と小文字の違いだけの名前も同じとみなす。
      class DuplicateSlugCheck < BaseCheck
        def validate
          taken = ChapterNames.existing_basenames
          duplicated = duplicated_groups(taken)
          return [] if duplicated.empty?

          [error(
            "スラッグが同じ章があります（#{duplicated.size} 組）",
            detail: duplicated.flat_map { |slug, basenames| duplication_lines(slug, basenames, taken) } +
                    ['スラッグが同じだと、vs build のスラッグの指定や章の参照（@chapref）がどちらの章を指すか決められないため、止めています。']
          )]
        end

        # 重なっている名前（小文字。「sample」）。ChapterTargetCheck が、重なった名前の指定（`vs build sample`）を
        # 「見つかりません」と重ねて案内しないために使う
        # @return [Array<String>]
        def duplicated_slugs = duplicated_groups(ChapterNames.existing_basenames).keys

        private

        def duplicated_groups(taken)
          taken.select { ChapterNames.slug_of(it) }.group_by { ChapterNames.slug_of(it) }.select { |_, list| list.size > 1 }
        end

        # 重なった組の一覧と、2 つめ以降を「-2」などを足した名前へ変えるコマンド。
        # 残すのは決まりの形の名前を先にした 1 つめ。勧めた名前は taken へ足し、2 組以上あっても同じ名前を勧めない
        def duplication_lines(slug, basenames, taken)
          ordered = basenames.sort_by { [ChapterNames.valid?(it) ? 0 : 1, it] }
          lines = ["- #{slug}: #{ordered.map { "contents/#{it}.md" }.join('、')}"]
          ordered.drop(1).each do |basename|
            suggested = ChapterNames.suggestion(basename, taken)
            next unless suggested

            taken << suggested
            lines << "  → #{ChapterNames.rename_command(basename, suggested)}"
          end
          lines
        end
      end
    end
  end
end
