#!/usr/bin/env ruby

# vfmbatch.rb - Convert multiple Markdown files to HTML using vfm
# Usage: ./vfmbatch.rb [options] file1.md file2.md ...
#        ./vfmbatch.rb [options] --all  (to process all *.md files)

require 'optparse'
require 'pathname'
require 'fileutils'

# デフォルト設定
options = {
  replace:      true,   # HTMLReplace（htmlreplace.rb）を実行するかどうか（デフォルトで有効）
  replace_json: nil,    # HTMLReplace用のJSONファイル
  output_dir:   nil,    # 出力先ディレクトリ
  verbose:      false,  # 詳細出力モード
  all_md:       false   # すべての.mdファイルを処理
}

# コマンドラインオプションのパース
optparser = OptionParser.new do |opts|
  opts.banner = "Usage: #{File.basename($0)} [options] file1.md file2.md ..."
  
  opts.on("--all", "Process all *.md files in the current directory") do
    options[:all_md] = true
  end
  
  opts.on("--no-replace", "Disable htmlreplace.rb on the generated HTML files") do
    options[:replace] = false
  end
  
  opts.on("--replace-json FILE", "Specify JSON file for htmlreplace.rb") do |file|
    options[:replace_json] = file
    options[:replace] = true  # --replace-jsonが指定された場合は自動的にreplaceを有効化
  end
  
  opts.on("-o", "--output-dir DIR", "Output directory for HTML files") do |dir|
    options[:output_dir] = dir
    # 出力ディレクトリが存在しない場合は作成
    FileUtils.mkdir_p(dir) unless File.directory?(dir)
  end
  
  opts.on("-v", "--verbose", "Verbose output") do
    options[:verbose] = true
  end
  
  opts.on("-h", "--help", "Show this help message") do
    puts opts
    exit
  end
end

# コマンドラインパラメータをパース
begin
  optparser.parse!
rescue OptionParser::InvalidOption => e
  puts "Error: #{e.message}"
  puts optparser
  exit 1
end

# 処理対象のMarkdownファイルを決定
md_files = []

if options[:all_md]
  # カレントディレクトリのすべての.mdファイルを処理
  md_files = Dir.glob("*.md")
else
  # コマンドライン引数で指定されたファイルを処理
  md_files = ARGV
end

# ファイルが指定されていない場合はヘルプを表示
if md_files.empty?
  puts "Error: No markdown files specified."
  puts optparser
  exit 1
end

# vfmコマンドが存在するか確認
unless system("which vfm > /dev/null 2>&1")
  puts "Error: vfm command not found. Please install it first."
  exit 1
end

# HTMLReplaceが必要な場合、htmlreplace.rbが存在するか確認
if options[:replace] && !File.exist?("htmlreplace.rb")
  puts "Error: htmlreplace.rb not found. Please make sure it exists in the current directory."
  exit 1
end

# 処理開始
puts "Processing #{md_files.length} markdown file(s)..."
processed_count = 0
success_count = 0

md_files.each do |md_file|
  # .mdファイルでない場合はスキップ
  unless md_file.end_with?(".md")
    puts "Skipping non-markdown file: #{md_file}" if options[:verbose]
    next
  end
  
  # 入力ファイルが存在するか確認
  unless File.exist?(md_file)
    puts "Error: File not found: #{md_file}"
    next
  end
  
  processed_count += 1
  basename = File.basename(md_file, ".md")
  
  # 出力先のHTMLファイル名を決定
  html_file = options[:output_dir] ? 
    File.join(options[:output_dir], "#{basename}.html") : 
    "#{basename}.html"
  
  puts "[#{processed_count}/#{md_files.length}] Converting #{md_file} -> #{html_file}" if options[:verbose]
  
  # vfmコマンドを実行してHTMLを生成
  vfm_command = "vfm #{md_file} > #{html_file}"
  if system(vfm_command)
    success_count += 1
    puts "  ✅ Generated #{html_file}" if options[:verbose]
    
    # HTMLReplace処理が指定されている場合は実行
    if options[:replace] && File.exist?(html_file)
      replace_cmd = "./htmlreplace.rb"
      replace_cmd += " --json #{options[:replace_json]}" if options[:replace_json]
      replace_cmd += " #{html_file}"
      
      if system(replace_cmd)
        puts "  ✅ Replaced patterns in #{html_file}" if options[:verbose]
      else
        puts "  ❌ Error running htmlreplace.rb on #{html_file}"
      end
    end
  else
    puts "  ❌ Error generating HTML from #{md_file}"
  end
end

# 処理結果のサマリーを表示
puts "\nSummary:"
puts "#{success_count} of #{processed_count} files successfully converted."
if success_count == processed_count && processed_count > 0
  puts "✅ All files processed successfully."
elsif success_count == 0
  puts "❌ No files were successfully processed."
else
  puts "⚠️  Some files failed to process."
end
