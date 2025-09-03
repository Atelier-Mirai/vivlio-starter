# frozen_string_literal: true
require 'nokogiri'
module Vivlio
  module Starter
    module CLI
      # ================================================================
      # Module: Thor コマンド群: toc（目次生成）
      # ------------------------------------------------
      # - 目的: 章HTMLから 03-toc.md/.html を生成
      # - 提供コマンド: toc
      # - 主な処理: 目次の <ul>/<li> 構築, 前書き/後書きの見出し追加, VFM 変換
      # - 関連: 共通処理は `lib/vivlio/starter/cli/common.rb`
      # ================================================================
      module TocCommands
        extend self
        def included(base)
          base.class_eval do
            desc 'toc [HTMLs...]', '目次HTMLを生成します（引数でHTMLを列挙した場合はそれらのみ対象）'
            long_desc <<~DESC
              指定した HTML を対象に目次を生成します。引数が無い場合はプロジェクト直下の HTML を自動検出し、
              以下を除外して処理します: 00-titlepage.html / 01-legalpage.html / 03-toc.html / 99-colophon.html。

              例:
                vs toc 11-gift.html 12-tutorial.html
                vs toc                # 自動検出
            DESC
            # ================================================================
            # Command: toc（目次生成）
            # ------------------------------------------------
            # - 概要: 指定（または自動検出）HTMLから 03-toc.md/.html を生成
            # - 入力: *.html（除外: 00-titlepage/01-legalpage/03-toc/99-colophon）
            # - 出力: 03-toc.md と 03-toc.html
            # - 補足: VFM で Markdown→HTML 変換、<body class="toc"> 付与
            # ================================================================
            def toc(*htmls)
              ENV['VERBOSE'] = '1' if options[:verbose]

              base_dir = '.'

              # 対象HTMLの選定（Rake実装に忠実）
              targets = if htmls.any?
                          files = htmls.select { |f| f.end_with?('.html') }
                          files.map { |f| File.dirname(f) == '.' ? File.join(base_dir, f) : f }
                        else
                          # base_dir 内の .html のうち、以下を除いて列挙する:
                          # 00-titlepage.html / 01-legalpage.html / 03-toc.html / 99-colophon.html
                          Dir.glob(File.join(base_dir, '*.html')).reject { |file|
                                                       File.basename(file) == '00-titlepage.html' ||
                                                       File.basename(file) == '01-legalpage.html' ||
                                                       File.basename(file) == '03-toc.html' ||
                                                       File.basename(file) == '99-colophon.html' }.sort
                        end

              if targets.empty?
                Common.log_warn('目次対象となるHTMLが見つかりません。処理を中止します')
                return
              end

              Common.log_action("目次の生成を開始します… 対象: #{targets.map { |p| File.basename(p) }.join(', ')}")

              # YAMLフロントマター付きのMarkdownを構築（Rake実装）
              result = String.new
              result << <<~MD
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

              # 先頭に前書き(02-preface.html)のH1テキストを必ず入れる（targetsに含まれていない場合のみ）
              begin
                preface_path = File.join(base_dir, '02-preface.html')
                unless targets.include?(preface_path)
                  if File.exist?(preface_path)
                    preface_html = File.read(preface_path, encoding: 'utf-8')
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

              # ネスト制御しつつ <ul>/<li> を直接生成（Rake実装に忠実）
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
                  case Common.get_file_type(target)
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
                            case Common.get_file_type(target)
                            when 'chapter'  then 'toc-chapter'
                            when 'appendix' then 'toc-chapter-appendix'
                            else 'toc-chapter-no-number'
                            end
                          when 'h2' then 'toc-section'
                          else 'toc-subsection'
                          end

                  # 対応する見出しのIDを使って data-href を付与
                  elem_id   = elem['id']
                  rel = File.basename(target)
                  data_href = elem_id && !elem_id.empty? ? "#{rel}##{elem_id}" : rel

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

              result << "</ul>\n</nav>"

              # 03-toc.md を保存
              md_path = File.join(base_dir, '03-toc.md')
              File.write(md_path, result, encoding: 'utf-8')

              # VFM で 03-toc.html を生成
              html_path = File.join(base_dir, '03-toc.html')
              vfm = Common::VFM_COMMAND
              system(%(#{vfm} "#{md_path}" > "#{html_path}"))

              # 03-toc.html <body class="toc">に変更
              if File.exist?(html_path)
                content = File.read(html_path, encoding: 'utf-8')
                content.sub!('<body>', '<body class="toc">')
                File.write(html_path, content, encoding: 'utf-8')
                Common.log_success("目次生成完了")
              else
                Common.log_warn('03-toc.html の生成に失敗しました（VFM 実行エラー）')
              end
            end
          end
        end
      end
    end
  end
end
