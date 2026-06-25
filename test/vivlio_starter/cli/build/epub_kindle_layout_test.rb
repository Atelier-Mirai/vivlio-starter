# frozen_string_literal: true

# ================================================================
# Test: build/epub_kindle_layout_test.rb
# ================================================================
# テスト対象:
#   Build::EpubBuilder の Kindle レイアウト是正（epub-kindle-layout-spec.md §6-1）
#   - mark_body_for_kindle!        : body へ vs-kindle クラス付与
#   - convert_math_units_for_epub! : inline/display 数式の ex→em 変換
#   - convert_code_blocks_for_epub! : Prism 行番号 → 2 列テーブル化
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'nokogiri'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/build/epub_builder'

module VivlioStarter
  module CLI
    class EpubKindleLayoutTest < Minitest::Test
      Builder = Build::EpubBuilder
      LOG_METHODS = %i[log_info log_success log_warn log_error log_action].freeze

      def setup
        @saved_logs = LOG_METHODS.to_h { [it, Common.method(it)] }
        LOG_METHODS.each { |name| Common.define_singleton_method(name) { |*, **| } }
      end

      def teardown
        @saved_logs&.each { |name, m| Common.define_singleton_method(name, m) }
      end

      # body に vs-kindle クラスが付与される
      def test_should_mark_body_with_vs_epub
        doc = process('<html><body class="chapter"><p>本文</p></body></html>') do |files|
          Builder.mark_body_for_kindle!(files)
        end
        assert_includes doc.at_css('body')['class'].split, 'vs-kindle'
        assert_includes doc.at_css('body')['class'].split, 'chapter', '既存クラスは保持される'
      end

      # inline 数式の ex 寸法が em（×0.5）へ変換される
      def test_should_convert_inline_math_ex_to_em
        html = '<html><body><p>単位は' \
               '<img class="vs-math vs-math-inline" src="images/math/x.svg" ' \
               'style="vertical-align: -0.566ex; width: 1.2ex; height: 2.262ex;" alt="A"></p></body></html>'
        doc = process(html) { |files| Builder.convert_math_units_for_epub!(files) }

        style = doc.at_css('img.vs-math-inline')['style']
        refute_includes style, 'ex', 'ex 単位が残ってはいけない'
        assert_includes style, 'height: 1.131em'
        assert_includes style, 'width: 0.6em'
        assert_includes style, 'vertical-align: -0.283em'
      end

      # 表セル内の inline 数式は最低 1em の高さを確保し、等比拡大される（単位記号の可読性）
      def test_should_enlarge_inline_math_inside_table_cell
        html = '<html><body><table><tbody><tr><td>' \
               '<img class="vs-math vs-math-inline" src="images/math/a.svg" ' \
               'style="vertical-align: -0.2ex; width: 1.4ex; height: 1.4ex;" alt="A"></td></tr></tbody></table></body></html>'
        doc = process(html) { |files| Builder.convert_math_units_for_epub!(files) }

        style = doc.at_css('td img.vs-math-inline')['style']
        # height 1.4ex は ×0.5 で 0.7em（<1.0em）なので factor=1.0/1.4 で等比拡大され height=1.0em
        assert_includes style, 'height: 1.0em'
        assert_includes style, 'width: 1.0em', '幅も同じ係数で拡大される（縦横比維持）'
        refute_includes style, 'ex'
      end

      # 表の外の inline 数式は ×0.5 のまま（拡大しない）
      def test_should_not_enlarge_inline_math_outside_table
        html = '<html><body><p>' \
               '<img class="vs-math vs-math-inline" src="images/math/a.svg" ' \
               'style="height: 1.4ex; width: 1.4ex;" alt="A"></p></body></html>'
        doc = process(html) { |files| Builder.convert_math_units_for_epub!(files) }
        assert_includes doc.at_css('img.vs-math-inline')['style'], 'height: 0.7em'
      end

      # book-card 画像に inline で幅・float が付与される（Kindle は外部 CSS の画像サイズを無視）
      def test_should_constrain_book_card_image_inline
        html = '<html><body><div class="book-card"><img src="images/_epub_assets/x.jpg" alt="">' \
               '<div class="book-info"><p>説明</p></div></div></body></html>'
        doc = process(html) { |files| Builder.constrain_layout_images_for_epub!(files) }

        style = doc.at_css('.book-card img')['style']
        assert_includes style, 'width: 40%'
        assert_includes style, 'float: left'
      end

      # sideimage（figure 子）は figure に幅・float、内側 img に width:100% を付与
      def test_should_constrain_sideimage_figure_inline
        html = '<html><body><div class="sideimage-right"><figure><img src="images/a.jpg" alt=""></figure>' \
               '<div class="sideimage-body"><p>本文</p></div></div></body></html>'
        doc = process(html) { |files| Builder.constrain_layout_images_for_epub!(files) }

        fig_style = doc.at_css('.sideimage-right figure')['style']
        assert_includes fig_style, 'width: 25%', 'sideimage は text3:image1（画像 1/4 = 25%）'
        assert_includes fig_style, 'float: right'
        assert_includes doc.at_css('.sideimage-right figure img')['style'], 'width: 100%'
      end

      # 数式画像に px の width/height 属性が付与される（Kindle が em を無視しても本文相当に固定）
      def test_should_add_px_attributes_to_math_for_kindle
        html = '<html><body><p>' \
               '<img class="vs-math vs-math-inline" src="images/math/a.svg" ' \
               'style="height: 1.4ex; width: 2.0ex;" alt="A"></p></body></html>'
        doc = process(html) { |files| Builder.convert_math_units_for_epub!(files) }

        img = doc.at_css('img.vs-math-inline')
        # 表外は ×0.5 → height 0.7em / width 1.0em。px は em×16（端数四捨五入）
        assert_equal '11', img['height'], 'height 0.7em ×16 ≒ 11px'
        assert_equal '16', img['width'], 'width 1.0em ×16 = 16px'
      end

      # 表セル内の数式は floor 後の em（=1.0em）から px を算出し本文相当（16px）になる
      def test_should_size_table_math_px_to_body
        html = '<html><body><table><tbody><tr><td>' \
               '<img class="vs-math vs-math-inline" src="images/math/m.svg" ' \
               'style="height: 1.4ex; width: 1.4ex;" alt="m"></td></tr></tbody></table></body></html>'
        doc = process(html) { |files| Builder.convert_math_units_for_epub!(files) }

        img = doc.at_css('td img.vs-math-inline')
        assert_equal '16', img['height'], '表内 floor 1.0em ×16 = 16px（本文相当）'
        assert_equal '16', img['width']
      end

      # tip / memo / column / notice / note にラベル要素が先頭注入される（Kindle で ::before ラベルが消える対策）
      def test_should_inject_admonition_label
        html = '<html><body class="vs-kindle">' \
               '<div class="tip"><p>ヒント本文</p></div>' \
               '<div class="memo"><p>メモ本文</p></div>' \
               '<div class="notice"><p>注意本文</p></div>' \
               '<div class="note"><p>補足本文</p></div>' \
               '<div class="column"><h5>コラム見出し</h5><p>本文</p></div></body></html>'
        doc = process(html) { |files| Builder.decorate_admonitions_for_epub!(files) }

        assert_equal '【TIP】', doc.at_css('.tip > .vs-adm-label')&.text
        assert_equal '【MEMO】', doc.at_css('.memo > .vs-adm-label')&.text
        assert_equal '【NOTICE】', doc.at_css('.notice > .vs-adm-label')&.text
        assert_equal '【NOTE】', doc.at_css('.note > .vs-adm-label')&.text
        assert_equal '【COLUMN】', doc.at_css('.column > .vs-adm-label')&.text
        assert_equal doc.at_css('.column > .vs-adm-label'), doc.at_css('.column').element_children.first,
                     'ラベルはコラム枠の先頭子要素（見出しより前）'
      end

      # 既に注入済みのラベルは二重に追加されない
      def test_should_not_double_inject_admonition_label
        html = '<html><body class="vs-kindle">' \
               '<div class="tip"><p class="vs-adm-label">【TIP】</p><p>本文</p></div></body></html>'
        doc = process(html) { |files| Builder.decorate_admonitions_for_epub!(files) }
        assert_equal 1, doc.css('.tip .vs-adm-label').size
      end

      # 空のコード行は nbsp で高さを保つ（行高の不揃い防止）
      def test_should_keep_blank_code_line_height_with_nbsp
        html = <<~HTML
          <html><body>
          <pre class="language-ruby line-numbers"><code class="language-ruby line-numbers">x = 1

          y = 2<span class="line-numbers-rows"><span></span><span></span><span></span></span></code></pre>
          </body></html>
        HTML
        doc = process(html) { |files| Builder.convert_code_blocks_for_epub!(files) }
        rows = doc.css('table.vs-code-epub tbody > tr')
        assert_equal 3, rows.size
        assert_equal "\u00A0", rows[1].at_css(%q{.vs-code-line code}).text, %q{空行は nbsp で埋める}
      end

      # display 数式画像の ex 寸法も変換される
      def test_should_convert_display_math_ex_to_em
        html = '<html><body><figure class="vs-math vs-math-display">' \
               '<img src="images/math/d.svg" style="width: 10ex; height: 4ex;" alt="eq"></figure></body></html>'
        doc = process(html) { |files| Builder.convert_math_units_for_epub!(files) }

        style = doc.at_css('figure.vs-math-display img')['style']
        assert_includes style, 'width: 5.0em'
        assert_includes style, 'height: 2.0em'
      end

      # Prism 行番号付きコードが 2 列テーブルへ変換される（番号・トークン span 保持・ガター除去）
      def test_should_convert_code_block_to_table
        html = <<~HTML
          <html><body>
          <pre class="language-ruby line-numbers"><code class="language-ruby line-numbers">def f
            <span class="token keyword">puts</span> 1
          end<span class="line-numbers-rows" aria-hidden="true"><span></span><span></span><span></span></span></code></pre>
          </body></html>
        HTML
        doc = process(html) { |files| Builder.convert_code_blocks_for_epub!(files) }

        table = doc.at_css('table.vs-code-epub')
        refute_nil table, 'pre.line-numbers は table.vs-code-epub へ変換されるべき'
        assert_nil doc.at_css('.line-numbers-rows'), '絶対配置ガターは除去されるべき'
        assert_nil doc.at_css('pre.line-numbers'), '元の pre は残らないべき'

        rows = table.css('tbody > tr')
        assert_equal 3, rows.size, '論理行数ぶんの行ができるべき'
        assert_equal %w[1 2 3], rows.map { it.at_css('.vs-code-num').text }
        assert_includes rows[1].at_css('.vs-code-line').inner_html, '<span class="token keyword">puts</span>',
                        'トークン span は保持されるべき'
      end

      # 複数行に跨るトークン（ブロックコメント等）は行ごとに span を開き直す
      def test_should_reopen_token_span_across_newlines
        html = <<~HTML
          <html><body>
          <pre class="language-ruby line-numbers"><code class="language-ruby line-numbers"><span class="token comment">=begin
          multi
          =end</span><span class="line-numbers-rows"><span></span><span></span><span></span></span></code></pre>
          </body></html>
        HTML
        doc = process(html) { |files| Builder.convert_code_blocks_for_epub!(files) }

        rows = doc.css('table.vs-code-epub tbody > tr')
        assert_equal 3, rows.size
        rows.each_with_index do |tr, i|
          line = tr.at_css('.vs-code-line')
          assert_equal 1, line.css('span.token.comment').size,
                       "#{i + 1} 行目もコメント span で包まれているべき（行跨ぎトークンの復元）"
        end
      end

      private

      # 一時ファイルに html を書き、ブロックで変換を適用し、保存結果を Nokogiri で返す
      def process(html)
        Dir.mktmpdir('vs-kindle-layout') do |dir|
          path = File.join(dir, 'chapter.html')
          File.write(path, html, encoding: 'utf-8')
          yield([path])
          return Nokogiri::HTML5(File.read(path, encoding: 'utf-8'))
        end
      end
    end
  end
end
