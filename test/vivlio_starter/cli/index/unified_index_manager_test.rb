# frozen_string_literal: true

require 'test_helper'
require 'vivlio_starter/cli/index/unified_index_manager'
require 'tmpdir'
require 'fileutils'

module VivlioStarter
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

      # 回帰: 地の文中のインライン ``` があっても、後続コードブロック内の
      # [###] や [00, 90-98, 99] を手動マークアップとして誤検出しない。
      def test_auto_process_excludes_code_even_with_inline_backticks
        File.write('contents/03b-metrics.md', <<~MD)
          # Metrics

          コードブロック（` ``` ` で囲んだ部分）は分析から除きます。

          ```
          第1章 はじめに  [##########  ] 2,500 文字
          ```

          ```yaml
          exclude_chapters: [00, 90-98, 99]
          ```

          本文の [実用語] は残ります。
        MD

        @manager.auto_process!(['03b-metrics'])

        content = File.read('_index_glossary_review.md')
        terms_section = content.split('## 2.')[0]
        # コード内の [] は「用語」（**...** 太字）として抽出されない
        # （周辺文脈のプレビューには現れうるが、それは登録語ではない）。
        refute_includes terms_section, '**##########  **'
        refute_includes terms_section, '**00, 90-98, 99**'
        assert_includes content, '**実用語**'
      end

      def test_auto_process_handles_special_characters
        File.write('contents/04-special.md', <<~MD)
          # Special Characters

          [||]は論理和演算子です。
          [404]はエラーコードです。
          [<h1>]は見出しタグです。
        MD

        @manager.auto_process!(['04-special'])

        content = File.read('_index_glossary_review.md')
        # 特殊文字を含む手動マークアップが表示される
        # （ASCII のみ 2 文字以下（[!] [&&] 等）は R9 により登録対象外・下の R9 テスト参照）
        assert_includes content, '**||**'
        assert_includes content, '**404**'
        assert_includes content, '**<h1>**'
      end

      # --- phase: R9 ASCII 短語ガード ---

      # R9: [用語]（読みなし）で ASCII のみ 2 文字以下は単位・記号表記とみなし登録しない
      def test_auto_process_skips_short_ascii_terms_with_warning
        File.write('contents/94-sample.md', <<~MD)
          # Units

          | 金属 | 仕事関数 φ [eV] | しきい周波数 [Hz] |
          書籍間で持ち運ぶ用語集[g]・reject・読み
        MD

        output, = capture_io { @manager.auto_process!(['94-sample']) }

        terms = load_all_terms
        refute_includes terms, 'eV'
        refute_includes terms, 'Hz'
        refute_includes terms, 'g'
        # 既定ログレベルで章名つきの警告と読み付き記法の案内が出る
        assert_includes output, '[eV] は単位・記号表記とみなし索引登録しません'
        assert_includes output, '94-sample'
        assert_includes output, '[eV|よみ]'
      end

      # R9 の逃げ道: 読み付き [eV|いーぶい] は従来どおり登録される
      def test_auto_process_registers_short_ascii_term_with_explicit_yomi
        File.write('contents/94-sample.md', <<~MD)
          # Units

          仕事関数の単位は[eV|いーぶい]です。
        MD

        @manager.auto_process!(['94-sample'])

        assert_includes load_all_terms, 'eV'
      end

      # --- phase: R8 辞書更新の可視化 ---

      # R8: auto が辞書へ書いた語は既定ログレベル（warn）で必ず要約表示される
      def test_auto_process_reports_dictionary_writes_at_default_level
        File.write('contents/05-visible.md', <<~MD)
          # Visible

          [特殊相対性理論|とくしゅそうたいせいりろん]を説明します。
        MD

        output, = capture_io { @manager.auto_process!(['05-visible']) }

        assert_includes output, '📝 辞書を更新しました'
        assert_includes output, '特殊相対性理論'
      end

      # R8: 何も登録しなかった実行では要約を出さない（無言＝無変更）
      def test_auto_process_stays_silent_when_nothing_written
        File.write('contents/06-plain.md', <<~MD)
          # Plain

          マークアップのない本文です。
        MD

        output, = capture_io { @manager.auto_process!(['06-plain']) }

        refute_includes output, '📝 辞書を更新しました'
      end

      def test_auto_process_saves_terms_to_yaml
        File.write('contents/05-save.md', <<~MD)
          # Save Test

          [SavedTerm|せーぶどたーむ]を保存します。
        MD

        @manager.auto_process!(['05-save'])

        assert File.exist?('config/index_glossary_terms.yml')
        content = File.read('config/index_glossary_terms.yml')
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

      # --- phase: context 鮮度（R5/R6） ---

      # R5: 現原稿に生きている context はそのまま温存される
      def test_enrich_preserves_live_context
        File.write('contents/10-intro.md', "この章では特殊相対性理論を丁寧に説明します。\n")
        terms = [{ 'term' => '特殊相対性理論', 'flags' => 'i',
                   'contexts' => [{ 'chapter' => '10-intro',
                                    'context' => 'この章では特殊相対性理論を 丁寧に説明します。' }] }]

        enriched = @manager.send(:enrich_terms_with_context, terms, ['10-intro'])

        contexts = enriched.first['contexts']
        assert_equal 1, contexts.size
        # 空白の揺れ（YAML 折返し）は stale とみなさない
        assert_includes contexts.first['context'], '特殊相対性理論'
      end

      # R5: stale な context は捨てられ、出現する複数章から補充される
      def test_enrich_discards_stale_context_and_refills_from_multiple_chapters
        File.write('contents/10-intro.md', "推敲後の新しい文章に特殊相対性理論が登場します。\n")
        File.write('contents/20-body.md', "この章でも特殊相対性理論を扱います。\n")
        terms = [{ 'term' => '特殊相対性理論', 'flags' => 'i',
                   'contexts' => [{ 'chapter' => '10-intro', 'context' => '推敲前の古い抜粋テキスト' }] }]

        enriched = @manager.send(:enrich_terms_with_context, terms, %w[10-intro 20-body])

        contexts = enriched.first['contexts']
        assert_equal %w[10-intro 20-body], contexts.map { it['chapter'] }.sort
        refute(contexts.any? { it['context'].include?('推敲前の古い抜粋') })
      end

      # R6: 今回対象外だが実在する章（catalog 外・部分実行）の context は判定せず温存
      def test_enrich_preserves_context_of_chapters_outside_scope
        File.write('contents/61-developer.md', "開発者向けの内容。\n")
        File.write('contents/10-intro.md', "本文。\n")
        terms = [{ 'term' => 'PDF/X-1a', 'flags' => 'g',
                   'contexts' => [{ 'chapter' => '61-developer', 'context' => '古い抜粋でも対象外章なら温存される' }] }]

        enriched = @manager.send(:enrich_terms_with_context, terms, ['10-intro'])

        contexts = enriched.first['contexts']
        assert_equal 1, contexts.size
        assert_equal '61-developer', contexts.first['chapter']
        assert contexts.first['out_of_scope'], 'catalog 外の表示注記フラグが付くこと'
      end

      # R5: 実在しない章（削除・改名）を参照する context は stale として捨てる
      def test_enrich_discards_context_of_deleted_chapters
        File.write('contents/10-intro.md', "本文にはこの語は出ません。\n")
        terms = [{ 'term' => '幻の用語', 'flags' => 'i',
                   'contexts' => [{ 'chapter' => '99-removed', 'context' => '削除済み章の抜粋' }] }]

        enriched = @manager.send(:enrich_terms_with_context, terms, ['10-intro'])

        assert_empty enriched.first['contexts']
      end

      # --- phase: 未出現の用語集語警告（R4） ---

      # R4: 今回のスキャンに出現しない g 語は catalog 外の出現章名つきで警告される（掲載は維持）
      def test_warn_unmatched_glossary_terms_hints_outside_chapter
        File.write('contents/61-developer.md', "PDF/X-1a は印刷入稿の規格です。\n")
        glossary = [{ 'term' => 'PDF/X-1a', 'flags' => 'g' }]

        output, = capture_io do
          @manager.send(:warn_unmatched_glossary_terms, glossary, {}, ['10-intro'])
        end

        assert_includes output, '用語集語がビルド対象章に出現しません: PDF/X-1a'
        assert_includes output, 'catalog 外の 61-developer に出現'
      end

      # R4: 原稿のどこにも出現しない g 語は「語の変更・削除？」の手掛かりを添える
      def test_warn_unmatched_glossary_terms_hints_missing_everywhere
        File.write('contents/10-intro.md', "本文。\n")
        glossary = [{ 'term' => '消えた用語', 'flags' => 'g' }]

        output, = capture_io do
          @manager.send(:warn_unmatched_glossary_terms, glossary, {}, ['10-intro'])
        end

        assert_includes output, '原稿のどこにも出現しません（語の変更・削除？）'
      end

      # R4: 今回のスキャンで出現した語には警告を出さない
      def test_warn_unmatched_glossary_terms_silent_when_all_matched
        glossary = [{ 'term' => 'CSS', 'flags' => 'g' }]
        backlinks = { 'CSS' => [{ 'chapter' => '10-intro', 'occurrence' => 1 }] }

        output, = capture_io do
          @manager.send(:warn_unmatched_glossary_terms, glossary, backlinks, ['10-intro'])
        end

        assert_empty output
      end

      # --- phase: 章走査記録（R7） ---

      # R7: auto_process! は走査した章集合を和集合で辞書へ記録する
      def test_auto_process_records_scanned_chapters_as_union
        File.write('contents/10-intro.md', "[Ruby|るびー]は良い言語です。\n")
        File.write('contents/20-body.md', "本文です。\n")

        @manager.auto_process!(['10-intro'])
        @manager.auto_process!(['20-body'])

        data = YAML.load_file('config/index_glossary_terms.yml')
        assert_equal %w[10-intro 20-body], data['scanned_chapters']
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

        # index_glossary_terms.yml に登録される
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

      # === フラグ別 apply→auto ラウンドトリップテスト ===

      def test_apply_g_flag_from_candidate_section
        # 候補セクションで [g] を選択
        content = build_review(
          terms: [],
          high: [{ term: 'ウェブサイト', yomi: 'ウェブサイト', flag: 'g' }],
          low: []
        )
        File.write('_index_glossary_review.md', content, encoding: 'utf-8')

        @manager.apply_markdown_review!

        # flags: 'g' で保存される
        glossary = load_glossary_terms
        assert_equal 1, glossary.size
        assert_equal 'ウェブサイト', glossary.first['term']

        # 索引には含まれない
        index = load_index_terms
        assert_empty index
      end

      def test_apply_ig_flag_from_candidate_section
        content = build_review(
          terms: [],
          high: [{ term: 'CSS', yomi: 'CSS', flag: 'ig' }],
          low: []
        )
        File.write('_index_glossary_review.md', content, encoding: 'utf-8')

        @manager.apply_markdown_review!

        # flags: 'ig' で保存 → 索引・用語集の両方
        index = load_index_terms
        glossary = load_glossary_terms
        assert_equal 1, index.size
        assert_equal 1, glossary.size
        assert_equal 'CSS', index.first['term']
      end

      def test_apply_minus_i_removes_index_flag
        seed_unified_terms([{ name: 'CSS', flags: 'ig' }])

        content = build_review(
          terms: [{ term: 'CSS', yomi: 'CSS', flag: '-i' }],
          high: [], low: []
        )
        File.write('_index_glossary_review.md', content, encoding: 'utf-8')

        @manager.apply_markdown_review!

        # 'i' が除去され 'g' のみ残る
        index = load_index_terms
        glossary = load_glossary_terms
        assert_empty index
        assert_equal 1, glossary.size
      end

      def test_apply_minus_g_removes_glossary_flag
        seed_unified_terms([{ name: 'CSS', flags: 'ig' }])

        content = build_review(
          terms: [{ term: 'CSS', yomi: 'CSS', flag: '-g' }],
          high: [], low: []
        )
        File.write('_index_glossary_review.md', content, encoding: 'utf-8')

        @manager.apply_markdown_review!

        # 'g' が除去され 'i' のみ残る
        index = load_index_terms
        glossary = load_glossary_terms
        assert_equal 1, index.size
        assert_empty glossary
      end

      def test_apply_r_flag_removes_term_entirely
        seed_unified_terms([{ name: 'CSS', flags: 'ig' }])

        content = build_review(
          terms: [{ term: 'CSS', yomi: 'CSS', flag: 'r' }],
          high: [], low: []
        )
        File.write('_index_glossary_review.md', content, encoding: 'utf-8')

        @manager.apply_markdown_review!

        # 完全に除去され rejected に追加
        assert_empty load_index_terms
        assert_empty load_glossary_terms
        assert_includes load_rejected_terms, 'CSS'
      end

      def test_apply_ig_to_i_transition_removes_g_flag
        seed_unified_terms([{ name: 'CSS', flags: 'ig' }])

        # [ig] だった用語を [i] に変更
        content = build_review(
          terms: [{ term: 'CSS', yomi: 'CSS', flag: 'i' }],
          high: [], low: []
        )
        File.write('_index_glossary_review.md', content, encoding: 'utf-8')

        @manager.apply_markdown_review!

        index = load_index_terms
        glossary = load_glossary_terms
        assert_equal 1, index.size
        assert_empty glossary
      end

      def test_apply_ig_to_g_transition_removes_i_flag
        seed_unified_terms([{ name: 'CSS', flags: 'ig' }])

        # [ig] だった用語を [g] に変更
        content = build_review(
          terms: [{ term: 'CSS', yomi: 'CSS', flag: 'g' }],
          high: [], low: []
        )
        File.write('_index_glossary_review.md', content, encoding: 'utf-8')

        @manager.apply_markdown_review!

        index = load_index_terms
        glossary = load_glossary_terms
        assert_empty index
        assert_equal 1, glossary.size
      end

      def test_glossary_only_term_persists_across_apply
        # glossary-only 用語が apply 後も消えないことを確認
        seed_unified_terms([
          { name: 'CSS', flags: 'i' },
          { name: 'ウェブサイト', flags: 'g' }
        ])

        # レビュー: CSS は [i]、ウェブサイト は [g] のまま
        content = build_review(
          terms: [
            { term: 'CSS', yomi: 'CSS', flag: 'i' },
            { term: 'ウェブサイト', yomi: 'ウェブサイト', flag: 'g' }
          ],
          high: [], low: []
        )
        File.write('_index_glossary_review.md', content, encoding: 'utf-8')

        @manager.apply_markdown_review!

        index = load_index_terms
        glossary = load_glossary_terms
        assert_equal 1, index.size
        assert_equal 'CSS', index.first['term']
        assert_equal 1, glossary.size
        assert_equal 'ウェブサイト', glossary.first['term']
      end

      def test_apply_minus_ig_removes_term_entirely
        seed_unified_terms([{ name: 'CSS', flags: 'ig' }])

        content = build_review(
          terms: [{ term: 'CSS', yomi: 'CSS', flag: '-ig' }],
          high: [], low: []
        )
        File.write('_index_glossary_review.md', content, encoding: 'utf-8')

        @manager.apply_markdown_review!

        assert_empty load_index_terms
        assert_empty load_glossary_terms
        assert_includes load_rejected_terms, 'CSS'
      end

      def test_unchecked_candidate_not_saved
        # [ ] のまま放置した候補は保存されない
        content = build_review(
          terms: [],
          high: [{ term: 'NewTerm', yomi: 'にゅーたーむ', flag: ' ' }],
          low: []
        )
        File.write('_index_glossary_review.md', content, encoding: 'utf-8')

        @manager.apply_markdown_review!

        assert_empty load_index_terms
        assert_empty load_glossary_terms
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
        File.write('config/index_glossary_terms.yml',
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
        return [] unless File.exist?('config/index_glossary_terms.yml')

        data = YAML.load_file('config/index_glossary_terms.yml')
        (data['terms'] || []).select { it['flags'].to_s.include?('i') }
      end

      def load_glossary_terms
        return [] unless File.exist?('config/index_glossary_terms.yml')

        data = YAML.load_file('config/index_glossary_terms.yml')
        (data['terms'] || []).select { it['flags'].to_s.include?('g') }
      end

      def load_rejected_terms
        return [] unless File.exist?('config/index_glossary_rejected.yml')

        data = YAML.load_file('config/index_glossary_rejected.yml')
        (data['rejected_terms'] || []).map { it['term'] }
      end

      def load_all_terms
        return [] unless File.exist?('config/index_glossary_terms.yml')

        data = YAML.load_file('config/index_glossary_terms.yml')
        (data['terms'] || []).map { it['term'] }
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

      # 汎用レビューファイルビルダー（全セクション対応）
      def build_review(terms: [], high: [], low: [], rejected: [])
        content = "# 索引・用語集レビュー\n"
        content += "※ フラグ: [i]=索引のみ、[g]=用語集のみ、[ig]=両方、[r]=棄却\n\n"

        content += "## 1. 登録済み用語の確認 (Terms: #{terms.size}語)\n\n"
        terms.each do |t|
          content += "- [#{t[:flag]}] **#{t[:term]}** (#{t[:yomi]}) - スコア: 100.0\n"
          content += "  - 01-test: テスト文脈\n\n"
        end

        content += "\n\n## 2. 推奨候補 (High Candidates: #{high.size}語)\n\n"
        high.each do |c|
          content += "- [#{c[:flag]}] `NEW!` **#{c[:term]}** (#{c[:yomi]}) - スコア: 200.0\n"
          content += "  - 01-test: テスト文脈\n\n"
        end

        content += "\n\n## 3. 一般候補 (Low Candidates: #{low.size}語)\n\n"
        low.each do |c|
          content += "- [#{c[:flag]}] `NEW!` **#{c[:term]}** (#{c[:yomi]}) - スコア: 100.0\n"
          content += "  - 01-test: テスト文脈\n\n"
        end

        content += "\n\n## 4. 除外済みリスト (Rejected: #{rejected.size}語)\n"
        content += "※ 復帰させたいものは [i], [g], [ig] を入れると索引・用語集に直接登録されます。\n\n"
        rejected.each do |r|
          content += "- [#{r[:flag]}] **#{r[:term]}** (#{r[:yomi]}) - スコア: 100.0\n"
          content += "  - 01-test: テスト文脈\n\n"
        end
        content += "除外済みの用語はありません。\n" if rejected.empty?

        content
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
