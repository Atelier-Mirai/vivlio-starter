# frozen_string_literal: true

# ================================================================
# Test: version_test.rb
# ================================================================
# テスト対象:
#   VivlioStarter::VERSION（lib/vivlio_starter/version.rb）
#
# 検証内容:
#   - セマンティックバージョン形式（X.Y.Z）の検証
# ================================================================

require 'test_helper'
require 'vivlio_starter/version'

module VivlioStarter
  module CLI
    # VERSION 定数のユニットテスト
    class VersionTest < Minitest::Test
      # バージョン定数がセマンティックバージョン形式であることを確認
      # pre-release 識別子（-alpha, -beta.1, -rc.2 等）にも対応
      def test_semver_format
        assert_match(/\A\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?\z/, VivlioStarter::VERSION)
      end
    end
  end
end
