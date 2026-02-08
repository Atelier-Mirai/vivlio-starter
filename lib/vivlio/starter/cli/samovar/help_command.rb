# frozen_string_literal: true

# ================================================================
# File: lib/vivlio/starter/cli/samovar/help_command.rb
# ================================================================
# 責務:
#   Samovar CLI の help コマンドを実装する。
#   Public Commands のみをカテゴリ別に表示する。
#
# 表示内容 (help_spec.md 準拠):
#   - プロジェクト管理: new, import, doctor, clean
#   - 執筆・編集支援: create, delete, rename, renumber, open
#   - 文章校正・用語: lint, metrics
#   - アセット・索引: cover, resize, index
#   - ビルド・出力: build, pdf:compress
# ================================================================

module Vivlio
  module Starter
    module CLI
      module SamovarCommands
        # help コマンドの Samovar 実装
        class HelpCommand < Samovar::Command
          self.description = 'Vivlio Starter の主要コマンド一覧を表示します'

          COMMAND_CATEGORIES = {
            'プロジェクト管理' => {
              'new' => 'プロジェクトを新規作成します',
              'import' => 'Re:VIEW Starter プロジェクトを取り込みます',
              'doctor' => '環境診断と不足ツールの自動セットアップ',
              'clean' => '生成物やキャッシュを削除します'
            },
            '執筆・編集支援' => {
              'create' => '章ファイルと画像ディレクトリを生成します',
              'delete' => '指定した章の Markdown と画像を削除します',
              'rename' => '章のスラッグ/番号を変更します',
              'renumber' => '章番号を一括で付け直します',
              'open' => '生成されたPDFを開きます（macOS専用）'
            },
            '文章校正・用語' => {
              'lint' => 'Markdownをtextlintで検査します',
              'metrics' => 'Markdownの行数・文字数を集計します'
            },
            'アセット・索引' => {
              'cover' => 'カバー画像を生成します（A4/B5/A5/EPUB）',
              'resize' => '画像をWebPに変換します（--high/--low で品質変更可）',
              'index' => '索引機能（index:auto / index:apply）'
            },
            'ビルド・出力' => {
              'build' => '書籍全体または指定章をビルドします',
              'pdf:compress' => '生成済みPDFを圧縮します'
            }
          }.freeze

          options do
            option '-h/--help', 'ヘルプを表示', key: :help
          end

          def call
            print_public_commands_help
            0
          end

          private

          def print_public_commands_help
            puts <<~HEADER
              Vivlio Starter - 技術書執筆のためのCLIツール
              
              使い方: vs <command> [options]
              
            HEADER

            COMMAND_CATEGORIES.each do |category, commands|
              puts "  #{category}:"
              commands.each { |name, desc| puts format('    %-16s %s', name, desc) }
              puts
            end

            puts <<~FOOTER
              オプション:
                -h, --help       ヘルプを表示
                -v, --verbose    冗長出力を有効化
                --version        バージョン情報を表示

              各コマンドの詳細: vs <command> --help
            FOOTER
          end
        end
      end
    end
  end
end
