#!/usr/bin/env ruby
# frozen_string_literal: true

require 'yaml'
require 'time'
require 'open3'
require 'fileutils'
require 'etc'

CONFIG_PATH = File.join(Dir.pwd, 'config', 'book.yml')
RESULT_CSV  = File.join(Dir.pwd, 'chapters_scaling.csv')
STEPS_CSV   = File.join(Dir.pwd, 'chapters_scaling_steps.csv')
SUMMARY_MD  = File.join(Dir.pwd, 'timings_summary.md')

# Collect optional chapters basenames (02..98)
contents = File.join(Dir.pwd, 'contents')
# Get all chapter files and filter by numeric range 02..98
optionals = Dir.glob(File.join(contents, '*.md'))
                .select { |p| File.basename(p) =~ /\A(\d{2})-/ && $1.to_i.between?(2, 98) }
                .sort_by { |p|
                  bn = File.basename(p)
                  num = bn[/\A(\d{2})-/, 1].to_i
                  [num, bn]
                }
                .map { |p| File.basename(p) }
if optionals.empty?
  warn 'No optional chapters (02..98) found under contents/. Abort.'
  exit 1
end

# Append a Markdown-formatted Build Step Timings block to timings_summary.md
def append_markdown_timings(k, build_output, chapters, mode = nil)
  count = chapters ? chapters.size : 'all'
  fl = if chapters && !chapters.empty?
         [chapters.first, chapters.last].join('..')
       else
         ''
       end

  ts = Time.now.iso8601
  lines = []
  mode_desc = mode ? ", mode=#{mode}" : ''
  header = if count == 'all'
             "## Build Step Timings (scaling k=#{k}, chapters=all#{mode_desc}, #{ts})"
           else
             "## Build Step Timings (scaling k=#{k}, chapters=#{count} #{fl.empty? ? '' : '(' + fl + ')'}#{mode_desc}, #{ts})"
           end
  lines << header
  lines << "\n```"
  lines << "== Build Step Timings =="
  build_output.each_line do |line|
    s = line.rstrip
    if s =~ /^\s*-\s+.*?\s+[0-9.]+s\s*$/ || s =~ /^\s*=\s*TOTAL\s+[0-9.]+s\s*$/
      lines << s
    end
  end
  lines << "```"
  File.open(SUMMARY_MD, 'a', encoding: 'utf-8') { |f| f.puts(lines.join("\n")) }
rescue
  # ignore summary append errors
end

# Return the array of chapter entries to write to YAML (strings as given)
def scenario_chapters(optionals, k)
  return nil if k.nil? || k <= 0
  optionals.first(k)
end

# Load and write config/book.yml safely
orig_text = File.read(CONFIG_PATH, encoding: 'utf-8')
orig_cfg = YAML.load(orig_text) || {}

# Helper: write chapters key to config
# - chapters=nil: removes key (interpreted as 'all')
# - chapters=[...]: write as array (normalized basenames as strings)
def write_chapters_config(cfg_base, chapters)
  cfg = Marshal.load(Marshal.dump(cfg_base))
  if chapters.nil?
    cfg.delete('chapters')
  else
    cfg['chapters'] = chapters
  end
  yaml = YAML.dump(cfg)
  File.write(CONFIG_PATH, yaml, encoding: 'utf-8')
end

# Run full build and capture total seconds from Build Step Timings
# Returns [total_seconds, raw_output]
def run_full_build(env = {})
  cmd = ['bin/vs', 'build']
  t0 = Time.now
  out, err, status = Open3.capture3(env, *cmd)
  t1 = Time.now
  total = nil
  # Prefer parsing TOTAL line, fallback to wall time
  if out =~ /^\s*=\s*TOTAL\s+([0-9.]+)s/m
    total = $1.to_f
  else
    total = (t1 - t0).to_f
  end
  [total, out + err]
end

