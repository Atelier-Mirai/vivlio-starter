#!/usr/bin/env ruby

# FIXME: 単体では機能するが、vivliostyle build すると、行番号は付与されない
# 理想: vivliostyle build でも行番号が表示されること
# 将来的には、md2html.rb内で実行されるようにする。

require "open-uri"
require "nokogiri"

# 使い方表示
if ARGV.size == 0
  puts <<~USAGE
    Code to modify an HTML file so that line numbers are displayed with Prism.
    usage: #{File.basename(__FILE__)} filename.html [options]
    
    Options:
      --output FILE    Output to specified file (default: overwrite input)
      --verbose        Show detailed processing information
      --help           Show this help message
  USAGE
  exit 1
end

# コマンドライン引数の解析
input_file = nil
output_file = nil
verbose = false

i = 0
while i < ARGV.length
  case ARGV[i]
  when "--output", "-o"
    i += 1
    output_file = ARGV[i] if i < ARGV.length
  when "--verbose", "-v"
    verbose = true
  when "--help", "-h"
    puts <<~USAGE
      Code to modify an HTML file so that line numbers are displayed with Prism.
      usage: #{File.basename(__FILE__)} filename.html [options]
      
      Options:
        --output FILE    Output to specified file (default: overwrite input)
        --verbose        Show detailed processing information
        --help           Show this help message
    USAGE
    exit 0
  else
    input_file = ARGV[i] if input_file.nil?
  end
  i += 1
end

if input_file.nil?
  puts "Error: No input file specified"
  exit 1
end

# 出力ファイルが指定されていない場合は入力ファイルを上書き
output_file = input_file if output_file.nil?

# コードの行数を返す
def line_count(pre)
  pre.text.count("\n") + 1
end

begin
  # HTMLを読み込む
  puts "Processing: #{input_file}" if verbose
  doc = Nokogiri::HTML.parse(URI.open(input_file))
  
  # <pre>要素を取得
  pre_tags = doc.css("pre")
  puts "Found #{pre_tags.length} <pre> elements" if verbose
  
  pre_tags.each_with_index do |pre, index|
    puts "\nProcessing <pre> element #{index + 1}/#{pre_tags.length}" if verbose
    
    # クラスを追加
    original_class = pre[:class] || ""
    pre[:class] = "#{original_class} line-numbers".strip
    
    code = pre.css("code").first
    if code
      original_code_class = code[:class] || ""
      code[:class] = "#{original_code_class} line-numbers".strip
      
      # 行番号の為の <span>要素を作成
      span = Nokogiri::XML::Node.new("span", doc)
      span["aria-hidden"] = "true"
      span["class"] = "line-numbers-rows"
      
      # <span></span>要素を、コードの行数分追加する
      line_count(pre).times do
        span_line = Nokogiri::XML::Node.new('span', doc)
        span.add_child(span_line)
      end
      
      # <code>要素の末尾に追加する
      code.add_child(span)
      
      puts "  Added line numbers (#{line_count(pre)} lines)" if verbose
    else
      puts "  Warning: No <code> element found in <pre>" if verbose
    end
  end
  
  # ファイルに出力
  puts "Writing to: #{output_file}" if verbose
  File.write(output_file, doc.to_html)
  puts "✅ Successfully processed #{input_file}" + (output_file != input_file ? " -> #{output_file}" : "")
  
rescue => e
  puts "Error: #{e.message}"
  exit 1
end
