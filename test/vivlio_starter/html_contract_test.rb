# frozen_string_literal: true

# ================================================================
# Test: html_contract_test.rb
# ================================================================
# テスト対象:
#   HtmlContract（lib/vivlio_starter/cli/html_contract.rb）・RoleInjector・SectionWrapper
#
# 検証内容（theme-contract-spec.md §2・§9 の S1）:
#   (a) stylesheets/ と同梱のテーマ（themes/）の CSS が選ぶクラスは、表の「保証」か
#       「テーマ」にある。CSS が選ぶ data-* 属性は、保証する属性にある
#   - 契約 HTML の形: section.level1 にページの種類の role が付き、h2 は theme.style に
#     依らず article.section-topic に包まれる
#
# (b)「記法の見本帳を HTML にし、出たクラスが表にある」は、実際に組む必要があるので
# 記法網羅のテスト（test/vivlio_starter/notation/notation_coverage_test.rb・test:notation）に置く。
# そちらは見本帳を 1 度だけ組み、その HTML を共用する。
# ================================================================

require 'test_helper'
require 'tempfile'
require 'nokogiri'
require 'vivlio_starter/cli/loader'

module VivlioStarter
  module CLI
    class HtmlContractTest < Minitest::Test
      REPO_ROOT = File.expand_path('../..', __dir__)
      CSS_FILES = Dir[File.join(REPO_ROOT, '{stylesheets,themes}', '**', '*.css')].freeze
      Entry = Data.define(:kind)

      # --- (a) CSS が選ぶクラスは、表の保証かテーマにある ----------------------------

      def test_should_classify_every_class_selected_by_bundled_css
        refute_empty CSS_FILES, 'stylesheets/ の CSS が見つかりません'

        unknown = CSS_FILES.flat_map do |path|
          HtmlContract.css_classes(File.read(path, encoding: 'utf-8'))
                      .reject { HtmlContract.selectable?(it) }
                      .map { "#{File.basename(path)}: .#{it}" }
        end

        assert_empty unknown,
                     "CSS が、契約 HTML の表の保証に無いクラスを選んでいます。lib/vivlio_starter/cli/html_contract.rb の表に足してください:\n" \
                     "#{unknown.join("\n")}"
      end

      def test_should_guarantee_every_data_attribute_selected_by_bundled_css
        unknown = CSS_FILES.flat_map do |path|
          HtmlContract.css_data_attributes(File.read(path, encoding: 'utf-8'))
                      .reject { HtmlContract::GUARANTEED_ATTRIBUTES.key?(it) }
                      .map { "#{File.basename(path)}: [#{it}]" }
        end

        assert_empty unknown, "CSS が、保証に無い data-* 属性を選んでいます:\n#{unknown.join("\n")}"
      end

      # 内部のクラスは、選ばれていないことを前提に変えてよいものなので、CSS が選んだら落ちる
      def test_should_not_treat_internal_classes_as_selectable
        refute HtmlContract.selectable?('index-term')
        refute HtmlContract.selectable?('talk-c-einstein')
        assert HtmlContract.selectable?('memo')
        assert HtmlContract.selectable?('language-ruby')
        assert HtmlContract.selectable?('keyword'), 'Prism のトークンは選んでよい'
      end

      # --- 表の引き方 --------------------------------------------------------------

      def test_should_report_classes_missing_from_the_table_except_prism_tokens
        doc = Nokogiri::HTML5(<<~HTML)
          <body class="chapter">
            <div class="memo vs-unknown-box"><span class="token keyword unheard-token">def</span></div>
          </body>
        HTML

        assert_equal Set['vs-unknown-box'], HtmlContract.unclassified_classes(doc)
      end

      def test_should_give_every_page_role_a_dpub_aria_value
        roles = HtmlContract::PAGE_ROLES.values.map { it[:role] }

        assert(roles.all? { it.start_with?('doc-') }, roles.inspect)
        assert_equal roles.uniq, roles
      end

      # --- role 属性（§2.3） -------------------------------------------------------

      def test_should_add_page_role_to_top_level_sections
        html = inject_roles(:chapter, <<~HTML)
          <section class="level1"><h1>章</h1><section class="level1"><h1>入れ子</h1></section></section>
          <section class="level1"><h1>二つめの h1</h1></section>
        HTML
        doc = Nokogiri::HTML5(html)

        assert_equal %w[doc-chapter doc-chapter], doc.css('body > section.level1').map { it['role'] }
        assert_nil doc.at_css('section.level1 section.level1')['role'], '入れ子の section には付けない'
      end

      def test_should_map_each_manuscript_page_kind_to_its_role
        expected = { preface: 'doc-preface', postface: 'doc-afterword', appendix: 'doc-appendix', part_title: 'doc-part' }

        actual = expected.keys.to_h do |kind|
          [kind, Nokogiri::HTML5(inject_roles(kind, '<section class="level1"><h1>見出し</h1></section>'))
                   .at_css('section.level1')['role']]
        end

        assert_equal expected, actual
      end

      def test_should_leave_pages_without_section_role_untouched
        html = inject_roles(:titlepage, '<section class="level1"><h1>扉</h1></section>')

        refute_includes html, 'role='
      end

      def test_should_keep_role_already_present
        html = inject_roles(:chapter, '<section class="level1" role="doc-glossary"><h1>見出し</h1></section>')

        assert_includes html, 'role="doc-glossary"'
      end

      # --- article.section-topic（§2.6） ------------------------------------------------

      # theme.style を読まない。simple の本でも image の本と同じ構造になる
      def test_should_wrap_h2_and_lead_regardless_of_theme_style
        html = <<~HTML
          <html><body class="chapter vs-header-simple">
          <section class="level1"><h1>章</h1>
          <section class="level2"><h2>節</h2><div class="section-lead"><p>リード</p></div><p>本文</p></section>
          </section></body></html>
        HTML

        doc = Nokogiri::HTML5(PostProcessCommands::SectionWrapper.wrap_h2_with_article!(html))

        article = doc.at_css('section.level2 > article.section-topic')
        refute_nil article, 'h2 が article.section-topic に包まれていません'
        assert_equal %w[h2 div], article.element_children.map(&:name)
        assert_equal 'p', article.next_element.name, '本文は article の外に残る'
      end

      private

      def inject_roles(kind, body)
        Tempfile.create(['vs_role_', '.html']) do |file|
          file.write("<html><body>\n#{body}\n</body></html>")
          file.flush
          PostProcessCommands::RoleInjector.inject!(file.path, Entry.new(kind:))
          return File.read(file.path, encoding: 'utf-8')
        end
      end
    end
  end
end
