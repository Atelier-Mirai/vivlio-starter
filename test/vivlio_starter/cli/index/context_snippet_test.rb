# frozen_string_literal: true

require 'test_helper'
require 'vivlio_starter/cli/index/context_snippet'

module VivlioStarter
  module CLI
    module IndexCommands
      class ContextSnippetTest < Minitest::Test
        def snippet(content, term, width: 40) = ContextSnippet.around(content, term, width:)

        # --- phase: 文を単位にする ---

        def test_returns_the_sentence_containing_the_term
          content = "前の文です。トンボ付きの PDF を出力し、入稿まで自動化します。こちらは次の文です。\n"

          assert_equal 'トンボ付きの PDF を出力し、入稿まで自動化します。', snippet(content, 'トンボ')
        end

        def test_markup_is_removed
          content = "**電子書籍**も `vs build` で[出力](https://example.com)できます {.aki}\n"

          assert_equal '電子書籍も vs build で出力できます', snippet(content, '電子書籍')
        end

        # 長い文は語の前後を読点の位置で詰め、詰めた側に「…」を付ける
        def test_long_sentence_is_shortened_at_a_comma_with_ellipsis
          content = "#{'あ' * 30}、#{'い' * 30}、トンボを付けて、#{'う' * 30}、#{'え' * 30}。\n"
          result = snippet(content, 'トンボ', width: 20)

          assert result.start_with?('…')
          assert result.end_with?('…')
          assert_includes result, 'トンボ'
          refute_includes result, 'あ'
        end

        # --- phase: どの行から取るか ---

        def test_prefers_body_sentence_over_heading_and_table
          content = <<~MD
            ## ルビの付け方

            | ルビ | 記法 |
            |---|---|

            ルビは本文の漢字に読みを添えます。
          MD

          assert_equal 'ルビは本文の漢字に読みを添えます。', snippet(content, 'ルビ')
        end

        def test_falls_back_to_table_row_then_heading
          assert_equal 'ルビ | 執筆チュートリアル', snippet("## 早見表\n\n| ルビ | 執筆チュートリアル |\n", 'ルビ')
          assert_equal 'ルビの付け方', snippet("## ルビの付け方\n", 'ルビ')
        end

        # 長い語の中の一致は使わない（「TeX」の抜粋に「LaTeX」の文を出さない）
        def test_ignores_matches_inside_longer_words
          content = "LaTeX のソースです。TeX の決まりで組まれます。\n"

          assert_equal 'TeX の決まりで組まれます。', snippet(content, 'TeX')
        end

        def test_code_only_occurrence_gives_empty_snippet
          assert_equal '', snippet("```yaml\npublisher: 発行者\n```\n", '発行者')
        end
      end
    end
  end
end
