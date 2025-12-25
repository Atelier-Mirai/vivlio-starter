# frozen_string_literal: true

# ================================================================
# Test: cover_test.rb
# ================================================================
# テスト対象:
#   CoverCommands モジュール（lib/vivlio/starter/cli/cover.rb）
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
require 'vivlio/starter/cli/common'
require 'vivlio/starter/cli/cover'

module Vivlio
  module Starter
    module CLI
      # CoverCommands のユニットテスト
      class CoverCommandsTest < Minitest::Test
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

            config = YAML.load_file('config/book.yml')
            CoverCommands.generate_epub_cover(covers_dir, config)

            output_jpg = File.join(covers_dir, 'cover.jpg')
            assert File.exist?(output_jpg), 'EPUB用JPEGが生成されるべきです'
            assert File.size(output_jpg).positive?, 'JPEGにデータが書き込まれているべきです'
          end
        end

        # execute_a4のテスト
        def test_execute_a4
          skip 'ImageMagickが必要です' unless imagemagick_available?

          within_temp_dir do
            setup_config
            covers_dir = 'covers'
            FileUtils.mkdir_p(covers_dir)
            create_dummy_master_files(covers_dir)

            command = build_cover_command
            CoverCommands.execute_a4(command)

            assert File.exist?(File.join(covers_dir, 'frontcover_rgb.pdf')),
                   'A4表紙PDFが生成されるべきです'
            assert File.exist?(File.join(covers_dir, 'backcover_rgb.pdf')),
                   'A4裏表紙PDFが生成されるべきです'
          end
        end

        # execute_epubのテスト
        def test_execute_epub
          skip 'ImageMagickが必要です' unless imagemagick_available?

          within_temp_dir do
            setup_config
            covers_dir = 'covers'
            FileUtils.mkdir_p(covers_dir)
            create_dummy_master_files(covers_dir)

            command = build_cover_command
            CoverCommands.execute_epub(command)

            assert File.exist?(File.join(covers_dir, 'cover.jpg')),
                   'EPUB用JPEGが生成されるべきです'
          end
        end

        private

        # テスト用の簡易 Thor コマンドクラスを生成する
        def build_cover_command(options = {})
          command_class = Class.new do
            def self.desc(*) = nil
            def self.long_desc(*) = nil
            def self.method_option(*) = nil
            def self.map(*) = nil

            include Vivlio::Starter::CLI::CoverCommands

            attr_reader :options

            def initialize(options)
              @options = options
            end
          end

          command_class.new(options)
        end

        # 一時ディレクトリ配下でテストを実行する
        def within_temp_dir
          Dir.mktmpdir do |dir|
            Dir.chdir(dir) { yield dir }
          end
        end

        # テスト用の設定ファイルを生成
        def setup_config
          FileUtils.mkdir_p('config')
          config = {
            'directories' => {
              'covers' => 'covers'
            },
            'output' => {
              'pdf' => {
                'cover' => {
                  'front' => 'frontcover_rgb.pdf',
                  'back' => 'backcover_rgb.pdf'
                }
              },
              'print_pdf' => {
                'cover' => {
                  'front' => 'frontcover_cmyk.pdf',
                  'back' => 'backcover_cmyk.pdf'
                }
              },
              'epub' => {
                'cover' => 'cover.jpg'
              }
            },
            'page' => {
              'use' => 'b5_standard'
            }
          }
          File.write('config/book.yml', config.to_yaml)
          File.write('config/page_presets.yml', DUMMY_PAGE_PRESETS.to_yaml)
          File.write('config/post_replace_list.yml', { 'replacements' => [] }.to_yaml)
        end

        # テスト用のマスター画像を配置
        def create_dummy_master_files(covers_dir, front: true, back: true)
          copy_fixture_master_files(covers_dir, front: front, back: back)
        end

        # ダミーのPNG画像を生成（ImageMagickが必要）
        def create_dummy_png(path, width: 100, height: 100)
          if (convert_cmd = imagemagick_convert_command)
            system(*convert_cmd, '-size', "#{width}x#{height}", 'xc:white', path, out: File::NULL, err: File::NULL)
          else
            # ImageMagickがない場合は空ファイルを作成
            FileUtils.touch(path)
          end
        end

        # コマンドが利用可能かチェック（PATHを直接探索してハングを防止）
        def imagemagick_available?
          !imagemagick_convert_command.nil?
        end

        def imagemagick_convert_command
          return ['magick', 'convert'] if command_in_path?('magick')
          return ['convert'] if command_in_path?('convert')
          nil
        end

        def command_in_path?(command)
          return false if command.to_s.empty?

          ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).any? do |dir|
            path = File.join(dir, command)
            File.executable?(path) && !File.directory?(path)
          end
        end

        def copy_fixture_master_files(covers_dir, front: true, back: true)
          FileUtils.mkdir_p(covers_dir)

          if front
            copy_or_stub_fixture(FRONT_MASTER_FIXTURE, File.join(covers_dir, 'frontcover_master.png'))
          end

          if back
            copy_or_stub_fixture(BACK_MASTER_FIXTURE, File.join(covers_dir, 'backcover_master.png'))
          end
        end

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
    end
  end
end
