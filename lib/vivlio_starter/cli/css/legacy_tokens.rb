# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/css/legacy_tokens.rb
# ================================================================
# 責務:
#   2.0 で `--book-*` に名前を変えた変数の、今の名前との対応の表（css-layer-restructure-spec.md §7.2・
#   theme-contract-spec.md §5）。次の三つが、この 1 枚の表を読む。
#     - stylesheets/tokens-legacy.css   今の名前を**読む**向きの別名（tokens 層。alias_css と同じ中身）
#     - BookSettingsCss                 custom.css が今の名前に**値を入れる**向き（settings 層。settings_declarations）
#     - vs upgrade                      custom.css の今の名前を新しい名前へ置き換える（rename）
#
# 名前を変える範囲（theme-contract-spec.md §5.1）:
#   公開する変数（§5.2）と機能の変数（扉絵 --book-frontispiece-*・節絵 --book-ornament-*）と、
#   standard へ移る見出しの 2 枚の中だけの変数（--standard-*）。vs の内部の変数（--page-width・
#   --font-body・--subtitle-* など）は 2.0 では名前を変えない。名前を変えた変数は例外なく、ここに載せる。
# ================================================================

require 'crass'

module VivlioStarter
  module CLI
    module Css
      # 今の名前 → 新しい名前の対応の表
      module LegacyTokens
        # テーマ色の 12 色（tokens.css の並び）
        ACCENTS = %w[yellow orange red magenta purple indigo navy blue cyan teal green lime].freeze

        # 今の名前 → 新しい名前。並びは tokens.css の分類（theme-contract-spec.md §5.2）の順
        MAP = {
          **ACCENTS.to_h { ["--accent-#{it}", "--book-accent-#{it}"] },
          # 本のテーマ色
          '--theme-accent' => '--book-color-accent',
          '--color-preface-accent' => '--book-color-accent-preface',
          '--appendix-accent-color' => '--book-color-accent-appendix',
          # 色
          **%w[text link strong em-underline border border-weak output-border column-bg column-border
               figure-border overlay danger mark].to_h { ["--color-#{it}", "--book-color-#{it}"] },
          '--heading-accent' => '--book-color-heading',
          '--section-number-color' => '--book-color-section-number',
          # 書体
          '--font-main-text' => '--book-font-body',
          '--font-header' => '--book-font-heading',
          '--font-column' => '--book-font-column',
          '--font-code' => '--book-font-code',
          '--font-folio' => '--book-font-folio',
          '--font-title' => '--book-font-title',
          # 版面
          **%w[top bottom inner outer].to_h { ["--page-margin-#{it}", "--book-page-margin-#{it}"] },
          '--base-font-size' => '--book-font-size',
          '--base-line-height' => '--book-line-height',
          '--letter-spacing' => '--book-letter-spacing',
          '--paper-scale' => '--book-paper-scale',
          # 柱とノンブル
          **%w[font-size color left-content right-content center-content].to_h { ["--folio-#{it}", "--book-folio-#{it}"] },
          # 見出しの印
          '--h3-marker' => '--book-marker-h3',
          '--h4-marker' => '--book-marker-h4',
          # 会話
          **%w[accent bg icon-size speaker-size].to_h { ["--talk-#{it}", "--book-talk-#{it}"] },
          # 扉絵（機能 frontispiece）
          **%w[image edge-inset background-size heading-width lead-width heading-offset binding-offset]
            .to_h { ["--frontispiece-#{it}", "--book-frontispiece-#{it}"] },
          # 節絵（機能 ornament）
          '--section-bg-image' => '--book-ornament-image',
          '--section-title-font-size' => '--book-ornament-title-font-size',
          # standard の見出しの 2 枚の中だけの変数
          '--heading-text' => '--standard-heading-text'
        }.freeze

        # 消した変数（どこからも読まれていなかった）。別名を置かない
        REMOVED = %w[--color-shadow --heading-gray --section-gray].freeze

        # :root でなく会話の要素の上で定義される変数（parts/talk.css の .talk、生成 CSS の話者の
        # .talk-item.talk-c-<key>）。:root の別名だけでは、要素の上で変えた値が今の名前に届かないので、
        # 同じ要素の上にも別名を置く（var() は、別名を定義した要素の上で解かれる）
        TALK_SCOPED = %w[--talk-accent --talk-bg].freeze
        TALK_SELECTOR = '.talk, .talk-item'

        # 変数の名前 1 つ（前後が名前の字でない）
        NAME = /(?<![\w-])--[a-z][\w-]*(?![\w-])/

        module_function

        # CSS の中の今の名前を、新しい名前に置き換える（定義も var() の中も、注釈の中も）。
        # @param text [String]
        # @return [String]
        def rename(text) = text.gsub(NAME) { MAP.fetch(it, it) }

        # CSS が使っている今の名前（定義と var() の両方）。注釈の中は数えない
        # @return [Array<String>] 出てきた順
        def legacy_names_in(css)
          css.gsub(%r{/\*.*?\*/}m, '').scan(NAME).select { MAP.key?(it) }.uniq
        end

        # custom.css の :root で今の名前に値を入れている定義を、新しい名前へ渡す settings 層の宣言。
        # custom.css は層の外にあるので、その定義は tokens-legacy.css の別名に勝ち、今の名前は値そのものに
        # なる。新しい名前をその値にすれば、vs の部品（新しい名前を読む）にも届く。
        # 値が新しい名前を読んでいる定義（`--theme-accent: var(--book-color-accent)`）は、渡すと
        # 循環になるので渡さない。
        # @param css [String] custom.css の全文
        # @return [Array<String>] `--book-x: var(--old);` の列（表の順）
        def settings_declarations(css)
          defined = root_definitions(css)
          MAP.filter_map do |old, new|
            value = defined[old] or next
            next if value.match?(/var\(\s*--book-/)

            "#{new}: var(#{old});"
          end
        end

        # :root（`:root`・`html`）の規則で定義された変数の名前 → 値。後の定義が勝つ
        def root_definitions(css)
          Crass.parse(css, preserve_comments: false).each_with_object({}) do |node, defs|
            next unless node in { node: :style_rule, selector: { value: list }, children: }
            next unless list.split(',').any? { it.strip.match?(/\A(:root|html)\z/) }

            children.each { defs[it[:name]] = it[:value].strip if it[:node] == :property && it[:name].start_with?('--') }
          end
        end

        # stylesheets/tokens-legacy.css の中身（読む向きの別名）。テストがファイルと突き合わせる
        def alias_css
          root = MAP.map { |old, new| "  #{old}: var(#{new});" }
          talk = TALK_SCOPED.map { "  #{it}: var(#{MAP.fetch(it)});" }
          <<~CSS
            @charset "utf-8";

            /* =============================================================
               tokens-legacy.css - 1.x の変数の名前の別名
               =============================================================

               2.0 で、公開する変数の名前は --book-* に変わりました（一覧は tokens.css）。
               このファイルは、1.x の名前（--theme-accent など）を新しい名前の別名として定義し、
               1.x の custom.css が var(--theme-accent) のように読んでも効くようにします。
               1.x の名前に値を入れた custom.css（:root { --color-link: #1a73e8; }）は、
               ビルドが book-settings.css で新しい名前へ渡します。

               自動生成: Css::LegacyTokens.alias_css と同じ中身（手で編集しない）。
               vs upgrade で custom.css を新しい名前へ置き換えられます。

               ============================================================= */

            :root {
            #{root.join("\n")}
            }

            /* 会話の色は話者の要素の上で決まるので、同じ要素の上にも別名を置く */
            #{TALK_SELECTOR} {
            #{talk.join("\n")}
            }
          CSS
        end
      end
    end
  end
end
