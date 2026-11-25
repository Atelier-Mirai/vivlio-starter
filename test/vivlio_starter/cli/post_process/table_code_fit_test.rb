# frozen_string_literal: true

require 'minitest/autorun'
require 'tempfile'
require_relative '../../../../lib/vivlio_starter/cli/post_process'

module VivlioStarter
  module CLI
    module PostProcessCommands
      # fit_table_codes! は、表の中のコードに二つの印を付ける。
      # - vs-one-line: 一列目のコードのうち、一行にしてもほかの列の幅が残るもの（PDF で一行に保つ）。
      #   列ごとに残すのは、中身の長さと「16 字を列の数で分けた幅」の小さいほう。
      # - vs-break-anywhere: 列の最小の幅の合計が版面を越える表で、長い語を含むコード（どこでも折る）。
      class TableCodeFitTest < Minitest::Test
        def apply(html, line:)
          Tempfile.create(['vs_table_code_fit_test_', '.html']) do |f|
            f.write("<html><body>#{html}</body></html>")
            f.flush
            PostProcessCommands.fit_table_codes!(f.path, line:)
            return File.read(f.path, encoding: 'utf-8')
          end
        end

        # 43.7 字は A4 の本の 1 行。二列目の中身（11.4 字）と余白を残しても、23.2 字のコードは入る
        def test_should_mark_short_code_in_first_column_only
          out = apply(<<~HTML, line: 43.7)
            <table><tbody>
              <tr><td><code>add_option("enemy", :dragon, "ドラゴン")</code></td><td><code>save_text(key, text)</code></td></tr>
            </tbody></table>
          HTML

          assert_includes out, '<code class="vs-one-line">add_option("enemy", :dragon, "ドラゴン")</code>'
          assert_includes out, '<code>save_text(key, text)</code>'
        end

        # 残りの幅（43.7 − 余白 − 16 字 ≒ 26 字）を越える 36.6 字のコードは、折り返しに任せる
        def test_should_leave_code_wider_than_room
          out = apply(<<~HTML, line: 43.7)
            <table><tbody>
              <tr><td>何も描かれない</td><td>パスを作っただけ</td></tr>
              <tr><td><code>TypeError: can't access property "getContext", canvas is null</code></td><td>要素より先にスクリプトが動いている</td></tr>
            </tbody></table>
          HTML

          refute_includes out, 'vs-one-line'
        end

        # 37 字は B5 の本の 1 行。三列の表で、ほかの二列に 8 字と 11.4 字（ocr_corrections.yml）を残すと 15.5 字しか残らない
        def test_should_leave_code_that_would_squeeze_other_columns
          out = apply(<<~HTML, line: 37)
            <table><tbody>
              <tr><td><code>PDF から文字を一つも取り出せませんでした</code></td><td>スキャン PDF を Standard Mode で読んだ</td><td><code>vivlio-starter-pdf</code> を入れて Enhanced Mode（OCR）で読む</td></tr>
              <tr><td><code>PDF が見つかりません</code></td><td><code>/</code> を含まない指定は <code>sources/</code> の中だけを探す</td><td><code>ocr_corrections.yml</code> にパターンを追加</td></tr>
            </tbody></table>
          HTML

          refute_includes out, '<code class="vs-one-line">PDF から'
          assert_includes out, '<code class="vs-one-line">PDF が見つかりません</code>'
        end

        # 30.6 字のタグを一行にすると、二列目の説明が 8 字ほどに細る。短いタグだけを一行にする
        def test_should_keep_room_for_description_column
          out = apply(<<~HTML, line: 43.7)
            <table><tbody>
              <tr><td><code>&lt;meta name="viewport" content="width=device-width"&gt;</code></td><td>スマートフォンでも、画面の幅に合わせて表示する</td></tr>
              <tr><td><code>&lt;link rel="stylesheet" href="…"&gt;</code></td><td>CSS のファイルを読み込む</td></tr>
            </tbody></table>
          HTML

          refute_includes out, %(<code class="vs-one-line">&lt;meta)
          assert_includes out, %(<code class="vs-one-line">&lt;link)
        end

        # ほかの列に長い英字の語（10.2 字・12.6 字）があると、一列目を一行にする幅が残らない
        def test_should_leave_table_that_would_overflow_with_one_line_codes
          out = apply(<<~HTML, line: 37)
            <table><tbody>
              <tr><td><code>catalog.yml が見つかりません</code></td><td>指定がずれている</td><td>ルートを指定する</td></tr>
              <tr><td><code>config/book.yml の値が更新されない</code></td><td><code>backcover_pdffile</code> の指定</td><td><code>covers/frontcover_master.png</code> を置き換える</td></tr>
            </tbody></table>
          HTML

          refute_includes out, 'vs-one-line'
        end

        def test_should_leave_code_blocks_and_text_outside_tables
          out = apply(<<~HTML, line: 43.7)
            <p><code>vs build</code></p>
            <table><tbody><tr><td><pre><code>puts 1</code></pre></td><td>例</td></tr></tbody></table>
          HTML

          refute_includes out, 'vs-one-line'
        end

        # コードの半角は全角の 3/5、日本語は 1 字
        def test_should_measure_code_width
          assert_in_delta 23.2, PostProcessCommands.code_width_em('add_option("enemy", :dragon, "ドラゴン")')
          assert_in_delta 20.4, PostProcessCommands.code_width_em('PDF から文字を一つも取り出せませんでした')
        end

        # 英字は空白・`/`・`-` の後ろで折れ、日本語は字ごとに折れる
        def test_should_measure_longest_unbreakable_word
          assert_in_delta 12.6, PostProcessCommands.longest_unbreakable_em('covers/frontcover_master.png を置き換える')
          assert_in_delta 4.8, PostProcessCommands.longest_unbreakable_em('vivlio-starter-pdf を入れる')
          assert_in_delta 1.0, PostProcessCommands.longest_unbreakable_em('原因')
        end

        # 長い語（28.8 字）と `covers/frontcover_master.png`（12.6 字）で、37 字の版面を越える。
        # いちばん長い語を含むコードだけを、どこでも折れるようにする
        def test_should_release_longest_code_when_table_overflows
          out = apply(<<~HTML, line: 37)
            <table><tbody>
              <tr><td><code>cp a.rb pneumonoultramicroscopicsilicovolcanoconiosis.rb</code></td><td><code>covers/frontcover_master.png</code> を置き換える</td></tr>
            </tbody></table>
          HTML

          assert_includes out, '<code class="vs-break-anywhere">cp a.rb pneumono'
          assert_includes out, '<code>covers/frontcover_master.png</code>'
        end

        # A4 の版面（43.7 字）なら収まるので、語の途中では折らない
        def test_should_keep_long_word_when_table_fits
          out = apply(<<~HTML, line: 43.7)
            <table><tbody>
              <tr><td><code>cp a.rb pneumonoultramicroscopicsilicovolcanoconiosis.rb</code></td><td>長い名前のファイルを写す</td></tr>
            </tbody></table>
          HTML

          refute_includes out, 'vs-break-anywhere'
        end
      end
    end
  end
end
