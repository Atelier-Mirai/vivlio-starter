# frozen_string_literal: true

require "test_helper"
require "vivlio/starter/cli/pdf/pdf_read_command"

module Vivlio
  module Starter
    module Commands
      class PdfReadCommandTest < Minitest::Test
        def setup
          @command = PdfReadCommand.new("dummy.pdf")
        end

        def test_text_area_margin_points_converts_mm_to_points
          margins_cfg = {
            top_margin: 10,
            bottom_margin: 12,
            inner_margin: 8,
            outer_margin: 6
          }

          @command.stub :pdf_read_text_area, margins_cfg do
            @command.instance_variable_set(:@text_area_margin_points, nil)
            margins = @command.send(:text_area_margin_points)

            assert_in_delta(28.346, margins[:top], 0.001)
            assert_in_delta(34.015, margins[:bottom], 0.001)
            assert_in_delta(22.677, margins[:inner], 0.001)
            assert_in_delta(17.008, margins[:outer], 0.001)
          end
        end

        def test_build_markdown_inserts_page_separator_when_enabled
          @command.stub :pdf_read_page_separator?, true do
            markdown = @command.send(:build_markdown, ["一頁目", "二頁目"])

            assert_equal("一頁目\n\n---\n\n二頁目\n", markdown)
          end
        end

        def test_build_markdown_merges_page_chunks_when_separator_disabled
          cleaner = Object.new
          cleaner.define_singleton_method(:clean) { |text| text.gsub("\n", "") }

          @command.stub :pdf_read_page_separator?, false do
            @command.stub :newline_cleaner, cleaner do
              markdown = @command.send(:build_markdown, ["基本的な理解が必要", "です。"])

              assert_equal("基本的な理解が必要です。\n", markdown)
            end
          end
        end


        def test_strip_fallback_borders_applies_bottom_margin_before_header_footer_filtering
          page = Data.define(:mediabox).new([0, 0, 100, 100])
          lines = ["第1章 サンプル", "本文1", "本文2", "脚注テキスト"]
          margins = { top: 0.0, bottom: 25.0, inner: 0.0, outer: 0.0 }

          @command.stub :text_area_margin_points, margins do
            filtered = @command.send(:strip_fallback_borders, lines, page)

            assert_equal(["第1章 サンプル", "本文1", "本文2"], filtered)
          end
        end

        def test_strip_fallback_borders_keeps_bottom_lines_on_first_page
          page = Data.define(:mediabox).new([0, 0, 100, 100])
          lines = ["第1章", "プログラミング技術習得の三要素", "比較しながら考えてみましょう。"]
          margins = { top: 0.0, bottom: 40.0, inner: 0.0, outer: 0.0 }

          @command.stub :text_area_margin_points, margins do
            filtered = @command.send(:strip_fallback_borders, lines, page, index: 0)

            assert_equal(["第1章", "プログラミング技術習得の三要素", "比較しながら考えてみましょう。"], filtered)
          end
        end

        def test_strip_fallback_borders_removes_repeated_chapter_title_header_on_later_pages
          page = Data.define(:mediabox).new([0, 0, 100, 100])
          lines = ["第1章 プログラミング技術習得の三要素", "♣ 2. ⽂法：表現のルール", "本文です。"]
          margins = { top: 0.0, bottom: 0.0, inner: 0.0, outer: 0.0 }

          @command.stub :text_area_margin_points, margins do
            filtered = @command.send(:strip_fallback_borders, lines, page, index: 1)

            assert_equal(["♣ 2. ⽂法：表現のルール", "本文です。"], filtered)
          end
        end

        def test_strip_fallback_borders_removes_numeric_pillar_when_heading_matches_first_page
          page = Data.define(:mediabox).new([0, 0, 100, 100])
          lines = ["1-1 プログラミング技術習得の三要素", "本文です。"]
          margins = { top: 0.0, bottom: 0.0, inner: 0.0, outer: 0.0 }

          @command.instance_variable_set(:@first_page_heading_tokens, ["プログラミング技術習得の三要素"])

          @command.stub :text_area_margin_points, margins do
            filtered = @command.send(:strip_fallback_borders, lines, page, index: 1)

            assert_equal(["本文です。"], filtered)
          end
        end

        def test_strip_fallback_borders_keeps_numeric_heading_when_not_matching_first_page
          page = Data.define(:mediabox).new([0, 0, 100, 100])
          lines = ["1-1 別の章タイトル", "本文です。"]
          margins = { top: 0.0, bottom: 0.0, inner: 0.0, outer: 0.0 }

          @command.instance_variable_set(:@first_page_heading_tokens, ["プログラミング技術習得の三要素"])

          @command.stub :text_area_margin_points, margins do
            filtered = @command.send(:strip_fallback_borders, lines, page, index: 1)

            assert_equal(lines, filtered)
          end
        end


        def test_newline_cleaner_uses_mecab_cleaner_without_config
          fake_cleaner_class = Class.new do
            class << self
              attr_reader :initialized_with
            end

            def initialize(*args)
              self.class.instance_variable_set(:@initialized_with, args)
            end
          end

          original_cleaner = Vivlio::Starter::PDF.const_get(:MecabNewlineCleaner)
          Vivlio::Starter::PDF.send(:remove_const, :MecabNewlineCleaner)
          Vivlio::Starter::PDF.const_set(:MecabNewlineCleaner, fake_cleaner_class)

          begin
            @command.instance_variable_set(:@newline_cleaner, nil)
            cleaner = @command.send(:newline_cleaner)

            assert_instance_of(fake_cleaner_class, cleaner)
            assert_equal([], fake_cleaner_class.initialized_with)
          ensure
            Vivlio::Starter::PDF.send(:remove_const, :MecabNewlineCleaner)
            Vivlio::Starter::PDF.const_set(:MecabNewlineCleaner, original_cleaner)
          end
        end
      end
    end
  end
end
