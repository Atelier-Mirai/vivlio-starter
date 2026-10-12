# frozen_string_literal: true

# ================================================================
# Test: cover_test.rb
# ================================================================
# テスト対象:
#   CoverCommands モジュール（lib/vivlio_starter/cli/cover.rb）
#
# 検証内容:
#   - マスターファイル存在チェック
#   - カバー画像生成（RGB/CMYK 変換）
#   - 出力形式ごとのカバー設定
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'yaml'
require 'samovar'
# PDF 検査は MIT の pdf-reader を使う（AGPL の HexaPDF には依存しない）。
require 'pdf/reader'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/cover'
require 'vivlio_starter/cli/create'
require 'vivlio_starter/cli/samovar/cover_command'

module VivlioStarter
  module CLI
    # 3 つのテストクラスが共有する画像の用意。ImageMagick があれば指定の寸法の白い PNG を、
    # 無ければ 1×1 の最小の PNG を書く。
    module CoverTestImages
      def create_dummy_png(path, width: 100, height: 100)
        if (convert_cmd = imagemagick_convert_command)
          system(*convert_cmd, '-size', "#{width}x#{height}", 'xc:white', path, out: File::NULL, err: File::NULL)
        else
          File.binwrite(path, "\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x02\x00\x00\x00" \
                              "\x90wS\xde\x00\x00\x00\nIDATx\x9cc\xf8\x00\x00\x00\x01\x00\x01\x00\x00\x00\x00IEND\xaeB`\x82")
        end
      end

      def imagemagick_available? = !imagemagick_convert_command.nil?

      # magick（ImageMagick 7+）を優先する。PATH を直接探すのは、外部コマンドを起動して
      # 確かめるとハングする環境があったため。
      def imagemagick_convert_command
        return ['magick'] if command_in_path?('magick')
        return ['convert'] if command_in_path?('convert')

        nil
      end

      def command_in_path?(command)
        ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).any? do |dir|
          path = File.join(dir, command)
          File.executable?(path) && !File.directory?(path)
        end
      end
    end

    # CoverCommands のユニットテスト
    class CoverCommandsTest < Minitest::Test
      include CoverTestImages

      # setup_config が temp book.yml で CONFIG を上書きするため、テスト後に
      # プロジェクトルートの canonical な book.yml で復旧する（後続テストファイルへの
      # CONFIG 汚染＝metadata / spellcheck キー欠落の波及を防ぐ。CoverConfigTest と同方針）。
      def teardown
        Common.reload_configuration!(silent: true) if File.file?('config/book.yml')
      end

      # マスターファイルが存在しない場合、false を返すことを確認
      def test_check_master_files_returns_false_when_missing
        within_temp_dir do
          setup_config
          covers_dir = 'covers'
          FileUtils.mkdir_p(covers_dir)

          result = CoverCommands.check_master_files(covers_dir)
          refute result, 'マスターファイルが存在しない場合はfalseを返すべきです'
        end
      end

      # マスターファイルが存在する場合、trueを返すことを確認
      def test_check_master_files_returns_true_when_present
        within_temp_dir do
          setup_config
          covers_dir = 'covers'
          FileUtils.mkdir_p(covers_dir)
          create_dummy_master_files(covers_dir)

          result = CoverCommands.check_master_files(covers_dir)
          assert result, 'マスターファイルが存在する場合はtrueを返すべきです'
        end
      end

      # 表紙マスターのみが存在する場合、trueを返すことを確認
      def test_check_master_files_with_front_only
        within_temp_dir do
          setup_config
          covers_dir = 'covers'
          FileUtils.mkdir_p(covers_dir)
          create_dummy_master_files(covers_dir, back: false)

          result = CoverCommands.check_master_files(covers_dir)
          assert result, '表紙マスターのみでもtrueを返すべきです'
        end
      end

      # ページサイズ判定（B5）のテスト
      def test_detect_page_size_b5
        size = CoverCommands.detect_page_size('b5_standard')
        assert_equal :b5, size, 'b5_standardからB5を判定すべきです'
      end

      # ページサイズ判定（A5）のテスト
      def test_detect_page_size_a5
        size = CoverCommands.detect_page_size('a5_standard')
        assert_equal :a5, size, 'a5_standardからA5を判定すべきです'
      end

      # ページサイズ判定（A4）のテスト
      def test_detect_page_size_a4
        size = CoverCommands.detect_page_size('a4_standard')
        assert_equal :a4, size, 'a4_standardからA4を判定すべきです'
      end

      # ページサイズ判定（デフォルト）のテスト
      def test_detect_page_size_default
        size = CoverCommands.detect_page_size('unknown_preset')
        assert_equal :b5, size, '不明なプリセットではデフォルトでB5を返すべきです'
      end

      # RGB PDF生成のテスト（ImageMagickが必要）
      def test_generate_rgb_pdf_single
        skip 'ImageMagickが必要です' unless imagemagick_available?

        within_temp_dir do
          setup_config
          covers_dir = 'covers'
          FileUtils.mkdir_p(covers_dir)
          input_png = File.join(covers_dir, 'frontcover_master.png')
          output_pdf = File.join(covers_dir, 'frontcover_rgb.pdf')

          create_dummy_png(input_png, width: 2894, height: 4092)

          size = CoverCommands::SIZES[:a4]
          CoverCommands.generate_rgb_pdf_single(input_png, output_pdf, size)

          assert File.exist?(output_pdf), 'RGB PDFが生成されるべきです'
          assert File.size(output_pdf).positive?, 'PDF にデータが書き込まれているべきです'
        end
      end

      # EPUB用JPEG生成のテスト（ImageMagickが必要）
      def test_generate_epub_cover
        skip 'ImageMagickが必要です' unless imagemagick_available?

        within_temp_dir do
          setup_config
          covers_dir = 'covers'
          FileUtils.mkdir_p(covers_dir)
          input_png = File.join(covers_dir, 'frontcover_master.png')

          create_dummy_png(input_png, width: 2894, height: 4092)

          CoverCommands.generate!(targets: ['epub'])

          # 生成物は生成キャッシュに出る（generated-assets 移設仕様 §2）
          output_jpg = File.join(Common.cover_cache_dir, 'cover_master.jpg')
          assert File.exist?(output_jpg), 'EPUB用JPEGが生成されるべきです'
          assert File.size(output_jpg).positive?, 'JPEGにデータが書き込まれているべきです'
        end
      end

      # vs cover は引数を取らず、book.yml の判型（b5_standard）と targets に従って作る
      def test_execute_generates_covers_for_the_book_page_size_and_targets
        skip 'ImageMagickが必要です' unless imagemagick_available?

        within_temp_dir do
          setup_config(targets: 'pdf, epub')
          covers_dir = 'covers'
          FileUtils.mkdir_p(covers_dir)
          create_dummy_master_files(covers_dir)

          assert_equal 0, SamovarCommands::CoverCommand.new([]).call

          # 生成物は生成キャッシュに出る（generated-assets 移設仕様 §2）
          %w[frontcover_master_b5_rgb.pdf backcover_master_b5_rgb.pdf cover_master.jpg].each do |name|
            assert File.exist?(File.join(Common.cover_cache_dir, name)), "#{name} が生成されるべきです"
          end
        end
      end

      # --- 電子書籍用の表紙の JPEG（ebook-cover-jpeg-spec.md）---

      # KDP の理想の寸法・品質 95 で書き、KDP へ上げる成果品としてプロジェクトの直下へも写す。
      def test_should_write_the_ebook_cover_in_kdp_size_and_publish_it_at_the_root
        skip 'ImageMagickが必要です' unless imagemagick_available?

        within_temp_dir do
          setup_config
          FileUtils.mkdir_p(Common.cover_cache_dir)
          create_dummy_png('front.png', width: 2894, height: 4092) # A4（左右を切り落とす比）
          output = File.join(Common.cover_cache_dir, 'cover_master.jpg')

          assert CoverCommands.write_ebook_cover!('front.png', output)

          assert_equal '1600x2560 95', jpeg_facts(output, '%wx%h %Q')
          published = Common.generate_cover_output_filename('front', ext: 'jpg')
          assert_equal Common.generate_cover_output_filename('front').sub(/\.pdf\z/, '.jpg'), published,
                       '入稿用の表紙の PDF と同じ名前で、拡張子だけ違う'
          assert_equal File.binread(output), File.binread(published), 'キャッシュ側（EPUB へ入れる元）と同じもの'
        end
      end

      # Display P3 などの色の情報は sRGB に直す。
      def test_should_convert_the_ebook_cover_to_srgb
        skip 'ImageMagickが必要です' unless imagemagick_available?
        skip 'sRGB の色の情報が無い環境では確かめられない' unless CoverCommands.srgb_profile_path
        display_p3 = '/System/Library/ColorSync/Profiles/Display P3.icc'
        skip 'Display P3 の色の情報が無い環境では確かめられない' unless File.file?(display_p3)

        within_temp_dir do
          setup_config
          FileUtils.mkdir_p(Common.cover_cache_dir)
          system(*CoverCommands.imagemagick_convert_command, '-size', '320x512', 'xc:rgb(200,100,50)', '-profile', display_p3, 'p3.png')
          output = File.join(Common.cover_cache_dir, 'cover_master.jpg')

          CoverCommands.write_ebook_cover!('p3.png', output)

          assert_match(/sRGB/, jpeg_facts(output, '%[profile:icc]'))
        end
      end

      # 電子書籍のターゲットがあるときだけ作る。Kindle だけのビルドでも作り、PDF だけなら作らない。
      def test_should_make_the_ebook_cover_only_for_ebook_targets
        skip 'ImageMagickが必要です' unless imagemagick_available?

        { 'kindle' => true, 'epub' => true, 'pdf' => false }.each do |targets, expected|
          within_temp_dir do
            setup_config(targets:)
            create_dummy_master_files('covers')

            CoverCommands.ensure_cover_files_for_build!

            assert_equal expected, File.exist?(File.join(Common.cover_cache_dir, 'cover_master.jpg')), "targets: #{targets}"
            assert_equal expected, File.exist?(Common.generate_cover_output_filename('front', ext: 'jpg')), "targets: #{targets}"
          end
        end
      end

      # 表と裏はそれぞれ元の画像を決める。表が SVG・裏が PNG でも、裏の入稿用は PNG の経路
      # （塗り足し・トンボ）で作る。以前は SVG の処理が PNG を素の PDF に変えるだけで、
      # 塗り足しもトンボも無い PDF を入稿用として直下へ複製していた。
      def test_should_make_the_png_side_print_ready_when_the_other_side_is_svg
        skip 'ImageMagick と rsvg-convert が必要です' unless imagemagick_available? && command_in_path?('rsvg-convert')

        within_temp_dir do
          setup_config(targets: 'print_pdf', theme: 'mix')
          FileUtils.mkdir_p('covers')
          File.write('covers/frontcover_mix.svg', <<~SVG)
            <svg xmlns="http://www.w3.org/2000/svg" width="182mm" height="257mm" viewBox="0 0 182 257">
              <rect width="182" height="257" fill="#336699"/>
            </svg>
          SVG
          create_dummy_png('covers/backcover_mix.png', width: 2508, height: 3541)

          CoverCommands.generate!

          back = ::PDF::Reader.new(File.join(Common.cover_cache_dir, 'backcover_mix_b5_cmyk.pdf')).pages.first
          margin_pt = (3 + CoverCommands::CROP_MARK_OFFSET_MM) * Units::PT_PER_MM
          assert_in_delta margin_pt, back.attributes[:TrimBox][0].to_f, 0.5, '裏表紙にも塗り足しとトンボ代があるべきです'
          assert_match(%r{/Fx\d+ Do}, back.raw_content, '裏表紙にもトンボが重ねられているべきです')
        end
      end

      # SVG の表紙（light・dark・著者の SVG）も、PNG の表紙と同じ寸法・品質になる。
      # 以前は判型の寸法を 150dpi で焼いていて、A4 で 1,240 × 1,754 px だった。
      def test_should_write_the_same_ebook_cover_from_an_svg
        skip 'ImageMagickが必要です' unless imagemagick_available?

        within_temp_dir do
          setup_config
          FileUtils.mkdir_p(Common.cover_cache_dir)
          File.write('front.svg', <<~SVG)
            <svg xmlns="http://www.w3.org/2000/svg" width="210mm" height="297mm" viewBox="0 0 210 297">
              <rect width="210" height="297" fill="#336699"/>
            </svg>
          SVG
          output = File.join(Common.cover_cache_dir, 'cover_light.jpg')

          assert CoverCommands::SvgCover.write_ebook_cover('front.svg', output, :a4)

          assert_equal '1600x2560 95', jpeg_facts(output, '%wx%h %Q')
          assert File.exist?(Common.generate_cover_output_filename('front', ext: 'jpg'))
        end
      end

      private

      def jpeg_facts(path, format)
        identify = CoverCommands.imagemagick_convert_command == ['magick'] ? %w[magick identify] : %w[identify]
        IO.popen([*identify, '-format', format, path], &:read)
      end

      # 一時ディレクトリ配下でテストを実行する
      # テスト実行後に自動的にクリーンアップされる安全な環境を提供
      def within_temp_dir
        Dir.mktmpdir do |dir|
          Dir.chdir(dir) { yield dir }
        end
      end

      # テスト用の設定ファイルを生成
      # カバー設定、ページプリセット、置換リストなどの必要な設定を作成
      def setup_config(targets: 'pdf', theme: 'master')
        FileUtils.mkdir_p('config')
        config = {
          'directories' => {
            'covers' => 'covers'
          },
          'output' => {
            'cover' => theme,
            'targets' => targets
          },
          'page' => {
            'use' => 'b5_standard'
          }
        }
        File.write('config/book.yml', config.to_yaml)
        File.write('config/page_presets.yml', DUMMY_PAGE_PRESETS.to_yaml)
        # reload_configuration! の ensure_required_yaml_files! が要求する必須ファイルを揃える
        File.write('config/catalog.yml',
                   { 'PREFACE' => [], 'CHAPTERS' => [], 'APPENDICES' => [], 'POSTFACE' => [] }.to_yaml)

        # 書き込んだ temp book.yml を CONFIG へ反映する。これを怠ると Samovar コマンド
        # 経路（execute_for_size 等）が起動時ロードの実プロジェクト CONFIG を参照し、
        # theme が実プロジェクト側の値になって cover:master 前提のテストが崩れる。
        Common.reload_configuration!(silent: true)
      end

      # テスト用のマスター画像を配置
      def create_dummy_master_files(covers_dir, front: true, back: true)
        copy_fixture_master_files(covers_dir, front: front, back: back)
      end

      # フィクスチャのマスター画像をコピーまたはスタブを作成
      # 実際のフィクスチャが存在しない場合はダミーPNGを生成
      def copy_fixture_master_files(covers_dir, front: true, back: true)
        FileUtils.mkdir_p(covers_dir)

        if front
          copy_or_stub_fixture(FRONT_MASTER_FIXTURE, File.join(covers_dir, 'frontcover_master.png'))
        end

        if back
          copy_or_stub_fixture(BACK_MASTER_FIXTURE, File.join(covers_dir, 'backcover_master.png'))
        end
      end

      # フィクスチャファイルをコピーまたはスタブを作成
      # ソースファイルが存在する場合はコピー、存在しない場合はダミーを生成
      def copy_or_stub_fixture(source, destination)
        if File.exist?(source)
          FileUtils.cp(source, destination)
        else
          create_dummy_png(destination, width: 2894, height: 4092)
        end
      end

      DUMMY_PAGE_PRESETS = {
        'b5_standard' => {
          'size' => 'B5',
          'base_font_size' => '10.5pt',
          'base_line_height' => '17pt',
          'margin_top' => '20mm',
          'margin_bottom' => '20mm',
          'margin_inner' => '20mm',
          'margin_outer' => '20mm'
        }
      }.freeze

      PROJECT_ROOT = File.expand_path('../../../../..', __dir__)
      FIXTURE_COVERS_DIR = File.join(PROJECT_ROOT, 'covers')
      FRONT_MASTER_FIXTURE = File.join(FIXTURE_COVERS_DIR, 'frontcover_master.png')
      BACK_MASTER_FIXTURE = File.join(FIXTURE_COVERS_DIR, 'backcover_master.png')
    end

    # Common::Config カバー設定機能のテスト
    class CoverConfigTest < Minitest::Test
      include CoverTestImages

      def setup
        @temp_dir = Dir.mktmpdir
        @original_dir = Dir.pwd
        Dir.chdir(@temp_dir)
        setup_test_environment
      end

      def teardown
        Dir.chdir(@original_dir)
        FileUtils.rm_rf(@temp_dir)
        # 本テストは Common.reload_configuration! を最小 book.yml で呼ぶため
        # CONFIG 定数が汚染される。プロジェクトルート配下の canonical な
        # book.yml で復旧しないと、後続の他テスト（LintCommandsTest 等）に
        # spellcheck / metadata キー欠落が波及する。
        Common.reload_configuration!(silent: true) if File.file?('config/book.yml')
      end

      # lightテーマ設定が正しく読み込めることを確認
      def test_should_read_light_theme_setting
        config_content = {
          'output' => {
            'cover' => 'light',
            'pdf' => { 'combined' => true },
            'epub' => { 'embed' => true }
          }
        }
        setup_config_file(config_content)
        
        # 設定を再読み込み
        Common.reload_configuration!
        
        assert_equal 'light', Common.cover_theme
        assert Common.pdf_combined?
        assert Common.epub_embed?
      end

      # darkテーマ設定が正しく読み込めることを確認
      def test_should_read_dark_theme_setting
        config_content = {
          'output' => {
            'cover' => 'dark',
            'pdf' => { 'combined' => false },
            'epub' => { 'embed' => false }
          }
        }
        setup_config_file(config_content)
        
        Common.reload_configuration!
        
        assert_equal 'dark', Common.cover_theme
        refute Common.pdf_combined?
        refute Common.epub_embed?
      end

      # カスタムテーマ設定が正しく読み込めることを確認
      def test_should_read_custom_theme_setting
        config_content = {
          'output' => {
            'cover' => 'my_custom_theme',
            'pdf' => { 'combined' => true },
            'epub' => { 'embed' => true }
          }
        }
        setup_config_file(config_content)
        
        Common.reload_configuration!
        
        assert_equal 'my_custom_theme', Common.cover_theme
        assert Common.pdf_combined?
        assert Common.epub_embed?
      end

      # カバー設定バリデーション：lightテーマが有効であることを確認
      def test_should_validate_light_theme_successfully
        setup_basic_config('light')
        Common.reload_configuration!
        
        result = Common.validate_cover_settings
        assert result, 'lightテーマは有効であるべきです'
      end

      # カバー設定バリデーション：darkテーマが有効であることを確認
      def test_should_validate_dark_theme_successfully
        setup_basic_config('dark')
        Common.reload_configuration!
        
        result = Common.validate_cover_settings
        assert result, 'darkテーマは有効であるべきです'
      end

      # カバー設定バリデーション：カスタムテーマ（PNGファイルあり）が有効であることを確認
      def test_should_validate_custom_theme_with_png_files
        setup_basic_config('my_custom')
        create_custom_theme_files('my_custom')
        Common.reload_configuration!
        
        result = Common.validate_cover_settings
        assert result, 'PNGファイルが存在するカスタムテーマは有効であるべきです'
      end

      # カバー設定バリデーション：カスタムテーマは SVG だけでも有効（改善案.md #65）
      def test_should_validate_custom_theme_with_svg_files
        setup_basic_config('floral')
        File.write('covers/frontcover_floral.svg', '<svg xmlns="http://www.w3.org/2000/svg"/>')
        File.write('covers/backcover_floral.svg', '<svg xmlns="http://www.w3.org/2000/svg"/>')
        Common.reload_configuration!

        assert Common.validate_cover_settings, 'SVG を置いたカスタムテーマは有効であるべきです'
      end

      # 表紙の元は面ごとに PNG → 著者の SVG → 同梱テンプレートの順で決まる。master は PNG だけ（改善案.md #65）
      def test_should_resolve_each_side_png_then_svg_then_bundled
        setup_basic_config('floral')
        File.write('covers/frontcover_floral.svg', '<svg xmlns="http://www.w3.org/2000/svg"/>')
        FileUtils.mkdir_p('covers/bundled')
        File.write('covers/bundled/backcover.svg', '<svg xmlns="http://www.w3.org/2000/svg"/>')

        assert_pattern { CoverCommands.resolve_source('front', 'floral') => { type: :svg, bundled: false } }
        back = Common.stub(:log_warn, nil) { CoverCommands.resolve_source('back', 'floral') }
        assert_pattern { back => { type: :svg, bundled: true } }
        assert_equal({ type: :missing }, CoverCommands.resolve_source('front', 'master'))

        create_custom_theme_files('floral')
        assert_equal :png, CoverCommands.resolve_source('front', 'floral')[:type],
                     'PNG があれば PNG の処理（PDF/X-1a・塗り足し）へ回す'
      end

      # カバー設定バリデーション：カスタムテーマ（PNGファイルなし）が無効であることを確認
      def test_should_fail_validation_for_custom_theme_without_png_files
        setup_basic_config('my_custom')
        Common.reload_configuration!
        
        result = Common.validate_cover_settings
        refute result, 'PNGファイルが存在しないカスタムテーマは無効であるべきです'
      end

      # カバー設定バリデーション：不正なテーマ名が無効であることを確認
      def test_should_fail_validation_for_invalid_theme_names
        invalid_names = ['My-Theme', 'my theme', 'MyTheme', '123_theme']
        
        invalid_names.each do |invalid_name|
          setup_basic_config(invalid_name)
          Common.reload_configuration!
          
          result = Common.validate_cover_settings
          refute result, "不正なテーマ名 '#{invalid_name}' は無効であるべきです"
        end
      end

      # カバー設定バリデーション：設定未指定が無効であることを確認
      def test_should_fail_validation_when_cover_setting_missing
        config_content = {
          'output' => {
            'pdf' => { 'combined' => true }
          }
        }
        setup_config_file(config_content)
        Common.reload_configuration!
        
        # output.cover を書かなくても既定の master が使われる（未設定という状態は無い）
        assert_equal 'master', Common.cover_theme

        # master の画像が無いプロジェクトなので、存在チェックで弾かれる
        result = Common.validate_cover_settings
        refute result, 'master 画像が無い場合は無効であるべきです'
      end

      private

      # テスト実行前に必要なディレクトリと設定ファイルを作成
      def setup_test_environment
        FileUtils.mkdir_p('config')
        %w[book catalog page_presets].each do |file|
          File.write("config/#{file}.yml", '{}')
        end
        FileUtils.mkdir_p('covers')
      end

      # 指定された内容でbook.ymlを設定
      def setup_config_file(content)
        File.write('config/book.yml', content.to_yaml)
      end

      # 基本的なカバー設定を作成（テーマ名を指定）
      def setup_basic_config(theme)
        config_content = {
          'output' => {
            'cover' => theme,
            'pdf' => { 'combined' => true },
            'epub' => { 'embed' => true }
          }
        }
        setup_config_file(config_content)
      end

      # カスタムテーマ用のPNGファイルを作成
      # 表紙と裏表紙のPNGファイルを指定されたテーマ名で生成
      def create_custom_theme_files(theme)
        create_dummy_png("covers/frontcover_#{theme}.png", width: 2894, height: 4092)
        create_dummy_png("covers/backcover_#{theme}.png", width: 2894, height: 4092)
      end

    end

    # ================================================================
    # CoverCropMarksTest: 表紙トンボ付与の検証テスト
    # ================================================================
    # 仕様書 cover_crop_marks_bugfix_spec.md の
    # P1・P2・P3 に対応する自動テスト。
    #
    # P1: print_pdf ターゲット時のページサイズ検証
    #     期待値 = 仕上がり + 2 × (bleed_mm + CROP_MARK_OFFSET_MM)
    # P2: pdf ターゲット時のページサイズ検証
    #     期待値 = 仕上がり + 2 × bleed_mm
    # P3: print_pdf ターゲット後のファイル存在確認
    # ================================================================
    class CoverCropMarksTest < Minitest::Test
      include CoverTestImages

      # B5 仕上がりサイズ（mm）
      TRIM_W_MM = 182.0
      TRIM_H_MM = 257.0
      BLEED_MM  = 3.0
      OFFSET_MM = VivlioStarter::CLI::CoverCommands::CROP_MARK_OFFSET_MM

      # P1: トンボ付き PDF のページサイズが正しいことを確認する
      # 期待ページサイズ = 仕上がり + 2 × (bleed + offset)
      def test_should_generate_cmyk_pdf_with_correct_page_size_for_print_pdf
        skip 'ImageMagickが必要です' unless imagemagick_available?

        within_temp_dir do
          setup_config_with_print_pdf
          covers_dir = 'covers'
          FileUtils.mkdir_p(covers_dir)
          input_png = File.join(covers_dir, 'frontcover_master.png')
          output_pdf = File.join(covers_dir, 'frontcover_master_b5_cmyk.pdf')
          create_dummy_png(input_png)

          base_size = CoverCommands::SIZES[:b5]
          CoverCommands.generate_pdfx_single(
            input_png, output_pdf, base_size,
            bleed_mm: BLEED_MM, crop_marks: true
          )

          assert File.exist?(output_pdf), 'トンボ付き CMYK PDF が生成されるべきです'

          # ページサイズ検証
          expected_w_mm = TRIM_W_MM + 2 * (BLEED_MM + OFFSET_MM)
          expected_h_mm = TRIM_H_MM + 2 * (BLEED_MM + OFFSET_MM)

          actual_w_mm, actual_h_mm = pdf_page_size_mm(output_pdf)

          assert_in_delta expected_w_mm, actual_w_mm, 1.0,
            "幅: 期待 #{expected_w_mm}mm、実際 #{actual_w_mm.round(2)}mm"
          assert_in_delta expected_h_mm, actual_h_mm, 1.0,
            "高さ: 期待 #{expected_h_mm}mm、実際 #{actual_h_mm.round(2)}mm"
        end
      end

      # P2: トンボなし PDF のページサイズが塗り足し込みサイズと一致することを確認する
      # 期待ページサイズ = 仕上がり + 2 × bleed
      def test_should_generate_cmyk_pdf_with_bleed_size_for_pdf_target
        skip 'ImageMagickが必要です' unless imagemagick_available?

        within_temp_dir do
          setup_config_with_print_pdf
          covers_dir = 'covers'
          FileUtils.mkdir_p(covers_dir)
          input_png = File.join(covers_dir, 'frontcover_master.png')
          output_pdf = File.join(covers_dir, 'frontcover_master_b5_rgb.pdf')
          create_dummy_png(input_png)

          base_size = CoverCommands::SIZES[:b5]
          CoverCommands.generate_pdfx_single(
            input_png, output_pdf, base_size,
            bleed_mm: BLEED_MM, crop_marks: false
          )

          assert File.exist?(output_pdf), 'トンボなし CMYK PDF が生成されるべきです'

          # ページサイズ検証（塗り足し込みサイズ）
          expected_w_mm = TRIM_W_MM + 2 * BLEED_MM
          expected_h_mm = TRIM_H_MM + 2 * BLEED_MM

          actual_w_mm, actual_h_mm = pdf_page_size_mm(output_pdf)

          assert_in_delta expected_w_mm, actual_w_mm, 1.0,
            "幅: 期待 #{expected_w_mm}mm、実際 #{actual_w_mm.round(2)}mm"
          assert_in_delta expected_h_mm, actual_h_mm, 1.0,
            "高さ: 期待 #{expected_h_mm}mm、実際 #{actual_h_mm.round(2)}mm"
        end
      end

      # P3: print_pdf ターゲット時に表紙・裏表紙 CMYK PDF が生成されることを確認する
      def test_should_generate_both_cover_cmyk_pdfs_for_print_pdf_target
        skip 'ImageMagickが必要です' unless imagemagick_available?

        within_temp_dir do
          setup_config_with_print_pdf
          covers_dir = 'covers'
          FileUtils.mkdir_p(covers_dir)
          create_dummy_master_files(covers_dir)

          CoverCommands.generate!(targets: ['print_pdf'], page_size: :b5)

          # 生成は生成キャッシュ・入稿用の成果品はルート直下へ複製（移設仕様 §2/§3.4）
          assert File.exist?(File.join(Common.cover_cache_dir, 'frontcover_master_b5_cmyk.pdf')),
            '表紙 CMYK PDF が生成されるべきです'
          assert File.exist?(File.join(Common.cover_cache_dir, 'backcover_master_b5_cmyk.pdf')),
            '裏表紙 CMYK PDF が生成されるべきです'
          assert File.exist?(Common.generate_cover_output_filename('front')),
            '表紙 CMYK PDF がルート直下へ成果品として複製されるべきです'
          assert File.exist?(Common.generate_cover_output_filename('back')),
            '裏表紙 CMYK PDF がルート直下へ成果品として複製されるべきです'
        end
      end

      # 判型ごとの画素数は、仕上がりの mm を 350dpi にした値（四捨五入）と一致する。
      # A4 の高さが 4091 px（正しくは 4093 px）で、A4 の表紙が本文より 0.18mm 低かった
      def test_should_match_sizes_to_trim_at_350dpi
        CoverCommands::SIZES.each do |name, size|
          expected = size[:mm].map { (it / Units::MM_PER_INCH * CoverCommands::DPI).round }
          assert_equal expected, [size[:width], size[:height]], "#{name} の画素数"
        end
      end

      # 入稿用の表紙は仕上がりサイズ（SIZES）を generate_pdfx_single へ渡すことを確認する
      # crop_marks: true 時は generate_pdfx_single 内でサイズ拡張が行われる
      def test_should_pass_trim_size_not_bleed_size_to_generate_pdfx_single
        base_size = CoverCommands::SIZES[:b5]
        assert_equal 2508, base_size[:width],  'B5 仕上がり幅は 2508px であるべきです'
        assert_equal 3541, base_size[:height], 'B5 仕上がり高さは 3541px であるべきです'
        assert_equal [182, 257], base_size[:mm], 'B5 仕上がりサイズは 182×257mm であるべきです'
      end

      # CROP_MARK_OFFSET_MM 定数が cover.rb に定義されていることを確認する
      def test_should_have_crop_mark_offset_constant_in_cover_commands
        assert_equal 13.0, CoverCommands::CROP_MARK_OFFSET_MM,
          'CROP_MARK_OFFSET_MM は 13.0mm であるべきです'
      end

      private

      # print_pdf ターゲットを含む設定ファイルを生成する
      def setup_config_with_print_pdf
        FileUtils.mkdir_p('config')
        config = {
          'directories' => { 'covers' => 'covers' },
          'output' => {
            'cover' => 'master',
            'targets' => 'print_pdf',
            'print_pdf' => { 'bleed' => '3mm', 'crop_marks' => true }
          },
          'page' => { 'use' => 'b5_standard' }
        }
        File.write('config/book.yml', config.to_yaml)
        File.write('config/page_presets.yml', CoverCommandsTest::DUMMY_PAGE_PRESETS.to_yaml)
      end

      # マスター PNG を一時ディレクトリに生成する
      def create_dummy_master_files(covers_dir)
        create_dummy_png(File.join(covers_dir, 'frontcover_master.png'))
        create_dummy_png(File.join(covers_dir, 'backcover_master.png'))
      end

      # PDF 先頭ページの仕上がり寸法（mm）を返す（pdf-reader・MIT）
      def pdf_page_size_mm(pdf_path)
        box = ::PDF::Reader.new(pdf_path).pages.first.attributes[:MediaBox]
        w_pt = box[2].to_f - box[0].to_f
        h_pt = box[3].to_f - box[1].to_f
        [w_pt / 72.0 * 25.4, h_pt / 72.0 * 25.4]
      end

      # 一時ディレクトリ内でテストを実行する
      def within_temp_dir
        Dir.mktmpdir do |dir|
          Dir.chdir(dir) { yield dir }
        end
      end
    end
  end
end
