# frozen_string_literal: true

# ================================================================
# File: lib/vivlio/starter/cli/pre_process/data_render/singularize.rb
# ================================================================
# 責務:
#   英単語の複数形を単数形に変換する軽量ヘルパー。
#   ActiveSupport::Inflector に依存せず、パターンマッチングで実装する。
#
# 例:
#   books       → book
#   categories  → category
#   branches    → branch
#   shelves     → shelf
#   elements    → element
#   data        → data（不変）
# ================================================================

module Vivlio
  module Starter
    module CLI
      module PreProcessCommands
        module DataRender
          # 英単語の複数形→単数形変換モジュール
          module Singularize
            module_function

            # 複数形の英単語を単数形に変換する
            # @param word [String] 変換対象の単語
            # @return [String] 単数形の単語
            def call(word)
              case word.to_s
              in /\A(.+)ies\z/              then "#{::Regexp.last_match(1)}y" # categories → category
              in /\A(.+)([sxz]|ch|sh)es\z/  then "#{::Regexp.last_match(1)}#{::Regexp.last_match(2)}" # branches → branch
              in /\A(.+)ves\z/              then "#{::Regexp.last_match(1)}f"       # shelves → shelf
              in /\A(.+)s\z/                then ::Regexp.last_match(1)             # elements → element
              else word.to_s # data, sheep（不変）
              end
            end
          end
        end
      end
    end
  end
end
