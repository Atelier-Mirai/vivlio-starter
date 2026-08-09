# frozen_string_literal: true

require_relative '../../../test_helper'
require 'vivlio_starter/cli/import/image_processor'
require 'vivlio_starter/cli/common'
require 'fileutils'
require 'tmpdir'

module VivlioStarter
  module CLI
    module Import
      class ImageProcessorTest < Minitest::Test
        def setup
          @tmpdir = Dir.mktmpdir('image_processor_test')
          @original_pwd = Dir.pwd
        end

        def teardown
          Dir.chdir(@original_pwd)
          FileUtils.rm_rf(@tmpdir) if @tmpdir && Dir.exist?(@tmpdir)
        end

        FRONT = CoverCommands::FRONTCOVER_MASTER
        BACK = CoverCommands::BACKCOVER_MASTER

        def import_front(starter_dir, value)
          ImageProcessor.import_master_cover!(starter_dir, value, master: FRONT, label: '表表紙')
        end

        # ================================================================
        # import_master_cover! テスト
        # ================================================================
        def test_import_master_cover_returns_false_for_nil
          refute import_front(@tmpdir, nil)
        end

        def test_import_master_cover_returns_false_for_non_pdf
          refute import_front(@tmpdir, 'cover.png')
        end

        def test_import_master_cover_returns_false_when_file_not_found
          starter_dir = File.join(@tmpdir, 'starter')
          FileUtils.mkdir_p(File.join(starter_dir, 'images'))

          Dir.chdir(@tmpdir) do
            refute import_front(starter_dir, 'hyoshi.pdf')
          end
        end

        def test_import_master_cover_copies_pdf_successfully
          starter_dir = File.join(@tmpdir, 'starter')
          images_dir = File.join(starter_dir, 'images')
          FileUtils.mkdir_p(images_dir)

          # ダミー PDF を作成
          pdf_path = File.join(images_dir, 'hyoshi.pdf')
          File.write(pdf_path, '%PDF-1.4 dummy')

          work_dir = File.join(@tmpdir, 'work')
          FileUtils.mkdir_p(work_dir)

          convert_args = nil

          Dir.chdir(work_dir) do
            stub = ->(covers_dir, filename, master) {
              convert_args = [covers_dir, filename, master]
              true
            }
            result = ImageProcessor.stub(:convert_cover_pdf_to_master!, stub) do
              import_front(starter_dir, 'hyoshi.pdf')
            end
            assert result
            assert File.exist?(File.join('covers', 'hyoshi.pdf'))
          end

          assert_equal ['covers', 'hyoshi.pdf', FRONT], convert_args
        end

        # 裏表紙も同じ経路で取り込む（雛形の見本 backcover_master.png を置き換える）
        def test_import_master_cover_handles_back_cover
          starter_dir = File.join(@tmpdir, 'starter')
          FileUtils.mkdir_p(File.join(starter_dir, 'images'))
          File.write(File.join(starter_dir, 'images', 'ura.pdf'), '%PDF-1.4 dummy')

          work_dir = File.join(@tmpdir, 'work')
          FileUtils.mkdir_p(work_dir)
          convert_args = nil

          Dir.chdir(work_dir) do
            stub = ->(covers_dir, filename, master) {
              convert_args = [covers_dir, filename, master]
              true
            }
            ImageProcessor.stub(:convert_cover_pdf_to_master!, stub) do
              assert ImageProcessor.import_master_cover!(starter_dir, 'ura.pdf', master: BACK, label: '裏表紙')
            end
          end

          assert_equal ['covers', 'ura.pdf', BACK], convert_args
        end

        # ================================================================
        # plain_cover_filename テスト（Re:VIEW Starter 側の書き方の揺れを吸収する）
        # ================================================================
        def test_plain_cover_filename_strips_page_number_and_bleed_marker
          assert_equal 'cover.pdf', ImageProcessor.plain_cover_filename('cover.pdf<2>*', label: '表表紙')
          assert_equal 'cover.pdf', ImageProcessor.plain_cover_filename('cover.pdf<2>', label: '表表紙')
          assert_equal 'cover.pdf', ImageProcessor.plain_cover_filename('cover.pdf*', label: '表表紙')
        end

        def test_plain_cover_filename_takes_first_of_array
          assert_equal 'a.pdf', ImageProcessor.plain_cover_filename(['a.pdf', 'b.pdf'], label: '表表紙')
        end

        def test_plain_cover_filename_returns_empty_for_nil
          assert_equal '', ImageProcessor.plain_cover_filename(nil, label: '表表紙')
        end

        def test_convert_cover_pdf_to_master_invokes_imagemagick_command
          work_dir = File.join(@tmpdir, 'work')
          covers_dir = File.join(work_dir, 'covers')
          FileUtils.mkdir_p(covers_dir)
          pdf_path = File.join(covers_dir, 'hyoshi.pdf')
          File.write(pdf_path, '%PDF-1.4 dummy')

          Dir.chdir(work_dir) do
            captured = nil
            ImageProcessor.stub :find_imagemagick_convert_command, ['magick', 'convert'] do
              ImageProcessor.stub :run_imagemagick_command, lambda { |cmd, label:|
                captured = { cmd:, label: }
                true
              } do
                result = ImageProcessor.convert_cover_pdf_to_master!(covers_dir, 'hyoshi.pdf', FRONT)
                assert result
              end
            end

            assert_includes captured[:cmd], "#{pdf_path}[0]"
            assert_includes captured[:cmd], "PNG32:#{File.join(covers_dir, FRONT)}"
            assert_equal "#{FRONT} 生成", captured[:label]
          end
        end

        def test_convert_cover_pdf_to_master_returns_false_without_imagemagick
          work_dir = File.join(@tmpdir, 'work')
          covers_dir = File.join(work_dir, 'covers')
          FileUtils.mkdir_p(covers_dir)
          pdf_path = File.join(covers_dir, 'hyoshi.pdf')
          File.write(pdf_path, '%PDF-1.4 dummy')

          Dir.chdir(work_dir) do
            ImageProcessor.stub :find_imagemagick_convert_command, nil do
              refute ImageProcessor.convert_cover_pdf_to_master!(covers_dir, 'hyoshi.pdf', FRONT)
            end
          end
        end

        # ================================================================
        # copy_images_to_local テスト（取り込み時のファイル名サニタイズ）
        # ================================================================
        # 危険文字を含む元画像名はコピー時に正規化され、安全名で配置される
        # （markdown 参照側 normalize_image_paths と同一基準。W14010 恒久防御）
        def test_copy_images_to_local_sanitizes_dangerous_filename
          starter_images = File.join(@tmpdir, 'starter', 'images', '94-sample')
          FileUtils.mkdir_p(starter_images)
          File.write(File.join(starter_images, "Einstein's_later_years.png"), 'dummy')
          File.write(File.join(starter_images, 'sakura(1).jpg'), 'dummy')

          work_dir = File.join(@tmpdir, 'work')
          FileUtils.mkdir_p(work_dir)

          Dir.chdir(work_dir) do
            ImageProcessor.copy_images_to_local(File.join(@tmpdir, 'starter', 'images'))

            assert File.exist?('images/94-sample/Einsteins_later_years.png'),
                   'アポストロフィを除去した安全名でコピーされるべき'
            assert File.exist?('images/94-sample/sakura1.png') || File.exist?('images/94-sample/sakura1.jpg'),
                   '括弧を除去した安全名でコピーされるべき'
            refute File.exist?("images/94-sample/Einstein's_later_years.png"),
                   '危険文字を含む名前のままでは配置されないべき'
          end
        end

        # ================================================================
        # remove_original_files! テスト
        # ================================================================
        def test_remove_original_files_removes_png_jpg_gif
          work_dir = File.join(@tmpdir, 'work')
          images_dir = File.join(work_dir, 'images')
          FileUtils.mkdir_p(images_dir)

          # ダミー画像を作成
          File.write(File.join(images_dir, 'test.png'), 'dummy')
          File.write(File.join(images_dir, 'test.jpg'), 'dummy')
          File.write(File.join(images_dir, 'test.gif'), 'dummy')
          File.write(File.join(images_dir, 'test.webp'), 'dummy')

          Dir.chdir(work_dir) do
            ImageProcessor.remove_original_files!

            refute File.exist?(File.join(images_dir, 'test.png'))
            refute File.exist?(File.join(images_dir, 'test.jpg'))
            refute File.exist?(File.join(images_dir, 'test.gif'))
            assert File.exist?(File.join(images_dir, 'test.webp'))
          end
        end
      end
    end
  end
end
