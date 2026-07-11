# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../../../lib/vivlio_starter/cli/pre_process/table_converter'

module VivlioStarter
  module CLI
    module PreProcessCommands
      # 統合テーブル変換（拡張パイプテーブル）の振る舞いを検証する。
      class TableConverterTest < Minitest::Test
        # B5 版・A5 標準相当の固定 page_cfg（プリセット適用・単位正規化済みを想定）。
        PAGE_CFG = {
          size: 'B5',
          margin_top: '22mm', margin_bottom: '22mm',
          margin_inner: '22mm', margin_outer: '18mm',
          base_font_size: '10pt', base_line_height: '17.0pt'
        }.freeze

        # =================================================================
        # パーサ単体: pipe_table_to_html
        # =================================================================
        def test_should_convert_basic_table
          md = <<~MD
            | Header1 | Header2 |
            | ------- | ------- |
            | Cell1   | Cell2   |
          MD
          result = TableConverter.pipe_table_to_html(md)

          assert_includes result, '<table>'
          assert_includes result, '<thead>'
          assert_includes result, '<th>Header1</th>'
          assert_includes result, '<tbody>'
          assert_includes result, '<td>Cell1</td>'
          assert_includes result, '</table>'
        end

        def test_should_apply_column_alignment
          md = <<~MD
            | Left | Center | Right |
            | :--- | :----: | ----: |
            | a    | b      | c     |
          MD
          result = TableConverter.pipe_table_to_html(md)

          assert_includes result, '<th style="text-align: left">Left</th>'
          assert_includes result, '<th style="text-align: center">Center</th>'
          assert_includes result, '<th style="text-align: right">Right</th>'
          assert_includes result, '<td style="text-align: left">a</td>'
        end

        def test_should_merge_cells_with_colspan
          md = <<~MD
            | A    | B    |
            | :--- | :--- |
            | x    | y   ||
          MD
          result = TableConverter.pipe_table_to_html(md)

          assert_includes result, '<td colspan="2">y</td>'
          # colspan セルにはインライン整列を付与しない
          refute_match(/colspan="2"[^>]*text-align/, result)
        end

        def test_should_build_multi_row_thead
          md = <<~MD
            |          |       結合       ||
            | ヘッダー1 | ヘッダー2 | ヘッダー3 |
            | :------- | :------: | -------: |
            | セル1     |      長いセル      ||
            | セル2     |  中央寄せ  |   右寄せ  |
            | セル3     | **太字**  |  *斜体*  |
            | セル4     |      さらに       ||
          MD
          expected = <<~HTML.chomp
            <table>
              <thead>
                <tr><th style="text-align: left"></th><th colspan="2">結合</th></tr>
                <tr><th style="text-align: left">ヘッダー1</th><th style="text-align: center">ヘッダー2</th><th style="text-align: right">ヘッダー3</th></tr>
              </thead>
              <tbody>
                <tr><td style="text-align: left">セル1</td><td colspan="2">長いセル</td></tr>
                <tr><td style="text-align: left">セル2</td><td style="text-align: center">中央寄せ</td><td style="text-align: right">右寄せ</td></tr>
                <tr><td style="text-align: left">セル3</td><td style="text-align: center"><strong>太字</strong></td><td style="text-align: right"><em>斜体</em></td></tr>
                <tr><td style="text-align: left">セル4</td><td colspan="2">さらに</td></tr>
              </tbody>
            </table>
          HTML

          assert_equal expected, TableConverter.pipe_table_to_html(md)
        end

        def test_should_keep_whitespace_only_cell_empty
          md = <<~MD
            | A    | B    |
            | :--- | :--- |
            | x    |      |
          MD
          result = TableConverter.pipe_table_to_html(md)

          # 空白のみのセルは本物の空セル（マージしない・colspan なし）
          assert_includes result, '<td style="text-align: left">x</td><td style="text-align: left"></td>'
          refute_includes result, 'colspan'
        end

        def test_should_treat_leading_zero_width_cell_as_empty
          md = <<~MD
            | A    | B    |
            | :--- | :--- |
            || x |
          MD
          result = TableConverter.pipe_table_to_html(md)

          # 行頭のゼロ幅セルはマージ先が無いため空セル
          assert_includes result, '<td style="text-align: left"></td><td style="text-align: left">x</td>'
          refute_includes result, 'colspan'
        end

        def test_should_unescape_pipes
          md = <<~MD
            | A       | B    |
            | :------ | :--- |
            | a \\| b  | c    |
          MD
          result = TableConverter.pipe_table_to_html(md)

          assert_includes result, '<td style="text-align: left">a | b</td>'
        end

        def test_should_render_inline_markdown_in_cells
          md = <<~MD
            | Code   | Bold     |
            | :----- | :------- |
            | `foo`  | **bar**  |
          MD
          result = TableConverter.pipe_table_to_html(md)

          # 既知バグ（<code> 二重エスケープ）が解消し、非エスケープで出る
          assert_includes result, '<code>foo</code>'
          assert_includes result, '<strong>bar</strong>'
          refute_includes result, '&lt;code&gt;'
        end

        def test_should_preserve_raw_html_in_cells
          md = <<~MD
            | Fig             | Note |
            | :-------------- | :--- |
            | <img src="x.svg"> | ok   |
          MD
          result = TableConverter.pipe_table_to_html(md)

          assert_includes result, '<img src="x.svg" />'
        end

        def test_should_return_nil_for_non_table
          assert_nil TableConverter.pipe_table_to_html('Not a table')
          # 区切り行が先頭（ヘッダー行なし）は不成立
          assert_nil TableConverter.pipe_table_to_html("| --- | --- |\n| a | b |")
        end

        # =================================================================
        # 素テーブル横取り: intercept_extended_tables
        # =================================================================
        def test_should_intercept_bare_table_with_colspan
          content = <<~MD
            前の段落。

            | A    | B    |
            | :--- | :--- |
            | x    | y   ||

            次の段落。
          MD
          result, count = TableConverter.intercept_extended_tables(content)

          assert_equal 1, count
          assert_includes result, '<td colspan="2">y</td>'
          assert_includes result, '前の段落。'
          assert_includes result, '次の段落。'
        end

        def test_should_intercept_bare_table_with_multi_row_header
          content = <<~MD
            | グループA ||
            | 列1 | 列2 |
            | :-- | :-- |
            | a   | b   |
          MD
          result, count = TableConverter.intercept_extended_tables(content)

          assert_equal 1, count
          assert_includes result, '<thead>'
          assert_includes result, '<th colspan="2">グループA</th>'
        end

        def test_should_not_touch_plain_gfm_table
          content = <<~MD
            | H1 | H2 |
            | -- | -- |
            | a  | b  |
          MD
          result, count = TableConverter.intercept_extended_tables(content)

          # 通常の GFM テーブルは完全不変（バイト一致）で VFM に委ねる
          assert_equal 0, count
          assert_equal content, result
        end

        def test_should_not_touch_tables_inside_code_fences
          content = <<~MD
            ```
            | A | B |
            | - | - |
            | x | y ||
            ```
          MD
          result, count = TableConverter.intercept_extended_tables(content)

          assert_equal 0, count
          assert_equal content, result
        end

        def test_should_not_touch_indented_pipe_lines
          content = "        | A | B |\n        | - | - |\n        | x | y ||\n"
          result, count = TableConverter.intercept_extended_tables(content)

          assert_equal 0, count
          assert_equal content, result
        end

        # =================================================================
        # コンテナ統合: convert_container_inner
        # =================================================================
        def test_should_convert_tables_inside_each_container_class
          %w[long-table rotate-table].each do |klass|
            content = <<~HTML
              <div class="#{klass}">
              **キャプション**

              | A    | B    |
              | :--- | :--- |
              | x    | y   ||
              </div>
            HTML
            result = TableConverter.convert_container_inner(content, klass)

            assert_includes result, "<div class=\"#{klass}\">", "class=#{klass}"
            assert_includes result, '<strong>キャプション</strong>', "caption for #{klass}"
            assert_includes result, '<td colspan="2">y</td>', "table for #{klass}"
          end
        end

        # =================================================================
        # 自動フィット: estimate_rotate_style
        # =================================================================
        def test_should_estimate_scale_and_height_from_page_and_table
          model = TableConverter.send(:parse, <<~MD)
            | 列1 | 列2 | 列3 |
            | :-- | :-- | :-- |
            | a   | b   | c   |
          MD
          style = TableConverter.estimate_rotate_style(model, PAGE_CFG)

          # 版面高さ = 257 - 22 - 22 = 213mm
          assert_equal '213.0mm', style['rotate-table-height']
          assert_match(/\A\d+%\z/, style['rotate-table-scale'])
          scale = style['rotate-table-scale'].to_i
          assert scale.between?(30, 100), "scale in range: #{scale}"
        end

        def test_should_shrink_scale_for_wider_table
          narrow = TableConverter.send(:parse, "| a | b |\n| :- | :- |\n| x | y |\n")
          wide_md = "| #{(['very-long-column-heading'] * 8).join(' | ')} |\n" \
                    "| #{(['-'] * 8).join(' | ')} |\n" \
                    "| #{(['very-long-column-heading'] * 8).join(' | ')} |\n"
          wide = TableConverter.send(:parse, wide_md)

          narrow_scale = TableConverter.estimate_rotate_style(narrow, PAGE_CFG)['rotate-table-scale'].to_i
          wide_scale   = TableConverter.estimate_rotate_style(wide, PAGE_CFG)['rotate-table-scale'].to_i

          assert wide_scale < narrow_scale, "wide(#{wide_scale}) < narrow(#{narrow_scale})"
        end

        def test_should_respect_author_scale_over_auto
          content = <<~HTML
            <div class="rotate-table" style="--rotate-table-scale:45%;">
            | A   | B   |
            | :-- | :-- |
            | x   | y   |
            </div>
          HTML
          result = TableConverter.convert_container_inner(content, 'rotate-table', page_cfg: PAGE_CFG)

          # 著者指定 scale は保持され、height は自動注入される
          assert_includes result, '--rotate-table-scale:45%;'
          assert_includes result, '--rotate-table-height:213.0mm;'
        end

        def test_should_skip_estimation_without_page_cfg
          content = <<~HTML
            <div class="rotate-table">
            | A   | B   |
            | :-- | :-- |
            | x   | y   |
            </div>
          HTML
          result = TableConverter.convert_container_inner(content, 'rotate-table')

          refute_includes result, 'rotate-table-height'
          assert_includes result, '<td style="text-align: left">x</td>'
        end
      end
    end
  end
end
