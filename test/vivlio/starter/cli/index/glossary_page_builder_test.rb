# frozen_string_literal: true

# ================================================================
# Test: glossary_page_builder_test.rb
# ----------------------------------------------------------------
# テスト対象:
#   GlossaryPageBuilder（lib/vivlio/starter/cli/index/glossary_page_builder.rb）
#
# 検証内容:
#   - 用語集ページの HTML 生成
#   - 読み順ソート
#   - 行グループ化（あ行、か行など）
#   - 説明文の Markdown 変換
#   - backlink の生成
# ================================================================

require 'test_helper'
require 'vivlio/starter/cli/index/glossary_page_builder'
require 'vivlio/starter/cli/index/glossary_terms_manager'
require 'tmpdir'
require 'fileutils'

module Vivlio
  module Starter
    module CLI
      class GlossaryPageBuilderTest < Minitest::Test
        # --- phase: setup ---

        def setup
          @original_dir = Dir.pwd
          @temp_dir = Dir.mktmpdir('glossary_builder_test')
          Dir.chdir(@temp_dir)
          FileUtils.mkdir_p('config')
          FileUtils.mkdir_p('stylesheets')
          @builder = GlossaryPageBuilder.new
        end

        def teardown
          Dir.chdir(@original_dir)
          FileUtils.rm_rf(@temp_dir)
        end

        # --- phase: build! tests ---

        def test_build_returns_nil_when_no_terms
          result = @builder.build!

          assert_nil result
        end

        def test_build_creates_html_file
          setup_terms([
            { 'term' => 'Ruby', 'yomi' => 'るびー', 'definition' => 'プログラミング言語' }
          ])

          result = @builder.build!

          assert_equal '_glossarypage.html', result
          assert File.exist?('_glossarypage.html')
        end

        def test_build_includes_term_in_html
          setup_terms([
            { 'term' => 'JavaScript', 'yomi' => 'じゃばすくりぷと', 'definition' => 'Web言語' }
          ])

          @builder.build!

          content = File.read('_glossarypage.html')
          assert_includes content, 'JavaScript'
          assert_includes content, 'じゃばすくりぷと'
        end

        def test_build_includes_definition_in_html
          setup_terms([
            { 'term' => 'Ruby', 'yomi' => 'るびー', 'definition' => 'まつもとゆきひろが作成した言語' }
          ])

          @builder.build!

          content = File.read('_glossarypage.html')
          assert_includes content, 'まつもとゆきひろが作成した言語'
        end

        def test_build_converts_markdown_in_definition
          setup_terms([
            { 'term' => 'Ruby', 'yomi' => 'るびー', 'definition' => '**強調**と`コード`を含む説明' }
          ])

          @builder.build!

          content = File.read('_glossarypage.html')
          assert_includes content, '<strong>強調</strong>'
          assert_includes content, '<code>コード</code>'
        end

        def test_build_groups_terms_by_initial
          setup_terms([
            { 'term' => 'あいうえお', 'yomi' => 'あいうえお', 'definition' => '説明1' },
            { 'term' => 'かきくけこ', 'yomi' => 'かきくけこ', 'definition' => '説明2' }
          ])

          @builder.build!

          content = File.read('_glossarypage.html')
          assert_includes content, 'glossary-group-header'
        end

        def test_build_sorts_terms_by_yomi
          setup_terms([
            { 'term' => 'Python', 'yomi' => 'ぱいそん', 'definition' => '説明2' },
            { 'term' => 'Ruby', 'yomi' => 'るびー', 'definition' => '説明1' }
          ])

          @builder.build!

          content = File.read('_glossarypage.html')
          # ぱいそん（は行）が るびー（ら行）より先に来る
          python_pos = content.index('Python')
          ruby_pos = content.index('Ruby')
          assert python_pos < ruby_pos, 'Terms should be sorted by yomi'
        end

        def test_build_includes_backlinks
          setup_terms([
            {
              'term' => 'Ruby',
              'yomi' => 'るびー',
              'definition' => '言語',
              'backlink_sources' => [
                { 'chapter' => '01-intro', 'occurrence' => 1 }
              ]
            }
          ])

          @builder.build!

          content = File.read('_glossarypage.html')
          assert_includes content, 'glossary-backlink'
          assert_includes content, 'gls-src-01-intro-1'
        end

        private

        def setup_terms(terms)
          data = {
            'generated_at' => Time.now.strftime('%Y-%m-%d %H:%M:%S'),
            'terms' => terms
          }
          File.write('config/glossary_terms.yml', data.to_yaml)
        end
      end
    end
  end
end
