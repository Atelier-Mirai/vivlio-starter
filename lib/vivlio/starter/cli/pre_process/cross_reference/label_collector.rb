# frozen_string_literal: true

module Vivlio
  module Starter
    module CLI
      module PreProcessCommands
        module CrossReference
          # 章からラベル定義を収集する処理を担当
          class LabelCollector
            def initialize(content:, source_file:, chapter_number:, label_class:, caption_pattern:, auto_label_ids:)
              @content = content
              @source_file = source_file
              @chapter_number = chapter_number
              @label_class = label_class
              @caption_pattern = caption_pattern
              @auto_label_ids = auto_label_ids
            end

            def collect
              lines = content.lines
              labels = []
              errors = []
              counters = { list: 0, table: 0, fig: 0 }
              in_code_block = false

              lines.each_with_index do |line, index|
                stripped = line.lstrip

                if stripped.start_with?('```') && !stripped.start_with?('```include:')
                  in_code_block = !in_code_block
                  next
                end

                next if in_code_block

                caption_info = extract_caption_label(line)
                next unless caption_info

                block_type = detect_block_type(lines, index)
                unless block_type
                  errors << "#{source_file}:#{index + 1} - キャプション行に@idがありますが、" \
                            "直後のブロックから種別（リスト/表/図）を判定できませんでした"
                  next
                end

                counters[block_type] += 1
                number = "#{chapter_number}-#{counters[block_type]}"

                label_id = if caption_info[:auto]
                             "#{block_type}-#{chapter_number}-#{counters[block_type]}"
                           else
                             caption_info[:id]
                           end

                label = label_class.new(
                  label_id,
                  block_type,
                  chapter_number,
                  number,
                  caption_info[:title],
                  source_file,
                  index + 1,
                  caption_info[:auto]
                )

                labels << label
              end

              { labels: labels, errors: errors }
            end

            private

            attr_reader :content, :source_file, :chapter_number, :label_class, :caption_pattern, :auto_label_ids

            def extract_caption_label(line)
              match = line.match(caption_pattern)
              return nil unless match

              title_with_id = match[1].strip
              label_id = match[2].strip
              auto_mode = auto_label_ids.include?(label_id)

              { title: title_with_id, id: label_id, auto: auto_mode }
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
          end
        end
      end
    end
  end
end
