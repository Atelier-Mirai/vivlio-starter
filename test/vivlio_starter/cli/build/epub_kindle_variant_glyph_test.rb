# frozen_string_literal: true

# ================================================================
# Test: build/epub_kindle_variant_glyph_test.rb
# ================================================================
# テスト対象:
#   Build::EpubBuilder.apply_variant_glyph_fonts_for_kindle!（kindle-ivs-font-spec.md §2・§4）
#   と、それが書いた @font-face を sanitize_epub_css! が残すこと。
#
# 検証方法:
#   一時プロジェクトの stylesheets/fonts/ に同梱の Noto をリンクで置き、Kindle 消費者 dir
#   相当の HTML と book-settings.css を書き換えさせる。同梱書体が無い環境では skip する。
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'nokogiri'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/build'
require 'vivlio_starter/cli/epub'

module VivlioStarter
  module CLI
    class EpubKindleVariantGlyphTest < Minitest::Test
      Builder = Build::EpubBuilder
      LOG_METHODS = %i[log_info log_success log_warn log_error log_action log_summary].freeze

      FONTS_ROOT = File.expand_path('../../../../stylesheets/fonts', __dir__)
      BUNDLED = {
        'Noto_Serif_JP' => %w[NotoSerifJP-Regular.ttf NotoSerifJP-Bold.ttf],
        'Noto_Sans_JP' => %w[NotoSansJP-Regular.ttf NotoSansJP-Bold.ttf]
      }.freeze

      def setup
        skip '同梱書体が無い環境では検証できない' unless bundled_fonts_present?

        @warnings = []
        @saved_logs = LOG_METHODS.to_h { [it, Common.method(it)] }
        LOG_METHODS.each { |name| Common.define_singleton_method(name) { |*, **| } }
        warnings = @warnings
        Common.define_singleton_method(:log_warn) { |message, *, **| warnings << message }
      end

      def teardown
        @saved_logs&.each { |name, m| Common.define_singleton_method(name, m) }
      end

      # 本文の字はセレクタを外した親字＋span になり、属性と <title> のセレクタは残る。
      def test_should_wrap_variant_characters_in_text_and_leave_attributes_alone
        html = <<~HTML
          <html><head><title>禰\u{E0100}</title></head><body>
          <h3 id="禰\u{E0100}" data-heading="禰\u{E0100}"><span class="subsection-title">禰 禰\u{E0100}</span></h3>
          <p>竈門禰\u{E0100}豆子<img src="a.jpg" alt="禰\u{E0100}"></p>
          </body></html>
        HTML

        with_kindle_dir(html) do |dir, path|
          Builder.apply_variant_glyph_fonts_for_kindle!([path], dir)
          doc = Nokogiri::HTML5(File.read(path, encoding: 'utf-8'))

          assert_equal %w[禰 禰], doc.css('span.vs-variant-1').map(&:text)
          assert_equal '竈門禰豆子', doc.at_css('p').text, '親字だけが残り、検索で「禰」が当たる'
          assert_equal "禰\u{E0100}", doc.at_css('h3')['id'], 'アンカーの id は変えない'
          assert_equal "禰\u{E0100}", doc.at_css('h3')['data-heading']
          assert_equal "禰\u{E0100}", doc.at_css('img')['alt'], '読み上げ用の alt も変えない'
          assert_equal "禰\u{E0100}", doc.at_css('title').text
        end
      end

      # 本文用と見出し用の書体を書き、見出しの中には見出し用（無ければ本文用）を当てる CSS を足す。
      def test_should_write_fonts_and_css_for_body_and_headings
        with_kindle_dir("<html><body><p>禰\u{E0100}</p></body></html>") do |dir, path|
          Builder.apply_variant_glyph_fonts_for_kindle!([path], dir)
          css = File.read(File.join(dir, 'book-settings.css'))

          assert_equal %w[vs-variant-1-bold.ttf vs-variant-1-heading-bold.ttf vs-variant-1-heading.ttf vs-variant-1.ttf],
                       Dir.children(File.join(dir, 'fonts')).sort
          assert_includes css, 'body { color: black; }', '既存の規則は残す'
          assert_includes css, '@font-face { font-family: "vs-variant-1"; font-weight: 700; src: url("fonts/vs-variant-1-bold.ttf"); }'
          assert_includes css, '.vs-variant-1 { font-family: "vs-variant-1"; }'
          assert_includes css, 'h3 .vs-variant-1'
          assert_includes css, 'font-family: "vs-variant-1-heading", "vs-variant-1";'
          refute_includes css, ':is(', 'KFX は :is() を解さない'
        end
      end

      # 同じ親字の異体が 2 つ出たときだけ書体が 2 本に分かれる。
      def test_should_use_a_second_font_when_the_same_base_has_two_variants
        with_kindle_dir("<html><body><p>邉\u{E0101}と邉\u{E0102}と禰\u{E0100}</p></body></html>") do |dir, path|
          Builder.apply_variant_glyph_fonts_for_kindle!([path], dir)
          doc = Nokogiri::HTML5(File.read(path, encoding: 'utf-8'))

          assert_equal %w[vs-variant-1 vs-variant-2 vs-variant-1], doc.css('p span').map { it['class'] }
          assert File.file?(File.join(dir, 'fonts', 'vs-variant-2.ttf'))
        end
      end

      # 組が無い本では何も書かない（書体も CSS も HTML も変わらない）。
      def test_should_leave_a_book_without_variation_sequences_untouched
        html = "<html><body><p>禰と邉</p></body></html>"

        with_kindle_dir(html) do |dir, path|
          css_before = File.read(File.join(dir, 'book-settings.css'))
          Builder.apply_variant_glyph_fonts_for_kindle!([path], dir)

          assert_equal html, File.read(path, encoding: 'utf-8')
          assert_equal css_before, File.read(File.join(dir, 'book-settings.css'))
          refute Dir.exist?(File.join(dir, 'fonts'))
        end
      end

      # 書体に字形が無い組は、出現箇所つきで 1 回だけ知らせる。既定の組（親字の形が正しい）は
      # 知らせも書き換えもしない。
      def test_should_warn_once_about_sequences_the_font_does_not_have
        html = "<html><body><p>渡邉\u{E010F}さん</p><p>邉\u{E010F}</p><p>禰\u{E0101}</p></body></html>"

        with_kindle_dir(html) do |dir, path|
          Builder.apply_variant_glyph_fonts_for_kindle!([path], dir)

          assert_equal 1, @warnings.count { it.include?('異体字の字形が書体にない') }
          assert(@warnings.any? { it.include?('U+9089 U+E010F') && it.include?('11-sample.html「渡邉') && it.include?('ほか 1 か所') })
          assert(@warnings.any? { it.include?('Noto Serif JP') })
          refute(@warnings.any? { it.include?('U+E0101') }, '既定の組は知らせない')
          assert_equal html, File.read(path, encoding: 'utf-8'), '置き換える組が無ければ HTML は変わらない'
        end
      end

      # 非埋め込みのサニタイズは、異体字の書体の @font-face を残す。消すと実体だけ残り親字に戻る。
      def test_should_keep_variant_font_faces_through_css_sanitizing
        css = <<~CSS
          @font-face { font-family: "Noto Serif JP"; src: url("fonts/NotoSerifJP-Regular.ttf"); }
          @font-face { font-family: "vs-variant-1"; font-weight: 400; src: url("fonts/vs-variant-1.ttf"); }
          .vs-variant-1 { font-family: "vs-variant-1"; }
        CSS

        Dir.mktmpdir('vs-variant-sanitize') do |dir|
          epub = build_epub(dir, 'EPUB/book-settings.css' => css)
          Builder.sanitize_epub_css!(epub, flavor: :kindle)
          result = read_from_epub(epub, 'EPUB/book-settings.css')

          refute_includes result, 'Noto Serif JP', '同梱しない書体の @font-face は従来どおり消す'
          assert_includes result, 'font-family: "vs-variant-1"; font-weight: 400'
        end
      end

      # クリーン EPUB は異体字セレクタのまま運ぶ（Apple Books などは OS の書体で正しく出る）。
      def test_should_not_touch_the_clean_epub
        Dir.mktmpdir('vs-variant-clean') do |dir|
          path = File.join(dir, '11-sample.html')
          File.write(path, "<html><body><p>禰\u{E0100}</p></body></html>", encoding: 'utf-8')

          Builder.stub(:collect_epub_htmls, ->(_base, _entries) { [path] }) do
            Builder.stub(:inject_heading_images_for_epub!, ->(files, **) { files }) do
              Builder.generate_epub_entries!(dir, [], flavor: :epub)
            end
          end

          refute_includes File.read(path, encoding: 'utf-8'), 'vs-variant-'
          refute Dir.exist?(File.join(dir, 'fonts'))
        end
      end

      private

      def bundled_fonts_present?
        BUNDLED.all? { |slug, files| files.all? { File.file?(File.join(FONTS_ROOT, slug, it)) } }
      end

      # 同梱の Noto をリンクで置いた一時プロジェクトに、Kindle 消費者 dir を作ってブロックへ渡す。
      def with_kindle_dir(html)
        original_config = Common::CONFIG
        Dir.mktmpdir('vs-variant-glyph') do |root|
          Dir.chdir(root) do
            BUNDLED.each do |slug, files|
              FileUtils.mkdir_p(File.join('stylesheets', 'fonts', slug))
              files.each { FileUtils.ln_s(File.join(FONTS_ROOT, slug, it), File.join('stylesheets', 'fonts', slug, it)) }
            end
            Common.install_configuration!(
              Common.build_direct_configuration(
                typography: { body: { font: 'Noto Serif JP' }, heading: { font: 'Noto Sans JP' } }
              )
            )

            dir = File.join(root, 'kindle')
            FileUtils.mkdir_p(dir)
            File.write(File.join(dir, 'book-settings.css'), "body { color: black; }\n")
            path = File.join(dir, '11-sample.html')
            File.write(path, html, encoding: 'utf-8')
            yield dir, path
          end
        end
      ensure
        Common.install_configuration!(original_config)
      end

      def build_epub(dir, files)
        staging = File.join(dir, 'staging')
        files.each do |rel, content|
          FileUtils.mkdir_p(File.join(staging, File.dirname(rel)))
          File.write(File.join(staging, rel), content)
        end
        epub = File.join(dir, 'book.epub')
        system('zip', '-qr', epub, '.', chdir: staging)
        epub
      end

      def read_from_epub(epub, member)
        IO.popen(['unzip', '-p', epub, member], &:read).force_encoding('UTF-8')
      end
    end
  end
end
