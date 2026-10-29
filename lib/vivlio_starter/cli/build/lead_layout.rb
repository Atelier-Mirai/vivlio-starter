# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/build/lead_layout.rb
# ================================================================
# 責務:
#   章扉のリードと章題が何行になるかを、組まずに見積もる（chapter-lead-size-spec.md §4.4）。
#   Chromium（Vivliostyle が使うブラウザ）と同じ順で、1 字ずつ並べて行を折る。
#
# 再現している組み方（3 冊・67 章のリードを 6 通りの設定で組み、実物の改行と比べて決めた）:
#   - 字の送りは書体の値に、書体のカーニングを足す（FontMetrics）
#   - 行の幅は CSS に書いた mm を px にし、1/64 px へ切り上げた値（Chromium の LayoutUnit）
#   - 約物の詰めは Vivliostyle の text-spacing: auto に合わせる。行頭の始め括弧と行末の終わり
#     約物は半角、終わり約物の後ろに終わり約物・中点が続けば前を半角、始め括弧の前が約物なら
#     その始め括弧を半角
#   - 和文と欧文・数字のあいだに 1/8 字のアキ（viv-ts-thin-sp）。空白の字なので行末ではぶら下がる
#   - 行頭に来られない字（、。」など。小書きのかなと長音記号は来られる）、行末に来られない字
#     （「（など）を守る。欧文の語の中はハイフンの後でだけ折れる。ASCII の引用符の前後では折れない
#   - 数式の画像は、style の ex を本文の書体の x ハイトで字の幅に直す
#
# 合わないところ:
#   Vivliostyle は組んだ後に約物を 1 つずつ包み直して位置を測るので、まれに 1 字手前で折れる
#   （段落の最後の「す。」が次の行へ送られるなど）。試しでは 402 件のリードのうち 399 件で
#   行数が合い、外れた 3 件も 1 行の違いだった。
# ================================================================

require 'nokogiri'
require_relative 'font_metrics'

