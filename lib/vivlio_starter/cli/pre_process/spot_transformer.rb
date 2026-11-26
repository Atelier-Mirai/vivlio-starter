# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/pre_process/spot_transformer.rb
# ================================================================
# 責務:
#   小さな挿絵を置く囲み `:::{.spot-right}`・`:::{.spot-left}`（改善案 #157）と、回り込ませずに
#   中央に置く `:::{.spot-center}`（改善案 #168）を、
#   幅を持つ `<div>` へ書き換え、中の画像に既定の属性を足す。
#
#     :::{.spot-left width=35%}          <div class="spot-left" style="width: 35%">
#     すてきな世界だわ              →
#                                        すてきな世界だわ
#     ![笑顔](haruka.webp)
#     :::                                ![笑顔](haruka.webp){trim=on border=off}
#
#                                        </div>
#                                        （閉じの後も空行）
#
#   見た目（float・吹き出し）は layout-utils.css が受け持つ。一つ目の段落が吹き出しになる。
#
# なぜ `<div>` へ書き換えるのか:
#   囲みの汎用の変換（ReplacementRules の CONTAINER_RULES）は、`{…}` の中にクラス名しか
#   通さない。`width=35%` を書くと開きの行が変換されず、本文に `:::{…}` が残る。
#   幅はここで style に移す。開きの後と閉じの前に空行を置き、中の段落と画像を
#   Markdown として読ませる（HTML ブロックは空行まで続くため）。
#
# なぜ画像に trim=on・border=off を足すのか:
#   小さな挿絵は、枠を付けず、余白を詰めて載せるのが普通の使い方なので、著者が画像ごとに
#   書かなくて済むようにする。著者が trim=・crop=・border= を書いていれば、そちらを使う。
#   余白の多い画像の警告（ImageTrimmer の 85%）も、この囲みの中では出さない。
#
# パイプラインの位置:
#   画像パスの正規化（normalize_image_paths!）の後、border= を内部クラスへ読み替える
#   transform_image_borders! の前。足した border=off も読み替えに載せるため。
#   幅の点検（validate）は、原稿そのままの行番号が使える前処理の最初に行う。
# ================================================================

require_relative '../common'
require_relative '../masking'
require_relative 'issue_registry'

module VivlioStarter
  module CLI
    module PreProcessCommands
      # 小さな挿絵の囲み（.spot-right・.spot-left・.spot-center）の前処理
      module SpotTransformer
        module_function

        # 小さな挿絵の囲みのクラス名。ImageTrimmer の余白の警告もこれを見る。
        CLASSES = %w[spot-right spot-left spot-center].freeze

        # 囲みの開き（`:::{.spot-right width=35%}`）。中身はクラス名と属性。
        OPEN = /\A[ \t]*:::[ \t]*\{([^{}\n]*)\}[ \t]*\n?\z/
        # 囲みの閉じ。`::::` の外枠の閉じには当たらない。
        CLOSE = /\A[ \t]*:::[ \t]*\n?\z/

        # 段落に単独で置いた画像（属性は任意）。
        IMAGE_LINE = /\A([ \t]*)(!\[[^\]]*\]\([^)]*\))(?:\{([^{}\n]*)\})?[ \t]*(\n?)\z/

        # 囲みの幅。画像の width= と同じ書き方（CSS の長さか割合。単位のない数は px）。
        WIDTH_VALUE = /\A["']?(\d+(?:\.\d+)?(?:%|mm|cm|Q|in|pt|px|em|rem)?)["']?\z/

        TRIM_OR_CROP = /(?<![\w-])(?:trim|crop)=/
        BORDER = /(?<![\w-])border=/

        # 囲みの開き 1 つ。line は 1 始まり。
        Block = Data.define(:line, :classes, :params)

        # 幅や属性の誤りを、原稿の行番号で知らせる。
        # @param content [String] 原稿（前処理の最初の、行番号が原稿と一致している時点）
        # @param filename [String] 警告に出すファイル名
        def validate(content, filename)
          each_block(content) do |block, _close_line|
            block.params.each { warn_param(filename, block, it) unless width_value(it) }
          end
        end

        # 囲みを `<div>` へ書き換え、中の画像に既定の属性を足す。
        # @param content [String]
        # @return [String]
        def transform(content)
          return content unless content.include?('spot-')

          lines = content.lines
          each_block(content).reverse_each do |block, close_line|
            inner = lines[block.line...(close_line - 1)].map { with_image_defaults(it) }
            # 閉じの後にも空行を置く。`</div>` の HTML ブロックは空行まで続き、すぐ後の段落を
            # 生の文字として飲み込むため
            lines[(block.line - 1)...close_line] = [open_tag(block), "\n", *inner, "\n", "</div>\n", "\n"]
          end
          lines.join
        end

        # 閉じた囲みを順に返す。コードの中の作例と、閉じない囲みは数えない。
        # 囲みの中に別の囲みの開きがあれば、その囲みは数えない（中身を壊さないため）。
        # @return [Enumerator<Array(Block, Integer)>] 開きと、閉じの行番号
        def each_block(content)
          return enum_for(:each_block, content) unless block_given?

          code = Masking.code_lines(content)
          pending = nil
          content.each_line.with_index(1) do |line, number|
            next if code.include?(number)

            if pending && line.match?(CLOSE)
              yield pending, number
              pending = nil
            elsif (open = line.match(OPEN))
              pending = spot_block(open[1], number)
            end
          end
        end

        def spot_block(body, line)
          params, tokens = body.split.partition { it.include?('=') }
          classes = tokens.map { it.delete_prefix('.') }
          return nil unless classes.any? { CLASSES.include?(it) }

          Block.new(line:, classes:, params:)
        end

        def open_tag(block)
          width = block.params.filter_map { width_value(it) }.first
          style = width ? %( style="width: #{width}") : ''
          %(<div class="#{block.classes.join(' ')}"#{style}>\n)
        end

        # `width=35%` の値。幅でなければ nil。単位のない数は px（画像の width= と同じ）。
        def width_value(param)
          key, value = param.split('=', 2)
          return nil unless key == 'width'

          width = value.to_s[WIDTH_VALUE, 1]
          width&.match?(/\A[\d.]+\z/) ? "#{width}px" : width
        end

        def with_image_defaults(line)
          match = line.match(IMAGE_LINE)
          return line unless match

          indent, image, attributes, newline = match.captures
          added = []
          added << 'trim=on' unless attributes.to_s.match?(TRIM_OR_CROP)
          added << 'border=off' unless attributes.to_s.match?(BORDER)
          return line if added.empty?

          "#{indent}#{image}{#{[attributes, *added].compact.join(' ').strip}}#{newline}"
        end

        def warn_param(filename, block, param)
          message = "小さな挿絵の囲みの属性を読めません（#{param}）"
          opener = ":::{#{block.classes.map { ".#{it}" }.join(' ')} width=35%}"
          Common.log_warn(
            "#{filename}:#{block.line} - #{message}",
            detail: "→ 幅を変えるなら #{opener} のように書いてください（% か mm などの長さ）。\n" \
                    "  幅を書かなければ、版面の #{block.classes.include?('spot-center') ? 40 : 28}% で組みます。"
          )
          IssueRegistry.record(chapter: filename, line: block.line, severity: :warn, category: :notation, message:)
        end
      end
    end
  end
end
