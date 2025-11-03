# frozen_string_literal: true

require 'test_helper'
require 'vivlio/starter/cli/common'
require 'vivlio/starter/cli/build_helpers'
require 'vivlio/starter/cli/build'

module Vivlio
  module Starter
    module CLI
      class FullBuildPipelineTest < Minitest::Test
        # フルビルドパイプラインが登録順にステップを実行し計時することを確認
        def test_run_executes_each_step_in_order
          options = {
            clean: true,
            resize: true,
            compress: true,
            high: false,
            low: false,
            force: false,
            :'no-cache' => false
          }
          command = Struct.new(:options).new(options)

          pipeline = BuildCommands::FullBuildPipeline.new(command, nil)
          order = []
          test_case = self

          # 各ステップをスタブ化し、呼び出し順と渡される引数を確認する
          stubs = [
            [pipeline, :run_step0_clean, -> { order << 'step0' }],
            [pipeline, :run_step1_optimize_images, -> { order << 'step1' }],
            [BuildHelpers, :prepare_theme_images!, -> { order << 'step2' }],
            [BuildHelpers, :build_sections_html!, lambda { |keep|
              test_case.assert_nil keep
              order << 'step5'
            }],
            [BuildHelpers, :generate_toc_and_pdf!, lambda { |dir, keep|
              test_case.assert_equal '.', dir
              test_case.assert_nil keep
              order << 'step6'
            }],
            [BuildHelpers, :build_overall_pdf_and_split_from_dir!, lambda { |dir, keep|
              test_case.assert_equal '.', dir
              test_case.assert_nil keep
              order << 'step7'
            }],
            [BuildHelpers, :build_frontmatter_pdf!, lambda { |keep|
              test_case.assert_nil keep
              order << 'step8'
            }],
            [pipeline, :run_step9_front_pages_and_tail, -> { order << 'step9' }],
            [BuildHelpers, :merge_all_pdfs_only!, lambda { |keep|
              test_case.assert_nil keep
              order << 'step10'
            }],
            [BuildHelpers, :add_outline_to_output_pdf!, lambda { |keep|
              test_case.assert_nil keep
              order << 'step11'
            }],
            [pipeline, :run_step12_compress_pdf, -> { order << 'step12' }],
            [pipeline, :run_step13_final_clean, -> { order << 'step13' }]
          ]

          with_stubs(stubs) do
            pipeline.run
          end

          # 期待する実行順を明示し、スタブ記録と照合する
          expected_order = %w[step0 step1 step2 step5 step6 step7 step8 step9 step10 step11 step12 step13]
          assert_equal expected_order, order

          expected_labels = [
            'Step 0 (clean)',
            'Step 1 (optimize images)',
            'Step 2 (prepare theme images)',
            'Step 5 (build sections html)',
            'Step 6 (generate toc and pdf)',
            'Step 7 (build overall pdf and split)',
            'Step 8 (build 02-03-front.pdf)',
            'Step 9 (build front pages and tail)',
            'Step 10 (merge all pdfs with outline)',
            'Step 11 (apply outline to output pdf)',
            'Step 12 (compress pdf)',
            'Step 13 (final clean)'
          ]
          labels = pipeline.timings.map(&:first)
          assert_equal expected_labels, labels
          pipeline.timings.each do |(_, duration)|
            assert duration.is_a?(Numeric), 'each timing entry should record elapsed seconds'
          end
        end

        private

        # 可変長のスタブセットをネスト適用するヘルパ
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
    end
  end
end
