# frozen_string_literal: true
# 付録HTML(91-*.html〜95-*.html)を単一HTMLに結合するRakeタスク
# 使い方:
#   rake merge:appendix [DIR=入力ディレクトリ OUT=出力先]
# 既定:
#   DIR=.
#   OUT=appendices.html

require 'pathname'

namespace :merge do
  desc '付録HTML(91-*.html〜95-*.html)を単一HTMLに結合して出力する'
  task :appendices do
    dir = ENV['DIR'] || '.'
    out = ENV['OUT'] || '90-appendices.html'

    root = Pathname.new(dir)
    base_dir = root.expand_path
    unless root.directory?
      warn "❌ 入力ディレクトリが見つかりません: #{root}"
      exit 1
    end

    patterns = %w[91-*.html 92-*.html 93-*.html 94-*.html 95-*.html 96-*.html 97-*.html]
    files = patterns.flat_map { |p| Dir[base_dir.join(p).to_s] }
    files.sort!

    if files.empty?
      warn '❌ 対象ファイル(91-*.html〜97-*.html)が見つかりません'
      exit 1
    end

    puts '📝 対象ファイル:'
    files.each { |f| puts "  - #{Pathname.new(f).relative_path_from(base_dir)}" }

    read_text = ->(path) { File.read(path, encoding: 'UTF-8') }
    extract = ->(html, tag) do
      m = html.match(/<#{tag}\b[^>]*>(.*?)<\/#{tag}>/im)
      m ? m[1] : nil
    end

    first_html = read_text.call(files.first)
    head_inner = extract.call(first_html, 'head')
    head_html = if head_inner && !head_inner.strip.empty?
      "<head>\n#{head_inner}\n</head>"
    else
      <<~HEAD
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>Appendices</title>
      </head>
      HEAD
    end

    sections = files.map do |file|
      html = read_text.call(file)
      body_inner = extract.call(html, 'body') || html
      body_inner.strip
    end.join("\n\n")

    final_html = <<~HTML
    <!doctype html>
    <html>
    #{head_html}
    <body class="appendix">
    #{sections}
    </body>
    </html>
    HTML

    out_path = Pathname.new(out)
    File.write(out_path, final_html, mode: 'w', encoding: 'UTF-8')

    puts "✅ 出力しました: #{out_path}"
  end

end