# Append result row
# Columns: k, total_seconds, chapter_count, first_last, chapters
def append_result(k, total, chapters, mode = nil)
  write_header = !File.exist?(RESULT_CSV) || File.zero?(RESULT_CSV)
  File.open(RESULT_CSV, 'a', encoding: 'utf-8') do |f|
    if write_header
      f.puts 'k,total_seconds,chapter_count,first_last,chapters,mode'
    end
    count = chapters ? chapters.size : 'all'
    fl = if chapters && !chapters.empty?
           [chapters.first, chapters.last].join('..')
         else
           ''
         end
    f.puts [k, format('%.2f', total), count, fl, (chapters ? chapters.join(' ') : ''), (mode || '')].join(',')
  end
end

# Parse per-step timings from build output and append to STEPS_CSV
# Expected lines (as printed by build.rb):
#   - Step 0 (clean)                       0.02s
#   = TOTAL                              251.73s
def append_steps(k, build_output, chapters, mode = nil)
  # Build chapter count/first_last for context
  count = chapters ? chapters.size : 'all'
  fl = if chapters && !chapters.empty?
         [chapters.first, chapters.last].join('..')
       else
         ''
       end

  write_header = !File.exist?(STEPS_CSV) || File.zero?(STEPS_CSV)
  File.open(STEPS_CSV, 'a', encoding: 'utf-8') do |f|
    f.puts 'k,step,seconds,chapter_count,first_last,mode' if write_header
    build_output.each_line do |line|
      line = line.rstrip
      if line =~ /^\s*-\s+(.*?)\s+([0-9.]+)s\s*$/
        step_label = $1
        secs = $2.to_f
        f.puts [k, step_label, format('%.2f', secs), count, fl, (mode || '')].join(',')
      elsif line =~ /^\s*=\s*TOTAL\s+([0-9.]+)s\s*$/
        secs = $1.to_f
        f.puts [k, 'TOTAL', format('%.2f', secs), count, fl, (mode || '')].join(',')
      end
    end
  end
end

# Main loop
begin
  puts "[Benchmark] Optional chapters total: #{optionals.size}"
  # Scenario 0: chapters not specified (full build baseline)
  puts "[Benchmark] Scenario k=0 (chapters unset → full set)"
  write_chapters_config(orig_cfg, nil)
  total, out = run_full_build
  append_result(0, total, nil, 'baseline')
  append_steps(0, out, nil, 'baseline')
  append_markdown_timings(0, out, nil, 'baseline')

  # AB: single-doc 有無 × 並列N（Step5並列） at k=0
  max_n = Etc.respond_to?(:nprocessors) ? Etc.nprocessors : 4
  levels = [1, 2, 4].select { |n| n <= max_n }
  single_docs = [0, 1]
  single_docs.each do |sd|
    levels.each do |n|
      mode = "singleDoc=#{sd},conc=#{n}"
      puts "[Benchmark] AB mode: #{mode}"
      env = {}
      env['VIVLIO_SINGLE_DOC'] = sd == 1 ? '1' : '0'
      env['VIVLIO_BUILD_CONCURRENCY'] = n.to_s
      total2, out2 = run_full_build(env)
      append_result(0, total2, nil, mode)
      append_steps(0, out2, nil, mode)
      append_markdown_timings(0, out2, nil, mode)
    end
  end

  # Increasing scenarios
  (1..optionals.size).each do |k|
    chapters = scenario_chapters(optionals, k)
    puts "[Benchmark] Scenario k=#{k} (#{chapters.size} chapters)"
    write_chapters_config(orig_cfg, chapters)
    total, out = run_full_build
    append_result(k, total, chapters)
    append_steps(k, out, chapters)
    append_markdown_timings(k, out, chapters)
  end
ensure
  # Restore original config
  File.write(CONFIG_PATH, orig_text, encoding: 'utf-8')
  puts '[Benchmark] Restored original config/book.yml'
end
