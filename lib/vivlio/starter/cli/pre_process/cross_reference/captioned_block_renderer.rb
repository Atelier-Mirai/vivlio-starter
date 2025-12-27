# frozen_string_literal: true

require_relative '../markdown_utils'

module Vivlio
  module Starter
    module CLI
      module PreProcessCommands
        module CrossReference
          # キャプション付きブロック（図・表・コード）の HTML 変換を担当
          class CaptionedBlockRenderer
            def initialize(content:, filename:, labels_map:, caption_extractor:, chapter_number_resolver:)
              @content = content
              @filename = filename
              @labels_map = labels_map
              @caption_extractor = caption_extractor
              @chapter_number_resolver = chapter_number_resolver
            end

            def render
              lines = content.lines
              output = []
              i = 0
              in_code_block = false
              auto_counters = { list: 0, table: 0, fig: 0 }
              counters = { list: 0, table: 0, fig: 0 }

              while i < lines.size
                line = lines[i]
                stripped = line.lstrip

                if stripped.start_with?('```')
                  in_code_block = !in_code_block
                  output << line
                  i += 1
                  next
                end

                if in_code_block
                  output << line
                  i += 1
                  next
                end

                caption_info = caption_extractor.call(line)

                unless caption_info
                  handled = handle_plain_image_patterns(lines, i, output)
                  if handled
                    i = handled
                    next
                  end

                  output << line
                  i += 1
                  next
                end

                block_type = detect_block_type(lines, i)
                unless block_type
                  output << line
                  i += 1
                  next
                end

                counters[block_type] += 1

                label = resolve_label(caption_info, block_type, counters[block_type], auto_counters)

                block_start = find_block_start(lines, i)
                wrapper_class = detect_wrapper_class(lines, block_start)

                html = case block_type
                       when :fig
                         transform_figure_block(lines, block_start, caption_info, label)
                       when :table
                         transform_table_block(lines, block_start, caption_info, label, wrapper_class)
                       when :list
                         transform_list_block(caption_info, label)
                       end

                if html
                  output << html
                  i = find_block_end(lines, block_start, block_type, wrapper_class) + 1
                else
                  output << line
                  i += 1
                end
              end

              output.join
            end

            private

            attr_reader :content, :filename, :labels_map, :caption_extractor, :chapter_number_resolver

            def handle_plain_image_patterns(lines, current_index, output)
              line = lines[current_index]

              if (plain_caption_match = line.match(/^\s*\*\*(.+?)\*\*\s*$/))
                caption_text = plain_caption_match[1].strip
                j = current_index + 1
                j += 1 while j < lines.size && lines[j].strip.empty?

                if j < lines.size && lines[j].strip.match?(/^!\[[^\]]*\]\([^)]+\)(?:\{[^}]+\})?$/)
                  if (img_info = parse_markdown_image_line(lines[j].strip))
                    html = build_plain_figure_html(img_info, caption_text: caption_text)
                    output << html
                    return j + 1
                  end
                end
              end

              stripped = line.strip
              if stripped.match?(/^!\[[^\]]*\]\([^)]+\)(?:\{[^}]+\})?$/)
                if (img_info = parse_markdown_image_line(stripped))
                  html = build_plain_figure_html(img_info, caption_text: nil)
                  output << html
                  return current_index + 1
                end
              end

              nil
            end

            def detect_block_type(lines, current_index)
              (current_index + 1...lines.size).each do |i|
                line = lines[i].strip
                next if line.empty?
                next if line.match?(/^:::\{/)

                return :list if line.start_with?('```')
                return :table if line.start_with?('|') && line.count('|') > 1
                return :fig if line.start_with?('![')
                return nil
              end
              nil
            end

            def resolve_label(caption_info, block_type, counter, auto_counters)
              if caption_info[:auto]
                auto_counters[block_type] += 1
                chapter_num = chapter_number_resolver.call(filename)
                generated_id = "#{block_type}-#{chapter_num}-#{counter}"
                labels_map[generated_id]
              else
                labels_map[caption_info[:id]]
              end
            end

            def find_block_start(lines, caption_index)
              block_start = caption_index + 1
              while block_start < lines.size
                line_stripped = lines[block_start].strip
                break unless line_stripped.empty? || line_stripped.match?(/^:::\{/)
                block_start += 1
              end
              block_start
            end

            def detect_wrapper_class(lines, block_start)
              i = block_start - 1
              while i >= 0
                stripped = lines[i].strip
                break unless stripped.empty? || stripped.match?(/^:::\{/)
                if stripped.match?(/^:::\{\.([a-z\-]+)\}/)
                  return stripped.match(/^:::\{\.([a-z\-]+)\}/)[1]
                end
                i -= 1
              end
              nil
            end

            def parse_markdown_image_line(line)
              return nil unless line

              stripped = line.strip
              return nil unless stripped =~ /!\[(.*?)\]\((.*?)\)(?:\{([^}]+)\})?/

              alt = Regexp.last_match(1)
              src = Regexp.last_match(2)
              attrs = Regexp.last_match(3)

              align = nil
              width = nil
              classes = []
              if attrs
                attrs.scan(/width=(?:"|')?(\d+%)(?:"|')?/) { |w| width ||= w[0] }
                attrs.scan(/align=(?:"|')?(left|center|right)(?:"|')?/) { |a| align ||= a[0] }
                attrs.scan(/\.([a-z\-]+)/) { |c| classes << c[0] }
              end

              { alt: alt.to_s, src: src.to_s, align: align, width: width, classes: classes }
            end

            def build_plain_figure_html(img_info, caption_text: nil)
              figure_style_parts = []
              figure_style_parts << "width: #{img_info[:width]}" if img_info[:width]
              figure_style_attr = figure_style_parts.any? ? " style=\"#{figure_style_parts.join('; ')}\"" : ''

              img_tag = "<img src=\"#{img_info[:src]}\" alt=\"#{img_info[:alt]}\">"

              figure_classes = []
              case img_info[:align]
              when 'center' then figure_classes << 'align-center'
              when 'right' then figure_classes << 'align-right'
              when 'left' then figure_classes << 'align-left'
              end
              class_attr = figure_classes.any? ? " class=\"#{figure_classes.join(' ')}\"" : ''

              html = []
              html << "<figure#{class_attr}#{figure_style_attr}>"
              html << "  #{img_tag}"
              html << "  <figcaption>#{caption_text}</figcaption>" if caption_text
              html << '</figure>'
              html << ''
              html.join("\n")
            end

            def transform_figure_block(lines, block_start, caption_info, label)
              img_line = lines[block_start].strip
              img_info = parse_markdown_image_line(img_line)
              align_value = img_info && img_info[:align]

              figure_style_attr = ''
              img_html = if img_info
                           figure_style_parts = []
                           figure_style_parts << "width: #{img_info[:width]}" if img_info[:width]
                           figure_style_attr = figure_style_parts.any? ? " style=\"#{figure_style_parts.join('; ')}\"" : ''
                           "<img src=\"#{img_info[:src]}\" alt=\"#{img_info[:alt]}\">"
                         else
                           img_line
                         end

              caption_text = label ? "#{label.full_number}: #{caption_info[:title]}" : caption_info[:title]

              html = []
              figure_classes = []
              case align_value
              when 'center' then figure_classes << 'align-center'
              when 'right' then figure_classes << 'align-right'
              when 'left' then figure_classes << 'align-left'
              end
              id_attr = label ? " id=\"#{label.id}\"" : ''
              class_attr = figure_classes.any? ? " class=\"#{figure_classes.join(' ')}\"" : ''
              html << "<figure#{id_attr}#{class_attr}#{figure_style_attr}>"
              html << "  #{img_html}"
              html << "  <figcaption>#{caption_text}</figcaption>"
              html << '</figure>'
              html << ''
              html.join("\n")
            end

            def transform_table_block(lines, block_start, caption_info, label, wrapper_class)
              table_lines = []
              i = block_start
              while i < lines.size
                line = lines[i]
                break if line.strip.empty? || !line.include?('|')

                table_lines << line
                i += 1
              end

              table_md = table_lines.join
              table_html = MarkdownUtils.render_markdown_to_html(table_md).strip

              auto_long_table = begin
                header_line = table_lines.first.to_s
                pipe_count = header_line.count('|')
                pipe_count >= 8
              rescue StandardError
                false
              end

              caption_text = label ? "#{label.full_number}: #{caption_info[:title]}" : caption_info[:title]

              html = []
              id_attr = label ? " id=\"#{label.id}\"" : ''
              classes = ['cross-ref-table']
              classes << 'long-table' if wrapper_class == 'long-table' || auto_long_table
              html << "<div#{id_attr} class=\"#{classes.join(' ')}\">"
              html << "  <p class=\"table-caption\">#{caption_text}</p>"
              html << "  #{table_html}"
              html << '</div>'
              html << ''
              html.join("\n")
            end

            def transform_list_block(caption_info, label)
              caption_text = label ? "#{label.full_number}: #{caption_info[:title]}" : caption_info[:title]
              data_id = (label && label.id) || caption_info[:id]
              ["**#{caption_text}**\n", "<!--xref:#{data_id}-->\n"].join
            end

            def find_block_end(lines, start_index, block_type, wrapper_class)
              end_index = case block_type
                          when :fig
                            start_index
                          when :table
                            i = start_index
                            i += 1 while i < lines.size && lines[i].include?('|')
                            i - 1
                          when :list
                            i = start_index + 1
                            while i < lines.size
                              break if lines[i].strip.start_with?('```')
                              i += 1
                            end
                            i
                          else
                            start_index
                          end

              if wrapper_class
                i = end_index + 1
                while i < lines.size
                  return i if lines[i].strip == ':::'

                  i += 1
                end
              end

              end_index
            end
          end
        end
      end
    end
  end
end
