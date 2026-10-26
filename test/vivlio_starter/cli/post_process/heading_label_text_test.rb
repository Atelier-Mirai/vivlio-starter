# frozen_string_literal: true

# ================================================================
# Test: post_process/heading_label_text_test.rb
# ================================================================
# 見出しの題の data 属性（PDF のしおりの題・EPUB の合成見出し画像の素材）に、
# 数式を文字で入れる（改善案 #119）。数式は前処理で <img class="vs-math" alt="$…$"> になり、
# 素の text では抜けて、前後の改行と字下げが残っていた。
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/loader'

module VivlioStarter
  module CLI
    module PostProcessCommands
      class HeadingLabelTextTest < Minitest::Test
        # 数式の画像は、実際の HTML と同じく手前に整形の改行と字下げを持たせる。原稿に書いた空白は
        # その改行より前に残る（「を␣⏎」）。行末の空白は消されやすいので、\n で書く
        INDENT = "\n            "
        HTML = [
          '<html><body>',
          '<h1>ブール代数 <img class="vs-math vs-math-inline" src="images/math/01-intro/a.svg" alt="$x^2 = x$"></h1>',
          "<h2>1.2 円周率を #{INDENT}<img class=\"vs-math vs-math-inline\" src=\"images/math/01-intro/b.svg\" " \
          "alt=\"$\\arctan$\"> の値として書く\n          </h2>",
          '<h3>第1部　基礎編</h3>',
          "<h3>補題 1：#{INDENT}<img class=\"vs-math vs-math-inline\" src=\"images/math/01-intro/c.svg\" alt=\"$G(0)$\"> と " \
          "#{INDENT}<img class=\"vs-math vs-math-inline\" src=\"images/math/01-intro/d.svg\" alt=\"$G(1)$\"> は整数</h3>",
          '</body></html>'
        ].join("\n")

        def teardown
          HeadingProcessor.chapter_tokens_override = nil
        end

        def test_should_write_formulas_as_text_in_heading_data_attributes
          with_chapter do |path|
            doc = Nokogiri::HTML(File.read(path))
            h1, h2, h3, lemma = doc.css('h1, h2, h3').to_a

            assert_equal 'ブール代数 x²=x', h1['data-heading']
            assert_equal 'ブール代数 x²=x', h1['data-chapter-title']
            assert_equal '1.2 円周率を arctan の値として書く', h2['data-h2'], '改行と字下げは 1 つの空白に詰める'
            assert_equal '1.2 円周率を arctan の値として書く', h2['data-section-title']
            assert_equal '第1部　基礎編', h3['data-subsection-title'], '全角空白は題の一部なので詰めない'
            assert_equal '補題 1：G(0) と G(1) は整数', lemma['data-subsection-title'],
                         '画像の手前の整形の改行は消し、原稿に書いた空白は残す（spiral-ruby の補遺 A.3 の形）'
            assert_equal 'ブール代数', h1['id'], 'h1 の id は今までどおり素の文字から作る'
            assert_equal 1, h2.css('img.vs-math').size, '紙面の見出しの数式の画像は残す'
          end
        end

        # 2 回目に走らせても、題の span を組み直さない（題の比べ方は素の文字のまま）
        def test_should_not_rebuild_headings_on_a_second_run
          with_chapter do |path|
            before = File.read(path)
            entry = TokenResolver::Resolver.new.resolve_file('01-intro')

            refute HeadingProcessor.inject_heading_number_spans!(path, entry), '組み直しは起きない'
            assert_equal before, File.read(path)
          end
        end

        # EPUB の目次（nav）は各章の <title> から作られる。VFM が見出しから作った <title> には
        # 用語集の印 † が入っていた（spiral-ruby の「第2部　オブジェクト指向†編」）
        def test_should_drop_glossary_marks_from_the_document_title
          html = '<html><head><title>第2部　オブジェクト指向†編</title></head><body>' \
                 '<h1>第2部　オブジェクト指向<a id="g" class="glossary-link" href="_glossarypage.html#gls-a"><sup>†</sup></a>編</h1>' \
                 '</body></html>'

          assert_equal '第2部　オブジェクト指向編', title_after_markers(html)
        end

        # 著者が frontmatter に書いた title（見出しと違う文字）は触らない
        def test_should_keep_a_title_the_author_wrote
          html = '<html><head><title>著者の題</title></head><body>' \
                 '<h1>第2部　オブジェクト指向<a class="glossary-link"><sup>†</sup></a>編</h1></body></html>'

          assert_equal '著者の題', title_after_markers(html)
        end

        private

        def title_after_markers(html)
          Dir.mktmpdir('vs-heading-title') do |dir|
            path = File.join(dir, '12-object-oriented.html')
            File.write(path, html)
            Common.stub(:log_info, nil) { HeadingProcessor.inject_heading_markers!([path], max_level: 3) }
            Nokogiri::HTML(File.read(path)).at_css('title').text
          end
        end

        def with_chapter
          Dir.mktmpdir('vs-heading-label') do |dir|
            Dir.chdir(dir) do
              FileUtils.mkdir_p(%w[config contents])
              File.write('config/catalog.yml', "CHAPTERS:\n  - 01-intro\n")
              File.write('contents/01-intro.md', "# 入門\n")
              HeadingProcessor.chapter_tokens_override = %w[01-intro]
              path = File.expand_path('01-intro.html')
              File.write(path, HTML)
              Common.stub(:log_info, nil) do
                HeadingProcessor.inject_heading_markers!([path], max_level: 3)
                HeadingProcessor.inject_heading_number_spans!(path, TokenResolver::Resolver.new.resolve_file('01-intro'))
                yield path
              end
            end
          end
        end
      end
    end
  end
end
