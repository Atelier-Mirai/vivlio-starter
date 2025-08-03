require_relative 'common'

# entries.js生成タスク
desc "entries.jsを生成します"
task :entries do |t, args|
  puts "📋 entries.jsを生成しています..."
  
  # コマンドライン引数を取得
  files_arg = BookBuild.process_args
  
  # HTMLファイルを取得
  html_files = if files_arg.any?
    files_arg.map { |f| "#{f}.html" }
  else
    # 01-toc.htmlを含める
    Rake::Task['toc'].invoke
    Dir.glob("*.html")
  end
  
  puts "  📄 処理対象ファイル: #{html_files.join(', ')}"
  
  # entries.jsの生成
  entries = html_files.map do |html_file|
    base_name = File.basename(html_file, ".html")
    title = base_name
    
    # HTMLファイルからタイトルを取得（優先）
    html_title = nil
    if File.exist?(html_file)
      content = File.read(html_file)
      if content =~ /<title>(.+?)<\/title>/
        html_title = $1.strip
        title = html_title if !html_title.empty?
      end
    end
    
    # HTMLからタイトルが取得できなかった場合のフォールバック処理
    if html_title.nil? || html_title.empty?
      # ファイル名からタイトルを生成
      if base_name =~ /^\d+-(.+)$/
        title = $1
      end
      
      # デフォルトのタイトルマッピング（フォールバック）
      title_mapping = {
        "preface"     => "始めに",
        "toc"         => "目次",
        "gift"        => "挑戦することの贈り物",
        "source"      => "万物の根源を求めて",
        "unit"        => "単位と測定",
        "electricity" => "電気の基礎",
        "electronics" => "電子回路の基礎",
        "ai"          => "AIへの道",
        "appendix-a"  => "付録A",
        "appendix-b"  => "付録B",
        "appendix-c"  => "付録C",
        "postface"    => "あとがき",
        "colophon"    => ""
      }
      
      # マッピングにあればそれを使用
      title = title_mapping[title] if title_mapping.key?(title)
    end
    
    # エントリーを生成
    { path: html_file, title: title }
  end
  
  # entries.jsをES Module形式で書き込み
  File.open("entries.js", "w") do |f|
    f.puts "export default ["
    entries.each_with_index do |entry, i|
      f.puts "  {"
      f.puts "    \"path\": \"#{entry[:path]}\","
      f.puts "    \"title\": \"#{entry[:title]}\""
      f.puts "  }#{i < entries.length - 1 ? ',' : ''}"
    end
    f.puts "];"
  end
  
  puts "✅ entries.js生成完了: #{entries.length}件のエントリを登録"
end
