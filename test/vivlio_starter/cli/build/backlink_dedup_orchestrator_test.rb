# frozen_string_literal: true

# ================================================================
# Test: build/backlink_dedup_orchestrator_test.rb
# ================================================================
# テスト対象:
#   BacklinkDedupOrchestrator の先回り（dedup-rerender-skip-spec.md §4）
#   - speculate!: 前回のページ対応で索引の重複を先に除き、消したリンクを証拠に残す
#   - run!: 今回のページ対応で判定を確かめ、当たりなら 2 回目の組版を省く
#   組版（build_sections_pdf!）と PDF からのページ対応の取得は差し替え、呼ばれた回数を数える。
# ================================================================

require_relative '../../../test_helper'
require 'tmpdir'
require 'fileutils'
require 'nokogiri'
require 'vivlio_starter/cli/loader'

module VivlioStarter
  module CLI
    module Build
      class BacklinkDedupOrchestratorTest < Minitest::Test
        Orchestrator = BacklinkDedupOrchestrator
        Extractor = PdfPageMapExtractor
        LOG_METHODS_TO_SILENCE = %i[log_info log_success log_warn log_error log_action].freeze

        # 「ファイル」の参照 2 本。同じページなら 1 本に減る
        INDEX_PAGE = <<~HTML
          <!DOCTYPE html>
          <html lang="ja"><head><meta charset="UTF-8"><title>索引</title></head>
          <body class="index-page"><dl class="index-list">
          <dt>ファイル</dt><dd><a href="01-life.html#idx-1"></a><a href="01-life.html#idx-2"></a></dd>
          </dl></body></html>
        HTML

        def setup
          @saved_log_methods = LOG_METHODS_TO_SILENCE.to_h { [it, Common.method(it)] }
          LOG_METHODS_TO_SILENCE.each { Common.define_singleton_method(it) { |*| } }
        end

        def teardown
          @saved_log_methods.each { |name, m| Common.define_singleton_method(name, m) }
        end

        def test_should_skip_second_render_when_previous_pages_still_hold
          in_workspace(previous: { 'idx-1' => 10, 'idx-2' => 10 }) do
            Orchestrator.speculate!
            assert_equal 1, dd_links.size, '前回のページ対応で、1 回目の組版の前に重複を除く'
            assert_equal ['01-life.html#idx-2'], witness_hrefs, '消したリンクは証拠として残す'

            renders = run_with(current: { 'idx-1' => 10, 'idx-2' => 10 })

            assert_equal 0, renders, '判定が同じなら 2 回目を組まない'
            refute Dir.exist?(Orchestrator.originals_dir), '先回り前の控えは片づける'
          end
        end

        # 判定に効かないずれ（どちらも同じページのまま動く）は当たりに数える
        def test_should_treat_shift_that_keeps_decisions_as_hit
          in_workspace(previous: { 'idx-1' => 10, 'idx-2' => 10 }) do
            Orchestrator.speculate!

            assert_equal 0, run_with(current: { 'idx-1' => 11, 'idx-2' => 11 })
          end
        end

        def test_should_render_again_with_new_decisions_when_pages_moved
          in_workspace(previous: { 'idx-1' => 10, 'idx-2' => 10 }) do
            Orchestrator.speculate!

            renders = run_with(current: { 'idx-1' => 10, 'idx-2' => 11 })

            assert_equal 1, renders
            assert_equal 2, dd_links.size, '今回のページ対応で作り直した索引で組む'
            assert_empty witness_hrefs, '組み直す索引には証拠を残さない'
          end
        end

        def test_should_render_again_when_images_were_swapped
          in_workspace(previous: { 'idx-1' => 10, 'idx-2' => 10 }) do
            Orchestrator.speculate!

            assert_equal 1, run_with(current: { 'idx-1' => 10, 'idx-2' => 10 }, images_changed: true)
          end
        end

        def test_should_render_twice_as_before_without_record
          in_workspace(previous: nil) do
            Orchestrator.speculate!
            refute Dir.exist?(Orchestrator.originals_dir), '記録が無ければ先回りしない'
            assert_equal 2, dd_links.size

            assert_equal 1, run_with(current: { 'idx-1' => 10, 'idx-2' => 10 })
            assert File.exist?(Orchestrator.record_path), '次のビルドのために記録を残す'
          end
        end

        def test_should_not_speculate_after_body_daggers_were_removed
          in_workspace(previous: { 'idx-1' => 10, 'idx-2' => 10 }, body_removed: 1) do
            Orchestrator.speculate!

            refute Dir.exist?(Orchestrator.originals_dir)
            assert_equal 2, dd_links.size
          end
        end

        # 入稿用だけの経路は 2 回目をもともと組まず、pdf/ の HTML で入稿用を組む。証拠を持ち込まない
        def test_should_hand_clean_index_to_print_only_render_on_hit
          in_workspace(previous: { 'idx-1' => 10, 'idx-2' => 10 }) do
            Orchestrator.speculate!

            assert_equal 0, run_with(current: { 'idx-1' => 10, 'idx-2' => 10 }, rebuild_pdf: false)
            assert_equal 1, dd_links.size
            assert_empty witness_hrefs
          end
        end

        def test_should_ignore_broken_record
          in_workspace(previous: nil) do
            File.write(Orchestrator.record_path, '{"version": 1, "pages": [')
            Orchestrator.speculate!

            refute Dir.exist?(Orchestrator.originals_dir)
          end
        end

        private

        # pdf/ に索引だけを置いた作業場で yield する。previous を渡すと前回の記録も置く
        def in_workspace(previous:, body_removed: 0)
          Dir.mktmpdir do |dir|
            Dir.chdir(dir) do
              FileUtils.mkdir_p(Common::BUILD_PDF_DIR)
              File.write(index_path, INDEX_PAGE, encoding: 'utf-8')
              if previous
                result = BacklinkDeduplicator::Result.new(glossary_removed: 0, body_removed:, index_removed: 0,
                                                          files_modified: [])
                Orchestrator.save_record!(mapping(previous), result)
              end
              IndexCommands.stub(:index_enabled?, true) { yield }
            end
          end
        end

        # Step 8 を、PDF から取ったことにしたページ対応で走らせ、2 回目の組版の回数を返す
        def run_with(current:, images_changed: false, rebuild_pdf: true)
          renders = 0
          Orchestrator.stub(:extract_page_mapping, mapping(current)) do
            Orchestrator.stub(:build_sections_pdf!, -> { renders += 1 }) do
              Orchestrator.run!([], rebuild_pdf:, images_changed:)
            end
          end
          renders
        end

        def mapping(pages) = Extractor.page_mapping_from(pages, total_pages: 30)

        def index_path = File.join(Common::BUILD_PDF_DIR, '_indexpage.html')

        def index_doc = Nokogiri::HTML5(File.read(index_path, encoding: 'utf-8'))

        def dd_links = index_doc.css('.index-list dd a')

        def witness_hrefs = index_doc.css("div.#{BacklinkDeduplicator::WITNESS_CLASS} a").map { it['href'] }
      end
    end
  end
end
