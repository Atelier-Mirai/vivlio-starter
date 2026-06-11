# frozen_string_literal: true

module VivlioStarter
  module CLI
    module Guards
      # Vivliostyle CLI の設定ファイル vivliostyle.config.js が存在するかを検証する。
      # ビルド後半（PDF 生成）で初めて参照されるため、Guard で早期に弾く価値が高い。
      class VivliostyleConfigCheck < BaseCheck
        def validate
          return [] if File.file?(Common::VIVLIOSTYLE_CONFIG_FILE)

          [error(
            "Vivliostyle 設定ファイルが見つかりません: #{Common::VIVLIOSTYLE_CONFIG_FILE}",
            detail: '対処: vs new で作成したプロジェクトには標準で含まれます。誤って削除した場合は Git 等から復元してください'
          )]
        end
      end
    end
  end
end
