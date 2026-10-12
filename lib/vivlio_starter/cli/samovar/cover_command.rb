# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/samovar/cover_command.rb
# ================================================================
# 責務:
#   Samovar CLI の cover コマンドを実装する。
#   カバー画像生成ロジック (CoverCommands) を呼び出す。
# ================================================================

require_relative '../cover'
require_relative '../guards'
require_relative 'vs_command'

module VivlioStarter
  module CLI
    module SamovarCommands
      # cover コマンドの Samovar 実装
      class CoverCommand < VsCommand
        self.description = '表紙・裏表紙の画像を生成します（book.yml の判型と output.targets に従う）'

        options do
          option '-h/--help', 'このコマンドの使い方を表示', key: :help
        end

        def call
          return print_usage if options[:help]

          # 前提条件の検証（ProjectRoot ◎ / ImagesDir ○）
          guard_failure = Guards.precheck(
            Guards::ProjectRootCheck.new,
            Guards::RelaxedCheck.new(Guards::ImagesDirCheck.new)
          )
          return guard_failure if guard_failure

          CoverCommands.execute_generate(self)
          0
        end
      end
    end
  end
end
