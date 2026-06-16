# frozen_string_literal: true

# ================================================================
# Test: epub_builder_test.rb
# ================================================================
# テスト対象:
#   Build::EpubBuilder（lib/vivlio_starter/cli/build/epub_builder.rb）
#   EpubCommands（lib/vivlio_starter/cli/epub.rb）
#
# 検証内容:
#   - EPUB 用 entries.js の生成（目次・裏表紙の除外）
#   - EPUB 用 vivliostyle.config.js の生成（cover 埋め込み制御）
#   - epub_target? の判定
#   - EPUB ファイル名の生成
#   - クリーンアップ
# ================================================================

require 'test_helper'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/build'
require 'vivlio_starter/cli/epub'

module VivlioStarter
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

      # 本文章（番号 1..89）の h1（扉絵）・h2（節絵）が合成画像 <img> へ置換され、
      # 見出しテキストが alt に格納されることを確認。render は librsvg/ImageMagick と実画像に
      # 依存するため、ここではスタブして EpubBuilder の注入ロジックを検証する。
      def test_inject_heading_images_rewrites_chapter_and_section_headings
        File.write('10-spring.html', <<~HTML)
          <!DOCTYPE html><html><head><title>春</title></head><body>
          <h1 data-chapter-number-display="第1章" data-chapter-title="春のお花見">
            <span class="chapter-number">第1章</span><span class="chapter-title">春のお花見</span>
          </h1>
          <article class="section-topic">
            <h2 data-section-number-display="1-1" data-section-title="導入">
              <span class="section-number">1-1</span><span class="section-title">導入</span>
            </h2>
          </article>
          </body></html>
        HTML

        context = {
          frontispiece: 'dummy_portrait.webp',
          ornament: 'dummy_landscape.webp',
          font_family: "'Zen Kaku Gothic New', sans-serif",
          number_color: '#f0a000'
        }

        Build::HeadingImageComposer.stub(:render, 'FAKEJPEGBYTES') do
          Build::EpubBuilder.inject_heading_images_into_file!('10-spring.html', context)
        end

        html = File.read('10-spring.html')
        # h1 に EPUB クラスと合成画像 <img>（JPEG）が入る
        assert_match(%r{<h1[^>]*class="[^"]*vs-image-heading-epub}, html)
        assert_includes html, 'class="vs-image-heading-img"'
        # 見出しテキストは alt に格納（目次は <title> 由来・clip による隠し span は廃止）
        assert_includes html, 'alt="第1章 春のお花見"'
        refute_includes html, 'vs-visually-hidden', '隠し span（clip）は使わない'
        # 節絵: 親 article に EPUB 用クラス、h2 に画像（alt に節番号＋タイトル）
        assert_includes html, 'vs-section-topic-epub'
        assert_includes html, 'alt="1-1 導入"'
        # 合成画像が images/headings/ に JPEG として書き出される
        assert Dir.glob('images/headings/frontispiece-*.jpg').any?, '扉絵 JPEG が書き出されるべき'
        assert Dir.glob('images/headings/ornament-*.jpg').any?, '節絵 JPEG が書き出されるべき'
      end

      # 付録（番号 90..98）には扉絵/節絵を注入せず simple 版にすることを確認（PDF と整合）
      def test_inject_heading_images_skips_appendix_chapters
        File.write('94-sample.html', <<~HTML)
          <!DOCTYPE html><html><head><title>付録</title></head><body>
          <h1 data-chapter-number-display="付録 A" data-chapter-title="サンプル">
            <span class="chapter-title">サンプル</span>
          </h1>
          </body></html>
        HTML

        context = { frontispiece: 'x.webp', ornament: nil, font_family: 'sans-serif', number_color: '#333' }

        Build::HeadingImageComposer.stub(:render, 'FAKEJPEGBYTES') do
          Build::EpubBuilder.inject_heading_images_into_file!('94-sample.html', context)
        end

        html = File.read('94-sample.html')
        refute_includes html, 'vs-image-heading-epub', '付録は simple 版（画像注入しない）'
      end

      # 番号を持たない見出し（前付など）には扉絵を注入しないことを確認
      def test_inject_heading_images_skips_headings_without_number
        File.write('00-preface.html', <<~HTML)
          <!DOCTYPE html><html><head><title>前書き</title></head><body>
          <h1><span class="chapter-title">前書き</span></h1>
          </body></html>
        HTML

        context = { frontispiece: 'x.webp', ornament: nil, font_family: 'sans-serif', number_color: '#333' }

        Build::HeadingImageComposer.stub(:render, 'FAKEJPEGBYTES') do
          Build::EpubBuilder.inject_heading_images_into_file!('00-preface.html', context)
        end

        html = File.read('00-preface.html')
        refute_includes html, 'vs-image-heading-epub', '番号なし見出し（前付）には注入しない'
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
        File.write(File.join(covers_dir, 'cover_light.jpg'), 'dummy')

        config = build_config_with_epub(epub_cfg, covers_dir:)
        Common.stub(:epub_embed?, true) do
          Common.stub(:cover_theme, 'light') do
            line = Build::EpubBuilder.build_cover_config_line(config, esc)

            assert_match(/cover:/, line, 'cover.embed: true の場合 cover 行が出力されるべき')
            assert_match(%r{covers/cover_light\.jpg}, line)
          end
        end
      end

      # cover.embed: false の場合に cover 行がコメントアウトされることを確認
      def test_build_cover_config_line_with_embed_false
        epub_cfg = build_epub_config(embed: false)
        esc = ->(s) { s.to_s }

        config = build_config_with_epub(epub_cfg)
        Common.stub(:epub_embed?, false) do
          line = Build::EpubBuilder.build_cover_config_line(config, esc)

          assert_match(/epub\.embed: false/, line, 'cover.embed: false の場合コメントになるべき')
        end
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
