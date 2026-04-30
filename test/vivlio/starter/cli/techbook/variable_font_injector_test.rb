# frozen_string_literal: true

require_relative '../../../../test_helper'
require_relative '../../../../../lib/vivlio/starter/cli/techbook/variable_font_injector'

module Vivlio
  module Starter
    module CLI
      module Techbook
        class VariableFontInjectorTest < Minitest::Test
          def test_should_generate_font_face_for_each_instance
            configs = [
              {
                family: "Noto Sans JP",
                src: "fonts/NotoSansJP-VF.woff2",
                instances: [
                  { weight: 400, settings: '"wght" 400' },
                  { weight: 700, settings: '"wght" 700' }
                ]
              }
            ]
            injector = VariableFontInjector.new(configs)

            result = injector.css

            assert_equal 2, result.scan("@font-face").count
            assert_includes result, 'font-family: "Noto Sans JP-400"'
            assert_includes result, 'font-family: "Noto Sans JP-700"'
          end

          def test_should_return_empty_css_when_no_configs
            injector = VariableFontInjector.new([])

            result = injector.css

            assert_equal "", result
          end

          def test_should_skip_entry_missing_family
            configs = [
              {
                src: "fonts/NotoSansJP-VF.woff2",
                instances: [{ weight: 400, settings: '"wght" 400' }]
              }
            ]
            injector = VariableFontInjector.new(configs)

            result = injector.css

            assert_equal "", result
          end

          def test_should_skip_entry_missing_src
            configs = [
              {
                family: "Noto Sans JP",
                instances: [{ weight: 400, settings: '"wght" 400' }]
              }
            ]
            injector = VariableFontInjector.new(configs)

            result = injector.css

            assert_equal "", result
          end

          def test_should_skip_entry_missing_instances
            configs = [
              {
                family: "Noto Sans JP",
                src: "fonts/NotoSansJP-VF.woff2"
              }
            ]
            injector = VariableFontInjector.new(configs)

            result = injector.css

            assert_equal "", result
          end

          def test_should_derive_font_family_name_with_weight
            configs = [
              {
                family: "Noto Sans JP",
                src: "fonts/NotoSansJP-VF.woff2",
                instances: [{ weight: 400, settings: '"wght" 400' }]
              }
            ]
            injector = VariableFontInjector.new(configs)

            result = injector.css

            assert_includes result, 'font-family: "Noto Sans JP-400"'
            assert_includes result, 'src: url("fonts/NotoSansJP-VF.woff2") format("woff2")'
            assert_includes result, "font-weight: 400"
            assert_includes result, "font-style: normal"
            assert_includes result, 'font-variation-settings: "wght" 400'
          end
        end
      end
    end
  end
end
