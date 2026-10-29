# frozen_string_literal: true

# ================================================================
# Test: pre_process/glyph_coverage_check_test.rb
# ================================================================
# 本の書体に無い字を、組む前に見つける（GlyphCoverageCheck・改善案 #124 の前倒し）。
# 書体は同梱のもの（stylesheets/fonts）。字の置き場所ごとに、探す書体の並びが違う:
#   本文 = Noto Serif JP → HackGen、コード = HackGen だけ、数式の画像 = Noto Serif JP だけ
# ================================================================

require_relative '../../../test_helper'
require 'tmpdir'
require 'fileutils'
require 'vivlio_starter/cli/pre_process/glyph_coverage_check'

class GlyphCoverageCheckTest < Minitest::Test
  Check = VivlioStarter::CLI::PreProcessCommands::GlyphCoverageCheck
  FontMetrics = VivlioStarter::CLI::Build::FontMetrics
  FONTS = File.expand_path('../../../../stylesheets/fonts', __dir__)

  def chains
    serif = FontMetrics.load("#{FONTS}/Noto_Serif_JP/NotoSerifJP-Regular.ttf")
    hackgen = FontMetrics.load("#{FONTS}/hackgen35/HackGen35ConsoleNF-Regular.ttf")
    { body: [serif, hackgen], heading: [FontMetrics.load("#{FONTS}/Noto_Sans_JP/NotoSansJP-Bold.ttf"), hackgen],
      code: [hackgen], math: [serif] }
  end

  def scan(content, source: content, techbook: true)
    Check.stub(:font_chains, chains) do
      Check.stub(:techbook?, techbook) do
        Check.stub(:figure_fonts, [FontMetrics.load("#{FONTS}/Noto_Sans_JP/NotoSansJP-Regular.ttf")]) do
          Check.scan(content, source:)
        end
      end
    end
  end

  def findings_of(content, **) = scan(content, **).map { [it.line, it.chars, it.where] }

  # 本文の ≒ は、本文の書体に無くても HackGen で組める。ₙ はどちらにも無い
  def test_should_follow_body_font_stack
    assert_equal [[3, ['ₙ'], nil]], findings_of("φ≒1.618 です。\n\nHₙ の和。\n")
  end

  # コードはコードの書体だけで探す（--font-code の次は OS の書体）。インラインもフェンスも
  def test_should_check_code_with_code_font_only
    content = "キーは `⌃+G` です。\n\n```\nγ = lim (Hₙ − ln n)\n```\n"

    assert_equal [[1, ['⌃'], 'コード'], [4, ['ₙ'], 'コード']], findings_of(content)
  end

  # 絵文字は techbook なら PDF を組む前に画像へ置き換えるので数えない
  def test_should_skip_emoji_replaced_by_techbook
    assert_empty findings_of("じゃんけん ✊ です。\n")
    assert_equal [[1, ['✊'], nil]], findings_of("じゃんけん ✊ です。\n", techbook: false)
  end

  # タグの中（画像の説明など）は組まれないので数えない
  def test_should_ignore_text_inside_tags
    assert_empty findings_of(%(<img src="a.png" alt="Hₙ の図">\n))
  end

  # 図の SVG の字は、図に埋める書体だけで描かれる。絵文字も置き換えないので数える。
  # 行番号は、原稿の図の参照の行
  def test_should_check_text_in_figure_svg
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir_p('images/11-a')
        File.write('images/11-a/curve.svg', '<svg><text x="1">面積 ≒ 2.5</text><text>✌️</text></svg>')
        content = %(<figure><img src="../../images/11-a/curve.svg" alt="曲線"></figure>\n)
        source = "前の段落。\n\n![曲線](curve.svg)\n"

        assert_equal [[3, %w[≒ ✌], '図 curve.svg']], findings_of(content, source:)
      end
    end
  end

  # 図の書体に無い字は、DerivedSvg が予備の書体（HackGen → DejaVu Sans Mono → DejaVu Sans）で補う
  # （改善案 #127）。補える字（≒・ⁿ・ₙ・⟹）は数えない。絵文字は予備の書体にあっても補わないので数える
  def test_should_count_fallback_font_in_figure_fonts
    original = VivlioStarter::CLI::Common::CONFIG
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir_p('stylesheets')
        FileUtils.cp_r(FONTS, 'stylesheets/fonts')
        VivlioStarter::CLI::Common.install_configuration!(
          VivlioStarter::CLI::Common.build_direct_configuration(typography: { heading: { font: 'Noto Sans JP' } })
        )
        svg = '<svg><text font-family="sans-serif">面積 ≒ xⁿ Hₙ ⟹ ✌</text></svg>'

        assert_equal ['✌'], Check.missing_chars(Check.svg_text(svg), Check.figure_fonts(svg))
      end
    end
  ensure
    VivlioStarter::CLI::Common.install_configuration!(original)
  end

  # 数式の画像の中の字（MathJax が字のまま描いたもの）は、埋めた本文の書体だけで描かれる
  def test_should_check_text_in_math_svg
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        math = File.join(VivlioStarter::CLI::Common::BUILD_HTML_DIR, 'images/math/11-a')
        FileUtils.mkdir_p(math)
        File.write(File.join(math, 'k.svg'), '<svg><text>2⁸</text></svg>')
        content = %(値は <img class="vs-math" src="images/math/11-a/k.svg" alt="$2⁸$"> です。\n)

        assert_equal [[1, ['⁸'], '数式']], findings_of(content, source: "値は $2⁸$ です。\n")
      end
    end
  end

  # 前処理で行がずれても、字の前後の字で元の原稿の行を引く
  def test_should_find_source_line_by_surrounding_text
    assert_equal 3, Check.source_line("# 題\n\n和は Hₙ です。\n", '和は Hₙ です。', 'ₙ')
  end

  def test_should_remember_reported_chars_for_type3_check
    Check.remember(%w[≒ ⁿ])

    assert_equal Set['≒', 'ⁿ'], Check.reported
  ensure
    Check.reset!
  end

  def test_should_give_advice_per_char
    assert_equal '≈ に置き換える', Check.advice_for('≒')
    assert_equal '本の書体にある字に置き換える', Check.advice_for('⟹')
  end
end
