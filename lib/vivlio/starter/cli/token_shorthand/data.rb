# frozen_string_literal: true

module Vivlio
  module Starter
    module CLI
      module TokenShorthand
        module Data
          # catalog.yml の 1 行を表す構造体。Resolver が immutable に扱えるよう Data.define を利用。
          CatalogEntry = ::Data.define(
            :number,
            :slug,
            :kind,
            :basename,
            :path,
            :ext,
            :exists
          )

          # CLI 各コマンドで直接用いる章レコード。catalog の存在有無や特殊ファイルも同一フォーマットで渡す。
          Entry = ::Data.define(
            :number,
            :slug,
            :kind,
            :basename,
            :path,
            :ext,
            :exists,
            :catalog_entry,
            :special?
          ) do
            # 既存コードに合わせて `entry.exists?` シンタックスも許容する。
            def exists?
              exists
            end
          end
        end
      end
    end
  end
end
