# 目次関連タスク
require_relative 'common'

desc "目次HTMLを生成します（引数でHTMLを列挙した場合はそれらのみ対象）"
task :toc do
  BookBuild.log_info("目次の生成を開始します...")

  require 'nokogiri'

  # 引数処理（ARGV から 'toc' を除去済みで files のみ取得）
  args = BookBuild.process_args('toc')
  files = (args[:files] || []).select { |f| f.end_with?('.html') }

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

  # 対象HTMLの選定
  targets = if files.any?
              files
            else
              # プロジェクトルート内の .html のうち、以下を除いて列挙する:
              # 00-titlepage.html / 01-legalpage.html / 03-toc.html / 99-colophon.html
              Dir.glob('*.html').reject { |file| file == '00-titlepage.html' ||
                                             file == '01-legalpage.html' ||
                                             file == '03-toc.html' ||
                                             file == '99-colophon.html' }.sort
            end

  # 先頭に前書き(02-preface.html)のH1を必ず入れる（targetsに含まれていない場合のみ）
  begin
    unless targets.include?('02-preface.html')
      if File.exist?('02-preface.html')
        preface_html = File.read('02-preface.html', encoding: 'utf-8')
        pre_doc = Nokogiri::HTML(preface_html)
        h1 = pre_doc.at_css('h1')
        if h1 && h1['id'] && !h1.text.strip.empty?
          preface_id = h1['id']
          preface_text = h1.text.strip
          result += %{- <a class="toc-chapter-no-number" href="02-preface.html##{preface_id}">}
          result += preface_text + "</a>\n"
        end
      end
    end
  rescue => _e
    # 目次生成自体は続行（ログ冗長を避けて抑止）
  end

  targets.each do |target|
    content = File.read(target, encoding: 'utf-8')
    doc     = Nokogiri::HTML(content)
    
    # 本文なら、h1, h2, h3を取得
    if BookBuild.get_file_type(target) == 'chapter'
      elems = doc.css('h1, h2, h3')
    elsif BookBuild.get_file_type(target) == 'appendix'
      elems = doc.css('h1, h2')
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
        elsif BookBuild.get_file_type(target) == 'appendix'
          result += %{- <a class="toc-chapter-appendix" href="#{target}##{id}">}
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

  # 末尾に後書き(98-postface.html)のH1を必ず入れる（targetsに含まれていない場合のみ）
  begin
    unless targets.include?('98-postface.html')
      if File.exist?('98-postface.html')
        postface_html = File.read('98-postface.html', encoding: 'utf-8')
        po_doc = Nokogiri::HTML(postface_html)
        h1 = po_doc.at_css('h1')
        if h1 && h1['id'] && !h1.text.strip.empty?
          postface_id = h1['id']
          postface_text = h1.text.strip
          result += %{- <a class="toc-chapter-no-number" href="98-postface.html##{postface_id}">}
          result += postface_text + "</a>\n"
        end
      elsif File.exist?(File.join('contents', '98-postface.md'))
        # HTML が未生成の場合は Markdown から H1 を抽出して使用
        md = File.read(File.join('contents', '98-postface.md'), encoding: 'utf-8')
        if (m = md.match(/^\s*#\s+(.+?)\s*$/))
          postface_text = m[1].strip
          # VFM の見出しID生成に厳密一致は保証できないが、素直にテキストを ID として用いる
          postface_id = postface_text
          result += %{- <a class="toc-chapter-no-number" href="98-postface.html##{postface_id}">}
          result += postface_text + "</a>\n"
        end
      end
    end
  rescue => _e
    # 目次生成自体は続行（ログ冗長を避けて抑止）
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
