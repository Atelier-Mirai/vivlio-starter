# frozen_string_literal: true

require 'test_helper'
require 'vivlio_starter/cli/metrics/cache'

module VivlioStarter
  module CLI
    module Metrics
      class CacheTest < Minitest::Test
        def setup
          @tmp_dir = Dir.mktmpdir
          @cache_dir = File.join(@tmp_dir, '.cache', 'metrics')
          @source_file = File.join(@tmp_dir, 'contents', '01-intro.md')

          FileUtils.mkdir_p(File.dirname(@source_file))
          File.write(@source_file, '# Intro')

          @cache = Cache.new(cache_dir: @cache_dir)
        end

        def teardown
          FileUtils.rm_rf(@tmp_dir)
          ENV.delete('VIVLIO_METRICS_CACHE')
        end

        def test_enabled_returns_true_by_default
          assert @cache.enabled?
        end

        def test_enabled_returns_false_when_env_set_to_zero
          ENV['VIVLIO_METRICS_CACHE'] = '0'

          refute @cache.enabled?
        end

        def test_fresh_returns_false_when_cache_not_exists
          refute @cache.fresh?('01-intro', @source_file)
        end

        def test_fresh_returns_true_when_cache_newer_than_reference
          @cache.ensure_cache_dir!
          cache_path = @cache.cache_file_path('01-intro')
          File.write(cache_path, { 'title' => 'Test' }.to_yaml)

          # キャッシュをソースより新しくする
          sleep 0.01
          FileUtils.touch(cache_path)

          assert @cache.fresh?('01-intro', @source_file)
        end

        def test_fresh_returns_false_when_source_newer_than_cache
          @cache.ensure_cache_dir!
          cache_path = @cache.cache_file_path('01-intro')
          File.write(cache_path, { 'title' => 'Test' }.to_yaml)

          # ソースをキャッシュより新しくする
          sleep 0.01
          FileUtils.touch(@source_file)

          refute @cache.fresh?('01-intro', @source_file)
        end

        def test_write_creates_cache_file
          data = { 'title' => 'Test Chapter', 'chars' => 1000 }

          @cache.write('01-intro', data)

          cache_path = @cache.cache_file_path('01-intro')
          assert File.exist?(cache_path)
        end

        def test_read_returns_cache_entry_when_fresh
          @cache.ensure_cache_dir!
          data = { 'title' => 'Test Chapter', 'chars' => 1000 }
          cache_path = @cache.cache_file_path('01-intro')
          File.write(cache_path, data.to_yaml)

          # キャッシュを新しくする
          sleep 0.01
          FileUtils.touch(cache_path)

          entry = @cache.read('01-intro', @source_file)

          assert_instance_of CacheEntry, entry
          assert_equal '01-intro', entry.basename
          assert_equal 'Test Chapter', entry.data['title']
          assert_equal 1000, entry.data['chars']
        end

        def test_read_returns_nil_when_not_fresh
          @cache.ensure_cache_dir!
          data = { 'title' => 'Test Chapter' }
          cache_path = @cache.cache_file_path('01-intro')
          File.write(cache_path, data.to_yaml)

          # ソースを新しくする
          sleep 0.01
          FileUtils.touch(@source_file)

          entry = @cache.read('01-intro', @source_file)

          assert_nil entry
        end

        def test_clear_removes_cache_directory
          @cache.ensure_cache_dir!
          @cache.write('01-intro', { 'title' => 'Test' })

          assert Dir.exist?(@cache_dir)

          @cache.clear!

          refute Dir.exist?(@cache_dir)
        end

        def test_cache_file_path_returns_yml_extension
          path = @cache.cache_file_path('01-intro')

          assert_match(/01-intro\.yml\z/, path)
        end
      end
    end
  end
end
