# frozen_string_literal: true

module VivlioStarter
  module CLI
    module Guards
      # 任意の Check の :error 違反を :warn に格下げするデコレータ。
      # コマンド × Check 対応表の「○=推奨」（違反しても停止はせず警告のみ）を表現する。
      class RelaxedCheck < BaseCheck
        # @param check [BaseCheck] 格下げ対象の Check
        def initialize(check)
          @check = check
          super()
        end

        def validate
          @check.validate.map do |violation|
            next violation unless violation.error?

            violation.with(severity: :warn)
          end
        end
      end
    end
  end
end
