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

      # 用語行の直後に子行を差し込む。フラグ欄では書けない値（章名・節指定）を
      # 著者が書き足す操作を再現する。
      def add_main_line(to)
        path = ReviewMarkdownGenerator::REVIEW_FILE
        File.write(path, File.read(path, encoding: 'utf-8')
          .sub(/^(- \[[^\]]*\] \*\*Markdown\*\*[^\n]*\n)/) { "#{::Regexp.last_match(1)}#{to}" })
      end

      # フラグ欄から主要参照を取り除く（＝指定の解除）
      def clear_main_flag
        path = ReviewMarkdownGenerator::REVIEW_FILE
        File.write(path, File.read(path, encoding: 'utf-8').sub(/^- \[([a-z-]*)m\??[^\]]*\]/) { "- [#{::Regexp.last_match(1)}]" })
      end

      # 章番号だけならフラグ欄へ収める。語ごとに子行を足すと、110 語の索引で
      # 110 行増えて一覧性が落ちる。
      def test_main_reference_goes_into_the_flag_field
        content = generate_main(%w[21 22])

        assert_match(/^- \[im21,22\] \*\*Markdown\*\*/, content)
        refute_includes content[/^## 1\..*/m], '  - 主要参照:', '子行は出さない（冒頭の凡例の例は除く）'
      end

      # 章名や節指定はフラグ欄だと読めないので子行に譲る
      def test_long_values_stay_on_a_child_line
        @generator.generate!(terms: [term_with_main(['21#Markdown とは'])],
                             high_candidates: [], low_candidates: [], rejected: [])
        content = File.read(ReviewMarkdownGenerator::REVIEW_FILE, encoding: 'utf-8')

        assert_includes content, '  - 主要参照: 21#Markdown とは'
        assert_match(/^- \[i\] \*\*Markdown\*\*/, content, 'フラグ欄には入れない')
      end

      def test_main_reference_roundtrips
        generate_main(%w[21 22])

        assert_equal({ 'Markdown' => %w[21 22] }, @generator.parse_main_references)
      end

      # `main:` も受ける（英語のキーで書きたい著者のため）
      # 子行はフラグ欄より優先する（後から書き足した細かい指定が勝つ）
      def test_child_line_overrides_the_flag_field
        generate_main(%w[21 22])
        add_main_line("  - main: 21-22\n")

        assert_equal({ 'Markdown' => ['21-22'] }, @generator.parse_main_references)
      end

      def test_main_reference_accepts_various_separators
        generate_main(%w[21])
        add_main_line("  - 主要参照: 21、22 33\n")

        assert_equal({ 'Markdown' => %w[21 22 33] }, @generator.parse_main_references)
      end

      # フラグ欄はカンマ区切りで複数章を書ける
      def test_flag_field_accepts_multiple_chapters
        generate_main(%w[21 22])

        assert_equal({ 'Markdown' => %w[21 22] }, @generator.parse_main_references)
      end

      # フラグ欄から m を消す＝指定の解除。nil で「解除」を表す
      def test_removing_the_flag_means_clearing_the_designation
        generate_main(%w[21])
        clear_main_flag

        assert_equal({ 'Markdown' => nil }, @generator.parse_main_references)
      end

      def test_main_reference_omitted_when_not_designated
        @generator.generate!(terms: [{ 'term' => 'Ruby', 'yomi' => 'るびー', 'flags' => 'i', 'in_index' => true }],
                             high_candidates: [], low_candidates: [], rejected: [])
        content = File.read(ReviewMarkdownGenerator::REVIEW_FILE, encoding: 'utf-8')

        refute_match(/^ {2}- 主要参照:/, content[/^## 1\..*/m], '指定が無ければ子行を出さない（冒頭の凡例は除く）')
        assert_match(/^- \[i\] \*\*Ruby\*\*/, content, 'フラグ欄にも入らない')
        assert_equal({ 'Ruby' => nil }, @generator.parse_main_references)
      end

      # 主要参照の子行は著者の指定であって出現箇所ではない。綴りが
      # `  - ラベル: 値` で出現箇所行と同型なので、弾かないと辞書へ
      # `chapter: 主要参照` が入り、往復のたび再出力されて残り続ける。
      def test_main_reference_child_line_is_not_taken_as_a_context
        @generator.generate!(terms: [{ 'term' => 'Markdown', 'yomi' => 'まーくだうん', 'flags' => 'ig',
                                       'in_index' => true, 'in_glossary' => true,
                                       'main_tokens' => ['21#Markdown とは'] }],
                             high_candidates: [], low_candidates: [], rejected: [])

        contexts = @generator.parse_glossary_approved.first['contexts']

        assert_empty contexts.select { it['chapter'].to_s.include?('主要参照') }
      end

      # 往復で値が空へ潰れた子行（`  - 主要参照: `）も同じく弾く。
      # 出現箇所行のほうは従来どおり拾えていること。
      def test_valueless_main_reference_line_is_ignored_while_contexts_survive
        @generator.generate!(terms: [{ 'term' => 'Markdown', 'yomi' => 'まーくだうん', 'flags' => 'ig',
                                       'in_index' => true, 'in_glossary' => true,
                                       'contexts' => [{ 'chapter' => '21-markdown', 'context' => '記法の基本' }] }],
                             high_candidates: [], low_candidates: [], rejected: [])
        add_main_line("  - 主要参照: \n")

        contexts = @generator.parse_glossary_approved.first['contexts']

        assert_equal [{ 'chapter' => '21-markdown', 'context' => '記法の基本' }], contexts
      end

      # 表示用の「（走査対象外）」注記は章名の一部ではないので辞書へ戻さない。
      # 剥がす sub と文脈の読み取りが同じ行に並ぶため、両方を一度に守る。
      def test_out_of_scope_annotation_is_stripped_while_context_survives
        @generator.generate!(terms: [{ 'term' => 'Markdown', 'yomi' => 'まーくだうん', 'flags' => 'ig',
                                       'in_index' => true, 'in_glossary' => true,
                                       'contexts' => [{ 'chapter' => '21-markdown', 'context' => '記法の基本',
                                                        'out_of_scope' => true }] }],
                             high_candidates: [], low_candidates: [], rejected: [])

        contexts = @generator.parse_glossary_approved.first['contexts']

        assert_equal [{ 'chapter' => '21-markdown', 'context' => '記法の基本' }], contexts
      end

      # スコアが取れない登録語は 2 通りある。文脈まで拾えなければ死語、
      # 文脈だけ拾えたなら今回走査しなかった章にいる——外す/残すの判断が逆になる
      def test_registered_term_without_score_distinguishes_dead_from_out_of_scope
        dead = { 'term' => '幻の用語', 'yomi' => 'まぼろし', 'flags' => 'i', 'in_index' => true }
        elsewhere = { 'term' => 'PDF/X-1a', 'yomi' => 'PDF/X-1a', 'flags' => 'i', 'in_index' => true,
                      'contexts' => [{ 'chapter' => '61-developer', 'context' => '入稿では PDF/X-1a を求められます',
                                       'out_of_scope' => true }] }

        @generator.generate!(terms: [dead, elsewhere], high_candidates: [], low_candidates: [], rejected: [])
        content = File.read(ReviewMarkdownGenerator::REVIEW_FILE, encoding: 'utf-8')

        assert_match(/\*\*幻の用語\*\*.*\[原稿に出現しません\]/, content)
        assert_match(%r{\*\*PDF/X-1a\*\*.*\[走査対象外の章に出現\]}, content)
      end

      # catalog に載っていない章にしか出ない語は、走査対象外とは行き先が違う
      # （章を catalog へ戻すか、語を索引から外すか）。注記も章名も言い分ける
      def test_term_living_only_outside_the_catalog_is_called_out
        term = { 'term' => 'インストルメンテーション', 'yomi' => 'いんすとるめんてーしょん',
                 'flags' => 'i', 'in_index' => true,
                 'contexts' => [{ 'chapter' => '61-developer', 'context' => '開発者だけが読む話',
                                  'outside_catalog' => true }] }

        @generator.generate!(terms: [term], high_candidates: [], low_candidates: [], rejected: [])
        content = File.read(ReviewMarkdownGenerator::REVIEW_FILE, encoding: 'utf-8')

        assert_match(/\[catalog 未登録の章に出現\]/, content)
        assert_includes content, '61-developer（catalog 未登録）'
      end

      # 注記は表示専用。章名の一部として辞書へ戻ってはいけない（走査対象外と同じ扱い）
      def test_outside_catalog_annotation_is_stripped_on_parse
        @generator.generate!(terms: [{ 'term' => 'Markdown', 'yomi' => 'まーくだうん', 'flags' => 'ig',
                                       'in_index' => true, 'in_glossary' => true,
                                       'contexts' => [{ 'chapter' => '61-developer', 'context' => '開発者向け',
                                                        'outside_catalog' => true }] }],
                             high_candidates: [], low_candidates: [], rejected: [])

        contexts = @generator.parse_glossary_approved.first['contexts']

        assert_equal [{ 'chapter' => '61-developer', 'context' => '開発者向け' }], contexts
      end

      # --- phase: 候補の提示（R2） ---

      # `NEW!` は「機械が推測した候補」の目印。既存の候補提示と同じラベルを使う
      def test_suggested_main_reference_is_labeled_new
        @generator.generate!(terms: [term_with_main(%w[33]).merge('main_suggested' => true)],
                             high_candidates: [], low_candidates: [], rejected: [])
        content = File.read(ReviewMarkdownGenerator::REVIEW_FILE, encoding: 'utf-8')

        assert_match(/^- \[im\?33\] \*\*Markdown\*\*/, content, '? が機械の推測を表す')
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

        assert_match(/^- \[im33\] \*\*Markdown\*\*/, content)
        refute_match(/^- \[im\?/, content, '著者が確定した指定に ? は付かない')
      end

      # 凡例で記法そのものを説明する。著者は辞書 YAML を開かない
      def test_header_explains_the_notation
        content = generate_main(%w[21])

        assert_match(/※.*主要参照/, content, '記法の説明が凡例にある')
        assert_includes content, 'm?', '推測であることの断りがある'
        refute_includes content, 'config/index_glossary_terms.yml',
                        '著者が編集するのは辞書 YAML ではなくこのファイル'
      end

      # フラグ欄に m33 を足しても、既存パーサの解釈は変わらない。
      # 有無で結果が一致することを見る（絶対値ではなく差分で確かめる）。
      def test_main_reference_does_not_disturb_other_parsers
        generate_main(%w[21])
        with_main = {
          approved: @generator.parse_index_approved,
          rejected: @generator.parse_index_rejected,
          yomi: @generator.parse_yomi_changes,
          section4: @generator.parse_rejected_section_all
        }

        clear_main_flag
        without_main = {
          approved: @generator.parse_index_approved,
          rejected: @generator.parse_index_rejected,
          yomi: @generator.parse_yomi_changes,
          section4: @generator.parse_rejected_section_all
        }

        assert_equal without_main, with_main, '主要参照はフラグの解釈を変えない'
        assert_equal ['Markdown'], with_main[:approved].map { it['term'] }
      end

      # --- phase: 1 節（登録済みの語）。小節を立てず、apply で変わる行を先に置く ---

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

      # 1 節は小節を立てない。外す印 [-i] の一般語 → 推測 m? の語 → それ以外、の順に並べる
      # （index-glossary-registration-spec.md §3.2。見直し候補はなくした）
      def test_terms_section_has_no_subsections_and_lists_changing_lines_first
        guessed = ordinary_term('数式').merge('main_tokens' => ['22'], 'main_suggested' => true)
        content = generate_with([ordinary_term('特殊相対性理論'), guessed, common_term('ファイル')])
        section = content[/^## 1\..*?(?=^## 2\.)/m]

        refute_includes section, '###'
        order = %w[ファイル 数式 特殊相対性理論].map { section.index("**#{it}**") }
        assert_equal order.sort, order
        assert_includes section, '本の広い範囲に散らばっていて'
      end

      # 外す印の説明は、外す印の付いた語があるときだけ出す
      def test_common_term_guide_appears_only_with_removal_flags
        refute_includes generate_with([ordinary_term('特殊相対性理論')]), '本の広い範囲に散らばっていて'
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

      # 主要参照が決まっている一般語は説明箇所がある語なので残す。機械の推測（m?）だけなら外す印（改善案 #99）
      def test_common_terms_with_a_confirmed_main_reference_stay_in_the_index
        confirmed = common_term('Markdown').merge('main_tokens' => ['21'])
        guessed = common_term('ファイル').merge('main_tokens' => ['25'], 'main_suggested' => true)
        content = generate_with([confirmed, guessed])

        assert_match(/^- \[im21\] \*\*Markdown\*\*/, content)
        assert_match(/^- \[-im\?25\] \*\*ファイル\*\*/, content)
      end

      # 用語集にも載っている一般語は [-ig]。g を印に含めて、用語集に載っていることを行に残す（§3.4）
      def test_common_glossary_term_shows_its_g_in_the_removal_flag
        content = generate_with([common_term('PDF').merge('in_glossary' => true, 'flags' => 'ig')])

        assert_match(/^- \[-ig\] \*\*PDF\*\*/, content)
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

      # 5 節（原稿に出てこない語）の行は、4 節（棄却した語）の読み取りに混ざらない。混ざると、
      # 5 節の登録済みの語の [ ] を「棄却のまま」と読み、apply で棄却してしまう（§3.3.1）
      def test_absent_section_is_not_read_as_the_rejected_section
        @generator.generate!(terms: [], high_candidates: [], low_candidates: [],
                             rejected: [{ 'term' => '棄却語', 'yomi' => 'ききゃくご', 'contexts' => [{ 'chapter' => '10-a', 'context' => '棄却語です' }] }],
                             absent: [{ 'term' => '旧い語', 'yomi' => 'ふるいご', 'kind' => 'registered', 'flags' => 'i', 'main_tokens' => ['33'] }])

        assert_equal ['棄却語'], @generator.parse_rejected_section_all.map { it['term'] }
      end

      # 5 節は、登録済み → 使っていない語 → 棄却した語の順。印はどれも [ ] で、いまの扱いを行末に添える
      def test_absent_section_lists_registered_first_with_current_status
        absent = [
          { 'term' => 'Step', 'yomi' => 'Step', 'kind' => 'rejected' },
          { 'term' => '用語', 'yomi' => 'ようご', 'kind' => 'unused', 'definition' => '残した説明文。' },
          { 'term' => '推奨候補', 'yomi' => 'すいしょうこうほ', 'kind' => 'registered', 'flags' => 'i', 'main_tokens' => ['33'] }
        ]
        @generator.generate!(terms: [], high_candidates: [], low_candidates: [], rejected: [], absent:)
        section = File.read(ReviewMarkdownGenerator::REVIEW_FILE, encoding: 'utf-8')[/^## 5\..*\z/m]

        assert_includes section, '- [ ] **推奨候補** (すいしょうこうほ) - [原稿に出現しません] - いまの登録: [im33]'
        assert_includes section, '- [ ] **用語** (ようご) - [原稿に出現しません] - 使っていない語'
        assert_includes section, "\n  残した説明文。\n", '残した説明文を見せる（[g] にすれば戻る）'
        order = %w[推奨候補 用語 Step].map { section.index("**#{it}**") }
        assert_equal order.sort, order
      end

      # 冒頭の凡例に子行の書き方の例を置く。例は字下げしてあるので、用語の行・主要参照・綴り・
      # 説明文のどれとしても読まれない（読まれると、例の語が辞書に入ってしまう）
      def test_legend_example_shows_child_lines_without_being_parsed
        @generator.generate!(terms: [], high_candidates: [], low_candidates: [], rejected: [])
        text = File.read(ReviewMarkdownGenerator::REVIEW_FILE, encoding: 'utf-8')

        assert_includes text, "      - 主要参照: 25#ラベルIDの扱い\n      - 綴り: ラベル ID\n"
        assert_empty IndexCommands::TermLine.scan(text)
        assert_empty @generator.parse_spelling_changes
        assert_empty @generator.parse_main_references
        assert_empty @generator.parse_glossary_approved
      end

      # 綴りの子行は、綴りの指定として読み、出現箇所（文脈）には混ぜない（改善案 #103）
      def test_spelling_line_is_read_as_a_spelling_change_not_a_context
        File.write(ReviewMarkdownGenerator::REVIEW_FILE, <<~MD)
          ## 1. 登録済みの語（1語）
          - [g] **ラベルID** (らべるID)
            - 25-cross-reference: ラベルIDを付けます。
            - 綴り: ラベル ID

            識別名。
          ## 4. 棄却した語（0語）
        MD

        assert_equal({ 'ラベルID' => 'ラベル ID' }, @generator.parse_spelling_changes)
        approved = @generator.parse_glossary_approved.first
        assert_equal ['25-cross-reference'], approved['contexts'].map { it['chapter'] }
        assert_equal '識別名。', approved['definition']
      end

      # [DELETE] は大文字・小文字を区別せずに読む（§3.3.3）
      def test_parse_deleted_reads_delete_marks
        File.write(ReviewMarkdownGenerator::REVIEW_FILE, <<~MD)
          ## 1. 登録済みの語（1語）
          - [DELETE] **Step** (Step)
          ## 4. 棄却した語（1語）
          - [delete] **Hz** (Hz)
          ## 5. 原稿に出てこない語（0語）
        MD

        assert_equal %w[Step Hz], @generator.parse_deleted
      end

      def test_omits_the_subsection_when_no_common_terms
        content = generate_with([ordinary_term('特殊相対性理論')])

        refute_includes content, '一般語'
        refute_includes content, '### 登録語'
      end

      # --- phase: 一般候補の圧縮 ---

      # 文脈は 1 語につき 3 行を占め、311 語ならファイルの半分になる。一般候補は
      # 眺める場所なので語だけを出し、末尾の除外済みリストが埋もれないようにする。
      def candidate(term, yomi)
        { 'term' => term, 'yomi' => yomi, 'score' => 150.0,
          'contexts' => [{ 'chapter' => '21-markdown', 'context' => '記法の基本' }] }
      end

      def test_low_candidates_are_listed_without_contexts
        @generator.generate!(terms: [], high_candidates: [],
                             low_candidates: [candidate('Python', 'ぱいそん')], rejected: [])
        content = File.read(ReviewMarkdownGenerator::REVIEW_FILE, encoding: 'utf-8')

        assert_includes content, '- [ ] **Python** (ぱいそん) - スコア: 150.0'
        refute_includes content, '21-markdown: 記法の基本', '一般候補に出現箇所は出さない'
      end

      # 推奨候補は判断する場所なので従来どおり文脈を添える
      def test_high_candidates_keep_their_contexts
        @generator.generate!(terms: [], high_candidates: [candidate('JavaScript', 'じゃばすくりぷと')],
                             low_candidates: [], rejected: [])
        content = File.read(ReviewMarkdownGenerator::REVIEW_FILE, encoding: 'utf-8')

        assert_includes content, '  - 21-markdown: 記法の基本'
      end

      # 語ごとに空行を挟むと 311 語で 622 行になる。詰めるのが目的なので詰める
      def test_low_candidates_are_packed_one_line_per_term
        @generator.generate!(terms: [], high_candidates: [],
                             low_candidates: [candidate('Python', 'ぱいそん'), candidate('Perl', 'ぱーる')],
                             rejected: [])
        content = File.read(ReviewMarkdownGenerator::REVIEW_FILE, encoding: 'utf-8')
        lines = content.lines.map(&:chomp)
        listed = lines.select { it.start_with?('- [ ]') }

        assert_equal 2, listed.size
        assert_equal listed.last, lines[lines.index(listed.first) + 1], '語の間に空行を置かない'
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
        assert_includes content, '## 1. 登録済みの語'
        assert_includes content, '## 2. 推奨する語'
        assert_includes content, '## 3. 残りの語'
        assert_includes content, '## 4. 棄却した語'
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

      # --- phase: parse_index_approved tests ---

      def test_parse_index_approved_extracts_checked_items
        content = <<~MD
          ## 2. 推奨する語 (High Candidates: 2語)

          - [x] `NEW!` **JavaScript** (じゃばすくりぷと) - スコア: 200.0
            - 01-intro - "sample context"

          - [ ] `NEW!` **Python** (ぱいそん) - スコア: 150.0
            - 02-basics - "another context"
        MD
        File.write('_index_glossary_review.md', content)

        approved = @generator.parse_index_approved

        assert_equal 1, approved.size
        assert_equal 'JavaScript', approved[0]['term']
        assert_equal 'じゃばすくりぷと', approved[0]['yomi']
      end

      # --- phase: parse_rejected tests ---

      def test_parse_rejected_extracts_r_marked_items
        content = <<~MD
          ## 2. 推奨する語 (High Candidates: 2語)

          - [r] `NEW!` **BadTerm** (ばっどたーむ) - スコア: 100.0
            - 01-intro - "context"

          - [ ] `NEW!` **GoodTerm** (ぐっどたーむ) - スコア: 150.0
            - 02-basics - "context"

          ## 4. 棄却した語 (Rejected: 0語)
        MD
        File.write('_index_glossary_review.md', content)

        rejected = @generator.parse_rejected

        assert_equal 1, rejected.size
        assert_equal 'BadTerm', rejected[0]['term']
      end

      def test_parse_rejected_ignores_rejected_section
        content = <<~MD
          ## 2. 推奨する語 (High Candidates: 1語)

          - [r] `NEW!` **FromCandidates** (ふろむきゃんでぃでーつ) - スコア: 100.0

          ## 4. 棄却した語 (Rejected: 1語)

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
          ## 2. 推奨する語 (High Candidates: 0語)

          ## 4. 棄却した語 (Rejected: 2語)

          - [i] `Today` **ToUnreject** (とぅあんりじぇくと) - スコア: 50.0
            - 01-intro - "context"

          - [ ] `Today` **StayRejected** (すていりじぇくてっど)
        MD
        File.write('_index_glossary_review.md', content)

        unreject = @generator.parse_unreject

        assert_equal 1, unreject.size
        assert_equal 'ToUnreject', unreject[0]['term']
      end

      # 見出し名は本文にも書かれる（凡例がまさにそう案内する）。境界の判定を
      # 行頭に限らないと、そこから先が丸ごと除外済み扱いになり、承認も棄却も
      # 読めなくなる。凡例に一行足しただけで 9 つの読み取りが壊れた実例がある。
      def test_section_boundary_ignores_the_heading_name_written_in_prose
        content = <<~MD
          # 索引・用語集レビュー
          ※ 外した語は ## 4. 棄却した語 に集まります

          ## 1. 登録済みの語 (Terms: 1語)

          - [-i] **Dropped** (どろっぷど)

          ## 4. 棄却した語 (Rejected: 1語)

          - [ ] **StayRejected** (すていりじぇくてっど)
        MD
        File.write('_index_glossary_review.md', content)

        assert_equal ['Dropped'], @generator.parse_index_rejected.map { it['term'] }
        assert_equal ['StayRejected'], @generator.parse_rejected_section_all.map { it['term'] }
      end

      # 棄却した語の数は 4 節の見出しに出す。次の本へ持ち運べることも添える
      def test_rejected_section_shows_the_count_and_how_to_carry_it
        @generator.generate!(terms: [], high_candidates: [], low_candidates: [],
                             rejected: [{ 'term' => 'Bad', 'yomi' => 'ばっど' },
                                        { 'term' => 'Worse', 'yomi' => 'わーす' }])
        content = File.read(ReviewMarkdownGenerator::REVIEW_FILE, encoding: 'utf-8')

        assert_includes content, '## 4. 棄却した語（2語）'
        assert_includes content, 'vs index:export'
      end

      # 古い形式（節の見出しが違う）のファイルを見分ける。apply が読み違えないように
      def test_current_format_rejects_old_section_headings
        File.write(ReviewMarkdownGenerator::REVIEW_FILE, "## 1. 登録済み用語の確認 (Terms: 0語)\n\n## 4. 除外済みリスト (Rejected: 0語)\n")
        refute @generator.current_format?

        @generator.generate!(terms: [], high_candidates: [], low_candidates: [], rejected: [])
        assert @generator.current_format?
      end

      # --- phase: parse_yomi_changes tests ---

      def test_parse_yomi_changes_extracts_from_terms_section
        content = <<~MD
          ## 1. 登録済みの語 (Terms: 1語)

          - [x] **Ruby** (るびー・かいてい)
            - 01-intro - "context"

          ## 2. 推奨する語 (High Candidates: 0語)
        MD
        File.write('_index_glossary_review.md', content)

        changes = @generator.parse_yomi_changes

        assert_equal 1, changes.size
        assert_equal 'Ruby', changes[0]['term']
        assert_equal 'るびー・かいてい', changes[0]['yomi']
      end

      # --- phase: exists? tests ---

      def test_exists_returns_false_when_file_missing
        refute @generator.exists?
      end

      def test_exists_returns_true_when_file_present
        File.write('_index_glossary_review.md', 'test')

        assert @generator.exists?
      end

      # --- phase: 見出しから拾った短い語（改善案 #98） ---

      def heading_candidate(term)
        { 'term' => term, 'yomi' => term, 'score' => 100.0, 'is_new' => true,
          'contexts' => [{ 'chapter' => '42-frontispiece', 'context' => "#{term}の文脈" }] }
      end

      def generate_candidates(high: [], low: [])
        @generator.generate!(terms: [], high_candidates: high, low_candidates: low, rejected: [])
        File.read(ReviewMarkdownGenerator::REVIEW_FILE, encoding: 'utf-8')
      end

      # 除外済みの語でも、原稿のどこにも無いものは注記する。文脈もスコアも無い行が黙って並ぶと、
      # 表示が漏れたのか語が消えたのか見分けられない（改善案 #99）
      def test_rejected_term_absent_from_the_manuscript_is_noted
        rejected = [{ 'term' => 'バリアント', 'yomi' => 'バリアント', 'contexts' => [] },
                    { 'term' => 'パターン', 'yomi' => 'ぱたーん', 'contexts' => [{ 'chapter' => '94-pdf-read', 'context' => 'パターンを追加' }] }]
        @generator.generate!(terms: [], high_candidates: [], low_candidates: [], rejected:)
        md = File.read(ReviewMarkdownGenerator::REVIEW_FILE, encoding: 'utf-8')

        assert_includes md, '**バリアント** (バリアント) - [原稿に出現しません]'
        refute_match(/\*\*パターン\*\* \(ぱたーん\)[^\n]*原稿に出現しません/, md)
      end

      # 主要参照の推測がある候補は `[m?61]`（空白なし。i を書き足せば `[im61]`）、無ければ `[ ]`（改善案 #99）
      def test_candidate_line_carries_the_suggested_main_reference_without_a_space
        guessed = heading_candidate('図番号').merge('main_tokens' => ['61'], 'main_suggested' => true)
        md = generate_candidates(high: [guessed, heading_candidate('派生画像')])

        assert_includes md, '- [m?61] `NEW!` **図番号**'
        assert_includes md, '- [ ] `NEW!` **派生画像**'
        assert_includes md, '`[im61]`', '2 節の案内で、i を書き足せば登録されることを示す'

        File.write(ReviewMarkdownGenerator::REVIEW_FILE, md.sub('- [m?61] `NEW!` **図番号**', '- [im61] `NEW!` **図番号**'))
        assert_equal ['図番号'], @generator.parse_index_approved.map { it['term'] }
        assert_equal ['61'], @generator.parse_main_references['図番号']
      end

      # 見出しから拾った短い語も、他の候補と同じ並びに置く（小節も注記も付けない。§3.2）
      def test_short_heading_words_sit_among_other_candidates
        md = generate_candidates(high: [heading_candidate('扉絵'), heading_candidate('図番号')],
                                 low: [heading_candidate('目安')])

        refute_includes md, '見出しから拾った'
        assert_includes md[/^## 2\..*?(?=^## 3\.)/m], '**扉絵**'
        assert_includes md[/^## 3\..*?(?=^## 4\.)/m], '**目安**'
      end
    end
  end
end
