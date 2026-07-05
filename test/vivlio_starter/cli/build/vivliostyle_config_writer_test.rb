# frozen_string_literal: true

# ================================================================
# Test: build/vivliostyle_config_writer_test.rb
# ================================================================
# テスト対象:
#   Build::VivliostyleConfigWriter.write_root_config! / root_config_content
#   （P3-4: ルート vivliostyle.config.js の book.yml からの全文生成）
#
#   - root_config_content: title 合成・size プリセット/実寸・language 既定・
#     hardLineBreaks の true/false 反映・エントリーレベル VFM・' エスケープ
#   - write_root_config!: マーカー付き既存 → 再生成 / 内容同一 → 無書込（mtime 不変）/
#     マーカー無し既存 → .bak 退避＋生成 / .bak 既存時は退避せず / ファイル欠落 → 生成
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
        @temp_dir = Dir.mktmpdir('vs-root-config')
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

      def write_book_yml(book: {}, page: {}, vfm: nil)
        data = { 'book' => book, 'page' => page }
        data['vfm'] = vfm unless vfm.nil?
        File.write('config/book.yml', data.to_yaml)
        Common.reload_configuration!(silent: true)
      end

      # --- root_config_content -------------------------------------------------

      def test_should_render_marker_and_metadata_from_book_yml
        write_book_yml(book: { 'main_title' => 'はじめての技術書', 'subtitle' => '実践ガイド',
                               'author' => 'アトリヱ未來', 'language' => 'ja' },
                       page: { 'size' => 'A5' })

        content = Writer.root_config_content

        assert_includes content, Writer::ROOT_CONFIG_MARKER
        assert_match(/title: 'はじめての技術書 実践ガイド',/, content)
        assert_match(/author: 'アトリヱ未來',/, content)
        assert_match(/language: 'ja',/, content)
        assert_match(/size: 'A5',/, content)
      end

      # エントリーレベル VFM: entries.map で各 entry に vfm を注入し、トップレベル vfm は出さない
      def test_should_apply_entry_level_vfm_without_toplevel_block
        write_book_yml(book: { 'main_title' => 'T' })

        content = Writer.root_config_content

        assert_match(/entry: entries\.map\(\(entry\) => \(\{/, content)
        assert_includes content, 'vfm: { hardLineBreaks: true }'
        refute_match(/^  vfm:/, content) # 2 スペース字下げのトップレベル vfm プロパティは無い
      end

      # hard_line_breaks: false を book.yml で明示すると false が反映される
      def test_should_reflect_hard_line_breaks_false
        write_book_yml(book: { 'main_title' => 'T' }, vfm: { 'hard_line_breaks' => false })

        assert_includes Writer.root_config_content, 'vfm: { hardLineBreaks: false }'
      end

      # size は実寸指定（プリセット名なし）でも "<width> <height>" として出る
      def test_should_render_literal_page_size
        write_book_yml(book: { 'main_title' => 'T' }, page: { 'width' => '128mm', 'height' => '188mm' })

        assert_match(%r{size: '128mm 188mm',}, Writer.root_config_content)
      end

      # 未設定のメタデータはプレースホルダへ寄せる（vivliostyle 11 スキーマが 1 文字以上を要求）
      def test_should_fall_back_to_placeholders
        write_book_yml(book: {})

        content = Writer.root_config_content
        assert_match(/title: '書籍タイトル',/, content)
        assert_match(/author: '著者名',/, content)
        assert_match(/language: 'ja',/, content)
      end

      # title 内の ' を JS 文字列として安全にエスケープする
      def test_should_escape_single_quote_in_title
        write_book_yml(book: { 'title' => "It's a book" })

        assert_includes Writer.root_config_content, %q(title: 'It\\'s a book',)
      end

      # --- write_root_config! --------------------------------------------------

      def test_should_generate_when_file_missing
        write_book_yml(book: { 'main_title' => 'T' })
        refute_path_exists('vivliostyle.config.js')

        Writer.write_root_config!

        assert_path_exists('vivliostyle.config.js')
        assert_includes File.read('vivliostyle.config.js'), Writer::ROOT_CONFIG_MARKER
      end

      # 内容が同一なら書き込まない（mtime 不変・write-if-changed）
      def test_should_not_rewrite_when_unchanged
        write_book_yml(book: { 'main_title' => 'T' })
        Writer.write_root_config!
        mtime = File.mtime('vivliostyle.config.js')

        sleep 0.01
        Writer.write_root_config!

        assert_equal mtime, File.mtime('vivliostyle.config.js')
      end

      # マーカー付き既存で内容が変わるなら再生成する
      def test_should_regenerate_marked_file_on_change
        write_book_yml(book: { 'main_title' => 'A' })
        Writer.write_root_config!
        write_book_yml(book: { 'main_title' => 'B' })

        Writer.write_root_config!

        assert_match(/title: 'B',/, File.read('vivliostyle.config.js'))
        refute_path_exists('vivliostyle.config.js.bak')
      end

      # マーカー無し既存（旧 scaffold or 手編集）は .bak へ退避してから生成する
      def test_should_backup_unmarked_file_once
        write_book_yml(book: { 'main_title' => 'T' })
        legacy = "// 著者が手で書いた古い config\nconst x = 1;\n"
        File.write('vivliostyle.config.js', legacy)

        Writer.write_root_config!

        assert_equal legacy, File.read('vivliostyle.config.js.bak')
        assert_includes File.read('vivliostyle.config.js'), Writer::ROOT_CONFIG_MARKER
      end

      # .bak が既に在れば退避しない（初回退避を保護）
      def test_should_not_overwrite_existing_bak
        write_book_yml(book: { 'main_title' => 'T' })
        File.write('vivliostyle.config.js', "// 手編集\n")
        File.write('vivliostyle.config.js.bak', "// 最初の退避\n")

        Writer.write_root_config!

        assert_equal "// 最初の退避\n", File.read('vivliostyle.config.js.bak')
      end
    end
  end
end
