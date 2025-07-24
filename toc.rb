#!/usr/bin/env ruby

require 'pathname'
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

# カレントフォルダ内の「toc.html以外の.htmlファイル」を列挙
current = Pathname.new('.')
current.glob('*.html').reject { |file| file.basename.to_s == 'toc.html' }.each do |target|
  # puts target
  content = target.read(encoding: 'utf-8')
  doc = Nokogiri::HTML(content)
  targetpath = target.to_s.gsub('\\', '/')
  
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

# 書き出し
# puts result
outpath = Pathname.new('toc.md')
outpath.write(result, encoding: 'utf-8')

# MarkdownをHTMLに変換してから一時ファイルを削除
system('vfm toc.md > toc.html && rm toc.md')
