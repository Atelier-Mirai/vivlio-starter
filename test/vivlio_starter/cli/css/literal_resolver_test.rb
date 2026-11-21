# frozen_string_literal: true

# ================================================================
# Test: css/literal_resolver_test.rb
# ================================================================
# テスト対象:
#   Css::LiteralResolver（css-layer-restructure-spec.md §4.4）。Kindle 用の平らな CSS から
#   var()・calc()・color-mix()・:is()・:where() を解き、:has() の選択子を落とす。
#
# 二つに分ける:
#   LiteralResolverTest       小さな CSS で、解き方の決まり（変数の表の段・深い変数・計算・混色・選択子）
#   LiteralResolverKindleTest 同梱の stylesheets/ から Kindle の束を組み、book.yml の色と custom.css の色が
#                             Kindle の規則に値として届くこと。1.x の BookSettingsCss が Kindle 用に
#                             焼いていた規則（kindle_accent_rules など。S3-3 で消した）の確かめを引き継ぐ
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'vivlio_starter/cli/css/bundle'
require 'vivlio_starter/cli/pre_process/book_settings_css'

module VivlioStarter
  module CLI
    module Css
      class LiteralResolverTest < Minitest::Test
        # 章の body のクラスで解く
        def resolve(css, body_classes: %w[chapter vs-epub vs-kindle], scoped: [], language: 'ja', layer: ['target'])
          scope = LiteralResolver.scope_for([body_classes], target_classes: [], language:, scoped:)
          piece = Flattener::Piece.new(layer: layer, text: css, source: 'test.css')
          LiteralResolver.resolve(Stylesheet.parse(css).map { piece.with(text: it.text) }, scope:)
        end

        def text_of(result) = result.pieces.map(&:text).join("\n")

        def test_should_resolve_variables_with_body_definitions_over_root
          result = resolve(<<~CSS)
            :root { --accent: #111111; --mark: var(--accent); }
            body.chapter { --accent: #222222; }
            body.appendix { --accent: #333333; }
            p { color: var(--accent); border-color: var(--mark); }
          CSS
          css = text_of(result)

          assert_includes css, 'color: #222222;', 'body の定義が :root に勝つ。ほかの種類の body の定義は当たらない'
          assert_includes css, 'border-color: #111111;', ':root の値の中の var() は :root の定義を読む（継承と同じ）'
          assert_empty result.dropped
        end

        def test_should_follow_specificity_and_order_within_the_same_level
          css = text_of(resolve(<<~CSS))
            :root { --a: #111111; }
            html { --a: #222222; }
            :root { --b: #333333; }
            :root { --b: #444444; }
            p { color: var(--a); background: var(--b); }
          CSS

          assert_includes css, 'color: #111111;', ':root（0,1,0）は後に書いた html（0,0,1）に勝つ'
          assert_includes css, 'background: #444444;', '同じ強さなら後に書いた定義'
        end

        # 要素ごとに値が違いうる変数（深い要素の上の定義・ページごとのクラス・HTML の style 属性）は解かず、
        # 読む宣言を落とす。KFX も var() を含む宣言を捨てるので、Kindle の結果は今と同じ
        def test_should_drop_declarations_that_read_scoped_variables
          result = resolve(<<~CSS, scoped: %w[--cols])
            :root { --book-talk-accent: #111111; }
            .talk { --book-talk-accent: #222222; }
            body.chapter-first { --first: 1px; }
            .talk-name { color: var(--book-talk-accent); }
            .first { margin: var(--first); }
            .pictures { columns: var(--cols, 3); }
            p { color: red; }
          CSS

          assert_equal %w[.talk-name .first .pictures], result.dropped.map(&:selector)
          assert(result.dropped.all? { it.reason == :variable })
          refute_match(/var\(/, text_of(result))
          assert_includes text_of(result), "p {\n  color: red;\n}"
        end

        def test_should_use_fallback_only_for_undefined_variables
          css = text_of(resolve(":root { --a: 2mm; }\np { margin: var(--a, 9mm); padding: var(--none, 3mm); }"))

          assert_includes css, 'margin: 2mm;'
          assert_includes css, 'padding: 3mm;'
        end

        # 変数の定義は値を解いて残す。HTML の中の <style> が var() で読むため
        def test_should_keep_definitions_with_resolved_values
          css = text_of(resolve(":root { --base: 4mm; --twice: calc(var(--base) * 2); --odd: calc(1mm + 2%); }"))

          assert_includes css, '--base: 4mm;'
          assert_includes css, '--twice: 8mm;'
          refute_includes css, '--odd', '解けない定義は落とす'
        end

        def test_should_calculate_calc_with_consistent_units
          result = resolve(<<~CSS)
            :root { --book-paper-scale: 0.96; }
            p {
              margin: calc(var(--book-paper-scale) * 4mm);
              width: calc(100% * 2 / 3);
              left: calc(50% + 2mm);
            }
          CSS
          css = text_of(result)

          assert_includes css, 'margin: 3.84mm;'
          assert_includes css, 'width: 66.666667%;'
          assert_equal [['left: calc(50% + 2mm)', :calc]], result.dropped.map { [it.declaration, it.reason] }
        end

        # 紙の寸法（clamp()・min()・max()）は、calc() の中でも外でも、変数から入ってきても落とす。
        # 落とした理由は :paper_dimension で、ほかの理由と分ける（css-layer-restructure-spec.md §4.4）
        def test_should_drop_paper_dimensions_with_their_own_reason
          result = resolve(<<~CSS)
            :root { --book-paper-scale: 0.96; --gap: clamp(2mm, 3mm, 4mm); --plain: 2mm; }
            p {
              padding: clamp(1mm, calc(var(--book-paper-scale) * 2mm), 3mm);
              text-indent: calc(-1 * clamp(9.1mm, calc(var(--book-paper-scale) * 13mm), 13mm));
              inline-size: min(100%, 30em);
              block-size: MAX(1em, 2mm);
              row-gap: var(--gap);
              min-width: 10mm;
              grid-template-columns: repeat(2, minmax(0, 1fr));
              margin: var(--plain);
              content: "clamp(";
            }
          CSS
          css = text_of(result)

          assert_equal %w[padding text-indent inline-size block-size row-gap],
                       result.dropped.map { it.declaration[/\A[\w-]+/] }
          assert(result.dropped.all? { it.reason == :paper_dimension })
          refute_includes css, '--gap', '紙の寸法の定義は、知らせずに落とす'
          assert_includes css, 'min-width: 10mm;', 'プロパティの名前の min は関数ではない'
          assert_includes css, 'minmax(0, 1fr)', 'minmax() の max( は紙の寸法の関数ではない'
          assert_includes css, 'margin: 2mm;'
          assert_includes css, 'content: "clamp(";', '引用符の中は見ない'
        end

        def test_should_mix_srgb_colors_and_drop_the_others
          result = resolve(<<~CSS)
            :root { --book-color-accent: #15803d; }
            p {
              background: color-mix(in srgb, var(--book-color-accent) 15%, white);
              color: color-mix(in srgb, red, blue);
              border-color: color-mix(in oklab, red 50%, white);
              outline-color: color-mix(in srgb, red 30%, transparent);
            }
          CSS
          css = text_of(result)

          assert_includes css, 'background: #dcece2;', '1.x の ThemeColor.mix_with_white と同じ値'
          assert_includes css, 'color: #800080;'
          assert_equal %i[color_mix color_mix], result.dropped.map(&:reason), 'srgb 以外と透明との混色は落とす'
        end

        def test_should_expand_is_and_drop_has_selectors
          result = resolve(<<~CSS)
            figure :is(img, svg) { margin: 0; }
            .align-left:not(:is(figure, img)) { float: left; }
            :where(h2, h3).title, p:has(+ table) { color: red; }
            p:has(> strong) { color: blue; }
          CSS
          css = text_of(result)

          assert_includes css, "figure img,\nfigure svg {"
          assert_includes css, '.align-left:not(figure):not(img) {'
          assert_includes css, "h2.title,\nh3.title {\n  color: red;\n}", ':has() の選択子だけを並びから外す'
          refute_match(/:is\(|:where\(|:has\(/, css)
          assert_equal ['p:has(+ table)', 'p:has(> strong)'], result.dropped.map(&:selector)
        end

        # どの層の規則も解く（css-layer-restructure-spec.md §4.4 の「解く層」）。部品の層の var()・calc() も
        # 値になり、:is() は並べた選択子になり、:has() の選択子だけが落ちる
        def test_should_resolve_rules_in_every_layer
          result = resolve(<<~CSS, layer: ['parts'])
            :root { --size: 10.5pt; --accent: #111111; }
            :root { font-size: var(--size); color: var(--accent); padding: calc(2mm * 2); }
            figure :is(img, svg) { margin: 0; }
            p:has(+ table) { color: blue; }
          CSS
          css = text_of(result)

          assert_includes css, "font-size: 10.5pt;\n  color: #111111;\n  padding: 4mm;"
          assert_includes css, "figure img,\nfigure svg {"
          refute_includes css, 'p:has'
          assert_equal [:has], result.dropped.map(&:reason)
        end

        # Kindle は画面の媒体なので、印刷の媒体の定義は表に入れない。値は同じ表で解く
        def test_should_ignore_print_only_definitions
          css = text_of(resolve(<<~CSS))
            :root { --gap: 2mm; }
            @media print { :root { --gap: 9mm; } p { margin: var(--gap); } }
            p { padding: var(--gap); }
          CSS

          assert_includes css, 'padding: 2mm;'
          assert_includes css, "@media print {\n:root {\n  --gap: 9mm;\n}\np {\n  margin: 2mm;\n}\n}", "定義は残すが、宣言は画面の表で解く"
        end

        def test_should_match_root_language_with_the_book_language
          css = <<~CSS
            :root { --q: "x"; }
            :root:lang(ja) { --q: "「"; }
            :root:lang(en) { --q: "“"; }
            q::before { content: var(--q); }
          CSS

          assert_includes text_of(resolve(css, language: 'ja')), 'content: "「";'
          assert_includes text_of(resolve(css, language: 'en-US')), 'content: "“";'
        end

        # @page と @font-face の中の宣言も解く。値に var() を含まない規則は書かれたままの値を保つ
        def test_should_resolve_page_rules_and_keep_plain_values
          css = text_of(resolve(":root { --w: 182mm; }\n@page { size: var(--w) 257mm; }\np::before { content: \"(1)\"; }"))

          assert_includes css, "@page {\n  size: 182mm 257mm;\n}"
          assert_includes css, 'content: "(1)";'
        end
      end

      # 同梱の stylesheets/ から Kindle の束を組み、book.yml と custom.css の色が値で届くことを確かめる
      class LiteralResolverKindleTest < Minitest::Test
        ROOT = File.expand_path('../../../..', __dir__)
        BSC = PreProcessCommands::BookSettingsCss

        # 本の写し（stylesheets/ は custom.css 以外をリポジトリへの symlink にする）で、
        # ページの種類 kind の Kindle 用の平らな CSS を組む。warnings は 🟡 の出力
        # @return [Array(String, String)] CSS と標準出力
        def kindle_css(kind, theme_color: 'yellow', appendix_color: 'red', preface_color: 'teal',
                       section_pagebreak: true, custom: nil)
          base = Common::CONFIG
          cfg = base.with(theme: base.theme.with(color: theme_color, appendix_color:, preface_color:),
                          page: base.page.with(section_pagebreak:))
          settings = BSC.render(cfg)
          Dir.mktmpdir('vs-literal') do |dir|
            stylesheets = File.join(dir, 'stylesheets')
            FileUtils.mkdir_p([stylesheets, File.join(dir, '.cache', 'vs')])
            Dir.children(File.join(ROOT, 'stylesheets')).each do
              File.symlink(File.join(ROOT, 'stylesheets', it), File.join(stylesheets, it)) unless it == 'custom.css'
            end
            File.write(File.join(stylesheets, 'custom.css'), custom.to_s)
            # standard の見出しの規則（Kindle の簡素な見出しを含む）は themes/standard/ にある
            File.symlink(File.join(ROOT, 'themes'), File.join(dir, 'themes'))
            File.write(File.join(dir, '.cache', 'vs', 'book-settings.css'), settings)
            File.write(File.join(dir, '.cache', 'vs', 'book-fonts.css'), '')
            html = File.join(dir, 'page.html')
            header = kind == 'chapter' ? 'vs-header-simple' : ('vs-header-simple' if kind == 'appendix')
            File.write(html, %(<html><body class="#{[kind, header].compact.join(' ')}"></body></html>))

            Dir.chdir(dir) do
              out, err = capture_io do
                pieces = Bundle.flat_pieces(kind, target: :kindle, dest: File.join(dir, 'styles', "#{kind}.css"),
                                                  package_root: dir, embed_fonts: false)
                pieces = Bundle.literalize(pieces, target: :kindle, scope: Bundle.kindle_scope([html]), reported: {})
                @css = Flattener.render(pieces)
              end
              return [@css, out + err]
            end
          end
        end

        # 規則の中の宣言の値（選択子の並びの先頭が selector の規則を探す）
        def value_of(css, selector, property)
          css.scan(/^#{Regexp.escape(selector)}[,\s][^{]*\{([^}]*)\}/).flatten
             .filter_map { it[/^\s*#{Regexp.escape(property)}:\s*([^;]+);/, 1] }.last
        end

        def test_should_leave_no_function_that_kfx_drops
          %w[chapter appendix preface colophon index glossary toc].each do |kind|
            css, = kindle_css(kind)

            %w[var( calc( color-mix( :is( :where( :has( @layer @import].each do |token|
              refute_includes css, token, "#{kind} の Kindle 用の CSS に #{token} を残さない"
            end
            # 紙の寸法は、生成が理由を付けて落とす（theme-contract-spec.md §9 の S6 の完了の条件の 7）
            refute_match(/(?<![\w-])(?:clamp|min|max)\(/, css, "#{kind} の Kindle 用の CSS に紙の寸法を残さない")
          end
        end

        # テーマ色（yellow = #f0a000）が本文の強調・囲み・h4 の印に届く。h4 の印は Techbook の <style> に
        # 勝つよう !important を保つ
        def test_should_bring_theme_color_to_kindle_rules
          css, = kindle_css('chapter')

          assert_equal '#f0a000', value_of(css, 'body.vs-kindle strong', 'color')
          assert_equal '#f0a000', value_of(css, 'body.vs-kindle .column', 'border-color')
          assert_equal '#fdf1d9', value_of(css, '.column', 'background'), 'コラムの地はテーマ色と白の混色（parts/box.css）'
          assert_equal '2px solid #f0a000', value_of(css, 'body.vs-header-simple.vs-kindle h1', 'border')
          assert_equal '"♦" !important', value_of(css, 'body.chapter.vs-kindle h4::before', 'content')
          assert_equal '#f0a000', value_of(css, 'body.chapter.vs-kindle h4::before', 'color')
        end

        # 付録のページは、テーマ色で塗るものを全部、付録の色（red = #dc2626）で塗る（改善案 #132）。
        # 章（テーマ色 yellow = #f0a000）は変わらない
        def test_should_bring_appendix_color_to_every_accent_in_appendix
          css, = kindle_css('appendix')

          assert_equal '2px solid #dc2626', value_of(css, 'body.vs-header-simple.vs-kindle h1', 'border')
          assert_equal '#dc2626', value_of(css, 'body.vs-kindle .subsection-marker', 'color')
          assert_equal '#dc2626', value_of(css, 'body.vs-kindle strong', 'color')
          assert_equal '#dc2626', value_of(css, 'body.appendix.vs-kindle .tip', 'border-color')
          assert_equal '#dc2626', value_of(css, 'body.vs-kindle .memo', 'border-color')
          assert_equal '#dc2626', value_of(css, 'body.vs-kindle .note', 'border-color')
          assert_equal '#fadede', value_of(css, '.column', 'background')
          assert_equal '#dc2626', value_of(css, 'body.appendix.vs-kindle .tip .vs-adm-label', 'color')
          assert_equal '#dc2626', value_of(css, 'body.vs-kindle .memo .vs-adm-label', 'color')

          chapter, = kindle_css('chapter')
          assert_equal '#f0a000', value_of(chapter, 'body.vs-kindle .memo', 'border-color')
          assert_equal '#f0a000', value_of(chapter, 'body.vs-kindle strong', 'color')
        end

        def test_should_bring_preface_color_to_preface_lines
          css, = kindle_css('preface')

          assert_equal '3px solid #0d9488', value_of(css, 'body.preface.vs-kindle h1', 'border-bottom')
          assert_equal '#0d9488', value_of(css, 'body.preface.vs-kindle a', 'color')
        end

        def test_should_bring_theme_color_to_index_glossary_and_colophon
          assert_equal '2px solid #f0a000', value_of(kindle_css('index').first, 'body.vs-kindle .index h1', 'border-bottom')
          glossary, = kindle_css('glossary')
          assert_equal '#fdf1d9', value_of(glossary, 'body.vs-kindle .glossary-group-header', 'background')
          assert_equal '1px solid #f0a000', value_of(kindle_css('colophon').first, 'body.vs-kindle .book-title',
                                                     'border-bottom')
        end

        def test_should_follow_section_pagebreak_setting
          enabled, = kindle_css('chapter')
          disabled, = kindle_css('chapter', section_pagebreak: false)

          assert_equal 'always', value_of(enabled, 'body.vs-header-simple.vs-kindle h2', 'page-break-before')
          assert_equal 'auto', value_of(disabled, 'body.vs-header-simple.vs-kindle h2', 'page-break-before')
          assert_equal 'auto', value_of(disabled, 'body.vs-header-simple.vs-kindle h2', 'break-before')
        end

        # custom.css の :root で変えた色は、平らな CSS の後ろで定義が勝ち、Kindle の規則に値で届く
        def test_should_bring_custom_css_colors_to_kindle
          css, out = kindle_css('chapter', custom: <<~CUSTOM)
            :root {
              --book-color-strong: #1a73e8;
              --book-color-column-border: var(--book-accent-red);
              --book-color-column-bg: color-mix(in srgb, var(--book-accent-red) 20%, white);
            }
          CUSTOM

          assert_equal '#1a73e8', value_of(css, 'body.vs-kindle strong', 'color')
          assert_equal '#dc2626', value_of(css, 'body.vs-kindle .memo', 'border-color')
          assert_equal '#f8d4d4', value_of(css, '.column', 'background')
          refute_includes out, 'Kindle では効きません'
        end

        # 本文の字の大きさと行送りは、PDF の紙面の値でなく端末の既定にし、書体は総称の名前だけにする
        # （targets/kindle-tokens.css）。custom.css の :root で PDF 用に変えた値も届かず、body.vs-kindle で
        # 書いた値は届く
        def test_should_keep_device_font_size_and_line_height_on_kindle
          %w[chapter appendix preface postface index glossary colophon part-title].each do |kind|
            css, = kindle_css(kind)

            assert_equal '1em', value_of(css, ':root', 'font-size'), kind
            assert_equal 'normal', value_of(css, ':root', 'line-height'), kind
            assert_equal 'serif', value_of(css, ':root', 'font-family'), kind
          end
          chapter, = kindle_css('chapter')
          assert_equal 'sans-serif', value_of(chapter, 'h1', 'font-family'), '見出しはゴシック'
          assert_equal 'monospace, monospace', value_of(chapter, 'code', 'font-family')

          pdf_only, = kindle_css('chapter', custom: ":root { --book-font-size: 12pt; }\n")
          assert_equal '1em', value_of(pdf_only, ':root', 'font-size')
          kindle_only, = kindle_css('chapter', custom: "body.vs-kindle { --book-font-size: 1.1em; }\n")
          assert_equal '1.1em', value_of(kindle_only, ':root', 'font-size')
        end

        # 1.x の kindle_custom_color_rules が Kindle に焼いていた custom.css の色のうち、S3-3a で届かなく
        # なった 3 つ（リンク・コラムの h5・テキストの図の枠）が、部品の規則と Kindle の規則から届く
        def test_should_bring_custom_css_link_mark_and_diagram_colors_to_kindle
          css, = kindle_css('chapter', custom: <<~CUSTOM)
            :root {
              --book-color-link: #1a73e8;
              --book-color-mark: #7c3aed;
              --book-color-border-weak: #aaaaaa;
            }
          CUSTOM

          assert_equal '#1a73e8', value_of(css, 'a', 'color')
          assert_equal '#7c3aed', value_of(css, '.column h5', 'color')
          assert_equal '1px solid #aaaaaa', value_of(css, 'body.vs-kindle .diagram', 'border'),
                       '--book-color-output-border の既定は --book-color-border-weak'

          default, = kindle_css('chapter')
          assert_equal '#000', value_of(default, 'a', 'color')
          assert_equal '1px solid #ddd', value_of(default, 'body.vs-kindle .diagram', 'border')
          assert_equal '1px solid #ddd', value_of(default, 'body.vs-kindle .output', 'border')
        end

        # 実行結果とテキストの図の枠は、custom.css の --book-color-output-border で PDF と Kindle の両方の色が変わる
        def test_should_bring_output_border_color_to_kindle
          css, = kindle_css('chapter', custom: ":root { --book-color-output-border: var(--book-color-accent); }\n")

          assert_includes css, ".output,\n.diagram {\n  margin-block: 3mm;\n  padding: 2.5mm 3mm;\n  border: solid 0.2mm #f0a000;",
                          '部品の .output, .diagram の規則（PDF と同じ規則）'
          assert_equal '1px solid #f0a000', value_of(css, 'body.vs-kindle .output', 'border')
          assert_equal '1px solid #f0a000', value_of(css, 'body.vs-kindle .diagram', 'border')
        end

        # custom.css の解けない宣言は、場所と直し方を 🟡 で知らせる。vs の CSS で落とした宣言は知らせない。
        # 紙の寸法は、custom.css に書いたものでも知らせない（PDF の紙面のための意図した書き方）
        def test_should_warn_only_author_declarations_that_kindle_cannot_use
          _, out = kindle_css('chapter', custom: "h2 { margin-block-start: calc(100% - 2mm); }\n" \
                                                 "h3 { margin-block-end: clamp(2mm, 3mm, 4mm); }\n")

          assert_includes out, 'stylesheets/custom.css の「h2 { margin-block-start: calc(100% - 2mm) }」は Kindle では効きません'
          assert_includes out, 'calc(100% - 2mm) → 95%'
          refute_includes out, 'talk', 'vs の CSS の落とした宣言（会話の深い変数）は知らせない'
          refute_includes out, 'clamp', '紙の寸法は知らせない'
        end
      end
    end
  end
end
