# frozen_string_literal: true

require 'test_helper'
require 'vivlio/starter/cli/common'
require 'vivlio/starter/cli/build'

module Vivlio
  module Starter
    module CLI
      # ================================================================
      # UnifiedBuildPipeline Full Mode Tests
      # ================================================================
      class UnifiedBuildPipelineFullModeTest < Minitest::Test
        # フルビルドパイプラインが登録順にステップを実行し計時することを確認
        def test_run_executes_each_step_in_order
          pipeline = build_full_pipeline(keep: nil)
          order = []
          test_case = self

          # 各ステップをスタブ化し、呼び出し順と渡される引数を確認する
          stubs = [
            [pipeline, :run_step1_clean, -> { order << 'step1' }],
            [pipeline, :run_step2_optimize_images, -> { order << 'step2' }],
            [Build, :prepare_theme_images!, -> { order << 'step3' }],
            [Build, :build_sections_html!, lambda { |keep|
              test_case.assert_nil keep
              order << 'step4'
            }],
            [Build, :generate_toc_and_pdf!, lambda { |dir, keep|
              test_case.assert_equal '.', dir
              test_case.assert_nil keep
              order << 'step6'
            }],
            [Build, :build_overall_pdf_and_split_from_dir!, lambda { |dir, keep|
              test_case.assert_equal '.', dir
              test_case.assert_nil keep
              order << 'step7'
            }],
            [Build, :build_frontmatter_pdf!, lambda { |keep|
              test_case.assert_nil keep
              order << 'step8'
            }],
            [pipeline, :run_step9_front_pages_and_tail, -> { order << 'step9' }],
            [Build, :merge_all_pdfs_only!, lambda { |keep|
              test_case.assert_nil keep
              order << 'step10'
            }],
            [Build, :add_outline_to_output_pdf!, lambda { |keep|
              test_case.assert_nil keep
              order << 'step11'
            }],
            [pipeline, :run_step12_compress_pdf, -> { order << 'step12' }],
            [Build, :rename_output_pdfs!, -> { order << 'step13' }],
            [pipeline, :run_step14_final_clean, -> { order << 'step14' }]
          ]

          with_stubs(stubs) do
            pipeline.run
          end

          # 期待する実行順を明示（Step 5 は full mode ではスキップ）
          expected_order = %w[step1 step2 step3 step4 step6 step7 step8 step9 step10 step11 step12 step13 step14]
          assert_equal expected_order, order
        end

        def test_full_mode_step_labels
          pipeline = build_full_pipeline(keep: nil)
          stub_all_steps(pipeline)

          pipeline.run

          expected_labels = [
            'Step  1 (clean)',
            'Step  2 (optimize images)',
            'Step  3 (prepare theme images)',
            'Step  4 (build sections html)',
            'Step  6 (generate toc and pdf)',
            'Step  7 (build overall pdf and split)',
            'Step  8 (build 02-03-front.pdf)',
            'Step  9 (build front pages and tail)',
            'Step 10 (merge all pdfs with outline)',
            'Step 11 (apply outline to output pdf)',
            'Step 12 (compress pdf)',
            'Step 13 (rename output pdfs)',
            'Step 14 (final clean)'
          ]
          labels = pipeline.timings.map(&:first)
          assert_equal expected_labels, labels
        end

        def test_timings_are_numeric
          pipeline = build_full_pipeline(keep: nil)
          stub_all_steps(pipeline)

          pipeline.run

          pipeline.timings.each do |(_, duration)|
            assert duration.is_a?(Numeric), 'each timing entry should record elapsed seconds'
          end
        end

        def test_mode_is_full
          pipeline = build_full_pipeline(keep: nil)
          assert_equal :full, pipeline.mode
        end

        private

        def build_full_pipeline(keep:)
          options = default_options
          command = Struct.new(:options).new(options)
          BuildCommands::UnifiedBuildPipeline.new(command, keep: keep, mode: :full)
        end

        def default_options
          {
            clean: true,
            resize: true,
            compress: true,
            high: false,
            low: false,
            force: false,
            :'no-cache' => false
          }
        end

        def stub_all_steps(pipeline)
          # スタブで実際の処理をスキップ
          pipeline.define_singleton_method(:run_step1_clean) {}
          pipeline.define_singleton_method(:run_step2_optimize_images) {}
          pipeline.define_singleton_method(:run_step9_front_pages_and_tail) {}
          pipeline.define_singleton_method(:run_step12_compress_pdf) {}
          pipeline.define_singleton_method(:run_step14_final_clean) {}
          Build::define_singleton_method(:prepare_theme_images!) {}
          Build::define_singleton_method(:build_sections_html!) { |_| }
          Build::define_singleton_method(:generate_toc_and_pdf!) { |_, _| }
          Build::define_singleton_method(:build_overall_pdf_and_split_from_dir!) { |_, _| }
          Build::define_singleton_method(:build_frontmatter_pdf!) { |_| }
          Build::define_singleton_method(:merge_all_pdfs_only!) { |_| }
          Build::define_singleton_method(:add_outline_to_output_pdf!) { |_| }
          Build::define_singleton_method(:rename_output_pdfs!) {}
        end

        def with_stubs(stubs, &block)
          if stubs.empty?
            yield
          else
            obj, method_name, impl = stubs.first
            obj.stub(method_name, impl) do
              with_stubs(stubs.drop(1), &block)
            end
          end
        end
      end

      # ================================================================
      # UnifiedBuildPipeline Single Mode Tests
      # ================================================================
      class UnifiedBuildPipelineSingleModeTest < Minitest::Test
        def test_single_mode_executes_correct_steps
          pipeline = build_single_pipeline(targets: ['45-first-html'])
          order = []

          stubs = [
            [pipeline, :run_step1_clean, -> { order << 'step1' }],
            [pipeline, :run_step2_optimize_images, -> { order << 'step2' }],
            [Build, :prepare_theme_images!, -> { order << 'step3' }],
            [pipeline, :build_target_sections_html, -> { order << 'step4' }],
            [pipeline, :generate_entries_and_pdf, -> { order << 'step5' }],
            [pipeline, :rename_single_mode_pdf, -> { order << 'step13' }]
          ]

          with_stubs(stubs) do
            pipeline.run
          end

          expected_order = %w[step1 step2 step3 step4 step5 step13]
          assert_equal expected_order, order
        end

        def test_single_mode_step_labels
          pipeline = build_single_pipeline(targets: ['45-first-html'])
          stub_all_single_mode_steps(pipeline)

          pipeline.run

          expected_labels = [
            'Step  1 (clean)',
            'Step  2 (optimize images)',
            'Step  3 (prepare theme images)',
            'Step  4 (build sections html)',
            'Step  5 (entries.js + pdf)',
            'Step 13 (rename output pdfs)'
          ]
          labels = pipeline.timings.map(&:first)
          assert_equal expected_labels, labels
        end

        def test_mode_is_single
          pipeline = build_single_pipeline(targets: ['45-first-html'])
          assert_equal :single, pipeline.mode
        end

        def test_targets_are_stored
          targets = ['45-first-html', '46-first-css']
          pipeline = build_single_pipeline(targets: targets)
          assert_equal targets, pipeline.targets
        end

        private

        def build_single_pipeline(targets:)
          options = default_options
          command = Struct.new(:options).new(options)
          BuildCommands::UnifiedBuildPipeline.new(command, targets: targets, mode: :single)
        end

        def default_options
          {
            clean: true,
            resize: true,
            compress: true,
            high: false,
            low: false,
            force: false,
            :'no-cache' => false
          }
        end

        def stub_all_single_mode_steps(pipeline)
          pipeline.define_singleton_method(:run_step1_clean) {}
          pipeline.define_singleton_method(:run_step2_optimize_images) {}
          pipeline.define_singleton_method(:build_target_sections_html) {}
          pipeline.define_singleton_method(:generate_entries_and_pdf) {}
          pipeline.define_singleton_method(:rename_single_mode_pdf) {}
          Build::define_singleton_method(:prepare_theme_images!) {}
        end

        def with_stubs(stubs, &block)
          if stubs.empty?
            yield
          else
            obj, method_name, impl = stubs.first
            obj.stub(method_name, impl) do
              with_stubs(stubs.drop(1), &block)
            end
          end
        end
      end

      # ================================================================
      # PDF Output Filename Tests
      # ================================================================
      class PdfOutputFilenameTest < Minitest::Test
        def test_single_chapter_pdf_name
          pipeline = build_single_pipeline(targets: ['54-operator'])

          # determine_single_mode_pdf_name は private なので send で呼び出し
          result = pipeline.send(:determine_single_mode_pdf_name)
          assert_equal '54-operator.pdf', result
        end

        def test_multiple_chapters_pdf_name_consecutive
          pipeline = build_single_pipeline(targets: ['54-operator', '55-condition', '56-loop'])

          result = pipeline.send(:determine_single_mode_pdf_name)
          assert_equal '54-56.pdf', result
        end

        def test_multiple_chapters_pdf_name_non_consecutive
          pipeline = build_single_pipeline(targets: ['45-first-html', '47-wave-studio-css'])

          result = pipeline.send(:determine_single_mode_pdf_name)
          assert_equal '45-47.pdf', result
        end

        def test_multiple_chapters_pdf_name_unordered
          # 入力順序に関係なく、番号でソートされて最初と最後の番号が使われる
          pipeline = build_single_pipeline(targets: ['56-loop', '54-operator', '55-condition'])

          result = pipeline.send(:determine_single_mode_pdf_name)
          assert_equal '54-56.pdf', result
        end

        def test_two_chapters_pdf_name
          pipeline = build_single_pipeline(targets: ['45-first-html', '46-first-css'])

          result = pipeline.send(:determine_single_mode_pdf_name)
          assert_equal '45-46.pdf', result
        end

        private

        def build_single_pipeline(targets:)
          options = { clean: true, resize: true, compress: true, high: false, low: false }
          command = Struct.new(:options).new(options)
          BuildCommands::UnifiedBuildPipeline.new(command, targets: targets, mode: :single)
        end
      end

      # ================================================================
      # Option Handling Tests
      # ================================================================
      class BuildOptionHandlingTest < Minitest::Test
        def test_no_clean_option_detected
          options = default_options.merge(clean: false)
          pipeline = build_pipeline(options, mode: :full)
          stub_all_steps(pipeline)

          # オプションが正しく設定されていることを確認
          assert_equal false, pipeline.send(:options)[:clean]
        end

        def test_no_resize_option_detected
          options = default_options.merge(resize: false)
          pipeline = build_pipeline(options, mode: :full)
          stub_all_steps(pipeline)

          assert_equal false, pipeline.send(:options)[:resize]
        end

        def test_high_preset_option_detected
          options = default_options.merge(high: true)
          pipeline = build_pipeline(options, mode: :full)
          stub_all_steps(pipeline)

          detected_preset = %i[high low].find { |k| pipeline.send(:options)[k] } || :medium
          assert_equal :high, detected_preset, '--high オプションでプリセットが high になるべき'
        end

        def test_low_preset_option_detected
          options = default_options.merge(low: true)
          pipeline = build_pipeline(options, mode: :full)
          stub_all_steps(pipeline)

          detected_preset = %i[high low].find { |k| pipeline.send(:options)[k] } || :medium
          assert_equal :low, detected_preset, '--low オプションでプリセットが low になるべき'
        end

        def test_default_preset_is_medium
          options = default_options
          pipeline = build_pipeline(options, mode: :full)
          stub_all_steps(pipeline)

          detected_preset = %i[high low].find { |k| pipeline.send(:options)[k] } || :medium
          assert_equal :medium, detected_preset, 'デフォルトプリセットは medium であるべき'
        end

        private

        def default_options
          {
            clean: true,
            resize: true,
            compress: true,
            high: false,
            low: false,
            force: false,
            :'no-cache' => false
          }
        end

        def build_pipeline(options, mode:)
          command = Struct.new(:options).new(options)
          BuildCommands::UnifiedBuildPipeline.new(command, keep: nil, mode: mode)
        end

        def stub_all_steps(pipeline)
          pipeline.define_singleton_method(:run_step1_clean) {}
          pipeline.define_singleton_method(:run_step2_optimize_images) {}
          pipeline.define_singleton_method(:run_step9_front_pages_and_tail) {}
          pipeline.define_singleton_method(:run_step12_compress_pdf) {}
          pipeline.define_singleton_method(:run_step14_final_clean) {}
          Build::define_singleton_method(:prepare_theme_images!) {}
          Build::define_singleton_method(:build_sections_html!) { |_| }
          Build::define_singleton_method(:generate_toc_and_pdf!) { |_, _| }
          Build::define_singleton_method(:build_overall_pdf_and_split_from_dir!) { |_, _| }
          Build::define_singleton_method(:build_frontmatter_pdf!) { |_| }
          Build::define_singleton_method(:merge_all_pdfs_only!) { |_| }
          Build::define_singleton_method(:add_outline_to_output_pdf!) { |_| }
          Build::define_singleton_method(:rename_output_pdfs!) {}
        end
      end

      # ================================================================
      # Timing Measurement Tests
      # ================================================================
      class BuildTimingMeasurementTest < Minitest::Test
        def test_timings_are_recorded_for_each_step
          pipeline = build_full_pipeline
          stub_all_steps(pipeline)

          pipeline.run

          # 各ステップの timing が記録されていることを確認
          assert pipeline.timings.length.positive?, 'タイミングが記録されるべき'
          pipeline.timings.each do |(label, duration)|
            assert label.is_a?(String), 'ラベルは文字列であるべき'
            assert duration.is_a?(Numeric), '時間は数値であるべき'
            assert duration >= 0, '時間は非負であるべき'
          end
        end

        def test_single_mode_timings_has_6_entries
          pipeline = build_single_pipeline(['45-test'])
          stub_single_mode_steps(pipeline)

          pipeline.run

          # single mode は 6 ステップ
          assert_equal 6, pipeline.timings.length, 'single mode は 6 ステップを記録するべき'
        end

        def test_full_mode_timings_has_13_entries
          pipeline = build_full_pipeline
          stub_all_steps(pipeline)

          pipeline.run

          # full mode は 13 ステップ（Step 5 を除く）
          assert_equal 13, pipeline.timings.length, 'full mode は 13 ステップを記録するべき'
        end

        private

        def build_full_pipeline
          options = { clean: true, resize: true, compress: true, high: false, low: false }
          command = Struct.new(:options).new(options)
          BuildCommands::UnifiedBuildPipeline.new(command, keep: nil, mode: :full)
        end

        def build_single_pipeline(targets)
          options = { clean: true, resize: true, compress: true, high: false, low: false }
          command = Struct.new(:options).new(options)
          BuildCommands::UnifiedBuildPipeline.new(command, targets: targets, mode: :single)
        end

        def stub_all_steps(pipeline)
          pipeline.define_singleton_method(:run_step1_clean) {}
          pipeline.define_singleton_method(:run_step2_optimize_images) {}
          pipeline.define_singleton_method(:run_step9_front_pages_and_tail) {}
          pipeline.define_singleton_method(:run_step12_compress_pdf) {}
          pipeline.define_singleton_method(:run_step14_final_clean) {}
          Build::define_singleton_method(:prepare_theme_images!) {}
          Build::define_singleton_method(:build_sections_html!) { |_| }
          Build::define_singleton_method(:generate_toc_and_pdf!) { |_, _| }
          Build::define_singleton_method(:build_overall_pdf_and_split_from_dir!) { |_, _| }
          Build::define_singleton_method(:build_frontmatter_pdf!) { |_| }
          Build::define_singleton_method(:merge_all_pdfs_only!) { |_| }
          Build::define_singleton_method(:add_outline_to_output_pdf!) { |_| }
          Build::define_singleton_method(:rename_output_pdfs!) {}
        end

        def stub_single_mode_steps(pipeline)
          pipeline.define_singleton_method(:run_step1_clean) {}
          pipeline.define_singleton_method(:run_step2_optimize_images) {}
          pipeline.define_singleton_method(:build_target_sections_html) {}
          pipeline.define_singleton_method(:generate_entries_and_pdf) {}
          pipeline.define_singleton_method(:rename_single_mode_pdf) {}
          Build::define_singleton_method(:prepare_theme_images!) {}
        end
      end
    end
  end
end
