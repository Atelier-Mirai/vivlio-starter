# frozen_string_literal: true

# ================================================================
# Test: cmyk_converter_test.rb
# ================================================================
# テスト対象: Build::CmykConverter（表紙 CMYK カラーマネジメント）
#
# 検証内容:
#   - ICC プロファイルの解決（press-ready 同梱・設定指定・不在時 nil）
#   - ICC 不在時は to_pdfx! が false（gs を起動しない）
#   - PDF/X-1a 定義 PostScript の必須マーカー・エスケープ
#
# 注意: gs は AGPL のため本テストでは実起動しない（純ロジックのみ検証）。
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/build/cmyk_converter'

module VivlioStarter
  module CLI
    module Build
      class CmykConverterTest < Minitest::Test
        # press-ready 同梱 ICC が cwd 配下にあれば自動解決する
        def test_resolves_press_ready_icc_from_node_modules
          Dir.mktmpdir do |dir|
            icc_dir = File.join(dir, 'node_modules', 'press-ready', 'assets')
            FileUtils.mkdir_p(icc_dir)
            File.write(File.join(icc_dir, 'JapanColor2001Coated.icc'), 'dummy-icc')

            Dir.chdir(dir) do
              # 期待値は解決済み cwd（macOS の /var→/private/var symlink）基準で組む
              expected = File.join(Dir.pwd, 'node_modules/press-ready/assets/JapanColor2001Coated.icc')
              assert_equal expected, CmykConverter.icc_profile_path
              assert CmykConverter.available?, 'ICC があれば available? は true'
            end
          end
        end

        # ICC がどこにも無ければ nil（呼び出し側は素朴 CMYK へフォールバック）
        def test_returns_nil_when_no_icc_available
          Dir.mktmpdir do |dir|
            Dir.chdir(dir) do
              assert_nil CmykConverter.icc_profile_path
              refute CmykConverter.available?, 'ICC が無ければ available? は false'
            end
          end
        end

        # ICC が無ければ to_pdfx! は false を返す（gs を起動しない）
        def test_to_pdfx_returns_false_without_icc
          CmykConverter.stub(:icc_profile_path, nil) do
            refute CmykConverter.to_pdfx!('/nonexistent.pdf', bleed_mm: 3, crop_offset_mm: 13)
          end
        end

        # ICC はあるが対象 PDF が無ければ false（存在しないファイルを gs に渡さない）
        def test_to_pdfx_returns_false_when_pdf_missing
          CmykConverter.stub(:icc_profile_path, '/tmp/fake.icc') do
            refute CmykConverter.to_pdfx!('/nonexistent-cover.pdf', bleed_mm: 3, crop_offset_mm: 13)
          end
        end

        # PDF/X-1a 定義に必須マーカー・ICC パス・N=4 が含まれ、括弧がエスケープされる
        def test_pdfx_def_ps_contains_required_markers
          ps = CmykConverter.pdfx_def_ps('/tmp/Japan (Color).icc', 'My Cover')

          assert_includes ps, 'PDF/X-1a:2001'
          assert_includes ps, '/S /GTS_PDFX'
          assert_includes ps, 'Japan Color 2001 Coated'
          assert_includes ps, '/OutputIntents'
          assert_includes ps, '/N 4', 'CMYK は 4 成分'
          assert_includes ps, '/tmp/Japan \\(Color\\).icc', 'ICC パスの括弧はエスケープされる'
          assert_includes ps, '(My Cover)', 'タイトルが埋め込まれる'
        end

        # PostScript 文字列リテラルの括弧・バックスラッシュがエスケープされる
        def test_ps_escape_escapes_parens
          assert_equal 'a\\(b\\)c', CmykConverter.ps_escape('a(b)c')
        end
      end
    end
  end
end
