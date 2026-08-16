# frozen_string_literal: true

module VivlioStarter
  module CLI
    module Guards
      # VFM（Vivliostyle Flavored Markdown）の CLI が利用可能かを検証する。
      #
      # なぜ node とは別に見るのか（2026-08-16 の実測）:
      #   `vfm` は Vivliostyle CLI に同梱されず、`@vivliostyle/vfm` を別途入れないと
      #   PATH に現れない。node も vivliostyle も揃った環境で `vfm` だけ無い状態が普通に成立する。
      #
      # なぜ 🔴 で止めるのか:
      #   変換は `vfm foo.md > foo.html` とリダイレクトで行うため、コマンドが無いと
      #   **0 バイトの HTML が作られる**。後続のステップはそれを正常な変換結果として読み、
      #   本文が空のまま PDF まで組み上がる。著者に届くのは「白い本」で、原因が原稿にあると
      #   誤解させる。変換の入口で止めるほうが静かに壊れた本より安い。
      class VfmCheck < BaseCheck
        # @param runner [#system] テストで外部コマンド実行を差し替えるための DI
        def initialize(runner: Kernel)
          @runner = runner
          super()
        end

        def validate
          return [] if @runner.system(Common::VFM_COMMAND, '--version', out: File::NULL, err: File::NULL)

          [error(
            'VFM が見つかりません（Markdown を HTML へ変換できません）',
            detail: [
              '対処: npm install -g @vivliostyle/vfm',
              '　　　（vs doctor --fix でもまとめて導入できます）',
              '注意: npm の `vfm` は同名の別パッケージです。@vivliostyle/vfm を指定してください'
            ]
          )]
        end
      end
    end
  end
end
