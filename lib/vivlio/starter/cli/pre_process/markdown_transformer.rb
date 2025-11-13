# frozen_string_literal: true

require 'cgi'
require_relative '../common'

module Vivlio
  module Starter
    module CLI
      module PreProcessCommands
        # Markdown変換処理を担当するモジュール
        module MarkdownTransformer
          # 拡張子→言語の対応表
          EXT_TO_LANG = {
            'c' => 'c',
            'cc' => 'cpp',
            'cpp' => 'cpp',
            'cs' => 'csharp',
            'css' => 'css',
            'cxx' => 'cpp',
            'go' => 'go',
            'html' => 'html',
            'java' => 'java',
            'js' => 'javascript',
            'json' => 'json',
            'kt' => 'kotlin',
            'md' => 'markdown',
            'php' => 'php',
            'py' => 'python',
            'rb' => 'ruby',
            'rs' => 'rust',
            'scala' => 'scala',
            'scss' => 'scss',
            'sh' => 'bash',
            'sql' => 'sql',
            'swift' => 'swift',
            'ts' => 'typescript',
            'xml' => 'xml',
            'yaml' => 'yaml',
            'yml' => 'yaml'
          }.freeze

          module_function

          # 拡張子から言語名を推定
          def detect_language(file_path)
            ext = File.extname(file_path).downcase.delete_prefix('.')
            EXT_TO_LANG.fetch(ext, 'text')
          end

          # 簡易Markdown→HTML 変換
          def render_markdown_to_html(md_text)
            # まずはKramdownを試す
            require 'kramdown'
            Kramdown::Document.new(md_text).to_html
          rescue LoadError
            # フォールバック: 最小限のMarkdownをHTMLへ
            lines = md_text.to_s.split(/\r?\n/)
            html_parts = []
            in_ol = false
            buffer_p = []

            flush_p = lambda do
              unless buffer_p.empty?
                paragraph = buffer_p.join(' ').strip
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
              if (m = line.match(/^\s*!\[[^\]]*\]\(([^)]+)\)\s*$/))
                flush_p.call
                src = m[1]
                html_parts << "<img src=\"#{src}\">"
                next
              end

              # 見出し相当の太字行
              if (m = line.match(/^\s*\*\*(.+?)\*\*\s*$/))
                flush_p.call
                html_parts << "<p><strong>#{m[1]}</strong></p>"
                next
              end

              # 番号リスト
              if (m = line.match(/^\s*(\d+)\.\s+(.*)$/))
                flush_p.call
                html_parts << '<ol>' unless in_ol
                in_ol = true
                html_parts << "<li>#{m[2]}</li>"
                next
              elsif in_ol
                html_parts << '</ol>'
                in_ol = false
              end

              buffer_p << line
            end

            flush_p.call
            html_parts << '</ol>' if in_ol
            html_parts.join("\n")
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
            replaced = text.gsub(/(?<!!)\[(.+?)\]\((https?:[^\s)]+)\)(?!\[\^url\d+\])/) do |_match|
              label = ::Regexp.last_match(1)
              url   = ::Regexp.last_match(2)
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

            new_defs = url_id.map do |u, id|
              next nil if existing_defs.key?(id)

              "[^#{id}]: #{u}"
            end.compact

            return replaced if new_defs.empty?

            # 文末に空行2つを挟んで脚注定義を追記
            if replaced.strip.end_with?("\n")
              "#{replaced}\n#{new_defs.join("\n")}\n"
            else
              "#{replaced}\n\n#{new_defs.join("\n")}\n"
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
                out << '' if next_line && next_line.strip != ''
              # 太字のみの行の直後に空行を補う
              elsif line.match(/^\s*\*\*[^*].*\*\*\s*$/)
                out << '' if next_line && next_line.strip != ''
              end
            end
            out.join("\n")
          end

          # <div class="book-card"> ... </div> の内側MarkdownをHTMLへ
          def convert_book_card_inner_markdown(content)
            # 開始/終了タグの直後に改行が入っているテンプレ構造を前提に、内側をキャプチャ
            content.gsub(%r{<div class="book-card">\n(.*?)\n</div>}m) do
              inner = ::Regexp.last_match(1)
              normalized = normalize_book_card_md(inner)
              html = render_markdown_to_html(normalized)
              formatted = format_book_card_inner_html(html)
              "<div class=\"book-card\">\n#{formatted}\n</div>"
            end
          end

          # パイプテーブルを簡易HTML化
          def pipe_table_to_html(md_text)
            text = md_text.to_s.strip
            lines = text.split(/\r?\n/).map(&:rstrip)
            return nil if lines.size < 2

            header = lines[0]
            sep    = lines[1]
            return nil unless header.include?('|')
            return nil unless sep && sep =~ /^\s*\|?[\s:\-|]+\|?\s*$/

            rows = lines[2..] || []

            to_cells = lambda do |line|
              parts = line.split('|')
              parts.shift if parts.first&.strip == ''
              parts.pop   if parts.last&.strip  == ''
              parts.map(&:strip)
            end

            esc_code = lambda do |s|
              s.gsub(/`([^`]+)`/) { "<code>#{::Regexp.last_match(1)}</code>" }
               .gsub('&', '&amp;')
               .gsub('<', '&lt;')
               .gsub('>', '&gt;')
            end

            thead_cells = to_cells.call(header)
            tbody_rows  = rows.map { |r| to_cells.call(r) }

            html = []
            html << '<table>'
            html << '  <thead>'
            html << "    <tr>#{thead_cells.map { |c| "<th>#{esc_code.call(c)}</th>" }.join}</tr>"
            html << '  </thead>'
            if tbody_rows.any?
              html << '  <tbody>'
              tbody_rows.each do |cells|
                html << "    <tr>#{cells.map { |c| "<td>#{esc_code.call(c)}</td>" }.join}</tr>"
              end
              html << '  </tbody>'
            end
            html << '</table>'
            html.join("\n")
          end

          # <div class="table-rotate"> ... </div> の内側MarkdownをHTMLへ
          def convert_table_rotate_inner_markdown(content)
            content.gsub(%r{<div class="table-rotate">\s*(.*?)\s*</div>}m) do
              inner = ::Regexp.last_match(1)
              normalized = "\n\n#{inner.to_s.strip}\n\n"
              html = render_markdown_to_html(normalized).to_s.strip

              # フォールバック: パイプテーブルらしき記号がある場合
              if !html.include?('<table') && inner.include?('|')
                table_html = pipe_table_to_html(inner)
                html = table_html if table_html
              end

              "<div class=\"table-rotate\">\n#{html}\n</div>"
            end
          end

          # book-card の内側を整形
          def format_book_card_inner_html(inner_html)
            html = inner_html.to_s.strip

            # 1) 画像タグを抽出
            img_match = html.match(/<img[^>]*>/i)
            return inner_html unless img_match

            img_tag = img_match[0]
            img_tag = img_tag.gsub(%r{\s*/?>}i) { |_m| '>' }

            # 画像のみの<p>ラッパーを除去
            if html.sub!(%r{<p>\s*#{Regexp.escape(img_match[0])}\s*</p>}i, '')
              # removed wrapped <p> with img
            else
              html.sub!(img_match[0], '')
            end

            # 2) タイトルを抽出
            title_match = html.match(%r{<p>\s*<strong>(.*?)</strong>\s*</p>}im)
            return inner_html unless title_match

            title_text = title_match[1].strip
            html.sub!(title_match[0], '')

            # 3) 残りを説明HTMLとする
            description_html = html.strip

            # 4) 目標の構造で出力
            parts = []
            parts << "  #{img_tag}"
            parts << '  <div class="book-info">'
            parts << "    <p class=\"book-title\">#{title_text}</p>"
            parts << '    <div class="book-description">'
            parts << "      #{description_html}"
            parts << '    </div>'
            parts << '  </div>'
            parts.join("\n")
          end

          # ::: {.class} 記法で囲まれたコンテナを div に変換して件数を返す
          def convert_container_blocks(content, class_name:)
            opened_count = 0
            closed_count = 0
            in_block = false

            converted = content.lines.map do |line|
              if line.match(/^\s*:::\{\.(#{Regexp.escape(class_name)})\}\s*$/)
                in_block = true
                opened_count += 1
                "<div class=\"#{class_name}\">\n"
              elsif in_block && line.match(/^\s*:::\s*$/)
                in_block = false
                closed_count += 1
                "</div>\n"
              else
                line
              end
            end.join

            [converted, opened_count, closed_count]
          end

          # ```include:path[:start-end]``` を検出し、codes/ または絶対パスから読込
          def process_code_include(content)
            matches_found = 0

            content.gsub!(/```include:([^:`\s]+)(?::(\d+)-(\d+))?\s*```/) do |match|
              matches_found += 1
              original_path = ::Regexp.last_match(1)
              start_line = ::Regexp.last_match(2)&.to_i
              end_line = ::Regexp.last_match(3)&.to_i

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
                                 # 1-origin の範囲指定を Ruby の配列スライスに合わせて 0-origin に補正（end も含む）
                                 selected_lines = lines[(start_line - 1)..(end_line - 1)]
                                 selected_lines.join
                               else
                                 # 範囲未指定時はファイル全体を取り込み
                                 "#{source_content}\n"
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

            Common.log_info("#{matches_found}個のinclude記法を処理") if matches_found.positive?
            content
          end
        end
      end
    end
  end
end
