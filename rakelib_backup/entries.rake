# entries.js 生成関連のタスク

namespace :entries do
  desc "workspaceディレクトリ内のHTMLファイルからentries.jsを生成します"
  task :generate, [:output_path, :all_enabled] do |t, args|
    output_path = args[:output_path] || "entries.js"
    all_enabled = args[:all_enabled] == "true" || args[:all_enabled] == true
    
    workspace_dir = "workspace"
    
    # workspaceディレクトリ存在確認
    unless Dir.exist?(workspace_dir)
      puts "❌ エラー: #{workspace_dir}ディレクトリが見つかりません"
      exit 1
    end
    
    puts "🔍 #{workspace_dir} 内のHTMLファイルを検索しています..."
    html_files = Dir.glob(File.join(workspace_dir, "*.html"))
    
    if html_files.empty?
      puts "❌ エラー: #{workspace_dir}ディレクトリ内にHTMLファイルが見つかりません"
      exit 1
    end
    
    # HTMLファイルをソート（数字プレフィックス順）
    sorted_html_files = html_files.sort_by do |filename|
      basename = File.basename(filename)
      # ファイル名から数値部分を抽出してソート用のキーを生成
      if match = basename.match(/^(\d+)/)
        match[1].to_i
      else
        # 数字で始まらないファイル名は最後にソート
        999999
      end
    end
    
    # ファイル名だけを抽出
    file_basenames = sorted_html_files.map { |path| File.basename(path) }
    
    # entries.jsの内容を生成
    entries_content = "// entries.js - 自動生成されたファイル\n"
    entries_content += "// #{Time.now.strftime('%Y-%m-%d %H:%M:%S')} に生成\n"
    entries_content += "module.exports = {\n"
    entries_content += "  entryContext: '#{workspace_dir}',\n"
    entries_content += "  entries: [\n"
    
    file_basenames.each_with_index do |file, index|
      prefix = all_enabled ? "    " : "    // "
      # 序文とTOCとcolophonは常に有効化（コメントアウトしない）
      prefix = "    " if file.start_with?("00-") || file == "99-colophon.html" || file == "toc.html" || all_enabled
      entries_content += "#{prefix}\"#{file}\""
      entries_content += "," unless index == file_basenames.length - 1
      entries_content += "\n"
    end
    
    entries_content += "  ]\n"
    entries_content += "};\n"
    
    # ファイルに書き出し
    File.write(output_path, entries_content)
    
    puts "✅ entries.jsを生成しました: #{output_path}"
    puts "  - 合計 #{file_basenames.length} ファイルのエントリを含んでいます"
    puts "  - デフォルトで有効になっているファイル: 序文(00-*)とcolophon"
    puts "  - すべてのファイルを有効化するには: rake entries:generate[entries.js,true]"
  end
  
  desc "entries.jsのプレビューを表示します（ファイルは更新されません）"
  task :preview do
    Rake::Task["entries:generate"].invoke("preview.js")
    
    if File.exist?("preview.js")
      content = File.read("preview.js")
      puts "\n===== entries.js プレビュー =====\n\n"
      puts content
      puts "\n==============================\n"
      File.delete("preview.js")
    end
  end
  
  desc "すべてのHTMLファイルを有効化したentries.jsを生成します"
  task :enable_all do
    Rake::Task["entries:generate"].reenable
    Rake::Task["entries:generate"].invoke("entries.js", true)
  end
  
  desc "一部のHTMLファイルのみ有効化したentries.jsを生成します（序文とcolophonのみ）"
  task :minimal do
    Rake::Task["entries:generate"].reenable
    Rake::Task["entries:generate"].invoke
  end
end
