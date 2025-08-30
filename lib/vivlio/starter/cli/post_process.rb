# frozen_string_literal: true

require 'json'
require 'yaml'
require 'nokogiri'

module Vivlio
  module Starter
    module CLI
      # ================================================================
      # Module: Thor コマンド群: post_process（HTML 後処理）
      # ------------------------------------------------
      # - 目的: 生成された HTML に対して後処理を実行
      # - 提供コマンド: post_process
      # - 主な処理: <body> クラス付与, 置換ルール適用, 章末脚注→ページ脚注,
      #            Prism.js 行番号付与
      # - 関連: 共通処理は `lib/vivlio/starter/cli/common.rb`
      # ================================================================
      module PostProcessCommands
        extend self
        def included(base)
          base.class_eval do
            desc 'post_process [TOKENS...]', 'HTMLファイルのポスト置換処理を行います'
            long_desc <<~DESC
              指定した HTML ファイルの後処理を行います。指定が無い場合はプロジェクトルートの全 .html を対象にします。

              処理内容:
              - <body> タグにファイルタイプクラスを付与
              - _post_replace_list.yml に基づく置換処理
              - 章末脚注をページ脚注に変換
              - ソースコードに行番号を追加（Prism.js対応）

              例:
                vs post_process 11-install
                vs post_process 11-install.html 12-tutorial
            DESC
            # ================================================================
            # Command: post_process（HTML 後処理）
            # ------------------------------------------------
            # - 概要: HTML に各種後処理を適用
            # - 入力: *.html（引数未指定時はカレント直下の *.html）
            # - 出力: 上書き保存
            # - 補足: 置換ルールは _post_replace_list.yml（YAML配列）
            # ================================================================
            def post_process(*tokens)
              ENV['VERBOSE'] = '1' if options[:verbose]

              files = Common.normalize_tokens(tokens)

              # ベースディレクトリ（常にプロジェクトルート）
              base_dir = '.'

              # 引数があれば .html のみを対象にする
              html_files = if files.any?
                files.map { |f|
                  name = f.end_with?('.html') ? f : "#{f}.html"
                  File.dirname(name) == '.' ? File.join(base_dir, name) : name
                }.uniq
              else
                Dir.glob(File.join(base_dir, '*.html'))
              end

              # file_typeを取得して、<body> にクラスを付与
              html_files.each do |html_file|
                content   = File.read(html_file, encoding: 'utf-8')
                file_type = Common.get_file_type(html_file)
                updated   = content.gsub('<body>', "<body class=\"#{file_type}\">")
                File.write(html_file, updated, encoding: 'utf-8')
                Common.log_info("#{html_file}: <body>→class追加(#{file_type})")
              end

              # 置換ルールの読み込み（YAMLのみ）
              replace_rules = nil
              target_yml = '_post_replace_list.yml'

              if File.exist?(target_yml)
                begin
                  yml_content = File.read(target_yml, encoding: 'utf-8')
                  parsed = YAML.safe_load(yml_content, permitted_classes: [], aliases: true)
                  replace_rules = parsed.is_a?(Array) ? parsed : nil
                  Common.log_error('エラー: YAMLファイルは置換オブジェクト配列である必要があります') unless replace_rules
                  Common.log_info("置換ルール: #{File.basename(target_yml)} を使用")
                rescue => e
                  Common.log_error("YAMLの読み込みに失敗: #{e.message}")
                end
              else
                Common.log_error("置換ルールYAMLが見つかりません: #{target_yml}")
              end

              # 置換ルールをもとにHTMLファイルの置換処理
              total_replacements = 0
              html_files.each do |html_file|
                Common.log_action("処理中: #{html_file}")
                result = process_html_file(html_file, replace_rules)
                if result[:changed]
                  total_replacements += result[:replacements]
                  Common.log_success("#{html_file}: #{result[:replacements]}個の置換を反映")
                else
                  Common.log_info("#{html_file}: 変更なし")
                end

                # 章末脚注→ページ脚注 変換
                content = File.read(html_file, encoding: 'utf-8')
                converted = convert_endnotes_to_page_footnotes!(content)
                if converted != content
                  File.write(html_file, converted, encoding: 'utf-8')
                  Common.log_success("#{html_file}: 章末脚注をページ脚注に変換")
                end

                # 行番号を追加(Prism.js対応) — 各ファイルごとに処理
                Vivlio::Starter::ThorCLI.start(['prism_lines', html_file])
              end

              Common.log_success("ポスト置換処理完了 (合計: #{total_replacements}個の置換)")
            end
          end
        end

        private

        # 指定HTMLファイルに対して、replace_rulesに基づく置換を適用
        # 戻り値: { changed: true/false, replacements: Integer }
        def process_html_file(html_file, replace_rules)
          html_content     = File.read(html_file, encoding: 'utf-8')
          original_content = html_content.dup
          file_replacements = 0

          # 置換ルール適用
          if replace_rules
            replace_rules.each do |item|
              next unless item.is_a?(Hash) && item.key?('f') && item.key?('r')

              pattern         = Regexp.new(item['f'])
              replacement_str = item['r'].dup
              matches_found   = 0

              html_content.gsub!(pattern) do |match|
                matches_found += 1
                m      = pattern.match(match)
                result = replacement_str.dup
                if m && m.captures.any?
                  m.captures.each_with_index { |cap, i| result.gsub!("$#{i + 1}", cap.to_s) }
                end
                result
              end

              if matches_found > 0
                file_replacements += matches_found
                Common.log_info("パターン '#{item['f']}' → #{matches_found}個の置換")
              end
            end
          end

          changed = html_content != original_content
          if changed
            File.write(html_file, html_content, encoding: 'utf-8')
          end

          { changed: changed, replacements: file_replacements }
        end

        # 章末の endnotes をページ脚注へ変換
        def convert_endnotes_to_page_footnotes!(html)
          # Nokogiri で解析（HTML5があれば優先）
          doc = if defined?(Nokogiri::HTML5)
                  Nokogiri::HTML5.parse(html)
                else
                  Nokogiri::HTML.parse(html, nil, 'UTF-8')
                end

          footnotes = doc.at_css('section.footnotes')
          return html unless footnotes

          # 定義の収集: <li id="fn1"> ... </li>
          defs = {}
          footnotes.css('li[id]').each do |li|
            fid = li['id']
            cleaned = li.dup
            # 戻りリンク除去
            cleaned.css('a.footnote-back, a.footnote-backref').each(&:remove)
            # 空段落除去
            cleaned.css('p').select { |p| p.text.strip.empty? }.each(&:remove)
            # <li> の内側HTML
            inner = cleaned.children.map(&:to_html).join.strip
            defs[fid] = inner
          end

          # footnotes セクション自体を除去
          footnotes.remove

          # 参照直後に脚注ノードを挿入
          defs.each do |fid, body|
            # アンカー参照（もっとも一般的）
            anchor = doc.at_css(%(a[href="##{fid}"]))
            if anchor
              in_paragraph = anchor.ancestors('p').any?
              if in_paragraph
                # 画面: インライン用 span
                span = Nokogiri::XML::Node.new('span', doc)
                span['role'] = 'doc-footnote'
                span['class'] = 'page-footnote page-footnote-inline'
                span['id'] = fid
                span.inner_html = body
                anchor.add_next_sibling(span)

                # 直後の空白をノーブレークスペースに変換して改行を防止
                following = span.next_sibling
                if following && following.text?
                  txt = following.text
                  if txt.start_with?(' ')
                    following.content = "\u00A0" + txt.lstrip
                  end
                end

                # 印刷: ページ脚注用 aside（画面では非表示）
                aside = Nokogiri::XML::Node.new('aside', doc)
                aside['role'] = 'doc-footnote'
                aside['class'] = 'page-footnote page-footnote-print'
                aside['id'] = fid
                aside.inner_html = body
                # 段落を壊さないよう、<p> の直後に配置
                para = anchor.ancestors('p').first
                if para
                  para.add_next_sibling("\n")
                  para.add_next_sibling(aside)
                else
                  # 念のためのフォールバック
                  anchor.add_next_sibling("\n")
                  anchor.add_next_sibling(aside)
                end
              else
                # 段落外: 従来どおり aside を使用
                aside = Nokogiri::XML::Node.new('aside', doc)
                aside['role'] = 'doc-footnote'
                aside['class'] = 'page-footnote page-footnote-print'
                aside['id'] = fid
                aside.inner_html = body
                anchor.add_next_sibling("\n")
                anchor.add_next_sibling(aside)
              end
              next
            end

            # フォールバック: 本文末尾に追加
            body_el = doc.at_css('body') || doc
            aside = Nokogiri::XML::Node.new('aside', doc)
            aside['role'] = 'doc-footnote'
            aside['class'] = 'page-footnote'
            aside['id'] = fid
            aside.inner_html = body
            body_el.add_child("\n")
            body_el.add_child(aside)
          end

          # 追加パス: 定義のない脚注参照にも対応
          doc.css('a.footnote-ref[href^="#fn"]').each do |anchor|
            href = anchor['href']
            next unless href&.start_with?('#')
            fid = href.delete_prefix('#')
            # 既に処理済みならスキップ
            next if doc.at_css(%(##{fid}))

            # 直前のリンク要素からURLを推定
            prev_link = anchor.previous_element
            while prev_link && prev_link.name != 'a'
              prev_link = prev_link.previous_element
            end
            url = prev_link&.[]('href')
            next unless url && !url.empty?

            # 本文HTML: URLをそのまま表示するリンク
            body = %Q(<a href="#{url}">#{url}</a>)

            in_paragraph = anchor.ancestors('p').any?
            if in_paragraph
              span = Nokogiri::XML::Node.new('span', doc)
              span['role'] = 'doc-footnote'
              span['class'] = 'page-footnote page-footnote-inline'
              span['id'] = fid
              span.inner_html = body
              anchor.add_next_sibling(span)

              # 改行防止のノーブレークスペース
              following = span.next_sibling
              if following && following.text?
                txt = following.text
                if txt.start_with?(' ')
                  following.content = "\u00A0" + txt.lstrip
                end
              end

              aside = Nokogiri::XML::Node.new('aside', doc)
              aside['role'] = 'doc-footnote'
              aside['class'] = 'page-footnote page-footnote-print'
              aside['id'] = fid
              aside.inner_html = body
              para = anchor.ancestors('p').first
              if para
                para.add_next_sibling("\n")
                para.add_next_sibling(aside)
              else
                anchor.add_next_sibling("\n")
                anchor.add_next_sibling(aside)
              end
            else
              aside = Nokogiri::XML::Node.new('aside', doc)
              aside['role'] = 'doc-footnote'
              aside['class'] = 'page-footnote page-footnote-print'
              aside['id'] = fid
              aside.inner_html = body
              anchor.add_next_sibling("\n")
              anchor.add_next_sibling(aside)
            end
          end

          # HTML 文字列として返却
          if doc.respond_to?(:to_html)
            doc.to_html
          else
            doc.to_s
          end
        end
      end
    end
  end
end
