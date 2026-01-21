# frozen_string_literal: true

module Vivlio
  module Starter
    module CLI
      module TokenShorthand
        module Errors
          # TokenShorthand 全体で共有する基底エラー。CLI 側で一括 rescue しやすくするために用意。
          Error = Class.new(StandardError)

          # catalog.yml で見つからない章/slug を指摘するエラー。
          UnknownChapterToken = Class.new(Error)
          # allow_new 時でも slug 省略が許可されないケースに対するエラー。
          MissingChapterSlug = Class.new(Error)
          # slug のみ指定が許可されない、または slug 重複で番号が必要なケース向けエラー。
          MissingChapterNumber = Class.new(Error)
          # 許可されていない特殊ファイルを CLI が指定した際のエラー。
          UnsupportedSpecialFile = Class.new(Error)
        end
      end
    end
  end
end
