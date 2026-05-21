# frozen_string_literal: true

require 'fileutils'

module Vivlio
  module Starter
    module Pdf
      # PDF を pdftoppm で JPEG 群に変換する共通処理。
      # 部分ページ指定時でもファイル名は元 PDF のページ番号に揃える。
      module PdfToJpeg
        class Error < StandardError
        end

        module_function

        def convert(pdf_path, output_dir:, dpi: 350, quality: 95, pages: nil, command_runner: Kernel)
          validate_options!(dpi:, quality:)

          FileUtils.mkdir_p(output_dir)
          FileUtils.rm_f(Dir.glob(File.join(output_dir, 'page-*.jpg')))

          command = build_command(pdf_path, File.join(output_dir, 'page'), dpi, quality)
          execute!(command, command_runner:)

          normalize_output_names(output_dir)
          images = Dir.glob(File.join(output_dir, 'page-*.jpg')).sort_by { page_number_from_path(it) }

          filter_pages!(images, pages)
        end

        def parse_page_spec(spec)
          text = spec.to_s.strip
          raise Error, 'ページ指定が空です' if text.empty?

          text.split(',').flat_map do |part|
            parse_page_part(part.strip)
          end.uniq.sort
        end

        def build_command(pdf_path, prefix, dpi, quality)
          [
            'pdftoppm',
            '-jpeg',
            '-jpegopt', "quality=#{quality}",
            '-r', dpi.to_s,
            pdf_path,
            prefix
          ]
        end

        def execute!(command, command_runner: Kernel)
          return if command_runner.system(*command)

          raise Error, "pdftoppm の実行に失敗しました: #{command.join(' ')}"
        end

        def filter_pages!(images, pages)
          return images if pages.nil? || pages.to_s.strip.empty?

          requested_pages = parse_page_spec(pages)
          selected = images.select { requested_pages.include?(page_number_from_path(it)) }
          (images - selected).each { FileUtils.rm_f(it) }
          selected
        end

        def normalize_output_names(output_dir)
          Dir.glob(File.join(output_dir, 'page-*.jpg')).each do |path|
            page_number = page_number_from_path(path)
            target = File.join(output_dir, format('page-%03d.jpg', page_number))
            next if path == target

            FileUtils.mv(path, target)
          end
        end

        def parse_page_part(part)
          raise Error, "ページ指定が不正です: #{part.inspect}" if part.empty?

          case part
          when /\A\d+\z/
            page = part.to_i
            raise Error, 'ページ番号は 1 以上で指定してください' if page < 1

            [page]
          when /\A(\d+)-(\d+)\z/
            start_page = ::Regexp.last_match(1).to_i
            end_page = ::Regexp.last_match(2).to_i
            validate_page_range!(start_page, end_page)
            (start_page..end_page).to_a
          else
            raise Error, "ページ指定が不正です: #{part.inspect}"
          end
        end

        def validate_page_range!(start_page, end_page)
          raise Error, 'ページ番号は 1 以上で指定してください' if start_page < 1 || end_page < 1
          raise Error, "ページ範囲が逆順です: #{start_page}-#{end_page}" if start_page > end_page
        end

        def validate_options!(dpi:, quality:)
          raise Error, 'dpi は 1 以上の整数で指定してください' unless dpi.to_i.positive?

          q = quality.to_i
          return if (1..100).cover?(q)

          raise Error, 'quality は 1〜100 の整数で指定してください'
        end

        def page_number_from_path(path)
          File.basename(path)[/page-(\d+)\.jpg\z/, 1].to_i
        end
      end
    end
  end
end
