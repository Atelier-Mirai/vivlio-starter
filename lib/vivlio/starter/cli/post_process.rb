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
        module_function

        POST_PROCESS_DESC = {
          short: 'HTMLファイルのポスト置換処理を行います',
          long: <<~DESC
            指定した HTML ファイルの後処理を行います。指定が無い場合はプロジェクトルートの全 .html を対象にします。

            処理内容:
            - <body> タグにファイルタイプクラスを付与
            - book.yml の files.post_replace で指定された YAML に基づく置換処理
            - 章末脚注をページ脚注に変換
            - ソースコードに行番号を追加（Prism.js対応）

            例:
              vs post_process 11-install
              vs post_process 11-install.html 12-tutorial
          DESC
        }.freeze

        def included(base)
          base.class_eval do
            desc 'post_process [TOKENS...]', POST_PROCESS_DESC[:short]
            long_desc POST_PROCESS_DESC[:long]
            # ================================================================
            # Command: post_process（HTML 後処理）
            # ------------------------------------------------
            # - 概要: HTML に各種後処理を適用
            # - 入力: *.html（引数未指定時はカレント直下の *.html）
            # - 出力: 上書き保存
            # - 補足: 置換ルールは book.yml の files.post_replace（YAML配列）
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
                             files.map do |f|
                               name = f.end_with?('.html') ? f : "#{f}.html"
                               File.dirname(name) == '.' ? File.join(base_dir, name) : name
                             end.uniq
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
              target_yml = Common.post_replace_file_path
              display_yml = target_yml && Common.relative_path_from_root(target_yml)

              if target_yml && File.exist?(target_yml)
                begin
                  yml_content = File.read(target_yml, encoding: 'utf-8')
                  parsed = YAML.safe_load(yml_content, permitted_classes: [], aliases: true)
                  # 期待スキーマ: 配列 [ { 'f': '正規表現文字列', 'r': '置換文字列' }, ... ]
                  # - 'f' は Ruby Regexp として評価
                  # - 'r' はキャプチャ $1..$n をサポート（gsub ブロック内で展開）
                  replace_rules = parsed.is_a?(Array) ? parsed : nil
                  Common.log_error('エラー: YAMLファイルは置換オブジェクト配列である必要があります') unless replace_rules
                  Common.log_info("置換ルール: #{display_yml || target_yml} を使用")
                rescue StandardError => e
                  Common.log_error("YAMLの読み込みに失敗: #{e.message}")
                end
              else
                missing_label = if display_yml
                                  display_yml
                                elsif target_yml
                                  target_yml
                                elsif Common::POST_REPLACE_FILE
                                  Common::POST_REPLACE_FILE
                                else
                                  '(未設定)'
                                end
                Common.log_error("置換ルールYAMLが見つかりません: #{missing_label}")
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
                rescue StandardError => e
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
                rescue StandardError => e
                  Common.log_warn("#{html_file}: 見出しメタ付与に失敗: #{e}")
                end

                begin
                  inject_heading_number_spans!(html_file)
                  Common.log_info("#{html_file}: 見出し番号スパンを構築")
                rescue StandardError => e
                  Common.log_warn("#{html_file}: 見出し番号スパン構築に失敗: #{e}")
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
            html = File.read(path, encoding: 'utf-8')
            doc  = if defined?(Nokogiri::HTML5)
                     Nokogiri::HTML5.parse(html)
                   else
                     Nokogiri::HTML.parse(html, nil, 'UTF-8')
                   end
            modified = false
            chapter_token = File.basename(path, File.extname(path)).to_s.strip
            chapter_token = nil if chapter_token.empty?
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
                heading_text = extract_heading_core_text(h)
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

                  if lvl == 1 && h['id'].to_s.strip.empty?
                    h['id'] = heading_text
                    modified = true
                  end
                end

                if chapter_token && h['data-chapter'] != chapter_token
                  h['data-chapter'] = chapter_token
                  modified = true
                end
              end
            end
            if modified
              out = doc.respond_to?(:to_html) ? doc.to_html : doc.to_s
              File.write(path, out, encoding: 'utf-8')
            end
          rescue StandardError => e
            Common.log_warn("見出しメタ付与に失敗: #{path} (#{e})")
          end
        end

        MAIN_CHAPTER_RANGE = (11..89)

        def inject_heading_number_spans!(html_path)
          return unless File.exist?(html_path)

          html = File.read(html_path, encoding: 'utf-8')
          doc = if defined?(Nokogiri::HTML5)
                  Nokogiri::HTML5.parse(html)
                else
                  Nokogiri::HTML.parse(html, nil, 'UTF-8')
                end

          file_type = Common.get_file_type(html_path)
          chapter_token = File.basename(html_path, File.extname(html_path))
          chapter_number = Common.get_chapter_number(chapter_token)
          chapter_number_i = chapter_number&.to_i

          chapter_display_number = resolve_main_chapter_display_number(chapter_token, chapter_number_i)
          appendix_letter = nil

          if chapter_number_i&.between?(91, 97)
            appendix_letter = Common.appendix_number_to_letter(chapter_number_i)&.upcase
          end

          process_h1 = %w[chapter appendix].include?(file_type)
          process_h2 = %w[chapter appendix].include?(file_type)
          process_h3 = %w[chapter appendix].include?(file_type)

          modified = false

          if process_h1 && (h1 = doc.at_css('h1'))
            title_text = extract_heading_core_text(h1)
            number_text = if file_type == 'appendix'
                            appendix_letter ? "付録 #{appendix_letter}" : nil
                          elsif chapter_display_number
                            "第#{chapter_display_number}章"
                          end
            modified |= rebuild_heading_with_spans(h1, number_text, title_text, :chapter, doc)
            if number_text
              h1['data-chapter-number-display'] = number_text
            else
              h1.delete('data-chapter-number-display')
            end
            if title_text
              h1['data-chapter-title'] = title_text
            else
              h1.delete('data-chapter-title')
            end
          end

          if process_h2
            section_index = 0
            doc.css('h2').each do |h2|
              section_index += 1
              title_text = extract_heading_core_text(h2)
              number_text = if file_type == 'appendix'
                              appendix_letter ? "#{appendix_letter}-#{section_index}" : section_index.to_s
                            elsif chapter_display_number
                              "#{chapter_display_number}-#{section_index}"
                            else
                              section_index.to_s
                            end
              modified |= rebuild_heading_with_spans(h2, number_text, title_text, :section, doc)
              h2['data-section-number-display'] = number_text if number_text
              h2['data-section-title'] = title_text if title_text
            end
          end

          if process_h3
            marker = Common::CONFIG.dig('theme', 'markers', 'h3') || '♣'
            doc.css('h3').each do |h3|
              title_text = extract_heading_core_text(h3)
              modified |= rebuild_heading_with_spans(h3, marker, title_text, :subsection, doc)
              h3['data-subsection-title'] = title_text if title_text
            end
          end

          return unless modified

          out = doc.respond_to?(:to_html) ? doc.to_html : doc.to_s
          File.write(html_path, out, encoding: 'utf-8')
        end

        def rebuild_heading_with_spans(node, number_text, title_text, kind, doc)
          number_text = number_text.to_s.strip
          title_text = title_text.to_s.strip

          number_class, title_class = case kind
                                      when :chapter then %w[chapter-number chapter-title]
                                      when :section then %w[section-number section-title]
                                      when :subsection then %w[subsection-marker subsection-title]
                                      else [nil, nil]
                                      end

          current_number_span = number_class ? node.at_css("span.#{number_class}") : nil
          current_title_span  = title_class ? node.at_css("span.#{title_class}") : nil

          current_number = current_number_span&.text&.strip
          current_title  = current_title_span&.text&.strip
          current_title ||= extract_heading_core_text(current_title_span || node)

          needs_update = false
          needs_update ||= (number_text.empty? ? !current_number.to_s.empty? : current_number != number_text)
          needs_update ||= (current_title != title_text)

          return false unless needs_update

          original_title_nodes = if current_title_span
                                   current_title_span.children.map(&:dup)
                                 else
                                   node.children.reject do |child|
                                     number_class && child.element? && child['class'].to_s.split.include?(number_class)
                                   end.map(&:dup)
                                 end

          node.children.remove

          if number_class && !number_text.empty?
            span = Nokogiri::XML::Node.new('span', doc)
            span['class'] = number_class
            span.content = number_text
            node.add_child(span)
          end

          if title_class
            span = Nokogiri::XML::Node.new('span', doc)
            span['class'] = title_class
            if original_title_nodes.empty?
              span.content = title_text
            else
              original_title_nodes.each { |child| span.add_child(child) }
            end
            node.add_child(span)
          else
            node.add_child(Nokogiri::XML::Text.new(title_text, doc)) unless title_text.empty?
          end

          true
        end

        def extract_heading_core_text(node)
          %w[chapter-title section-title subsection-title].each do |cls|
            span = node.at_css("span.#{cls}")
            return span.text.to_s.strip if span
          end
          node.text.to_s.strip
        end

        def resolve_main_chapter_display_number(chapter_token, chapter_number_i = nil)
          return nil if chapter_token.nil? || chapter_token.empty?

          chapter_number_i ||= Common.get_chapter_number(chapter_token)&.to_i
          return nil unless chapter_number_i && MAIN_CHAPTER_RANGE.include?(chapter_number_i)

          order = main_chapter_order
          if (idx = order.index(chapter_token))
            return idx + 1
          end

          chapter_number_i - 10
        end

        def main_chapter_order
          @main_chapter_order ||= begin
            configured = configured_main_chapter_tokens
            tokens = configured&.any? ? configured : discovered_main_chapter_tokens
            tokens
          end
        end

        def configured_main_chapter_tokens
          cfg = Common::CONFIG['chapters']
          raw_list = case cfg
                     when nil
                       nil
                     when String
                       str = cfg.to_s
                       return nil if str.strip.casecmp('all').zero?

                       str.lines.map(&:strip).reject(&:empty?)
                     when Array
                       cfg.map { |s| s.to_s.strip }.reject(&:empty?)
                     end
          return nil unless raw_list&.any?

          normalize_and_filter_tokens(raw_list)
        end

        def discovered_main_chapter_tokens
          html_tokens = Dir.glob(File.join('.', '*.html')).map { |path| File.basename(path, '.html') }
          normalize_and_filter_tokens(html_tokens).sort_by { |token| Common.get_chapter_number(token).to_i }
        end

        def normalize_and_filter_tokens(list)
          seen = {}
          Array(list).each_with_object([]) do |entry, acc|
            token = normalize_chapter_token(entry)
            next unless token
            next unless main_chapter_token?(token)
            next if seen[token]

            seen[token] = true
            acc << token
          end
        end

        def normalize_chapter_token(entry)
          s = entry.to_s.strip
          return nil if s.empty?

          s = s.sub(%r{\A\./}, '')
          s = s.sub(%r{\A#{Regexp.escape(Common::CONTENTS_DIR)}/}i, '')
          s = s.sub(/\.(html|md)\z/i, '')
          s = s.sub(/\.(html|md)\z/i, '') # 念のため二重拡張を排除
          s = s.strip
          return nil if s.empty?

          s
        end

        def main_chapter_token?(token)
          num = Common.get_chapter_number(token)
          num && MAIN_CHAPTER_RANGE.include?(num.to_i)
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
          replace_rules&.each do |item|
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
              m.captures.each_with_index { |cap, i| result.gsub!("$#{i + 1}", cap.to_s) } if m&.captures&.any?
              result
            end

            next unless matches_found.positive?

            # このファイルで何件置換したかを集計してログに反映
            file_replacements += matches_found
            Common.log_info("パターン '#{item['f']}' → #{matches_found}個の置換")
          end

          changed = html_content != original_content
          File.write(html_file, html_content, encoding: 'utf-8') if changed

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

          doc = parse_html_document(html)
          transformed = wrap_sections_with_article!(doc)
          transformed ? render_html_document(doc) : html
        end

        # Nokogiri を用いて HTML 文字列からドキュメントオブジェクトを生成する
        def parse_html_document(html)
          if defined?(Nokogiri::HTML5)
            Nokogiri::HTML5.parse(html)
          else
            Nokogiri::HTML.parse(html, nil, 'UTF-8')
          end
        end

        # Nokogiri ドキュメントを HTML 文字列へ戻す（HTML5/HTML 両対応）
        def render_html_document(doc)
          doc.respond_to?(:to_html) ? doc.to_html : doc.to_s
        end

        # section.level2 直下の h2 を article.section-topic でラップする
        def wrap_sections_with_article!(doc)
          changed = false
          doc.css('section.level2').each do |section|
            h2 = section.at_css('> h2')
            next unless h2 && h2.ancestors('article.section-topic').empty?

            lead = find_section_lead_for(h2)
            wrap_with_article(section, h2, lead)
            changed = true
          end
          changed
        end

        # h2 に続く .section-lead ノードを探索して返す
        def find_section_lead_for(h2)
          node = h2.next_sibling
          while node
            return node if node.element? && (node['class']&.split || []).include?('section-lead')

            if node.element? && node.name == 'p' && zero_width_text?(node.text)
              node = node.next_sibling
              next
            end

            node = node.element? ? nil : node.next_sibling
          end
          nil
        end

        # ゼロ幅スペース等のみで構成されているかを判定する
        def zero_width_text?(text)
          text.gsub(/[\u200B\u200C\u200D\u2060\uFEFF\u180E]/, '').strip.empty?
        end

        # h2 と（存在すれば）section-lead を article.section-topic で包む
        def wrap_with_article(section, h2, lead)
          article = Nokogiri::XML::Node.new('article', section.document)
          article['class'] = 'section-topic'
          h2.add_previous_sibling("\n")
          h2.add_previous_sibling(article)
          article.add_child(h2)
          return unless lead

          article.add_child("\n")
          article.add_child(lead)
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
          doc = parse_html_document(html)
          footnotes = doc.at_css('section.footnotes')
          return html unless footnotes

          definitions = extract_footnote_definitions(footnotes)
          footnotes.remove

          insert_footnotes_for_references!(doc, definitions)
          append_unused_footnotes_to_body!(doc, definitions)
          fill_missing_footnote_references!(doc)

          render_html_document(doc)
        end

        # section.footnotes 内の脚注定義を id => HTML として抽出する
        def extract_footnote_definitions(footnotes_section)
          footnotes_section.css('li[id]').each_with_object({}) do |li, memo|
            fid = li['id']
            cleaned = li.dup
            cleaned.css('a.footnote-back, a.footnote-backref').each(&:remove)
            cleaned.css('p').select { |p| p.text.strip.empty? }.each(&:remove)
            memo[fid] = cleaned.children.map(&:to_html).join.strip
          end
        end

        # 本文中の脚注参照アンカーへ定義を差し込む
        def insert_footnotes_for_references!(doc, definitions)
          definitions.keys.each do |fid|
            body = definitions[fid]
            anchor = doc.at_css(%(a[href="##{fid}"]))
            next unless anchor

            insert_footnote_for_anchor!(doc, anchor, fid, body)
            definitions.delete(fid)
          end
        end

        # アンカー位置に応じてインライン/印刷脚注を挿入する
        def insert_footnote_for_anchor!(doc, anchor, fid, body)
          if anchor.ancestors('p').any?
            insert_inline_footnote!(doc, anchor, fid, body)
            insert_print_footnote_after_paragraph!(doc, anchor, fid, body)
          else
            insert_print_footnote_after_anchor!(doc, anchor, fid, body)
          end
        end

        # インライン脚注 span を参照アンカー直後に挿入する
        def insert_inline_footnote!(doc, anchor, fid, body)
          span = build_inline_footnote_node(doc, fid, body)
          anchor.add_next_sibling(span)
          adjust_following_whitespace(span)
        end

        # 段落内参照の場合、段落直後に印刷用脚注 aside を差し込む
        def insert_print_footnote_after_paragraph!(doc, anchor, fid, body)
          aside = build_print_footnote_node(doc, fid, body)
          para = anchor.ancestors('p').first
          if para
            para.add_next_sibling("\n")
            para.add_next_sibling(aside)
          else
            anchor.add_next_sibling("\n")
            anchor.add_next_sibling(aside)
          end
        end

        # 段落外参照の場合、アンカーの直後に印刷用脚注を配置する
        def insert_print_footnote_after_anchor!(doc, anchor, fid, body)
          aside = build_print_footnote_node(doc, fid, body)
          anchor.add_next_sibling("\n")
          anchor.add_next_sibling(aside)
        end

        # 残った脚注定義を本文末尾の aside として追加する
        def append_unused_footnotes_to_body!(doc, definitions)
          return if definitions.empty?

          body_el = doc.at_css('body') || doc
          definitions.each do |fid, body|
            aside = Nokogiri::XML::Node.new('aside', doc)
            aside['role'] = 'doc-footnote'
            aside['class'] = 'page-footnote'
            aside['id'] = fid
            aside.inner_html = body
            body_el.add_child("\n")
            body_el.add_child(aside)
          end
        end

        # 定義が存在しない脚注参照を前方リンクから推測して補完する
        def fill_missing_footnote_references!(doc)
          doc.css('a.footnote-ref[href^="#fn"]').each do |anchor|
            fid = anchor['href']&.delete_prefix('#')
            next unless fid
            next if doc.at_css(%(##{fid}))

            body = inferred_body_from_previous_link(anchor)
            next unless body

            if anchor.ancestors('p').any?
              insert_inline_footnote!(doc, anchor, fid, body)
              insert_print_footnote_after_paragraph!(doc, anchor, fid, body)
            else
              insert_print_footnote_after_anchor!(doc, anchor, fid, body)
            end
          end
        end

        # 脚注参照直前のリンク要素から本文 HTML を推定する
        def inferred_body_from_previous_link(anchor)
          prev_link = anchor.previous_element
          prev_link = prev_link.previous_element while prev_link && prev_link.name != 'a'
          url = prev_link&.[]('href')
          return unless url && !url.empty?

          %(<a href="#{url}">#{url}</a>)
        end

        # インライン脚注用の span ノードを生成する
        def build_inline_footnote_node(doc, fid, body)
          span = Nokogiri::XML::Node.new('span', doc)
          span['role'] = 'doc-footnote'
          span['class'] = 'page-footnote page-footnote-inline'
          span['id'] = fid
          span.inner_html = body
          span
        end

        # 印刷用脚注の aside ノードを生成する
        def build_print_footnote_node(doc, fid, body)
          aside = Nokogiri::XML::Node.new('aside', doc)
          aside['role'] = 'doc-footnote'
          aside['class'] = 'page-footnote page-footnote-print'
          aside['id'] = fid
          aside.inner_html = body
          aside
        end

        # インライン脚注後の空白をノーブレークスペースへ変換する
        def adjust_following_whitespace(node)
          following = node.next_sibling
          return unless following&.text?

          text = following.text
          following.content = " #{text.lstrip}" if text.start_with?(' ')
        end
      end
    end
  end
end
