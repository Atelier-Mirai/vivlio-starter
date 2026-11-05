# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/pre_process/book_setting_warning.rb
# ================================================================
# 責務:
#   book.yml の値の誤り（色名・画像名・字数・寸法・倍率など）を 🟡 で知らせ、
#   IssueRegistry に記録して preflight / build の最終判定に数える。
#
# 設計:
#   - 章に紐付かない指摘なので chapter は nil（章別サマリーの表には出ず、最終行の件数に効く）
#   - 同じ設定は章ごとに何度も読まれるため、同じ文言は 1 回だけ出す
#     （IssueRegistry.reset! で数え直す。preflight / build の開始時に呼ばれる）
# ================================================================

require_relative '../common'
require_relative 'issue_registry'

module VivlioStarter
  module CLI
    module PreProcessCommands
      module BookSettingWarning
        module_function

        # @param message [String] 1 行目（どのキーのどの値が、どう扱われるか）
        # @param detail [String, nil] 2 行目以降（直し方）
        def report(message, detail: nil)
          return unless IssueRegistry.record_once(severity: :warn, category: :book_settings, message:)

          Common.log_warn(message, detail:)
        end
      end
    end
  end
end
