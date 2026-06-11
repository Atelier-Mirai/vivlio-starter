# frozen_string_literal: true

module VivlioStarter
  module CLI
    module Guards
      # 原稿ディレクトリ contents/ が存在するかを検証する。
      class ContentsDirCheck < BaseCheck
        def validate
          return [] if Dir.exist?(Common::CONTENTS_DIR)

          [error(
            "原稿ディレクトリが見つかりません: #{Common::CONTENTS_DIR}/",
            detail: '対処: プロジェクト直下で実行しているか確認してください'
          )]
        end
      end
    end
  end
end
