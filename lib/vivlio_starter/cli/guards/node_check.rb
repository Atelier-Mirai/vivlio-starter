# frozen_string_literal: true

module VivlioStarter
  module CLI
    module Guards
      # Node.js が利用可能かを検証する（Vivliostyle CLI / VFM の実行に必須）。
      # 詳細な環境診断・自動セットアップは vs doctor の責務のため、ここでは存在確認のみ。
      class NodeCheck < BaseCheck
        # @param runner [#system] テストで外部コマンド実行を差し替えるための DI
        def initialize(runner: Kernel)
          @runner = runner
          super()
        end

        def validate
          return [] if @runner.system('node', '--version', out: File::NULL, err: File::NULL)

          [error(
            'Node.js が見つかりません（PDF 生成に必須です）',
            detail: '対処: vs doctor --fix で必要ツールをセットアップできます'
          )]
        end
      end
    end
  end
end
