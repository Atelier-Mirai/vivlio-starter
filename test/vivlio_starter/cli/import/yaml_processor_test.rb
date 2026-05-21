# frozen_string_literal: true

require_relative '../../../test_helper'
require 'vivlio_starter/cli/import/yaml_processor'
require 'vivlio_starter/cli/common'

module VivlioStarter
  module CLI
    module Import
      class YamlProcessorTest < Minitest::Test
        # ================================================================
        # strip_re_extension テスト
        # ================================================================
        def test_strip_re_extension_string
          assert_equal '01-intro', YamlProcessor.strip_re_extension('01-intro.re')
        end

        def test_strip_re_extension_string_without_re
          assert_equal '01-intro', YamlProcessor.strip_re_extension('01-intro')
        end

        def test_strip_re_extension_array
          input = ['01-intro.re', '02-chapter.re']
          expected = ['01-intro', '02-chapter']
          assert_equal expected, YamlProcessor.strip_re_extension(input)
        end

        def test_strip_re_extension_hash
          input = { '01-intro.re' => 'value' }
          expected = { '01-intro' => 'value' }
          assert_equal expected, YamlProcessor.strip_re_extension(input)
        end

        def test_strip_re_extension_nested
          input = {
            'chapter.re' => ['section1.re', 'section2.re']
          }
          expected = {
            'chapter' => ['section1', 'section2']
          }
          assert_equal expected, YamlProcessor.strip_re_extension(input)
        end

        def test_strip_re_extension_nil
          assert_nil YamlProcessor.strip_re_extension(nil)
        end

        def test_strip_re_extension_number
          assert_equal 42, YamlProcessor.strip_re_extension(42)
        end
      end
    end
  end
end
