# frozen_string_literal: true

# ================================================================
# Test: renumber_commands_test.rb
# ================================================================
# テスト対象:
#   RenumberCommands モジュール（lib/vivlio/starter/cli/renumber.rb）
#
# 検証内容:
#   - RenumberCommands モジュールの存在確認
#
# 備考:
#   renumber は rename の別名として Samovar で実装されている。
#   実際の連番付け直しロジックは RenameCommandExecutor でテストされる。
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'vivlio/starter/cli/common'
require 'vivlio/starter/cli/rename'
require 'vivlio/starter/cli/renumber'

module Vivlio
  module Starter
    module CLI
      # RenumberCommands のユニットテスト
      class RenumberCommandsTest < Minitest::Test
        # RenumberCommands モジュールが存在することを確認
        def test_renumber_module_exists
          assert defined?(RenumberCommands), 'RenumberCommands モジュールが存在するはずです'
        end
      end
    end
  end
end
