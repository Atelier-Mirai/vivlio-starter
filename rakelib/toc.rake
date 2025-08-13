# 目次関連タスク
require_relative 'common'

desc "目次HTMLを生成します"
task :toc do
  BookBuild.log_info("目次の生成を開始します...")
  
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

  # プロジェクトルート内の「03-toc.htmlおよ゙99-colophon.html以外の.htmlファイル」を列挙
  Dir.glob('*.html').reject { |file| file == '03-toc.html' || file == '99-colophon.html' }.sort.each do |target|
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
        if BookBuild.get_file_type(target) == 'chapter'
          result += %{- <a class="toc-chapter" href="#{target}##{id}">}
        else
          result += %{- <a class="toc-chapter-no-number" href="#{target}##{id}">}
        end
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
  File.write('03-toc.md', result, encoding: 'utf-8')
  
  # VFMで変換
  system("#{BookBuild::VFM_COMMAND} 03-toc.md > 03-toc.html")

  # 03-toc.html <body class="toc">に変更
  content = File.read('03-toc.html', encoding: 'utf-8')
  content.sub!('<body>', '<body class="toc">')
  File.write('03-toc.html', content, encoding: 'utf-8') 

  BookBuild.log_success("目次生成完了")
end
