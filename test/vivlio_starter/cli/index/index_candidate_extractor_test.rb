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

        # --- phase: 候補の質（改善案 #98） ---

        def extract(markdown)
          File.write('contents/10-a.md', markdown)
          @extractor.extract_from_chapters!(['10-a'])
          @extractor.all_candidates
        end

        def mecab!
          skip 'MeCab が利用できない環境ではスキップ' unless YomiInferrer.new.available?
        end

        # 空白を落として連結すると「閲覧用PDF」になり、本文の「閲覧用 PDF」と一致しない
        def test_noun_sequence_keeps_the_space_between_words
          mecab!
          candidates = extract("閲覧用 PDF を作ります。閲覧用 PDF は画面で読みます。\n")

          assert_includes candidates, '閲覧用 PDF'
          refute_includes candidates, '閲覧用PDF'
        end

        # 接頭辞で切ると「章ビルド」という断片が候補になる
        def test_prefix_stays_with_the_following_noun
          mecab!
          candidates = extract("単章ビルドで確かめます。単章ビルドは速い。\n")

          assert_includes candidates, '単章ビルド'
          refute_includes candidates, '章ビルド'
        end

        # 英語の複合名は 1 語に。語の途中（viewBox）からは切り出さない
        def test_english_names_are_kept_whole
          candidates = extract("Kindle Previewer で確かめます。viewBox の値を決めます。\n")

          assert_includes candidates, 'Kindle Previewer'
          refute_includes candidates, 'Previewer'
          refute_includes candidates, 'Box'
        end

        # 見出しと次の行の語をつなげない
        def test_words_do_not_join_across_lines
          candidates = extract("## Technical Terms\n\nHTML を書きます。\n")

          refute(candidates.any? { it.include?('Terms HTML') }, candidates.inspect)
        end

        # 図解注釈の注釈行・画像の代替テキスト・ラベルは、紙面の本文ではない
        def test_machine_data_image_alt_and_labels_are_not_read
          candidates = extract(<<~MD)
            :::{.showcase}
            ![弾く人](a.webp)
            rect:1 10, 10, 20, 20 愛用のバイオリン
            :::

            ![アインシュタインの肖像](b.webp)

            ** 素数の表 @prime-table **
          MD

          %w[バイオリン アインシュタイン @prime-table prime-table].each { refute_includes candidates, it }
        end

        # 助詞で終わる・指示語で始まる断片と、数と単位は語ではない
        def test_fragments_and_measurements_are_rejected
          mecab!
          candidates = extract("前章の説明を見ます。その語について述べます。幅は 1mm と 2,894 です。\n")

          %w[前章の その語 1mm 2,894].each { refute_includes candidates, it }
        end

        # 表の列の値として並ぶ語は、本文の語のように数えない
        def test_table_column_values_are_discarded
          rows = Array.new(4) { |i| "| 記法#{i} | 拡張リファレンス |" }.join("\n")
          candidates = extract("| やりたいこと | 解説章 |\n|---|---|\n#{rows}\n\nKindle を使います。\n")

          refute_includes candidates, '拡張リファレンス'
        end

        # 本文によく出る語は、比較表の行見出しに並んでも残る
        def test_frequent_prose_term_survives_as_a_table_row_header
          prose = "Kindle で読みます。\n" * 8
          rows = Array.new(3) { "| Kindle | 対応 |" }.join("\n")
          candidates = extract("#{prose}\n| 形式 | 対応 |\n|---|---|\n#{rows}\n")

          assert_includes candidates, 'Kindle'
        end

        # 決まり文句の中の語（「表示結果は次のようになります」）は外す
        def test_boilerplate_phrase_is_discarded
          mecab!
          candidates = extract("表示結果は次のようになります。\n" * 6)

          refute_includes candidates, '表示結果'
        end

        # 続きが同じでも、決まった組み合わせの名前（Re:VIEW Starter）は定型句ではない
        def test_fixed_compound_name_is_not_boilerplate
          candidates = extract("Re:VIEW Starter の原稿です。\n" * 6)

          assert_includes candidates, 'Re:VIEW Starter'
        end

        # --- phase: 見出しの語（改善案 #98） ---

        # 2 字の要語は本文だけでは拾わないが、見出しに出れば拾う
        def test_short_noun_in_a_heading_becomes_a_candidate
          mecab!
          body = "扉絵を用意します。扉絵は縦長です。\n"
          refute_includes extract(body), '扉絵', '本文だけでは 2 字の語を拾わない'

          @extractor = IndexCandidateExtractor.new
          candidates = extract("## 扉絵の設定\n\n#{body}")

          assert_includes candidates, '扉絵'
          assert_includes @extractor.scoring.breakdown('扉絵')[:traits], :heading
        end

        # 見出しから拾った 2 字の語は、レビューで 1 か所にまとめるために見分ける
        def test_short_heading_term_is_identified
          mecab!
          extract("## 扉絵の設定\n\n扉絵を用意します。\n\n## 図番号の付け方\n\n図番号を振ります。\n")

          assert @extractor.short_heading_term?('扉絵')
          refute @extractor.short_heading_term?('図番号'), '3 字以上は本文の経路でも拾うので対象外'
          refute @extractor.short_heading_term?('未登録'), '候補でない語'
        end

        # 見出しの単独名詞でも、動作を表す名詞（サ変接続）は節の話題ではない
        def test_action_noun_in_a_heading_is_not_picked_up
          mecab!
          candidates = extract("## 指摘の見方\n\n指摘を読みます。\n")

          refute_includes candidates, '指摘'
        end

        # 多くの章の見出しに出る語（まとめ・設定）は構成の言葉なので見出しの加点をしない
        def test_structural_heading_word_gets_no_heading_bonus
          mecab!
          chapters = Array.new(5) { |i| "1#{i}-c" }
          chapters.each { File.write("contents/#{it}.md", "## 目次の設定\n\n目次を作ります。\n") }

          @extractor.extract_from_chapters!(chapters)

          refute_includes @extractor.all_candidates, '目次'
        end

        # 登録語にも候補と同じく見出しの加点を付ける。付けないと、見出しに出る登録語だけが
        # 候補より低く出て、見直し候補へ押し出される
        def test_registered_term_in_a_heading_gets_the_heading_bonus
          File.write('contents/10-a.md', "## 交ぜ書き\n\n交ぜ書きを直します。\n\n交ぜ書きは読みにくい。\n")
          File.write('contents/11-b.md', "体言止めを使います。\n\n体言止めは短い。\n")
          @extractor.extract_from_chapters!(%w[10-a 11-b])

          scores = @extractor.score_terms([{ 'term' => '交ぜ書き' }, { 'term' => '体言止め' }])

          assert_operator scores['交ぜ書き'], :>, scores['体言止め'], '同じ出方なら見出しに出る語が上'
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
