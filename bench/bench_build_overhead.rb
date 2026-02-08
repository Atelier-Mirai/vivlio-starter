# frozen_string_literal: true

# ================================================================
# bench/bench_build_overhead.rb
# ================================================================
# 計測1: npx vivliostyle build の起動オーバーヘッド
#
# 最小構成（1ページ HTML）で vivliostyle build を実行し、
# 純粋な起動〜終了の所要時間を計測する。
# 3回実行して平均・最小・最大を報告する。
#
# 使い方:
#   ruby bench/bench_build_overhead.rb
# ================================================================

require 'fileutils'
require 'tmpdir'

ITERATIONS = 3

Dir.mktmpdir('vs-bench-') do |dir|
  # 最小 HTML
  File.write(File.join(dir, 'minimal.html'), <<~HTML)
    <!DOCTYPE html>
    <html lang="ja">
    <head><meta charset="utf-8"><title>bench</title></head>
    <body><p>Hello</p></body>
    </html>
  HTML

  # entries.js
  File.write(File.join(dir, 'entries.js'), <<~JS)
    const defined = [{ path: 'minimal.html' }];
    export default defined;
  JS

  # vivliostyle.config.js
  File.write(File.join(dir, 'vivliostyle.config.js'), <<~JS)
    import entries from './entries.js';
    const vivliostyleConfig = {
      title: 'Benchmark',
      language: 'ja',
      entry: entries,
      output: ['./bench_output.pdf']
    };
    export default vivliostyleConfig;
  JS

  puts "=== 計測1: npx vivliostyle build 起動オーバーヘッド ==="
  puts "作業ディレクトリ: #{dir}"
  puts "反復回数: #{ITERATIONS}"
  puts

  timings = []

  ITERATIONS.times do |i|
    # 出力 PDF があれば削除
    out_pdf = File.join(dir, 'bench_output.pdf')
    FileUtils.rm_f(out_pdf)

    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    success = system('npx', 'vivliostyle', 'build',
                     chdir: dir,
                     out: File::NULL, err: File::NULL)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start

    status = success ? 'OK' : 'FAIL'
    pdf_exists = File.exist?(out_pdf) ? 'PDF生成済' : 'PDF未生成'
    timings << elapsed
    puts format("  Run %d: %.3fs (%s, %s)", i + 1, elapsed, status, pdf_exists)
  end

  puts
  puts format("  平均: %.3fs", timings.sum / timings.size)
  puts format("  最小: %.3fs", timings.min)
  puts format("  最大: %.3fs", timings.max)
  puts
end
