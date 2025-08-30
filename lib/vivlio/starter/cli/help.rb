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
        extend self
        def included(base)
          base.class_eval do
            desc 'help', 'Vivlio Starter のヘルプを表示します'
            long_desc '主要コマンドとオプションのチートシートを表示します。'
            # ================================================================
            # Command: help（ヘルプ表示）
            # ------------------------------------------------
            # 概要:
            #   Vivlio Starter の主要コマンド・オプションを一覧表示する。
            # 備考:
            #   - 固定のヘルプテキストを標準出力に表示。挙動の変更なし。
            # ================================================================
            def help_banner
              print <<~HELP
                📚 Vivlio Starter - Build System

                主なコマンド:
                  vs build                       - 全ファイルをビルド
                  vs build <chapter_name>        - 指定した章のみをビルド
                  vs open                        - 生成されたPDFを開く(macOS専用)
                  vs pdf:compress                - 生成されたPDFを圧縮

                  # ビルドオプション:
                  --high                # 高画質でビルド（画像の品質優先）
                  --medium              # 標準画質でビルド（デフォルト）
                  --low                 # 低画質でビルド（ファイルサイズ優先）
                  --no-resize           # 画像のリサイズ/最適化をスキップ
                  --no-compress         # PDFの圧縮をスキップ
                  --no-clean            # 中間ファイルのクリーンアップをスキップ
                  -v                    # 詳細な出力を表示

                章の管理:
                  vs create <chapter_name>       - 新しい章を作成
                  vs delete <chapter_name>       - 指定した章を削除
                  vs rename <old> <new>          - 章名・付録名/番号を変更
                                              （例: 11-install → 12-setup, 21 → 32）
                  vs renumber                    - 章番号・付録番号を整列
                  vs clean                       - ビルド生成物をクリーンアップ

                ヘルプ:
                  vs help                        - このヘルプを表示
                  vs --version                   - バージョン情報を表示
              HELP
            end
          end
        end
      end
    end
  end
end
