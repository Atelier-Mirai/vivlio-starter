# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/samovar/lint_command.rb
# ================================================================
# 責務:
#   Samovar CLI の lint コマンドを実装する。
#   textlint を使用した Markdown ファイルの文章校正を実行する。
#
# 機能:
#   - contents/ 以下の Markdown ファイルを textlint で検査
#   - 章番号指定・範囲指定による部分検査
#   - 英語エラーメッセージの日本語翻訳
#
# 依存:
#   - LintCommands: textlint 実行ロジック
# ================================================================

require_relative '../lint'
require_relative '../guards'
require_relative 'vs_command'

module VivlioStarter
  module CLI
    module SamovarCommands
      # lint コマンドの Samovar 実装
      class LintCommand < VsCommand
        self.description = '原稿の日本語・英単語の綴り・コードブロックの言語名を検査します'

        options do
          option '--fix', '自動修正可能なエラーを修正', default: false, key: :fix
          option '--register', 'スペルチェックの未知語をユーザー辞書へ一括登録', default: false, key: :register
          option '-h/--help', 'このコマンドの使い方を表示', key: :help
        end

        many :files, '対象ファイル（省略時は全章）'

        def call
          return print_help if options[:help]

          # 前提条件の検証（ProjectRoot ◎ / CatalogFile ◎ / CatalogEntries ○ / ContentsDir ◎）
          guard_failure = Guards.precheck(
            Guards::ProjectRootCheck.new,
            Guards::CatalogFileCheck.new,
            Guards::RelaxedCheck.new(Guards::CatalogEntriesCheck.new),
            Guards::ContentsDirCheck.new
          )
          return guard_failure if guard_failure

          # 巻を選ばなければ、全巻の原稿を見る（multivolume-spec.md §6.1）
          targets = Build::Volumes.select_from_arguments!(files || [])
          LintCommands.execute_lint(targets, build_options)
        rescue SystemExit => e
          e.status
        rescue StandardError => e
          Common.log_error("lint 実行中にエラー: #{e.message}")
          Common.log_error(e.backtrace.join("\n")) if ENV['VS_DEBUG']
          1
        ensure
          Build::Volumes.select!(nil)
        end

        private

        def print_help
          puts <<~HELP
            vs lint - 原稿の日本語・英単語の綴り・コードブロックの言語名を検査します

            Usage: vs lint [OPTIONS] [FILES...]

            引数:
              FILES   対象の章（省略時は catalog.yml の全章）
                      章番号のみ: vs lint 91 93
                      範囲指定:   vs lint 11-21
                      分冊の巻:   vs lint upper

            オプション:
              --fix              自動修正可能なエラーを修正します
              --register         スペルチェックの未知語を config/spellcheck_user_dictionary.yml へ一括登録します
                                 （スペルチェック専用。textlint は実行しません）

            例:
              vs lint                 # catalog.yml の全章を検査
              vs lint 11-install      # 11-install.md のみ検査
              vs lint 91 93           # 91-*.md と 93-*.md を検査
              vs lint 11-21           # 11-*.md から 21-*.md の範囲を検査
              vs lint --fix           # 自動修正を適用
              vs lint --register      # 未知語を辞書へ登録（スペルチェック専用）
          HELP
          0
        end

        def build_options
          {
            fix: options[:fix],
            register: options[:register]
          }
        end
      end
    end
  end
end
