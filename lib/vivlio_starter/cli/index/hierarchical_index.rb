# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/index/hierarchical_index.rb
# ================================================================
# 責務:
#   階層化索引の構築と同一ページ重複排除を行う。
#
# Phase 3 機能:
#   - 親子関係のある索引項目（例: HTML → HTML要素、HTMLタグ）
#   - 同一ページ内の重複リンクを排除
#   - ページ範囲の表示（例: 10-12）
# ================================================================

require_relative '../common'

module VivlioStarter
  module CLI
    module IndexCommands
      # 階層化索引ビルダー
      class HierarchicalIndex
        attr_reader :entries, :hierarchy

        def initialize
          @entries = Hash.new { |h, k| h[k] = [] }
          @hierarchy = Hash.new { |h, k| h[k] = Set[] }
        end

        # エントリを追加
        # @param term [String] 用語
        # @param link [String] リンク先
        # @param parent [String, nil] 親用語（階層化用）
        def add_entry(term, link, parent: nil)
          @entries[term] << link
          @hierarchy[parent] << term if parent
        end

        # 同一ページの重複を排除
        # HTMLファイル名が同じリンクをまとめる
        def deduplicate_same_page!
          @entries.each do |term, links|
            # ファイル名ごとにグループ化
            grouped = links.group_by { |link| link.split('#').first }

            # 各ファイルの最初のリンクのみを保持
            @entries[term] = grouped.map { |_, group| group.first }
          end
        end

        # ページ範囲を計算（連続ページをまとめる）
        # @param page_numbers [Array<Integer>] ページ番号の配列
        # @return [Array<String>] 範囲表記の配列（例: ["10-12", "15", "20-22"]）
        def calculate_page_ranges(page_numbers)
          return [] if page_numbers.empty?

          sorted = page_numbers.uniq.sort
          ranges = []
          range_start = sorted.first
          range_end = sorted.first

          sorted[1..].each do |num|
            if num == range_end + 1
              range_end = num
            else
              ranges << format_range(range_start, range_end)
              range_start = num
              range_end = num
            end
          end
          ranges << format_range(range_start, range_end)

          ranges
        end

        # 階層構造を取得
        # @return [Hash] 親用語 => 子用語の Set のハッシュ
        def get_hierarchy
          @hierarchy.transform_values(&:to_a)
        end

        # ルートレベルの用語を取得（親を持たない用語）
        def root_terms
          all_children = @hierarchy.values.flatten.to_set
          @entries.keys.reject { all_children.include?(it) }
        end

        # 用語の子用語を取得
        def children_of(term)
          @hierarchy[term].to_a
        end

        # エントリ数を取得
        def entry_count
          @entries.size
        end

        # リンク総数を取得
        def link_count
          @entries.values.sum(&:size)
        end

        private

        # 範囲をフォーマット
        def format_range(start_num, end_num)
          if start_num == end_num
            start_num.to_s
          else
            "#{start_num}-#{end_num}"
          end
        end
      end
    end
  end
end
