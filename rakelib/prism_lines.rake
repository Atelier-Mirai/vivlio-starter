# Prism.jsのコードブロックに行番号を追加するRakeタスク
require "open-uri"
require "nokogiri"

# コードの行数を返す
def line_count(pre)
  pre.text.count("\n") + 1
end

# Prism.jsの行番号を追加する処理
def add_prism_line_numbers(input_file, output_file = nil, verbose = false)
  output_file = input_file if output_file.nil?
  
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
    raise e
  end
end

namespace :prism do
  desc "HTMLファイル内のPrism.jsコードブロックに行番号を追加します"
  task :lines do
    # ARGV から引数を取得（最初の要素 'prism:lines' をスキップ）
    args = ARGV.drop(1)
    
    if args.empty?
      puts <<~USAGE
        HTMLファイル内のPrism.jsコードブロックに行番号を追加します
        使用法: rake prism:lines 入力ファイル [出力ファイル]
        
        引数:
          入力ファイル     HTMLファイル（必須）
          出力ファイル     出力先HTMLファイル（省略可、省略時は入力ファイルを上書き）
        
        オプション:
          VERBOSE=true   詳細な処理情報を表示
        
        使用例:
          rake prism:lines prime.html
          rake prism:lines prime.html prime_with_lines.html
          rake prism:lines prime.html VERBOSE=true
      USAGE
      exit 1
    end
    
    input_file = args[0]
    output_file = args[1]
    verbose = ENV['VERBOSE'] == 'true'
    
    unless File.exist?(input_file)
      puts "Error: Input file '#{input_file}' does not exist"
      exit 1
    end
    
    add_prism_line_numbers(input_file, output_file, verbose)
    
    # ARGV の残りの引数をタスクとして実行されないようにする
    args.each { |arg| task arg.to_sym do ; end }
  end
  
  desc "HTMLファイル内のすべてのPrism.jsコードブロックに行番号を追加します"
  task :lines_all do
    verbose = ENV['VERBOSE'] == 'true'
    html_files = Dir.glob("*.html")
    
    if html_files.empty?
      puts "現在のディレクトリにHTMLファイルが見つかりません"
      exit 0
    end
    
    puts "#{html_files.length}個のHTMLファイルを処理中..." if verbose
    
    html_files.each do |file|
      puts "\n=== #{file} を処理中 ===" if verbose
      add_prism_line_numbers(file, nil, verbose)
    end
    
    puts "\n✅ #{html_files.length}個のHTMLファイルを処理完了"
  end
end
