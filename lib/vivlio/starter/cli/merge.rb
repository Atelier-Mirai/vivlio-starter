# frozen_string_literal: true

require 'pathname'

module Vivlio
  module Starter
    module CLI
      # ==============================================================================
      # Module: MergeCommands
      # ------------------------------------------------------------------------------
      # 付録HTMLの結合など、複数ファイルを単一ファイルにまとめるためのコマンド群。
      #
      # 提供コマンド:
      #   - merge:appendices [DIR] [OUT]
      #       91-*.html〜97-*.html を 1 つの HTML に結合し出力する。
      #
      # 備考:
      #   - 既定の出力は DIR/90-appendices.html。
      #   - -v/--verbose 指定で ENV['VERBOSE']=1 を設定。
      # ==============================================================================
      # Thor コマンド群: merge（ファイル結合）
      module MergeCommands
        extend self
        def included(base)
          base.class_eval do
            desc 'merge:appendices [DIR] [OUT]', '付録HTML(91-*.html〜97-*.html)を単一HTMLに結合して出力する'
            long_desc <<~DESC
              付録HTMLファイルを単一のHTMLファイルに結合します。

              対象ファイル: 91-*.html 〜 97-*.html
              出力ファイル: 90-appendices.html（既定）

              引数:
                DIR    入力ディレクトリ（省略時はカレントディレクトリ）
                OUT    出力ファイルパス（省略時はDIR/90-appendices.html）

              使用例:
                vs merge:appendices
                vs merge:appendices . output.html
            DESC

            # ================================================================
            # Command: merge:appendices（付録HTMLを結合）
            # ------------------------------------------------
            # 概要:
            #   指定ディレクトリの 91-*.html〜97-*.html を収集し、
            #   <head> と <body> を適切に構成した単一 HTML に結合して出力する。
            #
            # 引数:
            #   dir    入力ディレクトリ（省略時 '.'）
            #   out    出力ファイルパス（省略時 DIR/90-appendices.html）
            #
            # 備考:
            #   - 入力が見つからない場合はエラー終了。
            #   - 先頭ファイルの <head> をベースに採用。
            # ================================================================
            def merge_appendices(dir = '.', out = nil)
              ENV['VERBOSE'] = '1' if options[:verbose]
              # Commonモジュールをロード（rakelib依存を解消）

              base_dir = '.'
              dir_path = dir || base_dir
              out_path = out || File.join(dir_path, '90-appendices.html')

              root = Pathname.new(dir_path)
              base_dir_path = root.expand_path
              unless root.directory?
                Common.log_error("❌ 入力ディレクトリが見つかりません: #{root}")
                exit(1)
              end

              # グロブで 91〜97 の章HTMLを抽出
              patterns = %w[91-*.html 92-*.html 93-*.html 94-*.html 95-*.html 96-*.html 97-*.html]
              files = patterns.flat_map { |p| Dir[base_dir_path.join(p).to_s] }
              files.sort!

              if files.empty?
                Common.log_error('❌ 対象ファイル(91-*.html〜97-*.html)が見つかりません')
                exit(1)
              end

              puts '📝 対象ファイル:'
              files.each { |f| puts "  - #{Pathname.new(f).relative_path_from(base_dir_path)}" }

              read_text = ->(path) { File.read(path, encoding: 'UTF-8') }
              extract = ->(html, tag) do
                m = html.match(/<#{tag}\b[^>]*>(.*?)<\/#{tag}>/im)
                m ? m[1] : nil
              end

              first_html = read_text.call(files.first)
              head_inner = extract.call(first_html, 'head')
              head_html = if head_inner && !head_inner.strip.empty?
                "<head>\n#{head_inner}\n</head>"
              else
                <<~HEAD
                <head>
                  <meta charset="utf-8" />
                  <meta name="viewport" content="width=device-width, initial-scale=1" />
                  <title>Appendices</title>
                </head>
                HEAD
              end

              sections = files.map do |file|
                html = read_text.call(file)
                body_inner = extract.call(html, 'body') || html
                body_inner.strip
              end.join("\n\n")

              final_html = <<~HTML
              <!doctype html>
              <html>
              #{head_html}
              <body class="appendix">
              #{sections}
              </body>
              </html>
              HTML

              out_pathname = Pathname.new(out_path)
              File.write(out_pathname, final_html, mode: 'w', encoding: 'UTF-8')

              puts "✅ 出力しました: #{out_pathname}"
            end
          end
        end
      end
    end
  end
end
