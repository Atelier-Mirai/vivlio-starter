# frozen_string_literal: true

# ================================================================
# Test: css_updater_test.rb
# ================================================================
# 検証内容:
#   - format_font_value: :font 変数へ generic フォールバックを付与する
#     （明朝=serif / ゴシック=sans-serif / コード=monospace）。
#     フォント非埋め込み EPUB でも category がリーダー側で保たれることの担保。
# ================================================================

require_relative '../../../test_helper'
require 'vivlio_starter/cli/pre_process/css_updater'

class CssUpdaterFontValueTest < Minitest::Test
  CU = VivlioStarter::CLI::PreProcessCommands::CssUpdater

  # 本文（明朝）は serif フォールバックが付く
  def test_should_append_serif_for_main_text
    assert_equal '"Zen Old Mincho", serif',
                 CU.format_font_value('--font-main-text', 'Zen Old Mincho', :font)
  end

  # コードは monospace フォールバックが付く
  def test_should_append_monospace_for_code
    assert_equal '"hackgen35", monospace',
                 CU.format_font_value('--font-code', 'hackgen35', :font)
  end

  # 見出し・コラム・ノンブル（ゴシック系）は sans-serif フォールバックが付く
  def test_should_append_sans_serif_for_gothic_variables
    assert_equal '"Zen Kaku Gothic New", sans-serif',
                 CU.format_font_value('--font-header', 'Zen Kaku Gothic New', :font)
    assert_equal '"Zen Maru Gothic", sans-serif',
                 CU.format_font_value('--font-column', 'Zen Maru Gothic', :font)
  end

  # book.yml 側で既にフォールバックを指定済み（カンマ含む）なら尊重して触らない
  def test_should_respect_existing_fallback_chain
    value = '"My Font", serif'
    assert_equal value, CU.format_font_value('--font-main-text', value, :font)
  end

  # :font 以外（kind が nil）の値はそのまま返す
  def test_should_not_touch_non_font_values
    assert_equal '210mm', CU.format_font_value('--page-width', '210mm', nil)
  end
end
