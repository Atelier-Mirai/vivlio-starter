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

      # 回帰: インライン脚注 `^[本文]` の中身を手動登録として辞書へ
      # 登録しない。登録されると本文中の同じ文字列が全章で自動タグ付けされ、
      # 被害が辞書に残る（inline-footnote-index-collision-spec.md §3.3）。
      def test_auto_process_excludes_inline_footnote_bodies
        File.write('contents/04-footnote.md', <<~MD)
          # Inline Footnote Test

          356 枚目にあたります^[この 49 ページというずれは本書での値です]。
          読み付きの形^[アルファ|べーた]も登録しない。
          [Ruby]は本文で使用。
        MD

        @manager.auto_process!(['04-footnote'])

        content = File.read('_index_glossary_review.md')
        terms_section = content.split('## 2.')[0]
        # 登録語は太字で並ぶ（文脈表示には原文がそのまま出るので、そこは見ない）
        refute_includes terms_section, '**この 49 ページというずれは本書での値です**'
        refute_includes terms_section, '**アルファ**'
        assert_includes terms_section, '**Ruby**'
        assert_includes terms_section, '## 1. 登録済みの語（1語）', '登録されるのは [Ruby] だけ'
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
        # コードフェンス内の [codeVariable] は手動登録として抽出されない
        # （Termsセクションに **codeVariable** が含まれていない）
        terms_section = content.split('## 2.')[0]
        refute_includes terms_section, '**codeVariable**'
        # 本文の [JavaScript] は抽出される
        assert_includes content, '**JavaScript**'
      end

      # 回帰: 地の文中のインライン ``` があっても、後続コードブロック内の
      # [###] や [00, 90-98, 99] を手動登録として誤検出しない。
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
        # 特殊文字を含む手動登録の語が表示される
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

      # タスクリストのマーカー（`- [x]`）とコードの中の `[g]` は索引の記法ではない（改善案 #99）
      def test_auto_process_ignores_task_markers_and_code_spans
        File.write('contents/21-tasks.md', <<~MD)
          # Tasks

          - [x] 原稿を書く
          - [ ] 図版を用意する

          記号として見せるなら `` `[g]` `` と書きます。
        MD

        output, = capture_io { @manager.auto_process!(['21-tasks']) }

        refute_includes output, '[x] は単位・記号表記'
        refute_includes output, '[g] は単位・記号表記'
        refute_includes load_all_terms, 'x'
      end

      # auto は件数と次の手順だけを告げる。目安の表は vs index:plan の役目（改善案 #99）
      def test_auto_process_reports_only_the_review_file_summary
        File.write('contents/10-intro.md', "Vivliostyle で組版します。Vivliostyle は CSS 組版エンジンです。\n")

        output, = capture_io { @manager.auto_process!(['10-intro']) }

        assert_includes output, '🔍 レビューファイルを生成しました: 推奨する語'
        assert_equal 1, output.scan('vs index:apply を実行してください').size
        refute_includes output, 'いまの目安'
        refute_includes output, '末尾から戻せます'
      end

      # 候補にも主要参照の推測を添え、その章の文脈を先頭に出す。[im95] と i を書き足せば主要参照ごと入る（改善案 #99）
      def test_candidate_gets_suggested_main_reference_and_its_context_first
        File.write('contents/00-preface.md', "# はじめに\n\n開発は Re:VIEW Starter に触発されて始まりました。\n")
        File.write('contents/95-import.md', <<~MD)
          # Re:VIEW Starter からの移行

          Re:VIEW Starter で書いた本を移すには、vs import を使います。
          Re:VIEW Starter の原稿をそのまま読み取ります。
          Re:VIEW Starter の設定も引き継ぎます。
        MD

        capture_io { @manager.auto_process!(%w[00-preface 95-import]) }
        review = File.read('_index_glossary_review.md')
        line = review.match(/^- \[m\?95\][^\n]*\*\*Re:VIEW Starter\*\*[^\n]*\n  - ([^:]+):/)

        refute_nil line, '候補の行に主要参照の推測 [m?95] が付く'
        assert_equal '95-import', line[1], '推測した章の文脈を先頭に出す'

        File.write('_index_glossary_review.md', review.sub('- [m?95] `NEW!` **Re:VIEW Starter**', '- [im95] `NEW!` **Re:VIEW Starter**'))
        capture_io { @manager.apply_markdown_review! }

        entry = UnifiedTermsManager.new.find_term('Re:VIEW Starter')
        assert_equal ['95-import'], entry['main']
      end

      # 除外済みリストの文脈にも、索引の対象から外した章（見本の 97 章）を使わない（改善案 #99）
      def test_rejected_contexts_skip_excluded_chapters
        File.write('contents/23-figures.md', "アインシュタインは一般相対性理論を提唱しました。\n")
        File.write('contents/97-sample.md', "特殊・一般相対性理論を提唱した。\n")
        ReviewQueueManager.new.save_rejected_terms([{ 'term' => '一般相対性理論', 'yomi' => 'いっぱんそうたいせいりろん' }])

        enriched = IndexCommands.stub(:without_excluded_chapters, ->(list, **) { list - ['97-sample'] }) do
          @manager.send(:enrich_rejected_with_context)
        end

        assert_equal ['23-figures'], enriched.first['contexts'].map { it['chapter'] }
      end

      # --- phase: 主要参照を付けない判断を残す（index-glossary-registration-spec.md §3.1.1） ---

      def write_markdown_chapter
        File.write('contents/21-intro.md', <<~MD)
          # Markdown 入門

          Markdown は軽量マークアップ言語です。Markdown の記法を学びます。
        MD
      end

      def review_line(term) = File.read('_index_glossary_review.md')[/^- \[[^\]]*\][^\n]*\*\*#{Regexp.escape(term)}\*\*[^\n]*/]

      # m? を消して [i] にすると「付けない」が残り、次の auto は推測を付けない
      def test_removing_the_guess_records_no_main_reference
        write_markdown_chapter
        seed_unified_terms([{ name: 'Markdown', flags: 'i' }])
        capture_io { @manager.auto_process!(['21-intro']) }
        assert_match(/\A- \[im\?21\]/, review_line('Markdown'), '決めていない語には推測が付く')

        File.write('_index_glossary_review.md', File.read('_index_glossary_review.md').sub(/^- \[im\?21\](?=[^\n]*\*\*Markdown\*\*)/, '- [i]'))
        capture_io { @manager.apply_markdown_review! }
        assert_equal [], UnifiedTermsManager.new.find_term('Markdown')['main']

        capture_io { @manager.auto_process!(['21-intro']) }
        assert_match(/\A- \[i\] /, review_line('Markdown'), '付けないと決めた語に推測を付け直さない')
      end

      # 推測を書き換えずに apply すれば、推測した章が入る（いまと同じ）
      def test_unchanged_guess_is_adopted
        write_markdown_chapter
        seed_unified_terms([{ name: 'Markdown', flags: 'i' }])
        capture_io { @manager.auto_process!(['21-intro']) }

        capture_io { @manager.apply_markdown_review! }

        assert_equal ['21-intro'], UnifiedTermsManager.new.find_term('Markdown')['main']
      end

      # 主要参照は索引の機能なので、用語集だけの語には「付けない」を記録しない
      def test_glossary_only_term_gets_no_main_record
        seed_unified_terms([{ name: 'WWW', flags: 'g' }])
        write_review_with_rejected_items(terms: [{ term: 'WWW', yomi: 'WWW', flag: 'g' }], rejected: [])

        capture_io { @manager.apply_markdown_review! }

        refute UnifiedTermsManager.new.find_term('WWW').key?('main')
      end

      # --- phase: 原稿の [語] は辞書に無い語の入口（index-glossary-registration-spec.md §3.1.2） ---

      # 用語集だけと決めた語は、原稿に [px|px] があっても索引のフラグを足さない
      def test_markup_does_not_add_index_flag_to_glossary_only_term
        File.write('contents/23-units.md', "# 単位\n\n幅は [px|px] で書きます。\n")
        seed_unified_terms([{ name: 'px', flags: 'g', definition: '画素。' }])

        capture_io { @manager.auto_process!(['23-units']) }

        assert_equal 'g', UnifiedTermsManager.new.find_term('px')['flags']
      end

      # 棄却した語は登録せず、場所つきで知らせる
      def test_markup_of_rejected_term_is_not_registered
        File.write('contents/11-intro.md', "# はじめに\n\n最初に[セットアップ]を済ませます。\n")
        ReviewQueueManager.new.save_rejected_terms([{ 'term' => 'セットアップ', 'yomi' => 'せっとあっぷ' }])

        output, = capture_io { @manager.auto_process!(['11-intro']) }

        assert_nil UnifiedTermsManager.new.find_term('セットアップ')
        assert_includes output, '11-intro:3 に [セットアップ] がありますが、棄却した語です'
      end

      # 原稿に添えた読みが辞書と違っても、辞書の読みを使い、違いを知らせる
      def test_markup_reading_does_not_override_the_dictionary
        File.write('contents/21-intro.md', "# 入門\n\n[行頭|ぎょうがしら]をそろえます。\n")
        File.write('config/index_glossary_terms.yml',
                   { 'terms' => [{ 'term' => '行頭', 'yomi' => 'ぎょうとう', 'flags' => 'i', 'pattern' => '/行頭/' }] }.to_yaml)
        @manager.terms_manager.clear_cache!

        output, = capture_io { @manager.auto_process!(['21-intro']) }

        assert_equal 'ぎょうとう', UnifiedTermsManager.new.find_term('行頭')['yomi']
        assert_includes output, '辞書の読み（ぎょうとう）と違います'
      end

      # --- phase: 棄却するとき、原稿の印も外す（index-glossary-registration-spec.md §3.1.3） ---

      def reject_with_answer(answer, flags: 'i', mark: '-i')
        File.write('contents/11-intro.md', "# はじめに\n\n最初に[セットアップ]を済ませます。\n")
        seed_unified_terms([{ name: 'セットアップ', flags:, definition: (flags.include?('g') ? '準備。' : nil) }])
        write_review_with_rejected_items(terms: [{ term: 'セットアップ', yomi: 'せっとあっぷ', flag: mark }], rejected: [])
        manager = UnifiedIndexManager.new(input: StringIO.new(answer))
        capture_io { manager.apply_markdown_review! }
      end

      def test_yes_strips_the_markup_and_rejects
        output, = reject_with_answer("y\n")

        assert_includes output, '11-intro:3 に [セットアップ] と書かれています'
        assert_includes File.read('contents/11-intro.md'), '最初にセットアップを済ませます。'
        assert_nil UnifiedTermsManager.new.find_term('セットアップ')
        assert_includes load_rejected_terms, 'セットアップ'
      end

      # 印が何箇所もあれば、最初の場所と残りの数を示す
      def test_confirmation_shows_the_first_place_and_the_rest
        File.write('contents/11-intro.md', "# はじめに\n\n[セットアップ]を済ませます。\n\n[セットアップ]は一度だけです。\n")
        seed_unified_terms([{ name: 'セットアップ', flags: 'i' }])
        write_review_with_rejected_items(terms: [{ term: 'セットアップ', yomi: 'せっとあっぷ', flag: '-i' }], rejected: [])

        output, = capture_io { UnifiedIndexManager.new(input: StringIO.new("y\n")).apply_markdown_review! }

        assert_includes output, '11-intro:3 ほか 1 箇所に [セットアップ] と書かれています。'
        assert_includes output, '原稿の [セットアップ] を外しました（2 箇所）'
      end

      # 「いいえ」（Enter だけ・端末でない実行も）なら、原稿も辞書も変えない
      def test_no_keeps_the_markup_and_the_registration
        output, = reject_with_answer("\n")

        assert_includes output, '棄却しませんでした'
        assert_includes File.read('contents/11-intro.md'), '[セットアップ]'
        assert_equal 'i', UnifiedTermsManager.new.find_term('セットアップ')['flags']
        refute_includes load_rejected_terms, 'セットアップ'
      end

      # 用語集に残る語（ig の [-i]）は辞書から消えないので、問い合わせない
      def test_term_staying_in_the_glossary_is_not_asked
        output, = reject_with_answer('', flags: 'ig')

        refute_includes output, '❓'
        assert_equal 'g', UnifiedTermsManager.new.find_term('セットアップ')['flags']
        assert_includes File.read('contents/11-intro.md'), '[セットアップ]'
      end

      # 古い形式のレビューファイルでは apply を止める。節の境目を読み違えると、
      # 棄却した語の欄を登録済みとして読んでしまう（index-glossary-registration-spec.md §4.1）
      def test_apply_stops_on_an_old_review_file
        seed_unified_terms([{ name: 'CSS', flags: 'i' }])
        File.write('_index_glossary_review.md', "## 1. 登録済み用語の確認 (Terms: 1語)\n\n- [ ] **CSS** (CSS)\n\n## 4. 除外済みリスト (Rejected: 0語)\n")

        output, = capture_io { @manager.apply_markdown_review! }

        assert_includes output, '古い形式です'
        assert_equal ['CSS'], load_index_terms.map { it['term'] }, '辞書は変えない'
      end

      # 棄却した語のスコアは、いまの候補のものだけを出す。原稿から消えた語に古い値を出さない
      def test_rejected_term_absent_from_candidates_shows_no_stale_score
        File.write('contents/10-intro.md', "# はじめに\n\n本文です。\n")
        ReviewQueueManager.new.save_rejected_terms([{ 'term' => 'Step', 'yomi' => 'Step', 'score' => 1790.0 }])

        enriched = @manager.send(:enrich_rejected_with_context, [])

        assert_nil enriched.first['score']
      end

      # --- phase: 原稿に出てこない語・使っていない語・[DELETE]（index-glossary-registration-spec.md §3.3） ---

      def review_text = File.read('_index_glossary_review.md')

      # 原稿に出てこない登録語は 5 節に [ ] で出る。そのまま apply すると外れ、説明文のある語は
      # 使っていない語（flags が空）として残る。棄却はしない
      def test_absent_registered_term_is_removed_but_keeps_its_definition
        File.write('contents/33-index.md', "# 索引\n\n推奨する語を選びます。\n")
        seed_unified_terms([{ name: '推奨候補', flags: 'ig', definition: '目安の内側の語。' }, { name: '見直し候補', flags: 'i' }])

        capture_io { @manager.auto_process!(['33-index']) }
        assert_includes review_text[/^## 5\..*\z/m], '**推奨候補**'
        refute_includes review_text[/^## 1\..*?(?=^## 2\.)/m], '**推奨候補**'

        capture_io { @manager.apply_markdown_review! }

        kept = UnifiedTermsManager.new.find_term('推奨候補')
        assert_equal '', kept['flags'], '索引にも用語集にも載せない'
        assert_equal '目安の内側の語。', kept['definition']
        assert_nil UnifiedTermsManager.new.find_term('見直し候補'), '説明文の無い語は辞書から消える'
        refute_includes load_rejected_terms, '見直し候補', '棄却はしない'
      end

      # 索引ライブラリから取り込んだ語は、原稿に出てこない間は 5 節に並べず、数だけ示す。
      # この本で外した語・棄却した語は並べる（index-library-reserve-spec.md §3.3）
      def test_absent_section_leaves_out_terms_imported_from_the_library
        File.write('contents/33-index.md', "# 索引\n\n推奨する語を選びます。\n")
        File.write('config/index_glossary_terms.yml', { 'terms' => [
          { 'term' => '版面', 'yomi' => 'はんづら', 'flags' => '', 'definition' => '文字を組む範囲。', 'source' => 'imported' },
          { 'term' => '推奨候補', 'yomi' => 'すいしょうこうほ', 'flags' => '', 'definition' => '目安の内側の語。', 'source' => 'review' }
        ] }.to_yaml)
        @manager.terms_manager.clear_cache!
        File.write('config/index_glossary_rejected.yml', { 'rejected_terms' => [
          { 'term' => '項目', 'yomi' => 'こうもく', 'source' => 'imported' },
          { 'term' => 'Step', 'yomi' => 'Step' }
        ] }.to_yaml)

        capture_io { @manager.auto_process!(['33-index']) }
        absent = review_text[/^## 5\..*\z/m]

        assert_includes absent, '**推奨候補**'
        assert_includes absent, '**Step**'
        refute_includes absent, '**版面**'
        refute_includes absent, '**項目**'
        assert_includes absent, '索引ライブラリから取り込んだ語のうち、原稿に出てこない 2 語は並べていません'
      end

      # 最後の報告の「棄却した語」は、4 節に並ぶ語（原稿に出てくる語）だけを数える
      def test_report_counts_only_rejected_terms_listed_in_section_four
        File.write('contents/33-index.md', "# 索引\n\n項目を選びます。\n")
        seed_rejected_terms(%w[項目 Step])

        output, = capture_io { @manager.auto_process!(['33-index']) }

        assert_includes output, '棄却した語 1 語'
        assert_includes review_text, '## 4. 棄却した語（1語）'
      end

      # 使っていない語を原稿に書き戻すと、以前の説明文つきで候補に戻る
      # （短い原稿では目安の語数が 0 になり帯に入らないので、候補の段で確かめる）
      def test_unused_term_returns_as_a_candidate_with_its_definition
        File.write('config/index_glossary_terms.yml',
                   { 'terms' => [{ 'term' => '推奨候補', 'yomi' => 'すいしょうこうほ', 'flags' => '', 'definition' => '目安の内側の語。' }] }.to_yaml)
        @manager.terms_manager.clear_cache!
        File.write('contents/33-index.md', "# 索引\n\n推奨候補を選びます。推奨候補は重要です。\n")

        selectable, = @manager.send(:selectable_candidates, @manager.send(:extract_candidates, ['33-index']))
        returning = @manager.send(:with_returning_unused_terms, selectable, ['33-index']).find { it['term'] == '推奨候補' }

        assert_equal '目安の内側の語。', returning['definition']
      end

      # 候補の欄で [g] にすれば、残しておいた説明文ごと用語集に戻る
      def test_unused_term_marked_glossary_comes_back_with_its_definition
        File.write('config/index_glossary_terms.yml',
                   { 'terms' => [{ 'term' => '推奨候補', 'yomi' => 'すいしょうこうほ', 'flags' => '', 'definition' => '目安の内側の語。' }] }.to_yaml)
        @manager.terms_manager.clear_cache!
        @manager.markdown_generator.generate!(
          terms: [], low_candidates: [], rejected: [],
          high_candidates: [{ 'term' => '推奨候補', 'yomi' => 'すいしょうこうほ', 'score' => 100.0, 'definition' => '目安の内側の語。' }]
        )
        File.write('_index_glossary_review.md', review_text.sub('- [ ] **推奨候補**', '- [g] **推奨候補**'))

        capture_io { @manager.apply_markdown_review! }

        entry = UnifiedTermsManager.new.find_term('推奨候補')
        assert_equal 'g', entry['flags']
        assert_equal '目安の内側の語。', entry['definition']
      end

      # [DELETE] は辞書からも棄却した語の一覧からも消す
      def test_delete_removes_the_record_everywhere
        seed_unified_terms([{ name: 'Step', flags: 'i' }])
        seed_rejected_terms(['Hz'])
        File.write('_index_glossary_review.md', <<~MD)
          ## 1. 登録済みの語（1語）
          - [DELETE] **Step** (Step)
          ## 4. 棄却した語（1語）
          - [DELETE] **Hz** (Hz)
          ## 5. 原稿に出てこない語（0語）
        MD

        capture_io { @manager.apply_markdown_review! }

        assert_nil UnifiedTermsManager.new.find_term('Step')
        refute_includes load_rejected_terms, 'Hz'
        refute_includes load_rejected_terms, 'Step', '棄却もしない'
      end

      # 原稿に印の残る語の [DELETE] は、印を外してよいか確かめる。「いいえ」なら消さない
      def test_delete_asks_about_markup_left_in_the_manuscript
        File.write('contents/11-intro.md', "# はじめに\n\n[Step]を踏みます。\n")
        seed_unified_terms([{ name: 'Step', flags: 'i' }])
        write_review_with_rejected_items(terms: [{ term: 'Step', yomi: 'Step', flag: 'DELETE' }], rejected: [])

        output, = capture_io { UnifiedIndexManager.new(input: StringIO.new("\n")).apply_markdown_review! }

        assert_includes output, '原稿の [] を外して削除しますか？'
        assert_equal 'i', UnifiedTermsManager.new.find_term('Step')['flags']
      end

      # 用語集だけの語には、一般語の外す印も主要参照の推測も付けない。付けると [-im?00] になって
      # g が消え、そのまま apply すると用語集から外れていた
      def test_glossary_only_term_keeps_its_mark_even_when_widespread
        %w[10-a 11-b 12-c 13-d 14-e 15-f].each { File.write("contents/#{it}.md", "# 章\n\nVivlio Starter を使います。Vivlio Starter で本を作ります。\n") }
        seed_unified_terms([{ name: 'Vivlio Starter', flags: 'g', definition: '電子書籍執筆システム。' }])

        capture_io { @manager.auto_process!(%w[10-a 11-b 12-c 13-d 14-e 15-f]) }
        assert_match(/^- \[g\] (`Today` )?\*\*Vivlio Starter\*\*/, review_text)

        capture_io { @manager.apply_markdown_review! }
        assert_equal 'g', UnifiedTermsManager.new.find_term('Vivlio Starter')['flags'], 'そのまま apply しても変わらない'
      end

      # --- phase: 見出し語の綴りを直す（`- 綴り: …`・改善案 #103） ---

      def write_spelling_review(term, spelled, flag: 'ig')
        File.write('_index_glossary_review.md', <<~MD)
          ## 1. 登録済みの語（1語）
          - [#{flag}m25] **#{term}** (らべるID)
            - 25-cross-reference: #{term}を付けます。
            - 綴り: #{spelled}

            識別名。
          ## 4. 棄却した語（0語）
          ## 5. 原稿に出てこない語（0語）
        MD
      end

      # 綴りだけを直し、読み・印・説明文・主要参照は残す。照合の綴り（pattern）も作り直す
      def test_spelling_line_renames_the_term_and_keeps_the_rest
        File.write('contents/25-cross-reference.md', "# 相互参照\n\nラベル ID を付けます。\n")
        File.write('config/index_glossary_terms.yml', { 'terms' => [
          { 'term' => 'ラベルID', 'yomi' => 'らべるID', 'flags' => 'ig', 'definition' => '識別名。',
            'main' => ['25-cross-reference'], 'pattern' => '/ラベルID/' }
        ] }.to_yaml)
        @manager.terms_manager.clear_cache!
        write_spelling_review('ラベルID', 'ラベル ID')

        capture_io { @manager.apply_markdown_review! }

        terms = UnifiedTermsManager.new
        assert_nil terms.find_term('ラベルID')
        entry = terms.find_term('ラベル ID')
        assert_equal ['ig', 'らべるID', '識別名。', ['25-cross-reference']], entry.values_at('flags', 'yomi', 'definition', 'main')
        assert_equal '/ラベル\ ID/', entry['pattern']
      end

      # 新しい綴りがもう辞書にあれば直さずに知らせる
      def test_spelling_line_does_not_overwrite_an_existing_term
        seed_unified_terms([{ name: 'ラベルID', flags: 'ig', definition: '識別名。' }, { name: 'ラベル ID', flags: 'i' }])
        write_spelling_review('ラベルID', 'ラベル ID')

        output, = capture_io { @manager.apply_markdown_review! }

        assert_includes output, 'すでに辞書にあります'
        refute_nil UnifiedTermsManager.new.find_term('ラベルID')
      end

      # 原稿に古い綴りが残っていれば、原稿も直すか確かめる。「はい」なら原稿を直す
      def test_spelling_line_offers_to_respell_the_manuscript
        File.write('contents/25-cross-reference.md', "# 相互参照\n\nラベルID を付けます。ラベル ID も同じです。\n")
        seed_unified_terms([{ name: 'ラベルID', flags: 'ig', definition: '識別名。' }])
        write_spelling_review('ラベルID', 'ラベル id')

        output, = capture_io { UnifiedIndexManager.new(input: StringIO.new("y\n")).apply_markdown_review! }

        assert_includes output, '「ラベルID」の綴りを「ラベル id」に直しました'
        assert_includes output, '原稿の 25-cross-reference:3 ほか 1 箇所に「ラベルID」「ラベル ID」があります。原稿も直しますか？'
        assert_equal "# 相互参照\n\nラベル id を付けます。ラベル id も同じです。\n", File.read('contents/25-cross-reference.md')
      end

      # 「いいえ」なら原稿は触らず、索引に載らないことを知らせる。辞書の綴りは直す
      def test_spelling_line_keeps_the_manuscript_when_declined
        File.write('contents/25-cross-reference.md', "# 相互参照\n\nラベルID を付けます。\n")
        seed_unified_terms([{ name: 'ラベルID', flags: 'ig', definition: '識別名。' }])
        write_spelling_review('ラベルID', 'ラベル id')

        output, = capture_io { UnifiedIndexManager.new(input: StringIO.new("\n")).apply_markdown_review! }

        assert_includes output, 'このままでは索引の「ラベル id」に載りません'
        assert_equal "# 相互参照\n\nラベルID を付けます。\n", File.read('contents/25-cross-reference.md')
        refute_nil UnifiedTermsManager.new.find_term('ラベル id')
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

        assert_includes output, '✅ 辞書を更新しました'
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

      # --- phase: 廃止キーと採否ロジック（§3.4 / §3.6） ---

      # 設定を差し替えた manager を作る。CONFIG はプロセス全体で共有される
      # ため触らない（他のテストへ漏れる）。ここで差し替えるのは素の Hash。
      # 帯（推奨候補・一般候補・見直し候補）の件数を見るテストは、必ず
      # `target_terms` を明示すること。**既定は Common::CONFIG＝プロジェクトの
      # book.yml から来る**ので、著者が `standard` を `light` に変えただけで
      # 目安語数が 0 になり、推奨候補が空になってテストが落ちる（実例あり）。
      def manager_with(overrides)
        manager = UnifiedIndexManager.new
        config = manager.instance_variable_get(:@config).merge(overrides)
        manager.instance_variable_set(:@config, config)
        manager
      end

      def test_auto_process_does_not_auto_approve_by_default
        File.write('contents/43-auto.md', <<~MD)
          # 自動承認の確認

          プロトコルスタックとは通信手順の階層である。プロトコルスタックを実装する。
        MD

        manager_with(target_terms: 1).auto_process!(['43-auto'])

        # 何も書かなければ辞書ファイル自体が作られない。それが最も強い「書いていない」証拠。
        auto_extracted = if File.exist?('config/index_glossary_terms.yml')
                           (YAML.load_file('config/index_glossary_terms.yml')['terms'] || [])
                             .select { it['source'] == 'auto_extracted' }
                         else
                           []
                         end

        assert_empty auto_extracted, '既定では候補を辞書へ書かない'
        assert_includes File.read('_index_glossary_review.md'), 'プロトコルスタック',
                        'レビューファイルには候補として出す'
      end

      def test_auto_process_auto_approves_when_enabled
        File.write('contents/44-approve.md', <<~MD)
          # 自動承認の確認

          プロトコルスタックとは通信手順の階層である。プロトコルスタックを実装する。
        MD

        manager_with(target_terms: 1, auto_approve: true).auto_process!(['44-approve'])

        terms = YAML.load_file('config/index_glossary_terms.yml')['terms'] || []

        assert(terms.any? { it['source'] == 'auto_extracted' },
               'auto_approve: true なら推奨候補を辞書へ書く')
      end

      # 目安語数が帯の境目になる。目安を絞れば推奨候補も絞られる。
      def test_target_terms_limits_the_recommended_band
        File.write('contents/45-target.md', <<~MD)
          # 目安の確認

          プロトコルスタックとは通信手順の階層である。
          レプリケーションとはデータ複製の仕組みである。
          コンパイラとは翻訳器である。
        MD

        small = manager_with(target_terms: 1, auto_approve: true)
        small.auto_process!(['45-target'])

        approved = (YAML.load_file('config/index_glossary_terms.yml')['terms'] || [])
                   .select { it['source'] == 'auto_extracted' }

        assert_operator approved.size, :<=, 1, '目安 1 語なら推奨候補も 1 語まで'
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
        assert_includes content, '## 4. 棄却した語'
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

      # --- phase: context はそのつど原稿から拾う ---
      #
      # 辞書は contexts を持たない（UnifiedTermsManager#save_terms!）。文脈は
      # レビューのたびに現原稿から採り直すので、古い抜粋が出る余地がない。

      def test_enrich_takes_context_from_the_current_manuscript
        File.write('contents/10-intro.md', "この章では特殊相対性理論を丁寧に説明します。\n")
        terms = [{ 'term' => '特殊相対性理論', 'flags' => 'i' }]

        enriched = @manager.send(:enrich_terms_with_context, terms, ['10-intro'])

        contexts = enriched.first['contexts']
        assert_equal 1, contexts.size
        assert_includes contexts.first['context'], '丁寧に説明します'
      end

      # 出現する章が複数あれば、そのぶん使用例を並べる（1 章で打ち切らない・報告書 §5.1）
      def test_enrich_collects_context_from_every_chapter_where_the_term_appears
        File.write('contents/10-intro.md', "推敲後の新しい文章に特殊相対性理論が登場します。\n")
        File.write('contents/20-body.md', "この章でも特殊相対性理論を扱います。\n")
        terms = [{ 'term' => '特殊相対性理論', 'flags' => 'i' }]

        enriched = @manager.send(:enrich_terms_with_context, terms, %w[10-intro 20-body])

        contexts = enriched.first['contexts']
        assert_equal %w[10-intro 20-body], contexts.map { it['chapter'] }.sort
      end

      # 旧辞書が抱えている古い抜粋は読まない——現原稿の文章に置き換わる
      def test_enrich_ignores_legacy_contexts_carried_in_the_dictionary
        File.write('contents/10-intro.md', "推敲後の新しい文章に特殊相対性理論が登場します。\n")
        terms = [{ 'term' => '特殊相対性理論', 'flags' => 'i',
                   'contexts' => [{ 'chapter' => '10-intro', 'context' => '推敲前の古い抜粋テキスト' }] }]

        enriched = @manager.send(:enrich_terms_with_context, terms, ['10-intro'])

        contexts = enriched.first['contexts']
        assert_equal 1, contexts.size
        assert_includes contexts.first['context'], '推敲後の新しい文章'
        refute(contexts.any? { it['context'].include?('推敲前の古い抜粋') })
      end

      # 章を指定した実行でも、指定外の章から文脈を拾う（欄が空だと残すか判断できない）。
      # 指定外から拾ったことは out_of_scope の注記で分かるようにする
      def test_enrich_falls_back_to_chapters_outside_the_scanned_set
        File.write('contents/61-developer.md', "入稿では PDF/X-1a を求められます。\n")
        File.write('contents/10-intro.md', "本文。\n")
        terms = [{ 'term' => 'PDF/X-1a', 'flags' => 'g' }]

        enriched = @manager.send(:enrich_terms_with_context, terms, ['10-intro'])

        contexts = enriched.first['contexts']
        assert_equal 1, contexts.size
        assert_equal '61-developer', contexts.first['chapter']
        assert_includes contexts.first['context'], '入稿では'
        assert contexts.first['out_of_scope'], '指定外の章から拾ったことを示す注記が付くこと'
      end

      # 指定章に出てくる語は、指定章の使い方を先に見せる（いま推敲している章が優先）
      def test_enrich_prefers_the_scanned_chapter_when_the_term_appears_in_both
        File.write('contents/10-intro.md', "はじめに特殊相対性理論の輪郭を描きます。\n")
        File.write('contents/61-developer.md', "開発者向けにも特殊相対性理論が出てきます。\n")
        terms = [{ 'term' => '特殊相対性理論', 'flags' => 'i' }]

        enriched = @manager.send(:enrich_terms_with_context, terms, ['10-intro'])

        contexts = enriched.first['contexts']
        assert_equal '10-intro', contexts.first['chapter']
        refute contexts.first['out_of_scope'], '指定章から拾ったものに注記は付かない'
      end

      # 原稿のどこにも出てこない語は文脈を持たない（削除済み・死語として著者に見せる）
      def test_enrich_yields_no_context_for_terms_absent_from_the_manuscript
        File.write('contents/10-intro.md', "本文にはこの語は出ません。\n")
        terms = [{ 'term' => '幻の用語', 'flags' => 'i',
                   'contexts' => [{ 'chapter' => '99-removed', 'context' => '削除済み章の抜粋' }] }]

        enriched = @manager.send(:enrich_terms_with_context, terms, ['10-intro'])

        assert_empty enriched.first['contexts']
      end

      # --- phase: 主要参照の候補提示（index-main-reference-spec.md R2） ---

      # 6 章のうち 3 章（0.5 >= 0.33）に出る語を作る。判定の下限は TermSpread と共通
      def spread_project(term)
        %w[10-a 20-b 30-c 40-d 50-e 60-f].each_with_index do |name, i|
          body = i < 3 ? "# #{term}を使う\n\n本文。\n" : "# 別の章\n\n本文。\n"
          File.write("contents/#{name}.md", body)
        end
        %w[10-a 20-b 30-c 40-d 50-e 60-f]
      end

      def test_suggests_a_chapter_for_widely_spread_terms
        chapters = spread_project('ノンブル')
        terms = [{ 'term' => 'ノンブル', 'flags' => 'i' }]

        enriched = @manager.send(:enrich_terms_with_context, terms, chapters)

        assert_equal ['10'], enriched.first['main_tokens']
        assert enriched.first['main_suggested'], '機械の推測であることを示す'
      end

      # 著者が既に決めている語には触らない（毎回 NEW! だと新旧が読めない）
      def test_does_not_overwrite_an_authored_main_reference
        chapters = spread_project('ノンブル')
        terms = [{ 'term' => 'ノンブル', 'flags' => 'i', 'main' => '30-c' }]

        enriched = @manager.send(:enrich_terms_with_context, terms, chapters)

        assert_equal ['30'], enriched.first['main_tokens']
        refute enriched.first['main_suggested']
      end

      # 2〜3 章にしか出ない語は索引のページ番号がそのまま案内として働く
      def test_no_suggestion_for_narrowly_used_terms
        File.write('contents/10-intro.md', "# ノンブル\n\n本文。\n")
        terms = [{ 'term' => 'ノンブル', 'flags' => 'i' }]

        enriched = @manager.send(:enrich_terms_with_context, terms, ['10-intro'])

        assert_nil enriched.first['main_tokens']
      end

      # reference_style: all は主要参照の扱いを丸ごと切る設定。
      # 使わない機能の候補を出し続けるのはノイズにしかならない。
      def test_no_suggestion_when_the_feature_is_turned_off
        chapters = spread_project('ノンブル')
        terms = [{ 'term' => 'ノンブル', 'flags' => 'i' }]
        @manager.instance_variable_get(:@config)[:reference_style] = 'all'

        enriched = @manager.send(:enrich_terms_with_context, terms, chapters)

        assert_nil enriched.first['main_tokens']
      end

      # --- phase: 未出現の用語集語警告（R4） ---

      # R4: 今回のスキャンに出現しない g 語は catalog 未登録の出現章名つきで警告される（掲載は維持）
      # （catalog.yml が無い環境なので走査範囲の判定はフォールバックし、従来どおり警告する）
      def test_warn_unmatched_glossary_terms_hints_outside_chapter
        File.write('contents/61-developer.md', "PDF/X-1a は印刷入稿の規格です。\n")
        glossary = [{ 'term' => 'PDF/X-1a', 'flags' => 'g' }]

        output, = capture_io do
          @manager.send(:warn_unmatched_glossary_terms, glossary, {}, ['10-intro'])
        end

        assert_includes output, '用語集語がビルド対象章に出現しません: PDF/X-1a'
        assert_includes output, 'catalog 未登録の 61-developer に出現'
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

      # 1 節の行で印を外した（[ ]）語は、用語集のフラグを失う
      def test_apply_blank_flag_in_section1_removes_from_glossary_terms
        seed_unified_terms([{ name: 'WWW', flags: 'g' }])
        write_review_with_rejected_items(terms: [{ term: 'WWW', yomi: 'WWW', flag: ' ' }], rejected: [])

        @manager.apply_markdown_review!

        assert_empty load_glossary_terms
      end

      # レビューファイルに行の無い語は、著者が判断していないので触らない
      # （index-glossary-registration-spec.md §3.1.4。表示しない登録語まで外れていた）
      def test_apply_keeps_terms_absent_from_the_review_file
        seed_unified_terms([{ name: 'WWW', flags: 'g' }, { name: 'CSS', flags: 'i' }])
        write_review_with_rejected_items(terms: [], rejected: [])

        @manager.apply_markdown_review!

        assert_equal ['WWW'], load_glossary_terms.map { it['term'] }
        assert_equal ['CSS'], load_index_terms.map { it['term'] }
      end

      # 1 節で印を外した（[ ]）語だけが索引から外れる。行の無い語（JavaScript）は残る
      def test_apply_stale_index_data_removed_when_not_approved
        seed_unified_terms([{ name: 'CSS', flags: 'i' }, { name: 'HTML', flags: 'i' }, { name: 'JavaScript', flags: 'i' }])

        write_review_with_rejected_items(
          terms: [{ term: 'CSS', yomi: 'CSS', flag: 'i' }, { term: 'HTML', yomi: 'HTML', flag: ' ' }],
          rejected: []
        )

        @manager.apply_markdown_review!

        assert_equal %w[CSS JavaScript], load_index_terms.map { it['term'] }.sort
      end

      # レビューファイルに行の無い用語集の語（Beta）は、著者が判断していないので残す（§3.1.4）
      def test_apply_keeps_glossary_terms_absent_from_the_review_file
        seed_unified_terms([{ name: 'Alpha', flags: 'g' }, { name: 'Beta', flags: 'g' }])

        write_review_with_glossary_approved(
          glossary: [{ term: 'Alpha', yomi: 'あるふぁ', definition: 'テスト定義' }],
          rejected: []
        )

        @manager.apply_markdown_review!

        assert_equal %w[Alpha Beta], load_glossary_terms.map { it['term'] }.sort
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

        # WWW はレビューファイルに行が無いので、触らずに残る（§3.1.4）
        assert_equal ['WWW'], load_glossary_terms.map { it['term'] }

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

      # マイナスは直後の 1 文字にだけ掛かる（index-glossary-registration-spec.md §3.4）。
      # [-ig] と [g-i] は「索引から外し、用語集には残す」、[-i-g] は両方外して棄却（[r] と同じ）
      def apply_mark(mark, flags: 'ig')
        seed_unified_terms([{ name: 'CSS', flags:, definition: '見た目を指定する言語。' }])
        File.write('_index_glossary_review.md', build_review(terms: [{ term: 'CSS', yomi: 'CSS', flag: mark }], high: [], low: []),
                   encoding: 'utf-8')
        capture_io { @manager.apply_markdown_review! }
        UnifiedTermsManager.new.find_term('CSS')
      end

      def test_apply_minus_i_with_g_keeps_the_glossary
        %w[-ig g-i].each do |mark|
          assert_equal 'g', apply_mark(mark)['flags'], mark
          refute_includes load_rejected_terms, 'CSS', "#{mark} は棄却しない"
        end
      end

      def test_apply_minus_g_with_i_keeps_the_index
        %w[i-g -gi].each { assert_equal 'i', apply_mark(it)['flags'], it }
      end

      def test_apply_minus_i_minus_g_rejects_like_r
        assert_nil apply_mark('-i-g')
        assert_includes load_rejected_terms, 'CSS'
      end

      # 索引から外す印に主要参照が書かれていても記録しない（主要参照は索引の機能）
      def test_apply_does_not_record_main_for_a_term_leaving_the_index
        seed_unified_terms([{ name: 'CSS', flags: 'ig', definition: '見た目を指定する言語。' }])
        File.write('_index_glossary_review.md',
                   build_review(terms: [{ term: 'CSS', yomi: 'CSS', flag: '-igm?21' }], high: [], low: []), encoding: 'utf-8')

        capture_io { @manager.apply_markdown_review! }

        entry = UnifiedTermsManager.new.find_term('CSS')
        assert_equal 'g', entry['flags']
        assert_nil entry['main']
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

      # --- phase: terms と rejected の排他性（index-apply-rejected-consistency-spec.md） ---
      #
      # 発端は 2026-08-21、原稿の加筆に合わせて apply を実行したら、手書きの定義文を持つ
      # 用語集の語が 3 件消えた事故。原因は 2 段の時限式で、1 回目の apply が矛盾
      # （terms と rejected の両方に載る）を作り、2 回目以降がそれを「削除」で解決していた。

      # IA-01: [-i] は「索引から外す／用語集には残す」。除外リストへ書いてはならない。
      def test_index_rejection_keeps_the_glossary_entry_out_of_the_rejected_list
        seed_unified_terms([{ name: 'CSS', flags: 'ig', definition: 'スタイルシート言語。' }])
        write_review_with_rejected_items(terms: [{ term: 'CSS', yomi: 'CSS', flag: '-i' }], rejected: [])

        @manager.apply_markdown_review!

        entry = YAML.load_file('config/index_glossary_terms.yml')['terms'].first

        assert_equal 'g', entry['flags'], '索引フラグだけ落ちる'
        assert_equal 'スタイルシート言語。', entry['definition'], '定義文は保たれる'
        refute_includes load_rejected_terms, 'CSS', '用語集に残る語を除外リストへ入れない'
      end

      # IA-02: フラグを全部失う場合だけは terms に残す先が無いので除外リストへ送る。
      def test_index_rejection_rejects_a_term_that_loses_every_flag
        seed_unified_terms([{ name: 'コピー', flags: 'i' }])
        write_review_with_rejected_items(terms: [{ term: 'コピー', yomi: 'こぴー', flag: '-i' }], rejected: [])

        @manager.apply_markdown_review!

        refute_includes load_all_terms, 'コピー'
        assert_includes load_rejected_terms, 'コピー'
      end

      # IA-03: [-g] も同型（索引には残す／全フラグを失えば除外リストへ）。
      def test_glossary_rejection_is_symmetric
        seed_unified_terms([{ name: 'CSS', flags: 'ig', definition: '定義文' }, { name: 'PDF', flags: 'g' }])
        write_review_with_rejected_items(
          terms: [{ term: 'CSS', yomi: 'CSS', flag: '-g' }, { term: 'PDF', yomi: 'PDF', flag: '-g' }],
          rejected: []
        )

        @manager.apply_markdown_review!

        assert_equal 'i', YAML.load_file('config/index_glossary_terms.yml')['terms']
                              .find { it['term'] == 'CSS' }['flags']
        refute_includes load_rejected_terms, 'CSS', 'i が残るので除外リストへ入れない'
        refute_includes load_all_terms, 'PDF'
        assert_includes load_rejected_terms, 'PDF', 'g しか無い語は全フラグを失う'
      end

      # IA-04: **回帰の要。** 既に矛盾を抱えた辞書（terms にも rejected にも居る）で
      # apply しても、定義文を持つ terms 側が残り、除外リストのほうが掃除される。
      def test_apply_resolves_the_contradiction_by_cleaning_the_rejected_list
        seed_unified_terms([{ name: 'CSS', flags: 'g', definition: 'スタイルシート言語。' }])
        seed_rejected_terms(['CSS'])
        # 実際の矛盾はこの形で現れる——生成器は登録済みなので 1 節へ並べ、
        # 除外リストにも居るので 4 節へも並べる。
        write_review_with_rejected_items(
          terms: [{ term: 'CSS', yomi: 'CSS', flag: 'g', definition: 'スタイルシート言語。' }],
          rejected: [{ term: 'CSS', yomi: 'CSS', flag: ' ' }]
        )

        @manager.apply_markdown_review!

        entry = YAML.load_file('config/index_glossary_terms.yml')['terms'].find { it['term'] == 'CSS' }

        refute_nil entry, '登録済みの語を除外リストを根拠に消さない'
        assert_equal 'スタイルシート言語。', entry['definition']
        refute_includes load_rejected_terms, 'CSS', '矛盾は除外リスト側を落として解消する'
      end

      # IA-05: 著者が明示した [r] は従来どおり削除し、除外リストへ登録する。
      def test_explicit_rejection_still_removes_the_term
        seed_unified_terms([{ name: 'ヒント', flags: 'i' }])
        write_review_with_rejected_items(terms: [{ term: 'ヒント', yomi: 'ひんと', flag: 'r' }], rejected: [])

        @manager.apply_markdown_review!

        refute_includes load_all_terms, 'ヒント'
        assert_includes load_rejected_terms, 'ヒント'
      end

      # IA-06: 定義文ごと消すときは黙らない。個別の分岐より規律のほうが長持ちする。
      def test_removing_a_term_with_a_definition_is_announced
        seed_unified_terms([{ name: 'CSS', flags: 'ig', definition: 'スタイルシート言語。' }])
        write_review_with_rejected_items(terms: [{ term: 'CSS', yomi: 'CSS', flag: 'r' }], rejected: [])

        warnings = []
        Common.stub(:log_warn, ->(msg) { warnings << msg }) { @manager.apply_markdown_review! }

        assert(warnings.any? { it.include?('CSS') && it.include?('定義文') }, "警告が出ていない: #{warnings}")
        assert(warnings.any? { it.include?('vs index:apply') }, '戻し方を添える')
      end

      # IA-07: **本丸。** 同じレビューで 2 回 apply しても 2 回目に削除が起きない。
      # 元の不具合は「1 回目は正常に見え、2 回目で壊れる」形だったので、
      # 1 回だけ走らせるテストでは捕まらない。
      def test_apply_is_idempotent_for_a_term_kept_in_the_glossary
        seed_unified_terms([{ name: 'CSS', flags: 'ig', definition: 'スタイルシート言語。' }])
        write_review_with_rejected_items(terms: [{ term: 'CSS', yomi: 'CSS', flag: '-i' }], rejected: [])
        review = File.read('_index_glossary_review.md')

        @manager.apply_markdown_review!
        File.write('_index_glossary_review.md', review, encoding: 'utf-8')
        @manager.terms_manager.clear_cache!
        @manager.apply_markdown_review!

        entry = YAML.load_file('config/index_glossary_terms.yml')['terms'].find { it['term'] == 'CSS' }

        refute_nil entry, '2 回目の apply で消えてはならない'
        assert_equal 'スタイルシート言語。', entry['definition']
      end

      private

      # --- テストヘルパー ---

      # 統合辞書をセットアップ
      # @param entries [Array<Hash>] { name:, flags:, definition: } のリスト
      def seed_unified_terms(entries)
        terms = entries.map do |e|
          {
            'term' => e[:name], 'yomi' => e[:name],
            'flags' => e[:flags], 'definition' => e[:definition].to_s,
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
        content += "## 1. 登録済みの語 (Terms: #{terms.size}語)\n\n"
        if terms.empty?
          content += "登録済みの用語はありません。\n"
        else
          terms.each do |t|
            content += "- [#{t[:flag]}] `Today` **#{t[:term]}** (#{t[:yomi]}) - スコア: 100.0\n"
            content += "  - 01-test: テスト文脈\n\n"
            # 用語集の説明文は空行の後にインデントして置く（実物の生成器と同じ形）
            content += "  #{t[:definition]}\n\n" if t[:definition]
          end
        end

        # Section 2 & 3: empty candidates
        content += "\n\n## 2. 推奨する語 (High Candidates: 0語)\n\n"
        content += "## 3. 残りの語 (Low Candidates: 0語)\n\n"

        # Section 4: Rejected
        content += "## 4. 棄却した語 (Rejected: #{rejected.size}語)\n"
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

        content += "## 1. 登録済みの語 (Terms: #{terms.size}語)\n\n"
        terms.each do |t|
          content += "- [#{t[:flag]}] **#{t[:term]}** (#{t[:yomi]}) - スコア: 100.0\n"
          content += "  - 01-test: テスト文脈\n\n"
        end

        content += "\n\n## 2. 推奨する語 (High Candidates: #{high.size}語)\n\n"
        high.each do |c|
          content += "- [#{c[:flag]}] `NEW!` **#{c[:term]}** (#{c[:yomi]}) - スコア: 200.0\n"
          content += "  - 01-test: テスト文脈\n\n"
        end

        content += "\n\n## 3. 残りの語 (Low Candidates: #{low.size}語)\n\n"
        low.each do |c|
          content += "- [#{c[:flag]}] `NEW!` **#{c[:term]}** (#{c[:yomi]}) - スコア: 100.0\n"
          content += "  - 01-test: テスト文脈\n\n"
        end

        content += "\n\n## 4. 棄却した語 (Rejected: #{rejected.size}語)\n"
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
        content += "## 1. 登録済みの語 (Terms: #{glossary.size}語)\n\n"
        glossary.each do |t|
          content += "- [g] `Today` **#{t[:term]}** (#{t[:yomi]}) - スコア: 100.0\n"
          content += "  - 01-test: テスト文脈\n\n"
          content += "  #{t[:definition]}\n\n" if t[:definition]
        end

        content += "\n\n## 2. 推奨する語 (High Candidates: 0語)\n\n"
        content += "## 3. 残りの語 (Low Candidates: 0語)\n\n"
        content += "## 4. 棄却した語 (Rejected: 0語)\n"
        content += "※ 復帰させたいものは [i], [g], [ig] を入れると索引・用語集に直接登録されます。\n\n"
        content += "除外済みの用語はありません。\n"

        File.write('_index_glossary_review.md', content, encoding: 'utf-8')
      end
    end
  end
end
