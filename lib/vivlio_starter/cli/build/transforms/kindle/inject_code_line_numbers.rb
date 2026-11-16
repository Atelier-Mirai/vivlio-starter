# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/build/transforms/kindle/inject_code_line_numbers.rb
# ================================================================
# 責務:
#   コードの行番号を、実体の字で入れる
# ================================================================

require_relative '../context'

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
        # @param doc [Nokogiri::HTML5::Document] 1 ページの HTML（破壊的に書き換える）
        # @param ctx [Transforms::Context]
        def call(doc, ctx)
          changed = false
          doc.css('div.vs-code-epub').each do |container|
            lines = container.css('> div.vs-code-line')
            next if lines.empty?

            start = (container['data-start'] || 1).to_i
            lines.each_with_index do |line, idx|
              next if line.at_css('.vs-code-ln') # 二重注入を防ぐ（冪等）

              span = Nokogiri::XML::Node.new('span', doc)
              span['class'] = 'vs-code-ln'
              # 番号は 3 桁固定で右詰め（＋区切り 1 文字 ＝ 計 4 文字）。等幅ならこれが
              # CSS の padding-left（2.4em）とほぼ一致し、折返し行が 1 行目の本文開始
              # 位置へ揃う。ブロックごとに桁数を変えると、この対応がブロックごとにずれる。
              # Kindle は ::before を解さず実テキストで番号を出すため、幅は CSS ではなく
              # 文字数で合わせるしかない（PDF・クリーン EPUB が常に 2.4em の番号欄を
              # 確保するのとも揃う）。
              span.content = "#{(start + idx).to_s.rjust(CODE_LINE_NUMBER_DIGITS, " ")} "
              line.prepend_child(span)
              changed = true
            end
          end
          Common.log_info("[EPUB] #{ctx.page_name} のコード行番号を注入しました") if changed
        end
      end
    end
  end
end
