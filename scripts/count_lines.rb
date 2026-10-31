#!/usr/bin/env ruby
# frozen_string_literal: true

require 'pathname'

# 集計の基準はプロジェクトルート（scripts/ の一つ上）。
ROOT = Pathname.new(File.expand_path('..', __dir__))

# 1ファイル分の行数集計結果。総計行にも同じ構造を流用する（path にラベルを入れる）。
FileStat = Data.define(:path, :total, :code, :comment) do
  # 複数の集計結果を畳み込み、ラベル付きの合計行を作る。
  def self.aggregate(label, stats)
    new(label, stats.sum(&:total), stats.sum(&:code), stats.sum(&:comment))
  end
end

# Ruby ソースの行数を数える。heredoc 本体と =begin/=end ブロックはコメント扱い・対象外として除外する。
def count_ruby(path)
  total = code = comment = 0
  in_block = in_heredoc = false
  heredoc_end = nil

  path.each_line do |line|
    total += 1
    stripped = line.strip

    if in_heredoc
      if heredoc_end && stripped.start_with?(heredoc_end)
        in_heredoc = false
        heredoc_end = nil
      end
      next
    end

    if in_block
      comment += 1
      in_block = false if stripped.start_with?('=end')
      next
    end

    next if stripped.empty?

    if stripped.start_with?('=begin')
      comment += 1
      in_block = true
    elsif line.lstrip.start_with?('#')
      comment += 1
    else
      code += 1
      if line =~ /<<[-~]?['"]?([A-Za-z0-9_]+)['"]?/
        heredoc_end = Regexp.last_match(1)
        in_heredoc = true
      end
    end
  end

  FileStat.new(path.relative_path_from(ROOT).to_s, total, code, comment)
end

# CSS の行数を数える。/* */ ブロックコメントと // 行コメントをコメントとして集計する。
def count_css(path)
  total = code = comment = 0
  in_block = false

  path.each_line do |line|
    total += 1
    stripped = line.strip

    if in_block
      comment += 1
      in_block = false if stripped.include?('*/')
      next
    end

    next if stripped.empty?

    if stripped.start_with?('/*')
      comment += 1
      # 同一行で閉じない、または */ の後に新たな /* が現れる場合はブロック継続。
      in_block = !stripped.include?('*/') || stripped.index('/*') > stripped.index('*/')
    elsif stripped.start_with?('//')
      comment += 1
    else
      code += 1
      in_block = true if stripped.include?('/*') && !stripped.include?('*/')
    end
  end

  FileStat.new(path.relative_path_from(ROOT).to_s, total, code, comment)
end

# Markdown の行数を数える。
def count_markdown(path)
  total = code = comment = 0
  in_block = false

  path.each_line do |line|
    total += 1
    stripped = line.strip

    next if stripped.empty?
  end

  code    = total
  comment = 0
  FileStat.new(path.relative_path_from(ROOT).to_s, total, code, comment)
end

# 全角文字は端末で 2 桁を占める。
def display_width(text) = text.each_char.sum { it.ascii_only? ? 1 : 2 }

def header(title) = format('%-*s %6s %6s %6s', PATH_WIDTH, title, 'total', 'code', 'comment')

# format の幅は文字数で数えるため、パスの欄は表示幅から求めた空白で埋める。
def format_row(stat)
  padding = ' ' * (PATH_WIDTH - display_width(stat.path))
  format('%s%s %6d %6d %6d', stat.path, padding, stat.total, stat.code, stat.comment)
end

def print_section(title, stats)
  puts title
  puts header('path')
  stats.each { puts format_row(it) }
end

# --- Phase: Collect ---
ruby_stats      = ROOT.glob('lib/vivlio_starter/**/*.rb').sort.map { count_ruby(it) }
test_stats      = ROOT.glob('test/vivlio_starter/**/*.rb').sort.map { count_ruby(it) }
css_stats       = ROOT.glob('stylesheets/**/*.css').sort.map { count_css(it) }
markdown_stats  = ROOT.glob('docs/**/*.md').sort.map { count_markdown(it) }

# パスの欄は最も長いパスに合わせる。固定幅だと長いパスの行だけ列がはみ出す。
PATH_WIDTH = [*ruby_stats, *test_stats, *css_stats, *markdown_stats].map { display_width(it.path) }.max

# --- Phase: Per-file output ---
print_section('Ruby files (lib/vivlio_starter/**/*.rb)', ruby_stats)
puts
print_section('Test files (test/vivlio_starter/**/*.rb)', test_stats)
puts
print_section('CSS files (stylesheets/**/*.css)', css_stats)
puts
print_section('Markdown files (docs/**/*.md)', markdown_stats)

# --- Phase: Totals ---
ruby_total = FileStat.aggregate("Ruby files (#{ruby_stats.size} files)", ruby_stats)
test_total      = FileStat.aggregate("Test files (#{test_stats.size} files)", test_stats)
css_total       = FileStat.aggregate("CSS files (#{css_stats.size} files)", css_stats)
markdown_total  = FileStat.aggregate("Markdown files (#{markdown_stats.size} files)", markdown_stats)

grand_size      = ruby_stats.size + test_stats.size + css_stats.size + markdown_stats.size
grand_total     = FileStat.aggregate("Grand Total (#{grand_size} files)", [ruby_total, test_total, css_total, markdown_total])

puts
puts header('Totals')
puts format_row(ruby_total)
puts format_row(test_total)
puts format_row(css_total)
puts format_row(markdown_total)
puts '-' * format_row(grand_total).size
puts format_row(grand_total)
