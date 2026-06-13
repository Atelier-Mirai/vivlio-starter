# frozen_string_literal: true

# ================================================================
# Test: epub_builder_sanitize_test.rb
# ================================================================
# テスト対象:
#   Build::EpubBuilder の EPUB 構造修正フック
#   （docs/specs/epub-pipeline-fix-spec.md の Fix-1〜4 / §4.1 EPF-01〜05）
#
# 検証内容:
#   - EPF-01: 生成後 EPUB の CSS から @page マージンボックスを除去（size: は残す）
#   - EPF-02: マージンボックス除去が通常ルール（margin-bottom 等）を壊さない
#   - EPF-03: 段落内脚注 span の id のみ除去（aside の id / data-footnote-number は残す）
#   - EPF-04: 絵文字 <img> に width/height 属性が無く style に寸法が入る
#   - EPF-05: generate_epub_config! が copyAsset.excludes を出力する
#   - EPF-06: @footnote at-rule もサニタイズで除去される（Fix-5）
#   - EPF-07: テーブルの align 属性が style の text-align へ変換される（Fix-6）
#   - EPF-08: content.opf の数字始まり id/idref に接頭辞が付く（Fix-7）
# ================================================================

require 'test_helper'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/build'
require 'vivlio_starter/cli/epub'
require_relative '../../../lib/vivlio_starter/cli/techbook/emoji_replacer'

