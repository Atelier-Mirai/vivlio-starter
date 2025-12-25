# frozen_string_literal: true

# ================================================================
# Test: glossary_commands_test.rb
# ================================================================
# テスト対象:
#   GlossaryLintCommands（lib/vivlio/starter/cli/glossary/lint_commands.rb）
#
# 検証内容:
#   - 用語集違反がない場合の正常終了
#   - 用語集違反がある場合の exit(2)
#   - 違反箇所の検出と報告
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'vivlio/starter/cli'
require 'vivlio/starter/cli/glossary'

module Vivlio
  module Starter
    module CLI
      # GlossaryLintCommands のユニットテスト
      class GlossaryCommandsTest < Minitest::Test
        # 用語集違反がない場合に成功メッセージが出力されることを確認
        def test_glossary_lint_passes_with_clean_content
          within_temp_dir do
            setup_glossary({ 'terms' => [{ 'name' => 'Ruby', 'abbr' => 'Ruby', 'aliases' => [] }] })
            write_markdown('contents/11-sample.md', "# Title\nRuby は楽しい\n")

            output = capture_io { GlossaryLintCommands.execute_glossary_lint }.first

            assert_includes output, '[glossary:lint] OK'
          end
        end

        # 用語集違反がある場合に exit(2) となることを確認
        def test_glossary_lint_exits_with_violations
          within_temp_dir do
            setup_glossary({ 'terms' => [{ 'name' => 'Ruby', 'abbr' => 'Ruby', 'aliases' => ['ルビー'] }] })
            write_markdown('contents/11-sample.md', "# Title\nルビー は楽しい\n")

            error = assert_raises(SystemExit) { capture_io { GlossaryLintCommands.execute_glossary_lint } }
            assert_equal 2, error.status
          end
        end

        private

        def within_temp_dir
          Dir.mktmpdir do |dir|
            Dir.chdir(dir) do
              FileUtils.mkdir_p('contents')
              yield dir
            end
          end
        end

        def setup_glossary(data)
          FileUtils.mkdir_p('config')
          File.write('config/glossary.yml', data.to_yaml)
        end

        def write_markdown(path, content)
          FileUtils.mkdir_p(File.dirname(path))
          File.write(path, content)
        end
      end
    end
  end
end
