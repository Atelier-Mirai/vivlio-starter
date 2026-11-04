# frozen_string_literal: true

module VivlioStarter
  module CLI
    module Guards
      # 原稿の中身を点検する検査（コードフェンス・改ページ・コンテナ）が、調べる原稿を受け取るための共通部分。
      #
      # なぜ範囲を受け取るのか:
      #   これらの検査は build と preflight の両方で走る（Guards.manuscript_checks）。章を指定した
      #   `vs build 12` で全章を調べると、書きかけの 45 章の閉じ忘れで 12 章のビルドまで止まる。
      #   章を指定したときは、組む章だけを調べる。指定しなければ contents/ の全原稿を調べる。
      module ManuscriptScope
        # @param paths [Array<String>, nil] 調べる原稿のパス。nil なら contents/ の全原稿
        def initialize(paths: nil)
          @paths = paths
          super()
        end

        private

        def markdown_files = @paths || Dir.glob(File.join(Common::CONTENTS_DIR, '*.md')).sort
      end
    end
  end
end
