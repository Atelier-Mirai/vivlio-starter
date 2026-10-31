#!/usr/bin/env ruby
# frozen_string_literal: true

# scripts/make_cover_templates.rb
# 表紙を自作する著者へ配る雛形の画像を covers/templates/ に作る。
# 判型ごとに表と裏の 2 枚ずつ（A4・B5・A5 で 6 枚）。
#
# 使い方: ruby scripts/make_cover_templates.rb

require 'fileutils'
require 'tmpdir'

# 複製元はプロジェクトルート（scripts/ の一つ上）。どこから起動しても同じ結果になる。
ROOT = File.expand_path('..', __dir__)
OUTPUT_DIR = File.join(ROOT, 'covers', 'templates')

# CoverCommands::SIZES と同じ値（cover_test.rb が突き合わせる）。
# lib を読むと book.yml まで読み込むので、ここへ写している。
SIZES = {
  a4: { width: 2894, height: 4093, mm: [210, 297] },
  b5: { width: 2508, height: 3541, mm: [182, 257] },
  a5: { width: 2039, height: 2894, mm: [148, 210] }
}.freeze

DPI = 350
MM_PER_INCH = 25.4

# 裁ち落とされる幅（output.print_pdf.bleed の既定値）
BLEED_MM = 3

# 文字を置ける内側の線。断裁のずれを見込んで裁ち落としより 2 mm 内へ取る。
SAFE_MM = 5

# 電子書籍の表紙の縦横比（CoverCommands::EPUB_SIZE）。高さをそろえて左右を切るので、
# この比より横に広い判型は左右の帯が見えなくなる。
EBOOK_ASPECT = 1600.0 / 2560

BLEED_COLOR = '#fbdcdc'
EBOOK_COLOR = '#dcebfb'
SAFE_COLOR = '#c0392b'
TEXT_COLOR = '#333333'
FONT_FAMILY = "'Hiragino Sans', 'Noto Sans CJK JP', sans-serif"

SIDES = {
  'front' => { label: '表紙', master: 'frontcover_master', ebook: true },
  'back' => { label: '裏表紙', master: 'backcover_master', ebook: false }
}.freeze

def mm_to_px(mm) = (mm / MM_PER_INCH * DPI).round

def with_comma(number) = number.to_s.reverse.scan(/\d{1,3}/).join(',').reverse

