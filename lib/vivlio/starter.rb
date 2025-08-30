# frozen_string_literal: true

# ================================================================
# Section: 必要ファイルのロードとフォールバック方針
# ------------------------------------------------
# 目的:
#   - CLI 実装(Thor)・バージョン・組み込み new コマンドをロードする。
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

begin
  # Thor ベースの CLI 実装。正常に読めれば `Vivlio::Starter::ThorCLI` が利用可能。
  require 'vivlio/starter/cli'
rescue LoadError
  # 互換性優先: ここでは例外を握りつぶし、後で `defined?(...)` により安全に判定。
  # 例: 極端な最小環境でもプロセス起動自体は継続させる。
end

# バージョンは必須。`Vivlio::Starter::VERSION` を CLI 表示や gem 情報で使用。
require 'vivlio/starter/version'

begin
  # 組み込み new（最小ブートストラップ）。存在すれば `vs new` を Thor に依存せず実行。
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
      #   コマンドライン実行の中核。`start(argv)` を提供し Thor へ委譲。
      # エクスポート:
      #   - module_function により `Vivlio::Starter::CLI.start` として利用。
      # 依存:
      #   - `vivlio/starter/cli`（Thor 実装）
      #   - `vivlio/starter/commands/new`（組み込み new コマンド）
      # ================================================================
      module_function

      # ================================================================
      # Method: start(argv)
      # ------------------------------------------------
      # 役割:
      #   vivlio-starter のエントリポイント。組み込み(--help/--version/new)を処理し、
      #   それ以外は Thor CLI に委譲する。
      # 振る舞い:
      #   - VS_CLI 環境変数で CLI 実行をマーク
      #   - --help/--version を先行処理
      #   - new は Commands::New に直行
      #   - -v/--verbose を抽出し ENV['VERBOSE']='1'
      #   - `vs <cmd> --help` は日本語ヘルプ(jp_task_help)に対応
      #   - オプションを前方に正規化して Thor に渡す
      # 返り値: 成功時 0、エラー時 非0
      # ================================================================
      def start(argv)
        # Rakefileのガードが実行を許可するように、このプロセスをCLI駆動としてマーク
        ENV['VS_CLI'] ||= '1'

        # 組み込み: helpとversion
        if argv && (argv.first == '--help' || argv.first == '-h' || argv.first == 'help')
          # Thor CLI のヘルプを表示
          Vivlio::Starter::ThorCLI.start(['help'])
          return 0
        end

        if argv && (argv.first == '--version' || argv.first == '-V' || argv.first == 'version')
          puts "vivlio-starter #{Vivlio::Starter::VERSION}"
          return 0
        end

        # プロジェクトのRakefileが存在する場合でも動作すべき組み込みコマンドを傍受
        if argv && argv.first == 'new'
          argv.shift # remove 'new'
          name = argv.shift
          return Commands::New.run(name) if defined?(Commands::New)
        end

        # グローバルフラグを抽出
        verbose = false
        argv = argv.reject do |a|
          case a
          when '-v', '--verbose'
            verbose = true
            true
          else
            false
          end
        end
        ENV['VERBOSE'] = '1' if verbose

        # Thor へ委譲（Rake フォールバックは撤去）
        cmd = argv.shift
        if cmd.nil? || %w[help -h --help].include?(cmd)
          Vivlio::Starter::ThorCLI.start(['help'])
          return 0
        end

        begin
          if defined?(Vivlio::Starter::ThorCLI)
            # `vs <cmd> --help` を日本語ヘルプ対応で処理
            if argv.any? { |a| a == '--help' || a == '-h' || a == 'help' }
              if Vivlio::Starter::ThorCLI.respond_to?(:jp_task_help)
                Vivlio::Starter::ThorCLI.jp_task_help(cmd)
              else
                Vivlio::Starter::ThorCLI.start(['help', cmd])
              end
              return 0
            end
            # オプションを前方へ正規化して Thor に渡す
            opts, args = argv.partition { |a| a.start_with?('--') || (a.start_with?('-') && a != '-') }
            normalized = [cmd, *opts, *args]
            Vivlio::Starter::ThorCLI.start(normalized)
            return 0
          end
        rescue SystemExit => e
          return e.status
        rescue Exception => e
          warn "❌ #{e.class}: #{e.message}"
          warn e.backtrace.join("\n") if ENV['VS_DEBUG']
          return 1
        end
        1
      end
    end
  end
end
