# frozen_string_literal: true

require_relative 'container_scanner'
require_relative 'manuscript_scope'

module VivlioStarter
  module CLI
    module Guards
      # 縦書きの本の原稿に、縦書きでは使えない部品（novel-vertical-spec.md §3.4 の表の 3 段目）が
      # 書かれていれば、場所を 🟡 で示す。組み上がりは保証しない（組むのは止めない）。
      #
      # 一覧は S8-4 の材料の本で確かめて決めた（判断の軸: 崩れずに読めるか）。
      #   左右に並べる記法 … 縦の流れの中で横に並べる箱が、紙の外へはみ出す
      #   本の紹介のカード … 画像と字を横に並べるカードの形にならない
      #   表の回転         … 横書きの版面のために表を 90 度回す記法で、縦書きの本では向きが合わない
      # 会話・行番号つきのコード・サイドイメージ・画像と字を並べる記法は、崩れずに読めるので示さない。
      class VerticalPartsCheck < BaseCheck
        include ManuscriptScope

        # クラス → [部品の名前, 代わりの書き方]
        UNSUPPORTED = {
          'side-by-side' => ['左右に並べる記法', '箱を外し、二つを上下（前後）に並べて書いてください'],
          'book-card' => ['本の紹介のカード', '箱を外し、表紙の画像と紹介の文を順に書いてください'],
          'rotate-table' => ['表の回転', '箱を外し、表をそのまま書いてください（横組みの箱として組まれます）']
        }.freeze

        # @return [Array<Violation>]
        def validate
          return [] unless Common.traits.vertical?

          markdown_files.flat_map { check_file(it) }
        end

        private

        def check_file(path)
          ContainerScanner.scan(path).select { it.kind == :open }.flat_map do |directive|
            (directive.classes & UNSUPPORTED.keys).map { unsupported_warning(path, directive, it) }
          end
        end

        def unsupported_warning(path, directive, klass)
          label, fix = UNSUPPORTED.fetch(klass)
          warning("#{path}:#{directive.line_number} - 縦書きの本では#{label}（:::{.#{klass}}）を使えません",
                  detail: ["→ #{fix}"])
        end
      end
    end
  end
end
