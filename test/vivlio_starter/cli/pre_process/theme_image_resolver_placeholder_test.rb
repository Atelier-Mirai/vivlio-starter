# frozen_string_literal: true

# ================================================================
# Test: theme_image_resolver_placeholder_test.rb
# ================================================================
# テスト対象:
#   ThemeImageResolver のプレースホルダー SVG の data URI
#
# 検証内容:
#   - data URI を読み戻すと正しい SVG になること。空白を `+` のままにすると、
#     data URI では空白に戻らず、`<svg+xmlns=…` という読めない SVG になる
# ================================================================

require 'test_helper'
require 'nokogiri'
require 'uri'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/pre_process'

module VivlioStarter
  module CLI
    class ThemeImageResolverPlaceholderTest < Minitest::Test
      TIR = PreProcessCommands::ThemeImageResolver

      def test_should_keep_placeholder_svg_readable_through_data_uri
        uri = TIR.svg_placeholder_uri(TIR::FRONTISPIECE_PLACEHOLDER_SVG, 'my image.webp')
        svg = URI.decode_uri_component(uri.delete_prefix('data:image/svg+xml;charset=utf-8,'))

        doc = Nokogiri::XML(svg, &:strict)

        assert_equal 'svg', doc.root.name
        assert_includes svg, 'my image.webp'
      end
    end
  end
end
