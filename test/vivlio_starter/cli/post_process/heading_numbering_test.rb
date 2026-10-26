# frozen_string_literal: true

# ================================================================
# Test: post_process/heading_numbering_test.rb
# ================================================================
# 見出しの番号を振るかを page.heading_numbering で選ぶ（heading-numbering-spec.md）。
#   - chapter_and_section … 章「第1章」と節「1-1」に振る（既定・今までの紙面）
#   - chapter             … 章にだけ振る
#   - none                … 振らない（見出しに自分で番号を書く本）
# 番号は章扉・節の見出し・図表番号・@chapref・PDF のしおり・目次の CSS・EPUB の章扉に出る。
# 全巻目次は volumes_test.rb で確かめる。
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/loader'

module VivlioStarter
  module CLI
    module PostProcessCommands
      class HeadingNumberingTest < Minitest::Test
        XR = PreProcessCommands::CrossReferenceProcessor
        BSC = PreProcessCommands::BookSettingsCss

        CATALOG = <<~YAML
          CHAPTERS:
            - 01-intro
          APPENDICES:
            - 90-tools
        YAML

        def teardown
          HeadingProcessor.heading_numbering = nil
          HeadingProcessor.chapter_numbering = true
          HeadingProcessor.chapter_tokens_override = nil
        end

        # --- 章扉・節の見出し（R2・R4） ---

        def test_should_number_chapter_and_sections_by_default
          with_project do
            chapter = numbered_headings('01-intro')
            appendix = numbered_headings('90-tools')

            assert_equal '第1章', chapter.at_css('h1 .chapter-number')&.text
            assert_equal %w[1-1 1-2], chapter.css('h2 .section-number').map(&:text)
            assert_equal '付録 A', appendix.at_css('h1 .chapter-number')&.text
            assert_equal %w[A-1], appendix.css('h2 .section-number').map(&:text)
          end
        end

        def test_should_number_only_chapters_when_chapter
          HeadingProcessor.heading_numbering = 'chapter'

          with_project do
            chapter = numbered_headings('01-intro')
            appendix = numbered_headings('90-tools')

            assert_equal '第1章', chapter.at_css('h1 .chapter-number')&.text
            assert_equal '付録 A', appendix.at_css('h1 .chapter-number')&.text
            # 番号を CSS で隠すのではなく、番号の要素そのものを作らない
            assert_empty chapter.css('h2 .section-number')
            assert_empty appendix.css('h2 .section-number')
            assert_empty chapter.css('h2[data-section-number-display]')
            assert_equal %w[準備 操作], chapter.css('h2 .section-title').map(&:text), '節題の span は付ける'
          end
        end

        def test_should_number_nothing_when_none
          HeadingProcessor.heading_numbering = 'none'

          with_project do
            chapter = numbered_headings('01-intro')
            appendix = numbered_headings('90-tools')

            assert_nil chapter.at_css('h1 .chapter-number'), '「第N章」を出さない'
            assert_nil appendix.at_css('h1 .chapter-number'), '「付録 A」も出さない'
            assert_nil chapter.at_css('h1')['data-chapter-number-display']
            # 柱の章題は .chapter-title から取るので、番号が無くても題の span は付ける
            assert_equal '入門', chapter.at_css('h1 .chapter-title')&.text
            assert_empty chapter.css('h2 .section-number')
            assert_empty appendix.css('h2 .section-number')
          end
        end

        # 章が一つの配布資料（#84）は章番号を振らない。節は heading_numbering に従う（R4）
        def test_should_let_heading_numbering_decide_sections_of_single_chapter_handout
          HeadingProcessor.chapter_numbering = false

          with_project do
            assert_equal %w[1 2], numbered_headings('01-intro').css('h2 .section-number').map(&:text)

            HeadingProcessor.heading_numbering = 'chapter'
            assert_empty numbered_headings('01-intro').css('h2 .section-number')
          end
        end

        # 解釈できない値は既定で組む。警告は BookSettingsCss が 1 回だけ出すので、ここでは鳴らさない
        def test_should_fall_back_to_default_for_unknown_value_without_warning
          warned = []
          Common.stub(:log_warn, ->(msg, **) { warned << msg }) do
            HeadingProcessor.heading_numbering = 'chapters'

            assert_equal 'chapter_and_section', HeadingProcessor.heading_numbering
            assert HeadingProcessor.section_numbering?
          end
          assert_empty warned

          HeadingProcessor.heading_numbering = ' None '
          assert_equal 'none', HeadingProcessor.heading_numbering, '大文字・前後の空白は受け付ける'
        end

        # --- 図表番号と @chapref（R2） ---

        def test_should_number_figures_by_heading_numbering
          content = "# 入門\n\n** 桜 @fig-a **\n![](a.webp)\n"
          appendix = "# 道具\n\n** 道具の表 @tbl-a **\n| a |\n| - |\n| 1 |\n"

          with_project do
            HeadingProcessor.heading_numbering = 'chapter'
            assert_equal '1-1', figure_number(content, '01-intro.md', :fig), '章の番号は残るので図 1-1'

            HeadingProcessor.heading_numbering = 'none'
            assert_equal '1', figure_number(content, '01-intro.md', :fig), '章ごとに 1 から数える'
            assert_equal '1', figure_number(appendix, '90-tools.md', :table), '付録の記号（表 A-1）も外す'
          end
        end

        def test_should_omit_chapter_number_from_chapref_when_none
          with_project do
            assert_equal '第1章', XR.chapter_number_text_for('01-intro')
            assert_equal '付録 A', XR.chapter_number_text_for('90-tools')

            HeadingProcessor.heading_numbering = 'none'
            assert_nil XR.chapter_number_text_for('01-intro'), '@chapref は「章題」だけになる'
            assert_nil XR.chapter_number_text_for('90-tools')
          end
        end

        # --- PDF のしおり ---

        # しおりは、章扉に番号が無いときファイル名の番号から「第N章」を補う。none の本で補うと、
        # 見出しに自分で書いた番号と二重になる（「第1章 第1部 基礎編」）
        def test_should_not_add_numbers_to_outline_when_none
          with_project do
            assert_equal '第1章 入門', Build::OutlineExtractor.build_chapter_display_text('11-intro', heading('入門'))

            HeadingProcessor.heading_numbering = 'none'
            assert_equal '入門', Build::OutlineExtractor.build_chapter_display_text('11-intro', heading('入門'))
            assert_nil Build::OutlineExtractor.appendix_label_for_basename('90-tools'), '「付録A」も付けない'
          end
        end

        # --- 目次の番号（R3） ---

        def test_should_emit_no_toc_rule_by_default
          assert_equal '', BSC.heading_numbering_rule({ heading_numbering: 'chapter_and_section' })
          assert_equal '', BSC.heading_numbering_rule({})
        end

        def test_should_cut_toc_numbers_by_heading_numbering
          chapter = BSC.heading_numbering_rule({ heading_numbering: 'chapter' })
          none = BSC.heading_numbering_rule({ heading_numbering: 'none' })

          assert_includes chapter, '#toc .toc-section::before'
          assert_includes chapter, '#toc .toc-subsection::before', '項の番号「3-2-1」は節の番号を含む'
          refute_includes chapter, '.toc-chapter::before', '章の番号は残す'
          assert_includes chapter, 'content: none;'
          %w[.toc-chapter::before .toc-chapter-appendix::before .toc-section::before].each do
            assert_includes none, "#toc #{it}"
          end
        end

        def test_should_warn_once_and_fall_back_for_unknown_value
          warned = []
          Common.stub(:log_warn, ->(msg) { warned << msg }) do
            assert_equal '', BSC.heading_numbering_rule({ heading_numbering: 'chapters' })
          end

          assert_equal 1, warned.size
          assert_includes warned.first, 'page.heading_numbering'
          assert_includes warned.first, 'chapter_and_section / chapter / none'
          assert_includes warned.first, 'before: heading_numbering: chapters'
          assert_includes warned.first, 'after : heading_numbering: chapter_and_section'
        end

        # --- EPUB の章扉（R4） ---

        # 章扉かどうかは番号ではなく章の種類で決める。番号の無い本文の章にも合成画像を入れる
        def test_should_compose_epub_frontispiece_without_chapter_number
          Dir.mktmpdir do |dir|
            Dir.chdir(dir) do
              File.write('11-basics.html', <<~HTML)
                <!DOCTYPE html><html><head><title>基礎編</title></head><body>
                <h1 data-chapter-title="第1部　基礎編"><span class="chapter-title">第1部　基礎編</span></h1>
                <div class="chapter-lead"><p>基礎を固めます。</p></div>
                </body></html>
              HTML
              context = { frontispiece: 'x.webp', ornament: nil, font_family: 'sans-serif', flavor: :kindle }

              Build::HeadingImageComposer.stub(:render, 'FAKEJPEGBYTES') do
                Build::EpubBuilder.inject_heading_images_into_file!('11-basics.html', context)
              end

              html = File.read('11-basics.html')
              assert_includes html, 'vs-image-heading-epub'
              assert_includes html, 'alt="第1部　基礎編 基礎を固めます。"', '番号の無い alt'
            end
          end
        end

        private

        def with_project
          Dir.mktmpdir('vs-heading-numbering') do |dir|
            Dir.chdir(dir) do
              FileUtils.mkdir_p(%w[config contents])
              File.write('config/catalog.yml', CATALOG)
              File.write('contents/01-intro.md', "# 入門\n")
              File.write('contents/90-tools.md', "# 道具\n")
              HeadingProcessor.chapter_tokens_override = %w[01-intro 90-tools]
              Common.stub(:log_info, nil) { yield }
            end
          end
        end

        # 章扉・節の番号を振った後の HTML
        def numbered_headings(basename)
          body = basename == '01-intro' ? '<h1>入門</h1><h2>準備</h2><h2>操作</h2>' : '<h1>道具</h1><h2>一覧</h2>'
          path = File.expand_path("#{basename}.html")
          File.write(path, "<html><body>#{body}</body></html>")

          HeadingProcessor.inject_heading_number_spans!(path, TokenResolver::Resolver.new.resolve_file(basename))
          Nokogiri::HTML(File.read(path))
        end

        def figure_number(content, filename, type)
          XR.collect_labels(content, filename, '1')[:labels].find { it.type == type }.number
        end

        def heading(text) = { level: 1, text:, number_display: '' }
      end
    end
  end
end
