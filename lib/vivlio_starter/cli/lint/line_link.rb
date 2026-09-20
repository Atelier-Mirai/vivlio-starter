# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/lint/line_link.rb
# ================================================================
# 責務:
#   `vs lint` の集約表示にある出現行（`行: 223, 401`）を、クリックで
#   エディタの該当行へ飛べる形にする。
#
# なぜ 2 通り持つか:
#   端末がリンクを見つける道は 2 つあり、どちらも一長一短で、どちらが良いかは
#   使っている端末に依る——だから book.yml の lint.line_links で選ぶ。
#
#     compact … OSC 8 ハイパーリンク。飛び先を URI に隠せるので表示は `223` だけで済む。
#               ただしリンクの装飾（下線）は端末が勝手に付けるもので、こちらからは外せない。
#     path    … 素のテキストで `contents/10-intro.md:223` と書く。端末は**画面に見えている
#               文字列**を見てパスと行を割り出すので、パスを省くことはできない。
#               その代わり端末はこれを「ただの文字」として描くため、下線は付かない。
#
#   つまり「短く書いて下線も付けない」は原理的に選べない。選べるのは
#   「短いが下線が付く（compact）」か「下線は無いが冗長（path）」かの二択である。
#
# 出さない場面:
#   端末でないとき（パイプ・リダイレクト・テストの捕捉）は素の数字に戻す。
#   エスケープはファイルに落ちても読めないゴミにしかならず、ログの突き合わせを壊すため。
# ================================================================

require_relative '../common'

module VivlioStarter
  module CLI
    module Lint
      # 出現行の番号を、端末で開けるリンクへ仕立てる
      module LineLink
        # 薄い青（256 色）。基本色（\e[34m など）はテーマ側で塗り替えられ、
        # 背景に沈む配色があるため、番号が読めなくなる余地を残さない
        COLOR = "\e[38;5;110m"
        RESET = "\e[0m"

        # book.yml lint.line_links に書ける値
        MODES = %w[compact path off].freeze

        module_function

        # 出現行 1 つを表示用の文字列にする
        # @param line [Integer] 行番号
        # @param path [String, nil] 原稿のパス（`vs` を起動した場所からの相対）
        # @return [String] 端末に出す文字列（リンクにできないときは数字のまま）
        def render(line, path:)
          return line.to_s unless path && linkable?

          case mode
          when 'compact' then hyperlink(uri(path, line), colorize(line.to_s))
          when 'path'    then "#{path}:#{line}"
          else                line.to_s
          end
        end

        # リンクを出してよい場面か（端末に直接書いているときだけ）
        #
        # log_always は Common.emit を通り、並列ビルドや構造化出力では配列へ溜まる。
        # 溜める先は端末ではないので、そこへエスケープを混ぜない。
        def linkable?
          return false if Thread.current[Common::EMIT_SINK_KEY]

          $stdout.respond_to?(:tty?) && $stdout.tty?
        end

        # book.yml lint.line_links の設定値
        def mode = normalize(configured_mode)

        # 未知の値は compact として扱う。書き間違いで校正そのものが止まるより、
        # 既定の見え方で動いたほうが著者の手が止まらない
        def normalize(value) = MODES.include?(value) ? value : 'compact'

        def configured_mode
          Common::CONFIG.lint.line_links.to_s
        rescue NoMethodError
          ''
        end

        # file:// は絶対パスで書く（端末は起動時の作業ディレクトリを知らない）。
        # 行番号は `:223` と添える——`#L223` や `?line=` はエディタによって
        # 数行ずれた位置に着地した（Zed で実測）。
        def uri(path, line) = "file://#{File.expand_path(path)}:#{line}"

        # OSC 8: ESC ] 8 ;; URI ST テキスト ESC ] 8 ;; ST
        def hyperlink(uri, text) = "\e]8;;#{uri}\e\\#{text}\e]8;;\e\\"

        # NO_COLOR が立っていれば色を付けない（https://no-color.org/ の約束）
        def colorize(text)
          return text if ENV['NO_COLOR'] && !ENV['NO_COLOR'].empty?

          "#{COLOR}#{text}#{RESET}"
        end
      end
    end
  end
end
