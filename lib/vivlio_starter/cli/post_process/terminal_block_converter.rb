# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/post_process/terminal_block_converter.rb
# ================================================================
# 責務:
#   前処理が :::{.terminal} を書き換えたチルダフェンス（~~~vs-terminal）の
#   VFM 出力を、本来の端末枠 <div class="terminal"><pre>…</pre></div> へ戻す。
#
# なぜ div で包むのか:
#   EpubBuilder::ADMONITION_LABELS の Kindle 用ラベル注入が doc.css("div.terminal")
#   に依存し、かつ <p class="vs-adm-label"> を <pre> の内側には置けない。div で
#   包めばラベルは <pre> の兄弟として先頭に入り、既存の Kindle 経路がそのまま生きる。
#
# なぜ language-* クラスを消すのか:
#   stylesheets/code.css の pre[class*="language-"] に巻き込まれ、
#   コードブロックの白地・枠線が端末枠の中に二重で描かれるため。
#
# 仕様: docs/specs/terminal-literal-spec.md
# ================================================================

require 'nokogiri'
require_relative '../common'
require_relative 'html_parser'

module VivlioStarter
  module CLI
    module PostProcessCommands
      # ~~~vs-terminal フェンスの HTML を端末枠へ復元するモジュール
      module TerminalBlockConverter
        module_function

        # 前処理が付けた独自言語名。MarkdownTransformer::TERMINAL_FENCE_LANG と対。
        TERMINAL_PRE_SELECTOR = 'pre.language-vs-terminal'

        # @param html_file [String] HTML ファイルのパス
        def convert_terminal_blocks!(html_file)
          content = File.read(html_file, encoding: 'utf-8')
          doc = HtmlParser.parse_html_document(content)

          targets = doc.css(TERMINAL_PRE_SELECTOR)
          return if targets.empty?

          targets.each { wrap_pre_in_terminal_div(it, doc) }

          HtmlParser.save_html_document(html_file, doc)
          Common.log_success("#{html_file}: terminal ブロックを #{targets.size} 件変換しました")
        end

        # <pre class="language-vs-terminal"><code …>…</code></pre>
        #   → <div class="terminal"><pre>…</pre></div>
        def wrap_pre_in_terminal_div(pre, doc)
          # <code> ラッパは畳む（テキストノードのまま子を引き上げる）
          code = pre.at_css('code')
          code.replace(code.children) if code

          pre.remove_attribute('class')

          wrapper = Nokogiri::XML::Node.new('div', doc)
          wrapper['class'] = 'terminal'
          pre.add_previous_sibling(wrapper)
          wrapper.add_child(pre)
        end
      end
    end
  end
end
