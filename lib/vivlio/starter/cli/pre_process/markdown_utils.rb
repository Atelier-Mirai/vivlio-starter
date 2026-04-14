# frozen_string_literal: true

# ================================================================
# File: lib/vivlio/starter/cli/pre_process/markdown_utils.rb
# ================================================================
# 責務:
#   Markdown 処理の共通ユーティリティを提供する。
#
# 機能:
#   - コードスパンの退避と復元
#   - 拡張子から言語名の推定
#   - 簡易 Markdown→HTML 変換
#   - パイプテーブルの HTML 変換
# ================================================================

module Vivlio
  module Starter
    module CLI
      module PreProcessCommands
        # Markdown 処理の共通ユーティリティ
        module MarkdownUtils
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

          CODE_SPAN_PLACEHOLDER_PREFIX = '__VS_CODE_SPAN__'

          module_function

          # コードスパン（バッククォートで囲まれた部分）を一時的に退避し、
          # その中身を後続のテキスト変形処理から除外するためのユーティリティ。
          # コードフェンス（```...```）も退避対象とする。
          def extract_code_spans(text)
            spans = {}
            counter = 0

            # まずコードフェンスブロック全体を退避（インラインコードより先に処理）
            protected_text = text.to_s.gsub(/^(`{3,}|~{3,}).*?^\1\s*$/m) do |match|
              key = "#{CODE_SPAN_PLACEHOLDER_PREFIX}#{counter}__"
              spans[key] = match
              counter += 1
              key
            end

            # 次にインラインコードスパンを退避
            protected_text = protected_text.gsub(/`([^`]*?)`/) do |match|
              key = "#{CODE_SPAN_PLACEHOLDER_PREFIX}#{counter}__"
              spans[key] = match
              counter += 1
              key
            end

            [protected_text, spans]
          end

          # extract_code_spans で退避したコードスパンを元に戻す
          def restore_code_spans(text, spans)
            restored = text.to_s
            # gsub の置換文字列として解釈されないよう Regexp.last_match を使う
            spans.each do |placeholder, original|
              restored = restored.gsub(placeholder) { original }
            end
            restored
          end

          # インラインコード（`...`）内は、そのままの文字列を維持する
          def escape_inline_code_html(md_text)
            md_text.to_s
          end

          # 拡張子から言語名を推定
          def detect_language(file_path)
            ext = File.extname(file_path).downcase.delete_prefix('.')
            EXT_TO_LANG.fetch(ext, 'text')
          end

          # 簡易Markdown→HTML 変換
          def render_markdown_to_html(md_text)
            # まずはKramdownを試す
            require 'kramdown'
            Kramdown::Document.new(md_text, syntax_highlighter: nil).to_html
          rescue LoadError
            # フォールバック: 最小限のMarkdownをHTMLへ
            render_markdown_fallback(md_text)
          end

          # Kramdown が使えない場合のフォールバック実装
          def render_markdown_fallback(md_text)
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
        end
      end
    end
  end
end
