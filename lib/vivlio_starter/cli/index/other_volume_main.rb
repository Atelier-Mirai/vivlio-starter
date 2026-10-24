# frozen_string_literal: true

# ================================================================
# Module: OtherVolumeMain
# ----------------------------------------------------------------
# 責務:
#   分冊の本で、主要参照（辞書の main:）が組んでいない巻の章にある語について、
#   索引に添える案内の文字（「上巻 第7章」）を作る。
#
# なぜ要るか:
#   副次参照の間引きは、主要参照の無い語を間引かない。分冊では main: を書いた語でも
#   組む巻に主要参照が無いことがあり、出現が全部並んでいた（book_ai_web_starter の下巻で
#   「HTML」が約 60 項目）。別の巻の章を案内すれば、主要参照の代わりになる。
#
# 仕様: index-other-volume-main-spec.md R1
# ================================================================

require 'set'
require_relative '../common'
require_relative '../token_resolver'
require_relative '../build/volumes'
require_relative '../pre_process/cross_reference_processor'
require_relative 'chapter_source'
require_relative 'main_reference'

module VivlioStarter
  module CLI
    module IndexCommands
      module OtherVolumeMain
        module_function

        # 巻を選んで組むときの、語ごとの案内。合本と分冊でない本では空（R3）
        # @param terms [Array<Hash>] 辞書エントリ（'term' と任意の 'main'）
        # @return [Hash{String => String}] 用語 => 「上巻 第7章」（複数の巻なら「・」でつなぐ）
        def guides(terms)
          return {} unless Build::Volumes.current

          local = TokenResolver::Resolver.new.resolve.select(&:in_catalog?).to_set(&:basename)
          chapters = catalog_order
          terms.each_with_object({}) do |term, map|
            places = Array(term['main']).map { MainReference.parse(it).chapter }.uniq
                                        .reject { local.include?(it) }
                                        .sort_by { chapters.index(it) || chapters.size }
                                        .filter_map { place_of(it) }
            map[term['term']] = places.join('・') unless places.empty?
          end
        end

        # 全巻を目次の順に並べた原稿の名前
        def catalog_order
          Build::Volumes.with_selection(:all) { TokenResolver::Resolver.new.resolve.select(&:in_catalog?).map(&:basename) }
        end

        # 別の巻の章の呼び名。その巻を組んだときの章扉と同じに数える。どの巻にも無い章は nil
        def place_of(chapter)
          volume = Build::Volumes.containing(chapter) or return nil

          number = Build::Volumes.with_selection(volume) do
            PreProcessCommands::CrossReferenceProcessor.chapter_number_text_for(chapter)
          end
          number ? "#{volume.name} #{number}" : "#{volume.name}「#{chapter_title(chapter)}」"
        end

        # 章番号を振らない章（前書きなど）は、章題で案内する
        def chapter_title(chapter)
          path = ChapterSource.path(chapter)
          heading = path && File.foreach(path, encoding: 'utf-8').find { it.start_with?('# ') }
          heading ? PreProcessCommands::CrossReferenceProcessor.plain_chapter_title(heading.delete_prefix('# ')) : chapter
        end
      end
    end
  end
end
