# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/build/transforms/runner.rb
# ================================================================
# 責務:
#   変換の並びを HTML に当てる
# ================================================================

require_relative 'context'

module VivlioStarter
  module CLI
    module Build
      # 変換の並びを HTML に当てる
      module Transforms::Runner
        module_function

        # 出力先の宣言の順に、段を 1 つずつ全部のページへ当てる。
        #
        # @param transforms [Array<Module>] 変換の段（`call(html_files, ctx)` を持つモジュール）の並び
        # @param html_files [Array<String>] 出力先のワークスペースの HTML のパス
        # @param ctx [Transforms::Context]
        # @return [Array<String>] そのままの配列
        def apply!(transforms, html_files, ctx)
          transforms.each { it.call(html_files, ctx) }
          html_files
        end
      end
    end
  end
end
