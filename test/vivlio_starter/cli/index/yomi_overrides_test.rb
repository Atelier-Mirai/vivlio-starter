# frozen_string_literal: true

# ================================================================
# Test: index/yomi_overrides_test.rb
# ================================================================
# テスト対象:
#   IndexCommands::YomiOverrides（読みの個人辞書の読み書き）
# ================================================================

require 'test_helper'
require 'vivlio_starter/cli/index/yomi_overrides'
require 'tmpdir'
require 'fileutils'
require 'yaml'

module VivlioStarter
  module CLI
    module IndexCommands
      class YomiOverridesTest < Minitest::Test
        def setup
          @original_dir = Dir.pwd
          @temp_dir = Dir.mktmpdir('yomi_overrides_test')
          Dir.chdir(@temp_dir)
          FileUtils.mkdir_p('config')
        end

        def teardown
          Dir.chdir(@original_dir)
          FileUtils.rm_rf(@temp_dir)
        end

        def test_load_returns_empty_without_file
          assert_empty YomiOverrides.load
        end

        def test_merge_adds_new_entries_and_saves_sorted
          written, skipped = YomiOverrides.merge!({ '重力' => 'じゅうりょく', '碍子' => 'がいし' })

          assert_equal 2, written
          assert_equal 0, skipped
          assert_equal({ '碍子' => 'がいし', '重力' => 'じゅうりょく' }, YomiOverrides.load)
        end

        def test_merge_keeps_existing_by_default
          YomiOverrides.merge!({ '重力' => 'じゅうりょく' })
          written, skipped = YomiOverrides.merge!({ '重力' => 'ちから' })

          assert_equal 0, written
          assert_equal 1, skipped
          assert_equal 'じゅうりょく', YomiOverrides.load['重力']
        end

        def test_merge_overwrites_with_prefer_import
          YomiOverrides.merge!({ '重力' => 'じゅうりょく' })
          written, skipped = YomiOverrides.merge!({ '重力' => 'ちから' }, prefer_import: true)

          assert_equal 1, written
          assert_equal 0, skipped
          assert_equal 'ちから', YomiOverrides.load['重力']
        end

        def test_merge_ignores_blank_entries
          written, = YomiOverrides.merge!({ '' => 'よみ', '語' => '' })

          assert_equal 0, written
        end
      end
    end
  end
end
