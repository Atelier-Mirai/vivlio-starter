# frozen_string_literal: true

module VivlioStarter
  module CLI
    module Guards
      # 画像ディレクトリ images/ が存在するかを検証する（resize / cover の前提）。
      class ImagesDirCheck < BaseCheck
        def validate
          return [] if Dir.exist?(Common::IMAGES_DIR)

          [error(
            "画像ディレクトリが見つかりません: #{Common::IMAGES_DIR}/",
            detail: '対処: プロジェクト直下で実行しているか確認してください'
          )]
        end
      end
    end
  end
end
