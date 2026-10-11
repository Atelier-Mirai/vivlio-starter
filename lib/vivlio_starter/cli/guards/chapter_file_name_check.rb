# frozen_string_literal: true

module VivlioStarter
  module CLI
    module Guards
      # 章のファイル名が `vs create` の作る形（`ChapterNames::VALID_BASENAME`）かを検証する
      # （pdf-read-file-naming-spec.md §7）。
      #
      # 番号で始まる原稿（contents/）と catalog.yml の章が対象。番号で始まらない原稿（メモなど）は章ではないので見ない。
      # 手で付けた名前はコマンドを通らないので、ここで止める。Finder の複製（「97-sample のコピー.md」）・版を付けた控え
      # （「97-sample.v2.md」）・`vs pdf:read` が作っていた名前（「01-vol.53_09_482.md」）は、どれも章の解決が
      # 別の章や存在しない原稿を指し、点を含む名前は全体ビルドを Errno::ENOENT で異常終了させていた。
      # 直す名前と、そのまま打てるコマンド（catalog.yml に載っていれば vs rename、載っていなければ mv）を添える。
      class ChapterFileNameCheck < BaseCheck
        def validate
          taken = ChapterNames.existing_basenames
          invalid = taken.select { it.match?(/\A\d/) && !ChapterNames.valid?(it) }
          return [] if invalid.empty?

          [error(
            "章のファイル名に使えない形があります（#{invalid.size} 件）",
            detail: invalid.flat_map { fix_lines(it, taken) } +
                    ['章のファイル名は、2 桁の番号と、英小文字・数字・ハイフンのスラッグで付けます（例: 11-intro、97-sample-2）。']
          )]
        end

        private

        # 直す名前は taken へ足し、2 件以上あっても同じ名前を勧めない
        def fix_lines(basename, taken)
          lines = ["- contents/#{basename}.md"]
          suggested = ChapterNames.suggestion(basename, taken)
          return lines unless suggested

          taken << suggested
          lines << "  → #{ChapterNames.rename_command(basename, suggested)}"
        end
      end
    end
  end
end
