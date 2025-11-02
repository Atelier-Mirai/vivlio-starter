#!/usr/bin/env ruby
# frozen_string_literal: true

# =============================================================
# diagonal_split_transform.rb
# -------------------------------------------------------------
# フレーム画像を対角線で上下に分割し、右下側を下方向に
# シフトさせて新しいキャンバスに再配置するツール。
# ImageMagick (magick) を呼び出してバッチ処理を行う。
# -------------------------------------------------------------
# 【修正済み】
# 1. 透明な背景が黒になる問題を回避するため、分割時に 
#    -background white -flatten を使用して、透過部分の内部RGB値を白で上書き。
# 2. 最後に -transparent white を使用し、この白い背景を再度透明に戻す。
# =============================================================

require "fileutils"
require "open3"
require "optparse"
require "tmpdir"

# Usage:
#   bundle exec ruby scripts/diagonal_split_transform.rb INPUT_DIR [OUTPUT_DIR] [--ratio=<value>]
#
# INPUT_DIR : Directory that contains frame images (PNG / JPG / JPEG)
# OUTPUT_DIR : Optional. Defaults to INPUT_DIR/diagonal_transformed
# --ratio    : Output aspect ratio (height/width). Presets: silver (default), cinemascope.
#              Numericや H:W 形式 (例: 4:3) も指定可能。

DEFAULT_RATIO = Math.sqrt(2)
DEFAULT_WAIFU2X_CMD = ENV['WAIFU2X_BIN'] || File.expand_path('~/.local/bin/waifu2x-ncnn-vulkan')
# プリセット名から縦横比を引けるようにマップを定義
RATIO_PRESETS = {
  "silver" => DEFAULT_RATIO,
  "cinemascope" => 1.0 / 2.39,
  "4:3" => 4.0 / 3.0
}.freeze

# 文字列で渡された ratio オプションを数値へ正規化するユーティリティ
def resolve_ratio(value)
  key = value.downcase
  return RATIO_PRESETS[key] if RATIO_PRESETS.key?(key)

  if value.include?(":")
    height_part, width_part = value.split(":", 2).map(&:strip)
    begin
      height = Float(height_part)
      width = Float(width_part)
    rescue ArgumentError
      abort "ratio の指定が不正です: #{value}"
    end
    abort "ratio の幅が 0 です: #{value}" if width.zero?
    return height / width
  end

  ratio = Float(value)
  abort "ratio は正の数で指定してください: #{value}" if ratio <= 0
  ratio
rescue ArgumentError
  abort "ratio の指定が不正です: #{value}"
end

options = {
  ratio: DEFAULT_RATIO,
  waifu2x: DEFAULT_WAIFU2X_CMD
}

# コマンドライン引数を解析し、必要なオプションを取り出す
parser = OptionParser.new do |opt|
  opt.banner = "Usage: ruby #{File.basename(__FILE__)} INPUT_DIR [OUTPUT_DIR] [options]"
  opt.on("--ratio=VALUE", "出力縦横比(height/width)。プリセット: silver, cinemascope。既定=銀比") do |value|
    options[:ratio] = resolve_ratio(value)
  end
  opt.on("--waifu2x=PATH", "waifu2x-ncnn-vulkan の実行ファイルパス (既定: #{DEFAULT_WAIFU2X_CMD})") do |value|
    options[:waifu2x] = value
  end
  opt.on("-h", "--help", "ヘルプを表示") do
    puts opt
    exit
  end
end

parser.parse!(ARGV)

input_dir_arg = ARGV.shift
output_dir_arg = ARGV.shift

if input_dir_arg.nil?
  warn parser.banner
  exit 1
end

# ImageMagick が利用可能か事前にチェック
def ensure_magick_available!
  out, status = Open3.capture2("magick", "-version")
  return if status.success?

  warn out
  abort "ImageMagick (magick command) が見つかりません。インストールを確認してください。"
rescue Errno::ENOENT
  abort "magick コマンドが見つかりません。ImageMagick をインストールしてください。"
end

ensure_magick_available!

