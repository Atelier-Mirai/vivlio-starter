# frozen_string_literal: true

# ================================================================
# Test: build_pipeline_test.rb
# ================================================================
# テスト対象:
#   UnifiedBuildPipeline（lib/vivlio_starter/cli/build/pipeline.rb）
#
# 検証内容:
#   - フルビルドモード: 全ステップの実行順序（Step 1-12）
#   - 単章ビルドモード: 指定章のみの処理
#   - 各ステップへの引数渡し（keep オプション等）
#
# ビルドパイプライン概要:
#   Step  1-3:  準備（クリーン、画像最適化）
#   Step  4:    Markdown前処理（frontmatter付加、画像パス修正）
#   Step  5:    索引スキャン・索引ページ生成
#   Step  6:    Markdown→HTML変換
#   Step  7:    目次生成
#   Step  8:    全体PDF生成（前書き+目次+本文+付録+後書き+索引）
#   Step  9:    表紙・奥付PDF生成
#   Step 10:    PDF結合
#   Step 11:    アウトライン付与
#   Step 12:    リネーム・クリーンアップ
#
# テスト手法:
#   - 各ステップをスタブ化して呼び出し順を記録
#   - 引数の検証をラムダ内で実行
# ================================================================

require 'test_helper'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/build'
require 'vivlio_starter/cli/token_resolver'

