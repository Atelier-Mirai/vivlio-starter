# frozen_string_literal: true

module VivlioStarter
  module CLI
    module Guards
      # Vivlio Starter プロジェクト直下で実行されているかを検証する。
      # プロジェクトの目印は config/book.yml の存在とする。
      class ProjectRootCheck < BaseCheck
        def validate
          return [] if File.file?(Common::CONFIG_FILE)

          [error(
            'Vivlio Starter プロジェクトの直下で実行してください（config/book.yml が見つかりません）',
            detail: '新規プロジェクトは vs new <プロジェクト名> で作成できます'
          )]
        end
      end
    end
  end
end
