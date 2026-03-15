# frozen_string_literal: true

# vivlio-starter テンプレートコンパイラ
# 著者が書きやすい独自記法を Slim に変換する。
#
# 変換ルール:
#   = expr              → nil/空文字なら行ごとスキップ（nil安全展開）
#   prefix = expr       → nil/空文字なら行ごとスキップ（nil安全展開）
#   = "literal string"  → | literal string
#   空行                 → | （空リテラル行）
#   - / | / で始まる行  → そのまま通す（Slim 構文）
#
# 例:
#   ### = book.title          → book.title が nil/空文字なら行スキップ
#   **著者**: = book.author   → book.author が nil/空文字なら行スキップ
#   ![](= book.cover){...}    → book.cover が nil/空文字なら行スキップ

module Vivlio
  module Starter
    module TemplateCompiler
      SLIM_CODE_PATTERN      = /\A\s*-/.freeze
      SLIM_LITERAL_PATTERN   = /\A\s*\|/.freeze
      SLIM_COMMENT_PATTERN   = /\A\s*\//.freeze
      STRING_LITERAL_PATTERN = /\A(\s*)=\s*"(.*)"\s*\z/.freeze

      # = expr を検出。= の前は行頭・空白のみ許可（align=right などは除外）
      EXPAND_PATTERN = /(?:^|(?<=\s))=\s*([A-Za-z_][A-Za-z0-9_.?]*)/.freeze

      # ![]( expr ) → 画像パスの自動展開
      # 拡張子あり（.png等）はリテラル、拡張子なし変数名のみ展開
      IMAGE_EXT_PATTERN  = /\.(png|jpg|jpeg|webp|gif|svg)\z/i.freeze
      IMAGE_PATH_PATTERN = /!\[([^\]]*)\]\(([A-Za-z_][A-Za-z0-9_.?]*)\)/.freeze

      def self.compile(source)
        counter = 0
        current_indent = ''
        source.lines.map do |line|
          raw = line.chomp

          # 空行 → 直前のインデントレベルを保持した改行出力
          if raw.strip.empty?
            next "#{current_indent}- _blank = \"\\n\"\n#{current_indent}| \#{_blank}\n"
          end

          # 現在のインデントレベルを更新
          current_indent = raw[/\A\s*/]

          # Slim 構文はそのまま通す
          next "#{raw}\n" if raw.match?(SLIM_CODE_PATTERN)
          next "#{raw}\n" if raw.match?(SLIM_LITERAL_PATTERN)
          next "#{raw}\n" if raw.match?(SLIM_COMMENT_PATTERN)

          # = "literal string" → | literal string
          if (m = raw.match(STRING_LITERAL_PATTERN))
            next "#{m[1]}| #{m[2]}\n"
          end

          indent  = raw[/\A\s*/]
          content = raw.lstrip

          # = expr または ![]( expr ) を含む行 → nil安全展開
          if content.match?(EXPAND_PATTERN) || content.match?(IMAGE_PATH_PATTERN)
            # nil安全の軸となる expr を先に取得
            expr = content.match(EXPAND_PATTERN)&.[](1) ||
                   content.match(IMAGE_PATH_PATTERN)&.[](2)

            # ![]( expr ) → 拡張子なし変数名のみ #{expr} に変換
            content = content.gsub(IMAGE_PATH_PATTERN) do
              alt, path = $1, $2
              IMAGE_EXT_PATTERN.match?(path) ? "![#{alt}](#{path})" : "![#{alt}](\#{#{path}})"
            end
            var  = "_l#{counter += 1}"
            # = expr を #{expr} に置換
            tmpl = content.gsub(EXPAND_PATTERN, '#{\1}')
            [
              "#{indent}- #{var} = #{expr}.then { \"#{tmpl}\\n\" } unless #{expr}.nil? || #{expr}.to_s.empty?",
              "#{indent}- if #{var}",
              "#{indent}  | \#{#{var}}\n"
            ].join("\n")
          else
            # = を含まない通常行 → | リテラル
            "#{indent}| #{content}\n"
          end
        end.join
      end
    end
  end
end