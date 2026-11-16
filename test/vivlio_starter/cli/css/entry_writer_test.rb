# frozen_string_literal: true

# ================================================================
# Test: css/entry_writer_test.rb
# ================================================================
# テスト対象:
#   Css::EntryWriter（ページの種類ごとの入口の CSS。css-layer-restructure-spec.md §2.3）
#
# 検証方法:
#   入口の全文の形と、リポジトリの stylesheets/ を読ませた入口を平らにした結果を見る。
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'vivlio_starter/cli/css/entry_writer'
require 'vivlio_starter/cli/css/flattener'
require 'yaml'

module VivlioStarter
  module CLI
    module Css
      class EntryWriterTest < Minitest::Test
        STYLESHEETS = File.expand_path('../../../../stylesheets', __dir__)

        # 層の順を先に宣言し、書体の定義と custom.css は層の外、book-settings.css は settings 層で読む
        def test_should_declare_layers_and_import_each_file_into_its_layer
          css = EntryWriter.render('chapter')
          lines = css.lines.map(&:strip)

          assert_includes lines, '@layer reset, base, tokens, parts, pages, theme, utilities, settings, target;'
          assert_includes lines, '@import url("../../stylesheets/fonts.css");'
          assert_includes lines, '@import url("book-fonts.css");'
          assert_includes lines, '@import url("../../stylesheets/tokens.css") layer(tokens);'
          assert_includes lines, '@import url("../../stylesheets/tokens-legacy.css") layer(tokens);'
          assert_includes lines, '@import url("../../stylesheets/parts/box.css") layer(parts);'
          assert_includes lines, '@import url("../../stylesheets/pages/chapter.css") layer(pages);'
          assert_includes lines, '@import url("../../stylesheets/utilities/pagebreak.css") layer(utilities);'
          assert_includes lines, '@import url("book-settings.css") layer(settings);'
          assert_equal '@import url("../../stylesheets/custom.css");', lines.last, 'custom.css は最後に、層の外で読む'
          assert lines.index { it.start_with?('@layer') } < lines.index { it.start_with?('@import') },
                 '層の順の宣言は @import より前'
        end

        # 本文以外のページは、土台・自分のページの CSS・見出しの 2 枚・設定だけを読む
        def test_should_give_generated_pages_only_the_foundation_and_their_own_css
          imports = EntryWriter.render('index').scan(/@import url\("([^"]+)"\)/).flatten

          assert_equal %w[../../stylesheets/fonts.css book-fonts.css
                          ../../stylesheets/base/reset.css ../../stylesheets/base/elements.css
                          ../../stylesheets/base/page.css ../../stylesheets/tokens.css ../../stylesheets/tokens-legacy.css
                          ../../stylesheets/pages/index.css
                          ../../stylesheets/parts/simple-header.css ../../stylesheets/parts/image-header.css
                          book-settings.css ../../stylesheets/custom.css], imports
        end

        # 本文のページ（章・付録・前書き・後書き）は同じ部品と著者の指定を読む。前書き・後書きは
        # 部品の最後に前書きの見た目を足し、違いはそれと pages/ のファイルだけ
        # （css-layer-restructure-spec.md §3.3）
        def test_should_give_every_body_page_the_same_parts_and_utilities
          layered = %w[chapter appendix preface postface].to_h do |kind|
            imports = EntryWriter.render(kind).scan(/@import url\("([^"]+)"\) layer\((\w+)\)/)
            [kind, imports.group_by(&:last).transform_values { it.map(&:first) }]
          end
          chapter = layered.fetch('chapter')

          assert_equal chapter['parts'], layered.fetch('appendix')['parts']
          %w[preface postface].each do |kind|
            assert_equal [*chapter['parts'], '../../stylesheets/parts/preface.css'], layered.fetch(kind)['parts'],
                         "#{kind} は章の部品の後に parts/preface.css を読む"
          end
          layered.each_value { assert_equal chapter['utilities'], it['utilities'] }
        end

        # standard の見出しの 2 枚は、どの種類のページでも parts 層でなく theme 層に読む
        # （theme-contract-spec.md §9 の S6-4）
        def test_should_import_the_standard_headers_into_the_theme_layer_of_every_page
          headers = %w[../../stylesheets/parts/simple-header.css ../../stylesheets/parts/image-header.css]
          EntryWriter::IMPORTS.each_key do |kind|
            imports = EntryWriter.render(kind, theme: nil).scan(/@import url\("([^"]+)"\) layer\((\w+)\)/)

            theme, others = imports.partition { it.last == 'theme' }

            assert_equal headers, theme.map(&:first), kind
            assert_empty others.map(&:first) & headers, "#{kind} はほかの層で 2 枚を読まない"
          end
        end

        # 扉絵を敷く @page :nth(1) は body のクラスで絞れないので、章だけが読むファイルに置く
        def test_should_keep_the_frontispiece_page_rule_out_of_non_chapter_pages
          frontispiece = /@page :nth\(1\) \{[^}]*--book-frontispiece-image/
          files = EntryWriter::IMPORTS.select { |kind, _| kind != 'chapter' }.values
                                      .flat_map(&:values).flatten.uniq
                                      .concat(EntryWriter::FOUNDATION.values.flatten)
          holders = files.select { File.read(File.join(STYLESHEETS, it)).match?(frontispiece) }

          assert_empty holders
          assert_match frontispiece, File.read(File.join(STYLESHEETS, 'pages/chapter.css'))
        end

        # 原稿の種類の名前の揺れを吸収し、知らない種類は本文の章の入口を使う
        def test_should_map_kinds_and_stylesheet_names_to_entries
          assert_equal '.cache/vs/entry-part-title.css', EntryWriter.path_for(:part_title)
          assert_equal '.cache/vs/entry-toc.css', EntryWriter.path_for('whole_toc')
          assert_equal '.cache/vs/entry-index.css', EntryWriter.path_for(:indexpage)
          assert_equal '.cache/vs/entry-chapter.css', EntryWriter.path_for('unknown')
          assert_equal 'toc', EntryWriter.kind_for_stylesheet('toc.css')
          assert_nil EntryWriter.kind_for_stylesheet('my-own.css')
        end

        # 入口が読む stylesheets/ のファイルは、リポジトリにすべてある
        def test_should_only_import_stylesheets_that_exist
          missing = EntryWriter::IMPORTS.values.flat_map(&:values).flatten.uniq
                                        .concat(EntryWriter::FOUNDATION.values.flatten)
                                        .reject { File.file?(File.join(STYLESHEETS, it)) }

          assert_empty missing
          assert File.file?(File.join(STYLESHEETS, 'fonts.css'))
        end

        # 全種類の入口を書き出し、本の stylesheets/ を平らにすると、@import も @layer も残らない
        def test_should_write_every_entry_and_flatten_the_real_stylesheets
          Dir.mktmpdir('vs-css-entry') do |root|
            Dir.chdir(root) do
              File.symlink(STYLESHEETS, 'stylesheets')
              written = EntryWriter.write_all!

              assert_equal EntryWriter::IMPORTS.size, written.size
              css = Flattener.flatten(EntryWriter.path_for('chapter'), rebase: ->(path) { path })

              refute_match(/@import|@layer/, css)
              refute_match(/vs-kindle|vs-epub/, css, 'PDF の入口は target 層を読まない')
              assert_includes css, 'hr.pagebreak'
            end
          end
        end

        # 出力先の規則は target 層で、そのページの種類の分だけ読む。Kindle は EPUB の規則も読む。
        # Kindle は、どの種類も最初に本文の字の大きさと行送りのトークン（kindle-tokens.css）を読む。
        # book.yml から生成する Kindle だけの規則は無い（色は Css::LiteralResolver が変数から解く）
        def test_should_import_target_files_per_kind_and_target
          targets = lambda do |kind, target|
            EntryWriter.render(kind, target:).scan(/@import url\("([^"]+)"\) layer\(target\)/).flatten
          end

          assert_empty targets.call('chapter', nil), 'PDF は target 層を読まない'
          assert_equal %w[../../stylesheets/targets/epub.css], targets.call('chapter', :epub)
          assert_equal %w[../../stylesheets/targets/kindle-tokens.css ../../stylesheets/targets/epub.css
                          ../../stylesheets/targets/kindle.css],
                       targets.call('appendix', :kindle)
          assert_equal %w[../../stylesheets/targets/kindle-tokens.css ../../stylesheets/targets/epub.css
                          ../../stylesheets/targets/kindle.css ../../stylesheets/targets/kindle-preface.css],
                       targets.call('postface', :kindle)
          assert_equal %w[../../stylesheets/targets/kindle-tokens.css ../../stylesheets/targets/kindle-colophon.css],
                       targets.call('colophon', :kindle), '奥付の Kindle の規則は奥付だけが読む'
          assert_equal %w[../../stylesheets/targets/kindle-tokens.css], targets.call('toc', :kindle)
          assert_empty targets.call('toc', :epub)
        end

        # target の表が指すファイルは、どれも stylesheets/targets/ にある
        def test_should_point_target_imports_at_existing_files
          files = [*EntryWriter::TARGET_FOUNDATION.values, *EntryWriter::TARGET_IMPORTS.values.flat_map(&:values)]
                  .flatten.uniq

          files.each { assert File.file?(File.join(STYLESHEETS, it)), "#{it} が無い" }
        end

        # テーマの tokens: は tokens 層の最後、styles: は theme 層、出力先の CSS は target 層の vs の targets/ の後に
        # 入る（theme-contract-spec.md §3.1・css-layer-restructure-spec.md §5）。土台 → 自分の順
        def test_should_import_the_theme_into_the_tokens_theme_and_target_layers
          with_theme_book do |theme|
            lines = EntryWriter.render('chapter', target: :kindle, theme:).lines.map(&:strip)
            imports = ->(layer) { lines.grep(/layer\(#{layer}\);\z/).map { it[/url\("([^"]+)"\)/, 1] } }

            assert_equal %w[../../stylesheets/tokens.css ../../stylesheets/tokens-legacy.css theme-tokens.css],
                         imports.call('tokens')
            assert_equal %w[../../stylesheets/parts/simple-header.css ../../stylesheets/parts/image-header.css
                            ../../themes/base/head.css ../../themes/mono/mono.css], imports.call('theme')
            assert_equal %w[../../stylesheets/targets/kindle-tokens.css ../../stylesheets/targets/epub.css
                            ../../stylesheets/targets/kindle.css ../../themes/base/epub.css
                            ../../themes/mono/kindle-chapter.css],
                         imports.call('target')
            assert_empty EntryWriter.render('chapter', theme:).lines.grep(/layer\(target\)/), 'PDF は target 層を読まない'
          end
        end

        # tokens: は :root の --book-* にして書き出す。空のテーマでは書かず、入口もテーマの無い入口と同じになる
        def test_should_write_the_theme_tokens_and_leave_an_empty_theme_out_of_the_entries
          with_theme_book do |theme, root|
            Dir.chdir(root) do
              FileUtils.mkdir_p(Common::CACHE_DIR)
              EntryWriter.write_theme_tokens!(theme)
              css = File.read(File.join(Common::CACHE_DIR, EntryWriter::THEME_TOKENS))

              assert_includes css, ":root {\n  --book-color-accent: #555;\n  --book-color-link: #222;\n}"

              empty = Theme.resolve('standard', root: REPO_ROOT)
              EntryWriter.write_theme_tokens!(empty)
              refute File.exist?(File.join(Common::CACHE_DIR, EntryWriter::THEME_TOKENS)), '前のビルドの残りを消す'
              EntryWriter::IMPORTS.each_key do |kind|
                [nil, :epub, :kindle].each do |target|
                  assert_equal EntryWriter.render(kind, target:, theme: nil), EntryWriter.render(kind, target:, theme: empty)
                end
              end
            end
          end
        end

        # テーマの CSS も、層を外すと 1 枚の CSS の、その層の位置に入る
        def test_should_flatten_the_theme_stylesheets_into_their_layers
          with_theme_book do |theme, root|
            Dir.chdir(root) do
              File.symlink(STYLESHEETS, 'stylesheets')
              FileUtils.mkdir_p(Common::CACHE_DIR)
              EntryWriter.write_theme_tokens!(theme)
              css = EntryWriter.render('chapter', target: :kindle, theme:)
              flat = Flattener.render(Flattener.pieces(EntryWriter.path_for('chapter'), rebase: ->(path) { path }, css:))

              assert_operator flat.index('--book-color-accent: #555'), :<, flat.index('.from-head'), 'tokens 層は theme 層の前'
              assert_operator flat.index('.from-mono'), :<, flat.index('.from-kindle-chapter'), 'theme 層は target 層の前'
            end
          end
        end

        private

        REPO_ROOT = File.expand_path('../../../..', __dir__)

        # 土台（base）と配色のテーマ（mono）を置いた本。中の CSS は、平らにした後の位置を探せる規則 1 つだけ
        def with_theme_book
          Dir.mktmpdir('vs-css-theme') do |root|
            { 'base' => [{ 'styles' => %w[head.css], 'tokens' => { 'color-accent' => '#111', 'color-link' => '#222' } },
                         %w[head.css epub.css]],
              'mono' => [{ 'extends' => 'base', 'styles' => %w[mono.css], 'tokens' => { 'color-accent' => '#555' } },
                         %w[mono.css kindle-chapter.css]] }.each do |name, (extra, files)|
              dir = File.join(root, 'themes', name)
              FileUtils.mkdir_p(dir)
              File.write(File.join(dir, 'theme.yml'), { 'name' => name, 'contract' => 1 }.merge(extra).to_yaml)
              files.each { File.write(File.join(dir, it), ".from-#{File.basename(it, '.css')} { color: red; }\n") }
            end
            yield Theme.resolve('mono', root:), root
          end
        end
      end
    end
  end
end
