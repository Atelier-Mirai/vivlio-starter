# frozen_string_literal: true

module VivlioStarter
  module CLI
    module Guards
      # 章番号が重複している原稿を検出する。
      #
      # `vs create` / `vs rename` / `vs renumber` を通しているかぎり起きないが、
      # 著者がファイル名を手で変えたときや、catalog.yml でコメントアウトを
      # 外し損ねたときに起こる。
      #
      # 番号は Entry の同一性の軸なので、重なると**その番号でどちらを指すか
      # 決められなくなる**——`vs build 97` が 97-foo と 97-sample のどちらを組むか
      # 決められない。かつては警告にとどめ、目次の読み込みが重なった片方を黙って外していたため、
      # 全体ビルドがその章を抜いたまま組み上がっていた。止めて、振り直すコマンドを添える。
      #
      # contents/ の原稿に加えて、catalog.yml に載っている章（原稿がまだ無いものも）を数える。
      class DuplicateNumberCheck < BaseCheck
        # basename の頭の番号。章の解決と同じく `_` も区切りとみなし（`97_sample` も 97 番）、番号だけの章（`15`）も数える
        NUMBER_PREFIX = /\A(\d+)(?=[-_]|\z)/

        def validate
          numbered = numbered_basenames
          duplicated = duplicated_groups(numbered)
          return [] if duplicated.empty?

          taken = numbered.map(&:last)
          [error(
            "章番号が重複している原稿があります（#{duplicated.size} 組）",
            detail: duplicated.flat_map { |number, entries| duplication_lines(number, entries.map(&:last), taken) } +
                    ['番号が重なっていると、その番号でどちらの章を指すか決められないため、止めています。']
          )]
        end

        # 重なっている番号（「97」）。ChapterTargetCheck が、重なった番号の指定（`vs build 97`）を
        # 「見つかりません（もしかして 97-sample）」と重ねて案内しないために使う
        # @return [Array<String>]
        def duplicated_numbers = duplicated_groups(numbered_basenames).keys

        private

        def duplicated_groups(numbered) = numbered.group_by(&:first).select { |_, entries| entries.size > 1 }

        # 重なった組の一覧と、2 つめ以降の名前を変えるコマンド（番号は同じ区分の空き番号、使えない字は直す）。
        # 残すのは決まりの形の名前を先にした 1 つめ。勧めた名前は taken へ足し、2 組以上あっても同じ名前を勧めない
        def duplication_lines(number, basenames, taken)
          ordered = basenames.sort_by { [ChapterNames.valid?(it) ? 0 : 1, it] }
          lines = ["- #{number}: #{ordered.map { "contents/#{it}.md" }.join('、')}"]
          ordered.drop(1).each do |basename|
            suggested = ChapterNames.suggestion(basename, taken)
            next unless suggested

            taken << suggested
            lines << "  → #{ChapterNames.rename_command(basename, suggested)}"
          end
          lines
        end

        # 番号を持たないものは対象外。番号は書かれた桁のまま比べる（`02` と `020` は別）
        # @return [Array<Array(String, String)>] [番号, basename] の組
        def numbered_basenames
          ChapterNames.existing_basenames
                      .filter_map { |basename| [Regexp.last_match(1), basename] if NUMBER_PREFIX.match(basename) }
        end
      end
    end
  end
end
