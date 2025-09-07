#!/usr/bin/env ruby
# frozen_string_literal: true
# Benchmark Vivliostyle build time between two entries forms:
# 1) Separate entries: 98-postface.html and 99-colophon.html
# 2) Combined single HTML: combined_98_99.html
# Runs each case 3 times and prints per-run times and averages.

require 'fileutils'
require 'open3'

ROOT = Dir.pwd
ENTRIES_BENCH = File.join(ROOT, 'entries_bench.js')
VIV_CONFIG_BENCH = File.join(ROOT, 'vivliostyle.config.bench.js')
OUTPUT_PDF = File.join(ROOT, 'bench_output.pdf')

VIV_CONFIG_TEMPLATE = <<~JS
  import entries from './entries_bench.js';
  // @ts-check
  /** @type {import('@vivliostyle/cli').VivliostyleConfigSchema} */
  const vivliostyleConfig = {
    title: 'Bench',
    author: 'bench',
    language: 'ja',
    readingProgression: 'ltr',
    entry: entries,
    output: [
      './bench_output.pdf'
    ]
  };
  export default vivliostyleConfig;
JS

SEPARATE_ENTRIES = <<~JS
  export default [
    { "path": "./98-postface.html",  "title": "postface"  },
    { "path": "./99-colophon.html", "title": "colophon" }
  ];
JS

COMBINED_ENTRY = <<~JS
  export default [
    './combined_98_99.html'
  ];
JS

# Ensure combined file exists
combined_html = File.join(ROOT, 'combined_98_99.html')
unless File.exist?(combined_html)
  abort "combined_98_99.html が見つかりません。先に生成してください。"
end

# Write bench config once
File.write(VIV_CONFIG_BENCH, VIV_CONFIG_TEMPLATE, encoding: 'utf-8')

# Helper to run vivliostyle build and extract real seconds
# Returns Float seconds, also prints through

def run_once
  FileUtils.rm_f(OUTPUT_PDF)
  cmd = [
    '/usr/bin/time', '-p', 'npx', 'vivliostyle', 'build',
    '-c', 'vivliostyle.config.bench.js', '-o', 'bench_output.pdf'
  ]
  stdout, stderr, status = Open3.capture3(*cmd)
  # macOS time writes to stderr like:
  # real 14.33\nuser 3.50\nsys 1.33
  real = nil
  stderr.each_line do |line|
    if line.start_with?('real ')
      real = line.split.last.to_f
    end
  end
  puts stdout unless stdout.to_s.empty?
  warn stderr unless stderr.to_s.empty?
  raise 'build failed' unless status.success?
  raise 'bench_output.pdf not generated' unless File.exist?(OUTPUT_PDF)
  real || Float::NAN
end

# Run a case N times

def run_case!(label, entries_js, n = 3)
  puts "\n== Case: #{label} =="
  File.write(ENTRIES_BENCH, entries_js, encoding: 'utf-8')
  times = []
  n.times do |i|
    puts "-- Run #{i+1}/#{n} --"
    t = run_once
    times << t
    puts format("real %.2fs", t)
  end
  avg = times.compact.sum / times.size
  puts format("Average: %.2fs (n=%d)", avg, times.size)
  avg
end

begin
  run_case!('Separate (98-postface + 99-colophon)', SEPARATE_ENTRIES, 3)
  run_case!('Combined (combined_98_99.html)', COMBINED_ENTRY, 3)
ensure
  # Cleanup bench files but keep PDFs for inspection
  # FileUtils.rm_f(ENTRIES_BENCH)
  # FileUtils.rm_f(VIV_CONFIG_BENCH)
end
