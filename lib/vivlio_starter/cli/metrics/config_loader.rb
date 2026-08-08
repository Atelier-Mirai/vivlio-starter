# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/metrics/config_loader.rb
# ================================================================
# 責務:
#   book.yml の metrics 設定を読み込み、プリセットを解決する。
#   設定の取得は Common::CONFIG に一本化する（独自の YAML 直読みはしない。
#   config-access-unification-spec.md Phase 2）。
#
# 機能:
#   - プリセット選択（compact/standard/commercial/author_custom）
#   - 除外章の解析
#   - しきい値の取得
# ================================================================

require_relative 'analyzer'
require_relative '../common'

require_relative '../config_keys'

module VivlioStarter
  module CLI
    module Metrics
      # metrics 設定を読み込み解決する
      class ConfigLoader
        # 相対モード（`use: relative`）の帯。**その本自身の章の本文字数の中央値**に
        # 対する倍率で判定する。章立ての粒度は著者の設計判断なので、絶対値の帯では
        # 正しく評価できない本が構造的に出る——リファレンス寄りの本ほど章が細かくなる。
        # 倍率は 2 通りの導出（確定プリセットの形／刊行書 128 章の比の分布）が一致した
        # 値で、min と max は互いに逆数の関係にある（1/1.5 ≒ 0.65）。刊行書に当てると
        # 「短い」10%・「長い」10% と両裾が釣り合う（`chapter-volume-calibration-data.md` §7.2.0）。
        RELATIVE_RATIOS = { min: 0.65, ideal_min: 0.80, ideal_max: 1.20, max: 1.50 }.freeze

        # 相対モードで中央値が安定する最小章数。これを下回ると絶対帯へ落とす。
        RELATIVE_MIN_CHAPTERS = 5

        # 総本文字数からプリセットを選ぶ境界（相対モードのフォールバック先）。
        PRESET_BY_TOTAL = [[35_000, :compact], [65_000, :handy],
                           [90_000, :standard], [150_000, :commercial]].freeze

        # 節の基準はプリセット共通。刊行書 408 節の実測が 200 頁以上の本からしか
        # 採れておらず、規模別に分ける根拠が無いため
        # （`chapter-volume-calibration-data.md` §3.4）。
        DEFAULT_SECTION = { min: 400, ideal: [1000, 2800], max: 4000 }.freeze

        # プリセットの既定値。すべて本文（コードと記法を除いた地の文）の文字数で、
        # 刊行済み技術書の実測から引いた（`chapter-volume-calibration-data.md` §7.1）。
        # `min` は 10・`ideal` は 25〜75・`max` は 90 パーセンタイル。
        # 選ぶ軸は総本文字数（頁数は判型・余白・図版量で動くため単独では決まらない）。
        DEFAULT_PRESETS = {
          # 〜3.5 万字（20〜50 頁）／実測 3 記事 24 章
          compact: {
            chapter: { min: 800, ideal: [1100, 3400], max: 4200 },
            section: DEFAULT_SECTION
          },
          # 3.5 万〜6.5 万字（50〜100 頁）／両隣の実測からの内挿（§7.2.1）
          handy: {
            chapter: { min: 2900, ideal: [3400, 5700], max: 6800 },
            section: DEFAULT_SECTION
          },
          # 6.5 万〜9 万字（100〜200 頁）／実測 2 冊 16 章
          standard: {
            chapter: { min: 4200, ideal: [4800, 8500], max: 9700 },
            section: DEFAULT_SECTION
          },
          # 9 万〜15 万字（200〜350 頁）／実測 4 冊 36 章
          commercial: {
            chapter: { min: 6400, ideal: [7800, 14_600], max: 17_800 },
            section: DEFAULT_SECTION
          },
          # 15 万字〜（350 頁以上）／実測 3 冊 52 章
          heavy: {
            chapter: { min: 9200, ideal: [11_000, 16_000], max: 19_600 },
            section: DEFAULT_SECTION
          }
        }.freeze

        DEFAULT_VOCABULARY = {
          kanji_ratio: { min: 20, ideal: [25, 35], max: 45 },
          word_length: { min: 1.5, ideal: [2.0, 2.5], max: 3.0 },
          ttr: { min: 0.3, ideal: [0.5, 0.7], max: 1.0 }
        }.freeze

        # 建石式 RS は値が大きいほど読みやすい。easy/standard は各バンドの下限。
        # RS >= easy → Easy（やさしい）、>= standard → Standard、未満 → Professional。
        # 既定値は建石式の絶対尺度上の目安（児童書 60+／実用書 40〜60／専門書 〜40）。
        DEFAULT_READABILITY = { easy: 60, standard: 40 }.freeze

        # 章別リストに添える文言。分量は too_short / just_right / too_long の 3 状態で
        # 対になっており、文章の質は monotonous / too_complex の 2 つ。
        # `chapter.ideal` は範囲を表す数値キーなので、こちらの語は `just_right` にして
        # 名前の衝突を避けている。
        DEFAULT_LABELS = {
          too_short: '加筆検討',
          just_right: '丁度良い',
          too_long: 'やや長い',
          monotonous: '表現が単調',
          too_complex: 'やや難解'
        }.freeze

        # @param book_config [Hash, nil] book.yml 相当の Hash（テスト用の差し替え口。
        #   文字列キー・シンボルキーのどちらでも受け付ける）。
        #   省略時は Common::CONFIG.metrics を使用する。
        def initialize(book_config = nil)
          metrics = if book_config
                      normalize_config(book_config)[:metrics]
                    else
                      normalize_config(Common::CONFIG&.metrics)
                    end
          @metrics_config = metrics || {}
        end

        # 選択されたプリセットの章・節しきい値を取得する。
        # 相対モードでは `resolve_relative_basis` が呼ばれるまで基準が決まらないため、
        # 呼び出し側（Formatter / WarningChecker）は値を抱え込まず毎回ここへ問い合わせる。
        def volume_thresholds
          @volume_thresholds ||= relative_thresholds ||
                                 symbolize_thresholds(resolve_preset(effective_preset_name))
        end

        # 相対モード（`metrics.use: relative`）か
        def relative? = preset_name == 'relative'

        # 相対モードの基準を確定する。全章を読むまで中央値が決まらないので、
        # Runner が事前スキャンを終えた時点で一度だけ呼ぶ。
        #
        # 判定対象の章が少ないと中央値が 1 章の増減で動くため、
        # RELATIVE_MIN_CHAPTERS 未満なら総本文字数から選んだ絶対帯へ落とす
        # （`chapter-volume-calibration-data.md` §7.2.0）。
        # @param judged_chars [Array<Integer>] 分量判定の対象となる章の本文字数
        # @param total_prose [Integer] 本全体の本文字数（フォールバック先の選択に使う）
        def resolve_relative_basis(judged_chars, total_prose)
          return unless relative?

          @volume_thresholds = nil
          if judged_chars.size >= RELATIVE_MIN_CHAPTERS
            @relative_baseline = median(judged_chars)
          else
            @relative_fallback = self.class.preset_for_total(total_prose)
          end
        end

        # 総本文字数からプリセットを選ぶ。境界は実測に基づく
        # （`chapter-volume-calibration-data.md` §7.1）。
        def self.preset_for_total(total)
          PRESET_BY_TOTAL.find { |limit, _| total < limit }&.last || :heavy
        end

        # 除外する章番号のリストを取得する
        def exclude_chapters
          raw = metrics_config[:exclude_chapters] || ConfigKeys::KEYS[%i[metrics exclude_chapters]].default
          expand_chapter_ranges(raw)
        end

        # 語彙難度のしきい値を取得する
        def vocabulary_thresholds
          merge_with_defaults(metrics_config, DEFAULT_VOCABULARY, %i[kanji_ratio word_length ttr])
        end

        # 読解難度のしきい値を取得する
        def readability_thresholds
          config_readability = metrics_config[:readability] || {}
          {
            easy: config_readability[:easy] || DEFAULT_READABILITY[:easy],
            standard: config_readability[:standard] || DEFAULT_READABILITY[:standard]
          }
        end

        # 警告ラベルを取得する
        def labels
          DEFAULT_LABELS.merge(metrics_config[:labels] || {})
        end

        private

        attr_reader :metrics_config

        # CONFIG の Data ラッパー / テストの Hash（文字列・シンボルキー混在）を
        # シンボルキーの素の Hash へ再帰的に正規化する
        def normalize_config(node)
          case node
          in nil then nil
          in Hash then node.to_h { |k, v| [k.to_sym, normalize_config(v)] }
          in Array then node.map { normalize_config(it) }
          else node.respond_to?(:to_h) ? normalize_config(node.to_h) : node
          end
        end

        # 相対モードのしきい値。基準が未確定（フォールバック中）なら nil。
        def relative_thresholds
          return nil unless relative? && @relative_baseline

          { chapter: RELATIVE_RATIOS.transform_values { (@relative_baseline * it).round },
            section: symbolize_range(DEFAULT_SECTION) }
        end

        # `use` に書かれたプリセット名。相対モードでフォールバックしていればその行き先。
        def effective_preset_name
          return @relative_fallback.to_s if relative? && @relative_fallback

          preset_name
        end

        def preset_name = (metrics_config[:use] || ConfigKeys::KEYS[%i[metrics use]].default).to_s

        def median(values)
          sorted = values.sort
          mid = sorted.size / 2
          sorted.size.odd? ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2.0
        end

        # プリセットを解決する。
        #
        # 既定値へ**深くマージ**する（Common.deep_merge_config）。かつては
        # `custom[:chapter]` の有無で全か無かを判定しており、プリセットに `section:` だけ
        # 書いて `chapter:` を書かないと**著者の指定が警告なく捨てられた**。
        # 合成規則は 1 つに決め、各所で再実装しない（config-defaults-design-spec.md §4.4）。
        def resolve_preset(name)
          fallback = DEFAULT_PRESETS[name.to_sym] || DEFAULT_PRESETS[:standard]
          custom = metrics_config[name.to_sym]
          return fallback unless custom.is_a?(Hash)

          Common.deep_merge_config(fallback, custom)
        end

        # しきい値をシンボルキーに変換する
        def symbolize_thresholds(preset)
          {
            chapter: symbolize_range(preset[:chapter] || {}),
            section: symbolize_range(preset[:section] || {})
          }
        end

        # 範囲を ideal_min / ideal_max 形式へ展開する
        def symbolize_range(range)
          ideal = range[:ideal] || [0, 0]
          {
            min: range[:min] || 0,
            ideal_min: ideal[0],
            ideal_max: ideal[1],
            max: range[:max] || Float::INFINITY
          }
        end

        # 章範囲を展開する
        def expand_chapter_ranges(ranges)
          ranges.flat_map do |item|
            case item.to_s
            in /\A(\d+)-(\d+)\z/
              (Regexp.last_match(1).to_i..Regexp.last_match(2).to_i).map { format('%02d', it) }
            else
              [format('%02d', item.to_s.to_i)]
            end
          end
        end

        # デフォルト値とマージする
        def merge_with_defaults(config, defaults, keys)
          keys.to_h do |key|
            config_value = config[key] || {}
            default_value = defaults[key]
            ideal = config_value[:ideal] || default_value[:ideal]

            [key, {
              min: config_value[:min] || default_value[:min],
              ideal_min: ideal[0],
              ideal_max: ideal[1],
              max: config_value[:max] || default_value[:max]
            }]
          end
        end
      end
    end
  end
end
