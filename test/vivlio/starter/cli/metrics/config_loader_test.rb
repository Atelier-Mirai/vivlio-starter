# frozen_string_literal: true

require 'test_helper'
require 'vivlio/starter/cli/metrics/config_loader'

module Vivlio
  module Starter
    module CLI
      module Metrics
        class ConfigLoaderTest < Minitest::Test
          def test_volume_thresholds_returns_default_standard_preset
            loader = ConfigLoader.new({})
            thresholds = loader.volume_thresholds

            assert_equal 3000, thresholds[:chapter][:min]
            assert_equal 5000, thresholds[:chapter][:ideal_min]
            assert_equal 10_000, thresholds[:chapter][:ideal_max]
            assert_equal 15_000, thresholds[:chapter][:max]
          end

          def test_volume_thresholds_respects_use_setting
            config = { 'metrics' => { 'use' => 'compact' } }
            loader = ConfigLoader.new(config)
            thresholds = loader.volume_thresholds

            assert_equal 1000, thresholds[:chapter][:min]
            assert_equal 5000, thresholds[:chapter][:max]
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

            assert_equal 30, thresholds[:easy]
            assert_equal 60, thresholds[:standard]
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
end
