# frozen_string_literal: true

require "tmpdir"

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

        def test_resolved_mode_uses_enhanced_when_plugin_is_available_in_auto_mode
          command = PdfReadCommand.new("dummy.pdf", mode: "auto")

          command.stub :plugin_available?, true do
            assert_equal(:enhanced, command.send(:resolved_mode))
          end
        end

        def test_resolved_mode_falls_back_to_standard_when_plugin_is_unavailable_in_auto_mode
          command = PdfReadCommand.new("dummy.pdf", mode: "auto")

          command.stub :plugin_available?, false do
            assert_equal(:standard, command.send(:resolved_mode))
          end
        end

        def test_convert_enhanced_writes_markdown_from_plugin_page_texts
          identity_cleaner = Object.new
          identity_cleaner.define_singleton_method(:clean) { |text| text }
          entry = Data.define(:basename).new("10-sample")
          result_payload = {
            page_texts: ["第1章 プログラミング技術習得の三要素\n本文です。", "- ii -\n続きです。"],
            page_chunks: [
              "第1章 プログラミング技術習得の三要素\n本文です。",
              "![](images/10-sample/page-002-image-01.webp)\n続きです。"
            ],
            pages: 2,
            images: [
              { page: 2, reference_path: "images/10-sample/page-002-image-01.webp" }
            ]
          }

          Dir.mktmpdir do |dir|
            @command.stub :contents_dir, dir do
              @command.stub :enhanced_result, result_payload do
                @command.stub :newline_cleaner, identity_cleaner do
                  @command.stub :pdf_read_page_separator?, true do
                    result = @command.send(:convert_enhanced, "dummy.pdf", entry)
                    markdown = File.read(result[:markdown_path], encoding: "UTF-8")

                    assert_equal(File.join(dir, "10-sample.md"), result[:markdown_path])
                    assert_equal(2, result[:pages])
                    assert_equal("第1章 プログラミング技術習得の三要素\n本文です。\n\n---\n\n![](images/10-sample/page-002-image-01.webp)\n\n続きです。\n", markdown)
                  end
                end
              end
            end
          end
        end

        def test_enhanced_command_includes_ocr_settings
          entry = Data.define(:basename).new("10-sample")

          @command.stub :pdf_read_page_separator?, false do
            @command.stub :text_area_margin_points, { top: 1.0, bottom: 2.0, inner: 3.0, outer: 4.0 } do
              @command.stub :line_merge_tolerance, 2.5 do
                @command.stub :enhanced_images_output_dir, "/tmp/images-out" do
                  @command.stub :enhanced_images_reference_dir, "images/10-sample" do
                    @command.stub :pdf_read_ocr, { mode: "always", languages: %w[jpn eng], dpi: 220, psm: 6 } do
                      command = @command.send(:enhanced_command, "dummy.pdf", entry)
                      ocr_token = command.find { it.start_with?("ocr=") }

                      refute_nil(ocr_token)
                      assert_equal(
                        { "mode" => "always", "languages" => ["jpn", "eng"], "dpi" => 220, "psm" => 6 },
                        JSON.parse(ocr_token.delete_prefix("ocr="))
                      )
                    end
                  end
                end
              end
            end
          end
        end

        def test_build_markdown_normalizes_image_reference_as_standalone_block_when_separator_disabled
          identity_cleaner = Object.new
          identity_cleaner.define_singleton_method(:clean) { |text| text }

          @command.stub :pdf_read_page_separator?, false do
            @command.stub :newline_cleaner, identity_cleaner do
              markdown = @command.send(:build_markdown, ["前文", "![](images/10-sample/page-001-image-01.webp)本文"])

              assert_equal("前文\n\n![](images/10-sample/page-001-image-01.webp)\n\n本文\n", markdown)
            end
          end
        end

        def test_normalize_image_reference_blocks_does_not_duplicate_existing_blank_lines
          markdown = "前文\n\n![](images/10-sample/page-001-image-01.webp)\n\n本文"

          assert_equal(markdown, @command.send(:normalize_image_reference_blocks, markdown))
        end

        def test_ensure_unique_output_entry_allocates_new_basename_for_existing_catalog_entry
          entry = Vivlio::Starter::CLI::TokenResolver::Entry.new(
            number: "10",
            slug: "three-elements-pages",
            kind: :chapter,
            label: "歴史篇",
            path: "contents/10-three-elements-pages.md",
            exists: true,
            in_catalog: true,
            valid: true
          )

          @command.stub :next_available_basename, "11-three-elements-pages" do
            resolved = @command.send(:ensure_unique_output_entry, entry)

            assert_equal("11-three-elements-pages", resolved.basename)
            refute(resolved.exists?)
            refute(resolved.in_catalog?)
          end
        end

        def test_ensure_unique_output_entry_allocates_new_basename_for_existing_uncatalogued_entry
          entry = Vivlio::Starter::CLI::TokenResolver::Entry.new(
            number: "10",
            slug: "three-elements-pages",
            kind: :chapter,
            label: "UNCATALOGED",
            path: "contents/10-three-elements-pages.md",
            exists: true,
            in_catalog: false,
            valid: true
          )

          @command.stub :next_available_basename, "11-three-elements-pages" do
            resolved = @command.send(:ensure_unique_output_entry, entry)

            assert_equal("11-three-elements-pages", resolved.basename)
            refute(resolved.exists?)
            refute(resolved.in_catalog?)
          end
        end

        def test_plugin_available_checks_vivlio_starter_pdf_version_command
          status = Data.define(:success?).new(true)

          Open3.stub :capture2e, ["0.1.0\n", status] do
            @command.instance_variable_set(:@plugin_checked, false)
            @command.instance_variable_set(:@plugin_available, false)

            assert_equal(true, @command.send(:plugin_available?))
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
