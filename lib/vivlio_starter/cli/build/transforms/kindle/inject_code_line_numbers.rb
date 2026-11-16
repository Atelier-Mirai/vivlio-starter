# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/build/transforms/kindle/inject_code_line_numbers.rb
# ================================================================
# 責務:
#   コードの行番号を、実体の字で入れる
# ================================================================

require_relative '../context'
require_relative '../../../post_process/html_parser'

module VivlioStarter
  module CLI
    module Build
      # コードの行番号を、実体の字で入れる
      module Transforms::Kindle::InjectCodeLineNumbers
        module_function

        # Kindle のコード行番号の桁数（実テキスト注入・nbsp で右詰め）。
        # 3 桁あれば実用上足り、番号 3 桁＋区切り 1 文字が CSS の番号欄幅（2.4em）と
        # 対応する。ブロックごとの最大桁に合わせると折返しのぶら下げ位置がブロック
        # ごとにずれるため、固定にしている（pdf-code-line-numbers-spec.md §3.3）。
        CODE_LINE_NUMBER_DIGITS = 3

        # Kindle 向けに各コード行の先頭へ実テキストの行番号 span を注入する（F 案 §2.2）。
        # KFX は ::before と var() を解さないため、vs-adm-label と同じ実体注入パターンで
        # 番号を持たせる。番号は nbsp で最大桁数へ右詰めパディングし、等幅フォントで桁を
        # 揃える（CSS の幅指定に依存せず、nbsp＋数字には分割機会が無いため縦折返しも起きない）。
        # クリーン EPUB はこのフェーズを通らないため span は混入しない。
        #
        # @param html_files [Array<String>] HTML ファイルパスの配列
        # @return [Array<String>] そのままの配列（パス変更なし）
        def call(html_files, _ctx)
          html_files.each do |path|
            html = File.read(path, encoding: 'utf-8')
            doc = PostProcessCommands::HtmlParser.parse_html_document(html)

            changed = false
            doc.css('div.vs-code-epub').each do |container|
              lines = container.css('> div.vs-code-line')
              next if lines.empty?

              start = (container['data-start'] || 1).to_i
              lines.each_with_index do |line, idx|
                next if line.at_css('.vs-code-ln') # 二重注入を防ぐ（冪等）

                span = Nokogiri::XML::Node.new('span', doc)
                span['class'] = 'vs-code-ln'
                # \u756A\u53F7\u306F 3 \u6841\u56FA\u5B9A\u3067\u53F3\u8A70\u3081\uFF08\uFF0B\u533A\u5207\u308A 1 \u6587\u5B57 \uFF1D \u8A08 4 \u6587\u5B57\uFF09\u3002\u7B49\u5E45\u306A\u3089\u3053\u308C\u304C
                # CSS \u306E padding-left\uFF082.4em\uFF09\u3068\u307B\u307C\u4E00\u81F4\u3057\u3001\u6298\u8FD4\u3057\u884C\u304C 1 \u884C\u76EE\u306E\u672C\u6587\u958B\u59CB
                # \u4F4D\u7F6E\u3078\u63C3\u3046\u3002\u30D6\u30ED\u30C3\u30AF\u3054\u3068\u306B\u6841\u6570\u3092\u5909\u3048\u308B\u3068\u3001\u3053\u306E\u5BFE\u5FDC\u304C\u30D6\u30ED\u30C3\u30AF\u3054\u3068\u306B\u305A\u308C\u308B\u3002
                # Kindle \u306F ::before \u3092\u89E3\u3055\u305A\u5B9F\u30C6\u30AD\u30B9\u30C8\u3067\u756A\u53F7\u3092\u51FA\u3059\u305F\u3081\u3001\u5E45\u306F CSS \u3067\u306F\u306A\u304F
                # \u6587\u5B57\u6570\u3067\u5408\u308F\u305B\u308B\u3057\u304B\u306A\u3044\uFF08PDF\u30FB\u30AF\u30EA\u30FC\u30F3 EPUB \u304C\u5E38\u306B 2.4em \u306E\u756A\u53F7\u6B04\u3092
                # \u78BA\u4FDD\u3059\u308B\u306E\u3068\u3082\u63C3\u3046\uFF09\u3002
                span.content = "#{(start + idx).to_s.rjust(CODE_LINE_NUMBER_DIGITS,"\u00A0")} "
                line.prepend_child(span)
                changed = true
              end
            end
            next unless changed

            PostProcessCommands::HtmlParser.save_html_document(path, doc)
            Common.log_info("[EPUB] #{File.basename(path)} のコード行番号を注入しました")
          end
          html_files
        end
      end
    end
  end
end
