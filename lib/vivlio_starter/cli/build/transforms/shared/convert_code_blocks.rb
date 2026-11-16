# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/build/transforms/shared/convert_code_blocks.rb
# ================================================================
# 責務:
#   行番号付きのコードを「1 論理行 = 1 ブロック」へ変換する
# ================================================================

require_relative '../context'
require_relative '../../../code_line_blocks'

module VivlioStarter
  module CLI
    module Build
      # 行番号付きのコードを「1 論理行 = 1 ブロック」へ変換する
      module Transforms::Shared::ConvertCodeBlocks
        module_function

        # Prism の行番号付きコードブロックを、リフローで崩れない行ブロック構造へ変換する
        # （F 案・epub-code-line-numbers-spec §1）。1 論理行 = 1 ブロック要素とし、折返しは
        # ぶら下げインデント（code.css）で番号の右＝コード開始位置へ揃える。行番号はクリーン
        # EPUB では CSS カウンタ（::before）、Kindle では Transforms::Kindle::InjectCodeLineNumbers
        # の実テキスト注入が担うため、ここでは番号を持たない構造だけを作る（両フレーバ共通）。
        #
        # @param doc [Nokogiri::HTML5::Document] 1 ページの HTML（破壊的に書き換える）
        # @param ctx [Transforms::Context]
        def call(doc, ctx)
          targets = doc.css('pre.line-numbers')
          return if targets.empty?

          changed = false
          targets.each { |pre| changed |= convert_code_pre_to_lines!(pre, doc) }
          Common.log_info("[EPUB] #{ctx.page_name} のコードを行ブロック化しました") if changed
        end

        # 1 つの pre.line-numbers を div.vs-code-epub（行ブロック容器）へ置換する。失敗時は変更せず false。
        def convert_code_pre_to_lines!(pre, doc)
          code = pre.at_css('code')
          return false unless code

          # 絶対配置ガター（.line-numbers-rows）は不要なので取り除く
          code.css('.line-numbers-rows').each(&:remove)

          lines = split_code_into_lines(code)
          return false if lines.empty?

          language_class = code['class'].to_s.split.find { it.start_with?('language-') }

          container = build_code_lines(doc, lines, language_class)
          # 範囲 include の開始行番号（code-include-line-number-spec）を容器へ引き継ぐ。
          # クリーン EPUB はインライン counter-reset がカウンタ開始値として消費し、
          # Kindle は注入時に data-start を採番開始値として消費する。
          if (start = pre['data-start']&.to_i) && start >= 1
            container['data-start'] = start.to_s
            container['style'] = "counter-reset: vs-code-ln #{start - 1}"
          end
          pre.replace(container)
          true
        rescue StandardError => e
          Common.log_warn("[EPUB] コードの行ブロック化に失敗（元のまま維持）: #{e.message}")
          false
        end

        # <code> の中身を論理行（\n 区切り）へ分割する。各行は Prism のトークン span を
        # 保持した HTML 断片。複数行に跨るトークンは行ごとに閉じ／開き直す（行スプリットの定石）。
        # 実装は CodeLineBlocks が正典で、PDF 側の行ブロック化と同じ意味論を共有する。
        #
        # @return [Array<String>] 各論理行の内部 HTML（末尾の空行は捨てる）
        def split_code_into_lines(code) = CodeLineBlocks.split(code)

        # 行配列から div.vs-code-epub（1 論理行 = 1 div.vs-code-line）を構築する。
        # language-* クラスは容器と各行 <code> の両方に付け、Prism トークン色 CSS と
        # 既存の [class*="language-"] 系セレクタの適用を保つ。
        def build_code_lines(doc, lines, language_class)
          container = Nokogiri::XML::Node.new('div', doc)
          container['class'] = ['vs-code-epub', language_class].compact.join(' ')

          lines.each do |line_html|
            line = Nokogiri::XML::Node.new('div', doc)
            line['class'] = 'vs-code-line'
            code = Nokogiri::XML::Node.new('code', doc)
            code['class'] = language_class if language_class
            # 空行は &nbsp; で 1 行ぶんの高さを保ち、行高を揃える（空ブロックの潰れ防止）。
            code.inner_html = line_html.strip.empty? ? "\u00A0" : line_html
            line.add_child(code)
            container.add_child(line)
          end
          container
        end
      end
    end
  end
end
