# frozen_string_literal: true

# ================================================================
# File: lib/vivlio/starter/cli/pre_process/cross_reference_processor.rb
# ================================================================
# 責務:
#   クロスリファレンス（相互参照）機能を提供する。
#
# 機能:
#   - ラベル定義の収集（** タイトル @id ** 形式）
#   - キャプション付きブロック（図・表・コード）の HTML 変換
#   - 本文中の @id 参照をリンクに置換
#   - 重複チェックとレポート生成
#
# 依存:
#   - Common: 設定読み込み・ログ出力
#   - HeadingProcessor: 章番号の取得
#   - MarkdownUtils: Markdown→HTML 変換
# ================================================================

require 'cgi'
require_relative '../common'
require_relative '../post_process/heading_processor'
require_relative 'markdown_utils'
require_relative 'cross_reference/chapter_resolver'
require_relative 'cross_reference/label_collector'
require_relative 'cross_reference/captioned_block_renderer'
require_relative 'cross_reference/reference_replacer'
require_relative 'cross_reference/report_builder'

module Vivlio
  module Starter
    module CLI
      module PreProcessCommands
        # クロスリファレンス処理モジュール
        module CrossReferenceProcessor
          # ラベル定義情報を保持する構造体
          Label = Struct.new(:id, :type, :chapter, :number, :title, :source_file, :line, :auto) do
            def display_name
              case type
              when :list then 'リスト'
              when :table then '表'
              when :fig then '図'
              else '要素'
              end
            end

            def full_number
              "#{display_name} #{number}"
            end
          end

          # キャプション行のパターン（** タイトル @id ** 形式）
          CAPTION_PATTERN = /^\*\*\s*(.+?)\s+@([-a-zA-Z0-9_]+)\s*\*\*\s*$/.freeze

          # 本文中で説明用に登場しても「参照」と見なさない予約済みID
          RESERVED_INLINE_LABEL_IDS = %w[auto omakase id].freeze

          module_function

          # キャプション行を検出してラベル情報を抽出
          def extract_caption_label(line)
            match = line.match(CAPTION_PATTERN)
            return nil unless match

            title_with_id = match[1].strip
            label_id = match[2].strip
            auto_mode = %w[auto omakase].include?(label_id)

            { title: title_with_id, id: label_id, auto: auto_mode }
          end

          # 次の非空行を取得し、種別を判定
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

          # 章番号を抽出（ファイル名から）
          def extract_chapter_number(filename)
            CrossReference::ChapterResolver.extract_number(filename)
          end

          def main_chapter_order_for_xref
            CrossReference::ChapterResolver.main_chapter_order
          end

          def display_chapter_number_for_filename(filename)
            CrossReference::ChapterResolver.display_number(filename)
          end

          # 章全体をスキャンしてラベル定義を収集
          def collect_labels(content, source_file, chapter_number)
            collector = CrossReference::LabelCollector.new(
              content: content,
              source_file: source_file,
              chapter_number: chapter_number,
              label_class: Label,
              caption_pattern: CAPTION_PATTERN,
              auto_label_ids: RESERVED_INLINE_LABEL_IDS
            )
            collector.collect
          end

          # キャプション行と直後のブロックをHTML化
          def transform_captioned_blocks(content, filename, labels_map)
            renderer = CrossReference::CaptionedBlockRenderer.new(
              content: content,
              filename: filename,
              labels_map: labels_map,
              caption_extractor: method(:extract_caption_label),
              chapter_number_resolver: method(:display_chapter_number_for_filename)
            )
            renderer.render
          end

          # 本文中の @id を番号付きリンクに置換
          def replace_references(content, labels_map, filename = nil)
            replacer = CrossReference::ReferenceReplacer.new(
              content: content,
              labels_map: labels_map,
              filename: filename,
              reserved_inline_label_ids: RESERVED_INLINE_LABEL_IDS
            )
            replacer.replace
          end

          # 複数章のラベルを統合し、重複チェックを行う
          def build_labels_map_with_duplicates_check(all_labels)
            CrossReference::ReportBuilder.build_labels_map_with_duplicates_check(all_labels)
          end

          # ID一覧レポートを生成
          def generate_cross_reference_report(all_labels)
            CrossReference::ReportBuilder.generate_cross_reference_report(all_labels)
          end

          # クロスリファレンス処理のメインエントリーポイント
          def process_cross_references(chapters)
            all_labels = []
            all_errors = []
            processed_chapters = {}

            Common.log_info('Phase 1: ラベル定義を収集中...')
            chapters.each do |filename, content|
              chapter_number = extract_chapter_number(filename)
              result = collect_labels(content, filename, chapter_number)
              all_labels.concat(result[:labels])
              all_errors.concat(result[:errors])
              Common.log_info("  #{filename}: #{result[:labels].size}個のラベルを検出")
            end

            Common.log_info('Phase 2: ラベルマップ構築と重複チェック...')
            map_result = build_labels_map_with_duplicates_check(all_labels)
            labels_map = map_result[:labels_map]
            duplicates = map_result[:duplicates]

            if duplicates.any?
              Common.log_error('ラベルIDの重複を検出しました:')
              duplicates.each { |dup| Common.log_error(dup) }
              all_errors.concat(duplicates)
            end

            Common.log_info('Phase 3: キャプション付きブロックをHTML化中...')
            chapters.each do |filename, content|
              transformed = transform_captioned_blocks(content, filename, labels_map)
              processed_chapters[filename] = transformed
            end

            Common.log_info('Phase 4: 本文中の @id 参照を置換中...')
            processed_chapters.each do |filename, content|
              result = replace_references(content, labels_map, filename)
              processed_chapters[filename] = result[:content]
              all_errors.concat(result[:errors])

              if result[:errors].any?
                Common.log_warn("  #{filename}: #{result[:errors].size}個の未定義参照を検出")
                result[:errors].each { |msg| Common.log_warn("    - #{msg}") }
              end
            end

            report = generate_cross_reference_report(all_labels)

            {
              chapters: processed_chapters,
              report: report,
              errors: all_errors,
              labels_count: all_labels.size
            }
          end
        end
      end
    end
  end
end
