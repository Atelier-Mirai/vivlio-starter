# frozen_string_literal: true

module VivlioStarter
  module CLI
    module Guards
      # config/catalog.yml に記載された章ファイルがすべて contents/ に実在するかを検証する。
      #
      # カタログ解析はセクション・部タイトル・ショートハンド対応済みの
      # TokenResolver::Resolver に委譲し、ロジックの二重化を避ける。
      # catalog.yml 自体の不在は CatalogFileCheck の責務のため、ここでは合格扱い。
      class CatalogEntriesCheck < BaseCheck
        def validate
          return [] unless File.file?(Build::CatalogLoader::CATALOG_FILE)

          missing = TokenResolver::Resolver.new.resolve.reject(&:exists?)
          return [] if missing.empty?

          [error(
            'config/catalog.yml に記載されている章ファイルが contents/ に見つかりません',
            detail: missing.map { "- contents/#{it.basename}.md" } +
                    ['対処: catalog.yml の該当行を削除するか原稿を作成してください（vs delete <章番号> で一括削除可）']
          )]
        end
      end
    end
  end
end
