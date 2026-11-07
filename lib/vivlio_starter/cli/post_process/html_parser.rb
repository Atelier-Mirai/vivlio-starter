# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/post_process/html_parser.rb
# ================================================================
# 責務:
#   Nokogiri を使用した HTML の解析・生成を行う共通ユーティリティ。
#
# 提供機能:
#   - parse_html_document: HTML 文字列 → Nokogiri Document
#   - render_html_document: Nokogiri Document → HTML 文字列
#   - zero_width_text?: ゼロ幅文字のみかどうかを判定
#
# 解析には HTML5 パーサーを使う（Nokogiri 1.12 以降は CRuby で常に使える）。
# ================================================================

require 'nokogiri'

module VivlioStarter
  module CLI
    module PostProcessCommands
      # HTML 解析ユーティリティモジュール
      module HtmlParser
        module_function

        # Nokogiri を用いて HTML 文字列からドキュメントオブジェクトを生成する
        def parse_html_document(html)
          Nokogiri::HTML5.parse(html)
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
