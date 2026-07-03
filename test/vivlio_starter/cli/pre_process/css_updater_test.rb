# frozen_string_literal: true

# ================================================================
# Test: css_updater_test.rb
# ================================================================
# 検証内容（P3 以降・CssUpdater は値計算＋config.js 同期のみ担う）:
#   - format_font_value: :font 変数へ generic フォールバックを付与する
#     （明朝=serif / ゴシック=sans-serif / コード=monospace）。
#     フォント非埋め込み EPUB でも category がリーダー側で保たれることの担保。
#   - sync_vivliostyle_config_title!: book.yml のタイトルを config.js へ同期する。
#
# theme.style（simple/image）による画像変数切替・ヘッダ切替・マーカー既定値は、
# P3 で BookSettingsCss 生成器＋方式A（body クラス）へ移行したため
# book_settings_css_test.rb / body_class_injector_test.rb 側で検証する。
# ================================================================

require_relative '../../../test_helper'
require 'tmpdir'
require 'fileutils'
require 'vivlio_starter/cli/pre_process/css_updater'

class CssUpdaterFontValueTest < Minitest::Test
  CU = VivlioStarter::CLI::PreProcessCommands::CssUpdater

  # 本文（明朝）は Type3 回避フォールバック（HackGen35 Console NF）＋ serif が付く
  def test_should_append_serif_for_main_text
    assert_equal '"Zen Old Mincho", "HackGen35 Console NF", serif',
                 CU.format_font_value('--font-main-text', 'Zen Old Mincho', :font)
  end

  # コードは Type3 回避フォールバックの本体（HackGen35 Console NF）のため挿入せず、monospace のみ付く
  def test_should_append_monospace_for_code
    assert_equal '"HackGen35 Console NF", monospace',
                 CU.format_font_value('--font-code', 'HackGen35 Console NF', :font)
  end

  # 見出し・コラム・ノンブル（ゴシック系）は Type3 回避フォールバック＋ sans-serif が付く
  def test_should_append_sans_serif_for_gothic_variables
    assert_equal '"Zen Kaku Gothic New", "HackGen35 Console NF", sans-serif',
                 CU.format_font_value('--font-header', 'Zen Kaku Gothic New', :font)
    assert_equal '"Zen Maru Gothic", "HackGen35 Console NF", sans-serif',
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

# sync_vivliostyle_config_title!: book.yml のタイトルを vivliostyle.config.js へ同期する。
# 回帰: CONFIG 互換層撤去後、book.yml に title キーが無い通常構成（main_title + subtitle）で
# 旧ブラケットアクセス book['title'] が ArgumentError を送出し、同期が沈黙して失敗していた。
# （chdir + reload_configuration! で canonical CONFIG を復旧する common_config_loading_test と同じ流儀）
class CssUpdaterTitleSyncTest < Minitest::Test
  CU = VivlioStarter::CLI::PreProcessCommands::CssUpdater
  Common = VivlioStarter::CLI::Common

  def setup
    @temp_dir = Dir.mktmpdir
    @original_dir = Dir.pwd
    Dir.chdir(@temp_dir)
    FileUtils.mkdir_p('config')
    %w[catalog page_presets post_replace_list].each { File.write("config/#{it}.yml", '{}') }
    File.write('vivliostyle.config.js', "  language: 'ja',\n  title: 'PLACEHOLDER',\n")
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@temp_dir)
    Common.reload_configuration!(silent: true) if File.file?('config/book.yml')
  end

  # 回帰の本丸: title キー不在でも main_title + subtitle を結合して同期できる
  def test_should_sync_title_from_main_title_and_subtitle_without_title_key
    File.write('config/book.yml',
               { 'book' => { 'main_title' => 'はじめての技術書', 'subtitle' => '実践ガイド' } }.to_yaml)
    Common.reload_configuration!(silent: true)

    CU.sync_vivliostyle_config_title!

    assert_match(/title:\s*'はじめての技術書 実践ガイド'/, File.read('vivliostyle.config.js'))
  end

  # title キーを明示した場合はそれを優先する
  def test_should_prefer_explicit_title_key
    File.write('config/book.yml',
               { 'book' => { 'main_title' => '無視される', 'title' => '明示タイトル' } }.to_yaml)
    Common.reload_configuration!(silent: true)

    CU.sync_vivliostyle_config_title!

    assert_match(/title:\s*'明示タイトル'/, File.read('vivliostyle.config.js'))
  end
end
