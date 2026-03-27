# frozen_string_literal: true

# ================================================================
# File: lib/vivlio/starter/cli/samovar/create_command.rb
# ================================================================
# 責務:
#   Samovar CLI の create 系コマンドを実装する。
#   章ファイル・特殊ページの生成を行う。
#
# 提供コマンド:
#   - create: 章 Markdown と画像ディレクトリを生成
#   - create:titlepage: タイトルページを生成
#   - create:colophon: 奥付を生成
#   - create:legalpage: 免責・商標ページを生成
#
# 依存:
#   - CreateCommands: 実際の生成処理
# ================================================================

require_relative '../create'

module Vivlio
  module Starter
    module CLI
      module SamovarCommands
        # create コマンド（Publicコマンド）
        class CreateCommand < Samovar::Command
          self.description = '章ファイルと画像ディレクトリを生成します'

          many :names, '作成する章スラッグ（複数可）', default: []

          options do
            option '-h/--help', 'このコマンドの使い方を表示', key: :help
          end

          def call
            return print_usage if options[:help]

            CreateCommands.execute_create(build_options, names)
            0
          rescue SystemExit => e
            raise e
          rescue StandardError => e
            Common.log_error("create コマンド実行中にエラー: #{e.message}")
            1
          end

          private

          def build_options
            { verbose: parent_verbose? }
          end

          def parent_verbose?
            parent&.options&.[](:verbose) || false
          end
        end

        # create:cover コマンド（内部コマンド）
        class CreateCoverCommand < Samovar::Command
          self.description = '表紙・裏表紙SVGを生成します（内部コマンド）'

          def call
            CreateCommands.execute_cover(build_options)
            0
          rescue SystemExit => e
            raise e
          rescue StandardError => e
            Common.log_error("create:cover 実行中にエラー: #{e.message}")
            1
          end

          private

          def build_options
            { verbose: parent_verbose? }
          end

          def parent_verbose?
            parent&.options&.[](:verbose) || false
          end
        end

        # create:titlepage コマンド（内部コマンド）
        class CreateTitlepageCommand < Samovar::Command
          self.description = 'タイトルページを生成します（内部コマンド）'

          options do
            option '--force/-f', '既存ファイルを強制上書き', default: false, key: :force
          end

          def call
            CreateCommands.execute_titlepage(build_options)
            0
          rescue SystemExit => e
            raise e
          rescue StandardError => e
            Common.log_error("create:titlepage 実行中にエラー: #{e.message}")
            1
          end

          private

          def build_options
            { verbose: parent_verbose?, force: options[:force] }
          end

          def parent_verbose?
            parent&.options&.[](:verbose) || false
          end
        end

        # create:colophon コマンド（内部コマンド）
        class CreateColophonCommand < Samovar::Command
          self.description = '奥付を生成します（内部コマンド）'

          options do
            option '--force/-f', '既存ファイルを強制上書き', default: false, key: :force
          end

          def call
            CreateCommands.execute_colophon(build_options)
            0
          rescue SystemExit => e
            raise e
          rescue StandardError => e
            Common.log_error("create:colophon 実行中にエラー: #{e.message}")
            1
          end

          private

          def build_options
            { verbose: parent_verbose?, force: options[:force] }
          end

          def parent_verbose?
            parent&.options&.[](:verbose) || false
          end
        end

        # create:legalpage コマンド（内部コマンド）
        class CreateLegalpageCommand < Samovar::Command
          self.description = 'リーガルページを生成します（内部コマンド）'

          options do
            option '--force/-f', '既存ファイルを強制上書き', default: false, key: :force
          end

          def call
            CreateCommands.execute_legalpage(build_options)
            0
          rescue SystemExit => e
            raise e
          rescue StandardError => e
            Common.log_error("create:legalpage 実行中にエラー: #{e.message}")
            1
          end

          private

          def build_options
            { verbose: parent_verbose?, force: options[:force] }
          end

          def parent_verbose?
            parent&.options&.[](:verbose) || false
          end
        end
      end
    end
  end
end
