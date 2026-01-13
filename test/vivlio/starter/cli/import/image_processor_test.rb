# frozen_string_literal: true

require_relative '../../../../test_helper'
require 'vivlio/starter/cli/import/image_processor'
require 'vivlio/starter/cli/common'
require 'fileutils'
require 'tmpdir'

module Vivlio
  module Starter
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

          # ================================================================
          # copy_front_cover! テスト
          # ================================================================
          def test_copy_front_cover_returns_false_for_nil
            refute ImageProcessor.copy_front_cover!(@tmpdir, nil)
          end

          def test_copy_front_cover_returns_false_for_non_pdf
            refute ImageProcessor.copy_front_cover!(@tmpdir, 'cover.png')
          end

          def test_copy_front_cover_returns_false_when_file_not_found
            starter_dir = File.join(@tmpdir, 'starter')
            FileUtils.mkdir_p(File.join(starter_dir, 'images'))

            Dir.chdir(@tmpdir) do
              refute ImageProcessor.copy_front_cover!(starter_dir, 'hyoshi.pdf')
            end
          end

          def test_copy_front_cover_copies_pdf_successfully
            starter_dir = File.join(@tmpdir, 'starter')
            images_dir = File.join(starter_dir, 'images')
            FileUtils.mkdir_p(images_dir)

            # ダミー PDF を作成
            pdf_path = File.join(images_dir, 'hyoshi.pdf')
            File.write(pdf_path, '%PDF-1.4 dummy')

            work_dir = File.join(@tmpdir, 'work')
            FileUtils.mkdir_p(work_dir)

            Dir.chdir(work_dir) do
              convert_args = nil
              stub = ->(covers_dir, filename) {
                convert_args = [covers_dir, filename]
                true
              }
              result = ImageProcessor.stub(:convert_front_cover_pdf_to_master!, stub) do
                ImageProcessor.copy_front_cover!(starter_dir, 'hyoshi.pdf')
              end
              assert result
              assert File.exist?(File.join('covers', 'hyoshi.pdf'))
            end

            assert_equal ['covers', 'hyoshi.pdf'], convert_args
          end

          def test_convert_front_cover_pdf_to_master_invokes_imagemagick_command
            work_dir = File.join(@tmpdir, 'work')
            covers_dir = File.join(work_dir, 'covers')
            FileUtils.mkdir_p(covers_dir)
            pdf_path = File.join(covers_dir, 'hyoshi.pdf')
            File.write(pdf_path, '%PDF-1.4 dummy')

            Dir.chdir(work_dir) do
              captured = nil
              ImageProcessor.stub :find_imagemagick_convert_command, ['magick', 'convert'] do
                ImageProcessor.stub :run_imagemagick_command, ->(cmd, label:) {
                  captured = cmd
                  true
                } do
                  result = ImageProcessor.convert_front_cover_pdf_to_master!(covers_dir, 'hyoshi.pdf')
                  assert result
                end
              end

              assert_includes captured, "#{pdf_path}[0]"
              assert_includes captured, "PNG32:#{File.join(covers_dir, 'frontcover_master.png')}"
            end
          end

          def test_convert_front_cover_pdf_to_master_returns_false_without_imagemagick
            work_dir = File.join(@tmpdir, 'work')
            covers_dir = File.join(work_dir, 'covers')
            FileUtils.mkdir_p(covers_dir)
            pdf_path = File.join(covers_dir, 'hyoshi.pdf')
            File.write(pdf_path, '%PDF-1.4 dummy')

            Dir.chdir(work_dir) do
              ImageProcessor.stub :find_imagemagick_convert_command, nil do
                refute ImageProcessor.convert_front_cover_pdf_to_master!(covers_dir, 'hyoshi.pdf')
              end
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
end
