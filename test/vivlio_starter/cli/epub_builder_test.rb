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

      # 扉絵/節絵注入テスト用の context（リードフォント・幅比も含む facsimile 仕様）
      def heading_context(flavor: :kindle)
        {
          frontispiece: 'dummy_portrait.webp',
          ornament: 'dummy_landscape.webp',
          font_family: "'Zen Kaku Gothic New', sans-serif",
          lead_font_family: "'Zen Old Mincho', serif",
          lead_ratio: 0.60,
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
        # 見出しテキスト＋リードが alt に格納（章扉画像へ焼き込んだリードの読み上げフォールバック）
        assert_includes html, 'alt="第1章 春のお花見 春の章のリード文です。"'
        refute_includes html, 'vs-visually-hidden', '隠し span（clip）は使わない'
        # リードは章扉画像へ焼き込むため HTML からは除去される（二重表示回避・facsimile 仕様）
        refute_includes html, 'chapter-lead', 'chapter-lead は焼き込み成功時に除去される'
        # 裾飾り（旧方式）は全廃した
        refute_includes html, 'vs-frontispiece-tail', '裾飾りは廃止済み'
        # 節絵: 親 article に EPUB 用クラス、h2 に画像（alt に節番号＋タイトル）
        assert_includes html, 'vs-section-topic-epub'
        assert_includes html, 'alt="1-1 導入"'
        # 合成画像が images/headings/ に JPEG として書き出される
        assert Dir.glob('images/headings/frontispiece-*.jpg').any?, '扉絵 JPEG が書き出されるべき'
        assert Dir.glob('images/headings/ornament-*.jpg').any?, '節絵 JPEG が書き出されるべき'
      end

      # 冪等: 既に vs-image-heading-epub の付いた h1 は再注入されず、リードが空合成へ差し替わらない
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
          assert_includes second, 'alt="第2章 夏 夏のリード。"', 'リードが空合成へ差し替わっていない'
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

      # リード内のインライン数式 <img> は alt（元 LaTeX・デリミタ除去）で焼き込まれる
      def test_extract_lead_text_absorbs_inline_math_alt
        doc = PostProcessCommands::HtmlParser.parse_html_document(<<~HTML)
          <!DOCTYPE html><html><body>
          <h1 data-chapter-number-display="第4章"></h1>
          <div class="chapter-lead"><p>公式 <img class="vs-math-inline" alt="$E=mc^2$"> が有名です。</p></div>
          </body></html>
        HTML
        lead_el = doc.css('div.chapter-lead').first

        warned = []
        Common.stub(:log_warn, ->(msg, **_) { warned << msg }) do
          text = Build::EpubBuilder.extract_lead_text(lead_el)
          assert_includes text, 'E=mc^2', 'デリミタを剥いだ式が焼き込まれる'
          refute_includes text, '$', 'デリミタ $ は残さない'
        end
        assert_equal 1, warned.size, '警告は 1 回'
        assert_includes lead_el.to_html, '<img', '元ノードは破壊しない（dup 処理）'
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

      # リード焼き込み幅比の純計算: lead_width ÷ 判型幅。導けない場合は 0.60 へフォールバック
      def test_lead_ratio_from_derives_or_falls_back
        assert_in_delta 88.0 / 148.0, Build::EpubBuilder.lead_ratio_from(88.0, 148.0), 0.001, '88/148 ≒ 0.595'
        assert_in_delta 0.60, Build::EpubBuilder.lead_ratio_from(nil, nil), 0.001, '幅欠落時は 0.60'
        assert_in_delta 0.60, Build::EpubBuilder.lead_ratio_from(88.0, 0), 0.001, '判型幅が非正なら 0.60'
        assert_in_delta 0.75, Build::EpubBuilder.lead_ratio_from(200.0, 210.0), 0.001, '上限 0.75 にクランプ'
        assert_in_delta 0.40, Build::EpubBuilder.lead_ratio_from(50.0, 210.0), 0.001, '下限 0.40 にクランプ'
      end

      # 実 CONFIG（preset 構成で page.width 未指定）では 0.60 にフォールバックする
      def test_frontispiece_lead_ratio_falls_back_on_preset_config
        assert_in_delta 0.60, Build::EpubBuilder.frontispiece_lead_ratio, 0.001
      end

      # Kindle 数式テキスト化: 単純式 img は span 化され、複雑式 img は無傷で残る
      def test_textify_simple_math_replaces_only_convertible_formulas
        File.write('30-math.html', <<~HTML)
          <!DOCTYPE html><html><head><title>数式</title></head><body class="vs-kindle">
          <p>質量エネルギー <img class="vs-math vs-math-inline" src="images/math/30/a.svg" alt="$E=mc^2$" style="height: 1.2ex" width="52" height="17"> です。</p>
          <p>根号 <img class="vs-math vs-math-inline" src="images/math/30/b.svg" alt="$\\sqrt{2}$" style="height: 2ex" width="20" height="30"> は残る。</p>
          </body></html>
        HTML

        Build::EpubBuilder.textify_simple_math_for_kindle!(['30-math.html'])
        html = File.read('30-math.html')

        # 単純式はテキスト span へ（img が消える）
        assert_includes html, '<span class="vs-math vs-math-text"><i>E</i>=<i>mc</i><sup>2</sup></span>'
        # 複雑式（\sqrt）は img のまま無傷（px 属性も保持）
        assert_includes html, 'alt="$\sqrt{2}$"'
        assert_includes html, 'width="20"'
        assert_equal 1, html.scan('vs-math-inline').size, '単純式だけが img から消える'
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

      # embed_cover? が nil（未設定）の場合 true を返すことを確認（デフォルト動作）
      def test_embed_cover_default_true
        epub_cfg = build_epub_config(embed: nil)
        assert Build::EpubBuilder.embed_cover?(epub_cfg),
               '未設定の場合はデフォルトで true を返すべき'
      end

      # embed_cover? が false の場合に false を返すことを確認
      def test_embed_cover_false
        epub_cfg = build_epub_config(embed: false)
        refute Build::EpubBuilder.embed_cover?(epub_cfg),
               'cover.embed: false の場合は false を返すべき'
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
