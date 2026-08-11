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
      # 前付・奥付の HTML は本文レンダへ相乗りさせるため、techbook 後処理より前に作る
      # （front-back-matter-single-render-spec.md §2.1）。
      # カバー資産は PDF 枝と EPUB 枝が同じファイルを読むため、分岐前に 1 回だけ作る
      # （build-target-parallelization-spec.md §3.2）。
      PREFIX = [
        'clean', 'optimize images', 'prepare theme images', 'prepare cover assets',
        'preprocess sections', 'index scan and build', 'convert sections html',
        'generate part title pages', 'generate front and back matter html',
        'techbook post-process', 'generate toc html'
      ].freeze

      # toc 生成後のターゲット依存テール（pre-P2 実装から採取）。
      PDF_ONLY = (PREFIX + [
        'build overall pdf', 'backlink dedup', 'build front and back matter',
        'merge all pdfs', 'apply outline to output pdf', 'compress, rename and final clean'
      ]).freeze

      # 入稿用のみ・導出フロー（既定）。導出のソースとして閲覧用の中間 PDF を作るため、
      # print_pdf 単独でも 'build overall pdf' / 'build front and back matter' が入る。
      # 最終成果物（merge 以降）は t.pdf 次第なので閲覧用 output.pdf は生まれない。
      PRINT_ONLY = (PREFIX + [
        'build overall pdf', 'backlink dedup', 'build front and back matter', 'print pdf', 'final clean'
      ]).freeze

      # 入稿用のみ・従来フロー（output.print_pdf.full_bleed: true）。
      # 本文を個別レンダするため閲覧用 PDF は不要で、entries/config だけを用意する。
      # 前付・奥付の HTML は共通前処理で作り済みなので、ここに専用ステップは無い。
      PRINT_ONLY_FULL_BLEED = (PREFIX + [
        'generate entries.js', 'backlink dedup', 'print pdf', 'final clean'
      ]).freeze

      PDF_PRINT = (PREFIX + [
        'build overall pdf', 'backlink dedup', 'build front and back matter', 'merge all pdfs',
        'apply outline to output pdf', 'compress and rename', 'print pdf', 'final clean'
      ]).freeze

      EPUB_ONLY = (PREFIX + ['generate epub', 'final clean']).freeze

      # P4 段階 3: dedup がワークスペース pdf/ に閉じたため、EPUB 隔離用の
      # 'snapshot pre-dedup html for epub' ステップは撤去された（P4 §3.4-3）。
      PDF_EPUB = (PREFIX + [
        'build overall pdf', 'backlink dedup',
        'build front and back matter', 'merge all pdfs', 'apply outline to output pdf',
        'compress and rename', 'generate epub', 'final clean'
      ]).freeze

      PRINT_EPUB = (PREFIX + [
        'build overall pdf', 'backlink dedup',
        'build front and back matter', 'print pdf', 'generate epub', 'final clean'
      ]).freeze

      ALL = (PREFIX + [
        'build overall pdf', 'backlink dedup',
        'build front and back matter', 'merge all pdfs', 'apply outline to output pdf',
        'compress and rename', 'print pdf', 'generate epub', 'final clean'
      ]).freeze

      # Kindle 用の回転テーブル画像は本文 PDF のページから切り出すため、
      # 「Kindle を作る」かつ「閲覧用 PDF を組む」構成でだけ抽出ステップが 1 つ増える
      # （kindle-rotate-table-image-spec.md §7）。切り出し元は dedup 前のレンダなので、
      # 位置は必ず 'build overall pdf' の直後。
      def self.with_rotate_extraction(steps)
        steps.dup.insert(steps.index('build overall pdf') + 1, 'extract rotate table images').freeze
      end

      PDF_KINDLE   = with_rotate_extraction(PDF_EPUB)
      PRINT_KINDLE = with_rotate_extraction(PRINT_EPUB)
      ALL_KINDLE   = with_rotate_extraction(ALL)

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
        %w[pdf kindle]                => PDF_KINDLE,
        %w[print_pdf kindle]          => PRINT_KINDLE,
        %w[pdf print_pdf kindle]      => ALL_KINDLE,
        %w[epub kindle]               => EPUB_ONLY,
        %w[pdf epub kindle]           => PDF_KINDLE,
        %w[print_pdf epub kindle]     => PRINT_KINDLE,
        %w[pdf print_pdf epub kindle] => ALL_KINDLE
      }.freeze

      # 単章モードは full mode の表から `unit: :chapter` を導出して作る
      # （build-mode-parity-spec.md §2.2）。以前は 'build sections html' が
      # preprocess / index / convert を独自に束ねており、全章側と別実装だった——
      # それが「単章では ○○ だったが全章では ×× だった」の温床になっていた。
      # 'techbook post-process' は章単位だが SINGLE_MODE_SKIP で意図的に外している。
      SINGLE_MODE = [
        'clean', 'optimize images', 'prepare theme images',
        'preprocess sections', 'index scan and build', 'convert sections html',
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

      # full_bleed: true（本文にフチなし要素がある本）では導出できないため、
      # 入稿用は個別レンダリングし、閲覧用の中間 PDF を作らない従来の経路に戻る。
      def test_full_bleed_falls_back_to_legacy_print_rendering
        Common.stub :print_pdf_full_bleed?, true do
          pipeline = build_pipeline(mode: :full, targets: targets_from(%w[print_pdf]))
          assert_equal PRINT_ONLY_FULL_BLEED, op_keys(pipeline)
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

      # --- phase: 進行表示の語彙 ---

      # preflight は原稿を検査するだけで何も組まない。「ビルド中」と出ると
      # 出力物ができると思われ、実行を止める判断を誤らせる。
      def test_preflight_does_not_claim_to_be_building
        pipeline = build_pipeline(mode: :preflight, targets: targets_from(%w[pdf]))
        label = pipeline.send(:spinner_label, steps(pipeline).first, 1)

        assert_includes label, '点検中'
        refute_includes label, 'ビルド'
      end

      def test_build_modes_still_say_building
        %i[full single].each do |mode|
          pipeline = build_pipeline(mode:, targets: targets_from(%w[pdf]))
          label = pipeline.send(:spinner_label, steps(pipeline).first, 1)

          assert_includes label, 'ビルド中', "#{mode} は従来どおり"
        end
      end

      # 「あと何段階か」が読めることは進行表示の主目的
      def test_label_carries_the_position
        pipeline = build_pipeline(mode: :preflight, targets: targets_from(%w[pdf]))
        total = steps(pipeline).size

        assert_includes pipeline.send(:spinner_label, steps(pipeline).first, 2), "(2/#{total})"
      end

      # 相の割り当て（build-target-parallelization-spec.md §2）。
      #
      # **`:pdf` 相に `html/` へ書くステップを入れてはならない**——EPUB 枝は
      # `html/` のクリーンな原本を読んで消費者 dir へステージするため、書き換えが
      # 走ると読んでいる最中に足元が変わる。前付・奥付の HTML 生成を `:shared` へ
      # 前倒ししてこの依存は消えており（§3.3）、本スナップショットがその状態を固定する。
      PHASE_OF = {
        'clean' => :shared, 'optimize images' => :shared, 'prepare theme images' => :shared,
        'prepare cover assets' => :shared, 'preprocess sections' => :shared,
        'index scan and build' => :shared, 'convert sections html' => :shared,
        'generate part title pages' => :shared, 'generate front and back matter html' => :shared,
        'techbook post-process' => :shared, 'generate toc html' => :shared,
        'build overall pdf' => :pdf, 'extract rotate table images' => :pdf,
        'generate entries.js' => :pdf, 'backlink dedup' => :pdf,
        'build front and back matter' => :pdf, 'merge all pdfs' => :pdf,
        'apply outline to output pdf' => :pdf, 'compress, rename and final clean' => :pdf,
        'compress and rename' => :pdf, 'print pdf' => :pdf,
        'generate epub' => :epub,
        'final clean' => :join
      }.freeze

      # 全ターゲット構成で、登録されたステップが想定どおりの相を名乗る。
      def test_every_full_mode_step_declares_the_expected_phase
        FULL_MODE_CASES.each_key do |targets_list|
          pipeline = build_pipeline(mode: :full, targets: targets_from(targets_list))
          steps(pipeline).each do |step|
            assert_includes BuildCommands::UnifiedBuildPipeline::PHASE_ORDER, step.phase,
                            "#{step.label} が未知の相 #{step.phase.inspect} を名乗っています"
            assert_equal PHASE_OF.fetch(step.label), step.phase,
                         "targets=#{targets_list.inspect} の #{step.label} の相が想定と違います"
          end
        end
      end

      # 相の順に並べ替えても、ステップの実行順は表の並びから動かない
      # （＝逐次実行の等価性。並列化はこの上に載せる）。
      def test_phase_order_preserves_the_sequential_execution_order
        pipeline = build_pipeline(mode: :full, targets: targets_from(%w[pdf print_pdf epub kindle]))
        by_phase = BuildCommands::UnifiedBuildPipeline::PHASE_ORDER
                   .flat_map { |phase| steps(pipeline).select { |s| s.phase == phase } }

        assert_equal steps(pipeline).map(&:label), by_phase.map(&:label)
      end

      # :single / :preflight は相を持たない（すべて :shared 扱い）。
      def test_single_and_preflight_modes_stay_in_the_shared_phase
        %i[single preflight].each do |mode|
          pipeline = build_pipeline(mode:, targets: targets_from(%w[pdf]))
          assert_equal [:shared], steps(pipeline).map(&:phase).uniq,
                       "#{mode} モードのステップは全て :shared であるべき"
        end
      end

      # カバーを綴じも埋めもしない構成では、生成ステップごと落ちる（§3.2）。
      # 共通前段へ引き上げたぶん「誰も読まないのに毎ビルド magick を回す」ことが
      # ないよう、従来の各枝の実行条件をそのまま合成した条件を持たせている。
      def test_cover_assets_step_is_skipped_when_no_branch_consumes_covers
        options = { clean: true, resize: true, compress: true, high: false, low: false }
        command = Struct.new(:options).new(options)
        pipeline = Common.stub :pdf_combined?, false do
          Common.stub :epub_embed?, false do
            BuildCommands::UnifiedBuildPipeline.new(command, entries: [], mode: :full,
                                                             targets: targets_from(%w[pdf epub]))
          end
        end

        refute_includes op_keys(pipeline), 'prepare cover assets',
                        '表紙を結合も埋め込みもしない構成でカバーを生成すべきではない'
      end

      private

      def steps(pipeline) = pipeline.instance_variable_get(:@steps)

      # ステップラベルを操作キー（番号を除いた括弧内説明、または番号なしラベルそのもの）へ正規化する。
      def op_keys(pipeline)
        steps(pipeline).map do |step|
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

      # カバー資産ステップの有無は book.yml（output.pdf.combined / output.epub.embed）に
      # 依存する。ステップ列のスナップショットを設定で揺らさないよう、ここでは出荷時の
      # 既定「どちらの枝もカバーを使う」に固定する。使わない構成で落ちることは
      # test_cover_assets_step_is_skipped_when_no_branch_consumes_covers が押さえる。
      def build_pipeline(mode:, targets:)
        options = { clean: true, resize: true, compress: true, high: false, low: false }
        command = Struct.new(:options).new(options)
        Common.stub :pdf_combined?, true do
          Common.stub :epub_embed?, true do
            BuildCommands::UnifiedBuildPipeline.new(command, entries: [], mode:, targets:)
          end
        end
      end
    end
  end
end
