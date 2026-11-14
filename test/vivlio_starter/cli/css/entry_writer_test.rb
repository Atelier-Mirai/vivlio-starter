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
          assert_includes lines, '@import url("../../stylesheets/theme.css") layer(tokens);'
          assert_includes lines, '@import url("../../stylesheets/chapter-common.css") layer(parts);'
          assert_includes lines, '@import url("../../stylesheets/chapter.css") layer(pages);'
          assert_includes lines, '@import url("../../stylesheets/pagebreak.css") layer(utilities);'
          assert_includes lines, '@import url("book-settings.css") layer(settings);'
          assert_equal '@import url("../../stylesheets/custom.css");', lines.last, 'custom.css は最後に、層の外で読む'
          assert lines.index { it.start_with?('@layer') } < lines.index { it.start_with?('@import') },
                 '層の順の宣言は @import より前'
        end

        # 本文以外のページは、土台・自分のページの CSS・設定だけを読む
        def test_should_give_generated_pages_only_the_foundation_and_their_own_css
          imports = EntryWriter.render('index').scan(/@import url\("([^"]+)"\)/).flatten

          assert_equal %w[../../stylesheets/fonts.css book-fonts.css ../../stylesheets/base.css
                          ../../stylesheets/page-settings.css ../../stylesheets/theme.css
                          ../../stylesheets/index.css book-settings.css ../../stylesheets/custom.css], imports
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
              assert_includes css, 'body.vs-kindle', 'Kindle の規則は S3 まで元のファイルのまま入る'
              assert_includes css, 'hr.pagebreak'
            end
          end
        end
      end
    end
  end
end
