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
#   ファイルの配置は §3.1（段階 S2-2 で分け、S2-4 で本文のページの部品をそろえた）。
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
                       'tokens' => %w[tokens.css tokens-legacy.css] }.freeze

        # 本文のページ（章・付録・前書き・後書き）がみな読む部品（css-layer-restructure-spec.md §3.3）。
        # 順は 1.x の章の @import の順を保つ（見出し 2 種 → prism・code・table・layout-utils・
        # components → chapter-common）。見出しの 2 種は body の vs-header-* のクラスで選ぶので、
        # どちらのクラスも付かない前書き・後書きには当たらない
        BODY_PARTS = %w[parts/simple-header.css parts/image-header.css
                        parts/prism.css parts/code.css parts/table.css
                        parts/layout.css parts/sideimage.css parts/side-by-side.css
                        parts/book-card.css parts/footnote.css parts/math.css parts/epub-reflow.css
                        parts/talk.css parts/reference.css
                        parts/heading.css parts/prose.css parts/list.css
                        parts/figure.css parts/box.css].freeze
        # 前書き・後書きは、部品の最後に前書きの見た目を読む。部品の記法の規則と詳細度で
        # 競わせるため、pages 層でなく parts 層に置く（parts/preface.css の冒頭の説明）
        PREFACE_PARTS = [*BODY_PARTS, 'parts/preface.css'].freeze

        # 著者が原稿で明示する指定。改ページ記法は、記法を書けるページの種類にだけ配る
        # （utilities/pagebreak.css の冒頭の説明）
        BODY_UTILITIES = %w[utilities/align.css utilities/gap.css
                            utilities/spacing.css utilities/pagebreak.css utilities/replace-list.css].freeze

        # 種類ごとの、層 → stylesheets/ のファイル。FOUNDATION と book-settings.css は全種類に足す。
        # 本文のページの違いは、pages/ のページの設定（章の扉絵・付録の色・前書きのノンブル）と
        # 前書き・後書きの parts/preface.css だけ
        IMPORTS = {
          'chapter' => { 'parts' => BODY_PARTS, 'pages' => %w[pages/chapter.css],
                         'utilities' => BODY_UTILITIES },
          'appendix' => { 'parts' => BODY_PARTS, 'pages' => %w[pages/appendix.css],
                          'utilities' => BODY_UTILITIES },
          'preface' => { 'parts' => PREFACE_PARTS, 'pages' => %w[pages/preface.css],
                         'utilities' => BODY_UTILITIES },
          'postface' => { 'parts' => PREFACE_PARTS, 'pages' => %w[pages/preface.css pages/postface.css],
                          'utilities' => BODY_UTILITIES },
          'toc' => { 'pages' => %w[pages/toc.css pages/whole-toc.css] },
          'index' => { 'pages' => %w[pages/index.css] },
          'glossary' => { 'pages' => %w[pages/glossary.css] },
          'colophon' => { 'pages' => %w[pages/colophon.css] },
          'titlepage' => { 'pages' => %w[pages/titlepage.css] },
          'legalpage' => { 'pages' => %w[pages/legalpage.css] },
          'part-title' => { 'pages' => %w[pages/part-title.css] }
        }.freeze

        # 出力先ごとの target 層（css-layer-restructure-spec.md §4.2 の 4・§5）。PDF は読まない。
        # Kindle の body にも vs-epub が付くので、Kindle は EPUB の規則も読む。
        # 入口のファイル（PDF が読む）には書かず、平らな CSS を作るときだけ足す（Bundle）。
        #
        # 種類ごとに分けるのは、移す前の規則が、そのページの種類が読むファイルにあったためである。
        # 奥付の `body.vs-kindle { … }` や前書きの `body.vs-kindle h1` を 1 枚にまとめると、
        # 本文のページにも当たる。中の規則は元のファイルの読み込みの順と、ファイルの中の順を保つ
        BODY_TARGETS = { epub: %w[targets/epub.css], kindle: %w[targets/epub.css targets/kindle.css] }.freeze
        PREFACE_TARGETS = { epub: BODY_TARGETS[:epub],
                            kindle: [*BODY_TARGETS[:kindle], 'targets/kindle-preface.css'] }.freeze
        TARGET_IMPORTS = {
          'chapter' => BODY_TARGETS, 'appendix' => BODY_TARGETS,
          'preface' => PREFACE_TARGETS, 'postface' => PREFACE_TARGETS,
          'index' => { kindle: %w[targets/kindle-index.css] },
          'glossary' => { kindle: %w[targets/kindle-glossary.css] },
          'colophon' => { kindle: %w[targets/kindle-colophon.css] }
        }.freeze

        # どの種類の束も、target 層の最初に読む出力先の CSS。Kindle は、部品の層まで値に解くので
        # （Css::LiteralResolver）、PDF 向けの本文の字の大きさと行送りのトークンを端末の既定へ置き換える
        TARGET_FOUNDATION = { kindle: %w[targets/kindle-tokens.css] }.freeze

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
        # @param target [Symbol, nil] :epub・:kindle なら target 層に出力先の CSS を足す
        def render(kind, target: nil)
          name = entry_name(kind)
          layered = FOUNDATION.merge(IMPORTS.fetch(name)) { |_, a, b| a + b }
          lines = LAYERS.flat_map do |layer|
            (layered[layer] || []).map { %(@import url("#{CACHE_TO_STYLESHEETS}#{it}") layer(#{layer});) }
          end
          lines << %(@import url("#{BOOK_SETTINGS}") layer(settings);)
          [*TARGET_FOUNDATION.fetch(target, []), *TARGET_IMPORTS.fetch(name, {}).fetch(target, [])].each do
            lines << %(@import url("#{CACHE_TO_STYLESHEETS}#{it}") layer(target);)
          end

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
