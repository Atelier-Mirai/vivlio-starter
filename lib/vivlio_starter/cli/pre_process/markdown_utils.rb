# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/pre_process/markdown_utils.rb
# ================================================================
# 責務:
#   Markdown 処理の共通ユーティリティを提供する。
#
# 機能:
#   - コードスパンの退避と復元
#   - 拡張子から言語名の推定
#   - 簡易 Markdown→HTML 変換
# ================================================================

require_relative '../masking'

module VivlioStarter
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

        # プレースホルダ書式は Masking と共有（唯一の定義元は Masking 側）。
        CODE_SPAN_PLACEHOLDER_PREFIX = Masking::CODE_SPAN_PLACEHOLDER_PREFIX

        module_function

        # コードスパン（フェンス／インライン）を一時的に退避し、その中身を
        # 後続のテキスト変形処理から除外する。実装は CLI::Masking へ一元化済み（P1）。
        # フェンス判定は状態機械で可変長・入れ子・~~~・include: 除外に追従する。
        def extract_code_spans(text) = Masking.protect_code(text.to_s)

        # extract_code_spans で退避したコードスパンを元に戻す（LIFO 復元）。
        def restore_code_spans(text, spans) = Masking.restore_code(text, spans)

        # インラインコード（`...`）内は、そのままの文字列を維持する
        def escape_inline_code_html(md_text)
          md_text.to_s
        end

        # 拡張子から言語名を推定
        def detect_language(file_path)
          ext = File.extname(file_path).downcase.delete_prefix('.')
          EXT_TO_LANG.fetch(ext, 'text')
        end

        # 段落内の改行を Kramdown の強制改行（行末スペース 2 つ）へ変換する。
        # 生 HTML 化経路（text-* コンテナ等）は VFM を通らずハード改行が失われるため、
        # Kramdown へ渡す前にこれを適用して VFM 本文と同じ「見たまま改行」を再現する。
        # 空行区切りの段落境界・リスト・表には作用しない（\S に挟まれた改行のみ対象）。
        def apply_hard_line_breaks(md_text) = md_text.to_s.gsub(/(?<=\S)\n(?=\S)/, "  \n")

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
      end
    end
  end
end
