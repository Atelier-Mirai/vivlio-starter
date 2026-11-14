# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/css/entry_writer.rb
# ================================================================
# 責務:
#   ページの種類ごとの入口の CSS（`.cache/vs/entry-<種類>.css`）を生成する
#   （css-layer-restructure-spec.md §2.3）。
#
# なぜ入口を生成するか:
#   層は `@import url(...) layer(...)` でしか付けられない（`<link>` では層を指定できない）。
#   そこで HTML が読む CSS を入口の 1 枚にし、入口の中で全部を層に入れて読む。
#   置き場を book-settings.css と同じ `.cache/vs/` にするのは、`stylesheets/` への
#   相対パスがそろうためである。
#
# 層:
#   `reset → base → tokens → parts → pages → theme → utilities → settings → target`。
#   後の層が前の層に勝ち、層の外（書体の定義と custom.css）はどの層にも勝つ（§2.1）。
#   ファイルの配置は §3.1（段階 S2-2 で分けた。前書き・後書きをそろえるのは S2-4）。
# ================================================================

require 'fileutils'
require_relative '../common'

module VivlioStarter
  module CLI
    module Css
      # 入口の CSS の生成
      module EntryWriter
        # 層の順（css-layer-restructure-spec.md §2.1）
        LAYERS = %w[reset base tokens parts pages theme utilities settings target].freeze

        # `.cache/vs/` から `stylesheets/` への相対
        CACHE_TO_STYLESHEETS = '../../stylesheets/'

        # book.yml から生成する CSS（`.cache/vs/` に置かれる）
        BOOK_SETTINGS = 'book-settings.css'
        BOOK_FONTS = 'book-fonts.css'

        # どのページも読む土台（判型・余白の箱の骨格と、公開する変数の既定値）
        FOUNDATION = { 'base' => %w[base/reset.css base/elements.css base/page.css],
                       'tokens' => %w[tokens.css] }.freeze

        # 本文のページ（章・付録・前書き・後書き）がみな読む部品。順は 1.x の @import の順を保つ
        # （1.x の prism・code・table・layout-utils・components の順）
        BODY_PARTS = %w[parts/prism.css parts/code.css parts/table.css
                        parts/layout.css parts/sideimage.css parts/side-by-side.css
                        parts/book-card.css parts/footnote.css parts/math.css parts/epub-reflow.css
                        parts/talk.css parts/reference.css].freeze
        # 章と付録だけが読む部品（1.x の chapter-common.css）。前書き・後書きにそろえるのは S2-4
        CHAPTER_ONLY_PARTS = %w[parts/heading.css parts/prose.css parts/list.css
                                parts/figure.css parts/box.css].freeze
        CHAPTER_PARTS = [*%w[parts/simple-header.css parts/image-header.css], *BODY_PARTS,
                         *CHAPTER_ONLY_PARTS].freeze
        APPENDIX_PARTS = CHAPTER_PARTS - %w[parts/image-header.css]
        PREFACE_PARTS = BODY_PARTS

        # 著者が原稿で明示する指定。改ページ記法は、記法を書けるページの種類にだけ配る
        # （utilities/pagebreak.css の冒頭の説明）。前書き・後書きは 1.x で spacing.css を
        # 読んでいない（そろえるのは S2-4）
        CHAPTER_UTILITIES = %w[utilities/align.css utilities/gap.css
                               utilities/spacing.css utilities/pagebreak.css utilities/replace-list.css].freeze
        PREFACE_UTILITIES = %w[utilities/align.css utilities/gap.css
                               utilities/pagebreak.css utilities/replace-list.css].freeze

        # 種類ごとの、層 → stylesheets/ のファイル。FOUNDATION と book-settings.css は全種類に足す
        IMPORTS = {
          'chapter' => { 'parts' => CHAPTER_PARTS, 'pages' => %w[pages/chapter.css],
                         'utilities' => CHAPTER_UTILITIES },
          'appendix' => { 'parts' => APPENDIX_PARTS, 'pages' => %w[pages/appendix.css],
                          'utilities' => CHAPTER_UTILITIES },
          'preface' => { 'parts' => PREFACE_PARTS, 'pages' => %w[pages/preface.css],
                         'utilities' => PREFACE_UTILITIES },
          'postface' => { 'parts' => PREFACE_PARTS, 'pages' => %w[pages/preface.css pages/postface.css],
                          'utilities' => PREFACE_UTILITIES },
          'toc' => { 'pages' => %w[pages/toc.css pages/whole-toc.css] },
          'index' => { 'pages' => %w[pages/index.css] },
          'glossary' => { 'pages' => %w[pages/glossary.css] },
          'colophon' => { 'pages' => %w[pages/colophon.css] },
          'titlepage' => { 'pages' => %w[pages/titlepage.css] },
          'legalpage' => { 'pages' => %w[pages/legalpage.css] },
          'part-title' => { 'pages' => %w[pages/part-title.css] }
        }.freeze

        # 原稿の種類（Entry#kind・file_type）と入口の名前が違うもの
        KIND_ALIASES = { 'part_title' => 'part-title', 'whole_toc' => 'toc',
                         'indexpage' => 'index', 'glossarypage' => 'glossary' }.freeze

        module_function

        # 入口の CSS のパス（作業ディレクトリからの相対）
        # @param kind [String, Symbol] ページの種類（IMPORTS のキー、または KIND_ALIASES のキー）
        def path_for(kind) = File.join(Common::CACHE_DIR, "entry-#{entry_name(kind)}.css")

        # 種類の名前を入口の名前にする。知らない種類は本文の章の入口を使う
        def entry_name(kind)
          name = kind.to_s
          name = KIND_ALIASES.fetch(name, name)
          IMPORTS.key?(name) ? name : 'chapter'
        end

        # 入口の名前から、種類の CSS（frontmatter の `stylesheet: toc.css`）を引く。無ければ nil
        def kind_for_stylesheet(basename)
          name = File.basename(basename.to_s, '.css')
          IMPORTS.key?(name) ? name : nil
        end

        # すべての種類の入口を書き出す。フル・単章・preflight のどのモードでも、
        # book-settings.css を生成する段から呼ばれる。
        # @return [Array<String>] 書き出したパス
        def write_all!
          FileUtils.mkdir_p(Common::CACHE_DIR)
          IMPORTS.each_key.map do |kind|
            path = path_for(kind)
            File.write(path, render(kind), encoding: 'utf-8')
            path
          end
        end

        # 入口の CSS の全文（副作用なし）
        def render(kind)
          name = entry_name(kind)
          layered = FOUNDATION.merge(IMPORTS.fetch(name)) { |_, a, b| a + b }
          lines = LAYERS.flat_map do |layer|
            (layered[layer] || []).map { %(@import url("#{CACHE_TO_STYLESHEETS}#{it}") layer(#{layer});) }
          end
          lines << %(@import url("#{BOOK_SETTINGS}") layer(settings);)

          <<~CSS
            @charset "utf-8";
            /* 自動生成: #{name} のページの入口（手編集しない。生成器: VivlioStarter::CLI::Css::EntryWriter）
               層の順は css-layer-restructure-spec.md §2.1。書体の定義と custom.css は層の外。 */
            @layer #{LAYERS.join(', ')};
            @import url("#{CACHE_TO_STYLESHEETS}fonts.css");
            @import url("#{BOOK_FONTS}");
            #{lines.join("\n")}
            @import url("#{CACHE_TO_STYLESHEETS}custom.css");
          CSS
        end
      end
    end
  end
end
