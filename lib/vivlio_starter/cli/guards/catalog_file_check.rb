# frozen_string_literal: true

module VivlioStarter
  module CLI
    module Guards
      # config/catalog.yml が存在するかを検証する。
      class CatalogFileCheck < BaseCheck
        def validate
          return [] if File.file?(Build::CatalogLoader::CATALOG_FILE)

          [error(
            "章構成ファイルが見つかりません: #{Build::CatalogLoader::CATALOG_FILE}",
            detail: '対処: vs new で作成したプロジェクトには標準で含まれます。誤って削除した場合は Git 等から復元してください'
          )]
        end
      end
    end
  end
end
