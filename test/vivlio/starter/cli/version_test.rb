# frozen_string_literal: true

# ================================================================
# Test: version_test.rb
# ================================================================
# テスト対象:
#   Vivlio::Starter::VERSION（lib/vivlio/starter/version.rb）
#
# 検証内容:
#   - セマンティックバージョン形式（X.Y.Z）の検証
# ================================================================

require 'test_helper'
require 'vivlio/starter/version'

module Vivlio
  module Starter
    module CLI
      # VERSION 定数のユニットテスト
      class VersionTest < Minitest::Test
        # バージョン定数がセマンティックバージョン形式であることを確認
        def test_semver_format
          assert_match(/\A\d+\.\d+\.\d+\z/, Vivlio::Starter::VERSION)
        end
      end
    end
  end
end
