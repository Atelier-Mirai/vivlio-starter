# frozen_string_literal: true

require 'test_helper'
require 'vivlio_starter/cli/index/term_spread'
require 'tmpdir'
require 'fileutils'

module VivlioStarter
  module CLI
    module IndexCommands
      class TermSpreadTest < Minitest::Test
        def setup
          @original_dir = Dir.pwd
          @temp_dir = Dir.mktmpdir('term_spread_test')
          Dir.chdir(@temp_dir)
          FileUtils.mkdir_p('contents')
        end

        def teardown
          Dir.chdir(@original_dir)
          FileUtils.rm_rf(@temp_dir)
        end

        def write_chapters(bodies)
          bodies.each_with_index do |body, i|
            File.write(format('contents/%02d-ch.md', i + 1), body)
          end
          bodies.each_index.map { format('%02d-ch', it + 1) }
        end

        def term(name, pattern: nil)
          pattern ? { 'term' => name, 'pattern' => pattern } : { 'term' => name }
        end

        # --- phase: 数え方（§3 R5.1） ---

        def test_counts_chapters_not_occurrences
          chapters = write_chapters(['対象語 対象語 対象語', '対象語', 'ほかの話'])

          spread = TermSpread.measure([term('対象語')], chapters)['対象語']

          assert_equal 2, spread.chapter_count, '1 章に何回出ても 1 章と数える'
          assert_equal 3, spread.total_chapters
        end

        # コード例の出現で広さを膨らませない。索引語はコードから拾わないので、
        # 「広く出ている」の判定にコードを数えるのは筋が通らない。
        def test_ignores_occurrences_inside_code_blocks
          chapters = write_chapters([
                                      "地の文に対象語があります。\n",
                                      "```ruby\nputs '対象語'\n```\n"
                                    ])

          spread = TermSpread.measure([term('対象語')], chapters)['対象語']

          assert_equal 1, spread.chapter_count, 'コードブロック内の出現は数えない'
        end

        # 辞書の pattern をそのまま使う（IndexMatchScanner と同じ綴りの約束）。
        # 語境界 \b が効くので Rubyist は別語として数えない。
        def test_uses_dictionary_pattern_when_present
          chapters = write_chapters(['Ruby の話', 'Rubyist の話'])

          spread = TermSpread.measure([term('Ruby', pattern: '/\bRuby\b/')], chapters)['Ruby']

          assert_equal 1, spread.chapter_count, 'pattern の語境界が効くこと'
        end

        # 辞書の \b は ASCII の語境界として読む（TermPattern）ので、「Rubyの話」の
        # ように日本語が続く形も数える。スキャナのタグ付けと同じ解釈でなければ、
        # 索引に載る出現が広さの計測から漏れて一般語の判定がずれる。
        def test_word_boundary_pattern_matches_adjacent_japanese
          chapters = write_chapters(['Rubyの話'])

          spread = TermSpread.measure([term('Ruby', pattern: '/\bRuby\b/')], chapters)['Ruby']

          assert_equal 1, spread.chapter_count
        end

        def test_falls_back_to_literal_match_on_broken_pattern
          chapters = write_chapters(['対象語です'])

          spread = TermSpread.measure([term('対象語', pattern: '/[/')], chapters)['対象語']

          assert_equal 1, spread.chapter_count, '壊れた pattern でも完全一致で数える'
        end

        # --- phase: 比率と下限（§3 R5.1） ---

        def test_ratio_is_chapter_count_over_total
          chapters = write_chapters(Array.new(4) { '対象語' } + ['別の話'])

          spread = TermSpread.measure([term('対象語')], chapters)['対象語']

          assert_in_delta 0.8, spread.ratio, 0.001
          assert_equal 80, spread.percentage
          assert_equal '4/5 章（80%）', spread.to_s
        end

        def test_common_terms_selects_widespread_terms
          chapters = write_chapters(Array.new(6) { '広い語' }.each_with_index.map { |b, i| i < 2 ? "#{b} 狭い語" : b })
          spreads = TermSpread.measure([term('広い語'), term('狭い語')], chapters)

          common = TermSpread.common_terms(spreads, ratio: 0.5)

          assert_equal ['広い語'], common.map(&:term)
        end

        # 5 章の本では 3 章に出るだけで比率 0.6 になる。誤検出は
        # 「機械が余計なことを言う」形で著者の信頼を削るので、判定しない。
        def test_does_not_judge_thin_books
          chapters = write_chapters(Array.new(5) { '対象語' })
          spreads = TermSpread.measure([term('対象語')], chapters)

          assert_empty TermSpread.common_terms(spreads, ratio: 0.5),
                       "全 #{TermSpread::MIN_TOTAL_CHAPTERS} 章未満の本では判定しない"
        end

        # 2 章に出て比率 1.0 でも「広い」とは言わない
        def test_requires_a_minimum_chapter_count
          bodies = Array.new(8) { '別の話' }
          bodies[0] = bodies[1] = '対象語'
          chapters = write_chapters(bodies)
          spreads = TermSpread.measure([term('対象語')], chapters)

          assert_empty TermSpread.common_terms(spreads, ratio: 0.1),
                       "出現章数 #{TermSpread::MIN_CHAPTER_COUNT} 未満は対象外"
        end

        def test_common_terms_sorted_by_breadth
          bodies = Array.new(8) { '' }
          bodies.each_index { |i| bodies[i] += '広い語 ' if i < 7 }
          bodies.each_index { |i| bodies[i] += 'やや広い語' if i < 5 }
          chapters = write_chapters(bodies)
          spreads = TermSpread.measure([term('広い語'), term('やや広い語')], chapters)

          common = TermSpread.common_terms(spreads, ratio: 0.5)

          assert_equal %w[広い語 やや広い語], common.map(&:term)
        end

        def test_measure_handles_missing_chapters
          spreads = TermSpread.measure([term('対象語')], %w[99-missing])

          assert_equal 0, spreads['対象語'].chapter_count
          assert_empty TermSpread.common_terms(spreads, ratio: 0.5)
        end
      end
    end
  end
end
