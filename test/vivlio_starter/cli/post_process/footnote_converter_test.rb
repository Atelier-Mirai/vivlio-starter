# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../../../../lib/vivlio_starter/cli/post_process/footnote_converter'

module VivlioStarter
  module CLI
    module PostProcessCommands
      # FootnoteConverter は VFM が生成した章末脚注（section.footnotes）を
      # ページ脚注（aside.page-footnote）へ変換する。
      #
      # Vivliostyle は、脚注参照リンク（href="#fnN"）の解決先が
      # float:footnote の aside 自体である場合、参照のあるページと aside の
      # あるページの両方へ同じ脚注を描画してしまう。そのため変換後の HTML では、
      # 参照リンクの解決先が必ず不可視のインライン脚注 span#fnN
      # （文書順で aside より先に出現する）になっている必要がある。
      class FootnoteConverterTest < Minitest::Test
        def footnotes_section(definitions)
          items = definitions.map do |fid, body|
            %(<li id="#{fid}"><p>#{body} <a href="#fnref1" class="footnote-back">↩</a></p></li>)
          end
          <<~HTML
            <section class="footnotes">
              <ol>#{items.join}</ol>
            </section>
          HTML
        end

        def convert(body_html)
          html = <<~HTML
            <!DOCTYPE html>
            <html><head><title>t</title></head><body>
            #{body_html}
            </body></html>
          HTML
          FootnoteConverter.convert_endnotes_to_page_footnotes!(html)
        end

        # =============================================================
        # 段落内参照: span（インライン）→ aside（印刷用）の順で挿入される
        # =============================================================

        def test_should_place_inline_span_before_aside_for_paragraph_reference
          body = <<~HTML
            <section>
              <p>本文 <a id="fnref1" href="#fn1" class="footnote-ref" role="doc-noteref"><sup>1</sup></a> 続き</p>
            </section>
            #{footnotes_section('fn1' => '脚注本文')}
          HTML

          out = convert(body)

          span_pos  = out.index('<span role="doc-footnote" class="page-footnote page-footnote-inline" id="fn1"')
          aside_pos = out.index('<aside role="doc-footnote" class="page-footnote page-footnote-print" id="fn1"')
          refute_nil span_pos
          refute_nil aside_pos
          assert_operator span_pos, :<, aside_pos,
                          '参照リンクの解決先となる span は aside より文書順で先になければならない'
        end

        # =============================================================
        # 段落外参照（テーブルセル内）: 重複描画防止の不可視 span が挿入される
        # =============================================================

        def test_should_insert_hidden_span_for_table_cell_reference
          body = <<~HTML
            <section>
              <table><tbody><tr>
                <td><a href="https://brew.sh">https://brew.sh</a> <a id="fnref1" href="#fn1" class="footnote-ref" role="doc-noteref"><sup>1</sup></a></td>
              </tr></tbody></table>
            </section>
            #{footnotes_section('fn1' => '<a href="https://brew.sh">https://brew.sh</a>')}
          HTML

          out = convert(body)

          span_pos  = out.index('<span role="doc-footnote" class="page-footnote page-footnote-inline" id="fn1"')
          aside_pos = out.index('<aside role="doc-footnote" class="page-footnote page-footnote-print" id="fn1"')
          refute_nil span_pos, 'テーブルセル内の参照にも不可視 span が挿入されること'
          refute_nil aside_pos
          assert_operator span_pos, :<, aside_pos
        end

        # =============================================================
        # テーブル内参照: VFM が入れ替えた定義内容が修復される
        # =============================================================

        def test_should_repair_swapped_footnote_definitions_for_table_references
          # VFM 2.x はテーブルセル内から参照される脚注の定義「本文」を
          # 入れ替えて出力することがある（参照IDの対応は正しいまま）。
          # ここでは fn1 の本文に fn2 のURLが入った状態を再現する。
          body = <<~HTML
            <section>
              <table><tbody>
                <tr><td><a href="https://brew.sh">brew.sh</a> <a id="fnref1" href="#fn1" class="footnote-ref" role="doc-noteref"><sup>1</sup></a></td></tr>
                <tr><td><a href="https://nodejs.org/">nodejs.org</a> <a id="fnref2" href="#fn2" class="footnote-ref" role="doc-noteref"><sup>2</sup></a></td></tr>
              </tbody></table>
            </section>
            #{footnotes_section(
              'fn1' => '<a href="https://nodejs.org/">https://nodejs.org/</a>',
              'fn2' => '<a href="https://brew.sh">https://brew.sh</a>'
            )}
          HTML

          out = convert(body)

          assert_match(
            %r{<aside[^>]*id="fn1"[^>]*><a href="https://brew\.sh">https://brew\.sh</a></aside>},
            out, 'fn1 の本文は参照直前のリンク（brew.sh）に修復されること'
          )
          assert_match(
            %r{<aside[^>]*id="fn2"[^>]*><a href="https://nodejs\.org/">https://nodejs\.org/</a></aside>},
            out, 'fn2 の本文は参照直前のリンク（nodejs.org）に修復されること'
          )
        end

        def test_should_not_touch_handwritten_footnote_definitions_in_tables
          # 手書きの脚注（本文が「URLそのものへのリンク」ではない）は
          # 入れ替わり修復の対象にしない
          body = <<~HTML
            <section>
              <table><tbody>
                <tr><td><a href="https://example.com/">サイト</a> <a id="fnref1" href="#fn1" class="footnote-ref" role="doc-noteref"><sup>1</sup></a></td></tr>
              </tbody></table>
            </section>
            #{footnotes_section('fn1' => '補足説明の脚注です')}
          HTML

          out = convert(body)

          assert_match(%r{<aside[^>]*id="fn1"[^>]*>(?:<p>)?補足説明の脚注です\s*(?:</p>)?</aside>}, out)
        end

        # =============================================================
        # sideimage 内参照: aside はコンテナの直後に配置される
        # =============================================================

        def test_should_place_aside_right_after_sideimage_container
          body = <<~HTML
            <section>
              <div class="sideimage-right">
                <figure><img src="x.webp"></figure>
                <div class="sideimage-body"><p>本文 <a id="fnref1" href="#fn1" class="footnote-ref" role="doc-noteref"><sup>1</sup></a></p></div>
              </div>
              <p>後続の段落</p>
            </section>
            #{footnotes_section('fn1' => '脚注本文')}
          HTML

          out = convert(body)

          # aside は sideimage コンテナの外（直後）にあり、endnote クラスは付かない
          refute_includes out, 'page-footnote-endnote'
          container_end = out.index('後続の段落')
          aside_pos = out.index('<aside role="doc-footnote" class="page-footnote page-footnote-print" id="fn1"')
          sideimage_pos = out.index('sideimage-right')
          refute_nil aside_pos
          assert_operator sideimage_pos, :<, aside_pos
          assert_operator aside_pos, :<, container_end,
                          'aside は sideimage コンテナ直後（後続段落より前）に配置されること'
        end
      end
    end
  end
end
