# frozen_string_literal: true

# ================================================================
# Test: epub_builder_sanitize_test.rb
# ================================================================
# テスト対象:
#   Build::Epub::Opf・Build::Transforms の EPUB 構造修正フック
#   （epub-pipeline-fix-spec.md の Fix-1〜4 / §4.1 EPF-01〜05）
#
# 検証内容:
#   - EPF-03: 段落内脚注 span の id のみ除去（aside の id / data-footnote-number は残す）
#   - EPF-04: 絵文字 <img> に width/height 属性が無く style に寸法が入る
#   - EPF-05: generate_epub_config! が entryContext と dir 内 output を出力する（P4 段階 4）
#   - EPF-07: テーブルの align 属性が style の text-align へ変換される（Fix-6）
#   - EPF-08: content.opf の数字始まり id/idref に接頭辞が付く（Fix-7）
#   - EPF-09: フォント非埋め込み時に fonts/ を除外（P2 サイズ最適化）
#   - EPF-10: 埋め込み経路（embed_fonts? = true）では fonts/ を保持
#   EPUB の中の CSS から落とすもの（EPF-01・02・06・09 の @font-face・data URI）は、
#   平らな CSS を作る段の確かめ（css/target_filter_test.rb）へ移した。
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

      # --- EPF-03: 脚注 span の id のみ除去 ---
      def test_should_strip_inline_footnote_span_id_only
        html = <<~HTML
          <p>本文<span role="doc-footnote" class="page-footnote page-footnote-inline" id="fn1">注</span>続き</p>
          <aside role="doc-footnote" class="page-footnote page-footnote-print" id="fn1" data-footnote-number="1">注</aside>
        HTML
        path = File.join(@test_dir, '01-intro.html')
        File.write(path, html)

        apply_transform(Build::Transforms::Shared::StripInlineFootnoteIds, [path])

        result = File.read(path)
        refute_match(/page-footnote-inline[^>]*id="fn1"/, result, 'span 側の id は除去されるべき')
        assert_match(/page-footnote-print[^>]*id="fn1"/, result, 'aside 側の id は残すべき')
        assert_includes result, 'data-footnote-number="1"', 'data-footnote-number は残すべき'
      end

      # --- EPF-03b: 脚注 span の「中身」の id も除去（RSC-005 の再発防止） ---
      # footnote_converter は span と aside へ同じ本文 HTML を流し込む。脚注本文に
      # 索引語・用語集語があると、本文中で採番済みの idx-… / gls-src-… が両方へ
      # 複製されて id が重複する（実測: 22 章「CSS」・33 章「ノンブル」）。
      # 見えるのは aside 側なので（.page-footnote-inline は display:none）、
      # 控えである span からアンカーごと外す。
      def test_should_strip_index_anchors_inside_inline_footnote_copy
        html = <<~HTML
          <p>本文<span role="doc-footnote" class="page-footnote page-footnote-inline" id="fn1">W3C の <span id="idx-abc-19" class="index-term">CSS</span><a id="gls-src-22-ext-css-19" class="glossary-link" href="_glossarypage.html#gls-css"><sup>†</sup></a> 仕様</span>続き</p>
          <aside role="doc-footnote" class="page-footnote page-footnote-print" id="fn1" data-footnote-anchored="1">W3C の <span id="idx-abc-19" class="index-term">CSS</span><a id="gls-src-22-ext-css-19" class="glossary-link" href="_glossarypage.html#gls-css"><sup>†</sup></a> 仕様</aside>
        HTML
        path = File.join(@test_dir, '22-extensions.html')
        File.write(path, html)

        apply_transform(Build::Transforms::Shared::StripInlineFootnoteIds, [path])

        result = File.read(path)
        assert_equal 1, result.scan('id="idx-abc-19"').size, '索引アンカーは文書内で 1 つだけになるべき'
        assert_equal 1, result.scan('id="gls-src-22-ext-css-19"').size, '用語集アンカーは文書内で 1 つだけになるべき'
        assert_match(/page-footnote-print.*id="idx-abc-19"/m, result, '残すのは読者に見える aside 側')
        assert_includes result, 'CSS', '本文テキストは両方に残る（id だけを外す）'
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
        path = Build::Epub::Config.generate_epub_config!(dir:)
        content = File.read(path)

        assert_equal File.join(dir, 'vivliostyle.config.epub.js'), path, 'config は消費者 dir 内に生成されるべき'
        assert_includes content, "entryContext: '#{dir}'", 'entryContext は消費者 dir を指すべき'
        assert_includes content, "'#{dir}/output.epub'", 'output は消費者 dir 内を指すべき'
        refute_includes content, 'copyAsset:', 'copyAsset ブロックは出力しない（選択はローカライズが担う）'
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

        apply_transform(Build::Transforms::Shared::RewriteTableAlign, [path])

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

        # P2: content.opf zip 手術は Build::Epub::Opf にある。
        Build::Epub::Opf.sanitize_epub_opf_ids!(epub)

        result = read_css_from_epub(epub, 'EPUB/content.opf')
        assert_includes result, 'id="id-00-prefacexhtml"', '数字始まりの id に接頭辞が付くべき'
        assert_includes result, 'idref="id-00-prefacexhtml"', '対応する idref も同一規則で書き換わるべき'
        assert_includes result, 'id="bookid"', '英字始まりの id は不変であるべき'
        assert_includes result, 'idref="toc"', '英字始まりの idref は不変であるべき'
        assert_includes result, 'href="00-preface.xhtml"', 'href は変更しないべき'
      end

      # 目次の文書（nav）の中で自分自身を指すリンクに、章の印 #ch-… を付ける。
      # Kindle の変換はファイル名だけの自己リンクを解決できず W14001 を出していた。
      # ほかの文書へのリンクと、nav の外のリンクは変えない
      def test_should_anchor_self_link_in_nav_document
        opf = <<~XML
          <package><manifest>
            <item id="id-00-prefacexhtml" href="00-preface.xhtml" media-type="application/xhtml+xml" properties="nav"></item>
          </manifest></package>
        XML
        preface = <<~XHTML
          <html><body><section><h1 id="はじめに-">はじめに<span id="ch-preface" class="vs-sec-anchor"></span></h1>
          <p><a href="00-preface.xhtml">本文中の自己リンク</a></p></section>
          <nav id="toc" role="doc-toc" epub:type="toc" hidden=""><ol><li><a href="00-preface.xhtml">はじめに</a></li><li><a href="11-workflow.xhtml">執筆</a></li></ol></nav>
          </body></html>
        XHTML
        epub = build_epub_with_css('EPUB/content.opf' => opf, 'EPUB/00-preface.xhtml' => preface)

        Build::Epub::Opf.anchor_nav_self_link!(epub)

        result = read_css_from_epub(epub, 'EPUB/00-preface.xhtml')
        assert_includes result, '<li><a href="00-preface.xhtml#ch-preface">はじめに</a></li>'
        assert_includes result, '<li><a href="11-workflow.xhtml">執筆</a></li>'
        assert_includes result, '<p><a href="00-preface.xhtml">本文中の自己リンク</a></p>'
      end

      # --- EPF-09b: 非埋め込み時はローカライズが fonts/ をコピーしない（keyfont TTF を除く） ---
      def test_should_exclude_fonts_dir_when_not_embedding
        create_stylesheet_fixture
        dir = '.cache/vs/build/epub'

        Build::Epub::Workspace.localize_assets!(dir, flavor: :epub)

        refute File.exist?(File.join(dir, 'stylesheets/theme.css')),
               'CSS は運ばない（styles/ の平らな CSS だけを読む・css-layer-restructure-spec.md §4.2）'
        refute File.exist?(File.join(dir, 'stylesheets/fonts/zen.ttf')),
               '非埋め込み時 fonts/ はローカライズしないべき'
        assert File.exist?(File.join(dir, 'stylesheets/fonts/Keyboard_font/Keyboard-JP-Regular.ttf')),
               'keyfont TTF は非埋め込みでも同梱されるべき（kbd キーキャップ描画）'
        refute File.exist?(File.join(dir, 'stylesheets/fonts/Keyboard_font/Keyboard-JP-Regular.otf')),
               'keyfont の OTF 原本は運ばない'
      end

      # --- EPF-10: 埋め込み経路（embed_fonts? = true）では fonts/@font-face を保持 ---
      def test_should_keep_fonts_when_embedding_enabled
        create_stylesheet_fixture
        dir = '.cache/vs/build/epub'

        Build::Epub::Workspace.stub(:embed_fonts?, true) do
          Build::Epub::Workspace.localize_assets!(dir, flavor: :epub)

          assert File.exist?(File.join(dir, 'stylesheets/fonts/zen.ttf')),
                 '埋め込み時は fonts/ もローカライズすべき'
        end
      end

      # --- EPF-11: 絵文字 img をプレーン絵文字へ復元・囲み数字は維持（Fix-8） ---
      def test_should_restore_plain_emoji_but_keep_circled_numbers
        html = <<~HTML
          <p>OK <img src="stylesheets/twemoji/2705.svg" alt="✅" class="emoji vs-emoji" style="width: 1em; height: 1em;"> done</p>
          <p>No.<img src="stylesheets/twemoji/vs-techbook/circled-1.webp" alt="1" aria-label="1" class="emoji vs-emoji vs-circled-number" style="width: 1em; height: 1em;"></p>
        HTML
        path = File.join(@test_dir, '11-workflow.html')
        File.write(path, html)

        apply_transform(Build::Transforms::Shared::RestorePlainEmoji, [path])

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

        Build::Epub::Workspace.localize_assets!(epub_dir, flavor: :epub)
        Build::Epub::Workspace.localize_assets!(kindle_dir, flavor: :kindle)

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

        result = Build::Transforms::Shared::PostProcessIndexGlossary.split_glossary_groups(html)

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
            --book-marker-h3: url("stylesheets/twemoji/vs-techbook/marker-h3.webp") !important;
            --vs-plain-color: #333;
          }
          </style></head><body><p>本文</p></body></html>
        HTML
        path = File.join(@test_dir, '00-preface.html')
        File.write(path, html)

        apply_transform(Build::Transforms::Kindle::StripWebpInlineStyles, [path])

        result = File.read(path)
        refute_includes result, '.webp', 'インライン style から webp 参照が除去される'
        refute_includes result, '--book-marker-h3', 'webp を含む宣言ごと除去される'
        # 数字入りカスタムプロパティ名が途中切れして断片（--h3 等）が残ると CSS-008 になる
        refute_match(/--h3|--h4|--subtitle/, result, '宣言の断片が残ってはいけない（CSS-008 回避）')
        assert_includes result, '--vs-plain-color: #333', 'webp を含まない宣言は残る'
      end

      private

      # ローカライズ検証用の stylesheets/ ソースツリーを作る。
      def create_stylesheet_fixture
        FileUtils.mkdir_p('stylesheets/twemoji/vs-techbook')
        FileUtils.mkdir_p('stylesheets/fonts/Keyboard_font')
        File.write('stylesheets/theme.css', 'body {}')
        File.write('stylesheets/twemoji/1f004.svg', '<svg/>')
        File.write('stylesheets/twemoji/vs-techbook/mark.svg', '<svg/>')
        File.write('stylesheets/twemoji/vs-techbook/circled-1.webp', 'webp')
        File.write('stylesheets/fonts/zen.ttf', 'font')
        File.write('stylesheets/fonts/Keyboard_font/Keyboard-JP-Regular.ttf', 'keyfont')
        File.write('stylesheets/fonts/Keyboard_font/Keyboard-JP-Regular.otf', 'keyfont-otf')
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
      # content.opf などの手術は unzip/zip による実差し替えを行うため、
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
