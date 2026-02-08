# frozen_string_literal: true

# ================================================================
# Test: page_layout_test.rb
# ================================================================
# テスト対象:
#   - vivliostyle.config.js の size プロパティ同期
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
require 'vivlio/starter/cli/common'
require 'vivlio/starter/cli/vivliostyle'
require 'vivlio/starter/cli/build'
require 'vivlio/starter/cli/pre_process/css_updater'

module Vivlio
  module Starter
    module CLI
      # ================================================================
      # vivliostyle.config.js size プロパティのテスト
      # ================================================================
      class VivliostyleConfigSizeTest < Minitest::Test
        def test_resolve_vivliostyle_size_returns_a5_for_a5_preset
          config = Common::CONFIG
          size = VivliostyleCommands.resolve_vivliostyle_size(config)
          assert_equal 'A5', size
        end

        def test_resolve_vivliostyle_size_returns_a5_when_page_nil
          # page が nil の場合はデフォルト A5
          mock_config = { page: nil }
          size = VivliostyleCommands.resolve_vivliostyle_size(mock_config)
          assert_equal 'A5', size
        end

        def test_resolve_vivliostyle_size_returns_dimensions_when_no_size_key
          mock_config = { page: { width: '182mm', height: '257mm' } }
          size = VivliostyleCommands.resolve_vivliostyle_size(mock_config)
          assert_equal '182mm 257mm', size
        end

        def test_resolve_vivliostyle_size_returns_b5_for_b5_preset
          mock_config = { page: { size: 'B5' } }
          size = VivliostyleCommands.resolve_vivliostyle_size(mock_config)
          assert_equal 'B5', size
        end

        def test_resolve_vivliostyle_size_normalizes_case
          mock_config = { page: { size: 'a4' } }
          size = VivliostyleCommands.resolve_vivliostyle_size(mock_config)
          assert_equal 'A4', size
        end

        def test_vivliostyle_config_js_contains_size_property
          content = File.read('vivliostyle.config.js', encoding: 'utf-8')
          assert_match(/size:\s*'A5'/, content,
                       'vivliostyle.config.js に size: A5 が含まれていること')
        end
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
          @merger = Vivlio::Starter::CLI::Build::PdfMerger
        end

        def test_insert_blank_when_body_pages_even
          # カバー除外後の本文ページ数が偶数 → 空白ページ挿入が必要
          files = %w[covers/front.pdf _titlepage_legalpage.pdf _sections.pdf _colophon.pdf]

          # covers/ は除外、titlepage_legalpage=2, sections=8 → total=10(偶数)
          fake_counts = { '_titlepage_legalpage.pdf' => 2, '_sections.pdf' => 8 }
          Vivlio::Starter::CLI::Build::Utilities.stub(:page_count, ->(f) { fake_counts[f] || 0 }) do
            Vivlio::Starter::CLI::Build::Utilities.stub(:ensure_blank_page_pdf, '_blank_before_colophon.pdf') do
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
          Vivlio::Starter::CLI::Build::Utilities.stub(:page_count, ->(f) { fake_counts[f] || 0 }) do
            result = @merger.send(:insert_blank_page_before_colophon, files)
            refute_includes result, '_blank_before_colophon.pdf',
                           '奇数ページ数のとき空白ページは挿入されないこと'
          end
        end

        def test_cover_excluded_from_parity
          # カバー(1p)を含めると偶数(12)だが、除外すると奇数(11) → 挿入なし
          files = %w[covers/frontcover_rgb.pdf _titlepage_legalpage.pdf _sections.pdf _colophon.pdf]

          fake_counts = { 'covers/frontcover_rgb.pdf' => 1, '_titlepage_legalpage.pdf' => 2, '_sections.pdf' => 9 }
          Vivlio::Starter::CLI::Build::Utilities.stub(:page_count, ->(f) { fake_counts[f] || 0 }) do
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

          Vivlio::Starter::CLI::Build::Utilities.stub(:page_count, ->(_) { 0 }) do
            result = @merger.send(:insert_blank_page_before_colophon, files)
            refute_includes result, '_blank_before_colophon.pdf',
                           'ページ数 0 のとき空白ページは挿入されないこと'
          end
        end
      end

      # ================================================================
      # vivliostyle.config.js size 同期のテスト
      # ================================================================
      class VivliostyleConfigSizeSyncTest < Minitest::Test
        def setup
          @tmpdir = Dir.mktmpdir
          @original_dir = Dir.pwd
          Dir.chdir(@tmpdir)
        end

        def teardown
          Dir.chdir(@original_dir)
          FileUtils.rm_rf(@tmpdir)
        end

        def test_sync_updates_existing_size_property
          File.write('vivliostyle.config.js', <<~JS)
            const vivliostyleConfig = {
              title: 'テスト',
              language: 'ja', // 言語設定
              size: 'A4', // ページサイズ
              entry: entries,
            };
          JS

          Vivlio::Starter::CLI::PreProcessCommands::CssUpdater.sync_vivliostyle_config_size!('148mm', '210mm', 'A5')

          content = File.read('vivliostyle.config.js')
          assert_match(/size:\s*'A5'/, content, 'size が A5 に更新されること')
          refute_match(/size:\s*'A4'/, content, '旧サイズ A4 が残らないこと')
        end

        def test_sync_inserts_size_when_missing
          File.write('vivliostyle.config.js', <<~JS)
            const vivliostyleConfig = {
              title: 'テスト',
              language: 'ja', // 言語設定
              entry: entries,
            };
          JS

          Vivlio::Starter::CLI::PreProcessCommands::CssUpdater.sync_vivliostyle_config_size!('148mm', '210mm', 'A5')

          content = File.read('vivliostyle.config.js')
          assert_match(/size:\s*'A5'/, content, 'size プロパティが挿入されること')
        end

        def test_sync_uses_dimensions_when_size_name_empty
          File.write('vivliostyle.config.js', <<~JS)
            const vivliostyleConfig = {
              title: 'テスト',
              language: 'ja', // 言語設定
              size: 'A4', // ページサイズ
              entry: entries,
            };
          JS

          Vivlio::Starter::CLI::PreProcessCommands::CssUpdater.sync_vivliostyle_config_size!('200mm', '300mm', nil)

          content = File.read('vivliostyle.config.js')
          assert_match(/size:\s*'200mm 300mm'/, content,
                       'サイズ名がない場合は幅×高さが設定されること')
        end

        def test_sync_skips_when_file_missing
          # vivliostyle.config.js が存在しない場合はエラーにならない
          assert_nil Vivlio::Starter::CLI::PreProcessCommands::CssUpdater.sync_vivliostyle_config_size!('148mm', '210mm', 'A5')
        end
      end
    end
  end
end
