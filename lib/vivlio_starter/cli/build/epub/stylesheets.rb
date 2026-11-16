# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/build/epub/stylesheets.rb
# ================================================================
# 責務:
#   平らな CSS を書き、HTML の link を付け替える（css_form）
# ================================================================

require_relative 'workspace'
require_relative '../../css/bundle'

module VivlioStarter
  module CLI
    module Build
      # 平らな CSS を書き、HTML の link を付け替える（css_form）
      module Epub::Stylesheets
        module_function

        # 平らにした CSS の置き場（消費者 dir からの相対）。ページの種類ごとに 1 枚
        # （css-layer-restructure-spec.md §4.2）。
        EPUB_STYLES_DIR = 'styles'

        # ステージした HTML の、入口の CSS への link（asset_prefix を剥がした後の作業ディレクトリ相対）
        ENTRY_HREF_PATTERN = %r{href="#{Regexp.escape(Common::CACHE_DIR)}/entry-([a-z-]+)\.css"}

        # 章の frontmatter の `stylesheet:` が足した CSS への link（FrontmatterGenerator が
        # 入口の後に層の外で足す）。中身は Css::Bundle.write_epub_extra! が styles/ の下へ写す
        EXTRA_STYLESHEET_HREF_PATTERN = %r{href="(#{Regexp.escape(Common::STYLESHEETS_DIR)}/[^"]+\.css)"}

        # 入口の CSS を平らにして EPUB へ同梱する（css-layer-restructure-spec.md §4.2）。
        #
        # KFX は `@layer` の囲みを中身ごと捨てるので、層の付いた入口をそのまま渡せない。
        # ページの種類ごとに、入口を平らにして出力先のフィルタを掛けた 1 枚（Css::Bundle）を
        # 消費者 dir の styles/ へ書き、章 HTML の link をその 1 枚へ付け替える。
        # 入口と book-settings.css の置き場 .cache/vs/ はパッケージルートの外なので、
        # 付け替えないと RSC-007（参照切れ）になる。
        # 章の frontmatter が足した CSS（stylesheets/ の中・層の外）も、同じフィルタを掛けて
        # styles/ の下へ写す。パッケージには stylesheets/ の CSS を運ばないためである。
        #
        # @param html_files [Array<String>] 章 HTML パスの配列
        # @param base_dir [String] 消費者 dir（平らな CSS の置き場）
        # @param flavor [Symbol] :epub / :kindle（出力先のフィルタを選ぶ）
        # @return [Hash{String => Css::Bundle::Sheet}] 付け替えた link の href → 書いた CSS
        #   （HTML の書き換えの後の判定 Finalizers::AuthorPriority に渡す）
        def bundle_flat!(html_files, base_dir, flavor:)
          htmls = html_files.to_h { [it, File.read(it, encoding: 'utf-8')] }
          html_by_kind = Hash.new { |hash, key| hash[key] = [] }
          htmls.each { |path, html| html.scan(ENTRY_HREF_PATTERN).flatten.uniq.each { html_by_kind[it] << path } }

          styles_dir = File.join(base_dir, EPUB_STYLES_DIR)
          written = Css::Bundle.write_epub!(html_by_kind, target: flavor, styles_dir:, embed_fonts: Epub::Workspace.embed_fonts?)
          extras = {}
          htmls.each do |path, html|
            updated = html.gsub(ENTRY_HREF_PATTERN) { %(href="#{EPUB_STYLES_DIR}/#{Regexp.last_match(1)}.css") }
            updated = updated.gsub(EXTRA_STYLESHEET_HREF_PATTERN) do
              source = Regexp.last_match(1)
              extras[source] ||= Css::Bundle.write_epub_extra!(source, target: flavor, styles_dir:,
                                                                      embed_fonts: Epub::Workspace.embed_fonts?)
              %(href="#{EPUB_STYLES_DIR}/#{source}")
            end
            File.write(path, updated, encoding: 'utf-8') unless updated == html
          end
          Common.log_success("[EPUB] 平らにした CSS を同梱しました（#{[*html_by_kind.keys.sort, *extras.keys].join(', ')}）")
          written.to_h { |kind, sheet| ["#{EPUB_STYLES_DIR}/#{kind}.css", sheet] }
                 .merge(extras.to_h { |source, sheet| ["#{EPUB_STYLES_DIR}/#{source}", sheet] })
        end

        # 付け替えた後の、平らな CSS への link（Epub::Stylesheets.bundle_flat! が書く。章が足した CSS を含む）
        STYLES_HREF_PATTERN = %r{href="(#{EPUB_STYLES_DIR}/[^"]+\.css)"}

        # HTML ごとの、読む平らな CSS の href（link の順）
        def linked_styles(html_files)
          html_files.to_h { [it, File.read(it, encoding: 'utf-8').scan(STYLES_HREF_PATTERN).flatten.uniq] }
        end
      end
    end
  end
end
