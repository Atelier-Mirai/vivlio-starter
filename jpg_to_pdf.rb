# frozen_string_literal: true
# vivlio_starter_v1.0.0.pdf を pdftoppm でラスタライズし img2pdf で結合する
#
# 使用法:
#   ruby rasterize_to_pdf.rb
#
# 必要なツール:
#   brew install poppler   # pdftoppm
#   brew install img2pdf

INPUT_PDF  = "vivlio_starter_v1.0.0.pdf"
OUTPUT_PDF = "vivlio_starter_v1.0.0_print.pdf"
IMAGES_DIR = "vivlio_starter_v1.0.0_images"
DPI        = 350
JPEG_QUALITY = 95

require 'fileutils'

def check_tools
  missing = []
  missing << "pdftoppm (brew install poppler)" unless system("which pdftoppm > /dev/null 2>&1")
  missing << "img2pdf   (brew install img2pdf)" unless system("which img2pdf  > /dev/null 2>&1")

  return if missing.empty?

  puts "エラー: 以下のツールが見つかりません:"
  missing.each { puts "  - #{_1}" }
  exit 1
end

def rasterize_pages(pdf_path, images_dir, dpi, quality)
  puts "--- Phase 1: PDF → JPEG ラスタライズ (pdftoppm) ---"
  FileUtils.mkdir_p(images_dir)

  # pdftoppm は全ページを一括処理するため、出力プレフィックスを指定する
  # 出力ファイル名: <prefix>-000001.jpg, <prefix>-000002.jpg, ...
  prefix = File.join(images_dir, "page")

  command = [
    "pdftoppm",
    "-jpeg",
    "-jpegopt", "quality=#{quality}",
    "-r", dpi.to_s,
    pdf_path,
    prefix
  ]

  puts "実行: #{command.join(' ')}"

  start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  success = system(*command)
  elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time).round(1)

  unless success
    puts "エラー: pdftoppm の実行に失敗しました。"
    exit 1
  end

  images = Dir.glob(File.join(images_dir, "page-*.jpg")).sort
  puts "完了: #{images.size} ページ (#{elapsed} 秒)"
  images
end

def merge_to_pdf(images, output_pdf)
  puts ""
  puts "--- Phase 2: JPEG → PDF 結合 (img2pdf) ---"
  puts "対象: #{images.size} 枚 → #{output_pdf}"

  success = system("img2pdf", *images, "-o", output_pdf)

  unless success
    puts "エラー: img2pdf の実行に失敗しました。"
    exit 1
  end

  size_mb = (File.size(output_pdf) / 1024.0 / 1024.0).round(1)
  puts "完了: #{output_pdf} (#{size_mb} MB, #{images.size} ページ)"
end

# --- main ---
check_tools

unless File.exist?(INPUT_PDF)
  puts "エラー: #{INPUT_PDF} が見つかりません。"
  exit 1
end

puts "入力:   #{INPUT_PDF}"
puts "出力:   #{OUTPUT_PDF}"
puts "解像度: #{DPI} dpi / JPEG品質: #{JPEG_QUALITY}"
puts ""

images = rasterize_pages(INPUT_PDF, IMAGES_DIR, DPI, JPEG_QUALITY)
merge_to_pdf(images, OUTPUT_PDF)