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

              Common.log_action('対象ファイル:')
              files.each { |f| Common.log_info("  - #{Pathname.new(f).relative_path_from(base_dir_path)}") }

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

                # Appendices ID prefix to avoid duplicates across merged file
                # Determine prefix by leading number in filename: 91 -> appendix-a, 92 -> appendix-b, ...
                base = File.basename(file)
                leading = base[/^(\d{2})-/, 1]
                prefix = case leading
                         when '91' then 'appendix-a'
                         when '92' then 'appendix-b'
                         when '93' then 'appendix-c'
                         when '94' then 'appendix-d'
                         when '95' then 'appendix-e'
                         when '96' then 'appendix-f'
                         when '97' then 'appendix-g'
                         else 'appendix-x'
                         end

                # Rewrite id="..." to id="<prefix>-..."
                rewritten = body_inner.gsub(/\bid=("|')(.*?)(\1)/) do |_m|
                  q = Regexp.last_match(1)
                  id = Regexp.last_match(2)
                  %(id=#{q}#{prefix}-#{id}#{q})
                end

                # Rewrite href="#..." (fragment links) accordingly
                rewritten = rewritten.gsub(/\bhref=("|')#(.*?)(\1)/) do |_m|
                  q = Regexp.last_match(1)
                  frag = Regexp.last_match(2)
                  %(href=#{q}##{prefix}-#{frag}#{q})
                end

                rewritten.strip
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

              Common.log_success("出力しました: #{out_pathname}")
            end

            desc 'merge:html OUT FILES...', '複数のHTMLを結合して単一HTMLに出力する'
            long_desc <<~DESC
              指定した複数の HTML ファイルを 1 つの HTML に結合します。

              仕様:
                - 先頭ファイルの <head> を採用し、それ以外のファイルは <body> 内部を順に連結します。
                - <head> が見つからない場合は最小限の <head> を生成します。

              使用例:
                vs merge:html 00-01-front.html 00-titlepage.html 01-legalpage.html
            DESC

            # ================================================================
            # Command: merge:html（任意のHTMLを結合）
            # ------------------------------------------------
            # 概要:
            #   引数で与えた FILES... を順に結合し、OUT に単一HTMLとして書き出す。
            # 引数:
            #   out    出力先HTMLパス
            #   files  入力HTMLの列（2つ以上推奨）
            # ================================================================
            def merge_html(out, *files)
              ENV['VERBOSE'] = '1' if options[:verbose]

              if out.nil? || out.to_s.strip.empty?
                Common.log_error('❌ 出力ファイル(OUT)を指定してください')
                exit(1)
              end
              if files.nil? || files.empty?
                Common.log_error('❌ 入力HTML(FILES...)を1つ以上指定してください')
                exit(1)
              end

              files = files.flatten.compact.map(&:to_s)
              missing = files.reject { |f| File.exist?(f) }
              unless missing.empty?
                Common.log_error("❌ 入力ファイルが見つかりません: #{missing.join(', ')}")
                exit(1)
              end

              read_text = ->(path) { File.read(path, encoding: 'UTF-8') }
              extract = ->(html, tag) do
                m = html.match(/<#{tag}\b[^>]*>(.*?)<\/#{tag}>/im)
                m ? m[1] : nil
              end

              # 先頭ファイルから lang/title を取得
              first_html = read_text.call(files.first)
              html_lang = first_html[/<html\b[^>]*\blang=("|')(.*?)(\1)/im, 2]
              title = first_html[/<title>(.*?)<\/title>/im, 1] || 'Merged'

              # すべての head から stylesheet を集約（重複除去、出現順維持）
              stylesheet_hrefs = []
              files.each do |f|
                h = extract.call(read_text.call(f), 'head') || ''
                h.scan(/<link\b[^>]*rel=("|')stylesheet\1[^>]*href=("|')(.*?)(\2)[^>]*>/im) do
                  href = Regexp.last_match(3)
                  stylesheet_hrefs << href unless stylesheet_hrefs.include?(href)
                end
              end

              # body クラスを集約（ユニーク化、順序保存）
              body_classes = []
              files.each do |f|
                html = read_text.call(f)
                if (m = html.match(/<body\b[^>]*class=("|')(.*?)(\1)/im))
                  m[2].split(/\s+/).each do |cls|
                    next if cls.nil? || cls.strip.empty?
                    body_classes << cls unless body_classes.include?(cls)
                  end
                end
              end
              body_class_attr = body_classes.any? ? %( class="#{body_classes.join(' ')}") : ''

              # 各 body の中身を連結
              sections = files.map do |file|
                html = read_text.call(file)
                extract.call(html, 'body') || html
              end.join("\n\n")

              # 正規化した head を構築
              head_lines = []
              head_lines << '<meta charset="utf-8" />'
              head_lines << '<meta name="viewport" content="width=device-width, initial-scale=1" />'
              head_lines << "<title>#{title}</title>"
              stylesheet_hrefs.each do |href|
                head_lines << %(<link rel="stylesheet" href="#{href}">)
              end
              head_html = "<head>\n  #{head_lines.join("\n  ")}\n</head>"

              # 最終 HTML
              html_open = html_lang && !html_lang.strip.empty? ? %(<html lang="#{html_lang}">) : '<html>'
              final_html = <<~HTML
              <!DOCTYPE html>
              #{html_open}
              #{head_html}
              <body#{body_class_attr}>
              #{sections}
              </body>
              </html>
              HTML

              File.write(out, final_html, mode: 'w', encoding: 'UTF-8')
              Common.log_success("出力しました: #{out}")
            end
          end
        end
      end
    end
  end
end
