# frozen_string_literal: true

# ================================================================
# Test: build/outline_extractor_test.rb
# ================================================================
# PDF のしおりのページと位置を、見出しの id の飛び先から引く（pdf-outline-heading-id-spec.md）。
#   - R1: しおりに載せる見出しへ、自分を指す空のリンクを pdf/ の写しにだけ足す
#   - R2: ページは結合した PDF の /Dests から「文書と id」で引く
#   - R3: 飛び先が無い見出しは、直前の項目（文書の先頭なら文書の始まり）のページを指す
#   - R4: しおりの項目と文字は変えない
#   - R6: pdftotext を使わない
#   - R7: 節と項は見出しの位置（:top）へ飛ぶ。章はページ全体
# PDF は Prawn（MIT）で vivliostyle と同じ形の /Dests を書いて作る。
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'prawn'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/loader'
require 'vivlio_starter/cli/pdf/provider'

module VivlioStarter
  module CLI
    module Build
      class OutlineExtractorTest < Minitest::Test
        CATALOG = <<~YAML
          PREFACE:
            - 00-preface
          CHAPTERS:
            - 11-intro
            - 12-usage
          APPENDICES:
            - 90-tools
        YAML

        HTMLS = {
          '00-preface' => '<h1 id="はじめに">はじめに</h1><h2 id="謝辞">謝辞</h2>',
          '_toc' => '<h1 id="目次">目次</h1>',
          '11-intro' => '<h1 id="入門" data-chapter-number-display="第1章">入門</h1>' \
                        '<h2 id="概要">概要</h2><h3 id="手順">手順</h3>',
          '12-usage' => '<h1 id="使い方" data-chapter-number-display="第2章">使い方</h1><h2 id="概要">概要</h2>',
          '90-tools' => '<h1 id="道具">道具</h1><h2 id="一覧">一覧</h2>'
        }.freeze

        # 節・項を article・section で囲んだ章（inject_heading_anchors! が見出しのすぐ外の要素に id を振った後の形）
        SECTIONED_HTMLS = HTMLS.merge(
          '11-intro' => '<h1 id="入門" data-chapter-number-display="第1章">入門</h1>' \
                        '<section><article id="vs-box-概要"><h2 id="概要">概要</h2></article>' \
                        '<section id="手順の節"><h3 id="手順">手順</h3></section></section>'
        ).freeze

        # [文書, id] => [ページ, 上端]。同じ id「概要」が 2 つの章にある
        DESTS = {
          %w[00-preface はじめに] => [3, 700.0], %w[00-preface 謝辞] => [4, 320.5],
          %w[_toc 目次] => [5, 700.0],
          %w[11-intro 入門] => [7, 650.0], %w[11-intro 概要] => [8, 512.25], %w[11-intro 手順] => [10, 130.0],
          %w[12-usage 使い方] => [12, 650.0], %w[12-usage 概要] => [13, 401.0],
          %w[90-tools 道具] => [15, 650.0], %w[90-tools 一覧] => [16, 600.0]
        }.freeze

        def teardown
          PostProcessCommands::HeadingProcessor.chapter_tokens_override = nil
        end

        # R2・R4・R7
        def test_should_take_pages_and_positions_from_heading_destinations
          with_book do |pdf, htmls|
            items = OutlineExtractor.heading_page_entries(pdf, htmls)

            assert_equal [
              [1, 'はじめに', 3, nil], [2, '謝辞', 4, 332.5],
              [1, '目次', 5, nil],
              [1, '第1章 入門', 7, nil], [2, '概要', 8, 524.25], [3, '手順', 10, 142.0],
              [1, '第2章 使い方', 12, nil], [2, '概要', 13, 413.0],
              [1, '付録A 道具', 15, nil], [2, '一覧', 16, 612.0]
            ], items.map { [it[:level], it[:text], it[:page], it[:top]] },
                         '本の順に並び、同じ id の「概要」も章ごとのページを指す。章はページ全体（:top なし）。節・項は飛び先の 12pt 上（HEADING_TOP_MARGIN）'
            assert_empty OutlineExtractor.last_outline_debug_info[:missing]
          end
        end

        # R3: 文書の途中の見出しは直前の項目のページを借り、:top は付けない。
        # 文書の最初の見出しは、その文書のほかの飛び先の最も前のページを借りる
        def test_should_borrow_a_page_for_headings_without_destination
          dests = DESTS.except(%w[11-intro 手順], %w[12-usage 使い方])

          with_book(dests:) do |pdf, htmls|
            items = OutlineExtractor.heading_page_entries(pdf, htmls).to_h { [[it[:chapter], it[:id]], it] }

            assert_equal 8, items[%w[11-intro 手順]][:page], '直前の「概要」と同じページ'
            assert_nil items[%w[11-intro 手順]][:top], '別の見出しの位置へは飛ばさない'
            assert_equal 13, items[%w[12-usage 使い方]][:page], '章の頭が無ければ、その章のほかの飛び先のページ'
            assert_equal [%w[11-intro 手順], %w[12-usage 使い方]],
                         OutlineExtractor.last_outline_debug_info[:missing].map { [it[:chapter], it[:id]] }
          end
        end

        # R7: 見出しの飛び先は文字の行の上端なので、節絵の帯のような文字より上の飾りが切れる。
        # 見出しのすぐ外の要素の飛び先が同じページで上にあればそちらへ飛ぶ。外の要素が前のページから
        # 始まるなら、見出しはページの頭へ送られているので、ページ全体を見せる
        def test_should_jump_to_the_enclosing_box_above_the_heading
          dests = DESTS.merge(%w[11-intro vs-box-概要] => [8, 544.5], %w[11-intro 手順の節] => [9, 300.0])

          with_book(dests:, htmls: SECTIONED_HTMLS) do |pdf, paths|
            items = OutlineExtractor.heading_page_entries(pdf, paths).to_h { [[it[:chapter], it[:id]], it] }

            assert_equal [8, 556.5], items[%w[11-intro 概要]].values_at(:page, :top), '帯の上端（article）の 12pt 上へ飛ぶ'
            assert_equal [10, nil], items[%w[11-intro 手順]].values_at(:page, :top), '外の section が前のページから始まる（見出しがページの頭へ送られた）ならページ全体'
          end
        end

        # R6: ページは PDF の飛び先から引くので、pdftotext が無くても作れる
        def test_should_not_need_pdftotext
          with_book do |pdf, htmls|
            Common.stub(:external_command_available?, false) do
              assert_equal 10, OutlineExtractor.heading_page_entries(pdf, htmls).size
            end
          end
        end

        # R7: プラグインへは :page と節・項の :top を渡す（項目の形は :level・:text・:page に :top を足すだけ）
        def test_should_pass_entries_with_top_to_the_provider
          received = nil
          provider = Object.new
          provider.define_singleton_method(:add_outline!) { |_path, entries, max_level:| received = [entries, max_level] }

          with_book do |pdf, htmls|
            VivlioStarter::Pdf.stub(:provider, provider) { OutlineExtractor.add_outline_from_headings!(pdf, htmls) }
          end

          entries, max_level = received
          assert_equal 3, max_level
          assert_equal({ level: 2, text: '概要', page: 8, top: 524.25, chapter: '11-intro', id: '概要' },
                       entries.find { it[:chapter] == '11-intro' && it[:level] == 2 })
        end

        private

        # catalog.yml・原稿・pdf/ の HTML・飛び先つきの結合 PDF を並べた一時プロジェクト
        def with_book(dests: DESTS, htmls: HTMLS)
          Dir.mktmpdir('vs-outline') do |dir|
            Dir.chdir(dir) do
              FileUtils.mkdir_p(['config', Common::CONTENTS_DIR, Common::BUILD_PDF_DIR])
              File.write('config/catalog.yml', CATALOG)
              htmls = htmls.map do |basename, body|
                File.write(File.join(Common::CONTENTS_DIR, "#{basename}.md"), "# #{basename}\n") unless basename.start_with?('_')
                File.join(Common::BUILD_PDF_DIR, "#{basename}.html").tap do
                  File.write(it, "<html><body>#{body}</body></html>")
                end
              end
              PostProcessCommands::HeadingProcessor.chapter_tokens_override = %w[11-intro 12-usage 90-tools]
              pdf = File.join(Common::BUILD_PDF_DIR, 'output.pdf')
              write_pdf_with_dests(pdf, dests)

              IndexCommands.stub(:index_enabled?, false) do
                Common.stub(:log_debug, nil) { yield pdf, htmls }
              end
            end
          end
        end

        # vivliostyle と同じ形の PDF: 文書カタログ直下の /Dests に、文書の URL と id を
        # `:XXXX` でエスケープした名前と `[ページ, /XYZ, 左端, 上端, 0]` を持つ
        def write_pdf_with_dests(path, dests)
          Prawn::Document.generate(path, page_size: [400, 600], margin: 0) do |pdf|
            pdf.text 'cover'
            19.times { pdf.start_new_page }

            store = pdf.state.store
            table = dests.to_h do |(document, id), (page, top)|
              name = "viv-id-#{escape("http://localhost:13000/vivliostyle/.cache/vs/build/pdf/#{document}.html")}" \
                     "#{escape("##{id}")}"
              [name.to_sym, [store[store.object_id_for_page(page)], :XYZ, 56.25, top, 0]]
            end
            store.root.data[:Dests] = store.ref(table)
          end
        end

        # vivliostyle の名前のエスケープ（英数字と `-` 以外を UTF-16 の 4 桁 hex に）
        def escape(text)
          text.each_char.map do |char|
            char.match?(/[A-Za-z0-9-]/) ? char : char.encode('UTF-16BE').unpack('n*').map { format(':%04x', it) }.join
          end.join
        end
      end

      # R1: pdf/ の写しに、見出しの飛び先を作る空のリンクを足す
      class HeadingAnchorsTest < Minitest::Test
        def test_should_add_a_link_for_each_heading_in_outline_targets
          within_workspace do
            write_html('11-intro', '<h1 id="入門">入門</h1><h2 id="a&quot;b">引用</h2><h3 id="手順">手順</h3><h4 id="深い">深い</h4>')
            write_html('_toc', '<h1 id="目次">目次</h1>')
            write_html('_colophon', '<h1 id="奥付">奥付</h1>')

            PdfBuilder.inject_heading_anchors!

            intro = File.read(pdf_html('11-intro'))
            links = Nokogiri::HTML(intro).css("a.#{PdfBuilder::HEADING_ANCHOR_CLASS}")
            assert_equal ['#入門', '#a"b', '#手順'], links.map { it['href'] }, 'h1〜h3 だけ。id の " は属性の中で壊れない'
            assert(links.all? { it['style'] == 'position:absolute' && it.text.empty? }, '流れから外した空のリンク')
            assert_match(/<body><a class="#{PdfBuilder::HEADING_ANCHOR_CLASS}"/o, intro, 'body の直後に置く')
            assert_includes File.read(pdf_html('_toc')), 'href="#目次"', '目次の見出しにも足す'
            refute_includes File.read(pdf_html('_colophon')), PdfBuilder::HEADING_ANCHOR_CLASS, 'しおりに載せない奥付には足さない'
          end
        end

        # 節・項の見出しのすぐ外の要素にも id を振ってリンクする。著者の id があればそれを使う。章（h1）と body は使わない
        def test_should_link_the_box_around_each_section_heading
          within_workspace do
            write_html('11-intro', '<section><h1 id="入門">入門</h1><section><article><h2 id="概要">概要</h2></article>' \
                                   '<section id="mine"><h3 id="手順">手順</h3></section></section></section>')

            PdfBuilder.inject_heading_anchors!

            doc = Nokogiri::HTML(File.read(pdf_html('11-intro')))
            assert_equal ['#入門', '#概要', '#vs-box-概要', '#手順', '#mine'],
                         doc.css("a.#{PdfBuilder::HEADING_ANCHOR_CLASS}").map { it['href'] }
            assert_equal [nil, nil, 'mine'], doc.css('section').map { it['id'] }, '章と節の section には振らない（外の要素は article）'
            assert_equal 'vs-box-概要', doc.at_css('article')['id']
          end
        end

        # 索引・用語集の見出しは id を持たないので、振ってからリンクする（振らないと、しおりが索引の頭を指したままになる）
        def test_should_give_an_id_to_headings_without_one
          within_workspace do
            write_html('_toc', '<h1>目次</h1><div class="index-section"><h2>A</h2></div><h2 id="b">B</h2>')

            PdfBuilder.inject_heading_anchors!

            doc = Nokogiri::HTML(File.read(pdf_html('_toc')))
            assert_equal %w[vs-heading-1 vs-heading-2 b], doc.css('h1, h2').map { it['id'] }
            assert_equal ['#vs-heading-1', '#vs-heading-2', '#vs-box-vs-heading-2', '#b'],
                         doc.css("a.#{PdfBuilder::HEADING_ANCHOR_CLASS}").map { it['href'] }
          end
        end

        def test_should_not_add_links_twice
          within_workspace do
            write_html('11-intro', '<h1 id="入門">入門</h1>')

            2.times { PdfBuilder.inject_heading_anchors! }

            assert_equal 1, File.read(pdf_html('11-intro')).scan(PdfBuilder::HEADING_ANCHOR_CLASS).size
          end
        end

        private

        def within_workspace
          Dir.mktmpdir('vs-heading-anchors') do |dir|
            Dir.chdir(dir) do
              FileUtils.mkdir_p([Common::CONTENTS_DIR, Common::BUILD_PDF_DIR])
              File.write(File.join(Common::CONTENTS_DIR, '11-intro.md'), "# 入門\n")
              IndexCommands.stub(:index_enabled?, false) { yield }
            end
          end
        end

        def pdf_html(basename) = File.join(Common::BUILD_PDF_DIR, "#{basename}.html")

        def write_html(basename, body) = File.write(pdf_html(basename), "<html><body>#{body}</body></html>")
      end
    end
  end
end
