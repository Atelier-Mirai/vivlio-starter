require_relative 'common'

# 目次関連タスク
desc "目次HTMLを生成します"
task :toc do
  puts "📚 目次を生成しています..."
  
  require 'nokogiri'
  
  result = <<~MD
          ---
          link: 
            - rel: "stylesheet"
              href: "stylesheets/toc.css"
          lang: 'ja'
          ---

          ## 目次
          <nav id="toc" role="doc-toc">

  MD

  # プロジェクトルート内の「01-toc.html以外の.htmlファイル」を列挙
  Dir.glob('*.html').reject { |file| file == '01-toc.html' }.sort.each do |target|
    content = File.read(target, encoding: 'utf-8')
    doc     = Nokogiri::HTML(content)
    
    # 本文なら、h1, h2, h3を取得
    if BookBuild.get_file_type(target) == 'chapter'
      elems = doc.css('h1, h2, h3')
    else
      elems = doc.css('h1')
    end
    
    elems.each do |elem|
      id = elem['id']
      text = elem.text.strip
      
      case elem.name
      when 'h1'
        result += %{- <a class="toc-chapter" href="#{target}##{id}">}
        result += text + "</a>\n"
      when 'h2'
        result += '  '  # 2スペース
        result += %{- <a class="toc-section" href="#{target}##{id}">}
        result += text + "</a>\n"
      when 'h3'
        result += '    '  # 4スペース
        result += %{- <a class="toc-subsection" href="#{target}##{id}">}
        result += text + "</a>\n"
      end
    end
  end

  result += "\n</nav>"
  
  # Markdownファイルとして保存
  File.write('01-toc.md', result, encoding: 'utf-8')
  
  # VFMで変換
  system("#{BookBuild::VFM_COMMAND} 01-toc.md > 01-toc.html")
  
  puts "✅ 目次生成完了"
end

# entries.js生成タスク
desc "entries.jsを生成します"
task :entries => [:toc] do |t, args|
  puts "📋 entries.jsを生成しています..."
  
  # コマンドライン引数を取得
  files_arg = BookBuild.process_args
  
  # HTMLファイルを取得
  html_files = if files_arg.any?
    files_arg.map { |f| "#{f}.html" }
  else
    Dir.glob("*.html")
  end
  
  # 目次ファイルを必ず含める
  html_files << "01-toc.html" unless html_files.include?("01-toc.html")
  
  # 重複を除去してソート
  html_files = html_files.uniq.sort
  
  puts "  📄 処理対象ファイル: #{html_files.join(', ')}"
  
  # entries.jsの生成
  entries = html_files.map do |html_file|
    title = File.basename(html_file, ".html")
    
    # タイトルを取得
    if File.exist?(html_file)
      content = File.read(html_file)
      if content =~ /<title>(.+?)<\/title>/
        title = $1
      end
    end
    
    # ファイル名からタイトルを生成
    if title =~ /^\d+-(.+)$/
      title = $1
    end
    
    # タイトルを日本語化
    case title
    when "preface"
      title = "始めに"
    when "toc"
      title = "目次"
    when "gift"
      title = "挑戦することの贈り物"
    when "source"
      title = "万物の根源を求めて"
    when "unit"
      title = "単位と測定"
    when "electricity"
      title = "電気の基礎"
    when "electronics"
      title = "電子回路の基礎"
    when "ai"
      title = "AIへの道"
    when "appendix-a"
      title = "付録A"
    when "appendix-b"
      title = "付録B"
    when "appendix-c"
      title = "付録C"
    when "postface"
      title = "あとがき"
    when "colophon"
      title = "奨付"
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
