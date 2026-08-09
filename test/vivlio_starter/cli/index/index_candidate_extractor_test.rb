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

        # --- phase: スコアは ScoringEngine に委ねる（R1・R2） ---

        # ボーナスは語ごと 1 回。同じ語が何度パターンに当たっても増えない。
        # 旧実装は出現ごとの加算で、頻出語ほど高スコアになる原因だった。
        def test_repeated_matches_do_not_inflate_the_trait_bonus
          File.write('contents/11-a.md', <<~MD)
            シングルトンとは生成を 1 つに限る手法である。
            シングルトンとは生成を 1 つに限る手法である。
            シングルトンとは生成を 1 つに限る手法である。
          MD

          @extractor.extract_from_chapters!(%w[11-a])
          breakdown = @extractor.scoring.breakdown('シングルトン')

          assert_includes breakdown[:traits], :definition
          # 性質は複数付きうる（カタカナ語なので :technical も付く）。要点は
          # 「同じ性質が何度当たっても 1 回ぶん」で、合計が重みの単純和に一致すること。
          expected = breakdown[:traits].sum { ScoringEngine::TRAIT_WEIGHTS.fetch(it) }

          assert_in_delta expected, breakdown[:trait_bonus], 0.001,
                          '3 回当たってもボーナスは各性質 1 回ぶん'
        end

        # 索引語としての価値は「稀だが特定の章に集中する」こと。
        # 全章にばらまかれた語より高くなることを実データ相当の形で固定する。
        def test_concentrated_term_outranks_widespread_term
          3.times do |i|
            File.write("contents/1#{i}-ch.md", <<~MD)
              テキストエディタの話題はどの章にも出てきます。テキストエディタは便利です。
              #{i.zero? ? 'ソレノイドコイルの原理をソレノイドコイルで説明します。' : ''}
            MD
          end

          @extractor.extract_from_chapters!(%w[10-ch 11-ch 12-ch])
          scores = @extractor.term_scores

          skip 'MeCab 依存の候補が得られない環境' unless scores.key?('ソレノイドコイル') && scores.key?('テキストエディタ')

          assert_operator scores['ソレノイドコイル'], :>, scores['テキストエディタ'],
                          '1 章に集中する語が、全章に散る語より上に来ること'
        end

        def test_term_scores_comes_from_the_scoring_engine
          File.write('contents/11-a.md', "Vivliostyle とは組版エンジンである。\n")
          @extractor.extract_from_chapters!(%w[11-a])

          assert_equal @extractor.scoring.scores, @extractor.term_scores,
                       'スコアの算出元は ScoringEngine 一箇所であること'
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

        # --- phase: 記法・文の断片を候補にしない ---

        # 定義パターンは「〜について」の直前を切り出すので、素の `.` で 20 文字
        # 取ると文の途中から始まる断片が生まれる。実測（本書 27 章）では
        # 候補 4,053 件のうち 1,355 件がこの類だった。
        def test_definition_pattern_does_not_slice_across_sentences
          File.write('contents/10-a.md', <<~MD)
            索引は本の後ろに置きます。ノンブルについては次章で説明します。
          MD

          @extractor.extract_from_chapters!(['10-a'])

          assert_includes @extractor.all_candidates, 'ノンブル'
          refute(@extractor.all_candidates.any? { it.include?('。') }, '句点をまたいだ断片を拾わない')
        end

        def test_markup_fragments_are_rejected
          File.write('contents/10-a.md', <<~MD)
            ## テーマカラー

            **強調**した箇条書き。

            - `コード` を含む行
            | 表 | の | 行 |
          MD

          @extractor.extract_from_chapters!(['10-a'])

          %w[# * | ` > [ ]].each do |mark|
            refute(@extractor.all_candidates.any? { it.include?(mark) },
                   "記法 #{mark} を含む候補が残っています")
          end
        end

        # --- phase: MeCab が 1 語と認識する複合語 ---

        # 名詞連続は 2 語以上を対象にするため、MeCab の辞書に 1 語として載っている
        # 専門用語が丸ごと漏れていた（「特殊相対性理論」は拾えるのに「相対性理論」は漏れる）。
        def test_compound_noun_recognized_as_a_single_token_is_picked_up
          skip 'MeCab が利用できない環境ではスキップ' unless YomiInferrer.new.available?

          File.write('contents/10-a.md', "相対性理論を説明します。相対性理論は難しい。\n")

          @extractor.extract_from_chapters!(['10-a'])

          assert_includes @extractor.all_candidates, '相対性理論'
        end

        # 短い単独名詞まで拾うと「本」「方法」「場合」で埋まる
        def test_short_single_nouns_are_not_picked_up
          skip 'MeCab が利用できない環境ではスキップ' unless YomiInferrer.new.available?

          File.write('contents/10-a.md', "本を書く方法を説明します。場合によります。\n")

          @extractor.extract_from_chapters!(['10-a'])

          %w[本 方法 場合].each do |word|
            refute_includes @extractor.all_candidates, word
          end
        end

        # 英字のみの単独名詞は CSS クラス名や記法由来が大半（実測 153 件中 136 件）
        def test_ascii_only_single_nouns_are_not_picked_up
          skip 'MeCab が利用できない環境ではスキップ' unless YomiInferrer.new.available?

          File.write('contents/10-a.md', "section と column を並べます。\n")

          @extractor.extract_from_chapters!(['10-a'])

          refute_includes @extractor.all_candidates, 'section'
          refute_includes @extractor.all_candidates, 'column'
        end

        # --- phase: 登録語のスコア付け（score_terms） ---

        # 原稿に 1 回も出てこない語はスコアを持たない。技術用語らしい綴りだと
        # 性質ボーナスだけが残り、死語が「スコア: 15.0」と生きて見えていた
        def test_terms_absent_from_the_manuscript_get_no_score
          File.write('contents/10-a.md', "Docker で環境を揃えます。\n")
          @extractor.extract_from_chapters!(['10-a'])

          scores = @extractor.score_terms([{ 'term' => 'Docker' }, { 'term' => 'Kubernetes' }])

          assert_operator scores['Docker'], :>, 0, '原稿に出る語にはスコアが付く'
          refute scores.key?('Kubernetes'), '出現しない語は技術用語らしくてもスコアを持たない'
        end
      end
    end
  end
end
