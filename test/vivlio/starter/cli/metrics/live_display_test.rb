# frozen_string_literal: true

require 'test_helper'
require 'vivlio/starter/cli/metrics/formatter'
require 'vivlio/starter/cli/metrics/live_display'

module Vivlio
  module Starter
    module CLI
      module Metrics
        class LiveDisplayTest < Minitest::Test
          Placeholder = Struct.new(:path, :title, :chapter_num, :chars)
          ChapterStub = Struct.new(:path, :chars, :sections, :warning)
          AnalysisStub = Struct.new(:chapter)

          def setup
            @formatter = FakeFormatter.new
          end

          def test_render_initial_outputs_placeholders
            placeholder = Placeholder.new('contents/01-intro.md', 'Intro', 1, 1200)
            display = build_display([placeholder])

            output = capture_io { display.render_initial }.first

            assert_includes output, '第01章 Intro'
            assert_includes output, '1,200 文字'
          end

          def test_update_analysis_replaces_placeholder_line
            placeholder = Placeholder.new('contents/01-intro.md', 'Intro', 1, 1200)
            display = build_display([placeholder])
            analysis = build_analysis('contents/01-intro.md')

            output = capture_io do
              display.render_initial
              display.update_analysis('contents/01-intro.md', analysis)
            end.first

            assert_includes output, 'LINE: contents/01-intro.md'
          end

          def test_render_final_outputs_final_lines_without_initial
            placeholder = Placeholder.new('contents/01-intro.md', 'Intro', 1, 1200)
            display = build_display([placeholder])
            analysis = build_analysis('contents/01-intro.md')

            output = capture_io { display.render_final([analysis]) }.first

            assert_includes output, 'LINE: contents/01-intro.md'
          end

          def test_render_empty_outputs_notice
            display = build_display([])

            output = capture_io { display.render_empty }.first

            assert_includes output, '対象章がありません'
          end

          private

          def build_display(placeholders)
            LiveDisplay.new(placeholders:, formatter: @formatter, show_sections: false)
          end

          def build_analysis(path)
            chapter = ChapterStub.new(path, 800, [], nil)
            AnalysisStub.new(chapter)
          end

          class FakeFormatter
            def format_chapter_line(chapter, _max_chars, _show_sections)
              "LINE: #{chapter.path}"
            end
          end
        end
      end
    end
  end
end
