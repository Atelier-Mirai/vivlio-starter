# frozen_string_literal: true

# ================================================================
# File: lib/vivlio/starter/cli/build/output_helpers.rb
# ================================================================
# 責務:
#   ビルド結果の表示とタイミング情報の出力を行う。
#
# 提供機能:
#   - Dry Run 結果の表示（ビルド予定一覧）
#   - ビルドタイミングのコンソール出力
#   - アウトラインデバッグ情報の出力
#   - タイミングサマリーの JSON ファイル保存
#
# 出力形式:
#   - コンソール: 色付きの進捗表示
#   - ファイル: build_timings.json（オプション）
# ================================================================

module Vivlio
  module Starter
    module CLI
      module BuildCommands
        # ビルド結果出力ヘルパーモジュール
        module OutputHelpers
          STEP5_LABEL        = 'Step  5 (convert sections html)'.freeze
          STEP5B_LABEL       = 'Step 5b (generate part title pages)'.freeze
          STEP5_AGG_LABEL    = 'Step  5 (generate sections / part pages)'.freeze

          # ビルドタイミングをコンソールに出力する
          def print_build_timings(build_timings)
            aggregated, label_groups = aggregate_step_timings(build_timings)
            return if aggregated.empty?

            total = aggregated.map { |(_, dt)| dt }.inject(0.0, :+)
            label_width = aggregated.map { |(label, _)| label.to_s.length }.max || 0
            label_width = [label_width, 'TOTAL'.length, 34].max
            value_width = 7

            Common.echo_always "\n== Build Step Timings =="
            vs_timings = Common.consume_vivliostyle_build_timings
            vs_map = vs_timings.group_by { |entry| entry[:label].to_s }
            sub_label = '(vivliostyle build)'

            aggregated.each do |label, dt|
              raw_label = label.to_s
              value_text = format("%#{value_width}.2fs", dt)
              label_text = format("%-#{label_width}s", raw_label)
              line = "  - #{label_text} #{value_text}"
              Common.echo_always line

              original_labels = label_groups[raw_label] || [raw_label]
              entries = original_labels.flat_map { |original| vs_map[original] }.compact.flatten
              next unless entries&.any?

              value_start_idx = line.length - value_text.length
              indent = ' ' * 4

              entries.each do |entry|
                entry_value = format('(%.2fs)', entry[:duration])
                extra_spaces = calculate_extra_spaces(entry[:duration])
                target_index = value_start_idx + extra_spaces
                label_segment = format("%-#{label_width}s", sub_label)
                base_prefix = "#{indent}#{label_segment} "
                base_prefix += ' ' * (target_index - base_prefix.length) if base_prefix.length < target_index
                Common.echo_always("#{base_prefix}#{entry_value}")
              end
            end
            Common.echo_always format("  = %-#{label_width}s %#{value_width}.2fs", 'TOTAL', total)
            Common.echo_always "==========================\n"
          end

          # アウトラインデバッグ情報を出力する
          def print_outline_debug_info
            outline_info = Build::OutlineExtractor.last_outline_debug_info
            return unless outline_info && Common.current_log_level >= 3

            Common.echo_always '-- Outline Debug Info --'
            outline_info[:items].each do |item|
              next unless item[:chapter] && item[:text]

              level_tag = case item[:level].to_i
                          when 1 then 'H1'
                          when 2 then 'H2'
                          when 3 then 'H3'
                          else "H#{item[:level]}"
                          end
              Common.echo_always format('  %<ch>s / [%<tag>s] %<txt>s -> page %<pg>d',
                                        ch: item[:chapter], tag: level_tag, txt: item[:text], pg: item[:page])
            end

            chapter_ranges = outline_info[:chapter_ranges] || {}
            chapter_order  = outline_info[:chapter_order] || []
            return unless chapter_ranges.any?

            Common.echo_always '-- Chapter Ranges --'
            order = chapter_order.is_a?(Array) && !chapter_order.empty? ? chapter_order : chapter_ranges.keys.sort
            order.each do |bn|
              rng = chapter_ranges[bn]
              next unless rng

              Common.echo_always format('  %<bn>s %<s>s %<e>s', bn: bn, s: rng[0] || '-', e: rng[1] || '-')
            end
          end

          # 余白計算ヘルパー
          def calculate_extra_spaces(duration)
            return 0 if duration >= 100
            return 1 if duration >= 10

            2
          end

          # timings_summary.md にビルドタイミングを記録する
          def save_timings_to_file(build_timings)
            aggregated, label_groups = aggregate_step_timings(build_timings)
            return if aggregated.empty?

            total = aggregated.map { |(_, dt)| dt }.inject(0.0, :+)
            label_width = aggregated.map { |(label, _)| label.to_s.length }.max || 0
            label_width = [label_width, 'TOTAL'.length, 34].max
            value_width = 7

            vs_timings = Common.consume_vivliostyle_build_timings
            vs_map = vs_timings.group_by { |entry| entry[:label].to_s }
            sub_label = '(vivliostyle build)'

            ts = Time.now.iso8601
            new_block = []
            new_block << "\n## Build Step Timings (#{ts})\n"
            new_block << "````\n"
            new_block << '== Build Step Timings =='

            aggregated.each do |label, dt|
              raw_label = label.to_s
              value_text = format("%#{value_width}.2fs", dt)
              label_text = format("%-#{label_width}s", raw_label)
              line = "  - #{label_text} #{value_text}"
              new_block << line

              original_labels = label_groups[raw_label] || [raw_label]
              entries = original_labels.flat_map { |original| vs_map[original] }.compact.flatten
              next unless entries&.any?

              paren_idx = line.index('(') || line.index(raw_label.strip) || 4
              value_digit_idx = line.length - value_text.lstrip.length
              prefix_spaces = ' ' * paren_idx

              entries.each do |entry|
                entry_value = format('(%.2fs)', entry[:duration])
                label_segment = "#{prefix_spaces}#{sub_label}"
                digit_column = value_digit_idx
                target_length = [digit_column - 1, label_segment.length + 1].max
                line_segment = label_segment.ljust(target_length)
                new_block << "#{line_segment}#{entry_value}"
              end
            end
            new_block << format("  = %-#{label_width}s %#{value_width}.2fs", 'TOTAL', total)
            new_block << '```'

            path = File.join(Dir.pwd, 'timings_summary.md')
            previous = File.exist?(path) ? File.read(path, encoding: 'utf-8') : ''
            File.open(path, 'w', encoding: 'utf-8') do |f|
              f.write(new_block.join("\n"))
              f.write("\n")
              f.write(previous.to_s)
            end
          end

          def aggregate_step_timings(build_timings)
            label_groups = {}
            aggregated = []
            needs_merge = build_timings.any? { |label, _| label == STEP5_LABEL } &&
                          build_timings.any? { |label, _| label == STEP5B_LABEL }

            build_timings.each do |label, duration|
              if needs_merge && (label == STEP5_LABEL || label == STEP5B_LABEL)
                entry = aggregated.find { |(lbl, _)| lbl == STEP5_AGG_LABEL }
                if entry
                  entry[1] += duration
                else
                  aggregated << [STEP5_AGG_LABEL, duration]
                end
                label_groups[STEP5_AGG_LABEL] ||= []
                label_groups[STEP5_AGG_LABEL] << label
              else
                aggregated << [label, duration]
                label_groups[label] = [label]
              end
            end

            [aggregated, label_groups]
          end
        end
      end
    end
  end
end
