# frozen_string_literal: true

require 'test_helper'
require 'tmpdir'
require 'fileutils'
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

          command_class.new({ cache: false }.merge(options))
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

          %w[11-sample.html entries.js 03-toc.md 11-sample.md 00-titlepage.md].each do |name|
            write_file(name)
          end

          %w[00-titlepage.pdf 00-01-front.pdf output_tmp1.pdf].each { |name| write_file(name) }
          write_file('11-sample.pdf')

          pdf_output_files.each { |path| write_file(path) }
        end

        # 中間生成物が削除されたことを検証する
        def assert_clean_directory
          refute Dir.exist?('.vivliostyle'), '.vivliostyle ディレクトリは削除されるべきです'

          %w[11-sample.html entries.js 03-toc.md 11-sample.md 00-titlepage.md
             00-titlepage.pdf 00-01-front.pdf output_tmp1.pdf].each do |name|
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
      end
    end
  end
end
