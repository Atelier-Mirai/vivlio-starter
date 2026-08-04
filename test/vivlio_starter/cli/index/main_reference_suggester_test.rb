# frozen_string_literal: true

require 'test_helper'
require 'vivlio_starter/cli/index/main_reference_suggester'
require 'tmpdir'
require 'fileutils'

module VivlioStarter
  module CLI
    module IndexCommands
      # 主要参照の候補算出（index-main-reference-spec.md R2）
      #
      # 起票の経緯: 索引は「出現箇所」ではなく「説明箇所」を指すべきだが、
      # 全語に main: を手で書かせるのは現実的でない。見出し一致から 1 章だけ
      # 提示し、確定は著者に委ねる。
      class MainReferenceSuggesterTest < Minitest::Test
        def setup
          @original_dir = Dir.pwd
          @temp_dir = Dir.mktmpdir('main_ref_suggester_test')
          Dir.chdir(@temp_dir)
          FileUtils.mkdir_p('contents')
        end

        def teardown
          Dir.chdir(@original_dir)
          FileUtils.rm_rf(@temp_dir)
        end

        def write_chapter(basename, body)
          File.write("contents/#{basename}.md", body)
          basename
        end

        def term(name, pattern: nil)
          entry = { 'term' => name }
          entry['pattern'] = pattern if pattern
          entry
        end

        def suggest(terms, chapters) = MainReferenceSuggester.suggest(terms, chapters)

        # --- phase: 見出し一致（優先順位 1） ---

        def test_picks_the_chapter_with_the_most_headings
          chapters = [
            write_chapter('10-intro', "# はじめに\n\n索引について少し触れます。\n"),
            write_chapter('33-index', "# 索引の作り方\n\n## 索引の設定\n\n### 索引の確認\n\n本文。\n")
          ]

          assert_equal({ '索引' => '33-index' }, suggest([term('索引')], chapters))
        end

        # 同数なら章番号の若い方。実行のたびに候補が入れ替わると、
        # 著者は「前回と違う」を差分として読めなくなる。
        def test_ties_go_to_the_earlier_chapter
          chapters = [
            write_chapter('21-markdown', "# Markdown の記法\n\n本文。\n"),
            write_chapter('22-extension', "# Markdown の拡張\n\n本文。\n")
          ]

          assert_equal({ 'Markdown' => '21-markdown' }, suggest([term('Markdown')], chapters))
        end

        # 章の渡され方（順序）で結果が変わらないこと
        def test_result_does_not_depend_on_chapter_argument_order
          write_chapter('21-markdown', "# Markdown の記法\n")
          write_chapter('22-extension', "# Markdown の拡張\n")

          forward = suggest([term('Markdown')], %w[21-markdown 22-extension])
          reversed = suggest([term('Markdown')], %w[22-extension 21-markdown])

          assert_equal forward, reversed
        end

        # h4 以下は拾わない。細かすぎる見出しまで数えると、
        # 手順の見出しが並ぶ章がどの語でも勝ってしまう。
        def test_only_h1_to_h3_count
          chapters = [
            write_chapter('10-intro', "#### 索引の小見出し\n\n本文。\n"),
            write_chapter('33-index', "### 索引\n\n本文。\n")
          ]

          assert_equal({ '索引' => '33-index' }, suggest([term('索引')], chapters))
        end

        # コード例の中の「# 索引」はコメント行であって見出しではない
        def test_code_fences_are_stripped_before_counting_headings
          chapters = [
            write_chapter('10-intro', "```ruby\n# 索引\n# 索引\n# 索引\n```\n\n索引に触れます。\n"),
            write_chapter('33-index', "# 索引\n\n索引の本文。\n")
          ]

          assert_equal({ '索引' => '33-index' }, suggest([term('索引')], chapters))
        end

        # --- phase: 出現回数（見出しに出ない語の受け皿） ---

        # 見出しに一度も出ない語でも、出現回数で候補を出せる。
        # 旧実装（見出しヒット数だけ）は 44 語中 14 語で候補を出せなかった。
        def test_picks_by_occurrence_when_no_heading_matches
          chapters = [
            write_chapter('10-intro', "# はじめに\n\nノンブルを使います。\n"),
            write_chapter('40-layout', "# レイアウト\n\nノンブルとページ。ノンブルは番号。ノンブルの位置。\n")
          ]

          assert_equal({ 'ノンブル' => '40-layout' }, suggest([term('ノンブル')], chapters))
        end

        # 見出しは重い。1 回の h1 は本文 3 回ぶんに相当する
        def test_headings_outweigh_plain_occurrences
          chapters = [
            write_chapter('10-intro', "# はじめに\n\nノンブルとノンブル。\n"),
            write_chapter('40-nombre', "# ノンブル\n\n本文。\n")
          ]

          assert_equal({ 'ノンブル' => '40-nombre' }, suggest([term('ノンブル')], chapters))
        end

        # --- phase: 出現が 1 回だけの語 ---

        # 索引に出るページ番号が 1 つしかない語を太字にしても、読者に伝わる
        # 情報が増えない（実測で該当は 1 語）。
        def test_no_candidate_for_a_term_that_appears_once
          chapters = [write_chapter('10-intro', "# はじめに\n\nノンブルの話。\n")]

          assert_empty suggest([term('ノンブル')], chapters)
        end

        # --- phase: 候補なし ---

        def test_no_candidate_when_nothing_matches
          chapters = [write_chapter('10-intro', "# はじめに\n\n本文だけです。\n")]

          assert_empty suggest([term('ノンブル')], chapters)
        end

        def test_empty_input_is_safe
          assert_empty suggest([], ['10-intro'])
          assert_empty suggest([term('索引')], [])
        end

        # --- phase: 辞書 pattern の解釈 ---

        # 照合は本文タグ付け（IndexMatchScanner）と同じ pattern で行う。
        # ここだけ緩めると、索引に載らない章を主要参照として勧めることになる。
        #
        # Ruby の \b は日本語を語構成文字として扱うので、`/\bRuby\b/` は
        # 「Rubyの基礎」に**当たらない**。本文タグ付けもそうなので揃えている。
        def test_uses_the_dictionary_pattern
          chapters = [
            write_chapter('10-intro', "# Rubyの基礎\n\nRubyの本文。\n"),
            write_chapter('20-ruby', "# Ruby とは\n\nRuby の本文。\n")
          ]

          assert_equal({ 'Ruby' => '20-ruby' },
                       suggest([term('Ruby', pattern: '/\\bRuby\\b/')], chapters))
        end

        # 壊れた pattern で走査全体を止めない
        def test_broken_pattern_falls_back_to_literal_match
          chapters = [write_chapter('33-index', "# 索引\n\n索引の本文。\n")]

          assert_equal({ '索引' => '33-index' },
                       suggest([term('索引', pattern: '/[/')], chapters))
        end
      end
    end
  end
end
