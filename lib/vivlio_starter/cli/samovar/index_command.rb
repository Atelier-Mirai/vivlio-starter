# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/samovar/index_command.rb
# ================================================================
# 責務:
#   Samovar CLI の index コマンドを実装する。
#   索引機能のサブコマンドを提供する。
#   仕様書 indexing_implementation_spec3.md に準拠
#
# 公開コマンド:
#   - index:auto: 全自動索引候補抽出 → _index_review.md 生成
#   - index:apply: レビュー結果を適用
#
# 内部コマンド（利用者には非公開）:
#   - index:build: 索引ページを生成（vs build から呼ばれる）
#
# 依存:
#   - UnifiedIndexManager: 統合マネージャー
#   - IndexCommands: 既存の索引処理
# ================================================================

require_relative '../index'
require_relative '../index/unified_index_manager'
require_relative '../index/index_library'
require_relative '../guards'

module VivlioStarter
  module CLI
    module SamovarCommands
      # index コマンドの Samovar 実装
      class IndexCommand < Samovar::Command
        self.description = '索引機能のサブコマンドを表示します'

        options do
          option '-h/--help', 'このコマンドの使い方を表示', key: :help
        end

        def call
          puts <<~HELP
            索引機能のコマンド:

              vs index:auto [章]  - 候補抽出・分類・_index_review.md 生成（章を指定可）
              vs index:apply      - レビュー結果を index_glossary_terms.yml に適用
              vs index:export     - 用語集[g]・棄却語 を index_library.yml に書き出す
              vs index:import     - index_library.yml から用語集[g]・棄却語 を取り込む

            ワークフロー:
              1. vs index:auto   → _index_review.md を生成
              2. _index_review.md を編集（[x]で承認、[r]で棄却）
              3. vs index:apply  → index_glossary_terms.yml を更新
              4. vs build        → 索引ページを含む PDF を生成

            章の指定（長い本で一部だけ見たいとき）:
              vs index:auto 21          # 21 章だけを対象に候補抽出
              vs index:auto 21-23,25    # 範囲・複数指定も可

            書籍間での持ち運び（用語集[g]・棄却語 を別の本へ引き継ぐ）:
              vs index:export           # book.yml の既定パスへ書き出す
              vs index:import           # book.yml の既定パスから取り込む

            詳細は各コマンドに --help を付けて確認してください。
          HELP
          0
        end
      end

      # index:auto コマンド - 全自動索引候補抽出
      class IndexAutoCommand < Samovar::Command
        self.description = '候補抽出・分類・_index_review.md 生成'

        options do
          option '-v/--verbose', '詳細出力', default: false, key: :verbose
          option '-h/--help', 'このコマンドの使い方を表示', key: :help
        end

        many :files, '対象ファイル（省略時は全章）'

        def call
          return print_usage if options[:help]

          # 前提条件の検証（ProjectRoot ◎ / CatalogFile ◎ / CatalogEntries ○ / ContentsDir ◎）
          guard_failure = Guards.precheck(
            Guards::ProjectRootCheck.new,
            Guards::CatalogFileCheck.new,
            Guards::RelaxedCheck.new(Guards::CatalogEntriesCheck.new),
            Guards::ContentsDirCheck.new
          )
          return guard_failure if guard_failure

          ENV['VERBOSE'] = '1' if options[:verbose]

          # auto_discovery 設定を確認（未設定 nil は true 扱い、false のみ無効化）
          unless Common::CONFIG.index.auto_discovery != false
            Common.log_info('index.auto_discovery: false のため、自動候補抽出は無効です')
            Common.log_info('手動マークアップ [用語|読み] のみが索引に反映されます')
            Common.log_info('自動抽出を有効にするには book.yml で auto_discovery: true を設定してください')
            return 0
          end

          chapters = IndexCommands.resolve_chapters(files || [])

          manager = UnifiedIndexManager.new
          manager.auto_process!(chapters)
          0
        rescue SystemExit => e
          raise e
        rescue StandardError => e
          Common.log_error("index:auto 実行中にエラー: #{e.message}")
          Common.log_error(e.backtrace.first(5).join("\n")) if ENV['VERBOSE']
          1
        end
      end

      # index:apply コマンド - レビュー結果を適用
      class IndexApplyCommand < Samovar::Command
        self.description = 'レビュー結果を index_glossary_terms.yml に適用'

        options do
          option '-v/--verbose', '詳細出力', default: false, key: :verbose
          option '-h/--help', 'このコマンドの使い方を表示', key: :help
        end

        def call
          return print_usage if options[:help]

          # 前提条件の検証（ProjectRoot ◎ / CatalogFile ◎ / ContentsDir ◎）
          guard_failure = Guards.precheck(
            Guards::ProjectRootCheck.new,
            Guards::CatalogFileCheck.new,
            Guards::ContentsDirCheck.new
          )
          return guard_failure if guard_failure

          ENV['VERBOSE'] = '1' if options[:verbose]

          manager = UnifiedIndexManager.new
          manager.apply_markdown_review!
          0
        rescue SystemExit => e
          raise e
        rescue StandardError => e
          Common.log_error("index:apply 実行中にエラー: #{e.message}")
          Common.log_error(e.backtrace.first(5).join("\n")) if ENV['VERBOSE']
          1
        end
      end

      # index:export コマンド - 用語集[g]・棄却語 を持ち運び用ファイルへ書き出す
      class IndexExportCommand < Samovar::Command
        self.description = '用語集[g]・棄却語 を index_library.yml に書き出す'

        options do
          option '-h/--help', 'このコマンドの使い方を表示', key: :help
        end

        many :args, '書き出し先パス（省略時は book.yml の既定）'

        def call
          return print_usage if options[:help]

          guard_failure = Guards.precheck(Guards::ProjectRootCheck.new)
          return guard_failure if guard_failure

          path = IndexCommands::IndexLibrary.resolve_path((args || []).first, :export)
          Common.log_info("書き出し先: #{path}")
          IndexCommands::IndexLibrary.new.export!(path)
          0
        rescue SystemExit => e
          raise e
        rescue StandardError => e
          Common.log_error("index:export 実行中にエラー: #{e.message}")
          1
        end
      end

      # index:import コマンド - 持ち運び用ファイルから用語集[g]・棄却語 を取り込む
      class IndexImportCommand < Samovar::Command
        self.description = 'index_library.yml から用語集[g]・棄却語 を取り込む'

        options do
          option '--prefer-import', '衝突時にライブラリ側で既存を上書きする', default: false, key: :prefer_import
          option '-h/--help', 'このコマンドの使い方を表示', key: :help
        end

        many :args, '取り込み元パス（省略時は book.yml の既定）'

        def call
          return print_usage if options[:help]

          guard_failure = Guards.precheck(Guards::ProjectRootCheck.new)
          return guard_failure if guard_failure

          path = IndexCommands::IndexLibrary.resolve_path((args || []).first, :import)
          Common.log_info("取り込み元: #{path}")
          result = IndexCommands::IndexLibrary.new.import!(path, prefer_import: options[:prefer_import])
          result ? 0 : 1
        rescue SystemExit => e
          raise e
        rescue StandardError => e
          Common.log_error("index:import 実行中にエラー: #{e.message}")
          1
        end
      end

      # index:build コマンド - 索引ページを生成（内部用）
      # 利用者には非公開だが、デバッグ用に残す
      class IndexBuildCommand < Samovar::Command
        self.description = '索引ページを生成（内部用）'

        options do
          option '-v/--verbose', '詳細出力', default: false, key: :verbose
          option '-h/--help', 'このコマンドの使い方を表示', key: :help
        end

        many :files, '対象ファイル（省略時は全章）'

        def call
          return print_usage if options[:help]

          ENV['VERBOSE'] = '1' if options[:verbose]
          chapters = IndexCommands.resolve_chapters(files || [])

          manager = UnifiedIndexManager.new
          manager.build_index!(chapters)
          0
        rescue SystemExit => e
          raise e
        rescue StandardError => e
          Common.log_error("index:build 実行中にエラー: #{e.message}")
          Common.log_error(e.backtrace.first(5).join("\n")) if ENV['VERBOSE']
          1
        end
      end
    end
  end
end
