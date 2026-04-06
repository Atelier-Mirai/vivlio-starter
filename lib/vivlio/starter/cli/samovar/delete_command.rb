# frozen_string_literal: true

# ================================================================
# File: lib/vivlio/starter/cli/samovar/delete_command.rb
# ================================================================
# 責務:
#   Samovar CLI の delete コマンドを実装する。
#   章 Markdown と画像ディレクトリの削除を行う。
#
# 対象指定方法:
#   - 章番号: "11" → 11-*.md にマッチ
#   - 範囲: "11-13" → 11〜13 番の章すべて
#   - ファイル名: "11-install" → 11-install.md
#
# 主要オプション:
#   - --force: 確認なしで削除
#
# 依存:
#   - DeleteCommands::DeleteCommandExecutor: 実際の削除処理
# ================================================================

require_relative '../delete'

module Vivlio
  module Starter
    module CLI
      module SamovarCommands
        # delete コマンドの Samovar 実装
        class DeleteCommand < Samovar::Command
          self.description = '指定した章の Markdown と画像を削除します'

          many :targets, '削除対象（章番号/レンジ/ファイル名）', default: []

          options do
            option '--force/-f', '確認なしで削除を実行', default: false, key: :force
            option '--yes/-y', '[互換] --force と同じ意味', default: false, key: :yes
            option '--verbose/-v', '冗長ログを表示', default: false, key: :verbose
            option '-h/--help', 'このコマンドの使い方を表示', key: :help
          end

          def call
            return print_usage if options[:help]

            DeleteCommands::DeleteCommandExecutor.new(options, target_args).call
            0
          rescue SystemExit => e
            raise e
          rescue StandardError => e
            common.log_error("delete コマンド実行中にエラー: #{e.message}")
            1
          end

          private

          def target_args
            Array(targets).dup
          end

          def common
            Vivlio::Starter::CLI::Common
          end
        end
      end
    end
  end
end
