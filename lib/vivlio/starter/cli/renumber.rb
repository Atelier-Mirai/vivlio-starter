# frozen_string_literal: true

require 'fileutils'
module Vivlio
  module Starter
    module CLI
      # ================================================================
      # Module: renumber（章番号の付け直しユーティリティ）
      # ------------------------------------------------
      # - 目的: 全章の連番付け直し、または特定章の番号変更（rename の別名）
      # - 補足: 付録(91..97)は appendix-letter を自動調整
      # - 関連: 共通処理は `lib/vivlio/starter/cli/common.rb`
      # - NOTE: 実際のコマンドは lib/vivlio/starter/cli/samovar/rename_command.rb で実装
      # ================================================================
      module RenumberCommands
        module_function
      end
    end
  end
end
