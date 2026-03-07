# frozen_string_literal: true

require "test_helper"
require "vivlio/starter/cli/pdf/mecab_newline_cleaner"

module Vivlio
  module Starter
    module PDF
      class MecabNewlineCleanerTest < Minitest::Test
        def setup
          @cleaner = MecabNewlineCleaner.new
        end

        def test_clean_merges_split_section_heading_and_keeps_break_after_heading
          text = "1-2\nAI時代の技術者とは\n本文はここから始まります。"

          cleaned = @cleaner.clean(text)

          assert_equal("1-2AI時代の技術者とは\n本文はここから始まります。", cleaned)
        end

        def test_clean_preserves_existing_heading_break_without_invoking_mecab
          text = "1-3螺旋階段モデル\nこの節では螺旋階段モデルを説明します。"

          cleaned = @cleaner.clean(text)

          assert_equal("1-3螺旋階段モデル\nこの節では螺旋階段モデルを説明します。", cleaned)
        end

        def test_clean_inserts_blank_line_before_split_section_heading
          text = "前の文章です。\n1-2\nAI時代の技術者とは\n本文はここから始まります。"

          cleaned = @cleaner.clean(text)

          assert_equal("前の文章です。\n\n1-2AI時代の技術者とは\n本文はここから始まります。", cleaned)
        end

        def test_clean_inserts_blank_line_before_existing_section_heading
          text = "前の文章です。\n1-3螺旋階段モデル\n本文です。"

          cleaned = @cleaner.clean(text)

          assert_equal("前の文章です。\n\n1-3螺旋階段モデル\n本文です。", cleaned)
        end

        def test_clean_preserves_single_newlines_between_chapter_heading_title_and_prose
          text = "第1章\n\nプログラミング技術習得の三要素\n\nプログラミングを学ぶということは、単にコードの書き⽅を覚えることではありません。"

          cleaned = @cleaner.clean(text)

          assert_equal("第1章\nプログラミング技術習得の三要素\nプログラミングを学ぶということは、単にコードの書き⽅を覚えることではありません。", cleaned)
        end

        def test_clean_keeps_chapter_heading_and_title_on_separate_lines_with_single_newline
          text = "第1章\nプログラミング技術習得の三要素\nプログラミングを学ぶということは、単にコードの書き⽅を覚えることではありません。"

          cleaned = @cleaner.clean(text)

          assert_equal("第1章プログラミング技術習得の三要素\nプログラミングを学ぶということは、単にコードの書き⽅を覚えることではありません。", cleaned)
        end

        def test_clean_preserves_newline_between_chapter_title_and_multiline_prose_block
          text = "第1章\n\nプログラミング技術習得の三要素\n\nプログラミングを学ぶということは、単にコ\nードの書き⽅を覚えることではありません。"

          cleaned = @cleaner.clean(text)

          assert_equal("第1章\nプログラミング技術習得の三要素\nプログラミングを学ぶということは、単にコードの書き⽅を覚えることではありません。", cleaned)
        end

        def test_clean_merges_midword_break_for_katakana_word
          text = "この章ではコー\nドの読み方を説明します。"

          cleaned = @cleaner.clean(text)

          assert_equal("この章ではコードの読み方を説明します。", cleaned)
        end

        def test_clean_merges_midword_break_for_hiragana_and_kanji
          text = "吾輩は猫であ\nる。名前はまだ無い。"

          cleaned = @cleaner.clean(text)

          assert_equal("吾輩は猫である。名前はまだ無い。", cleaned)
        end
      end
    end
  end
end
