# frozen_string_literal: true

# ================================================================
# Test: build/pipeline_steps_test.rb
# ================================================================
# 目的（P2 回帰ゲート）:
#   UnifiedBuildPipeline が登録するステップ列を、出力ターゲットの全 16 組
#   （2^4 − 空 ＋既定）× mode(:full/:single/:preflight) について固定する。
#
#   ステップ列は「操作キー」= ラベルの `Step NN (...)` から括弧内の説明だけを
#   取り出したもので比較する。これにより「Step 13 (print pdf)」と
#   「Step 10 (print pdf)」が同一キー "print pdf" に正規化され、番号付き分岐実装
#   （現行）でも番号なし宣言的テーブル（P2-2 後）でも、同一のスナップショットで
#   操作の同一性を検証できる。期待値は pre-P2 の現行実装から採取して固定した。
# ================================================================

require 'test_helper'
require 'vivlio_starter/cli/build'
require 'vivlio_starter/cli/token_resolver'
require 'vivlio_starter/cli/create'
require 'vivlio_starter/cli/clean'

module VivlioStarter
  module CLI
    class PipelineStepsSnapshotTest < Minitest::Test
      # HTML 生成までの共通前処理（全ターゲットで不変）。
      PREFIX = [
        'clean', 'optimize images', 'prepare theme images', 'preprocess sections',
        'index scan and build', 'convert sections html', 'generate part title pages',
        'techbook post-process', 'generate toc html'
      ].freeze

      # toc 生成後のターゲット依存テール（pre-P2 実装から採取）。
      PDF_ONLY = (PREFIX + [
        'build overall pdf', 'backlink dedup', 'build front pages and tail',
        'merge all pdfs', 'apply outline to output pdf', 'compress, rename and final clean'
      ]).freeze

      PRINT_ONLY = (PREFIX + [
        'generate entries.js', 'backlink dedup', 'build front pages html', 'print pdf', 'final clean'
      ]).freeze

      PDF_PRINT = (PREFIX + [
        'build overall pdf', 'backlink dedup', 'build front pages and tail', 'merge all pdfs',
        'apply outline to output pdf', 'rename', 'print pdf', 'final clean'
      ]).freeze

      EPUB_ONLY = (PREFIX + ['build front pages html', 'generate epub', 'final clean']).freeze

      PDF_EPUB = (PREFIX + [
        'build overall pdf', 'snapshot pre-dedup html for epub', 'backlink dedup',
        'build front pages and tail', 'merge all pdfs', 'apply outline to output pdf',
        'rename', 'generate epub', 'final clean'
      ]).freeze

      PRINT_EPUB = (PREFIX + [
        'generate entries.js', 'snapshot pre-dedup html for epub', 'backlink dedup',
        'build front pages html', 'print pdf', 'generate epub', 'final clean'
      ]).freeze

      ALL = (PREFIX + [
        'build overall pdf', 'snapshot pre-dedup html for epub', 'backlink dedup',
        'build front pages and tail', 'merge all pdfs', 'apply outline to output pdf',
        'rename', 'print pdf', 'generate epub', 'final clean'
      ]).freeze

      # 全 16 組（空＝既定 pdf を含む）→ 期待する操作キー列。
      FULL_MODE_CASES = {
        %w[]                          => PDF_ONLY,
        %w[pdf]                       => PDF_ONLY,
        %w[print_pdf]                 => PRINT_ONLY,
        %w[pdf print_pdf]             => PDF_PRINT,
        %w[epub]                      => EPUB_ONLY,
        %w[pdf epub]                  => PDF_EPUB,
        %w[print_pdf epub]            => PRINT_EPUB,
        %w[pdf print_pdf epub]        => ALL,
        %w[kindle]                    => EPUB_ONLY,
        %w[pdf kindle]                => PDF_EPUB,
        %w[print_pdf kindle]          => PRINT_EPUB,
        %w[pdf print_pdf kindle]      => ALL,
        %w[epub kindle]               => EPUB_ONLY,
        %w[pdf epub kindle]           => PDF_EPUB,
        %w[print_pdf epub kindle]     => PRINT_EPUB,
        %w[pdf print_pdf epub kindle] => ALL
      }.freeze

      SINGLE_MODE = [
        'clean', 'optimize images', 'prepare theme images', 'build sections html',
        'entries.js + pdf', 'rename output pdfs', 'final clean'
      ].freeze

      PREFLIGHT_MODE = [
        'optimize images', 'prepare theme images', 'preprocess sections', 'index scan and build'
      ].freeze

      def test_full_mode_step_sequences_for_all_target_combos
        FULL_MODE_CASES.each do |targets_list, expected|
          pipeline = build_pipeline(mode: :full, targets: targets_from(targets_list))
          assert_equal expected, op_keys(pipeline),
                       "targets=#{targets_list.inspect} のステップ列が想定と一致しません"
        end
      end

      def test_single_mode_step_sequence
        pipeline = build_pipeline(mode: :single, targets: targets_from(%w[pdf]))
        assert_equal SINGLE_MODE, op_keys(pipeline)
      end

      def test_preflight_mode_step_sequence
        pipeline = build_pipeline(mode: :preflight, targets: targets_from(%w[pdf]))
        assert_equal PREFLIGHT_MODE, op_keys(pipeline)
      end

      private

      # ステップラベルを操作キー（番号を除いた括弧内説明、または番号なしラベルそのもの）へ正規化する。
      def op_keys(pipeline)
        pipeline.instance_variable_get(:@steps).map do |step|
          m = step.label.match(/\AStep\s+\S+\s+\((.+)\)\z/)
          m ? m[1] : step.label
        end
      end

      def targets_from(list)
        Build::Targets.new(
          pdf: list.empty? ? true : list.include?('pdf'),
          print_pdf: list.include?('print_pdf'),
          epub: list.include?('epub'),
          kindle: list.include?('kindle')
        )
      end

      def build_pipeline(mode:, targets:)
        options = { clean: true, resize: true, compress: true, high: false, low: false }
        command = Struct.new(:options).new(options)
        BuildCommands::UnifiedBuildPipeline.new(command, entries: [], mode:, targets:)
      end
    end
  end
end
