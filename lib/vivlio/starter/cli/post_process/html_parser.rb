# frozen_string_literal: true

# ================================================================
# File: lib/vivlio/starter/cli/post_process/html_parser.rb
# ================================================================
# 責務:
#   Nokogiri を使用した HTML の解析・生成を行う共通ユーティリティ。
#
# 提供機能:
#   - parse_html_document: HTML 文字列 → Nokogiri Document
#   - render_html_document: Nokogiri Document → HTML 文字列
#   - zero_width_text?: ゼロ幅文字のみかどうかを判定
#
# 互換性:
#   - Nokogiri::HTML5 が利用可能なら HTML5 パーサーを使用
#   - 利用不可なら従来の HTML パーサーにフォールバック
# ================================================================

require 'nokogiri'

module Vivlio
  module Starter
    module CLI
      module PostProcessCommands
        # HTML 解析ユーティリティモジュール
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
            doc.respond_to?(:to_html) ? doc.to_html(encoding: 'UTF-8') : doc.to_s
          end

          # HTMLドキュメントをファイルに保存
          def save_html_document(path, doc)
            File.write(path, render_html_document(doc), encoding: 'utf-8')
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
