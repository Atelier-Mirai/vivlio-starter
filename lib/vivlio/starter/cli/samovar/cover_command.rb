# frozen_string_literal: true

# ================================================================
# File: lib/vivlio/starter/cli/samovar/cover_command.rb
# ================================================================
# 責務:
#   Samovar CLI の cover コマンドを実装する。
#   カバー画像生成ロジック (CoverCommands) を呼び出す。
# ================================================================

require_relative '../cover'

module Vivlio
  module Starter
    module CLI
      module SamovarCommands
        # cover コマンドの Samovar 実装
        class CoverCommand < Samovar::Command
          self.description = 'カバー画像を生成します（A4/B5/A5/EPUB）'

          options do
            option '-h/--help', 'このコマンドの使い方を表示', key: :help
          end

          one :target, '生成対象 (auto, a4, b5, a5, epub)', default: 'auto', required: false

          def call
            return print_usage if options[:help]

            case target || 'auto'
            when 'auto', 'all'
              CoverCommands.execute_generate(self)
            when 'a4'
              CoverCommands.execute_for_size(:a4, self)
            when 'b5'
              CoverCommands.execute_for_size(:b5, self)
            when 'a5'
              CoverCommands.execute_for_size(:a5, self)
            when 'epub'
              CoverCommands.execute_epub(self)
            else
              Common.log_error("未知のカバー種別です: #{target}")
              Common.log_info('指定可能な値: auto, a4, b5, a5, epub')
              return 1
            end

            0
          end
        end
      end
    end
  end
end
