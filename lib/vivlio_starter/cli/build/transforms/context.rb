# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/build/transforms/context.rb
# ================================================================
# 責務:
#   変換の段と本全体の段へ渡す文脈（出力先・ワークスペース・書き換えているページ）と、transforms/ の名前空間
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
        #
        # @!attribute target [OutputTarget] 出力先の宣言
        # @!attribute workspace [String] 出力先の HTML と CSS を置くディレクトリ（既定は宣言の値。
        #   テストは一時ディレクトリを渡す）
        # @!attribute path [String, nil] 書き換えているページの HTML のパス（変換の段の中だけ）
        # @!attribute pages [Hash{String => Nokogiri::HTML5::Document}] 本の全部のページ（パス → 今の DOM）。
        #   変換は自分のページだけを書き換える。ほかのページを読むのは、索引・用語集のリンク先を
        #   照合する PostProcessIndexGlossary だけである
        # @!attribute memo [Hash] 本の全部のページで使い回す値の置き場（remember で読み書きする）
        Context = Data.define(:target, :workspace, :path, :pages, :memo) do
          def initialize(target:, workspace: target.workspace, path: nil, pages: {}, memo: {}) = super

          # @param id [Symbol] 出力先の名前（:epub / :kindle）
          def self.for(id, workspace: nil)
            target = OutputTarget.for(id)
            new(target:, workspace: workspace || target.workspace)
          end

          # 出力先の名前。1.x の flavor（:epub / :kindle）と同じ値
          def flavor = target.id

          # 書き換えているページのファイル名（ログに出す）と、置き場のディレクトリ
          def page_name = File.basename(path)
          def page_dir = File.dirname(path)

          # 本の全部のページで同じ値を、最初のページで一度だけ求める（テーマの画像・外部コマンドの
          # 有無・変換した画像の表など）。段は状態を持たないので、ここに置く
          def remember(key) = memo.fetch(key) { memo[key] = yield }
        end
      end
    end
  end
end
