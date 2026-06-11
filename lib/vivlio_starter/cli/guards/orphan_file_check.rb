# frozen_string_literal: true

module VivlioStarter
  module CLI
    module Guards
      # contents/ にあるが config/catalog.yml に未登録の原稿（孤立ファイル）を検出する。
      #
      # catalog.yml で章をコメントアウトして除外するのは正規のワークフローのため、
      # 警告のみ（preflight 専用）とし、1件ずつではなく1つの警告にまとめて列挙する。
      class OrphanFileCheck < BaseCheck
        def validate
          return [] unless File.file?(Build::CatalogLoader::CATALOG_FILE)

          catalog_basenames = TokenResolver::Resolver.new.resolve.map(&:basename)
          orphans = contents_basenames - catalog_basenames
          return [] if orphans.empty?

          [warning(
            "catalog.yml に未登録の原稿が #{orphans.size} 件あります（ビルド対象外）",
            detail: orphans.map { "- contents/#{it}.md" }
          )]
        end

        private

        # アンダースコア始まり（_titlepage 等のシステムページ）は対象外
        def contents_basenames
          Dir.glob(File.join(Common::CONTENTS_DIR, '*.md'))
             .map { File.basename(it, '.md') }
             .reject { it.start_with?('_') }
             .sort
        end
      end
    end
  end
end
