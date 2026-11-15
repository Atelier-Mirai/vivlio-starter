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
          assert_includes lines, '@import url("../../stylesheets/parts/box.css") layer(parts);'
          assert_includes lines, '@import url("../../stylesheets/pages/chapter.css") layer(pages);'
          assert_includes lines, '@import url("../../stylesheets/utilities/pagebreak.css") layer(utilities);'
          assert_includes lines, '@import url("book-settings.css") layer(settings);'
          assert_equal '@import url("../../stylesheets/custom.css");', lines.last, 'custom.css は最後に、層の外で読む'
          assert lines.index { it.start_with?('@layer') } < lines.index { it.start_with?('@import') },
                 '層の順の宣言は @import より前'
        end

        # 本文以外のページは、土台・自分のページの CSS・設定だけを読む
        def test_should_give_generated_pages_only_the_foundation_and_their_own_css
          imports = EntryWriter.render('index').scan(/@import url\("([^"]+)"\)/).flatten

          assert_equal %w[../../stylesheets/fonts.css book-fonts.css
                          ../../stylesheets/base/reset.css ../../stylesheets/base/elements.css
                          ../../stylesheets/base/page.css ../../stylesheets/tokens.css
                          ../../stylesheets/pages/index.css book-settings.css ../../stylesheets/custom.css], imports
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

        # 扉絵を敷く @page :nth(1) は body のクラスで絞れないので、章だけが読むファイルに置く
        def test_should_keep_the_frontispiece_page_rule_out_of_non_chapter_pages
          frontispiece = /@page :nth\(1\) \{[^}]*--frontispiece-image/
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

        # 出力先の規則は target 層で、そのページの種類の分だけ読む。Kindle は EPUB の規則も読み、
        # 最後に book.yml から生成した Kindle の規則を読む（BookSettingsCss.render_kindle）
        def test_should_import_target_files_per_kind_and_target
          targets = lambda do |kind, target|
            EntryWriter.render(kind, target:).scan(/@import url\("([^"]+)"\) layer\(target\)/).flatten
          end

          assert_empty targets.call('chapter', nil), 'PDF は target 層を読まない'
          assert_equal %w[../../stylesheets/targets/epub.css], targets.call('chapter', :epub)
          assert_equal %w[../../stylesheets/targets/epub.css ../../stylesheets/targets/kindle.css
                          book-settings-kindle.css], targets.call('appendix', :kindle)
          assert_equal %w[../../stylesheets/targets/epub.css ../../stylesheets/targets/kindle.css
                          ../../stylesheets/targets/kindle-preface.css book-settings-kindle.css],
                       targets.call('postface', :kindle)
          assert_equal %w[../../stylesheets/targets/kindle-colophon.css book-settings-kindle.css],
                       targets.call('colophon', :kindle), '奥付の Kindle の規則は奥付だけが読む'
          assert_equal %w[book-settings-kindle.css], targets.call('toc', :kindle)
          assert_empty targets.call('toc', :epub)
        end

        # target の表が指すファイルは、どれも stylesheets/targets/ にある
        def test_should_point_target_imports_at_existing_files
          files = EntryWriter::TARGET_IMPORTS.values.flat_map(&:values).flatten.uniq

          files.each { assert File.file?(File.join(STYLESHEETS, it)), "#{it} が無い" }
        end
      end
    end
  end
end
