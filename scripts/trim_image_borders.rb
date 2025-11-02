#!/usr/bin/env ruby
# frozen_string_literal: true

# =============================================================
#  trim_image_borders.rb
# -------------------------------------------------------------
#  指定ディレクトリ配下の画像ファイル (PNG/JPG) を ImageMagick の
#  -trim で自動トリミングし、透過 PNG として出力するユーティリティ。
#  --fuzz オプションで境界判定の緩さもコントロール可能。
# =============================================================

require "fileutils"
require "open3"
require "optparse"

OPTIONS = {
  fuzz: nil
}.freeze

options = OPTIONS.dup
# コマンドライン引数を解析してオプションを取得
parser = OptionParser.new do |opt|
  opt.banner = "Usage: ruby #{File.basename(__FILE__)} INPUT_DIR [OUTPUT_DIR] [options]"
  opt.on("--fuzz=PERCENT", "境界判定の許容度 (例: 5%)") do |value|
    options[:fuzz] = value
  end
  opt.on("-h", "--help", "Show this help") do
    puts opt
    exit
  end
end

parser.parse!(ARGV)
input_dir = ARGV[0]
output_dir = ARGV[1]

if input_dir.nil?
  warn parser.banner
  exit 1
end

# ImageMagick が利用可能かを事前にチェック
begin
  out, status = Open3.capture2("magick", "-version")
  unless status.success?
    warn out
    abort "ImageMagick (magick コマンド) が見つかりません。インストールを確認してください。"
  end
rescue Errno::ENOENT
  abort "magick コマンドが見つかりません。ImageMagick をインストールしてください。"
end

input_dir = File.expand_path(input_dir)
output_dir = File.expand_path(output_dir || File.join(input_dir, "trimmed"))
FileUtils.mkdir_p(output_dir)

# 入力ディレクトリ直下の対象画像を列挙
image_paths = Dir.glob(File.join(input_dir, "**", "*.{png,PNG,jpg,JPG,jpeg,JPEG}"))
if image_paths.empty?
  warn "No images found under #{input_dir}"
  exit 1
end

image_paths.each do |path|
  basename = File.basename(path, ".*")
  relative_dir = File.dirname(path).delete_prefix(input_dir).sub(%r{^/}, "")
  target_dir = File.join(output_dir, relative_dir)
  FileUtils.mkdir_p(target_dir)

  destination = File.join(target_dir, "#{basename}.png")

  # ImageMagick の -trim コマンドで画像をトリミング
  command = ["magick", path, "-alpha", "set"]
  command += ["-fuzz", options[:fuzz]] if options[:fuzz]
  command += ["-bordercolor", "none", "-border", "1x1", "-trim", "+repage", destination]

  unless system(*command)
    warn "トリミングに失敗しました: #{path}"
    next
  end

  puts "trimmed: #{destination}"
end

puts "完了しました。出力先: #{output_dir}"