module VivlioStarter
  module CLI
    class EpubBuilderSanitizeTest < Minitest::Test
      EMOJI_FIXTURES_DIR = File.expand_path('techbook/fixtures/twemoji', __dir__)

      def setup
        @original_dir = Dir.pwd
        @test_dir = Dir.mktmpdir('epub_sanitize_test')
        Dir.chdir(@test_dir)
      end

      def teardown
        Dir.chdir(@original_dir)
        FileUtils.rm_rf(@test_dir)
      end

      # --- EPF-01: マージンボックス除去（size: は残る） ---
      def test_should_strip_margin_box_but_keep_page_size
        css = "@page { size: A5; @bottom-center { content: counter(page); } }\n"
        epub = build_epub_with_css('EPUB/stylesheets/page-settings.css' => css)

        Build::EpubBuilder.sanitize_epub_css!(epub)

        result = read_css_from_epub(epub, 'EPUB/stylesheets/page-settings.css')
        refute_includes result, '@bottom-center', 'マージンボックスは除去されるべき'
        assert_includes result, 'size: A5', '@page の size: は残すべき'
      end

      # --- EPF-02: 通常ルールを壊さない ---
      def test_should_not_break_normal_rules_with_bottom_in_property_name
        css = ".foo { margin-bottom: 1em; }\n.bar { padding-top: 2px; }\n"
        epub = build_epub_with_css('EPUB/stylesheets/components.css' => css)

        Build::EpubBuilder.sanitize_epub_css!(epub)

        result = read_css_from_epub(epub, 'EPUB/stylesheets/components.css')
        assert_equal css, result, 'マージンボックス以外の通常ルールは不変であるべき'
      end

      # --- EPF-03: 脚注 span の id のみ除去 ---
      def test_should_strip_inline_footnote_span_id_only
        html = <<~HTML
          <p>本文<span role="doc-footnote" class="page-footnote page-footnote-inline" id="fn1">注</span>続き</p>
          <aside role="doc-footnote" class="page-footnote page-footnote-print" id="fn1" data-footnote-number="1">注</aside>
        HTML
        path = File.join(@test_dir, '01-intro.html')
        File.write(path, html)

        Build::EpubBuilder.strip_inline_footnote_ids_for_epub!([path])

        result = File.read(path)
        refute_match(/page-footnote-inline[^>]*id="fn1"/, result, 'span 側の id は除去されるべき')
        assert_match(/page-footnote-print[^>]*id="fn1"/, result, 'aside 側の id は残すべき')
        assert_includes result, 'data-footnote-number="1"', 'data-footnote-number は残すべき'
      end

      # --- EPF-04: 絵文字 img の寸法は style に統合され属性は無い ---
      def test_should_emit_emoji_img_without_dimension_attributes
        replacer = Techbook::EmojiReplacer.new(EMOJI_FIXTURES_DIR)

        result = replacer.process('Task ✅ done')

        refute_match(/<img[^>]*\swidth="/, result, 'width 属性は出力されないべき')
        refute_match(/<img[^>]*\sheight="/, result, 'height 属性は出力されないべき')
        assert_match(/style="width: 1em; height: 1em;/, result, '寸法は style に統合されるべき')
      end

      # --- EPF-05: generate_epub_config! が copyAsset.excludes を出力する ---
      def test_should_generate_config_with_copy_asset_excludes
        path = Build::EpubBuilder.generate_epub_config!
        content = File.read(path)

        assert_includes content, 'copyAsset:', 'copyAsset ブロックが出力されるべき'
        assert_includes content, 'excludes:', 'excludes 配列が出力されるべき'
        %w[lib/** docs/** test/** *_images/** covers/bundled/**].each do |pattern|
          assert_includes content, "'#{pattern}'", "除外パターン #{pattern} が含まれるべき"
        end
      end

      # --- EPF-06: @footnote at-rule の除去（Fix-5。通常ルールは残す） ---
      def test_should_strip_footnote_at_rule_but_keep_normal_rules
        css = <<~CSS
          @page { size: A5; @footnote { list-style: none; padding-inline-start: 0; margin: 0; } }
          .note { list-style: none; }
        CSS
        epub = build_epub_with_css('EPUB/stylesheets/page-settings.css' => css)

        Build::EpubBuilder.sanitize_epub_css!(epub)

        result = read_css_from_epub(epub, 'EPUB/stylesheets/page-settings.css')
        refute_includes result, '@footnote', '@footnote at-rule は除去されるべき'
        assert_includes result, 'size: A5', '@page の size: は残すべき'
        assert_includes result, '.note { list-style: none; }', '通常ルールは残すべき'
      end

      # --- EPF-07: align 属性の style 変換（Fix-6。属性順の前後両対応） ---
      def test_should_convert_table_align_attribute_to_style
        html = <<~HTML
          <table>
            <tr><th align="left">頒布先</th><th align="center">中央</th></tr>
            <tr><td style="color:red" align="right">style前</td><td align="right" style="color:blue">style後</td></tr>
            <tr><td>整列なし</td></tr>
          </table>
        HTML
        path = File.join(@test_dir, '11-workflow.html')
        File.write(path, html)

        Build::EpubBuilder.rewrite_table_align_for_epub!([path])

        result = File.read(path)
        refute_match(/\salign="/, result, 'align 属性はすべて除去されるべき')
        assert_includes result, '<th style="text-align:left">'
        assert_includes result, '<th style="text-align:center">'
        # 既存 style への統合: align と style の属性順がどちらでも style 属性は 1 つに保たれる
        assert_includes result, 'style="text-align:right;color:red"'
        assert_includes result, 'style="text-align:right;color:blue"'
        assert_equal 0, result.scan(/<t[hd][^>]*style="[^"]*"[^>]*style=/).size,
                     'style 属性が二重になってはならない'
        assert_includes result, '<td>整列なし</td>', '整列指定の無いセルは不変であるべき'
      end

      # --- EPF-08: content.opf の数字始まり id/idref へ接頭辞付与（Fix-7） ---
      def test_should_prefix_digit_leading_opf_ids
        opf = <<~XML
          <?xml version="1.0" encoding="UTF-8"?>
          <package unique-identifier="bookid">
            <dc:identifier id="bookid">urn:uuid:dummy</dc:identifier>
            <manifest>
              <item id="00-prefacexhtml" href="00-preface.xhtml" media-type="application/xhtml+xml"></item>
              <item id="toc" href="toc.xhtml" media-type="application/xhtml+xml"></item>
            </manifest>
            <spine>
              <itemref idref="00-prefacexhtml"></itemref>
              <itemref idref="toc"></itemref>
            </spine>
          </package>
        XML
        epub = build_epub_with_css('EPUB/content.opf' => opf)

        options = { clean: true, resize: true, compress: true, high: false, low: false }
        command = Struct.new(:options).new(options)
        pipeline = BuildCommands::UnifiedBuildPipeline.new(command, entries: [], mode: :full)
        pipeline.send(:sanitize_epub_opf_ids!, epub)

        result = read_css_from_epub(epub, 'EPUB/content.opf')
        assert_includes result, 'id="id-00-prefacexhtml"', '数字始まりの id に接頭辞が付くべき'
        assert_includes result, 'idref="id-00-prefacexhtml"', '対応する idref も同一規則で書き換わるべき'
        assert_includes result, 'id="bookid"', '英字始まりの id は不変であるべき'
        assert_includes result, 'idref="toc"', '英字始まりの idref は不変であるべき'
        assert_includes result, 'href="00-preface.xhtml"', 'href は変更しないべき'
      end

      private

      # EPUB 構造を模した zip を作成して .epub パスを返す。
      # sanitize_epub_css! は unzip/zip による実差し替えを行うため、
      # 実バイナリでの往復を検証する統合テストとする。
      def build_epub_with_css(css_files)
        css_files.each do |rel_path, content|
          full = File.join(@test_dir, rel_path)
          FileUtils.mkdir_p(File.dirname(full))
          File.write(full, content)
        end
        epub = File.join(@test_dir, 'book.epub')
        Dir.chdir(@test_dir) do
          system('zip', '-q', '-r', epub, 'EPUB', out: File::NULL, err: File::NULL)
        end
        epub
      end

      # EPUB から特定 CSS を取り出して文字列を返す。
      def read_css_from_epub(epub, rel_path)
        Dir.mktmpdir('epub_read') do |dir|
          system('unzip', '-o', epub, rel_path, '-d', dir, out: File::NULL, err: File::NULL)
          File.read(File.join(dir, rel_path), encoding: 'UTF-8')
        end
      end
    end
  end
end
