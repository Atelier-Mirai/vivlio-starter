# frozen_string_literal: true

# ================================================================
# File: lib/vivlio/starter/cli/samovar/clean_command.rb
# ================================================================
# 責務:
#   Samovar CLI の clean コマンドを実装する。
#   ビルド生成物・キャッシュ・カバー画像の削除を行う。
#
# 主要オプション:
#   - (なし): 中間生成物を削除、最終 PDF は保持
#   - --purge: 最終 PDF も含めてすべて削除
#   - --cache: キャッシュのみ削除
#   - --cover: カバー画像のみ削除（マスターは保持）
#
# 依存:
#   - CleanCommands: 実際の削除処理
# ================================================================

require_relative '../clean'

module Vivlio
  module Starter
    module CLI
      module SamovarCommands
        # clean コマンドの Samovar 実装
        class CleanCommand < Samovar::Command
          self.description = '生成物やキャッシュを削除します'

          options do
            option '--purge/-P', '生成物（PDF含む）をすべて削除します', default: false, key: :purge
            option '--cache/-C', 'キャッシュのみを削除します', default: false, key: :cache
            option '--cover', '生成されたカバー画像のみを削除します', default: false, key: :cover
            option '--generated-images', '生成された扉絵/装飾などの画像を削除します', default: false, key: :generated_images
            option '-h/--help', 'このコマンドの使い方を表示', key: :help
          end

          # 内部利用の --all オプションをパースするために手動で input をパッチする
          def initialize(input = nil, **options)
            @all_mode = false
            if input.is_a?(Array) && input.include?('--all')
              input.delete('--all')
              @all_mode = true
            end
            super(input, **options)
          end

          def call
            return print_usage if options[:help]

            opts = options.dup
            opts[:all] = @all_mode
            CleanCommands.execute_clean(opts)
            0
          rescue SystemExit => e
            raise e
          rescue StandardError => e
            Vivlio::Starter::CLI::Common.log_warn("clean コマンド実行中にエラー: #{e.message}")
            1
          end
        end
      end
    end
  end
end
