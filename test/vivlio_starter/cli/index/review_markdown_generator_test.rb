# frozen_string_literal: true

require 'test_helper'
require 'vivlio_starter/cli/index/review_markdown_generator'
require 'tmpdir'
require 'fileutils'

module VivlioStarter
  module CLI
    class ReviewMarkdownGeneratorTest < Minitest::Test
      # --- phase: setup ---

      def setup
        @original_dir = Dir.pwd
        @temp_dir = Dir.mktmpdir('review_md_test')
        Dir.chdir(@temp_dir)
        FileUtils.mkdir_p('config')
        @generator = ReviewMarkdownGenerator.new
      end

      def teardown
        Dir.chdir(@original_dir)
        FileUtils.rm_rf(@temp_dir)
      end

      # --- phase: 主要参照の指定（index-main-reference-spec.md R3） ---

      def term_with_main(tokens)
        { 'term' => 'Markdown', 'yomi' => 'まーくだうん', 'flags' => 'i',
          'in_index' => true, 'main_tokens' => tokens }
      end

      def generate_main(tokens)
        @generator.generate!(terms: [term_with_main(tokens)],
                             high_candidates: [], low_candidates: [], rejected: [])
        File.read(ReviewMarkdownGenerator::REVIEW_FILE, encoding: 'utf-8')
      end

      # 用語の子行だけを書き換える。冒頭の凡例にも記法の例文が載っているので、
      # 素の文字列置換だと凡例のほうに当たってしまう。
      def rewrite_main_line(to)
        path = ReviewMarkdownGenerator::REVIEW_FILE
        File.write(path, File.read(path, encoding: 'utf-8').sub(/^ {2}- 主要参照: .*\n/, to))
      end

      # 著者が触るのはレビューファイルであって辞書 YAML ではない。
      # 用語集の説明文と同じく子ブロックで書く。
      def test_main_reference_is_written_as_a_child_line
        content = generate_main(%w[21 22])

        assert_includes content, '  - 主要参照: 21, 22'
        assert_match(/^- \[i\] \*\*Markdown\*\*/, content, 'フラグ欄は無傷であること')
      end

      def test_main_reference_roundtrips
        generate_main(%w[21 22])

        assert_equal({ 'Markdown' => %w[21 22] }, @generator.parse_main_references)
      end

      # `main:` も受ける（英語のキーで書きたい著者のため）
      def test_main_alias_is_accepted
        generate_main(%w[21 22])
        rewrite_main_line("  - main: 21-22\n")

        assert_equal({ 'Markdown' => ['21-22'] }, @generator.parse_main_references)
      end

      def test_main_reference_accepts_various_separators
        generate_main(%w[21])
        rewrite_main_line("  - 主要参照: 21、22 33\n")

        assert_equal({ 'Markdown' => %w[21 22 33] }, @generator.parse_main_references)
      end

      # 行を消す＝指定の解除。nil で「解除」を表す（キーが無いのとは違う）
      def test_removing_the_line_means_clearing_the_designation
        generate_main(%w[21])
        rewrite_main_line('')

        assert_equal({ 'Markdown' => nil }, @generator.parse_main_references)
      end

      def test_main_reference_omitted_when_not_designated
        @generator.generate!(terms: [{ 'term' => 'Ruby', 'yomi' => 'るびー', 'flags' => 'i', 'in_index' => true }],
                             high_candidates: [], low_candidates: [], rejected: [])
        content = File.read(ReviewMarkdownGenerator::REVIEW_FILE, encoding: 'utf-8')

        refute_match(/^ {2}- 主要参照:/, content, '指定が無ければ子行を出さない')
        assert_equal({ 'Ruby' => nil }, @generator.parse_main_references)
      end

      # --- phase: 候補の提示（R2） ---

      # `NEW!` は「機械が推測した候補」の目印。既存の候補提示と同じラベルを使う
      def test_suggested_main_reference_is_labeled_new
        @generator.generate!(terms: [term_with_main(%w[33]).merge('main_suggested' => true)],
                             high_candidates: [], low_candidates: [], rejected: [])
        content = File.read(ReviewMarkdownGenerator::REVIEW_FILE, encoding: 'utf-8')

        assert_includes content, '  - 主要参照: `NEW!` 33'
      end

      # ラベルは表示だけの飾りで、値の解釈には混ざらない
      def test_new_label_is_stripped_when_parsing
        @generator.generate!(terms: [term_with_main(%w[33]).merge('main_suggested' => true)],
                             high_candidates: [], low_candidates: [], rejected: [])

        assert_equal({ 'Markdown' => ['33'] }, @generator.parse_main_references)
      end

      # 著者が確定した指定にラベルは付けない（毎回 NEW! だと新旧が読めない）
      def test_confirmed_main_reference_has_no_label
        content = generate_main(%w[33])

        assert_includes content, '  - 主要参照: 33'
        refute_includes content, '主要参照: `NEW!`'
      end

      # 凡例で記法そのものを説明する。著者は辞書 YAML を開かない
      def test_header_explains_the_notation
        content = generate_main(%w[21])

        assert_match(/※.*主要参照/, content, '記法の説明が凡例にある')
        assert_includes content, 'NEW!', '推測であることの断りがある'
        refute_includes content, 'config/index_glossary_terms.yml',
                        '著者が編集するのは辞書 YAML ではなくこのファイル'
      end

      # 主要参照の行を足しても、既存 7 パーサの解釈は変わらない。
      # 行の有無で結果が一致することを見る（絶対値ではなく差分で確かめる）。
      def test_main_reference_line_does_not_disturb_other_parsers
        generate_main(%w[21])
        with_line = {
          approved: @generator.parse_index_approved,
          rejected: @generator.parse_index_rejected,
          yomi: @generator.parse_yomi_changes,
          section4: @generator.parse_rejected_section_all
        }

        rewrite_main_line('')
        without_line = {
          approved: @generator.parse_index_approved,
          rejected: @generator.parse_index_rejected,
          yomi: @generator.parse_yomi_changes,
          section4: @generator.parse_rejected_section_all
        }

        assert_equal without_line, with_line, '主要参照の行は他のパーサの解釈を変えない'
        assert_equal ['Markdown'], with_line[:approved].map { it['term'] }
      end

      # --- phase: 一般語のサブセクション（§3 R5.2） ---

      def common_term(name, spread: '20/27 章（74%）')
        { 'term' => name, 'yomi' => name, 'flags' => 'i', 'in_index' => true,
          'common_term' => true, 'spread_text' => spread }
      end

      def ordinary_term(name)
        { 'term' => name, 'yomi' => name, 'flags' => 'i', 'in_index' => true, 'score' => 300.0 }
      end

      def generate_with(terms)
        @generator.generate!(terms:, high_candidates: [], low_candidates: [], rejected: [])
        File.read(ReviewMarkdownGenerator::REVIEW_FILE, encoding: 'utf-8')
      end

      # --- phase: 見直し候補のサブセクション ---

      def review_term(name)
        { 'term' => name, 'yomi' => name, 'flags' => 'i', 'in_index' => true,
          'review_candidate' => true, 'score' => 120.0 }
      end

      # 件数だけ告げられても、どの語のことか分からないまま終わる。
      # 外すべき語を見つける場はここにしかない。
      def test_review_candidates_get_their_own_subsection
        content = generate_with([review_term('カラー'), ordinary_term('特殊相対性理論')])

        assert_includes content, '### 見直し候補（1語）'
        assert_includes content, '**カラー**'
        assert_includes content, '### 登録語 (1語)'
      end

      # 一般語と違い、既定は現状維持。順位が低いことは「索引に要らない」を意味しない
      def test_review_candidates_stay_registered_by_default
        content = generate_with([review_term('カラー')])

        assert_match(/^- \[i\] \*\*カラー\*\*/, content)
      end

      def test_review_subsection_shows_how_to_act
        content = generate_with([review_term('カラー')])

        assert_includes content, '[-i]', '索引から外す手段'
        assert_includes content, '[r]', '二度と候補に出さない手段'
      end

      # 同じ語を 2 つの枠に出すと、どちらの助言に従えばよいのか分からなくなる
      def test_a_term_appears_in_only_one_subsection
        both = common_term('ファイル').merge('review_candidate' => true)
        content = generate_with([both])

        assert_includes content, '### 一般語（索引から外すことを推奨・1語）'
        refute_includes content, '### 見直し候補'
        assert_equal 1, content.scan(/\*\*ファイル\*\*/).size
      end

      def test_no_subsection_when_nothing_needs_review
        content = generate_with([ordinary_term('特殊相対性理論')])

        refute_includes content, '### 見直し候補'
        refute_includes content, '### 登録語', '仕分けが無ければ見出しも要らない'
      end

      def test_common_terms_get_their_own_subsection
        content = generate_with([common_term('ファイル'), ordinary_term('特殊相対性理論')])

        assert_includes content, '### 一般語（索引から外すことを推奨・1語）'
        assert_includes content, '### 登録語 (1語)'
      end

      # 著者が判断できるよう、事実（どれだけ広いか）を必ず添える
      def test_common_terms_show_how_widespread_they_are
        content = generate_with([common_term('ファイル', spread: '23/27 章（85%）')])

        assert_includes content, '一般語: 23/27 章（85%）に出現'
      end

      # 「外す」を既定にして提示する。残したい語は著者が [i] へ戻す。
      def test_common_terms_are_prefilled_with_removal_flag
        content = generate_with([common_term('ファイル')])

        assert_match(/^- \[-i\] \*\*ファイル\*\*/, content)
      end

      # 行の書式を変えると既存パーサが軒並みマッチしなくなる。
      # 追加情報は行末（スコアと同じ位置）に置く、という約束を固定する。
      def test_common_term_lines_stay_parseable
        generate_with([common_term('ファイル'), ordinary_term('特殊相対性理論')])

        rejected = @generator.parse_index_rejected
        approved = @generator.parse_index_approved

        assert_equal ['ファイル'], rejected.map { it['term'] }
        assert_equal ['特殊相対性理論'], approved.map { it['term'] }
      end

      # セクション番号を増やすと「## 4. 除外済みリスト」を境界に使う
      # パーサの解釈がずれる。入れ子の ### で足すこと。
      def test_does_not_introduce_a_new_numbered_section
        content = generate_with([common_term('ファイル')])

        assert_includes content, '## 1. 登録済み用語の確認'
        assert_includes content, '## 4. 除外済みリスト'
        refute_includes content, '## 5.'
      end

      def test_omits_the_subsection_when_no_common_terms
        content = generate_with([ordinary_term('特殊相対性理論')])

        refute_includes content, '一般語'
        refute_includes content, '### 登録語'
      end

      # --- phase: generate! tests ---

      def test_generate_creates_review_file
        data = {
          terms: [],
          high_candidates: [],
          low_candidates: [],
          rejected: []
        }

        @generator.generate!(data)

        assert File.exist?('_index_glossary_review.md')
      end

      def test_generate_includes_all_sections
        data = {
          terms: [
            { 'term' => 'Ruby', 'yomi' => 'るびー', 'source' => 'manual_markup' }
          ],
          high_candidates: [
            { 'term' => 'JavaScript', 'yomi' => 'じゃばすくりぷと', 'score' => 200.0, 'is_new' => true, 'contexts' => [] }
          ],
          low_candidates: [
            { 'term' => 'Python', 'yomi' => 'ぱいそん', 'score' => 150.0, 'is_new' => true, 'contexts' => [] }
          ],
          rejected: [
            { 'term' => 'Bad', 'yomi' => 'ばっど', 'rejected_at' => Time.now.strftime('%Y-%m-%d %H:%M:%S'), 'contexts' => [] }
          ]
        }

        @generator.generate!(data)

        content = File.read('_index_glossary_review.md')
        assert_includes content, '## 1. 登録済み用語の確認'
        assert_includes content, '## 2. 推奨候補'
        assert_includes content, '## 3. 一般候補'
        assert_includes content, '## 4. 除外済みリスト'
      end

      def test_generate_shows_manual_markup_label
        data = {
          terms: [
            { 'term' => 'Manual', 'yomi' => 'まにゅある', 'source' => 'manual_markup', 'contexts' => [] }
          ],
          high_candidates: [],
          low_candidates: [],
          rejected: []
        }

        @generator.generate!(data)

        content = File.read('_index_glossary_review.md')
        assert_includes content, '[手動登録]'
      end

      def test_generate_shows_score_for_auto_extracted
        data = {
          terms: [
            { 'term' => 'Auto', 'yomi' => 'おーと', 'source' => 'auto_extracted', 'score' => 150.5, 'contexts' => [] }
          ],
          high_candidates: [],
          low_candidates: [],
          rejected: []
        }

        @generator.generate!(data)

        content = File.read('_index_glossary_review.md')
        assert_includes content, 'スコア: 150.5'
      end

      # --- phase: parse_approved tests ---

      def test_parse_approved_extracts_checked_items
        content = <<~MD
          ## 2. 推奨候補 (High Candidates: 2語)

          - [x] `NEW!` **JavaScript** (じゃばすくりぷと) - スコア: 200.0
            - 01-intro - "sample context"

          - [ ] `NEW!` **Python** (ぱいそん) - スコア: 150.0
            - 02-basics - "another context"
        MD
        File.write('_index_glossary_review.md', content)

        approved = @generator.parse_approved

        assert_equal 1, approved.size
        assert_equal 'JavaScript', approved[0]['term']
        assert_equal 'じゃばすくりぷと', approved[0]['yomi']
      end

      # --- phase: parse_rejected tests ---

      def test_parse_rejected_extracts_r_marked_items
        content = <<~MD
          ## 2. 推奨候補 (High Candidates: 2語)

          - [r] `NEW!` **BadTerm** (ばっどたーむ) - スコア: 100.0
            - 01-intro - "context"

          - [ ] `NEW!` **GoodTerm** (ぐっどたーむ) - スコア: 150.0
            - 02-basics - "context"

          ## 4. 除外済みリスト (Rejected: 0語)
        MD
        File.write('_index_glossary_review.md', content)

        rejected = @generator.parse_rejected

        assert_equal 1, rejected.size
        assert_equal 'BadTerm', rejected[0]['term']
      end

      def test_parse_rejected_ignores_rejected_section
        content = <<~MD
          ## 2. 推奨候補 (High Candidates: 1語)

          - [r] `NEW!` **FromCandidates** (ふろむきゃんでぃでーつ) - スコア: 100.0

          ## 4. 除外済みリスト (Rejected: 1語)

          - [r] `Today` **AlreadyRejected** (おるれでぃりじぇくてっど)
        MD
        File.write('_index_glossary_review.md', content)

        rejected = @generator.parse_rejected

        assert_equal 1, rejected.size
        assert_equal 'FromCandidates', rejected[0]['term']
      end

      # --- phase: parse_unreject tests ---

      def test_parse_unreject_extracts_from_rejected_section
        content = <<~MD
          ## 2. 推奨候補 (High Candidates: 0語)

          ## 4. 除外済みリスト (Rejected: 2語)

          - [i] `Today` **ToUnreject** (とぅあんりじぇくと) - スコア: 50.0
            - 01-intro - "context"

          - [ ] `Today` **StayRejected** (すていりじぇくてっど)
        MD
        File.write('_index_glossary_review.md', content)

        unreject = @generator.parse_unreject

        assert_equal 1, unreject.size
        assert_equal 'ToUnreject', unreject[0]['term']
      end

      # --- phase: parse_yomi_changes tests ---

      def test_parse_yomi_changes_extracts_from_terms_section
        content = <<~MD
          ## 1. 登録済み用語の確認 (Terms: 1語)

          - [x] **Ruby** (るびー・かいてい)
            - 01-intro - "context"

          ## 2. 推奨候補 (High Candidates: 0語)
        MD
        File.write('_index_glossary_review.md', content)

        changes = @generator.parse_yomi_changes

        assert_equal 1, changes.size
        assert_equal 'Ruby', changes[0]['term']
        assert_equal 'るびー・かいてい', changes[0]['yomi']
      end

      # --- phase: exists? and cleanup! tests ---

      def test_exists_returns_false_when_file_missing
        refute @generator.exists?
      end

      def test_exists_returns_true_when_file_present
        File.write('_index_glossary_review.md', 'test')

        assert @generator.exists?
      end

      def test_cleanup_removes_file
        File.write('_index_glossary_review.md', 'test')

        @generator.cleanup!

        refute File.exist?('_index_glossary_review.md')
      end
    end
  end
end
