# frozen_string_literal: true

module Vivlio
  module Starter
    module CLI
      # ==============================================================================
      # Module: HelpCommands
      # ------------------------------------------------------------------------------
      # Vivlio Starter の主要コマンドとオプションを一覧表示するヘルプ出力コマンド群。
      # 実際の処理は標準出力へ固定のチートシートを表示するのみ。
      # ==============================================================================
      module HelpCommands
        module_function

        HELP_DESC = {
          short: 'Vivlio Starter のヘルプを表示します',
          long: '主要コマンドとオプションのチートシートを表示します。'
        }.freeze

        HELP_MESSAGE = <<~HELP
          📚 Vivlio Starter - Build System

          主なコマンド:
            vs build                       - 全ファイルをビルド
            vs build <chapter_name>        - 指定した章のみをビルド
            vs open                        - 生成されたPDFを開く(macOS専用)
            vs pdf:compress                - 生成されたPDFを圧縮
            vs doctor                      - 必要ツールの診断とセットアップ(macOS)
              （Xcode Command Line Tools / Homebrew / Node.js / qpdf / pdfinfo / gs / ImageMagick 等）
              --fix                        # 不足ツールを自動インストール(Homebrew)。Homebrew が無ければ自動導入を案内
                                           # macOS では CLT 未導入時にインストーラを起動し、完了を待機
              -y, --yes                    # 確認を省略（Homebrew 導入や npm -g 実行時の確認をスキップ）

          # ビルドオプション:
          --high                # 高画質でビルド（画像の品質優先）
          --medium              # 標準画質でビルド（デフォルト）
          --low                 # 低画質でビルド（ファイルサイズ優先）
          --no-resize           # 画像のリサイズ/最適化をスキップ
          --no-compress         # PDFの圧縮をスキップ
          --no-clean            # 中間ファイルのクリーンアップをスキップ
          --log[=level]         # ログレベルを指定（error/warn/info/debug、既定は info）

          章の管理:
            vs create <chapter_name>       - 新しい章を作成
            vs delete <chapter_name>       - 指定した章を削除
            vs rename <old> <new>          - 章名・付録名/番号を変更
                                          （例: 11-install → 12-setup, 21 → 32）
            vs renumber                    - 章番号・付録番号を整列
            vs clean                       - ビルド生成物をクリーンアップ

          プロジェクト作成:
            vs new <name>                  - 新規書籍プロジェクトを作成
              (既定) 依存ツールの自動インストールを実行し、確認を省略します
              --interactive                # 対話的に確認しながら実行
              --manual-install             # doctor の自動実行を無効化

          ヘルプ:
            vs help                        - このヘルプを表示
            vs --version                   - バージョン情報を表示
        HELP

        def included(base)
          base.class_eval do
            desc 'help', HELP_DESC[:short]
            long_desc HELP_DESC[:long]
            # ================================================================
            # Command: help（ヘルプ表示）
            # ------------------------------------------------
            # 概要:
            #   Vivlio Starter の主要コマンド・オプションを一覧表示する。
            # 備考:
            #   - 固定のヘルプテキストを標準出力に表示。
            # ================================================================
            def help_banner
              print HELP_MESSAGE
            end
          end
        end
      end
    end
  end
end
