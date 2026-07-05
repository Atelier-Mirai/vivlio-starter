# frozen_string_literal: true

# ================================================================
# Test: math_transformer_test.rb
# ================================================================
# 検証内容（math-frontispiece-svg-spec.md §A-7）:
#   - インライン $…$ / \(…\) を <img class="vs-math-inline"> 化する（④-A）
#   - ディスプレイ $$…$$ / \[…\] を <figure class="vs-math-display"> 化する（④-A）
#   - GFM 表セル内の $…$ も <img> 化する（④-B）
#   - コードスパン内の $ は変換しない（$ を含むコード例の保護）
#   - MathJax SVG の ex 値（vertical-align/width/height）を <img> へ写す
#   - 同一式はキャッシュされ、レンダラ呼び出しは未キャッシュ分のみ・1 回に束ねる
#   - renderer 不在（node/mathjax-full 未導入相当）時は本文を変えずに返す（縮退）
# ================================================================

require_relative '../../../test_helper'
require 'tmpdir'
require 'vivlio_starter/cli/pre_process/math_transformer'

class MathTransformerTest < Minitest::Test
  MT = VivlioStarter::CLI::PreProcessCommands::MathTransformer
  # SVG はワークスペースの html/images/math/ へ書き出される（P4b §2.1）
  MATH_DIR = File.join(VivlioStarter::CLI::Common::BUILD_HTML_DIR, 'images', 'math')

  # MathJax 風の SVG（ex 単位の整列情報付き）を返すフェイクのバッチレンダラ。
  # Node/mathjax-full に依存せず決定論的にテストするため。
  class FakeRenderer
    attr_reader :batches

    def initialize
      @batches = []
    end

    def render_batch(items)
      @batches << items
      # mathjax_to_svg.mjs が正規化した後の形（寸法は data-vs-* に退避・viewBox のみ）
      items.to_h do |item|
        svg = %(<svg data-vs-valign="-0.5ex" data-vs-width="3ex" data-vs-height="2ex" ) +
              %(xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1 1"><g/></svg>)
        [item[:id], svg]
      end
    end
  end

  def in_tmp
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) { yield }
    end
  end

  def test_should_convert_inline_math_to_img_with_mathjax_metrics
    in_tmp do
      result = MT.transform('式 $E=mc^2$ です。', chapter_slug: '94-sample', renderer: FakeRenderer.new)

      assert_match(/<img class="vs-math vs-math-inline"/, result)
      # 参照パスは消費者 dir 相対（asset_prefix 無し・P4b §2.1）
      assert_match(%r{src="images/math/94-sample/[0-9a-f]{16}\.svg"}, result)
      assert_match(/alt="\$E=mc\^2\$"/, result)
      # MathJax SVG の ex 値が <img> の style に写る
      assert_match(/vertical-align: -0\.5ex; width: 3ex; height: 2ex;/, result)
    end
  end

  def test_should_convert_display_math_to_figure
    in_tmp do
      md = "前段\n\n$$\n\\nu_0 = \\frac{\\phi}{h}\n$$\n\n後段"
      result = MT.transform(md, chapter_slug: '94-sample', renderer: FakeRenderer.new)

      assert_match(/<figure class="vs-math vs-math-display">/, result)
      assert_match(%r{<img src="images/math/94-sample/[0-9a-f]{16}\.svg"}, result)
      assert_match(/width: 3ex; height: 2ex;/, result)
      # alt は改行を畳んで 1 行になる
      assert_match(/alt="\$\$ \\nu_0 = \\frac\{\\phi\}\{h\} \$\$"/, result)
    end
  end

  def test_should_convert_paren_and_bracket_delimiters
    in_tmp do
      inline = MT.transform('値は \\(a+b\\) です。', chapter_slug: 'ch', renderer: FakeRenderer.new)
      display = MT.transform("\\[\nx = y\n\\]", chapter_slug: 'ch', renderer: FakeRenderer.new)

      assert_match(/vs-math-inline/, inline)
      assert_match(/alt="\\\(a\+b\\\)"/, inline)
      assert_match(/vs-math-display/, display)
    end
  end

  # ④-B: GFM 表セル内の $…$ も SVG 化される
  def test_should_convert_math_inside_table_cell
    in_tmp do
      md = "| 単位 | 記号 |\n| --- | --- |\n| 秒 | $\\text{s}$ |\n"
      result = MT.transform(md, chapter_slug: 'ch', renderer: FakeRenderer.new)

      assert_match(/\| <img class="vs-math vs-math-inline"[^>]*> \|/, result)
    end
  end

  def test_should_not_convert_math_inside_code_spans
    in_tmp do
      md = "インラインコード `$5` と `$x$` は不変。フェンス:\n\n```\n$E=mc^2$\n```\n"
      result = MT.transform(md, chapter_slug: 'ch', renderer: FakeRenderer.new)

      assert_includes result, '`$5`'
      assert_includes result, '`$x$`'
      assert_includes result, "```\n$E=mc^2$\n```"
      refute_match(/vs-math/, result)
    end
  end

  def test_should_cache_identical_formula_and_batch_render
    in_tmp do
      renderer = FakeRenderer.new
      md = '同じ式 $a+b$ が二度 $a+b$ 出る。'
      MT.transform(md, chapter_slug: 'ch', renderer:)

      assert_equal 1, Dir.glob(File.join(MATH_DIR, 'ch', '*.svg')).size, '同一式は 1 ファイルに集約される'
      assert_equal 1, renderer.batches.size, 'レンダラ呼び出しは 1 回に束ねられる'
      assert_equal 1, renderer.batches.first.size, '重複式は 1 件に集約して渡される'
    end
  end

  def test_should_not_rerender_cached_formula_on_second_run
    in_tmp do
      renderer = FakeRenderer.new
      MT.transform('式 $a+b$。', chapter_slug: 'ch', renderer:)
      MT.transform('再び $a+b$。', chapter_slug: 'ch', renderer:)

      # 2 回目はキャッシュ済みのためレンダラを呼ばない
      assert_equal 1, renderer.batches.size
    end
  end

  # node/mathjax-full 未導入相当（renderer: nil）では本文を変えずに返す（縮退）
  def test_should_return_content_unchanged_when_renderer_absent
    in_tmp do
      md = '式 $E=mc^2$ です。'
      result = MT.transform(md, chapter_slug: 'ch', renderer: nil)

      assert_equal md, result
      assert_empty Dir.glob(File.join(MATH_DIR, '**', '*.svg'))
    end
  end

  # レンダラが SVG を返さない（描画失敗）場合は元の記法を維持する
  def test_should_keep_original_when_render_returns_nil
    in_tmp do
      bad_renderer = Object.new
      def bad_renderer.render_batch(items) = items.to_h { |i| [i[:id], nil] }

      result = MT.transform('式 $E=mc^2$ です。', chapter_slug: 'ch', renderer: bad_renderer)

      assert_equal '式 $E=mc^2$ です。', result
      assert_empty Dir.glob(File.join(MATH_DIR, '**', '*.svg'))
    end
  end

  # node + mathjax-full が導入されていれば実エンジンでも正しい SVG を生成する
  def test_should_render_with_real_mathjax_when_available
    skip 'node / mathjax-full 未導入' unless MT.available?

    in_tmp do
      result = MT.transform('式 $\\langle x \\rangle$ です。', chapter_slug: 'ch')

      assert_match(/vs-math-inline/, result)
      svg = Dir.glob(File.join(MATH_DIR, 'ch', '*.svg')).first
      assert svg, 'SVG ファイルが生成される'
      assert_match(/\A<svg/, File.read(svg))
    end
  end
end
