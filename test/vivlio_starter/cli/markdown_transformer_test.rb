# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require_relative '../../../lib/vivlio_starter/cli/pre_process/markdown_transformer'
require_relative '../../../lib/vivlio_starter/cli/pre_process/markdown_utils'
require_relative '../../../lib/vivlio_starter/cli/pre_process/cross_reference_processor'

module VivlioStarter
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

        # 入れ子（後から退避したインラインの original が先のフェンスのプレースホルダを
        # 内包する）でも、復元が LIFO のためプレースホルダが残留しない（回帰テスト）。
        # FIFO だと `__VS_CODE_SPAN__0__` が本文へ漏れ出す。
        def test_restore_code_spans_lifo_for_nested_placeholders
          # 行を跨ぐバッククォート対が、フェンス置換後のプレースホルダを巻き込む構図
          text = "`a\n```ruby\nx\n```\nb`\n"
          protected_text, spans = extract_code_spans(text)

          assert_operator spans.size, :>=, 2, '入れ子（フェンス＋それを内包するインライン）が成立する前提'
          restored = restore_code_spans(protected_text, spans)

          assert_equal text, restored, 'LIFO 復元で入れ子のプレースホルダも完全に巻き戻る'
          refute_match(/__VS_CODE_SPAN__\d+__/, restored, 'プレースホルダが本文へ漏れ出さない')
        end

        # 章原稿規模（フェンス多数＋行跨ぎインライン）でも往復が完全一致する（回帰テスト）。
        def test_extract_and_restore_code_spans_round_trip_identity
          text = +''
          5.times { |i| text << "段落#{i} `inline#{i}`\n\n```\ncode #{i}\n```\n\n" }
          # 行跨ぎのバッククォート対でプレースホルダ巻き込みを誘発
          text << "`open\n```\nfenced\n```\nclose`\n"

          protected_text, spans = extract_code_spans(text)

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

        # 説明部の連続行は hardLineBreaks に合わせてハード改行（末尾2スペース→<br>）になる
        def test_normalize_book_card_md_hard_breaks_description_lines
          md = <<~MD
            **Title**
            高橋征義 著
            Rubyを楽しく学べる入門書。
          MD
          result = normalize_book_card_md(md)

          assert_includes result, "高橋征義 著  \n", '著者行に Markdown ハード改行（末尾2スペース）が付く'
          # 実際に <br> へ描画されることまで確認
          html = MarkdownUtils.render_markdown_to_html(result)
          assert_match(%r{高橋征義 著<br\s*/?>}, html, '著者と説明が <br> で改行される')
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
        # convert_definition_lists
        # =================================================================
        def test_convert_definition_lists_basic
          md = "用語1\n: 用語1の説明\n用語2\n: 用語2の説明\n"
          out = convert_definition_lists(md)

          assert_includes out, '<dl class="def-list">', '索引/奥付と衝突しない class 付きの dl になる'
          assert_includes out, '<dt>用語1</dt>'
          assert_includes out, '<dd>用語1の説明</dd>'
          assert_includes out, '<dt>用語2</dt>'
          assert_includes out, '<dd>用語2の説明</dd>'
        end

        def test_convert_definition_lists_multiple_dd_and_continuation
          md = "Ruby\n: 開発者は Matz です。\n  動的型付けが特徴です。\n: 宝石の名前。\n"
          out = convert_definition_lists(md)

          # 複数の : 行 → 複数 <dd>
          assert_equal 2, out.scan('<dd>').size, '用語に対し定義 2 つぶんの <dd> ができる'
          # 字下げ継続行は直前の <dd> に取り込まれる
          assert_includes out, '動的型付けが特徴です。'
          assert_includes out, '<dd>宝石の名前。</dd>'
        end

        def test_convert_definition_lists_continuation_is_hard_break
          md = "Ruby\n: 1行目の説明。\n  2行目の説明。\n"
          out = convert_definition_lists(md)

          # 本書の hardLineBreaks: true に合わせ、説明内の改行は <br> になる
          assert_includes out, '<br', '複数行の説明は <br> で改行される'
          assert_includes out, '1行目の説明。'
          assert_includes out, '2行目の説明。'
        end

        def test_convert_definition_lists_renders_inline_code
          md = "Ruby\n: `<ruby>` は振り仮名のタグです。\n"
          out = convert_definition_lists(md)

          assert_includes out, '<code>&lt;ruby&gt;</code>', '定義内のインラインコードは Kramdown が処理する'
        end

        def test_convert_definition_lists_skips_code_fence
          md = "```markdown\n用語X\n: コード例なので変換しない\n```\n"
          out = convert_definition_lists(md)

          refute_includes out, '<dl', 'コードフェンス内の定義リスト記法は変換しない'
          assert_includes out, ': コード例なので変換しない'
        end

        def test_convert_definition_lists_leaves_plain_prose
          md = "これは普通の段落です。\n次の行も普通の文章です。\n"
          out = convert_definition_lists(md)

          assert_equal md, out, '定義行（: ）を伴わない地の文は変換されない'
        end

        # =================================================================
        # convert_standalone_spacing（単独行 {.aki} → @vspace）
        # =================================================================
        def test_convert_standalone_spacing_aki_to_vspace
          md = "前の段落。\n\n{.aki}\n次の段落。\n"
          out = convert_standalone_spacing(md)

          assert_equal "前の段落。\n\n@vspace:1lh\n\n次の段落。\n", out
        end

        def test_convert_standalone_spacing_aki2_to_vspace
          md = "前。\n\n{.aki2}\n次。\n"
          out = convert_standalone_spacing(md)

          assert_equal "前。\n\n@vspace:2lh\n\n次。\n", out
        end

        def test_convert_standalone_spacing_keeps_trailing_marker
          md = "文章の終わり。{.aki}\n"
          out = convert_standalone_spacing(md)

          assert_equal md, out, '段落末（同一行末尾）の {.aki} はクラス付与用なので変換しない'
        end

        def test_convert_standalone_spacing_keeps_marker_attached_to_prev_line
          md = "本文\n{.aki}\n"
          out = convert_standalone_spacing(md)

          assert_equal md, out, '直前が空行でない（本文に続く）{.aki} は trailing 添付なので変換しない'
        end

        def test_convert_standalone_spacing_skips_code_fence
          md = "```\n{.aki}\n```\n"
          out = convert_standalone_spacing(md)

          assert_equal md, out, 'コードフェンス内の {.aki} は変換しない'
        end

        def test_convert_standalone_spacing_no_double_blank
          md = "前。\n\n{.aki}\n\n次。\n"
          out = convert_standalone_spacing(md)

          assert_equal "前。\n\n@vspace:1lh\n\n次。\n", out, '直後が既に空行なら余分な空行を足さない'
        end

        # =================================================================
        # normalize_container_fence_spacing
        # =================================================================
        def test_normalize_container_fence_inserts_blank_after_open_and_before_close
          md = ":::{.output}\n**見出し**\n本文\n:::\n"
          out = normalize_container_fence_spacing(md)

          assert_equal ":::{.output}\n\n**見出し**\n本文\n\n:::\n", out
        end

        def test_normalize_container_fence_keeps_existing_blanks
          md = ":::{.note}\n\n本文\n\n:::\n"
          out = normalize_container_fence_spacing(md)

          assert_equal md, out, '既に空行があれば二重に入れない'
        end

        def test_normalize_container_fence_skips_inside_code_fence
          md = "```markdown\n:::{.note}\n本文\n:::\n```\n"
          out = normalize_container_fence_spacing(md)

          assert_equal md, out, 'コードフェンス内の ::: は対象外'
        end

        # =================================================================
        # process_code_include（同一 include 文字列の取り違え防止）
        # =================================================================
        # 記法説明フェンス内の例文と、:::{.output} 等に置いた本物の include が同一文字列でも、
        # 例文だけスキップし本物は展開する（行番号を出現順に消費する回帰テスト）。
        def test_process_code_include_distinguishes_duplicate_strings
          Dir.mktmpdir do |dir|
            Dir.chdir(dir) do
              FileUtils.mkdir_p('codes')
              File.write('codes/sample.rb', "puts 'hi'\n")
              content = +''
              content << "````markdown\n"          # 記法説明（4 連フェンス）の例文
              content << "**例 @x**\n"
              content << "```include:sample.rb```\n"
              content << "````\n\n"
              content << ":::{.output}\n"            # 本物（フェンス外）
              content << "**本物 @y**\n"
              content << "```include:sample.rb```\n"
              content << ":::\n"

              out = process_code_include(content)

              assert_includes out, '```include:sample.rb```', 'フェンス内の例文は展開しない'
              assert_includes out, "```ruby:sample.rb\nputs 'hi'", '同一文字列でも本物は展開する'
            end
          end
        end

        # 開始は有効で終了だけがファイル末尾を超える場合は、末尾までクランプして取り込む（回帰テスト）。
        def test_process_code_include_end_beyond_eof_clamps_to_last_line
          Dir.mktmpdir do |dir|
            Dir.chdir(dir) do
              FileUtils.mkdir_p('codes')
              File.write('codes/sample.rb', (1..5).map { |i| "line#{i}\n" }.join) # 5 行

              out = process_code_include(+"```include:sample.rb:4-99```\n", source_filename: 'x.md')

              assert_includes out, "```ruby:sample.rb\nline4\nline5\n```", '開始〜ファイル末尾までを取り込む'
              refute_includes out, 'line3', 'クランプ後も開始行より前は含まない'
            end
          end
        end

        # 開始行自体がファイル末尾を超える（救済不能）なら、クラッシュせず全文取り込みへフォールバックする。
        # 旧実装は lines[(start-1)..(end-1)] が nil を返し nil.join で落ちていた。
        def test_process_code_include_start_beyond_eof_falls_back_to_whole_file
          Dir.mktmpdir do |dir|
            Dir.chdir(dir) do
              FileUtils.mkdir_p('codes')
              File.write('codes/sample.rb', (1..5).map { |i| "line#{i}\n" }.join) # 5 行

              out = process_code_include(+"```include:sample.rb:22-25```\n", source_filename: 'x.md')

              assert_includes out, '```ruby:sample.rb', '言語付きコードブロックとして展開される'
              assert_includes out, 'line1', '全文（先頭行）が含まれる'
              assert_includes out, 'line5', '全文（末尾行）が含まれる'
            end
          end
        end

        # 逆順の範囲も全文フォールバックする。
        def test_process_code_include_reversed_range_falls_back
          Dir.mktmpdir do |dir|
            Dir.chdir(dir) do
              FileUtils.mkdir_p('codes')
              File.write('codes/sample.rb', (1..5).map { |i| "line#{i}\n" }.join)

              out = process_code_include(+"```include:sample.rb:4-2```\n", source_filename: 'x.md')

              assert_includes out, 'line1'
              assert_includes out, 'line5'
            end
          end
        end

        # 有効な範囲は従来どおり該当行のみを取り込む。
        def test_process_code_include_valid_range_extracts_lines
          Dir.mktmpdir do |dir|
            Dir.chdir(dir) do
              FileUtils.mkdir_p('codes')
              File.write('codes/sample.rb', (1..5).map { |i| "line#{i}\n" }.join)

              out = process_code_include(+"```include:sample.rb:2-4```\n", source_filename: 'x.md')

              assert_includes out, "```ruby:sample.rb\nline2\nline3\nline4\n```"
              refute_includes out, 'line1'
              refute_includes out, 'line5'
            end
          end
        end

        # 同一パスを複数回 include したとき、警告は**その出現の原稿ファイル行**を報告する（回帰テスト）。
        # 旧実装は source_line_map がパスキーで衝突し、常に最初の出現行を報告していた。
        def test_process_code_include_warning_reports_correct_line_for_duplicate_path
          Dir.mktmpdir do |dir|
            Dir.chdir(dir) do
              FileUtils.mkdir_p('codes')
              File.write('codes/sample.rb', (1..5).map { |i| "line#{i}\n" }.join) # 5 行
              src = +''
              src << "# title\n\n"                  # 1, 2
              src << "```include:sample.rb```\n\n"  # 3（全文・正常）, 4
              src << "```include:sample.rb:9-9```\n" # 5（範囲超過）
              File.write('chapter.md', src)
              content = File.read('chapter.md')

              out, = capture_io do
                process_code_include(content, source_filename: 'chapter.md', source_path: 'chapter.md')
              end

              assert_match(/chapter\.md:5 -/, out, '2 つ目の include（5 行目）の行番号を報告する')
              refute_match(/chapter\.md:3 -/, out, '1 つ目の行番号（3 行目）を誤報告しない')
            end
          end
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

        # 回帰: キャプション付きコードブロックが、キャプションだけでなくコード本体ごと
        # 出力される（list_markdown がコードを読み飛ばして消す不具合の防止）。
        # post_process の wrap_cross_ref_code_blocks! が <!--xref--> 直後の <pre> を
        # 参照するため、コードフェンスがマーカーに続いて残ることが必須。
        def test_transform_captioned_code_block_keeps_code_body
          content = <<~'MD'
            ** サンプルコード @sample-code **
            ```ruby
            def hello(name)
              puts "Hello, #{name}!"
            end
            ```
          MD
          labels_map = build_labels_map_with_duplicates_check(
            collect_labels(content, 'test.md', '1')[:labels]
          )[:labels_map]

          result = transform_captioned_blocks(content, 'test.md', labels_map)

          assert_includes result, '<!--xref:sample-code-->', 'xref マーカーが出力される'
          assert_includes result, '```ruby', 'コードフェンスが保持される'
          assert_includes result, 'def hello(name)', 'コード本体が保持される'
          assert_includes result, 'サンプルコード', 'キャプションのタイトルが出力される'
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

        # Markdown リンクのテキスト・URL 内の @（npm スコープ名等）は参照として扱わない
        def test_replace_references_ignores_at_inside_markdown_links
          labels_map = {}

          content = <<~MD
            最新版は [npmjs.com/@vivliostyle/cli](https://www.npmjs.com/package/@vivliostyle/cli) で確認。
            画像も ![alt @vivliostyle](images/@vivliostyle/logo.png) 同様。
            脚注定義行の裸 URL も対象外:
            [^url1]: https://www.npmjs.com/package/@vivliostyle/cli
          MD
          result = replace_references(content, labels_map, 'test.md')

          assert_empty result[:errors], "リンク内の @ で未定義警告が出てはいけない: #{result[:errors].inspect}"
          assert_includes result[:content], '[npmjs.com/@vivliostyle/cli](https://www.npmjs.com/package/@vivliostyle/cli)'
        end

        # 索引・用語集の手動登録マークアップ（[用語|読み]・[@用語]）内の @ は参照として扱わない
        def test_replace_references_ignores_at_inside_index_markup
          labels_map = {}

          content = <<~MD
            索引登録: [@vivliostyle] と [@vivliostyle/cli|びぶりおすたいるしーえるあい] を掲載。
          MD
          result = replace_references(content, labels_map, 'test.md')

          assert_empty result[:errors], "索引マークアップ内の @ で未定義警告が出てはいけない: #{result[:errors].inspect}"
          assert_includes result[:content], '[@vivliostyle]'
        end

        # 角括弧・リンク・code の外に裸で書かれた @語 は従来どおり未定義参照として検出する
        # （表セルへ平文で書かれた npm パッケージ名等。バッククォートで括るのが正）
        def test_replace_references_still_flags_bare_at_words
          labels_map = {}

          content = "| @vivliostyle/cli | 11.0.2 |\n"
          result = replace_references(content, labels_map, 'test.md')

          assert_equal 1, result[:errors].size
          assert_match(/未定義のラベルID.*@vivliostyle/, result[:errors].first)
        end

        # 除外スパンが混在する行でも、平文部分の正当な参照は置換される
        def test_replace_references_replaces_refs_between_masked_spans
          label = Label.new('sample', :fig, '1', '1-1', 'Sample', 'test.md', 5, false)
          labels_map = { 'sample' => label }

          content = '[リンク @vivliostyle](https://example.com/@vivliostyle) の後で @sample を参照。'
          result = replace_references(content, labels_map, 'test.md')

          assert_empty result[:errors]
          assert_includes result[:content], '<a href="test.html#sample"'
          assert_includes result[:content], '(https://example.com/@vivliostyle)'
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

        def test_replace_references_preserves_post_replace_list_macros
          labels_map = {}

          # post_replace_list.yml の完全一致マクロ
          content = <<~MD
            余白: @vspace:10 と @vspace:-10
            旧記法: @nega:3 と @posi:5
            コメント: @comment:編集中@commend
          MD
          result = replace_references(content, labels_map, 'test.md')

          %w[@vspace @nega @posi @comment @commend].each do |macro|
            assert_includes result[:content], macro, "予約マクロ #{macro} が残っていない"
          end
          assert_empty result[:errors], "予約マクロで未定義警告が出てはいけない: #{result[:errors].inspect}"
        end

        def test_replace_references_preserves_absolute_position_macros
          labels_map = {}

          # @lu25,15@20,30 や @ls40@20,20 のような絶対配置マクロ
          # （Planned 扱いだが Planned-期間中も警告を出さない）
          content = <<~MD
            左上ガイド @lu25,15@20,30
            右下ガイド @rd30,20@100,80
            水平線 @ls40@20,20 / 垂直線 @us30@40,40
            接頭辞のみ @lu / @ld / @ru / @rd / @ur / @ls / @rs / @us / @ds
          MD
          result = replace_references(content, labels_map, 'test.md')

          # prefix+digits パターン（@lu25, @rd30, @ls40, @us30 など）が予約扱い
          assert_empty result[:errors], "絶対配置マクロで未定義警告が出てはいけない: #{result[:errors].inspect}"
          # 原文が保持されている
          assert_includes result[:content], '@lu25'
          assert_includes result[:content], '@rd30'
          assert_includes result[:content], '@ls40'
        end

        def test_reserved_id_helper
          # 完全一致グループ
          %w[auto omakase id].each do |id|
            assert CrossReferenceProcessor.reserved_id?(id), "#{id} は予約ID"
          end
          %w[vspace nega posi comment commend].each do |id|
            assert CrossReferenceProcessor.reserved_id?(id), "#{id} は予約マクロID"
          end
          # 接頭辞＋数字グループ
          %w[lu ld ru rd ur ls rs us ds lu25 rd30 ls40 us30].each do |id|
            assert CrossReferenceProcessor.reserved_id?(id), "#{id} は予約マクロ接頭辞"
          end
          # 非予約ID は false を返す
          %w[foo bar einstein ruby-sample prop-list lux ldap russet].each do |id|
            refute CrossReferenceProcessor.reserved_id?(id), "#{id} は予約IDではない"
          end
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
          assert_empty result[:duplicates_by_id]
        end

        def test_build_labels_map_with_duplicates
          label1 = Label.new('same-id', :list, '1', '1-1', 'Title1', 'a.md', 1, false)
          label2 = Label.new('same-id', :table, '2', '2-1', 'Title2', 'b.md', 2, false)

          result = build_labels_map_with_duplicates_check([label1, label2])

          assert_equal 1, result[:labels_map].size
          assert_equal 1, result[:duplicates_by_id].size
          assert result[:duplicates_by_id].key?('same-id')
        end

        # =================================================================
        # convert_terminal_blocks
        # -----------------------------------------------------------------
        # :::{.terminal} は「端末の逐語転写」であり、中身は Markdown ではない。
        # ~~~vs-terminal フェンスへ書き換えることで以降の前処理・VFM から
        # 中身を守る（docs/specs/terminal-literal-spec.md）。
        # =================================================================

        def test_convert_terminal_blocks_keeps_body_verbatim
          md = <<~MD
            :::{.terminal}
            $ cp *.png *.bak
            $ echo `date`
            $ echo $A$B
            $ mv _old_ _new_
            ---
            | id | name  | email |

            $ ls
            foobar.png
            :::
          MD

          result = MarkdownTransformer.convert_terminal_blocks(md)

          assert_includes result, "~~~vs-terminal\n"
          assert_includes result, '$ cp *.png *.bak'
          assert_includes result, '$ echo `date`'
          assert_includes result, '$ echo $A$B'
          assert_includes result, '$ mv _old_ _new_'
          assert_includes result, "---\n"
          assert_includes result, '| id | name  | email |'
          assert_includes result, "$ ls\nfoobar.png\n"
          refute_includes result, ':::'
        end

        def test_convert_terminal_blocks_preserves_blank_lines_inside_body
          md = ":::{.terminal}\n$ ls\n\nfoo.png\n:::\n"

          result = MarkdownTransformer.convert_terminal_blocks(md)

          assert_equal "\n~~~vs-terminal\n$ ls\n\nfoo.png\n~~~\n\n", result
        end

        def test_convert_terminal_blocks_skips_notation_inside_code_fence
          md = <<~MD
            ```markdown
            :::{.terminal}
            vs build
            :::
            ```
          MD

          assert_equal md, MarkdownTransformer.convert_terminal_blocks(md)
        end

        def test_convert_terminal_blocks_lengthens_fence_when_body_has_tildes
          md = ":::{.terminal}\n$ echo\n~~~~\n:::\n"

          result = MarkdownTransformer.convert_terminal_blocks(md)

          assert_includes result, "~~~~~vs-terminal\n"
          assert_includes result, "\n~~~~~\n"
        end

        def test_convert_terminal_blocks_leaves_other_containers_untouched
          md = ":::{.output}\n- 出力: dist/sample.pdf\n:::\n"

          assert_equal md, MarkdownTransformer.convert_terminal_blocks(md)
        end
      end
    end
  end
end
