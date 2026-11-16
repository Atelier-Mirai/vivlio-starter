# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/build/transforms/shared/strip_inline_footnote_ids.rb
# ================================================================
# 責務:
#   段落内脚注の span の、重複する id を外す
# ================================================================

require_relative '../context'
require_relative '../../../post_process/html_parser'

module VivlioStarter
  module CLI
    module Build
      # 段落内脚注の span の、重複する id を外す
      module Transforms::Shared::StripInlineFootnoteIds
        module_function

        # ================================================================
        # EPUB 用 脚注 id 重複の解消
        # ================================================================
        # footnote_converter は段落内脚注に対し span（画面用）と aside（印刷用）へ
        # 同じ本文 HTML を流し込む（PDF の脚注二重描画回避。PDF 経路では変更禁止）。
        # XHTML では同一文書内の id 重複が ERROR になるため、EPUB 経路でのみ
        # span 側の id を除去して aside 側に一意化する。
        # 残す側を aside にするのは、EPUB で読者に見えるのが aside だから
        # （parts/footnote.css の `.page-footnote-inline { display: none }` と
        # `body.vs-epub aside.page-footnote { display: block }`）。索引・用語集の
        # リンク先も、読者が実際に読む側に着地させる。
        # ================================================================

        # 段落内脚注 span（page-footnote-inline）自身と、その中身から id を除去する。
        #
        # span 自身の id だけを外していたため、脚注本文に索引語・用語集語があると
        # `idx-…` / `gls-src-…` が span と aside の両方に残って重複していた
        # （実測: 22 章「CSS」・33 章「ノンブル」で epubcheck RSC-005 ERROR）。
        # span は丸ごと aside の控えなので、中の id もすべて控え側から外す。
        #
        # @param html_files [Array<String>] HTML ファイルパスの配列
        # @return [Array<String>] そのままの配列（パス変更なし）
        def call(html_files, _ctx)
          html_files.each do |path|
            doc = PostProcessCommands::HtmlParser.parse_html_document(File.read(path, encoding: 'utf-8'))
            removed = doc.css('span.page-footnote-inline').sum { strip_ids_within!(it) }
            next if removed.zero?

            PostProcessCommands::HtmlParser.save_html_document(path, doc)
            Common.log_info("[EPUB] #{File.basename(path)} の脚注 span から id を #{removed} 件除去しました")
          end
          html_files
        end

        # 要素自身とその子孫から id 属性を外す。
        # @return [Integer] 外した id の数
        def strip_ids_within!(element)
          targets = [element, *element.css('[id]')].select { it['id'] }
          targets.each { it.remove_attribute('id') }
          targets.size
        end
      end
    end
  end
end
