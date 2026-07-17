# frozen_string_literal: true

# ================================================================
# Test: build/epub_kindle_layout_test.rb
# ================================================================
# テスト対象:
#   Build::EpubBuilder の Kindle レイアウト是正（epub-kindle-layout-spec.md §6-1）
#   - mark_body_for_kindle!        : body へ vs-kindle クラス付与
#   - convert_math_units_for_epub! : inline/display 数式の ex→em 変換
#   - convert_code_blocks_for_epub! : Prism 行番号 pre → 行ブロック化（F 案・両フレーバ共通）
#   - inject_code_line_numbers_for_kindle! : 行番号の実テキスト注入（Kindle 限定）
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
               '<div class="output"><p>出力本文</p></div>' \
               '<div class="terminal"><pre>$ vs build</pre></div>' \
               '<div class="column"><h5>コラム見出し</h5><p>本文</p></div></body></html>'
        doc = process(html) { |files| Builder.decorate_admonitions_for_epub!(files) }

        assert_equal '【TIP】', doc.at_css('.tip > .vs-adm-label')&.text
        assert_equal '【MEMO】', doc.at_css('.memo > .vs-adm-label')&.text
        assert_equal '【NOTICE】', doc.at_css('.notice > .vs-adm-label')&.text
        assert_equal '【NOTE】', doc.at_css('.note > .vs-adm-label')&.text
        assert_equal '【OUTPUT】', doc.at_css('.output > .vs-adm-label')&.text
        assert_equal '【TERMINAL】', doc.at_css('.terminal > .vs-adm-label')&.text
        assert_equal doc.at_css('.terminal > .vs-adm-label'), doc.at_css('.terminal').element_children.first,
                     'ラベルは <pre> の兄弟として枠の先頭に入る（<pre> の内側には置けない）'
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
        rows = doc.css('div.vs-code-epub > div.vs-code-line')
        assert_equal 3, rows.size
        assert_equal "\u00A0", rows[1].at_css('code').text, %q{空行は nbsp で埋める}
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

      # Prism 行番号付きコードが行ブロック（1 論理行 = 1 div）へ変換される（F 案・トークン span 保持・ガター除去）
      def test_should_convert_code_block_to_line_blocks
        html = <<~HTML
          <html><body>
          <pre class="language-ruby line-numbers"><code class="language-ruby line-numbers">def f
            <span class="token keyword">puts</span> 1
          end<span class="line-numbers-rows" aria-hidden="true"><span></span><span></span><span></span></span></code></pre>
          </body></html>
        HTML
        doc = process(html) { |files| Builder.convert_code_blocks_for_epub!(files) }

        container = doc.at_css('div.vs-code-epub')
        refute_nil container, 'pre.line-numbers は div.vs-code-epub へ変換されるべき'
        assert_includes container['class'].split, 'language-ruby', '容器に language-* クラスが付くべき'
        assert_nil doc.at_css('.line-numbers-rows'), '絶対配置ガターは除去されるべき'
        assert_nil doc.at_css('pre.line-numbers'), '元の pre は残らないべき'
        assert_nil container['data-start'], 'data-start なしの pre では容器にも付かない（1 始まり）'

        rows = container.css('> div.vs-code-line')
        assert_equal 3, rows.size, '論理行数ぶんの行ブロックができるべき'
        rows.each do |row|
          assert_includes row.at_css('code')['class'].split, 'language-ruby', '各行 code に language-* が付くべき'
        end
        assert_includes rows[1].inner_html, '<span class="token keyword">puts</span>',
                        'トークン span は保持されるべき'
      end

      # 範囲 include の data-start は容器へ引き継がれ、クリーン EPUB 用カウンタ開始値になる
      def test_should_carry_data_start_to_container
        html = <<~HTML
          <html><body>
          <pre class="language-ruby line-numbers" data-start="22" style="counter-reset: linenumber 21"><code class="language-ruby line-numbers">a = 1
          b = 2</code></pre>
          </body></html>
        HTML
        doc = process(html) { |files| Builder.convert_code_blocks_for_epub!(files) }

        container = doc.at_css('div.vs-code-epub')
        assert_equal '22', container['data-start'], 'data-start は容器へ引き継がれるべき'
        assert_equal 'counter-reset: vs-code-ln 21', container['style'],
                     'クリーン EPUB のカウンタ開始値（N-1）が style に載るべき'
      end

      # .terminal の <pre> は <code> を持たない（前処理でリテラル化し後処理で code を畳むため）。
      # PrismLines が全 <pre> へ line-numbers クラスを付けるので pre.line-numbers に一致するが、
      # 行番号テーブル化の対象にしてはならない（端末の逐語転写に行番号は付かない）。
      def test_should_not_tableize_terminal_pre_without_code
        html = '<html><body><div class="terminal"><pre class="line-numbers">$ vs build</pre></div></body></html>'
        doc = process(html) { |files| Builder.convert_code_blocks_for_epub!(files) }

        assert_empty doc.css('div.vs-code-epub')
        assert_equal '$ vs build', doc.at_css('div.terminal > pre').text
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

        rows = doc.css('div.vs-code-epub > div.vs-code-line')
        assert_equal 3, rows.size
        rows.each_with_index do |line, i|
          assert_equal 1, line.css('span.token.comment').size,
                       "#{i + 1} 行目もコメント span で包まれているべき（行跨ぎトークンの復元）"
        end
      end

      # Kindle 行番号注入: nbsp 右詰めパディング＋末尾区切り空白（等幅で桁が揃う）
      def test_should_inject_right_padded_line_numbers_for_kindle
        lines = (1..10).map { "line#{it}" }.join("\n")
        html = <<~HTML
          <html><body class="vs-kindle">
          <pre class="language-ruby line-numbers"><code class="language-ruby line-numbers">#{lines}</code></pre>
          </body></html>
        HTML
        doc = process(html) do |files|
          Builder.convert_code_blocks_for_epub!(files)
          Builder.inject_code_line_numbers_for_kindle!(files)
        end

        spans = doc.css('div.vs-code-epub > div.vs-code-line > span.vs-code-ln')
        assert_equal 10, spans.size, '各行の先頭に番号 span が注入されるべき'
        assert_equal "\u00A09 ", spans[8].text, '1 桁の番号は nbsp で最大桁数へ右詰めされる'
        assert_equal '10 ', spans[9].text, '最大桁の番号はパディングなし＋区切り空白'
        assert_equal spans[0], doc.at_css('div.vs-code-line').element_children.first,
                     '番号 span は行ブロックの先頭子要素'
      end

      # Kindle 行番号注入: data-start があれば採番の開始値になる
      def test_should_inject_line_numbers_from_data_start
        html = <<~HTML
          <html><body class="vs-kindle">
          <pre class="language-ruby line-numbers" data-start="22"><code class="language-ruby line-numbers">a = 1
          b = 2</code></pre>
          </body></html>
        HTML
        doc = process(html) do |files|
          Builder.convert_code_blocks_for_epub!(files)
          Builder.inject_code_line_numbers_for_kindle!(files)
        end

        assert_equal ['22 ', '23 '], doc.css('span.vs-code-ln').map(&:text),
                     'data-start=22 なら 22 始まりで採番される'
      end

      # Kindle 行番号注入は冪等（再実行しても二重注入されない）
      def test_should_not_double_inject_line_numbers
        html = <<~HTML
          <html><body class="vs-kindle">
          <pre class="language-ruby line-numbers"><code class="language-ruby line-numbers">a = 1</code></pre>
          </body></html>
        HTML
        doc = process(html) do |files|
          Builder.convert_code_blocks_for_epub!(files)
          Builder.inject_code_line_numbers_for_kindle!(files)
          Builder.inject_code_line_numbers_for_kindle!(files)
        end

        assert_equal 1, doc.css('span.vs-code-ln').size
      end

      # =================================================================
      # decorate_list_markers_for_epub!（fancy list / outline-list の実体マーカー注入・
      # nested-list-notation-spec.md §6.1）
      # =================================================================

      # fancy 各様式のマーカー文字列が li 先頭へ実体注入される（KFX は ::before を描けない）
      def test_should_inject_fancy_list_markers_for_kindle
        html = <<~HTML
          <html><body class="vs-kindle">
          <ol class="vs-fancy-list vs-list-lower-alpha" type="a"><li>甲</li><li>乙</li></ol>
          <ol class="vs-fancy-list vs-list-upper-roman-paren" type="I"><li>壱</li><li>弐</li></ol>
          <ol class="vs-fancy-list vs-list-decimal-paren2" style="counter-reset: vs-fancy 0"><li>一</li></ol>
          </body></html>
        HTML
        doc = process(html) { |files| Builder.decorate_list_markers_for_epub!(files) }

        alpha = doc.css('ol.vs-list-lower-alpha > li > span.vs-li-marker').map(&:text)
        assert_equal ['a. ', 'b. '], alpha, 'ピリオド様式は「a. 」形式'
        roman = doc.css('ol.vs-list-upper-roman-paren > li > span.vs-li-marker').map(&:text)
        assert_equal ['I) ', 'II) '], roman, '片括弧様式は「I) 」形式'
        decimal = doc.css('ol.vs-list-decimal-paren2 > li > span.vs-li-marker').map(&:text)
        assert_equal ['(1) '], decimal, '両括弧様式は「(1) 」形式'
      end

      # start 属性から開始値を復元して採番する
      def test_should_inject_fancy_markers_from_start_attribute
        html = <<~HTML
          <html><body class="vs-kindle">
          <ol class="vs-fancy-list vs-list-lower-roman-paren2" type="i" start="4"
              style="counter-reset: vs-fancy 3"><li>四</li><li>五</li></ol>
          </body></html>
        HTML
        doc = process(html) { |files| Builder.decorate_list_markers_for_epub!(files) }

        assert_equal ['(iv) ', '(v) '], doc.css('span.vs-li-marker').map(&:text),
                     'start="4" のローマ数字は iv 始まり'
      end

      # outline-list はネスト位置から複合番号を計算して注入する（ul は素通し）
      def test_should_inject_outline_list_compound_numbers
        html = <<~HTML
          <html><body class="vs-kindle">
          <div class="outline-list">
          <ol><li>概要<ol><li>この機能について</li><li>インストール方法</li></ol></li>
          <li>使い方<ol><li>基本</li></ol><ul><li>補足の箇条書き</li></ul></li></ol>
          </div>
          </body></html>
        HTML
        doc = process(html) { |files| Builder.decorate_list_markers_for_epub!(files) }

        markers = doc.css('.outline-list span.vs-li-marker').map(&:text)
        assert_equal ['1. ', '1.1. ', '1.2. ', '2. ', '2.1. '], markers,
                     '複合番号は CSS counters(vs-outline, ".") と同じ「1.1. 」表記'
        assert_empty doc.css('.outline-list ul span.vs-li-marker'), 'ul には注入されない'
      end

      # ルーズ形式（li 直下が <p>）は最初の <p> の内側へ注入され、独立行にならない
      def test_should_inject_marker_inside_first_paragraph_of_loose_item
        html = <<~HTML
          <html><body class="vs-kindle">
          <ol class="vs-fancy-list vs-list-lower-alpha" type="a"><li><p>ルーズ項目</p></li></ol>
          </body></html>
        HTML
        doc = process(html) { |files| Builder.decorate_list_markers_for_epub!(files) }

        refute_nil doc.at_css('li > p > span.vs-li-marker'), 'マーカーは p の内側の先頭に入る'
        assert_equal 'a. ルーズ項目', doc.at_css('li > p').text
      end

      # リストマーカー注入は冪等（再実行しても二重注入されない）
      def test_should_not_double_inject_list_markers
        html = <<~HTML
          <html><body class="vs-kindle">
          <ol class="vs-fancy-list vs-list-lower-alpha" type="a"><li>甲</li></ol>
          <div class="outline-list"><ol><li>概要</li></ol></div>
          </body></html>
        HTML
        doc = process(html) do |files|
          Builder.decorate_list_markers_for_epub!(files)
          Builder.decorate_list_markers_for_epub!(files)
        end

        assert_equal 2, doc.css('span.vs-li-marker').size, '2 回適用しても注入は各 li に 1 つ'
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
