# frozen_string_literal: true

require_relative '../masking'
require_relative 'container_scanner'
require_relative 'manuscript_scope'

module VivlioStarter
  module CLI
    module Guards
      # `:::{.text-table}`（本文の右に短い表を並べる）と `:::{.table-text}`（表の右に本文を並べる）の
      # 中身を点検する（text-table-spec.md §5・§13）。
      #
      # 指摘するのは、並べられない形の 3 通り:
      #   - 表が無い           … 表の列に置くものが無く、本文だけが全幅で組まれる
      #   - 表が二つ以上       … 表の列に置けるのは最初の 1 つだけで、残りは本文の列へ入る
      #   - .long-table などが中にある … 長い表・横長の表のための記法で、目的が逆
      #
      # 重大度は警告（🟡）。どれも組版は成立する（後処理が縮退して組む）ので、ビルドは止めない。
      # 表の行数と幅は調べない。空くかどうかは原稿の位置で決まり、紙面で著者が判断する（§3）。
      class TextTableCheck < BaseCheck
        include ManuscriptScope

        # 囲みのクラスと、本文から見た表の側（指摘の文に使う）
        TABLE_SIDE = { 'text-table' => '右', 'table-text' => '左' }.freeze
        # 中に入れても並べられない表の記法
        NESTED_TABLE_CLASSES = %w[long-table rotate-table].freeze
        # 表の区切り行（`|---|:--:|`）。`|` を少なくとも 1 つ含むものだけを数え、
        # 改ページの `---` を区切り行と取り違えない
        DELIMITER_ROW = /\A\s*\|?\s*:?-+:?\s*(?:\|\s*:?-+:?\s*)*\|?\s*\z/

        # @return [Array<Violation>] 警告の配列（合格なら空配列）
        def validate
          markdown_files.flat_map { check_file(it) }
        end

        private

        def check_file(path)
          directives = ContainerScanner.scan(path)
          prose = Masking.each_prose_line(File.read(path, encoding: 'utf-8')).to_a
          text_table_ranges(directives).flat_map do |open, close_line|
            inside = directives.select { open.line_number < it.line_number && it.line_number < close_line }
            lines = prose.select { |_line, lineno| open.line_number < lineno && lineno < close_line }
            violations_for(path, open, count_tables(lines), nested_tables(inside))
          end
        end

        # text-table・table-text の開始行と、対応する終了行の行番号の組。閉じ忘れなら原稿の終わりまで
        # （閉じ忘れそのものは ContainerFenceCheck が 🔴 で出す）
        def text_table_ranges(directives)
          stack = []
          ranges = []
          directives.each do |directive|
            if directive.kind == :open
              stack << directive
            elsif (open = stack.pop) && table_class(open)
              ranges << [open, directive.line_number]
            end
          end
          ranges + stack.select { table_class(it) }.map { [it, Float::INFINITY] }
        end

        def table_class(directive) = (directive.classes & TABLE_SIDE.keys).first

        # 見出し行（`|` を含む）の直後に区切り行がある所を、表の始まりとして数える
        def count_tables(lines)
          lines.each_cons(2).count do |(line, lineno), (following, following_no)|
            following_no == lineno + 1 && line.include?('|') &&
              following.include?('|') && following.match?(DELIMITER_ROW)
          end
        end

        def nested_tables(inside)
          inside.select { it.kind == :open }.flat_map(&:classes) & NESTED_TABLE_CLASSES
        end

        def violations_for(path, open, tables, nested)
          klass = table_class(open)
          side = TABLE_SIDE.fetch(klass)
          location = "#{path}:#{open.line_number} - :::{.#{klass}}"
          violations = []
          if tables.zero?
            violations << warning("#{location} の中に表がありません",
                                  detail: "→ 本文の#{side}に並べる表を囲みの中に書くか、:::{.#{klass}} を外してください")
          elsif tables > 1
            violations << warning("#{location} の中に表が #{tables} つあります",
                                  detail: "→ #{side}に並べられる表は 1 つだけです。囲みを表ごとに分けてください")
          end
          nested.each do |nested_class|
            violations << warning("#{location} の中では :::{.#{nested_class}} を使えません",
                                  detail: "→ 本文の#{side}に並べるのは短い表です。" \
                                          ":::{.#{nested_class}} の表は、囲みの外へ出してください")
          end
          violations
        end
      end
    end
  end
end
