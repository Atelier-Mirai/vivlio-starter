# frozen_string_literal: true

require 'fileutils'

module VivlioStarter
  module Pdf
    # PDF を pdftoppm で JPEG 群に変換する共通処理。
    # 部分ページ指定時でもファイル名は元 PDF のページ番号に揃える。
    module PdfToJpeg
      class Error < StandardError
      end

      module_function

      # PDF を JPEG 群へ変換し、生成した画像パスの配列を返す
      #
      # pages 指定時も全ページを一度変換してから不要分を削除する。
      # pdftoppm の -f/-l による部分変換では出力ファイル名の連番が
      # 1 起点に振り直され、元 PDF のページ番号と一致しなくなるため。
      #
      # @param pages [String, nil] ページ指定（例: "3", "1-5", "1,3,7-9"）
      # @param command_runner [#system] テストで外部コマンドを差し替えるための DI
      # @return [Array<String>] ページ番号順の JPEG パス
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

      # ページ指定文字列をページ番号配列に展開する（例: "1,3-5" → [1, 3, 4, 5]）
      def parse_page_spec(spec)
        text = spec.to_s.strip
        raise Error, 'ページ指定が空です' if text.empty?

        text.split(',').flat_map do |part|
          parse_page_part(part.strip)
        end.uniq.sort
      end

      # pdftoppm のコマンドライン配列を組み立てる（shell を介さず配列で実行する）
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

      # コマンドを実行し、失敗時は Error を送出する
      def execute!(command, command_runner: Kernel)
        return if command_runner.system(*command)

        raise Error, "pdftoppm の実行に失敗しました: #{command.join(' ')}"
      end

      # 指定ページのみを残し、対象外の JPEG はディスクからも削除する
      def filter_pages!(images, pages)
        return images if pages.nil? || pages.to_s.strip.empty?

        requested_pages = parse_page_spec(pages)
        selected = images.select { requested_pages.include?(page_number_from_path(it)) }
        (images - selected).each { FileUtils.rm_f(it) }
        selected
      end

      # 出力ファイル名を page-001.jpg 形式（3桁ゼロ埋め）に統一する
      # pdftoppm は総ページ数によって連番の桁数を変える（page-1.jpg / page-01.jpg）ため
      def normalize_output_names(output_dir)
        Dir.glob(File.join(output_dir, 'page-*.jpg')).each do |path|
          page_number = page_number_from_path(path)
          target = File.join(output_dir, format('page-%03d.jpg', page_number))
          next if path == target

          FileUtils.mv(path, target)
        end
      end

      # ページ指定の1要素（"3" または "3-5"）をページ番号配列へ展開する
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

      # dpi / quality の値域を検証する（pdftoppm に渡す前に日本語で失敗理由を示す）
      def validate_options!(dpi:, quality:)
        raise Error, 'dpi は 1 以上の整数で指定してください' unless dpi.to_i.positive?

        q = quality.to_i
        return if (1..100).cover?(q)

        raise Error, 'quality は 1〜100 の整数で指定してください'
      end

      # JPEG パスからページ番号を取り出す（例: "page-012.jpg" → 12）
      def page_number_from_path(path)
        File.basename(path)[/page-(\d+)\.jpg\z/, 1].to_i
      end
    end
  end
end
