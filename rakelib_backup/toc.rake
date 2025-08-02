# 目次生成関連のタスク
require 'pathname'
require 'nokogiri'

desc "HTML ファイルから目次を自動生成します"
task :generate_toc do
  puts "📚 目次を生成しています..."
  
  result = <<~MD
          ---
          link: 
            - rel: "stylesheet"
              href: "../stylesheets/toc.css"
          lang: 'ja'
          ---

          ## 目次
          <nav id="toc" role="doc-toc">

  MD

  # workspaceディレクトリ内の「00-toc.html以外の.htmlファイル」を列挙
  workspace_dir = Pathname.new('workspace')
  FileUtils.mkdir_p(workspace_dir) unless workspace_dir.exist?

  workspace_dir.glob('*.html').reject { |file| file.basename.to_s == '00-toc.html' }.each do |target|
    # puts target
    content = target.read(encoding: 'utf-8')
    doc = Nokogiri::HTML(content)
    targetpath = target.relative_path_from(workspace_dir).to_s.gsub('\\', '/')
    
    # h1～h3要素を取得
    elems = doc.css('h1, h2, h3')
    elems.each do |elem|
      id = elem['id']
      text = elem.text.strip
      
      case elem.name
      when 'h1'
        result += %{- <a class="toc-chapter" href="#{targetpath}##{id}">}
        result += text + "</a>\n"
      when 'h2'
        result += '  '  # 2スペース
        result += %{- <a class="toc-section" href="#{targetpath}##{id}">}
        result += text + "</a>\n"
      when 'h3'
        result += '    '  # 4スペース
        result += %{- <a class="toc-subsection" href="#{targetpath}##{id}">}
        result += text + "</a>\n"
      end
    end
  end

  result += "\n</nav>"

  output = "<!DOCTYPE html>\n<html lang=\"ja\">\n<head>\n<meta charset=\"utf-8\">\n<link rel=\"stylesheet\" href=\"../stylesheets/toc.css\">\n<title>目次</title>\n</head>\n<body class=\"frontmatter\">\n#{result}</body>\n</html>"

  output_path = Pathname.new('workspace/00-toc.html')
  output_path.write(output, encoding: 'utf-8')

  puts "✅ 目次を生成しました: #{output_path}"
end
