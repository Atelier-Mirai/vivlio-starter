# frozen_string_literal: true

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'vivlio/starter/cli/common'
require 'vivlio/starter/cli/build_helpers'
require 'vivlio/starter/cli/build'
require 'vivlio/starter/cli'

module Vivlio
  module Starter
    module CLI
      class SingleChapterRunnerTest < Minitest::Test
        # 単章ビルドが各ステップを正しい順で呼び出し、PDF 名を収集することを確認
        def test_run_invokes_thor_tasks_and_renames_output
          within_temp_dir do
            runner = build_runner('11-sample')
            calls = []

            Vivlio::Starter::ThorCLI.stub :start, ->(args) { calls << args } do
              FileUtils.touch('output.pdf')
              generated = runner.run

              expected_calls = [
                ['pre_process', '11-sample'],
                ['convert', '11-sample'],
                ['post_process', '11-sample'],
                ['entries', '11-sample'],
                ['pdf']
              ]
              assert_equal expected_calls, calls
              assert_equal ['11-sample.pdf'], generated
              assert File.exist?('11-sample.pdf'), '単章PDFが生成されるはずです'
            end
          end
        end

        private

        # テスト用 SingleChapterRunner を生成する
        def build_runner(chapter)
          command = Struct.new(:options).new({})
          Vivlio::Starter::CLI::BuildCommands::SingleChapterRunner.new(command, chapter)
        end

        # 一時ディレクトリで副作用を隔離する
        def within_temp_dir
          Dir.mktmpdir do |dir|
            Dir.chdir(dir) { yield dir }
          end
        end
      end
    end
  end
end
