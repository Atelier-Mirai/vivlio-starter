# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/lint/finding_rows.rb
# ================================================================
# 責務:
#   `vs lint` の集約表示を 3 つの検査で揃える。textlint（TextlintFormatter）・
#   独自校正（ProseChecker）・スペルチェック（SpellChecker）は、集める対象も
#   グループ化の鍵も違うが、**集めたあとの見せ方は同じでなければならない**——
#   著者から見れば 1 回の `vs lint` の出力だからである。
#
#   そこで「どう畳むか」は各検査に残し、「どう並べ、どう表示するか」だけを
#   ここへ集めた。3 箇所に同じ整形が散っていた頃は、並び順を直すのに 3 箇所を
#   同じように直す必要があり、片方だけ直して食い違う余地があった。
# ================================================================

require_relative '../common'
require_relative 'line_link'

module VivlioStarter
  module CLI
    module Lint
      # 集約済みの指摘を、表示用の行へ整えて並べる
      module FindingRows
        # 表示する出現行番号の最大件数（超過分は … で省略する）
        MAX_SHOWN_LINES = 10

        module_function

        # 並びは「件数の多い順、同数なら最初の出現行の早い順」。著者は原稿を上から
        # 直していくので、同じ重さの指摘は紙面の並びで出したほうが追いやすい。
        # 第 2 の鍵を明示するのは、Ruby の sort_by が安定ではなく、件数だけで並べると
        # 同数の行が実行ごとに違う順で出てしまうため。
        #
        # 出現行は畳んで昇順にする。**件数は呼び出し側が決めたものをそのまま使う**——
        # 「同じ行に 2 回出た」を 2 件と数えるか 1 件と数えるかは検査ごとに違い
        # （スペルチェックは語の出現行数、他は指摘の個数）、ここで決めてよいものではない。
        #
        # @param rows [Array<Hash>] { count:, label:, lines: [Integer] }
        # @param path [String, nil] 原稿のパス（出現行をクリックで開けるようにする。
        #   省くと素の数字で出る——飛び先が無いため）
        # @return [Array<Hash>] { count:, label:, lines: String }
        def arrange(rows, path: nil)
          rows.map { it.merge(lines: it[:lines].compact.uniq.sort) }
              .sort_by { [-it[:count], it[:lines].first || 0] }
              .map { it.merge(lines: format_lines(it[:lines], path)) }
        end

        # 出現行の並びを表示用の文字列にする（超過分は末尾の … に畳む）
        #
        # 畳むのはリンクにする前——省略した分をリンクにしても誰も押せないし、
        # 見えない行にエスケープだけが残る。
        # @param lines [Array<Integer>] 昇順に整列済みの出現行
        # @param path [String, nil] 原稿のパス
        # @return [String]
        def format_lines(lines, path = nil)
          shown = lines.first(MAX_SHOWN_LINES).map { LineLink.render(it, path: path) }.join(', ')
          lines.size > MAX_SHOWN_LINES ? "#{shown}, …" : shown
        end
      end
    end
  end
end
