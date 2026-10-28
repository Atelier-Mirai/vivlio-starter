# frozen_string_literal: true

# ================================================================
# Test: epub_builder_test.rb
# ================================================================
# テスト対象:
#   Build::EpubBuilder（lib/vivlio_starter/cli/build/epub_builder.rb）
#   EpubCommands（lib/vivlio_starter/cli/epub.rb）
#
# 検証内容:
#   - EPUB 用 entries.js の生成（目次・裏表紙の除外）
#   - EPUB 用 vivliostyle.config.js の生成（cover 埋め込み制御）
#   - epub_target? の判定
#   - EPUB ファイル名の生成
#   - html/ → 消費者 dir ステージング（asset_prefix 剥がし・P4 段階 4）
# ================================================================

require 'test_helper'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/build'
require 'vivlio_starter/cli/epub'

module VivlioStarter
  module CLI
    # ================================================================
    # EpubBuilder のユニットテスト
    # ================================================================
    class EpubBuilderTest < Minitest::Test
      def setup
        @base_dir = '.'
        @original_dir = Dir.pwd
        @test_dir = Dir.mktmpdir('epub_builder_test')
        Dir.chdir(@test_dir)

        # テスト用 HTML ファイルを生成
        create_test_html('00-preface.html', '前書き')
        create_test_html('_toc.html', '目次')
        create_test_html('01-intro.html', 'はじめに')
        create_test_html('02-basics.html', '基礎')
        create_test_html('99-postface.html', '後書き')
        create_test_html('_colophon.html', '奥付')
      end

      def teardown
        Dir.chdir(@original_dir)
        FileUtils.rm_rf(@test_dir)
      end

      # 扉絵/節絵注入テスト用の context。扉絵も節絵も横長（landscape）の画像を使う
      def heading_context(flavor: :kindle)
        {
          frontispiece: 'dummy_landscape.webp',
          ornament: 'dummy_landscape.webp',
          font_family: "'Noto Sans JP', sans-serif",
          number_color: '#f0a000',
          flavor:
        }
      end

      # 目次（_toc）が EPUB entries から除外されることを確認
      def test_excluded_basename_toc
        assert Build::EpubBuilder.excluded_basename?('_toc.html'),
               '_toc.html は EPUB から除外されるべき'
      end

      # 通常の章は除外されないことを確認
      def test_excluded_basename_normal_chapter
        refute Build::EpubBuilder.excluded_basename?('01-intro.html'),
               '通常の章は除外されないべき'
      end

      # 奥付は除外されないことを確認
      def test_excluded_basename_colophon
        refute Build::EpubBuilder.excluded_basename?('_colophon.html'),
               '奥付は EPUB に含めるべき'
      end

      # 本文章（番号 1..89）の h1（扉絵）・h2（節絵）が合成画像 <img> へ置換され、
      # 見出しテキストが alt に格納されることを確認。render は librsvg/ImageMagick と実画像に
      # 依存するため、ここではスタブして EpubBuilder の注入ロジックを検証する。
      def test_inject_heading_images_rewrites_chapter_and_section_headings
        File.write('10-spring.html', <<~HTML)
          <!DOCTYPE html><html><head><title>春</title></head><body>
          <h1 data-chapter-number-display="第1章" data-chapter-title="春のお花見">
            <span class="chapter-number">第1章</span><span class="chapter-title">春のお花見</span>
          </h1>
          <div class="chapter-lead"><p>春の章のリード文です。</p></div>
          <article class="section-topic">
            <h2 data-section-number-display="1-1" data-section-title="導入">
              <span class="section-number">1-1</span><span class="section-title">導入</span>
            </h2>
          </article>
          </body></html>
        HTML

        # flavor: :kindle は合成画像を JPEG（render）で焼き込む経路。クリーン EPUB（:epub）は
        # 合成 SVG（compose）を配るため別経路（Step ④ のテストで検証）。
        context = heading_context(flavor: :kindle)

        Build::HeadingImageComposer.stub(:render, 'FAKEJPEGBYTES') do
          Build::EpubBuilder.inject_heading_images_into_file!('10-spring.html', context)
        end

        html = File.read('10-spring.html')
        # h1 に EPUB クラスと合成画像 <img>（JPEG）が入る
        assert_match(%r{<h1[^>]*class="[^"]*vs-image-heading-epub}, html)
        assert_includes html, 'class="vs-image-heading-img"'
        # 見出しテキストが alt に格納される。リードは焼き込まないので alt に入れない
        assert_includes html, 'alt="第1章 春のお花見"'
        refute_includes html, 'vs-visually-hidden', '隠し span（clip）は使わない'
        # リードは扉絵の次に本文の文字として残る（chapter-lead-size-spec.md §2.2.1）
        assert_match %r{class="chapter-lead"><p>春の章のリード文です。</p>}, html
        assert_operator html.index('vs-image-heading-img'), :<, html.index('chapter-lead'), 'リードは扉絵の後'
        # 裾飾り（旧方式）は全廃した
        refute_includes html, 'vs-frontispiece-tail', '裾飾りは廃止済み'
        # 節絵: 親 article に EPUB 用クラス、h2 に画像（alt に節番号＋タイトル）
        assert_includes html, 'vs-section-topic-epub'
        assert_includes html, 'alt="1-1 導入"'
        # 合成画像が images/headings/ に JPEG として書き出される
        assert Dir.glob('images/headings/frontispiece-*.jpg').any?, '扉絵 JPEG が書き出されるべき'
        assert Dir.glob('images/headings/ornament-*.jpg').any?, '節絵 JPEG が書き出されるべき'
      end

      # 冪等: 既に vs-image-heading-epub の付いた h1 は再注入されず、リードもそのまま残る
      def test_inject_heading_images_is_idempotent
        File.write('11-summer.html', <<~HTML)
          <!DOCTYPE html><html><head><title>夏</title></head><body>
          <h1 data-chapter-number-display="第2章" data-chapter-title="夏">
            <span class="chapter-title">夏</span>
          </h1>
          <div class="chapter-lead"><p>夏のリード。</p></div>
          </body></html>
        HTML

        context = heading_context(flavor: :kindle)
        Build::HeadingImageComposer.stub(:render, 'FAKEJPEGBYTES') do
          Build::EpubBuilder.inject_heading_images_into_file!('11-summer.html', context)
          first = File.read('11-summer.html')
          Build::EpubBuilder.inject_heading_images_into_file!('11-summer.html', context)
          second = File.read('11-summer.html')

          assert_equal first, second, '2 回目の注入で HTML は変化しない'
          assert_includes second, 'alt="第2章 夏"'
          assert_includes second, '<p>夏のリード。</p>', 'リードは本文の文字のまま'
        end
      end

      # 合成失敗（render が nil）時は h1 も chapter-lead も実テキストのまま残る（simple 縮退）
      def test_inject_heading_images_degrades_when_compose_fails
        File.write('12-autumn.html', <<~HTML)
          <!DOCTYPE html><html><head><title>秋</title></head><body>
          <h1 data-chapter-number-display="第3章" data-chapter-title="秋">
            <span class="chapter-title">秋</span>
          </h1>
          <div class="chapter-lead"><p>秋のリード。</p></div>
          </body></html>
        HTML

        context = heading_context(flavor: :kindle)
        Build::HeadingImageComposer.stub(:render, nil) do
          Build::EpubBuilder.inject_heading_images_into_file!('12-autumn.html', context)
        end

        html = File.read('12-autumn.html')
        refute_includes html, 'vs-image-heading-epub', '合成失敗時は画像化しない'
        assert_includes html, 'chapter-lead', 'リードは実テキストのまま残る'
      end

      # リード内のインライン数式は画像に焼き込まず、本文の数式のまま残す。以前は alt の
      # 文字列で章扉へ焼き込み、警告を出していた
      def test_inject_heading_images_keeps_inline_math_in_lead
        File.write('13-winter.html', <<~HTML)
          <!DOCTYPE html><html><head><title>冬</title></head><body>
          <h1 data-chapter-number-display="第4章" data-chapter-title="冬"></h1>
          <div class="chapter-lead"><p>公式 <img class="vs-math-inline" alt="$E=mc^2$"> が有名です。</p></div>
          </body></html>
        HTML

        warned = []
        Common.stub(:log_warn, ->(msg, **_) { warned << msg }) do
          Build::HeadingImageComposer.stub(:render, 'FAKEJPEGBYTES') do
            Build::EpubBuilder.inject_heading_images_into_file!('13-winter.html', heading_context)
          end
        end

        html = File.read('13-winter.html')
        assert_includes html, 'alt="第4章 冬"'
        assert_match(/chapter-lead.*<img class="vs-math-inline" alt="\$E=mc\^2\$">/m, html)
        assert_empty warned
      end

      # 付録（番号 90..98）には扉絵/節絵を注入せず simple 版にすることを確認（PDF と整合）
      def test_inject_heading_images_skips_appendix_chapters
        File.write('94-sample.html', <<~HTML)
          <!DOCTYPE html><html><head><title>付録</title></head><body>
          <h1 data-chapter-number-display="付録 A" data-chapter-title="サンプル">
            <span class="chapter-title">サンプル</span>
          </h1>
          </body></html>
        HTML

        context = { frontispiece: 'x.webp', ornament: nil, font_family: 'sans-serif', number_color: '#333' }

        Build::HeadingImageComposer.stub(:render, 'FAKEJPEGBYTES') do
          Build::EpubBuilder.inject_heading_images_into_file!('94-sample.html', context)
        end

        html = File.read('94-sample.html')
        refute_includes html, 'vs-image-heading-epub', '付録は simple 版（画像注入しない）'
      end

      # 番号を持たない見出し（前付など）には扉絵を注入しないことを確認
      def test_inject_heading_images_skips_headings_without_number
        File.write('00-preface.html', <<~HTML)
          <!DOCTYPE html><html><head><title>前書き</title></head><body>
          <h1><span class="chapter-title">前書き</span></h1>
          </body></html>
        HTML

        context = { frontispiece: 'x.webp', ornament: nil, font_family: 'sans-serif', number_color: '#333' }

        Build::HeadingImageComposer.stub(:render, 'FAKEJPEGBYTES') do
          Build::EpubBuilder.inject_heading_images_into_file!('00-preface.html', context)
        end

        html = File.read('00-preface.html')
        refute_includes html, 'vs-image-heading-epub', '番号なし見出し（前付）には注入しない'
      end

      # EPUB の節題は、章題に対する大きさの比を PDF にそろえた字数で組む。A4 の PDF では
      # 節題（14 字）は章題の 0.73 倍。横長の扉絵の章題（10 字・幅の 6%）にその比を掛けると、
      # 節題は 1 行 18 字になる（chapter-lead-size-spec.md §2.2.1）。判型が読めないときは A4 相当
      def test_epub_ornament_chars_keeps_pdf_title_ratio
        PreProcessCommands::BookSettingsCss.stub(:build_page_cfg, {}) do
          assert_in_delta 18.0, Build::EpubBuilder.epub_ornament_chars(10, 14), 0.01
          # 章題の字数が少ないと帯の章題は上限の大きさ（幅の 7.5%）で止まり、節題もそのぶん大きい
          assert_in_delta 14.4, Build::EpubBuilder.epub_ornament_chars(8, 14), 0.01
          # 節題の字数を増やした著者の指定は、EPUB でも小さくなる向きに効く
          assert_operator Build::EpubBuilder.epub_ornament_chars(10, 18), :>, 18.0
        end
      end

      # EPUB の扉絵は theme.frontispiece.image の横長版を使う（縦長版は PDF の章扉の背景）
      def test_frontispiece_landscape_path_uses_landscape_variant_of_frontispiece_image
        calls = []
        resolver = lambda do |source, **opts|
          calls << [source, opts]
          'x'
        end
        PreProcessCommands::ThemeImageResolver.stub(:resolve_ornament_path, resolver) do
          Build::EpubBuilder.frontispiece_landscape_path({ theme_cfg: { frontispiece: { image: 'ume' } } })
          Build::EpubBuilder.frontispiece_landscape_path({ theme_cfg: { frontispiece: 'suisen' } })
        end

        assert_equal [['ume', { allow_generation: true }], ['suisen', { allow_generation: true }]], calls
      end

      # Kindle 数式テキスト化: 単純式 img は span 化され、複雑式 img は無傷で残る
      def test_textify_simple_math_replaces_only_convertible_formulas
        File.write('30-math.html', <<~HTML)
          <!DOCTYPE html><html><head><title>数式</title></head><body class="vs-kindle">
          <p>質量エネルギー <img class="vs-math vs-math-inline" src="images/math/30/a.svg" alt="$E=mc^2$" style="height: 1.2ex" width="52" height="17"> です。</p>
          <p>入れ子 <img class="vs-math vs-math-inline" src="images/math/30/b.svg" alt="$x^{y^z}$" style="height: 2ex" width="20" height="30"> は残る。</p>
          </body></html>
        HTML

        Build::EpubBuilder.textify_simple_math_for_kindle!(['30-math.html'])
        html = File.read('30-math.html')

        # 単純式はテキスト span へ（img が消える）
        assert_includes html, '<span class="vs-math vs-math-text"><i>E</i>=<i>mc</i><sup>2</sup></span>'
        # テキストで表せない式（上下付きの 2 段入れ子）は img のまま無傷（px 属性も保持）
        assert_includes html, 'alt="$x^{y^z}$"'
        assert_includes html, 'width="20"'
        assert_equal 1, html.scan('vs-math-inline').size, 'テキスト化できた式だけが img から消える'
      end

      # alt のデリミタは $…$ / \(…\) の 2 形式とも剥がす
      def test_textify_simple_math_strips_both_delimiter_forms
        File.write('31-math.html', <<~HTML)
          <!DOCTYPE html><html><head><title>数式</title></head><body class="vs-kindle">
          <p><img class="vs-math vs-math-inline" src="a.svg" alt="$\\gamma$">
          <img class="vs-math vs-math-inline" src="b.svg" alt="\\(\\gamma\\)"></p>
          </body></html>
        HTML

        Build::EpubBuilder.textify_simple_math_for_kindle!(['31-math.html'])
        html = File.read('31-math.html')

        assert_equal 2, html.scan('vs-math-text').size, '$…$ と \\(…\\) の両形式が span 化される'
        refute_includes html, 'vs-math-inline', 'img は残らない'
      end

      # 素の表記から起こした式は data-vs-tex の TeX を読む（plain-math-notation-spec.md §7.6）。
      # alt は著者の原文なので、そこから読むと MathTextRenderer が `²` で式全体を拒否し、
      # Kindle が px 固定 SVG へ落ちてフォントサイズに追従しなくなる。
      def test_textify_simple_math_prefers_the_transpiled_tex_over_alt
        File.write('33-math.html', <<~HTML)
          <!DOCTYPE html><html><head><title>数式</title></head><body class="vs-kindle">
          <p><img class="vs-math vs-math-inline" src="a.svg" alt="$x²+y²$" data-vs-tex="x^{2}+y^{2}"></p>
          </body></html>
        HTML

        Build::EpubBuilder.textify_simple_math_for_kindle!(['33-math.html'])
        html = File.read('33-math.html')

        assert_includes html, '<i>x</i><sup>2</sup>+<i>y</i><sup>2</sup>'
        refute_includes html, 'vs-math-inline', '素の表記でもテキスト化される'
      end

      # data-vs-tex が無ければ従来どおり alt から読む（属性の無い既存 HTML との後方互換）
      def test_textify_simple_math_falls_back_to_alt_without_the_tex_attribute
        File.write('34-math.html', <<~HTML)
          <!DOCTYPE html><html><head><title>数式</title></head><body class="vs-kindle">
          <p><img class="vs-math vs-math-inline" src="a.svg" alt="$E=mc^2$"></p>
          </body></html>
        HTML

        Build::EpubBuilder.textify_simple_math_for_kindle!(['34-math.html'])

        assert_includes File.read('34-math.html'), '<i>E</i>=<i>mc</i><sup>2</sup>'
      end

      # 素の表記で書かれた式は、MathTextRenderer が拒否しても**著者の原文テキスト**へ落とす
      # （plain-math-notation-spec.md §3-2.3）。SVG へ落とすと Kindle でフォントサイズに
      # 追従しなくなり、変換器を入れる前より悪くなる（実測 34 種の退行）。
      def test_textify_falls_back_to_the_author_source_when_the_renderer_rejects
        File.write('35-math.html', <<~HTML)
          <!DOCTYPE html><html><head><title>数式</title></head><body class="vs-kindle">
          <p><img class="vs-math vs-math-inline" src="a.svg" alt="$x^(y^z)$" data-vs-tex="x^{y^{z}}"></p>
          <p><img class="vs-math vs-math-inline" src="b.svg" alt="$vec v$" data-vs-tex="\\vec{v}"></p>
          </body></html>
        HTML

        Build::EpubBuilder.textify_simple_math_for_kindle!(['35-math.html'])
        html = File.read('35-math.html')

        assert_includes html, '<span class="vs-math vs-math-text vs-math-plain">x^(y^z)</span>'
        assert_includes html, '<span class="vs-math vs-math-text vs-math-plain">vec v</span>'
        refute_includes html, 'vs-math-inline', '原文テキストへ落ちるので img は残らない'
      end

      # LaTeX で書かれた式には原文を使えない（`\sqrt{2}` と出てしまう）。SVG のまま残す。
      def test_textify_keeps_svg_for_latex_authored_formulas_it_cannot_render
        File.write('36-math.html', <<~HTML)
          <!DOCTYPE html><html><head><title>数式</title></head><body class="vs-kindle">
          <p><img class="vs-math vs-math-inline" src="a.svg" alt="$x^{y^z}$" width="20" height="30"></p>
          </body></html>
        HTML

        Build::EpubBuilder.textify_simple_math_for_kindle!(['36-math.html'])
        html = File.read('36-math.html')

        assert_includes html, 'vs-math-inline', 'SVG のまま残る'
        assert_includes html, 'width="20"', 'px フォールバックも保つ'
      end

      # 通る式は今までどおり HTML（変数が斜体・真の <sup>）。原文テキストへ落とさない。
      def test_textify_prefers_html_over_the_author_source
        File.write('37-math.html', <<~HTML)
          <!DOCTYPE html><html><head><title>数式</title></head><body class="vs-kindle">
          <p><img class="vs-math vs-math-inline" src="a.svg" alt="$x²+y²$" data-vs-tex="x^{2}+y^{2}"></p>
          </body></html>
        HTML

        Build::EpubBuilder.textify_simple_math_for_kindle!(['37-math.html'])
        html = File.read('37-math.html')

        assert_includes html, '<i>x</i><sup>2</sup>+<i>y</i><sup>2</sup>'
        refute_includes html, 'vs-math-plain', '通る式は HTML 経路を使う'
      end

      # 日本語を含む式も Kindle からは SVG（<text> 入り）が消える。単純なら HTML へ、
      # サブセット外を含むなら原文テキストへ落ちる。どちらも画像ではないので追従する。
      def test_textify_handles_formulas_containing_japanese
        File.write('38-math.html', <<~HTML)
          <!DOCTYPE html><html><head><title>数式</title></head><body class="vs-kindle">
          <p><img class="vs-math vs-math-inline" src="a.svg" alt="$平文^e mod n$" data-vs-tex="平文^{e} \\bmod n"></p>
          <p><img class="vs-math vs-math-inline" src="b.svg" alt="$下限 = vec p$" data-vs-tex="下限 = \\vec{p}"></p>
          </body></html>
        HTML

        Build::EpubBuilder.textify_simple_math_for_kindle!(['38-math.html'])
        html = File.read('38-math.html')

        # 単純な日本語入りの式は真の上付き付きの HTML になる
        assert_includes html, '平文<sup><i>e</i></sup> mod <i>n</i>'
        # \sqrt を含むものは原文テキストへ
        assert_includes html, '<span class="vs-math vs-math-text vs-math-plain">下限 = vec p</span>'
        refute_includes html, 'vs-math-inline'
      end

      # HTML 予約文字は退避する（原文をそのまま流し込まない）。
      def test_textify_escapes_html_characters_in_the_author_source
        File.write('39-math.html', <<~HTML)
          <!DOCTYPE html><html><head><title>数式</title></head><body class="vs-kindle">
          <p><img class="vs-math vs-math-inline" src="a.svg" alt="$a<b & vec c$" data-vs-tex="a&lt;b \\&amp; \\vec{c}"></p>
          </body></html>
        HTML

        Build::EpubBuilder.textify_simple_math_for_kindle!(['39-math.html'])
        html = File.read('39-math.html')

        assert_includes html, 'a&lt;b &amp; vec c'
        refute_includes html, '<b &'
      end

      # ディスプレイ数式は Kindle で PNG へ差し替える（plain-math-notation-spec.md §3-2.4）。
      # Σ・∫ を含む大きな式の組版を保つため、テキスト化はしない。
      def test_rasterize_display_math_replaces_the_svg_reference
        skip 'rsvg-convert が無い環境ではラスター化を検証できない' unless
          system('rsvg-convert', '--version', out: File::NULL, err: File::NULL)

        rel = 'images/math/90-x'
        FileUtils.mkdir_p(File.join(VivlioStarter::CLI::Common::BUILD_HTML_DIR, rel))
        svg = File.join(VivlioStarter::CLI::Common::BUILD_HTML_DIR, rel, 'abc.svg')
        File.write(svg, '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 20">' \
                        '<rect width="100" height="20" fill="black"/></svg>')

        File.write('40-math.html', <<~HTML)
          <!DOCTYPE html><html><head><title>数式</title></head><body class="vs-kindle">
          <figure class="vs-math vs-math-display">
          <img src="#{rel}/abc.svg" alt="$$Σx$$" style="width: 22.4ex; height: 3.2ex;">
          </figure>
          </body></html>
        HTML

        Build::EpubBuilder.rasterize_display_math_for_kindle!(['40-math.html'])
        html = File.read('40-math.html')

        assert_includes html, "#{rel}/abc.png", 'src が PNG を指す'
        refute_includes html, 'abc.svg'
        assert_includes html, 'width: 22.4ex', 'style は保つ（convert_math_units_for_epub! が px を足す）'
        assert_path_exists File.join(VivlioStarter::CLI::Common::BUILD_HTML_DIR, rel, 'abc.png')
      ensure
        FileUtils.rm_rf(File.join(VivlioStarter::CLI::Common::BUILD_HTML_DIR, rel.to_s)) if rel
        FileUtils.rm_rf(VivlioStarter::CLI::PreProcessCommands::GeneratedAssetCache.dir('math-png'))
      end

      # インライン数式は対象外（テキスト化か SVG のまま）。
      def test_rasterize_display_math_leaves_inline_math_alone
        File.write('41-math.html', <<~HTML)
          <!DOCTYPE html><html><head><title>数式</title></head><body class="vs-kindle">
          <p><img class="vs-math vs-math-inline" src="images/math/90-x/z.svg" alt="$x$"></p>
          </body></html>
        HTML

        Build::EpubBuilder.rasterize_display_math_for_kindle!(['41-math.html'])

        assert_includes File.read('41-math.html'), 'z.svg', 'インラインは触らない'
      end

      # 冪等: 置換後は vs-math-inline が消えるので再実行しても変化しない
      def test_textify_simple_math_is_idempotent
        File.write('32-math.html', <<~HTML)
          <!DOCTYPE html><html><head><title>数式</title></head><body class="vs-kindle">
          <p><img class="vs-math vs-math-inline" src="a.svg" alt="$x^2$"></p>
          </body></html>
        HTML

        Build::EpubBuilder.textify_simple_math_for_kindle!(['32-math.html'])
        first = File.read('32-math.html')
        Build::EpubBuilder.textify_simple_math_for_kindle!(['32-math.html'])
        second = File.read('32-math.html')

        assert_equal first, second
      end

      # EPUB entries.js が正しく書き出されることを確認
      def test_write_epub_entries_creates_file
        html_files = ['./01-intro.html', './02-basics.html']
        Build::EpubBuilder.write_epub_entries(@base_dir, html_files)

        entries_path = File.join(@base_dir, Build::EpubBuilder::EPUB_ENTRIES_FILE)
        assert File.exist?(entries_path), 'entries.epub.js が生成されるべき'

        content = File.read(entries_path)
        assert_match(/export default \[/, content)
        assert_match(/01-intro/, content)
        assert_match(/02-basics/, content)
        # _toc が含まれていないことを確認
        refute_match(/_toc/, content)
      end

      # cover.embed: true の場合に cover 行が出力されることを確認
      def test_build_cover_config_line_with_embed_true
        epub_cfg = build_epub_config(embed: true)
        esc = ->(s) { s.to_s }

        # カバー画像ファイルを生成（生成物は生成キャッシュに置かれる・移設仕様 §3.2）
        FileUtils.mkdir_p(Common.cover_cache_dir)
        File.write(File.join(Common.cover_cache_dir, 'cover_light.jpg'), 'dummy')

        config = build_config_with_epub(epub_cfg, covers_dir: 'covers')
        Common.stub(:epub_embed?, true) do
          Common.stub(:cover_theme, 'light') do
            line = Build::EpubBuilder.build_cover_config_line(config, esc)

            assert_match(/cover:/, line, 'cover.embed: true の場合 cover 行が出力されるべき')
            assert_match(%r{covers/cover_light\.jpg}, line)
          end
        end
      end

      # cover.embed: false の場合に cover 行がコメントアウトされることを確認
      def test_build_cover_config_line_with_embed_false
        epub_cfg = build_epub_config(embed: false)
        esc = ->(s) { s.to_s }

        config = build_config_with_epub(epub_cfg)
        Common.stub(:epub_embed?, false) do
          line = Build::EpubBuilder.build_cover_config_line(config, esc)

          assert_match(/epub\.embed: false/, line, 'cover.embed: false の場合コメントになるべき')
        end
      end

      # 生成バリアント webp が book-settings.css の url() 参照分だけ
      # パッケージ theme-images/ へ同梱されることを確認（generated-assets 移設仕様 §3.2）
      def test_localize_theme_variant_images_copies_referenced_variants
        cache_root = File.join(Common::CACHE_DIR, 'theme-images')
        FileUtils.mkdir_p(File.join(cache_root, 'bundled'))
        File.write(File.join(cache_root, 'bundled', 'sakura_landscape.webp'), 'ref')
        File.write(File.join(cache_root, 'bundled', 'himawari_portrait.webp'), 'unref')
        FileUtils.mkdir_p(Common::CACHE_DIR)
        File.write(PreProcessCommands::BookSettingsCss.output_path, <<~CSS)
          :root { --section-bg-image: url("theme-images/bundled/sakura_landscape.webp"); }
        CSS

        dir = 'pkg-epub'
        FileUtils.mkdir_p(dir)
        Build::EpubBuilder.localize_theme_variant_images!(dir, :epub)

        assert_path_exists File.join(dir, 'theme-images', 'bundled', 'sakura_landscape.webp'),
                           'CSS が参照するバリアントは同梱されるべき'
        refute_path_exists File.join(dir, 'theme-images', 'bundled', 'himawari_portrait.webp'),
                           'CSS が参照しないバリアントは同梱しないべき'
      end

      # kindle フレーバでは WebP 非対応のため theme-images を同梱しないことを確認
      def test_localize_theme_variant_images_skips_kindle
        cache_root = File.join(Common::CACHE_DIR, 'theme-images')
        FileUtils.mkdir_p(File.join(cache_root, 'bundled'))
        File.write(File.join(cache_root, 'bundled', 'sakura_landscape.webp'), 'ref')
        FileUtils.mkdir_p(Common::CACHE_DIR)
        File.write(PreProcessCommands::BookSettingsCss.output_path, <<~CSS)
          :root { --section-bg-image: url("theme-images/bundled/sakura_landscape.webp"); }
        CSS

        dir = 'pkg-kindle'
        FileUtils.mkdir_p(dir)
        Build::EpubBuilder.localize_theme_variant_images!(dir, :kindle)

        refute_path_exists File.join(dir, 'theme-images'), 'kindle には theme-images を同梱しないべき'
      end

      # html/ → 消費者 dir のステージングで asset_prefix が剥がれることを確認（P4 段階 4）
      def test_stage_consumer_htmls_strips_asset_prefix
        FileUtils.mkdir_p(Common::BUILD_HTML_DIR)
        File.write(File.join(Common::BUILD_HTML_DIR, '01-intro.html'), <<~HTML)
          <html><head>
          <link rel="stylesheet" href="#{Common::ASSET_PREFIX}stylesheets/theme.css">
          </head><body><img src="#{Common::ASSET_PREFIX}images/01/a.webp"></body></html>
        HTML

        Build::EpubBuilder.stage_consumer_htmls!(Common::BUILD_EPUB_DIR)

        staged = File.read(File.join(Common::BUILD_EPUB_DIR, '01-intro.html'))
        assert_includes staged, 'href="stylesheets/theme.css"', 'CSS 参照はパッケージルート相対になるべき'
        assert_includes staged, 'src="images/01/a.webp"', '画像参照はパッケージルート相対になるべき'
        refute_includes staged, Common::ASSET_PREFIX, 'asset_prefix は残らないべき'
      end

      private

      # テスト用の HTML ファイルを作成する
      def create_test_html(filename, title)
        File.write(filename, <<~HTML)
          <!DOCTYPE html>
          <html><head><title>#{title}</title></head>
          <body><h1>#{title}</h1></body></html>
        HTML
      end

      # epub 設定のモック Data オブジェクトを構築する
      def build_epub_config(embed: true)
        cover = Struct.new(:embed, :image, keyword_init: true).new(embed:, image: 'cover.jpg')
        Struct.new(:cover, :layout, keyword_init: true).new(cover:, layout: 'reflowable')
      end

      # CONFIG に近い構造のモック Data オブジェクトを構築する
      def build_config_with_epub(epub_cfg, covers_dir: 'covers')
        directories = Struct.new(:covers, keyword_init: true).new(covers: covers_dir)
        output = Struct.new(:epub, keyword_init: true).new(epub: epub_cfg)
        Struct.new(:output, :directories, keyword_init: true).new(output:, directories:)
      end

    end

    # ================================================================
    # EPUB config メタデータ解決の一本化（P3-4 §2.6）
    # ================================================================
    # generate_epub_config! の title/author/language が VivliostyleConfigWriter の
    # リゾルバ（ルート config・パイプライン config と共通の単一の解決規則）から
    # 生成されることを固定する。旧インライン解決との二重管理を防ぐ回帰網。
    class EpubConfigMetadataUnificationTest < Minitest::Test
      Writer = Build::VivliostyleConfigWriter
      LOG_METHODS = %i[log_info log_success log_warn log_error log_action].freeze

      def setup
        @original_dir = Dir.pwd
        @temp_dir = Dir.mktmpdir('epub-config-meta')
        Dir.chdir(@temp_dir)
        FileUtils.mkdir_p('config')
        %w[catalog page_presets].each { File.write("config/#{it}.yml", '{}') }
        @saved_logs = LOG_METHODS.to_h { [it, Common.method(it)] }
        LOG_METHODS.each { |m| Common.define_singleton_method(m) { |*_a, **_k| } }
      end

      def teardown
        @saved_logs.each { |m, impl| Common.define_singleton_method(m, impl) }
        Dir.chdir(@original_dir)
        FileUtils.rm_rf(@temp_dir)
        Common.reload_configuration!(silent: true) if File.file?('config/book.yml')
      end

      def config_metadata(book:)
        File.write('config/book.yml', { 'book' => book }.to_yaml)
        Common.reload_configuration!(silent: true)
        path = Build::EpubBuilder.generate_epub_config!(flavor: :epub, dir: @temp_dir)
        lines = File.readlines(path)
        %i[title author language].to_h do |key|
          line = lines.find { it =~ /^\s*#{key}:/ }
          [key, line[/'(.*)'/, 1]]
        end
      end

      # main_title + subtitle 構成: EPUB config の 3 値が writer のリゾルバと一致する
      def test_epub_config_metadata_matches_writer_resolvers
        meta = config_metadata(book: { 'main_title' => 'はじめての技術書', 'subtitle' => '実践ガイド',
                                       'author' => '早乙女 遙香', 'language' => 'ja' })

        assert_equal Writer.resolve_title, meta[:title]
        assert_equal Writer.resolve_author, meta[:author]
        assert_equal Writer.resolve_language, meta[:language]
        assert_equal 'はじめての技術書 実践ガイド', meta[:title]
      end

      # 副題に扉で改行させる <br> を書いても、書誌（PDF の文書情報・EPUB の dc:title）には入れない
      # （改善案.md #116）
      def test_epub_config_title_drops_line_break_tags
        meta = config_metadata(book: { "main_title" => "AIと学ぶモダンWebサイト入門",
                                       "subtitle" => "HTML/CSSグリッドと<br>やさしいJavaScriptの基本",
                                       "author" => "早乙女 遙香", "language" => "ja" })

        assert_equal "AIと学ぶモダンWebサイト入門 HTML/CSSグリッドとやさしいJavaScriptの基本", meta[:title]
      end

      # 著者名・言語・title キー未設定: 空文字もプレースホルダへ寄る（writer と同一規則）
      def test_epub_config_falls_back_to_placeholders_like_writer
        meta = config_metadata(book: { 'main_title' => 'T', 'author' => '', 'language' => '' })

        assert_equal '著者名', meta[:author]
        assert_equal 'ja', meta[:language]
        assert_equal Writer.resolve_author, meta[:author]
        assert_equal Writer.resolve_language, meta[:language]
      end
    end

    # ================================================================
    # EpubCommandRunner のユニットテスト
    # ================================================================
    class EpubCommandRunnerTest < Minitest::Test
      # build_command が指定された生成 config（消費者 dir 内）を --config で渡すことを確認
      def test_build_command_includes_consumer_dir_config
        runner = EpubCommands::EpubCommandRunner.new(
          {},
          config_path: '.cache/vs/build/epub/vivliostyle.config.epub.js',
          output_path: '.cache/vs/build/epub/output.epub'
        )
        cmd = runner.send(:build_command)

        assert_match(%r{--config \.cache/vs/build/epub/vivliostyle\.config\.epub\.js}, cmd,
                     '--config で消費者 dir 内の生成 config を指定するべき')
      end
    end

    # ================================================================
    # Targets.epub（旧 epub_target?）のユニットテスト
    # ================================================================
    class EpubTargetTest < Minitest::Test
      def setup
        @options = { clean: true, resize: true, compress: true, high: false, low: false }
        @command = Struct.new(:options).new(@options)
      end

      # targets に 'epub' を含む場合に epub_target? が true を返すことを確認
      def test_epub_target_true_when_epub_in_targets
        with_config_targets('pdf, epub') do
          pipeline = BuildCommands::UnifiedBuildPipeline.new(@command, entries: [], mode: :full)
          assert pipeline.targets.epub, 'epub が targets に含まれる場合 true を返すべき'
        end
      end

      # targets に 'epub' を含まない場合に epub_target? が false を返すことを確認
      def test_epub_target_false_when_no_epub_in_targets
        with_config_targets('pdf') do
          pipeline = BuildCommands::UnifiedBuildPipeline.new(@command, entries: [], mode: :full)
          refute pipeline.targets.epub, 'epub が targets にない場合 false を返すべき'
        end
      end

      # targets が 'epub' のみの場合に epub_target? が true を返すことを確認
      def test_epub_target_true_when_epub_only
        with_config_targets('epub') do
          pipeline = BuildCommands::UnifiedBuildPipeline.new(@command, entries: [], mode: :full)
          assert pipeline.targets.epub, 'epub のみの場合 true を返すべき'
        end
      end

      private

      # output.targets を一時的に書き換えるヘルパー
      def with_config_targets(targets_str)
        original_config = Common::CONFIG
        # extract_targets が受け取る文字列をモック
        mock_output = Struct.new(:targets, :pdf, :epub, keyword_init: true)
                            .new(targets: targets_str, pdf: nil, epub: nil)
        mock_config = Struct.new(:output, keyword_init: true).new(output: mock_output)

        # CONFIG を一時差し替え
        Common.const_set(:TEMP_ORIGINAL_CONFIG, original_config)
        Common.send(:remove_const, :CONFIG)
        Common.const_set(:CONFIG, mock_config)
        yield
      ensure
        Common.send(:remove_const, :CONFIG)
        Common.const_set(:CONFIG, Common.const_get(:TEMP_ORIGINAL_CONFIG))
        Common.send(:remove_const, :TEMP_ORIGINAL_CONFIG)
      end
    end

    # ================================================================
    # generate_epub_filename のユニットテスト
    # ================================================================
    class EpubFilenameTest < Minitest::Test
      # EPUB ファイル名が .epub 拡張子で生成されることを確認
      def test_generate_epub_filename_extension
        filename = Common.generate_epub_filename
        assert filename.end_with?('.epub'), "EPUB ファイル名は .epub で終わるべき: #{filename}"
      end
    end
  end
end
