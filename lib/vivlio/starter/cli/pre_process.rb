# frozen_string_literal: true

require 'yaml'

module Vivlio
  module Starter
    module CLI
      # ================================================================
      # Module: Thor コマンド群: pre_process（Markdown 前処理）
      # ------------------------------------------------
      # - 目的: Markdown ファイルに対して前処理を実行
      # - 提供コマンド: pre_process
      # - 主な処理: フロントマター生成/更新, 画像パス修正, ソースコード取込,
      #            book-card/table-rotate ブロックのHTML化, リンク脚注化
      # - 関連: 共通処理は `lib/vivlio/starter/cli/common.rb`
      # ================================================================
      module PreProcessCommands
        extend self
        def included(base)
          base.class_eval do
            desc 'pre_process [TOKENS...]', 'Markdownファイルの前処理を行います'
            long_desc <<~DESC
              指定した Markdown ファイルの前処理を行います。指定が無い場合は contents/ 配下の全 .md を対象にします。

              処理内容:
              - フロントマターの生成/更新
              - 画像パスの修正
              - ソースコードインクルード
              - book-card/table-rotate ブロックの変換
              - リンクの脚注化

              例:
                vs pre_process 11-install
                vs pre_process 11-install.md 12-tutorial
            DESC
            # ================================================================
            # Command: pre_process（Markdown 前処理）
            # ------------------------------------------------
            # - 概要: 指定 Markdown を対象に前処理を適用
            # - 入力: contents/*.md または引数で指定した章
            # - 出力: 上書き保存（フロントマター、パス、ブロック変換等を反映）
            # - オプション: --verbose (-v)
            # ================================================================
            def pre_process(*tokens)
              ENV['VERBOSE'] = '1' if options[:verbose]
              # Common ベース実装

              # 引数を正規化
              files = Common.normalize_tokens(tokens)

              # 処理対象のファイルを決定
              md_files = if files.any?
                # 存在しないファイルをチェック
                missing_files = files.reject { |f| File.exist?("#{Common::CONTENTS_DIR}/#{f}.md") }
                if missing_files.any?
                  Common.log_error("エラー: 次のファイルが存在しません: #{missing_files.join(', ')}")
                  Common.log_warn("前処理を中止します")
                  exit(1)
                end

                files.map { |f| "#{Common::CONTENTS_DIR}/#{f}.md" }
              else
                # 引数がない場合は全Markdownファイルを処理
                Dir.glob("#{Common::CONTENTS_DIR}/*.md")
              end

              # 各Markdownファイルを処理
              Common.log_action("Markdownファイルの前処理を行っています...")
              md_files.each do |md_file|
                process_single_markdown_file(md_file)
              end

              Common.log_success("Markdownの前処理が完了しました")
            end
          end
        end

        private

        # 拡張子→言語の対応表
        EXT_TO_LANG = {
          'c'    => 'c',
          'cc'   => 'cpp',
          'cpp'  => 'cpp',
          'cs'   => 'csharp',
          'css'  => 'css',
          'cxx'  => 'cpp',
          'go'   => 'go',
          'html' => 'html',
          'java' => 'java',
          'js'   => 'javascript',
          'json' => 'json',
          'kt'   => 'kotlin',
          'md'   => 'markdown',
          'php'  => 'php',
          'py'   => 'python',
          'rb'   => 'ruby',
          'rs'   => 'rust',
          'scala'=> 'scala',
          'scss' => 'scss',
          'sh'   => 'bash',
          'sql'  => 'sql',
          'swift'=> 'swift',
          'ts'   => 'typescript',
          'xml'  => 'xml',
          'yaml' => 'yaml',
          'yml'  => 'yaml'
        }.freeze

        # ファイル拡張子から言語を推定
        def detect_language(file_path)
          ext = File.extname(file_path).downcase.delete_prefix('.')
          EXT_TO_LANG.fetch(ext, 'text')
        end

        # 簡易Markdown→HTML 変換
        def render_markdown_to_html(md_text)
          # まずはKramdownを試す
          begin
            require 'kramdown'
            return Kramdown::Document.new(md_text).to_html
          rescue LoadError
            # フォールバック: 最小限のMarkdownをHTMLへ
            lines = md_text.to_s.split(/\r?\n/)
            html_parts = []
            in_ol = false
            buffer_p = []

            flush_p = lambda do
              unless buffer_p.empty?
                paragraph = buffer_p.join(" ").strip
                html_parts << "<p>#{paragraph}</p>" unless paragraph.empty?
                buffer_p.clear
              end
            end

            lines.each do |line|
              if line.strip.empty?
                flush_p.call
                next
              end

              # 画像
              if m = line.match(/^\s*!\[[^\]]*\]\(([^)]+)\)\s*$/)
                flush_p.call
                src = m[1]
                html_parts << "<img src=\"#{src}\">"
                next
              end

              # 見出し相当の太字行
              if m = line.match(/^\s*\*\*(.+?)\*\*\s*$/)
                flush_p.call
                html_parts << "<p><strong>#{m[1]}</strong></p>"
                next
              end

              # 番号リスト
              if m = line.match(/^\s*(\d+)\.\s+(.*)$/)
                flush_p.call
                html_parts << "<ol>" unless in_ol
                in_ol = true
                html_parts << "<li>#{m[2]}</li>"
                next
              else
                if in_ol
                  html_parts << "</ol>"
                  in_ol = false
                end
              end

              buffer_p << line
            end

            flush_p.call
            html_parts << "</ol>" if in_ol
            html_parts.join("\n")
          end
        end

        # Markdown内のリンク記法を脚注化
        def transform_links_to_footnotes(md_text)
          text = md_text.to_s

          # 既存の url 脚注番号の最大を取得
          max_n = 0
          text.scan(/\[\^url(\d+)\]:/).each do |m|
            n = m[0].to_i
            max_n = n if n > max_n
          end

          url_id = {}
          replacements = []

          # リンク本体を置換
          replaced = text.gsub(/(?<!\!)\[(.+?)\]\((https?:[^\s)]+)\)(?!\[\^url\d+\])/) do |match|
            label = $1
            url   = $2
            id = (url_id[url] ||= begin
              max_n += 1
              "url#{max_n}"
            end)
            replacements << [id, url]
            "[#{label}](#{url}) [^#{id}]"
          end

          # 追加する脚注定義を生成
          existing_defs = {}
          text.scan(/\[\^(url\d+)\]:\s*(\S+)/) { |id, u| existing_defs[id] = u }

          new_defs = url_id.map { |u, id|
            next nil if existing_defs.key?(id)
            "[^#{id}]: #{u}"
          }.compact

          return replaced if new_defs.empty?

          # 文末に空行2つを挟んで脚注定義を追記
          if replaced.strip.end_with?("\n")
            replaced + "\n" + new_defs.join("\n") + "\n"
          else
            replaced + "\n\n" + new_defs.join("\n") + "\n"
          end
        end

        # book-card 内のMarkdownを事前整形
        def normalize_book_card_md(md_text)
          lines = md_text.to_s.split(/\r?\n/, -1)
          out = []
          lines.each_with_index do |line, i|
            out << line
            next_line = lines[i + 1]

            # 画像のみの行の直後に空行を補う
            if line.match(/^\s*!\[[^\]]*\]\([^)]+\)\s*$/)
              if next_line && next_line.strip != ""
                out << ""
              end
            # 太字のみの行の直後に空行を補う
            elsif line.match(/^\s*\*\*[^*].*\*\*\s*$/)
              if next_line && next_line.strip != ""
                out << ""
              end
            end
          end
          out.join("\n")
        end

        # <div class="book-card"> ... </div> の内側MarkdownをHTMLへ
        def convert_book_card_inner_markdown(content)
          content.gsub(/<div class=\"book-card\">\n(.*?)\n<\/div>/m) do
            inner = $1
            normalized = normalize_book_card_md(inner)
            html = render_markdown_to_html(normalized)
            formatted = format_book_card_inner_html(html)
            "<div class=\"book-card\">\n#{formatted}\n</div>"
          end
        end

        # パイプテーブルを簡易HTML化
        def pipe_table_to_html(md_text)
          text = md_text.to_s.strip
          lines = text.split(/\r?\n/).map { |l| l.rstrip }
          return nil if lines.size < 2

          header = lines[0]
          sep    = lines[1]
          return nil unless header.include?("|")
          return nil unless sep && sep =~ /^\s*\|?[\s:\-\|]+\|?\s*$/

          rows = lines[2..] || []

          to_cells = lambda do |line|
            parts = line.split("|")
            parts.shift if parts.first&.strip == ""
            parts.pop   if parts.last&.strip  == ""
            parts.map { |c| c.strip }
          end

          esc_code = lambda do |s|
            s.gsub(/`([^`]+)`/) { "<code>#{$1}</code>" }
              .gsub(/&/, "&amp;")
              .gsub(/</, "&lt;")
              .gsub(/>/, "&gt;")
          end

          thead_cells = to_cells.call(header)
          tbody_rows  = rows.map { |r| to_cells.call(r) }

          html = []
          html << "<table>"
          html << "  <thead>"
          html << "    <tr>#{thead_cells.map { |c| "<th>#{esc_code.call(c)}</th>" }.join}</tr>"
          html << "  </thead>"
          if tbody_rows.any?
            html << "  <tbody>"
            tbody_rows.each do |cells|
              html << "    <tr>#{cells.map { |c| "<td>#{esc_code.call(c)}</td>" }.join}</tr>"
            end
            html << "  </tbody>"
          end
          html << "</table>"
          html.join("\n")
        end

        # <div class="table-rotate"> ... </div> の内側MarkdownをHTMLへ
        def convert_table_rotate_inner_markdown(content)
          content.gsub(/<div class=\"table-rotate\">\s*(.*?)\s*<\/div>/m) do
            inner = $1
            normalized = "\n\n#{inner.to_s.strip}\n\n"
            html = render_markdown_to_html(normalized).to_s.strip

            # フォールバック
            if !html.include?("<table") && inner.include?("|")
              table_html = pipe_table_to_html(inner)
              html = table_html if table_html
            end

            "<div class=\"table-rotate\">\n#{html}\n<\/div>"
          end
        end

        # book-card の内側を整形
        def format_book_card_inner_html(inner_html)
          html = inner_html.to_s.strip

          # 1) 画像タグを抽出
          img_match = html.match(/<img[^>]*>/i)
          return inner_html unless img_match
          img_tag = img_match[0]
          img_tag = img_tag.gsub(/\s*\/?>/i) { |m| '>' }

          # 画像のみの<p>ラッパーを除去
          if html.sub!(/<p>\s*#{Regexp.escape(img_match[0])}\s*<\/p>/i, '')
            # removed wrapped <p> with img
          else
            html.sub!(img_match[0], '')
          end

          # 2) タイトルを抽出
          title_match = html.match(/<p>\s*<strong>(.*?)<\/strong>\s*<\/p>/im)
          return inner_html unless title_match
          title_text = title_match[1].strip
          html.sub!(title_match[0], '')

          # 3) 残りを説明HTMLとする
          description_html = html.strip

          # 4) 目標の構造で出力
          parts = []
          parts << "  #{img_tag}"
          parts << "  <div class=\"book-info\">"
          parts << "    <p class=\"book-title\">#{title_text}</p>"
          parts << "    <div class=\"book-description\">"
          parts << "      #{description_html}"
          parts << "    </div>"
          parts << "  </div>"
          parts.join("\n")
        end

        # フロントマターを生成
        def generate_frontmatter(file_type, chapter_num = nil, existing_frontmatter = {})
          # ファイルタイプに対応する基本スタイルシート
          theme_name = begin
            cfg = Common::CONFIG
            t = (cfg && cfg['theme'] && cfg['theme']['name']) || 'yellow'
            t = t.to_s.strip.downcase
            %w[yellow blue red green purple].include?(t) ? t : 'yellow'
          rescue
            'yellow'
          end

          # 扉画像の選択
          door_token = begin
            cfg = Common::CONFIG
            raw = (cfg && cfg['theme'] && cfg['theme']['door'])
            if raw.nil?
              'door2'
            else
              s = raw.to_s.strip.downcase
              if s =~ /^door([1-7])$/
                "door#{$1}"
              elsif s =~ /^[1-7]$/
                "door#{s}"
              else
                'door2'
              end
            end
          rescue
            'door2'
          end

          # テーマCSSを更新
          begin
            theme_css_path = File.join(Common::STYLESHEETS_DIR, 'theme.css')
            css = File.read(theme_css_path, encoding: 'utf-8')

            css = css.gsub(/(--theme-accent:\s*var\()(--accent-[^)]+)(\)\s*;)/) do
              pre, _old, post = $1, $2, $3
              "#{pre}--accent-#{theme_name}#{post}"
            end

            css = css.gsub(/(--section-bg-image:\s*url\(")[^"]+("\)\s*;)/) do
              pre, post = $1, $2
              "#{pre}images/frame-#{theme_name}.webp#{post}"
            end

            css = css.gsub(/(--chapter-door-image:\s*url\(")[^"]+("\)\s*;)/) do
              pre, post = $1, $2
              "#{pre}images/#{door_token}.webp#{post}"
            end

            File.write(theme_css_path, css, encoding: 'utf-8')
            Common.log_success("theme.css を更新: theme=#{theme_name}, door=#{door_token}")
          rescue => _e
            # 失敗しても前処理は継続
          end

          # appendix.css のアクセント色を設定
          begin
            appendix_choice = begin
              cfg = Common::CONFIG
              a = (cfg && cfg['theme'] && cfg['theme']['appendix_accent']) || 'blue'
              a = a.to_s.strip.downcase
              %w[neutral red blue].include?(a) ? a : 'blue'
            rescue
              'blue'
            end

            color_map = {
              'neutral' => '#111',
              'red'     => '#c62828',
              'blue'    => '#3da8c9'
            }
            hex = color_map[appendix_choice]

            appendix_css_path = File.join(Common::STYLESHEETS_DIR, 'appendix.css')
            if File.exist?(appendix_css_path)
              a_css = File.read(appendix_css_path, encoding: 'utf-8')
              replaced = a_css.sub(/(--appendix-accent-color:\s*)#[0-9a-fA-F]{3,8}(\s*;)/, "\\1#{hex}\\2")
              if replaced != a_css
                File.write(appendix_css_path, replaced, encoding: 'utf-8')
                Common.log_success("appendix.css を更新: appendix_accent=#{appendix_choice} (#{hex})")
              else
                Common.log_info('appendix.css に --appendix-accent-color の定義が見つかりません（置換なし）')
              end
            else
              Common.log_info("appendix.css が見つかりません: #{appendix_css_path}")
            end
          rescue => _e
            # 前処理続行
          end

          # page-settings.css の各種変数を反映
          begin
            cfg = Common::CONFIG
            page_cfg = (cfg && cfg['page']).is_a?(Hash) ? cfg['page'] : {}

            # 紙サイズ
            size_map = {
              'A4' => ['210mm', '297mm'],
              'B5' => ['182mm', '257mm'],
              'A5' => ['148mm', '210mm']
            }
            sz = page_cfg['size']
            if sz && sz.to_s.strip != ''
              key = sz.to_s.strip.upcase
              if size_map[key]
                page_cfg['width']  = page_cfg['width']  && page_cfg['width'].to_s.strip != '' ? page_cfg['width']  : size_map[key][0]
                page_cfg['height'] = page_cfg['height'] && page_cfg['height'].to_s.strip != '' ? page_cfg['height'] : size_map[key][1]
              end
            end

            # ノンブル配置
            placement = page_cfg['folio_placement'].to_s.strip.downcase
            placement = 'center' unless %w[center sides].include?(placement)
            case placement
            when 'center'
              page_cfg['folio_center'] = 'counter(page)'
              page_cfg['folio_left']   = 'none'
              page_cfg['folio_right']  = 'none'
            when 'sides'
              page_cfg['folio_center'] = 'none'
              page_cfg['folio_left']   = 'counter(page)'
              page_cfg['folio_right']  = 'counter(page)'
            end

            mappings = [
              ['--page-width',            page_cfg['width']],
              ['--page-height',           page_cfg['height']],
              ['--base-font-size',        page_cfg['base_font_size']],
              ['--base-line-height',      page_cfg['base_line_height']],
              ['--letters-per-line',      page_cfg['letters_per_line']],
              ['--lines-per-page',        page_cfg['lines_per_page']],
              ['--page-margin-top',       page_cfg['margin_top']],
              ['--page-margin-xshift',    page_cfg['margin_xshift']],
              ['--column-font-size',      page_cfg['column_font_size']],
              ['--main-text-font',        page_cfg['main_text_font'],  :font],
              ['--header-font',           page_cfg['header_font'],     :font],
              ['--code-font',             page_cfg['code_font'],       :font],
              ['--folio-font',            page_cfg['folio_font'],      :font],
              ['--folio-font-size',       page_cfg['folio_font_size']],
              ['--folio-color',           page_cfg['folio_color']],
              ['--folio-center-content',  page_cfg['folio_center']],
              ['--folio-left-content',    page_cfg['folio_left']],
              ['--folio-right-content',   page_cfg['folio_right']]
            ]

            candidates = []
            primary_new = File.join(Common::STYLESHEETS_DIR, 'page-settings.css')
            candidates << primary_new
            alt_new = File.join('awesomebook', 'stylesheets', 'page-settings.css')
            candidates << alt_new unless alt_new == primary_new

            candidates.uniq.each do |css_path|
              next unless File.exist?(css_path)
              css = File.read(css_path, encoding: 'utf-8')

              updated = css.dup
              mappings.each do |name, val, kind|
                next if val.nil? || val.to_s.strip.empty?
                v = val.to_s.strip
                if kind == :font
                  unless v.include?(',')
                    v = v =~ /^\s*".*"\s*$/ ? v : '"' + v + '"'
                  end
                end

                updated = updated.sub(/(#{Regexp.escape(name)}:\s*)[^;]+(\s*;)/) do
                  pre, post = $1, $2
                  "#{pre}#{v}#{post}"
                end
              end

              if updated != css
                File.write(css_path, updated, encoding: 'utf-8')
                Common.log_success("#{File.basename(css_path)} を更新: #{css_path}")
              else
                Common.log_info("#{File.basename(css_path)} に適用すべき差分はありません: #{css_path}")
              end
            end
          rescue => _e
            # 失敗しても続行
          end

          # フロントマターのCSS
          stylesheets = [
            'theme.css',
            "#{file_type}.css"
          ]

          # チャプター固有のCSSを追加
          if file_type == 'chapter' && chapter_num
            stylesheets << "#{chapter_num}.css"
          end

          # 新しいフロントマターのベースを作成
          new_frontmatter = {
            'link' => stylesheets.map { |css|
              { 'rel' => 'stylesheet', 'href' => "stylesheets/#{css}" }
            },
            'lang' => 'ja'
          }

          # 既存のフロントマターと新しいフロントマターを併合
          merged_frontmatter = {}

          merged_frontmatter = existing_frontmatter.dup
          if merged_frontmatter['link'].is_a?(Array)
            merged_frontmatter['link'] = merged_frontmatter['link'].reject do |lnk|
              href = (lnk && lnk['href']).to_s
              href.match(%r{stylesheets/(theme-(yellow|blue|red|accent)\.css|theme-overrides\.css)})
            end
          end

          new_frontmatter.each do |key, value|
            if key == 'link' && merged_frontmatter['link']
              existing_links = merged_frontmatter['link']
              new_links = value

              merged_frontmatter['link'] = existing_links + new_links.reject { |new_link|
                existing_links.any? { |existing_link|
                  existing_link['href'] == new_link['href']
                }
              }
            else
              merged_frontmatter[key] = value
            end
          end

          merged_frontmatter
        end

        # 画像パスを修正
        def fix_image_paths(content, filename)
          chapter_dir = filename.sub(/\.md$/, '')

          content.gsub(/!\[(.*?)\]\((?!https?:\/\/)([^)]+)\)/) do
            alt_text  = $1
            image_path = $2

            normalized = if image_path.start_with?('images/')
                           image_path
                         else
                           "images/#{chapter_dir}/#{image_path}"
                         end

            normalized = normalized.sub(/\.(png|jpe?g)\z/i, '.webp')

            "![#{alt_text}](#{normalized})"
          end
        end

        # ソースコード読み込み処理
        def process_code_include(content)
          matches_found = 0

          content.gsub!(/```include:([^:`\s]+)(?::(\d+)-(\d+))?\s*```/) do |match|
            matches_found += 1
            original_path = $1
            start_line = $2&.to_i
            end_line = $3&.to_i

            Common.log_action("マッチ発見: #{match.strip}")
            Common.log_info("元のパス: #{original_path}")

            file_path = if original_path.start_with?('/')
                          original_path
                        else
                          File.join(Common::CODES_DIR, original_path)
                        end
            Common.log_info("解決されたパス: #{file_path}")

            if File.exist?(file_path)
              source_content = File.read(file_path)
              lines = source_content.lines

              code_content = if start_line && end_line
                               selected_lines = lines[(start_line-1)..(end_line-1)]
                               selected_lines.join
                             else
                               source_content + "\n"
                             end

              language = detect_language(file_path)
              replacement = "```#{language}:#{original_path}\n#{code_content}```"
              Common.log_success("置換完了: #{original_path} (#{language})")

              replacement
            else
              Common.log_error("ファイルが見つかりません: #{file_path}")
              match
            end
          end

          Common.log_info("#{matches_found}個のinclude記法を処理") if matches_found > 0
          content
        end

        # 単一のMarkdownファイルを処理
        def process_single_markdown_file(md_file)
          filename = File.basename(md_file)
          output_file = filename

          Common.log_info("#{md_file} → #{output_file}")

          content = File.read(md_file, encoding: 'utf-8')

          file_type = Common.get_file_type(filename)
          chapter_num = Common.get_chapter_number(filename)

          # フロントマターを処理
          if content.start_with?('---')
            frontmatter_match = content.match(/\A---\n(.*?)\n---\n/m)

            if frontmatter_match
              frontmatter_yaml = frontmatter_match[1]
              begin
                existing_frontmatter = YAML.safe_load(frontmatter_yaml) || {}

                merged_frontmatter = generate_frontmatter(file_type, chapter_num, existing_frontmatter)

                new_frontmatter_yaml = YAML.dump(merged_frontmatter)
                Common.log_success("フロントマター併合")

                content = content.sub(/\A---\n.*?\n---\n/m, "#{new_frontmatter_yaml}---\n")

                Common.log_success("フロントマター更新")
              rescue => e
                line = (e.respond_to?(:line) && e.line) ? e.line.to_i : (e.message[/line (\d+)/i, 1]&.to_i)
                column = (e.respond_to?(:column) && e.column) ? e.column.to_i : (e.message[/column (\d+)/i, 1]&.to_i)

                if line && line > 0
                  Common.log_warn("フロントマター（--- ～ ---）の記述に誤りがあります（位置: 行#{line} 列#{column && column > 0 ? column : '?'}）。内容を見直してください。")
                else
                  Common.log_warn("フロントマター（--- ～ ---）の記述に誤りがあります。内容を見直してください。")
                end

                begin
                  fm_lines = frontmatter_yaml.to_s.lines
                  if line && line > 0 && line <= fm_lines.length
                    idx = line - 1
                    start = [idx - 2, 0].max
                    finish = [idx + 2, fm_lines.length - 1].min
                    snippet = fm_lines[start..finish].each_with_index.map { |l, i2| "#{start + i2 + 1}: #{l.chomp}" }.join("\n")
                    err_line_text = fm_lines[idx].to_s.chomp
                    caret_line = (column && column > 0) ? (" " * (column - 1) + "^") : ""
                    Common.log_info("問題のフロントマター（抜粋）:\n---\n#{snippet}\n---\n該当行:\n#{err_line_text}\n#{caret_line}")
                  else
                    Common.log_info("問題のフロントマター（抜粋）:\n---\n#{frontmatter_yaml}\n---")
                  end
                rescue => _ignore
                  Common.log_info("問題のフロントマター（抜粋）:\n---\n#{frontmatter_yaml}\n---")
                end
              end
            end
          else
            new_frontmatter = generate_frontmatter(file_type, chapter_num)
            new_frontmatter_yaml = YAML.dump(new_frontmatter)

            content = "#{new_frontmatter_yaml}---\n\n#{content}"
            Common.log_success("フロントマター追加")
          end

          # 画像パスを修正
          content = fix_image_paths(content, filename)
          Common.log_success("画像パスを修正しました: #{filename}")

          # ソースコードを取り込む
          Common.log_action("ソースコード読み込み記法をスキャンしています…")
          content = process_code_include(content)
          Common.log_success("ソースコード読み込み処理が完了しました")

          # .book-card マークダウンブロックをHTMLに変換
          Common.log_action("book-cardブロックをHTMLのdiv要素に変換しています…")
          in_book_card = false
          opened_count = 0
          closed_count = 0
          converted_lines = content.lines.map do |line|
            if line.match(/^\s*:::\{\.book-card\}\s*$/)
              in_book_card = true
              opened_count += 1
              "<div class=\"book-card\">\n"
            elsif in_book_card && line.match(/^\s*:::\s*$/)
              in_book_card = false
              closed_count += 1
              "</div>\n"
            else
              line
            end
          end
          content = converted_lines.join
          Common.log_success("book-cardブロックの事前変換が完了しました（開始:#{opened_count}件 終了:#{closed_count}件）")

          # book-card の内側MarkdownをHTMLへ変換
          Common.log_action("book-card内のMarkdownをHTMLへ変換しています…")
          content = convert_book_card_inner_markdown(content)
          Common.log_success("book-card内のMarkdownをHTMLへ変換しました")

          # .table-rotate マークダウンブロックをHTMLに変換
          Common.log_action("table-rotateブロックをHTMLのdiv要素に変換しています…")
          in_table_rotate = false
          tr_opened_count = 0
          tr_closed_count = 0
          tr_converted_lines = content.lines.map do |line|
            if line.match(/^\s*:::\{\.table-rotate\}\s*$/)
              in_table_rotate = true
              tr_opened_count += 1
              "<div class=\"table-rotate\">\n"
            elsif in_table_rotate && line.match(/^\s*:::\s*$/)
              in_table_rotate = false
              tr_closed_count += 1
              "</div>\n"
            else
              line
            end
          end
          content = tr_converted_lines.join
          Common.log_success("table-rotateブロックの事前変換が完了しました（開始:#{tr_opened_count}件 終了:#{tr_closed_count}件）")

          # table-rotate の内側MarkdownをHTMLへ変換
          Common.log_action("table-rotate内のMarkdownをHTMLへ変換しています…")
          content = convert_table_rotate_inner_markdown(content)
          Common.log_success("table-rotate内のMarkdownをHTMLへ変換しました")

          # リンク記法を脚注化
          Common.log_action("リンク記法を脚注化しています…")
          before = content.dup
          content = transform_links_to_footnotes(content)
          if content != before
            Common.log_success("リンクの脚注化を適用しました")
          else
            Common.log_info("脚注化の対象リンクはありません")
          end

          # 処理後のファイルを保存
          File.write(output_file, content, encoding: 'utf-8')
          Common.log_success("保存が完了しました")
        end
      end
    end
  end
end
