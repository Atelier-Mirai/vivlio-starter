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

          assert File.exist?('_index_glossary_review.md')
        end

        def test_auto_process_extracts_manual_markups
          File.write('contents/02-manual.md', <<~MD)
            # Manual Markup Test

            [Ruby|るびー]は素晴らしい言語です。
            [Python]も人気があります。
          MD

          @manager.auto_process!(['02-manual'])

          content = File.read('_index_glossary_review.md')
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

          content = File.read('_index_glossary_review.md')
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

          content = File.read('_index_glossary_review.md')
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

          assert File.exist?('config/glossary_terms.yml')
          content = File.read('config/glossary_terms.yml')
          assert_includes content, 'SavedTerm'
        end

        # --- phase: apply_review! tests ---

        def test_apply_markdown_review_approves_checked_candidates
          # レビューファイルを直接生成して [i] 承認をテスト
          write_review_with_rejected_items(
            terms: [{ term: 'JavaScript', yomi: 'JavaScript', flag: 'i' }],
            rejected: []
          )

          result = @manager.apply_markdown_review!

          assert result
          terms = load_index_terms
          assert_equal 1, terms.size
          assert_equal 'JavaScript', terms.first['term']
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
          File.write('config/index_glossary_rejected.yml', rejected_data.to_yaml)

          @manager.auto_process!(['07-reject'])

          content = File.read('_index_glossary_review.md')
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

          content = File.read('_index_glossary_review.md')
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
          File.write('config/index_glossary_rejected.yml', rejected_data.to_yaml)

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
          File.write('config/index_glossary_rejected.yml', rejected_data.to_yaml)

          @manager.reset_rejected!

          refute File.exist?('config/index_glossary_rejected.yml')
        end

        # === Section 4 同期テスト ===

        def test_apply_section4_blank_flag_removes_from_index_terms
          # 統合辞書に索引用語が3語
          seed_unified_terms([{ name: 'CSS', flags: 'i' }, { name: 'HTML', flags: 'i' }, { name: 'JavaScript', flags: 'i' }])

          # レビューファイル: Section 1 は空、Section 4 に [ ] で3語
          write_review_with_rejected_items(
            terms: [],
            rejected: [
              { term: 'CSS', yomi: 'CSS', flag: ' ' },
              { term: 'HTML', yomi: 'HTML', flag: ' ' },
              { term: 'JavaScript', yomi: 'JavaScript', flag: ' ' }
            ]
          )

          @manager.apply_markdown_review!

          # 統合辞書から全て除去される
          terms = load_index_terms
          assert_empty terms

          # rejected.yml に追加される
          rejected = load_rejected_terms
          assert_includes rejected, 'CSS'
          assert_includes rejected, 'HTML'
          assert_includes rejected, 'JavaScript'
        end

        def test_apply_section4_blank_flag_removes_from_glossary_terms
          # 統合辞書に用語集用語がある
          seed_unified_terms([{ name: 'WWW', flags: 'g' }])

          # レビューファイル: 候補セクションに WWW あるが [g] なし
          write_review_with_rejected_items(terms: [], rejected: [])

          @manager.apply_markdown_review!

          # 用語集フラグが除去される
          terms = load_glossary_terms
          assert_empty terms
        end

        def test_apply_stale_index_data_removed_when_not_approved
          # 統合辞書に3語あるが、レビューでは1語のみ [i] 承認
          seed_unified_terms([{ name: 'CSS', flags: 'i' }, { name: 'HTML', flags: 'i' }, { name: 'JavaScript', flags: 'i' }])

          write_review_with_rejected_items(
            terms: [{ term: 'CSS', yomi: 'CSS', flag: 'i' }],
            rejected: []
          )

          @manager.apply_markdown_review!

          terms = load_index_terms
          assert_equal 1, terms.size
          assert_equal 'CSS', terms.first['term']
        end

        def test_apply_stale_glossary_data_removed_when_not_approved
          # 統合辞書に用語集用語2つあるが、レビューでは1語のみ [g] 承認
          seed_unified_terms([{ name: 'Alpha', flags: 'g' }, { name: 'Beta', flags: 'g' }])

          write_review_with_glossary_approved(
            glossary: [{ term: 'Alpha', yomi: 'あるふぁ', definition: 'テスト定義' }],
            rejected: []
          )

          @manager.apply_markdown_review!

          terms = load_glossary_terms
          assert_equal 1, terms.size
          assert_equal 'Alpha', terms.first['term']
        end

        def test_apply_unreject_with_i_flag_registers_to_index
          # rejected に用語がある
          seed_rejected_terms(['Gamma'])

          # Section 4 で [i] にフラグ変更
          write_review_with_rejected_items(
            terms: [],
            rejected: [{ term: 'Gamma', yomi: 'がんま', flag: 'i' }]
          )

          @manager.apply_markdown_review!

          # 統合辞書に flags: 'i' で登録される
          terms = load_index_terms
          assert_equal 1, terms.size
          assert_equal 'Gamma', terms.first['term']

          # rejected.yml から解除される
          rejected = load_rejected_terms
          refute_includes rejected, 'Gamma'
        end

        def test_apply_unreject_with_g_flag_registers_to_glossary
          seed_rejected_terms(['Delta'])

          write_review_with_rejected_items(
            terms: [],
            rejected: [{ term: 'Delta', yomi: 'でるた', flag: 'g' }]
          )

          @manager.apply_markdown_review!

          # glossary_terms.yml に登録される
          terms = load_glossary_terms
          assert_equal 1, terms.size
          assert_equal 'Delta', terms.first['term']
        end

        def test_apply_unreject_with_ig_flag_registers_to_both
          seed_rejected_terms(['Epsilon'])

          write_review_with_rejected_items(
            terms: [],
            rejected: [{ term: 'Epsilon', yomi: 'いぷしろん', flag: 'ig' }]
          )

          @manager.apply_markdown_review!

          # 統合辞書に flags: 'ig' で登録 → 索引と用語集の両方に出現
          index_terms = load_index_terms
          glossary_terms = load_glossary_terms
          assert_equal 1, index_terms.size
          assert_equal 'Epsilon', index_terms.first['term']
          assert_equal 1, glossary_terms.size
          assert_equal 'Epsilon', glossary_terms.first['term']
        end

        def test_apply_mixed_scenario
          # 複合シナリオ: 索引に3語、用語集に1語が登録済み
          seed_unified_terms([
            { name: 'CSS', flags: 'i' },
            { name: 'HTML', flags: 'i' },
            { name: 'JavaScript', flags: 'i' },
            { name: 'WWW', flags: 'g' }
          ])
          seed_rejected_terms(['OldReject'])

          # レビュー: CSS のみ [i] 承認、HTML/JavaScript は Section 4 で [ ]
          # OldReject は [i] で unreject
          write_review_with_rejected_items(
            terms: [{ term: 'CSS', yomi: 'CSS', flag: 'i' }],
            rejected: [
              { term: 'HTML', yomi: 'HTML', flag: ' ' },
              { term: 'JavaScript', yomi: 'JavaScript', flag: ' ' },
              { term: 'OldReject', yomi: 'おーるどりじぇくと', flag: 'i' }
            ]
          )

          @manager.apply_markdown_review!

          # CSS と OldReject が索引に残る
          index_terms = load_index_terms
          index_names = index_terms.map { it['term'] }
          assert_includes index_names, 'CSS'
          assert_includes index_names, 'OldReject'
          refute_includes index_names, 'HTML'
          refute_includes index_names, 'JavaScript'

          # glossary は空（WWW は承認されていない）
          glossary_terms = load_glossary_terms
          assert_empty glossary_terms

          # rejected に HTML, JavaScript が入っている
          rejected = load_rejected_terms
          assert_includes rejected, 'HTML'
          assert_includes rejected, 'JavaScript'
          # OldReject は unreject されている
          refute_includes rejected, 'OldReject'
        end

        def test_apply_review_file_preserved_after_apply
          write_review_with_rejected_items(terms: [], rejected: [])

          @manager.apply_markdown_review!

          # レビューファイルが残っている
          assert File.exist?('_index_glossary_review.md')
        end

        private

        # --- テストヘルパー ---

        # 統合辞書をセットアップ
        # @param entries [Array<Hash>] { name:, flags: } のリスト
        def seed_unified_terms(entries)
          terms = entries.map do |e|
            {
              'term' => e[:name], 'yomi' => e[:name],
              'flags' => e[:flags], 'definition' => '',
              'pattern' => "/#{e[:name]}/", 'source' => 'test',
              'approved_at' => Time.now.strftime('%Y-%m-%d %H:%M:%S')
            }
          end
          FileUtils.mkdir_p('config')
          File.write('config/glossary_terms.yml',
                     { 'generated_at' => Time.now.to_s, 'terms' => terms }.to_yaml)
          @manager.terms_manager.clear_cache!
        end

        def seed_rejected_terms(names)
          terms = names.map do |name|
            { 'term' => name, 'yomi' => name, 'rejected_at' => Time.now.strftime('%Y-%m-%d %H:%M:%S') }
          end
          FileUtils.mkdir_p('config')
          File.write('config/index_glossary_rejected.yml',
                     { 'rejected_at' => Time.now.to_s, 'rejected_terms' => terms }.to_yaml)
        end

        def load_index_terms
          return [] unless File.exist?('config/glossary_terms.yml')

          data = YAML.load_file('config/glossary_terms.yml')
          (data['terms'] || []).select { it['flags'].to_s.include?('i') }
        end

        def load_glossary_terms
          return [] unless File.exist?('config/glossary_terms.yml')

          data = YAML.load_file('config/glossary_terms.yml')
          (data['terms'] || []).select { it['flags'].to_s.include?('g') }
        end

        def load_rejected_terms
          return [] unless File.exist?('config/index_glossary_rejected.yml')

          data = YAML.load_file('config/index_glossary_rejected.yml')
          (data['rejected_terms'] || []).map { it['term'] }
        end

        def write_review_with_rejected_items(terms:, rejected:)
          content = "# 索引・用語集レビュー\n"
          content += "※ フラグ: [i]=索引のみ、[g]=用語集のみ、[ig]=両方、[r]=棄却\n\n"

          # Section 1: Terms
          content += "## 1. 登録済み用語の確認 (Terms: #{terms.size}語)\n\n"
          if terms.empty?
            content += "登録済みの用語はありません。\n"
          else
            terms.each do |t|
              content += "- [#{t[:flag]}] `Today` **#{t[:term]}** (#{t[:yomi]}) - スコア: 100.0\n"
              content += "  - 01-test: テスト文脈\n\n"
            end
          end

          # Section 2 & 3: empty candidates
          content += "\n\n## 2. 推奨候補 (High Candidates: 0語)\n\n"
          content += "## 3. 一般候補 (Low Candidates: 0語)\n\n"

          # Section 4: Rejected
          content += "## 4. 除外済みリスト (Rejected: #{rejected.size}語)\n"
          content += "※ 復帰させたいものは [i], [g], [ig] を入れると索引・用語集に直接登録されます。\n\n"
          if rejected.empty?
            content += "除外済みの用語はありません。\n"
          else
            rejected.each do |r|
              content += "- [#{r[:flag]}] `Today` **#{r[:term]}** (#{r[:yomi]}) - スコア: 100.0\n"
              content += "  - 01-test: テスト文脈\n\n"
            end
          end

          File.write('_index_glossary_review.md', content, encoding: 'utf-8')
        end

        def write_review_with_glossary_approved(glossary:, rejected:)
          content = "# 索引・用語集レビュー\n"
          content += "※ フラグ: [i]=索引のみ、[g]=用語集のみ、[ig]=両方、[r]=棄却\n\n"

          # Section 1: Terms with [g] flags
          content += "## 1. 登録済み用語の確認 (Terms: #{glossary.size}語)\n\n"
          glossary.each do |t|
            content += "- [g] `Today` **#{t[:term]}** (#{t[:yomi]}) - スコア: 100.0\n"
            content += "  - 01-test: テスト文脈\n\n"
            content += "  #{t[:definition]}\n\n" if t[:definition]
          end

          content += "\n\n## 2. 推奨候補 (High Candidates: 0語)\n\n"
          content += "## 3. 一般候補 (Low Candidates: 0語)\n\n"
          content += "## 4. 除外済みリスト (Rejected: 0語)\n"
          content += "※ 復帰させたいものは [i], [g], [ig] を入れると索引・用語集に直接登録されます。\n\n"
          content += "除外済みの用語はありません。\n"

          File.write('_index_glossary_review.md', content, encoding: 'utf-8')
        end
      end
    end
  end
end
