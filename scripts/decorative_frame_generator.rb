#!/usr/bin/env ruby
# frozen_string_literal: true

# =============================================================
#  decorative_frame_generator.rb
# -------------------------------------------------------------
#  1. trim_image_borders.rb で余白をトリミング
#  2. diagonal_split_transform.rb で縦横 2 パターンを生成
#  3. 生成画像を waifu2x で 2 倍化し、ImageMagick で 2880px WebP に変換
# -------------------------------------------------------------
# 既存スクリプトを組み合わせたバッチ処理用ユーティリティ。
# 各ステップは失敗時に例外終了し、途中結果は所定ディレクトリに保存する。
# =============================================================
# 使用例:
#   ruby scripts/decorative_frame_generator.rb ./stylesheets/images/bundled \
#     --fuzz=5% \
#     --waifu2x=./scripts/waifu2x/waifu2x-ncnn-vulkan \
#     --target-width=2880 \
#     --webp-quality=90
# =============================================================

require "fileutils"
require "optparse"
require "open3"
require "shellwords"
require "rbconfig"

DEFAULT_WAIFU2X = ENV["WAIFU2X_BIN"] || File.expand_path("~/.local/bin/waifu2x/waifu2x-ncnn-vulkan")
DEFAULT_WAIFU2X_NOISE = 0
DEFAULT_SCALE = 2
DEFAULT_TARGET_WIDTH = 2880
DEFAULT_WEBP_QUALITY = 90

options = {
  fuzz: nil,
  trim_output: nil,
  portrait_output: nil,
  landscape_output: nil,
  high_resolution_output: nil,
  webp_output: nil,
  waifu2x: DEFAULT_WAIFU2X,
  waifu2x_args: [],
  waifu2x_noise: DEFAULT_WAIFU2X_NOISE,
  scale: DEFAULT_SCALE,
  target_width: DEFAULT_TARGET_WIDTH,
  webp_quality: DEFAULT_WEBP_QUALITY,
  keep_intermediate: false
}