input_dir = File.expand_path(input_dir_arg)
output_dir = File.expand_path(output_dir_arg || File.join(input_dir, "diagonal_transformed"))
FileUtils.mkdir_p(output_dir)

ratio = options[:ratio]

IMAGE_GLOB = %w[*.png *.PNG *.jpg *.JPG *.jpeg *.JPEG].freeze
# 取り込み対象のファイル一覧を取得
image_paths = IMAGE_GLOB.flat_map { |pattern| Dir.glob(File.join(input_dir, pattern)) }

if image_paths.empty?
  warn "入力ディレクトリに対象画像が見つかりません: #{input_dir}"
  exit 1
end

# 各画像は tmpdir 内で一時ファイルを使って処理する
Dir.mktmpdir("diag_split") do |tmpdir|
  image_paths.each do |path|
    filename = File.basename(path, ".*")
    output_path = File.join(output_dir, "#{filename}.png")

    # 元画像の寸法を取得し、縦横比計算に使う
    dims, status = Open3.capture2("magick", "identify", "-format", "%w %h", path)
    unless status.success?
      warn "寸法取得に失敗しました: #{path}"
      next
    end

    width_str, height_str = dims.strip.split
    width = width_str.to_i
    height = height_str.to_i

    if width <= 0 || height <= 0
      warn "不正な寸法です: #{path} (#{width}x#{height})"
      next
    end

    # 出力比率に合わせて新しいキャンバス寸法を算出
    current_ratio = height.to_f / width
    if ratio >= current_ratio
      # 銀比など縦長 → 高さを拡張し、右下三角形を下にオフセット
      new_width = width
      new_height = (width * ratio).round
      bottom_x_offset = 0
      bottom_y_offset = new_height - height
    else
      # シネスコなど横長 → 幅を拡張し、右下三角形を右にオフセット
      new_height = height
      new_width = (height / ratio).round
      bottom_x_offset = new_width - width
      bottom_y_offset = 0
    end

    top_x_offset = 0
    top_y_offset = 0

    top_path = File.join(tmpdir, "#{filename}_top.png")
    bottom_path = File.join(tmpdir, "#{filename}_bottom.png")

    # Step 1 & 2: 元画像を白でフラット化しつつ、対角線でマスク
    top_cmd = [
      "magick", path,
      "-background", "white", "-flatten",
      "(",
        "-size", "#{width}x#{height}",
        "xc:none",
        "-fill", "white",
        "-draw", "polygon 0,0 #{width},0 0,#{height}",
      ")",
      "-compose", "CopyAlpha", "-composite",
      "PNG32:#{top_path}"
    ]

    bottom_cmd = [
      "magick", path,
      "-background", "white", "-flatten",
      "(",
        "-size", "#{width}x#{height}",
        "xc:none",
        "-fill", "white",
        "-draw", "polygon #{width},#{height} #{width},0 0,#{height}",
      ")",
      "-compose", "CopyAlpha", "-composite",
      "PNG32:#{bottom_path}"
    ]

    # 合成コマンド
    composite_cmd = [
      "magick",
      "-size", "#{new_width}x#{new_height}",
      "xc:white",
      "-alpha", "set",
      "+repage",
      top_path, "-geometry", "+#{top_x_offset}+#{top_y_offset}", "-compose", "Over", "-composite",
      bottom_path, "-geometry", "+#{bottom_x_offset}+#{bottom_y_offset}", "-compose", "Over", "-composite",
      # キャンバスへ再配置した後、白背景を透明へ戻す
      "-transparent", "white",
      "PNG32:#{output_path}"
    ]

    # 生成コマンド群を順に実行し、失敗時は警告して次のファイルへ
    [top_cmd, bottom_cmd, composite_cmd].each do |cmd|
      status = system(*cmd)
      unless status
        warn "コマンド実行に失敗しました: #{cmd.join(' ')}"
        break
      end
    end

    puts "generated: #{output_path}"
  end
end

puts "完了しました。出力先: #{output_dir} (ratio=#{format('%.3f', ratio)})"