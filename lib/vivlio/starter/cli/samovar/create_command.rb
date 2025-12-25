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
        # create 系コマンド共通のヘルパーメソッド
        module CreateCommandHelpers
          private

          def command_context(extra_options = {})
            CreateCommandContext.new(base_options.merge(extra_options))
          end

          def base_options
            { verbose: verbose_from_parent }
          end

          def verbose_from_parent
            return false unless parent.respond_to?(:options)

            !!parent.options[:verbose]
          end

          def common
            Vivlio::Starter::CLI::Common
          end
        end

        class CreateCommandContext
          attr_reader :options

          def initialize(options = {})
            @options = options || {}
          end
        end

        class CreateCommand < Samovar::Command
          include CreateCommandHelpers

          self.description = '章ファイルと画像ディレクトリを生成します'

          many :names, '作成する章スラッグ（複数可）', default: []

          options do
            option '-h/--help', 'このコマンドの使い方を表示', key: :help
          end

          def call
            return print_usage if options[:help]

            CreateCommands.execute_create(command_context, names)
            0
          rescue SystemExit => e
            raise e
          rescue StandardError => e
            common.log_error("create コマンド実行中にエラー: #{e.message}")
            1
          end
        end

        class CreateTitlepageCommand < Samovar::Command
          include CreateCommandHelpers

          self.description = 'config/book.yml からタイトルページを生成します'

          options do
            option '--force/-f', '既存ファイルを強制上書き', default: false, key: :force
            option '-h/--help', 'このコマンドの使い方を表示', key: :help
          end

          def call
            return print_usage if options[:help]

            CreateCommands.execute_titlepage(command_context(force: options[:force]))
            0
          rescue SystemExit => e
            raise e
          rescue StandardError => e
            common.log_error("create:titlepage 実行中にエラー: #{e.message}")
            1
          end
        end

        class CreateColophonCommand < Samovar::Command
          include CreateCommandHelpers

          self.description = 'config/book.yml から奥付 (_colophon.md) を生成します'

          options do
            option '--force/-f', '既存ファイルを強制上書き', default: false, key: :force
            option '-h/--help', 'このコマンドの使い方を表示', key: :help
          end

          def call
            return print_usage if options[:help]

            CreateCommands.execute_colophon(command_context(force: options[:force]))
            0
          rescue SystemExit => e
            raise e
          rescue StandardError => e
            common.log_error("create:colophon 実行中にエラー: #{e.message}")
            1
          end
        end

        class CreateLegalpageCommand < Samovar::Command
          include CreateCommandHelpers

          self.description = 'config/book.yml の legal 設定からリーガルページを生成します'

          options do
            option '--force/-f', '既存ファイルを強制上書き', default: false, key: :force
            option '-h/--help', 'このコマンドの使い方を表示', key: :help
          end

          def call
            return print_usage if options[:help]

            CreateCommands.execute_legalpage(command_context(force: options[:force]))
            0
          rescue SystemExit => e
            raise e
          rescue StandardError => e
            common.log_error("create:legalpage 実行中にエラー: #{e.message}")
            1
          end
        end
      end
    end
  end
end
