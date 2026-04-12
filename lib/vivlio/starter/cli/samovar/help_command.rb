# frozen_string_literal: true

# ================================================================
# File: lib/vivlio/starter/cli/samovar/help_command.rb
# ================================================================
# 責務:
#   Samovar CLI の help コマンドを実装する。
#   Public Commands のみをカテゴリ別に表示する。
#
# 表示内容:
#   - プロジェクト管理: new, import, pdf:read, doctor, clean
#   - 執筆・編集支援: create, delete, rename, renumber
#   - 文章校正・統計: lint, metrics
#   - 索引・用語集: index:auto, index:apply
#   - 画像・カバー: cover, resize
#   - ビルド・出力・プレビュー: build, open, pdf:compress
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
              'pdf:read' => 'PDFを解析して Markdown 形式へ変換・抽出します',
              'doctor' => '環境診断と不足ツールの自動セットアップ',
              'clean' => '生成物やキャッシュを削除します'
            },
            '執筆・編集支援' => {
              'create' => '章ファイルと画像ディレクトリを生成します',
              'delete' => '指定した章の Markdown と画像を削除します',
              'rename' => '章の番号やファイル名（スラッグ）を変更します',
              'renumber' => '章番号を一括で付け直します'
            },
            '文章校正・統計' => {
              'lint' => 'Markdownをtextlintで検査します',
              'metrics' => 'Markdownの行数・文字数を集計します'
            },
            '索引・用語集' => {
              'index:auto' => '索引・用語集の候補を抽出し、確認用ファイルを作成します',
              'index:apply' => '確認済みの候補を、プロジェクトの索引辞書に登録・保存します'
            },
            '画像・カバー' => {
              'cover' => '表紙・裏表紙の画像を生成します（A4/B5/A5/EPUB対応）',
              'resize' => 'images/画像をWebP形式に変換・最適化します（--high/--lowで品質変更可）'
            },
            'ビルド・出力・プレビュー' => {
              'build' => '書籍全体または指定章をビルドします',
              'open' => '生成されたPDFを開きます',
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
              📚 Vivlio Starter - 技術書執筆のためのCLIツール 🛠️
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