def text_tag(text, x, y, size, anchor: 'middle', weight: 400)
  %(<text x="#{x}" y="#{y}" font-size="#{size}" font-weight="#{weight}" text-anchor="#{anchor}">#{text}</text>)
end

# 雛形 1 枚の SVG を組み立てる。数値の単位はすべて画素。
def template_svg(page, side)
  # --- Phase: 寸法 ---
  width, height = page.values_at(:width, :height)
  trim_w, trim_h = page[:mm]
  bleed = mm_to_px(BLEED_MM)
  safe = mm_to_px(SAFE_MM)
  ebook_band = ((width - (height * EBOOK_ASPECT)) / 2).round
  bleed_w = mm_to_px(trim_w + (BLEED_MM * 2))
  bleed_h = mm_to_px(trim_h + (BLEED_MM * 2))
  unit = height / 100.0
  center = width / 2
  swatch_x = (width * 0.2).round
  label_x = swatch_x + (unit * 5).round
  swatch_w = (unit * 3.6).round
  swatch_h = (unit * 1.8).round

  # --- Phase: 目安の線と帯 ---
  bands = []
  if side[:ebook]
    bands << %(<rect x="0" y="0" width="#{ebook_band}" height="#{height}" fill="#{EBOOK_COLOR}"/>)
    bands << %(<rect x="#{width - ebook_band}" y="0" width="#{ebook_band}" height="#{height}" fill="#{EBOOK_COLOR}"/>)
  end
  inner = "M#{bleed} #{bleed}H#{width - bleed}V#{height - bleed}H#{bleed}Z"
  bands << %(<path d="M0 0H#{width}V#{height}H0Z#{inner}" fill="#{BLEED_COLOR}" fill-rule="evenodd"/>)
  dash = (unit * 0.8).round
  stroke = (unit * 0.12).round(1)
  bands << %(<rect x="#{safe}" y="#{safe}" width="#{width - (safe * 2)}" height="#{height - (safe * 2)}" fill="none" ) +
           %(stroke="#{SAFE_COLOR}" stroke-width="#{stroke}" stroke-dasharray="#{dash} #{dash}"/>)

  # --- Phase: 見出しと寸法 ---
  lines = [
    text_tag("#{side[:label]}の雛形", center, (unit * 24).round, (unit * 4.2).round, weight: 700),
    text_tag("#{page[:name]}（#{trim_w} × #{trim_h} mm）", center, (unit * 30).round, (unit * 2.6).round),
    text_tag("#{with_comma(width)} × #{with_comma(height)} px", center, (unit * 38).round, (unit * 4.6).round, weight: 700),
    text_tag("#{DPI} dpi", center, (unit * 42).round, (unit * 2).round)
  ]

  # --- Phase: 凡例 ---
  legend = [["裁ち落とされる範囲（#{BLEED_MM} mm）", BLEED_COLOR]]
  ebook_mm = (ebook_band / unit * trim_h / 100).round
  legend << ["電子書籍では切れる範囲（左右 #{ebook_mm} mm ずつ）", EBOOK_COLOR] if side[:ebook]
  legend << ["文字はこの線の内側へ（端から #{SAFE_MM} mm）", nil]
  legend.each_with_index do |(label, color), index|
    y = (unit * (50 + (index * 4))).round
    lines << if color
               %(<rect x="#{swatch_x}" y="#{y - swatch_h}" width="#{swatch_w}" height="#{swatch_h}" fill="#{color}" ) +
                 %(stroke="#{TEXT_COLOR}" stroke-width="1"/>)
             else
               %(<line x1="#{swatch_x}" y1="#{y - (swatch_h / 2)}" x2="#{swatch_x + swatch_w}" y2="#{y - (swatch_h / 2)}" ) +
                 %(stroke="#{SAFE_COLOR}" stroke-width="#{stroke}" stroke-dasharray="#{dash / 2} #{dash / 2}"/>)
             end
    lines << text_tag(label, label_x, y, (unit * 1.9).round, anchor: 'start')
  end

  # --- Phase: 使い方 ---
  [
    ["完成したら covers/#{side[:master]}.png として保存し、", 68],
    ['book.yml を cover: master にします。', 71.4],
    ["塗り足しまで描くときは #{side[:master]}_bleed.png", 76.6],
    ["（#{with_comma(bleed_w)} × #{with_comma(bleed_h)} px）で保存します。", 80],
    ['仕上げるときは、この文字と線を消してください。', 85.2]
  ].each { |text, row| lines << text_tag(text, center, (unit * row).round, (unit * 1.9).round) }

  <<~SVG
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 #{width} #{height}" width="#{width}" height="#{height}">
      <rect width="#{width}" height="#{height}" fill="#ffffff"/>
      #{bands.join("\n  ")}
      <g font-family="#{FONT_FAMILY}" fill="#{TEXT_COLOR}">
      #{lines.join("\n  ")}
      </g>
    </svg>
  SVG
end

# rsvg-convert の PNG は解像度の情報を持たない。作図ソフトで開いたときに
# 実寸で見えるよう、ImageMagick で 350 dpi を書き込む。
def write_png(svg, output)
  Dir.mktmpdir('cover-template') do |tmp|
    svg_path = File.join(tmp, 'template.svg')
    png_path = File.join(tmp, 'template.png')
    File.write(svg_path, svg, encoding: 'utf-8')
    abort "rsvg-convert に失敗しました: #{output}" unless system('rsvg-convert', '-f', 'png', '-o', png_path, svg_path)

    converted = system('magick', png_path, '-units', 'PixelsPerInch', '-density', DPI.to_s, output)
    abort "magick に失敗しました: #{output}" unless converted
  end
end

FileUtils.mkdir_p(OUTPUT_DIR)
SIZES.each do |size, page|
  SIDES.each do |side_name, side|
    output = File.join(OUTPUT_DIR, "#{side_name}cover_#{size}.png")
    write_png(template_svg(page.merge(name: size.to_s.upcase), side), output)
    puts "WRITE covers/templates/#{File.basename(output)}（#{File.size(output) / 1024} KB）"
  end
end
