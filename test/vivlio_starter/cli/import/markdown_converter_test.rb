# frozen_string_literal: true

require_relative '../../../test_helper'
require 'vivlio_starter/cli/import/markdown_converter'
require 'vivlio_starter/cli/common'

module VivlioStarter
  module CLI
    module Import
      class MarkdownConverterTest < Minitest::Test
        # ================================================================
        # img タグ変換テスト
        # ================================================================
        def test_convert_img_tags_to_markdown
          input = '<img src="./images/chapter/sample.png">'
          expected = '![](sample.webp)'
          assert_equal expected, MarkdownConverter.convert_img_tags(input)
        end

        def test_convert_img_tags_with_nested_path
          input = '<img src="./images/01-intro/figure1.jpg">'
          expected = '![](figure1.webp)'
          assert_equal expected, MarkdownConverter.convert_img_tags(input)
        end

        def test_convert_img_tags_case_insensitive
          input = '<img src="./images/test/IMAGE.PNG">'
          expected = '![](IMAGE.webp)'
          assert_equal expected, MarkdownConverter.convert_img_tags(input)
        end

        # ================================================================
        # フェンス記法変換テスト
        # ================================================================
        def test_convert_abstract_block
          input = "[abstract]\nこれは概要です。\n[/abstract]"
          result = MarkdownConverter.convert_fence_blocks(input)
          assert_includes result, ':::{.chapter-lead}'
          assert_includes result, 'これは概要です。'
          assert_includes result, ':::'
        end

        def test_convert_tip_block
          input = "[tip]\nヒント内容\n[/tip]"
          result = MarkdownConverter.convert_fence_blocks(input)
          assert_includes result, ':::{.tip}'
        end

        def test_convert_note_block
          input = "[note]\n注釈内容\n[/note]"
          result = MarkdownConverter.convert_fence_blocks(input)
          assert_includes result, ':::{.note}'
        end

        def test_convert_notice_block
          input = "[notice]\n警告内容\n[/notice]"
          result = MarkdownConverter.convert_fence_blocks(input)
          assert_includes result, ':::{.notice}'
        end

        def test_convert_centering_block
          input = "[centering]\n中央揃えテキスト\n[/centering]"
          result = MarkdownConverter.convert_fence_blocks(input)
          assert_includes result, ':::{.centering}'
        end

        def test_convert_flushright_block
          input = "[flushright]\n右揃えテキスト\n[/flushright]"
          result = MarkdownConverter.convert_fence_blocks(input)
          assert_includes result, ':::{.text-right}'
        end

        # ================================================================
        # column ブロック変換テスト
        # ================================================================
        def test_convert_column_block_without_title
          input = "[column]\nコラム本文\n[/column]"
          result = MarkdownConverter.convert_fence_blocks(input)
          assert_includes result, ':::{.column}'
          assert_includes result, 'コラム本文'
        end

        def test_convert_column_block_with_title
          input = "[column] コラムタイトル\nコラム本文\n[/column]"
          result = MarkdownConverter.convert_fence_blocks(input)
          assert_includes result, ':::{.column}'
          assert_includes result, '**コラムタイトル**'
          assert_includes result, 'コラム本文'
        end

        def test_convert_flushright_blocks_independently
          input = <<~MD
            [flushright]
            早乙女遙香 さん
            [/flushright]

            [flushright]
            穂髙未來 さん
            [/flushright]
          MD

          expected = <<~MD
            :::{.text-right}
            早乙女遙香 さん
            :::


            :::{.text-right}
            穂髙未來 さん
            :::

          MD

          assert_equal expected, MarkdownConverter.convert_fence_blocks(input)
        end

        # ================================================================
        # quote ブロック変換テスト
        # ================================================================
        def test_convert_quote_block
          input = "[quote]\n引用文\n[/quote]\n"
          result = MarkdownConverter.convert_quote_blocks(input)
          assert_includes result, '> 引用文'
        end

        def test_convert_multiline_quote_block
          input = "[quote]\n引用文1\n引用文2\n[/quote]\n"
          result = MarkdownConverter.convert_quote_blocks(input)
          assert_includes result, '> 引用文1'
          assert_includes result, '> 引用文2'
        end

        # ================================================================
        # コードブロックキャプション変換テスト
        # ================================================================
        def test_convert_code_caption_css
          input = "<span class=\"caption\">▼styles.css</span>\n```"
          expected = '```css:styles.css'
          assert_equal expected, MarkdownConverter.convert_code_captions(input)
        end

        def test_convert_code_caption_js
          input = "<span class=\"caption\">▼app.js</span>\n```"
          expected = '```js:app.js'
          assert_equal expected, MarkdownConverter.convert_code_captions(input)
        end

        def test_convert_code_caption_no_extension
          input = "<span class=\"caption\">▼Makefile</span>\n```"
          expected = '```text:Makefile'
          assert_equal expected, MarkdownConverter.convert_code_captions(input)
        end

        # ================================================================
        # 画像パス正規化テスト
        # ================================================================
        def test_normalize_image_paths
          input = '![代替テキスト](./images/chapter/figure.png)'
          expected = '![代替テキスト](figure.webp)'
          assert_equal expected, MarkdownConverter.normalize_image_paths(input)
        end

        def test_normalize_image_paths_with_brackets_in_alt
          input = '![図[1]の説明](./images/chapter/figure.jpg)'
          expected = '![図[1]の説明](figure.webp)'
          assert_equal expected, MarkdownConverter.normalize_image_paths(input)
        end

        # ================================================================
        # dl/dt/dd 変換テスト
        # ================================================================
        def test_convert_definition_lists
          input = '<dl><dt>用語</dt><dd>説明文</dd></dl>'
          result = MarkdownConverter.convert_definition_lists(input)
          assert_includes result, '- **用語**'
          assert_includes result, '説明文'
        end

        def test_convert_definition_lists_multiple
          input = '<dl><dt>用語1</dt><dd>説明1</dd><dt>用語2</dt><dd>説明2</dd></dl>'
          result = MarkdownConverter.convert_definition_lists(input)
          assert_includes result, '- **用語1**'
          assert_includes result, '- **用語2**'
        end

        # ================================================================
        # HTML テーブル変換テスト
        # ================================================================
        def test_convert_html_tables
          input = <<~HTML
            <div class="table"><table><tr><th>ヘッダ1</th><th>ヘッダ2</th></tr><tr><td>データ1</td><td>データ2</td></tr></table></div>
          HTML
          result = MarkdownConverter.convert_html_tables(input)
          assert_includes result, '| ヘッダ1 | ヘッダ2 |'
          assert_includes result, '| --- | --- |'
          assert_includes result, '| データ1 | データ2 |'
        end

        def test_convert_html_tables_with_caption
          input = <<~HTML
            <div class="table"><p class="caption">表1: サンプル</p><table><tr><th>A</th></tr><tr><td>B</td></tr></table></div>
          HTML
          result = MarkdownConverter.convert_html_tables(input)
          assert_includes result, '**表1: サンプル**'
        end

        # ================================================================
        # ルビ記法変換テスト
        # ================================================================
        def test_convert_ruby_notation_hiragana
          input = '漢字（かんじ）'
          expected = '{漢字|かんじ}'
          assert_equal expected, MarkdownConverter.convert_ruby_notation(input)
        end

        def test_convert_ruby_notation_katakana
          input = '音楽（オンガク）'
          expected = '{音楽|オンガク}'
          assert_equal expected, MarkdownConverter.convert_ruby_notation(input)
        end

        def test_convert_ruby_notation_multiple
          input = '日本（にほん）の文化（ぶんか）'
          expected = '{日本|にほん}の{文化|ぶんか}'
          assert_equal expected, MarkdownConverter.convert_ruby_notation(input)
        end

        # ================================================================
        # コードブロック言語推定テスト
        # ================================================================
        def test_detect_lang_shell_with_dollar
          code = "$ npm install\n$ npm start"
          assert_equal 'zsh', MarkdownConverter.detect_lang(code)
        end

        def test_detect_lang_shell_with_percent
          code = "% ls -la\n% cd .."
          assert_equal 'zsh', MarkdownConverter.detect_lang(code)
        end

        def test_detect_code_block_languages_adds_lang
          input = "```\nputs 'hello'\n```"
          result = MarkdownConverter.detect_code_block_languages(input)
          # 言語指定が追加されていることを確認（具体的な言語は Rouge の推定結果による）
          refute_equal input, result
          assert_match(/^```\w+\n/, result)
        end

        # ================================================================
        # 統合テスト: transform メソッド
        # ================================================================
        def test_transform_full_conversion
          input = <<~MD
            # テスト章

            [abstract]
            これは概要です。
            [/abstract]

            <img src="./images/test/sample.png">

            漢字（かんじ）のテスト
          MD

          result = MarkdownConverter.transform(input)

          assert_includes result, ':::{.chapter-lead}'
          assert_includes result, '![](sample.webp)'
          assert_includes result, '{漢字|かんじ}'
        end

        def test_transform_preserves_normal_text
          input = "これは通常のテキストです。\n\n変換対象ではありません。"
          result = MarkdownConverter.transform(input)
          assert_includes result, 'これは通常のテキストです。'
          assert_includes result, '変換対象ではありません。'
        end

        def test_transform_decodes_html_entities
          input = '&lt;div&gt; &amp; &quot;test&quot;'
          result = MarkdownConverter.transform(input)
          assert_includes result, '<div>'
          assert_includes result, '&'
          assert_includes result, '"test"'
        end
      end
    end
  end
end
