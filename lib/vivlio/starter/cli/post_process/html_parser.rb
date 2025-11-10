# frozen_string_literal: true

require 'nokogiri'

module Vivlio
  module Starter
    module CLI
      module PostProcessCommands
        # HTML解析処理を担当するモジュール
        module HtmlParser
          module_function

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

          # ゼロ幅スペース等のみで構成されているかを判定する
          def zero_width_text?(text)
            text.gsub(/[\u200B\u200C\u200D\u2060\uFEFF\u180E]/, '').strip.empty?
          end
        end
      end
    end
  end
end
