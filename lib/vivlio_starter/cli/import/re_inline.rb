# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/import/re_inline.rb
# ================================================================
# 責務:
#   Re:VIEW / Starter のインライン命令（`@<name>{…}`）を Vivlio の記法へ直す。
#
# なぜ正規表現ひとつで済まないか（re-direct-import-spec.md §2.5）:
#   - Starter ではインライン命令を**入れ子にできる**（`@<code>{f(@<b>{x})}`）
#   - 引数の中の `}` は `\}` でエスケープする
#   - `@<b>|…|` `@<b>$…$` のフェンス記法があり、そちらはエスケープが効かない
#   どれも「対応する閉じ」を数えないと切り出せないので、文字送りで読む。
# ================================================================

require_relative '../image_filename_sanitizer'
require_relative 're_report'

module VivlioStarter
  module CLI
    module Import
      # インライン命令の変換
      module ReInline
        module_function

        # 変換に必要な周辺情報。行ごとに作り直さずに使い回す
        Context = Data.define(:report, :file, :line, :words) do
          def at(line) = with(line:)
        end

        # `@<name>` の頭。名前に使えるのは英数字と _
        COMMAND_HEAD = /\A@<([A-Za-z0-9_]+)>/

        # 前後を同じ記号で挟むだけの命令
        WRAPPERS = {
          'code' => '`', 'tt' => '`', 'file' => '`', 'samp' => '`', 'var' => '`',
          'ttb' => '`', 'tti' => '`',
          'B' => '**', 'strong' => '**', 'b' => '**', 'kw' => '**',
          'xstrong' => '**', 'xxstrong' => '**',
          'i' => '*', 'em' => '*', 'dfn' => '*', 'cite' => '*',
          'del' => '~~'
        }.freeze

        # 中身だけを残す。落ちる情報が無いので通知しない
        PLAIN = %w[nop letitgo userinput].freeze

        # 中身は残るが、装飾・機能は移せない（🟡）
        DEGRADED = {
          'u' => '下線', 'ins' => '下線（挿入箇所）', 'ami' => '網掛け', 'bou' => '傍点',
          'weak' => '目立たせない指定', 'abbr' => '略語の展開', 'acronym' => '略語の展開',
          'dtp' => 'DTP 指示', 'recipe' => 'レシピ指定', 'tcy' => '縦中横',
          'cursor' => 'ターミナルのカーソル', 'bib' => '参考文献への参照'
        }.freeze

        # 出力しない。本文に現れない命令なので、消しても紙面は変わらない
        DROPPED = %w[comment hidx foldhere].freeze

        # クロスリファレンス。Vivlio では `@ラベル` の一形式に集約される
        REFS = %w[list img imgref table eq hd chap chapref secref title column noteref].freeze

        # 引数を取らず、決まった文字になるもの
        LITERALS = { 'LaTeX' => 'LaTeX', 'TeX' => 'TeX', 'hearts' => '♥' }.freeze

        # 対応概念が無い（🔴）。原文をそのまま残す
        UNSUPPORTED = {
          'balloon' => 'コード内の吹き出し',
          'embed' => '出力形式ごとの生データ', 'raw' => '出力形式ごとの生データ',
          'big' => '文字を大きくする指定', 'large' => '文字を大きくする指定',
          'xlarge' => '文字を大きくする指定', 'xxlarge' => '文字を大きくする指定'
        }.freeze

        # 小書き（`@<small>` 系）。行まるごとか文中かでレンダラが使い分ける
        SMALL = %w[small xsmall xxsmall].freeze

        # テキスト 1 行ぶんのインライン命令を Vivlio の記法へ直す
        #
        # @param text [String] .re の 1 行（または引数の中身）
        # @param context [Context]
        # @param plain [Boolean] true なら装飾を付けず中身だけを残す
        #   （インラインコードの中では Markdown の装飾記号が効かないため）
        # @return [String]
        def transform(text, context, plain: false)
          out = +''
          index = 0

          while (at = text.index('@<', index))
            out << text[index...at]
            command = read_command(text, at)

            if command
              out << render(command, context, plain:)
              index = command[:next]
            else
              out << '@<'
              index = at + 2
            end
          end

          out << text[index..].to_s
        end

        # 装飾をすべて落として中身だけを取り出す（キャプション・照合用）
        def strip(text, context) = transform(text, context, plain: true)

        # `@<name>{…}` を 1 つ読む。読めなければ nil（ただの文字列として扱う）
        def read_command(text, at)
          head = COMMAND_HEAD.match(text[at..])
          return nil unless head

          body_at = at + head[0].length
          delimiter = text[body_at]
          return nil if delimiter.nil? || delimiter.match?(/[A-Za-z0-9\s]/)

          arg, following = read_argument(text, body_at, delimiter)
          return nil unless arg

          { name: head[1], arg:, at:, raw: text[at...following], next: following }
        end

        # 引数の中身と、その次に読む位置を返す
        def read_argument(text, body_at, delimiter)
          delimiter == '{' ? read_braced(text, body_at + 1) : read_fenced(text, body_at + 1, delimiter)
        end

        # `{ … }` を閉じまで読む。
        #
        # **裸の `{` は数えない**——Starter のスキャナ（`scan_inline_command`）は
        # `@<name>{` という開始トークンでだけ入れ子を積み、`}` で下ろす。
        # だから `@<b>{var x = {a: 1\};}` のように「開いていない `}`」を
        # エスケープする書き方が成立する（`\{` はエスケープではない）。
        def read_braced(text, from)
          buffer = +''
          depth = 0
          index = from

          while index < text.length
            if text[index] == '\\' && ['}', '\\'].include?(text[index + 1])
              buffer << text[index + 1]
              index += 2
              next
            end

            nested = nested_open(text, index)
            if nested
              depth += 1
              buffer << nested
              index += nested.length
              next
            end

            if text[index] == '}'
              return [buffer, index + 1] if depth.zero?

              depth -= 1
            end

            buffer << text[index]
            index += 1
          end

          [nil, nil]
        end

        # その位置から始まる入れ子の開始トークン（`@<name>{`）。無ければ nil
        def nested_open(text, index)
          return nil unless text[index] == '@'

          head = COMMAND_HEAD.match(text[index..])
          return nil unless head && text[index + head[0].length] == '{'

          "#{head[0]}{"
        end

        # `| … |` のフェンス記法。エスケープは効かない（Starter の仕様）
        def read_fenced(text, from, delimiter)
          close = text.index(delimiter, from)
          close ? [text[from...close], close + 1] : [nil, nil]
        end

        # 読み取った 1 命令を Vivlio の記法へ直す
        def render(command, context, plain: false)
          name = command[:name]
          arg = command[:arg]

          return keep_original(command, context) if UNSUPPORTED.key?(name)

          context.report.count(:inline)
          return transform(arg, context, plain: true) if plain

          render_known(name, arg, context)
        end

        # 🔴 対応概念が無い記法。原文を残して著者に判断してもらう
        def keep_original(command, context)
          name = command[:name]
          context.report.unsupported(
            "@<#{name}>",
            file: context.file, line: context.line,
            message: "@<#{name}>（#{UNSUPPORTED[name]}）は Vivlio に対応する記法がありません。原文をそのまま残しました。",
            detail: '対処: 該当箇所を書き換えてください（拡張記法リファレンスの章を参照）。'
          )
          command[:raw]
        end

        def render_known(name, arg, context)
          case name
          when *WRAPPERS.keys then wrap(name, arg, context)
          when *PLAIN then transform(arg, context)
          when *DROPPED then ''
          when *REFS then "@#{ReInline.strip(arg, context).strip}"
          when *SMALL then %(<span class="small">#{transform(arg, context)}</span>)
          when *LITERALS.keys then LITERALS[name]
          when *DEGRADED.keys then degrade(name, arg, context)
          else render_special(name, arg, context)
          end
        end

        # `@<code>{…}` のような囲み。中では Markdown の装飾記号が効かないので
        # 引数は plain で解く（`@<code>{f(@<b>{x})}` は `` `f(x)` `` になる）
        def wrap(name, arg, context)
          note_bold_as_strong(context) if name == 'b'
          mark = WRAPPERS.fetch(name)
          body = transform(arg, context, plain: mark == '`')
          return "`` #{body} ``" if mark == '`' && body.include?('`')

          "#{mark}#{body}#{mark}"
        end

        # Re:VIEW の `@<b>` は「太字にするだけ」で、`@<B>`（＝`@<strong>`）と違って
        # ゴシック体にならない。Vivlio の強調（`**…**`）は太字に色も付くので、
        # そのぶん見た目が変わる。Markdown に「色の付かない太字」は無いため
        # `**…**` へ寄せ、変わることだけ伝える（著者の作業は要らない）
        def note_bold_as_strong(context)
          context.report.note('@<b>',
                              file: context.file, line: context.line,
                              message: '@<b>（太字だけの指定）は強調（**…**）にしました。' \
                                       'Vivlio の強調は太字に色も付きます。')
        end

        def degrade(name, arg, context)
          context.report.degraded(
            "@<#{name}>",
            file: context.file, line: context.line,
            message: "@<#{name}>の#{DEGRADED[name]}は移せないため、中身だけを残しました。",
            detail: '対処: 強調が必要なら **…** などに書き換えてください。'
          )
          transform(arg, context)
        end

        # 引数の解釈が要るもの
        def render_special(name, arg, context)
          case name
          when 'href', 'hlink' then render_link(arg, context)
          when 'ruby' then render_ruby(arg, context)
          when 'fn' then "[^#{arg.strip}]"
          when 'm' then "$#{arg.strip}$"
          when 'kbd' then "〘#{transform(arg, context)}〙"
          when 'q', 'qq' then "“#{transform(arg, context)}”"
          when 'sup', 'sub' then "<#{name}>#{transform(arg, context)}</#{name}>"
          when 'uchar' then render_uchar(arg, context)
          when 'icon' then "![](#{ImageFilenameSanitizer.sanitize(arg.strip)}.webp)"
          when 'br' then "\n"
          when 'par' then "\n\n"
          when 'clearpage' then "\n\n@pagebreak\n\n"
          when 'idx', 'term', 'termnoidx' then "[#{arg.strip}]"
          when 'pageref' then "@pageref:#{arg.strip}"
          when 'w', 'wb', 'W' then render_word(name, arg, context)
          when 'include' then render_include(arg, context)
          else render_unknown(name, arg, context)
          end
        end

        # `@<href>{url, テキスト}`。テキストが無ければ URL をそのまま出す。
        # 分割は最初のカンマだけ（Re:VIEW と同じ。URL にカンマがあれば著者が直す）
        def render_link(arg, context)
          url, text = arg.split(',', 2).map(&:strip)
          text.to_s.empty? ? "<#{url}>" : "[#{transform(text, context)}](#{url})"
        end

        def render_ruby(arg, context)
          base, reading = arg.split(',', 2).map(&:strip)
          return transform(arg, context) if reading.to_s.empty?

          "{#{base}|#{reading}}"
        end

        def render_uchar(arg, context)
          code = Integer(arg.strip, 16)
          [code].pack('U')
        rescue ArgumentError, RangeError
          context.report.degraded(
            '@<uchar>',
            file: context.file, line: context.line,
            message: "@<uchar>{#{arg}} のコードポイントを読めませんでした。原文を残しました。"
          )
          "@<uchar>{#{arg}}"
        end

        # 単語展開。辞書（Starter の words.yml）が要る
        def render_word(name, arg, context)
          key = arg.strip
          word = context.words[key]

          unless word
            context.report.unsupported(
              "@<#{name}>",
              file: context.file, line: context.line,
              message: "@<#{name}>{#{key}} を展開できません（words.yml に #{key} がありません）。原文を残しました。",
              detail: '対処: 展開後の語を直接書いてください。'
            )
            return "@<#{name}>{#{key}}"
          end

          name == 'w' ? word : "**#{word}**"
        end

        # `@<include>{file}` は原稿の分割取り込み。パーサ側（ReParser）で
        # ファイルごと読み込むので、ここまで来たものは解決できなかったもの
        def render_include(arg, context)
          context.report.degraded(
            '@<include>',
            file: context.file, line: context.line,
            message: "@<include>{#{arg}} の取り込み先が見つかりませんでした。",
            detail: '対処: 取り込み先の内容を原稿へ直接書いてください。'
          )
          ''
        end

        # 定義に無い命令。原稿の誤記のことが多い（実測: @<if>{…}）
        def render_unknown(name, arg, context)
          context.report.unsupported(
            "@<#{name}>",
            file: context.file, line: context.line,
            message: "@<#{name}> は Re:VIEW にも Starter にも無い命令です（原稿の誤記の可能性）。原文を残しました。",
            detail: '対処: 命令名の綴りを確かめてください。'
          )
          "@<#{name}>{#{arg}}"
        end
      end
    end
  end
end
