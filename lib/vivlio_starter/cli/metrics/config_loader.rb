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

module VivlioStarter
  module CLI
    module Metrics
      # metrics 設定を読み込み解決する
      class ConfigLoader
        # デフォルトのプリセット設定
        DEFAULT_PRESETS = {
          compact: {
            chapter: { min: 1000, ideal: [1500, 3000], max: 5000 },
            section: { min: 300, ideal: [500, 1000], max: 1500 }
          },
          standard: {
            chapter: { min: 3000, ideal: [5000, 10_000], max: 15_000 },
            section: { min: 800, ideal: [1500, 3000], max: 4000 }
          },
          commercial: {
            chapter: { min: 5000, ideal: [8000, 12_000], max: 20_000 },
            section: { min: 1500, ideal: [2000, 4000], max: 6000 }
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

        DEFAULT_LABELS = {
          too_short: '加筆検討',
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

        # 選択されたプリセットの章・節しきい値を取得する
        def volume_thresholds
          preset_name = metrics_config[:use] || 'standard'
          preset = resolve_preset(preset_name)
          symbolize_thresholds(preset)
        end

        # 除外する章番号のリストを取得する
        def exclude_chapters
          raw = metrics_config[:exclude_chapters] || %w[00 90-98 99]
          expand_chapter_ranges(raw)
        end

        # 語彙難度のしきい値を取得する
        def vocabulary_thresholds
          merge_with_defaults(metrics_config, DEFAULT_VOCABULARY, %i[kanji_ratio word_length ttr])
        end

        # MATTR（移動平均 TTR）の窓幅を取得する（語彙多様度の算出単位）。
        def mattr_window
          (metrics_config[:mattr_window] || Analyzer::DEFAULT_MATTR_WINDOW).to_i
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

        # プリセットを解決する
        def resolve_preset(name)
          custom = metrics_config[name.to_sym]
          return custom if custom.is_a?(Hash) && custom[:chapter]

          DEFAULT_PRESETS[name.to_sym] || DEFAULT_PRESETS[:standard]
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
