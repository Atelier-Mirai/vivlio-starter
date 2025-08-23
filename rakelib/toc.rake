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
          <ul>

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

  # 先頭に前書き(02-preface.html)のH1テキストを必ず入れる（targetsに含まれていない場合のみ）
  begin
    unless targets.include?('02-preface.html')
      if File.exist?('02-preface.html')
        preface_html = File.read('02-preface.html', encoding: 'utf-8')
        pre_doc = Nokogiri::HTML(preface_html)
        h1 = pre_doc.at_css('h1')
        if h1 && !h1.text.strip.empty?
          preface_text = h1.text.strip
          preface_id   = h1['id']
          data_href    = preface_id && !preface_id.empty? ? "02-preface.html##{preface_id}" : "02-preface.html"
          result += %(<li class="toc-chapter-no-number" data-href="#{data_href}">#{preface_text}</li>\n)
        end
      end
    end
  rescue => _e
    # 目次生成自体は続行（ログ冗長を避けて抑止）
  end

  # ネスト制御しつつ <ul>/<li> を直接生成
  current_level = 1
  opened_item = false
  open_item = lambda do |klass, text, data_href|
    if data_href && !data_href.empty?
      result << "<li class=\"#{klass}\" data-href=\"#{data_href}\">#{text}"
    else
      result << "<li class=\"#{klass}\">#{text}"
    end
    opened_item = true
  end
  close_item = lambda do
    if opened_item
      result << "</li>\n"
      opened_item = false
    end
  end

  targets.each do |target|
    content = File.read(target, encoding: 'utf-8')
    doc     = Nokogiri::HTML(content)

    # 本文なら、h1, h2, h3を取得
    elems =
      case BookBuild.get_file_type(target)
      when 'chapter'   then doc.css('h1, h2, h3')
      when 'appendix'  then doc.css('h1, h2')
      else                   doc.css('h1')
      end

    elems.each do |elem|
      text = elem.text.strip
      next if text.empty?

      level = case elem.name
              when 'h1' then 1
              when 'h2' then 2
              else 3
              end

      # レベル差に応じてクローズ/オープン
      if level > current_level
        (level - current_level).times do
          result << "\n<ul>\n"
        end
      elsif level < current_level
        close_item.call
        (current_level - level).times do
          result << "</ul>\n"
          result << "</li>\n"
        end
      else
        # 同レベル: 直前項目を閉じる
        close_item.call
      end
      current_level = level

      klass = case elem.name
              when 'h1'
                case BookBuild.get_file_type(target)
                when 'chapter'  then 'toc-chapter'
                when 'appendix' then 'toc-chapter-appendix'
                else 'toc-chapter-no-number'
                end
              when 'h2' then 'toc-section'
              else 'toc-subsection'
              end

      # 対応する見出しのIDを使って data-href を付与
      elem_id   = elem['id']
      data_href = elem_id && !elem_id.empty? ? "#{target}##{elem_id}" : target

      open_item.call(klass, text, data_href)
    end
  end

  # クローズ処理（最終アイテムと全てのネストULを閉じる）
  close_item.call
  while current_level > 1
    result << "</ul>\n</li>\n"
    current_level -= 1
  end

  # 末尾に後書き(98-postface.html)のH1テキストを必ず入れる（targetsに含まれていない場合のみ）
  begin
    unless targets.include?('98-postface.html')
      if File.exist?('98-postface.html')
        postface_html = File.read('98-postface.html', encoding: 'utf-8')
        po_doc = Nokogiri::HTML(postface_html)
        h1 = po_doc.at_css('h1')
        if h1 && !h1.text.strip.empty?
          postface_text = h1.text.strip
          postface_id   = h1['id']
          data_href     = postface_id && !postface_id.empty? ? "98-postface.html##{postface_id}" : "98-postface.html"
          result << %(<li class="toc-chapter-no-number" data-href="#{data_href}">#{postface_text}</li>\n)
        end
      elsif File.exist?(File.join('contents', '98-postface.md'))
        md = File.read(File.join('contents', '98-postface.md'), encoding: 'utf-8')
        if (m = md.match(/^\s*#\s+(.+?)\s*$/))
          postface_text = m[1].strip
          result << %(<li class="toc-chapter-no-number">#{postface_text}</li>\n)
        end
      end
    end
  rescue => _e
    # 目次生成自体は続行（ログ冗長を避けて抑止）
  end

  result += "</ul>\n</nav>"
  
  # Markdownファイルとして保存（YAMLフロントマターとMarkdown見出しを含むため）
  File.write('03-toc.md', result, encoding: 'utf-8')
  
  # VFMで変換
  system("#{BookBuild::VFM_COMMAND} 03-toc.md > 03-toc.html")

  # 03-toc.html <body class="toc">に変更
  content = File.read('03-toc.html', encoding: 'utf-8')
  content.sub!('<body>', '<body class="toc">')
  File.write('03-toc.html', content, encoding: 'utf-8') 

  BookBuild.log_success("目次生成完了")
end
