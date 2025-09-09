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
            # - パイプライン概要:
            #   (1) 対象HTML解決 → (2) <body> に file_type クラス付与 →
            #   (3) YAML置換の適用 → (4) 章末脚注をページ脚注へ変換 → (5) Prism行番号付与
            # ================================================================
            def post_process(*tokens)
              ENV['VERBOSE'] = '1' if options[:verbose]

              files = Common.normalize_tokens(tokens)

              # ベースディレクトリ（常にプロジェクトルート）
              base_dir = '.'

              # 引数があれば .html のみを対象にする
              # - トークンは拡張子 .html を強制し、相対指定はプロジェクトルートに解決
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
                # 単純置換で <body> にクラスを付与
                # - 既存 class 属性が無いテンプレ構成を前提に、文字列置換で高速に処理
                # - 今後 <body> に既に属性が付く可能性がある場合は、正規表現に切替が必要
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
                  # 期待スキーマ: 配列 [ { 'f': '正規表現文字列', 'r': '置換文字列' }, ... ]
                  # - 'f' は Ruby Regexp として評価
                  # - 'r' はキャプチャ $1..$n をサポート（gsub ブロック内で展開）
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

                # theme.style: image のとき、section.level2 内の h2（および直後の .section-lead）を
                # <article class="section-topic"> でラップする
                begin
                  content_before = File.read(html_file, encoding: 'utf-8')
                  content_after  = wrap_h2_with_article_if_image_style!(content_before)
                  if content_after != content_before
                    File.write(html_file, content_after, encoding: 'utf-8')
                    Common.log_success("#{html_file}: h2 を <article.section-topic> でラップ（theme.style=image）")
                    # ラップ後に生じた空段落などを除去するため、置換ルールを再適用
                    result2 = process_html_file(html_file, replace_rules)
                    if result2[:changed]
                      Common.log_success("#{html_file}: ラップ後の不要な空段落をクリーンアップ (#{result2[:replacements]}件)")
                    end
                  end
                rescue => e
                  Common.log_error("#{html_file}: section-topic ラップ中にエラー: #{e.message}")
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

                # 見出し(h1..h3)にクラス/data属性を付与（PDF参照用のメタ）
                begin
                  inject_heading_markers!([html_file], max_level: 3)
                  Common.log_info("#{html_file}: 見出しメタを付与 (class=data)")
                rescue => e
                  Common.log_warn("#{html_file}: 見出しメタ付与に失敗: #{e}")
                end
              end

              Common.log_success("ポスト置換処理完了 (合計: #{total_replacements}個の置換)")
            end
          end
        end

        private

        # 見出し(h1..hN)に本文参照用のマーカー（class と data 属性）を付与
        # - class: vs-h-marker（既存クラスは保持）
        # - data-heading: 見出しテキスト（汎用）
        # - data-hN: 見出しテキスト（レベル別）
        # 旧実装による直前の <div.vs-h-marker> は除去し、版面崩れを防ぐ
        def inject_heading_markers!(html_paths, max_level: 3)
          paths = Array(html_paths).select { |p| File.exist?(p) }
          return if paths.empty?
          max_l = [[max_level.to_i, 1].max, 6].min
          paths.each do |path|
            begin
              html = File.read(path, encoding: 'utf-8')
              doc  = if defined?(Nokogiri::HTML5)
                        Nokogiri::HTML5.parse(html)
                      else
                        Nokogiri::HTML.parse(html, nil, 'UTF-8')
                      end
              modified = false
              (1..max_l).each do |lvl|
                doc.css("h#{lvl}").each do |h|
                  # 見出し要素自体に vs-h-marker クラスを付与
                  classes = (h['class'] || '').split
                  unless classes.include?('vs-h-marker')
                    classes << 'vs-h-marker'
                    h['class'] = classes.join(' ').strip
                    modified = true
                  end

                  # 見出しテキストを data 属性として付与（PDFアウトライン等の外部処理向け）
                  heading_text = h.text.to_s.strip
                  if heading_text && !heading_text.empty?
                    # data-heading（汎用）と data-h{level}（レベル別）の両方を設定
                    if h['data-heading'] != heading_text
                      h['data-heading'] = heading_text
                      modified = true
                    end
                    lvl_key = "data-h#{lvl}"
                    if h[lvl_key] != heading_text
                      h[lvl_key] = heading_text
                      modified = true
                    end
                  end
                end
              end
              if modified
                out = doc.respond_to?(:to_html) ? doc.to_html : doc.to_s
                File.write(path, out, encoding: 'utf-8')
              end
            rescue => e
              Common.log_warn("見出しメタ付与に失敗: #{path} (#{e})")
            end
          end
        end

        

        # 指定HTMLファイルに対して、replace_rulesに基づく置換を適用
        # 戻り値: { changed: true/false, replacements: Integer }
        # - 各 item は { 'f': 正規表現文字列, 'r': 置換文字列 } を想定
        # - 'f' は Regexp として評価し、'r' は $1..$n をキャプチャに展開
        # - ファイル単位で置換回数を集計し、差分があれば保存
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

              # String#gsub(Regexp) { |match| ... } を用い、各一致ごとに置換文字列を生成
              # - ブロック内で pattern.match(match) を取り直してキャプチャ順で $1..$n を展開
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
                # このファイルで何件置換したかを集計してログに反映
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

        # theme.style が image の場合に、章セクションの見出しを <article.section-topic>
        # でラップし、CSS グリッドの対象構造を整える。
        # 規則:
        # - 対象: <section class="level2"> の直下にある <h2>
        # - 直後にある .section-lead（要素ノード）も一緒にラップする（存在すれば）
        # - 既に <article.section-topic> でラップ済みの場合は何もしない
        def wrap_h2_with_article_if_image_style!(html)
          return html unless Common::CONFIG.dig('theme', 'style') == 'image'

          doc = if defined?(Nokogiri::HTML5)
                  Nokogiri::HTML5.parse(html)
                else
                  Nokogiri::HTML.parse(html, nil, 'UTF-8')
                end

          changed = false

          doc.css('section.level2').each do |section|
            # section 直下の h2 を対象
            h2 = section.at_css('> h2')
            next unless h2
            # 既に article.section-topic 配下ならスキップ
            next if h2.ancestors('article.section-topic').any?

            # h2 の直後に現れる .section-lead（要素ノード）を探索
            # 空の <p> などはスキップし、はじめに見つかった .section-lead を採用
            lead = nil
            node = h2.next_sibling
            while node
              if node.element?
                classes = node['class']&.split || []
                if classes.include?('section-lead')
                  lead = node
                  break
                end
                # 空段落 <p> はスキップ（改行や空白・ゼロ幅文字のみ）
                if node.name == 'p' && (node.text.gsub(/[\u200B\u200C\u200D\u2060\uFEFF\u180E]/, '').strip.empty?)
                  node = node.next_sibling
                  next
                end
                # それ以外の要素が来たら探索終了
                break
              else
                # テキストノードやコメントはスキップ
                node = node.next_sibling
              end
            end

            article = Nokogiri::XML::Node.new('article', doc)
            article['class'] = 'section-topic'

            # h2 の直前に article を挿入し、h2 と（あれば）lead を移動
            h2.add_previous_sibling("\n")
            h2.add_previous_sibling(article)
            article.add_child(h2)
            if lead
              article.add_child("\n")
              article.add_child(lead)
            end
            changed = true
          end

          return html unless changed

          if doc.respond_to?(:to_html)
            doc.to_html
          else
            doc.to_s
          end
        end

        # 章末の endnotes をページ脚注へ変換
        # アルゴリズム概要:
        # 1) Nokogiri(HTML5優先)で解析し、section.footnotes 内の <li id="fnN"> を収集
        # 2) 戻りリンク/空段落を除去した内側HTMLを defs[fid] として保持
        # 3) footnotes セクションを削除
        # 4) 本文の参照アンカー <a href="#fid"> 直後に
        #    - 画面用: <span class="page-footnote page-footnote-inline" role="doc-footnote">
        #    - 印刷用: <aside class="page-footnote page-footnote-print" role="doc-footnote">
        #    を挿入。インライン後の空白は NBSP に置換し改行を抑止
        # 5) アンカー未検出の定義は <body> 末尾に aside を追加（フォールバック）
        # 6) 定義のない脚注参照 a.footnote-ref についても前方のリンクURLから本文を推定して補完
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
                # - 行末の脚注で折り返されると読みにくい問題に対応
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
                # - ブロックレベルでページ脚注を出すため、段落ノードの直後に sibling として置く
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
            # - Kramdown の [:ref] と生成物の差異により参照のみで定義が無いケースがあるため、
            #   実用上もっとも近い preceding <a> の href を本文として補完
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
