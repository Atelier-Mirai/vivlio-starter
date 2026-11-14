# frozen_string_literal: true

# ================================================================
# scripts/pdf_pixel_diff.rb — 二つの PDF を、全ページの画素で比べる
# ================================================================
# 使い方:
#   ruby scripts/pdf_pixel_diff.rb <基準の PDF> <新しい PDF> [--out DIR] [--dpi N]
#
#   --out DIR  違うページの差の画像（page-0012.png など）を書き出す先。
#              省略すると、差があったときだけ一時のディレクトリに書き出し、その場所を示す
#   --dpi N    画像にする解像度（既定: 100）
#
# 終了コード: 0 = 全ページが一致 / 1 = 違うページがある・ページ数が違う / 2 = 比べられなかった
#
# 許容は 0 画素である（`v2-migration-plan.md` §3.3）。「差は小さいので許す」をしないので、
# 違う画素が 1 つでもあれば違うページとして数える。
#
# 画像にするのは pdftoppm（poppler）、比べるのは ImageMagick の compare -metric AE。
# 文字の位置だけを比べたいとき（色だけが変わることの確かめ）は、この道具ではなく
# pdftotext -bbox の座標を比べる。
# ================================================================

require 'etc'
require 'fileutils'
require 'open3'
require 'optparse'
require 'tmpdir'

options = { dpi: 100 }
parser = OptionParser.new do |o|
  o.banner = 'usage: ruby scripts/pdf_pixel_diff.rb <base.pdf> <new.pdf> [--out DIR] [--dpi N]'
  o.on('--out DIR') { options[:out] = File.expand_path(it) }
  o.on('--dpi N', Integer) { options[:dpi] = it }
end
base_pdf, new_pdf = parser.parse(ARGV)
abort parser.banner unless base_pdf && new_pdf

[base_pdf, new_pdf].each do |pdf|
  next if File.file?(pdf)

  warn "PDF が見つかりません: #{pdf}"
  exit 2
end

# PDF を 1 ページ 1 枚の PNG にし、ページ順に並べて返す。
# pdftoppm は総ページ数に合わせて番号の桁を変える（-01・-001）ので、名前の数字で並べる。
def rasterize(pdf, dir, dpi)
  _out, err, status = Open3.capture3('pdftoppm', '-r', dpi.to_s, '-png', pdf, File.join(dir, 'p'))
  unless status.success?
    warn "pdftoppm に失敗しました: #{pdf}\n#{err}"
    exit 2
  end
  Dir.glob(File.join(dir, 'p-*.png')).sort_by { it[/-(\d+)\.png\z/, 1].to_i }
end

# 二枚の画像の、違う画素の数を返す。寸法が違えば nil（ページの大きさが変わった）。
# compare は似ていれば 0・違えば 1・比べられなければ 2 で終わり、数を標準エラーへ書く。
def differing_pixels(base_png, new_png)
  _out, err, status = Open3.capture3('magick', 'compare', '-metric', 'AE', base_png, new_png, 'null:')
  return nil if status.exitstatus == 2

  err[/\A[\d.e+]+/].to_f.to_i
end

Dir.mktmpdir('pdf-pixel-diff') do |work|
  # --- Phase: 画像にする（二つの PDF を並行して） ---
  base_dir = File.join(work, 'base')
  new_dir = File.join(work, 'new')
  FileUtils.mkdir_p([base_dir, new_dir])
  threads = [[base_pdf, base_dir], [new_pdf, new_dir]].map do |pdf, dir|
    Thread.new { rasterize(pdf, dir, options[:dpi]) }
  end
  base_pages, new_pages = threads.map(&:value)

  # --- Phase: ページごとに比べる ---
  pairs = base_pages.zip(new_pages).take([base_pages.size, new_pages.size].min)
  queue = Queue.new
  pairs.each_with_index { |pair, i| queue << [i + 1, *pair] }
  queue.close
  results = {}
  mutex = Mutex.new
  Array.new(Etc.nprocessors) do
    Thread.new do
      while (job = queue.pop)
        page, base_png, new_png = job
        count = differing_pixels(base_png, new_png)
        mutex.synchronize { results[page] = [count, base_png, new_png] }
      end
    end
  end.each(&:join)

  differing = results.sort.reject { |_page, (count, _b, _n)| count&.zero? }

  # --- Phase: 報告する ---
  puts "基準:   #{base_pdf}（#{base_pages.size} ページ）"
  puts "新しい: #{new_pdf}（#{new_pages.size} ページ）"
  page_count_differs = base_pages.size != new_pages.size
  puts "ページ数が違います: #{base_pages.size} → #{new_pages.size}（先頭の #{pairs.size} ページを比べました）" if page_count_differs

  if differing.empty?
    puts "違うページ: 0（#{pairs.size} ページを #{options[:dpi]}dpi で比べました）"
    exit(page_count_differs ? 1 : 0)
  end

  out = options[:out] || Dir.mktmpdir('pdf-pixel-diff-out')
  FileUtils.mkdir_p(out)
  puts "違うページ: #{differing.size}"
  differing.each do |page, (count, base_png, new_png)|
    label = count.nil? ? 'ページの寸法が違う' : "#{count} 画素"
    diff_png = File.join(out, format('page-%04d.png', page))
    # 寸法が違うと差の画像は作れないので、両方の画像を並べて残す。
    if count.nil?
      FileUtils.cp(base_png, diff_png.sub('.png', '-base.png'))
      FileUtils.cp(new_png, diff_png.sub('.png', '-new.png'))
    else
      Open3.capture3('magick', 'compare', base_png, new_png, diff_png)
    end
    puts format('  p%<page>d: %<label>s', page:, label:)
  end
  puts "差の画像: #{out}"
  exit 1
end
