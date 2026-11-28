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

          # macOS は濁点付きファイル名を NFD で保持することがあり、catalog の
          # NFC 表記と文字列比較で不一致になる（NF-02 で検出）。両辺を NFC へ
          # 揃えて正規化差だけのファイルを孤立扱いしない。
          # 分冊の本では、巻を選んでいても全巻の目次と比べる（改善案 #188）。選んだ巻の目次と比べると、
          # ほかの巻に載せた原稿（合本なら 2 巻目以降の前書きも）を未登録として挙げていた
          catalog_basenames = Build::Volumes.with_selection(:all) do
            TokenResolver::Resolver.new.resolve.map { it.basename.unicode_normalize(:nfc) }
          end
          orphans = contents_basenames.map { it.unicode_normalize(:nfc) } - catalog_basenames
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
