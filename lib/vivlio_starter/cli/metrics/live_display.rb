# frozen_string_literal: true

module VivlioStarter
  module CLI
    module Metrics
      # 章別分量のライブ表示を制御する
      class LiveDisplay
        Entry = Struct.new(:path, :placeholder, :analysis, keyword_init: true)

        CLEAR_LINE = "\e[2K"

        def initialize(placeholders:, formatter:, show_sections: false)
          @formatter = formatter
          @show_sections = show_sections
          @entries = placeholders.map do |placeholder|
            Entry.new(path: placeholder.path, placeholder:, analysis: nil)
          end
          @path_index = @entries.each_with_index.to_h { |entry, index| [entry.path, index] }
          @rendered = false
          @finalized = false
          @line_count = 0
          @current_lines = []
        end

        def render_initial
          return if @rendered

          @current_lines = build_lines
          @line_count = @current_lines.size
          @current_lines.each { puts it }
          @rendered = true
        end

        def update_analysis(path, analysis)
          return unless @rendered
          return if @finalized

          idx = @path_index[path]
          return unless idx

          entry = @entries[idx]
          entry.analysis = analysis
          entry.placeholder = nil
          redraw
        end

        def render_final(analyses)
          @finalized = true
          @entries = analyses.map do |analysis|
            Entry.new(path: analysis.chapter.path, placeholder: nil, analysis:)
          end
          @path_index = @entries.each_with_index.to_h { |entry, index| [entry.path, index] }

          if @entries.empty?
            render_empty
          elsif @rendered
            redraw
          else
            @current_lines = build_lines
            @line_count = @current_lines.size
            @current_lines.each { puts it }
            @rendered = true
          end
        end

        def render_empty
          clear_block if @rendered

          puts '（対象章がありません）'
          @line_count = 1
          @rendered = true
        end

        private

        attr_reader :formatter, :show_sections, :entries, :line_count

        def redraw
          return unless @rendered

          @current_lines = build_lines
          refresh_block(@current_lines)
        end

        def build_lines
          max_chars = compute_max_chars
          entries.map do |entry|
            if entry.analysis
              formatter.format_chapter_line(entry.analysis.chapter, max_chars, show_sections)
            else
              format_placeholder_line(entry.placeholder)
            end
          end
        end

        def compute_max_chars
          values = entries.map do |entry|
            if entry.analysis
              entry.analysis.chapter.chars
            elsif entry.placeholder
              entry.placeholder.chars
            else
              0
            end
          end

          values.compact.max || 1
        end

        def refresh_block(lines)
          move_cursor_up(@line_count) if @line_count.positive?
          max_lines = [@line_count, lines.size].max

          max_lines.times do |idx|
            clear_current_line
            text = lines[idx]
            puts text || ''
          end

          @line_count = lines.size
        end

        def clear_block
          move_cursor_up(@line_count) if @line_count.positive?
          @line_count.times do
            clear_current_line
            puts ''
          end
          @line_count = 0
        end

        def move_cursor_up(lines)
          return if lines <= 0

          print "\e[#{lines}A"
        end

        def clear_current_line
          print "\r"
          print CLEAR_LINE
        end

        def format_placeholder_line(placeholder)
          label = placeholder_label(placeholder)
          padded = pad_label(label)
          "#{padded} ... #{number_with_comma(placeholder.chars)} 文字"
        end

        def placeholder_label(placeholder)
          num = format('%02d', placeholder.chapter_num)
          "第#{num}章 #{placeholder.title}"
        end

        def pad_label(text)
          truncate_label(text).ljust(Formatter::CHAPTER_LABEL_WIDTH)
        end

        def truncate_label(text)
          width = Formatter::CHAPTER_LABEL_WIDTH
          return text if text.length <= width

          "#{text.each_char.take(width - 1).join}…"
        end

        def number_with_comma(num)
          num.to_s.gsub(/(\d)(?=(\d{3})+(?!\d))/, '\1,')
        end
      end
    end
  end
end
