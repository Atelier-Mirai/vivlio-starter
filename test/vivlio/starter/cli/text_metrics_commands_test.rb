# frozen_string_literal: true

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'json'
require 'vivlio/starter/cli'
require 'vivlio/starter/cli/text_metrics'

module Vivlio
  module Starter
    module CLI
      class TextMetricsCommandsTest < Minitest::Test
        # 対象 Markdown が見つからない場合に警告を出力することを確認
        def test_text_metrics_warns_when_no_targets
          within_temp_dir do
            command = build_text_metrics_command

            output = capture_io { command.text_metrics('missing') }.first

            assert_includes output, '見つかりません'
          end
        end

        # JSON 出力オプションで統計が JSON 形式になることを確認
        def test_text_metrics_outputs_json
          within_temp_dir do
            command = build_text_metrics_command(json: true)
            write_markdown('contents/11-sample.md', "本文。テストです、はい。\n")

            output = capture_io { command.text_metrics }.first
            parsed = JSON.parse(output)

            assert_equal ['stats', 'totals'], parsed.keys.sort
            assert_equal 'contents/11-sample.md', parsed['stats'].first['path']
          end
        end

        private

        def build_text_metrics_command(options = {})
          Class.new do
            # Thor DSL のスタブ
            def self.desc(*) = nil
            def self.long_desc(*) = nil
            def self.option(*) = nil

            include TextMetricsCommands

            attr_reader :options

            def initialize(options)
              @options = options
            end
          end.new(options)
        end

        def within_temp_dir
          Dir.mktmpdir do |dir|
            Dir.chdir(dir) do
              FileUtils.mkdir_p('contents')
              yield dir
            end
          end
        end

        def write_markdown(path, content)
          FileUtils.mkdir_p(File.dirname(path))
          File.write(path, content)
        end
      end
    end
  end
end
