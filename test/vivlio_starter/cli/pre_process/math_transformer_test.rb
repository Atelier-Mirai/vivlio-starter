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
require 'fileutils'
require 'nokogiri'
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

  # 永続キャッシュ（.cache/vs/math/）は BUILD_DIR の外にあり、ワークスペースが
  # final clean で消えても式が同じなら再描画せずに復元される。
  def test_should_reuse_the_persistent_cache_across_a_workspace_clean
    in_tmp do
      renderer = FakeRenderer.new
      MT.transform('式 $a+b$。', chapter_slug: 'ch', renderer:)
      # final clean 相当: BUILD_DIR（ワークスペース）を丸ごと削除
      FileUtils.rm_rf(VivlioStarter::CLI::Common::BUILD_DIR)

      result = MT.transform('再び $a+b$。', chapter_slug: 'ch', renderer:)

      assert_equal 1, renderer.batches.size, 'キャッシュヒット時はレンダラを呼ばない'
      assert_match(%r{src="images/math/ch/[0-9a-f]{16}\.svg"}, result)
      assert_equal 1, Dir.glob(File.join(MATH_DIR, 'ch', '*.svg')).size, 'ワークスペースへ復元される'
    end
  end

  # キャッシュキーは章に依存しないため、別章に現れる同一式は 1 回しか描かれない。
  def test_should_share_identical_formulas_across_chapters
    in_tmp do
      renderer = FakeRenderer.new
      MT.transform('式 $a+b$。', chapter_slug: 'ch1', renderer:)
      MT.transform('式 $a+b$。', chapter_slug: 'ch2', renderer:)

      assert_equal 1, renderer.batches.size, '2 章目はキャッシュヒットで描画しない'
      assert_equal 1, Dir.glob(File.join(MATH_DIR, 'ch2', '*.svg')).size, '各章のワークスペースには配られる'
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
  # 素の表記（`√n`・`x²`）は TeX へ起こしてから MathJax へ渡す
  # （plain-math-notation-spec.md §7.5）。4 デリミタすべてで効くこと。
  def test_should_transpile_plain_notation_before_rendering
    in_tmp do
      renderer = FakeRenderer.new
      MT.transform("インライン $√n$ と $$x²+y²$$ と \\(H₂O\\) と \\[Σx²\\]\n",
                   chapter_slug: 'plain', renderer:)

      assert_equal ['\\sqrt{n}', 'x^{2}+y^{2}', 'H_{2}O', '\\sum x^{2}'].sort,
                   renderer.batches.flatten.map { it[:latex] }.sort
    end
  end

  # alt は**著者の原文のまま**でなければならない（§7.6）。TeX は data-vs-tex で渡す。
  # alt を TeX にすると章扉リードの焼き込み（extract_lead_text）が `\sqrt{2}` を描いてしまう。
  def test_should_keep_the_author_source_in_alt_and_put_tex_in_a_data_attribute
    in_tmp do
      result = MT.transform("面積は $√n$ です\n", chapter_slug: 'plain', renderer: FakeRenderer.new)

      assert_includes result, 'alt="$√n$"'
      assert_includes result, 'data-vs-tex="\\sqrt{n}"'
    end
  end

  # LaTeX の構文（\command・{}）で書かれた式には data-vs-tex を付けない。
  # 属性は「素の表記で書かれた」ことの印で、Kindle が原文テキストへ落とせるかを決める（§3-2.3）。
  def test_should_not_add_the_tex_attribute_to_latex_authored_formulas
    in_tmp do
      result = MT.transform("速さは $\\frac{1}{2}gt^2$ です\n", chapter_slug: 'plain', renderer: FakeRenderer.new)

      refute_includes result, 'data-vs-tex'
    end
  end

  # 変換が要らなかった式でも、素の表記で書かれていれば印を付ける。
  # `a × b` は記号がそのまま正しく描かれるので無変換だが、原文はそのまま読める。
  def test_should_mark_plain_sources_even_when_no_conversion_was_needed
    in_tmp do
      result = MT.transform("面積は $a × b$ です\n", chapter_slug: 'plain', renderer: FakeRenderer.new)

      assert_includes result, 'data-vs-tex="a × b"'
    end
  end

  # `$x²$` と `$x^{2}$` は同じ SVG を共有する（表記のゆれでキャッシュキーが割れない）。
  def test_should_share_the_cache_key_between_plain_and_tex_spellings
    in_tmp do
      renderer = FakeRenderer.new
      MT.transform("$x²$ と $x^{2}$\n", chapter_slug: 'plain', renderer:)

      assert_equal 1, renderer.batches.flatten.size
    end
  end

  # `<text>` を含む SVG（＝日本語を含む式）には、その字だけのサブセット書体を埋め込む。
  # <img> 参照の SVG は独立文書で @font-face が届かず、PDF に Type 3 が混入するため
  # （plain-math-notation-spec.md §3.1・type3-font-embedding-notes.md §4）。
  class TextBearingRenderer
    def render_batch(items)
      items.to_h do |item|
        [item[:id],
         %(<svg data-vs-valign="0ex" data-vs-width="4ex" data-vs-height="2ex" ) +
         %(xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1 1">) +
         %(<text font-family="serif">下</text></svg>)]
      end
    end
  end

  # 書体の実体（stylesheets/fonts/）はリポジトリ root からの相対で解決されるため、
  # このテストだけ in_tmp を使わず、生成物を後始末する。
  def test_should_embed_a_subset_font_into_svgs_that_contain_text_elements
    skip '書体の実体が無い環境では埋め込みを検証できない' unless
      VivlioStarter::CLI::PreProcessCommands::SvgFontEmbedder.send(:heading_font_path)

    MT.transform("$$下限$$\n", chapter_slug: 'jp-embed', renderer: TextBearingRenderer.new)
    body = File.read(Dir.glob(File.join(MATH_DIR, 'jp-embed', '*.svg')).first, encoding: 'utf-8')

    assert_includes body, '@font-face', 'サブセット書体が抱かれている'
    assert_includes body, 'font-family="vs-math-cjk"', '汎用名 serif から専用名へ書き換わる'
    refute_includes body, 'font-family="serif"', '汎用名が残ると @font-face を当てられない'
  ensure
    FileUtils.rm_rf(File.join(MATH_DIR, 'jp-embed'))
    FileUtils.rm_rf(VivlioStarter::CLI::PreProcessCommands::GeneratedAssetCache.dir('math'))
  end

  # 書体を解決できない環境では、**名前も書き換えない**。埋め込めないのに専用名へ変えると
  # 存在しないファミリを指すだけで、従来（serif）より悪くなる。
  def test_should_leave_the_family_name_alone_when_the_font_cannot_be_resolved
    in_tmp do
      MT.transform("$$下限$$\n", chapter_slug: 'jp', renderer: TextBearingRenderer.new)
      body = File.read(Dir.glob(File.join(MATH_DIR, 'jp', '*.svg')).first, encoding: 'utf-8')

      refute_includes body, '@font-face'
      assert_includes body, 'font-family="serif"', '埋め込めないなら汎用名のまま残す'
    end
  end

  # `<text>` が無い SVG（通常の数式）は 1 バイトも変えない。
  def test_should_leave_svgs_without_text_elements_untouched
    in_tmp do
      MT.transform("$$x$$\n", chapter_slug: 'plain', renderer: FakeRenderer.new)
      body = File.read(Dir.glob(File.join(MATH_DIR, 'plain', '*.svg')).first, encoding: 'utf-8')

      refute_includes body, '@font-face'
    end
  end

  # 日本語を含む式だけ、書体をキャッシュキーへ混ぜる（著者が書体を替えたら焼き直すため）。
  # 含まない式のキーは書体に依存しない——既刊原稿のキャッシュを割らないこと。
  def test_should_mix_the_font_into_the_cache_key_only_for_formulas_with_japanese
    plain_key = MT.send(:digest, false, 'x^{2}')
    jp_key    = MT.send(:digest, false, '下限')

    assert_equal plain_key, MT.send(:digest, false, 'x^{2}'), '同じ式は同じキー'
    refute_equal jp_key, Digest::SHA256.hexdigest('I:下限')[0, 16], '日本語を含む式は書体を混ぜる'
  end

  # 角括弧は alt の中で数値文字参照へ退避する。索引マークアップ `[用語]` は前処理の
  # 最後に本文全体へ当たり、生成済みの <img alt="…"> の中まで届く。`∫[0, π/2]` のような
  # 式をそのまま置くと**タグが壊れ**、style が本文へ漏れて数式が巨大化する（実測）。
  def test_should_escape_brackets_in_alt_to_avoid_the_index_markup_collision
    in_tmp do
      result = MT.transform("$$∫[0, π/2] sin(x) dx$$\n", chapter_slug: 'br', renderer: FakeRenderer.new)

      assert_includes result, '&#91;0, π/2&#93;'
      refute_match(/alt="[^"]*\[/, result, 'alt に生の [ が残らない')
      # Nokogiri で読み出す側（Kindle テキスト化・章扉の焼き込み）は復号された [ を受け取る
      assert_equal '$$∫[0, π/2] sin(x) dx$$', Nokogiri::HTML5.fragment(result).at_css('img')['alt']
    end
  end

  # インラインの大型演算子は上下限が記号の横へ寄って潰れる（実測 2.563ex）。
  # `\limits` を挿して上下へ開く（5.449ex）——数学書と同じ組み方。
  # `\int` と `\lim` は対象外（積分は慣習、lim は開いても行内に収まる）。
  # ディスプレイ数式は元から開いているので触らない。
  def test_should_stack_operator_limits_for_inline_math_only
    stack = ->(tex) { MT.send(:stack_operator_limits, tex) }

    assert_equal '\\sum\\limits_{i=1}^{n} i', stack.call('\\sum_{i=1}^{n} i')
    assert_equal '\\lim_{n} a', stack.call('\\lim_{n} a'), 'lim は横のまま（開いても行内に収まり利点が無い）'
    assert_equal '\\int_{0}^{1} x dx', stack.call('\\int_{0}^{1} x dx'), '積分は慣習どおり横のまま'
    assert_equal '\\sum x^{2}', stack.call('\\sum x^{2}'), '上下限が無ければ挿さない（TeX エラーになる）'
    assert_equal '\\sum\\nolimits_{i}^{n} i', stack.call('\\sum\\nolimits_{i}^{n} i'), '著者の指定を尊重する'
  end

  # ディスプレイ数式には挿さない（元から上下へ開いている）。
  def test_should_not_stack_limits_for_display_math
    in_tmp do
      renderer = FakeRenderer.new
      MT.transform("$$\\sum_{i=1}^{n} i$$\n", chapter_slug: 'disp', renderer:)

      assert_equal '\\sum_{i=1}^{n} i', renderer.batches.flatten.first[:latex]
    end
  end

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
