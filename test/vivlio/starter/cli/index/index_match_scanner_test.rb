# frozen_string_literal: true

require 'test_helper'
require 'vivlio/starter/cli/index/index_match_scanner'
require 'tmpdir'
require 'fileutils'

module Vivlio
  module Starter
    module CLI
      module IndexCommands
        class IndexMatchScannerTest < Minitest::Test
          # --- phase: setup ---

          def setup
            @original_dir = Dir.pwd
            @temp_dir = Dir.mktmpdir('match_scanner_test')
            Dir.chdir(@temp_dir)
            FileUtils.mkdir_p('contents')
            FileUtils.mkdir_p('config')
            @scanner = IndexMatchScanner.new
          end

          def teardown
            Dir.chdir(@original_dir)
            FileUtils.rm_rf(@temp_dir)
          end

          # --- phase: scan_and_tag_file! tests ---

          def test_scan_detects_term_with_yomi
            File.write('01-test.md', <<~MD)
              # Test

              [Ruby|るびー]は素晴らしい言語です。
            MD

            @scanner.scan_and_tag_file!('01-test.md')

            assert_equal 1, @scanner.matches.size
            assert_equal 'Ruby', @scanner.matches[0]['term']
            assert_equal 'るびー', @scanner.matches[0]['yomi']
          end

          def test_scan_detects_term_without_yomi
            File.write('02-test.md', <<~MD)
              # Test

              [JavaScript]を学びましょう。
            MD

            @scanner.scan_and_tag_file!('02-test.md')

            assert_equal 1, @scanner.matches.size
            assert_equal 'JavaScript', @scanner.matches[0]['term']
          end

          def test_scan_excludes_markdown_links
            File.write('03-test.md', <<~MD)
              # Test

              [リンクテキスト](https://example.com)はスキップされる。
              [索引語]は検出される。
            MD

            @scanner.scan_and_tag_file!('03-test.md')

            assert_equal 1, @scanner.matches.size
            assert_equal '索引語', @scanner.matches[0]['term']
          end

          def test_scan_excludes_footnote_references
            File.write('04-test.md', <<~MD)
              # Test

              脚注参照[^1]はスキップされる。
              [有効な用語]は検出される。

              [^1]: 脚注の内容
            MD

            @scanner.scan_and_tag_file!('04-test.md')

            term_names = @scanner.matches.map { it['term'] }
            refute_includes term_names, '^1'
            assert_includes term_names, '有効な用語'
          end

          def test_scan_tags_first_occurrence_with_dfn
            File.write('05-test.md', <<~MD)
              # Test

              [Ruby]は初出です。
              [Ruby]は2回目です。
            MD

            @scanner.scan_and_tag_file!('05-test.md')

            assert_equal 2, @scanner.matches.size
            assert_equal 'dfn', @scanner.matches[0]['tag_type']
            assert_equal 'span', @scanner.matches[1]['tag_type']
          end

          def test_scan_excludes_code_blocks
            File.write('06-test.md', <<~MD)
              # Test

              ```ruby
              [コードブロック内]は除外される
              ```

              [本文の用語]は検出される。
            MD

            @scanner.scan_and_tag_file!('06-test.md')

            term_names = @scanner.matches.map { it['term'] }
            refute_includes term_names, 'コードブロック内'
            assert_includes term_names, '本文の用語'
          end

          def test_scan_handles_special_characters
            File.write('07-test.md', <<~MD)
              # Test

              [!]は否定演算子です。
              [&&]は論理積演算子です。
              [||]は論理和演算子です。
              [404]はエラーコードです。
            MD

            @scanner.scan_and_tag_file!('07-test.md')

            term_names = @scanner.matches.map { it['term'] }
            assert_includes term_names, '!'
            assert_includes term_names, '&&'
            assert_includes term_names, '||'
            assert_includes term_names, '404'
          end

          def test_scan_handles_html_like_terms
            File.write('08-test.md', <<~MD)
              # Test

              [<h1>]は見出しタグです。
              [</h1>]は閉じタグです。
              [!DOCTYPE]はHTML宣言です。
            MD

            @scanner.scan_and_tag_file!('08-test.md')

            term_names = @scanner.matches.map { it['term'] }
            assert_includes term_names, '<h1>'
            assert_includes term_names, '</h1>'
            assert_includes term_names, '!DOCTYPE'
          end

          # --- phase: read_only mode tests ---

          def test_scan_read_only_does_not_modify_file
            original_content = "[Ruby]は素晴らしい。\n"
            File.write('contents/09-test.md', original_content)

            @scanner.scan_and_tag_file!('contents/09-test.md', read_only: true)

            assert_equal original_content, File.read('contents/09-test.md')
            assert_equal 1, @scanner.matches.size
          end

          def test_scan_non_read_only_modifies_file
            File.write('10-test.md', "[Ruby]は素晴らしい。\n")

            @scanner.scan_and_tag_file!('10-test.md', read_only: false)

            content = File.read('10-test.md')
            assert_includes content, '<dfn'
            assert_includes content, 'class="index-term"'
          end

          # --- phase: scan_all_chapters! tests ---

          def test_scan_all_chapters_saves_matches
            File.write('11-a.md', "[用語A]を説明。\n")
            File.write('12-b.md', "[用語B]を説明。\n")

            @scanner.scan_all_chapters!(%w[11-a 12-b])

            assert File.exist?('_index_matches.yml')
            data = YAML.load_file('_index_matches.yml')
            assert_equal 2, data['total_matches']
          end

          # --- phase: auto indexing with config tests ---

          def test_scan_applies_config_terms
            config_content = <<~YAML
              terms:
                - term: Ruby
                  yomi: るびー
                  pattern: "/Ruby/"
            YAML
            File.write('config/index_terms.yml', config_content)

            # 新しいスキャナを作成（configを読み込むため）
            scanner = IndexMatchScanner.new
            File.write('13-test.md', "Rubyは素晴らしい言語です。\n")

            scanner.scan_and_tag_file!('13-test.md')

            assert scanner.matches.any? { it['term'] == 'Ruby' }
          end

          # --- phase: find_chapter_file tests ---

          def test_find_chapter_file_prefers_root_by_default
            File.write('chapter.md', 'root content')
            File.write('contents/chapter.md', 'contents content')

            result = @scanner.find_chapter_file('chapter', prefer_contents: false)

            assert_equal 'chapter.md', result
          end

          def test_find_chapter_file_prefers_contents_when_specified
            File.write('chapter.md', 'root content')
            File.write('contents/chapter.md', 'contents content')

            result = @scanner.find_chapter_file('chapter', prefer_contents: true)

            assert_equal 'contents/chapter.md', result
          end

          def test_find_chapter_file_returns_nil_when_missing
            result = @scanner.find_chapter_file('nonexistent')

            assert_nil result
          end
        end
      end
    end
  end
end
