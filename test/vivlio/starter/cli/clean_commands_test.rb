# frozen_string_literal: true

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'yaml'
require 'vivlio/starter/cli/common'
require 'vivlio/starter/cli/clean'

module Vivlio
  module Starter
    module CLI
      class CleanCommandsTest < Minitest::Test
        # --purge なしで clean 実行時、生成物のみ削除され最終PDFが残ることを確認
        def test_clean_preserves_final_pdfs_without_purge
          within_temp_dir do
            setup_generated_files
            build_clean_command.clean

            assert_clean_directory
            assert_final_pdfs_exist
            assert File.exist?('11-sample.pdf'), '単章PDFは purge なしでは残るはずです'
          end
        end

        # --purge 指定で clean 実行時、最終PDFや単章PDFも削除されることを確認
        def test_clean_with_purge_removes_final_outputs
          within_temp_dir do
            setup_generated_files
            build_clean_command(purge: true).clean

            assert_clean_directory
            assert_final_pdfs_removed
            refute File.exist?('11-sample.pdf'), 'purge 指定時は単章PDFも削除されるはずです'
          end
        end

        # --cache 指定で clean 実行時、キャッシュのみ削除されることを確認
        def test_clean_cache_only_removes_cache_directory
          within_temp_dir do
            setup_generated_files
            cache_dir = Vivlio::Starter::CLI::Common.cache_dir
            FileUtils.mkdir_p(cache_dir)
            write_file(File.join(cache_dir, 'cached.pdf'))

            build_clean_command(cache: true).clean

            refute Dir.exist?(cache_dir), 'キャッシュディレクトリは削除されるべきです'
            assert File.exist?('11-sample.html'), '--cache では生成物を削除しないはずです'
            assert_final_pdfs_exist
            assert File.exist?('11-sample.pdf'), '単章PDFは保持されるはずです'
          end
        end

        # --cover 指定で clean 実行時、カバー画像のみ削除されることを確認
        def test_clean_cover_only_removes_cover_files
          within_temp_dir do
            setup_generated_files
            setup_cover_files
            setup_config_for_cover

            build_clean_command(cover: true).clean

            # カバー画像が削除されること
            assert_cover_files_removed
            # マスター画像は保持されること
            assert_master_files_exist
            # 通常の生成物は保持されること
            assert File.exist?('11-sample.html'), '--cover では通常の生成物を削除しないはずです'
            assert_final_pdfs_exist
          end
        end

        # --cover --cache 指定で clean 実行時、カバー画像とキャッシュが削除されることを確認
        def test_clean_cover_and_cache
          within_temp_dir do
            setup_generated_files
            setup_cover_files
            setup_config_for_cover
            cache_dir = Vivlio::Starter::CLI::Common.cache_dir
            FileUtils.mkdir_p(cache_dir)
            write_file(File.join(cache_dir, 'cached.pdf'))

            build_clean_command(cover: true, cache: true).clean

            # カバー画像が削除されること
            assert_cover_files_removed
            # キャッシュが削除されること
            refute Dir.exist?(cache_dir), 'キャッシュディレクトリは削除されるべきです'
            # 通常の生成物は保持されること
            assert File.exist?('11-sample.html'), '--cover --cache では通常の生成物を削除しないはずです'
            assert_final_pdfs_exist
          end
        end

        # --cover --purge 指定で clean 実行時、カバー画像と通常のクリーンが実行されることを確認
        def test_clean_cover_and_purge
          within_temp_dir do
            setup_generated_files
            setup_cover_files
            setup_config_for_cover

            build_clean_command(cover: true, purge: true).clean

            # カバー画像が削除されること
            assert_cover_files_removed
            # 通常のクリーンも実行されること
            assert_clean_directory
            assert_final_pdfs_removed
          end
        end

        # --cover --cache --purge 指定で clean 実行時、すべてが削除されることを確認
        def test_clean_cover_cache_and_purge
          within_temp_dir do
            setup_generated_files
            setup_cover_files
            setup_config_for_cover
            cache_dir = Vivlio::Starter::CLI::Common.cache_dir
            FileUtils.mkdir_p(cache_dir)
            write_file(File.join(cache_dir, 'cached.pdf'))

            build_clean_command(cover: true, cache: true, purge: true).clean

            # カバー画像が削除されること
            assert_cover_files_removed
            # キャッシュが削除されること
            refute Dir.exist?(cache_dir), 'キャッシュディレクトリは削除されるべきです'
            # 通常のクリーンも実行されること
            assert_clean_directory
            assert_final_pdfs_removed
          end
        end

        # --all 指定で clean 実行時、開発者用のフルクリーンが行われることを確認
        def test_clean_with_all_option
          within_temp_dir do
            setup_generated_files
            setup_cover_files
            setup_config_for_cover
            cache_dir = Vivlio::Starter::CLI::Common.cache_dir
            FileUtils.mkdir_p(cache_dir)
            write_file(File.join(cache_dir, 'cached.pdf'))

            build_clean_command(all: true).clean

            # カバー画像が削除されること
            assert_cover_files_removed
            # キャッシュが削除されること
            refute Dir.exist?(cache_dir), '--all ではキャッシュを削除するはずです'
            # 通常のクリーンも実行されること
            assert_clean_directory
            assert_final_pdfs_removed
          end
        end

        # book.yml の設定に基づいてカバー画像が削除されることを確認
        def test_clean_cover_respects_config
          within_temp_dir do
            setup_generated_files
            covers_dir = 'covers'
            FileUtils.mkdir_p(covers_dir)
            
            # カスタムファイル名でカバー画像を作成
            write_file(File.join(covers_dir, 'custom_front.pdf'))
            write_file(File.join(covers_dir, 'custom_back.pdf'))
            write_file(File.join(covers_dir, 'custom_cover.jpg'))
            write_file(File.join(covers_dir, 'frontcover_master.png'))
            
            # カスタム設定を作成
            setup_custom_config_for_cover('custom_front.pdf', 'custom_back.pdf', 'custom_cover.jpg')

            build_clean_command(cover: true).clean

            # カスタムファイル名のカバー画像が削除されること
            refute File.exist?(File.join(covers_dir, 'custom_front.pdf')),
                   'カスタム表紙PDFは削除されるべきです'
            refute File.exist?(File.join(covers_dir, 'custom_back.pdf')),
                   'カスタム裏表紙PDFは削除されるべきです'
            refute File.exist?(File.join(covers_dir, 'custom_cover.jpg')),
                   'カスタムEPUBカバーは削除されるべきです'
            # マスター画像は保持されること
            assert File.exist?(File.join(covers_dir, 'frontcover_master.png')),
                   'マスター画像は保持されるべきです'
          end
        end

        private

        # テスト用の簡易 Thor コマンドクラスを生成する
        def build_clean_command(options = {})
          command_class = Class.new do
            # Thor DSL メソッドのスタブを用意してからモジュールを include する
            def self.desc(*) = nil
            def self.long_desc(*) = nil
            def self.method_option(*) = nil

            include Vivlio::Starter::CLI::CleanCommands

            attr_reader :options

            def initialize(options)
              @options = options
            end
          end

          defaults = {
            cache: false,
            cover: false,
            purge: false,
            all: false
          }
          command_class.new(defaults.merge(options))
        end

        # 一時ディレクトリ配下でテストを実行する
        def within_temp_dir
          Dir.mktmpdir do |dir|
            Dir.chdir(dir) { yield dir }
          end
        end

        # clean 対象となる生成物一式を用意する
        def setup_generated_files
          FileUtils.mkdir_p('.vivliostyle')
          write_file('.vivliostyle/placeholder.txt')

          %w[11-sample.html entries.js 03-toc.md 11-sample.md _titlepage.md].each do |name|
            write_file(name)
          end

          %w[_titlepage.pdf _titlepage_legalpage.pdf output_tmp1.pdf].each { |name| write_file(name) }
          write_file('11-sample.pdf')

          pdf_output_files.each { |path| write_file(path) }
        end

        # 中間生成物が削除されたことを検証する
        def assert_clean_directory
          refute Dir.exist?('.vivliostyle'), '.vivliostyle ディレクトリは削除されるべきです'

          %w[11-sample.html entries.js 03-toc.md 11-sample.md _titlepage.md
             _titlepage.pdf _titlepage_legalpage.pdf output_tmp1.pdf].each do |name|
            refute File.exist?(name), "#{name} は削除されるべきです"
          end
        end

        # 最終出力PDFが残っていることを検証する
        def assert_final_pdfs_exist
          pdf_output_files.each do |path|
            assert File.exist?(path), "#{path} は保持されるべきです"
          end
        end

        # 最終出力PDFが削除されたことを検証する
        def assert_final_pdfs_removed
          pdf_output_files.each do |path|
            refute File.exist?(path), "#{path} は purge 指定時に削除されるべきです"
          end
        end

        # CONFIG から最終PDF名を取得する
        def pdf_output_files
          config = Vivlio::Starter::CLI::Common::CONFIG['pdf'] || {}
          [
            config['output_file'] || 'output.pdf',
            config['output_file_compressed'] || 'output_compressed.pdf'
          ].uniq
        end

        # テスト用に空ファイルを生成する
        def write_file(path)
          FileUtils.mkdir_p(File.dirname(path)) unless File.dirname(path) == '.'
          FileUtils.touch(path)
        end

        # カバー画像ファイルを生成する
        def setup_cover_files
          covers_dir = 'covers'
          FileUtils.mkdir_p(covers_dir)
          
          # 生成されたカバー画像
          write_file(File.join(covers_dir, 'frontcover_rgb.pdf'))
          write_file(File.join(covers_dir, 'backcover_rgb.pdf'))
          write_file(File.join(covers_dir, 'frontcover_cmyk.pdf'))
          write_file(File.join(covers_dir, 'backcover_cmyk.pdf'))
          write_file(File.join(covers_dir, 'cover.jpg'))
          
          # マスター画像
          write_file(File.join(covers_dir, 'frontcover_master.png'))
          write_file(File.join(covers_dir, 'backcover_master.png'))
        end

        # カバー画像用の設定ファイルを生成
        def setup_config_for_cover
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
            }
          }
          File.write('config/book.yml', config.to_yaml)
        end

        # カスタムファイル名の設定ファイルを生成
        def setup_custom_config_for_cover(front_pdf, back_pdf, epub_cover)
          FileUtils.mkdir_p('config')
          config = {
            'directories' => {
              'covers' => 'covers'
            },
            'output' => {
              'pdf' => {
                'cover' => {
                  'front' => front_pdf,
                  'back' => back_pdf
                }
              },
              'print_pdf' => {
                'cover' => {
                  'front' => front_pdf,
                  'back' => back_pdf
                }
              },
              'epub' => {
                'cover' => epub_cover
              }
            }
          }
          File.write('config/book.yml', config.to_yaml)
        end

        # カバー画像が削除されたことを検証する
        def assert_cover_files_removed
          covers_dir = 'covers'
          refute File.exist?(File.join(covers_dir, 'frontcover_rgb.pdf')),
                 '表紙RGB PDFは削除されるべきです'
          refute File.exist?(File.join(covers_dir, 'backcover_rgb.pdf')),
                 '裏表紙RGB PDFは削除されるべきです'
          refute File.exist?(File.join(covers_dir, 'frontcover_cmyk.pdf')),
                 '表紙CMYK PDFは削除されるべきです'
          refute File.exist?(File.join(covers_dir, 'backcover_cmyk.pdf')),
                 '裏表紙CMYK PDFは削除されるべきです'
          refute File.exist?(File.join(covers_dir, 'cover.jpg')),
                 'EPUB用JPEGは削除されるべきです'
        end

        # マスター画像が保持されたことを検証する
        def assert_master_files_exist
          covers_dir = 'covers'
          assert File.exist?(File.join(covers_dir, 'frontcover_master.png')),
                 '表紙マスター画像は保持されるべきです'
          assert File.exist?(File.join(covers_dir, 'backcover_master.png')),
                 '裏表紙マスター画像は保持されるべきです'
        end
      end
    end
  end
end
