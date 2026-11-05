# frozen_string_literal: true

require 'minitest/autorun'
require 'tempfile'
require_relative '../../../../lib/vivlio_starter/cli/post_process'

module VivlioStarter
  module CLI
    module PostProcessCommands
      # wrap_text_table_blocks! は `:::{.text-table}` の中身を、本文（.text-table-body）と
      # 表の側（.text-table-table）の 2 列に包む（text-table-spec.md §2.1）。
      # `:::{.table-text}` は表の側を先に置く（§13）。
      class TextTableTest < Minitest::Test
        def wrap(inner, klass: 'text-table')
          Tempfile.create(['vs_text_table_test_', '.html']) do |f|
            f.write(%(<html><body><div class="#{klass}">#{inner}</div></body></html>))
            f.flush
            PostProcessCommands.wrap_text_table_blocks!(f.path)
            return Nokogiri::HTML(File.read(f.path, encoding: 'utf-8')).at_css("div.#{klass}")
          end
        end

        TABLE = '<table><tr><td>a</td></tr></table>'

        # 本文が 2 段落でも 2 列になる（包まないと flex の列が子の数だけできる）
        def test_should_wrap_body_paragraphs_and_table_into_two_columns
          box = wrap("<p>一つ目。</p><p>二つ目。</p>#{TABLE}")

          assert_equal %w[text-table-body text-table-table], box.element_children.map { it['class'] }
          assert_equal %w[p p], box.at_css('.text-table-body').element_children.map(&:name)
          assert_equal %w[table], box.at_css('.text-table-table').element_children.map(&:name)
        end

        # 表の直前の太字だけの段落はキャプションとして表の側へ入る
        def test_should_move_caption_with_table
          box = wrap("<p>本文。</p><p><strong>評価の範囲</strong></p>#{TABLE}")

          assert_equal %w[p table], box.at_css('.text-table-table').element_children.map(&:name)
          assert_equal '評価の範囲', box.at_css('.text-table-table strong').text
          assert_equal '本文。', box.at_css('.text-table-body').text
        end

        # ラベル付きの表は div.cross-ref-table ごと表の側へ入る
        def test_should_move_cross_ref_table_as_a_whole
          box = wrap('<p>本文。</p><div class="cross-ref-table"><p class="table-caption">表 1</p>' \
                     "#{TABLE}</div>")

          assert_equal %w[cross-ref-table], box.at_css('.text-table-table').element_children.map { it['class'] }
        end

        # 原稿で表を先に書いても、本文を先・表を後に並べる（縦に積んだとき本文から読める）
        def test_should_put_body_before_table_even_when_written_after
          box = wrap("#{TABLE}<p>本文。</p>")

          assert_equal %w[text-table-body text-table-table], box.element_children.map { it['class'] }
        end

        # 表が無ければ包まない（本文だけが全幅で組まれる）
        def test_should_leave_box_without_table_untouched
          box = wrap('<p>本文だけ。</p>')

          assert_equal %w[p], box.element_children.map(&:name)
        end

        # 表が二つなら、最初の表だけを右へ置き、残りは本文の側に入る
        def test_should_move_only_first_table
          box = wrap("<p>本文。</p>#{TABLE}<table><tr><td>b</td></tr></table>")

          assert_equal 'a', box.at_css('.text-table-table td').text
          assert_equal 'b', box.at_css('.text-table-body td').text
        end

        # table-text は表の側を先（左）、本文を後（右）に並べる。キャプションは表と一緒に動く
        def test_should_put_table_before_body_for_table_text
          box = wrap("<p><strong>向きと伸びる方向</strong></p>#{TABLE}<p>一つ目。</p><p>二つ目。</p>",
                     klass: 'table-text')

          assert_equal %w[table-text-table table-text-body], box.element_children.map { it['class'] }
          assert_equal %w[p table], box.at_css('.table-text-table').element_children.map(&:name)
          assert_equal %w[p p], box.at_css('.table-text-body').element_children.map(&:name)
        end

        # 原稿で本文を先に書いても、table-text は表を先に並べる（縦に積んだとき表から読める）
        def test_should_put_table_first_for_table_text_even_when_written_after
          box = wrap("<p>本文。</p>#{TABLE}", klass: 'table-text')

          assert_equal %w[table-text-table table-text-body], box.element_children.map { it['class'] }
        end
      end
    end
  end
end
