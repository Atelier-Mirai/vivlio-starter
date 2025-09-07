#!/usr/bin/env ruby
# frozen_string_literal: true

require 'csv'
require 'time'

# Read timings.csv (chapter,step,seconds)
path = File.join(Dir.pwd, 'timings.csv')
unless File.exist?(path)
  warn 'timings.csv が見つかりません'
  exit 1
end

rows = []
CSV.foreach(path, headers: true) do |r|
  chapter = r['chapter']&.strip
  step    = r['step']&.strip
  sec     = r['seconds']
  next if chapter.nil? || step.nil? || sec.nil?
  seconds = sec.to_f
  rows << [chapter, step, seconds]
end

if rows.empty?
  puts "timings.csv にデータがありません"
  exit 0
end

# Chapters: collect observed numeric chapters only (e.g., 00-titlepage -> 00)
chapter_keys = rows.map do |(ch, _st, _s)|
  if ch =~ /\A(\d{2})-/
    $1
  else
    ch # e.g., __full__ など
  end
end

# prefer two-digit numeric keys
chap_nums = chapter_keys.select { |k| k =~ /\A\d{2}\z/ }.uniq.sort

# Map chapter key -> list of basenames (keep first occurrence)
# Also compute mapping from two-digit key to full chapter basename for reference
chapter_full_names = {}
rows.each do |(ch, _st, _s)|
  if ch =~ /\A(\d{2})-/
    chapter_full_names[$1] ||= ch
  end
end

# Pre-compute line counts for each chapter (prefer processed root <basename>.md, fallback to contents/<basename>.md)
def count_lines_for(basename)
  candidates = [
    File.join(Dir.pwd, "#{basename}.md"),
    File.join(Dir.pwd, 'contents', "#{basename}.md")
  ]
  candidates.each do |p|
    if File.exist?(p)
      begin
        return File.foreach(p).count
      rescue
        # ignore and continue
      end
    end
  end
  nil
end

line_counts = {}
chap_nums.each do |num|
  basename = chapter_full_names[num]
  next unless basename
  line_counts[num] = count_lines_for(basename)
end

# Steps: include Step 0..13 if present, then known per-chapter steps, then others
step_set = rows.map { |(_, st, _)| st }.uniq
step_order = []
# Step 0..13
(0..13).each do |i|
  label = format('Step %d', i)
  step_order << label if step_set.include?(label)
end
# Known chapter steps
%w[pre_process convert post_process entries pdf].each do |st|
  step_order << st if step_set.include?(st)
end
# Others
(step_set - step_order).sort.each { |st| step_order << st }

# Build aggregation: value[step][chap_num] = sum seconds
values = Hash.new { |h, k| h[k] = Hash.new(0.0) }
step_totals = Hash.new(0.0)
full_build_values = {} # for Step N rows with chapter == __full__ (optional)

rows.each do |(ch, st, s)|
  if ch == '__full__'
    full_build_values[st] = (full_build_values[st] || 0.0) + s
    next
  end
  key = (ch =~ /\A(\d{2})-/) ? $1 : nil
  next unless key && chap_nums.include?(key)
  values[st][key] += s
  step_totals[st] += s
end

# Column widths
col_width = 7 # for numbers like 123.45
chap_cols = chap_nums

header = [''.ljust(8)] + chap_cols.map { |c| c.rjust(col_width) } + ['合計'.rjust(col_width), '全章ビルド(参考)'.rjust(col_width)]
sep = '-' * (header.join(' ').size)

puts header.join(' ')
puts sep

# Print rows
grand_total = 0.0
full_build_total = 0.0

step_order.each do |st|
  label = st.start_with?('Step ') ? st : st
  line = label.ljust(8)
  row_sum = 0.0
  chap_cols.each do |c|
    v = values[st][c] || 0.0
    row_sum += v
    line << ' ' + (v.zero? ? ''.rjust(col_width) : format('%6.2f', v))
  end
  line << ' ' + (row_sum.zero? ? ''.rjust(col_width) : format('%6.2f', row_sum))
  fb = full_build_values[st]
  if fb
    full_build_total += fb
  end
  line << ' ' + (fb ? format('%6.2f', fb) : ''.rjust(col_width))
  puts line
  grand_total += row_sum
end

# Total row
puts sep
total_line = 'Total'.ljust(8)
chap_totals = Hash.new(0.0)
chap_cols.each do |c|
  sum = step_order.inject(0.0) { |acc, st| acc + (values[st][c] || 0.0) }
  chap_totals[c] = sum
  total_line << ' ' + (sum.zero? ? ''.rjust(col_width) : format('%6.2f', sum))
end

total_line << ' ' + (grand_total.zero? ? ''.rjust(col_width) : format('%6.2f', grand_total))

total_line << ' ' + (full_build_total.zero? ? ''.rjust(col_width) : format('%6.2f', full_build_total))
puts total_line

# Lines row
lines_label = 'Lines'.ljust(8)
lines_sum = 0
chap_cols.each do |c|
  lc = line_counts[c]
  if lc
    lines_sum += lc
  end
  lines_label << ' ' + (lc ? lc.to_s.rjust(col_width) : ''.rjust(col_width))
end
lines_label << ' ' + (lines_sum > 0 ? lines_sum.to_s.rjust(col_width) : ''.rjust(col_width))
lines_label << ' ' + ''.rjust(col_width)
puts lines_label
