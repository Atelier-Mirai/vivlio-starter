# frozen_string_literal: true

module Vivlio
  module Starter
    module CLI
      module PreProcessCommands
        module CrossReference
          # ラベルマップ構築とレポート生成を担当
          module ReportBuilder
            module_function

            # 複数章のラベルを統合し、重複チェックを行う
            def build_labels_map_with_duplicates_check(all_labels)
              labels_map = {}
              duplicates = []

              all_labels.each do |label|
                if labels_map.key?(label.id)
                  existing = labels_map[label.id]
                  duplicates << "ラベルID '@#{label.id}' が重複しています:\n" \
                                "  - #{existing.source_file}:#{existing.line}\n" \
                                "  - #{label.source_file}:#{label.line}"
                else
                  labels_map[label.id] = label
                end
              end

              { labels_map: labels_map, duplicates: duplicates }
            end

            # ID一覧レポートを生成
            def generate_cross_reference_report(all_labels)
              report = ["# Cross Reference Map\n"]

              labels_by_file = all_labels.group_by(&:source_file)

              labels_by_file.each do |file, labels|
                report << "\n- #{file}"
                labels.each do |label|
                  mode = label.auto ? 'auto' : 'manual'
                  report << "  - @#{label.id.ljust(30)} (#{label.full_number.ljust(12)}, #{mode.ljust(6)}) 「#{label.title}」"
                end
              end

              report.join("\n")
            end
          end
        end
      end
    end
  end
end
