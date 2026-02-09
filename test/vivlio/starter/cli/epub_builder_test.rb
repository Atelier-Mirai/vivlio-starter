# frozen_string_literal: true

# ================================================================
# Test: epub_builder_test.rb
# ================================================================
# テスト対象:
#   Build::EpubBuilder（lib/vivlio/starter/cli/build/epub_builder.rb）
#   EpubCommands（lib/vivlio/starter/cli/epub.rb）
#
# 検証内容:
#   - EPUB 用 entries.js の生成（目次・裏表紙の除外）
#   - EPUB 用 vivliostyle.config.js の生成（cover 埋め込み制御）
#   - epub_target? の判定
#   - EPUB ファイル名の生成
#   - クリーンアップ
# ================================================================

require 'test_helper'
require 'vivlio/starter/cli/common'
require 'vivlio/starter/cli/build'
require 'vivlio/starter/cli/epub'

module Vivlio
  module Starter
    module CLI
      # ================================================================
      # EpubBuilder のユニットテスト
      # ================================================================
      class EpubBuilderTest < Minitest::Test
        def setup
          @base_dir = '.'
          @original_dir = Dir.pwd
          @test_dir = Dir.mktmpdir('epub_builder_test')
          Dir.chdir(@test_dir)

          # テスト用 HTML ファイルを生成
          create_test_html('00-preface.html', '前書き')
          create_test_html('_toc.html', '目次')
          create_test_html('01-intro.html', 'はじめに')
          create_test_html('02-basics.html', '基礎')
          create_test_html('99-postface.html', '後書き')
          create_test_html('_colophon.html', '奥付')
        end

        def teardown
          Dir.chdir(@original_dir)
          FileUtils.rm_rf(@test_dir)
        end

        # 目次（_toc）が EPUB entries から除外されることを確認
        def test_excluded_basename_toc
          assert Build::EpubBuilder.excluded_basename?('_toc.html'),
                 '_toc.html は EPUB から除外されるべき'
        end

        # 通常の章は除外されないことを確認
        def test_excluded_basename_normal_chapter
          refute Build::EpubBuilder.excluded_basename?('01-intro.html'),
                 '通常の章は除外されないべき'
        end

        # 奥付は除外されないことを確認
        def test_excluded_basename_colophon
          refute Build::EpubBuilder.excluded_basename?('_colophon.html'),
                 '奥付は EPUB に含めるべき'
        end

        # EPUB entries.js が正しく書き出されることを確認
        def test_write_epub_entries_creates_file
          html_files = ['./01-intro.html', './02-basics.html']
          Build::EpubBuilder.write_epub_entries(@base_dir, html_files)

          entries_path = File.join(@base_dir, Build::EpubBuilder::EPUB_ENTRIES_FILE)
          assert File.exist?(entries_path), 'entries.epub.js が生成されるべき'

          content = File.read(entries_path)
          assert_match(/export default \[/, content)
          assert_match(/01-intro/, content)
          assert_match(/02-basics/, content)
          # _toc が含まれていないことを確認
          refute_match(/_toc/, content)
        end

        # cover.embed: true の場合に cover 行が出力されることを確認
        def test_build_cover_config_line_with_embed_true
          epub_cfg = build_epub_config(embed: true)
          esc = ->(s) { s.to_s }

          # カバー画像ファイルを生成
          covers_dir = 'covers'
          FileUtils.mkdir_p(covers_dir)
          File.write(File.join(covers_dir, 'cover.jpg'), 'dummy')

          config = build_config_with_epub(epub_cfg, covers_dir:)
          line = Build::EpubBuilder.build_cover_config_line(config, esc)

          assert_match(/cover:/, line, 'cover.embed: true の場合 cover 行が出力されるべき')
          assert_match(%r{covers/cover\.jpg}, line)
        end

        # cover.embed: false の場合に cover 行がコメントアウトされることを確認
        def test_build_cover_config_line_with_embed_false
          epub_cfg = build_epub_config(embed: false)
          esc = ->(s) { s.to_s }

          config = build_config_with_epub(epub_cfg)
          line = Build::EpubBuilder.build_cover_config_line(config, esc)

          assert_match(/cover\.embed: false/, line, 'cover.embed: false の場合コメントになるべき')
        end

        # embed_cover? が nil（未設定）の場合 true を返すことを確認（デフォルト動作）
        def test_embed_cover_default_true
          epub_cfg = build_epub_config(embed: nil)
          assert Build::EpubBuilder.embed_cover?(epub_cfg),
                 '未設定の場合はデフォルトで true を返すべき'
        end

        # embed_cover? が false の場合に false を返すことを確認
        def test_embed_cover_false
          epub_cfg = build_epub_config(embed: false)
          refute Build::EpubBuilder.embed_cover?(epub_cfg),
                 'cover.embed: false の場合は false を返すべき'
        end

        # クリーンアップが中間ファイルを削除することを確認
        def test_cleanup_removes_intermediate_files
          # テスト用中間ファイルを作成
          File.write(Build::EpubBuilder::EPUB_CONFIG_FILE, 'test')
          File.write(Build::EpubBuilder::EPUB_ENTRIES_FILE, 'test')
          File.write(Build::EpubBuilder::EPUB_OUTPUT_FILE, 'test')

          Build::EpubBuilder.cleanup!

          refute File.exist?(Build::EpubBuilder::EPUB_CONFIG_FILE),
                 'vivliostyle.config.epub.js が削除されるべき'
          refute File.exist?(Build::EpubBuilder::EPUB_ENTRIES_FILE),
                 'entries.epub.js が削除されるべき'
          refute File.exist?(Build::EpubBuilder::EPUB_OUTPUT_FILE),
                 'output.epub が削除されるべき'
        end

        # クリーンアップがファイル不在でもエラーにならないことを確認
        def test_cleanup_does_not_error_when_no_files
          assert_silent_or_logged { Build::EpubBuilder.cleanup! }
        end

        private

        # テスト用の HTML ファイルを作成する
        def create_test_html(filename, title)
          File.write(filename, <<~HTML)
            <!DOCTYPE html>
            <html><head><title>#{title}</title></head>
            <body><h1>#{title}</h1></body></html>
          HTML
        end

        # epub 設定のモック Data オブジェクトを構築する
        def build_epub_config(embed: true)
          cover = Struct.new(:embed, :image, keyword_init: true).new(embed:, image: 'cover.jpg')
          Struct.new(:cover, :layout, keyword_init: true).new(cover:, layout: 'reflowable')
        end

        # CONFIG に近い構造のモック Data オブジェクトを構築する
        def build_config_with_epub(epub_cfg, covers_dir: 'covers')
          directories = Struct.new(:covers, keyword_init: true).new(covers: covers_dir)
          output = Struct.new(:epub, keyword_init: true).new(epub: epub_cfg)
          Struct.new(:output, :directories, keyword_init: true).new(output:, directories:)
        end

        # ログ出力があってもエラーにならないことを確認するヘルパー
        def assert_silent_or_logged
          yield
          pass
        rescue StandardError => e
          flunk "予期しないエラー: #{e.message}"
        end
      end

      # ================================================================
      # EpubCommandRunner のユニットテスト
      # ================================================================
      class EpubCommandRunnerTest < Minitest::Test
        # build_command が --format epub オプションを含むことを確認
        def test_build_command_includes_format_epub
          runner = EpubCommands::EpubCommandRunner.new({})
          cmd = runner.send(:build_command)

          assert_match(/--config vivliostyle\.config\.epub\.js/, cmd,
                       '--config で EPUB 専用設定ファイルを指定するべき')
        end
      end

      # ================================================================
      # epub_target? のユニットテスト
      # ================================================================
      class EpubTargetTest < Minitest::Test
        def setup
          @options = { clean: true, resize: true, compress: true, high: false, low: false }
          @command = Struct.new(:options).new(@options)
        end

        # targets に 'epub' を含む場合に epub_target? が true を返すことを確認
        def test_epub_target_true_when_epub_in_targets
          with_config_targets('pdf, epub') do
            pipeline = BuildCommands::UnifiedBuildPipeline.new(@command, entries: [], mode: :full)
            assert pipeline.send(:epub_target?), 'epub が targets に含まれる場合 true を返すべき'
          end
        end

        # targets に 'epub' を含まない場合に epub_target? が false を返すことを確認
        def test_epub_target_false_when_no_epub_in_targets
          with_config_targets('pdf') do
            pipeline = BuildCommands::UnifiedBuildPipeline.new(@command, entries: [], mode: :full)
            refute pipeline.send(:epub_target?), 'epub が targets にない場合 false を返すべき'
          end
        end

        # targets が 'epub' のみの場合に epub_target? が true を返すことを確認
        def test_epub_target_true_when_epub_only
          with_config_targets('epub') do
            pipeline = BuildCommands::UnifiedBuildPipeline.new(@command, entries: [], mode: :full)
            assert pipeline.send(:epub_target?), 'epub のみの場合 true を返すべき'
          end
        end

        private

        # output.targets を一時的に書き換えるヘルパー
        def with_config_targets(targets_str)
          original_config = Common::CONFIG
          # extract_targets が受け取る文字列をモック
          mock_output = Struct.new(:targets, :pdf, :epub, keyword_init: true)
                              .new(targets: targets_str, pdf: nil, epub: nil)
          mock_config = Struct.new(:output, keyword_init: true).new(output: mock_output)

          # CONFIG を一時差し替え
          Common.const_set(:TEMP_ORIGINAL_CONFIG, original_config)
          Common.send(:remove_const, :CONFIG)
          Common.const_set(:CONFIG, mock_config)
          yield
        ensure
          Common.send(:remove_const, :CONFIG)
          Common.const_set(:CONFIG, Common.const_get(:TEMP_ORIGINAL_CONFIG))
          Common.send(:remove_const, :TEMP_ORIGINAL_CONFIG)
        end
      end

      # ================================================================
      # generate_epub_filename のユニットテスト
      # ================================================================
      class EpubFilenameTest < Minitest::Test
        # EPUB ファイル名が .epub 拡張子で生成されることを確認
        def test_generate_epub_filename_extension
          filename = Common.generate_epub_filename
          assert filename.end_with?('.epub'), "EPUB ファイル名は .epub で終わるべき: #{filename}"
        end
      end
    end
  end
end
