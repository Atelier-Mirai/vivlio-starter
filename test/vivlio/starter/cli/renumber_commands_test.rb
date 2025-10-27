# frozen_string_literal: true

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'vivlio/starter/cli/common'
require 'vivlio/starter/cli/rename'
require 'vivlio/starter/cli/renumber'

module Vivlio
  module Starter
    module CLI
      class RenumberCommandsTest < Minitest::Test
        # renumber が rename を委譲して実行することを確認
        def test_renumber_delegates_to_rename
          within_temp_dir do
            command = build_renumber_command
            invoked = []

            command.stub :invoke, ->(name, args, forwarded_opts) { invoked << [name, args, forwarded_opts] } do
              command.renumber('11-old', '12-new')
            end

            assert_equal [[:rename, ['11-old', '12-new'], command.options]], invoked
          end
        end

        private

        # テスト用 Renumber コマンドを生成
        def build_renumber_command
          Class.new do
            # Thor DSL のスタブ
            def self.desc(*) = nil
            def self.long_desc(*) = nil
            def self.method_option(*) = nil

            include RenumberCommands

            def invoke(*)
              raise NotImplementedError
            end

            def options
              { force: false, dry_run: false }
            end
          end.new
        end

        # 一時ディレクトリで実行
        def within_temp_dir
          Dir.mktmpdir do |dir|
            Dir.chdir(dir) do
              FileUtils.mkdir_p(Common::CONTENTS_DIR)
              yield dir
            end
          end
        end
      end
    end
  end
end
