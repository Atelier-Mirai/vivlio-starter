# frozen_string_literal: true

require_relative '../html_contract'
require_relative 'html_parser'

module VivlioStarter
  module CLI
    module PostProcessCommands
      # ================================================================
      # Module: RoleInjector
      # ----------------------------------------------------------------
      # 【役割】
      # - 原稿から組むページ（章・前書き・後書き・付録・部扉）の最上位の section.level1 に、
      #   ページの種類に応じた role 属性を付ける（theme-contract-spec.md §2.3）
      #
      # 【なぜ付けるのか】
      # - Vivliostyle の公式テーマは要素を role で選ぶ（`:is(html, body):has([role='doc-chapter'])`・
      #   `section[role='doc-appendix'] > h1`）。section.level1 に付ければ、両方の形に当たる
      # - 今の vs の CSS は role を選んでいないので、見た目は変わらない
      #
      # 値は HtmlContract::PAGE_ROLES が正典。索引・奥付・目次・用語集は、それぞれのページを
      # 生成する処理が自分で付ける（ここでは section.level1 を持つページだけを扱う）。
      # ================================================================
      module RoleInjector
        module_function

        # @param html_file [String] HTML ファイルのパス
        # @param entry [TokenResolver::Entry] ページの種類（kind）を持つ Entry
        # @return [Boolean] 付けたかどうか
        def inject!(html_file, entry)
          role = section_role_for(entry.kind)
          return false unless role

          doc = HtmlParser.parse_html_document(File.read(html_file, encoding: 'utf-8'))
          sections = doc.css('body > section.level1').reject { it['role'] }
          return false if sections.empty?

          sections.each { it['role'] = role }
          HtmlParser.save_html_document(html_file, doc)
          true
        end

        # section.level1 に付ける role。そのページの種類で section.level1 に付けないなら nil
        def section_role_for(kind)
          page_role = HtmlContract::PAGE_ROLES[kind]
          page_role[:role] if page_role&.dig(:element) == 'section.level1'
        end
      end
    end
  end
end