parser = OptionParser.new do |opt|
  opt.banner = <<~BANNER
    Usage: ruby #{File.basename(__FILE__)} INPUT_DIR [options]

    INPUT_DIR に含まれる画像に対し、以下の処理を順に実行します:
      1. trim_image_borders.rb で余白トリミング (任意で --fuzz 指定可)
      2. diagonal_split_transform.rb で銀比/シネスコ PNG を生成
      3. 生成 PNG を waifu2x で拡大後、横幅 #{DEFAULT_TARGET_WIDTH}px の WebP へ変換

    主要オプション:
      --trim-output=DIR      トリミング後の出力先
      --portrait-output=DIR  銀比 PNG の出力先
      --landscape-output=DIR シネスコ PNG の出力先
      --high-resolution-output=DIR 高解像度(中間)ファイルの出力ベース
      --webp-output=DIR      最終 WebP の出力先 (既定: INPUT_DIR)
      --waifu2x=PATH         使用する waifu2x 実行ファイル
      --target-width=PX      最終 WebP の横幅 (既定: #{DEFAULT_TARGET_WIDTH})
      --webp-quality=VALUE   WebP 品質値 (既定: #{DEFAULT_WEBP_QUALITY})
  BANNER

  opt.on("--fuzz=PERCENT", "trim_image_borders.rb に渡す --fuzz") do |value|
    options[:fuzz] = value
  end
  opt.on("--trim-output=DIR", "トリミング後の画像出力先 (既定: INPUT_DIR/trimmed)") do |value|
    options[:trim_output] = value
  end
  opt.on("--portrait-output=DIR", "銀比 (portrait) 画像の出力先 (既定: <trimmed>/diagonal_portrait)") do |value|
    options[:portrait_output] = value
  end
  opt.on("--landscape-output=DIR", "シネスコ (landscape) 画像の出力先 (既定: <trimmed>/diagonal_landscape)") do |value|
    options[:landscape_output] = value
  end
  opt.on("--high-resolution-output=DIR", "高解像度(中間)ファイルの出力先") do |value|
    options[:high_resolution_output] = value
  end
  opt.on("--webp-output=DIR", "最終 WebP の出力先 (既定: INPUT_DIR)") do |value|
    options[:webp_output] = value
  end
  opt.on("--waifu2x=PATH", "waifu2x 実行ファイル (既定: #{DEFAULT_WAIFU2X})") do |value|
    options[:waifu2x] = value
  end
  opt.on("--waifu2x-args=ARGS", "waifu2x へ渡す追加引数 (空白区切り)") do |value|
    options[:waifu2x_args] = Shellwords.split(value)
  end
  opt.on("--waifu2x-noise=LEVEL", Integer, "waifu2x のノイズ除去レベル (既定: #{DEFAULT_WAIFU2X_NOISE})") do |value|
    options[:waifu2x_noise] = value
  end
  opt.on("--scale=VALUE", Integer, "waifu2x の拡大倍率 (既定: #{DEFAULT_SCALE})") do |value|
    options[:scale] = value
  end
  opt.on("--target-width=PX", Integer, "最終 WebP の横幅 (既定: #{DEFAULT_TARGET_WIDTH})") do |value|
    options[:target_width] = value
  end
  opt.on("--webp-quality=VALUE", Integer, "WebP の品質 (既定: #{DEFAULT_WEBP_QUALITY})") do |value|
    options[:webp_quality] = value
  end
  opt.on("--keep-intermediate", "waifu2x の中間 PNG を削除せず保持") do
    options[:keep_intermediate] = true
  end
  opt.on("-h", "--help", "ヘルプを表示") do
    puts opt
    exit
  end
end

parser.parse!(ARGV)
input_dir_arg = ARGV.shift

if input_dir_arg.nil?
  warn parser.banner
  exit 1
end

trim_output_specified = !options[:trim_output].nil?

# -------------------------------------------------------------
# ヘルパー
# -------------------------------------------------------------

def command_available?(cmd)
  return File.executable?(cmd) if cmd.include?(File::SEPARATOR)

  ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? do |path|
    candidate = File.join(path, cmd)
    File.executable?(candidate)
  end
end

def ensure_command!(cmd, friendly_name = cmd)
  return if command_available?(cmd)

  abort "#{friendly_name} (#{cmd}) が見つかりません。PATH を確認してください。"
end

def shell_join(cmd)
  Shellwords.join(cmd)
end

def run_command!(cmd, label)
  puts "==> #{label}"
  puts "    $ #{shell_join(cmd)}"
  status = system(*cmd)
  abort "#{label} に失敗しました。" unless status
end

def run_command_warn(cmd, label)
  puts "    $ #{shell_join(cmd)}"
  status = system(*cmd)
  unless status
    warn "警告: #{label} に失敗しました。"
  end
  status
end

def rename_with_suffix(dir, suffix)
  Dir.glob(File.join(dir, "*.png"), File::FNM_CASEFOLD).each do |path|
    dirname = File.dirname(path)
    basename = File.basename(path, ".png")
    next if basename.end_with?(suffix)

    target = File.join(dirname, "#{basename}#{suffix}.png")
    FileUtils.mv(path, target, force: true)
  end
end

def cleanup_generated_webps(dir)
  %w[_portrait.webp _landscape.webp].each do |suffix|
    Dir.glob(File.join(dir, "*#{suffix}"), File::FNM_CASEFOLD).each do |path|
      FileUtils.rm_f(path)
    end
  end
end

# -------------------------------------------------------------
# 前提チェック
# -------------------------------------------------------------

ensure_command!("magick", "ImageMagick")
ensure_command!(options[:waifu2x], "waifu2x")

scripts_root = File.expand_path(__dir__)
trim_script = File.join(scripts_root, "trim_image_borders.rb")
diagonal_script = File.join(scripts_root, "diagonal_split_transform.rb")

[trim_script, diagonal_script].each do |script_path|
  abort "必要なスクリプトが見つかりません: #{script_path}" unless File.exist?(script_path)
end

input_dir = File.expand_path(input_dir_arg)
abort "入力ディレクトリが見つかりません: #{input_dir}" unless Dir.exist?(input_dir)

trim_output_dir = File.expand_path(options[:trim_output] || File.join(input_dir, "trimmed"))
portrait_dir = File.expand_path(options[:portrait_output] || File.join(trim_output_dir, "diagonal_portrait"))
landscape_dir = File.expand_path(options[:landscape_output] || File.join(trim_output_dir, "diagonal_landscape"))
high_resolution_root = File.expand_path(options[:high_resolution_output] || File.join(input_dir, "high_resolution"))
intermediate_dir = File.join(high_resolution_root, "x#{options[:scale]}_png")
final_output_dir = File.expand_path(options[:webp_output] || input_dir)

FileUtils.mkdir_p(trim_output_dir)
[portrait_dir, landscape_dir].each { |dir| FileUtils.rm_rf(dir) }
FileUtils.rm_rf(high_resolution_root)
FileUtils.mkdir_p(portrait_dir)
FileUtils.mkdir_p(landscape_dir)
FileUtils.mkdir_p(high_resolution_root)
FileUtils.mkdir_p(final_output_dir)
FileUtils.rm_rf(intermediate_dir) unless options[:keep_intermediate]
FileUtils.mkdir_p(intermediate_dir)
cleanup_generated_webps(final_output_dir)

# -------------------------------------------------------------
# 1) トリミング
# -------------------------------------------------------------

trim_cmd = [RbConfig.ruby, trim_script, input_dir, trim_output_dir]
trim_cmd << "--fuzz=#{options[:fuzz]}" if options[:fuzz]
run_command!(trim_cmd, "trim_image_borders.rb")

# -------------------------------------------------------------
# 2) 対角線分割 (銀比 / シネスコ)
# -------------------------------------------------------------

diagonal_portrait_cmd = [RbConfig.ruby, diagonal_script, trim_output_dir, portrait_dir, "--ratio=silver"]
run_command!(diagonal_portrait_cmd, "diagonal_split_transform.rb (銀比)")
rename_with_suffix(portrait_dir, "_portrait")

diagonal_landscape_cmd = [RbConfig.ruby, diagonal_script, trim_output_dir, landscape_dir, "--ratio=cinemascope"]
run_command!(diagonal_landscape_cmd, "diagonal_split_transform.rb (シネスコ)")
rename_with_suffix(landscape_dir, "_landscape")

# -------------------------------------------------------------
# 3) 高解像度化 & WebP 変換
# -------------------------------------------------------------

source_images = Dir.glob(File.join(portrait_dir, "*.png")) + Dir.glob(File.join(landscape_dir, "*.png"))
if source_images.empty?
  warn "変換対象の PNG が見つかりません。前段の処理結果を確認してください。"
  exit 1
end

source_images.sort.each do |image_path|
  basename = File.basename(image_path, ".png")
  waifu_output_path = File.join(intermediate_dir, "#{basename}_color_x#{options[:scale]}.png")
  alpha_path = File.join(intermediate_dir, "#{basename}_alpha.png")
  alpha_scaled_path = File.join(intermediate_dir, "#{basename}_alpha_x#{options[:scale]}.png")
  merged_path = File.join(intermediate_dir, "#{basename}_merged_x#{options[:scale]}.png")
  webp_path = File.join(final_output_dir, "#{basename}.webp")

  alpha_cmd = [
    "magick", image_path,
    "-alpha", "extract",
    "PNG32:#{alpha_path}"
  ]

  unless run_command_warn(alpha_cmd, "アルファ抽出 (#{basename})")
    next
  end

  waifu_cmd = [
    options[:waifu2x],
    "-i", image_path,
    "-o", waifu_output_path,
    "-n", options[:waifu2x_noise].to_s,
    "-s", options[:scale].to_s
  ] + options[:waifu2x_args]

  puts "==> waifu2x: #{basename}"
  unless run_command_warn(waifu_cmd, "waifu2x (#{basename})")
    next
  end

  scale_percent = format("%.2f%%", options[:scale].to_f * 100)
  alpha_resize_cmd = [
    "magick", alpha_path,
    "-filter", "catrom",
    "-resize", scale_percent,
    "PNG32:#{alpha_scaled_path}"
  ]

  unless run_command_warn(alpha_resize_cmd, "アルファ拡大 (#{basename})")
    next
  end

  compose_cmd = [
    "magick", waifu_output_path, alpha_scaled_path,
    "-compose", "CopyAlpha", "-composite",
    "PNG32:#{merged_path}"
  ]

  unless run_command_warn(compose_cmd, "アルファ再適用 (#{basename})")
    next
  end

  convert_cmd = [
    "magick", merged_path,
    "-alpha", "set",
    "-background", "none",
    "-transparent", "white",
    "-resize", "#{options[:target_width]}x",
    "-quality", options[:webp_quality].to_s,
    webp_path
  ]

  puts "==> webp変換: #{basename}"
  unless run_command_warn(convert_cmd, "ImageMagick 変換 (#{basename})")
    next
  end

  unless options[:keep_intermediate]
    [waifu_output_path, alpha_path, alpha_scaled_path, merged_path].each do |tmp|
      FileUtils.rm_f(tmp)
    end
  end
  puts "    -> #{webp_path}"
end

unless options[:keep_intermediate]
  FileUtils.rm_rf(intermediate_dir)
  if Dir.exist?(high_resolution_root) && Dir.children(high_resolution_root).empty?
    Dir.rmdir(high_resolution_root)
  end
end

trim_output_removed = false
portrait_output_removed = false
landscape_output_removed = false

unless trim_output_specified
  FileUtils.rm_rf(trim_output_dir)
  trim_output_removed = true
  if portrait_dir.start_with?(trim_output_dir)
    portrait_output_removed = true
  end
  if landscape_dir.start_with?(trim_output_dir)
    landscape_output_removed = true
  end
end

puts "\n処理が完了しました。"
puts "  トリミング出力: #{trim_output_dir}#{trim_output_removed ? " (削除済み)" : ""}"
puts "  銀比 PNG:       #{portrait_dir}#{portrait_output_removed ? " (削除済み)" : ""}"
puts "  シネスコ PNG:    #{landscape_dir}#{landscape_output_removed ? " (削除済み)" : ""}"
puts "  WebP 出力:       #{final_output_dir}"

puts "\n必要に応じて waifu2x パラメータ (--waifu2x-args など) を調整してください。"
