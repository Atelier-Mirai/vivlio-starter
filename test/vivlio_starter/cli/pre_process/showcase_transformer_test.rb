# frozen_string_literal: true

# ================================================================
# Test: showcase_transformer_test.rb
# ================================================================
# 検証内容（explanatory-diagram-spec.md §9）:
#   - :::{.showcase} ブロック → <figure class="vs-showcase"><img> 置換（統合）
#   - SVG とラスターが対で焼かれ、両方あるビルドでは再生成しない（キャッシュ）
#   - ラスター形式の自動判定: スクリーンショット → PNG / 写真 → JPEG
#   - 画像内容が変われば別キーになる（撮り直しで再生成される）
#   - コードフェンス内の作例は変換しない（記法の解説原稿を壊さない）
#   - 縮退経路: magick/rsvg 不在 → 注釈なしの通常画像＋警告（ツールガード不要・常時実行）
#   - 画像なし／2 枚以上のブロックの扱い
# 実画像を使う経路は fixtures の小さな PNG で行い、magick/rsvg 不在環境では skip する。
# ================================================================

require_relative '../../../test_helper'
require 'fileutils'
require 'tmpdir'
require 'vivlio_starter/cli/pre_process/showcase_transformer'

class ShowcaseTransformerTest < Minitest::Test
  T = VivlioStarter::CLI::PreProcessCommands::ShowcaseTransformer
  FIXTURE = File.expand_path('../../fixtures/showcase/editor.png', __dir__)

  # 外部ツールを一切持たない環境（縮退経路の検証用）。
  class NoTools
    def available? = false
    def image_dimensions(_path) = nil
    def photographic?(_path) = false
    def data_uri(_path) = nil
    def rasterize(_svg, _width, format: :png) = nil
  end

  # 呼び出し回数と要求形式を記録するフェイク。生成有無・キャッシュ・形式選択を観測する。
  class CountingTools
    attr_reader :rasterized, :formats

    # @param photo [Boolean] 元画像を写真と判定させるか（ラスター形式の選択を切り替える）
    def initialize(photo: false)
      @rasterized = 0
      @formats = []
      @photo = photo
    end

    def available? = true
    def image_dimensions(_path) = [400, 200]
    def photographic?(_path) = @photo
    def data_uri(_path) = 'data:image/png;base64,AAAA'

    def rasterize(_svg, _width, format: :png)
      @rasterized += 1
      @formats << format
      'RASTERBYTES'
    end
  end

  # プロジェクト構造（images/ と .cache/vs/build/html/）を持つ一時ディレクトリで実行する。
  def in_project
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir_p(File.join(dir, 'images', '10-intro'))
        FileUtils.cp(FIXTURE, File.join(dir, 'images', '10-intro', 'editor.png'))
        yield dir
      end
    end
  end

  # ImagePathNormalizer 通過後の形（asset_prefix 付き）でブロックを組み立てる。
  def block(annotations = "rect:1 190, 30, 360, 90 {pos=right} untitled タブの枠\n")
    <<~MD
      本文の前。

      :::{.showcase}
      ![エディタ画面](#{VivlioStarter::CLI::Common.asset_prefix}images/10-intro/editor.png){width=80% crop="10 20"}
      #{annotations}:::

      本文の後。
    MD
  end

  def showcase_dir(chapter_slug = '10-intro')
    File.join(VivlioStarter::CLI::Common::BUILD_HTML_DIR, 'images', 'showcase', chapter_slug)
  end

  def transform(content, tools:, chapter_slug: '10-intro')
    T.transform(content, chapter_slug:, source_filename: '10-intro.md', tools:)
  end

  def test_should_replace_the_block_with_a_figure_referencing_the_composed_svg
    in_project do
      result = transform(block, tools: CountingTools.new)

      assert_match(%r{<figure class="vs-showcase">}, result)
      # 参照は消費者 dir 相対（asset_prefix 無し・ビルド生成物のため）
      assert_match(%r{<img class="vs-showcase" src="images/showcase/10-intro/[0-9a-f]{16}\.svg"}, result)
      # 著者コメントは alt へ丸数字付きで集約される
      assert_match(/alt="エディタ画面: ① untitled タブの枠"/, result)
      # 画像属性の width が style へ写る
      assert_match(/style="width: 80%;"/, result)
      # ブロックの外の本文は保たれ、figure は独立段落になる
      assert_match(/本文の前。/, result)
      assert_match(/本文の後。/, result)
      refute_match(/:::/, result)
    end
  end

  def test_should_rasterize_screenshots_to_png_and_photos_to_jpeg
    in_project do
      shot = CountingTools.new(photo: false)
      result = transform(block, tools: shot)

      assert_equal [:png], shot.formats
      # ラスターの参照は data-vs-raster に明示される（EpubBuilder に拡張子を推測させない）
      assert_match(%r{data-vs-raster="images/showcase/10-intro/[0-9a-f]{16}\.png"}, result)
      assert_equal 1, Dir.glob(File.join(showcase_dir, '*.png')).size
    end

    in_project do
      photo = CountingTools.new(photo: true)
      result = transform(block, tools: photo)

      assert_equal [:jpg], photo.formats
      assert_match(%r{data-vs-raster="images/showcase/10-intro/[0-9a-f]{16}\.jpg"}, result)
      assert_equal 1, Dir.glob(File.join(showcase_dir, '*.jpg')).size
      assert_empty Dir.glob(File.join(showcase_dir, '*.png'))
    end
  end

  # PDF は合成 SVG をそのまま使うため、src は形式判定に関わらず常に .svg のまま
  def test_should_always_reference_the_svg_from_src_regardless_of_raster_format
    in_project do
      result = transform(block, tools: CountingTools.new(photo: true))

      assert_match(%r{src="images/showcase/10-intro/[0-9a-f]{16}\.svg"}, result)
    end
  end

  def test_should_write_svg_and_png_as_a_pair
    in_project do
      transform(block, tools: CountingTools.new)

      svgs = Dir.glob(File.join(showcase_dir, '*.svg'))
      pngs = Dir.glob(File.join(showcase_dir, '*.png'))

      assert_equal 1, svgs.size
      assert_equal 1, pngs.size
      assert_equal File.basename(svgs.first, '.svg'), File.basename(pngs.first, '.png')
      assert_match(/\A<svg /, File.read(svgs.first, encoding: 'utf-8'))
      assert_equal 'RASTERBYTES', File.binread(pngs.first)
    end
  end

  def test_should_skip_regeneration_when_both_assets_already_exist
    in_project do
      tools = CountingTools.new
      transform(block, tools:)
      transform(block, tools:)

      assert_equal 1, tools.rasterized
    end
  end

  def test_should_regenerate_with_a_new_key_when_the_source_image_changes
    in_project do |dir|
      first = transform(block, tools: CountingTools.new)

      # 著者がスクリーンショットを撮り直した状況（画像内容をキーに含めるため別キーになる）
      File.binwrite(File.join(dir, 'images', '10-intro', 'editor.png'), "#{File.binread(FIXTURE)}\0")
      second = transform(block, tools: CountingTools.new)

      refute_equal first[/[0-9a-f]{16}/], second[/[0-9a-f]{16}/]
      assert_equal 2, Dir.glob(File.join(showcase_dir, '*.svg')).size
    end
  end

  def test_should_degrade_to_a_plain_image_when_tools_are_missing
    in_project do
      result = transform(block, tools: NoTools.new)

      # 注釈は捨て、画像行だけを通常の画像記法として残す（原稿がビルド不能にならない）
      assert_match(%r{!\[エディタ画面\]\(\.\./\.\./\.\./\.\./images/10-intro/editor\.png\)}, result)
      refute_match(/<figure/, result)
      refute_match(/rect:1/, result)
      refute_match(/:::/, result)
    end
  end

  def test_should_drop_the_block_when_it_has_no_image
    in_project do
      content = ":::{.showcase}\nrect:1 190, 30, 360, 90\n:::\n"

      assert_equal '', transform(content, tools: CountingTools.new).strip
    end
  end

  def test_should_use_only_the_first_image_when_the_block_has_several
    in_project do
      prefix = VivlioStarter::CLI::Common.asset_prefix
      content = ":::{.showcase}\n![一枚目](#{prefix}images/10-intro/editor.png)\n" \
                "![二枚目](#{prefix}images/10-intro/editor.png)\n:::\n"
      result = transform(content, tools: CountingTools.new)

      assert_equal 1, result.scan(/<img /).size
      assert_match(/alt="一枚目"/, result)
    end
  end

  # 記法そのものを解説する原稿では、フェンスの中に showcase の「書き方の例」が入る。
  # 退避しないと作例が変換に食われて消える（拡張記法リファレンスで実際に発生した）。
  def test_should_not_transform_showcase_examples_inside_code_fences
    in_project do
      example = <<~MD
        次のように書きます。

        ```markdown
        :::{.showcase}
        ![エディタ画面](editor.png)
        rect:1 190, 30, 360, 90 {pos=right} コメント
        :::
        ```

        実行結果は次のようになります。
      MD
      result = transform(example, tools: CountingTools.new)

      assert_equal example, result
      refute_match(/<figure/, result)
    end
  end

  # フェンス内の作例は素通しし、地の文の実ブロックだけを変換する（同一原稿での共存）
  def test_should_transform_the_real_block_while_keeping_the_fenced_example
    in_project do
      content = "```markdown\n:::{.showcase}\n![例](editor.png)\nrect:1 1, 2, 3, 4\n:::\n```\n\n#{block}"
      result = transform(content, tools: CountingTools.new)

      assert_includes result, "```markdown\n:::{.showcase}\n![例](editor.png)\nrect:1 1, 2, 3, 4\n:::\n```"
      assert_match(/<figure class="vs-showcase">/, result)
      assert_equal 1, result.scan(/<figure/).size
    end
  end

  def test_should_leave_content_without_showcase_blocks_untouched
    content = "# 見出し\n\n:::{.note}\nただの囲み\n:::\n"

    assert_equal content, transform(content, tools: CountingTools.new)
  end

  def test_should_compose_a_real_png_through_magick_and_rsvg
    skip '[showcase] magick / rsvg-convert が無い環境のためスキップします' unless T.default_tools.available?

    in_project do
      result = transform(block, tools: T.default_tools)

      assert_match(%r{src="images/showcase/10-intro/[0-9a-f]{16}\.svg"}, result)
      png = Dir.glob(File.join(showcase_dir, '*.png')).first

      refute_nil png
      # 実体が PNG シグネチャで始まる（rsvg-convert が実際にラスタライズしている）
      assert_equal "\x89PNG".b, File.binread(png, 4)
      # クロップ後幅 400 * (1 - 0.02 - 0.02) = 384 を 2 倍で焼く
      assert_equal '768', `magick identify -format '%w' #{png}`.strip
    end
  end

  # 実ツールでの形式自動判定。平坦な fixture（2 色）は PNG、写真相当の fixture
  # （約 9,600 色）は JPEG になる。写真を PNG で焼くと可逆ゆえに数倍太るため。
  def test_should_choose_the_raster_format_from_the_real_image_with_magick
    skip '[showcase] magick / rsvg-convert が無い環境のためスキップします' unless T.default_tools.available?

    in_project do |dir|
      FileUtils.cp(File.expand_path('../../fixtures/showcase/photo.png', __dir__),
                   File.join(dir, 'images', '10-intro', 'photo.png'))
      prefix = VivlioStarter::CLI::Common.asset_prefix
      content = ":::{.showcase}\n![写真](#{prefix}images/10-intro/photo.png)\nrect:1 100, 100, 300, 300\n:::\n"
      result = transform(content, tools: T.default_tools)

      assert_match(/data-vs-raster="[^"]+\.jpg"/, result)
      jpg = Dir.glob(File.join(showcase_dir, '*.jpg')).first

      refute_nil jpg
      assert_equal "\xFF\xD8\xFF".b, File.binread(jpg, 3), 'JPEG シグネチャで始まるべき'
      assert_empty Dir.glob(File.join(showcase_dir, '*.png')), '写真を PNG でも焼かないべき'
    end
  end

  def test_should_detect_photographic_sources_by_unique_color_count
    skip '[showcase] magick が無い環境のためスキップします' unless T.default_tools.available?

    photo = File.expand_path('../../fixtures/showcase/photo.png', __dir__)

    assert T.default_tools.photographic?(photo), '約 9,600 色の写真相当は写真と判定すべき'
    refute T.default_tools.photographic?(FIXTURE), '2 色の平坦な画像は写真と判定すべきでない'
  end
end
