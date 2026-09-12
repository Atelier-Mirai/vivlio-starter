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
      # 決められなくなる**——`vs build 02-vivlio` のような単章ビルドが
      # 「catalog.yml に無い」と言って止まる。原因がファイル名にあると気づきにくい
      # ので、ビルドの手前で名指しして知らせる。
      #
      # 警告にとどめるのは、番号が重なっていても catalog.yml に載せるのが片方だけなら
      # 本は組めるため（下書きを別名で置いている途中など）。
      class DuplicateNumberCheck < BaseCheck
        # `01-intro` のように「数字 + ハイフン」で始まる basename の、数字の部分
        NUMBER_PREFIX = /\A(\d+)-/

        def validate
          duplicated = numbered_basenames.group_by { it.first }.select { |_, entries| entries.size > 1 }
          return [] if duplicated.empty?

          [warning(
            "章番号が重複している原稿があります（#{duplicated.size} 組）",
            detail: duplicated.map { |number, entries| duplication_line(number, entries) } +
                    ['対処: vs renumber で振り直すか、どちらかの番号を変えてください。',
                     '番号が重なっていると、その番号でどちらを指すか決められず、単章ビルドが止まります。']
          )]
        end

        private

        def duplication_line(number, entries)
          "- #{number}: #{entries.map { |_, basename| "contents/#{basename}.md" }.join('、')}"
        end

        # アンダースコア始まり（_titlepage 等のシステムページ）と、
        # 番号を持たないファイルは対象外
        def numbered_basenames
          Dir.glob(File.join(Common::CONTENTS_DIR, '*.md'))
             .map { File.basename(it, '.md') }
             .reject { it.start_with?('_') }
             .sort
             .filter_map { |basename| [Regexp.last_match(1), basename] if NUMBER_PREFIX.match(basename) }
        end
      end
    end
  end
end
