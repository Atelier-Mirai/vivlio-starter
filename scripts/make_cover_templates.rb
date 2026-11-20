#!/usr/bin/env ruby
# frozen_string_literal: true

# scripts/make_cover_templates.rb
# 表紙を自作する著者へ配る雛形の画像を covers/templates/ に作る。
# 判型ごとに表と裏の 2 枚ずつ。判型は本文と表紙が使う表（Common::PAGE_SIZES）から引くので、
# 判型を足すと下敷きも増える（cover-size-independence-spec.md §5）。
#
# 使い方: ruby scripts/make_cover_templates.rb

require 'fileutils'
require 'tmpdir'
require_relative '../lib/vivlio_starter/cli/cover'

# 複製元はプロジェクトルート（scripts/ の一つ上）。どこから起動しても同じ結果になる。
ROOT = File.expand_path('..', __dir__)
OUTPUT_DIR = File.join(ROOT, 'covers', 'templates')

# 判型ごとの仕上がりの寸法（CoverCommands::TrimSize）。JIS-B5 は B5 と同じ名前になるので 1 枚にまとめる
PAGES = VivlioStarter::CLI::Common::PAGE_SIZES.keys
                                            .map { VivlioStarter::CLI::CoverCommands.trim_size(size: it) }
                                            .uniq(&:name)
                                            .freeze

DPI = VivlioStarter::CLI::CoverCommands::DPI
MM_PER_INCH = 25.4

# 裁ち落とされる幅（output.print_pdf.bleed の既定値）
BLEED_MM = 3

# 文字を置ける内側の線。断裁のずれを見込んで裁ち落としより 2 mm 内へ取る。
SAFE_MM = 5

# 電子書籍の表紙の縦横比（CoverCommands::EPUB_SIZE）。高さをそろえて左右を切るので、
# この比より横に広い判型は左右の帯が見えなくなる。新書のように細長い判型は左右が切れないので、帯を描かない。
EBOOK_ASPECT = 1600.0 / 2560

# 字の大きさを高さで決める判型の比の上限（高さ ÷ 幅）。これより細長い判型は幅で決める
TEXT_ASPECT_LIMIT = 1.45

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
  width = page.width
  height = page.height
  trim_w, trim_h = page.mm
  bleed = mm_to_px(BLEED_MM)
  safe = mm_to_px(SAFE_MM)
  ebook_band = ((width - (height * EBOOK_ASPECT)) / 2).round
  ebook = side[:ebook] && ebook_band.positive?
  bleed_w = mm_to_px(trim_w + (BLEED_MM * 2))
  bleed_h = mm_to_px(trim_h + (BLEED_MM * 2))
  unit = height / 100.0
  # 字と見本の大きさの単位。高さの 100 分の 1 だが、新書のように細長い判型では幅で抑える
  # （高さで決めると、使い方の行が左右の端まで届く）。A 列・B 列は高さのまま
  text_unit = [height, width * TEXT_ASPECT_LIMIT].min / 100.0
  center = width / 2
  swatch_x = (width * 0.2).round
  label_x = swatch_x + (text_unit * 5).round
  swatch_w = (text_unit * 3.6).round
  swatch_h = (text_unit * 1.8).round

  # --- Phase: 目安の線と帯 ---
  bands = []
  if ebook
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
    text_tag("#{side[:label]}の雛形", center, (unit * 24).round, (text_unit * 4.2).round, weight: 700),
    text_tag("#{page.label}（#{trim_w} × #{trim_h} mm）", center, (unit * 30).round, (text_unit * 2.6).round),
    text_tag("#{with_comma(width)} × #{with_comma(height)} px", center, (unit * 38).round, (text_unit * 4.6).round, weight: 700),
    text_tag("#{DPI} dpi", center, (unit * 42).round, (text_unit * 2).round)
  ]

  # --- Phase: 凡例 ---
  legend = [["裁ち落とされる範囲（#{BLEED_MM} mm）", BLEED_COLOR]]
  ebook_mm = (ebook_band / unit * trim_h / 100).round
  legend << ["電子書籍では切れる範囲（左右 #{ebook_mm} mm ずつ）", EBOOK_COLOR] if ebook
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
    lines << text_tag(label, label_x, y, (text_unit * 1.9).round, anchor: 'start')
  end

  # --- Phase: 使い方 ---
  [
    ["完成したら covers/#{side[:master]}.png として保存し、", 68],
    ['book.yml を cover: master にします。', 71.4],
    ["塗り足しまで描くときは #{side[:master]}_bleed.png", 76.6],
    ["（#{with_comma(bleed_w)} × #{with_comma(bleed_h)} px）で保存します。", 80],
    ['仕上げるときは、この文字と線を消してください。', 85.2]
  ].each { |text, row| lines << text_tag(text, center, (unit * row).round, (text_unit * 1.9).round) }

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
PAGES.each do |page|
  SIDES.each do |side_name, side|
    output = File.join(OUTPUT_DIR, "#{side_name}cover_#{page.name}.png")
    write_png(template_svg(page, side), output)
    puts "WRITE covers/templates/#{File.basename(output)}（#{File.size(output) / 1024} KB）"
  end
end
