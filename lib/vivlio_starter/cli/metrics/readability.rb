# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/metrics/readability.rb
# ================================================================
# 責務:
#   日本語テキストの読解難度（リーダビリティー）を算出する。
#
# 採用式:
#   建石由佳・小野芳彦・山田尚勇 (1988)「日本文の読みやすさの評価式」
#   情報処理学会 ヒューマンインタフェース研究会報告 No.18。
#
#   RS = -0.12·ls − 1.37·la + 7.4·lh − 23.18·lc − 5.4·lk − 4.67·cp + 115.79
#
#     ls = 平均文長（文字数）
#     la = アルファベット連の平均長
#     lh = ひらがな連の平均長
#     lc = 漢字連の平均長
#     lk = カタカナ連の平均長
#     cp = 句点（。）あたりの読点（、）の数
#
#   「連」は同一文字種が連続する一続き。RS は偏差値的な指標で、
#   値が大きいほど読みやすい（漢字連が長いほど大きく下がる）。
#
# 設計:
#   章ごとに RS を平均しても全体の RS にはならない（各 l* は平均値で
#   非線形に効くため）。そこで章単位では「特徴量（連の数・連の文字数・
#   文の数・文字数・句読点数）」を蓄積し、全体ではそれを合算してから
#   一度だけ RS を算出する。ReadabilityFeatures がその蓄積単位。
# ================================================================

module VivlioStarter
  module CLI
    module Metrics
      # RS 算出に必要な生の特徴量（合算可能な素の集計値）。
      # 平均ではなく「合計と個数」を保持することで、章をまたいだ合算後に
      # 正しい平均（l*）を再構成できる。
      ReadabilityFeatures = Data.define(
        :sentence_count, :sentence_char_total,
        :alpha_run_count, :alpha_char_total,
        :hira_run_count, :hira_char_total,
        :kanji_run_count, :kanji_char_total,
        :kata_run_count, :kata_char_total,
        :period_count, :comma_count
      ) do
        # すべて 0 の空特徴量（空章・合算の初期値）。
        def self.zero = new(**members.to_h { [it, 0] })
      end

      # 建石式リーダビリティーの算出ロジック。
      module Readability
        module_function

        # 建石・小野・山田 (1988) の確定係数。
        COEFFICIENTS = { ls: -0.12, la: -1.37, lh: 7.4, lc: -23.18, lk: -5.4, cp: -4.67 }.freeze
        CONSTANT = 115.79

        SENTENCE_DELIMITER = /[。！？!?]+/
        PERIOD = '。'
        COMMA = '、'

        # テキストから RS 算出用の特徴量を抽出する。
        # @param text [String] コード除去後の本文（prose）
        # @return [ReadabilityFeatures]
        def extract_features(text)
          sentences = sentence_lengths(text)
          runs = count_character_runs(text)

          ReadabilityFeatures.new(
            sentence_count: sentences.size,
            sentence_char_total: sentences.sum,
            alpha_run_count: runs[:alpha][:runs], alpha_char_total: runs[:alpha][:chars],
            hira_run_count: runs[:hira][:runs], hira_char_total: runs[:hira][:chars],
            kanji_run_count: runs[:kanji][:runs], kanji_char_total: runs[:kanji][:chars],
            kata_run_count: runs[:kata][:runs], kata_char_total: runs[:kata][:chars],
            period_count: text.count(PERIOD),
            comma_count: text.count(COMMA)
          )
        end

        # 特徴量から RS を算出する。値が大きいほど読みやすい。
        # @param features [ReadabilityFeatures]
        # @return [Float]
        def score(features)
          ls = avg(features.sentence_char_total, features.sentence_count)
          la = avg(features.alpha_char_total, features.alpha_run_count)
          lh = avg(features.hira_char_total, features.hira_run_count)
          lc = avg(features.kanji_char_total, features.kanji_run_count)
          lk = avg(features.kata_char_total, features.kata_run_count)
          cp = avg(features.comma_count, features.period_count)

          CONSTANT +
            (COEFFICIENTS[:ls] * ls) + (COEFFICIENTS[:la] * la) + (COEFFICIENTS[:lh] * lh) +
            (COEFFICIENTS[:lc] * lc) + (COEFFICIENTS[:lk] * lk) + (COEFFICIENTS[:cp] * cp)
        end

        # RS をしきい値で難易度ラベルに変換する（大きいほど易しい）。
        # @param thresholds [Hash] { easy:, standard: } いずれもバンド下限
        def label(score, thresholds)
          return 'Easy' if score >= thresholds[:easy]
          return 'Standard' if score >= thresholds[:standard]

          'Professional'
        end

        # 章ごとの特徴量を合算する（全体 RS 算出用）。
        # @param features_list [Array<ReadabilityFeatures>]
        # @return [ReadabilityFeatures]
        def aggregate(features_list)
          return ReadabilityFeatures.zero if features_list.empty?

          ReadabilityFeatures.members.to_h { |field| [field, features_list.sum { it.public_send(field) }] }
                             .then { ReadabilityFeatures.new(**it) }
        end

        # --- 内部ヘルパー ---

        # 文ごとの文字数（空白除く）。
        def sentence_lengths(text)
          text.split(SENTENCE_DELIMITER)
              .map { it.gsub(/\s/, '').length }
              .reject(&:zero?)
        end

        # 文字種ごとに「連の数」と「連に含まれる文字数」を数える。
        def count_character_runs(text)
          acc = %i[alpha hira kanji kata].to_h { [it, { runs: 0, chars: 0 }] }
          previous = nil

          text.each_char do |char|
            klass = character_class(char)
            if klass
              acc[klass][:chars] += 1
              acc[klass][:runs] += 1 if klass != previous
            end
            previous = klass
          end

          acc
        end

        # 1 文字の文字種を判定する（対象外は nil で連を区切る）。
        # 長音符（ー）はカタカナ語に付くため、カタカナ連として扱う。
        def character_class(char)
          case char
          when /\p{Han}/ then :kanji
          when /\p{Hiragana}/ then :hira
          when /\p{Katakana}/, 'ー' then :kata
          when /[A-Za-z]/ then :alpha
          end
        end

        def avg(sum, count) = count.positive? ? sum.to_f / count : 0.0
      end
    end
  end
end
