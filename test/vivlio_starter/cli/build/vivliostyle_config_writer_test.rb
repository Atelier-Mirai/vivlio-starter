# frozen_string_literal: true

# ================================================================
# Test: build/vivliostyle_config_writer_test.rb
# ================================================================
# テスト対象:
#   Build::VivliostyleConfigWriter.config_content / write!
#   （P4 §3.2: workspace の用途別 entries / config 生成）
#
#   - config_content: title 合成・size プリセット/実寸・language 既定・
#     プレースホルダ・' エスケープ（後方一致バックリファレンス誤解釈の回避）
#   - write!: entries と config のペア生成（entries は config と同居・
#     path は cwd 相対 ./ 前置）
#
# 注: 旧ルート vivliostyle.config.js の全文生成（write_root_config!）は
#     手動フロー撤去（vivlioverso-manual-flow-removal-spec.md）で削除済み。
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'vivlio_starter/cli/loader'

module VivlioStarter
  module CLI
    class VivliostyleConfigWriterTest < Minitest::Test
      Writer = Build::VivliostyleConfigWriter
      LOG_METHODS = %i[log_info log_success log_warn log_error log_action].freeze

      def setup
        @temp_dir = Dir.mktmpdir('vs-config-writer')
        @original_dir = Dir.pwd
        Dir.chdir(@temp_dir)
        FileUtils.mkdir_p('config')
        %w[catalog page_presets post_replace_list].each { File.write("config/#{it}.yml", '{}') }
        @saved_logs = LOG_METHODS.to_h { [it, Common.method(it)] }
        LOG_METHODS.each { |m| Common.define_singleton_method(m) { |*_a, **_k| } }
      end

      def teardown
        @saved_logs.each { |m, impl| Common.define_singleton_method(m, impl) }
        Dir.chdir(@original_dir)
        FileUtils.rm_rf(@temp_dir)
        Common.reload_configuration!(silent: true) if File.file?('config/book.yml')
      end

      def write_book_yml(book: {}, page: {})
        File.write('config/book.yml', { 'book' => book, 'page' => page }.to_yaml)
        Common.reload_configuration!(silent: true)
      end

      # --- config_content ------------------------------------------------------

      def test_should_render_metadata_from_book_yml
        write_book_yml(book: { 'main_title' => 'はじめての技術書', 'subtitle' => '実践ガイド',
                               'author' => 'アトリヱ未來', 'language' => 'ja' },
                       page: { 'size' => 'A5' })

        content = Writer.config_content(entries_basename: 'entries.sections.js', output: 'x.pdf')

        assert_includes content, "import entries from './entries.sections.js';"
        assert_match(/title: 'はじめての技術書 実践ガイド',/, content)
        assert_match(/author: 'アトリヱ未來',/, content)
        assert_match(/language: 'ja',/, content)
        assert_match(/size: 'A5',/, content)
        assert_includes content, "'./x.pdf'"
      end

      # size は実寸指定（プリセット名なし）でも "<width> <height>" として出る
      def test_should_render_literal_page_size
        write_book_yml(book: { 'main_title' => 'T' }, page: { 'width' => '128mm', 'height' => '188mm' })

        content = Writer.config_content(entries_basename: 'entries.sections.js', output: 'x.pdf')

        assert_match(%r{size: '128mm 188mm',}, content)
      end

      # 未設定のメタデータはプレースホルダへ寄せる（vivliostyle 11 スキーマが 1 文字以上を要求）
      def test_should_fall_back_to_placeholders
        write_book_yml(book: {})

        content = Writer.config_content(entries_basename: 'entries.sections.js', output: 'x.pdf')

        assert_match(/title: '書籍タイトル',/, content)
        assert_match(/author: '著者名',/, content)
        assert_match(/language: 'ja',/, content)
      end

      # title 内の ' を JS 文字列として安全にエスケープする
      # （gsub の置換文字列内 \' は後方一致と解釈されるため、ブロック形で回避している）
      def test_should_escape_single_quote_in_title
        write_book_yml(book: { 'title' => "It's a book" })

        content = Writer.config_content(entries_basename: 'entries.sections.js', output: 'x.pdf')

        assert_includes content, %q(title: 'It\\'s a book',)
      end

      # --- write! ---------------------------------------------------------------

      # entries と config をペアで生成し、entries は config と同居・path は ./ 前置
      def test_should_write_entries_and_config_pair
        write_book_yml(book: { 'main_title' => 'T' })
        File.write('11-intro.html', '<html><title>はじめに</title></html>')

        config_path = Writer.write!(name: 'sections', entry_htmls: ['11-intro.html'],
                                    output: File.join(Common::BUILD_PDF_DIR, '_sections.pdf'))

        assert_equal File.join(Common::BUILD_PDF_DIR, 'vivliostyle.config.sections.js'), config_path
        entries = File.read(File.join(Common::BUILD_PDF_DIR, 'entries.sections.js'))
        assert_includes entries, '"path": "./11-intro.html"'
        assert_includes entries, '"title": "はじめに"'
        config = File.read(config_path)
        assert_includes config, "import entries from './entries.sections.js';"
      end
    end
  end
end
