# frozen_string_literal: true

# ================================================================
# Test: css/bundle_test.rb
# ================================================================
# テスト対象:
#   Css::Bundle（出力先ごとの平らな CSS の生成。css-layer-restructure-spec.md §4.2・§4.3 の (1)）
#
# 検証内容:
#   - EPUB の束: 入口の中身は EntryWriter.render から作り、target 層を足し、
#     url() をパッケージの中の位置へ引き直す
#   - VS_CSS_FORM=flat: PDF の入口のファイルを平らな CSS で置き換え、url() を .cache/vs/ から
#     見た位置へ引き直す。余白の箱は落とさない。flat でなければ何もしない
#   - 入れ子の規則は落とし、種類をまたいで一度だけ知らせる
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'vivlio_starter/cli/css/bundle'

module VivlioStarter
  module CLI
    module Css
      class BundleTest < Minitest::Test
        def test_should_write_epub_styles_with_target_layer_and_package_urls
          with_project do
            write('stylesheets/parts/box.css', %(.box { background: url("../images/box.png"); }\n))
            write('stylesheets/targets/kindle.css', %(body.vs-kindle .box { border: 1px solid #000; }\n))
            write('stylesheets/custom.css', %(.mine { color: red; }\n))

            written = Bundle.write_epub!({ 'chapter' => [] }, target: :kindle, styles_dir: 'pkg/styles',
                                                              embed_fonts: false)
            css = File.read(written.fetch('chapter'))

            assert_includes css, 'url("../stylesheets/images/box.png")'
            assert css.index('.box {') < css.index('body.vs-kindle .box'), 'target 層は部品の後'
            assert css.index('body.vs-kindle .box') < css.index('.mine'), 'custom.css は層の外で最後'
          end
        end

        def test_should_not_add_target_layer_to_clean_epub
          with_project do
            write('stylesheets/targets/kindle.css', %(body.vs-kindle .box { border: 1px solid #000; }\n))

            written = Bundle.write_epub!({ 'chapter' => [] }, target: :epub, styles_dir: 'pkg/styles',
                                                              embed_fonts: false)

            refute_includes File.read(written.fetch('chapter')), 'vs-kindle'
          end
        end

        def test_should_replace_pdf_entries_with_flat_css_only_when_asked
          with_project do
            write('stylesheets/base/page.css', %(@page { @top-left { content: "柱"; } }\n))
            write('stylesheets/parts/box.css', %(.box { background: url("../images/box.png"); }\n))
            EntryWriter.write_all!
            layered = File.read(EntryWriter.path_for('chapter'))

            assert_empty with_env(nil) { Bundle.write_pdf_entries! }
            assert_equal layered, File.read(EntryWriter.path_for('chapter'))

            written = with_env('flat') { Bundle.write_pdf_entries! }
            css = File.read(EntryWriter.path_for('chapter'))

            assert_equal EntryWriter::IMPORTS.size, written.size
            refute_match(/@layer|@import/, css)
            assert_includes css, '@top-left', 'PDF の束では余白の箱を落とさない'
            assert_includes css, 'url("../../stylesheets/images/box.png")', '.cache/vs/ から見た位置'
          end
        end

        def test_should_warn_once_about_nested_rules
          with_project do
            write('stylesheets/custom.css', %(.box { color: red; & p { color: blue; } }\n.ok { color: green; }\n))
            warnings = []

            Common.stub(:log_warn, ->(message, **) { warnings << message }) do
              written = Bundle.write_epub!({ 'chapter' => [], 'appendix' => [] }, target: :epub,
                                                                                  styles_dir: 'pkg/styles', embed_fonts: false)

              refute_includes File.read(written.fetch('chapter')), '.box'
              assert_includes File.read(written.fetch('chapter')), '.ok { color: green; }'
            end

            assert_equal 1, warnings.size, '種類をまたいで一度だけ知らせる'
            assert_includes warnings.first, 'stylesheets/custom.css'
            assert_includes warnings.first, '入れ子'
          end
        end

        private

        def with_project
          Dir.mktmpdir('vs-css-bundle') do |root|
            Dir.chdir(root) do
              FileUtils.mkdir_p(Common::CACHE_DIR)
              File.write(File.join(Common::CACHE_DIR, EntryWriter::BOOK_SETTINGS), '')
              yield
            end
          end
        end

        def write(path, content)
          FileUtils.mkdir_p(File.dirname(path))
          File.write(path, content)
        end

        def with_env(value)
          saved = ENV.fetch(Bundle::FORM_ENV, nil)
          ENV[Bundle::FORM_ENV] = value
          yield
        ensure
          ENV[Bundle::FORM_ENV] = saved
        end
      end
    end
  end
end
