#!/usr/bin/env ruby

require 'json'
require 'pathname'

# HTMLファイル置換スクリプト
# Usage: ./html_replacer.rb [html_file] [--json json_file]

def show_usage
  puts "Usage: #{File.basename($0)} [html_file] [--json json_file]"
  puts ""
  puts "Options:"
  puts "  html_file    : HTML file to process"
  puts "  --json file  : JSON replacement list file (default: _postReplaceList.json)"
  puts ""
  puts "Example:"
  puts "  #{File.basename($0)} sample.html"
  puts "  #{File.basename($0)} sample.html --json custom_replace.json"
end

# コマンドライン引数の解析
html_file = nil
json_file = "_postReplaceList.json"

i = 0
while i < ARGV.length
  case ARGV[i]
  when "--json"
    i += 1
    if i < ARGV.length
      json_file = ARGV[i]
    else
      puts "Error: --json option requires a file path"
      show_usage
      exit 1
    end
  when "--help", "-h"
    show_usage
    exit 0
  else
    if html_file.nil?
      html_file = ARGV[i]
    else
      puts "Error: Multiple HTML files specified"
      show_usage
      exit 1
    end
  end
  i += 1
end

# HTMLファイルが指定されていない場合
if html_file.nil?
  puts "Error: HTML file not specified"
  show_usage
  exit 1
end

# HTMLファイルの存在確認
unless File.exist?(html_file)
  puts "Error: HTML file '#{html_file}' not found"
  exit 1
end

# JSONファイルの存在確認
unless File.exist?(json_file)
  puts "Error: JSON file '#{json_file}' not found"
  exit 1
end

begin
  # JSONファイルを読み込み
  json_content = File.read(json_file, encoding: 'utf-8')
  replacement_list = JSON.parse(json_content)
  
  # JSONが配列でない場合はエラー
  unless replacement_list.is_a?(Array)
    puts "Error: JSON file must contain an array of replacement objects"
    exit 1
  end
  
  puts "Loading replacement patterns from: #{json_file}"
  puts "Processing HTML file: #{html_file}"
  
  # HTMLファイルを読み込み
  html_content = File.read(html_file, encoding: 'utf-8')
  original_content = html_content.dup
  
  # 置換処理
  replacement_count = 0
  replacement_list.each_with_index do |item, index|
    unless item.is_a?(Hash) && item.key?('f') && item.key?('r')
      puts "Warning: Invalid replacement item at index #{index}, skipping"
      next
    end
    
    pattern_str = item['f']
    replacement_str = item['r']
    
    begin
      # 正規表現パターンを作成
      pattern = Regexp.new(pattern_str)
      
      # 置換実行（キャプチャグループを考慮）
      matches_found = 0
      html_content.gsub!(pattern) do |match|
        matches_found += 1
        match_data = pattern.match(match)
        result = replacement_str.dup
        
        # キャプチャグループの置換 ($1, $2, etc.)
        if match_data && match_data.captures.length > 0
          match_data.captures.each_with_index do |capture, cap_index|
            result.gsub!("$#{cap_index + 1}", capture.to_s) if capture
          end
        end
        
        result
      end
      
      if matches_found > 0
        replacement_count += matches_found
        puts "  Pattern #{index + 1}: #{matches_found} replacement(s) made"
      end
      
    rescue RegexpError => e
      puts "Warning: Invalid regex pattern at index #{index}: #{pattern_str}"
      puts "  Error: #{e.message}"
    end
  end
  
  # 結果の出力
  if html_content != original_content
    # HTMLファイルを上書き
    File.write(html_file, html_content, encoding: 'utf-8')
    puts ""
    puts "✅ Successfully processed #{html_file}"
    puts "   Total replacements made: #{replacement_count}"
  else
    puts ""
    puts "ℹ️  No replacements were made in #{html_file}"
  end
  
rescue JSON::ParserError => e
  puts "Error: Invalid JSON format in #{json_file}"
  puts "  #{e.message}"
  exit 1
rescue => e
  puts "Error: #{e.message}"
  exit 1
end
