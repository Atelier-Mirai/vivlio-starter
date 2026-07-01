# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/metrics/kanji_levels.rb
# ================================================================
# 責務:
#   本文中の漢字を難易度レベルに分類し、ルビ候補として集計する。
#
# レベル定義:
#   L0 教育       … 小学校の学年別配当漢字（同梱データ）
#   L1 中学       … 中学で習う常用漢字（同梱データ）
#   L2 一般(L2)   … JIS第一水準 ∖ 常用漢字（符号位置から算出）
#   L3 専門(L3)   … JIS第二水準（符号位置から算出）
#   L4 JIS外      … JIS X 0208 に無い漢字（第三水準・補助漢字など）
#
# 目的:
#   小学生向けなど、対象読者より上位の漢字（＝ルビを振るべき候補）を把握する。
#   読みの自動付与は誤読が多く危険なため、ここでは「どの漢字がどのレベルで、
#   どこに出現するか」の統計に徹する（自動ルビは将来の vs furigana に分離）。
# ================================================================

module VivlioStarter
  module CLI
    module Metrics
      # 漢字レベル集計の結果。
      #   ratios    … [表示ラベル, 割合%] の配列（内訳の表示順）
      #   lists     … { level_key => [[漢字, 回数], …] }（中学/一般/専門のみ）
      #   locations … [[漢字, ["第NN章 L##", …]], …]（一般・専門の出現箇所）
      KanjiLevelReport = Data.define(:ratios, :lists, :locations)

      module KanjiLevels
        module_function

        DATA_PATH = File.expand_path('data/kyoiku_joyo_kanji.tsv', __dir__)
        HAN = /\p{Han}/
        # 表示ラベルと内訳の並び順。
        LABELS = { kyoiku: '教育', chugaku: '中学', ippan: '一般(L2)', senmon: '専門(L3)', gaiji: 'JIS外' }.freeze
        ORDER = %i[kyoiku chugaku ippan senmon gaiji].freeze
        # 一覧・出現箇所の表示上限。
        LIST_LABELS = { chugaku: '中学漢字', ippan: '一般漢字(L2)', senmon: '専門漢字(L3)' }.freeze
        LOCATION_CHAR_LIMIT = 15
        LOCATION_PER_CHAR = 5

        # 漢字 1 文字のレベルを返す。教育・中学は同梱データ、それ以外は符号位置で判定。
        def level_of(char)
          grade = table[char]
          return :chugaku if grade == '中学'
          return :kyoiku if grade

          jis_level(char)
        end

        # 位置つきの文の列から、漢字レベルの集計レポートを作る。漢字が無ければ nil。
        def build_report(sentences)
          totals = Hash.new(0)
          chars = {}

          sentences.each do |sentence|
            scan_kanji(sentence, totals, chars)
          end
          return nil if chars.empty?

          KanjiLevelReport.new(ratios: ratios(totals), lists: candidate_lists(chars), locations: locations(chars))
        end

        # --- 内部ヘルパー ---

        def table = @table ||= load_table

        def load_table
          File.foreach(DATA_PATH, encoding: 'UTF-8').each_with_object({}) do |line, map|
            next if line.start_with?('#') || line.strip.empty?

            char, grade = line.chomp.split("\t")
            map[char] = grade
          end
        end

        # JIS X 0208 の区（EUC-JP の第 1 バイト）で第一/第二水準を分ける。
        def jis_level(char)
          bytes = char.encode('EUC-JP').bytes
          return :gaiji unless bytes.size == 2

          (bytes[0] - 0xA0) <= 47 ? :ippan : :senmon
        rescue Encoding::UndefinedConversionError
          :gaiji
        end

        def scan_kanji(sentence, totals, chars)
          sentence.text.each_char do |char|
            next unless char.match?(HAN)

            level = level_of(char)
            totals[level] += 1
            record = (chars[char] ||= { level:, count: 0, locations: [] })
            record[:count] += 1
            # 出現箇所は [章番号, 行] のまま持ち、表示側で章ごとにまとめる。
            record[:locations] << [sentence.chapter_num, sentence.line]
          end
        end

        def ratios(totals)
          grand = totals.values.sum.to_f
          ORDER.filter_map do |level|
            next if totals[level].zero?

            [LABELS[level], (totals[level] / grand * 100).round]
          end
        end

        def candidate_lists(chars)
          LIST_LABELS.keys.to_h do |level|
            entries = chars.select { |_char, rec| rec[:level] == level }
                           .sort_by { |char, rec| [-rec[:count], char] }
                           .map { |char, rec| [char, rec[:count]] }
            [level, entries]
          end
        end

        # 一般・専門漢字（稀でルビを振りたい）を、出現の少ない順に位置つきで返す。
        def locations(chars)
          chars.select { |_char, rec| %i[ippan senmon].include?(rec[:level]) }
               .sort_by { |char, rec| [rec[:count], char] }
               .first(LOCATION_CHAR_LIMIT)
               .map { |char, rec| [char, rec[:locations].uniq.first(LOCATION_PER_CHAR)] }
        end
      end
    end
  end
end