module VivlioStarter
  module CLI
    module Build
      module LeadLayout
        OPEN = '（「『【〔〈《［｛〘〖“‘'
        CLOSE = '）」』】〕〉》］｝〙〗”’、。，．'
        # 終わり約物の後ろにこれが続くと、終わり約物を半角にする（Vivliostyle の trim-adjacent）
        MIDDLE = "・：；　·‧"
        # 行頭に来られない字（line-break: normal。小書きのかなと長音記号は行頭に来られる）。
        # 用語集の印 † は行頭に来られる（実物で「k平均法／†、ナイーブベイズ」と折れた）
        NO_START = "#{CLOSE}！？：；・‥…ゝゞヽヾ々〻".freeze
        # 数式などの画像を表す字
        IMAGE = "￼"

        # 和文と欧文・数字のあいだのアキ（viv-ts-thin-sp: 0.5em の空白 − 0.375em）
        AUTOSPACE = 0.125
        # .chapter-lead p { text-indent: 1em }
        INDENT = 1.0
        # 用語集の印 † は本文の書体の 0.7 倍で、前に 0.1em 空く（chapter.css の .glossary-link）
        GLOSSARY_SCALE = 0.7
        GLOSSARY_GAP = 0.1
        # @pageref・@chapref の後ろに CSS が足す「（p.123）」。組む前はページが分からないので 3 桁とみる
        PAGEREF_SUFFIX = '（p.000）'

        # 字と、その送り（段落の字の大きさに対する比。カーニングを含む）
        Atom = Data.define(:char, :width)

        # 段落を組む書体（FontMetrics）。bold・code が無ければ body で代える
        Fonts = Data.define(:body, :bold, :code)

        module_function

        # 段落ごとの行数。
        #
        # @param paragraphs [Array<String>] 段落ごとのインラインの HTML
        # @param fonts [Fonts]
        # @param width_px [Float] 行の幅（CSS の px）
        # @param font_px [Float] 字の大きさ（CSS の px）
        # @return [Array<Integer>]
        def line_counts(paragraphs, fonts:, width_px:, font_px:)
          limit = layout_px(width_px) / font_px
          paragraphs.map { break_lines(atoms(it, fonts), limit).size }
        end

        # 行に入る幅。Chromium は幅を 1/64 px の単位で持ち、入るかを比べるときに 1 単位の遊びを足す。
        # CSS の mm は小数 2 桁に丸めてあるので、字数ちょうどの行がわずかに広いことがある
        # （20 字ぶんの 74.08mm = 279.988px にも、24 字ぶんの 102.23mm = 386.381px にも、
        #  字数ちょうどの行が入っていた）
        def layout_px(px) = ((px * 64).ceil + 1) / 64.0

        # --- 字の並び ---

        # 段落の HTML を字の並びにする。字の送りは、同じ書体が続くあいだカーニングを足す
        def atoms(html, fonts)
          items = []
          collect(Nokogiri::HTML.fragment(html.to_s), :body, items)
          items = items.flat_map do |face, value|
            face == :image ? [[face, value]] : value.gsub(/[[:space:]]+/, ' ').chars.map { [face, it] }
          end
          items.shift while items.first&.last == ' '
          items.pop while items.last&.last == ' '

          items.each_with_index.map do |(face, value), i|
            next Atom.new(IMAGE, value * (value.negative? ? -fonts.body.x_height : 1)) if face == :image

            following = items[i + 1]
            Atom.new(value, char_width(face, value, following&.first == face ? following.last : nil, fonts))
          end
        end

        # 要素をたどり、[書体, 字の並び] を集める。画像は [:image, 幅]（ex は負の数で持ち、x ハイトを掛ける）
        def collect(node, face, items)
          node.children.each do |child|
            classes = child.element? ? child['class'].to_s.split : []
            if child.text?
              items << [face, child.text]
            elsif child.name == 'img'
              width = image_width(child['style'])
              items << [:image, width] if width
            elsif %w[rt rp].include?(child.name)
              next
            elsif child.name == 'a' && classes.include?('glossary-link')
              items << [:glossary, child.text.strip]
            else
              collect(child, child_face(child, face), items)
              items << [face, PAGEREF_SUFFIX] if child.name == 'a' && classes.include?('pageref')
            end
          end
        end

        def child_face(element, face)
          case element.name
          when 'code', 'kbd' then :code
          when 'strong', 'b' then face == :code ? :code : :bold
          else face
          end
        end

        def image_width(style)
          match = style.to_s.match(/(?<![-\w])width:\s*([\d.]+)(ex|em)/) or return nil
          match[2] == 'ex' ? -match[1].to_f : match[1].to_f
        end

        # 1 字の送り。書体に無い字は本文の書体、コードの書体の順に探し、どれにも無ければ全角 1・半角 0.5
        def char_width(face, char, following, fonts)
          return GLOSSARY_GAP + (GLOSSARY_SCALE * (fonts.body.advance(char) || 0.5)) if face == :glossary

          metrics = { body: fonts.body, bold: fonts.bold || fonts.body, code: fonts.code || fonts.body }[face]
          if metrics.glyph?(char)
            kern = following && metrics.glyph?(following) ? metrics.kern(char, following) : 0.0
            return metrics.advance(char) + kern
          end

          fallback = [fonts.body, fonts.code].compact.find { it.glyph?(char) }
          return fallback.advance(char) if fallback

          char.match?(/[\p{Han}\p{Hiragana}\p{Katakana}　-ヿ＀-￯]/) ? 1.0 : 0.5
        end

        # --- 行に分ける ---

        # 字の並びを、幅 limit（字の大きさに対する比）の行に分け、行ごとの字（空白を除く）を返す。
        # 前から詰め、入るうちでいちばん後ろの折り目で折る（Chromium の行分割と同じ貪欲法）
        def break_lines(atoms, limit, indent: INDENT)
          widths = trimmed_widths(atoms)
          spaces = autospaces(atoms)
          lines = []
          start = 0
          first = true
          while start < atoms.size
            start += 1 while atoms[start]&.char == ' '
            break if start >= atoms.size

            cut = line_end(atoms, widths, spaces, start, limit, first ? indent : 0.0)
            lines << atoms[start...cut].map(&:char).join.delete(' ')
            start = cut
            first = false
          end
          lines
        end

        # start から始まる行の終わり（次の行の頭の位置）
        def line_end(atoms, widths, spaces, start, limit, indent)
          sum = indent - (OPEN.include?(atoms[start].char) ? 0.5 : 0.0) # 行頭の始め括弧は半角
          best = nil
          j = start
          while j < atoms.size
            sum += widths[j]
            j += 1
            break if sum - 1.0 > limit # 行末の詰めを足しても、もう入らない

            best = j if (j == atoms.size || break_before?(atoms, j)) && line_width(atoms, widths, start, j, sum) <= limit
            sum += spaces[j - 1]
          end
          # 折れない並びが 1 行より長いときは、はみ出して次の折り目まで置く
          best || ((start + 1)..atoms.size).find { it == atoms.size || break_before?(atoms, it) }
        end

        # 行の幅。行末の空白はぶら下げ、行末の終わり約物は半角に詰める
        def line_width(atoms, widths, start, stop, sum)
          last = stop - 1
          while last > start && atoms[last].char == ' '
            sum -= widths[last]
            last -= 1
          end
          CLOSE.include?(atoms[last].char) ? sum - 0.5 : sum
        end

        # 約物が並んだときの詰め（Vivliostyle の trim-adjacent）
        def trimmed_widths(atoms)
          atoms.each_with_index.map do |atom, i|
            following = atoms[i + 1]&.char
            preceding = i.positive? ? atoms[i - 1].char : nil
            width = atom.width
            width -= 0.5 if CLOSE.include?(atom.char) && following && (CLOSE.include?(following) || MIDDLE.include?(following))
            if OPEN.include?(atom.char) && preceding && "#{OPEN}#{CLOSE}#{MIDDLE}".include?(preceding)
              width -= 0.5
            end
            width
          end
        end

        # 字の後ろに入る和欧間のアキ（Vivliostyle の text-autospace: ideograph-alpha ideograph-numeric）
        def autospaces(atoms)
          atoms.each_cons(2).map { |a, b| autospace?(a.char, b.char) ? AUTOSPACE : 0.0 } << 0.0
        end

        def autospace?(left, right)
          return false if [left, right].any? { it == ' ' || it == IMAGE }

          (kanji_kana?(left) && latin?(right)) || (latin?(left) && kanji_kana?(right))
        end

        def kanji_kana?(char) = char.match?(/[\p{Han}ぁ-ヿ㇀-ㇿ]/) && !char.match?(/\p{P}/)
        def latin?(char) = char.match?(/[\p{L}\p{Nd}]/) && !wide?(char)

        def wide?(char)
          char == IMAGE || OPEN.include?(char) || NO_START.include?(char) ||
            char.match?(/[\p{Han}\p{Hiragana}\p{Katakana}ー々〆〇　-ヿ＀-￯]/)
        end

        # 字 i の前で折れるか
        def break_before?(atoms, index)
          return false if index.zero?

          left = atoms[index - 1].char
          right = atoms[index].char
          return true if left == ' '
          return false if right == ' ' || NO_START.include?(right) || OPEN.include?(left)
          # ASCII の引用符の前後では折らない（UAX #14 の QU）
          return false if [left, right].any? { %w[" '].include?(it) }
          # 欧文の語の中は、ハイフンの後でだけ折れる
          return left == '-' && right.match?(/[A-Za-z]/) unless wide?(left) || wide?(right)

          true
        end

        # --- 章題 ---

        # 章題の行数。章題は文節ごとに折れない塊（.vs-nobr）にしてあり、塊の境目で折れる。
        # ただし境目でも、行頭禁則や欧文の語の途中（「catalog」と「.yml」）では折れない。
        # 1 行より長い文節は折れずにはみ出す（.vs-nobr は white-space: nowrap）。
        # 行数は text-wrap: balance でも前から詰めたときと変わらないので、前から詰めて数える。
        #
        # @param segments [Array<String>] 文節（HeadingSegmenter.segment の結果）。用語集の印は "†" 1 字の文節
        # @param metrics [FontMetrics] 章題の書体
        # @param glossary_metrics [FontMetrics] 用語集の印の書体（本文の書体。chapter.css の .glossary-link sup）
        # @param letter_spacing [Float] 字の大きさに対する比。字ごとに足す（行末の字のぶんも数える）
        def title_line_count(segments, metrics:, glossary_metrics:, width_px:, font_px:, letter_spacing:)
          limit = layout_px(width_px) / font_px
          width_of = lambda do |text|
            chars = text.chars
            next GLOSSARY_GAP + (GLOSSARY_SCALE * (glossary_metrics.advance('†') || 0.5)) + letter_spacing if text == '†'

            chars.each_with_index.sum do |char, i|
              advance = metrics.advance(char) || (wide?(char) ? 1.0 : 0.5)
              advance + letter_spacing + (chars[i + 1] ? metrics.kern(char, chars[i + 1]) : 0.0)
            end
          end

          # 折れない塊にまとめる。文節の後ろの空白は、塊の後ろにぶら下がる空き
          blocks = []
          segments.each do |segment|
            core = segment.rstrip
            space = segment.size > core.size ? width_of.(' ') : 0.0
            next blocks.last[2] += space if core.empty? && blocks.last

            joined = blocks.last && blocks.last[2].zero? && !title_break?(blocks.last[0][-1], core[0])
            if joined
              blocks.last[0] += core
              blocks.last[1] += width_of.(core)
              blocks.last[2] = space
            else
              blocks << [core, width_of.(core), space]
            end
          end

          lines = 1
          used = 0.0
          blocks.each do |_text, width, space|
            if used.positive? && used + width > limit
              lines += 1
              used = 0.0
            end
            used += width + space
          end
          lines
        end

        def title_break?(left, right)
          return true if left.nil? || right.nil?
          return false if NO_START.include?(right) || OPEN.include?(left)
          return true if wide?(left) || wide?(right)

          left == '-' && right.match?(/[A-Za-z]/)
        end
      end
    end
  end
end
