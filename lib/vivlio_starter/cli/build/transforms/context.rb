# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/build/transforms/context.rb
# ================================================================
# 責務:
#   変換の段と本全体の段へ渡す文脈（出力先とワークスペース）と、transforms/ の名前空間
# ================================================================

require_relative '../output_target'

module VivlioStarter
  module CLI
    module Build
      # 出力先の HTML を書き換える段（v2-architecture-spec.md §4.3）。
      # shared/ は EPUB と Kindle の両方、kindle/ は Kindle だけで走る。どの出力先でどの順に走るかは
      # 出力先の宣言（build/targets/*.rb）の transforms: が決める。
      #
      # 両方で走る段の名前空間を Common にしないのは、この下で書いた `Common.log_info` が
      # CLI::Common でなく Transforms::Common を指してしまうためである。
      module Transforms
        module Shared; end
        module Kindle; end

        # 段へ渡す文脈。
        # workspace は、出力先の HTML と CSS を置くディレクトリ（既定は出力先の宣言の値。
        # テストは一時ディレクトリを渡す）。
        Context = Data.define(:target, :workspace) do
          # @param id [Symbol] 出力先の名前（:epub / :kindle）
          def self.for(id, workspace: nil)
            target = OutputTarget.for(id)
            new(target:, workspace: workspace || target.workspace)
          end

          # 出力先の名前。1.x の flavor（:epub / :kindle）と同じ値
          def flavor = target.id
        end
      end
    end
  end
end
