# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/math_delimiters.rb
# ================================================================
# 責務:
#   数式の区切り（`$$…$$`・`\[…\]`・`$…$`・`\(…\)`）の綴りの唯一の定義元。
#
# なぜ独立したファイルか:
#   数式を SVG にする MathTransformer と、数式の中を索引の印として読まない
#   IndexMarkup（改善案.md #115）の両方が、同じ区切りで数式を見分ける必要がある。
#   MathTransformer に置いたままだと、IndexMarkup が書体の処理や設定の読み込みまで
#   連れてくることになるので、綴りだけをここへ切り出した。
# ================================================================

module VivlioStarter
  module CLI
    module MathDelimiters
      # $$ を $ より先に当てる（INLINE_DOLLAR は $$ の片割れを拾わないが、順序で確実にする）
      DISPLAY_DOLLAR  = /(?<!\\)\$\$(.+?)(?<!\\)\$\$/m
      DISPLAY_BRACKET = /\\\[(.+?)\\\]/m
      INLINE_DOLLAR   = /(?<!\\)\$(?!\s)((?:[^$\n\\]|\\.)+?)(?<!\s)(?<!\\)\$(?!\$)/
      INLINE_PAREN    = /\\\((.+?)\\\)/m

      # 当てる順に並べたもの
      ALL = [DISPLAY_DOLLAR, DISPLAY_BRACKET, INLINE_DOLLAR, INLINE_PAREN].freeze
    end
  end
end
