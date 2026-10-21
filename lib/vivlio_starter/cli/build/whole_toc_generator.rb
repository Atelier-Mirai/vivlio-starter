# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/build/whole_toc_generator.rb
# ================================================================
# 責務:
#   分冊の本で、全巻の構成を章まで示す目次（全巻目次）のページを作る（multivolume-spec.md §9）。
#   巻の設定に whole_toc: true を書いた巻を組むときだけ作り、その巻の目次（_toc）の前に置く。
#
# 生成物:
#   - .cache/vs/_whole_toc.md: 全巻目次の Markdown ソース
#   - _whole_toc.html: VFM 変換後の HTML（中間 HTML の置き場）
#
# ページ番号は載せない。今の目次は組み上がった HTML から作り、ページ番号は Vivliostyle が組版のときに
# 数えるが、他の巻はその場で組まないのでわからない。今の巻の分だけ付けると見た目がそろわないので、
# 今の巻にも付けない（今の巻のページは、続く詳しい目次で引ける）。項目もリンクにしない。
# ================================================================

require 'cgi'
require 'fileutils'

module VivlioStarter
  module CLI
    module Build
      # 全巻目次の生成モジュール
      module WholeTocGenerator
        BASENAME = '_whole_toc'
        HEADING = '全巻目次'

        module_function

        # 全巻目次を載せるか（巻を選んで組み、その巻に whole_toc: true があるとき）
        def needed? = Volumes.current&.whole_toc? == true

        # 全巻目次のページを作る。載せない巻では何もしない
        # @return [String, nil] 作った basename
        def generate!
          return nil unless needed?

          Common.ensure_cache_dir!
          md_path = File.join(Common::CACHE_DIR, "#{BASENAME}.md")
          FileUtils.mkdir_p(File.dirname(md_path))
          File.write(md_path, markdown, encoding: 'utf-8')

          PreProcessCommands.execute_pre_process({}, [BASENAME])
          ConvertCommands.execute_convert({}, [BASENAME])
          PostProcessCommands.execute_post_process({}, [BASENAME])
          Common.log_success("[WholeToc] #{HEADING}を作りました")
          BASENAME
        end

        # 組み立てで、その巻の目次の前に差し込む HTML（無ければ空）
        # @return [Array<String>]
        def htmls(base_dir) = [File.join(base_dir, "#{BASENAME}.html")].select { needed? && File.exist?(it) }

        # 全巻目次の Markdown。巻の順に、巻の名前の下へ前書き・部・章・付録・後書きを並べる
        def markdown
          current = Volumes.current
          volumes = Volumes.list.map { volume_block(it, current: it.id == current&.id) }
          <<~MD
            ---
            title: #{HEADING}
            stylesheet: toc.css
            ---

            # #{HEADING}

            <div class="whole-toc">

            #{volumes.join("\n\n")}

            </div>
          MD
        end

        # 1 巻ぶんのブロック。今の巻は vs-current-volume で目立たせる（toc.css）
        def volume_block(volume, current:)
          items = Volumes.with_selection(volume) { volume_items(volume) }
          classes = ['whole-toc-volume', ('vs-current-volume' if current)].compact.join(' ')
          <<~HTML.chomp
            <section class="#{classes}">
            <p class="whole-toc-volume-name">#{CGI.escapeHTML(volume.name)}</p>
            <ul>
            #{items.join("\n")}
            </ul>
            </section>
          HTML
        end

        # 巻の目次の項目（<li>）。番号は、その巻を選んだ状態で章扉と同じ規則で数える（§5）
        def volume_items(volume)
          sections = volume.sections
          [
            *CatalogLoader.flatten_section(sections['PREFACE']).map { item('whole-toc-preface', it) },
            *chapter_items(sections['CHAPTERS']),
            *CatalogLoader.flatten_section(sections['APPENDICES']).map { item('whole-toc-appendix', it) },
            *CatalogLoader.flatten_section(sections['POSTFACE']).map { item('whole-toc-postface', it) }
          ].compact
        end

        # 本文の項目。部（Hash のキー）は部の題名の行を置いてから、その部の章を並べる
        def chapter_items(items)
          Array(items).flat_map do |entry|
            case entry
            in Hash
              entry.flat_map do |title, children|
                [%(<li class="whole-toc-part">#{CGI.escapeHTML(title.to_s)}</li>), *chapter_items(children)]
              end
            in String | Integer
              CatalogLoader.expand_item(entry).map { item('whole-toc-chapter', it) }
            else []
            end
          end
        end

        # 1 項目。章扉の番号の文字（「第3章」「付録 A」）と章題。原稿が無ければ載せない
        def item(css_class, basename)
          title = chapter_title(basename)
          return nil unless title

          number = PreProcessCommands::CrossReferenceProcessor.chapter_number_text_for(basename)
          label = number ? %(<span class="whole-toc-number">#{CGI.escapeHTML(number)}</span>) : ''
          %(<li class="#{css_class}">#{label}#{CGI.escapeHTML(title)}</li>)
        end

        # 原稿の最初の `# ` 見出し（@chapref と同じく記号とタグを外す）
        def chapter_title(basename)
          path = File.join(Common::CONTENTS_DIR, "#{basename}.md")
          return nil unless File.exist?(path)

          heading = File.foreach(path, encoding: 'utf-8').find { it.match?(/\A#\s+\S/) }
          heading && PreProcessCommands::CrossReferenceProcessor.plain_chapter_title(heading.sub(/\A#\s+/, ''))
        end
      end
    end
  end
end
