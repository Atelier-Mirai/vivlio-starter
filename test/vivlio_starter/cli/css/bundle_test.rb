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
            css = File.read(written.fetch('chapter').dest)

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

            refute_includes File.read(written.fetch('chapter').dest), 'vs-kindle'
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

        # 著者の custom.css の入れ子は正当な CSS なので、開いて EPUB と Kindle に届け、著者には何も知らせない
        # （Kindle は入れ子の中の宣言を捨てる。kindle-css-compatibility-notes.md §2）
        def test_should_unfold_nested_rules_for_epub_and_kindle_without_warning
          with_project do
            write('stylesheets/custom.css', %(.box { color: red; & p { color: blue; } }\n.ok { color: green; }\n))
            warnings = []

            Common.stub(:log_warn, ->(message, **) { warnings << message }) do
              %i[epub kindle].each do |target|
                written = Bundle.write_epub!({ 'chapter' => [] }, target:, styles_dir: "pkg-#{target}/styles", embed_fonts: false)
                css = File.read(written.fetch('chapter').dest)

                assert_includes css, '.box p {', target.to_s
                refute_includes css, '&', target.to_s
                assert_includes css, '.ok {', target.to_s
              end
            end

            assert_empty warnings
          end
        end

        # --log=debug のとき、書き換え後の HTML で要素ごとの判定を行い、組を一覧にする。
        # Kindle の規則（target 層）が body.vs-kindle の印の付いた HTML で当たること
        def test_should_report_inversions_on_rewritten_html_only_in_debug
          with_project do
            write('stylesheets/parts/box.css', %(div.box p { text-align: center; }\n))
            write('stylesheets/targets/kindle.css', %(.vs-kindle p { text-align: right; }\n))
            write('chapter.html', '<html><body class="vs-epub vs-kindle"><div class="box"><p>本文</p></div></body></html>')
            sheets = Bundle.write_epub!({ 'chapter' => ['chapter.html'] }, target: :kindle, styles_dir: 'pkg/styles',
                                                                           embed_fonts: false)
                           .transform_keys { "styles/#{it}.css" }
            html_sheets = { 'chapter.html' => ['styles/chapter.css'] }
            messages = []

            Common.stub(:log_debug, ->(message, **) { messages << message }) do
              Bundle.report_epub_inversions!(sheets, html_sheets, target: :kindle)
              assert_empty messages, 'debug でなければ何もしない'

              Common.stub(:current_log_level, Common::LEVELS['debug']) do
                Bundle.report_epub_inversions!(sheets, html_sheets, target: :kindle)
              end
            end

            assert_includes messages, '[css] chapter（kindle）: 層を外すと勝ち負けが変わる組 1'
            assert(messages.any? { it.include?('.vs-kindle p { text-align: right }') && it.include?('div.box p') })
          end
        end

        # custom.css の宣言が平らな CSS で vs の規則に負けるときだけ、書いた CSS を !important 付きで書き直す
        # （css-layer-restructure-spec.md §7.1）。負けない本では CSS を書き直さない
        def test_should_rewrite_flat_css_so_that_custom_css_wins
          with_project do
            write('stylesheets/parts/heading.css', %(body.simple h2 { margin-top: 0; }\n))
            write('stylesheets/custom.css', %(/* h2 { color: red; } は例 */\n\nh2 {\n  margin-top: 2em;\n}\n))
            write('chapter.html', '<html><body class="simple"><h2>見出し</h2></body></html>')
            sheets = Bundle.write_epub!({ 'chapter' => ['chapter.html'] }, target: :epub, styles_dir: 'pkg/styles',
                                                                           embed_fonts: false)
                           .transform_keys { "styles/#{it}.css" }

            updated = Bundle.prioritize_author_css!(sheets, { 'chapter.html' => ['styles/chapter.css'] }, target: :epub)

            assert_includes File.read('pkg/styles/chapter.css'), 'margin-top: 2em !important;'
            assert_includes updated.fetch('styles/chapter.css').pieces.last.text, '2em !important'
          end
        end

        def test_should_keep_flat_css_when_custom_css_does_not_lose
          with_project do
            write('stylesheets/parts/heading.css', %(h2 { margin-top: 0; }\n))
            write('stylesheets/custom.css', %(h2 { margin-top: 2em; }\n))
            write('chapter.html', '<html><body class="simple"><h2>見出し</h2></body></html>')
            sheets = Bundle.write_epub!({ 'chapter' => ['chapter.html'] }, target: :epub, styles_dir: 'pkg/styles',
                                                                           embed_fonts: false)
                           .transform_keys { "styles/#{it}.css" }
            before = File.read('pkg/styles/chapter.css')

            Bundle.prioritize_author_css!(sheets, { 'chapter.html' => ['styles/chapter.css'] }, target: :epub)

            assert_equal before, File.read('pkg/styles/chapter.css')
          end
        end

        # 付けられない宣言は、custom.css の行と、取り合う原稿の要素を示して知らせる。vs の選択子は見せない
        def test_should_warn_about_custom_css_that_cannot_win_with_its_place
          with_project do
            write('stylesheets/parts/heading.css', %(body.s h2.t { color: green; }\n))
            write('stylesheets/custom.css', %(/* h2.t { color: red } は例 */\n.x h2 { color: blue !important; }\n) +
                                            %(h2.t { color: red; }\n))
            write('contents/10-intro.md', "# 序章\n")
            write('10-intro.html', '<html><body class="s"><h2 class="t">一</h2>' \
                                   '<div class="x"><h2 class="t">二</h2></div></body></html>')
            sheets = Bundle.write_epub!({ 'chapter' => ['10-intro.html'] }, target: :kindle, styles_dir: 'pkg/styles',
                                                                            embed_fonts: false)
                           .transform_keys { "styles/#{it}.css" }
            warnings = []

            Common.stub(:log_warn, ->(message, detail: []) { warnings << [message, detail] }) do
              Bundle.prioritize_author_css!(sheets, { '10-intro.html' => ['styles/chapter.css'] }, target: :kindle)
            end

            assert_equal 1, warnings.size
            message, detail = warnings.first
            assert_equal 'stylesheets/custom.css（3 行目）の「h2.t { color: red }」は Kindle では効きません', message
            assert_includes detail.first, 'contents/10-intro.md の <h2 class="t">'
            assert_includes detail.first, '「.x h2 { color: blue !important }」'
            refute(detail.any? { it.include?('body.s') }, 'vs の選択子は見せない')
            refute_includes File.read('pkg/styles/chapter.css'), 'color: red !important'
          end
        end

        # style 属性に !important を付けた HTML は書き直す（style 属性が PDF と同じく勝つ）
        def test_should_rewrite_html_whose_style_attribute_is_kept_winning
          with_project do
            write('stylesheets/parts/figure.css', %(.figure img { width: 100%; }\n))
            write('stylesheets/custom.css', %(img { width: 50%; }\n))
            write('10-intro.html', '<html><body><div class="figure"><img src="a.png"></div>' \
                                   '<img src="b.png" style="width: 10px"></body></html>')
            sheets = Bundle.write_epub!({ 'chapter' => ['10-intro.html'] }, target: :kindle, styles_dir: 'pkg/styles',
                                                                            embed_fonts: false)
                           .transform_keys { "styles/#{it}.css" }

            Bundle.prioritize_author_css!(sheets, { '10-intro.html' => ['styles/chapter.css'] }, target: :kindle)

            assert_includes File.read('pkg/styles/chapter.css'), 'width: 50% !important;'
            assert_includes File.read('10-intro.html'), 'style="width: 10px !important;"'
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
