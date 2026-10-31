# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/samovar/config_command.rb
# ================================================================
# 責務:
#   Samovar CLI の config 系コマンドを実装する。設定ファイルの書き方を見せる（読むだけ）。
#
#   - vs config         : 下の 3 つの案内（vs index と同じ形）
#   - vs config:book    : book.yml の区分・キー・言葉から説明を引く
#   - vs config:catalog : catalog.yml の書き方と、その本の章立て
#   - vs config:talk    : talk.yml の書き方と、その本の話者。display: のキーも引く
#
# 依存:
#   - ConfigGuide: 説明の読み取りと表示（config-command-spec.md）
# ================================================================

require_relative '../config_guide'
require_relative 'vs_command'

module VivlioStarter
  module CLI
    module SamovarCommands
      # config コマンドの Samovar 実装
      class ConfigCommand < VsCommand
        self.description = '設定ファイルの書き方を調べるコマンドの一覧を表示します'

        options do
          option '-h/--help', 'このコマンドの使い方を表示', key: :help
        end

        def call
          puts <<~HELP
            設定ファイルの書き方を調べるコマンド:

              vs config:book [キー] - config/book.yml（本の設定）の説明と今の値を表示
              vs config:catalog     - config/catalog.yml（章の構成）の書き方と、この本の章立てを表示
              vs config:talk [キー] - config/talk.yml（会話文）の書き方と、この本の話者を表示

            book.yml の調べ方:
              vs config:book                     # 区分の一覧
              vs config:book index               # 区分のキーと説明
              vs config:book index.target_terms  # キーの説明と今の値
              vs config:book 目次                # 言葉で探す
          HELP
          0
        end
      end

      # config:book コマンドの Samovar 実装
      class ConfigBookCommand < VsCommand
        self.description = 'book.yml の設定の説明と今の値を表示します'

        options do
          option '-h/--help', 'このコマンドの使い方を表示', key: :help
        end

        one :query, '区分・キー・探す言葉（省略すると区分の一覧）', required: false

        def call
          return print_usage if options[:help]

          ConfigGuide::Book.new.show(query)
        rescue StandardError => e
          Common.log_error("config:book コマンド実行中にエラー: #{e.message}")
          1
        end
      end

      # config:catalog コマンドの Samovar 実装
      class ConfigCatalogCommand < VsCommand
        self.description = 'catalog.yml の書き方と、この本の章立てを表示します'

        options do
          option '-h/--help', 'このコマンドの使い方を表示', key: :help
        end

        def call
          return print_usage if options[:help]

          ConfigGuide::Catalog.new.show
        rescue StandardError => e
          Common.log_error("config:catalog コマンド実行中にエラー: #{e.message}")
          1
        end
      end

      # config:talk コマンドの Samovar 実装
      class ConfigTalkCommand < VsCommand
        self.description = 'talk.yml の書き方と、この本の話者を表示します'

        options do
          option '-h/--help', 'このコマンドの使い方を表示', key: :help
        end

        one :query, 'display: のキーか探す言葉（省略すると書き方と話者の一覧）', required: false

        def call
          return print_usage if options[:help]

          ConfigGuide::Talk.new.show(query)
        rescue StandardError => e
          Common.log_error("config:talk コマンド実行中にエラー: #{e.message}")
          1
        end
      end
    end
  end
end
