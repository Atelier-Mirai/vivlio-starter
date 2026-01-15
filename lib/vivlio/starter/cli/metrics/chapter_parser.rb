# frozen_string_literal: true

# ================================================================
# File: lib/vivlio/starter/cli/metrics/chapter_parser.rb
# ================================================================
# 責務:
#   Markdown ファイルから章・節構造を解析する。
#
# 機能:
#   - H1 見出しから章タイトル・番号を抽出
#   - H2 見出しから節を抽出
#   - 各セクションの文字数を算出
# ================================================================

module Vivlio
  module Starter
    module CLI
      module Metrics
        # Markdown から章・節構造を解析する
        class ChapterParser
          H1_PATTERN = /^#\s+(.+)$/
          H2_PATTERN = /^##\s+(.+)$/
          CHAPTER_NUM_PATTERN = /^(\d+)-/

          def initialize(warning_checker)
            @warning_checker = warning_checker
          end

          # ファイルパスから章メトリクスを生成する
          def parse(path)
            content = File.read(path, encoding: 'UTF-8')
            parse_content(path, content)
          rescue Encoding::InvalidByteSequenceError, Encoding::UndefinedConversionError
            blank_chapter(path)
          end

          def parse_content(path, content)
            chapter_num = extract_chapter_num(path)
            title = extract_title(content) || File.basename(path, '.md')
            sections = parse_sections(content, chapter_num)
            total_chars = content.delete("\r\n").length

            warning = warning_checker.chapter_warning(chapter_num, total_chars)

            ChapterMetrics.new(
              path:,
              title:,
              chapter_num:,
              chars: total_chars,
              sections:,
              warning:
            )
          end

          private

          attr_reader :warning_checker

          # ファイル名から章番号を抽出する
          def extract_chapter_num(path)
            basename = File.basename(path, '.md')
            match = basename.match(CHAPTER_NUM_PATTERN)
            match ? match[1].to_i : 0
          end

          # H1 見出しからタイトルを抽出する
          def extract_title(content)
            match = content.match(H1_PATTERN)
            match ? match[1].strip : nil
          end

          # H2 見出しから節を解析する
          def parse_sections(content, chapter_num)
            sections = []
            current_title = nil
            current_content = []

            content.each_line do |line|
              case line
              in H2_PATTERN
                flush_section(sections, current_title, current_content, chapter_num) if current_title
                current_title = Regexp.last_match(1).strip
                current_content = []
              else
                current_content << line if current_title
              end
            end

            flush_section(sections, current_title, current_content, chapter_num) if current_title
            sections
          end

          # 節を確定してリストに追加する
          def flush_section(sections, title, content_lines, chapter_num)
            text = content_lines.join.delete("\r\n")
            chars = text.length
            warning = warning_checker.section_warning(chars, chapter_num: chapter_num)

            sections << SectionMetrics.new(title:, chars:, warning:)
          end

          # エラー時の空章データ
          def blank_chapter(path)
            ChapterMetrics.new(
              path:,
              title: File.basename(path, '.md'),
              chapter_num: 0,
              chars: 0,
              sections: [],
              warning: nil
            )
          end
        end
      end
    end
  end
end
