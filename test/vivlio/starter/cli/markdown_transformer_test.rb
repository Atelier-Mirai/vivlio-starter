# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../../../../lib/vivlio/starter/cli/pre_process/markdown_transformer'
require_relative '../../../../lib/vivlio/starter/cli/pre_process/markdown_utils'
require_relative '../../../../lib/vivlio/starter/cli/pre_process/cross_reference_processor'

module Vivlio
  module Starter
    module CLI
      module PreProcessCommands
        class MarkdownTransformerTest < Minitest::Test
          include MarkdownTransformer
          include MarkdownUtils
          include CrossReferenceProcessor

          # CaptionedBlockTransformer の private メソッドをテスト用に公開
          def parse_markdown_image_line(line)
            CrossReferenceProcessor::CaptionedBlockTransformer.new('', '', {})
              .send(:parse_image, line)
          end

          def build_plain_figure_html(img_info, caption_text: nil)
            CrossReferenceProcessor::CaptionedBlockTransformer.new('', '', {})
              .send(:build_figure_html, img_info, caption_text)
          end

          # =================================================================
          # extract_code_spans / restore_code_spans
          # =================================================================
          def test_extract_code_spans_basic
            text = 'Hello `code` world'
            protected_text, spans = extract_code_spans(text)

            assert_match(/#{CODE_SPAN_PLACEHOLDER_PREFIX}\d+__/, protected_text)
            refute_includes protected_text, '`code`'
            assert_equal 1, spans.size
            assert_includes spans.values, '`code`'
          end

          def test_extract_code_spans_multiple
            text = 'Use `foo` and `bar` here'
            protected_text, spans = extract_code_spans(text)

            assert_equal 2, spans.size
            assert_includes spans.values, '`foo`'
            assert_includes spans.values, '`bar`'
          end

          def test_restore_code_spans
            text = 'Hello `code` world'
            protected_text, spans = extract_code_spans(text)
            restored = restore_code_spans(protected_text, spans)

            assert_equal text, restored
          end

          def test_extract_and_restore_code_spans_empty
            text = 'No code spans here'
            protected_text, spans = extract_code_spans(text)

            assert_equal text, protected_text
            assert_empty spans
          end

          # マルチバッククォートのインラインコード（内部にバッククォートを含む）を保護する
          def test_extract_code_spans_multi_backtick_inline
            text = 'See ``foo `bar` baz`` here'
            protected_text, spans = extract_code_spans(text)

            assert_equal 1, spans.size
            assert_includes spans.values, '``foo `bar` baz``'
            assert_equal text, restore_code_spans(protected_text, spans)
          end

          # フェンスの開閉がインデント（0-3 スペース）されていても保護する
          def test_extract_code_spans_indented_fence
            text = "before\n   ```ruby\n   p 1\n   ```\nafter\n"
            protected_text, spans = extract_code_spans(text)

            assert_equal 1, spans.size
            assert_includes spans.values.first, 'p 1'
            assert_equal text, restore_code_spans(protected_text, spans)
          end

          # コードフェンス内の `![](...)` 画像記法が後続の変換から保護される（回帰テスト）
          def test_extract_code_spans_protects_image_inside_fence
            text = "text\n```markdown\n![](cover){width=40%}\n```\nafter\n"
            protected_text, spans = extract_code_spans(text)

            refute_includes protected_text, '![](cover)'
            assert_equal text, restore_code_spans(protected_text, spans)
          end

          # インラインコード内の `![](key)` が保護される（回帰テスト）
          def test_extract_code_spans_protects_image_inside_inline_code
            text = '`![](key)` と書くと展開されます'
            protected_text, spans = extract_code_spans(text)

            refute_includes protected_text, '![](key)'
            assert_equal text, restore_code_spans(protected_text, spans)
          end

          # =================================================================
          # detect_language
          # =================================================================
          def test_detect_language_ruby
            assert_equal 'ruby', detect_language('sample.rb')
          end

          def test_detect_language_javascript
            assert_equal 'javascript', detect_language('app.js')
          end

          def test_detect_language_python
            assert_equal 'python', detect_language('script.py')
          end

          def test_detect_language_unknown
            assert_equal 'text', detect_language('file.xyz')
          end

          def test_detect_language_yaml_variants
            assert_equal 'yaml', detect_language('config.yaml')
            assert_equal 'yaml', detect_language('config.yml')
          end

          # =================================================================
          # transform_links_to_footnotes
          # =================================================================
          def test_transform_links_to_footnotes_basic
            md = '[Ruby](https://ruby-lang.org)'
            result = transform_links_to_footnotes(md)

            assert_includes result, '[Ruby](https://ruby-lang.org) [^url1]'
            assert_includes result, '[^url1]: https://ruby-lang.org'
          end

          def test_transform_links_to_footnotes_multiple_same_url
            md = <<~MD
              Visit [Ruby](https://ruby-lang.org) and [Ruby Site](https://ruby-lang.org) again.
            MD
            result = transform_links_to_footnotes(md)

            # 同じURLは同じ脚注IDを共有する
            assert_match(/\[Ruby\].*\[\^url1\]/, result)
            assert_match(/\[Ruby Site\].*\[\^url1\]/, result)
            assert_equal 1, result.scan(/\[\^url1\]:/).size
          end

          def test_transform_links_to_footnotes_preserves_code_spans
            md = 'Check `[not a link](http://example.com)` inline code'
            result = transform_links_to_footnotes(md)

            # コードスパン内のリンク記法は変換されない
            assert_includes result, '`[not a link](http://example.com)`'
            refute_includes result, '[^url'
          end

          def test_transform_links_to_footnotes_image_not_converted
            md = '![alt](https://example.com/image.png)'
            result = transform_links_to_footnotes(md)

            # 画像記法は変換されない
            assert_equal md, result.strip
          end

          # =================================================================
          # normalize_book_card_md
          # =================================================================
          def test_normalize_book_card_md_adds_blank_after_image
            md = <<~MD
              ![cover](cover.jpg)
              **Title**
            MD
            result = normalize_book_card_md(md)

            lines = result.split("\n")
            # 画像行の直後に空行が挿入される
            assert_equal '', lines[1]
          end

          def test_normalize_book_card_md_adds_blank_after_bold
            md = <<~MD
              **Title**
              Description text
            MD
            result = normalize_book_card_md(md)

            lines = result.split("\n")
            # 太字行の直後に空行が挿入される
            assert_equal '', lines[1]
          end

          # =================================================================
          # pipe_table_to_html
          # =================================================================
          def test_pipe_table_to_html_basic
            md = <<~MD
              | Header1 | Header2 |
              | ------- | ------- |
              | Cell1   | Cell2   |
            MD
            result = pipe_table_to_html(md)

            assert_includes result, '<table>'
            assert_includes result, '<th>Header1</th>'
            assert_includes result, '<th>Header2</th>'
            assert_includes result, '<td>Cell1</td>'
            assert_includes result, '<td>Cell2</td>'
            assert_includes result, '</table>'
          end

          def test_pipe_table_to_html_with_code
            md = <<~MD
              | Code | Description |
              | ---- | ----------- |
              | `foo` | A foo value |
            MD
            result = pipe_table_to_html(md)

            # 実装では <code> 変換後に HTML エスケープが適用されるため、
            # <code> タグ自体がエスケープされる（既存動作）
            assert_includes result, '&lt;code&gt;foo&lt;/code&gt;'
          end

          def test_pipe_table_to_html_invalid_returns_nil
            md = 'Not a table'
            result = pipe_table_to_html(md)

            assert_nil result
          end

          # =================================================================
          # convert_container_blocks
          # =================================================================
          def test_convert_container_blocks_basic
            content = <<~MD
              ::: {.table-rotate}
              | A | B |
              | - | - |
              | 1 | 2 |
              :::
            MD
            converted, opened, closed = convert_container_blocks(content, class_name: 'table-rotate')

            assert_equal 1, opened
            assert_equal 1, closed
            assert_includes converted, '<div class="table-rotate">'
            assert_includes converted, '</div>'
          end

          def test_convert_container_blocks_with_scale_param
            content = <<~MD
              ::: {.table-rotate scale=60%}
              | A | B |
              :::
            MD
            converted, _, _ = convert_container_blocks(content, class_name: 'table-rotate')

            assert_includes converted, '--table-rotate-scale:60%;'
          end

          def test_convert_container_blocks_with_shift_y_param
            content = <<~MD
              ::: {.table-rotate shift-y=20%}
              | A | B |
              :::
            MD
            converted, _, _ = convert_container_blocks(content, class_name: 'table-rotate')

            assert_includes converted, '--table-rotate-shift-y:+20%;'
          end

          def test_convert_container_blocks_ignores_other_classes
            content = <<~MD
              ::: {.other-class}
              Some content
              :::
            MD
            converted, opened, closed = convert_container_blocks(content, class_name: 'table-rotate')

            assert_equal 0, opened
            assert_equal 0, closed
            # 他のクラスはそのまま残る
            assert_includes converted, '::: {.other-class}'
          end

          # =================================================================
          # extract_caption_label
          # =================================================================
          def test_extract_caption_label_manual_id
            line = '** サンプルコード @sample-code **'
            result = extract_caption_label(line)

            assert result
            assert_equal 'サンプルコード', result[:title]
            assert_equal 'sample-code', result[:id]
            refute result[:auto]
          end

          def test_extract_caption_label_auto_id
            line = '** 自動ID付きコード @auto **'
            result = extract_caption_label(line)

            assert result
            assert_equal '自動ID付きコード', result[:title]
            assert_equal 'auto', result[:id]
            assert result[:auto]
          end

          def test_extract_caption_label_omakase_id
            line = '** おまかせID @omakase **'
            result = extract_caption_label(line)

            assert result
            assert result[:auto]
          end

          def test_extract_caption_label_no_match
            line = 'Regular text without caption'
            result = extract_caption_label(line)

            assert_nil result
          end

          # =================================================================
          # detect_block_type
          # =================================================================
          def test_detect_block_type_code_block
            lines = [
              '** Caption @id **',
              '',
              '```ruby',
              'puts "hello"',
              '```'
            ]
            result = detect_block_type(lines, 0)

            assert_equal :list, result
          end

          def test_detect_block_type_table
            lines = [
              '** Caption @id **',
              '',
              '| A | B |',
              '| - | - |',
              '| 1 | 2 |'
            ]
            result = detect_block_type(lines, 0)

            assert_equal :table, result
          end

          def test_detect_block_type_figure
            lines = [
              '** Caption @id **',
              '',
              '![alt](image.png)'
            ]
            result = detect_block_type(lines, 0)

            assert_equal :fig, result
          end

          def test_detect_block_type_unknown
            lines = [
              '** Caption @id **',
              '',
              'Just regular text'
            ]
            result = detect_block_type(lines, 0)

            assert_nil result
          end

          # =================================================================
          # parse_markdown_image_line
          # =================================================================
          def test_parse_markdown_image_line_basic
            line = '![alt text](image.png)'
            result = parse_markdown_image_line(line)

            assert result
            assert_equal 'alt text', result[:alt]
            assert_equal 'image.png', result[:src]
            assert_nil result[:align]
            assert_nil result[:width]
          end

          def test_parse_markdown_image_line_with_attrs
            line = '![alt](image.png){width=50% align=center}'
            result = parse_markdown_image_line(line)

            assert result
            assert_equal '50%', result[:width]
            assert_equal 'center', result[:align]
          end

          def test_parse_markdown_image_line_with_classes
            line = '![alt](image.png){.shadow .rounded}'
            result = parse_markdown_image_line(line)

            assert result
            assert_includes result[:classes], 'shadow'
            assert_includes result[:classes], 'rounded'
          end

          def test_parse_markdown_image_line_invalid
            line = 'Not an image'
            result = parse_markdown_image_line(line)

            assert_nil result
          end

          # =================================================================
          # build_plain_figure_html
          # =================================================================
          def test_build_plain_figure_html_basic
            img_info = { alt: 'Test', src: 'test.png', align: nil, width: nil, classes: [] }
            html = build_plain_figure_html(img_info, caption_text: nil)

            assert_includes html, '<figure>'
            assert_includes html, '<img src="test.png" alt="Test">'
            assert_includes html, '</figure>'
            refute_includes html, '<figcaption>'
          end

          def test_build_plain_figure_html_with_caption
            img_info = { alt: 'Test', src: 'test.png', align: nil, width: nil, classes: [] }
            html = build_plain_figure_html(img_info, caption_text: 'My Caption')

            assert_includes html, '<figcaption>My Caption</figcaption>'
          end

          def test_build_plain_figure_html_with_width
            img_info = { alt: 'Test', src: 'test.png', align: nil, width: '50%', classes: [] }
            html = build_plain_figure_html(img_info, caption_text: nil)

            assert_includes html, 'style="width: 50%"'
          end

          def test_build_plain_figure_html_with_align
            img_info = { alt: 'Test', src: 'test.png', align: 'center', width: nil, classes: [] }
            html = build_plain_figure_html(img_info, caption_text: nil)

            assert_includes html, 'class="align-center"'
          end

          # =================================================================
          # collect_labels
          # =================================================================
          def test_collect_labels_single_code_block
            content = <<~MD
              ** サンプルコード @sample **

              ```ruby
              puts "hello"
              ```
            MD
            result = collect_labels(content, 'test.md', '1')

            assert_equal 1, result[:labels].size
            label = result[:labels].first
            assert_equal 'sample', label.id
            assert_equal :list, label.type
            assert_equal '1-1', label.number
            assert_empty result[:errors]
          end

          def test_collect_labels_multiple_types
            content = <<~MD
              ** コード @code1 **

              ```ruby
              code
              ```

              ** 表 @table1 **

              | A | B |
              | - | - |

              ** 図 @fig1 **

              ![image](img.png)
            MD
            result = collect_labels(content, 'test.md', '2')

            assert_equal 3, result[:labels].size
            types = result[:labels].map(&:type)
            assert_includes types, :list
            assert_includes types, :table
            assert_includes types, :fig
          end

          def test_collect_labels_ignores_caption_in_code_block
            content = <<~MD
              ```markdown
              ** これはコード内のキャプション @fake **
              ```
            MD
            result = collect_labels(content, 'test.md', '1')

            assert_empty result[:labels]
          end

          # =================================================================
          # replace_references
          # =================================================================
          def test_replace_references_basic
            label = Label.new('sample', :list, '1', '1-1', 'Sample', 'test.md', 5, false)
            labels_map = { 'sample' => label }

            content = 'See @sample for details.'
            result = replace_references(content, labels_map, 'test.md')

            assert_includes result[:content], '<a href="test.html#sample"'
            assert_includes result[:content], 'リスト 1-1'
            assert_empty result[:errors]
          end

          def test_replace_references_undefined_label
            labels_map = {}

            content = 'See @undefined for details.'
            result = replace_references(content, labels_map, 'test.md')

            assert_includes result[:content], '@undefined'
            assert_equal 1, result[:errors].size
            assert_match(/未定義のラベルID.*@undefined/, result[:errors].first)
          end

          def test_replace_references_preserves_reserved_ids
            labels_map = {}

            content = '手動IDは @id、自動IDは @auto または @omakase を使います。'
            result = replace_references(content, labels_map, 'test.md')

            # 予約IDはそのまま残り、エラーにもならない
            assert_includes result[:content], '@id'
            assert_includes result[:content], '@auto'
            assert_includes result[:content], '@omakase'
            assert_empty result[:errors]
          end

          def test_replace_references_preserves_code_blocks
            label = Label.new('sample', :list, '1', '1-1', 'Sample', 'test.md', 5, false)
            labels_map = { 'sample' => label }

            content = <<~MD
              ```ruby
              # @sample はコード内なので変換されない
              ```
            MD
            result = replace_references(content, labels_map, 'test.md')

            assert_includes result[:content], '# @sample'
            refute_includes result[:content], '<a href='
          end

          def test_replace_references_preserves_inline_code
            label = Label.new('sample', :list, '1', '1-1', 'Sample', 'test.md', 5, false)
            labels_map = { 'sample' => label }

            content = 'Use `@sample` in your code.'
            result = replace_references(content, labels_map, 'test.md')

            assert_includes result[:content], '`@sample`'
          end

          # =================================================================
          # build_labels_map_with_duplicates_check
          # =================================================================
          def test_build_labels_map_no_duplicates
            label1 = Label.new('id1', :list, '1', '1-1', 'Title1', 'a.md', 1, false)
            label2 = Label.new('id2', :table, '1', '1-1', 'Title2', 'b.md', 2, false)

            result = build_labels_map_with_duplicates_check([label1, label2])

            assert_equal 2, result[:labels_map].size
            assert_empty result[:duplicates]
          end

          def test_build_labels_map_with_duplicates
            label1 = Label.new('same-id', :list, '1', '1-1', 'Title1', 'a.md', 1, false)
            label2 = Label.new('same-id', :table, '2', '2-1', 'Title2', 'b.md', 2, false)

            result = build_labels_map_with_duplicates_check([label1, label2])

            assert_equal 1, result[:labels_map].size
            assert_equal 1, result[:duplicates].size
            assert_match(/same-id.*重複/, result[:duplicates].first)
          end
        end
      end
    end
  end
end
