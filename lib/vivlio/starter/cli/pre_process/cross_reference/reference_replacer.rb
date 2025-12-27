# frozen_string_literal: true

require 'cgi'

module Vivlio
  module Starter
    module CLI
      module PreProcessCommands
        module CrossReference
          # 本文中の @id 参照をリンクに置換する処理を担当
          class ReferenceReplacer
            def initialize(content:, labels_map:, filename:, reserved_inline_label_ids:)
              @content = content
              @labels_map = labels_map
              @filename = filename
              @reserved_inline_label_ids = reserved_inline_label_ids
            end

            def replace
              errors = []
              in_code_block = false
              processed_lines = []

              content.lines.each_with_index do |line, idx|
                line_number = idx + 1
                stripped = line.lstrip

                if stripped.start_with?('```')
                  in_code_block = !in_code_block
                  processed_lines << line
                elsif in_code_block
                  processed_lines << line
                else
                  processed_lines << replace_in_line(line, line_number, errors)
                end
              end

              { content: processed_lines.join, errors: errors }
            end

            private

            attr_reader :content, :labels_map, :filename, :reserved_inline_label_ids

            def replace_in_line(line, line_number, errors)
              parts = line.split(/(<code[^>]*>.*?<\/code>)/)

              parts.map! do |part|
                next part if part.start_with?('<code')

                segments = part.scan(/`+[^`]*`+|[^`]+/)

                segments.map! do |segment|
                  next segment if segment.start_with?('`')

                  segment.gsub(/(?<![a-zA-Z0-9_.])@([a-zA-Z0-9_\-]+)/) do
                    label_id = ::Regexp.last_match(1)
                    replace_reference(label_id, line_number, errors)
                  end
                end

                segments.join
              end

              parts.join
            end

            def replace_reference(label_id, line_number, errors)
              return "@#{label_id}" if reserved_inline_label_ids.include?(label_id)

              label = labels_map[label_id]
              return render_link(label) if label

              errors << undefined_label_message(label_id, line_number)
              "@#{label_id}"
            end

            def render_link(label)
              anchor_id = label.id.to_s
              link_text = label.full_number.to_s
              href = begin
                src = label.source_file.to_s
                if src.empty?
                  "##{anchor_id}"
                else
                  base = File.basename(src, File.extname(src))
                  "#{base}.html##{anchor_id}"
                end
              rescue StandardError
                "##{anchor_id}"
              end

              %(<a href="#{href}" class="cross-ref-link">#{::CGI.escapeHTML(link_text)}</a>)
            end

            def undefined_label_message(label_id, line_number)
              location = if filename && line_number
                           "#{filename}:#{line_number}"
                         elsif line_number
                           "行#{line_number}"
                         else
                           '(位置情報なし)'
                         end
              "#{location} - 未定義のラベルID: @#{label_id}"
            end
          end
        end
      end
    end
  end
end
