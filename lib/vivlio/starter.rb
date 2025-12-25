# frozen_string_literal: true

# ================================================================
# Section: 必要ファイルのロードとフォールバック方針
# ------------------------------------------------
# 目的:
#   - CLI 実装(Samovar)・バージョン・組み込み new コマンドをロードする。
# 方針:
#   - version は必須: バージョン表示や gem 情報のため常に必要。
#   - cli は実質必須: 通常のコマンド実行/ヘルプ表示のため。ただし互換性を重視
#     し、ここでは LoadError を握りつぶして後段ロジックに委ねる。
#   - commands/new は任意: 「組み込み new」を提供するための最小依存の雛形作成。
#     存在しない場合はスキップし、`defined?(Commands::New)` で安全に分岐する。
# 運用メモ:
#   - 問題の早期検知を優先する場合は rescue を外す/警告を強化するなどの
#     fail-fast 化が可能（本ファイルでは互換性優先のため現状維持）。
# ================================================================

# Samovar ベースの CLI
require 'vivlio/starter/cli/samovar'

# バージョンは必須。`Vivlio::Starter::VERSION` を CLI 表示や gem 情報で使用。
require 'vivlio/starter/version'

begin
  # 組み込み new（最小ブートストラップ）。存在すれば `vs new` を実行。
  require 'vivlio/starter/commands/new'
rescue LoadError
  # 古いインストール等で未同梱でも動作継続。`defined?(Commands::New)` で分岐済み。
end

module Vivlio
  # ================================================================
  # Module: Vivlio
  # ------------------------------------------------
  # 役割:
  #   上位名前空間。vivlio 関連ライブラリのトップレベルを提供。
  # 備考:
  #   - 本 gem では `Vivlio::Starter` をぶら下げる。
  # ================================================================
  module Starter
    # ================================================================
    # Module: Vivlio::Starter
    # ------------------------------------------------
    # 役割:
    #   vivlio-starter のコア名前空間。バージョンや CLI を束ねる。
    # 構成:
    #   - VERSION 定数（`vivlio/starter/version`）
    #   - CLI サブモジュール（エントリポイント）
    # ================================================================
    module CLI
      # ================================================================
      # Module: Vivlio::Starter::CLI
      # ------------------------------------------------
      # 役割:
      #   コマンドライン実行の中核。`start(argv)` を提供し Samovar へ委譲。
      # エクスポート:
      #   - module_function により `Vivlio::Starter::CLI.start` として利用。
      # 依存:
      #   - `vivlio/starter/cli/samovar`（Samovar 実装）
      #   - `vivlio/starter/commands/new`（組み込み new コマンド）
      # ================================================================

      module_function

      # ================================================================
      # Method: start(argv)
      # ------------------------------------------------
      # 役割:
      #   vivlio-starter のエントリポイント。Samovar CLI に処理を委譲する。
      # 振る舞い:
      #   - VS_CLI 環境変数で CLI 実行をマーク
      #   - --help/--version を先行処理
      #   - new は Commands::New に直行
      #   - -v/--verbose を抽出し ENV['VERBOSE']='1'
      #   - `vs <cmd> --help` は日本語ヘルプに対応
      # 返り値: 成功時 0、エラー時 非0
      # ================================================================
      def start(argv)
        args = Array(argv).dup

        result = Vivlio::Starter::CLI::SamovarCommands::RootCommand.call(args)
        result.is_a?(Integer) ? result : 0
      rescue SystemExit => e
        e.status
      rescue Exception => e
        warn "❌ #{e.class}: #{e.message}"
        warn e.backtrace.join("\n") if ENV['VS_DEBUG']
        1
      end
    end
  end
end
