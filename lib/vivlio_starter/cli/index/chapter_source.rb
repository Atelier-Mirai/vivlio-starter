# frozen_string_literal: true

require_relative '../common'

module VivlioStarter
  module CLI
    module IndexCommands
      # 索引の見積もり・分布・主要参照の推定が読む、章の Markdown の場所。
      module ChapterSource
        module_function

        # 章名（`21-basic`）か既存のパスを受け、読むファイルを返す。著者の原稿（contents/）を
        # 優先し、無ければ前処理済みの中間 .md（ワークスペースの html/）。どちらも無ければ nil。
        # @param chapter [String]
        # @return [String, nil]
        def path(chapter)
          return chapter if File.exist?(chapter.to_s)

          [File.join(Common::CONTENTS_DIR, "#{chapter}.md"),
           File.join(Common::BUILD_HTML_DIR, "#{chapter}.md")].find { File.exist?(it) }
        end
      end
    end
  end
end
