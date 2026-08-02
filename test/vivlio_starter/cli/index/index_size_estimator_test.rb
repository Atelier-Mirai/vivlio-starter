# frozen_string_literal: true

require 'test_helper'
require 'vivlio_starter/cli/index/index_size_estimator'
require 'tmpdir'
require 'fileutils'

module VivlioStarter
  module CLI
    module IndexCommands
      class IndexSizeEstimatorTest < Minitest::Test
        # 本書の実測値。仕様書 §3.5 の数字をここで固定する。
        BOOK_CHARS = 129_006

        def setup
          @estimator = IndexSizeEstimator.new(BOOK_CHARS)
        end

        # --- phase: Heaps 則（§3.2） ---

        # 刊行書 10 冊の実測から得た値を固定する。ここが動いたら較正が変わったということ。
        def test_standard_preset_matches_measured_calibration
          est = @estimator.estimate('standard')

          assert_equal :standard, est.preset
          assert_equal 244, est.range.begin
          assert_equal 356, est.range.end
        end

        def test_all_presets_are_ordered_by_density
          light, standard, thorough = @estimator.all_presets.map { it.range }

          assert_operator light.end, :<, standard.begin
          assert_operator standard.end, :<, thorough.begin
        end

        # 索引語は分量に比例せず逓減する。3 倍の分量でも約 2.3 倍にしかならない。
        # 比例（3 倍）で計算していたら落ちる。
        def test_index_size_grows_sublinearly
          small = IndexSizeEstimator.new(50_000).estimate('standard').range.end
          large = IndexSizeEstimator.new(150_000).estimate('standard').range.end

          ratio = large.to_f / small

          assert_operator ratio, :>, 2.0, 'まったく増えないのは誤り'
          assert_operator ratio, :<, 2.5, '比例（3 倍）になってはならない'
        end

        # --- phase: target_terms の解釈（§3.4） ---

        def test_integer_setting_becomes_a_single_point
          est = @estimator.estimate(260)

          assert_nil est.preset
          assert_equal(260..260, est.range)
          assert_equal '260 語', est.to_s
        end

        def test_numeric_string_setting_is_accepted
          assert_equal(260..260, @estimator.estimate('260').range)
        end

        def test_nil_setting_falls_back_to_standard
          assert_equal :standard, @estimator.estimate(nil).preset
        end

        def test_unknown_setting_warns_and_falls_back
          est = nil
          out, err = capture_io { est = @estimator.estimate('reference') }

          assert_equal :standard, est.preset
          assert_match(/target_terms/, out + err, '解釈できない値は黙って落とさず知らせる')
          assert_match(/light|standard|thorough/, out + err, '指定できる値を示す（親切警告の流儀）')
        end

        # --- phase: 密度の併記（§6.2 の橋渡し） ---

        # 著者は「500 字に 1 語」という密度で考える。語数と密度の対応が狂うと
        # 操作盤の意味がなくなるので、両端の対応を固定する。
        def test_chars_per_term_range_bridges_to_author_mental_model
          r = @estimator.estimate(260).chars_per_term_range

          assert_equal 496, r.begin
          assert_equal 496, r.end
        end

        def test_chars_per_term_inverts_with_term_count
          light = @estimator.estimate('light').chars_per_term_range
          thorough = @estimator.estimate('thorough').chars_per_term_range

          assert_operator light.begin, :>, thorough.end,
                          '語数が多い（thorough）ほど 1 語あたりの字数は小さくなる'
        end

        # --- phase: 文字数の計数は Metrics::Analyzer に委ねる（§3.3） ---

        def test_prose_chars_excludes_code_blocks
          Dir.mktmpdir('estimator_test') do |dir|
            original = Dir.pwd
            begin
              Dir.chdir(dir)
              FileUtils.mkdir_p('contents')
              File.write('contents/11-a.md', <<~MD)
                # 見出し

                これは地の文です。

                ```ruby
                puts 'これはコードなので数えない'
                ```
              MD

              chars = IndexSizeEstimator.prose_chars_of(%w[11-a])

              assert_operator chars, :>=, 8, '地の文は数える'
              assert_operator chars, :<, 20, 'コードブロックと見出し記号は数えない'
            ensure
              Dir.chdir(original)
            end
          end
        end

        def test_prose_chars_is_zero_for_missing_chapter
          assert_equal 0, IndexSizeEstimator.prose_chars_of(%w[99-missing])
        end
      end
    end
  end
end