module VivlioStarter
  module CLI
    # UnifiedBuildPipeline フルモードのユニットテスト
    class UnifiedBuildPipelineFullModeTest < Minitest::Test
      # フルビルドパイプラインが登録順にステップを実行することを確認
      def test_run_executes_each_step_in_order
        pipeline = build_full_pipeline
        order = []
        test_case = self

        # 各ステップをスタブ化し、呼び出し順と渡される引数を確認する
        # entries は空配列（フルビルドモードではカタログから読み込む）
        stubs = [
          [pipeline, :run_step0_clean, -> { order << 'step0' }],
          [pipeline, :run_step1_optimize_images, -> { order << 'step1' }],
          [Build::ImageOptimizer, :prepare_theme_images!, -> { order << 'step2' }],
          [Build::SectionBuilder, :preprocess_sections!, lambda { |entries|
            test_case.assert_equal [], entries
            order << 'step3'
          }],
          [pipeline, :run_step4_index_processing, -> { order << 'step4' }],
          [Build::SectionBuilder, :convert_sections_html!, lambda { |entries|
            test_case.assert_equal [], entries
            order << 'step5'
          }],
          [Build::PartTitleGenerator, :generate_all!, -> { order << 'step5b' }],
          [Build::TocGenerator, :generate_toc_and_pdf!, lambda { |dir, entries|
            test_case.assert_equal '.', dir
            test_case.assert_equal [], entries
            order << 'step6'
          }],
          [Build::PdfBuilder, :build_overall_pdf_from_dir!, lambda { |dir, entries|
            test_case.assert_equal '.', dir
            test_case.assert_equal [], entries
            order << 'step7'
          }],
          [Build::BacklinkDedupOrchestrator, :run!, lambda { |entries|
            test_case.assert_equal [], entries
            order << 'step8'
          }],
          [pipeline, :run_step9_front_pages_and_tail, -> { order << 'step9' }],
          [Build::PdfMerger, :merge_all_pdfs!, lambda { |entries|
            test_case.assert_equal [], entries
            order << 'step10'
          }],
          [Build::PdfMerger, :add_outline_to_output_pdf!, lambda { |entries|
            test_case.assert_equal [], entries
            order << 'step11'
          }],
          [pipeline, :run_step12_rename_and_clean, -> { order << 'step12' }]
        ]

        with_stubs(stubs) do
          pipeline.run
        end

        # 期待する実行順を明示（Step 0, 1, 2, 3, 4, 5, 5b, 6, 7, 8, 9, 10, 11, 12）
        expected_order = %w[step0 step1 step2 step3 step4 step5 step5b step6 step7 step8 step9 step10 step11 step12]
        assert_equal expected_order, order
      end

      def test_full_mode_step_labels
        pipeline = build_full_pipeline
        stub_all_steps(pipeline)

        with_build_stubs { pipeline.run }

        expected_labels = [
          'Step  0 (clean)',
          'Step  1 (optimize images)',
          'Step  2 (prepare theme images)',
          'Step  3 (preprocess sections)',
          'Step  4 (index scan and build)',
          'Step  5 (convert sections html)',
          'Step 5b (generate part title pages)',
          'Step  6 (generate toc and pdf)',
          'Step  7 (build overall pdf)',
          'Step  8 (backlink dedup)',
          'Step  9 (build front pages and tail)',
          'Step 10 (merge all pdfs)',
          'Step 11 (apply outline to output pdf)',
          'Step 12 (compress, rename and final clean)'
        ]
        labels = pipeline.timings.map(&:first)
        # Step 5c (techbook post-process) が追加されている場合も許容する
        if labels.include?('Step 5c (techbook post-process)')
          expected_labels.insert(expected_labels.index('Step  6 (generate toc and pdf)'), 'Step 5c (techbook post-process)')
        end
        assert_equal expected_labels, labels
      end

      def test_timings_are_numeric
        pipeline = build_full_pipeline
        stub_all_steps(pipeline)

        with_build_stubs { pipeline.run }

        pipeline.timings.each do |(_, duration)|
          assert duration.is_a?(Numeric), 'each timing entry should record elapsed seconds'
        end
      end

      def test_mode_is_full
        pipeline = build_full_pipeline
        assert_equal :full, pipeline.mode
      end

      private

      def build_full_pipeline
        options = default_options
        command = Struct.new(:options).new(options)
        # book.yml の targets 設定に依存しないよう pdf 専用モードを強制する
        klass = Class.new(BuildCommands::UnifiedBuildPipeline) do
          define_method(:pdf_target?)       { true }
          define_method(:epub_target?)      { false }
          define_method(:kindle_target?)    { false }
          define_method(:print_pdf_target?) { false }
        end
        klass.new(command, entries: [], mode: :full)
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
        # インスタンスメソッドのスタブ
        pipeline.define_singleton_method(:run_step0_clean) {}
        pipeline.define_singleton_method(:run_step1_optimize_images) {}
        pipeline.define_singleton_method(:run_step4_index_processing) {}
        pipeline.define_singleton_method(:run_step9_front_pages_and_tail) {}
        pipeline.define_singleton_method(:run_step12_rename_and_clean) {}
      end

      def with_build_stubs
        Build::ImageOptimizer.stub :prepare_theme_images!, -> {} do
          Build::SectionBuilder.stub :preprocess_sections!, ->(_) {} do
            Build::SectionBuilder.stub :convert_sections_html!, ->(_) {} do
              Build::PartTitleGenerator.stub :generate_all!, -> {} do
                Build::TocGenerator.stub :generate_toc_and_pdf!, ->(_, _) {} do
                  Build::PdfBuilder.stub :build_overall_pdf_from_dir!, ->(_, _) {} do
                    Build::BacklinkDedupOrchestrator.stub :run!, ->(_) {} do
                      Build::PdfMerger.stub :merge_all_pdfs!, ->(_) {} do
                        Build::PdfMerger.stub :add_outline_to_output_pdf!, ->(_) {} do
                          yield
                        end
                      end
                    end
                  end
                end
              end
            end
          end
        end
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
          [pipeline, :run_step0_clean, -> { order << 'step0' }],
          [pipeline, :run_step1_optimize_images, -> { order << 'step1' }],
          [Build::ImageOptimizer, :prepare_theme_images!, -> { order << 'step2' }],
          [pipeline, :build_target_sections_html, -> { order << 'step3' }],
          [pipeline, :generate_entries_and_pdf, -> { order << 'step4' }],
          [pipeline, :rename_single_mode_pdf, -> { order << 'step5' }],
          [pipeline, :run_final_clean, -> { order << 'stepF' }]
        ]

        with_stubs(stubs) do
          pipeline.run
        end

        expected_order = %w[step0 step1 step2 step3 step4 step5 stepF]
        assert_equal expected_order, order
      end

      def test_single_mode_step_labels
        pipeline = build_single_pipeline(targets: ['45-first-html'])
        stub_all_single_mode_steps(pipeline)

        Build::ImageOptimizer.stub :prepare_theme_images!, -> {} do
          pipeline.run
        end

        expected_labels = [
          'Step  0 (clean)',
          'Step  1 (optimize images)',
          'Step  2 (prepare theme images)',
          'Step  3 (build sections html)',
          'Step  4 (entries.js + pdf)',
          'Step  5 (rename output pdfs)',
          'Step F (final clean)'
        ]
        labels = pipeline.timings.map(&:first)
        assert_equal expected_labels, labels
      end

      def test_mode_is_single
        pipeline = build_single_pipeline(targets: ['45-first-html'])
        assert_equal :single, pipeline.mode
      end

      def test_entries_are_stored
        targets = ['45-first-html', '46-first-css']
        pipeline = build_single_pipeline(targets: targets)
        # entries の basename が正しく格納されていることを確認
        assert_equal targets, pipeline.entries.map(&:basename)
      end

      private

      def build_single_pipeline(targets:)
        options = default_options
        command = Struct.new(:options).new(options)
        entries = targets.map { |bn| make_entry(bn) }
        klass = Class.new(BuildCommands::UnifiedBuildPipeline) do
          define_method(:pdf_target?)       { true }
          define_method(:epub_target?)      { false }
          define_method(:kindle_target?)    { false }
          define_method(:print_pdf_target?) { false }
        end
        klass.new(command, entries: entries, mode: :single)
      end

      def make_entry(basename)
        name = basename.sub(/\.md\z/, '')
        num = name[/\A(\d+)-/, 1]&.to_i
        slug = name.sub(/\A\d+-/, '')
        TokenResolver::Entry.new(
          number: num,
          slug: slug,
          kind: :chapter,
          label: name,
          path: "contents/#{name}.md",
          exists: true,
          in_catalog: true,
          valid: true
        )
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
        pipeline.define_singleton_method(:run_step0_clean) {}
        pipeline.define_singleton_method(:run_step1_optimize_images) {}
        pipeline.define_singleton_method(:build_target_sections_html) {}
        pipeline.define_singleton_method(:generate_entries_and_pdf) {}
        pipeline.define_singleton_method(:rename_single_mode_pdf) {}
        # Step F もスタブしないと実際の CleanCommands.execute_clean が走ってしまう
        pipeline.define_singleton_method(:run_final_clean) {}
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
        entries = targets.map { |bn| make_entry(bn) }
        klass = Class.new(BuildCommands::UnifiedBuildPipeline) do
          define_method(:pdf_target?)       { true }
          define_method(:epub_target?)      { false }
          define_method(:kindle_target?)    { false }
          define_method(:print_pdf_target?) { false }
        end
        klass.new(command, entries: entries, mode: :single)
      end

      def make_entry(basename)
        name = basename.sub(/\.md\z/, '')
        num = name[/\A(\d+)-/, 1]&.to_i
        slug = name.sub(/\A\d+-/, '')
        TokenResolver::Entry.new(
          number: num,
          slug: slug,
          kind: :chapter,
          label: name,
          path: "contents/#{name}.md",
          exists: true,
          in_catalog: true,
          valid: true
        )
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
        # book.yml の targets 設定に依存しないよう pdf 専用モードを強制する
        klass = Class.new(BuildCommands::UnifiedBuildPipeline) do
          define_method(:pdf_target?)       { true }
          define_method(:epub_target?)      { false }
          define_method(:kindle_target?)    { false }
          define_method(:print_pdf_target?) { false }
        end
        klass.new(command, entries: [], mode: mode)
      end

      def stub_all_steps(pipeline)
        pipeline.define_singleton_method(:run_step0_clean) {}
        pipeline.define_singleton_method(:run_step1_optimize_images) {}
        pipeline.define_singleton_method(:run_step4_index_processing) {}
        pipeline.define_singleton_method(:run_step9_front_pages_and_tail) {}
        pipeline.define_singleton_method(:run_step12_rename_and_clean) {}
      end
    end

    # ================================================================
    # Timing Measurement Tests
    # ================================================================
    class BuildTimingMeasurementTest < Minitest::Test
      def test_timings_are_recorded_for_each_step
        pipeline = build_full_pipeline
        stub_pipeline_steps(pipeline)

        with_build_stubs { pipeline.run }

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
        stub_single_pipeline_steps(pipeline)

        Build::ImageOptimizer.stub :prepare_theme_images!, -> {} do
          pipeline.run
        end

        # single mode は 7 ステップ（Step 0-5 + Step F）
        assert_equal 7, pipeline.timings.length, 'single mode は 7 ステップを記録するべき'
      end

      def test_full_mode_timings_has_12_entries
        pipeline = build_full_pipeline
        stub_pipeline_steps(pipeline)

        with_build_stubs { pipeline.run }

        # full mode（pdf専用）は 15 ステップ（Step 0, 1, 2, 3, 4, 5, 5b, 5c, 6, 7, 8, 9, 10, 11, 12）
        assert_equal 15, pipeline.timings.length, 'full mode は 15 ステップを記録するべき'
      end

      private

      def build_full_pipeline
        options = { clean: true, resize: true, compress: true, high: false, low: false }
        command = Struct.new(:options).new(options)
        # book.yml の targets 設定に依存しないよう pdf 専用モードを強制する
        klass = Class.new(BuildCommands::UnifiedBuildPipeline) do
          define_method(:pdf_target?)       { true }
          define_method(:epub_target?)      { false }
          define_method(:kindle_target?)    { false }
          define_method(:print_pdf_target?) { false }
        end
        klass.new(command, entries: [], mode: :full)
      end

      def build_single_pipeline(targets)
        options = { clean: true, resize: true, compress: true, high: false, low: false }
        command = Struct.new(:options).new(options)
        entries = targets.map { |bn| make_entry(bn) }
        klass = Class.new(BuildCommands::UnifiedBuildPipeline) do
          define_method(:pdf_target?)       { true }
          define_method(:epub_target?)      { false }
          define_method(:kindle_target?)    { false }
          define_method(:print_pdf_target?) { false }
        end
        klass.new(command, entries: entries, mode: :single)
      end

      def make_entry(basename)
        name = basename.sub(/\.md\z/, '')
        num = name[/\A(\d+)-/, 1]&.to_i
        slug = name.sub(/\A\d+-/, '')
        TokenResolver::Entry.new(
          number: num,
          slug: slug,
          kind: :chapter,
          label: name,
          path: "contents/#{name}.md",
          exists: true,
          in_catalog: true,
          valid: true
        )
      end

      def stub_pipeline_steps(pipeline)
        pipeline.define_singleton_method(:run_step0_clean) {}
        pipeline.define_singleton_method(:run_step1_optimize_images) {}
        pipeline.define_singleton_method(:run_step4_index_processing) {}
        pipeline.define_singleton_method(:run_step9_front_pages_and_tail) {}
        pipeline.define_singleton_method(:run_step12_rename_and_clean) {}
      end

      def stub_single_pipeline_steps(pipeline)
        pipeline.define_singleton_method(:run_step0_clean) {}
        pipeline.define_singleton_method(:run_step1_optimize_images) {}
        pipeline.define_singleton_method(:build_target_sections_html) {}
        pipeline.define_singleton_method(:generate_entries_and_pdf) {}
        pipeline.define_singleton_method(:rename_single_mode_pdf) {}
        # Step F もスタブしないと実際の CleanCommands.execute_clean が走ってしまう
        pipeline.define_singleton_method(:run_final_clean) {}
      end

      def with_build_stubs
        Build::ImageOptimizer.stub :prepare_theme_images!, -> {} do
          Build::SectionBuilder.stub :preprocess_sections!, ->(_) {} do
            Build::SectionBuilder.stub :convert_sections_html!, ->(_) {} do
              Build::PartTitleGenerator.stub :generate_all!, -> {} do
                Build::TocGenerator.stub :generate_toc_and_pdf!, ->(_, _) {} do
                  Build::PdfBuilder.stub :build_overall_pdf_from_dir!, ->(_, _) {} do
                    Build::BacklinkDedupOrchestrator.stub :run!, ->(_) {} do
                      Build::PdfMerger.stub :merge_all_pdfs!, ->(_) {} do
                        Build::PdfMerger.stub :add_outline_to_output_pdf!, ->(_) {} do
                          yield
                        end
                      end
                    end
                  end
                end
              end
            end
          end
        end
      end
    end

    # catalog.yml に記載があるのに contents/ に原稿が存在しない場合の
    # フェイルファスト（ensure_entry_files_exist!）を検証する
    class UnifiedBuildPipelineMissingFileTest < Minitest::Test
      def test_should_abort_with_guidance_when_catalog_entry_file_is_missing
        existing = make_entry('11-install', exists: true)
        missing  = make_entry('89-bugfix-check', exists: false)
        pipeline = build_pipeline(entries: [existing, missing])

        out, = capture_io do
          error = assert_raises(SystemExit) { pipeline.run }
          assert_equal 1, error.status, '欠落検出時は exit 1 で終了するべき'
        end

        assert_includes out, 'contents/89-bugfix-check.md'
        assert_includes out, 'catalog.yml'
        assert_includes out, 'vs delete'
        refute_includes out, 'contents/11-install.md', '存在する章はエラー一覧に含めない'
      end

      def test_should_run_steps_when_all_entry_files_exist
        pipeline = build_pipeline(entries: [make_entry('11-install', exists: true)])

        capture_io { pipeline.run }

        assert_equal 1, pipeline.timings.length, '検証通過後はステップが実行されるべき'
      end

      private

      # 検証ロジックのみを対象にするため、ステップは1つのダミーに差し替える
      def build_pipeline(entries:)
        command = Struct.new(:options).new({ clean: false, resize: false })
        klass = Class.new(BuildCommands::UnifiedBuildPipeline) do
          define_method(:register_steps) { add_step('Step dummy', -> {}) }
        end
        klass.new(command, entries: entries, mode: :full)
      end

      def make_entry(basename, exists:)
        num = basename[/\A(\d+)-/, 1]
        TokenResolver::Entry.new(
          number: num,
          slug: basename.sub(/\A\d+-/, ''),
          kind: :chapter,
          label: basename,
          path: "contents/#{basename}.md",
          exists: exists,
          in_catalog: true,
          valid: true
        )
      end
    end
  end
end
