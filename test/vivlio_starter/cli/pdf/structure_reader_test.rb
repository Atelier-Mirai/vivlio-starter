# frozen_string_literal: true

require "stringio"
require "tmpdir"

require "prawn"
require "test_helper"
require "vivlio_starter/cli/pdf/structure_reader"

module VivlioStarter
  module PDF
    # タグ付き PDF を Prawn で描き、構造ツリーから Markdown が戻るかを確かめる
    # （pdf-read-structure-spec.md の経路 A）。本体のテストは AGPL の HexaPDF に頼らないので、
    # マーク付き内容（BDC … EMC）と構造ツリーは Prawn の低い層で書き込む
    class StructureReaderTest < Minitest::Test
      # Prawn の描画に MCID を付け、構造要素を作る小道具
      class TaggedPdf
        def initialize(pdf)
          @pdf = pdf
          @next_mcid = Hash.new(0)
        end

        # 文字を MCID つきのマーク付き内容で描き、その MCID を返す
        def text(string, x, y, size: 12, font: 'Helvetica')
          mcid = @next_mcid[@pdf.page_number]
          @next_mcid[@pdf.page_number] += 1
          @pdf.add_content("/Span <</MCID #{mcid}>> BDC")
          draw(string, x, y, size:, font:)
          @pdf.add_content('EMC')
          mcid
        end

        # 本文ではない印（柱など）。構造ツリーにも本文の数にも入らない
        def artifact(string, x, y)
          @pdf.add_content('/Artifact BMC')
          draw(string, x, y)
          @pdf.add_content('EMC')
        end

        # どのマークにも入れずに描く（aria-hidden にした行番号はこう描かれる）
        def untagged(string, x, y, font: 'Helvetica') = draw(string, x, y, font:)

        def element(type, *kids, **extra)
          @pdf.ref!({ Type: :StructElem, S: type, K: kids, Pg: @pdf.state.page.dictionary }.merge(extra))
        end

        def marked_content_reference(mcid) = { Type: :MCR, MCID: mcid, Pg: @pdf.state.page.dictionary }

        def new_page = @pdf.start_new_page

        def finish(kids, role_map: nil)
          tree = { Type: :StructTreeRoot, K: [element(:Document, *kids)] }
          tree[:RoleMap] = role_map if role_map
          @pdf.state.store.root.data[:StructTreeRoot] = @pdf.ref!(tree)
        end

        private

        def draw(string, x, y, size: 12, font: 'Helvetica')
          @pdf.font(font) { @pdf.draw_text(string, at: [x, y], size:) }
        end
      end

      # 見出し・段落・リスト・表を構造ツリーから戻す。語のあいだの空白は文字として描かれないので、
      # 座標の隙間から戻る
      def test_should_rebuild_markdown_from_tagged_pdf
        markdown = read_tagged_pdf do |pdf|
          [
            pdf.element(:H1, pdf.text('Chapter Title', 72, 760, size: 24)),
            pdf.element(:P, pdf.text('Hello world, this is a paragraph.', 72, 720)),
            pdf.element(:L,
                        pdf.element(:LI, pdf.element(:Lbl, pdf.text('1.', 72, 690)), pdf.text('First item', 90, 690)),
                        pdf.element(:LI, pdf.element(:Lbl, pdf.text('2.', 72, 670)), pdf.text('Second item', 90, 670))),
            pdf.element(:Table,
                        pdf.element(:TR, pdf.element(:TH, pdf.text('Name', 72, 630)), pdf.element(:TH, pdf.text('Value', 200, 630))),
                        pdf.element(:TR, pdf.element(:TD, pdf.text('alpha', 72, 610)), pdf.element(:TD, pdf.text('1', 200, 610))))
          ]
        end

        assert_equal(<<~MARKDOWN, markdown)
          # Chapter Title

          Hello world, this is a paragraph.

          1. First item
          2. Second item

          | Name | Value |
          | --- | --- |
          | alpha | 1 |
        MARKDOWN
      end

      # InDesign などの独自の型名は RoleMap で標準の型へ読み替える。MCR（MCID の参照）と
      # 2 ページ目の要素（Pg）も辿る
      def test_should_follow_role_map_and_marked_content_references
        markdown = read_tagged_pdf(role_map: { Heading1: :H1, Body: :NormalParagraphStyle, NormalParagraphStyle: :P }) do |pdf|
          heading = pdf.element(:Heading1, pdf.marked_content_reference(pdf.text('Custom Heading', 72, 760, size: 20)))
          pdf.new_page
          body = pdf.element(:Body, pdf.text('Second page body.', 72, 760))
          [heading, body]
        end

        assert_equal("# Custom Heading\n\nSecond page body.\n", markdown)
      end

      # 構造ツリーが本文のわずかしか覆っていなければ（InDesign の論文は表紙の 3 項目だけだった）、
      # 経路 A を使わない
      def test_should_not_use_structure_when_tree_covers_little_of_body
        reader = tagged_reader do |pdf|
          title = pdf.element(:H1, pdf.text('Title', 72, 760))
          20.times { pdf.untagged("Untagged body line #{it}", 72, 700 - (it * 20)) }
          [title]
        end

        assert_operator(reader.coverage, :<, 0.1)
        refute(reader.usable?)
      end

      # 柱などの Artifact は本文として数えない
      def test_should_not_count_artifacts_as_body_text
        reader = tagged_reader do |pdf|
          pdf.artifact('Running head', 72, 800)
          [pdf.element(:P, pdf.text('Body text only.', 72, 700))]
        end

        assert_in_delta(1.0, reader.coverage)
        assert(reader.usable?)
      end

      # 構造ツリーの無い PDF は、ページを読まずに覆う割合 0 と答える
      def test_should_report_no_coverage_for_untagged_pdf
        Dir.mktmpdir do |dir|
          path = File.join(dir, 'plain.pdf')
          Prawn::Document.generate(path) { it.text 'No tags here.' }
          reader = StructureReader.new(::PDF::Reader.new(path))

          assert_nil(reader.root)
          assert_in_delta(0.0, reader.coverage)
        end
      end

      # 構造ツリーの外に描かれた行番号（aria-hidden）を拾い直し、開始番号を #L で書き戻す
      def test_should_strip_line_numbers_drawn_outside_the_tree
        markdown = read_tagged_pdf do |pdf|
          pdf.untagged('28', 60, 700, font: 'Courier')
          pdf.untagged('29', 60, 686, font: 'Courier')
          caption = pdf.element(:Caption, pdf.text('lensing.rb', 90, 716))
          code = pdf.element(:Code, pdf.text('angle = 1', 90, 700, font: 'Courier'), pdf.text('  arc = 2', 90, 686, font: 'Courier'))
          [pdf.element(:Figure, caption, code)]
        end

        assert_equal("```ruby:lensing.rb#L28\nangle = 1\n  arc = 2\n```\n", markdown)
      end

      private

      def read_tagged_pdf(role_map: nil, &) = tagged_reader(role_map:, &).markdown

      def tagged_reader(role_map: nil)
        Dir.mktmpdir do |dir|
          path = File.join(dir, 'tagged.pdf')
          Prawn::Document.generate(path, page_size: 'A4', margin: 0) do |document|
            tagged = TaggedPdf.new(document)
            tagged.finish(yield(tagged), role_map:)
          end
          StructureReader.new(::PDF::Reader.new(StringIO.new(File.binread(path))))
        end
      end
    end
  end
end
