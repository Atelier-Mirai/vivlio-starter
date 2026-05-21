# frozen_string_literal: true

require 'test_helper'
require 'vivlio_starter/cli/index/unified_page_builder'
require 'tmpdir'
require 'fileutils'

module VivlioStarter
  module CLI
    module IndexCommands
      class UnifiedPageBuilderTest < Minitest::Test
        def setup
          @original_dir = Dir.pwd
          @temp_dir = Dir.mktmpdir('unified_page_builder_test')
          Dir.chdir(@temp_dir)
          @builder = UnifiedPageBuilder.new
        end

        def teardown
          Dir.chdir(@original_dir)
          FileUtils.rm_rf(@temp_dir)
        end

        # === 索引ページ ===

        def test_build_index_returns_nil_when_no_cache
          result = @builder.build_index!

          assert_nil result
        end

        def test_build_index_creates_html
          create_index_cache('CSS' => [{ 'yomi' => 'CSS', 'link' => '01.html#1' }])

          result = @builder.build_index!

          assert_equal '_indexpage.html', result
          assert File.exist?('_indexpage.html')
        end

        def test_build_index_generates_valid_structure
          create_index_cache('CSS' => [{ 'yomi' => 'CSS', 'link' => '01.html#1' }])

          @builder.build_index!

          html = File.read('_indexpage.html')
          assert_includes html, '<!DOCTYPE html>'
          assert_includes html, '<title>索引</title>'
          assert_includes html, 'class="index-page"'
          assert_includes html, 'CSS'
        end

        def test_build_index_groups_by_kana_row
          create_index_cache(
            'あいう' => [{ 'yomi' => 'あいう', 'link' => '01.html#1' }],
            'かきく' => [{ 'yomi' => 'かきく', 'link' => '01.html#2' }]
          )

          @builder.build_index!

          html = File.read('_indexpage.html')
          assert_includes html, 'data-initial="あ"'
          assert_includes html, 'data-initial="か"'
        end

        def test_build_index_returns_nil_when_empty
          create_index_cache({})

          result = @builder.build_index!

          assert_nil result
        end

        def test_build_index_removes_stale_file
          File.write('_indexpage.html', '<html>stale</html>')
          create_index_cache({})

          @builder.build_index!

          refute File.exist?('_indexpage.html')
        end

        # === 用語集ページ ===

        def test_build_glossary_returns_nil_when_no_terms
          result = @builder.build_glossary!([])

          assert_nil result
        end

        def test_build_glossary_creates_html
          terms = [{ 'term' => 'CSS', 'yomi' => 'CSS', 'definition' => 'スタイルシート言語', 'flags' => 'g' }]

          result = @builder.build_glossary!(terms)

          assert_equal '_glossarypage.html', result
          assert File.exist?('_glossarypage.html')
        end

        def test_build_glossary_includes_definition
          terms = [{ 'term' => 'CSS', 'yomi' => 'CSS', 'definition' => 'スタイルシート言語', 'flags' => 'g' }]

          @builder.build_glossary!(terms)

          html = File.read('_glossarypage.html')
          assert_includes html, 'スタイルシート言語'
          assert_includes html, 'CSS'
        end

        def test_build_glossary_includes_backlinks
          terms = [{
            'term' => 'CSS', 'yomi' => 'CSS', 'definition' => 'テスト', 'flags' => 'g',
            'backlink_sources' => [
              { 'chapter' => '01-intro', 'occurrence' => 1, 'anchor_id' => 'gls-src-01-intro-css-1' }
            ]
          }]

          @builder.build_glossary!(terms)

          html = File.read('_glossarypage.html')
          assert_includes html, 'gls-src-01-intro-css-1'
          assert_includes html, 'glossary-backlink'
        end

        def test_build_glossary_removes_stale_file
          File.write('_glossarypage.html', '<html>stale</html>')

          @builder.build_glossary!([])

          refute File.exist?('_glossarypage.html')
        end

        def test_build_glossary_groups_by_initial
          terms = [
            { 'term' => 'あいう', 'yomi' => 'あいう', 'definition' => 'テスト1', 'flags' => 'g' },
            { 'term' => 'かきく', 'yomi' => 'かきく', 'definition' => 'テスト2', 'flags' => 'g' }
          ]

          @builder.build_glossary!(terms)

          html = File.read('_glossarypage.html')
          assert_includes html, 'glossary-group-header'
        end

        def test_build_glossary_with_custom_title
          builder = UnifiedPageBuilder.new(glossary_config: { title: 'カスタム用語集' })
          terms = [{ 'term' => 'CSS', 'yomi' => 'CSS', 'definition' => 'テスト', 'flags' => 'g' }]

          builder.build_glossary!(terms)

          html = File.read('_glossarypage.html')
          assert_includes html, 'カスタム用語集'
        end

        # === 統合テスト ===

        def test_both_pages_can_be_built_sequentially
          create_index_cache('CSS' => [{ 'yomi' => 'CSS', 'link' => '01.html#1' }])
          terms = [{ 'term' => 'CSS', 'yomi' => 'CSS', 'definition' => 'スタイルシート', 'flags' => 'ig',
                     'backlink_sources' => [{ 'chapter' => '01', 'occurrence' => 1, 'anchor_id' => 'gls-src-01-css-1' }] }]

          @builder.build_index!
          @builder.build_glossary!(terms)

          assert File.exist?('_indexpage.html')
          assert File.exist?('_glossarypage.html')

          glossary_html = File.read('_glossarypage.html')
          assert_includes glossary_html, 'gls-src-01-css-1'
        end

        private

        def create_index_cache(terms_hash)
          data = {
            'generated_at' => Time.now.iso8601,
            'total_matches' => terms_hash.values.sum { it.size },
            'terms' => terms_hash
          }
          File.write('_index_matches.yml', data.to_yaml)
        end
      end
    end
  end
end
