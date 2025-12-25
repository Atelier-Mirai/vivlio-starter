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

        PRISM_LINES_DESC = {
          short: 'HTMLファイル内のPrism.jsコードブロックに行番号を追加します',
          long: <<~DESC
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
        }.freeze

        def included(base); end

        # Samovar/直接呼び出し用エントリポイント
        def execute_prism_lines(input_file, output_file = nil)
          output_file ||= input_file

          unless File.exist?(input_file)
            Common.log_error("エラー: 入力ファイル '#{input_file}' が存在しません")
            return
          end

          add_prism_line_numbers(input_file, output_file)
        end
        # コードの行数を返す
        def line_count(pre)
          pre.text.count("\n") + 1
        end

        # Prism.jsの行番号を追加する処理
        def add_prism_line_numbers(input_file, output_file = nil)
          document = parse_html(input_file)
          document.css('pre').each { |pre| decorate_pre_tag(pre, document) }
          remove_legacy_meta(document)

          target = output_file || input_file
          File.write(target, document.to_html(encoding: 'UTF-8'))
          log_result(input_file, target)
        end

        # HTMLファイルを Nokogiri ドキュメントに変換
        def parse_html(path)
          html = File.read(path, encoding: 'UTF-8')
          if defined?(Nokogiri::HTML5)
            Nokogiri::HTML5.parse(html)
          else
            Nokogiri::HTML.parse(html, nil, 'UTF-8')
          end
        end

        # <pre> 要素と内包する <code> に行番号用クラスと要素を付与
        def decorate_pre_tag(pre, document)
          pre[:class] = combine_class(pre[:class], 'line-numbers')
          code = pre.at_css('code')
          return unless code

          code[:class] = combine_class(code[:class], 'line-numbers')
          code.add_child(build_line_numbers_span(document, line_count(pre)))
        end

        # 行数分の <span> line-numbers-rows 構造を生成
        def build_line_numbers_span(document, lines)
          span = Nokogiri::XML::Node.new('span', document)
          span['aria-hidden'] = 'true'
          span['class'] = 'line-numbers-rows'

          lines.times do
            span.add_child(Nokogiri::XML::Node.new('span', document))
          end

          span
        end

        # 不要な Content-Type メタタグを除去
        def remove_legacy_meta(document)
          document.css('meta[http-equiv="Content-Type"]').each(&:remove)
        end

        # 既存クラス文字列に安全にクラスを追加
        def combine_class(original, addition)
          classes = [original, addition].compact.reject(&:empty?)
          classes.join(' ')
        end

        # 処理完了メッセージを出力
        def log_result(input_file, output_file)
          suffix = input_file == output_file ? '' : " -> #{output_file}"
          Common.log_success("行番号付与完了: #{input_file}#{suffix}")
        end
      end
    end
  end
end
