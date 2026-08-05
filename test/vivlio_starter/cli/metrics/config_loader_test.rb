# frozen_string_literal: true

require 'test_helper'
require 'vivlio_starter/cli/metrics/config_loader'

module VivlioStarter
  module CLI
    module Metrics
      class ConfigLoaderTest < Minitest::Test
        def test_volume_thresholds_returns_default_standard_preset
          loader = ConfigLoader.new({})
          thresholds = loader.volume_thresholds

          assert_equal 4200, thresholds[:chapter][:min]
          assert_equal 4800, thresholds[:chapter][:ideal_min]
          assert_equal 8500, thresholds[:chapter][:ideal_max]
          assert_equal 9700, thresholds[:chapter][:max]
        end

        def test_volume_thresholds_respects_use_setting
          config = { 'metrics' => { 'use' => 'compact' } }
          loader = ConfigLoader.new(config)
          thresholds = loader.volume_thresholds

          assert_equal 800, thresholds[:chapter][:min]
          assert_equal 4200, thresholds[:chapter][:max]
        end

        # 薄い本と大部の本を受ける帯を足したので、5 段すべてが単調に上がる
        def test_should_provide_five_presets_in_ascending_order
          mins = %w[compact handy standard commercial heavy].map do |name|
            ConfigLoader.new({ 'metrics' => { 'use' => name } }).volume_thresholds[:chapter][:min]
          end

          assert_equal [800, 2900, 4200, 6400, 9200], mins
          assert_equal mins.sort, mins
        end

        # 節の帯はプリセット共通（規模別に分ける実測が無いため）
        def test_should_share_the_same_section_band_across_presets
          bands = %w[compact handy standard commercial heavy].map do |name|
            ConfigLoader.new({ 'metrics' => { 'use' => name } }).volume_thresholds[:section]
          end

          assert_equal 1, bands.uniq.size
          assert_equal({ min: 400, ideal_min: 1000, ideal_max: 2800, max: 4000 }, bands.first)
        end

        def test_exclude_chapters_returns_default_list
          loader = ConfigLoader.new({})
          excluded = loader.exclude_chapters

          assert_includes excluded, '00'
          assert_includes excluded, '99'
          assert_includes excluded, '90'
          assert_includes excluded, '98'
        end

        def test_exclude_chapters_expands_ranges
          config = { 'metrics' => { 'exclude_chapters' => ['01-03', '99'] } }
          loader = ConfigLoader.new(config)
          excluded = loader.exclude_chapters

          assert_includes excluded, '01'
          assert_includes excluded, '02'
          assert_includes excluded, '03'
          assert_includes excluded, '99'
        end

        def test_vocabulary_thresholds_returns_defaults
          loader = ConfigLoader.new({})
          thresholds = loader.vocabulary_thresholds

          assert_equal 20, thresholds[:kanji_ratio][:min]
          assert_equal 25, thresholds[:kanji_ratio][:ideal_min]
          assert_equal 35, thresholds[:kanji_ratio][:ideal_max]
          assert_equal 45, thresholds[:kanji_ratio][:max]
        end

        def test_readability_thresholds_returns_defaults
          loader = ConfigLoader.new({})
          thresholds = loader.readability_thresholds

          assert_equal 60, thresholds[:easy]
          assert_equal 40, thresholds[:standard]
        end

        def test_mattr_window_defaults_and_overrides
          assert_equal Analyzer::DEFAULT_MATTR_WINDOW, ConfigLoader.new({}).mattr_window
          assert_equal 50, ConfigLoader.new({ 'metrics' => { 'mattr_window' => 50 } }).mattr_window
        end

        def test_labels_returns_defaults
          loader = ConfigLoader.new({})
          labels = loader.labels

          assert_equal '加筆検討', labels[:too_short]
          assert_equal 'やや長い', labels[:too_long]
        end

        def test_labels_can_be_customized
          config = { 'metrics' => { 'labels' => { 'too_short' => 'SHORT!' } } }
          loader = ConfigLoader.new(config)
          labels = loader.labels

          assert_equal 'SHORT!', labels[:too_short]
          assert_equal 'やや長い', labels[:too_long]
        end
      end
    end
  end
end
