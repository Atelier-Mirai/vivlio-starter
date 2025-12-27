# frozen_string_literal: true

require_relative '../common'

module Vivlio
  module Starter
    module CLI
      module PostProcessCommands
        # ================================================================
        # Module: BodyClassInjector
        # ----------------------------------------------------------------
        # 【役割】
        # - HTMLファイルの <body> タグにファイルタイプクラスを付与
        #
        # 【処理内容】
        # - ファイル名から chapter/preface/appendix などを判定
        # - <body> を <body class="file_type"> に置換
        # ================================================================
        module BodyClassInjector
          module_function

          # HTMLファイルの <body> タグにファイルタイプクラスを付与
          # @param html_file [String] HTMLファイルのパス
          # @return [Boolean] 変更があったかどうか
          def inject_body_class(html_file)
            content = File.read(html_file, encoding: 'utf-8')
            file_type = Common.get_file_type(html_file)

            # 単純置換で <body> にクラスを付与
            # - 既存 class 属性が無いテンプレ構成を前提に、文字列置換で高速に処理
            updated = content.gsub('<body>', "<body class=\"#{file_type}\">")

            return if updated == content

            File.write(html_file, updated, encoding: 'utf-8')
            Common.log_info("#{html_file}: <body>→class追加(#{file_type})")
          end
        end
      end
    end
  end
end
