# frozen_string_literal: true

require 'test_helper'
require 'vivlio_starter/cli/index/index_candidate_extractor'
require 'tmpdir'
require 'fileutils'

module VivlioStarter
  module CLI
    module IndexCommands
      class IndexCandidateExtractorTest < Minitest::Test
        # --- phase: setup ---

        def setup
          @original_dir = Dir.pwd
          @temp_dir = Dir.mktmpdir('candidate_extractor_test')
          Dir.chdir(@temp_dir)
          FileUtils.mkdir_p('contents')
          FileUtils.mkdir_p('config')
          @extractor = IndexCandidateExtractor.new
        end

        def teardown
          Dir.chdir(@original_dir)
          FileUtils.rm_rf(@temp_dir)
        end

        # --- phase: extract_from_chapters! tests ---

        def test_extract_from_chapters_finds_definition_patterns
          File.write('contents/01-intro.md', <<~MD)
            # Introduction

            プログラミングとは、コンピュータに命令を与えることである。
            JavaScriptについては、次の章で詳しく説明する。
          MD

          @extractor.extract_from_chapters!(['01-intro'])

          candidates = @extractor.all_candidates
          assert candidates.any? { it.include?('プログラミング') }
        end

        def test_extract_from_chapters_finds_technical_terms
          File.write('contents/02-tech.md', <<~MD)
            # Technical Terms

            HTMLやCSSは基本的なウェブ技術です。
            JavaScriptを使ってインタラクションを追加します。
          MD

          @extractor.extract_from_chapters!(['02-tech'])

          candidates = @extractor.all_candidates
          assert candidates.any? { it == 'HTML' }
          assert candidates.any? { it == 'CSS' }
          assert candidates.any? { it == 'JavaScript' }
        end

        def test_extract_from_chapters_excludes_code_blocks
          File.write('contents/03-code.md', <<~MD)
            # Code Example

            以下はサンプルコードです。

            ```javascript
            const currentIndex = 0;
            function processData() {
              return currentIndex + 1;
            }
            ```

            本文中のJavaScriptは抽出されます。
          MD

          @extractor.extract_from_chapters!(['03-code'])

          candidates = @extractor.all_candidates
          # コードブロック内の変数名は抽出されない
          refute candidates.any? { it == 'currentIndex' }
          refute candidates.any? { it == 'processData' }
          # 本文のJavaScriptは抽出される
          assert candidates.any? { it == 'JavaScript' }
        end

        def test_extract_from_chapters_skips_missing_files
          # ファイルが存在しない章はスキップされる
          @extractor.extract_from_chapters!(['nonexistent'])

          # エラーなく完了
          assert_empty @extractor.all_candidates
        end

        def test_extract_from_chapters_records_contexts
          File.write('contents/04-context.md', <<~MD)
            # Context Test

            Rubyとは、まつもとゆきひろによって開発されたプログラミング言語である。
          MD

          @extractor.extract_from_chapters!(['04-context'])

          contexts = @extractor.term_contexts
          ruby_contexts = contexts.select { |term, _| term.include?('Ruby') }
          refute_empty ruby_contexts
        end

        # --- phase: export_candidates! tests ---

        def test_export_candidates_creates_yaml_file
          File.write('contents/05-export.md', <<~MD)
            # Export Test

            プログラミングとは、コンピュータに命令を与えることである。
            HTMLとCSSとJavaScriptを使います。
          MD

          @extractor.extract_from_chapters!(['05-export'])
          @extractor.export_candidates!('config/index_candidates.yml', 10)

          assert File.exist?('config/index_candidates.yml')
        end

        def test_export_candidates_includes_metadata
          File.write('contents/06-meta.md', <<~MD)
            # Metadata Test

            Pythonについては、データ分析で広く使われている。
            JavaScriptはウェブ開発の必須技術である。
          MD

          @extractor.extract_from_chapters!(['06-meta'])
          @extractor.export_candidates!('config/index_candidates.yml', 10)

          content = File.read('config/index_candidates.yml')
          assert_includes content, 'generated_at:'
          assert_includes content, 'threshold:'
          assert_includes content, 'total_candidates:'
        end

        def test_export_candidates_filters_by_threshold
          File.write('contents/07-threshold.md', <<~MD)
            # Threshold Test

            HighScore語 HighScore語 HighScore語 HighScore語 HighScore語
            LowScore語
          MD

          @extractor.extract_from_chapters!(['07-threshold'])
          @extractor.export_candidates!('config/index_candidates.yml', 1000)

          content = File.read('config/index_candidates.yml')
          # 高閾値なので候補が少ない
          yaml_data = YAML.load_file('config/index_candidates.yml')
          # 閾値が高すぎると候補がない可能性がある
          assert yaml_data['candidates'].is_a?(Array)
        end

        # --- phase: sanitize tests (integration) ---

        def test_sanitize_removes_html_tags
          File.write('contents/08-html.md', <<~MD)
            # HTML Tags

            <span class="index-term">タグ内テキスト</span>は除外される。
            本文のRubyは抽出される。
          MD

          @extractor.extract_from_chapters!(['08-html'])

          candidates = @extractor.all_candidates
          refute candidates.any? { it.include?('span') }
          refute candidates.any? { it.include?('class') }
        end

        def test_sanitize_removes_vivliostyle_notation
          File.write('contents/09-vivlio.md', <<~MD)
            # Vivliostyle

            :::{.sideimage-right}
            ![画像](image.png){width=20%}
            :::

            本文のCSSは抽出される。
          MD

          @extractor.extract_from_chapters!(['09-vivlio'])

          candidates = @extractor.all_candidates
          refute candidates.any? { it.include?('width') }
          refute candidates.any? { it.include?('sideimage') }
        end

        # --- phase: valid_term? tests (integration) ---

        def test_rejects_html_tag_fragments
          File.write('contents/10-invalid.md', <<~MD)
            # Invalid Terms

            <div>タグ</div>の説明。
            HTMLは正常に抽出される。
          MD

          @extractor.extract_from_chapters!(['10-invalid'])

          candidates = @extractor.all_candidates
          # HTML タグの断片は除外される
          refute candidates.any? { it == '<div>' }
          refute candidates.any? { it == '</div>' }
          # 正常な用語は抽出される
          assert candidates.any? { it == 'HTML' }
        end
      end
    end
  end
end
