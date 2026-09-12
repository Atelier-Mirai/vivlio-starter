# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require_relative '../../../../lib/vivlio_starter/cli/post_process/definition_list_converter'

module VivlioStarter
  module CLI
    module PostProcessCommands
      # 定義リストは VFM が組んだ HTML を受け取ってから <dl> にする。
      # Markdown 段階で HTML 化していた頃は、中のルビ（VFM）と索引（ビルド Step 4）が
      # 生 HTML に隠れて効かず、紙面に記法がそのまま出ていた。
      class DefinitionListConverterTest < Minitest::Test
        # hardLineBreaks: true の VFM は、定義リストのブロックを 1 つの <p> にまとめ、
        # 行を <br> で区切って出す
        MARK = DefinitionListConverter::CONTINUATION_MARK

        def convert(inner_html)
          entries = DefinitionListConverter.parse_entries(inner_html)
          entries && DefinitionListConverter.build_dl(entries)
        end

        def test_should_build_dl_from_terms_and_definitions
          html = convert('用語1<br>: 用語1の説明<br>用語2<br>: 用語2の説明')

          assert_includes html, '<dl class="def-list">', '索引・奥付の <dl> と衝突しない class を付ける'
          assert_includes html, '<dt>用語1</dt><dd>用語1の説明</dd>'
          assert_includes html, '<dt>用語2</dt><dd>用語2の説明</dd>'
        end

        def test_should_make_multiple_dd_for_one_term
          html = convert('Ruby<br>: 開発者は Matz です。<br>: 宝石の名前。')

          assert_equal 2, html.scan('<dd>').size
          assert_includes html, '<dd>宝石の名前。</dd>'
        end

        # 字下げした継続行は、前処理が置く印（WORD JOINER）で見分ける。
        # VFM の出力では行頭の空白が落ちており、字下げの有無はこれでしか分からない
        def test_should_join_marked_continuation_with_break
          html = convert("Ruby<br>: 1行目の説明。<br>#{MARK}2行目の説明。")

          assert_includes html, '<dd>1行目の説明。<br>2行目の説明。</dd>'
          assert_equal 1, html.scan('<dd>').size
          refute_includes html, MARK, '印は出力に残さない'
        end

        # 印が無ければ新しい用語。同じ「次が定義行」でも、字下げの有無で行き先が変わる
        def test_should_tell_term_from_continuation_by_mark
          html = convert("用語A<br>: 説明A<br>#{MARK}続きの行<br>用語B<br>: 説明B")

          assert_includes html, '<dd>説明A<br>続きの行</dd>'
          assert_includes html, '<dt>用語B</dt><dd>説明B</dd>'
        end

        # VFM が組み終えた記法（ルビなど）は、そのまま <dd> の中へ入る
        def test_should_keep_markup_produced_by_vfm
          html = convert('用語<br>: <ruby>翳<rt>かざ</rt></ruby>すと開きます。')

          assert_includes html, '<dd><ruby>翳<rt>かざ</rt></ruby>すと開きます。</dd>'
        end

        def test_should_leave_plain_paragraph_untouched
          assert_nil convert('これは普通の段落です。<br>次の行も普通の文章です。')
        end

        # 用語行を伴わない「: 」だけの段落は定義リストにしない
        def test_should_require_a_term_before_definition
          assert_nil convert(': 説明だけの行<br>: もう一行')
        end

        def test_should_ignore_colon_without_following_space
          assert_nil convert('注意:次の行<br>ここは地の文です。')
        end

        # ================================================================
        # ファイル単位
        # ================================================================
        def test_should_rewrite_only_definition_paragraphs_in_file
          Dir.mktmpdir('def_list_test') do |dir|
            path = File.join(dir, 'chap.html')
            File.write(path, <<~HTML, encoding: 'utf-8')
              <html><body>
              <p>用語<br>: 説明です。</p>
              <p>普通の段落です。</p>
              <pre><code>用語
              : コードの中なので触らない
              </code></pre>
              </body></html>
            HTML

            DefinitionListConverter.convert!(path)
            result = File.read(path, encoding: 'utf-8')

            assert_includes result, '<dl class="def-list"><dt>用語</dt><dd>説明です。</dd></dl>'
            assert_includes result, '<p>普通の段落です。</p>'
            assert_includes result, ': コードの中なので触らない'
          end
        end
      end
    end
  end
end
