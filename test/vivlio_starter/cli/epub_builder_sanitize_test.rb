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
#   - EPF-05: generate_epub_config! が entryContext と dir 内 output を出力する（P4 段階 4）
#   - EPF-06: @footnote at-rule もサニタイズで除去される（Fix-5）
#   - EPF-07: テーブルの align 属性が style の text-align へ変換される（Fix-6）
#   - EPF-08: content.opf の数字始まり id/idref に接頭辞が付く（Fix-7）
#   - EPF-09: フォント非埋め込み時に @font-face 除去・fonts/ 除外（P2 サイズ最適化）
#   - EPF-10: 埋め込み経路（embed_fonts? = true）では fonts/@font-face を保持
#   - EPF-11: 絵文字 img のプレーン復元・囲み数字維持・twemoji 直下除外（Fix-8）
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

      # --- EPF-05: generate_epub_config! が entryContext と dir 内 output を出力する（P4 段階 4）。
      #   パッケージ内容の選択は copyAsset.excludes ではなくローカライズ（localize_assets!）が
      #   担うため、config に copyAsset ブロックは出力しない。 ---
      def test_should_generate_config_with_entry_context
        dir = '.cache/vs/build/epub'
        FileUtils.mkdir_p(dir)
        path = Build::EpubBuilder.generate_epub_config!(dir:)
        content = File.read(path)

        assert_equal File.join(dir, 'vivliostyle.config.epub.js'), path, 'config は消費者 dir 内に生成されるべき'
        assert_includes content, "entryContext: '#{dir}'", 'entryContext は消費者 dir を指すべき'
        assert_includes content, "'#{dir}/output.epub'", 'output は消費者 dir 内を指すべき'
        refute_includes content, 'copyAsset:', 'copyAsset ブロックは出力しない（選択はローカライズが担う）'
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

        # P2: content.opf zip 手術は Build::EpubBuilder へ移設済み。
        Build::EpubBuilder.sanitize_epub_opf_ids!(epub)

        result = read_css_from_epub(epub, 'EPUB/content.opf')
        assert_includes result, 'id="id-00-prefacexhtml"', '数字始まりの id に接頭辞が付くべき'
        assert_includes result, 'idref="id-00-prefacexhtml"', '対応する idref も同一規則で書き換わるべき'
        assert_includes result, 'id="bookid"', '英字始まりの id は不変であるべき'
        assert_includes result, 'idref="toc"', '英字始まりの idref は不変であるべき'
        assert_includes result, 'href="00-preface.xhtml"', 'href は変更しないべき'
      end

      # --- EPF-09: フォント非埋め込み時に @font-face と fonts/ への @import を除去（既定） ---
      def test_should_strip_font_face_when_not_embedding_fonts
        css = <<~CSS
          @import url("fonts/google-fonts.css");
          @font-face { font-family: "Zen Old Mincho"; src: url("fonts/ZenOldMincho-Regular.ttf"); }
          body { font-family: var(--font-main-text); }
        CSS
        epub = build_epub_with_css('EPUB/stylesheets/page-settings.css' => css)

        Build::EpubBuilder.sanitize_epub_css!(epub)

        result = read_css_from_epub(epub, 'EPUB/stylesheets/page-settings.css')
        refute_includes result, '@font-face', '非埋め込み時 @font-face は除去されるべき'
        refute_includes result, 'fonts/google-fonts.css', 'fonts/ への @import も除去されるべき（RSC-007 回避）'
        assert_includes result, 'font-family: var(--font-main-text)', '通常の font-family 宣言は残すべき'
      end

      # --- EPF-09b: 非埋め込み時はローカライズが fonts/ をコピーしない ---
      def test_should_exclude_fonts_dir_when_not_embedding
        create_stylesheet_fixture
        dir = '.cache/vs/build/epub'

        Build::EpubBuilder.localize_assets!(dir, flavor: :epub)

        assert File.exist?(File.join(dir, 'stylesheets/theme.css')), 'CSS はローカライズされるべき'
        refute File.exist?(File.join(dir, 'stylesheets/fonts/zen.ttf')),
               '非埋め込み時 fonts/ はローカライズしないべき'
      end

      # --- EPF-10: 埋め込み経路（embed_fonts? = true）では fonts/@font-face を保持 ---
      def test_should_keep_fonts_when_embedding_enabled
        css = %(@font-face { font-family: "X"; src: url("fonts/x.ttf"); }\n)
        epub = build_epub_with_css('EPUB/stylesheets/page-settings.css' => css)
        create_stylesheet_fixture
        dir = '.cache/vs/build/epub'

        Build::EpubBuilder.stub(:embed_fonts?, true) do
          Build::EpubBuilder.sanitize_epub_css!(epub)
          Build::EpubBuilder.localize_assets!(dir, flavor: :epub)

          assert File.exist?(File.join(dir, 'stylesheets/fonts/zen.ttf')),
                 '埋め込み時は fonts/ もローカライズすべき'
        end

        result = read_css_from_epub(epub, 'EPUB/stylesheets/page-settings.css')
        assert_includes result, '@font-face', '埋め込み時 @font-face は保持されるべき'
      end

      # --- EPF-11: 絵文字 img をプレーン絵文字へ復元・囲み数字は維持（Fix-8） ---
      def test_should_restore_plain_emoji_but_keep_circled_numbers
        html = <<~HTML
          <p>OK <img src="stylesheets/twemoji/2705.svg" alt="✅" class="emoji vs-emoji" style="width: 1em; height: 1em;"> done</p>
          <p>No.<img src="stylesheets/twemoji/vs-techbook/circled-1.webp" alt="1" aria-label="1" class="emoji vs-emoji vs-circled-number" style="width: 1em; height: 1em;"></p>
        HTML
        path = File.join(@test_dir, '11-workflow.html')
        File.write(path, html)

        Build::EpubBuilder.restore_plain_emoji_for_epub!([path])

        result = File.read(path)
        assert_includes result, 'OK ✅ done', '絵文字は alt の元文字へ復元されるべき'
        refute_includes result, '2705.svg', '絵文字 img は除去されるべき'
        assert_includes result, 'circled-1.webp', '囲み数字は画像のまま維持されるべき'
        assert_includes result, 'vs-circled-number', '囲み数字の class は残るべき'
      end

      # --- EPF-11b: WebP 除外は Kindle フレーバのみ（Kindle 非対応）。
      #   クリーン EPUB（:epub・Kobo/Apple Books）は WebP を高画質維持するため除外しない（§4）。
      #   twemoji 直下 svg は両フレーバで除外、vs-techbook サブツリーは丸ごと全除外しない。
      #   さらに消費者 dir 内へ直接生成される _epub_assets/・headings/ はルートの残骸を拾わない。 ---
      def test_should_exclude_webp_only_for_kindle_flavor
        create_stylesheet_fixture
        create_image_fixture
        epub_dir = '.cache/vs/build/epub'
        kindle_dir = '.cache/vs/build/kindle'

        Build::EpubBuilder.localize_assets!(epub_dir, flavor: :epub)
        Build::EpubBuilder.localize_assets!(kindle_dir, flavor: :kindle)

        # kindle は WebP を同梱しない（transcode 済み・Kindle 非対応）
        refute File.exist?(File.join(kindle_dir, 'images/01/photo.webp')), 'kindle は本文画像の WebP を除外すべき'
        refute File.exist?(File.join(kindle_dir, 'stylesheets/twemoji/vs-techbook/circled-1.webp')),
               'kindle はスタイルシート配下の WebP も除外すべき'
        # クリーン EPUB は WebP を高画質のまま維持する（§4）
        assert File.exist?(File.join(epub_dir, 'images/01/photo.webp')), 'クリーン EPUB は WebP を維持すべき'
        assert File.exist?(File.join(epub_dir, 'stylesheets/twemoji/vs-techbook/circled-1.webp')),
               'クリーン EPUB は vs-techbook の WebP も維持すべき'
        # 非 WebP 画像は両フレーバで同梱する
        assert File.exist?(File.join(kindle_dir, 'images/01/pic.png')), 'kindle も PNG は同梱すべき'
        # twemoji 直下 svg（絵文字マスター）は両フレーバで除外、vs-techbook svg は維持
        [epub_dir, kindle_dir].each do |dir|
          refute File.exist?(File.join(dir, 'stylesheets/twemoji/1f004.svg')), 'twemoji 直下 svg を除外すべき'
          assert File.exist?(File.join(dir, 'stylesheets/twemoji/vs-techbook/mark.svg')),
                 'vs-techbook を巻き込む全除外はしないべき'
        end
        # ルートの生成物残骸（_epub_assets/・headings/）は拾わない（消費者 dir 内へ直接生成される）
        refute File.exist?(File.join(epub_dir, 'images/_epub_assets/stale.jpg')), 'ルートの _epub_assets は拾わない'
        refute File.exist?(File.join(epub_dir, 'images/headings/stale.svg')), 'ルートの headings は拾わない'
      end

      # --- EPF-12: 用語集 <dl> 直下のグループ見出し div を dl の外へ出し頭文字ごとに分割（RSC-005・§1-8） ---
      def test_should_split_glossary_groups_outside_dl
        html = <<~HTML
          <dl class="glossary-list">
            <div class="glossary-group-header" role="heading" aria-level="2">A-Z</div>
          <dt id="gls-x" class="glossary-term">X</dt><dd class="glossary-definition">定義</dd>
            <div class="glossary-group-header" role="heading" aria-level="2">あ行</div>
          <dt id="gls-a" class="glossary-term">あ</dt><dd class="glossary-definition">定義2</dd>
          </dl>
        HTML

        result = Build::EpubBuilder.split_glossary_groups_for_epub(html)

        refute_match(%r{<dl[^>]*>\s*<div class="glossary-group-header"}, result,
                     '<dl> 直下に見出し div が残ってはいけない（RSC-005）')
        assert_match(%r{<p class="glossary-group-header" role="heading" aria-level="2">A-Z</p>}, result,
                     '見出しは dl の外へ <p role=heading> として出る')
        assert_match(%r{<p class="glossary-group-header" role="heading" aria-level="2">あ行</p>}, result)
        assert_equal 2, result.scan('<dl class="glossary-list">').size, '頭文字ごとに dl が分割される'
        refute_match(%r{<dl class="glossary-list">\s*</dl>}, result, '空の dl は残らない')
        assert_includes result, '<dt id="gls-x" class="glossary-term">X</dt>', 'dt/dd は dl 内に保持'
      end

      # --- EPF-13: Kindle のインライン <style> から webp url() を除去（RSC-007・参照切れ回避） ---
      def test_should_strip_webp_url_from_inline_style_for_kindle
        html = <<~HTML
          <html><head><style>
          :root {
            --h3-marker: url("stylesheets/twemoji/vs-techbook/marker-h3.webp") !important;
            --code-font: var(--font-code);
          }
          </style></head><body><p>本文</p></body></html>
        HTML
        path = File.join(@test_dir, '00-preface.html')
        File.write(path, html)

        Build::EpubBuilder.strip_webp_inline_styles_for_kindle!([path])

        result = File.read(path)
        refute_includes result, '.webp', 'インライン style から webp 参照が除去される'
        refute_includes result, '--h3-marker', 'webp を含む宣言ごと除去される'
        # 数字入りカスタムプロパティ名が途中切れして断片（--h3 等）が残ると CSS-008 になる
        refute_match(/--h3|--h4|--subtitle/, result, '宣言の断片が残ってはいけない（CSS-008 回避）')
        assert_includes result, '--code-font: var(--font-code)', 'webp を含まない宣言は残る'
      end

      private

      # ローカライズ検証用の stylesheets/ ソースツリーを作る。
      def create_stylesheet_fixture
        FileUtils.mkdir_p('stylesheets/twemoji/vs-techbook')
        FileUtils.mkdir_p('stylesheets/fonts')
        File.write('stylesheets/theme.css', 'body {}')
        File.write('stylesheets/twemoji/1f004.svg', '<svg/>')
        File.write('stylesheets/twemoji/vs-techbook/mark.svg', '<svg/>')
        File.write('stylesheets/twemoji/vs-techbook/circled-1.webp', 'webp')
        File.write('stylesheets/fonts/zen.ttf', 'font')
      end

      # ローカライズ検証用の images/ ソースツリーを作る（生成物の残骸を含む）。
      def create_image_fixture
        FileUtils.mkdir_p('images/01')
        FileUtils.mkdir_p('images/_epub_assets')
        FileUtils.mkdir_p('images/headings')
        File.write('images/01/photo.webp', 'webp')
        File.write('images/01/pic.png', 'png')
        File.write('images/_epub_assets/stale.jpg', 'jpg')
        File.write('images/headings/stale.svg', '<svg/>')
      end

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
