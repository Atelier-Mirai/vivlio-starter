# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/import/re_renderer.rb
# ================================================================
# 責務:
#   ReParser が読んだノードの木を、Vivlio Starter の Markdown へ書き出す。
#   記法の対応表（re-direct-import-spec.md §3）はここに閉じる——
#   対応を増やすときに触るのはこのファイルだけで、パーサは動かない。
# ================================================================

require_relative '../common'
require_relative '../image_filename_sanitizer'
require_relative '../units'
require_relative 're_inline'
require_relative 're_parser'
require_relative 're_report'

module VivlioStarter
  module CLI
    module Import
      # ノードの木 → Vivlio Markdown
      class ReRenderer
        # `:::{.class}` で囲むブロック
        BOX_CLASSES = {
          'abstract' => 'chapter-lead', 'lead' => 'chapter-lead', 'read' => 'chapter-lead',
          'tip' => 'tip', 'note' => 'note', 'info' => 'note',
          'memo' => 'memo', 'box' => 'memo',
          'notice' => 'notice', 'caution' => 'notice', 'warning' => 'notice', 'important' => 'notice',
          'centering' => 'align-center', 'textcenter' => 'align-center',
          'flushright' => 'align-right', 'textright' => 'align-right',
          'textleft' => 'align-left'
        }.freeze

        # コードフェンスになるブロック
        CODE_BLOCKS = %w[list listnum emlist emlistnum source program].freeze

        # 逐語ブロックを囲む枠（中の <pre> には行番号が付かない）
        VERBATIM_BOXES = { 'terminal' => 'terminal', 'cmd' => 'terminal', 'output' => 'output' }.freeze

        # 引用
        QUOTES = %w[quote blockquote doorquote].freeze

        # 落とすだけ。紙面に出ない指示なので著者の作業は要らない（🔵）
        SILENT_COMMANDS = {
          'noindent' => '字下げの抑制（Vivlio では CSS が持ちます）',
          'paragraphend' => '段の終わりの空き',
          'subparagraphend' => '小段の終わりの空き',
          'parasep' => '段落の区切り',
          'tsize' => '表の列幅指定（Vivlio では列幅は自動です）',
          'comment' => 'コメント'
        }.freeze

        # 落とすが、紙面が変わるので知らせる（🟡）
        DROPPED_COMMANDS = {
          'needvspace' => '「残りが足りなければ改ページ」の指定',
          'makechaptitlepage' => '章扉の指定',
          'chapterauthor' => '章の著者名',
          'label' => '参照用のラベル',
          'address' => '住所ブロック',
          'bibpaper' => '参考文献の項目',
          'bpo' => '記法の抑制指定'
        }.freeze

        # 対応概念が無い（🔴）
        UNSUPPORTED_BLOCKS = {
          'hr' => '水平線（Vivlio の --- は改ページです）',
          'graph' => '外部ツールによる作図',
          'embed' => '出力形式ごとの生データ',
          'raw' => '出力形式ごとの生データ'
        }.freeze

        # 画像列の比率の下限・上限。極端な指定で本文の列が潰れるのを防ぐ
        WIDTH_PERCENT_RANGE = (10..60).freeze

        # 文の終わりとみなす字。ここで終わる行の改行は残す（同 §3.1.1）
        SENTENCE_END = /[。．！？!?」』）)]\z/

        # この章で定義されたラベル ID。全章そろってから一意化するのに使う
        attr_reader :labels

        def initialize(report:, file:, words: {}, text_width_mm: nil)
          @report = report
          @file = file
          @context = ReInline::Context.new(report:, file:, line: 1, words:)
          @text_width_mm = text_width_mm
          @chunks = []
          @footnotes = []
          @labels = []
          @open_column = false
          @next_line_number = nil
        end

        # ノードの配列を Markdown 文字列にする
        def render(nodes)
          nodes.each { visit(it) }
          @chunks << ':::' if @open_column
          @chunks.concat(@footnotes)
          "#{@chunks.compact.reject(&:empty?).join("\n\n")}\n"
        end

        private

        def visit(node)
          @context = @context.at(node.line)

          case node
          in ReParser::Heading then push(heading(node))
          in ReParser::Paragraph then push(paragraph(node))
          in ReParser::UList then push(unordered_list(node))
          in ReParser::OList then push(ordered_list(node))
          in ReParser::DList then push(definition_list(node))
          in ReParser::Block then push(block(node))
          in ReParser::Command then command(node)
          end
        end

        # エンドレスメソッドに修飾子を付けると定義自体が条件になるので、通常の形で書く
        def push(text)
          @chunks << text unless text.nil? || text.to_s.empty?
        end

        # --- 見出し・コラム ---

        def heading(node)
          return close_column if node.tag == '/column'

          return open_column(node) if node.tag == 'column'

          warn_heading_tag(node) if node.tag
          title = inline(node.text)
          @labels << node.id if node.id
          label = node.id ? " @#{node.id}" : ''
          "#{'#' * node.level} #{title}#{label}"
        end

        def open_column(node)
          prefix = close_column.to_s
          @open_column = true
          opened = ":::{.column}\n**#{inline(node.text)}**"
          prefix.empty? ? opened : "#{prefix}\n\n#{opened}"
        end

        def close_column
          return '' unless @open_column

          @open_column = false
          ':::'
        end

        def warn_heading_tag(node)
          @report.degraded("=[#{node.tag}]", file: @file, line: node.line,
                                             message: "見出しの [#{node.tag}] 指定は移せないため、通常の見出しにしました。",
                                             detail: '対処: 番号や目次の扱いは book.yml とスタイルで調整してください。')
        end

        # --- 段落 ---
        #
        # Re:VIEW は段落内の行を連結して組むが、Vivlio は hardLineBreaks で
        # 改行をそのまま出す。著者は一文一行で書いているので文の切れ目の改行は
        # 残し、文の途中で折り返した行だけを連結する（同 §3.1.1）。
        def paragraph(node)
          lines = node.lines.each_with_index.map { |line, offset| inline(line, node.line + offset) }
          joined = +''

          lines.each_with_index do |line, index|
            if index.zero?
              joined << line
            elsif SENTENCE_END.match?(joined)
              joined << "\n" << line
            else
              joined << join_mark(joined, line) << line
            end
          end

          joined
        end

        # 連結するとき、両側が英数字のときだけ空白を挟む
        # （和文同士は Re:VIEW も空白を入れずに連ねる）
        def join_mark(left, right)
          left[-1].to_s.match?(/[A-Za-z0-9]/) && right[0].to_s.match?(/[A-Za-z0-9]/) ? ' ' : ''
        end

        # --- リスト ---

        def unordered_list(node)
          node.items.map { "#{'    ' * (it.level - 1)}- #{item_text(it)}" }.join("\n")
        end

        # Starter の ` - 1. ` は標準の番号リストへ、` - (A) ` は fancy list へ
        def ordered_list(node)
          node.items.map { "#{'    ' * (it.level - 1)}#{it.marker} #{item_text(it)}" }.join("\n")
        end

        def item_text(item)
          [inline(item.text), *item.continuation.map { inline(it) }].inject do |joined, line|
            joined + join_mark(joined, line) + line
          end
        end

        # Re:VIEW は「用語の次の行に説明」、Vivlio は「用語の次の行に `: 説明`」
        def definition_list(node)
          node.items.map do |item|
            body = item.description.each_with_index.map do |line, index|
              index.zero? ? ": #{inline(line)}" : "  #{inline(line)}"
            end
            [inline(item.term), *body].join("\n")
          end.join("\n\n")
        end

        # --- ブロック命令 ---

        def block(node)
          case node.name
          when *CODE_BLOCKS then code_block(node)
          when *VERBATIM_BOXES.keys then verbatim_box(node)
          when *QUOTES then quote(node)
          when *BOX_CLASSES.keys then box(node)
          when 'table', 'emtable' then table(node)
          when 'image', 'indepimage', 'numberlessimage' then image(node)
          when 'sideimage' then sideimage(node)
          when 'talklist' then talk_group(node)
          when 'talk', 't' then talk_group(node, single: true)
          when 'desclist' then desc_group(node)
          when 'desc' then desc_group(node, single: true)
          when 'texequation' then equation(node)
          when 'imgtable' then imgtable(node)
          when *UNSUPPORTED_BLOCKS.keys then unsupported(node)
          else unknown(node)
          end
        end

        # --- 本文を持たない命令 ---

        def command(node)
          case node.name
          when 'image', 'indepimage', 'numberlessimage' then push(image(node))
          when 'footnote' then @footnotes << footnote(node)
          when 'clearpage', 'pagebreak' then push('@pagebreak')
          when 'blankline' then blankline
          when 'vspace', 'addvspace' then push(vspace(node))
          when 'firstlinenum' then @next_line_number = node.args.first.to_i
          when 'sampleoutputbegin' then open_sample_output
          when 'sampleoutputend' then close_sample_output
          when 'talk', 't' then push(talk_group(node, single: true))
          when 'desc' then push(desc_group(node, single: true))
          when 'olnum' then nil
          when *SILENT_COMMANDS.keys then silent(node)
          when *DROPPED_COMMANDS.keys then dropped(node)
          when *UNSUPPORTED_BLOCKS.keys then push(unsupported(node))
          else push(unknown(node))
          end
        end

        # --- コード・端末・実行結果 ---

        # `//list[ラベル][キャプション][オプション]`
        #
        # 第 3 引数は実測の 9 割が `file=パス,開始行` か裸の数値（開始行）で、
        # 残りが `lineno=` などのキー付き。file= の値はカンマを含むので先に抜く
        def code_block(node)
          label, caption, options = node.args
          opts = parse_options(options)
          @report.count(:block)

          return include_fence(node, opts, label, caption) if opts['file']

          language = detect_language(caption, nil, node.body)
          [caption_for(label, caption), fence(node.body, info_string(language, label, caption, opts))]
            .compact.join("\n\n")
        end

        # 外部ファイルは Vivlio の `include:` へ落とす。source/ は codes/ へ
        # コピーされるので、コードの置き場所が 1 つに保たれる（同 §0.4）
        def include_fence(node, opts, label, caption)
          path = opts['file'].sub(%r{\A(?:\./)?source/}, '')
          warn_start_line(node, opts)

          [caption_for(label, caption), "```include:#{path}\n```"].compact.join("\n\n")
        end

        def warn_start_line(node, opts)
          start = opts['start'].to_i
          return if start <= 1

          @report.degraded("//#{node.name}", file: @file, line: node.line,
                                             message: "外部ファイルの開始行 #{start} は移せないため、ファイル全体を取り込みます。",
                                             detail: '対処: 範囲を絞るなら ```include:パス:開始-終了 と書いてください（拡張記法リファレンス）。')
        end

        # フェンスの情報文字列。キャプションがファイル名に見えるときだけ
        # `lang:ファイル名` に入れる（ラベルがあるならキャプション行が出るので重複させない）
        def info_string(language, label, caption, opts)
          return language unless label.to_s.strip.empty? && filename_like?(caption)

          start = (opts['start'] || @next_line_number).to_i
          @next_line_number = nil
          marker = start > 1 ? "#L#{start}" : ''
          "#{language}:#{caption.strip}#{marker}"
        end

        # 逐語ブロックの中でも `@<userinput>` `@<balloon>` は使われる（実測あり）。
        # ただし Markdown の装飾記号はコードの中で効かないので、中身だけを残す
        def fence(body, info)
          verbatim = body.map { ReInline.strip(it, @context) }
          "```#{info}\n#{verbatim.join("\n")}\n```"
        end

        # `//terminal` `//output` は枠で囲む。中の逐語には行番号が付かない
        def verbatim_box(node)
          label, caption, = node.args
          klass = VERBATIM_BOXES.fetch(node.name)
          language = klass == 'terminal' ? 'zsh' : 'text'
          @report.count(:block)

          body = fence(node.body, language)
          [caption_for(label, caption), ":::{.#{klass}}\n#{body}\n:::"].compact.join("\n\n")
        end

        # --- 囲み枠・引用 ---

        def box(node)
          klass = BOX_CLASSES.fetch(node.name)
          title = node.args.first
          @report.count(:block)

          inner = render_children(node.children)
          inner = "**#{inline(title)}**\n\n#{inner}" unless title.to_s.strip.empty?
          ":::{.#{klass}}\n#{inner}\n:::"
        end

        def quote(node)
          @report.count(:block)
          render_children(node.children).lines.map { "> #{it.chomp}".rstrip }.join("\n")
        end

        def equation(node)
          label, caption, = node.args
          @report.count(:block)
          [caption_for(label, caption), "$$\n#{node.body.join("\n")}\n$$"].compact.join("\n\n")
        end

        # --- 会話・説明リスト ---

        # `//talklist` の中身は `//talk` の並びだが、地の文が混じることもある。
        # talk でないノードは捨てずに、そのまま囲みの中へ描く
        def talk_group(node, single: false)
          @report.count(:block)
          sources = single ? [node] : node.children
          items = sources.map { talk?(it) ? talk_line(it) : render_children([it]) }
                         .compact.reject(&:empty?)
          warn_speakers(node, items)
          ":::{.talk}\n#{items.join("\n")}\n:::"
        end

        def talk?(node) = node.respond_to?(:name) && %w[talk t].include?(node.name)

        # `//talk[アイコン][名前][発話]`。アイコンを使うときは名前を省き、
        # 発話は第 3 引数（コンパクト形式）かブロック本体のどちらかに書く
        def talk_line(node)
          icon, name, spoken = node.args
          speaker = name.to_s.strip.empty? ? icon.to_s.strip : name.to_s.strip
          body = spoken.to_s.strip.empty? ? body_text(node) : spoken
          "#{speaker}: #{inline(body.to_s.gsub("\n", ''))}"
        end

        def warn_speakers(node, items)
          speakers = items.compact.filter_map { it[/\A([^:]+):/, 1] }.uniq
          return if speakers.empty?

          @report.degraded('//talk', file: @file, line: node.line,
                                     message: "会話の話者（#{speakers.join('、')}）は book.yml への登録が要ります。",
                                     detail: '対処: book.yml の characters に話者キーと表示名・色を足してください（拡張記法リファレンス「会話」）。')
        end

        def desc_group(node, single: false)
          @report.count(:block)
          items = single ? [desc_item(node)] : node.children.map { desc_item(it) }
          items.compact.join("\n\n")
        end

        def desc_item(node)
          key = node.args.first.to_s.strip
          body = body_text(node)
          ["#{inline(key)}", *body.lines.map { ": #{it.chomp}" }].join("\n")
        end

        # ブロックの中身を文字列にする（逐語なら body、入れ子なら children）。
        # Command（`//talk[話者][発話]` のように本文を持たない形）は空
        def body_text(node)
          return '' unless node.is_a?(ReParser::Block)
          return node.body.join("\n") if node.body.any?

          render_children(node.children)
        end

        # 入れ子のノードを同じレンダラで描く。脚注は親と共有する
        def render_children(children)
          saved = @chunks
          @chunks = []
          children.each { visit(it) }
          rendered = @chunks.compact.reject(&:empty?).join("\n\n")
          @chunks = saved
          rendered
        end

        # --- 表 ---

        def table(node)
          label, caption, options = node.args
          opts = parse_options(options)
          @report.count(:block)
          warn_table_options(node, opts)

          header, rows = split_table(node.body, csv: opts['csv'] == 'on')
          [caption_for(label, caption), markdown_table(header, rows)].compact.join("\n\n")
        end

        # ヘッダと本体は `-` か `=` を並べた行で分かれる（Starter の仕様は 12 文字以上。
        # 取りこぼさないよう 3 文字以上を受ける）。区切りが無ければ先頭行をヘッダにする。
        # セルの区切りは「1 文字以上のタブ」なので、連続タブで空セルを作らない
        HEADER_RULE = /\A[-=]{3,}\s*\z/

        def split_table(body, csv:)
          header = []
          rows = []
          current = header

          body.each do |line|
            next current = rows if HEADER_RULE.match?(line)

            cells = (csv ? split_csv(line) : line.split(/\t+/)).map { cell(it) }
            current << cells
          end

          header.empty? && rows.any? ? [[rows.shift], rows] : [header, rows]
        end

        # csv=on の行を割る。囲みの中のカンマは区切りにしない。
        #
        # CSV gem を使わないのは、Ruby 4.0 で bundled gem へ移り Gemfile に
        # 書かないと読めなくなったため。表のためだけに依存を増やす価値はない
        # （実測 999 行のうちダブルクォートを含む行は 0 だった）。
        def split_csv(line)
          cells = []
          buffer = +''
          quoted = false
          index = 0

          while index < line.length
            char = line[index]

            if char == '"'
              quoted && line[index + 1] == '"' ? (buffer << '"'; index += 1) : quoted = !quoted
            elsif char == ',' && !quoted
              cells << buffer
              buffer = +''
            else
              buffer << char
            end

            index += 1
          end

          cells << buffer
        end

        # `.` 1 文字は空欄（Re:VIEW の約束）。縦棒はエスケープする
        def cell(raw)
          text = raw.to_s.strip
          return '' if text == '.'

          inline(text).gsub('|', '\\|')
        end

        def markdown_table(header, rows)
          columns = (header + rows).map(&:size).max.to_i
          return '' if columns.zero?

          lines = header.map { row_line(it, columns) }
          lines << row_line(Array.new(columns, '---'), columns)
          lines.concat(rows.map { row_line(it, columns) })
          lines.join("\n")
        end

        def row_line(cells, columns)
          padded = cells + Array.new([columns - cells.size, 0].max, '')
          "| #{padded.join(' | ')} |"
        end

        def warn_table_options(node, opts)
          dropped = opts.keys & %w[hline pos fontsize headerrows headercols]
          return if dropped.empty?

          @report.degraded('//table', file: @file, line: node.line,
                                      message: "表の #{dropped.join('・')} 指定は移せないため落としました。",
                                      detail: '対処: 行の多い表は :::{.long-table}、横に広い表は :::{.rotate-table} で囲めます。')
        end

        # --- 画像 ---

        def image(node)
          name, caption, options = node.args
          opts = parse_options(options)
          @report.count(:block)
          warn_image_options(node, opts)

          markup = "![](#{ImageFilenameSanitizer.sanitize(name.to_s.strip)}.webp)#{image_attrs(opts)}"
          return markup if node.name != 'image'

          [caption_for(name, caption), markup].compact.join("\n\n")
        end

        # `border=on` は .bordered へ。白背景の図版は枠が無いと輪郭が消える
        def image_attrs(opts)
          attrs = []
          attrs << '.bordered' if opts['border'] == 'on'
          attrs << "width=#{opts['width']}" if opts['width']
          attrs << "width=#{(opts['scale'].to_f * 100).round}%" if opts['scale'] && !opts['width']
          attrs.empty? ? '' : "{#{attrs.join(' ')}}"
        end

        def warn_image_options(node, opts)
          return unless opts.key?('pos')

          @report.degraded("//#{node.name}", file: @file, line: node.line,
                                             message: '画像の pos 指定は移せないため落としました（Vivlio は浮動体を使いません）。',
                                             detail: '対処: 置きたい位置に画像を書いてください。')
        end

        # 画像を表として番号づけする命令。Vivlio では図として出る
        def imgtable(node)
          @report.degraded('//imgtable', file: @file, line: node.line,
                                         message: '//imgtable は図として取り込みました（表番号は付きません）。',
                                         detail: '対処: 表番号が要るなら Markdown の表に書き直してください。')
          image(node)
        end

        # `//sideimage[画像][幅][sep=5mm,side=R]`
        def sideimage(node)
          name, width, options = node.args
          opts = parse_options(options)
          @report.count(:block)

          klass = opts['side'] == 'R' ? 'sideimage-right' : 'sideimage-left'
          attrs = [('.bordered' if opts['border'] == 'on'), width_attr(width)].compact
          markup = "![](#{ImageFilenameSanitizer.sanitize(name.to_s.strip)}.webp)"
          markup += "{#{attrs.join(' ')}}" if attrs.any?

          ":::{.#{klass}}\n#{markup}\n\n#{render_children(node.children)}\n:::"
        end

        # Re:VIEW は mm 指定、Vivlio は版面に対する比率
        def width_attr(width)
          millimeters = Units.length_to_mm(width.to_s.strip)
          return nil unless millimeters&.positive? && @text_width_mm.to_f.positive?

          percent = ((millimeters / @text_width_mm) * 100).round
                    .clamp(WIDTH_PERCENT_RANGE.begin, WIDTH_PERCENT_RANGE.end)
          "width=#{percent}%"
        end

        # --- 余白・脚注・その他の単発命令 ---

        def footnote(node)
          id, text = node.args
          @report.count(:block)
          "[^#{id.to_s.strip}]: #{inline(text.to_s)}"
        end

        # 直前の段落の末尾へ {.aki}。段落が無ければ独立した余白にする
        def blankline
          @report.count(:block)
          last = @chunks.last

          if last && !last.end_with?(':::', '```', '}')
            @chunks[-1] = "#{last}{.aki}"
          else
            @chunks << '@vspace:1lh'
          end
        end

        # Starter の記法解説で使う「表示結果」の囲み。開きと閉じが別命令で来る
        def open_sample_output
          @report.count(:block)
          push('::::{.output}')
        end

        # コロンを 4 つにするのは、表示結果の中に別の囲み（`:::{.talk}` など）が
        # 入りうるため。入れ子は外側のコロンを増やして表す
        def close_sample_output
          push('::::')
        end

        def vspace(node)
          @report.count(:block)
          "@vspace:#{node.args.last.to_s.strip}"
        end

        def silent(node)
          @report.note("//#{node.name}", file: @file, line: node.line,
                                         message: "//#{node.name}（#{SILENT_COMMANDS[node.name]}）は落としました。")
          nil
        end

        def dropped(node)
          @report.degraded("//#{node.name}", file: @file, line: node.line,
                                             message: "//#{node.name}（#{DROPPED_COMMANDS[node.name]}）は移せないため落としました。",
                                             detail: dropped_hint(node.name))
          nil
        end

        def dropped_hint(name)
          case name
          when 'makechaptitlepage' then '対処: 章扉は book.yml の frontispiece で設定できます（扉絵の章）。'
          when 'chapterauthor' then '対処: 著者名が要るなら本文に書いてください。'
          else '対処: 必要なら本文やスタイルで書き直してください。'
          end
        end

        def unsupported(node)
          @report.unsupported("//#{node.name}", file: @file, line: node.line,
                                                message: "//#{node.name}（#{UNSUPPORTED_BLOCKS[node.name]}）は Vivlio に対応する記法がありません。原文を残しました。",
                                                detail: '対処: 該当箇所を書き換えてください（拡張記法リファレンスの章）。')
          original(node)
        end

        def unknown(node)
          @report.unsupported("//#{node.name}", file: @file, line: node.line,
                                                message: "//#{node.name} は変換に対応していない命令です。原文を残しました。",
                                                detail: '対処: 命令名の綴りを確かめ、必要なら手で書き換えてください。')
          original(node)
        end

        # 原文をそのまま残す。著者が探せるよう命令の形を保つ
        def original(node)
          head = "//#{node.name}#{node.args.map { "[#{it}]" }.join}"
          inner = body_text(node)
          return head if inner.empty?

          "#{head}{\n#{inner}\n//}"
        end

        # --- 補助 ---

        # キャプション行（`** タイトル @ラベル **`）。
        #
        # **タイトルが空のときは行そのものを出さない。** `** @id **` と書くと
        # Vivlio はキャプションの定義ではなく参照（`@id`）として読み、
        # 「未定義のラベルID」になる。Re:VIEW でキャプションを空にした画像・表は
        # 番号を振らない扱いにして、ラベルが失われることを著者へ伝える。
        def caption_for(label, caption)
          text = inline(caption.to_s.strip)
          id = label.to_s.strip
          return nil if text.empty? && id.empty?
          return nil if id.empty? && filename_like?(caption.to_s.strip)
          return drop_label(id) if text.empty?

          @labels << id unless id.empty?
          "** #{[text, id.empty? ? '' : "@#{id}"].reject(&:empty?).join(' ')} **"
        end

        def drop_label(id)
          @report.degraded('label', file: @file, line: @context.line,
                                    message: "キャプションが空のためラベル #{id} を落としました（図表番号も付きません）。",
                                    detail: "対処: 番号や参照が要るなら `** タイトル @#{id} **` のキャプション行を足してください。")
          nil
        end

        FILENAME = %r{\A[\w./-]+\.\w{1,8}\z}

        def filename_like?(caption) = FILENAME.match?(caption.to_s.strip)

        # `file=パス,開始行` は値にカンマを含むので先に抜き、残りを , で割る
        FILE_OPTION = /file=\s*([^,\s]+)(?:\s*,\s*(\d+))?/

        def parse_options(raw)
          text = raw.to_s.strip
          return {} if text.empty?

          options = {}
          if (match = FILE_OPTION.match(text))
            options['file'] = match[1]
            options['start'] = match[2] if match[2]
            text = text.sub(match[0], '')
          end

          text.split(',').each { absorb_option(options, it) }
          options
        end

        def absorb_option(options, part)
          token = part.strip
          return if token.empty?

          key, value = token.split('=', 2)
          if value.nil?
            options['start'] = key if key.match?(/\A\d+\z/)
          else
            options[key.strip] = value.strip
          end
        end

        # 言語名は「明示 → ファイル名の拡張子 → Rouge の推定」の順に決める
        def detect_language(caption, explicit, body)
          return explicit.strip if explicit.to_s.strip.match?(/\A[a-z0-9+#-]+\z/i)

          extension = File.extname(caption.to_s.strip)
          return extension.delete('.').downcase unless extension.empty?

          guess_language(body.join("\n"))
        end

        # Rouge による推定。シェルらしさだけは先に見る（$ や % で始まる行）
        ROUGE_TAGS = {
          'javascript' => 'js', 'typescript' => 'ts', 'markdown' => 'md',
          'plaintext' => 'text', 'bash' => 'zsh', 'shell' => 'zsh'
        }.freeze

        def guess_language(code)
          return 'zsh' if code.match?(/^[ \t]*[$%][ \t]+/)

          require 'rouge'
          tag = Rouge::Lexer.guess(source: code).tag
          ROUGE_TAGS.fetch(tag, tag)
        rescue LoadError, StandardError
          'text'
        end

        def inline(text, line = nil)
          @context = @context.at(line) if line
          ReInline.transform(text.to_s, @context)
        end
      end
    end
  end
end
