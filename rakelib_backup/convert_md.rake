# Markdownファイルの変換関連のタスク
require 'optparse'
require 'pathname'
require 'fileutils'

namespace :md do
  desc "Markdownファイルを処理してHTMLに変換します"
  task :to_html, [:files] => [:check_deps] do |t, args|
    # デフォルト設定
    options = {
      replace:       true,   # HTMLReplace（html_replacer.rb）を実行するかどうか（デフォルトで有効）
      replace_json:  nil,    # HTMLReplace用のJSONファイル
      input_dir:     'content', # 入力元ディレクトリ
      output_dir:    'workspace', # 出力先ディレクトリ
      verbose:       true,    # 詳細出力モード
      all_md:        args[:files].nil? || args[:files] == "all",  # すべての.mdファイルを処理
      body_classes:  true,   # <body>タグにクラスを設定するかどうか
      skip_classes:  false   # 既存のbodyクラスをスキップするかどうか
    }

    # 入出力ディレクトリの存在確認と作成
    FileUtils.mkdir_p(options[:input_dir]) unless File.directory?(options[:input_dir])
    FileUtils.mkdir_p(options[:output_dir]) unless File.directory?(options[:output_dir])

    # 処理対象のMarkdownファイルを決定
    md_files = []

    if options[:all_md]
      # 入力ディレクトリのすべての.mdファイルを処理
      md_files = Dir.glob(File.join(options[:input_dir], "*.md"))
    else
      # 引数で指定されたファイルを処理
      files_arg = args[:files].split(" ") rescue []
      md_files = files_arg.map do |arg|
        if File.directory?(arg)
          Dir.glob(File.join(arg, "*.md"))
        else
          arg.start_with?(options[:input_dir]) ? arg : File.join(options[:input_dir], File.basename(arg))
        end
      end.flatten
    end

    # ファイルが指定されていない場合はエラー
    if md_files.empty?
      puts "エラー: Markdownファイルが見つかりませんでした。"
      exit 1
    end

    # 処理開始
    puts "🔄 #{md_files.length}個のMarkdownファイルを処理します..."
    processed_count = 0
    success_count = 0

    md_files.each do |md_file|
      # .mdファイルでない場合はスキップ
      unless md_file.end_with?(".md")
        puts "🔄 非Markdownファイルをスキップします: #{md_file}" if options[:verbose]
        next
      end
      
      # 入力ファイルが存在するか確認
      unless File.exist?(md_file)
        puts "❌ ファイルが見つかりません: #{md_file}"
        next
      end
      
      processed_count += 1
      
      # ファイル名を取得
      file_basename = File.basename(md_file)
      basename = File.basename(file_basename, ".md")
      
      # 出力先のHTMLファイル名を決定
      html_file = File.join(options[:output_dir], "#{basename}.html")
      
      puts "[#{processed_count}/#{md_files.length}] 変換中: #{md_file} → #{html_file}" if options[:verbose]
      
      # vfmコマンドを実行してHTMLを生成
      vfm_command = "vfm #{md_file} > #{html_file}"
      if system(vfm_command)
        success_count += 1
        puts "  ✅ #{html_file}を生成しました" if options[:verbose]
        
        # HTMLReplace処理が指定されている場合は実行
        if options[:replace] && File.exist?(html_file)
          begin
            # html:replaceタスクを呼び出し
            json_path = options[:replace_json] || "_postReplaceList.json"
            Rake::Task["html:replace"].reenable
            Rake::Task["html:replace"].invoke(html_file, json_path)
            puts "  ✅ #{html_file}のパターンを置換しました" if options[:verbose]
          rescue => e
            puts "  ❌ #{html_file}のHTML置換中にエラーが発生しました: #{e.message}"
          end
        end
      else
        puts "  ❌ #{md_file}からHTMLの生成中にエラーが発生しました"
      end
    end

    # 処理結果のサマリーを表示
    puts "\n処理結果:"
    puts "#{success_count}/#{processed_count}ファイルが正常に変換されました。"
    if success_count == processed_count && processed_count > 0
      puts "✅ すべてのファイルが正常に処理されました。"
    elsif success_count == 0
      puts "❌ 正常に処理されたファイルはありません。"
    else
      puts "⚠️  一部のファイルの処理に失敗しました。"
    end

    # <body>タグにクラスを設定
    if options[:body_classes] && success_count > 0
      Rake::Task["md:set_body_classes"].invoke(md_files, options)
    end
  end

  desc "VFM依存関係をチェックします"
  task :check_deps do
    # vfmコマンドが存在するか確認
    unless system("which vfm > /dev/null 2>&1")
      puts "❌ エラー: vfmコマンドが見つかりません。先にインストールしてください。"
      exit 1
    end

    # HTML置換用のRakeタスクが定義されているか確認
    unless Rake::Task.task_defined?("html:replace")
      puts "❌ エラー: html:replaceタスクが定義されていません。rakelib/html_replacer.rakeが存在することを確認してください。"
      exit 1
    end
  end

  desc "HTML本文タグにクラスを設定します"
  task :set_body_classes, [:md_files, :options] do |t, args|
    md_files = args[:md_files]
    options = args[:options] || {}
    skip_classes = options[:skip_classes] || false
    output_dir = options[:output_dir] || "workspace"

    # 生成されたHTMLファイル一覧を作成
    if md_files.is_a?(String)
      md_files = [md_files]
    end

    if md_files.nil? || md_files.empty?
      md_files = Dir.glob(File.join('content', "*.md"))
    end

    generated_html_files = md_files.map do |md_file|
      basename = File.basename(md_file, ".md")
      File.join(output_dir, "#{basename}.html")
    end.select { |f| File.exist?(f) }
    
    # 他に処理する必要のあるHTMLファイルを追加
    additional_files = ['00-toc.html', '99-colophon.html']
    additional_files.each do |file|
      output_file = File.join(output_dir, file)
      if File.exist?(output_file) && !generated_html_files.include?(output_file)
        generated_html_files << output_file
      end
    end
    
    set_body_classes_impl(generated_html_files, skip_classes)
    puts "✅ bodyクラスを設定しました"
  end
