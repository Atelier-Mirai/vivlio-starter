# frozen_string_literal: true

module Vivlio
  module Starter
    module CLI
      # ==============================================================================
      # Module: HelpCommands
      # ------------------------------------------------------------------------------
      # Vivlio Starter の主要コマンドとオプションを一覧表示するヘルプ出力コマンド群。
      # 実際の処理は標準出力へ固定のチートシートを表示するのみ。
      #
      # ⚠️  注意: このファイルは cli.rb から require されているため削除不可。
      #   ただし、HELP_MESSAGE および print_help メソッドは現在使われていない。
      #   実際のヘルプ出力は lib/vivlio/starter/cli/samovar/help_command.rb の
      #   HelpCommand#print_public_commands_help が担っている。
      #
      #   将来的には cli.rb の責務分離と合わせて、このファイルのデッドコードを
      #   整理することを検討する（CHANGELOG Planned 参照）。
      # ==============================================================================
      module HelpCommands
        module_function

        HELP_DESC = {
          short: 'Vivlio Starter のヘルプを表示します',
          long: '主要コマンドとオプションのチートシートを表示します。'
        }.freeze

        HELP_MESSAGE = <<~HELP
          📚 Vivlio Starter - 技術書執筆のためのCLIツール 🛠️
          使い方: vs <command> [options]

          プロジェクト管理:
            new              プロジェクトを新規作成します
            import           Re:VIEW Starter プロジェクトを取り込みます
            pdf:read         PDFを解析して Markdown 形式へ変換・抽出します
            doctor           環境診断と不足ツールの自動セットアップ
            clean            生成物やキャッシュを削除します

          執筆・編集支援:
            create           章ファイルと画像ディレクトリを生成します
            delete           指定した章の Markdown と画像を削除します
            rename           章の番号やファイル名（スラッグ）を変更します
            renumber         章番号を一括で付け直します

          文章校正・統計:
            lint             Markdownをtextlintで検査します
            metrics          Markdownの行数・文字数を集計します

          索引・用語集:
            index:auto       索引・用語集の候補を抽出し、確認用ファイルを作成します
            index:apply      確認済みの候補を、プロジェクトの索引辞書に登録・保存します

          画像・カバー:
            cover            表紙・裏表紙の画像を生成します（A4/B5/A5/EPUB対応）
            resize           images/画像をWebP形式に変換・最適化します（--high/--lowで品質変更可）

          ビルド・出力・プレビュー:
            build            書籍全体または指定章をビルドします
            open             生成されたPDFを開きます
            pdf:compress     生成済みPDFを圧縮します

          オプション:
            -h, --help       ヘルプを表示
            -v, --verbose    冗長出力を有効化
            --version        バージョン情報を表示

          各コマンドの詳細: vs <command> --help
        HELP

        def print_help
          print HELP_MESSAGE
        end
      end
    end
  end
end
