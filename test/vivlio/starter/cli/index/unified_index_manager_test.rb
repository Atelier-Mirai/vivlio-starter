# frozen_string_literal: true

require 'test_helper'
require 'vivlio/starter/cli/index/unified_index_manager'
require 'tmpdir'
require 'fileutils'

module Vivlio
  module Starter
    module CLI
      class UnifiedIndexManagerTest < Minitest::Test
        # --- phase: setup ---

        def setup
          @original_dir = Dir.pwd
          @temp_dir = Dir.mktmpdir('unified_index_test')
          Dir.chdir(@temp_dir)
          FileUtils.mkdir_p('contents')
          FileUtils.mkdir_p('config')
          @manager = UnifiedIndexManager.new
        end

        def teardown
          Dir.chdir(@original_dir)
          FileUtils.rm_rf(@temp_dir)
        end

        # --- phase: auto_process! integration tests ---

        def test_auto_process_creates_review_file
          File.write('contents/01-test.md', <<~MD)
            # Test Chapter

            [手動マークアップ|しゅどうまーくあっぷ]を含むテキスト。
            JavaScriptとHTMLとCSSについて説明します。
          MD

          @manager.auto_process!(['01-test'])

          assert File.exist?('_index_review.md')
        end

        def test_auto_process_extracts_manual_markups
          File.write('contents/02-manual.md', <<~MD)
            # Manual Markup Test

            [Ruby|るびー]は素晴らしい言語です。
            [Python]も人気があります。
          MD

          @manager.auto_process!(['02-manual'])

          content = File.read('_index_review.md')
          assert_includes content, 'Ruby'
          assert_includes content, '[手動登録]'
        end

        def test_auto_process_excludes_code_fences
          File.write('contents/03-code.md', <<~MD)
            # Code Fence Test

            ```javascript
            const [codeVariable] = useState(0);
            ```

            [JavaScript]は本文で使用。
          MD

          @manager.auto_process!(['03-code'])

          content = File.read('_index_review.md')
          # コードフェンス内の [codeVariable] は手動マークアップとして抽出されない
          # （Termsセクションに **codeVariable** が含まれていない）
          terms_section = content.split('## 2.')[0]
          refute_includes terms_section, '**codeVariable**'
          # 本文の [JavaScript] は抽出される
          assert_includes content, '**JavaScript**'
        end

        def test_auto_process_handles_special_characters
          File.write('contents/04-special.md', <<~MD)
            # Special Characters

            [!]は否定演算子です。
            [&&]は論理積演算子です。
            [||]は論理和演算子です。
            [404]はエラーコードです。
            [<h1>]は見出しタグです。
          MD

          @manager.auto_process!(['04-special'])

          content = File.read('_index_review.md')
          # 特殊文字を含む手動マークアップが表示される
          assert_includes content, '**!**'
          assert_includes content, '**&&**'
          assert_includes content, '**||**'
          assert_includes content, '**404**'
          assert_includes content, '**<h1>**'
        end

        def test_auto_process_saves_terms_to_yaml
          File.write('contents/05-save.md', <<~MD)
            # Save Test

            [SavedTerm|せーぶどたーむ]を保存します。
          MD

          @manager.auto_process!(['05-save'])

          assert File.exist?('config/index_terms.yml')
          content = File.read('config/index_terms.yml')
          assert_includes content, 'SavedTerm'
        end

        # --- phase: apply_review! tests ---

        def test_apply_markdown_review_approves_checked_candidates
          # まず auto_process でレビューファイルを生成
          File.write('contents/06-apply.md', <<~MD)
            # Apply Test

            JavaScriptとHTMLについて説明します。
          MD
          @manager.auto_process!(['06-apply'])

          # レビューファイルを編集して候補を承認
          content = File.read('_index_review.md')
          # 候補セクションの [ ] を [x] に変更
          modified = content.gsub(/^- \[ \] `NEW!` \*\*JavaScript\*\*/, '- [x] `NEW!` **JavaScript**')
          File.write('_index_review.md', modified)

          result = @manager.apply_markdown_review!

          assert result
        end

        def test_apply_markdown_review_returns_false_when_no_file
          result = @manager.apply_markdown_review!

          refute result
        end

        # --- phase: rejected terms tests ---

        def test_rejected_terms_are_excluded_from_candidates
          File.write('contents/07-reject.md', <<~MD)
            # Reject Test

            RejectedTermはリジェクト済みです。
          MD

          # リジェクト済み用語を設定
          rejected_data = {
            'rejected_at' => Time.now.strftime('%Y-%m-%d %H:%M:%S'),
            'rejected_terms' => [
              { 'term' => 'RejectedTerm', 'yomi' => 'りじぇくてっどたーむ' }
            ]
          }
          File.write('config/index_rejected.yml', rejected_data.to_yaml)

          @manager.auto_process!(['07-reject'])

          content = File.read('_index_review.md')
          # 候補セクションには表示されない（除外済みセクションに表示される）
          assert_includes content, '除外済みリスト'
        end

        # --- phase: enrich_terms_with_context tests ---

        def test_terms_include_context_information
          File.write('contents/08-context.md', <<~MD)
            # Context Test

            [ContextTerm|こんてきすとたーむ]は文脈付きで表示されます。
          MD

          @manager.auto_process!(['08-context'])

          content = File.read('_index_review.md')
          # 文脈情報が含まれる
          assert_match(/08-context/, content)
        end

        # --- phase: utility method tests ---

        def test_list_rejected_terms_works
          rejected_data = {
            'rejected_at' => Time.now.strftime('%Y-%m-%d %H:%M:%S'),
            'rejected_terms' => [
              { 'term' => 'TestTerm', 'yomi' => 'てすとたーむ' }
            ]
          }
          File.write('config/index_rejected.yml', rejected_data.to_yaml)

          # 例外なく実行できる
          @manager.list_rejected_terms
        end

        def test_reset_rejected_clears_file
          rejected_data = {
            'rejected_at' => Time.now.strftime('%Y-%m-%d %H:%M:%S'),
            'rejected_terms' => [
              { 'term' => 'TestTerm', 'yomi' => 'てすとたーむ' }
            ]
          }
          File.write('config/index_rejected.yml', rejected_data.to_yaml)

          @manager.reset_rejected!

          refute File.exist?('config/index_rejected.yml')
        end
      end
    end
  end
end
