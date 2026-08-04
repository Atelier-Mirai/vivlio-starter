# frozen_string_literal: true

require 'test_helper'
require 'vivlio_starter/cli/index/heading_outline'
require 'vivlio_starter/cli/index/main_reference'

module VivlioStarter
  module CLI
    module IndexCommands
      # 節指定の解決（index-main-reference-section-spec.md R2〜R4）
      class HeadingOutlineTest < Minitest::Test
        CHAPTER = <<~MD
          # Markdown 執筆チュートリアル

          前置きの本文。

          ## Markdown とは

          ### Markdown の概要

          説明。

          ### 主な用途

          用途の説明。

          ## 拡張記法

          ### 主な用途

          こちらにも同じ見出しがある。

          #### 深い見出し

          h4 の本文。
        MD

        def outline = @outline ||= HeadingOutline.parse(CHAPTER)

        # --- phase: 文言で指す ---

        def test_locates_a_section_by_text
          located = outline.locate(['Markdown とは'])

          assert_equal 5, located.range.begin
          refute located.ambiguous
        end

        # 自動推測は語を含む見出しを探すが、手動指定は文言の一致だけを見る。
        # だから語を含まない見出しも指せる。
        def test_locates_a_heading_that_does_not_contain_the_term
          refute_nil outline.locate(['用途の説明']) || outline.locate(['主な用途'])
        end

        # レベルを問わない。実測で h4 は 56 個、h5 は 3 個ある
        def test_locates_a_deep_heading
          refute_nil outline.locate(['深い見出し'])
        end

        # 「CSS 組版」と「CSS組版」の揺れを吸収する
        def test_ignores_whitespace_when_comparing
          refute_nil outline.locate(['Markdownとは']), '空白を詰めても一致する'
        end

        # 見出しには強調・コード・ルビ・索引タグが混ざる
        def test_normalizes_decorations
          o = HeadingOutline.parse("## **強調**した `コード` の [用語|よみ]\n")

          refute_nil o.locate(['強調したコードの用語'])
        end

        # --- phase: 範囲 ---

        # 節の範囲は次の同レベル以上の見出しの直前まで
        def test_range_ends_at_the_next_sibling
          located = outline.locate(['Markdown とは'])

          assert_equal 5, located.range.begin
          assert_equal 14, located.range.end, '「## 拡張記法」の直前まで'
        end

        def test_range_of_the_last_section_reaches_the_end
          located = outline.locate(['深い見出し'])

          assert_equal CHAPTER.lines.size, located.range.end
        end

        # --- phase: 曖昧さ ---

        # 「主な用途」は 2 箇所ある。黙って最初を採らず、曖昧だと知らせる
        def test_reports_ambiguity
          located = outline.locate(['主な用途'])

          assert located.ambiguous
          assert_equal 2, located.candidates.size
          assert_includes located.candidates.first, 'Markdown とは'
        end

        # 親を添えれば一意に絞れる
        def test_ancestor_disambiguates
          located = outline.locate(['拡張記法', '主な用途'])

          refute located.ambiguous
          assert_equal 17, located.range.begin
        end

        # 中間は省略できる（祖先のいずれかに一致すればよい）
        def test_intermediate_ancestors_may_be_omitted
          located = outline.locate(['Markdown 執筆チュートリアル', '主な用途'])

          assert located.ambiguous, '章題は両方の祖先なので絞れない'
        end

        # --- phase: 見つからない ---

        def test_returns_nil_when_absent
          assert_nil outline.locate(['存在しない見出し'])
        end

        # 見出しは推敲で変わる。近いものを挙げて直し方を示せるように
        def test_suggests_a_near_heading
          o = HeadingOutline.parse("# 章\n\n## さまざまな用途\n")

          assert_includes o.nearest(['主な用途']), 'さまざまな用途'
        end

        # 候補を並べ立てない。著者が探しているのは正解であって選択肢の山ではない
        def test_nearest_returns_at_most_two
          assert_operator outline.nearest(['用途']).size, :<=, 2
        end

        def test_nearest_is_empty_when_nothing_is_close
          assert_empty outline.nearest(['まったく無関係な文字列'])
        end

        # --- phase: MainReference の分解 ---

        def test_parses_chapter_only
          ref = MainReference.parse('33-index-glossary')

          assert_equal '33-index-glossary', ref.chapter
          refute_predicate ref, :section?
        end

        def test_parses_chapter_and_section
          ref = MainReference.parse('21#Markdown とは')

          assert_equal '21', ref.chapter
          assert_equal ['Markdown とは'], ref.path
          assert_predicate ref, :section?
        end

        def test_parses_nested_path
          ref = MainReference.parse('23#章の削除（vs delete）#基本的な使い方')

          assert_equal %w[23], [ref.chapter]
          assert_equal ['章の削除（vs delete）', '基本的な使い方'], ref.path
        end

        # 著者が書いたとおりの形へ戻せる（辞書へ書き戻すため）
        def test_round_trips
          %w[33-index-glossary 21#Markdown 23#親#子].each do |value|
            assert_equal value, MainReference.parse(value).to_s
          end
        end
      end
    end
  end
end
