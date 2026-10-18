# frozen_string_literal: true

require_relative 'targets'

module VivlioStarter
  module CLI
    module Build
      # ================================================================
      # Build::KindlePreviewerNotice — Kindle を選んだ本の、Kindle Previewer の入れ方の案内
      # ================================================================
      # output.targets に kindle があるのに Kindle Previewer が無いとき、vs build・vs preflight の
      # 終わりに、vs doctor --fix で入れられることを 💡 で知らせる（改善案.md #87）。
      #
      # Kindle Previewer が無くても Kindle 向けのビルドは通り（KPF への変換だけを飛ばす）、
      # 原稿の誤りでもないので止めない。vs new や vs doctor では言わない——Kindle を選んで
      # いない著者に Kindle の話をしても、体験が悪くなるだけだった（ユーザーの指摘）。
      # ================================================================
      module KindlePreviewerNotice
        module_function

        COMMAND = 'kindlepreviewer'

        # @param targets [Build::Targets] 出力ターゲット（既定は book.yml から解決）
        # @param available [#call] Kindle Previewer のコマンドがあるか（テストで差し替える）
        def report(targets: Targets.resolve, available: -> { Common.external_command_available?(COMMAND) })
          return unless targets.kindle
          return if available.call

          # 「Kindle 向けのビルドが止まった」と読まれないよう、KPF への変換だけを飛ばしたことを言う
          Common.log_always('💡 Kindle 用の KPF は、Kindle Previewer で変換して作ります（今回は変換を飛ばしました）')
          Common.log_always("#{Common::DETAIL_INDENT}vs doctor --fix で入れられます（管理者のパスワードを尋ねられます）")
        end
      end
    end
  end
end
