# frozen_string_literal: true

require 'minitest/autorun'
require 'tempfile'
require 'nokogiri'
require_relative '../../../../lib/vivlio_starter/cli/post_process'

module VivlioStarter
  module CLI
    module PostProcessCommands
      # renumber_footnotes_by_document_order! は、脚注の番号を本文での出現順に
      # 振り直す。番号を振る単位は「脚注」であって「参照」ではない。
      #
      # 同じ脚注ラベルを複数回参照すると、VFM は 2 回目以降の参照にも同じ
      # href="#fnN" と番号を付ける。かつては参照ごとに連番を振っていたため、
      # 参照が 1・2・3 と進み、存在しない #fn3 を指す参照ができ、脚注本文は
      # 最後の番号で描かれていた（97 章で実測）。
      class FootnoteRenumberTest < Minitest::Test
        # VFM の出力を、ビルドと同じ順に脚注変換 → 再番号付けへ通す。
        def build(body_html)
          html = <<~HTML
            <!DOCTYPE html>
            <html><head><title>t</title></head><body>
            #{body_html}
            </body></html>
          HTML
          converted = FootnoteConverter.convert_endnotes_to_page_footnotes!(html)

          Tempfile.create(['vs_footnote_renumber_', '.html']) do |f|
            f.write(converted)
            f.flush
            PostProcessCommands.renumber_footnotes_by_document_order!(f.path)
            return Nokogiri::HTML(File.read(f.path, encoding: 'utf-8'))
          end
        end

        def refs(doc) = doc.css('a.footnote-ref')

        # =============================================================
        # 同じ脚注を複数回参照する
        # =============================================================

        # VFM 2.x の実出力（`[^a]` → `[^b]` → `[^a]` の順に参照）
        def test_should_give_repeated_reference_the_same_number
          doc = build(<<~HTML)
            <p>一文目です<a id="fnref1" href="#fn1" class="footnote-ref" role="doc-noteref"><sup>1</sup></a>。二文目です<a id="fnref2" href="#fn2" class="footnote-ref" role="doc-noteref"><sup>2</sup></a>。</p>
            <p>三文目です<a id="fnref1-1" href="#fn1" class="footnote-ref" role="doc-noteref"><sup>1</sup></a>。</p>
            <section class="footnotes" role="doc-endnotes">
              <ol>
                <li id="fn1" role="doc-endnote">共通の脚注。<a href="#fnref1" class="footnote-back">↩</a><a href="#fnref1-1" class="footnote-back">↩</a></li>
                <li id="fn2" role="doc-endnote">別の脚注。<a href="#fnref2" class="footnote-back">↩</a></li>
              </ol>
            </section>
          HTML

          assert_equal %w[1 2 1], refs(doc).map(&:text)
          assert_equal %w[#fn1 #fn2 #fn1], refs(doc).map { it['href'] }
          assert_equal '1', doc.at_css('span#fn1')['data-footnote-number']
          assert_includes doc.at_css('span#fn1').text, '共通の脚注。'
          assert_equal '2', doc.at_css('span#fn2')['data-footnote-number']
        end

        # 出現順と VFM の番号がずれていて振り直しが走る場合も、同じ脚注への
        # 参照は同じ番号にまとまり、本文との対応も保たれる。参照の id は
        # 重複させない（2 回目以降は VFM と同じ fnrefN-K の形）。
        def test_should_keep_repeated_references_together_when_renumbering
          doc = build(<<~HTML)
            <p>先<a id="fnref2" href="#fn2" class="footnote-ref" role="doc-noteref"><sup>2</sup></a>。</p>
            <p>次<a id="fnref1" href="#fn1" class="footnote-ref" role="doc-noteref"><sup>1</sup></a>。</p>
            <p>再び<a id="fnref2-1" href="#fn2" class="footnote-ref" role="doc-noteref"><sup>2</sup></a>。</p>
            <section class="footnotes" role="doc-endnotes">
              <ol>
                <li id="fn1" role="doc-endnote">後から出る脚注。</li>
                <li id="fn2" role="doc-endnote">先に出る脚注。</li>
              </ol>
            </section>
          HTML

          assert_equal %w[1 2 1], refs(doc).map(&:text)
          assert_equal %w[#fn1 #fn2 #fn1], refs(doc).map { it['href'] }
          assert_equal %w[fnref1 fnref2 fnref1-1], refs(doc).map { it['id'] }
          assert_includes doc.at_css('span#fn1').text, '先に出る脚注。'
          assert_equal '1', doc.at_css('span#fn1')['data-footnote-number']
          assert_includes doc.at_css('span#fn2').text, '後から出る脚注。'
          assert_equal '2', doc.at_css('span#fn2')['data-footnote-number']
        end
      end
    end
  end
end
