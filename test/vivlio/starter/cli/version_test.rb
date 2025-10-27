# frozen_string_literal: true

require 'test_helper'
require 'vivlio/starter/version'

module Vivlio
  module Starter
    module CLI
      class VersionTest < Minitest::Test
        # バージョン定数がセマンティックバージョン形式で定義されていることを確認
        def test_semver_format
          assert_match(/\A\d+\.\d+\.\d+\z/, Vivlio::Starter::VERSION)
        end
      end
    end
  end
end
