# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/import/re_parser.rb
# ================================================================
# 責務:
#   Re:VIEW / Starter の原稿（.re）1 章を読み、ノードの木にする。
#   記法の対応づけは行わない——ここは「構文を読む」だけで、
#   「何へ変換するか」は ReRenderer が持つ（re-direct-import-spec.md §5.1）。
#
# 文法の正典:
#   Re:VIEW Starter 同梱の review-compiler.rb（parse_document / parse_list /
#   read_block）。行頭だけを見て上から順に分岐する（同 §2.1）。
# ================================================================

require_relative 're_report'

module VivlioStarter
  module CLI
    module Import
      # .re をノードの木にする
      module ReParser
        module_function

        # --- ノード（すべて行番号を持つ。file:line 付きの通知に要る）---
        Heading = Data.define(:level, :id, :tag, :text, :line)
        Paragraph = Data.define(:lines, :line)
        Block = Data.define(:name, :args, :body, :children, :line)
        Command = Data.define(:name, :args, :line)
        UList = Data.define(:items, :line)
        OList = Data.define(:items, :line)
        DList = Data.define(:items, :line)

        # 箇条書き・番号リストの 1 項目。continuation は次行以降の折り返し
        Item = Data.define(:level, :marker, :text, :continuation)
        # 定義リストの 1 項目
        Term = Data.define(:term, :description)

        # --- 行頭の分岐（順序が優先順位そのもの）---
        COMMENT = /\A\#@/
        HEADING = /\A(=+)(?:\[(.*?)\])?(?:\{(.*?)\})?(.*)\z/
        LIST_ITEM = /\A( +)(\*+|-+) +(.*)\z/
        OLIST_ITEM = /\A\s+(\d+)\. +(.*)\z/
        DLIST_ITEM = /\A\s*:\s+?(.*)\z/
        BLOCK_END = %r{\A//\}\s*\z}
        BLOCK_OPEN = %r{\A//(\w+)}

        # 中身を逐語で扱うブロック。入れ子のブロックもインラインも解釈しない
        # （Starter の RAW_BLOCK_COMMANDS と同じ顔ぶれ）
        RAW_BLOCKS = %w[
          list listnum emlist emlistnum source program terminal cmd output
          embed table emtable raw
        ].freeze

        # `//include` の入れ子の上限。循環しても止まるようにする
        INCLUDE_DEPTH_LIMIT = 5

        # 1 章を読んでノードの配列を返す
        #
        # @param path [String] .re のパス
        # @param report [ReReport]
        # @return [Array] ノードの配列
        def parse(path, report:)
          lines = read_with_includes(path, report:, depth: 0)
          nodes, = parse_nodes(lines, 0, inside_block: false)
          nodes
        end

        # `//include[file]` を読み込んで平らにする。
        # Re:VIEW の原稿分割機能で、パースより前に済ませておくほうが素直
        def read_with_includes(path, report:, depth:)
          File.readlines(path, encoding: 'utf-8').flat_map do |raw|
            included = raw.chomp[%r{\A//include\[(.+?)\]\s*\z}, 1]
            next raw unless included

            expand_include(included, path, report:, depth:)
          end
        end

        def expand_include(name, path, report:, depth:)
          target = File.join(File.dirname(path), name.end_with?('.re') ? name : "#{name}.re")

          if depth >= INCLUDE_DEPTH_LIMIT || !File.exist?(target)
            report.degraded('//include', file: File.basename(path), line: 0,
                                         message: "//include[#{name}] の取り込み先を読めませんでした。",
                                         detail: '対処: 取り込み先の内容を原稿へ直接書いてください。')
            return []
          end

          read_with_includes(target, report:, depth: depth + 1)
        end

        # --- Phase: 本体（行頭を見て分岐する）---
        #
        # @return [Array(Array, Integer)] ノードの配列と、次に読む行番号
        def parse_nodes(lines, from, inside_block:)
          nodes = []
          index = from

          while index < lines.size
            line = lines[index].chomp

            case line
            when COMMENT then index += 1
            when BLOCK_END
              return [nodes, index + 1] if inside_block

              index += 1
            when HEADING_LINE then index = take_heading(nodes, lines, index)
            when LIST_ITEM then index = take_list(nodes, lines, index)
            when OLIST_ITEM then index = take_olist(nodes, lines, index)
            when DLIST_ITEM then index = take_dlist(nodes, lines, index)
            when BLOCK_OPEN then index = take_block(nodes, lines, index)
            else
              index = line.strip.empty? ? index + 1 : take_paragraph(nodes, lines, index)
            end
          end

          [nodes, index]
        end

        # 見出しの判定だけは「`=` の後に空白・`[`・`{` が続くこと」まで見る
        # （`====` だけの区切り線を見出しと誤認しないため）
        HEADING_LINE = /\A=+[\[\s{]/

        def take_heading(nodes, lines, index)
          match = HEADING.match(lines[index].chomp)
          nodes << Heading.new(level: match[1].size, tag: match[2], id: match[3],
                               text: match[4].to_s.strip, line: index + 1)
          index + 1
        end

        # --- Phase: 箇条書き・番号リスト ---
        #
        # Starter では `*` が箇条書き、**`-` が番号つきリスト**（同 §2.2）。
        # マーカーの数がレベルで、直後の最初のトークンが番号になる。
        def take_list(nodes, lines, index)
          items = []
          start = index
          ordered = nil

          while index < lines.size && (match = LIST_ITEM.match(lines[index].chomp))
            marker = match[2]
            ordered = marker.start_with?('-') if ordered.nil?
            break unless marker.start_with?('-') == ordered

            text = match[3]
            number, body = ordered ? text.split(/\s+/, 2) : [nil, text]
            index += 1
            continuation, index = take_continuation(lines, index, match[1].size)
            items << Item.new(level: marker.size, marker: number, text: body.to_s, continuation:)
          end

          nodes << (ordered ? OList : UList).new(items:, line: start + 1)
          index
        end

        # Re:VIEW 本体式の ` 1. 項目`。入れ子は無い
        def take_olist(nodes, lines, index)
          items = []
          start = index

          while index < lines.size && (match = OLIST_ITEM.match(lines[index].chomp))
            index += 1
            continuation, index = take_continuation(lines, index, 1)
            items << Item.new(level: 1, marker: "#{match[1]}.", text: match[2], continuation:)
          end

          nodes << OList.new(items:, line: start + 1)
          index
        end

        # 項目より深くインデントされた行は、その項目の続き
        def take_continuation(lines, index, indent)
          buffer = []

          while index < lines.size
            line = lines[index].chomp
            break if line.strip.empty? || LIST_ITEM.match?(line) || OLIST_ITEM.match?(line)
            break unless line[/\A( +)/, 1].to_s.size > indent

            buffer << line.strip
            index += 1
          end

          [buffer, index]
        end

        # --- Phase: 定義リスト ---
        #
        # ` : 用語` の次の行からインデントして説明を書く（Vivlio とは順序が逆）
        def take_dlist(nodes, lines, index)
          items = []
          start = index

          while index < lines.size && (match = DLIST_ITEM.match(lines[index].chomp))
            term = match[1].strip
            index += 1
            description, index = take_description(lines, index)
            items << Term.new(term:, description:)
          end

          nodes << DList.new(items:, line: start + 1)
          index
        end

        def take_description(lines, index)
          buffer = []

          while index < lines.size
            line = lines[index].chomp
            break if line.strip.empty? || DLIST_ITEM.match?(line)
            break unless line.start_with?(' ', "\t")

            buffer << line.strip
            index += 1
          end

          [buffer, index]
        end

        # --- Phase: ブロック命令 ---
        def take_block(nodes, lines, index)
          line = lines[index].chomp
          name = line[BLOCK_OPEN, 1]
          args = parse_args(line)
          opens_body = line.rstrip.end_with?('{')

          unless opens_body
            nodes << Command.new(name:, args:, line: index + 1)
            return index + 1
          end

          if RAW_BLOCKS.include?(name)
            body, next_index = take_raw_body(lines, index + 1, name)
            nodes << Block.new(name:, args:, body:, children: [], line: index + 1)
          else
            children, next_index = parse_nodes(lines, index + 1, inside_block: true)
            nodes << Block.new(name:, args:, body: [], children:, line: index + 1)
          end

          next_index
        end

        # 逐語ブロックの中身。`//}` まで、行をそのまま集める
        # （`//embed` を除きコメント行だけは落とす。Starter の read_block と同じ）
        def take_raw_body(lines, index, name)
          buffer = []
          keep_comments = name == 'embed'

          while index < lines.size
            line = lines[index].chomp
            return [buffer, index + 1] if BLOCK_END.match?(line)

            buffer << line unless !keep_comments && COMMENT.match?(line)
            index += 1
          end

          [buffer, index]
        end

        # `//name[引数][引数]{` の引数を切り出す。`\]` はエスケープ
        def parse_args(line)
          args = []
          index = line.index('[')
          return args unless index

          while index < line.length && line[index] == '['
            arg, index = read_arg(line, index + 1)
            break unless arg

            args << arg
          end

          args
        end

        # Re:VIEW の parse_args と同じ規則: `\]` は `]`、`\\` は `\`、
        # それ以外の `\x` はバックスラッシュを残したまま通す
        def read_arg(line, from)
          buffer = +''
          index = from

          while index < line.length
            if line[index] == '\\' && [']', '\\'].include?(line[index + 1])
              buffer << line[index + 1]
              index += 2
              next
            end

            return [buffer, index + 1] if line[index] == ']'

            buffer << line[index]
            index += 1
          end

          [nil, index]
        end

        # --- Phase: 段落 ---
        #
        # 空行・命令・見出しに当たるまでを 1 段落として集める。
        # 行頭の空白は Re:VIEW では意味を持たないので落とす（同 §2.1）
        def take_paragraph(nodes, lines, index)
          buffer = []
          start = index

          while index < lines.size
            line = lines[index].chomp
            break if line.strip.empty? || line.start_with?('//') || COMMENT.match?(line)
            break if HEADING_LINE.match?(line) || LIST_ITEM.match?(line) ||
                     OLIST_ITEM.match?(line) || DLIST_ITEM.match?(line)

            buffer << line.strip
            index += 1
          end

          nodes << Paragraph.new(lines: buffer, line: start + 1) if buffer.any?
          index
        end
      end
    end
  end
end
