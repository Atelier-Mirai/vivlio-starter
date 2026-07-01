# frozen_string_literal: true

require_relative 'metrics/runner'

module VivlioStarter
  module CLI
    # ================================================================
    # Module: MetricsCommands
    # ----------------------------------------------------------------
    # `vs metrics` のエントリポイント。対象ファイルの解決から出力までの
    # 実処理は Metrics::Runner に委譲する（本モジュールは薄い入口）。
    # ================================================================
    module MetricsCommands
      module_function

      # metrics コマンドの処理を実行クラスに委譲する
      def execute_metrics(targets, options = {})
        Metrics::Runner.new(targets, options).call
      end

      # 後方互換: 旧 execute_text_metrics エントリポイントを維持
      def execute_text_metrics(targets, options = {})
        execute_metrics(targets, options)
      end
    end

    # 後方互換: 旧 TextMetricsCommands 定数を維持
    TextMetricsCommands = MetricsCommands
  end
end
