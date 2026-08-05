# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/metrics/chapter_parser.rb
# ================================================================
# 責務:
#   Markdown ファイルから章・節構造を解析する。
#
# 機能:
#   - H1 見出しから章タイトル・番号を抽出
#   - H2 見出しから節を抽出
#   - 各セクションの本文字数を算出
# ================================================================

require_relative '../masking'
require_relative 'analyzer'

module VivlioStarter
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

        # 分量は本文（コードと記法を除いた地の文）で数える。
        # コードが多い章ほど「分量が十分」と判定されてしまう歪みを断つため
        # （`chapter-volume-calibration-data.md` §7.1）。
        def parse_content(path, content)
          chapter_num = extract_chapter_num(path)
          title = extract_title(content) || File.basename(path, '.md')
          sections = parse_sections(content, chapter_num)
          total_chars = Analyzer.prose_length(content)

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

        # H2 見出しから節を解析する。
        # 見出しの判定はコードフェンスの外だけで行う。記法を解説する原稿では
        # フェンス内に `## 見出し` の実例が現れ、そこで節を切ると閉じフェンスが
        # 開きフェンスとして解釈され、後続の地の文がコード扱いで消えてしまう
        # （本書の 21-markdown-tutorial で本文が 6,303 → 2,195 字に化けていた）。
        def parse_sections(content, chapter_num)
          heading_lines = prose_heading_lines(content)
          sections = []
          current_title = nil
          current_content = []

          content.each_line.with_index(1) do |line, lineno|
            if heading_lines.include?(lineno)
              flush_section(sections, current_title, current_content, chapter_num) if current_title
              current_title = line[H2_PATTERN, 1].strip
              current_content = []
            elsif current_title
              current_content << line
            end
          end

          flush_section(sections, current_title, current_content, chapter_num) if current_title
          sections
        end

        # コードフェンスの外にある H2 見出しの行番号（1 始まり）。
        # フェンス解釈は Masking（唯一の実装）へ委ねて独自の状態機械を作らない。
        def prose_heading_lines(content)
          Masking.each_prose_line(content)
                 .filter_map { |line, lineno| lineno if line.match?(H2_PATTERN) }
        end

        # 節を確定してリストに追加する。分量は章と同じく本文で数える。
        def flush_section(sections, title, content_lines, chapter_num)
          chars = Analyzer.prose_length(content_lines.join)
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
