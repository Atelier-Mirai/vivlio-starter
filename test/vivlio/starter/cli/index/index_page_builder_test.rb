# frozen_string_literal: true

require 'test_helper'
require 'vivlio/starter/cli/index/index_page_builder'
require 'tmpdir'
require 'fileutils'

module Vivlio
  module Starter
    module CLI
      module IndexCommands
        class IndexPageBuilderTest < Minitest::Test
          # --- phase: setup ---

          def setup
            @original_dir = Dir.pwd
            @temp_dir = Dir.mktmpdir('index_page_test')
            Dir.chdir(@temp_dir)
            @builder = IndexPageBuilder.new
          end

          def teardown
            Dir.chdir(@original_dir)
            FileUtils.rm_rf(@temp_dir)
          end

          # --- phase: build! tests ---

          def test_build_returns_nil_when_cache_missing
            result = @builder.build!

            assert_nil result
          end

          def test_build_creates_html_file
            create_sample_index_cache

            result = @builder.build!('_index_matches.yml', '_indexpage.html')

            assert_equal '_indexpage.html', result
            assert File.exist?('_indexpage.html')
          end

          def test_build_generates_valid_html_structure
            create_sample_index_cache

            @builder.build!

            html = File.read('_indexpage.html')
            assert_includes html, '<!DOCTYPE html>'
            assert_includes html, '<html lang="ja">'
            assert_includes html, '<title>索引</title>'
            assert_includes html, 'class="index-page"'
          end

          def test_build_groups_terms_by_kana_row
            cache_data = {
              'generated_at' => Time.now.iso8601,
              'total_matches' => 3,
              'terms' => {
                'あいう' => [{ 'yomi' => 'あいう', 'link' => '01.html#1' }],
                'かきく' => [{ 'yomi' => 'かきく', 'link' => '01.html#2' }],
                'さしす' => [{ 'yomi' => 'さしす', 'link' => '01.html#3' }]
              }
            }
            File.write('_index_matches.yml', cache_data.to_yaml)

            @builder.build!

            html = File.read('_indexpage.html')
            assert_includes html, 'data-initial="あ"'
            assert_includes html, 'data-initial="か"'
            assert_includes html, 'data-initial="さ"'
          end

          def test_build_handles_english_terms
            cache_data = {
              'generated_at' => Time.now.iso8601,
              'total_matches' => 2,
              'terms' => {
                'CSS' => [{ 'yomi' => 'CSS', 'link' => '01.html#1' }],
                'Ruby' => [{ 'yomi' => 'Ruby', 'link' => '01.html#2' }]
              }
            }
            File.write('_index_matches.yml', cache_data.to_yaml)

            @builder.build!

            html = File.read('_indexpage.html')
            assert_includes html, 'data-initial="C"'
            assert_includes html, 'data-initial="R"'
          end

          def test_build_handles_symbols
            cache_data = {
              'generated_at' => Time.now.iso8601,
              'total_matches' => 1,
              'terms' => {
                '!' => [{ 'yomi' => '!', 'link' => '01.html#1' }]
              }
            }
            File.write('_index_matches.yml', cache_data.to_yaml)

            @builder.build!

            html = File.read('_indexpage.html')
            assert_includes html, 'data-initial="記号"'
          end

          def test_build_handles_numbers
            cache_data = {
              'generated_at' => Time.now.iso8601,
              'total_matches' => 1,
              'terms' => {
                '404' => [{ 'yomi' => '404', 'link' => '01.html#1' }]
              }
            }
            File.write('_index_matches.yml', cache_data.to_yaml)

            @builder.build!

            html = File.read('_indexpage.html')
            assert_includes html, 'data-initial="数字"'
          end

          # --- phase: integration with HierarchicalIndex ---

          def test_build_deduplicates_same_page_links
            cache_data = {
              'generated_at' => Time.now.iso8601,
              'total_matches' => 3,
              'terms' => {
                'Ruby' => [
                  { 'yomi' => 'るびー', 'link' => '01.html#idx-1' },
                  { 'yomi' => 'るびー', 'link' => '01.html#idx-2' },
                  { 'yomi' => 'るびー', 'link' => '02.html#idx-3' }
                ]
              }
            }
            File.write('_index_matches.yml', cache_data.to_yaml)

            @builder.build!

            # HierarchicalIndex により同一ページは1リンクに集約される
            assert_equal 2, @builder.hierarchical_index.entries['Ruby'].size
          end

          private

          def create_sample_index_cache
            cache_data = {
              'generated_at' => Time.now.iso8601,
              'total_matches' => 2,
              'terms' => {
                'Ruby' => [
                  { 'yomi' => 'るびー', 'link' => '01-intro.html#idx-ruby-1' }
                ],
                'JavaScript' => [
                  { 'yomi' => 'じゃばすくりぷと', 'link' => '02-basics.html#idx-js-1' }
                ]
              }
            }
            File.write('_index_matches.yml', cache_data.to_yaml)
          end
        end
      end
    end
  end
end
