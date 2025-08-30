# frozen_string_literal: true

require 'nokogiri'

module Vivlio
  module Starter
    module CLI
      # ==============================================================================
      # Module: PrismLinesCommands
      # ------------------------------------------------------------------------------
      # Prism.js のコードブロック（<pre><code>）に行番号を付与するコマンド群。
      # 入力HTMLを解析し、必要なクラスと line-numbers-rows を自動追加して保存する。
      #
      # 提供コマンド:
      #   - prism:lines INPUT_FILE [OUTPUT_FILE]
      #     入力HTML内の Prism.js コードブロックに行番号を追加する。
      #
      # 備考:
      #   - -v/--verbose で詳細ログを表示（ENV には反映しません）。
      #   - OUTPUT_FILE を省略した場合、INPUT_FILE を上書きします。
      # ==============================================================================
      module PrismLinesCommands
        extend self
        def included(base)
          base.class_eval do
            desc 'prism:lines INPUT_FILE [OUTPUT_FILE]', 'HTMLファイル内のPrism.jsコードブロックに行番号を追加します'
            long_desc <<~DESC
              指定したHTMLファイル内のPrism.jsコードブロックに行番号を追加します。

              引数:
                INPUT_FILE     入力HTMLファイル（必須）
                OUTPUT_FILE    出力HTMLファイル（省略可、省略時は入力ファイルを上書き）

              オプション:
                -v, --verbose  詳細な処理情報を表示

              使用例:
                vs prism:lines prime.html
                vs prism:lines prime.html prime_with_lines.html
            DESC

            # ================================================================
            # Command: prism:lines（行番号の付与）
            # ------------------------------------------------
            # 概要:
            #   入力HTMLの <pre><code> に Prism.js の行番号用クラス/要素を追加し、
            #   出力HTMLとして書き出す。OUTPUT_FILE 未指定時は入力を上書き。
            # 引数:
            #   input_file     入力HTML（必須）
            #   output_file    出力HTML（省略可）
            # オプション:
            #   -v, --verbose  詳細ログを表示
            # ================================================================
            def prism_lines(input_file, output_file = nil)
              output_file ||= input_file
              verbose = options[:verbose]

              unless File.exist?(input_file)
                Common.log_error("エラー: 入力ファイル '#{input_file}' が存在しません")
                exit(1)
              end

              add_prism_line_numbers(input_file, output_file, verbose)
            end

            
          end
        end

        private

        # コードの行数を返す
        def line_count(pre)
          pre.text.count("\n") + 1
        end

        # Prism.jsの行番号を追加する処理
        def add_prism_line_numbers(input_file, output_file = nil, verbose = false)
          output_file = input_file if output_file.nil?

          # HTMLを読み込む
          html = File.read(input_file, encoding: 'UTF-8')
          # HTML5パーサが使える場合は優先
          if defined?(Nokogiri::HTML5)
            doc = Nokogiri::HTML5.parse(html)
          else
            doc = Nokogiri::HTML.parse(html, nil, 'UTF-8')
          end

          # <pre>要素を取得
          pre_tags = doc.css("pre")

          pre_tags.each_with_index do |pre, index|
            # クラスを追加
            original_class = pre[:class] || ""
            pre[:class] = "#{original_class} line-numbers".strip

            code = pre.css("code").first
            if code
              original_code_class = code[:class] || ""
              code[:class] = "#{original_code_class} line-numbers".strip

              # 行番号の為の <span>要素を作成
              span = Nokogiri::XML::Node.new("span", doc)
              span["aria-hidden"] = "true"
              span["class"] = "line-numbers-rows"

              # <span></span>要素を、コードの行数分追加する
              line_count(pre).times do
                span_line = Nokogiri::XML::Node.new('span', doc)
                span.add_child(span_line)
              end

              # <code>要素の末尾に追加する
              code.add_child(span)
            end
          end

          # ファイルに出力
          # 不要な Content-Type の meta タグを除去（charset指定は <meta charset> を優先）
          doc.css('meta[http-equiv="Content-Type"]').each do |meta|
            meta.remove
          end
          File.write(output_file, doc.to_html(encoding: 'UTF-8'))
          Common.log_success("行番号付与完了: #{input_file}" + (output_file != input_file ? " -> #{output_file}" : ""))
        end
      end
    end
  end
end
