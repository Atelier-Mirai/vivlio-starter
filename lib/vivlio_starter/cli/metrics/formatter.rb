# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/metrics/formatter.rb
# ================================================================
# 責務:
#   メトリクス分析結果を仕様に沿った形式で出力する。
#
# 機能:
#   - 基本統計・詳細分析・章別分量のフォーマット
#   - バーグラフの描画
#   - 警告ラベルの付与
# ================================================================

module VivlioStarter
  module CLI
    module Metrics
      # メトリクス出力フォーマッタ
      class Formatter
        BAR_WIDTH = 12
        BAR_CHAR = '#'
        BAR_EMPTY_CHAR = '.'
        CHAPTER_LABEL_WIDTH = 30
        SECTION_LABEL_WIDTH = 36
        CHAR_COUNT_WIDTH = 6

        def initialize(config_loader)
          @config = config_loader
          @thresholds = config_loader.volume_thresholds
          @labels = config_loader.labels
        end

        # 全体の出力を生成する
        def format_full(basic, vocab, readability, chapters, show_sections: false)
          lines = []
          lines << format_basic_info(basic)
          lines << format_sentence_structure(basic)
          lines << '---'
          lines << format_detailed_analysis(vocab, readability)
          lines << '---'
          lines << format_chapters(chapters, show_sections:)
          lines.join("\n\n")
        end

        # 基本情報セクションを生成する
        def format_basic_info(basic)
          <<~OUTPUT.chomp
            📊 文章統計 — 基本情報
            - 文字数: #{number_with_comma(basic.chars_no_newline)} 文字（改行除く）
            - 行数: #{number_with_comma(basic.lines)} 行
          OUTPUT
        end

        # 文構造セクションを生成する
        def format_sentence_structure(basic)
          <<~OUTPUT.chomp
            📊 文章統計 — 文構造
            - 文の数: #{basic.sentences} 文（平均 #{basic.avg_sentence_len.round(1)} 文字/文）
            - 節の数: #{basic.clauses} 節（平均 #{basic.avg_clause_len.round(1)} 文字/節）
            - 読点数: #{basic.commas} 個
          OUTPUT
        end

        # 詳細分析セクションを生成する
        def format_detailed_analysis(vocab, readability)
          <<~OUTPUT.chomp
            📈 詳細分析

            【語彙難度】
            - 漢字比率: #{kanji_evaluation(vocab.kanji_ratio)}（#{vocab.kanji_ratio.round(1)}%） — 理想的な範囲 25〜35%
            - 平均語長: #{vocab.avg_word_length.round(1)} 文字

            【語彙多様度】
            - 語彙の豊かさ: #{ttr_evaluation(vocab.ttr)}（TTR: #{vocab.ttr.round(2)}）
              - 評価基準: 0.7 以上=非常に豊富、0.5〜0.7=豊富、0.3〜0.5=標準的、0.3 未満=単調

            【読解難度】
            - 評価: #{readability.label}（#{readability_description(readability.label)}）
            - スコア: #{readability.score.round(1)} 点
          OUTPUT
        end

        # 章別分量セクションを生成する
        def format_chapters(chapters, show_sections: false)
          return '📚 章別の分量\n\n（対象章がありません）' if chapters.empty?

          max_chars = chapters.map(&:chars).max
          title = show_sections ? '📚 章別の分量（節詳細）' : '📚 章別の分量'

          lines = [title, '']
          chapters.each do |ch|
            lines << format_chapter_line(ch, max_chars, show_sections)
          end
          lines.join("\n")
        end

        # 章行をフォーマットする（公開メソッド）
        def format_chapter_line(chapter, max_chars, show_sections)
          bar = render_bar(chapter.chars, max_chars)
          warning = chapter.warning ? " ⚠️ #{chapter.warning}" : ''

          if show_sections && chapter.sections.any?
            format_chapter_with_sections(chapter, bar, warning, max_chars)
          else
            label = padded_label(chapter_label(chapter))
            char_count = format_char_count(chapter.chars)
            "#{label} #{bar} #{char_count}#{warning}"
          end
        end

        private

        attr_reader :config, :thresholds, :labels

        # 節付きで章をフォーマットする
        def format_chapter_with_sections(chapter, _bar, warning, max_chars)
          header = truncate_label(chapter_label(chapter))
          lines = ["#{header} (#{number_with_comma(chapter.chars)} 文字)#{warning}"]

          chapter.sections.each_with_index do |sec, idx|
            prefix = idx == chapter.sections.size - 1 ? '  └' : '  ├'
            sec_bar = render_bar(sec.chars, max_chars)
            sec_warning = sec.warning ? " ⚠️ #{sec.warning}" : ''
            sec_title = padded_section_title(sec.title)
            char_count = format_char_count(sec.chars)
            lines << "#{prefix} #{sec_title} #{sec_bar} #{char_count}#{sec_warning}"
          end

          lines.join("\n")
        end

        def chapter_label(chapter)
          num = format('%02d', chapter.chapter_num)
          "第#{num}章 #{chapter.title}"
        end

        def padded_label(text)
          pad_to_width(truncate_label(text), CHAPTER_LABEL_WIDTH)
        end

        def truncate_label(text)
          truncate_to_width(text, CHAPTER_LABEL_WIDTH)
        end

        def padded_section_title(text)
          pad_to_width(truncate_section_title(text), SECTION_LABEL_WIDTH)
        end

        def truncate_section_title(text)
          truncate_to_width(text, SECTION_LABEL_WIDTH)
        end

        def truncate_to_width(text, width)
          return text if display_width(text) <= width

          result = +''
          current_width = 0

          text.each_char do |char|
            char_width = display_width(char)
            break if current_width + char_width > width - 1

            result << char
            current_width += char_width
          end

          result << '…'
        end

        def pad_to_width(text, width)
          pad = width - display_width(text)
          return text if pad <= 0

          text + (' ' * pad)
        end

        def display_width(text)
          text.each_char.sum { display_width_for_char(it) }
        end

        def display_width_for_char(char)
          fullwidth_char?(char) ? 2 : 1
        end

        def fullwidth_char?(char)
          !char.ascii_only?
        end

        # バーグラフを描画する
        def render_bar(value, max_value)
          return "[#{BAR_EMPTY_CHAR * BAR_WIDTH}]" if max_value.zero?

          filled = [(value.to_f / max_value * BAR_WIDTH).round, BAR_WIDTH].min
          empty = BAR_WIDTH - filled
          "[#{BAR_CHAR * filled}#{BAR_EMPTY_CHAR * empty}]"
        end

        # 数値をカンマ区切りにする
        def number_with_comma(num) = num.to_s.gsub(/(\d)(?=(\d{3})+(?!\d))/, '\\1,')

        def format_char_count(num)
          formatted = number_with_comma(num)
          "#{formatted.rjust(CHAR_COUNT_WIDTH)} 文字"
        end

        # 漢字比率の評価
        def kanji_evaluation(ratio)
          case ratio
          in ..20 then '平易'
          in 20..25 then 'やや平易'
          in 25..35 then '適切'
          in 35..45 then 'やや難解'
          else '難解'
          end
        end

        # TTR の評価
        def ttr_evaluation(ttr)
          case ttr
          in ..0.3 then '単調'
          in 0.3..0.5 then '標準的'
          in 0.5..0.7 then '豊富'
          else '非常に豊富'
          end
        end

        # 読解難度の説明
        def readability_description(label)
          case label
          in 'Easy' then '小中学生向け'
          in 'Standard' then '一般的なビジネス・実用書'
          in 'Professional' then '専門家・技術者向け'
          else label
          end
        end
      end

      # 章・節の警告判定
      class WarningChecker
        def initialize(config_loader)
          @thresholds = config_loader.volume_thresholds
          @labels = config_loader.labels
          @exclude = config_loader.exclude_chapters
        end

        # 章の警告を判定する
        def chapter_warning(chapter_num, chars)
          return nil if excluded?(chapter_num)

          check_volume(chars, thresholds[:chapter])
        end

        # 節の警告を判定する
        def section_warning(chars, chapter_num: nil)
          return nil if excluded?(chapter_num)

          check_volume(chars, thresholds[:section])
        end

        # 警告がある章かどうか
        def has_warning?(chapter_num, chars, sections)
          return true if chapter_warning(chapter_num, chars)

          sections.any? { section_warning(it.chars, chapter_num:) }
        end

        def excluded_chapter?(chapter_num)
          excluded?(chapter_num)
        end

        private

        attr_reader :thresholds, :labels, :exclude

        # 除外対象か判定する
        def excluded?(chapter_num)
          return false unless chapter_num

          exclude.include?(format('%02d', chapter_num.to_i))
        end

        # 分量チェック
        def check_volume(chars, threshold)
          if chars < threshold[:min]
            labels[:too_short]
          elsif chars > threshold[:max]
            labels[:too_long]
          end
        end
      end
    end
  end
end
