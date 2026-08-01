# frozen_string_literal: true

# ================================================================
# Test: build/rotate_table_images_test.rb
# ================================================================
# テスト対象:
#   Build::RotateTableImages（kindle-rotate-table-image-spec.md）
#   ＋ PdfBuilder.inject_rotate_table_anchors!（/Dests の目印を埋める側）
#
# 検証内容:
#   - 内部 ID の収集（html/ の原本から）
#   - 版面の切り出し寸法（柱・ノンブルを落とし、表裏の判定を要らなくする）
#   - PDF が無いときの縮退と、その案内が具体的であること
#   - staged HTML への自己参照リンク注入（id だけでは /Dests に出ない）
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'vivlio_starter/cli/loader'
require 'vivlio_starter/cli/build'

module VivlioStarter
  module CLI
    module Build
      class RotateTableImagesTest < Minitest::Test
        WRAPPER = '<div id="rot-22-extentions-1" class="rotate-table"><table></table></div>'

        def teardown
          RotateTableImages.arm!(false)
        end

        # --- ID の収集 ---------------------------------------------------------

        def test_should_collect_rotate_ids_from_workspace_html
          Dir.mktmpdir do |dir|
            File.write(File.join(dir, '22-extentions.html'), "<html><body>#{WRAPPER}</body></html>")
            File.write(File.join(dir, '11-workflow.html'), '<html><body><p>回転テーブルなし</p></body></html>')

            assert_equal %w[rot-22-extentions-1], RotateTableImages.collect_anchor_ids(dir).keys
          end
        end

        def test_should_collect_nothing_when_no_rotate_tables_exist
          Dir.mktmpdir do |dir|
            File.write(File.join(dir, '11-workflow.html'), '<html><body><table></table></body></html>')

            assert_empty RotateTableImages.collect_anchor_ids(dir)
          end
        end

        # --- 切り出し寸法 -------------------------------------------------------

        # 左右は inner/outer の狭いほうで対称に切る。柱とノンブルは天地の余白に入るので、
        # 左右は「版面を欠かない」ことだけ満たせばよく、ページの表裏を判定せずに済む。
        def test_should_crop_symmetrically_using_the_narrower_side_margin
          geometry = RotateTableImages.crop_geometry

          skip 'プロジェクト文脈が無い環境ではスキップ' unless geometry

          page = Common::CONFIG.page.to_h
          side = [Units.length_to_mm(page[:margin_inner]), Units.length_to_mm(page[:margin_outer])].min
          expected_left = (side * geometry[:dpi] / Units::MM_PER_INCH).round

          assert_equal expected_left, geometry[:left]
          assert_operator geometry[:width], :>, 0
          assert_operator geometry[:height], :>, geometry[:width], '版面は横より縦が長い'
        end

        # 解像度は「版面幅が CONTENT_WIDTH_PX になる」ように決まる。
        # Kindle 端末幅（1072px）を上回り、拡大しても粗が出ない。
        def test_should_choose_a_resolution_that_renders_the_content_width_at_render_width
          geometry = RotateTableImages.crop_geometry

          skip 'プロジェクト文脈が無い環境ではスキップ' unless geometry

          page = Common::CONFIG.page.to_h
          page_w = Units.length_to_mm(Common.resolve_page_size(page).first)
          content_w = page_w - Units.length_to_mm(page[:margin_inner]) - Units.length_to_mm(page[:margin_outer])
          rendered = content_w / Units::MM_PER_INCH * geometry[:dpi]

          assert_in_delta RotateTableImages::CONTENT_WIDTH_PX, rendered, 5
        end

        # --- 縮退 ---------------------------------------------------------------

        # PDF を作らないビルドでは画像化できない。素の表へ落とすが、黙って落とさず
        # 「どうすれば画像になるか」を添える（warning-messages-actionable）。
        def test_should_warn_with_a_concrete_fix_when_the_source_pdf_is_missing
          warnings = []
          Common.stub :log_warn, ->(msg, detail: nil) { warnings << [msg, detail].compact.join("\n") } do
            RotateTableImages.stub :collect_anchor_ids, { 'rot-22-extentions-1' => 'x.html' } do
              assert_equal 0, RotateTableImages.extract!('/nonexistent/_sections.pdf')
            end
          end

          assert_match(/本文 PDF がありません/, warnings.join)
          assert_match(/output\.targets/, warnings.join, '対処（targets に pdf を足す）を示すべき')
        end

        def test_should_do_nothing_when_there_are_no_rotate_tables
          RotateTableImages.stub :collect_anchor_ids, {} do
            assert_equal 0, RotateTableImages.extract!('/nonexistent/_sections.pdf')
          end
        end

        # --- ラッチ -------------------------------------------------------------

        # 待つ相手がいないビルド（PDF 枝が無い）では待たない
        def test_should_not_wait_when_the_latch_is_not_armed
          RotateTableImages.arm!(false)

          refute RotateTableImages.armed?
          refute_nil Thread.new { RotateTableImages.wait_until_ready! }.join(5), '待たずに戻るべき'
        end

        def test_should_wait_until_released
          RotateTableImages.arm!(true)
          waiter = Thread.new { RotateTableImages.wait_until_ready! }

          assert_nil waiter.join(0.2), '解放前は待ち続けるべき'

          RotateTableImages.release!

          refute_nil waiter.join(5), '解放したら戻るべき'
        end

        # --- /Dests の目印 ------------------------------------------------------

        # id を持つだけの要素は /Dests に出ない。リンクの飛び先にして初めて出る
        # （前付・奥付と同じ落とし穴）。
        def test_should_inject_a_link_that_targets_the_rotate_table_id
          with_staged_html("<html><body>#{WRAPPER}</body></html>") do |path|
            PdfBuilder.inject_rotate_table_anchors!

            html = File.read(path)

            assert_includes html, '<a href="#rot-22-extentions-1" style="position:absolute"></a>'
            assert_equal 1, html.scan('id="rot-22-extentions-1"').size, 'id は増やさない（リンクだけ足す）'
          end
        end

        def test_should_leave_html_without_rotate_tables_untouched
          source = '<html><body><p>回転テーブルなし</p></body></html>'
          with_staged_html(source) do |path|
            PdfBuilder.inject_rotate_table_anchors!

            assert_equal source, File.read(path)
          end
        end

        private

        def with_staged_html(html)
          Dir.mktmpdir do |dir|
            path = File.join(dir, '22-extentions.html')
            File.write(path, html)
            with_build_pdf_dir(dir) { yield path }
          end
        end

        # BUILD_PDF_DIR は定数なので、差し替えは remove_const → const_set で行う
        def with_build_pdf_dir(dir)
          original = Common::BUILD_PDF_DIR
          Common.send(:remove_const, :BUILD_PDF_DIR)
          Common.const_set(:BUILD_PDF_DIR, dir)
          yield
        ensure
          Common.send(:remove_const, :BUILD_PDF_DIR)
          Common.const_set(:BUILD_PDF_DIR, original)
        end
      end
    end
  end
end
