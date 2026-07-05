# frozen_string_literal: true

# ================================================================
# Test: page_layout_test.rb
# ================================================================
# テスト対象:
#   - vivliostyle size 解決（resolve_vivliostyle_size）
#   - CSS break-before: recto による右ページ始まり
#   - 奥付の偶数ページ配置（空白ページ挿入）
#   - 画像オーバーフロー防止 CSS
#
# 設計方針:
#   - PDF を実際にビルドせずにロジックを検証
#   - CSS ファイルの内容チェックで break-before を確認
#   - insert_blank_page_before_colophon のロジックをユニットテスト
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/vivliostyle'
require 'vivlio_starter/cli/build'
require 'vivlio_starter/cli/pre_process/css_updater'

module VivlioStarter
  module CLI
    # ================================================================
    # vivliostyle.config.js size プロパティのテスト
    # ================================================================
    class VivliostyleConfigSizeTest < Minitest::Test
      def test_resolve_vivliostyle_size_returns_a5_for_a5_preset
        config = Common.wrap_config(page: { size: 'A5' })
        size = VivliostyleCommands.resolve_vivliostyle_size(config)
        assert_equal 'A5', size
      end

      def test_resolve_vivliostyle_size_returns_a5_when_page_nil
        size = VivliostyleCommands.resolve_vivliostyle_size(Common.wrap_config(page: nil))
        assert_equal 'A5', size
      end

      def test_resolve_vivliostyle_size_returns_dimensions_when_no_size_key
        config = Common.wrap_config(page: { width: '182mm', height: '257mm' })
        size = VivliostyleCommands.resolve_vivliostyle_size(config)
        assert_equal '182mm 257mm', size
      end

      def test_resolve_vivliostyle_size_returns_b5_for_b5_preset
        config = Common.wrap_config(page: { size: 'B5' })
        size = VivliostyleCommands.resolve_vivliostyle_size(config)
        assert_equal 'B5', size
      end

      def test_resolve_vivliostyle_size_normalizes_case
        config = Common.wrap_config(page: { size: 'a4' })
        size = VivliostyleCommands.resolve_vivliostyle_size(config)
        assert_equal 'A4', size
      end

      # 注: ルート vivliostyle.config.js の size 検証は手動フロー撤去
      # （vivlioverso-manual-flow-removal-spec.md）に伴い削除。生成 config の
      # size は vivliostyle_config_writer_test.rb が検証する。
    end

    # ================================================================
    # CSS break-before: recto のテスト
    # ================================================================
    class CssBreakBeforeTest < Minitest::Test
      STYLESHEETS_DIR = 'stylesheets'

      def test_toc_css_has_break_before_recto
        css = read_css('toc.css')
        assert_match(/break-before:\s*recto/, css,
                     'toc.css に break-before: recto が含まれていること')
      end

      def test_chapter_common_css_has_break_before_recto
        css = read_css('chapter-common.css')
        assert_match(/break-before:\s*recto/, css,
                     'chapter-common.css に break-before: recto が含まれていること')
      end

      def test_glossary_css_has_break_before_recto
        css = read_css('glossary.css')
        assert_match(/break-before:\s*recto/, css,
                     'glossary.css に break-before: recto が含まれていること')
      end

      def test_index_css_has_break_before_recto
        css = read_css('index.css')
        assert_match(/break-before:\s*recto/, css,
                     'index.css に break-before: recto が含まれていること')
      end

      def test_postface_css_has_break_before_recto
        css = read_css('postface.css')
        assert_match(/break-before:\s*recto/, css,
                     'postface.css に break-before: recto が含まれていること')
      end

      private

      def read_css(filename)
        File.read(File.join(STYLESHEETS_DIR, filename), encoding: 'utf-8')
      end
    end

    # ================================================================
    # 画像オーバーフロー防止 CSS のテスト
    # ================================================================
    class CssImageOverflowTest < Minitest::Test
      def test_base_css_has_image_max_inline_size
        css = File.read('stylesheets/base.css', encoding: 'utf-8')
        assert_match(/img\s*\{[^}]*max-inline-size:\s*100%/m, css,
                     'base.css に img { max-inline-size: 100% } が含まれていること')
      end
    end

    # ================================================================
    # 奥付偶数ページ配置ロジックのテスト
    # ================================================================
    class ColophonPageParityTest < Minitest::Test
      def setup
        @merger = VivlioStarter::CLI::Build::PdfMerger
      end

      def test_insert_blank_when_body_pages_even
        # カバー除外後の本文ページ数が偶数 → 空白ページ挿入が必要
        files = %w[covers/front.pdf _titlepage_legalpage.pdf _sections.pdf _colophon.pdf]

        # covers/ は除外、titlepage_legalpage=2, sections=8 → total=10(偶数)
        fake_counts = { '_titlepage_legalpage.pdf' => 2, '_sections.pdf' => 8 }
        VivlioStarter::CLI::Build::Utilities.stub(:page_count, ->(f) { fake_counts[f] || 0 }) do
          VivlioStarter::CLI::Build::Utilities.stub(:ensure_blank_page_pdf, '_blank_before_colophon.pdf') do
            result = @merger.send(:insert_blank_page_before_colophon, files)
            assert_includes result, '_blank_before_colophon.pdf',
                           '偶数ページ数のとき空白ページが挿入されること'
            colophon_idx = result.index('_colophon.pdf')
            blank_idx = result.index('_blank_before_colophon.pdf')
            assert blank_idx < colophon_idx, '空白ページは奥付の前に配置されること'
          end
        end
      end

      def test_no_blank_when_body_pages_odd
        # カバー除外後の本文ページ数が奇数 → 空白ページ不要
        files = %w[covers/front.pdf _titlepage_legalpage.pdf _sections.pdf _colophon.pdf]

        # covers/ は除外、titlepage_legalpage=2, sections=9 → total=11(奇数)
        fake_counts = { '_titlepage_legalpage.pdf' => 2, '_sections.pdf' => 9 }
        VivlioStarter::CLI::Build::Utilities.stub(:page_count, ->(f) { fake_counts[f] || 0 }) do
          result = @merger.send(:insert_blank_page_before_colophon, files)
          refute_includes result, '_blank_before_colophon.pdf',
                         '奇数ページ数のとき空白ページは挿入されないこと'
        end
      end

      def test_cover_excluded_from_parity
        # カバー(1p)を含めると偶数(12)だが、除外すると奇数(11) → 挿入なし
        files = %w[covers/frontcover_rgb.pdf _titlepage_legalpage.pdf _sections.pdf _colophon.pdf]

        fake_counts = { 'covers/frontcover_rgb.pdf' => 1, '_titlepage_legalpage.pdf' => 2, '_sections.pdf' => 9 }
        VivlioStarter::CLI::Build::Utilities.stub(:page_count, ->(f) { fake_counts[f] || 0 }) do
          result = @merger.send(:insert_blank_page_before_colophon, files)
          refute_includes result, '_blank_before_colophon.pdf',
                         'カバーを除外した本文ページ数が奇数なら空白挿入なし'
        end
      end

      def test_no_colophon_in_files_returns_unchanged
        files = %w[_titlepage_legalpage.pdf _sections.pdf]
        result = @merger.send(:insert_blank_page_before_colophon, files)
        assert_equal files, result, '奥付がない場合はファイルリストが変更されないこと'
      end

      def test_zero_page_count_returns_unchanged
        files = %w[_titlepage_legalpage.pdf _sections.pdf _colophon.pdf]

        VivlioStarter::CLI::Build::Utilities.stub(:page_count, ->(_) { 0 }) do
          result = @merger.send(:insert_blank_page_before_colophon, files)
          refute_includes result, '_blank_before_colophon.pdf',
                         'ページ数 0 のとき空白ページは挿入されないこと'
        end
      end
    end

    # vivliostyle.config.js の size/title 同期テストは P3-4 で全文生成
    # （Build::VivliostyleConfigWriter）へ移行したため撤去した。
    # 生成の検証は test/vivlio_starter/cli/build/vivliostyle_config_writer_test.rb を参照。

    # ================================================================
    # calculate_align_max_width のテスト
    #
    # Vivliostyle が `min(26em, max-content)` を未対応なため、
    # CSS カスタムプロパティ `--align-max-width` として判型別に値を供給する。
    # 詳細は docs/specs/vivliostyle_warnings_spec.md 参照。
    # ================================================================
    class CalculateAlignMaxWidthTest < Minitest::Test
      CssUpdater = VivlioStarter::CLI::PreProcessCommands::CssUpdater

      def test_a5_returns_26em
        assert_equal '26em', CssUpdater.calculate_align_max_width('148mm')
      end

      def test_b5_jis_returns_36em
        assert_equal '36em', CssUpdater.calculate_align_max_width('182mm')
      end

      def test_b5_iso_returns_36em
        assert_equal '36em', CssUpdater.calculate_align_max_width('176mm')
      end

      def test_a4_returns_40em
        assert_equal '40em', CssUpdater.calculate_align_max_width('210mm')
      end

      def test_larger_than_a4_returns_40em
        assert_equal '40em', CssUpdater.calculate_align_max_width('257mm')
      end

      def test_invalid_value_falls_back_to_40em
        assert_equal '40em', CssUpdater.calculate_align_max_width('')
        assert_equal '40em', CssUpdater.calculate_align_max_width(nil)
      end

      def test_a5_boundary_155mm_returns_26em
        assert_equal '26em', CssUpdater.calculate_align_max_width('155mm')
      end

      def test_just_over_a5_boundary_returns_36em
        assert_equal '36em', CssUpdater.calculate_align_max_width('160mm')
      end
    end
  end
end
