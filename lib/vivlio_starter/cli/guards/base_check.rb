# frozen_string_literal: true

module VivlioStarter
  module CLI
    module Guards
      # 単一の前提条件違反。
      # detail は Common.log_error / log_warn の detail: に渡され、
      # 2行目以降としてインデント表示される（docs/specs/logging_spec.md 準拠）。
      # @!attribute severity [r] :error（停止）または :warn（警告のみ）
      Violation = Data.define(:severity, :message, :detail) do
        def error? = severity == :error
        def warn?  = severity == :warn
      end

      # すべての Check が満たすべき契約。
      # validate は違反の配列を返し、空配列なら合格とする。
      # 検証は軽量・高速・単一責務に保ち、丁寧な診断は vs preflight / vs doctor に委ねる。
      class BaseCheck
        # @return [Array<Violation>] 違反の配列（空配列なら合格）
        def validate = raise NotImplementedError

        private

        # :error 違反を生成する（detail 省略可）
        def error(message, detail: nil) = Violation.new(severity: :error, message:, detail:)

        # :warn 違反を生成する（detail 省略可）
        def warning(message, detail: nil) = Violation.new(severity: :warn, message:, detail:)
      end
    end
  end
end
