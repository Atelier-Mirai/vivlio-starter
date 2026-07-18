# frozen_string_literal: true

# ================================================================
# Test: mermaid_transformer_test.rb
# ================================================================
# 検証内容（mermaid-diagram-spec.md §9-1）:
#   - トップレベル ```mermaid → <figure class="vs-mermaid"><img> 置換
#   - SVG（PDF 用）と PNG（EPUB/Kindle 用）が対で焼かれ、両方あれば再生成しない（キャッシュ）
#   - 図ソースが変われば別キーになる（描き直しで再生成される）
#   - キャッシュキーの決定性（同一入力 → 同一 16 桁 hex）
#   - 記法解説フェンス（````markdown の中の ```mermaid の例示）は変換しない
#   - 縮退経路: mmdc 不在 → 本文を変えず ```mermaid のまま（ビルドは止まらない）
#   - 生成失敗（render が nil）→ 当該ブロックは原文のまま残す
# mmdc 実行は重く環境依存のため、レンダラは FakeRenderer で DI 差し替えする。
# ================================================================

require_relative '../../../test_helper'
require 'fileutils'
require 'tmpdir'
require 'vivlio_starter/cli/pre_process/mermaid_transformer'

class MermaidTransformerTest < Minitest::Test
  T = VivlioStarter::CLI::PreProcessCommands::MermaidTransformer

  # 呼び出し形式を記録するフェイクレンダラ。生成有無・キャッシュ・形式を観測する。
  class FakeRenderer
    attr_reader :calls

    def initialize(available: true, svg: "<svg>ok</svg>\n", png: 'PNGBYTES', version: '11.0.0')
      @available = available
      @svg = svg
      @png = png
      @version = version
      @calls = []
    end

    def available? = @available
    def version = @version

    def render(_source, format:, font_family: nil)
      @calls << format
      @font_family = font_family
      format == :svg ? @svg : @png
    end
  end

  # 一切描画できないレンダラ（生成失敗の縮退検証用）。
  class FailingRenderer < FakeRenderer
    def render(_source, format:, font_family: nil)
      @calls << format
      nil
    end
  end

  def in_project
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) { yield dir }
    end
  end

  def mermaid_dir(chapter_slug = '10-intro')
    File.join(VivlioStarter::CLI::Common::BUILD_HTML_DIR, 'images', 'mermaid', chapter_slug)
  end

  def transform(content, renderer:, chapter_slug: '10-intro')
    T.transform(content, chapter_slug:, source_filename: '10-intro.md', renderer:)
  end

  # トップレベルの ```mermaid ブロック 1 つ。
  def diagram
    <<~MD
      本文の前。

      ```mermaid
      graph LR
        A --> B
      ```

      本文の後。
    MD
  end

  def test_should_replace_a_top_level_block_with_a_figure
    in_project do
      result = transform(diagram, renderer: FakeRenderer.new)

      assert_match(%r{<figure class="vs-mermaid">}, result)
      # 参照は消費者 dir 相対（asset_prefix 無し・ビルド生成物のため）
      assert_match(%r{<img class="vs-mermaid" src="images/mermaid/10-intro/[0-9a-f]{16}\.svg"}, result)
      assert_match(%r{data-vs-raster="images/mermaid/10-intro/[0-9a-f]{16}\.png"}, result)
      # alt は図ソース先頭の意味ある行（種別/宣言行）
      assert_match(/alt="graph LR"/, result)
      # ブロック外の本文は保たれ、フェンスは消える
      assert_match(/本文の前。/, result)
      assert_match(/本文の後。/, result)
      refute_match(/```mermaid/, result)
    end
  end

  def test_should_write_svg_and_png_as_a_pair
    in_project do
      renderer = FakeRenderer.new
      transform(diagram, renderer:)

      svgs = Dir.glob(File.join(mermaid_dir, '*.svg'))
      pngs = Dir.glob(File.join(mermaid_dir, '*.png'))

      assert_equal 1, svgs.size
      assert_equal 1, pngs.size
      assert_equal File.basename(svgs.first, '.svg'), File.basename(pngs.first, '.png')
      assert_equal %i[svg png], renderer.calls
    end
  end

  # 両方の生成物が既にあれば再生成しない（--no-clean で効く）。
  def test_should_not_regenerate_when_both_assets_exist
    in_project do
      transform(diagram, renderer: FakeRenderer.new)

      second = FakeRenderer.new
      transform(diagram, renderer: second)

      assert_empty second.calls, '既に SVG/PNG が揃っていれば mmdc を呼ばない'
    end
  end

  # 永続キャッシュ（.cache/vs/mermaid/）は BUILD_DIR の外にあり、ワークスペースが
  # final clean で消えても図ソースが同じなら mmdc を呼ばずに復元される。
  def test_should_reuse_the_persistent_cache_across_a_workspace_clean
    in_project do
      transform(diagram, renderer: FakeRenderer.new)
      # final clean 相当: BUILD_DIR（ワークスペース）を丸ごと削除
      FileUtils.rm_rf(VivlioStarter::CLI::Common::BUILD_DIR)
      refute_path_exists mermaid_dir, 'ワークスペースは消えている'
      assert Dir.exist?(File.join('.cache', 'vs', 'mermaid')), '永続キャッシュは残る'

      second = FakeRenderer.new
      result = transform(diagram, renderer: second)

      assert_empty second.calls, 'キャッシュヒット時は mmdc を呼ばない'
      assert_match(%r{<img class="vs-mermaid" src="images/mermaid/10-intro/[0-9a-f]{16}\.svg"}, result)
      assert_equal 1, Dir.glob(File.join(mermaid_dir, '*.svg')).size, 'ワークスペースへ復元される'
    end
  end

  # 図ソースが変われば別キー（別ファイル）になる。
  def test_should_use_a_different_key_when_the_source_changes
    in_project do
      transform(diagram, renderer: FakeRenderer.new)
      other = <<~MD
        ```mermaid
        graph TD
          X --> Y
        ```
      MD
      transform(other, renderer: FakeRenderer.new)

      assert_equal 2, Dir.glob(File.join(mermaid_dir, '*.svg')).size
    end
  end

  # 記法解説フェンス（外側が長いフェンス）の中の ```mermaid は変換しない。
  def test_should_not_convert_mermaid_nested_in_a_longer_fence
    in_project do
      nested = <<~MD
        記法の説明:

        ````markdown
        ```mermaid
        graph LR
          A --> B
        ```
        ````

        ここまで。
      MD
      renderer = FakeRenderer.new
      result = transform(nested, renderer:)

      assert_empty renderer.calls, '入れ子の例示は描画しない'
      assert_match(/```mermaid/, result)
      refute_match(/vs-mermaid/, result)
    end
  end

  # mmdc 不在時は本文を変えず ```mermaid のまま残す（ビルドは止めない）。
  def test_should_leave_the_block_untouched_when_the_renderer_is_unavailable
    in_project do
      result = transform(diagram, renderer: FakeRenderer.new(available: false))

      assert_equal diagram, result
      assert_match(/```mermaid/, result)
    end
  end

  # 生成失敗（render が nil）時は当該ブロックを原文のまま残す。
  def test_should_keep_the_raw_block_when_rendering_fails
    in_project do
      result = transform(diagram, renderer: FailingRenderer.new)

      assert_match(/```mermaid/, result)
      refute_match(/vs-mermaid/, result)
      assert_empty Dir.glob(File.join(mermaid_dir, '*'))
    end
  end

  # キャッシュキーは同一入力で決定的（16 桁 hex）。
  def test_cache_key_is_deterministic
    renderer = FakeRenderer.new
    key1 = T.cache_key('graph LR', nil, renderer)
    key2 = T.cache_key('graph LR', nil, renderer)

    assert_equal key1, key2
    assert_match(/\A[0-9a-f]{16}\z/, key1)
    refute_equal key1, T.cache_key('graph TD', nil, renderer)
  end

  # 他のコードフェンス（通常コード・terminal 由来の ~~~ フェンス）と共存しても、
  # mermaid だけを横取りし、他のフェンスの中身には触れない（§9-3・パイプライン順序）。
  def test_should_coexist_with_other_code_fences
    in_project do
      content = <<~MD
        ```ruby
        puts "```mermaid inside a string is safe"
        ```

        ```mermaid
        graph LR
          A --> B
        ```

        ~~~vs-terminal
        $ echo done
        ~~~
      MD
      result = transform(content, renderer: FakeRenderer.new)

      # mermaid だけが figure 化され、他のフェンスは原文のまま
      assert_equal 1, result.scan(/<figure class="vs-mermaid">/).size
      assert_match(/```ruby/, result)
      assert_match(/puts "```mermaid inside a string is safe"/, result)
      assert_match(/~~~vs-terminal/, result)
      assert_match(/\$ echo done/, result)
    end
  end

  # 複数ブロックをすべて置換する。
  def test_should_convert_multiple_blocks
    in_project do
      content = "#{diagram}\n中間。\n\n```mermaid\nsequenceDiagram\n  A->>B: hi\n```\n"
      result = transform(content, renderer: FakeRenderer.new)

      assert_equal 2, result.scan(/<figure class="vs-mermaid">/).size
      assert_equal 2, Dir.glob(File.join(mermaid_dir, '*.svg')).size
    end
  end
end