end

# <body>タグにクラスを設定する実装
def set_body_classes_impl(html_files, skip_classes = false)
  return unless html_files.any?
  
  # ファイルとクラスのマッピング
  file_class_mapping = {
    'frontmatter' => ['00-preface.html', '00-toc.html', '98-postface.html', '99-colophon.html'],
    'main-content' => ['01-gift.html', '02-source.html', '03-unit.html', 
                     '04-electricity.html', '05-electronics.html', '07-ai.html']
  }
  
  # 各グループのファイルを処理
  file_class_mapping.each do |class_name, file_patterns|
    # 実際に処理するファイルをパターンマッチングで取得
    matched_files = html_files.select do |file|
      basename = File.basename(file)
      file_patterns.any? { |pattern| File.fnmatch(pattern, basename) }
    end
    
    next if matched_files.empty?
    puts "📄 【#{class_name}】"
    
    matched_files.each do |path|
      next unless File.exist?(path)
      content = File.read(path)
      
      # 既存の<body>タグにクラスがあるか確認
      if skip_classes && content =~ /<body[^>]*\sclass=['"][^'"]*['"]/
        puts " - #{path}: 既存のクラスがあるためスキップ"
        next
      end
      
      # classが既にある場合は置換、ない場合は追加
      modified = if content.include?('<body class=')
        content.gsub(/<body class="[^"]*">/, "<body class=\"#{class_name}\">") 
      else
        content.gsub(/<body>/, "<body class=\"#{class_name}\">") 
      end
      
      if content != modified
        File.write(path, modified)
        puts " ✅ #{path}: class=\"#{class_name}\"を設定"
      else
        puts " - #{path}: 変更なし"
      end
    end
  end
end
