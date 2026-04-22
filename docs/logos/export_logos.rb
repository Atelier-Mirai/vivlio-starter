#!/usr/bin/env ruby
# frozen_string_literal: true

# logos/ 以下の SVG を PNG / WebP に書き出すスクリプト。
# 出力先: contents/logos/png/  および  contents/logos/webp/
#
# 使い方:
#   ruby contents/logos/export_logos.rb
#
# 依存コマンド:
#   rsvg-convert  — SVG → PNG（Homebrew: librsvg）
#   magick        — PNG → WebP（Homebrew: imagemagick）

require 'fileutils'

LOGOS_DIR = File.expand_path(__dir__)
PNG_DIR   = File.join(LOGOS_DIR, 'png')
WEBP_DIR  = File.join(LOGOS_DIR, 'webp')

# SVG ファイル名 => 出力幅(px)。viewBox の幅に合わせた 2x 解像度。
FILES = {
  'vivlio_starter_logo_outline.svg'          => 2400,
  'vivlio_starter_logo_outline_stacked.svg'  => 1200,
  'vivlio_starter_logo_text.svg'             => 2400,
  'vivlio_starter_logo_text_stacked.svg'     => 1200,
  'vs_logo_outline.svg'                      =>  720,
  'vs_logo_outline_garnish.svg'              => 2400,
  'vs_logo_text_garnish.svg'                 => 2400,
  'vs_vivlio_starter_logo_outline.svg'       => 3200,
  'vs_vivlio_starter_logo_outline_stacked.svg' => 1800,
  'vs_vivlio_starter_logo_text.svg'          => 3200,
  'vs_vivlio_starter_logo_text_stacked.svg'  => 1800,
}.freeze

def run(cmd)
  success = system(*cmd)
  raise "失敗: #{cmd.join(' ')}" unless success
end

FileUtils.mkdir_p(PNG_DIR)
FileUtils.mkdir_p(WEBP_DIR)

FILES.each do |filename, width|
  svg  = File.join(LOGOS_DIR, filename)
  base = File.basename(filename, '.svg')
  png  = File.join(PNG_DIR,  "#{base}.png")
  webp = File.join(WEBP_DIR, "#{base}.webp")

  unless File.exist?(svg)
    warn "スキップ（見つかりません）: #{filename}"
    next
  end

  # SVG → PNG（rsvg-convert: 幅指定、高さは自動）
  run ['rsvg-convert', '-w', width.to_s, svg, '-o', png]
  puts "PNG: #{File.basename(png)}"

  # PNG → WebP lossless（magick）
  run ['magick', png, '-define', 'webp:lossless=true', webp]
  puts "WebP: #{File.basename(webp)}"
end

puts "\n完了。出力先: #{PNG_DIR}"
